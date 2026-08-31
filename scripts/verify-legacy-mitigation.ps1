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

$HookPattern = '(?s)int\s+MyRecvFromHook\s*\([^)]*\).*?const\s+int\s+ret\s*=\s*g_realRecvFrom.*?if\s*\(\s*ret\s*!=\s*0\s*\).*?return\s+ret\s*;.*?return\s+HandleModernZeroDatagrams\s*\('
$ModernDrainPattern = '(?s)int\s+HandleModernZeroDatagrams\s*\([^)]*\).*?RecordZeroDatagram\s*\(\s*from\s*,\s*fromlen\s*\).*?SocketReadableNow\s*\(\s*s\s*\).*?g_realRecvFrom\s*\(\s*s\s*,\s*buf\s*,\s*len\s*,\s*flags\s*,\s*from\s*,\s*fromlen\s*\).*?SetNoDeliverableDatagramError\s*\(\s*\).*?return\s+SOCKET_ERROR\s*;'
$LegacyFallbackPattern = '(?s)if\s*\(\s*g_effectiveMitigationMode\s*==\s*kLegacy25Mode\s*\)\s*\{.*?RecordZeroDatagram\s*\(\s*from\s*,\s*fromlen\s*\).*?return\s+25\s*;.*?\}'
$WouldBlockPattern = 'WSASetLastError\s*\(\s*WSAEWOULDBLOCK\s*\)'
$DefaultModernPattern = 'constexpr\s+int\s+kDefaultMitigationMode\s*=\s*kModernDropMode\s*;'
$DrainBudgetPattern = 'constexpr\s+int\s+kDefaultDrainBudget\s*=\s*256\s*;'
$TargetGuardPattern = '#if\s+SOURCE_ENGINE\s*!=\s*SE_LEFT4DEAD\s*&&\s*SOURCE_ENGINE\s*!=\s*SE_LEFT4DEAD2'

if ($Source -notmatch $HookPattern) {
    throw 'Regression guard failed: recvfrom modern dispatch path is missing or structurally changed.'
}

if ($Source -notmatch $ModernDrainPattern -or $Source -notmatch $WouldBlockPattern) {
    throw 'Regression guard failed: bounded DROP-WOULDBLOCK drain path is missing or structurally changed.'
}

if ($Source -notmatch $LegacyFallbackPattern) {
    throw 'Regression guard failed: LEGACY-25 emergency fallback is missing.'
}

if ($Source -notmatch $DefaultModernPattern -or $Source -notmatch $DrainBudgetPattern) {
    throw 'Regression guard failed: modern mitigation defaults are no longer present.'
}

if ($Source -notmatch $TargetGuardPattern) {
    throw 'Regression guard failed: explicit L4D/L4D2 compile target guard is missing.'
}

Write-Host 'L4D/L4D2 mitigation regression guard: OK (bounded DROP-WOULDBLOCK default + LEGACY-25 fallback preserved).'
