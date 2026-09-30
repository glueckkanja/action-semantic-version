#!/usr/bin/env bash
set -eo pipefail

release_id=""
existing_release_id=$(gh release view "${TAG_NAME}" --json databaseId --jq '.databaseId' 2>/dev/null) || true
if [[ -n "$existing_release_id" ]]; then
  echo "Release ${TAG_NAME} already exists." >&2
  exit 1
fi

is_prerelease="${IS_PRERELEASE,,}"
# Build the release command with conditional notes-start-tag
release_args=(
  "${TAG_NAME}"
  --title "${TAG_NAME}"
  --target "${GITHUB_SHA}"
  --generate-notes
)

if [[ "$is_prerelease" == "true" ]]; then
  # Add prerelease flag if needed
  release_args+=(--prerelease)
fi

if [[ -n "$CHANGELOG_BASE_TAG" ]]; then
# Add notes-start-tag if there's a previous tag for changelog
  release_args+=(--notes-start-tag "$CHANGELOG_BASE_TAG")
  echo "Generating release notes from ${CHANGELOG_BASE_TAG} to ${TAG_NAME}"
else
  echo "Generating release notes from initial commit to ${TAG_NAME}"
fi

gh release create "${release_args[@]}"

release_id=$(gh release view "${TAG_NAME}" --json databaseId --jq '.databaseId')
if [[ -z "$release_id" ]]; then
  echo "Failed to resolve release id after creation" >&2
  exit 1
fi
echo "Created release ${TAG_NAME} with id ${release_id}"

echo "release_id=${release_id}" >> "$GITHUB_OUTPUT"
