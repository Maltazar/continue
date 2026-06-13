# Continue Fork

Personal fork of [continuedev/continue](https://github.com/continuedev/continue). Build in WSL, run in VSCodium on Windows.

## Quick start

```bash
./scripts/fork-setup.sh                                    # once
SKIP_INSTALLS=true ./scripts/fork-build.sh --skip-gui      # build (bumps patch version)
./scripts/fork-install.sh                                  # install latest VSIX to VSCodium
```

Reopen VSCodium after install. Confirm **Continue.continue** at the new version under Running Extensions.

## Prerequisites

- Node.js **v20.20.1** (`nvm use` — see `.nvmrc`)
- WSL for building
- VSCodium on Windows — extensions in `%USERPROFILE%\.vscode-oss\extensions`

Do **not** run upstream `scripts/install-dependencies.sh` or build the `binary/` package. Neither is required for the VS Code extension; `binary/` fails on Node 22.

## Fork changes

### SSH / remote terminal

Fixes agent terminal commands over SSH, WSL, and dev containers ([#10542](https://github.com/continuedev/continue/issues/10542), [PR #10786](https://github.com/continuedev/continue/pull/10786)).

- `extensions/vscode/src/VsCodeIde.ts` — `sendText(command, true)`; `runCommandWithOutput()` with shell integration; remote terminals via `workbench.action.terminal.new`
- `core/tools/implementations/runTerminalCommand.ts` — remotes use `runCommandWithOutput` instead of fire-and-forget `runCommand`
- Protocol wired through core and VS Code messenger layers

### Rules, skills, and agents (`.cursor` / `.vscode`)

Loads Cursor/VS Code layouts automatically. Optional paths point at shared workstation folders (no symlinks).

| Kind   | Workspace                                             | Global (`~`)              |
| ------ | ----------------------------------------------------- | ------------------------- |
| Rules  | `.cursor/rules`, `.vscode/rules`                      | same                      |
| Skills | `.cursor/skills`, `.vscode/skills`, `.claude/skills`  | + `.cursor/skills-cursor` |
| Agents | `.cursor`, `.vscode` (AGENTS.md, AGENT.md, CLAUDE.md) | same                      |

**Settings** (VSCodium → search `continue.external`):

```json
{
  "continue.externalRulesPaths": ["D:\\shared\\cursor-rules"],
  "continue.externalSkillsPaths": ["D:\\shared\\skills"],
  "continue.externalAgentPaths": ["D:\\shared\\agents"]
}
```

**Rules behavior** (upstream Continue, used as-is):

- `alwaysApply: true` in `.mdc` frontmatter → always injected
- `globs` → applied when open files / context match
- `alwaysApply: false` + globs → scoped only

Key files: `core/config/markdown/externalConfigPaths.ts`, `loadMarkdownRules.ts`, `loadLocalAssistants.ts`

### Lazy skill loading

Reduces context window usage for skills. The agent sees **name + description** in the `read_skill` tool schema; **SKILL.md bodies load only when the agent calls the tool** for one skill.

| Stage             | What loads                                                        |
| ----------------- | ----------------------------------------------------------------- |
| Tool definition   | `loadMarkdownSkillMetadata()` — name, description, path per skill |
| `read_skill` call | `loadMarkdownSkillContent()` — one SKILL.md body + aux file list  |

Auxiliary files in a skill directory are not walked at index time; they are listed when that skill is read.

Key files: `core/config/markdown/loadMarkdownSkills.ts`, `core/tools/definitions/readSkill.ts`, `core/tools/implementations/readSkill.ts`

### VSCodium / SSH remote

- `extensionKind: ["ui"]` only — avoids duplicate activation on Windows host + SSH remote
- Workspace-host activation skipped in `activate.ts`

The Running Extensions warning `focusContinueInput already registered` is cosmetic when Continue works. Ignore it.

## Build

Build in WSL; target **Windows** native binaries (`win32-x64`). VSCodium runs on Windows, not inside WSL.

```bash
./scripts/fork-setup.sh          # once
./scripts/fork-build.sh          # full build
```

**Daily incremental build:**

```bash
SKIP_INSTALLS=true ./scripts/fork-build.sh --skip-gui
```

| Flag / env              | Effect                                                                                         |
| ----------------------- | ---------------------------------------------------------------------------------------------- |
| `--skip-gui`            | Skip GUI rebuild (requires existing `gui/dist`)                                                |
| `--setup`               | Run `fork-setup.sh` before build                                                               |
| `--no-bump`             | Do not increment `package.json` version                                                        |
| `SKIP_INSTALLS=true`    | Skip npm reinstalls in prepackage; still downloads Windows sqlite/ripgrep when cross-compiling |
| `CONTINUE_BUILD_TARGET` | Native binary target (default: `win32-x64`)                                                    |

Each build **bumps the patch version** in `extensions/vscode/package.json` (e.g. `1.3.44` → `1.3.45`) unless `--no-bump` is passed.

**Output:**

```
extensions/vscode/build/continue-<version>.vsix
extensions/vscode/build/continue-install-bundle/
  continue-<version>.vsix
  install-vsix.ps1
```

`fork-install.sh` without arguments installs the **newest** VSIX in `extensions/vscode/build/`. Always run `fork-build.sh` before `fork-install.sh` after code changes.

## Install

Install on Windows where VSCodium runs.

### PowerShell (recommended)

Copy `continue-install-bundle` anywhere on Windows:

```powershell
cd C:\Users\You\Downloads\continue-install-bundle
.\install-vsix.ps1
```

Or with an explicit path:

```powershell
.\install-vsix.ps1 -VsixPath C:\Users\You\Downloads\continue-1.3.45.vsix
```

`install-vsix.ps1` closes VSCodium, uninstalls old `Continue.continue`, removes stale extension folders and `extensions.json` entries, then runs `codium.cmd --install-extension --force`.

### From WSL

```bash
./scripts/fork-install.sh
./scripts/fork-install.sh extensions/vscode/build/continue-1.3.45.vsix
```

Delegates to `install-vsix.ps1` (stages VSIX to `%TEMP%\continue-vsix-install` on Windows).

### Manual

VSCodium → Extensions → `...` → **Install from VSIX...**

## Scripts

| Script                     | Purpose                                         |
| -------------------------- | ----------------------------------------------- |
| `scripts/fork-setup.sh`    | One-time deps (core, gui, vscode extension)     |
| `scripts/fork-build.sh`    | Bump version, build VSIX, create install bundle |
| `scripts/install-vsix.ps1` | Native Windows installer (ships in bundle)      |
| `scripts/fork-install.sh`  | WSL wrapper → `install-vsix.ps1`                |
| `scripts/fork-common.sh`   | Shared helpers (not run directly)               |

## Environment variables

| Variable                | Used by            | Purpose                                                               |
| ----------------------- | ------------------ | --------------------------------------------------------------------- |
| `CONTINUE_BUILD_TARGET` | `fork-build.sh`    | Native binary target (default: `win32-x64`)                           |
| `SKIP_INSTALLS=true`    | `fork-build.sh`    | Faster prepackage; Windows natives still fetched when cross-compiling |
| `CONTINUE_WINDOWS_USER` | `fork-install.sh`  | Windows username for staging (auto-detected)                          |
| `CONTINUE_VSCODIUM_CMD` | `install-vsix.ps1` | Path to `codium.cmd`                                                  |

## Troubleshooting

### `node_sqlite3.node is not a valid Win32 application`

VSIX was built for the wrong platform (WSL default `linux-x64`). Rebuild with the fork scripts (they default to `win32-x64`), then reinstall:

```bash
SKIP_INSTALLS=true ./scripts/fork-build.sh --skip-gui
./scripts/fork-install.sh
```

### Installed old version after code changes

`fork-install.sh` installs the newest VSIX in `build/`. Run `fork-build.sh` first — it bumps the version so the new VSIX replaces the old one cleanly.

### `focusContinueInput already registered`

Cosmetic VSCodium message when Continue works. Ignore.

### YAML grammar overwrite warnings (DevTools)

Red Hat YAML extension overriding built-in VSCodium YAML grammar. Unrelated to Continue.

### Install reports success but wrong version in Running Extensions

Fully quit VSCodium (all windows), reopen. Confirm only one `continue.continue-*` folder under `%USERPROFILE%\.vscode-oss\extensions\`.

## Out of scope (not implemented in this fork)

- `.cursorignore` enforcement on agent `read_file` / tools (Continue uses `.continueignore` for indexing only)
- Credentials / secrets filtering in context
- Conditional reference files (custom rules/globs can cover this)
