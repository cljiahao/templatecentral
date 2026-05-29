#!/bin/bash
# Blocks agent writes to secrets and CI/CD pipeline files only.
# Skills, specs, and all other project files are unrestricted.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.file_path // .path // empty' 2>/dev/null)

[[ -z "$FILE" ]] && exit 0

if [[ "$FILE" =~ (^|/)\.env(\.[^/]*)?$ ]] || \
   [[ "$FILE" =~ (^|/)\.github/workflows/ ]] || \
   [[ "$FILE" =~ \.(pem|key|p12|pfx|secret)$ ]] || \
   [[ "$FILE" =~ (^|/)(\.secrets|credentials\.json|\.netrc)$ ]]; then
  echo "Protected path — manual edit required: $FILE" >&2
  exit 2
fi

exit 0
