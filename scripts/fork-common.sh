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

fork_read_extension_version() {
  local repo_root="$1"
  node -p "require('$repo_root/extensions/vscode/package.json').version"
}

fork_github_repo() {
  local repo_root="$1"
  if [ -n "${FORK_GITHUB_REPO:-}" ]; then
    echo "$FORK_GITHUB_REPO"
    return
  fi

  local url
  url="$(git -C "$repo_root" remote get-url origin 2>/dev/null)" || fork_die "No git origin remote. Set FORK_GITHUB_REPO."

  if [[ "$url" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  else
    fork_die "Could not parse GitHub repo from origin: $url"
  fi
}

fork_release_tag() {
  echo "continue-v$1"
}

# Load repo-root .env (gitignored). Does not override variables already set in the shell.
fork_load_env() {
  local repo_root="${1:-$(fork_repo_root)}"
  local env_file="$repo_root/.env"
  local line key value

  [ -f "$env_file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] || continue
    [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue

    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ "$value" =~ ^\"(.*)\"$ ]]; then
      value="${BASH_REMATCH[1]}"
    elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi

    if [ -z "${!key:-}" ]; then
      export "$key=$value"
    fi
  done < "$env_file"
}

fork_github_token() {
  fork_load_env

  if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "$GITHUB_TOKEN"
    return
  fi

  fork_die "GITHUB_TOKEN is required. Add it to .env in the repo root, or export it. Token needs 'repo' scope: https://github.com/settings/tokens"
}

fork_github_release_exists() {
  local repo="$1"
  local tag="$2"
  local token http_code

  token="$(fork_github_token)"
  http_code="$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${repo}/releases/tags/${tag}")"

  [ "$http_code" = "200" ]
}

# Create a GitHub release. Prints the numeric release id on success.
fork_github_release_create() {
  local repo="$1"
  local tag="$2"
  local title="$3"
  local body="$4"
  local token payload response

  token="$(fork_github_token)"
  payload="$(node - "$tag" "$title" "$body" <<'NODE'
const [tag, title, body] = process.argv.slice(2);
console.log(JSON.stringify({
  tag_name: tag,
  name: title,
  body,
  draft: false,
  prerelease: false,
}));
NODE
)"

  response="$(curl -sf -X POST \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "https://api.github.com/repos/${repo}/releases")" || fork_die "Failed to create GitHub release $tag on $repo"

  echo "$response" | node -p "JSON.parse(require('fs').readFileSync(0,'utf8')).id"
}

fork_github_release_upload() {
  local repo="$1"
  local release_id="$2"
  local file_path="$3"
  local asset_name="$4"
  local token

  token="$(fork_github_token)"
  [ -f "$file_path" ] || fork_die "Asset not found: $file_path"

  curl -sf -X POST \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${file_path}" \
    "https://uploads.github.com/repos/${repo}/releases/${release_id}/assets?name=${asset_name}" \
    >/dev/null || fork_die "Failed to upload asset $asset_name"
}

# Bump extensions/vscode/package.json patch version (e.g. 1.3.44 -> 1.3.45).
fork_bump_extension_version() {
  local repo_root="$1"
  local pkg_json="$repo_root/extensions/vscode/package.json"

  node - "$pkg_json" <<'NODE'
const fs = require("fs");
const pkgPath = process.argv[2];
const raw = fs.readFileSync(pkgPath, "utf8");
const pkg = JSON.parse(raw);
const match = String(pkg.version).match(/^(\d+)\.(\d+)\.(\d+)$/);
if (!match) {
  console.error(`Cannot bump non-semver version: ${pkg.version}`);
  process.exit(1);
}
const next = `${match[1]}.${match[2]}.${Number(match[3]) + 1}`;
fs.writeFileSync(
  pkgPath,
  raw.replace(/"version":\s*"[^"]+"/, `"version": "${next}"`),
);
console.log(next);
NODE
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
