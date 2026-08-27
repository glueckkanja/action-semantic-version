#!/usr/bin/env bash
set -eo pipefail

previous="${PREVIOUS_TAG:-none}"
commit="${COMMIT_SUBJECT:-No commits since last release}"

{
  echo "### Semantic version summary"
  echo ""
  echo "- Version: \`${VERSION}\`"
  echo "- Tag: \`${TAG}\`"
  echo "- Bump type: \`${BUMP_TYPE}\`"
  echo "- Previous tag: \`${previous}\`"
  echo "- Commit: ${commit}"
} >> "$GITHUB_STEP_SUMMARY"
