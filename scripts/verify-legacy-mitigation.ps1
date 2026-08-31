[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SourcePath = Join-Path $RepoRoot 'src\extension.cpp'

if (-not (Test-Path $SourcePath)) {
    throw "Source file not found: $SourcePath"
}

$Source = Get-Content -Raw -Path $SourcePath

$HookPattern = '(?s)int\s+MyRecvFromHook\s*\([^)]*\).*?const\s+int\s+ret\s*=.*?if\s*\(\s*ret\s*==\s*0\s*\)\s*\{.*?RecordZeroDatagram\s*\(\s*from\s*,\s*fromlen\s*\)\s*;.*?return\s+25\s*;.*?\}\s*return\s+ret\s*;'
$TargetGuardPattern = '#if\s+SOURCE_ENGINE\s*!=\s*SE_LEFT4DEAD\s*&&\s*SOURCE_ENGINE\s*!=\s*SE_LEFT4DEAD2'

if ($Source -notmatch $HookPattern) {
    throw 'Regression guard failed: recvfrom legacy compatibility path (ret == 0 -> RecordZeroDatagram -> return 25) is missing or structurally changed.'
}

if ($Source -notmatch $TargetGuardPattern) {
    throw 'Regression guard failed: explicit L4D/L4D2 compile target guard is missing.'
}

Write-Host 'Legacy L4D/L4D2 mitigation regression guard: OK (ret == 0 -> return 25 preserved).'
