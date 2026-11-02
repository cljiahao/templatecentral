<!-- ref: scaffold/shared/user-choices.md
     loaded-by: scaffold/SKILL.md Step 1
     prereq: Stack identified and the Step 1 inputs settled. Do not invoke this file directly — it is loaded at runtime by the templatecentral:scaffold skill. -->

# Scaffold Step 1 — user choices

Ask these together, in one message, and only for what the user has not already answered. Each has a default, which applies when the user does not choose. Record the answers: the stack guide and the shared kit use them instead of asking again, and ask only for a choice left open here.

- extra project skills — any repeated workflow to capture as a project skill beyond the verify skills the template ships (the stack guide lists candidates). Default: none.
- `CLAUDE.md` — whether the user works in Claude Code, so the guide writes a one-line `CLAUDE.md` that imports `AGENTS.md`. Default: yes when this scaffold runs in Claude Code, otherwise no.
- task management — whether to append the structured task-management section to `AGENTS.md`. Default: no.
- remove example code — whether to delete the example feature with the cleanup utility once the project is verified and runs. Default: no; the example stays until the user removes it.
- Azure DevOps Code Wiki (`adoWiki`) — whether the repo is published as an Azure DevOps Code Wiki, so every folder also gets a `.order` file and a wiki-page file. Default: no.
- rich READMEs (`richReadme`) — whether per-folder READMEs describe each file from its contents, which stays accurate only while README enforcement is on, rather than listing file names. Default: no.
- post-scaffold checks — the build, test, dependency-update and review utilities run after the harness is seeded. Default: run them. Skipping them leaves problems undetected, so tell the user that and skip only on their explicit confirmation.
- Claude Code plugins — whether to install the `caveman` and `superpowers` plugins (user-scoped). Default: install them when this scaffold runs in Claude Code.
