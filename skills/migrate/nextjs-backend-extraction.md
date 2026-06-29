<!-- ref: migrate/nextjs-backend-extraction.md
     loaded-by: migrate/SKILL.md
     prereq: User wants to extract Next.js API routes to a dedicated backend service. Do not invoke this file directly. -->

# Next.js Backend Extraction — Target Router

Determine which backend the user wants to migrate to, then load the full migration guide.

## Step 1 — Identify the target backend

Read the user's request for clues:
- "NestJS" or "Nest" → target: **NestJS**
- "FastAPI", "fastapi", or "Python" → target: **FastAPI**

If the target is unclear, ask:
> "Which backend do you want to extract to? (NestJS / FastAPI)"

## Step 2 — Route to the correct leaf

| Target | Command |
|---|---|
| NestJS | `cat "<skill-dir>/nextjs-backend-extraction/nestjs.md"` |
| FastAPI | `cat "<skill-dir>/nextjs-backend-extraction/fastapi.md"` |
| Other | Respond: "Not yet supported. Supported targets: NestJS, FastAPI." Exit without changes. |

## Step 3 — Execute

Follow the loaded guide exactly.
