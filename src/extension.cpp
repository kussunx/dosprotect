/*
 * DoS Protect for Left 4 Dead and Left 4 Dead 2
 * Current maintenance: Kussun
 * Based on the original DoS Protect by ZombieX2.net
 */

#include "extension.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <unordered_map>
#include <vector>

#if !defined(_WIN32)
#error DoS Protect currently targets Windows only.
#endif

#if SOURCE_ENGINE != SE_LEFT4DEAD && SOURCE_ENGINE != SE_LEFT4DEAD2
#error DoS Protect supports only Left 4 Dead and Left 4 Dead 2.
#endif

static_assert(sizeof(SOCKET) == sizeof(int), "DoS Protect requires the Win32/x86 socket ABI.");

#define CallGlobalChangeCallback CallGlobalChangeCallbacks
SH_DECL_HOOK3_void(ICvar, CallGlobalChangeCallback, SH_NOATTRIB, false, ConVar *, const char *, float);

namespace
{
using Clock = std::chrono::steady_clock;
using TimePoint = Clock::time_point;
using RecvFromFn = int (*)(int, char *, int, int, struct sockaddr *, int *);

#if SOURCE_ENGINE == SE_LEFT4DEAD
constexpr const char *kGameName = "Left 4 Dead";
constexpr const char *kBinaryName = "dosprotect_l4d1_mm";
#else
constexpr const char *kGameName = "Left 4 Dead 2";
constexpr const char *kBinaryName = "dosprotect_l4d2_mm";
#endif

constexpr const char *kMitigationName = "DROP-WOULDBLOCK";
constexpr int kDefaultDrainBudget = 256;
constexpr int kMinDrainBudget = 1;
constexpr int kMaxDrainBudget = 4096;
constexpr int kDefaultMaxSources = 4096;
constexpr int kMinMaxSources = 128;
constexpr int kMaxMaxSources = 65536;
constexpr int kDefaultExpireSeconds = 900;
constexpr int kMaxExpireSeconds = 86400;
constexpr int kMaintenanceIntervalSeconds = 30;
constexpr size_t kStatusTopLimit = 10;
constexpr size_t kTopCommandLimit = 20;

struct SourceRecord
{
    uint64_t count;
    TimePoint lastSeen;
};

struct DoSStats
{
    uint64_t zeroDatagramsDropped = 0;
    uint64_t drainBudgetHits = 0;
    uint64_t invalidSourcePackets = 0;
    uint64_t untrackedSourcePackets = 0;
    uint64_t expiredRecords = 0;
    uint64_t currentWindowPackets = 0;
    uint64_t lastPps = 0;
    uint64_t peakPps = 0;
    TimePoint ppsWindowStart = Clock::now();
};

struct IPv4Hash
{
    size_t operator()(uint32_t value) const noexcept
    {
        static const uint64_t seed =
            static_cast<uint64_t>(Clock::now().time_since_epoch().count()) ^ 0x9E3779B97F4A7C15ULL;

        uint64_t z = static_cast<uint64_t>(value) + seed + 0x9E3779B97F4A7C15ULL;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        z ^= (z >> 31);
        return static_cast<size_t>(z);
    }
};

struct RankedRecord
{
    uint32_t ip;
    uint64_t count;
    uint64_t ageSeconds;
};

ICvar *g_icvar = nullptr;
ConVar *g_dospEnable = nullptr;
ConVar *g_dospDrainBudget = nullptr;
ConVar *g_dospMaxSources = nullptr;
ConVar *g_dospExpireSeconds = nullptr;

std::unordered_map<uint32_t, SourceRecord, IPv4Hash> g_sources;
DoSStats g_stats;
TimePoint g_nextMaintenance = Clock::now();
size_t g_reservedSourceLimit = 0;

bool g_recvfromHooked = false;
bool g_ignoreEnableCallback = false;
RecvFromFn g_realRecvFrom = nullptr;
int g_effectiveDrainBudget = kDefaultDrainBudget;
int g_effectiveMaxSources = kDefaultMaxSources;
int g_effectiveExpireSeconds = kDefaultExpireSeconds;

int ClampInt(int value, int minimum, int maximum)
{
    if (value < minimum)
        return minimum;
    if (value > maximum)
        return maximum;
    return value;
}

void RefreshRuntimeConfig()
{
    g_effectiveDrainBudget = g_dospDrainBudget
        ? ClampInt(g_dospDrainBudget->GetInt(), kMinDrainBudget, kMaxDrainBudget)
        : kDefaultDrainBudget;

    g_effectiveMaxSources = g_dospMaxSources
        ? ClampInt(g_dospMaxSources->GetInt(), kMinMaxSources, kMaxMaxSources)
        : kDefaultMaxSources;

    g_effectiveExpireSeconds = g_dospExpireSeconds
        ? ClampInt(g_dospExpireSeconds->GetInt(), 0, kMaxExpireSeconds)
        : kDefaultExpireSeconds;

    const size_t requested = static_cast<size_t>(g_effectiveMaxSources);
    if (requested > g_reservedSourceLimit)
    {
        g_sources.reserve(requested);
        g_reservedSourceLimit = requested;
    }
}

void RollPpsWindow(const TimePoint now)
{
    const auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - g_stats.ppsWindowStart).count();
    if (elapsedMs < 1000)
        return;

    g_stats.lastPps = (g_stats.currentWindowPackets * 1000ULL) / static_cast<uint64_t>(elapsedMs);
    g_stats.peakPps = std::max(g_stats.peakPps, g_stats.lastPps);
    g_stats.currentWindowPackets = 0;
    g_stats.ppsWindowStart = now;
}

void ResetTelemetry()
{
    g_sources.clear();
    g_stats = DoSStats{};

    const TimePoint now = Clock::now();
    g_stats.ppsWindowStart = now;
    g_nextMaintenance = now + std::chrono::seconds(kMaintenanceIntervalSeconds);
}

void MaybeExpireRecords(const TimePoint now)
{
    if (now < g_nextMaintenance)
        return;

    g_nextMaintenance = now + std::chrono::seconds(kMaintenanceIntervalSeconds);

    if (g_effectiveExpireSeconds <= 0 || g_sources.empty())
        return;

    const auto expiry = std::chrono::seconds(g_effectiveExpireSeconds);
    uint64_t removed = 0;

    for (auto iter = g_sources.begin(); iter != g_sources.end();)
    {
        if ((now - iter->second.lastSeen) >= expiry)
        {
            iter = g_sources.erase(iter);
            ++removed;
        }
        else
        {
            ++iter;
        }
    }

    g_stats.expiredRecords += removed;
}

bool TryExtractIPv4(const struct sockaddr *from, const int *fromlen, uint32_t *ip)
{
    if (!from || !fromlen || !ip)
        return false;

    if (*fromlen < static_cast<int>(sizeof(sockaddr_in)) || from->sa_family != AF_INET)
        return false;

    const auto *address = reinterpret_cast<const sockaddr_in *>(from);
    *ip = static_cast<uint32_t>(address->sin_addr.s_addr);
    return true;
}

void RecordZeroDatagram(const struct sockaddr *from, const int *fromlen, const TimePoint now)
{
    ++g_stats.zeroDatagramsDropped;
    ++g_stats.currentWindowPackets;

    uint32_t ip = 0;
    if (!TryExtractIPv4(from, fromlen, &ip))
    {
        ++g_stats.invalidSourcePackets;
        return;
    }

    auto found = g_sources.find(ip);
    if (found != g_sources.end())
    {
        ++found->second.count;
        found->second.lastSeen = now;
        return;
    }

    if (g_sources.size() >= static_cast<size_t>(g_effectiveMaxSources))
    {
        ++g_stats.untrackedSourcePackets;
        return;
    }

    g_sources.emplace(ip, SourceRecord{1, now});
}

void SetWouldBlockError()
{
    WSASetLastError(WSAEWOULDBLOCK);
}

int SocketReadableNow(int socketHandle)
{
    fd_set readSet;
    FD_ZERO(&readSet);
    FD_SET(static_cast<SOCKET>(socketHandle), &readSet);

    timeval timeout{};
    return select(0, &readSet, nullptr, nullptr, &timeout);
}

int HandleZeroDatagramBurst(
    int s,
    char *buf,
    int len,
    int flags,
    struct sockaddr *from,
    int *fromlen,
    int addressCapacity,
    const TimePoint now)
{
    int droppedThisCall = 0;

    while (true)
    {
        RecordZeroDatagram(from, fromlen, now);
        ++droppedThisCall;

        if (droppedThisCall >= g_effectiveDrainBudget)
        {
            ++g_stats.drainBudgetHits;
            SetWouldBlockError();
            return SOCKET_ERROR;
        }

        const int readable = SocketReadableNow(s);
        if (readable == SOCKET_ERROR)
            return SOCKET_ERROR;

        if (readable == 0)
        {
            SetWouldBlockError();
            return SOCKET_ERROR;
        }

        if (fromlen)
            *fromlen = addressCapacity;

        const int ret = g_realRecvFrom(s, buf, len, flags, from, fromlen);
        if (ret == 0)
            continue;

        return ret;
    }
}

uint64_t SecondsSince(const TimePoint now, const TimePoint then)
{
    const auto seconds = std::chrono::duration_cast<std::chrono::seconds>(now - then).count();
    return seconds > 0 ? static_cast<uint64_t>(seconds) : 0;
}

void PrintIp(uint32_t ip)
{
    const uint32_t host = ntohl(ip);
    META_CONPRINTF(
        "%u.%u.%u.%u",
        static_cast<unsigned int>((host >> 24) & 0xFF),
        static_cast<unsigned int>((host >> 16) & 0xFF),
        static_cast<unsigned int>((host >> 8) & 0xFF),
        static_cast<unsigned int>(host & 0xFF));
}

void PrintTopSources(size_t limit, const TimePoint now)
{
    std::vector<RankedRecord> ranked;
    ranked.reserve(g_sources.size());

    for (const auto &entry : g_sources)
    {
        ranked.push_back(RankedRecord{
            entry.first,
            entry.second.count,
            SecondsSince(now, entry.second.lastSeen)});
    }

    std::sort(ranked.begin(), ranked.end(), [](const RankedRecord &left, const RankedRecord &right) {
        if (left.count != right.count)
            return left.count > right.count;
        return left.ageSeconds < right.ageSeconds;
    });

    const size_t count = std::min(limit, ranked.size());
    if (count == 0)
    {
        META_CONPRINT(" No tracked sources.\n");
        return;
    }

    META_CONPRINT(" Source IP       | Packets      | Last seen\n");
    META_CONPRINT("------------------------------------------------\n");

    for (size_t index = 0; index < count; ++index)
    {
        META_CONPRINT(" ");
        PrintIp(ranked[index].ip);
        META_CONPRINTF(
            " | %-12llu | %llu sec ago\n",
            static_cast<unsigned long long>(ranked[index].count),
            static_cast<unsigned long long>(ranked[index].ageSeconds));
    }
}

int MyRecvFromHook(int s, char *buf, int len, int flags, struct sockaddr *from, int *fromlen)
{
    if (!g_realRecvFrom)
    {
        WSASetLastError(WSAENOTSOCK);
        return SOCKET_ERROR;
    }

    const int addressCapacity = fromlen ? *fromlen : 0;
    const int ret = g_realRecvFrom(s, buf, len, flags, from, fromlen);
    if (ret != 0)
        return ret;

    const TimePoint now = Clock::now();
    RollPpsWindow(now);
    MaybeExpireRecords(now);

    return HandleZeroDatagramBurst(s, buf, len, flags, from, fromlen, addressCapacity, now);
}

bool ReHookRecvFrom()
{
    if (g_recvfromHooked)
        return true;

    if (!g_pVCR || !g_pVCR->Hook_recvfrom)
    {
        META_CONPRINT("[DoS Protect] ERROR: VCR recvfrom hook target is unavailable.\n");
        return false;
    }

    if (g_pVCR->Hook_recvfrom == &MyRecvFromHook)
    {
        META_CONPRINT("[DoS Protect] ERROR: recvfrom already points to DoS Protect while internal state is unhooked.\n");
        return false;
    }

    g_realRecvFrom = g_pVCR->Hook_recvfrom;
    g_pVCR->Hook_recvfrom = &MyRecvFromHook;
    g_recvfromHooked = true;

    META_CONPRINTF("[DoS Protect] Protection enabled for %s (%s).\n", kGameName, kMitigationName);
    return true;
}

bool TryUnHookRecvFrom()
{
    if (!g_recvfromHooked)
        return true;

    if (!g_pVCR || g_pVCR->Hook_recvfrom != &MyRecvFromHook)
    {
        META_CONPRINT("[DoS Protect] WARNING: another recvfrom hook is installed after DoS Protect; refusing to break the hook chain.\n");
        return false;
    }

    if (!g_realRecvFrom)
    {
        META_CONPRINT("[DoS Protect] ERROR: original recvfrom pointer is unavailable; refusing to unhook.\n");
        return false;
    }

    g_pVCR->Hook_recvfrom = g_realRecvFrom;
    g_realRecvFrom = nullptr;
    g_recvfromHooked = false;

    META_CONPRINT("[DoS Protect] Protection disabled.\n");
    return true;
}

void RestoreEnableConVar(int value)
{
    if (!g_dospEnable)
        return;

    g_ignoreEnableCallback = true;
    g_dospEnable->SetValue(value);
    g_ignoreEnableCallback = false;
}

void dosp_status_CommandCallback()
{
    const TimePoint now = Clock::now();
    RollPpsWindow(now);
    MaybeExpireRecords(now);

    META_CONPRINT("\n========== DoS Protect ==========\n");
    META_CONPRINTF(" Version: %s\n", DOSP_VERSION);
    META_CONPRINTF(" Game: %s\n", kGameName);
    META_CONPRINTF(" Binary: %s\n", kBinaryName);
    META_CONPRINTF(" Status: %s\n", g_recvfromHooked ? "ENABLED" : "DISABLED");
    META_CONPRINTF(" Mitigation: %s\n", kMitigationName);
    META_CONPRINTF(" Drain budget: %d zero datagrams/call\n", g_effectiveDrainBudget);
    META_CONPRINTF(" Zero datagrams dropped: %llu\n", static_cast<unsigned long long>(g_stats.zeroDatagramsDropped));
    META_CONPRINTF(" Drain budget hits: %llu\n", static_cast<unsigned long long>(g_stats.drainBudgetHits));
    META_CONPRINTF(" Tracked sources: %llu / %d\n", static_cast<unsigned long long>(g_sources.size()), g_effectiveMaxSources);
    META_CONPRINTF(" Invalid/unavailable source packets: %llu\n", static_cast<unsigned long long>(g_stats.invalidSourcePackets));
    META_CONPRINTF(" Untracked packets (source table full): %llu\n", static_cast<unsigned long long>(g_stats.untrackedSourcePackets));
    META_CONPRINTF(" Expired source records: %llu\n", static_cast<unsigned long long>(g_stats.expiredRecords));
    META_CONPRINTF(" Last PPS: %llu\n", static_cast<unsigned long long>(g_stats.lastPps));
    META_CONPRINTF(" Peak PPS: %llu\n", static_cast<unsigned long long>(g_stats.peakPps));
    META_CONPRINTF(" Source expiry: %d sec%s\n", g_effectiveExpireSeconds, g_effectiveExpireSeconds == 0 ? " (disabled)" : "");
    META_CONPRINT("---------------------------------\n");
    PrintTopSources(kStatusTopLimit, now);
    META_CONPRINT("=================================\n\n");
}

void dosp_top_CommandCallback()
{
    const TimePoint now = Clock::now();
    RollPpsWindow(now);
    MaybeExpireRecords(now);

    META_CONPRINTF("\n[DoS Protect] Top %llu sources:\n", static_cast<unsigned long long>(kTopCommandLimit));
    PrintTopSources(kTopCommandLimit, now);
    META_CONPRINT("\n");
}

void dosp_reset_CommandCallback()
{
    ResetTelemetry();
    META_CONPRINT("[DoS Protect] Telemetry and tracked sources reset. Protection state unchanged.\n");
}

void OnDoSPConVarChange(ConVar *var, const char *pOldValue, float flOldValue)
{
    (void)pOldValue;
    (void)flOldValue;

    if (!var)
        return;

    if (var == g_dospEnable)
    {
        if (g_ignoreEnableCallback)
            return;

        if (var->GetInt() != 0)
        {
            if (!ReHookRecvFrom())
                RestoreEnableConVar(0);
        }
        else if (!TryUnHookRecvFrom())
        {
            RestoreEnableConVar(1);
        }
        return;
    }

    if (var == g_dospDrainBudget || var == g_dospMaxSources || var == g_dospExpireSeconds)
        RefreshRuntimeConfig();
}
} // namespace

DoSProtect g_DoSProtect;
PLUGIN_EXPOSE(DoSProtect, g_DoSProtect);

bool DoSProtect::Load(PluginId id, ISmmAPI *ismm, char *error, size_t maxlen, bool late)
{
    (void)id;
    (void)late;

    PLUGIN_SAVEVARS();

    GET_V_IFACE_CURRENT(GetEngineFactory, g_icvar, ICvar, CVAR_INTERFACE_VERSION);
    g_pCVar = g_icvar;

    new ConVar("dosp_version", DOSP_VERSION, FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY, "DoS Protect version");
    g_dospEnable = new ConVar("dosp_enable", "1", 0, "Enable or disable DoS Protect");
    g_dospDrainBudget = new ConVar("dosp_drain_budget", "256", 0, "Maximum zero-length UDP datagrams drained in one recvfrom hook call (1-4096)");
    g_dospMaxSources = new ConVar("dosp_max_sources", "4096", 0, "Maximum IPv4 source records retained in memory (128-65536)");
    g_dospExpireSeconds = new ConVar("dosp_expire_seconds", "900", 0, "Expire inactive source records after N seconds; 0 disables expiry");

    new ConCommand("dosp_status", dosp_status_CommandCallback, "Show DoS Protect status and telemetry", 0);
    new ConCommand("dosp_top", dosp_top_CommandCallback, "Show the top tracked UDP sources", 0);
    new ConCommand("dosp_reset", dosp_reset_CommandCallback, "Reset telemetry without changing protection state", 0);

    SH_ADD_HOOK_STATICFUNC(ICvar, CallGlobalChangeCallback, g_icvar, OnDoSPConVarChange, false);
    ConVar_Register(0, this);

    g_sources.max_load_factor(0.75f);
    RefreshRuntimeConfig();
    ResetTelemetry();

    if (g_dospEnable->GetInt() != 0 && !ReHookRecvFrom())
    {
        RestoreEnableConVar(0);
        SH_REMOVE_HOOK_STATICFUNC(ICvar, CallGlobalChangeCallback, g_icvar, OnDoSPConVarChange, false);

        if (error && maxlen > 0)
            std::snprintf(error, maxlen, "DoS Protect could not hook g_pVCR->Hook_recvfrom for %s", kGameName);

        return false;
    }

    META_CONPRINTF("[DoS Protect] %s loaded for %s. Mitigation: %s.\n", DOSP_VERSION, kGameName, kMitigationName);
    return true;
}

bool DoSProtect::Unload(char *error, size_t maxlen)
{
    if (!TryUnHookRecvFrom())
    {
        if (error && maxlen > 0)
            std::snprintf(error, maxlen, "DoS Protect cannot unload safely because the recvfrom hook chain changed");
        return false;
    }

    if (g_icvar)
        SH_REMOVE_HOOK_STATICFUNC(ICvar, CallGlobalChangeCallback, g_icvar, OnDoSPConVarChange, false);

    g_sources.clear();
    g_sources.rehash(0);
    g_reservedSourceLimit = 0;

    g_icvar = nullptr;
    g_pCVar = nullptr;
    g_dospEnable = nullptr;
    g_dospDrainBudget = nullptr;
    g_dospMaxSources = nullptr;
    g_dospExpireSeconds = nullptr;

    META_CONPRINT("[DoS Protect] Unloaded.\n");
    return true;
}

bool DoSProtect::RegisterConCommandBase(ConCommandBase *pCommandBase)
{
    META_REGCVAR(pCommandBase);
    return true;
}

const char *DoSProtect::GetLicense()
{
    return "Unspecified";
}

const char *DoSProtect::GetVersion()
{
    return DOSP_VERSION;
}

const char *DoSProtect::GetDate()
{
    return __DATE__;
}

const char *DoSProtect::GetLogTag()
{
    return "DOSP";
}

const char *DoSProtect::GetAuthor()
{
    return "Kussun";
}

const char *DoSProtect::GetDescription()
{
    return "Zero-length UDP datagram protection for Left 4 Dead and Left 4 Dead 2";
}

const char *DoSProtect::GetName()
{
    return "DoS Protect";
}

const char *DoSProtect::GetURL()
{
    return "https://github.com/kussunx/dosprotect";
}
