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

### VSCodium activation fix

Prevents duplicate command registration when running UI host + SSH remote.

- `extensions/vscode/package.json` — `extensionKind` set to `["ui"]` only
- `extensions/vscode/src/activation/activate.ts` — skips workspace-host activation and duplicate `activate()` calls
- `extensions/vscode/src/commands.ts` — skips commands already registered (survives partial reloads)

After installing, **fully quit VSCodium** (all windows) before reopening. Reload Window alone can leave stale command handlers.

## Prerequisites

- Node.js **v20.20.1** (see `.nvmrc`) — `nvm use`
- WSL for building
- VSCodium on Windows — extensions live in `%USERPROFILE%\.vscode-oss\extensions`

Do **not** run the upstream `scripts/install-dependencies.sh` or build the `binary/` package. They are not required for the VS Code extension and fail on Node 22.

## Build

```bash
./scripts/fork-setup.sh          # once — installs deps for core, gui, vscode extension
./scripts/fork-build.sh          # produces VSIX
```

Incremental rebuild (skip GUI when unchanged):

```bash
SKIP_INSTALLS=true ./scripts/fork-build.sh --skip-gui
```

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

The script uninstalls the old `Continue.continue`, removes stale extension folders and `extensions.json` entries, then installs the VSIX via `codium.cmd --install-extension --force`.

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

| Variable                | Used by            | Purpose                                      |
| ----------------------- | ------------------ | -------------------------------------------- |
| `SKIP_INSTALLS=true`    | `fork-build.sh`    | Skip sqlite re-download during prepackage    |
| `CONTINUE_WINDOWS_USER` | `fork-install.sh`  | Windows username for staging (auto-detected) |
| `CONTINUE_VSCODIUM_CMD` | `install-vsix.ps1` | Path to `codium.cmd`                         |
