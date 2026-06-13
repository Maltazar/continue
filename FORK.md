# Continue Fork

Personal fork of [continuedev/continue](https://github.com/continuedev/continue) for local use with VSCodium on Windows and development in WSL.

## Changes

### SSH / remote terminal fix

Fixes agent terminal commands failing over SSH, WSL, and dev containers ([#10542](https://github.com/continuedev/continue/issues/10542)).

- `extensions/vscode/src/VsCodeIde.ts` — `runCommand()` uses `sendText(command, true)`; new `runCommandWithOutput()` uses shell integration; remote terminals created via `workbench.action.terminal.new`
- `core/tools/implementations/runTerminalCommand.ts` — remote environments use `runCommandWithOutput` instead of fire-and-forget `runCommand`
- Protocol wired through core and VS Code messenger layers

### Rules, skills, and agents from `.cursor` / `.vscode`

Loads Cursor/VS Code config layouts automatically, with optional extra paths via settings.

**Scanned automatically:**

| Kind   | Workspace                                             | Global (`~`)              |
| ------ | ----------------------------------------------------- | ------------------------- |
| Rules  | `.cursor/rules`, `.vscode/rules`                      | same                      |
| Skills | `.cursor/skills`, `.vscode/skills`, `.claude/skills`  | + `.cursor/skills-cursor` |
| Agents | `.cursor`, `.vscode` (AGENTS.md, AGENT.md, CLAUDE.md) | same                      |

**Optional settings** (VSCodium → Settings → search `continue.external`):

```json
{
  "continue.externalRulesPaths": ["D:\\shared\\cursor-rules"],
  "continue.externalSkillsPaths": ["D:\\shared\\skills"],
  "continue.externalAgentPaths": ["D:\\shared\\agents"]
}
```

Use these to point at shared folders on a workstation without symlinks.

Key files: `core/config/markdown/externalConfigPaths.ts`, `loadMarkdownRules.ts`, `loadMarkdownSkills.ts`, `loadLocalAssistants.ts`

### Lazy skill loading

Reduces context usage: the agent sees skill **names and descriptions** in the `read_skill` tool schema, but SKILL.md **bodies are loaded only when the agent calls the tool** for one skill.

- `loadMarkdownSkillMetadata()` — indexes name, description, path (reads frontmatter only; no auxiliary file walks)
- `loadMarkdownSkillContent()` — loads one SKILL.md body + supporting files on demand
- `read_skill` tool — metadata for the tool definition; full content on invocation

Key files: `core/config/markdown/loadMarkdownSkills.ts`, `core/tools/definitions/readSkill.ts`, `core/tools/implementations/readSkill.ts`

### VSCodium / SSH remote

- `extensions/vscode/package.json` — `extensionKind` set to `["ui"]` only (avoids duplicate activation on Windows host + SSH remote)
- `extensions/vscode/src/activation/activate.ts` — skips workspace-host activation

The Running Extensions warning about `focusContinueInput` already registered is a known VSCodium cosmetic message when Continue works; safe to ignore.

## Prerequisites

- Node.js **v20.20.1** (see `.nvmrc`) — `nvm use`
- WSL for building
- VSCodium on Windows — extensions live in `%USERPROFILE%\.vscode-oss\extensions`

Do **not** run the upstream `scripts/install-dependencies.sh` or build the `binary/` package. They are not required for the VS Code extension and fail on Node 22.

## Build

Build in WSL, but target **Windows** binaries (VSCodium runs on Windows, not inside WSL):

```bash
./scripts/fork-setup.sh          # once — installs deps for core, gui, vscode extension
./scripts/fork-build.sh          # produces VSIX (defaults to CONTINUE_BUILD_TARGET=win32-x64)
```

Incremental rebuild (skip GUI when unchanged):

```bash
SKIP_INSTALLS=true ./scripts/fork-build.sh --skip-gui
```

`fork-build.sh` sets `CONTINUE_BUILD_TARGET=win32-x64` by default. Prepackage downloads Windows-native `node_sqlite3.node`, LanceDB, and onnx binaries even when building from Linux/WSL.

**Output:**

```
extensions/vscode/build/continue-<version>.vsix
extensions/vscode/build/continue-install-bundle/
  continue-<version>.vsix
  install-vsix.ps1
```

## Install

Build in WSL. Install on Windows where VSCodium runs.

### Option A — PowerShell on Windows (recommended)

Copy `continue-install-bundle` anywhere on Windows, then:

```powershell
cd C:\Users\You\Downloads\continue-install-bundle
.\install-vsix.ps1
```

Or pass an explicit path:

```powershell
.\install-vsix.ps1 -VsixPath C:\Users\You\Downloads\continue-1.3.40.vsix
```

Dry run:

```powershell
.\install-vsix.ps1 -DryRun
```

The script closes VSCodium before installing (clears stale extension host state), uninstalls the old `Continue.continue`, removes stale folders and `extensions.json` entries, then installs the VSIX via `codium.cmd --install-extension --force`.

Override VSCodium location if needed:

```powershell
$env:CONTINUE_VSCODIUM_CMD = "C:\Program Files\VSCodium\bin\codium.cmd"
```

### Option B — from WSL

Delegates to the PowerShell installer (stages files to `%TEMP%\continue-vsix-install` on Windows):

```bash
./scripts/fork-install.sh extensions/vscode/build/continue-1.3.40.vsix
```

### Option C — manual

VSCodium → Extensions → `...` → **Install from VSIX...**

### After install

Fully quit VSCodium, then reopen. Confirm **Continue.continue** appears under Running Extensions without activation errors.

## Scripts

| Script                     | Purpose                                   |
| -------------------------- | ----------------------------------------- |
| `scripts/fork-setup.sh`    | One-time dev environment setup            |
| `scripts/fork-build.sh`    | Build VSIX + install bundle               |
| `scripts/install-vsix.ps1` | Native Windows installer (copy with VSIX) |
| `scripts/fork-install.sh`  | WSL wrapper around `install-vsix.ps1`     |
| `scripts/fork-common.sh`   | Shared helpers (not run directly)         |

## Environment variables

| Variable                | Used by            | Purpose                                                             |
| ----------------------- | ------------------ | ------------------------------------------------------------------- |
| `CONTINUE_BUILD_TARGET` | `fork-build.sh`    | Native binary target (default: `win32-x64`)                         |
| `SKIP_INSTALLS=true`    | `fork-build.sh`    | Skip npm reinstalls in prepackage (Windows sqlite still downloaded) |
| `CONTINUE_WINDOWS_USER` | `fork-install.sh`  | Windows username for staging (auto-detected)                        |
| `CONTINUE_VSCODIUM_CMD` | `install-vsix.ps1` | Path to `codium.cmd`                                                |

## Troubleshooting

### `node_sqlite3.node is not a valid Win32 application`

The VSIX was built for the wrong platform (usually `linux-x64` because WSL auto-detected the host). Rebuild with:

```bash
CONTINUE_BUILD_TARGET=win32-x64 ./scripts/fork-build.sh --skip-gui
```

Then reinstall with `install-vsix.ps1` (removes all `continue.continue-*` versions).

### `Command 'continue.focusContinueInput' already registered`

Cosmetic VSCodium message when Continue is working. Ignore it.

### YAML grammar overwrite warnings

From the Red Hat YAML extension overriding the built-in VSCodium YAML grammar. Unrelated to Continue; safe to ignore.
