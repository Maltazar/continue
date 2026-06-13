import { parseMarkdownRule } from "@continuedev/config-yaml";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { IDE } from "../..";
import { walkDir } from "../../indexing/walkDir";
import { getAllDotContinueDefinitionFiles } from "../loadLocalAssistants";
import { getExternalConfigDirs } from "./externalConfigPaths";
import {
  loadMarkdownSkillContent,
  loadMarkdownSkillMetadata,
} from "./loadMarkdownSkills";

vi.mock("../loadLocalAssistants", () => ({
  getAllDotContinueDefinitionFiles: vi.fn(),
}));

vi.mock("./externalConfigPaths", () => ({
  getExternalConfigDirs: vi.fn(),
}));

vi.mock("../../indexing/walkDir", () => ({
  walkDir: vi.fn(),
}));

const skillUri = "file:///workspace/.cursor/skills/demo/SKILL.md";
const skillBody = `---
name: demo-skill
description: A demo skill
---
# Demo skill body
Do the thing.
`;

describe("loadMarkdownSkills lazy loading", () => {
  const mockIde = {
    readFile: vi.fn(),
    getWorkspaceDirs: vi.fn().mockResolvedValue(["file:///workspace"]),
    fileExists: vi.fn().mockResolvedValue(true),
  } as unknown as IDE;

  beforeEach(() => {
    vi.resetAllMocks();
    vi.mocked(getExternalConfigDirs).mockResolvedValue([]);
    vi.mocked(mockIde.getWorkspaceDirs).mockResolvedValue([
      "file:///workspace",
    ]);
    vi.mocked(getAllDotContinueDefinitionFiles).mockResolvedValue([
      { path: skillUri, content: skillBody },
    ] as any);
    vi.mocked(mockIde.readFile).mockResolvedValue(skillBody);
    vi.mocked(walkDir).mockResolvedValue([
      `${skillUri.replace("/SKILL.md", "")}/helper.md`,
    ]);
  });

  it("loadMarkdownSkillMetadata indexes frontmatter without walking skill aux files", async () => {
    const { skills, errors } = await loadMarkdownSkillMetadata(mockIde);

    expect(errors).toHaveLength(0);
    expect(skills).toEqual([
      {
        name: "demo-skill",
        description: "A demo skill",
        path: ".cursor/skills/demo/SKILL.md",
        fileUri: skillUri,
      },
    ]);
    expect(walkDir).not.toHaveBeenCalled();
  });

  it("loadMarkdownSkillContent loads one skill body and aux files on demand", async () => {
    const { skills } = await loadMarkdownSkillMetadata(mockIde);
    const skill = await loadMarkdownSkillContent(mockIde, skills[0]);

    const { markdown } = parseMarkdownRule(skillBody) as {
      markdown: string;
    };

    expect(skill.content).toBe(markdown);
    expect(skill.files).toEqual([
      "file:///workspace/.cursor/skills/demo/helper.md",
    ]);
    expect(walkDir).toHaveBeenCalledTimes(1);
  });
});
