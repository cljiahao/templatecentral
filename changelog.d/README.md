# Changelog fragments

Each PR adds one file here instead of editing `CHANGELOG.md`. `scripts/changelog-assemble.sh` collects the fragments into a release section and deletes them.

File name: `<short-slug>.<category>.md`

- `slug`: lower-case letters, digits and `-`, starting with a letter or digit.
- `category`: `added`, `changed`, `removed`, `fixed` or `security`. A release lists them in that order.
- Content: one or more Markdown bullets, the text you would have put in `CHANGELOG.md`. The first line starts with `- `. Continuation lines start with exactly two spaces. No blank lines; the file ends with a newline.

Example, `changelog.d/sonar-parity-table.added.md`:

```
- Sonar way parity table for the seeded lint configs: `scripts/sonar-parity.tsv`.
```

No subdirectories. `scripts/changelog-check.sh` rejects any other name or layout.

Every PR except the release PR adds a fragment, with no exemption: PRs with no user-facing change and bot PRs included. Describe the change in one bullet.

A fragment passes `cl_content_ok` (`scripts/changelog-lib.sh`), the same rule for the check and the assemble script, which emits each fragment byte for byte. Catches, with the line and the rule named: any control byte but LF (CR, TAB, NUL, ESC, DEL), a last line with no newline, invalid UTF-8 (overlong, surrogate, stray or lone byte), an invisible or reordering character (C1 controls, soft hyphen, zero width, bidi marks and overrides, line and paragraph separators, BOM, tag characters), a blank line; a line that is not `- text` (the first line and after), `  - text` or `  text` (two spaces); text that starts with anything but a letter, a digit, a backtick, `[`, `(`, `"`, `'`, or `#` and a digit (a PR reference such as `#96`), has no letter or digit or starts like a list marker (`1.`, `1)`); a backtick count that is odd on a line, two backticks in a row, a backslash before a backtick; outside backtick spans, `<` before a letter, `/`, `!` or `?` (raw HTML, comment, CDATA, processing instruction, autolink) `](`, `][` or `] [` (a link destination or label), `]:` anywhere (a link reference definition) and a `[` or `]` that does not balance on its line (a label cannot run over a line break or hide behind a backslash). So a heading, quote, fence, thematic break, setext underline, table or HTML block is rejected, and the script and Markdown agree on every line break and every code span. Does not catch: a fragment whose text is wrong or meaningless; inline Markdown inside a valid line that cannot open a block or hide a backtick (emphasis, entity references, bare URLs of any scheme, `www.` hosts and email addresses, look-alike letters (homoglyphs) and combining marks, task boxes, a backslash before another character, a `[text]` that a `[text]:` definition elsewhere in `CHANGELOG.md` turns into a link, trailing spaces); a fragment under the wrong category; a fragment that duplicates another fragment's text.

A PR may add fragments only. It may not edit or delete a fragment that already exists on the base, because a fragment belongs to the PR that added it (status M or D is rejected). Only the release PR deletes fragments.

A normal PR may edit `.claude-plugin/plugin.json` and `.claude/harness.json` but may not change the `version` or `templatecentral_version` value; that happens only in the release PR. It may not delete either file or change its type either, and each copy (merge base and head) must have exactly one version line, on a line of its own: minified JSON and a repeated key fail.

`## [Unreleased]` in `CHANGELOG.md` stays empty. Put every entry in a fragment, never under that heading: `scripts/changelog-check.sh` fails a PR that leaves an entry there, and `scripts/changelog-assemble.sh` refuses to run while one is there. A PR that only moves existing `[Unreleased]` entries into fragments passes if every moved entry is a line of an added fragment.

## Release PR

The release PR is the only PR that edits `CHANGELOG.md` otherwise.

1. Run `bash scripts/changelog-assemble.sh <N.N.N> <YYYY-MM-DD>`. It writes the release section and deletes every fragment.
2. Bump `.claude-plugin/plugin.json` `version` and `.claude/harness.json` `templatecentral_version` to `N.N.N`, higher than before. Change nothing else in those files.
3. Touch no other file. A release does not need one: golden hashes and the README do not carry the version.

`scripts/changelog-check.sh` replays step 1 on the merge base and needs the result to match `CHANGELOG.md` byte for byte. Its header has the numbered release rules; a failure names the rule.
