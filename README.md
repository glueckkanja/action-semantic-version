# action-semver-version

This reusable action can be used to generate semantic version numbers for your releases in other repositories.

## Semantic Versioning workflow

Use the reusable semver action to compute the next semantic version, expose it as an output, and tag the current commit.

### Calling the workflow

```yaml
# actions.yml in a consumer repository
name: Release

on:
  push:
    branches:
      - main

permissions:
  contents: write

jobs:
  version:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    outputs:
      version: ${{ steps.version.outputs.version }}
      tag: ${{ steps.version.outputs.tag }}
      bump_type: ${{ steps.version.outputs.bump_type }}
      previous_tag: ${{ steps.version.outputs.previous_tag }}
      commit_subject: ${{ steps.version.outputs.commit_subject }}
      release_id: ${{ steps.version.outputs.release_id }}
    steps:
      - name: Generate semantic version
        id: version
        uses: glueckkanja/action-semver-version@SHA # v1.0.0
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          prefix: license-module # optional: prefix for tags like license-module-vX.Y.Z
          suppress_release: "false" # optional: set true to skip creating a GitHub release
          is_draft_release: "false" # optional: set true to create a draft GitHub release
          suppress_tag: "false" # optional: set true to skip both tag and release creation
          check_last_commit_only: "false" # optional: set true to only inspect the latest commit
          is_prerelease: "false" # optional: set true to generate a prerelease version
          prerelease_name: "" # optional: set a prerelease suffix name (for example 'rc', 'alpha', 'beta'); keep empty to create a prerelease without suffix
          asset_path: "" # optional: path to a file or directory to attach to the release as assets

  publish:
    runs-on: ubuntu-latest
    needs: version
    steps:
      - name: Show generated version
        run: |
          echo "Version:    ${{ needs.version.outputs.version }}"
          echo "Tag:        ${{ needs.version.outputs.tag }}"
          echo "Bump:       ${{ needs.version.outputs.bump_type }}"
          echo "Prev tag:   ${{ needs.version.outputs.previous_tag }}"
          echo "Commit:     ${{ needs.version.outputs.commit_subject }}"
          echo "Release ID: ${{ needs.version.outputs.release_id }}"
```

### Permissions

- `contents: write` — Required on the **caller's job**. Allows the action to create tags and releases. Pass `${{ secrets.GITHUB_TOKEN }}` via the `github_token` input.

### Inputs

- `github_token` _(string, required)_ – GitHub token with `contents: write` permission. Pass `${{ secrets.GITHUB_TOKEN }}`.
- `prefix` _(string, default: empty)_ – Optional prefix prepended to generated tags (for example `license-module-vX.Y.Z`).
- `suppress_release` _(boolean, default: false)_ – When `true`, skips creating a GitHub release while still creating tags (unless suppressed below).
- `is_draft_release` _(string `"true"/"false"`, default: `"false"`)_ – When `"true"`, creates the GitHub release as a draft.
- `suppress_tag` _(boolean, default: false)_ – When `true`, skips creating both the Git tag and the GitHub release.
- `check_last_commit_only` _(boolean, default: false)_ – When `true`, only the most recent commit is inspected to determine the bump type instead of all commits since the previous tag.
- `is_prerelease` _(boolean, default: false)_ – When `true`, generates a prerelease version (for example `1.2.3-rc.1`).
- `prerelease_name` _(string, default: "")_ – Name for the prerelease identifier (for example `rc`, `alpha`, `beta`). If set, the version includes a suffix (for example `1.8.2-rc.1`). If empty, the version remains plain semver (for example `1.8.2`) while still creating a prerelease release.
- `asset_path` _(string, default: empty)_ – Path to a file or directory to attach to the release as assets. When set, the release is created as a draft first and assets are uploaded before publication. If `is_draft_release` is `"true"`, the release remains a draft after assets are uploaded.

### Outputs

- `version` – The calculated semantic version (for example `1.2.3`).
- `tag` – The tag name that would be created (for example `v1.2.3` or `module-v1.2.3`).
- `bump_type` – The bump classification applied (`major`, `minor`, or `patch`).
- `previous_tag` – The most recent matching tag prior to this run, if any.
- `commit_subject` – The commit message subject that determined the bump decision.
- `release_id` – Numeric ID of the created GitHub release. Empty when release creation is suppressed via `suppress_release` or `suppress_tag`.

The run summary also includes a direct link to the created GitHub release for quick access.

### Bump rules

The action inspects commit messages and applies the following precedence:

- **MAJOR**: If any commit subject starts with `BREAKING CHANGE:` or its first word ends with `!:` (for example `feat!:`, `fix!:`, `chore!:`, `feat(scope)!:`).
- **MINOR**: If any commit subject starts with `feat:` or `feat(<scope>):`, case-insensitive.
- **PATCH**: Any other commit message.

If no existing tags matching `v*` are found, versioning starts from `0.0.0`.

Each run also publishes a Git tag matching the new version. By default tags look like `vX.Y.Z`, but you can provide a `prefix` input (for example `license-module`) to emit tags such as `license-module-vX.Y.Z`. When no `prefix` is set, the action creates a GitHub release with auto-generated release notes. When a `prefix` is set, the GitHub release is still created, but auto-generated release notes are skipped. If a tag or release for the computed version already exists, the action aborts with an error (an existing release may be immutable and unable to receive assets).

### Release notes predecessor

The tag used as the start point for auto-generated release notes depends on whether `prefix` and `prerelease_name` are set. This lookup only applies when `prefix` is empty, because prefixed releases do not generate release notes:

- **No `prefix` and no `prerelease_name`** — the predecessor is taken from GitHub's release metadata, so release notes compare against something of the same "level":
  - For a stable release (`is_prerelease: "false"`): the release currently flagged as **latest** on GitHub (via `GET /repos/{owner}/{repo}/releases/latest`).
  - For a prerelease (`is_prerelease: "true"`, no suffix name): the newest non-draft release (stable or prerelease) whose tag matches `v<major>.<minor>.<patch>`, ordered by publication date.
  - If the GitHub API returns no matching release (brand-new repo, nothing flagged yet, API error), the action falls back to the git-tag-based predecessor described below.
- **No `prefix` and a `prerelease_name` set** — name-neighbour matching from local tags: the newest prerelease tag with the same base version and suffix name is used, falling back to the newest matching stable tag.

The `previous_tag` output always reflects the newest matching stable tag from local git history, regardless of which mode is used for the release notes predecessor.

### Commit message hook

A PowerShell-based Git commit-msg hook is available at `git/hooks/enforceConventionalCommits/commit-msg.ps1` to enforce the [Conventional Commits](https://www.conventionalcommits.org/) standard locally before commits are created.

### Installation

#### Windows

1. Copy **both** the `commit-msg.ps1` and `commit-msg` to your repository's `.git/hooks` directory

#### Mac / Linux

1. Copy just the `commit-msg.ps1` to your repository's `.git/hooks` directory
1. Remove the .ps1 ending (so the final filename inside the `.git/hooks` directory is `commit-msg`)
1. Add execution permissions:

```bash
chmod +x .git/hooks/commit-msg
```

### What it validates

The hook validates that commit messages follow the Conventional Commits format:

```
<type>[optional scope][optional !]: <description>

[optional body]

[optional footer(s)]
```

#### Valid types

| Type       | Description                                               |
| ---------- | --------------------------------------------------------- |
| `feat`     | A new feature                                             |
| `fix`      | A bug fix                                                 |
| `docs`     | Documentation only changes                                |
| `style`    | Code style changes (formatting, missing semicolons, etc.) |
| `refactor` | Code change that neither fixes a bug nor adds a feature   |
| `perf`     | Performance improvements                                  |
| `test`     | Adding or correcting tests                                |
| `build`    | Changes to build system or dependencies                   |
| `ci`       | Changes to CI configuration files and scripts             |
| `chore`    | Other changes that don't modify src or test files         |
| `revert`   | Reverts a previous commit                                 |
| `deps`     | Dependency updates                                        |

#### Examples

```
feat: add user authentication
fix(api): resolve null reference exception
feat(auth)!: change login flow (breaking change)
docs: update README with setup instructions
```

### Warnings

The hook will display warnings (but not reject the commit) for:

- **Long subject lines**: Subject lines longer than 72 characters
- **Missing breaking change documentation**: When `!` is used but no `BREAKING CHANGE:` section is present in the body
