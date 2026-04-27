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

const STACK_AGENTS_CONTENT: Record<string, string> = {
  nextjs: `## Identity

Agent: read \`claude-skills/nextjs/AGENT.md\` to find the right skill for each task.

## Architecture Decisions

- App Router only (\`src/app/\`); no \`pages/\` directory
- Route groups: \`(public)/\` for public pages; run \`nextjs-add-auth\` skill to add \`dashboard/\` and auth
- Feature-first structure: \`src/features/<name>/\` (api/, components/, hooks/, schemas/)
- Integration layer: \`src/integrations/\` for all external API clients
- Server components by default; \`'use client'\` only for interactivity

## Key Conventions

- Named exports only (no default exports in application code)
- Secrets never in \`NEXT_PUBLIC_*\` env vars
- API tests: Vitest under \`test/api/\` for \`src/app/api/**\` in the same change`,

  fastapi: `## Identity

Agent: read \`claude-skills/fastapi/AGENT.md\` to find the right skill for each task.

## Architecture Decisions

- Layered: \`api/\` (routers → services) → \`models/\`
- \`core/\` is standalone infrastructure (config, logging, exceptions) — never import from \`api/\` or \`models/\`
- \`utils/\` for pure helpers only
- Centralized error handling via \`error_handler.py\`; never raise raw HTTP exceptions in services

## Key Conventions

- Pydantic v2 with camelCase aliases via \`alias_generator\`; \`extra="forbid"\` on all schemas
- Use \`X | None\` not \`Optional[X]\`
- Tests: pytest under \`test/\`; use \`TestClient\` from FastAPI`,

  "vite-react": `## Identity

Agent: read \`claude-skills/vite-react/AGENT.md\` to find the right skill for each task.

## Architecture Decisions

- Client-only SPA (no SSR/RSC)
- Feature-first structure: \`src/features/<name>/\` (api/, components/, hooks/, schemas/)
- Routes defined in \`src/router.tsx\` (not filesystem-based)
- Auth via \`AuthProvider\` context with dev bypass (\`ENV.IS_DEV\`)

## Key Conventions

- Named exports only (no default exports in application code)
- Never \`process.env\` — use \`import.meta.env.VITE_*\` via \`src/lib/constants/env.ts\`
- Secrets never in \`VITE_*\` env vars — exposed in client bundle`,

  nestjs: `## Identity

Agent: read \`claude-skills/nestjs/AGENT.md\` to find the right skill for each task.

## Architecture Decisions

- One module per feature: \`src/modules/<feature>/\`
- Shared infrastructure: \`src/common/\` (filters, types, utils) and \`src/config/\`
- DTOs via \`nestjs-zod\` with \`createZodDto\` — no class-validator
- Fastify adapter — use \`app.inject()\` for e2e tests (not supertest)

## Key Conventions

- Named exports; never \`export default\` in application code
- Swagger on every endpoint: \`@ApiTags()\` + \`@ApiOperation()\`
- Tests: Jest under \`test/\`; e2e via \`test/jest-e2e.json\``,
};

function generateProjectAgentsMd(
  projectName: string,
  stack: string,
  version: string
): string {
  const date = new Date().toISOString().split("T")[0];
  const stackContent =
    STACK_AGENTS_CONTENT[stack] ??
    `## Identity

Agent: read \`claude-skills/${stack}/AGENT.md\` to find the right skill for each task.

## Architecture Decisions

_Document significant architecture decisions here as the project evolves._`;

  return `<!-- templateCentral: ${stack}@${version} -->
# ${projectName}

**Stack**: ${stack}
**Scaffolded**: ${date}
**Template source**: templateCentral

${stackContent}

## Project-Specific Notes

_Add project-specific integrations, decisions, and team conventions here._
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
