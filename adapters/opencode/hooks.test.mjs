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
