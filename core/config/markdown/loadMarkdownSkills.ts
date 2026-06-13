import {
  ConfigValidationError,
  parseMarkdownRule,
} from "@continuedev/config-yaml";
import z from "zod";
import { IDE, Skill, SkillMetadata } from "../..";
import { walkDir } from "../../indexing/walkDir";
import { findUriInDirs } from "../../util/uri";
import { getAllDotContinueDefinitionFiles } from "../loadLocalAssistants";
import { getExternalConfigDirs } from "./externalConfigPaths";

const skillFrontmatterSchema = z.object({
  name: z.string().min(1),
  description: z.string().min(1),
});

const SKILLS_DIR = "skills";

async function discoverSkillFileUris(ide: IDE): Promise<string[]> {
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
    ...(await getExternalSkillFileUris(ide)),
  ];

  return yamlAndMarkdownFileUris.filter((path) => path.endsWith("SKILL.md"));
}

/**
 * Get skill markdown files from .claude/skills, .cursor/skills, .vscode/skills, and configured paths
 */
async function getExternalSkillFileUris(ide: IDE): Promise<string[]> {
  const fullDirs = await getExternalConfigDirs(ide, "skills");

  return (
    await Promise.all(
      fullDirs.map(async (dir) => {
        const exists = await ide.fileExists(dir);
        if (!exists) {
          return [];
        }
        const uris = await walkDir(dir, ide, {
          source: "get external skills files",
        });
        return uris.filter((uri) => uri.endsWith("SKILL.md"));
      }),
    )
  ).flat();
}

/**
 * Index skill name, description, and paths only — no SKILL.md bodies or auxiliary files.
 */
export async function loadMarkdownSkillMetadata(ide: IDE) {
  const errors: ConfigValidationError[] = [];
  const skills: SkillMetadata[] = [];

  try {
    const skillFiles = await discoverSkillFileUris(ide);
    const workspaceDirs = await ide.getWorkspaceDirs();

    for (const fileUri of skillFiles) {
      try {
        const content = await ide.readFile(fileUri);
        const { frontmatter } = parseMarkdownRule(content) as unknown as {
          frontmatter: Skill;
        };

        const validatedFrontmatter = skillFrontmatterSchema.parse(frontmatter);
        const foundRelativeUri = findUriInDirs(fileUri, workspaceDirs);

        skills.push({
          name: validatedFrontmatter.name,
          description: validatedFrontmatter.description,
          path: foundRelativeUri.foundInDir
            ? foundRelativeUri.relativePathOrBasename
            : fileUri,
          fileUri,
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

/**
 * Load one skill's body and auxiliary file list when the agent calls read_skill.
 */
export async function loadMarkdownSkillContent(
  ide: IDE,
  metadata: SkillMetadata,
): Promise<Skill> {
  const content = await ide.readFile(metadata.fileUri);
  const { frontmatter, markdown } = parseMarkdownRule(content) as unknown as {
    frontmatter: Skill;
    markdown: string;
  };

  skillFrontmatterSchema.parse(frontmatter);

  const skillDirUri = metadata.fileUri.substring(
    0,
    metadata.fileUri.lastIndexOf("/"),
  );
  const filesInSkillsDirectory = (
    await walkDir(skillDirUri, ide, {
      source: "get skill files",
    })
  ).filter((file) => !file.endsWith("SKILL.md"));

  return {
    ...metadata,
    content: markdown,
    files: filesInSkillsDirectory,
    license: frontmatter.license,
  };
}

/** @deprecated Use loadMarkdownSkillMetadata — kept for callers that expect the old name */
export async function loadMarkdownSkills(ide: IDE) {
  return loadMarkdownSkillMetadata(ide);
}
