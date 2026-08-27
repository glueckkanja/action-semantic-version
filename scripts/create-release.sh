#!/usr/bin/env bash
set -eo pipefail

if gh release view "${TAG_NAME}" >/dev/null 2>&1; then
  echo "Release ${TAG_NAME} already exists. Skipping creation."
  exit 0
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
echo "Created release ${TAG_NAME}"
