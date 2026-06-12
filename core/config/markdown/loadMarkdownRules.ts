import {
  ConfigValidationError,
  markdownToRule,
} from "@continuedev/config-yaml";
import ignore from "ignore";
import { IDE, RuleWithSource } from "../..";
import {
  DEFAULT_IGNORE_DIRS,
  DEFAULT_IGNORE_FILETYPES,
} from "../../indexing/ignore";
import { walkDir } from "../../indexing/walkDir";
import { PROMPTS_DIR_NAME, RULES_DIR_NAME } from "../../promptFiles";
import { joinPathsToUri } from "../../util/uri";
import { getAllDotContinueDefinitionFiles } from "../loadLocalAssistants";
import {
  getExternalConfigDirs,
  isRuleMarkdownFile,
} from "./externalConfigPaths";

export const SUPPORTED_AGENT_FILES = [
  "AGENTS.md",
  "AGENT.md",
  "CLAUDE.md",
  "CODEX.md",
];

async function loadMarkdownFilesFromDir(
  ide: IDE,
  dir: string,
): Promise<{ path: string; content: string }[]> {
  try {
    const exists = await ide.fileExists(dir);
    if (!exists) {
      return [];
    }

    const overrideDefaultIgnores = ignore()
      .add(
        DEFAULT_IGNORE_FILETYPES.filter(
          (t) => t !== "config.yaml" && t !== "config.yml",
        ),
      )
      .add(DEFAULT_IGNORE_DIRS);

    const uris = await walkDir(dir, ide, {
      overrideDefaultIgnores,
      source: "get external config files",
    });

    const mdFiles = uris.filter((uri) => isRuleMarkdownFile(uri));

    return Promise.all(
      mdFiles.map(async (uri) => ({
        path: uri,
        content: await ide.readFile(uri),
      })),
    );
  } catch {
    return [];
  }
}

async function loadAgentFilesFromDirs(
  ide: IDE,
  dirs: string[],
): Promise<RuleWithSource[]> {
  const rules: RuleWithSource[] = [];

  for (const dir of dirs) {
    for (const fileName of SUPPORTED_AGENT_FILES) {
      try {
        const agentFileUri = joinPathsToUri(dir, fileName);
        const exists = await ide.fileExists(agentFileUri);
        if (exists) {
          const agentContent = await ide.readFile(agentFileUri);
          const rule = markdownToRule(agentContent, {
            uriType: "file",
            fileUri: agentFileUri,
          });
          rules.push({
            ...rule,
            source: "agentFile",
            sourceFile: agentFileUri,
            alwaysApply: true,
          });
          return rules;
        }
      } catch {
        // File doesn't exist or can't be read
      }
    }
  }

  return rules;
}
/**
 * Loads rules from markdown files in the .continue/rules and .continue/prompts directories
 * and agent files (AGENTS.md, AGENT.md, CLAUDE.md) at workspace root
 */
export async function loadMarkdownRules(ide: IDE): Promise<{
  rules: RuleWithSource[];
  errors: ConfigValidationError[];
}> {
  const errors: ConfigValidationError[] = [];
  const rules: RuleWithSource[] = [];

  // Load agent files: workspace root, then .cursor/.vscode and configured paths
  const workspaceDirs = await ide.getWorkspaceDirs();

  for (const workspaceDir of workspaceDirs) {
    let agentFileFound = false;
    for (const fileName of SUPPORTED_AGENT_FILES) {
      try {
        const agentFileUri = joinPathsToUri(workspaceDir, fileName);
        const exists = await ide.fileExists(agentFileUri);
        if (exists) {
          const agentContent = await ide.readFile(agentFileUri);

          const rule = markdownToRule(agentContent, {
            uriType: "file",
            fileUri: agentFileUri,
          });
          rules.push({
            ...rule,
            source: "agentFile",
            sourceFile: agentFileUri,
            alwaysApply: true,
          });
          agentFileFound = true;
        }

        break; // Use the first found agent file in this workspace
      } catch (e) {
        // File doesn't exist or can't be read, continue to next file
      }
    }
    if (agentFileFound) {
      break; // Use agent file from first workspace that has one
    }
  }

  if (rules.length === 0) {
    const externalAgentDirs = await getExternalConfigDirs(ide, "agents");
    const agentRules = await loadAgentFilesFromDirs(ide, externalAgentDirs);
    rules.push(...agentRules);
  }

  // Load markdown files from both .continue/rules and .continue/prompts
  const dirsToCheck = [RULES_DIR_NAME, PROMPTS_DIR_NAME];

  for (const dirName of dirsToCheck) {
    try {
      const markdownFiles = await getAllDotContinueDefinitionFiles(
        ide,
        {
          includeGlobal: true,
          includeWorkspace: true,
          fileExtType: "markdown",
        },
        dirName,
      );

      // Filter to just .md files
      const mdFiles = markdownFiles.filter((file) => file.path.endsWith(".md"));

      // Process each markdown file
      for (const file of mdFiles) {
        try {
          const rule = markdownToRule(file.content, {
            uriType: "file",
            fileUri: file.path,
          });
          if (!rule.invokable) {
            rules.push({
              ...rule,
              source: "rules-block",
              sourceFile: file.path,
            });
          }
        } catch (e) {
          errors.push({
            fatal: false,
            message: `Failed to parse markdown rule file ${file.path}: ${e instanceof Error ? e.message : e}`,
          });
        }
      }
    } catch (e) {
      errors.push({
        fatal: false,
        message: `Error loading markdown rule files from ${dirName}: ${e instanceof Error ? e.message : e}`,
      });
    }
  }

  // Load rules from .cursor/rules, .vscode/rules, and configured external paths
  const externalRulesDirs = await getExternalConfigDirs(ide, "rules");
  const externalRuleFiles = (
    await Promise.all(
      externalRulesDirs.map((dir) => loadMarkdownFilesFromDir(ide, dir)),
    )
  ).flat();

  for (const file of externalRuleFiles) {
    try {
      const rule = markdownToRule(file.content, {
        uriType: "file",
        fileUri: file.path,
      });
      if (!rule.invokable) {
        rules.push({
          ...rule,
          source: "rules-block",
          sourceFile: file.path,
        });
      }
    } catch (e) {
      errors.push({
        fatal: false,
        message: `Failed to parse external rule file ${file.path}: ${e instanceof Error ? e.message : e}`,
      });
    }
  }

  return { rules, errors };
}
