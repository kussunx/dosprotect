[CmdletBinding()]
param(
    [ValidateSet('l4d', 'l4d2', 'all')]
    [string]$Target = 'all',

    [ValidateSet('Release')]
    [string]$Configuration = 'Release',

    [switch]$CleanDeps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SourceFile = Join-Path $RepoRoot 'src\extension.cpp'
$HeaderFile = Join-Path $RepoRoot 'src\extension.h'
$DependencyLock = Import-PowerShellDataFile (Join-Path $RepoRoot 'build\dependencies.psd1')

if (-not (Test-Path $HeaderFile)) {
    throw "Version header not found: $HeaderFile"
}

$HeaderText = Get-Content -Raw -Path $HeaderFile
if ($HeaderText -notmatch '#define\s+DOSP_VERSION\s+"([^"]+)"') {
    throw 'Unable to derive DOSP_VERSION from src\extension.h.'
}
$DoSProtectVersion = $Matches[1]

if ($env:DOSP_DEPS_DIR) {
    $DepsRoot = $env:DOSP_DEPS_DIR
} elseif ($env:RUNNER_TOOL_CACHE) {
    $DepsRoot = Join-Path $env:RUNNER_TOOL_CACHE 'dosprotect-deps'
} else {
    $DepsRoot = Join-Path $RepoRoot '.deps'
}

$MetamodRoot = Join-Path $DepsRoot 'metamod-source'

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

    if (-not (Test-Path (Join-Path $Path '.git'))) {
        New-Item -ItemType Directory -Force (Split-Path $Path -Parent) | Out-Null
        Invoke-Git clone --filter=blob:none $Url $Path
    }

    Invoke-Git -C $Path fetch --force --depth 1 origin $Commit
    Invoke-Git -C $Path checkout --force --detach $Commit
    Invoke-Git -C $Path clean -ffd

    if ($Submodules) {
        Invoke-Git -C $Path submodule sync --recursive
        Invoke-Git -C $Path submodule update --init --recursive --depth 1
    }
}

function Import-VsDevEnvironment {
    $Candidates = @(@(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
    ) | Where-Object { $_ -and (Test-Path $_) })

    if ($Candidates.Count -eq 0) {
        $VsWhereCommand = Get-Command vswhere.exe -ErrorAction SilentlyContinue
        if ($VsWhereCommand) {
            $Candidates = @($VsWhereCommand.Source)
        }
    }

    if ($Candidates.Count -eq 0) {
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

    foreach ($Tool in @('cl.exe', 'link.exe', 'dumpbin.exe')) {
        if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
            throw "$Tool is unavailable after initializing Visual Studio."
        }
    }
}

function Build-Game {
    param([ValidateSet('l4d', 'l4d2')][string]$Game)

    if ($Game -eq 'l4d') {
        $TargetConfig = $DependencyLock.L4D
        $DisplayName = 'Left 4 Dead'
        $BinaryBaseName = 'dosprotect_l4d1_mm'
        $VdfSource = Join-Path $RepoRoot 'config\dosprotect_l4d1.vdf'
    }
    else {
        $TargetConfig = $DependencyLock.L4D2
        $DisplayName = 'Left 4 Dead 2'
        $BinaryBaseName = 'dosprotect_l4d2_mm'
        $VdfSource = Join-Path $RepoRoot 'config\dosprotect_l4d2.vdf'
    }

    $Hl2SdkRoot = Join-Path $DepsRoot "hl2sdk-$Game"
    $ArtifactRoot = Join-Path $RepoRoot "artifacts\dosprotect-$Game-win32"
    $BinRoot = Join-Path $ArtifactRoot 'addons\dosprotect\bin'
    $MetaRoot = Join-Path $ArtifactRoot 'addons\metamod'
    $ObjRoot = Join-Path $RepoRoot "out\$Game\obj"

    Ensure-Checkout -Url $TargetConfig.Repository -Path $Hl2SdkRoot -Commit $TargetConfig.Commit

    Remove-Item -Recurse -Force $ArtifactRoot, $ObjRoot -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $BinRoot, $MetaRoot, $ObjRoot | Out-Null

    $DllPath = Join-Path $BinRoot "$BinaryBaseName.dll"
    $PdbPath = Join-Path $BinRoot "$BinaryBaseName.pdb"
    $ObjPath = Join-Path $ObjRoot 'extension.obj'
    $ObjPdbPath = Join-Path $ObjRoot 'compile.pdb'
    $ImportLibPath = Join-Path $ObjRoot "$BinaryBaseName.lib"

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
        "/DSOURCE_ENGINE=$($TargetConfig.Engine)"
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
        "/Fo$ObjPath",
        "/Fd$ObjPdbPath"
    ) + $Defines + $Includes + @($SourceFile)

    Write-Host "Compiling DoS Protect for $DisplayName (Win32/x86, SOURCE_ENGINE=$($TargetConfig.Engine))..."
    & cl.exe @CompileArgs
    if ($LASTEXITCODE -ne 0) {
        throw "$DisplayName compilation failed with exit code $LASTEXITCODE"
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
        "/IMPLIB:$ImportLibPath",
        "/OUT:$DllPath",
        $ObjPath
    ) + $Libraries

    Write-Host "Linking $DisplayName $BinaryBaseName.dll..."
    & link.exe @LinkArgs
    if ($LASTEXITCODE -ne 0) {
        throw "$DisplayName link failed with exit code $LASTEXITCODE"
    }

    if (-not (Test-Path $VdfSource)) {
        throw "Target VDF is missing: $VdfSource"
    }

    Copy-Item $VdfSource (Join-Path $MetaRoot 'dosprotect.vdf') -Force
    Copy-Item (Join-Path $RepoRoot 'README.md') (Join-Path $ArtifactRoot 'README.md') -Force

    $Headers = & dumpbin.exe /headers $DllPath
    if ($LASTEXITCODE -ne 0 -or -not ($Headers -match '14C machine \(x86\)')) {
        throw "$DisplayName DLL is not a valid x86 PE image."
    }

    $Exports = & dumpbin.exe /exports $DllPath
    if ($LASTEXITCODE -ne 0 -or -not ($Exports -match 'CreateInterface')) {
        throw "$DisplayName DLL does not export CreateInterface as required by Metamod:Source."
    }

    $PackagedVdf = Get-Content -Raw -Path (Join-Path $MetaRoot 'dosprotect.vdf')
    if ($PackagedVdf -notmatch [regex]::Escape($BinaryBaseName)) {
        throw "$DisplayName packaged VDF does not reference $BinaryBaseName."
    }

    $Hash = (Get-FileHash -Algorithm SHA256 $DllPath).Hash
    $Compiler = "MSVC $env:VCToolsVersion (x86)"
    $BuildInfo = @(
        "DoS Protect $DisplayName Win32 build",
        "Version: $DoSProtectVersion",
        "Binary: $BinaryBaseName.dll",
        "Configuration: $Configuration",
        "SOURCE_ENGINE: $($TargetConfig.Engine)",
        "Metamod:Source commit: $($DependencyLock.MetamodSource.Commit)",
        "HL2SDK $Game commit: $($TargetConfig.Commit)",
        "Compiler: $Compiler",
        "DLL SHA256: $Hash"
    ) -join [Environment]::NewLine
    Set-Content -Path (Join-Path $ArtifactRoot 'build-info.txt') -Value $BuildInfo -Encoding UTF8

    Write-Host ''
    Write-Host "$DisplayName build complete."
    Write-Host "Version: $DoSProtectVersion"
    Write-Host "DLL: $DllPath"
    Write-Host "SHA256: $Hash"
}

if ($env:OS -ne 'Windows_NT') {
    throw 'This build targets Windows x86 only.'
}

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    throw 'git.exe is required.'
}

if ($CleanDeps -and (Test-Path $DepsRoot)) {
    Remove-Item -Recurse -Force $DepsRoot
}

& (Join-Path $PSScriptRoot 'verify-legacy-mitigation.ps1')

Ensure-Checkout -Url $DependencyLock.MetamodSource.Repository -Path $MetamodRoot -Commit $DependencyLock.MetamodSource.Commit -Submodules
Import-VsDevEnvironment

$Targets = if ($Target -eq 'all') { @('l4d', 'l4d2') } else { @($Target) }
foreach ($Game in $Targets) {
    Build-Game -Game $Game
}

Write-Host ''
Write-Host 'Requested DoS Protect build(s) completed successfully.'
