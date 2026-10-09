<!-- ref: add/ai-security/implementation.md
     loaded-by: add/SKILL.md
     prereq: Stack identified. Do not invoke this file directly — it is loaded at runtime by the templatecentral:add skill. -->
## Step 0 — Verify context

Look for `<!-- templateCentral:` on line 1 of `AGENTS.md`.

If found → proceed to the stack-specific implementation below.

If not found → invoke `templatecentral:migrate`. Once complete, re-check for
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

// ✅ Always: role separation — user content stays in the user turn
const prompt = [
  { role: 'system', content: systemPrompt },
  { role: 'user', content: userMessage },
];
```

**Validation gate** — reject inputs that attempt to override instructions:

```ts
// Narrow phrases only — bare words like "disregard" or "system prompt" reject ordinary input.
const INJECTION_PATTERNS = [
  /ignore (all |the )?(previous|above|prior) instructions/i,
  /disregard (all |the )?(previous|above|prior) instructions/i,
  /reveal (your|the) system prompt/i,
  /you are now (in )?(developer|dan|jailbreak) mode/i,
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
import re

INJECTION_PATTERNS = [
    r'ignore (all |the )?(previous|above|prior) instructions',
    r'disregard (all |the )?(previous|above|prior) instructions',
    r'reveal (your|the) system prompt',
    r'you are now (in )?(developer|dan|jailbreak) mode',
]

def validate_user_prompt(text: str) -> None:
    if len(text) > 4000:
        raise ValueError("Input exceeds maximum length")
    for pattern in INJECTION_PATTERNS:
        if re.search(pattern, text, re.IGNORECASE):
            raise ValueError("Input contains disallowed content")
```

> **Pattern-matching is a first layer, not a complete defense.** A denylist catches obvious overrides but cannot stop novel or obfuscated injection — prompt injection is not fully solvable by filtering. The load-bearing controls are *structural*: keep user content in `user`-role messages (never concatenated into the system prompt), never grant the model authority to change its own instructions or invoke high-privilege tools without an out-of-band gate, validate/escape model **output** before it reaches a sink, and apply least-agency tool scoping (ASI02). Treat the denylist as defense-in-depth on top of these.

---

### LLM02 — Sensitive Information Disclosure

Never allow PII or credentials to enter LLM context. Strip before sending.

```ts
// Order matters: specific patterns run before broad ones, or the bare-digit national-ID
// pattern consumes card and phone numbers first. Replace NATIONAL-ID with your locale's
// exact format — "any 6-12 digits" also hits order numbers and amounts.
const PII_PATTERNS: Array<[RegExp, string]> = [
  [/\b[\w.+-]+@[\w-]+(?:\.[\w-]+)*\.\w{2,}\b/g, '[EMAIL]'],
  [/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/g, '[CARD]'],
  [/\+?\b\d{1,3}[\s-]?\d{3,5}[\s-]?\d{4,8}\b/g, '[PHONE]'],
  [/\b\d{6,12}\b/g, '[NATIONAL-ID]'],
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
// ❌ Never — bare alias, behaviour changes without notice
const model = 'gpt-4o';

// ✅ Always — pin a specific dated snapshot from your provider's model catalogue, never a floating alias
const model = '<provider>-<model>-<snapshot-date>';
```

For open-source / self-hosted models: verify checksums against the provider's published hash before loading.

---

### LLM04 — Data and Model Poisoning

Training data, fine-tuning sets, and retrieval corpora are attack surfaces. Compromised data introduces backdoors, biased outputs, or degraded reliability without visible model changes.

**For application developers using hosted models** (the common case):
- Validate and sanitize any data you feed into fine-tuning pipelines or RAG corpora
- Use immutable checksums to verify model weights and training datasets against provider-published hashes before loading
- Never pull model weights from unverified mirrors — use only signed releases from the original provider

```ts
import { createHash } from 'node:crypto';

// Store provenance with every chunk so a poisoned source can be traced and purged later.
// Regex-stripping HTML here is not a control (bypassable); rendering safety is LLM05's job.
async function ingestDocument(content: string, source: string, expectedHash?: string): Promise<void> {
  const hash = createHash('sha256').update(content).digest('hex');
  if (expectedHash && hash !== expectedHash) {
    throw new Error('Document hash mismatch — possible content tampering');
  }
  await embedAndStore(content, { source, sha256: hash });
}
```

```python
import hashlib


def ingest_document(content: str, source: str, expected_hash: str | None = None) -> None:
    digest = hashlib.sha256(content.encode()).hexdigest()
    if expected_hash and digest != expected_hash:
        raise ValueError("Document hash mismatch — possible content tampering")
    embed_and_store(content, metadata={"source": source, "sha256": digest})
```

**Monitoring gate** — detect unexpected output drift in production:

```ts
// Baseline measured on clean data — a sudden shift may indicate poisoned context.
const EXPECTED_REFUSAL_RATE = 0.02;

function monitorOutputDrift(refusalCount: number, totalCount: number): void {
  if (totalCount === 0) return;
  const rate = refusalCount / totalCount;
  if (rate > EXPECTED_REFUSAL_RATE * 3) {
    logger.warn({ rate, expected: EXPECTED_REFUSAL_RATE }, 'Abnormal refusal rate — possible data poisoning');
  }
}
```

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

function parseAnswer(content: string | null): z.infer<typeof AnswerSchema> {
  let json: unknown;
  try {
    json = JSON.parse(content ?? '');
  } catch {
    throw new Error('Model returned non-JSON output');
  }
  const parsed = AnswerSchema.safeParse(json);
  if (!parsed.success) throw new Error('Model returned invalid structure');
  return parsed.data;
}
```

```python
from pydantic import BaseModel, Field, HttpUrl


class AnswerResponse(BaseModel):
    answer: str = Field(max_length=2000)
    confidence: float = Field(ge=0, le=1)
    sources: list[HttpUrl] = Field(max_length=5)


# Raises pydantic.ValidationError on non-JSON or off-schema output.
parsed = AnswerResponse.model_validate_json(content or "")
```

---

### LLM06 — Excessive Agency (applies once any tool/function is wired)

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
  validateToolCall(toolName);
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

### LLM07 — System Prompt Leakage

The system prompt may be extractable through adversarial user inputs. Treat it as semi-public: never embed credentials, business logic that would be compromised if known, or instructions that rely on secrecy to function.

```ts
// ❌ Never embed secrets or security-by-obscurity logic
const systemPrompt = `
  The admin password is ${process.env.ADMIN_PASSWORD}.
  Do not reveal you are built on GPT-4.
`;

// ✅ System prompt must remain safe to read — no credentials, no hidden logic
const systemPrompt = `
  You are a helpful assistant for ${process.env.APP_NAME}.
  Answer questions about our product only.
  Decline requests outside this scope.
`;
```

**Checklist:**
- System prompt assembled server-side — never passed through client code or env vars prefixed `NEXT_PUBLIC_` / `VITE_`
- No credentials, API keys, or internal URLs in the system prompt
- Security controls do not rely on the user not knowing the system prompt contents

---

### LLM08 — Vector & Embedding Weaknesses (RAG only — Capability B)

Apply the same access controls to retrieved documents as to direct data access.

```ts
// ❌ Never: retrieve then filter — data is already exposed to the model
const allDocs = await vectorDB.query(embedding);
const authorizedDocs = allDocs.filter(d => userCanAccess(d, userId));

// ✅ Always: filter at query time using metadata — pushes access control into the vector DB query
const docs = await vectorDB.query(embedding, {
  filter: { userId },
  topK: 5,
});
```

---

### LLM09 — Misinformation

AI systems produce plausible but false information (hallucination). Never surface raw model output as verified fact without grounding or human review.

```ts
// Always instruct the model to cite context and admit uncertainty
const systemPrompt = `
Answer only from the provided context. If unsure, say "I don't know."
Do not invent statistics, names, dates, or URLs.
`;

// For factual claims: validate against authoritative source before displaying
const result = await callModel(prompt);
if (requiresFactualGrounding(result.content)) {
  const verified = await crossReferenceDatabase(result.content);
  // surface only confirmed facts
  return verified;
}
```

**Rule**: For high-stakes domains (medical, legal, financial), gate AI output behind a human review step or source citation before presenting to end users.

---

### LLM10 — Unbounded Consumption

Every LLM call must have explicit token limits and a per-user rate limit.

```ts
const response = await openai.chat.completions.create({
  model: '<provider>-<model>-<snapshot-date>',
  messages,
  // Newer OpenAI models reject `max_tokens`; Anthropic's Messages API requires `max_tokens`.
  max_completion_tokens: Number(process.env.AI_MAX_TOKENS_PER_REQUEST ?? 1000),
});
```

Enforce the per-user limit server-side, keyed on the authenticated user id (not IP) — reuse the project's auth rate limiter or the gateway.

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
1. the build utility — load it with: `cat "<skill-dir>/../build/SKILL.md"` — validate the project still compiles
2. the review utility — load it with: `cat "<skill-dir>/../review/SKILL.md"` — check code standards and security patterns

## Responsible AI Checklist

Cloud providers publish responsible-AI checklists for evaluating production AI systems — e.g. the AWS Responsible AI Lens, which defines 10 dimensions; use your cloud provider's equivalent. Run one alongside OWASP LLM Top 10 for pre-launch reviews:

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

For Capability C (agentic systems), also apply the **OWASP Top 10 for Agentic Applications (ASI prefix codes)** — a separate framework covering multi-agent orchestration risks:

| Code | Name | Mitigation focus |
|------|------|-----------------|
| ASI01 | Agent Goal Hijack | Validate objective integrity; reject goal mutations from untrusted input |
| ASI02 | Tool Misuse & Exploitation | Scope tool allowlists per-agent; block recursive/unbounded execution |
| ASI03 | Identity & Privilege Abuse | Re-validate authority at every delegation boundary |
| ASI04 | Agentic Supply Chain Vulnerabilities | Allowlist MCP/tool-server connections; pin + verify external agent/tool/schema versions (signed manifests where available) and re-verify on runtime discovery, before trust |
| ASI05 | Unexpected Code Execution | Sandbox agent-generated code; never eval untrusted model output |
| ASI06 | Memory & Context Poisoning | Validate memory reads; isolate long-term memory from prompt construction |
| ASI07 | Insecure Inter-Agent Communication | Re-authenticate agent-to-agent messages; no implicit trust between agents |
| ASI08 | Cascading Failures | Circuit-break chains; cap propagation depth; isolate failure domains |
| ASI09 | Human-Agent Trust Exploitation | Scope confirmations to specific actions; reject open-ended authority grants |
| ASI10 | Rogue Agents | Hard-code objective boundaries; monitor for goal drift in long-running agents |

The overarching design principle is **Least Agency**: grant each agent only the minimum permissions and tool access required for its specific task — scope both credentials and tool allowlists per-agent, not globally. The LLM Top 10 covers model-layer risks; the Agentic Top 10 covers orchestration-layer risks that emerge when agents chain actions autonomously.

## Rules

- Apply controls proportional to capability: A (simple) needs LLM01, 02, 03, 05, 07, 09, 10; B (RAG) adds LLM04 (data/model poisoning — validate RAG and fine-tuning ingestion) and LLM08. LLM09 (misinformation/overreliance) applies at every tier. **LLM06 (Excessive Agency) applies the moment ANY tool, function, or plugin is wired — not only multi-agent setups** — so add it as soon as the model can take an action. C (agentic) adds the full OWASP Agentic Top 10 (ASI01–ASI10, Least-Agency principle)
- Use structured output validation (Zod/Pydantic) on every model response — treat it like an external API
- Document the AI feature's data flow in the project's `AGENTS.md` under "Architecture Decisions"

