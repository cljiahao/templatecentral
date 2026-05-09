---
name: shared-add-ai-security
description: Apply OWASP LLM Top 10 v2.0 security controls when adding AI/LLM features to any templateCentral project
version: "1.0.0"
---

# Add AI Security Patterns

Wire OWASP LLM Top 10 v2.0 security controls into a project that uses an LLM API. Use this skill any time you add AI-powered features — chat, summarisation, code generation, agents, RAG pipelines.

## Prerequisites

Requires a project scaffolded with any templateCentral scaffold skill. See Step 0.

## When to Use

- Adding a chat interface, AI assistant, or copilot feature
- Integrating OpenAI, Anthropic, AWS Bedrock, Azure OpenAI, or any LLM API
- Building RAG (retrieval-augmented generation) pipelines
- Creating AI agents with tool/function calling

## First: One Question

Before writing any code, ask:

> **What AI capability are you adding?**
> - **A** — Simple prompt → response (no tools, no RAG)
> - **B** — RAG pipeline (vector search + retrieval)
> - **C** — Agentic system (tool use, function calling, multi-step)
>
> Answer affects which controls are mandatory vs advisory.

---

## Implementation

Load the full AI security implementation guide:
```bash
cat "$HOME/.claude/plugins/marketplaces/templatecentral/skills/shared-add-ai-security/implementation.md"
```
Follow the loaded guide exactly.
