# DoS Protect

Modern revamp of the original **DoS Protect** Metamod:Source plugin for **Left 4 Dead** and **Left 4 Dead 2**.

The project now uses a standards-oriented zero-length UDP filtering strategy by default. The real `recvfrom()` consumes zero-length datagrams, DoS Protect drains them in a bounded loop, forwards the first real packet unchanged if one is already queued, and otherwise reports the normal non-blocking "no deliverable packet" result (`SOCKET_ERROR` with `WSAEWOULDBLOCK` on Windows). No positive byte count is fabricated by the modern path.

The known-working `LEGACY-25` behavior remains available as a runtime fallback while the modern path is validated against the same real attack case on both games.

## Authorship

- **Revamp / current maintainer:** Kussun
- **Original project / original author:** ZombieX2.net

This repository is a substantial modernization based on the original DoS Protect source. Credit for the original implementation and concept remains with ZombieX2.net.

## Current version

`2.0.0-dev.3`

This revision introduces the bounded `DROP-WOULDBLOCK` mitigation as the default while retaining `LEGACY-25` as an immediate A/B fallback.

## Supported targets

| Game | HL2SDK | `SOURCE_ENGINE` | Platform | Plugin binary | Package |
| --- | --- | ---: | --- | --- | --- |
| Left 4 Dead | `l4d` | `8` | Windows x86 / Win32 | `dosprotect_l4d1_mm.dll` | `dosprotect-l4d-win32` |
| Left 4 Dead 2 | `l4d2` | `9` | Windows x86 / Win32 | `dosprotect_l4d2_mm.dll` | `dosprotect-l4d2-win32` |

Both binaries are produced from the same source tree. Packet-handling logic is shared between L4D1 and L4D2 and the compiler rejects unsupported Source engine targets.

## Mitigation modes

### Modern mode — default

```text
dosp_mitigation_mode 1
```

Reported as:

```text
Mitigation: DROP-WOULDBLOCK
```

Modern handling works as follows:

1. Call the real `recvfrom()`.
2. If it returns a normal packet or a socket error, return that result unchanged.
3. If it returns a zero-length UDP datagram, record and discard it.
4. Check whether the socket is immediately readable using a zero-timeout `select()`.
5. If more traffic is queued, continue receiving and discard additional zero-length datagrams up to the configured drain budget.
6. If a real packet is encountered, return its real length and buffer/address data unchanged to the engine.
7. If no deliverable packet remains, or the drain budget is reached, return `SOCKET_ERROR` and set `WSAEWOULDBLOCK`.

This avoids both problems with the original workaround: it does not claim that nonexistent payload bytes were received, and it does not stop after consuming only one attack datagram when a burst of zero-length packets is already queued.

### Legacy fallback

```text
dosp_mitigation_mode 0
```

Reported as:

```text
Mitigation: LEGACY-25
```

This retains the previously validated behavior:

```cpp
if (ret == 0)
{
    RecordZeroDatagram(...);
    return 25;
}
```

The fallback can be selected at runtime without recompiling or restarting the server. It remains intentionally available until the modern method passes the full regression procedure on both L4D1 and L4D2.

## Runtime modernization

The original plugin kept a linear linked list of heap-allocated IP records for the entire server lifetime. The current implementation includes:

- bounded IPv4 source table using `std::unordered_map` instead of a linear `SourceHook::List` scan;
- 64-bit packet counters;
- randomized mixed IPv4 hashing;
- first/last-seen tracking using a monotonic clock;
- configurable expiration of inactive source records;
- configurable hard limit on retained source records;
- validated `sockaddr`/`fromlen` handling before reading IPv4 data;
- total, current, last and peak PPS telemetry;
- separate counters for modern drops and legacy fallback responses;
- bounded modern receive draining with drain-budget hit telemetry;
- `dosp_top` ranked-source diagnostics;
- `dosp_reset` telemetry reset without disabling protection;
- safer/idempotent hook installation and removal;
- protection against overwriting another plugin's later recvfrom hook during disable/unload;
- no per-packet console or disk logging in the hot path;
- target-specific L4D1/L4D2 DLL and VDF packaging;
- build validation for x86 PE format, `CreateInterface` export and VDF/binary consistency.

## Runtime commands and ConVars

### Commands

```text
dosp_status
```

Shows version, game, binary, hook state, active mitigation, drain budget, total zero-length UDP interceptions, modern/legacy response counts, drain-budget hits, tracked source count, invalid-source count, table-full count, expired records, PPS telemetry and the top tracked sources.

```text
dosp_top
```

Shows the top 20 retained IPv4 sources ranked by intercepted packet count.

```text
dosp_reset
```

Clears telemetry and the retained source table. It does **not** change whether protection is enabled or which mitigation mode is selected.

### ConVars

```text
dosp_version
```

Current plugin version.

```text
dosp_enable 1
```

`1` enables the recvfrom protection hook. `0` disables it.

```text
dosp_mitigation_mode 1
```

- `1`: `DROP-WOULDBLOCK` modern mode, default.
- `0`: `LEGACY-25` fallback.

The mode changes immediately at runtime.

```text
dosp_drain_budget 256
```

Maximum number of zero-length UDP datagrams the modern path will consume in one engine `recvfrom` hook call before yielding with `WSAEWOULDBLOCK`. Effective range: `1..4096`.

The default is intentionally bounded so the plugin can drain bursts without allowing one network callback to monopolize the server thread. `dosp_status` reports `Drain budget hits`; repeated hits during a known test indicate that the budget is being saturated.

```text
dosp_max_sources 4096
```

Maximum number of IPv4 source records retained in memory. The runtime clamps the effective value to `128..65536`.

```text
dosp_expire_seconds 900
```

Inactive records are removed after this many seconds. `0` disables expiration. Maintenance is amortized and does not scan the source table on every packet.

## Repository layout

```text
build/
  dependencies.psd1
config/
  dosprotect_l4d1.vdf
  dosprotect_l4d2.vdf
docs/
  REGRESSION_TEST.md
src/
  extension.cpp
  extension.h
  platform_wrappers.h
scripts/
  build.ps1
  verify-legacy-mitigation.ps1
.github/workflows/
  build.yml
CHANGELOG.md
README.md
```

## Pinned upstream dependencies

Exact upstream revisions are stored in `build/dependencies.psd1`:

- Metamod:Source `1.12-dev`: `afc8233eedcd0c832b411c1da852328328db5c50`
- HL2SDK `l4d`: `0a8e862697335b12976a124daf728c38e975e381`
- HL2SDK `l4d2`: `2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6`

## Local build

Requirements:

- Windows;
- Visual Studio with **Desktop development with C++** and x86 build tools;
- Git;
- PowerShell.

Build both games:

```powershell
.\scripts\build.ps1 -Target all
```

Build only Left 4 Dead:

```powershell
.\scripts\build.ps1 -Target l4d
```

Build only Left 4 Dead 2:

```powershell
.\scripts\build.ps1 -Target l4d2
```

Discard cached dependencies and fetch pinned revisions again:

```powershell
.\scripts\build.ps1 -Target all -CleanDeps
```

## Build output

### Left 4 Dead

```text
artifacts/dosprotect-l4d-win32/
  addons/
    dosprotect/
      bin/
        dosprotect_l4d1_mm.dll
        dosprotect_l4d1_mm.pdb
    metamod/
      dosprotect.vdf
  README.md
  build-info.txt
```

### Left 4 Dead 2

```text
artifacts/dosprotect-l4d2-win32/
  addons/
    dosprotect/
      bin/
        dosprotect_l4d2_mm.dll
        dosprotect_l4d2_mm.pdb
    metamod/
      dosprotect.vdf
  README.md
  build-info.txt
```

Each target-specific VDF points to the matching binary. The build fails if the VDF and DLL name disagree, if the result is not x86, or if the Metamod `CreateInterface` export is missing.

## GitHub Actions / self-hosted runner

`.github/workflows/build.yml` runs a two-target matrix on the self-hosted Windows runner. Every push to `main`, pull request targeting `main`, or manual workflow run builds both packages.

The upload to GitHub Actions artifact storage is **best effort**. Artifact-storage quota exhaustion does not invalidate a successful compile/link/package validation.

## Installation — Left 4 Dead

```text
left4dead/addons/dosprotect/bin/dosprotect_l4d1_mm.dll
left4dead/addons/metamod/dosprotect.vdf
```

## Installation — Left 4 Dead 2

```text
left4dead2/addons/dosprotect/bin/dosprotect_l4d2_mm.dll
left4dead2/addons/metamod/dosprotect.vdf
```

Restart the server and verify:

```text
meta list
dosp_status
```

For `dev.3`, the expected default status is:

```text
Status: ENABLED
Mitigation: DROP-WOULDBLOCK
Legacy fallback: available (dosp_mitigation_mode 0)
Drain budget: 256 zero datagrams/call
```

## Runtime regression policy

Source/build CI is not a replacement for the real server regression. The modern mode is accepted only after the same controlled test case that previously validated `LEGACY-25` is blocked on both games while normal connections, queries and gameplay remain functional.

If the new path does not behave correctly during testing, switch immediately to:

```text
dosp_mitigation_mode 0
```

See [`docs/REGRESSION_TEST.md`](docs/REGRESSION_TEST.md) for the acceptance procedure.

## License

The original source snapshot does not include a clear standalone license file. No new license is asserted for the inherited source until the original licensing status is established. Metamod:Source and HL2SDK retain their respective upstream licenses and are fetched as external build dependencies.
