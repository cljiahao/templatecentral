"""Prints the app's OpenAPI document to stdout, sorted and indented, for the contract gate.

Run from the project root: python3 -I scripts/export-openapi.py > openapi.json
It builds the document from the app object. No server starts, nothing listens on a port and nothing touches the network.
"""

import contextlib
import json
import os
import sys
import tempfile

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, "src")


def build() -> dict:
    """Imports the app with its logs on stderr and no .env file in reach, so the document does not depend on the machine."""
    sys.path.insert(0, os.path.abspath(SRC))
    with tempfile.TemporaryDirectory() as empty, contextlib.redirect_stdout(sys.stderr):
        home = os.getcwd()
        os.chdir(empty)
        try:
            from app import app
        finally:
            os.chdir(home)
    return app.openapi()


if __name__ == "__main__":
    json.dump(build(), sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
