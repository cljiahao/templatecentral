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
