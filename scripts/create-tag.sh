#!/usr/bin/env bash
set -eo pipefail

if git rev-parse -q --verify "refs/tags/${TAG_NAME}" >/dev/null; then
  echo "Tag ${TAG_NAME} already exists. Skipping creation."
  exit 0
fi

git tag "${TAG_NAME}" "${GITHUB_SHA}"
# Explicit auth required as credentials are not persisted in checkout-step
authorization_header="AUTHORIZATION: basic $(printf 'x-access-token:%s' "${GITHUB_TOKEN}" | base64 -w0)"
git -c http.extraheader="${authorization_header}" push origin "${TAG_NAME}"
echo "Pushed tag ${TAG_NAME}"
