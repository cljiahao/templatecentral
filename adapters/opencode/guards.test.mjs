// Unit tests for the ported guard logic in templatecentral.plugin.js.
// Run: node adapters/opencode/guards.test.mjs   (no deps; exits non-zero on failure)
// These cover the pure block/allow decisions, mirroring the Claude Code hooks they port from.
import { bashCommandReason as bash, protectedFileReason as file } from "./templatecentral.plugin.js";

let pass = 0, fail = 0;
const ok = (name, cond) => { if (cond) pass++; else { fail++; console.log("  ✗ " + name); } };

// bash guard — must BLOCK
ok("commit --no-verify", !!bash("git commit --no-verify -m x", ""));
ok("commit -n", !!bash("git commit -n -m x", ""));
ok("commit on main", !!bash('git commit -m "feat: x"', "main"));
ok("force-push main", !!bash("git push --force origin main", ""));
ok("+refspec push", !!bash("git push origin +develop", ""));
ok("checkout AGENTS.md", !!bash("git checkout AGENTS.md", ""));
ok("rm -rf src", !!bash("rm -rf src", ""));
ok("rm -rf .claude/hooks", !!bash("rm -rf .claude/hooks", ""));
ok("rm -rf node_modules", !!bash("rm -rf node_modules", ""));

// bash guard — must ALLOW
ok("commit on feature branch", !bash('git commit -m "feat: x"', "feat/foo"));
ok("commit msg mentions --no-verify (scrubbed)", !bash('git commit -m "docs: explain --no-verify"', "feat/foo"));
ok("normal pnpm test", !bash("pnpm test --run", ""));
ok("rm single file", !bash("rm foo.txt", ""));

// file guard — must BLOCK
ok(".env", !!file("/p/.env", "/p"));
ok("secrets/", !!file("/p/secrets/x", "/p"));
ok("cert .pem", !!file("/p/server.pem", "/p"));
ok("AGENTS.md governance", !!file("/p/AGENTS.md", "/p"));
ok(".claude/settings.json", !!file("/p/.claude/settings.json", "/p"));
ok("Dockerfile", !!file("/p/Dockerfile", "/p"));

// file guard — must ALLOW
ok(".env.example", !file("/p/.env.example", "/p"));
ok("normal src file", !file("/p/src/app.ts", "/p"));
ok("normal README", !file("/p/README.md", "/p"));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
