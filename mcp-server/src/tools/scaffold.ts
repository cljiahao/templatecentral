import fs from "node:fs/promises";
import path from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { validateStack } from "../lib/stacks.js";
import { templatesDir } from "../lib/paths.js";
import { getLatestVersion } from "../lib/version.js";

const EXCLUDE_PATTERNS = new Set([
  "node_modules",
  ".next",
  ".venv",
  "__pycache__",
  ".pytest_cache",
  ".env",
  ".env.local",
  "dist",
  ".DS_Store",
]);

function shouldCopy(src: string): boolean {
  const basename = path.basename(src);
  return !EXCLUDE_PATTERNS.has(basename);
}

function generateProjectAgentsMd(
  projectName: string,
  stack: string,
  version: string
): string {
  const date = new Date().toISOString().split("T")[0];
  return `<!-- templateCentral: ${stack}@${version} -->
# ${projectName}

**Stack**: ${stack}
**Scaffolded**: ${date}
**Template source**: templateCentral

## Architecture Decisions

_Document significant architecture decisions here as the project evolves._

## Project-Specific Notes

_Add project-specific conventions, integrations, and decisions here._
`;
}

export function registerScaffoldTools(server: McpServer): void {
  server.tool(
    "scaffold_project",
    "Scaffold a new project from a template. Copies the template files and generates an AGENTS.md with version tracking.",
    {
      stack: z.string().describe("Stack to scaffold (e.g., 'nextjs', 'fastapi')"),
      name: z.string().describe("Project name"),
      target_dir: z.string().describe("Absolute path to the target directory"),
    },
    async ({ stack, name, target_dir }) => {
      await validateStack(stack);

      const sourceDir = templatesDir(stack);

      // Check if source template exists
      try {
        await fs.stat(sourceDir);
      } catch {
        return {
          content: [
            {
              type: "text",
              text: `Template directory not found for stack '${stack}'. The stack has skills but no template files.`,
            },
          ],
          isError: true,
        };
      }

      // Check if target directory exists and is non-empty
      try {
        const entries = await fs.readdir(target_dir);
        if (entries.length > 0) {
          return {
            content: [
              {
                type: "text",
                text: `Target directory '${target_dir}' is not empty. Please use an empty directory or a new path.`,
              },
            ],
            isError: true,
          };
        }
      } catch {
        // Directory doesn't exist — that's fine, we'll create it
      }

      // Copy template to target
      await fs.cp(sourceDir, target_dir, {
        recursive: true,
        filter: shouldCopy,
      });

      // Generate AGENTS.md with version marker
      const version = (await getLatestVersion(stack)) ?? "0.0.0";
      const agentsMd = generateProjectAgentsMd(name, stack, version);
      await fs.writeFile(path.join(target_dir, "AGENTS.md"), agentsMd, "utf-8");

      // List what was created (top-level only)
      const created = await fs.readdir(target_dir);

      return {
        content: [
          {
            type: "text",
            text: [
              `Project '${name}' scaffolded successfully.`,
              "",
              `Stack: ${stack}`,
              `Location: ${target_dir}`,
              `Version: ${stack}@${version}`,
              "",
              `Files created:`,
              ...created.map((f) => `  - ${f}`),
              "",
              `Next steps: install dependencies and start the dev server.`,
            ].join("\n"),
          },
        ],
      };
    }
  );
}
