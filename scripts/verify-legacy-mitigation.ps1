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
$Pattern = '(?s)int\s+MyRecvFromHook\s*\([^)]*\).*?g_real_recvfrom_ptr\s*\([^;]+;.*?if\s*\(\s*ret\s*==\s*0\s*\).*?return\s+25\s*;'

if ($Source -notmatch $Pattern) {
    throw 'Regression guard failed: legacy L4D recvfrom mitigation (ret == 0 -> return 25) is missing or structurally changed.'
}

Write-Host 'Legacy mitigation regression guard: OK (ret == 0 -> return 25 preserved).'
