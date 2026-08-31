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
    @{ Name = 'zero datagram branch'; Pattern = 'if\s*\(\s*ret\s*!=\s*0\s*\)' },
    @{ Name = 'bounded burst handler'; Pattern = 'int\s+HandleZeroDatagramBurst\s*\(' },
    @{ Name = 'zero datagram accounting'; Pattern = 'RecordZeroDatagram\s*\(' },
    @{ Name = 'socket readiness probe'; Pattern = 'SocketReadableNow\s*\(\s*s\s*\)' },
    @{ Name = 'drain budget'; Pattern = 'droppedThisCall\s*>=\s*g_effectiveDrainBudget' },
    @{ Name = 'would-block result'; Pattern = 'WSASetLastError\s*\(\s*WSAEWOULDBLOCK\s*\)' },
    @{ Name = 'socket error return'; Pattern = 'return\s+SOCKET_ERROR\s*;' },
    @{ Name = 'dual-game target guard'; Pattern = '#if\s+SOURCE_ENGINE\s*!=\s*SE_LEFT4DEAD\s*&&\s*SOURCE_ENGINE\s*!=\s*SE_LEFT4DEAD2' },
    @{ Name = 'Win32 ABI guard'; Pattern = 'static_assert\s*\(\s*sizeof\(SOCKET\)\s*==\s*sizeof\(int\)' }
)

foreach ($Required in $RequiredPatterns) {
    if ($Source -notmatch $Required.Pattern) {
        throw "Mitigation guard failed: required structure '$($Required.Name)' is missing."
    }
}

$ForbiddenPatterns = @(
    @{ Name = 'legacy fabricated packet length'; Pattern = 'return\s+25\s*;' },
    @{ Name = 'legacy mode label'; Pattern = 'LEGACY-25' },
    @{ Name = 'legacy mitigation selector'; Pattern = 'dosp_mitigation_mode' }
)

foreach ($Forbidden in $ForbiddenPatterns) {
    if ($Source -match $Forbidden.Pattern) {
        throw "Mitigation guard failed: removed legacy structure '$($Forbidden.Name)' is present."
    }
}

Write-Host 'L4D/L4D2 mitigation guard: OK (bounded DROP-WOULDBLOCK path only).'
