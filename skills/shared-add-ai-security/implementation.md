<!-- ref: shared-add-ai-security/implementation.md
     loaded-by: shared-add-ai-security/SKILL.md
     prereq: Stack identified. Do not invoke this file directly — it is loaded at runtime by the shared-add-ai-security skill. -->
## Step 0 — Verify context

Look for `<!-- templateCentral:` anywhere in `AGENTS.md`.

If found → proceed to the stack-specific implementation below.

If not found → invoke `templatecentral:shared-migrate`. Once complete, re-check for
the marker.
- Marker now present → proceed below.
- Still absent (user chose to stop) → exit. Do not generate any files.

---

## Controls (apply all that are relevant to the chosen capability)

### LLM01 — Prompt Injection

User-supplied content must never be concatenated directly into a system prompt.

**Pattern — wrap user input with a trust boundary marker:**

```ts
// ❌ Never: direct interpolation
const prompt = `You are a helpful assistant. User says: ${userMessage}`;

// ✅ Always: labelled boundary so the model knows what is user content
const prompt = [
  { role: 'system', content: systemPrompt },
  { role: 'user', content: userMessage },  // model sees this as untrusted input
];
```

**Validation gate** — reject inputs that attempt to override instructions:

```ts
const INJECTION_PATTERNS = [
  /ignore (previous|above|all) instructions/i,
  /system prompt/i,
  /you are now/i,
  /disregard/i,
];

export function validateUserPrompt(input: string): void {
  if (input.length > 4000) throw new Error('Input exceeds maximum length');
  for (const pattern of INJECTION_PATTERNS) {
    if (pattern.test(input)) throw new Error('Input contains disallowed content');
  }
}
```

```python
# Python equivalent
INJECTION_PATTERNS = [
    r'ignore (previous|above|all) instructions',
    r'system prompt',
    r'you are now',
    r'disregard',
]

def validate_user_prompt(text: str) -> None:
    if len(text) > 4000:
        raise ValueError("Input exceeds maximum length")
    for pattern in INJECTION_PATTERNS:
        if re.search(pattern, text, re.IGNORECASE):
            raise ValueError("Input contains disallowed content")
```

---

### LLM02 — Sensitive Information Disclosure

Never allow PII or credentials to enter LLM context. Strip before sending.

```ts
// Redact common PII patterns before sending to the model
const PII_PATTERNS: Array<[RegExp, string]> = [
  [/\b\d{6,12}\b/g, '[NATIONAL-ID]'],                            // National ID — adapt regex to your jurisdiction's format
  [/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/g, '[CARD]'],   // Credit card
  [/\b[\w.+-]+@[\w-]+\.\w{2,}\b/g, '[EMAIL]'],
  [/\b\+?\d{1,3}[\s-]?\d{3,5}[\s-]?\d{4,8}\b/g, '[PHONE]'],    // International phone — adapt to expected formats
];

export function redactPII(text: string): string {
  return PII_PATTERNS.reduce((t, [pattern, replacement]) =>
    t.replace(pattern, replacement), text);
}
```

**Rule**: Log only `request_id`, `model`, `token_count`, `duration_ms` — never log the raw prompt or completion.

---

### LLM03 — Supply Chain

Pin model identifiers explicitly. Never use `latest` or version-free aliases in production.

```ts
// ❌ Never
const model = 'gpt-4o';  // bare alias — behaviour changes without notice

// ✅ Always — pin a specific dated snapshot from your provider's model catalogue
const model = 'gpt-4o-2024-08-06';  // example only — use your provider's current snapshot
```

For open-source / self-hosted models: verify checksums against the provider's published hash before loading.

---

### LLM05 — Improper Output Handling

Treat all LLM output as untrusted user input. Never evaluate, exec, or render it directly.

```ts
// ❌ Never render raw LLM output as HTML
return <div dangerouslySetInnerHTML={{ __html: llmOutput }} />;

// ✅ Sanitise or use text-only rendering
import DOMPurify from 'dompurify';
return <div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(llmOutput) }} />;

// ✅ Or use a markdown renderer with sanitisation (e.g. react-markdown with rehype-sanitize)
```

**Structured output** — use schema validation on model responses:

```ts
import { z } from 'zod';

const AnswerSchema = z.object({
  answer: z.string().max(2000),
  confidence: z.number().min(0).max(1),
  sources: z.array(z.url()).max(5),
});

const raw = await openai.chat.completions.create({ ... });
const parsed = AnswerSchema.safeParse(JSON.parse(raw.choices[0].message.content ?? '{}'));
if (!parsed.success) throw new Error('Model returned invalid structure');
```

```python
# Python equivalent using Pydantic
from pydantic import BaseModel, HttpUrl
from typing import Annotated
from annotated_types import Len

class AnswerResponse(BaseModel):
    answer: Annotated[str, Len(max_length=2000)]
    confidence: float
    sources: list[HttpUrl]

import json
raw = client.chat.completions.create(...)
parsed = AnswerResponse.model_validate(json.loads(raw.choices[0].message.content or "{}"))
```

---

### LLM06 — Excessive Agency (Agentic systems only — Capability C)

Every tool the agent can call must have an explicit allowlist. Irreversible actions need a human-in-the-loop gate.

```ts
// Define an explicit tool allowlist — never allow open-ended shell execution
const ALLOWED_TOOLS = new Set(['search_web', 'read_document', 'create_draft']);

export function validateToolCall(toolName: string): void {
  if (!ALLOWED_TOOLS.has(toolName)) {
    throw new Error(`Tool "${toolName}" is not in the allowlist`);
  }
}

// Irreversible actions require confirmation before execution
const IRREVERSIBLE_TOOLS = new Set(['send_email', 'delete_record', 'submit_form']);

export async function executeToolWithGate(
  toolName: string,
  args: unknown,
  confirmFn: (name: string, args: unknown) => Promise<boolean>
): Promise<unknown> {
  if (IRREVERSIBLE_TOOLS.has(toolName)) {
    const confirmed = await confirmFn(toolName, args);
    if (!confirmed) throw new Error('Tool execution cancelled by user');
  }
  return executeTool(toolName, args);
}
```

**Max steps guard** — prevent infinite loops:

```ts
const MAX_AGENT_STEPS = 10;
let steps = 0;

while (agentNeedsMoreSteps && steps < MAX_AGENT_STEPS) {
  steps++;
  // ... agent step
}

if (steps >= MAX_AGENT_STEPS) {
  logger.warn({ steps }, 'Agent reached max steps — halting');
}
```

---

### LLM08 — Vector & Embedding Weaknesses (RAG only — Capability B)

Apply the same access controls to retrieved documents as to direct data access.

```ts
// ❌ Never: retrieve then filter — data is already exposed to the model
const allDocs = await vectorDB.query(embedding);
const authorizedDocs = allDocs.filter(d => userCanAccess(d, userId));

// ✅ Always: filter at query time using metadata
const docs = await vectorDB.query(embedding, {
  filter: { userId },      // push access control into the vector DB query
  topK: 5,
});
```

---

### LLM10 — Unbounded Consumption

Every LLM call must have explicit token limits and a per-user rate limit.

```ts
// Always set max_tokens — never allow uncapped completions
const response = await openai.chat.completions.create({
  model: 'gpt-4o-2024-08-06',  // example only — use your provider's current snapshot
  messages,
  max_tokens: 1000,    // explicit cap — never omit
  temperature: 0.7,
});

// Per-user rate limiting
// Use @upstash/ratelimit or infrastructure-layer rate limiting
```

**Environment variables to document in `.env.example`:**

```
# AI provider keys — never commit real values
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
AWS_BEDROCK_REGION=

# Token budgets
AI_MAX_TOKENS_PER_REQUEST=1000
AI_MAX_REQUESTS_PER_USER_PER_MINUTE=10
```

---

## Hardcoded Prohibitions

Regardless of capability or environment, **never**:

- Log raw prompts or completions (contain user data / PII)
- Store API keys in client-side code (`NEXT_PUBLIC_*`, `VITE_*`)
- Render LLM output as raw HTML without sanitisation
- Execute LLM-generated code without a human review gate
- Use `latest` model aliases in production — always pin snapshots
- Allow unrestricted tool calling without an explicit allowlist (agentic)

---

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate the project still compiles
2. `shared-review-agent` — check code standards and security patterns

## AWS Responsible AI Lens

The AWS Responsible AI Lens (re:Invent 2025) defines 10 dimensions for evaluating production AI systems. Use it alongside OWASP LLM Top 10 for pre-launch reviews:

- **Controllability** — ability to override, retrain, or shut down the model
- **Privacy** — data minimization, consent, and PII handling
- **Security** — prompt injection, adversarial input, model extraction defense
- **Safety** — preventing harmful outputs across user populations
- **Veracity** — factual accuracy, hallucination detection, grounding
- **Robustness** — performance under distribution shift and edge inputs
- **Fairness** — equitable outcomes across demographic groups
- **Explainability** — traceability from input to output decision
- **Transparency** — disclosure of AI involvement to end users
- **Governance** — audit trails, policy enforcement, accountability

No single framework covers everything — OWASP LLM Top 10 focuses on attack vectors; the Responsible AI Lens focuses on systemic trustworthiness. Run both checklists before shipping AI features to production.

For Capability C (agentic systems), also apply the **OWASP Top 10 for Agentic Applications (2026)** — a separate framework covering multi-agent orchestration risks such as privilege escalation across agent boundaries, plan hijacking, and unsafe memory persistence. The LLM Top 10 covers model-layer risks; the Agentic Top 10 covers orchestration-layer risks that emerge when agents chain actions autonomously.

## Rules

- Apply controls proportional to capability: A (simple) needs LLM01, 02, 05, 10; B (RAG) adds LLM08; C (agentic) adds LLM06 + OWASP Agentic Top 10
- Use structured output validation (Zod/Pydantic) on every model response — treat it like an external API
- Document the AI feature's data flow in the project's `AGENTS.md` under "Architecture Decisions"

## Changelog
### 1.1.0
- Added OWASP Top 10 for Agentic Applications (2026) reference for Capability C systems
### 1.0.0
- Initial release — OWASP LLM Top 10 v2.0 controls for A/B/C AI capability tiers
