#!/usr/bin/env bash
# Shared helpers for fork build/install scripts.

set -euo pipefail

fork_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir/.." && pwd
}

fork_log() {
  echo "[fork] $*"
}

fork_warn() {
  echo "[fork] WARNING: $*" >&2
}

fork_die() {
  echo "[fork] ERROR: $*" >&2
  exit 1
}

fork_check_node() {
  if ! command -v node >/dev/null 2>&1; then
    fork_die "node is not installed. Install Node.js >= 20.20.1 first."
  fi

  if [ -f .nvmrc ]; then
    local required current
    required="$(tr -d 'v' < .nvmrc)"
    current="$(node -v | tr -d 'v')"
    if [ "$required" != "$current" ]; then
      fork_warn "Node.js v$current does not match .nvmrc (v$required). Consider: nvm use"
    fi
  fi
}

fork_latest_vsix() {
  local build_dir="$1"
  ls -1t "$build_dir"/continue-*.vsix 2>/dev/null | head -1
}

fork_detect_windows_user() {
  if [ -n "${CONTINUE_WINDOWS_USER:-}" ]; then
    echo "$CONTINUE_WINDOWS_USER"
    return
  fi

  if [ -d /mnt/c/Users ]; then
    local user
    for user in /mnt/c/Users/*; do
      [ -d "$user" ] || continue
      case "$(basename "$user")" in
        Default|Default\ User|Public|All\ Users) continue ;;
      esac
      if [ -d "$user/.vscode-oss/extensions" ] || [ -d "$user/AppData/Local/Temp" ]; then
        basename "$user"
        return
      fi
    done
  fi

  echo ""
}

# Stage installer + VSIX on the Windows filesystem for powershell.exe -File (UNC/WSL paths hang).
fork_stage_for_windows_installer() {
  local ps_script="$1"
  local vsix_path="$2"
  local win_user staging_dir

  win_user="$(fork_detect_windows_user)"
  [ -n "$win_user" ] || fork_die "Cannot find Windows user. Set CONTINUE_WINDOWS_USER."

  staging_dir="/mnt/c/Users/$win_user/AppData/Local/Temp/continue-vsix-install"
  mkdir -p "$staging_dir"
  cp "$ps_script" "$staging_dir/install-vsix.ps1"
  cp "$vsix_path" "$staging_dir/$(basename "$vsix_path")"

  echo "$(wslpath -w "$staging_dir/install-vsix.ps1")"
  echo "$(wslpath -w "$staging_dir/$(basename "$vsix_path")")"
}

fork_copy_install_bundle() {
  local build_dir="$1"
  local vsix_path="$2"
  local bundle_dir="$build_dir/continue-install-bundle"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  rm -rf "$bundle_dir"
  mkdir -p "$bundle_dir"
  cp "$vsix_path" "$bundle_dir/"
  cp "$script_dir/install-vsix.ps1" "$bundle_dir/"
}
