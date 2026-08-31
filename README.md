# DoS Protect

Modern revamp of the original **DoS Protect** Metamod:Source plugin for **Left 4 Dead** and **Left 4 Dead 2**.

The project intentionally preserves the legacy UDP mitigation that has proven effective in production: when the hooked `recvfrom()` path returns a zero-length datagram, the compatibility path records the source and returns `25` to the engine. This behavior is regression-guarded and must not be removed or altered without a verified replacement that blocks the same attack case.

## Authorship

- **Revamp / current maintainer:** Kussun
- **Original project / original author:** ZombieX2.net

This repository is a substantial modernization effort based on the original DoS Protect source. Credit for the original implementation and concept remains with ZombieX2.net.

## Current version

`2.0.0-dev.1`

This is the first build-ready dual-target revamp baseline. The mitigation behavior remains intentionally compatible with the original implementation while the surrounding build and maintenance infrastructure is modernized.

## Supported targets

| Game | HL2SDK | `SOURCE_ENGINE` | Platform | Artifact |
| --- | --- | ---: | --- | --- |
| Left 4 Dead | `l4d` | `8` | Windows x86 / Win32 | `dosprotect-l4d-win32` |
| Left 4 Dead 2 | `l4d2` | `9` | Windows x86 / Win32 | `dosprotect-l4d2-win32` |

Both binaries are produced from the same source tree. The packet-handling logic is not forked between games.

## Repository layout

```text
build/
  dependencies.psd1
src/
  extension.cpp
  extension.h
  platform_wrappers.h
scripts/
  build.ps1
  verify-legacy-mitigation.ps1
.github/workflows/
  build.yml
dosprotect.vdf
```

## Pinned upstream dependencies

Exact upstream revisions are stored in `build/dependencies.psd1` so SDK updates cannot silently change the binary produced by this baseline:

- Metamod:Source `1.12-dev`: `afc8233eedcd0c832b411c1da852328328db5c50`
- HL2SDK `l4d`: `0a8e862697335b12976a124daf728c38e975e381`
- HL2SDK `l4d2`: `2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6`

The build script downloads these repositories automatically and caches them outside the tracked source tree.

## Local build

Requirements:

- Windows
- Visual Studio with **Desktop development with C++** and x86 build tools
- Git
- PowerShell

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

To discard cached dependencies and fetch the pinned revisions again:

```powershell
.\scripts\build.ps1 -Target all -CleanDeps
```

The script discovers Visual Studio with `vswhere.exe`, initializes an x86 developer environment through `VsDevCmd.bat`, compiles with the installed `cl.exe`, links against the correct HL2SDK libraries and validates each result as an x86 PE DLL using `dumpbin.exe`.

## Build output

L4D:

```text
artifacts/dosprotect-l4d-win32/
  addons/
    dosprotect/
      bin/
        dosprotect_mm.dll
        dosprotect_mm.pdb
    metamod/
      dosprotect.vdf
  README.md
  build-info.txt
```

L4D2:

```text
artifacts/dosprotect-l4d2-win32/
  addons/
    dosprotect/
      bin/
        dosprotect_mm.dll
        dosprotect_mm.pdb
    metamod/
      dosprotect.vdf
  README.md
  build-info.txt
```

Each `build-info.txt` records the target, dependency revisions, compiler identity and DLL SHA-256.

## GitHub Actions / self-hosted runner

`.github/workflows/build.yml` runs a two-target matrix on the repository self-hosted Windows runner. The intended runner is the Dev VM runner named `dosprotect`.

Every push to `main`, pull request targeting `main`, or manual workflow run builds both:

- `dosprotect-l4d-win32`
- `dosprotect-l4d2-win32`

Each package contains the appropriate game-specific DLL under the same Metamod install layout.

The upload to GitHub Actions artifact storage is **best effort**. A storage-quota failure does not invalidate a successful compile, link, x86 validation or SHA-256 calculation; those results remain visible in the workflow log and the package remains in the self-hosted runner workspace for the duration of that job. Once GitHub artifact storage is available again, the same workflow will upload both packages normally.

Merged in-repository pull request branches are automatically removed by the workflow to keep the repository clean.

## Regression guard

Before every build, `scripts/verify-legacy-mitigation.ps1` verifies that `MyRecvFromHook` still contains the compatibility path:

```cpp
if (ret == 0)
{
    // source accounting
    return 25;
}
```

This is not a substitute for the real attack regression test. It prevents accidental refactors from deleting the known working behavior before runtime testing occurs.

## Installation — Left 4 Dead

Copy the packaged `addons` directory from `dosprotect-l4d-win32` into the L4D game directory so the resulting paths are:

```text
left4dead/addons/dosprotect/bin/dosprotect_mm.dll
left4dead/addons/metamod/dosprotect.vdf
```

## Installation — Left 4 Dead 2

Copy the packaged `addons` directory from `dosprotect-l4d2-win32` into the L4D2 game directory so the resulting paths are:

```text
left4dead2/addons/dosprotect/bin/dosprotect_mm.dll
left4dead2/addons/metamod/dosprotect.vdf
```

Restart the server and verify the plugin through Metamod:

```text
meta list
```

Useful console commands:

```text
dosp_version
dosp_enable
dosp_status
```

## Compatibility policy

Changes to packet handling must be validated separately on both games:

1. Build the known-compatible baseline.
2. Confirm the known attack is blocked on L4D.
3. Confirm the known attack is blocked on L4D2.
4. Apply the proposed packet-handling change.
5. Rebuild both targets and repeat the same tests.
6. Accept the change only if protection remains equivalent or improves on both games.

## License

The original source snapshot does not include a clear standalone license file. No new license is asserted for the inherited source until the original licensing status is established. Metamod:Source and HL2SDK retain their respective upstream licenses and are fetched as external build dependencies.
