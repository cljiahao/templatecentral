# Stub of a fastapi export entry point (scripts/export-openapi.py) for the seeded contract test: prints the file named by STUB_OUT, then exits with STUB_EXIT.
import os
import sys

if os.environ.get("STUB_OUT"):
    with open(os.environ["STUB_OUT"], encoding="utf-8") as fh:
        sys.stdout.write(fh.read())
if os.environ.get("STUB_ERR"):
    sys.stderr.write(os.environ["STUB_ERR"] + "\n")
sys.exit(int(os.environ.get("STUB_EXIT", "0")))
