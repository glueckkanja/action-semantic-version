#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

$Previous = $env:PREVIOUS_TAG ? $env:PREVIOUS_TAG : 'none'
$Commit = $env:COMMIT_SUBJECT ? $env:COMMIT_SUBJECT : 'No commits since last release'
$ReleaseId = $env:RELEASE_ID ? $env:RELEASE_ID : 'none'

$Lines = @(
    '### Semantic version summary'
    ''
    "- Version: ``$env:VERSION``"
    "- Tag: ``$env:TAG``"
    "- Bump type: ``$env:BUMP_TYPE``"
    "- Previous tag: ``$Previous``"
    "- Commit: $Commit"
    "- Release ID: ``$ReleaseId``"
)

Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $Lines
