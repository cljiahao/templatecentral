# Exclusion fixtures

Each folder is a small project used by `scripts/seeded-exclude-reasons.test.sh` (the seeded gate) and `scripts/exclusion-audit.test.sh` (the migrate audit). A folder name ends in `-none` (an exclude without a reason), `-ok` (the clean control with a reason), or names another case such as `-dynamic` (a list the scanners cannot read).

## Audit bound and CPU figures

The audit reads at most 400 JS, TS and JSON configs per run in one node run, and one small python or awk run per TOML, INI or properties file. The test builds a 150-package project (450 audit lines) and measures user plus system CPU time of the whole runner with the shell `time` keyword. Last measured: 7.02 CPU seconds, budget 30 (set `AUDIT_CPU_BUDGET` to change it). Before the single node run it took 31.21 seconds with one node run per config.
