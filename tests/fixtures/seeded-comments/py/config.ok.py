import os
# Loads the second module.
import sys

# Settings used by the tool.
SETTINGS = {
    # Where output goes.
    "out": "dist",
    # Which files count.
    "include": [os, sys],
}

# Guards the load.
if os:
    # Registers the hook.
    print(1)
# Falls back below.
try:
    print(2)
# Handles the failure.
except ValueError:
    print(3)
