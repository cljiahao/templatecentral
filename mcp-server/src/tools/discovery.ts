import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { getStacks, getSkillsForStack, validateStack } from "../lib/stacks.js";
import { readMarkdownFile } from "../lib/markdown.js";
import { agentPath, codeStandardsPath, skillPath } from "../lib/paths.js";

export function registerDiscoveryTools(server: McpServer): void {
  server.tool(
    "list_templates",
    "List all available project templates/stacks with metadata",
    {},
    async () => {
      const stacks = await getStacks();
      const lines = stacks.map(
        (s) =>
          `- **${s.name}**: ${s.description} (${s.skillCount} skills, template: ${s.templateExists ? "available" : "missing"})`
      );
      const sharedSkills = await getSkillsForStack("shared");
      lines.push(
        `- **shared**: Cross-stack skills usable by any subagent (${sharedSkills.length} skills, no template)`
      );

      return {
        content: [
          {
            type: "text",
            text: `# Available Templates\n\n${lines.join("\n")}`,
          },
        ],
      };
    }
  );

  server.tool(
    "list_skills",
    "List available skills, optionally filtered by stack",
    { stack: z.string().optional().describe("Filter by stack name (e.g., 'nextjs', 'fastapi')") },
    async ({ stack }) => {
      if (stack) {
        await validateStack(stack);
        const skills = await getSkillsForStack(stack);
        const lines = skills.map((s) => `- **${s.name}**: ${s.description}`);
        return {
          content: [
            {
              type: "text",
              text: `# Skills for ${stack}\n\n${lines.join("\n")}`,
            },
          ],
        };
      }

      const stacks = await getStacks();
      const sections: string[] = [];
      for (const s of stacks) {
        const skills = await getSkillsForStack(s.name);
        const lines = skills.map((sk) => `- **${sk.name}**: ${sk.description}`);
        sections.push(`## ${s.name}\n\n${lines.join("\n")}`);
      }
      // Always include shared cross-stack skills
      const sharedSkills = await getSkillsForStack("shared");
      const sharedLines = sharedSkills.map((sk) => `- **${sk.name}**: ${sk.description}`);
      sections.push(`## shared\n\n${sharedLines.join("\n")}`);

      return {
        content: [
          {
            type: "text",
            text: `# All Skills\n\n${sections.join("\n\n")}`,
          },
        ],
      };
    }
  );

  server.tool(
    "get_skill",
    "Get the full content of a specific skill",
    {
      stack: z.string().describe("Stack name (e.g., 'nextjs')"),
      name: z.string().describe("Skill name (e.g., 'add-feature', 'scaffold')"),
    },
    async ({ stack, name }) => {
      await validateStack(stack);
      try {
        const content = await readMarkdownFile(skillPath(stack, name));
        return { content: [{ type: "text", text: content }] };
      } catch {
        const skills = await getSkillsForStack(stack);
        const available = skills.map((s) => s.name).join(", ");
        return {
          content: [
            {
              type: "text",
              text: `Skill '${name}' not found for stack '${stack}'. Available skills: ${available}`,
            },
          ],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_code_standards",
    "Get the coding standards/conventions for a stack",
    { stack: z.string().describe("Stack name (e.g., 'nextjs')") },
    async ({ stack }) => {
      await validateStack(stack);
      try {
        const content = await readMarkdownFile(codeStandardsPath(stack));
        return { content: [{ type: "text", text: content }] };
      } catch {
        return {
          content: [
            {
              type: "text",
              text: `No code-standards found for stack '${stack}'.`,
            },
          ],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_agent_definition",
    "Get the agent definition (AGENT.md) for a stack",
    { stack: z.string().describe("Stack name (e.g., 'nextjs')") },
    async ({ stack }) => {
      await validateStack(stack);
      try {
        const content = await readMarkdownFile(agentPath(stack));
        return { content: [{ type: "text", text: content }] };
      } catch {
        return {
          content: [
            {
              type: "text",
              text: `AGENT.md not found for stack '${stack}'.`,
            },
          ],
          isError: true,
        };
      }
    }
  );
}
