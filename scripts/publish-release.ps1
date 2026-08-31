[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('l4d', 'l4d2')]
    [string]$Target
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Version = '2.0.0-dev.2'
$Tag = 'v2.0.0-dev.2'
$ReleaseTarget = '6a0904ca7ee7071de37934289e414ca5dd8e6da7'
$Repo = $env:GITHUB_REPOSITORY
$Token = $env:GITHUB_TOKEN

if (-not $Repo -or -not $Token) {
    throw 'GITHUB_REPOSITORY and GITHUB_TOKEN are required.'
}

if ($Target -eq 'l4d') {
    $GameLabel = 'l4d1'
    $BinaryName = 'dosprotect_l4d1_mm.dll'
} else {
    $GameLabel = 'l4d2'
    $BinaryName = 'dosprotect_l4d2_mm.dll'
}

$ArtifactRoot = Join-Path $RepoRoot "artifacts\dosprotect-$Target-win32"
$DllPath = Join-Path $ArtifactRoot "addons\dosprotect\bin\$BinaryName"
if (-not (Test-Path $DllPath)) {
    throw "Compiled DLL not found: $DllPath"
}

$ZipName = "dosprotect-$GameLabel-$Version-win32.zip"
$ZipPath = Join-Path $RepoRoot $ZipName
Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $ArtifactRoot '*') -DestinationPath $ZipPath -CompressionLevel Optimal

$Headers = @{
    Authorization = "Bearer $Token"
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

$ApiBase = "https://api.github.com/repos/$Repo"
$Release = $null
try {
    $Release = Invoke-RestMethod -Method Get -Uri "$ApiBase/releases/tags/$Tag" -Headers $Headers
} catch {
    $StatusCode = $null
    if ($_.Exception.Response) {
        $StatusCode = [int]$_.Exception.Response.StatusCode
    }
    if ($StatusCode -ne 404) {
        throw
    }
}

if (-not $Release) {
    $Payload = @{
        tag_name = $Tag
        target_commitish = $ReleaseTarget
        name = "DoS Protect $Version"
        body = "Development build for Left 4 Dead 1 and Left 4 Dead 2. Preserves the regression-sensitive LEGACY-25 recvfrom mitigation. Built as Windows x86 against pinned HL2SDK/Metamod:Source revisions."
        draft = $false
        prerelease = $true
    } | ConvertTo-Json

    $Release = Invoke-RestMethod -Method Post -Uri "$ApiBase/releases" -Headers $Headers -ContentType 'application/json' -Body $Payload
}

function Publish-Asset {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ContentType
    )

    $Existing = @($Release.assets | Where-Object { $_.name -eq $Name })
    foreach ($Asset in $Existing) {
        Invoke-RestMethod -Method Delete -Uri "$ApiBase/releases/assets/$($Asset.id)" -Headers $Headers | Out-Null
    }

    $UploadUri = "https://uploads.github.com/repos/$Repo/releases/$($Release.id)/assets?name=$([uri]::EscapeDataString($Name))"
    Invoke-RestMethod -Method Post -Uri $UploadUri -Headers $Headers -ContentType $ContentType -InFile $Path | Out-Null
    Write-Host "Published release asset: $Name"
}

Publish-Asset -Path $DllPath -Name $BinaryName -ContentType 'application/octet-stream'
Publish-Asset -Path $ZipPath -Name $ZipName -ContentType 'application/zip'

Write-Host "Release: $($Release.html_url)"
