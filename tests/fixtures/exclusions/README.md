# Exclusion fixtures

Each folder is a small project used by `scripts/seeded-exclude-reasons.test.sh` (the seeded gate) and `scripts/exclusion-audit.test.sh` (the migrate audit). A folder name ends in `-none` (an exclude without a reason), `-ok` (the clean control with a reason), or names another case such as `-dynamic` (a list the scanners cannot read).

## Audit bound and CPU figures

The audit reads at most 400 JS, TS and JSON configs per run in one node run, and one small python or awk run per TOML, INI or properties file. The test builds a 150-package project (450 audit lines) and measures user plus system CPU time of the whole runner with the shell `time` keyword. Last measured: 12.86 CPU seconds on a loaded machine (7.02 on an idle one), budget 30 (set `AUDIT_CPU_BUDGET` to change it). Before the single node run it took 31.21 seconds with one node run per config.

The audit test copies every fixture into one folder and runs the audit once over it, so a fixture's lines are the ones prefixed with its folder name. A copy leaves out files named `.env*` by name. Folders `audit-hides` (hides-source and grouping) and the `*-filler-*`, `*-computed-*`, `*-merge-*`, `nycrc-*`, `c8rc-*`, `jscpd-*`, `defaults-*` and `pkg-*` sets belong to the gate and audit fixes of round 1.

## Round 2 sets (`r2-*`)

Each `r2-*` folder pairs with an `-ok` control. Every finding has a revert proof in `scripts/seeded-exclude-reasons.test.sh` (a mutant copy of the gate with the fix reverted must lose the finding) and, for the audit, in `scripts/exclusion-audit.test.sh`. Sets cover: broad excludes (`r2-broad-*`), unanchored build folders, anchored defaults, build folders beside `package.json` (`r2-pkg-*`), directory symlinks, config variants (`r2-vitest-*`, `r2-codecov-*`, `r2-karma-*`), command-line flags and unread config pointers (`r2-flag-*`, `r2-pointer-*`), Sonar parsing (`r2-sonar-*`), inline coverage markers (`r2-marker-*`), reason shape (`r2-shape-*`), Stryker, coverage source lists, duplicate keys and bad JSON.

Audit limits: the runner prunes `dist`, `build`, `coverage` and `.next` by name before it calls the audit, so a config inside one of them is not handed over; the audit's own file list (`rules_files`) skips no folder by name. It reports a symlink that is not a link to a regular file, and an invalid `package.json` only when the file holds a tool key.

## Round 3 (built at run time)

The round-3 projects are not stored here. `scripts/seeded-exclude-reasons.test.sh` and `scripts/exclusion-audit.test.sh` build them in a temp folder when they run, because a folder such as `.tox`, `env` or `lib` may be hidden by `.gitignore`, an empty folder is not stored, and a git work tree is needed for some cases. Each case has a twin that differs only in the thing under test, and a mutant copy of the gate or audit with the fix undone must lose the finding (or, for a clean control, must start to fail). Cases: broad patterns decided from the files (`src/**/*.[jt]s`, `**/*.(t|j)s`, `**/*.?s`, `src/**/?*`, `src/./**`, `src//**`, `packages/*/src/**`, `apps/web/src/**`, `frontend/src/**`, `my_pkg/**`), the one file list (git work tree or not, a folder holding `pyvenv.cfg`), command lines and the CI, Taskfile, justfile, Dockerfile and shell files they live in, markers as the first token of a comment, normalised defaults, includes that cover a source root, `sonar.*.test.inclusions`, and symlinks.
