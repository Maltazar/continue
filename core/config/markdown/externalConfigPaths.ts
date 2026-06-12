import * as os from "node:os";
import * as path from "node:path";
import { IDE } from "../..";
import { localPathToUri } from "../../util/pathToUri";
import { joinPathsToUri } from "../../util/uri";

export type ExternalConfigKind = "rules" | "skills" | "agents";

const WORKSPACE_SUBDIRS: Record<ExternalConfigKind, string[][]> = {
  rules: [
    [".cursor", "rules"],
    [".vscode", "rules"],
  ],
  skills: [
    [".cursor", "skills"],
    [".vscode", "skills"],
    [".claude", "skills"],
  ],
  agents: [[".cursor"], [".vscode"]],
};

const GLOBAL_SUBDIRS: Record<ExternalConfigKind, string[][]> = {
  rules: [
    [".cursor", "rules"],
    [".vscode", "rules"],
  ],
  skills: [
    [".cursor", "skills"],
    [".cursor", "skills-cursor"],
    [".vscode", "skills"],
    [".claude", "skills"],
  ],
  agents: [[".cursor"], [".vscode"]],
};

function normalizePathToUri(p: string): string {
  if (p.includes("://")) {
    return p;
  }
  return localPathToUri(path.resolve(p));
}

/**
 * Resolves directories to scan for rules, skills, or agent files.
 * Includes workspace .cursor/.vscode dirs, global home dirs, and optional
 * workstation paths from IDE settings (continue.external*Paths).
 */
export async function getExternalConfigDirs(
  ide: IDE,
  kind: ExternalConfigKind,
): Promise<string[]> {
  const dirs = new Set<string>();
  const workspaceDirs = await ide.getWorkspaceDirs();
  const settings = await ide.getIdeSettings();

  for (const workspaceDir of workspaceDirs) {
    for (const segments of WORKSPACE_SUBDIRS[kind]) {
      dirs.add(joinPathsToUri(workspaceDir, ...segments));
    }
  }

  const home = os.homedir();
  for (const segments of GLOBAL_SUBDIRS[kind]) {
    dirs.add(normalizePathToUri(path.join(home, ...segments)));
  }

  const settingKey =
    kind === "rules"
      ? "externalRulesPaths"
      : kind === "skills"
        ? "externalSkillsPaths"
        : "externalAgentPaths";

  const externalPaths = settings[settingKey];
  if (externalPaths) {
    for (const p of externalPaths) {
      if (p.trim()) {
        dirs.add(normalizePathToUri(p.trim()));
      }
    }
  }

  return [...dirs];
}

export const RULE_FILE_EXTENSIONS = [".md", ".mdc"];

export function isRuleMarkdownFile(filePath: string): boolean {
  const lower = filePath.toLowerCase();
  return RULE_FILE_EXTENSIONS.some((ext) => lower.endsWith(ext));
}
