// Drives the plugin through its default export's hooks — the guard helpers are intentionally NOT
// exported (OpenCode would load named exports as plugins). Run: node adapters/opencode/hooks.test.mjs
import plugin from "./templatecentral.plugin.js";

// Mock of OpenCode's `$` tagged-template shell. `branch` is what `git rev-parse` returns; `files`
// are the paths `test -f` finds; `typeErrors` is what a failing typecheck prints (null = passes).
const mkShell = ({ branch = "feat/x", files = [], typeErrors = null, calls = [] } = {}) => (strings, ...values) => {
  const text = strings.reduce((acc, s, i) => acc + s + (i < values.length ? [].concat(values[i]).join(" ") : ""), "");
  calls.push(text);
  let p;
  if (text.startsWith("test -f ")) p = files.includes(text.slice(8)) ? Promise.resolve("") : Promise.reject(new Error("missing"));
  else if (/tsc|pyright/.test(text) && typeErrors) p = Promise.reject(Object.assign(new Error("exit 2"), { stdout: typeErrors }));
  else p = Promise.resolve("");
  p.catch(() => {});
  p.text = async () => branch;
  p.cwd = () => p;
  p.quiet = () => p;
  return p;
};

const beforeFeature = (await plugin({ directory: "/proj", $: mkShell() }))["tool.execute.before"];
const beforeMain = (await plugin({ directory: "/proj", $: mkShell({ branch: "main" }) }))["tool.execute.before"];

let pass = 0, fail = 0;
const check = (name, ok, detail = "") => { if (ok) pass++; else { fail++; console.log(`  ✗ ${name}${detail}`); } };
const blocks = async (name, before, args) => {
  try { await before({}, { args }); check(name, false, " (should BLOCK)"); } catch { check(name, true); }
};
const allows = async (name, before, args) => {
  try { await before({}, { args }); check(name, true); } catch (e) { check(name, false, ` (should ALLOW, threw: ${e.message})`); }
};

// ── bash-command guard: hook bypasses ──
await blocks("git commit --no-verify", beforeFeature, { command: "git commit --no-verify -m x" });
await blocks("git commit -n",          beforeFeature, { command: "git commit -n -m x" });
await blocks("git commit -an cluster", beforeFeature, { command: "git commit -an -m x" });
await blocks("git push --no-verify",   beforeFeature, { command: "git push --no-verify origin feat/x" });
await blocks("git merge --no-verify",  beforeFeature, { command: "git merge --no-verify feat/y" });
await blocks("git -C dir commit -n",   beforeFeature, { command: "git -C /proj commit -n -m x" });
await blocks("/usr/bin/git commit -n", beforeFeature, { command: "/usr/bin/git commit -n -m x" });
await blocks("bash -c wrapped",        beforeFeature, { command: 'bash -c "git commit --no-verify -m x"' });
await blocks("chained after &&",       beforeFeature, { command: "pnpm lint && git commit --no-verify -m x" });
await blocks("bash via args.cmd",      beforeFeature, { cmd: "git commit --no-verify -m x" });
await blocks("LEFTHOOK=0 git commit",  beforeFeature, { command: 'LEFTHOOK=0 git commit -m "x"' });
await blocks("LEFTHOOK_EXCLUDE commit", beforeFeature, { command: "LEFTHOOK_EXCLUDE=lint git commit -m msg" });
await blocks("git -c core.hooksPath",  beforeFeature, { command: "git -c core.hooksPath=/dev/null commit -m msg" });
await blocks("git config core.hooksPath", beforeFeature, { command: "git config core.hooksPath /dev/null" });
await blocks("GIT_CONFIG_* hooksPath", beforeFeature, { command: "GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/x git commit -m y" });
await blocks("alias wrapping --no-verify", beforeFeature, { command: "git config alias.ci 'commit --no-verify'" });
await allows("commit -m value containing n", beforeFeature, { command: "git commit -m nonsense" });
await allows("git log -n 5",           beforeFeature, { command: "git log -n 5" });
await allows("grep -n after commit",   beforeFeature, { command: "git commit -m x && grep -n foo src/a.ts" });
await allows("git config --get hooksPath", beforeFeature, { command: "git config --get core.hooksPath" });
await allows("commit msg mentions --no-verify (scrubbed)", beforeFeature, { command: 'git commit -m "docs: --no-verify note"' });
await allows("heredoc msg mentions --no-verify", beforeFeature, { command: "git commit -F - <<'EOF'\ndocs: git commit --no-verify\nEOF" });
await allows("LEFTHOOK=0 non-git",     beforeFeature, { command: "LEFTHOOK=0 pnpm test" });
await allows("commit msg says LEFTHOOK (scrubbed)", beforeFeature, { command: 'git commit -m "chore: note LEFTHOOK=0 in docs"' });

// ── bash-command guard: protected branches ──
await blocks("commit on protected branch", beforeMain, { command: 'git commit -m "feat: x"' });
await allows("commit on feature branch",   beforeFeature, { command: 'git commit -m "feat: x"' });
await allows("non-commit git on main",     beforeMain, { command: "git status" });
await blocks("git push --force main",  beforeFeature, { command: "git push --force origin main" });
await blocks("git push -f main",       beforeFeature, { command: "git push -f origin main" });
await blocks("--force-with-lease main", beforeFeature, { command: "git push --force-with-lease origin main" });
await blocks("git push +develop",      beforeFeature, { command: "git push origin +develop" });
await blocks("HEAD:main force",        beforeFeature, { command: "git push -f origin HEAD:main" });
await blocks("delete protected",       beforeFeature, { command: "git push origin :uat" });
await blocks("bare force-push on main", beforeMain, { command: "git push --force" });
await allows("force-push feature",     beforeFeature, { command: "git push --force origin feat/x" });
await allows("force-push branch named fix-main", beforeFeature, { command: "git push -f origin fix-main" });
await allows("plain push main",        beforeFeature, { command: "git push origin main" });

// ── bash-command guard: branch of the command's own directory ──
// A worktree or a `cd`/`git -C` target can sit on a different branch from the project root. Candidates are
// the cwd plus each literal cd-like target, resolved against every candidate so far; any protected one
// blocks. Anything the guard cannot resolve exactly (a variable, $(…), ~, cd -, popd, eval, CDPATH,
// GIT_DIR, --git-dir) also judges the project root, as before.
// `branches` maps a git directory to its branch; `dirs` are the other directories that exist.
const mkDirShell = (branches, dirs = []) => (strings, ...values) => {
  const text = strings.reduce((acc, s, i) => acc + s + (i < values.length ? [].concat(values[i]).join(" ") : ""), "");
  const rev = text.match(/^git -C (\S+) rev-parse/);
  const dir = text.match(/^test -d (\S+)$/);
  const ok = rev ? rev[1] in branches : dir ? dir[1] in branches || dirs.includes(dir[1]) : true;
  // Real `$` rejects a failing command from `.text()` too, not only from the promise itself.
  const p = ok ? Promise.resolve("") : Promise.reject(new Error(`exit 128: ${text}`));
  p.catch(() => {});
  p.text = async () => { if (!ok) throw new Error(`exit 128: ${text}`); return rev ? branches[rev[1]] : ""; };
  p.cwd = () => p;
  p.quiet = () => p;
  return p;
};
const repos = { "/proj": "main", "/wt/feat": "feat/x", "/wt/feat/docs": "feat/x", "/wt/dev": "develop" };
const rootMain = (await plugin({ directory: "/proj", $: mkDirShell(repos, ["/tmp", "/wt"]) }))["tool.execute.before"];
const rootFeat = (await plugin({ directory: "/wt/feat", $: mkDirShell(repos, ["/tmp", "/wt"]) }))["tool.execute.before"];
const wf = { workdir: "/wt/feat" };
// the reported bug: a worktree session whose project root sits on a protected branch
await allows("bare commit in feature workdir", rootMain, { command: "git commit -m x", ...wf });
await allows("via args.cwd", rootMain, { command: "git commit -m x", cwd: "/wt/feat" });
await allows("relative workdir resolves against root", rootMain, { command: "git commit -m x", workdir: "../wt/feat" });
await allows("force-push HEAD in feature workdir", rootMain, { command: "git push -f origin HEAD", ...wf });
await allows("git -C feature", rootMain, { command: "git -C /wt/feat commit -m x", ...wf });
await allows("relative cd within the worktree", rootMain, { command: "cd docs && git commit -m x", ...wf });
await allows("cd to the worktree itself", rootMain, { command: "cd /wt/feat && git commit -m x", ...wf });
await allows("non-repo cd then feature cd", rootMain, { command: "cd /tmp; cd /wt/feat && git commit -m x", ...wf });
await allows("glob word", rootMain, { command: "git add * && git commit -m x", ...wf });
await allows("cd as a commit message word", rootMain, { command: "git commit -m cd", ...wf });
await allows("env without -C", rootMain, { command: "env FOO=1 git commit -m x", ...wf });
await allows("env -C feature", rootMain, { command: "env -C /wt/feat git commit -m x", ...wf });
// protected cwd or target
await blocks("protected workdir", rootFeat, { command: "git commit -m x", workdir: "/proj" });
await blocks("cd protected &&", rootFeat, { command: "cd /wt/dev && git commit -m x" });
await blocks("cd protected ;", rootFeat, { command: "cd /proj; git commit -m x" });
await blocks("relative cd into protected", rootFeat, { command: "cd ../dev && git commit -m x" });
await blocks("pushd protected", rootFeat, { command: "pushd /proj && git commit -m x" });
await blocks("git -C protected", rootFeat, { command: "git -C /proj commit -m x" });
await blocks("cd protected && force-push HEAD", rootFeat, { command: "cd /proj && git push -f origin HEAD" });
await blocks("force-push main from feature", rootMain, { command: "cd /wt/feat && git push -f origin main", ...wf });
// undone or failed cd must not hide a protected cwd
await blocks("subshell cd", rootFeat, { command: "(cd /wt/feat && true); git commit -m x", workdir: "/proj" });
await blocks("cd -", rootFeat, { command: "cd /wt/feat; cd -; git commit -m x", workdir: "/proj" });
await blocks("pushd/popd", rootFeat, { command: "pushd /wt/feat; popd; git commit -m x", workdir: "/proj" });
await blocks("backgrounded cd", rootFeat, { command: "cd /wt/feat & git commit -m x", workdir: "/proj" });
await blocks("piped cd", rootFeat, { command: "cd /wt/feat | git commit -m x", workdir: "/proj" });
await blocks("failed cd", rootFeat, { command: "cd nosuch; git commit -m x", workdir: "/proj" });
await blocks("subshell cd then force-push HEAD", rootFeat, { command: "(cd /wt/feat && true); git push -f origin HEAD", workdir: "/proj" });
// cd-like words anywhere before git
await blocks("if cd", rootFeat, { command: "if cd /proj; then git commit -m x; fi" });
await blocks("while cd", rootFeat, { command: "while cd /proj; do git commit -m x; break; done" });
await blocks("\\cd", rootFeat, { command: "\\cd /proj && git commit -m x" });
await blocks("eval cd", rootFeat, { command: "eval cd /proj && git commit -m x" });
await blocks("command cd", rootFeat, { command: "command cd /proj && git commit -m x" });
await blocks("then cd", rootFeat, { command: "if true; then cd /proj; fi; git commit -m x" });
await blocks("env -C protected", rootFeat, { command: "env -C /proj git commit -m x" });
await blocks("sudo -D protected", rootFeat, { command: "sudo -D /proj git commit -m x" });
await blocks("bash -c wrapped cd", rootFeat, { command: 'bash -c "cd /proj && git commit -m x"' });
// anything not resolvable exactly judges the project root
await blocks("CDPATH", rootMain, { command: "CDPATH=/ cd proj && git commit -m x", ...wf });
await blocks("GIT_DIR prefix", rootMain, { command: "GIT_DIR=/proj/.git git commit -m x", ...wf });
await blocks("exported GIT_WORK_TREE", rootMain, { command: "export GIT_WORK_TREE=/proj; git commit -m x", ...wf });
await blocks("--git-dir=", rootMain, { command: "git --git-dir=/proj/.git commit -m x", ...wf });
await blocks("--work-tree", rootMain, { command: "git --work-tree /proj commit -m x", ...wf });
await blocks("variable cd target", rootMain, { command: "X=/wt/feat; cd $X && git commit -m x", ...wf });
await blocks("quoted variable cd target", rootMain, { command: 'X=/wt/feat; cd "$X" && git commit -m x', ...wf });
await blocks("printf -v", rootMain, { command: "X=/wt/feat; printf -vX %s /proj; cd $X && git commit -m x", ...wf });
await blocks("git -C variable", rootMain, { command: "git -C $X commit -m x", ...wf });
await blocks("cd $(…)", rootMain, { command: "cd $(git rev-parse --show-toplevel) && git commit -m x", ...wf });
await blocks('cd "$(…)"', rootMain, { command: 'cd "$(git rev-parse --show-toplevel)" && git commit -m x', ...wf });
await blocks("cd backtick", rootMain, { command: "cd `pwd` && git commit -m x", ...wf });
await blocks("bare cd", rootMain, { command: "cd && git commit -m x", ...wf });
await blocks("cd - with unknown OLDPWD", rootMain, { command: "cd - && git commit -m x", ...wf });
await blocks("cd ~", rootMain, { command: "cd ~ && git commit -m x", ...wf });
await blocks("non-repo workdir falls back to root", rootMain, { command: "git commit -m x", workdir: "/tmp" });
// quote pairing must still catch flags
await blocks("--no-verify after a quoted $(…)", rootFeat, { command: 'echo "root: $(git rev-parse --show-toplevel)"; git commit --no-verify -m "x y"' });
await blocks("force-push main after a quoted $(…)", rootFeat, { command: 'echo "root: $(git rev-parse --show-toplevel)" && git push --force origin main -o "a b"' });
// a cd after git (loop, function), chained -C, sourcing
await blocks("cd after git in a loop", rootMain, { command: "for i in 1 2; do git commit -m x; cd ../../proj; done", ...wf });
await blocks("function body after cd", rootMain, { command: "f(){ git commit -m x; }; cd /tmp; f", ...wf });
await blocks("function keyword", rootMain, { command: "function f { git commit -m x; }; f", ...wf });
await blocks("chained -C into protected", rootFeat, { command: "git -C /proj -C . commit -m x" });
await allows("chained -C within the worktree", rootMain, { command: "git -C /wt/feat -C docs commit -m x", ...wf });
await blocks("source", rootMain, { command: "source ./go.sh; git commit -m x", ...wf });
await blocks(". in command position", rootMain, { command: ". ./go.sh; git commit -m x", ...wf });
await allows(". as an argument", rootMain, { command: "ls . && git commit -m x", ...wf });
await allows("cd .", rootMain, { command: "cd . && git commit -m x", ...wf });
// an empty -C must not swallow the subcommand
await blocks("git -C '' commit", rootFeat, { command: "git -C '' commit -m x", workdir: "/proj" });
await blocks('git -C "" commit', rootFeat, { command: 'git -C "" commit -m x', workdir: "/proj" });
// conservative by design: a protected cwd stays a candidate after a cd
await blocks("cd out of a protected cwd still blocks", rootMain, { command: "cd /wt/feat && git commit -m x" });

// ── bash-command guard: guard-layer + destructive ──
await blocks("git checkout AGENTS.md", beforeFeature, { command: "git checkout AGENTS.md" });
await blocks("git restore ./.claude",  beforeFeature, { command: "git restore ./.claude/settings.json" });
await allows("git checkout branch",    beforeFeature, { command: "git checkout -b feat/y" });
await blocks("rm -rf src",             beforeFeature, { command: "rm -rf src" });
await blocks("rm -rf .claude/hooks",   beforeFeature, { command: "rm -rf .claude/hooks" });
await blocks("rm -rf node_modules",    beforeFeature, { command: "rm -rf node_modules" });
await allows("normal pnpm test",       beforeFeature, { command: "pnpm test --run" });
await allows("rm single file",         beforeFeature, { command: "rm foo.txt" });

// ── protected-file guard ──
await blocks(".env",                   beforeFeature, { filePath: "/proj/.env" });
await blocks(".env.local",             beforeFeature, { filePath: "/proj/.env.local" });
await blocks(".ENV (case-insensitive)", beforeFeature, { filePath: "/proj/.ENV" });
await blocks("relative ./.env",        beforeFeature, { filePath: "./.env" });
await blocks("secrets/x",              beforeFeature, { filePath: "/proj/secrets/x" });
await blocks("src/../secrets/x",       beforeFeature, { filePath: "/proj/src/../secrets/x" });
await blocks("cert .pem",              beforeFeature, { filePath: "/proj/server.pem" });
await blocks("credentials.json",       beforeFeature, { filePath: "/proj/config/credentials.json" });
await blocks("AGENTS.md",              beforeFeature, { filePath: "/proj/AGENTS.md" });
await blocks("agents.md (case-insensitive)", beforeFeature, { filePath: "/proj/agents.md" });
await blocks(".claude/settings.json",  beforeFeature, { filePath: "/proj/.claude/settings.json" });
await blocks(".claude/settings.local.json", beforeFeature, { filePath: "/proj/.claude/settings.local.json" });
await blocks(".claude/agents/x.md",    beforeFeature, { filePath: "/proj/.claude/agents/x.md" });
await blocks(".mcp.json",              beforeFeature, { filePath: "/proj/.mcp.json" });
await blocks("comment-hygiene patterns", beforeFeature, { filePath: "/proj/.claude/comment-hygiene-patterns.txt" });
await blocks("Dockerfile",             beforeFeature, { filePath: "/proj/Dockerfile" });
await blocks("dockerfile (case-insensitive)", beforeFeature, { filePath: "/proj/api/dockerfile" });
await blocks(".github/workflows",      beforeFeature, { filePath: "/proj/.github/workflows/ci.yml" });
await blocks(".github/actions",        beforeFeature, { filePath: "/proj/.github/actions/x/action.yml" });
await blocks("azure-pipelines.yml",    beforeFeature, { filePath: "/proj/azure-pipelines.yml" });
await blocks("azure-pipelines*.yaml",  beforeFeature, { filePath: "/proj/azure-pipelines-prod.yaml" });
await blocks(".azuredevops/",          beforeFeature, { filePath: "/proj/.azuredevops/pipeline.yml" });
await blocks(".gitlab-ci.yml",         beforeFeature, { filePath: "/proj/.gitlab-ci.yml" });
await blocks("Jenkinsfile",            beforeFeature, { filePath: "/proj/Jenkinsfile" });
await blocks("file via args.path",     beforeFeature, { path: "/proj/.env" });
await blocks("file via args.file_path", beforeFeature, { file_path: "/proj/.env" });
await allows(".env.example",           beforeFeature, { filePath: "/proj/.env.example" });
await allows(".env.default",           beforeFeature, { filePath: "/proj/.env.default" });
await allows("src/app.ts",             beforeFeature, { filePath: "/proj/src/app.ts" });
await allows("README.md",              beforeFeature, { filePath: "/proj/README.md" });
await allows("no args",                beforeFeature, {});

// ── typecheck-on-edit (feedback only) ──
const runAfter = async ({ files, typeErrors, file, result = "ok" }) => {
  const calls = [];
  const hooks = await plugin({ directory: "/proj", $: mkShell({ files, typeErrors, calls }) });
  const output = { args: { filePath: file }, output: result };
  await hooks["tool.execute.after"]({}, output);
  return { calls, output };
};
{
  const { output } = await runAfter({ files: ["/proj/package.json"], typeErrors: "error TS2322: bad", file: "/proj/src/a.ts" });
  check("TS error appended to tool output", output.output.includes("error TS2322"));
}
{
  const { calls } = await runAfter({ files: ["/proj/package.json"], typeErrors: "error TS1", file: "/proj/README.md" });
  check("non-source edit skips typecheck", !calls.some((c) => c.includes("tsc")));
}
{
  const { calls, output } = await runAfter({ files: ["/proj/pyproject.toml"], typeErrors: "1 error", file: "/proj/src/app/main.py" });
  check("Python edit runs pyright", calls.some((c) => c.includes("pyright")) && output.output.includes("1 error"));
}
{
  const { output } = await runAfter({ files: ["/proj/package.json"], typeErrors: null, file: "/proj/src/a.ts" });
  check("clean typecheck leaves output untouched", output.output === "ok");
}
{
  const hooks = await plugin({ directory: "/proj", $: mkShell() });
  let threw = false;
  try { await hooks["tool.execute.after"]({}, {}); } catch { threw = true; }
  check("after hook with no args never throws", !threw);
}

console.log(`\nHook matrix: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
