$ErrorActionPreference = 'Stop'

$version = '2.0.0'
$tag = "v$version"

Write-Host "Publishing DoS Protect $version..."

& "$PSScriptRoot\verify-mitigation.ps1"
& "$PSScriptRoot\build.ps1" -Target all -Configuration Release

$l4d1 = "dosprotect-$version-l4d1-win32.zip"
$l4d2 = "dosprotect-$version-l4d2-win32.zip"

Compress-Archive -Path .\artifacts\dosprotect-l4d-win32\* -DestinationPath $l4d1 -Force
Compress-Archive -Path .\artifacts\dosprotect-l4d2-win32\* -DestinationPath $l4d2 -Force

$hash1 = (Get-FileHash $l4d1 -Algorithm SHA256).Hash
$hash2 = (Get-FileHash $l4d2 -Algorithm SHA256).Hash
@(
    "$hash1  $l4d1"
    "$hash2  $l4d2"
) | Set-Content -Path SHA256SUMS.txt -Encoding ascii

$headers = @{
    Authorization = "Bearer $env:GITHUB_TOKEN"
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

$release = $null
try {
    $release = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/$env:GITHUB_REPOSITORY/releases/tags/$tag" -Headers $headers
    Write-Host "Release $tag already exists; completing any missing assets."
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -ne 404) { throw }
}

if (-not $release) {
    git fetch --tags --force
    $tagExists = [bool](git tag -l $tag)

    if (-not $tagExists) {
        git config user.name 'github-actions[bot]'
        git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
        git tag -a $tag -m "DoS Protect $version"
        git push origin $tag
        if ($LASTEXITCODE -ne 0) { throw "Could not push tag $tag." }
    }

    $changelog = Get-Content .\CHANGELOG.md -Raw
    $escaped = [regex]::Escape($version)
    $match = [regex]::Match($changelog, "(?ms)^##\s+$escaped\s*\r?\n(.*?)(?=^##\s+|\z)")
    if (-not $match.Success) { throw "No changelog section found for $version." }

    $deps = Import-PowerShellDataFile .\build\dependencies.psd1
    $notes = "Built and tested with Metamod:Source $($deps.MetamodSource.Ref) (commit $($deps.MetamodSource.Commit)).`r`n`r`n" + $match.Groups[1].Value.Trim()

    $payload = @{
        tag_name = $tag
        target_commitish = $env:GITHUB_SHA
        name = "DoS Protect $version"
        body = $notes
        draft = $false
        prerelease = $false
    } | ConvertTo-Json

    $release = Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$env:GITHUB_REPOSITORY/releases" -Headers $headers -ContentType 'application/json' -Body $payload
}

$uploadUrl = $release.upload_url -replace '\{\?name,label\}$', ''
$existingAssets = @($release.assets | ForEach-Object { $_.name })

foreach ($asset in @($l4d1, $l4d2, 'SHA256SUMS.txt')) {
    $fileName = [IO.Path]::GetFileName($asset)
    if ($existingAssets -contains $fileName) {
        Write-Host "Asset $fileName already exists; skipping."
        continue
    }

    $name = [uri]::EscapeDataString($fileName)
    $contentType = if ($asset.EndsWith('.zip')) { 'application/zip' } else { 'text/plain' }
    Invoke-RestMethod -Method Post -Uri "${uploadUrl}?name=$name" -Headers $headers -InFile $asset -ContentType $contentType | Out-Null
    Write-Host "Uploaded $fileName."
}

Write-Host "DoS Protect $version release is complete."
Write-Host "L4D1 package SHA256: $hash1"
Write-Host "L4D2 package SHA256: $hash2"
