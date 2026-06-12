#!/usr/bin/env bash
# Build a VSIX for this Continue fork.
#
# Usage:
#   ./scripts/fork-build.sh              # incremental build (defaults to win32-x64 for VSCodium on Windows)
#   ./scripts/fork-build.sh --setup      # run fork-setup.sh first if needed
#   ./scripts/fork-build.sh --skip-gui   # skip gui rebuild (faster, core/vscode only)
#
# Environment:
#   CONTINUE_BUILD_TARGET=win32-x64      # default; override for other platforms
#   SKIP_INSTALLS=true                   # skip npm reinstalls in prepackage (sqlite still downloaded when cross-compiling)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/fork-common.sh
source "$SCRIPT_DIR/fork-common.sh"

RUN_SETUP=false
SKIP_GUI=false

while [ $# -gt 0 ]; do
  case "$1" in
    --setup)
      RUN_SETUP=true
      ;;
    --skip-gui)
      SKIP_GUI=true
      ;;
    -h|--help)
      sed -n '2,13p' "$0"
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

fork_check_node

needs_setup=false
if [ ! -d core/node_modules ] || [ ! -d gui/node_modules ] || [ ! -d extensions/vscode/node_modules ]; then
  needs_setup=true
fi

if [ "$RUN_SETUP" = true ] || [ "$needs_setup" = true ]; then
  if [ "$needs_setup" = true ]; then
    fork_log "Dependencies missing; running setup..."
  else
    fork_log "Running setup (--setup)..."
  fi
  "$SCRIPT_DIR/fork-setup.sh"
fi

if [ "$SKIP_GUI" = false ]; then
  fork_log "Building GUI..."
  pushd gui >/dev/null
  NODE_OPTIONS="--max-old-space-size=4096" npm run build
  popd >/dev/null
else
  fork_warn "Skipping GUI build (--skip-gui)"
  [ -d gui/dist ] || fork_die "gui/dist is missing. Run without --skip-gui first."
fi

BUILD_TARGET="${CONTINUE_BUILD_TARGET:-win32-x64}"
export CONTINUE_BUILD_TARGET="$BUILD_TARGET"

fork_log "Packaging VS Code extension for $BUILD_TARGET..."
pushd extensions/vscode >/dev/null
npm run package
popd >/dev/null

# The repo's top-level `binary/` package is NOT required for the VS Code extension.
# The extension runs core in-process and bundles native deps (sqlite, onnx, lancedb)
# via prepackage into extensions/vscode/bin and extensions/vscode/out.

VSIX_PATH="$(fork_latest_vsix "$REPO_ROOT/extensions/vscode/build")"
[ -n "$VSIX_PATH" ] || fork_die "No VSIX produced in extensions/vscode/build"

fork_copy_install_bundle "$REPO_ROOT/extensions/vscode/build" "$VSIX_PATH"
BUNDLE_DIR="$REPO_ROOT/extensions/vscode/build/continue-install-bundle"

fork_log "Build complete: $VSIX_PATH (target: $BUILD_TARGET)"
fork_log ""
fork_log "Install options:"
fork_log "  1. Windows:    copy $BUNDLE_DIR to Windows, then: .\\install-vsix.ps1"
fork_log "  2. From WSL:    ./scripts/fork-install.sh $VSIX_PATH"
fork_log "  3. Manual:      VSCodium -> Extensions -> ... -> Install from VSIX..."
