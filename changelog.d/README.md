# Changelog fragments

Each PR adds one file here instead of editing `CHANGELOG.md`. `scripts/changelog-assemble.sh` collects the fragments into a release section and deletes them.

File name: `<short-slug>.<category>.md`

- `slug`: lower-case letters, digits and `-`, starting with a letter or digit.
- `category`: `added`, `changed`, `fixed` or `security`.
- Content: one or more Markdown bullets, the text you would have put in `CHANGELOG.md`. The first line starts with `- `. Continuation lines are indented.

Example, `changelog.d/sonar-parity-table.added.md`:

```
- Sonar way parity table for the seeded lint configs: `scripts/sonar-parity.tsv`.
```

No subdirectories. `scripts/changelog-check.sh` rejects any other name or layout.

Every PR adds a fragment, with no exemption: PRs with no user-facing change and bot PRs included. Describe the change in one bullet.

Fragments cannot contain heading lines or code fences. Continuation lines that start with `#`, three backticks or `~~~` are rejected.

## Release PR

The release PR is the only PR that edits `CHANGELOG.md`.

1. Run `bash scripts/changelog-assemble.sh <N.N.N> <YYYY-MM-DD>`. It writes the release section and deletes every fragment.
2. Bump `.claude-plugin/plugin.json` `version` and `.claude/harness.json` `templatecentral_version` to `N.N.N`.
3. Touch nothing else except the allow-listed release files: `README.md`, `skills/scaffold/shared/harness-kit-finalize.md` and `tests/golden/<name>.sha256` (regenerated hashes). Header of `scripts/changelog-check.sh` has the rules.

`scripts/changelog-check.sh` replays step 1 on the merge base and needs the result to match `CHANGELOG.md` byte for byte.
