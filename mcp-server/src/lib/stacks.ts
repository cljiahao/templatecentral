import fs from "node:fs/promises";
import path from "node:path";
import { SKILLS_DIR, TEMPLATES_DIR, agentPath } from "./paths.js";
import { parseFrontmatter, readMarkdownFile } from "./markdown.js";

export interface StackInfo {
  name: string;
  description: string;
  templateExists: boolean;
  skillCount: number;
}

export interface SkillInfo {
  name: string;
  description: string;
  stack: string;
}

async function dirExists(dirPath: string): Promise<boolean> {
  try {
    const stat = await fs.stat(dirPath);
    return stat.isDirectory();
  } catch {
    return false;
  }
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    const stat = await fs.stat(filePath);
    return stat.isFile();
  } catch {
    return false;
  }
}

export async function getStacks(): Promise<StackInfo[]> {
  const entries = await fs.readdir(SKILLS_DIR, { withFileTypes: true });
  const stacks: StackInfo[] = [];

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;

    // A valid stack has an AGENT.md file (excludes "shared")
    const agentFile = agentPath(entry.name);
    if (!(await fileExists(agentFile))) continue;

    const templateExists = await dirExists(
      path.join(TEMPLATES_DIR, entry.name)
    );
    const skills = await getSkillsForStack(entry.name);

    // Extract description from first heading in AGENT.md
    const agentContent = await readMarkdownFile(agentFile);
    const headingMatch = agentContent.match(/^#\s+(.+)$/m);
    const description = headingMatch?.[1]?.trim() ?? entry.name;

    stacks.push({
      name: entry.name,
      description,
      templateExists,
      skillCount: skills.length,
    });
  }

  return stacks;
}

export async function getSkillsForStack(stack: string): Promise<SkillInfo[]> {
  const stackDir = path.join(SKILLS_DIR, stack);
  if (!(await dirExists(stackDir))) {
    throw new Error(
      `Stack '${stack}' not found. Run list_templates to see available stacks.`
    );
  }

  const entries = await fs.readdir(stackDir, { withFileTypes: true });
  const skills: SkillInfo[] = [];

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;

    const skillFile = path.join(stackDir, entry.name, "SKILL.md");
    if (!(await fileExists(skillFile))) continue;

    const content = await readMarkdownFile(skillFile);
    const { name, description } = parseFrontmatter(content);

    skills.push({
      name: name || entry.name,
      description: description || "",
      stack,
    });
  }

  return skills;
}

export async function validateStack(stack: string): Promise<void> {
  // Reject any stack name that isn't a simple alphanumeric/hyphen slug.
  // This prevents path traversal before any filesystem access occurs.
  if (!/^[a-z0-9-]+$/.test(stack)) {
    throw new Error(
      `Invalid stack name '${stack}'. Stack names may only contain lowercase letters, digits, and hyphens.`
    );
  }

  // "shared" is a special stack with cross-stack skills but no AGENT.md
  if (stack === "shared") {
    const stackDir = path.join(SKILLS_DIR, stack);
    if (await dirExists(stackDir)) return;
    throw new Error(`Stack 'shared' directory not found.`);
  }
  const agentFile = agentPath(stack);
  if (!(await fileExists(agentFile))) {
    const stacks = await getStacks();
    const available = [...stacks.map((s) => s.name), "shared"].join(", ");
    throw new Error(
      `Stack '${stack}' not found. Available stacks: ${available}`
    );
  }
}
