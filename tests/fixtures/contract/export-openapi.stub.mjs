// Stub of a nestjs export entry point (scripts/export-openapi.mjs) for the seeded contract test: prints the file named by STUB_OUT, then exits with STUB_EXIT.
import { readFileSync } from "node:fs";

if (process.env.STUB_OUT) process.stdout.write(readFileSync(process.env.STUB_OUT, "utf8"));
if (process.env.STUB_ERR) process.stderr.write(process.env.STUB_ERR + "\n");
process.exit(Number(process.env.STUB_EXIT || "0"));
