#!/usr/bin/env bash
# Build a VSIX and publish it to GitHub Releases (GitHub REST API; no gh CLI).
#
# Usage:
#   GITHUB_TOKEN=ghp_... ./scripts/fork-publish.sh              # build + publish
#   ./scripts/fork-publish.sh --skip-gui                        # or set GITHUB_TOKEN in .env
#   ./scripts/fork-publish.sh --no-build                        # publish newest VSIX only
#   ./scripts/fork-publish.sh --no-bump                         # build without version bump
#
# Requires: curl, GITHUB_TOKEN with 'repo' scope (repo-root .env or environment)
#
# Environment:
#   GITHUB_TOKEN                           # required; read from .env or environment
#   FORK_GITHUB_REPO=Maltazar/continue     # default: parsed from git origin
#   SKIP_INSTALLS=true                     # passed through to fork-build.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/fork-common.sh
source "$SCRIPT_DIR/fork-common.sh"

RUN_BUILD=true
BUILD_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --no-build)
      RUN_BUILD=false
      ;;
    --skip-gui|--no-bump|--setup)
      BUILD_ARGS+=("$1")
      ;;
    -h|--help)
      sed -n '2,15p' "$0"
      exit 0
      ;;
    *)
      fork_die "Unknown argument: $1"
      ;;
  esac
  shift
done

REPO_ROOT="$(fork_repo_root)"
cd "$REPO_ROOT"

if ! command -v curl >/dev/null 2>&1; then
  fork_die "curl is required."
fi

# Fail early if token is missing.
fork_github_token >/dev/null

if [ "$RUN_BUILD" = true ]; then
  fork_log "Building VSIX..."
  "$SCRIPT_DIR/fork-build.sh" "${BUILD_ARGS[@]}"
else
  fork_log "Skipping build (--no-build)"
fi

VSIX_PATH="$(fork_latest_vsix "$REPO_ROOT/extensions/vscode/build")"
[ -n "$VSIX_PATH" ] || fork_die "No VSIX found in extensions/vscode/build. Run without --no-build first."

VERSION="$(fork_read_extension_version "$REPO_ROOT")"
REPO="$(fork_github_repo "$REPO_ROOT")"
TAG="$(fork_release_tag "$VERSION")"
VSIX_NAME="$(basename "$VSIX_PATH")"

if [ "$VSIX_NAME" != "continue-${VERSION}.vsix" ]; then
  fork_warn "VSIX filename ($VSIX_NAME) does not match package.json version ($VERSION)"
fi

if fork_github_release_exists "$REPO" "$TAG"; then
  fork_die "Release $TAG already exists on $REPO. Bump the version and rebuild."
fi

NOTES="$(cat <<EOF
Continue fork VSIX **${VERSION}** for VSCodium on Windows (\`win32-x64\`).

## Install

Download \`install-vsix.ps1\` from this release, then:

\`\`\`powershell
.\\install-vsix.ps1 -GitHubRepo ${REPO} -Version ${VERSION}
\`\`\`

Or install the latest release:

\`\`\`powershell
.\\install-vsix.ps1 -GitHubRepo ${REPO}
\`\`\`

Built from [\`${REPO}\`](https://github.com/${REPO}). See FORK.md in the repo for fork-specific behavior.
EOF
)"

fork_log "Publishing $VSIX_NAME to https://github.com/${REPO}/releases/tag/${TAG}"

RELEASE_ID="$(fork_github_release_create "$REPO" "$TAG" "Continue VSIX ${VERSION}" "$NOTES")"
fork_log "Created release $TAG (id: $RELEASE_ID)"

fork_log "Uploading $VSIX_NAME..."
fork_github_release_upload "$REPO" "$RELEASE_ID" "$VSIX_PATH" "$VSIX_NAME"

fork_log "Uploading install-vsix.ps1..."
fork_github_release_upload "$REPO" "$RELEASE_ID" "$SCRIPT_DIR/install-vsix.ps1" "install-vsix.ps1"

fork_log "Published: https://github.com/${REPO}/releases/tag/${TAG}"
fork_log ""
fork_log "Others can install with:"
fork_log "  .\\install-vsix.ps1 -GitHubRepo ${REPO} -Version ${VERSION}"
