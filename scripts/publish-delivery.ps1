[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('l4d', 'l4d2')]
    [string]$Target
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ArtifactRoot = Join-Path $RepoRoot "artifacts\dosprotect-$Target-win32"
$DeliveryRoot = Join-Path $RepoRoot "delivery\$Target"

if (-not (Test-Path $ArtifactRoot)) {
    throw "Artifact root not found: $ArtifactRoot"
}

New-Item -ItemType Directory -Force $DeliveryRoot | Out-Null
Copy-Item (Join-Path $ArtifactRoot 'addons\dosprotect\bin\*.dll') $DeliveryRoot -Force
Copy-Item (Join-Path $ArtifactRoot 'addons\metamod\dosprotect.vdf') $DeliveryRoot -Force
Copy-Item (Join-Path $ArtifactRoot 'build-info.txt') $DeliveryRoot -Force

$Dll = Get-ChildItem -Path $DeliveryRoot -Filter '*.dll' | Select-Object -First 1
if (-not $Dll) {
    throw "No DLL found in $DeliveryRoot"
}

Get-ChildItem -Path $DeliveryRoot -Filter '*.b64.*.txt' -ErrorAction SilentlyContinue | Remove-Item -Force
$Base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Dll.FullName))
$ChunkSize = 48000
$Part = 1
for ($Offset = 0; $Offset -lt $Base64.Length; $Offset += $ChunkSize) {
    $Length = [Math]::Min($ChunkSize, $Base64.Length - $Offset)
    $Chunk = $Base64.Substring($Offset, $Length)
    $PartPath = Join-Path $DeliveryRoot ("{0}.b64.{1:D2}.txt" -f $Dll.BaseName, $Part)
    [IO.File]::WriteAllText($PartPath, $Chunk, [Text.Encoding]::ASCII)
    $Part++
}

[IO.File]::WriteAllText(
    (Join-Path $DeliveryRoot ($Dll.BaseName + '.b64.parts.txt')),
    [string]($Part - 1),
    [Text.Encoding]::ASCII)

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add -f "delivery/$Target"
git commit -m "delivery: $Target recompiled binaries"
if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }
git push --force origin "HEAD:refs/heads/delivery/$Target"
if ($LASTEXITCODE -ne 0) { throw 'git push failed' }
