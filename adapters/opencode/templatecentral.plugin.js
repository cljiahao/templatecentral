// templatecentral.plugin.js — OpenCode adapter for templateCentral's in-agent harness guards.
//
// Claude Code is templateCentral's primary target; its in-agent guards live in `.claude/hooks/`
// (see scaffold/shared/harness-kit.md). This plugin ports the cleanly-mappable guards to OpenCode's
// plugin API so an OpenCode / OpenChamber user gets the same live protection. The git-hook + CI half
// of the harness (lefthook, gitleaks, the CI workflow) is already tool-agnostic and needs no adapter.
//
// Guard parity with the Claude Code hooks:
//   • bash-command guard   (← block-no-verify.sh, PreToolUse Bash)  — hard-block, throws
//   • protected-file guard (← protect-files.sh,   PreToolUse Edit|Write) — hard-block, throws
//   • typecheck-on-edit    (← post-edit-typecheck.sh, PostToolUse)  — feedback only, never blocks
//
// Not ported (no clean OpenCode equivalent yet — documented in adapters/opencode/README.md):
//   • Stop test-gate (stop-checks.sh) — OpenCode has no blocking end-of-turn plugin hook.
//   • SubagentStop type-gate, SessionStart context re-injection.
//
// Install: see adapters/opencode/README.md. OpenCode loads config once at startup — restart after
// installing. Arg key names below are read defensively because OpenCode's internal tool-arg shape
// can shift between versions; the README includes a live smoke test to confirm them.

const PROTECTED_BRANCHES = ["main", "uat", "develop"];

// IMPORTANT: keep the helpers below UN-exported. OpenCode treats EVERY named export of a plugin
// module as a plugin factory and invokes it with a plugin-input object — exporting a plain helper
// makes OpenCode call e.g. bashCommandReason(input) and crash with "failed to load plugin". Only
// `export default` (the factory at the bottom) may be exported. Tests drive the default export's
// hooks (see hooks.test.mjs); they must NOT import named helpers from this file.

// ── protected-file guard (port of protect-files.sh) ───────────────────────────
// Returns a block reason string, or null to allow. Mirrors the hard-block set; governance files
// (AGENTS.md, CONSTITUTION.md, settings, hooks, Dockerfile, lefthook/gitleaks) are also hard-blocked
// here with a "confirm with a human" message — OpenCode plugins can't raise Claude Code's softer
// "ask" prompt mid-tool, so the safe default is to block and let the human re-run intentionally.
function protectedFileReason(filePath, root) {
  if (!filePath) return null;
  const base = filePath.split("/").pop();
  // Hard block: .env* except committed templates.
  if (base.startsWith(".env") && base !== ".env.example" && base !== ".env.default") {
    return `writing ${base} is not allowed — add placeholders to .env.example; keep real secrets out of the repo`;
  }
  const rel = root && filePath.startsWith(root + "/") ? filePath.slice(root.length + 1) : filePath;
  if (rel.startsWith(".github/workflows/") || rel.startsWith(".github/actions/") || rel.startsWith(".azuredevops/") ||
      base === "azure-pipelines.yml" || /^azure-pipelines.*\.ya?ml$/.test(base) ||
      base === ".gitlab-ci.yml" || base === "Jenkinsfile") {
    return `${rel} is a CI/CD pipeline definition (GitHub / Azure DevOps / GitLab / Jenkins) — requires human review`;
  }
  if (rel.startsWith("secrets/") || rel.startsWith(".secrets/")) return `${rel} is inside a secrets directory — must never be written by the agent`;
  if (/\.(pem|key|p12|pfx|secret)$/.test(rel) || base === "credentials.json" || base === ".netrc" || base === ".secrets") {
    return `${rel} is a certificate or credential file — must never be committed`;
  }
  const governance = [
    [/(^|\/)AGENTS\.md$|(^|\/)CLAUDE\.md$/, "agent instruction file — prompt-injection attack surface"],
    [/(^|\/)docs\/CONSTITUTION\.md$/, "binding invariants document — affects all agents"],
    [/(^|\/)\.claude\/settings\.json$/, "harness config — editing it can silently disable every hook"],
    [/(^|\/)\.claude\/hooks\//, "enforcement hook script — editing it can weaken a guard"],
    [/(^|\/)\.claude\/(harness\.json|verify-harness\.sh|regen-harness\.sh)$/, "harness integrity baseline/verifier"],
    [/(^|\/)Dockerfile$/, "container image definition"],
    [/(^|\/)(lefthook\.yml|\.gitleaks\.toml)$/, "git-hook enforcement config"],
    [/(^|\/)\.lefthook\//, "git-hook script — editing it can weaken commit-time guards"],
  ];
  for (const [re, why] of governance) {
    if (re.test(rel)) return `PROTECTED FILE: ${rel} — ${why}. Confirm human approval before editing (re-run intentionally).`;
  }
  return null;
}

// ── bash-command guard (port of block-no-verify.sh) ───────────────────────────
// `branch` is the current git branch (or "") so the protected-branch check works without a subprocess
// inside the regex logic. Returns a block reason string, or null to allow.
function bashCommandReason(cmd, branch) {
  if (!cmd) return null;
  // Scrub quoted strings (e.g. commit messages) so text inside -m "..." can't false-trigger flags.
  const scan = cmd.replace(/'[^']*'/g, "").replace(/"[^"]*"/g, "");

  if (/git\s+commit/.test(scan) && /--no-verify|\s-[a-zA-Z]*n/.test(scan)) {
    return "--no-verify (or -n) on git commit bypasses the pre-commit hooks. Fix the failure instead.";
  }
  // Equivalent full bypasses of the pre-commit hook layer: LEFTHOOK=0 / LEFTHOOK_EXCLUDE env-var
  // assignment, and `git -c core.hooksPath=...` override (same effect as --no-verify).
  if (/\bgit\b/.test(scan) && /\bcommit\b/.test(scan) && /(^|\s)LEFTHOOK(_EXCLUDE)?=|core\.hooksPath\s*=/.test(scan)) {
    return "LEFTHOOK=0 / LEFTHOOK_EXCLUDE / 'git -c core.hooksPath=...' disables the pre-commit hook layer — the same bypass as --no-verify. Fix the failure instead.";
  }
  if (/git\s+commit/.test(cmd) && PROTECTED_BRANCHES.includes(branch)) {
    return `direct commit to protected branch '${branch}'. Create a feature branch first.`;
  }
  if (/git\s+push/.test(cmd) &&
      ((/--force([\s=]|$)|\s-[a-z]*f/.test(cmd) && /\b(main|uat|develop)\b/.test(cmd)) ||
       /\s\+(main|uat|develop)\b/.test(cmd))) {
    return "force-push to a protected branch (--force/-f or +refspec). Open a PR instead.";
  }
  if (/git\s+(checkout|restore)\b/.test(cmd) &&
      /(^|\s)(\.claude\/|\.lefthook\/|\.github\/|lefthook\.yml|\.gitleaks\.toml|AGENTS\.md|CLAUDE\.md|docs\/CONSTITUTION\.md)/.test(cmd)) {
    return "'git checkout/restore' on a guard-layer file discards enforcement config. Confirm with a human first.";
  }
  if (/(^|\s)rm(\s|$)/.test(cmd) && /\s-[a-zA-Z]*r|\s--recursive/.test(cmd) &&
      /\s-[a-zA-Z]*f|\s--force/.test(cmd) &&
      /(^|[\s/"])(src|app|lib|test|\.claude|\.lefthook|\.git|node_modules)([\s/"]|$)/.test(cmd)) {
    return "recursive rm on a source directory. Confirm with a human first.";
  }
  return null;
}

// Pick the type-check command for the project (feedback only).
async function typecheckCommand($, directory) {
  try {
    const hasPkg = await $`test -f ${directory}/package.json`.then(() => true).catch(() => false);
    if (hasPkg) return ["pnpm", "exec", "tsc", "--noEmit"];
    const hasPy = await $`test -f ${directory}/pyproject.toml`.then(() => true).catch(() => false)
      || await $`test -f ${directory}/requirements.txt`.then(() => true).catch(() => false);
    if (hasPy) return ["python", "-m", "pyright", "src/"];
  } catch { /* ignore */ }
  return null;
}

export default async ({ directory, $ }) => {
  const root = directory || ".";
  return {
    // PreToolUse equivalent — runs before the tool; throwing aborts the tool call.
    // Keyed on the SHAPE of the tool args (presence of a command string / a file path), NOT on the
    // tool name — OpenCode's tool names vary by version, so name-gating silently misses calls. This
    // mirrors the proven args-based approach used by env-protection-style plugins.
    "tool.execute.before": async (_input, output) => {
      const args = output?.args || {};
      const command = args.command || args.cmd;
      const file = args.filePath || args.path || args.file_path;
      // Bash-command guard
      if (typeof command === "string" && command) {
        let branch = "";
        try { branch = (await $`git -C ${root} rev-parse --abbrev-ref HEAD`.text()).trim(); } catch { /* not a repo */ }
        const reason = bashCommandReason(command, branch);
        if (reason) throw new Error(`[templatecentral] BLOCKED: ${reason}`);
      }
      // Protected-file guard
      if (typeof file === "string" && file) {
        const reason = protectedFileReason(file, root);
        if (reason) throw new Error(`[templatecentral] BLOCKED: ${reason}`);
      }
    },
    // PostToolUse equivalent — type feedback after a file write. Never blocks (best-effort).
    "tool.execute.after": async (_input, output) => {
      const file = output?.args?.filePath || output?.args?.path || output?.args?.file_path;
      if (typeof file !== "string" || !file) return; // only after a file-writing tool
      const cmd = await typecheckCommand($, root);
      if (!cmd) return;
      try {
        await $`${cmd}`.cwd(root).quiet();
      } catch (e) {
        // Surface type errors as feedback; do not throw (matches the CC feedback-only hook).
        const out = (e?.stderr || e?.stdout || e?.message || "").toString().slice(0, 4000);
        if (out) console.error(`[templatecentral] typecheck feedback:\n${out}`);
      }
    },
  };
};
