// templatecentral.plugin.js — OpenCode adapter for templateCentral's in-agent harness guards.
//
// Ports the cleanly-mappable Claude Code hooks (scaffold/shared/harness-kit.md) to OpenCode's plugin API:
//   • bash-command guard   ← block-no-verify.sh      (PreToolUse Bash)       — hard-block, throws
//   • protected-file guard ← protect-files.sh        (PreToolUse Edit|Write) — hard-block, throws
//   • typecheck-on-edit    ← post-edit-typecheck.sh  (PostToolUse)           — feedback only
// What is not ported, and why, is in adapters/opencode/README.md. Tool-arg key names are read
// defensively because OpenCode's tool-arg shape can shift between versions.
//
// Keep every helper UN-exported: OpenCode treats each named export as a plugin factory and calls it
// with the plugin-input object, so an exported helper crashes plugin loading. Tests drive the
// default export's hooks (hooks.test.mjs).

import path from "node:path";

const PROTECTED = "main|uat|develop";
const PROTECTED_RE = new RegExp(`^(${PROTECTED})$`);
const GIT_HOOK_SUBCOMMANDS = new Set(["commit", "push", "merge", "am", "rebase", "cherry-pick", "revert", "pull"]);
const GUARD_PATH_RE = /(^|\s)(\.\/)?(\.claude\/|\.claude(\s|$)|\.lefthook\/|\.github\/|lefthook\.yml|\.gitleaks\.toml|AGENTS\.md|CLAUDE\.md|docs\/CONSTITUTION\.md)/;

// OpenCode plugins can't raise Claude Code's "ask the human" prompt mid-tool, so governance files
// are hard-blocked with a "confirm and re-run intentionally" message instead.
const GOVERNANCE = [
  [/(^|\/)(agents|claude)\.md$/, "agent instruction file — prompt-injection attack surface"],
  [/(^|\/)docs\/constitution\.md$/, "binding invariants document — affects all agents"],
  [/(^|\/)\.claude\/settings(\.local)?\.json$/, "harness config — editing it can silently disable every hook"],
  [/(^|\/)\.claude\/hooks\//, "enforcement hook script — editing it can weaken a guard"],
  [/(^|\/)\.claude\/agents\//, "agent definition — editing it can alter subagent tool access"],
  [/(^|\/)\.mcp\.json$/, "MCP server config — editing it can register an exfiltrating server"],
  [/(^|\/)\.claude\/(harness\.json|verify-harness\.sh|regen-harness\.sh)$/, "harness integrity baseline/verifier"],
  [/(^|\/)\.claude\/\.harness-base\//, "merge base snapshot — editing it can poison harness re-sync merges"],
  [/(^|\/)\.claude\/comment-hygiene-patterns\.txt$/, "comment-hygiene pattern list — editing it weakens the CI gate"],
  [/(^|\/)dockerfile$/, "container image definition"],
  [/(^|\/)(lefthook\.yml|\.gitleaks\.toml)$/, "git-hook enforcement config"],
  [/(^|\/)\.lefthook\//, "git-hook script — editing it can weaken commit-time guards"],
];

// Lexically normalised, project-relative path. Matching is case-insensitive because case-insensitive
// filesystems (macOS, Windows) make `.ENV` and `.env` the same file. Symlinked parents are not
// resolved here (the CC hook does); lefthook + CI remain the backstop.
function protectedFileReason(filePath, root) {
  if (!filePath) return null;
  const abs = path.posix.resolve(root, filePath);
  const relRaw = path.posix.relative(root, abs);
  const shown = relRaw && !relRaw.startsWith("..") ? relRaw : abs;
  const rel = shown.toLowerCase();
  const base = path.posix.basename(rel);

  if (base.startsWith(".env") && base !== ".env.example" && base !== ".env.default") {
    return `writing ${path.posix.basename(shown)} is not allowed — add placeholders to .env.example; keep real secrets out of the repo`;
  }
  if (/^(\.github\/(workflows|actions)|\.azuredevops)\//.test(rel) || /^azure-pipelines.*\.ya?ml$/.test(base) ||
      base === ".gitlab-ci.yml" || base === "jenkinsfile") {
    return `${shown} is a CI/CD pipeline definition (GitHub / Azure DevOps / GitLab / Jenkins) — requires human review`;
  }
  if (/^\.?secrets\//.test(rel)) return `${shown} is inside a secrets directory — must never be written by the agent`;
  if (/\.(pem|key|p12|pfx|secret)$/.test(base) || ["credentials.json", ".netrc", ".secrets"].includes(base)) {
    return `${shown} is a certificate or credential file — must never be committed`;
  }
  for (const [re, why] of GOVERNANCE) {
    if (re.test(rel)) return `PROTECTED FILE: ${shown} — ${why}. Confirm human approval before editing (re-run intentionally).`;
  }
  return null;
}

// A commit message saying "git push --force origin main" inside a heredoc is text, not a command.
function stripHeredocBodies(cmd) {
  const out = [];
  let word = null;
  let tabs = false;
  for (const line of cmd.split("\n")) {
    if (word !== null) {
      if ((tabs ? line.replace(/^\t+/, "") : line) === word) word = null;
      continue;
    }
    out.push(line);
    const m = line.replace(/<<</g, "").match(/<<(-?)\s*["']?([A-Za-z_][A-Za-z0-9_]*)/);
    if (m) { tabs = m[1] === "-"; word = m[2]; }
  }
  return out.join("\n");
}

// Unwrap `bash -c "…"`/`eval '…'`, unquote single quoted words (the shell strips those quotes too),
// then blank multi-word quoted strings so text inside -m "…" can't false-trigger. Double quotes go
// first so an apostrophe inside "it's done" can't pair with a later ' and swallow real flags.
function normalise(cmd) {
  return cmd
    .replace(/(^|[\s;&|(])(bash|sh|zsh|eval)(\s+-[a-z]*c)?\s+"([^"]*)"/g, "$1 $4 ")
    .replace(/(^|[\s;&|(])(bash|sh|zsh|eval)(\s+-[a-z]*c)?\s+'([^']*)'/g, "$1 $4 ")
    .replace(/"([^"'\s]*)"/g, "$1").replace(/"[^"]*"/g, " Q ")
    .replace(/'([^'\s]*)'/g, "$1").replace(/'[^']*'/g, " Q ");
}

function commitShortFlagReason(args) {
  let skipNext = false;
  for (const a of args) {
    if (a === "--") break;
    if (skipNext) { skipNext = false; continue; }
    if (a.startsWith("--") || !/^-./.test(a)) continue;
    const flags = a.slice(1);
    for (let i = 0; i < flags.length; i++) {
      const c = flags[i];
      if (c === "n") return "-n (--no-verify) on git commit bypasses the pre-commit hooks. Fix the failure instead.";
      if ("mFcCtSu".includes(c)) {
        if (i === flags.length - 1 && c !== "S" && c !== "u") skipNext = true;
        break;
      }
    }
  }
  return null;
}

function pushTargetsProtectedWithForce(args, branch) {
  let force = false, target = false, explicit = false, positional = 0;
  for (const a of args) {
    if (/^--(force(-with-lease)?(=.*)?|force-if-includes|mirror|delete)$/.test(a)) { force = true; continue; }
    if (a.startsWith("--")) continue;
    if (a.startsWith("-")) { if (/[fd]/.test(a.slice(1))) force = true; continue; }
    positional++;
    if (positional === 1) continue;
    explicit = true;
    if (a.startsWith("+") || a.startsWith(":")) force = true;
    if (new RegExp(`^\\+?((refs/heads/)?(${PROTECTED})|[^:]*:(refs/heads/)?(${PROTECTED}))$`).test(a)) target = true;
    if (/^\+?(HEAD|@)$/.test(a) && PROTECTED_RE.test(branch)) target = true;
  }
  if (!explicit && PROTECTED_RE.test(branch)) target = true;
  return force && target;
}

// Port of block-no-verify.sh: evaluates each simple command's git invocation separately.
// `branch` is the project's current git branch (or ""). A best-effort tripwire, not a boundary.
function bashCommandReason(rawCmd, branch) {
  if (!rawCmd) return null;
  const cmd = stripHeredocBodies(rawCmd);
  const scan = normalise(cmd);
  const lower = cmd.toLowerCase();

  if (/(^|[^A-Za-z0-9_])LEFTHOOK(_EXCLUDE)?=/.test(scan) && /(^|[^A-Za-z0-9_-])git(\s|$)/.test(scan)) {
    return "LEFTHOOK=0 / LEFTHOOK_EXCLUDE disables the pre-commit hook layer — the same bypass as --no-verify. Fix the failure instead.";
  }
  if (/git_config_(parameters|key_[0-9]+)/.test(lower) && lower.includes("hookspath")) {
    return "GIT_CONFIG_* overriding core.hooksPath disables the git-hook layer. Fix the failure instead.";
  }
  if (lower.includes("alias.") && lower.includes("no-verify")) {
    return "a git alias wrapping --no-verify is the same bypass as --no-verify. Fix the failure instead.";
  }

  for (const seg of scan.split(/[;|&()`\n]/)) {
    const t = seg.trim().split(/\s+/).filter(Boolean);
    let i = t.findIndex((w) => { const x = w.replace(/^\\/, ""); return x === "git" || x.endsWith("/git"); });
    if (i < 0) continue;
    i++;
    while (i < t.length && t[i].startsWith("-")) {
      const o = t[i];
      if (o === "-c" || o === "--config-env") {
        if (/core\.hookspath/i.test(t[i + 1] || "")) return "'git -c core.hooksPath=…' disables the git-hook layer — the same bypass as --no-verify. Fix the failure instead.";
        i += 2; continue;
      }
      if (["-C", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix"].includes(o)) { i += 2; continue; }
      if (/core\.hookspath/i.test(o)) return "overriding core.hooksPath disables the git-hook layer. Fix the failure instead.";
      i++;
    }
    const sub = t[i] || "";
    const args = t.slice(i + 1);
    const beforeDashDash = args.includes("--") ? args.slice(0, args.indexOf("--")) : args;

    if (GIT_HOOK_SUBCOMMANDS.has(sub) && beforeDashDash.some((a) => a.startsWith("--no-veri"))) {
      return `--no-verify on 'git ${sub}' bypasses the git hooks. Fix the failure instead.`;
    }
    if (sub === "commit") {
      const reason = commitShortFlagReason(args);
      if (reason) return reason;
      if (PROTECTED_RE.test(branch)) return `direct commit to protected branch '${branch}'. Create a feature branch first.`;
    }
    if (sub === "push" && pushTargetsProtectedWithForce(args, branch)) {
      return "force-push/delete on a protected branch (--force, --force-with-lease, -f, +refspec, HEAD:main). Open a PR instead.";
    }
    if (sub === "config" && /core\.hookspath/i.test(args.join(" ")) &&
        !args.some((a) => ["--get", "--get-all", "--get-regexp", "get", "-l", "--list"].includes(a))) {
      return "'git config core.hooksPath' re-points or disables the git-hook layer. Confirm with a human first.";
    }
    if ((sub === "checkout" || sub === "restore") && GUARD_PATH_RE.test(" " + args.join(" "))) {
      return "'git checkout/restore' on a guard-layer file discards enforcement config. Confirm with a human first.";
    }
  }

  if (/(^|\s)rm(\s|$)/.test(cmd) && /\s-[a-zA-Z]*r|\s--recursive/.test(cmd) && /\s-[a-zA-Z]*f|\s--force/.test(cmd) &&
      /(^|[\s/"])(src|app|lib|test|\.claude|\.lefthook|\.git|node_modules)([\s/"]|$)/.test(cmd)) {
    return "recursive rm on a source directory. Confirm with a human first.";
  }
  return null;
}

async function fileExists($, p) {
  return $`test -f ${p}`.then(() => true).catch(() => false);
}

// Mirrors post-edit-typecheck.sh: only source edits of the project's language trigger a check.
async function typecheckCommand($, root, file) {
  if (/\.(ts|tsx|mts|cts)$/.test(file) && await fileExists($, `${root}/package.json`)) {
    return ["pnpm", "exec", "tsc", "--noEmit", "--incremental"];
  }
  if (/\.pyi?$/.test(file) &&
      (await fileExists($, `${root}/pyproject.toml`) || await fileExists($, `${root}/requirements.txt`))) {
    return ["python", "-m", "pyright", "src/"];
  }
  return null;
}

const argsOf = (input, output) => output?.args || input?.args || {};
const fileArg = (args) => args.filePath || args.path || args.file_path;

export default async ({ directory, $ }) => {
  const root = path.posix.resolve(directory || ".");
  return {
    // Keyed on the SHAPE of the tool args, not the tool name — OpenCode's tool names vary by
    // version, so name-gating silently misses calls. Throwing aborts the tool call.
    "tool.execute.before": async (input, output) => {
      const args = argsOf(input, output);
      const command = args.command || args.cmd;
      if (typeof command === "string" && command) {
        let branch = "";
        try { branch = (await $`git -C ${root} rev-parse --abbrev-ref HEAD`.text()).trim(); } catch { /* not a git repo */ }
        const reason = bashCommandReason(command, branch);
        if (reason) throw new Error(`[templatecentral] BLOCKED: ${reason}`);
      }
      const file = fileArg(args);
      if (typeof file === "string" && file) {
        const reason = protectedFileReason(file, root);
        if (reason) throw new Error(`[templatecentral] BLOCKED: ${reason}`);
      }
    },
    // Feedback only — never throws. Appending to the tool result is what reaches the model;
    // console output is the fallback when the result shape isn't a string.
    "tool.execute.after": async (input, output) => {
      const file = fileArg(argsOf(input, output));
      if (typeof file !== "string" || !file) return;
      const cmd = await typecheckCommand($, root, file);
      if (!cmd) return;
      try {
        await $`${cmd}`.cwd(root).quiet();
      } catch (e) {
        const errs = (e?.stdout || e?.stderr || e?.message || "").toString().slice(0, 4000);
        if (!errs) return;
        const note = `\n\n[templatecentral] typecheck reports errors after this edit — fix them before moving on:\n${errs}`;
        if (output && typeof output.output === "string") output.output += note;
        else console.error(note);
      }
    },
  };
};
