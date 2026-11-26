# Changelog fragments

Each PR adds one file here instead of editing `CHANGELOG.md`. `scripts/changelog-assemble.sh` collects the fragments into a release section and deletes them.

File name: `<short-slug>.<category>.md`

- `slug`: lower-case letters, digits and `-`, starting with a letter or digit.
- `category`: `added`, `changed`, `removed`, `fixed` or `security`. A release lists them in that order.
- Content: one or more Markdown bullets, the text you would have put in `CHANGELOG.md`. The first line starts with a bullet marker (`- `, `* `, `+ `, `1. ` or `1) `). Continuation lines are indented or start with a marker.

Example, `changelog.d/sonar-parity-table.added.md`:

```
- Sonar way parity table for the seeded lint configs: `scripts/sonar-parity.tsv`.
```

No subdirectories. `scripts/changelog-check.sh` rejects any other name or layout.

Every PR except the release PR adds a fragment, with no exemption: PRs with no user-facing change and bot PRs included. Describe the change in one bullet.

Fragments cannot contain heading lines, code fences or thematic breaks. A line is rejected when, after the indent and any number of bullet markers (`-`, `*`, `+`, `1.`, `1)`, each followed by a space), its text starts with `#` and no digit, three backticks or `~~~`, or is a break: three or more `-`, `=`, `*` or `_` (same character, spaces allowed, so `- - -` and `* * *` count). `- --flag is new`, `- **bold** text` and `- #96 fixed` (a `#` and a digit is a PR reference) are fine. Not caught: Markdown that is not a heading, fence or break, such as a table, a quote, a link reference or raw HTML; `Setext` underlines of one or two characters (`-`, `==`); a heading marker after a non-marker token, for example `- (# x`.

A PR may add fragments only. It may not edit or delete a fragment that already exists on the base, because a fragment belongs to the PR that added it (status M or D is rejected). Only the release PR deletes fragments.

A normal PR may edit `.claude-plugin/plugin.json` and `.claude/harness.json` but may not change the `version` or `templatecentral_version` value; that happens only in the release PR. It may not delete either file or change its type either, and each copy (merge base and head) must have exactly one version line, on a line of its own: minified JSON and a repeated key fail.

`## [Unreleased]` in `CHANGELOG.md` stays empty. Put every entry in a fragment, never under that heading: `scripts/changelog-check.sh` fails a PR that leaves an entry there, and `scripts/changelog-assemble.sh` refuses to run while one is there. A PR that only moves existing `[Unreleased]` entries into fragments passes if every moved entry is a line of an added fragment.

## Release PR

The release PR is the only PR that edits `CHANGELOG.md` otherwise.

1. Run `bash scripts/changelog-assemble.sh <N.N.N> <YYYY-MM-DD>`. It writes the release section and deletes every fragment.
2. Bump `.claude-plugin/plugin.json` `version` and `.claude/harness.json` `templatecentral_version` to `N.N.N`, higher than before. Change nothing else in those files.
3. Touch no other file. A release does not need one: golden hashes and the README do not carry the version.

`scripts/changelog-check.sh` replays step 1 on the merge base and needs the result to match `CHANGELOG.md` byte for byte. Its header has the numbered release rules; a failure names the rule.
