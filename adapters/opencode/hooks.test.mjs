// Tests the plugin through its default export's tool.execute.before hook — the only correct way,
// since the guard helpers are intentionally NOT exported (OpenCode would try to load named exports
// as plugins; see the note in templatecentral.plugin.js). Covers the full block/allow matrix +
// the arg-key shapes OpenCode may use. Run: node adapters/opencode/hooks.test.mjs
import plugin from "./templatecentral.plugin.js";

// Mock OpenCode's PluginInput `$` (tagged-template shell). `branch` is what `git rev-parse` returns.
const mkShell = (branch) => (..._a) => { const p = Promise.resolve(""); p.text = async () => branch; p.cwd = () => p; p.quiet = async () => ""; return p; };
const onFeature = await plugin({ directory: "/proj", $: mkShell("feat/x") }); // non-protected branch
const onMain = await plugin({ directory: "/proj", $: mkShell("main") });      // protected branch
const beforeFeature = onFeature["tool.execute.before"];
const beforeMain = onMain["tool.execute.before"];

let pass = 0, fail = 0;
const blocks = async (name, before, args) => {
  try { await before({}, { args }); fail++; console.log("  ✗ " + name + " (should BLOCK)"); } catch { pass++; }
};
const allows = async (name, before, args) => {
  try { await before({}, { args }); pass++; } catch (e) { fail++; console.log("  ✗ " + name + " (should ALLOW, threw: " + e.message + ")"); }
};

// ── bash-command guard (no tool name — keyed on args shape) ──
await blocks("git commit --no-verify", beforeFeature, { command: "git commit --no-verify -m x" });
await blocks("git commit -n",          beforeFeature, { command: "git commit -n -m x" });
await blocks("git push --force main",  beforeFeature, { command: "git push --force origin main" });
await blocks("git push +develop",      beforeFeature, { command: "git push origin +develop" });
await blocks("git checkout AGENTS.md", beforeFeature, { command: "git checkout AGENTS.md" });
await blocks("rm -rf src",             beforeFeature, { command: "rm -rf src" });
await blocks("rm -rf .claude/hooks",   beforeFeature, { command: "rm -rf .claude/hooks" });
await blocks("rm -rf node_modules",    beforeFeature, { command: "rm -rf node_modules" });
await blocks("commit on protected branch", beforeMain, { command: 'git commit -m "feat: x"' });
await allows("commit on feature branch",   beforeFeature, { command: 'git commit -m "feat: x"' });
await allows("commit msg mentions --no-verify (scrubbed)", beforeFeature, { command: 'git commit -m "docs: --no-verify note"' });
await allows("normal pnpm test",       beforeFeature, { command: "pnpm test --run" });
await allows("rm single file",         beforeFeature, { command: "rm foo.txt" });
await blocks("bash via args.cmd",      beforeFeature, { cmd: "git commit --no-verify -m x" });

// ── protected-file guard ──
await blocks(".env",                   beforeFeature, { filePath: "/proj/.env" });
await blocks("secrets/x",              beforeFeature, { filePath: "/proj/secrets/x" });
await blocks("cert .pem",              beforeFeature, { filePath: "/proj/server.pem" });
await blocks("AGENTS.md",              beforeFeature, { filePath: "/proj/AGENTS.md" });
await blocks(".claude/settings.json",  beforeFeature, { filePath: "/proj/.claude/settings.json" });
await blocks("Dockerfile",             beforeFeature, { filePath: "/proj/Dockerfile" });
await blocks("file via args.path",     beforeFeature, { path: "/proj/.env" });
await allows(".env.example",           beforeFeature, { filePath: "/proj/.env.example" });
await allows(".env.default",           beforeFeature, { filePath: "/proj/.env.default" });
await allows("src/app.ts",             beforeFeature, { filePath: "/proj/src/app.ts" });
await allows("README.md",              beforeFeature, { filePath: "/proj/README.md" });

console.log(`\nHook matrix: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
