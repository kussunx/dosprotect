[CmdletBinding()]
param(
    [switch]$CleanDeps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SourceFile = Join-Path $RepoRoot 'src\extension.cpp'
$ArtifactRoot = Join-Path $RepoRoot 'artifacts\dosprotect-l4d-win32'
$BinRoot = Join-Path $ArtifactRoot 'addons\dosprotect\bin'
$MetaRoot = Join-Path $ArtifactRoot 'addons\metamod'
$ObjRoot = Join-Path $RepoRoot 'out\obj'

$MetamodCommit = 'afc8233eedcd0c832b411c1da852328328db5c50'
$Hl2SdkCommit = '0a8e862697335b12976a124daf728c38e975e381'

if ($env:DOSP_DEPS_DIR) {
    $DepsRoot = $env:DOSP_DEPS_DIR
} elseif ($env:RUNNER_TOOL_CACHE) {
    $DepsRoot = Join-Path $env:RUNNER_TOOL_CACHE 'dosprotect-deps'
} else {
    $DepsRoot = Join-Path $RepoRoot '.deps'
}

$MetamodRoot = Join-Path $DepsRoot 'metamod-source'
$Hl2SdkRoot = Join-Path $DepsRoot 'hl2sdk-l4d'

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git failed: git $($Arguments -join ' ')"
    }
}

function Ensure-Checkout {
    param(
        [string]$Url,
        [string]$Path,
        [string]$Commit,
        [switch]$Submodules
    )

    if ($CleanDeps -and (Test-Path $Path)) {
        Remove-Item -Recurse -Force $Path
    }

    if (-not (Test-Path (Join-Path $Path '.git'))) {
        New-Item -ItemType Directory -Force (Split-Path $Path -Parent) | Out-Null
        Invoke-Git clone --filter=blob:none $Url $Path
    }

    Invoke-Git -C $Path fetch --depth 1 origin $Commit
    Invoke-Git -C $Path checkout --detach $Commit

    if ($Submodules) {
        Invoke-Git -C $Path submodule sync --recursive
        Invoke-Git -C $Path submodule update --init --recursive --depth 1
    }
}

function Import-VsDevEnvironment {
    $Candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
    ) | Where-Object { $_ -and (Test-Path $_) }

    if (-not $Candidates) {
        throw 'vswhere.exe was not found. Install Visual Studio with Desktop development with C++.'
    }

    $VsWhere = $Candidates[0]
    $InstallPath = (& $VsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    if (-not $InstallPath) {
        throw 'Visual Studio C++ x86/x64 build tools were not found.'
    }

    $VsDevCmd = Join-Path $InstallPath 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path $VsDevCmd)) {
        throw "VsDevCmd.bat was not found under $InstallPath"
    }

    Write-Host "Using Visual Studio: $InstallPath"

    $CmdLine = "`"$VsDevCmd`" -no_logo -arch=x86 -host_arch=x64 >nul && set"
    $Environment = & $env:ComSpec /s /c $CmdLine
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to initialize the Visual Studio x86 developer environment.'
    }

    foreach ($Line in $Environment) {
        if ($Line -match '^([^=]+)=(.*)$') {
            Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2]
        }
    }

    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
        throw 'cl.exe is unavailable after initializing Visual Studio.'
    }
}

if ($env:OS -ne 'Windows_NT') {
    throw 'This baseline build currently targets Windows x86 only.'
}

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    throw 'git.exe is required.'
}

& (Join-Path $PSScriptRoot 'verify-legacy-mitigation.ps1')
if ($LASTEXITCODE -ne 0) {
    throw 'Legacy mitigation verification failed.'
}

Ensure-Checkout -Url 'https://github.com/alliedmodders/metamod-source.git' -Path $MetamodRoot -Commit $MetamodCommit -Submodules
Ensure-Checkout -Url 'https://github.com/alliedmodders/hl2sdk.git' -Path $Hl2SdkRoot -Commit $Hl2SdkCommit

Import-VsDevEnvironment

Remove-Item -Recurse -Force $ArtifactRoot, $ObjRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $BinRoot, $MetaRoot, $ObjRoot | Out-Null

$DllPath = Join-Path $BinRoot 'dosprotect_mm.dll'
$PdbPath = Join-Path $BinRoot 'dosprotect_mm.pdb'
$ObjPath = Join-Path $ObjRoot 'extension.obj'

$Defines = @(
    '/DWIN32',
    '/D_WINDOWS',
    '/D_USRDLL',
    '/DNDEBUG',
    '/D_CRT_SECURE_NO_DEPRECATE',
    '/D_CRT_SECURE_NO_WARNINGS',
    '/D_CRT_NONSTDC_NO_DEPRECATE',
    '/DSE_EPISODE1=1',
    '/DSE_DARKMESSIAH=2',
    '/DSE_ORANGEBOX=3',
    '/DSE_BLOODYGOODTIME=4',
    '/DSE_EYE=5',
    '/DSE_CSS=6',
    '/DSE_ORANGEBOXVALVE=7',
    '/DSE_LEFT4DEAD=8',
    '/DSE_LEFT4DEAD2=9',
    '/DSE_ALIENSWARM=10',
    '/DSE_PORTAL2=11',
    '/DSE_CSGO=12',
    '/DSE_DOTA=13',
    '/DSOURCE_ENGINE=8'
)

$Includes = @(
    "/I$($MetamodRoot)\core",
    "/I$($MetamodRoot)\core\sourcehook",
    "/I$($Hl2SdkRoot)\public",
    "/I$($Hl2SdkRoot)\public\engine",
    "/I$($Hl2SdkRoot)\public\game\server",
    "/I$($Hl2SdkRoot)\public\tier0",
    "/I$($Hl2SdkRoot)\public\tier1",
    "/I$($Hl2SdkRoot)\public\vstdlib"
)

$CompileArgs = @(
    '/nologo',
    '/c',
    '/TP',
    '/O2',
    '/MT',
    '/W3',
    '/Zi',
    '/EHsc',
    '/Oy-',
    '/std:c++17',
    "/Fo$ObjPath"
) + $Defines + $Includes + @($SourceFile)

Write-Host 'Compiling DoS Protect for Left 4 Dead (Win32/x86)...'
& cl.exe @CompileArgs
if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE"
}

$Libraries = @(
    (Join-Path $Hl2SdkRoot 'lib\public\tier0.lib'),
    (Join-Path $Hl2SdkRoot 'lib\public\tier1.lib'),
    (Join-Path $Hl2SdkRoot 'lib\public\vstdlib.lib'),
    'kernel32.lib',
    'user32.lib',
    'advapi32.lib',
    'ws2_32.lib'
)

$LinkArgs = @(
    '/NOLOGO',
    '/DLL',
    '/MACHINE:X86',
    '/SUBSYSTEM:WINDOWS',
    '/OPT:REF',
    '/OPT:ICF',
    '/DEBUG',
    "/PDB:$PdbPath",
    "/OUT:$DllPath",
    $ObjPath
) + $Libraries

Write-Host 'Linking dosprotect_mm.dll...'
& link.exe @LinkArgs
if ($LASTEXITCODE -ne 0) {
    throw "Link failed with exit code $LASTEXITCODE"
}

Copy-Item (Join-Path $RepoRoot 'dosprotect.vdf') (Join-Path $MetaRoot 'dosprotect.vdf') -Force

$Headers = & dumpbin.exe /headers $DllPath
if ($LASTEXITCODE -ne 0 -or -not ($Headers -match '14C machine \(x86\)')) {
    throw 'Built DLL is not a valid x86 PE image.'
}

$Hash = (Get-FileHash -Algorithm SHA256 $DllPath).Hash
$Compiler = (& cl.exe 2>&1 | Select-Object -First 1)
$BuildInfo = @(
    'DoS Protect L4D1 Win32 build',
    "Version: 2.0.0-dev.1",
    "Metamod:Source commit: $MetamodCommit",
    "HL2SDK L4D commit: $Hl2SdkCommit",
    "Compiler: $Compiler",
    "DLL SHA256: $Hash"
) -join [Environment]::NewLine
Set-Content -Path (Join-Path $ArtifactRoot 'build-info.txt') -Value $BuildInfo -Encoding UTF8

Write-Host ''
Write-Host 'Build complete.'
Write-Host "DLL: $DllPath"
Write-Host "SHA256: $Hash"
