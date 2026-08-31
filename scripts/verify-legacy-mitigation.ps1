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

$RequiredPatterns = @(
    @{ Name = 'recvfrom hook'; Pattern = 'int\s+MyRecvFromHook\s*\(' },
    @{ Name = 'real recvfrom call'; Pattern = 'g_realRecvFrom\s*\(\s*s\s*,\s*buf\s*,\s*len\s*,\s*flags\s*,\s*from\s*,\s*fromlen\s*\)' },
    @{ Name = 'zero-datagram branch'; Pattern = 'if\s*\(\s*ret\s*!=\s*0\s*\)' },
    @{ Name = 'modern drain function'; Pattern = 'int\s+HandleModernZeroDatagrams\s*\(' },
    @{ Name = 'zero datagram telemetry'; Pattern = 'RecordZeroDatagram\s*\(\s*from\s*,\s*fromlen\s*\)' },
    @{ Name = 'readiness probe'; Pattern = 'SocketReadableNow\s*\(\s*s\s*\)' },
    @{ Name = 'bounded drain check'; Pattern = 'drained\s*>=\s*g_effectiveDrainBudget' },
    @{ Name = 'would-block translation'; Pattern = 'WSASetLastError\s*\(\s*WSAEWOULDBLOCK\s*\)' },
    @{ Name = 'socket error return'; Pattern = 'return\s+SOCKET_ERROR\s*;' },
    @{ Name = 'legacy mode branch'; Pattern = 'g_effectiveMitigationMode\s*==\s*kLegacy25Mode' },
    @{ Name = 'legacy return 25'; Pattern = 'return\s+25\s*;' },
    @{ Name = 'modern default'; Pattern = 'constexpr\s+int\s+kDefaultMitigationMode\s*=\s*kModernDropMode\s*;' },
    @{ Name = 'default drain budget'; Pattern = 'constexpr\s+int\s+kDefaultDrainBudget\s*=\s*256\s*;' },
    @{ Name = 'dual-game target guard'; Pattern = '#if\s+SOURCE_ENGINE\s*!=\s*SE_LEFT4DEAD\s*&&\s*SOURCE_ENGINE\s*!=\s*SE_LEFT4DEAD2' }
)

foreach ($Required in $RequiredPatterns) {
    if ($Source -notmatch $Required.Pattern) {
        throw "Regression guard failed: required mitigation structure '$($Required.Name)' is missing."
    }
}

$LegacyBlockPattern = '(?s)if\s*\(\s*g_effectiveMitigationMode\s*==\s*kLegacy25Mode\s*\)\s*\{.*?RecordZeroDatagram\s*\(\s*from\s*,\s*fromlen\s*\).*?\+\+g_stats\.legacy25Responses\s*;.*?return\s+25\s*;.*?\}'
if ($Source -notmatch $LegacyBlockPattern) {
    throw 'Regression guard failed: LEGACY-25 fallback no longer records telemetry and returns 25 as one guarded block.'
}

Write-Host 'L4D/L4D2 mitigation regression guard: OK (bounded DROP-WOULDBLOCK default + LEGACY-25 fallback preserved).'
