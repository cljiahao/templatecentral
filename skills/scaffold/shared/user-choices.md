<!-- ref: scaffold/shared/user-choices.md
     loaded-by: scaffold/SKILL.md Step 1
     prereq: Stack identified and the Step 1 inputs settled. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->

# Scaffold Step 1 — user choices

Ask these together, in one message, and only for what the user has not already answered. Each has a default, which applies when the user does not choose. Record the answers: the stack guide and the shared kit use them instead of asking again, and ask only for a choice left open here.

- `CLAUDE.md` — whether the user works in Claude Code, so the guide writes a one-line `CLAUDE.md` that imports `AGENTS.md`. Default: yes when this scaffold runs in Claude Code, otherwise no.
- task management — whether to append the structured task-management section to `AGENTS.md`. Default: no.
- remove example code — whether to delete the example feature with the cleanup utility once the project is verified and runs. Default: no; the example stays until the user removes it.
- Azure DevOps Code Wiki (`adoWiki`) — whether `docs/` is published as a wiki, so it also gets a `.order` file. Default: no.
- post-scaffold checks — the check command, test, dependency-update and review utilities run after the harness is seeded. Default: run them. Skipping them leaves problems undetected, so tell the user that and skip only on their explicit confirmation.
- Claude Code plugins — whether to install the `caveman` and `superpowers` plugins (user-scoped). Default: no.
