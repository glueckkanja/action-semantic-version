#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

$Prefix = $env:PREFIX ?? ''
$CheckLastCommitOnly = ($env:CHECK_LAST_COMMIT_ONLY ?? '').ToLowerInvariant()
$IsPrerelease = ($env:IS_PRERELEASE ?? '').ToLowerInvariant()
$PrereleaseName = $env:PRERELEASE_NAME ? $env:PRERELEASE_NAME : 'prerelease'

if ($Prefix) {
    $TagMatch = "$Prefix-v*"
    $PrefixWithDash = "$Prefix-"
} else {
    $TagMatch = 'v*'
    $PrefixWithDash = ''
}

$TagOutput = & git tag -l $TagMatch --sort=-version:refname
$AllTags = @()
if ($TagOutput) {
    $AllTags = @($TagOutput | Where-Object { $_ })
}

# Get all tags matching the pattern
function Get-VersionFromTag {
    param([string]$Tag, [string]$PrefixWithDash)
    $Stripped = if ($PrefixWithDash -and $Tag.StartsWith($PrefixWithDash)) {
        $Tag.Substring($PrefixWithDash.Length)
    } else {
        $Tag
    }
    if ($Stripped.StartsWith('v')) { $Stripped.Substring(1) } else { $Stripped }
}

# Find the last stable version (no prerelease identifier)
$LastStableTag = ''
$LastStableVersion = '0.0.0'
foreach ($Tag in $AllTags) {
    $Version = Get-VersionFromTag -Tag $Tag -PrefixWithDash $PrefixWithDash
    if ($Version -notmatch '-') {
        $LastStableTag = $Tag
        $LastStableVersion = $Version
        break
    }
}

# Parse the stable version for bump calculation
$VersionParts = $LastStableVersion -split '\.'
$Major = ($VersionParts.Count -ge 1 -and $VersionParts[0]) ? [int]$VersionParts[0] : 0
$Minor = ($VersionParts.Count -ge 2 -and $VersionParts[1]) ? [int]$VersionParts[1] : 0
$Patch = ($VersionParts.Count -ge 3 -and $VersionParts[2]) ? [int]$VersionParts[2] : 0

$MajorPattern = '^\S*!:'
$MinorPattern = '^feat(\([^)]*\))?:'

if ($CheckLastCommitOnly -eq 'true') {
    if ($LastStableTag) {
        $CommitSubjects = @(& git log -1 --pretty=%s "$LastStableTag..HEAD")
    } else {
        $CommitSubjects = @(& git log -1 --pretty=%s)
    }
} else {
    if ($LastStableTag) {
        $CommitSubjects = @(& git log "$LastStableTag..HEAD" --pretty=%s)
    } else {
        $CommitSubjects = @(& git log --pretty=%s)
    }
}

$CommitSubjects = @($CommitSubjects | Where-Object { $null -ne $_ -and $_ -ne '' })

$HighestLevel = 0
$CommitSubject = ''

foreach ($Subject in $CommitSubjects) {
    if (-not $CommitSubject) {
        $CommitSubject = $Subject
    }
    if ($Subject -match $MajorPattern) {
        $HighestLevel = 2
        $CommitSubject = $Subject
        break
    } elseif ($Subject -match $MinorPattern) {
        if ($HighestLevel -lt 1) {
            $HighestLevel = 1
            $CommitSubject = $Subject
        }
    }
}

if ($CommitSubjects.Count -eq 0) {
    $CommitSubject = 'No commits since last release'
    $HighestLevel = 0
}

# Calculate the new stable version based on bump type
switch ($HighestLevel) {
    2 {
        $Major += 1
        $Minor = 0
        $Patch = 0
        $BumpType = 'major'
    }
    1 {
        $Minor += 1
        $Patch = 0
        $BumpType = 'minor'
    }
    default {
        $Patch += 1
        $BumpType = 'patch'
    }
}

$TargetBaseVersion = "$Major.$Minor.$Patch"

# Find the last prerelease for this target base version and name
$LastPrereleaseTag = ''
$LastPrereleaseVersion = 0
if ($IsPrerelease -eq 'true') {
    $EscapedPrereleaseName = [regex]::Escape($PrereleaseName)
    $PrereleasePattern = "^(\d+\.\d+\.\d+)-$EscapedPrereleaseName\.(\d+)$"
    foreach ($Tag in $AllTags) {
        $Version = Get-VersionFromTag -Tag $Tag -PrefixWithDash $PrefixWithDash
        if ($Version -cmatch $PrereleasePattern) {
            $BaseVersion = $Matches[1]
            $PrereleaseNumber = [int]$Matches[2]
            if ($BaseVersion -eq $TargetBaseVersion) {
                $LastPrereleaseTag = $Tag
                $LastPrereleaseVersion = $PrereleaseNumber
                break
            }
        }
    }
}

# Build the final version string and determine changelog base tag
if ($IsPrerelease -eq 'true') {
    # Increment prerelease version
    $PrereleaseVersion = $LastPrereleaseVersion + 1
    $NewVersion = "$Major.$Minor.$Patch-$PrereleaseName.$PrereleaseVersion"
    # For prereleases, compare against the previous prerelease for this base version if present, otherwise last stable
    $ChangelogBaseTag = $LastPrereleaseTag ? $LastPrereleaseTag : $LastStableTag
} else {
    $NewVersion = "$Major.$Minor.$Patch"
    # For stable releases, always use the last stable tag
    $ChangelogBaseTag = $LastStableTag
}

$NewTag = "${PrefixWithDash}v${NewVersion}"

$OutputLines = @(
    "bump_type=$BumpType"
    "previous_tag=$LastStableTag"
    "previous_tag_for_changelog=$ChangelogBaseTag"
    "version=$NewVersion"
    "tag=$NewTag"
    "commit_subject=$CommitSubject"
)
Add-Content -Path $env:GITHUB_OUTPUT -Value $OutputLines

Write-Output "Determined $BumpType bump from '$CommitSubject' -> $NewTag"
$ChangelogDisplay = $ChangelogBaseTag ? $ChangelogBaseTag : 'initial commit'
Write-Output "Changelog will be generated from: $ChangelogDisplay"
