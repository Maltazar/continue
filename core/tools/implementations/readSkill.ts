import { ToolImpl } from ".";
import {
  loadMarkdownSkillContent,
  loadMarkdownSkillMetadata,
} from "../../config/markdown/loadMarkdownSkills";
import { ContinueError, ContinueErrorReason } from "../../util/errors";
import { getStringArg } from "../parseArgs";

export const readSkillImpl: ToolImpl = async (args, extras) => {
  const skillName = getStringArg(args, "skillName");

  const { skills: skillMetadata } = await loadMarkdownSkillMetadata(extras.ide);
  const metadata = skillMetadata.find((s) => s.name === skillName);

  if (!metadata) {
    const availableSkills = skillMetadata.map((s) => s.name).join(", ");
    throw new ContinueError(
      ContinueErrorReason.SkillNotFound,
      `Skill "${skillName}" not found. Available skills: ${availableSkills || "none"}`,
    );
  }

  const skill = await loadMarkdownSkillContent(extras.ide, metadata);

  let content = skill.content;

  if (skill.files.length > 0) {
    content += `\n
## Supporting files
Skill directory:
${skill.files.join("\n")}

Use the read file tool to access these files as needed.`;
  }

  return [
    {
      name: `Skill: ${skill.name}`,
      description: skill.description,
      content,
      uri: {
        type: "file",
        value: skill.path,
      },
    },
  ];
};
