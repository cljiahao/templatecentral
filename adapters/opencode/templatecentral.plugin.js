// templatecentral.plugin.js — OpenCode adapter for templateCentral's in-agent harness guards.
//
// Ports the cleanly-mappable Claude Code hooks (scaffold/shared/harness-kit*.md) to OpenCode's plugin API:
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
    .replace(/"([^"'\s]+)"/g, "$1").replace(/"[^"]*"/g, " Q ")
    .replace(/'([^'\s]+)'/g, "$1").replace(/'[^']*'/g, " Q ");
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

const unresolved = (d) => !d || d === "-" || d === "Q" || /[$`~]/.test(d);

// A strict `&&` chain (no ; || | lone & ( ) ` or newline once N>&M redirections are set aside) reaches
// each git only after every cd before it succeeded, so the directories its git words run in are known
// exactly: those, or null when the command is anything short of that. A cd that is not a plain literal
// at the start of a segment, or a git that is not the first word of its segment, gives null.
async function strictChainDirs(scan, cwd, env) {
  const chk = scan.replace(/[0-9]*>&[0-9-]*/g, "").replace(/&>>?/g, "").replace(/&&/g, " ");
  if (/[;|&()`\n]/.test(chk)) return null;
  const bare = (w) => w.replace(/^\\/, "");
  const isGit = (w) => bare(w) === "git" || bare(w).endsWith("/git");
  const DIR_WORDS = new Set(["cd", "pushd", "popd", "env", "sudo", "command", "builtin", "exec"]);
  let cur = cwd, sawGit = false;
  const out = [];
  for (const seg of scan.split("&&")) {
    const t = seg.trim().split(/\s+/).filter(Boolean);
    if (t.length === 0) continue;
    const first = bare(t[0]);
    if (first === "cd" || first === "pushd") {
      const d = t.slice(1).find((x) => !/^-./.test(x)) ?? "";
      if (unresolved(d)) return null;
      const dir = path.posix.resolve(cur, d);
      if (!(await env.isDir(dir))) return null;
      cur = dir;
      continue;
    }
    if (t.some((w) => DIR_WORDS.has(bare(w)))) return null;
    if (isGit(t[0])) {
      sawGit = true;
      if (!out.includes(cur)) out.push(cur);
    } else if (t.some(isGit)) return null;
  }
  return sawGit ? out : null;
}

// The first protected branch a bare commit/push may land on, or "". `st.cands` holds the command's cwd
// plus each literal cd-like target resolved against every candidate so far: the real directory is always
// one of them, so a cd the shell undoes (subshell, `&`, `|`) or that fails cannot hide it, and ANY
// protected candidate counts. `st.redir` (anything this check cannot resolve exactly) adds the project
// root, the directory it judged before it knew the cwd, so a construct the parser misses never leaves it
// weaker than that.
async function protectedBranch(st, cdir) {
  const isProtected = (b) => typeof b === "string" && PROTECTED_RE.test(b);
  const dirs = [...st.cands];
  if (st.redir) dirs.push(st.root);
  const cdOk = Boolean(cdir) && !unresolved(cdir);
  if (cdir && !cdOk) dirs.push(st.root);
  let found = false;
  for (const d of dirs) {
    const b = await st.branchAt(cdOk ? path.posix.resolve(d, cdir) : d);
    if (b == null) continue;
    found = true;
    if (isProtected(b)) return b;
  }
  if (found) return "";
  // No candidate is inside a git repo: judge the project root, as before.
  const b = await st.branchAt(cdOk ? path.posix.resolve(st.root, cdir) : st.root);
  return isProtected(b) ? b : "";
}

// Port of block-no-verify.sh: evaluates each simple command's git invocation separately.
// `env` = { root, branchAt(dir) → branch or null, isDir(dir) → boolean }, so a worktree or a `cd` is
// judged by the branch it actually commits on. A best-effort tripwire, not a boundary.
async function bashCommandReason(rawCmd, cwd, env) {
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

  const st = { ...env, cands: [cwd], redir: false };
  const addTarget = async (d) => {
    // With CDPATH set, a bare relative name may resolve through it rather than through a candidate.
    if (unresolved(d) || (process.env.CDPATH && !/^(\/|\.\.?(\/|$))/.test(d))) { st.redir = true; return; }
    let any = false;
    for (const c of [...st.cands]) {
      const dir = path.posix.resolve(c, d);
      if (!(await env.isDir(dir))) continue;
      any = true;
      // Already a candidate: nothing new, so the repeat passes settle.
      if (!st.cands.includes(dir)) st.cands.push(dir);
    }
    if (!any) st.redir = true;
  };
  const segments = scan.split(/[;|&()`\n]/).map((seg) => seg.trim().split(/\s+/).filter(Boolean));
  const gitIndex = (t) => t.findIndex((w) => { const x = w.replace(/^\\/, ""); return x === "git" || x.endsWith("/git"); });
  // Collect directory changes before judging any git invocation: a loop or a function can run a cd that
  // appears after the git word. Words before each segment's git executable (all words, when there is
  // none) are scanned wherever they sit — `if cd x`, `\cd x`, `env -C x git …`. Passes repeat until the
  // candidate set stops growing, so a relative target is resolved against every reachable directory.
  const POSITION = new Set(["then", "do", "else", "if", "while", "until", "!", "{", "time", "command", "builtin", "exec"]);
  // `name() { … }` defines a function whose body may cd where this check cannot follow.
  if (/(^|[^A-Za-z0-9_])[A-Za-z_][\w-]*\s*\(\)/.test(scan)) st.redir = true;
  let settled = false;
  for (let pass = 0; pass < 4 && !settled; pass++) {
    const before = st.cands.length;
    for (const t of segments) {
      const g = gitIndex(t);
      const end = g < 0 ? t.length : g;
      for (let p = 0; p < end; p++) {
        const w = t[p].replace(/^\\/, "");
        const rest = t.slice(p + 1, end);
        if (w === "cd" || w === "pushd") await addTarget(rest.find((x) => !/^-./.test(x)) ?? "");
        else if (["popd", "eval", "source", "function"].includes(w) || /^(CDPATH|GIT_DIR|GIT_WORK_TREE)=/.test(w)) st.redir = true;
        // `.` sources a script only in command position; elsewhere it is an ordinary argument (`ls .`).
        else if (w === "." && (p === 0 || POSITION.has(t[p - 1]))) st.redir = true;
        else if (w === "env" || w === "sudo") {
          for (let q = 0; q < rest.length; q++) {
            const a = rest[q];
            if (a === "-C" || a === "-D" || a === "--chdir") await addTarget(rest[q + 1] ?? "");
            else if (a.startsWith("--chdir=")) await addTarget(a.slice(8));
            else if (/^-[CD]./.test(a)) await addTarget(a.slice(2));
          }
        }
      }
    }
    settled = st.cands.length === before;
  }
  if (!settled) st.redir = true; // still growing at the cap: judge the project root too
  // In a strict && chain the real directories are known, so a protected cwd the chain cds out of drops out.
  if (!st.redir) {
    const chainDirs = await strictChainDirs(scan, cwd, env);
    if (chainDirs) st.cands = chainDirs;
  }
  for (const t of segments) {
    let i = gitIndex(t);
    if (i < 0) continue;
    i++;
    let cdir = "";
    while (i < t.length && t[i].startsWith("-")) {
      const o = t[i];
      if (o === "-c" || o === "--config-env") {
        if (/core\.hookspath/i.test(t[i + 1] || "")) return "'git -c core.hooksPath=…' disables the git-hook layer — the same bypass as --no-verify. Fix the failure instead.";
        i += 2; continue;
      }
      if (o === "-C") {
        // git applies every -C in turn, each relative to the one before.
        const x = t[i + 1] || "";
        cdir = !cdir || x.startsWith("/") ? x : `${cdir}/${x}`;
        i += 2; continue;
      }
      if (o === "--git-dir" || o === "--work-tree") { st.redir = true; i += 2; continue; }
      if (o.startsWith("--git-dir=") || o.startsWith("--work-tree=")) { st.redir = true; i++; continue; }
      if (["--namespace", "--exec-path", "--super-prefix"].includes(o)) { i += 2; continue; }
      if (/core\.hookspath/i.test(o)) return "overriding core.hooksPath disables the git-hook layer. Fix the failure instead.";
      i++;
    }
    const sub = t[i] || "";
    const args = t.slice(i + 1);
    const branch = sub === "commit" || sub === "push" ? await protectedBranch(st, cdir) : "";
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
        const workdir = args.workdir || args.cwd;
        const cwd = typeof workdir === "string" && workdir ? path.posix.resolve(root, workdir) : root;
        const env = {
          root,
          branchAt: async (dir) => {
            try { return (await $`git -C ${dir} rev-parse --abbrev-ref HEAD`.text()).trim(); } catch { return null; }
          },
          isDir: async (dir) => $`test -d ${dir}`.then(() => true).catch(() => false),
        };
        const reason = await bashCommandReason(command, cwd, env);
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
