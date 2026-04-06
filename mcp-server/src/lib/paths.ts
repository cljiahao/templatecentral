import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// From dist/lib/ → two levels up to mcp-server/, then one more to repo root
export const REPO_ROOT = path.resolve(__dirname, "..", "..", "..");

export const SKILLS_DIR = path.join(REPO_ROOT, "claude-skills");
export const TEMPLATES_DIR = path.join(REPO_ROOT, "templates");

export function skillsDir(stack?: string): string {
  return stack ? path.join(SKILLS_DIR, stack) : SKILLS_DIR;
}

export function templatesDir(stack?: string): string {
  return stack ? path.join(TEMPLATES_DIR, stack) : TEMPLATES_DIR;
}

export function skillPath(stack: string, skillName: string): string {
  return path.join(SKILLS_DIR, stack, skillName, "SKILL.md");
}

export function agentPath(stack: string): string {
  return path.join(SKILLS_DIR, stack, "AGENT.md");
}

export function codeStandardsPath(stack: string): string {
  return path.join(SKILLS_DIR, stack, "code-standards", "SKILL.md");
}
