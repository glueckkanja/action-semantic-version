#!/usr/bin/env bash
set -eo pipefail

prefix="${PREFIX:-}"
check_last_commit_only="${CHECK_LAST_COMMIT_ONLY,,}"
is_prerelease="${IS_PRERELEASE,,}"
prerelease_name="${PRERELEASE_NAME:-prerelease}"

if [[ -n "$prefix" ]]; then
  tag_match="${prefix}-v*"
  prefix_with_dash="${prefix}-"
else
  tag_match='v*'
  prefix_with_dash=""
fi

# Get all tags matching the pattern
if tag_output=$(git tag -l "$tag_match" --sort=-version:refname) && [[ -n "$tag_output" ]]; then
  mapfile -t all_tags <<< "$tag_output"
else
  all_tags=()
fi

# Find the last stable version (no prerelease identifier)
last_stable_tag=""
last_stable_version="0.0.0"
for tag in "${all_tags[@]}"; do
  stripped_tag="${tag#${prefix_with_dash}}"
  version="${stripped_tag#v}"
  # Check if this is a stable version (no dash in version)
  if [[ ! "$version" =~ - ]]; then
    last_stable_tag="$tag"
    last_stable_version="$version"
    break
  fi
done

# Parse the stable version for bump calculation
IFS='.' read -r major minor patch <<< "$last_stable_version"
major=${major:-0}
minor=${minor:-0}
patch=${patch:-0}

# Determine which commits to check based on mode
major_pattern='^[^[:space:]]*!:'
minor_pattern='^feat(\([^)]*\))?:'

if [[ "$check_last_commit_only" == "true" ]]; then
  if [[ -n "$last_stable_tag" ]]; then
    mapfile -t commit_subjects < <(git log -1 --pretty=%s "${last_stable_tag}..HEAD")
  else
    mapfile -t commit_subjects < <(git log -1 --pretty=%s)
  fi
else
  if [[ -n "$last_stable_tag" ]]; then
    mapfile -t commit_subjects < <(git log "${last_stable_tag}..HEAD" --pretty=%s)
  else
    mapfile -t commit_subjects < <(git log --pretty=%s)
  fi
fi

highest_level=0
commit_subject=""

for subject in "${commit_subjects[@]}"; do
  [[ -z "$commit_subject" ]] && commit_subject="$subject"

  subject_lower=$(printf '%s' "$subject" | tr '[:upper:]' '[:lower:]')

  if [[ $subject =~ $major_pattern ]]; then
    highest_level=2
    commit_subject="$subject"
    break
  elif [[ $subject_lower =~ $minor_pattern ]]; then
    if (( highest_level < 1 )); then
      highest_level=1
      commit_subject="$subject"
    fi
  fi
done

if [[ ${#commit_subjects[@]} -eq 0 ]]; then
  commit_subject="No commits since last release"
  highest_level=0
fi

# Calculate the new stable version based on bump type
case $highest_level in
  2)
    major=$((major + 1))
    minor=0
    patch=0
    bump_type="major"
    ;;
  1)
    minor=$((minor + 1))
    patch=0
    bump_type="minor"
    ;;
  *)
    patch=$((patch + 1))
    bump_type="patch"
    ;;
esac

target_base_version="$major.$minor.$patch"

# Find the last prerelease for this target base version and name
last_prerelease_tag=""
last_prerelease_version="0"
if [[ "$is_prerelease" == "true" ]]; then
  escaped_prerelease_name=$(printf '%s' "$prerelease_name" | sed 's/[].[*^$()+?{|\\]/\\&/g')
  for tag in "${all_tags[@]}"; do
    stripped_tag="${tag#${prefix_with_dash}}"
    version="${stripped_tag#v}"
    if [[ "$version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-${escaped_prerelease_name}\.([0-9]+)$ ]]; then
      base_version="${BASH_REMATCH[1]}"
      prerelease_number="${BASH_REMATCH[2]}"
      if [[ "$base_version" == "$target_base_version" ]]; then
        last_prerelease_tag="$tag"
        last_prerelease_version="$prerelease_number"
        break
      fi
    fi
  done
fi

# Build the final version string and determine changelog base tag
if [[ "$is_prerelease" == "true" ]]; then
  # Increment prerelease version
  prerelease_version=$((last_prerelease_version + 1))
  new_version="$major.$minor.$patch-${prerelease_name}.${prerelease_version}"
  # For prereleases, compare against the previous prerelease for this base version if present, otherwise last stable
  if [[ -n "$last_prerelease_tag" ]]; then
    changelog_base_tag="$last_prerelease_tag"
  else
    changelog_base_tag="$last_stable_tag"
  fi
else
  new_version="$major.$minor.$patch"
  # For stable releases, always use the last stable tag
  changelog_base_tag="$last_stable_tag"
fi

new_tag="${prefix_with_dash}v${new_version}"

printf 'bump-type=%s\n' "$bump_type" >> "$GITHUB_OUTPUT"
printf 'previous-tag=%s\n' "$last_stable_tag" >> "$GITHUB_OUTPUT"
printf 'previous-tag-for-changelog=%s\n' "$changelog_base_tag" >> "$GITHUB_OUTPUT"
printf 'version=%s\n' "$new_version" >> "$GITHUB_OUTPUT"
printf 'tag=%s\n' "$new_tag" >> "$GITHUB_OUTPUT"
printf 'commit-subject=%s\n' "$commit_subject" >> "$GITHUB_OUTPUT"

echo "Determined $bump_type bump from '$commit_subject' -> $new_tag"
echo "Changelog will be generated from: ${changelog_base_tag:-initial commit}"
