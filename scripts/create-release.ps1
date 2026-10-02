#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

$TagName = $env:TAG_NAME
$GithubSha = $env:GITHUB_SHA
$ChangelogBaseTag = $env:CHANGELOG_BASE_TAG
$IsPrerelease = ($env:IS_PRERELEASE ?? '').ToLowerInvariant()

$ExistingReleaseId = & gh release view $TagName --json databaseId --jq '.databaseId' 2>$null
if ($ExistingReleaseId) {
    throw "Release $TagName already exists."
}

# Build the release command with conditional notes-start-tag
$ReleaseArgs = @(
    $TagName
    '--title', $TagName
    '--target', $GithubSha
    '--generate-notes'
)

if ($IsPrerelease -eq 'true') {
    # Add prerelease flag if needed
    $ReleaseArgs += '--prerelease'
}

if ($ChangelogBaseTag) {
    # Add notes-start-tag if there's a previous tag for changelog
    $ReleaseArgs += @('--notes-start-tag', $ChangelogBaseTag)
    Write-Output "Generating release notes from $ChangelogBaseTag to $TagName"
}
else {
    Write-Output "Generating release notes from initial commit to $TagName"
}

& gh release create @ReleaseArgs
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create release $TagName"
}

$ReleaseId = & gh release view $TagName --json databaseId --jq '.databaseId'
if ($LASTEXITCODE -ne 0 -or -not $ReleaseId) {
    throw "Failed to resolve release id after creation"
}
Write-Output "Created release $TagName with id $ReleaseId"

Add-Content -Path $env:GITHUB_OUTPUT -Value "release_id=$ReleaseId"
