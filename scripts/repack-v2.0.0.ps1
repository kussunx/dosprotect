Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$version = '2.0.0'
$tag = 'v2.0.0'

Write-Host 'Rebuilding clean DoS Protect 2.0.0 packages...'

& "$PSScriptRoot\build.ps1" -Target all -Configuration Release
if ($LASTEXITCODE -ne 0) {
    throw 'Release build failed.'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repoRoot

$packages = @(
    @{
        Root = Join-Path $repoRoot 'artifacts\dosprotect-l4d-win32'
        Zip = Join-Path $repoRoot "dosprotect-$version-l4d1-win32.zip"
        Expected = @(
            'addons\dosprotect\bin\dosprotect_l4d1_mm.dll',
            'addons\metamod\dosprotect.vdf'
        )
    },
    @{
        Root = Join-Path $repoRoot 'artifacts\dosprotect-l4d2-win32'
        Zip = Join-Path $repoRoot "dosprotect-$version-l4d2-win32.zip"
        Expected = @(
            'addons\dosprotect\bin\dosprotect_l4d2_mm.dll',
            'addons\metamod\dosprotect.vdf'
        )
    }
)

foreach ($package in $packages) {
    $root = (Resolve-Path $package.Root).Path
    $actual = @(Get-ChildItem -Path $root -Recurse -File | ForEach-Object {
        $_.FullName.Substring($root.Length + 1)
    } | Sort-Object)
    $expected = @($package.Expected | Sort-Object)

    $diff = @(Compare-Object -ReferenceObject $expected -DifferenceObject $actual)
    if (($actual.Count -ne $expected.Count) -or $diff.Count -ne 0) {
        throw "Unexpected release package contents under $root. Actual: $($actual -join ', ')"
    }

    Write-Host "Validated clean artifact: $($actual -join ', ')"

    if (Test-Path $package.Zip) {
        Remove-Item $package.Zip -Force
    }
    Compress-Archive -Path (Join-Path $root '*') -DestinationPath $package.Zip -Force
}

$l4d1 = Join-Path $repoRoot "dosprotect-$version-l4d1-win32.zip"
$l4d2 = Join-Path $repoRoot "dosprotect-$version-l4d2-win32.zip"
$sums = Join-Path $repoRoot 'SHA256SUMS.txt'

$hash1 = (Get-FileHash $l4d1 -Algorithm SHA256).Hash.ToLowerInvariant()
$hash2 = (Get-FileHash $l4d2 -Algorithm SHA256).Hash.ToLowerInvariant()
@(
    "$hash1  dosprotect-$version-l4d1-win32.zip",
    "$hash2  dosprotect-$version-l4d2-win32.zip"
) | Set-Content -Path $sums -Encoding ascii

if (-not $env:GITHUB_TOKEN) {
    throw 'GITHUB_TOKEN is not available.'
}
if (-not $env:GITHUB_REPOSITORY) {
    throw 'GITHUB_REPOSITORY is not available.'
}

$headers = @{
    Authorization = "Bearer $env:GITHUB_TOKEN"
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

$release = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/$env:GITHUB_REPOSITORY/releases/tags/$tag" -Headers $headers

$assets = @(
    @{ Name = "dosprotect-$version-l4d1-win32.zip"; Path = $l4d1; ContentType = 'application/zip' },
    @{ Name = "dosprotect-$version-l4d2-win32.zip"; Path = $l4d2; ContentType = 'application/zip' },
    @{ Name = 'SHA256SUMS.txt'; Path = $sums; ContentType = 'text/plain' }
)

foreach ($existing in @($release.assets)) {
    if ($assets.Name -contains $existing.name) {
        Write-Host "Deleting old release asset: $($existing.name) ($($existing.id))"
        Invoke-RestMethod -Method Delete -Uri "https://api.github.com/repos/$env:GITHUB_REPOSITORY/releases/assets/$($existing.id)" -Headers $headers
    }
}

$uploadUrl = $release.upload_url -replace '\{\?name,label\}$', ''
foreach ($asset in $assets) {
    $encodedName = [uri]::EscapeDataString($asset.Name)
    $uri = "${uploadUrl}?name=$encodedName"
    Write-Host "Uploading clean release asset: $($asset.Name)"
    Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -InFile $asset.Path -ContentType $asset.ContentType | Out-Null
}

Write-Host 'Clean DoS Protect 2.0.0 release assets uploaded successfully.'
Write-Host "L4D1 ZIP SHA256: $hash1"
Write-Host "L4D2 ZIP SHA256: $hash2"
