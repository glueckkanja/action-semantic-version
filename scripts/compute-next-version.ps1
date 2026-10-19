$ErrorActionPreference = 'Stop'

$Prefix = $env:PREFIX
$CheckLastCommitOnly = $env:CHECK_LAST_COMMIT_ONLY -eq 'true'
$IsPrerelease = $env:IS_PRERELEASE -eq 'true'
$PrereleaseName = ($env:PRERELEASE_NAME ?? '').Trim()
$HasPrereleaseSuffix = -not [string]::IsNullOrWhiteSpace($PrereleaseName)

if ($Prefix) {
  $TagMatch = "$Prefix-v*"
  $PrefixWithDash = "$Prefix-"
} else {
  $TagMatch = "v*"
  $PrefixWithDash = ""
}

# Get all tags matching the pattern, sorted by version descending
$TagOutput = git tag -l "$TagMatch" --sort=-version:refname
$AllTags = @($TagOutput | Where-Object { $_ })

function Get-VersionFromTag {
  param([string]$Tag, [string]$PrefixWithDash)
  $StrippedTag = $Tag -replace "^$([regex]::Escape($PrefixWithDash))", ''
  return $StrippedTag -replace '^v', ''
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

# Determine which commits to check based on mode
$LogLimit = $CheckLastCommitOnly ? @('-1') : @()
$LogRange = $LastStableTag ? @("$LastStableTag..HEAD") : @()
$CommitSubjects = @(git log @LogLimit --pretty=%s @LogRange)

# Scan commits for the highest bump level: breaking change (2) > feature (1) > patch (0)
$ExclamationMarkPattern = '^\S*!:'
$BreakingChangePattern = '^BREAKING CHANGE:'
$FeaturePattern = '^feat(\([^)]*\))?:'

$HighestLevel = 0
$CommitSubject = ''

foreach ($Subject in $CommitSubjects) {
  if (-not $CommitSubject) {
    $CommitSubject = $Subject
  }

  if ($Subject -match $ExclamationMarkPattern -or $Subject -match $BreakingChangePattern) {
    $HighestLevel = 2
    $CommitSubject = $Subject
    break
  } elseif ($Subject -match $FeaturePattern -and $HighestLevel -lt 1) {
    $HighestLevel = 1
    $CommitSubject = $Subject
  }
}

if ($CommitSubjects.Count -eq 0) {
  $CommitSubject = 'No commits since last release'
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

if ($IsPrerelease -and $HasPrereleaseSuffix) {
  $EscapedName = [regex]::Escape($PrereleaseName)
  foreach ($Tag in $AllTags) {
    $Version = Get-VersionFromTag -Tag $Tag -PrefixWithDash $PrefixWithDash
    if ($Version -match "^(\d+\.\d+\.\d+)-${EscapedName}\.(\d+)$" -and $Matches[1] -eq $TargetBaseVersion) {
      $LastPrereleaseTag = $Tag
      $LastPrereleaseVersion = [int]$Matches[2]
      break
    }
  }
}

# Build the final version string and determine changelog base tag
if ($IsPrerelease -and $HasPrereleaseSuffix) {
  # Increment prerelease version
  $PrereleaseVersion = $LastPrereleaseVersion + 1
  $NewVersion = "$TargetBaseVersion-$PrereleaseName.$PrereleaseVersion"
  # For stable releases, always use the last stable tag
  $ChangelogBaseTag = $LastPrereleaseTag ? $LastPrereleaseTag : $LastStableTag
} else {
  $NewVersion = $TargetBaseVersion
  $ChangelogBaseTag = $LastStableTag
}

# When no prerelease suffix is provided, derive the predecessor
# from GitHub release metadata (the "latest" / "prerelease" flags) rather than
# from local tag ordering. With a suffix we keep name-neighbor matching.
if (-not $HasPrereleaseSuffix) {
  $NoSuffixTagPattern = '^v\d+\.\d+\.\d+$'

  try {
    if ($IsPrerelease) {
      # Prerelease without a suffix: the predecessor is the newest no-suffix release,
      # stable or prerelease. Releases are listed newest first, so page until one is found.
      $PredecessorRelease = $null
      $ReleasePage = 1

      do {
        $ReleasesJson = gh api "repos/$env:GITHUB_REPOSITORY/releases?per_page=100&page=$ReleasePage" 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $ReleasesJson) {
          Write-Host "::warning::GitHub API request for releases page $ReleasePage failed (exit code $LASTEXITCODE); stopping predecessor lookup."
          break
        }

        $PageReleases = @($ReleasesJson | ConvertFrom-Json)
        $PredecessorRelease = $PageReleases |
        Where-Object { -not $_.draft -and $_.tag_name -match $NoSuffixTagPattern } |
        Sort-Object -Property published_at -Descending |
        Select-Object -First 1

        $ReleasePage++
      } while (-not $PredecessorRelease -and $PageReleases.Count -eq 100)

      if ($PredecessorRelease) {
        $ChangelogBaseTag = $PredecessorRelease.tag_name
      } else {
        Write-Host 'GitHub API returned no matching releases for prerelease predecessor lookup; falling back to git-tag-derived predecessor.'
      }
    } else {
      # Stable release: use whatever GitHub currently flags as "latest".
      $LatestReleaseJson = gh api "repos/$env:GITHUB_REPOSITORY/releases/latest" 2>$null
      if ($LASTEXITCODE -eq 0 -and $LatestReleaseJson) {
        $LatestRelease = $LatestReleaseJson | ConvertFrom-Json
        if ($LatestRelease.tag_name -match $NoSuffixTagPattern) {
          $ChangelogBaseTag = $LatestRelease.tag_name
        }
      } else {
        Write-Host '::warning::GitHub API returned no "latest" release; falling back to git-tag-derived predecessor.'
      }
    }
  } catch {
    Write-Host "::warning::GitHub API predecessor lookup failed, falling back to git-tag-derived predecessor: $_"
  } finally {
    $global:LASTEXITCODE = 0
  }
}

$NewTag = "${PrefixWithDash}v${NewVersion}"

# Write outputs
"bump_type=$BumpType" >> $env:GITHUB_OUTPUT
"previous_tag=$LastStableTag" >> $env:GITHUB_OUTPUT
"previous_tag_for_changelog=$ChangelogBaseTag" >> $env:GITHUB_OUTPUT
"version=$NewVersion" >> $env:GITHUB_OUTPUT
"tag=$NewTag" >> $env:GITHUB_OUTPUT
"commit_subject=$CommitSubject" >> $env:GITHUB_OUTPUT

Write-Host "Determined $BumpType bump from '$CommitSubject' -> $NewTag"
Write-Host "Changelog will be generated from: $($ChangelogBaseTag ? $ChangelogBaseTag : 'initial commit')"
