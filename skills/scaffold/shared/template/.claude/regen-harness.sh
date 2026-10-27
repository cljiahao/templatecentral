#!/usr/bin/env bash
# HUMAN-RUN ONLY. Rewrites origin_hash in .claude/harness.json to the current files.
# NEVER let an agent run this — regenerating the baseline masks the drift the verifier
# exists to catch. protect-files.sh requires human approval to edit harness.json itself.
set -euo pipefail
if command -v node >/dev/null 2>&1; then
  node -e 'const fs=require("fs"),cr=require("crypto"),j=JSON.parse(fs.readFileSync(".claude/harness.json","utf8"));for(const v of Object.values(j.seeded_files)){if(fs.existsSync(v.path))v.origin_hash=cr.createHash("sha256").update(fs.readFileSync(v.path)).digest("hex");}fs.writeFileSync(".claude/harness.json",JSON.stringify(j,null,2)+"\n");console.log("harness baseline regenerated");'
elif command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,hashlib,os;j=json.load(open(".claude/harness.json"));[v.__setitem__("origin_hash",hashlib.sha256(open(v["path"],"rb").read()).hexdigest()) for v in j["seeded_files"].values() if os.path.isfile(v["path"])];open(".claude/harness.json","w").write(json.dumps(j,indent=2)+"\n");print("harness baseline regenerated")'
else
  echo "regen-harness: need node or python3" >&2; exit 3
fi
