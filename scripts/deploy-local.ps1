[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('l4d', 'l4d2')]
    [string]$Target
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LocalRepo = 'C:\L4D-DEV\dosprotect'
$ArtifactRoot = Join-Path $RepoRoot "artifacts\dosprotect-$Target-win32"
$DestinationRoot = Join-Path $LocalRepo "artifacts\dosprotect-$Target-win32"
$ReadyRoot = Join-Path $LocalRepo 'READY'

if (-not (Test-Path $ArtifactRoot)) {
    throw "Build artifact not found: $ArtifactRoot"
}

if (-not (Test-Path $LocalRepo)) {
    New-Item -ItemType Directory -Force $LocalRepo | Out-Null
}

$GitDir = Join-Path $LocalRepo '.git'
if (Test-Path $GitDir) {
    $TrackedDirty = @(& git -C $LocalRepo status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to inspect the local C:\L4D-DEV\dosprotect clone.'
    }

    if ($TrackedDirty.Count -eq 0) {
        & git -C $LocalRepo fetch origin main
        if ($LASTEXITCODE -ne 0) { throw 'git fetch failed for local clone.' }
        & git -C $LocalRepo checkout main
        if ($LASTEXITCODE -ne 0) { throw 'git checkout main failed for local clone.' }
        & git -C $LocalRepo merge --ff-only origin/main
        if ($LASTEXITCODE -eq 0) {
            Write-Host 'LOCAL_SOURCE_SYNC=updated'
        } else {
            Write-Host 'LOCAL_SOURCE_SYNC=skipped-non-fast-forward'
        }
    } else {
        Write-Host 'LOCAL_SOURCE_SYNC=skipped-tracked-changes'
    }
}

Remove-Item -Recurse -Force $DestinationRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Split-Path $DestinationRoot -Parent), $ReadyRoot | Out-Null
Copy-Item -Recurse -Force $ArtifactRoot $DestinationRoot

if ($Target -eq 'l4d') {
    $BinaryName = 'dosprotect_l4d1_mm.dll'
    $ReadyVdf = 'dosprotect_l4d1.vdf'
} else {
    $BinaryName = 'dosprotect_l4d2_mm.dll'
    $ReadyVdf = 'dosprotect_l4d2.vdf'
}

$DllSource = Join-Path $ArtifactRoot "addons\dosprotect\bin\$BinaryName"
$VdfSource = Join-Path $ArtifactRoot 'addons\metamod\dosprotect.vdf'
$InfoSource = Join-Path $ArtifactRoot 'build-info.txt'

Copy-Item -Force $DllSource (Join-Path $ReadyRoot $BinaryName)
Copy-Item -Force $VdfSource (Join-Path $ReadyRoot $ReadyVdf)
Copy-Item -Force $InfoSource (Join-Path $ReadyRoot "build-info-$Target.txt")

$Hash = (Get-FileHash -Algorithm SHA256 (Join-Path $ReadyRoot $BinaryName)).Hash
Write-Host "LOCAL_DELIVERY_TARGET=$Target"
Write-Host "LOCAL_DELIVERY_DLL=$(Join-Path $ReadyRoot $BinaryName)"
Write-Host "LOCAL_DELIVERY_SHA256=$Hash"
