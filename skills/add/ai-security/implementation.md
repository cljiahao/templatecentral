<!-- ref: add/ai-security/implementation.md
     loaded-by: add/SKILL.md
     prereq: Stack identified. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
---

## Checklist

Apply by capability tier: **A** (simple) LLM01, 02, 03, 05, 07, 09, 10. **B** (RAG) adds LLM04 and LLM08. **LLM06 applies as soon as any tool, function or plugin is wired**, not only in agent setups. **C** (agentic) adds the Agentic list below. Nothing seeded scans prompts for injection (`user-prompt-guard` checks inline credentials only), so LLM01 is code you write.

### LLM01 — Prompt injection
- User content stays in `user`-role messages, never concatenated into the system prompt: the one structural control a filter cannot replace.
- A denylist of override phrases is a first layer only; keep it narrow (bare words like "disregard" reject ordinary input) and cap input length.
- The model gets no authority to change its own instructions or call high-privilege tools without an out-of-band gate.

### LLM02 — Sensitive information disclosure
- Strip PII and credentials before the prompt leaves your process; set the national-ID pattern to your locale, and run it last because bare digits swallow card and phone numbers.
- Log only `request_id`, `model`, `token_count`, `duration_ms`: raw prompts and completions hold user data.
- Confirm the provider's terms on logging and training before sending sensitive data.

### LLM03 — Supply chain
- Pin a dated model snapshot, never a floating alias: behaviour changes without notice.
- Self-hosted weights: verify the provider's published checksum and use formats that cannot execute code on load.
- Files uploaded for model processing get the upload rules in `<skill-dir>/../standards/validation-patterns/patterns.md` (rule 5).

### LLM04 — Data and model poisoning (RAG, fine-tuning)
- Store a source and sha256 per ingested chunk so a poisoned source can be purged.
- Alert when the refusal rate drifts far from a baseline taken on clean data.

### LLM05 — Improper output handling
- Model output is untrusted input: never `eval`, exec or render it as raw HTML. Sanitise with a real sanitiser (regex-stripping HTML is bypassable) or render as text.
- Validate every response against a Zod or Pydantic schema, as for any external API.

### LLM06 — Excessive agency
- Explicit tool allowlist; irreversible tools (send, delete, submit) need human confirmation.
- Cap agent steps so a loop cannot run unbounded.

### LLM07 — System prompt leakage
- Treat the system prompt as public: no credentials, internal URLs or secrecy-dependent rules.
- Assemble it server-side, never through client code or `NEXT_PUBLIC_*` / `VITE_*` variables.

### LLM08 — Vector and embedding weaknesses (RAG)
- Filter by user or tenant metadata inside the vector query. Filtering after retrieval has already exposed the documents to the model.

### LLM09 — Misinformation
- Instruct the model to answer from context only and admit uncertainty.
- High-stakes domains (medical, legal, financial): human review or a source citation before the user sees it.
- Keep a small evaluation set and re-run it when the model, prompt or retrieval changes; tell users where AI output is shown that it can be wrong.

### LLM10 — Unbounded consumption
- Set a token cap on every call. The parameter name differs by provider (`max_completion_tokens` on newer OpenAI models; `max_tokens` is required by Anthropic's Messages API).
- Rate-limit per authenticated user id (not IP), server-side, reusing the project's auth rate limiter or the gateway.
- Document `AI_MAX_TOKENS_PER_REQUEST`, `AI_MAX_REQUESTS_PER_USER_PER_MINUTE` and the provider key names (values blank) in `.env.example`.

## Agentic applications (capability C)

Apply the OWASP Top 10 for Agentic Applications (ASI01–ASI10) with **least agency**: scope tools and credentials per agent, never globally. Three that are easy to miss:
- **ASI03** — re-check authority at every delegation boundary.
- **ASI04** — allowlist MCP and tool-server connections, pin and verify external tool and schema versions, and re-verify on runtime discovery.
- **ASI06** — validate memory reads and keep long-term memory out of prompt construction.

## Rules

- Document the AI feature's data flow in the project's `AGENTS.md` under "Architecture Decisions".
