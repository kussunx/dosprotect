# DoS Protect

Modern revamp of the original **DoS Protect** Metamod:Source plugin for **Left 4 Dead** and **Left 4 Dead 2**.

The project intentionally preserves the legacy UDP mitigation that has proven effective in production: when the hooked `recvfrom()` path returns a zero-length datagram, the compatibility path records the event and returns `25` to the engine. This behavior is regression-guarded and must not be removed or altered without a verified replacement that blocks the same real attack case on both games.

## Authorship

- **Revamp / current maintainer:** Kussun
- **Original project / original author:** ZombieX2.net

This repository is a substantial modernization based on the original DoS Protect source. Credit for the original implementation and concept remains with ZombieX2.net.

## Current version

`2.0.0-dev.2`

This revision begins the full runtime revamp while retaining the known-working `ret == 0 -> return 25` compatibility contract.

## Supported targets

| Game | HL2SDK | `SOURCE_ENGINE` | Platform | Plugin binary | Package |
| --- | --- | ---: | --- | --- | --- |
| Left 4 Dead | `l4d` | `8` | Windows x86 / Win32 | `dosprotect_l4d1_mm.dll` | `dosprotect-l4d-win32` |
| Left 4 Dead 2 | `l4d2` | `9` | Windows x86 / Win32 | `dosprotect_l4d2_mm.dll` | `dosprotect-l4d2-win32` |

Both binaries are produced from the same source tree. Packet-handling logic is shared between L4D1 and L4D2 and the compiler rejects unsupported Source engine targets.

## What changed in the revamp

The original plugin kept a linear linked list of heap-allocated IP records for the entire server lifetime. The current implementation keeps the same mitigation response but modernizes the surrounding runtime:

- bounded IPv4 source table using `std::unordered_map` instead of a linear `SourceHook::List` scan;
- 64-bit packet counters;
- randomized mixed IPv4 hashing to make attacker-controlled key distribution less predictable;
- first/last-seen tracking using a monotonic clock;
- configurable expiration of inactive source records;
- configurable hard limit on retained source records;
- accounting for packets that cannot be associated with a valid IPv4 source;
- accounting for packets intentionally left untracked when the source table is full;
- total intercepted packet count;
- current/last/peak one-second telemetry;
- `dosp_top` ranked-source diagnostics;
- `dosp_reset` telemetry reset without disabling protection;
- validated `sockaddr`/`fromlen` handling before reading an IPv4 address;
- safer/idempotent hook installation and removal;
- protection against accidentally overwriting another plugin's later recvfrom hook during disable/unload;
- no per-packet console or disk logging in the hot path;
- per-game DLL and VDF packaging;
- build validation for x86 PE format, `CreateInterface` export and VDF/binary consistency.

## Runtime commands and ConVars

### Commands

```text
dosp_status
```

Shows version, game, binary, hook state, compatibility mode, total zero-length UDP interceptions, tracked source count, invalid-source count, table-full count, expired records, PPS telemetry and the top tracked sources.

```text
dosp_top
```

Shows the top 20 retained IPv4 sources ranked by intercepted packet count.

```text
dosp_reset
```

Clears telemetry and the retained source table. It does **not** change whether protection is enabled.

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
dosp_max_sources 4096
```

Maximum number of IPv4 source records retained in memory. The runtime clamps the effective value to `128..65536`.

```text
dosp_expire_seconds 900
```

Inactive records are removed after this many seconds. `0` disables expiration. Maintenance is amortized and does not scan the source table on every packet.

## Compatibility mode

The runtime reports:

```text
Compatibility: LEGACY-25
```

The critical path remains intentionally simple:

```cpp
const int ret = g_realRecvFrom(...);
if (ret == 0)
{
    RecordZeroDatagram(from, fromlen);
    return 25;
}
return ret;
```

`RecordZeroDatagram()` may update bounded telemetry, but it does not change the compatibility return value. Even if source metadata is absent or invalid, the function still returns `25` after a zero-length datagram because the mitigation contract takes priority over accounting.

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

Exact upstream revisions are stored in `build/dependencies.psd1` so SDK updates cannot silently change the binary produced by this baseline:

- Metamod:Source `1.12-dev`: `afc8233eedcd0c832b411c1da852328328db5c50`
- HL2SDK `l4d`: `0a8e862697335b12976a124daf728c38e975e381`
- HL2SDK `l4d2`: `2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6`

The build script downloads these repositories automatically and caches them outside the tracked source tree.

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

Discard cached dependencies and fetch the pinned revisions again:

```powershell
.\scripts\build.ps1 -Target all -CleanDeps
```

The script discovers Visual Studio with `vswhere.exe`, initializes an x86 developer environment through `VsDevCmd.bat`, compiles with the installed `cl.exe`, links against the correct HL2SDK libraries and validates each result using `dumpbin.exe`.

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

`.github/workflows/build.yml` runs a two-target matrix on the repository self-hosted Windows runner. The intended runner is the Dev VM runner named `dosprotect`.

Every push to `main`, pull request targeting `main`, or manual workflow run builds both packages.

The upload to GitHub Actions artifact storage is **best effort**. Artifact-storage quota exhaustion does not invalidate a successful compile/link/package validation. The actual build result is determined before the upload step.

Merged in-repository pull request branches are automatically removed by the workflow to keep the repository clean.

## Installation — Left 4 Dead

Copy the packaged `addons` directory from `dosprotect-l4d-win32` into the L4D game directory so the resulting paths are:

```text
left4dead/addons/dosprotect/bin/dosprotect_l4d1_mm.dll
left4dead/addons/metamod/dosprotect.vdf
```

## Installation — Left 4 Dead 2

Copy the packaged `addons` directory from `dosprotect-l4d2-win32` into the L4D2 game directory so the resulting paths are:

```text
left4dead2/addons/dosprotect/bin/dosprotect_l4d2_mm.dll
left4dead2/addons/metamod/dosprotect.vdf
```

Restart the server and verify the plugin through Metamod:

```text
meta list
```

Then inspect:

```text
dosp_status
```

## Runtime regression policy

Source/build CI is not a replacement for the real server attack regression. Any future change to the packet-handling path must be validated separately on both games.

See [`docs/REGRESSION_TEST.md`](docs/REGRESSION_TEST.md) for the acceptance procedure.

## License

The original source snapshot does not include a clear standalone license file. No new license is asserted for the inherited source until the original licensing status is established. Metamod:Source and HL2SDK retain their respective upstream licenses and are fetched as external build dependencies.
