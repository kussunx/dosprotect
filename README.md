# DoS Protect

Modern revamp of the original **DoS Protect** Metamod:Source plugin for **Left 4 Dead 1**.

The project intentionally preserves the legacy UDP mitigation that has proven effective in L4D1 deployments: when the hooked `recvfrom()` path returns a zero-length datagram, the compatibility path records the source and returns `25` to the engine. This behavior is regression-guarded and must not be removed or altered without a verified replacement that blocks the same attack case.

## Authorship

- **Revamp / current maintainer:** Kussun
- **Original project / original author:** ZombieX2.net

This repository is a substantial modernization effort based on the original DoS Protect source. Credit for the original implementation and concept remains with ZombieX2.net.

## Current version

`2.0.0-dev.1`

This is the first build-ready revamp baseline. The mitigation behavior remains intentionally compatible with the original implementation while the surrounding build and maintenance infrastructure has been modernized.

## Target

- Game: Left 4 Dead 1
- Engine: Source / `SE_LEFT4DEAD`
- Metamod:Source: 1.12 development line, pinned for reproducible builds
- Platform: Windows
- Architecture: x86 / Win32
- Compiler: Microsoft C++ toolchain from the installed Visual Studio instance

## Repository layout

```text
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

The build script pins exact upstream revisions so that a future SDK change cannot silently alter the binary produced by this baseline:

- Metamod:Source: `afc8233eedcd0c832b411c1da852328328db5c50`
- HL2SDK `l4d`: `0a8e862697335b12976a124daf728c38e975e381`

The script downloads these repositories automatically. They are not vendored into this repository.

## Local build

Requirements:

- Windows
- Visual Studio with **Desktop development with C++** and x86 build tools
- Git
- PowerShell

From the repository root:

```powershell
.\scripts\build.ps1
```

To discard cached upstream dependencies and fetch them again:

```powershell
.\scripts\build.ps1 -CleanDeps
```

The script discovers Visual Studio with `vswhere.exe`, initializes an x86 developer environment through `VsDevCmd.bat`, compiles with the installed `cl.exe`, links against the pinned L4D HL2SDK libraries and validates that the result is an x86 PE DLL.

## Build output

Successful builds create:

```text
artifacts/dosprotect-l4d-win32/
  addons/
    dosprotect/
      bin/
        dosprotect_mm.dll
        dosprotect_mm.pdb
    metamod/
      dosprotect.vdf
  build-info.txt
```

`build-info.txt` contains the dependency revisions, compiler identity and DLL SHA-256.

## GitHub Actions / self-hosted runner

The workflow uses the repository's Windows self-hosted runner label:

```text
self-hosted
dosprotect
```

It runs on pushes to `main`, pull requests targeting `main`, and manual `workflow_dispatch` runs. Successful runs upload `dosprotect-l4d-win32` as a GitHub Actions artifact.

## Regression guard

Before every build, `scripts/verify-legacy-mitigation.ps1` verifies that `MyRecvFromHook` still contains the compatibility path:

```cpp
if (ret == 0)
{
    // source accounting
    return 25;
}
```

This is not a substitute for the real L4D attack regression test. It prevents accidental source refactors from deleting the known working behavior before runtime testing occurs.

## Installation

Copy the packaged `addons` directory into the L4D `left4dead` game directory so the resulting paths are:

```text
left4dead/addons/dosprotect/bin/dosprotect_mm.dll
left4dead/addons/metamod/dosprotect.vdf
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

The following sequence is mandatory for changes to the packet-handling path:

1. Build the known-compatible baseline.
2. Confirm the known L4D attack is blocked.
3. Apply the proposed packet-handling change.
4. Rebuild and repeat the same attack test.
5. Accept the change only if protection remains equivalent or improves.

## License

The original source snapshot does not include a clear standalone license file. No new license is asserted for the inherited source until the original licensing status is established. Metamod:Source and HL2SDK retain their respective upstream licenses and are fetched as external build dependencies.
