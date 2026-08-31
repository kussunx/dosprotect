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

$HookPattern = '(?s)int\s+MyRecvFromHook\s*\([^)]*\).*?const\s+int\s+ret\s*=.*?if\s*\(\s*ret\s*==\s*0\s*\)\s*\{\s*return\s+HandleZeroDatagram\s*\(\s*from\s*,\s*fromlen\s*\)\s*;\s*\}.*?return\s+ret\s*;'
$ModernPattern = '(?s)int\s+HandleZeroDatagram\s*\([^)]*\).*?RecordZeroDatagram\s*\(\s*from\s*,\s*fromlen\s*\)\s*;.*?SetNoDeliverableDatagramError\s*\(\s*\)\s*;\s*return\s+SOCKET_ERROR\s*;'
$LegacyFallbackPattern = '(?s)if\s*\(\s*g_effectiveMitigationMode\s*==\s*kLegacy25Mode\s*\)\s*\{.*?return\s+25\s*;.*?\}'
$WouldBlockPattern = 'WSASetLastError\s*\(\s*WSAEWOULDBLOCK\s*\)'
$DefaultModernPattern = 'constexpr\s+int\s+kDefaultMitigationMode\s*=\s*kModernDropMode\s*;'
$TargetGuardPattern = '#if\s+SOURCE_ENGINE\s*!=\s*SE_LEFT4DEAD\s*&&\s*SOURCE_ENGINE\s*!=\s*SE_LEFT4DEAD2'

if ($Source -notmatch $HookPattern) {
    throw 'Regression guard failed: recvfrom zero-datagram dispatch path is missing or structurally changed.'
}

if ($Source -notmatch $ModernPattern -or $Source -notmatch $WouldBlockPattern) {
    throw 'Regression guard failed: modern DROP-WOULDBLOCK path is missing or structurally changed.'
}

if ($Source -notmatch $LegacyFallbackPattern) {
    throw 'Regression guard failed: LEGACY-25 emergency fallback is missing.'
}

if ($Source -notmatch $DefaultModernPattern) {
    throw 'Regression guard failed: modern mitigation is no longer the default.'
}

if ($Source -notmatch $TargetGuardPattern) {
    throw 'Regression guard failed: explicit L4D/L4D2 compile target guard is missing.'
}

Write-Host 'L4D/L4D2 mitigation regression guard: OK (DROP-WOULDBLOCK default + LEGACY-25 fallback preserved).'
