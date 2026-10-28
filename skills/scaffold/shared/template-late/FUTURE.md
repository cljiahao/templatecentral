# Future Directions

Design seams built into this project for AI collaboration patterns that are not yet activated. These are integration points, not features — nothing here runs unless you build it.

## Meta-Harness

CI that validates this project's own harness: a job that scaffolds the project and asserts the output passes tests and lint. Most near-term post-harness direction.

**Seam:** `<!-- [[post-harness:meta]] -->` in `AGENTS.md` — reserved for meta-harness CI configuration.

## Trace-Driven Evolution

Capture agent decision traces across sessions, aggregate patterns, and use them to improve conventions over time. Off by default.

**Seam:** None yet — no trace hook exists in the seeded `.claude/settings.json` (it is comment-free JSON with no disabled/placeholder entries). This is a roadmap item: a future revision could add a dedicated hook (e.g. a `Stop` or `SessionEnd` trace-writer) once a concrete consumer for the captured traces is designed. Until then, treat this as unactivated design intent, not an existing seam.

## Environment Engineering

A fully specified, reproducible environment ensuring every agent session starts from the same known state. Think devcontainers or Nix flakes with agent-specific overlays.

**Seam:** `devcontainer.json` if present.

---

*Seams from [templateCentral](https://github.com/cljiahao/templatecentral). None activated.*
