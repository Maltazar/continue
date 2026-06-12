#!/usr/bin/env bash
# One-time local dev environment setup for this Continue fork.
# Does NOT build the VSIX or install into an editor.
#
# Usage:
#   ./scripts/fork-setup.sh
#
# Workflow:
#   ./scripts/fork-setup.sh                 # once
#   ./scripts/fork-build.sh                 # produces VSIX + portable install bundle
#   ./scripts/fork-install.sh path/to.vsix  # WSL wrapper; or run install-vsix.ps1 on Windows

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/fork-common.sh
source "$SCRIPT_DIR/fork-common.sh"

REPO_ROOT="$(fork_repo_root)"
cd "$REPO_ROOT"

fork_check_node
fork_log "Setting up dev environment in $REPO_ROOT"

fork_log "Installing root dependencies..."
npm install

fork_log "Building internal packages..."
node ./scripts/build-packages.js

fork_log "Installing core..."
pushd core >/dev/null
export PUPPETEER_SKIP_DOWNLOAD=true
npm install
npm link
popd >/dev/null

fork_log "Installing and building GUI..."
pushd gui >/dev/null
npm install
npm link @continuedev/core
NODE_OPTIONS="--max-old-space-size=4096" npm run build
popd >/dev/null

fork_log "Installing VS Code extension dependencies..."
pushd extensions/vscode >/dev/null
npm install
npm link @continuedev/core
popd >/dev/null

fork_log "Setup complete."
fork_log "Next: ./scripts/fork-build.sh"
