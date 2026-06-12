#!/usr/bin/env bash
# Install a Continue VSIX into VSCodium by delegating to install-vsix.ps1 on Windows.
#
# Build in WSL/Linux, install on Windows:
#   ./scripts/fork-build.sh
#   ./scripts/fork-install.sh extensions/vscode/build/continue-1.3.40.vsix
#
# Or copy the portable bundle to Windows and run PowerShell there:
#   .\install-vsix.ps1
#
# Usage:
#   ./scripts/fork-install.sh [path/to/continue-X.Y.Z.vsix]
#   ./scripts/fork-install.sh --dry-run [path]
#
# With no arguments, installs the newest VSIX from extensions/vscode/build/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/fork-common.sh
source "$SCRIPT_DIR/fork-common.sh"

VSIX_PATH=""
DRY_RUN=false
PS_SCRIPT="$SCRIPT_DIR/install-vsix.ps1"

while [ $# -gt 0 ]; do
  case "$1" in
    --vsix)
      shift
      VSIX_PATH="${1:-}"
      [ -n "$VSIX_PATH" ] || fork_die "--vsix requires a path"
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    --*)
      fork_die "Unknown argument: $1"
      ;;
    *)
      [ -z "$VSIX_PATH" ] || fork_die "Unexpected extra argument: $1"
      VSIX_PATH="$1"
      ;;
  esac
  shift
done

if [ -z "$VSIX_PATH" ]; then
  REPO_ROOT="$(fork_repo_root)"
  VSIX_PATH="$(fork_latest_vsix "$REPO_ROOT/extensions/vscode/build")"
fi

[ -n "$VSIX_PATH" ] || fork_die "No VSIX found. Run ./scripts/fork-build.sh or pass a path."
[[ "$VSIX_PATH" = /* ]] || VSIX_PATH="$(cd "$(dirname "$VSIX_PATH")" && pwd)/$(basename "$VSIX_PATH")"
[ -f "$VSIX_PATH" ] || fork_die "VSIX not found: $VSIX_PATH"
[ -f "$PS_SCRIPT" ] || fork_die "Missing installer: $PS_SCRIPT"

if ! command -v powershell.exe >/dev/null 2>&1; then
  fork_die "powershell.exe not found. Copy the VSIX + install-vsix.ps1 to Windows and run:
  .\\install-vsix.ps1 -VsixPath 'C:\\path\\to\\continue.vsix'"
fi

mapfile -t STAGED_PATHS < <(fork_stage_for_windows_installer "$PS_SCRIPT" "$VSIX_PATH")
WIN_PS_SCRIPT="${STAGED_PATHS[0]}"
WIN_VSIX_PATH="${STAGED_PATHS[1]}"

PS_ARGS=(-NoProfile -ExecutionPolicy Bypass -File "$WIN_PS_SCRIPT" -VsixPath "$WIN_VSIX_PATH")
if [ "$DRY_RUN" = true ]; then
  PS_ARGS+=(-DryRun)
fi

fork_log "Delegating to PowerShell installer..."
powershell.exe "${PS_ARGS[@]}"
