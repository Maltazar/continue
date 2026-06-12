import {
  ConfigValidationError,
  parseMarkdownRule,
} from "@continuedev/config-yaml";
import z from "zod";
import { IDE, Skill } from "../..";
import { walkDir } from "../../indexing/walkDir";
import { findUriInDirs } from "../../util/uri";
import { getAllDotContinueDefinitionFiles } from "../loadLocalAssistants";
import { getExternalConfigDirs } from "./externalConfigPaths";

const skillFrontmatterSchema = z.object({
  name: z.string().min(1),
  description: z.string().min(1),
});

const SKILLS_DIR = "skills";

/**
 * Get skills from .claude/skills, .cursor/skills, .vscode/skills, and configured paths
 */
async function getExternalSkillsDirs(ide: IDE) {
  const fullDirs = await getExternalConfigDirs(ide, "skills");

  return (
    await Promise.all(
      fullDirs.map(async (dir) => {
        const exists = await ide.fileExists(dir);
        if (!exists) return [];
        const uris = await walkDir(dir, ide, {
          source: "get external skills files",
        });
        return uris.filter((uri) => uri.endsWith(".md"));
      }),
    )
  ).flat();
}

export async function loadMarkdownSkills(ide: IDE) {
  const errors: ConfigValidationError[] = [];
  const skills: Skill[] = [];

  try {
    const yamlAndMarkdownFileUris = [
      ...(
        await getAllDotContinueDefinitionFiles(
          ide,
          {
            includeGlobal: true,
            includeWorkspace: true,
            fileExtType: "markdown",
          },
          SKILLS_DIR,
        )
      ).map((file) => file.path),
      ...(await getExternalSkillsDirs(ide)),
    ];

    const skillFiles = yamlAndMarkdownFileUris.filter((path) =>
      path.endsWith("SKILL.md"),
    );

    const workspaceDirs = await ide.getWorkspaceDirs();
    for (const fileUri of skillFiles) {
      try {
        const content = await ide.readFile(fileUri);
        const { frontmatter, markdown } = parseMarkdownRule(
          content,
        ) as unknown as { frontmatter: Skill; markdown: string };

        const validatedFrontmatter = skillFrontmatterSchema.parse(frontmatter);

        const filesInSkillsDirectory = (
          await walkDir(fileUri.substring(0, fileUri.lastIndexOf("/")), ide, {
            source: "get skill files",
          })
        )
          // do not include SKILL.md as it is already in content
          .filter((file) => !file.endsWith("SKILL.md"));

        const foundRelativeUri = findUriInDirs(fileUri, workspaceDirs);

        skills.push({
          ...validatedFrontmatter,
          content: markdown,
          path: foundRelativeUri.foundInDir
            ? foundRelativeUri.relativePathOrBasename
            : fileUri,
          files: filesInSkillsDirectory,
        });
      } catch (error) {
        errors.push({
          fatal: false,
          message: `Failed to parse markdown skill file: ${error instanceof Error ? error.message : error}`,
        });
      }
    }
  } catch (err) {
    errors.push({
      fatal: false,
      message: `Error loading markdown skill files: ${err instanceof Error ? err.message : err}`,
    });
  }

  return { skills, errors };
}
