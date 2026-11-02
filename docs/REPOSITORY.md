# Repository structure

Layout of the templatecentral repo. Back to the [README](../README.md).

```
templatecentral/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest (points to skills/)
│   └── marketplace.json     # Marketplace manifest (`claude plugin marketplace add`)
├── .github/workflows/       # CI — skill lint + manifest, scaffold parse/verify, AI review, ecosystem refresh, dist build, release
├── scripts/
│   ├── lint-skills.sh       # Mechanical pattern checks for all skill files
│   ├── validate-manifest.sh # Validates plugin.json + marketplace.json before publish
│   ├── validate-scaffold-configs.sh # Parses the JSON/JS config files under skills/scaffold/<stack>/template/ and the shared settings trees
│   ├── test-harness-kit.sh  # Regression suite for the hooks and gates under skills/scaffold/shared/template*/
│   ├── test-template-copy.sh # Tests for the copy script (skills/scaffold/shared/tc-copy.sh) and the template trees
│   ├── lint-skills.test.sh  # Negative tests for the lint checks that read the template trees
│   ├── check-fences.py/.sh  # Fence snapshot: every copy-verbatim fence, or the template file that replaced it, matches tests/golden/fences/
│   ├── check-fences-frozen.sh # Fails a PR that edits the fence snapshot (label `fence-snapshot-change` to allow)
│   ├── check-fences.test.sh, check-fences-frozen.test.sh # Tests for the two fence checks
│   ├── check-golden.sh      # Seeded scaffold output matches tests/golden/*.sha256 (check-golden.test.sh tests it)
│   ├── count-load.sh        # Token load per scaffold stack and per add/migrate/standards entry (count-load.test.sh tests it)
│   ├── extract-fences.py    # Extracts scaffold fences into a file tree (golden and hook tests; extract-fences.test.sh tests it)
│   ├── check-research-content.py # Validates the ecosystem-refresh output before its PR opens (check-research-content.test.sh tests it)
│   ├── build-agents-dist.sh # Builds the namespace-free copy for other agent tools
│   ├── pre-guard.sh         # Repo guard: blocks secret access, asks before instruction/CI edits
│   ├── bash-guard.sh        # Repo guard: blocks shell reads/writes of secret files
│   ├── post-edit-lint.sh    # Repo hook: lint feedback after skill edits
│   └── pre-guard.test.sh    # Tests for both repo guards
├── skills/                  # Shipped skills — nested reference file architecture
│   ├── scaffold/shared/template*/ # Files the scaffold copies verbatim: hooks, gates, lefthook, CI (template/, template-ts/, template-py/, template-ci/)
│   ├── scaffold/shared/tc-copy.sh # The one script that copies the template trees (and appends the AGENTS.md tail); the kit runs it, never reads it. add/migrate leaves run it with TC_PART=leaf
│   ├── scaffold/shared/template.manifest # Every template file with its mode
│   ├── scaffold/shared/template-{settings-ts,settings-py,late,tail}/ # settings.json (copied at Step A), FUTURE.md + CONSTITUTION + /skill-audit (copied at Step C), and the AGENTS.md tail (appended at Step G, never copied)
│   ├── scaffold/nextjs/template*/ # The Next.js files the scaffold copies verbatim (template/, template-agents/ = AGENTS.md, template-tail/ = text appended on request) plus scaffold/nextjs/template.manifest
│   ├── scaffold/nestjs/template*/ # The NestJS files the scaffold copies verbatim (template/, template-agents/ = AGENTS.md, template-tail/ = text appended on request) plus scaffold/nestjs/template.manifest
│   ├── scaffold/fastapi/template*/ # The FastAPI files the scaffold copies verbatim (same three trees) plus scaffold/fastapi/template.manifest
│   ├── scaffold/vite-react/template*/ # The same trees for Vite + React, plus scaffold/vite-react/template.manifest
│   ├── add/<capability>/<leaf>/template*/ # Files an add leaf copies verbatim (e.g. add/auth/nestjs/template/, template-cookie/), plus the leaf's template.manifest
│   ├── migrate/database/<stack>/template/ # Files a migrate leaf copies verbatim, plus its template.manifest
│   ├── CONVENTIONS.md       # Single source of truth for skill authoring rules
│   ├── scaffold/SKILL.md    # Router → skills/scaffold/<stack>/
│   ├── add/SKILL.md         # Router → skills/add/<capability>/<stack>.md
│   ├── standards/SKILL.md   # Router → skills/standards/<check>/
│   ├── migrate/SKILL.md     # Router → skills/migrate/<type>/
│   ├── build/               # (de-registered utility) detect stack + run build command
│   ├── test/                # (de-registered utility) write and run tests
│   ├── review/              # (de-registered utility) code review + dependency updates
│   └── cleanup/             # (de-registered utility) remove example code / task scaffolding
├── adapters/opencode/       # OpenCode plugin porting the in-agent guards
├── docs/CROSS-TOOL.md       # Running the skills outside Claude Code
├── tests/golden/            # Golden sha256 manifests per stack x CI host, and the fence snapshot (fences/, fences/moved.d/)
├── .claude/rules/           # Per-stack version floors and boundaries (the floor of record)
├── .claude/skills/          # Repo-internal contributor skills (NOT shipped to installs)
│   ├── tc-audit/            # /tc-audit — full ecosystem + accuracy audit
│   └── tc-write-skill/      # /tc-write-skill — skill authoring checklist
├── AGENTS.md                # Agent orchestration guide
└── CHANGELOG.md             # Full version history
```

## Scheduled loops

- **`scaffold-verify`** (monthly) — scaffolds a test project from each template and runs its build + test gate, catching regressions before they reach users.
- **`ecosystem-refresh`** (paused) — re-scans framework release notes, library changelogs and security advisories, then opens a PR updating `.claude/audit-ecosystem-research.md`. The research agent runs read-only with no shell; a separate job with no AI in it validates the output and opens the PR. While paused, maintainers refresh the research file by hand, and `/tc-audit` re-scans when it is more than 30 days old.

Both need an `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` repository secret (they skip cleanly without one). See [CONTRIBUTING.md](../CONTRIBUTING.md).


## Adding a new skill

1. Read `skills/CONVENTIONS.md` — it defines all nesting rules, description limits, and ref header formats
2. Use `/tc-write-skill` — it walks through the authoring checklist and validates your skill before you open a PR
3. If adding a new stack, create `.claude/rules/<stack>.md`
4. Run `bash scripts/lint-skills.sh skills/` and `bash scripts/validate-manifest.sh` locally — both must pass
5. Open a PR — CI will run both scripts automatically

> **Contributor-only skills.** `/tc-write-skill` (authoring) and `/tc-audit` (full ecosystem + accuracy audit) live in this repo under `.claude/skills/` and are available as project skills when you clone and open the repo. They are **not** shipped to installed projects — end users never carry the plugin's maintenance tooling.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the full guide.

