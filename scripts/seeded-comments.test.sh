#!/usr/bin/env bash
# scripts/seeded-comments.test.sh — tests for the seeded scripts/check-comments.sh (and its node and python readers).
# Typescript: TC_TEST_TYPESCRIPT_DIR (a typescript package folder), else the exact version pinned in skills/scaffold/shared/versions.txt
# is installed once from the public npm registry (no login) into a cache folder under TMPDIR and reused.
# Usage: bash scripts/seeded-comments.test.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$REPO_ROOT/skills/scaffold/shared"
GATE="$SHARED/template/scripts/check-comments.sh"
FIX="$REPO_ROOT/tests/fixtures/seeded-comments"

PASS=0
FAIL=0
check() { # check <want> <got> <description>
  if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — expected [$1], got [$2]"; fi
}
has() { # has <needle> <haystack> <description>
  if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] not in [$2]"; fi
}
lacks() { # lacks <needle> <haystack> <description>
  if [[ "$2" != *"$1"* ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $3 — [$1] found in [$2]"; fi
}

T=$(mktemp -d "${TMPDIR:-/tmp}/sc.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT

TS_VERSION=$(awk '$1 == "npm" && $2 == "typescript" { v = $3; gsub(/[^0-9.]/, "", v); print v }' "$SHARED/versions.txt")
if [[ -z "$TS_VERSION" ]]; then
  echo "seeded-comments.test: no typescript version pinned in skills/scaffold/shared/versions.txt." >&2
  exit 2
fi
TS_CACHE="${TMPDIR:-/tmp}/tc-seeded-comments-typescript-$TS_VERSION"
TSPKG=${TC_TEST_TYPESCRIPT_DIR:-}
if [[ -n "$TSPKG" ]]; then
  if [[ ! -f "$TSPKG/package.json" && -f "$TSPKG/node_modules/typescript/package.json" ]]; then TSPKG=$TSPKG/node_modules/typescript; fi
  if [[ ! -f "$TSPKG/package.json" ]]; then
    echo "seeded-comments.test: TC_TEST_TYPESCRIPT_DIR has no typescript package. Fix: point it at a typescript package folder, or unset it to install the pinned version." >&2
    exit 2
  fi
else
  TSPKG=$TS_CACHE/node_modules/typescript
  if [[ ! -f "$TSPKG/package.json" ]]; then
    if ! command -v npm > /dev/null 2>&1; then
      echo "seeded-comments.test: npm is missing, so typescript $TS_VERSION cannot be installed. Fix: install Node.js, or set TC_TEST_TYPESCRIPT_DIR to a typescript package folder." >&2
      exit 2
    fi
    stage=$(mktemp -d "$TS_CACHE.stage.XXXXXX") || exit 2
    if ! npm install --prefix "$stage" --cache "$stage.cache" --no-audit --no-fund --ignore-scripts --loglevel=error "typescript@$TS_VERSION" > "$stage.log" 2>&1; then
      echo "seeded-comments.test: npm install typescript@$TS_VERSION failed: $(tail -n 1 "$stage.log"). Fix: check network access to the public npm registry, or set TC_TEST_TYPESCRIPT_DIR." >&2
      rm -rf "$stage" "$stage.log"
      exit 2
    fi
    rm -f "$stage.log"
    if [[ -f "$TSPKG/package.json" ]]; then rm -rf "$stage"; else mv "$stage" "$TS_CACHE"; fi
  fi
  got_version=$(node -p "require('$TSPKG/package.json').version" 2> /dev/null || true)
  if [[ "$got_version" != "$TS_VERSION" ]]; then
    echo "seeded-comments.test: cached typescript is $got_version, pinned is $TS_VERSION. Fix: delete $TS_CACHE and re-run." >&2
    exit 2
  fi
fi
mkdir -p "$T/tsroot/node_modules"
ln -s "$TSPKG" "$T/tsroot/node_modules/typescript"

CLEAN_ENV=(env -u CI -u GITHUB_ACTIONS -u TF_BUILD -u BASE_REF -u GITHUB_BASE_REF -u SYSTEM_PULLREQUEST_TARGETBRANCH -u SYSTEM_PULLREQUEST_TARGETBRANCHNAME -u NODE_PATH)

# gate <dir> [args...] — runs the gate with no CI markers over a folder in --all mode; sets OUT and EC.
gate_all() {
  local d=$1
  shift
  OUT=$("${CLEAN_ENV[@]}" bash "$GATE" --root "$d" --ts-from "$T/tsroot" "$@" --all . 2>&1)
  EC=$?
}

# one_file <fixture> — copies one fixture into its own folder and judges it.
one_file() {
  local d
  d=$(mktemp -d "$T/one.XXXXXX")
  cp "$FIX/$1" "$d/"
  gate_all "$d" --full
}

# expect_rule <fixture> <rule> <line> — the bad fixture yields exactly that one finding.
expect_rule() {
  one_file "$1"
  local base=${1##*/}
  check 1 "$EC" "$1: exits 1"
  check 1 "$(printf '%s\n' "$OUT" | grep -c ': comments/')" "$1: one finding ($OUT)"
  has "$base:$3: comments/$2:" "$OUT" "$1: names file, line and rule"
  has "Fix:" "$OUT" "$1: names the fix"
}

expect_clean() {
  one_file "$1"
  check 0 "$EC" "$1: clean control exits 0 ($OUT)"
  has "check-comments: ok" "$OUT" "$1: ok line"
}

for lang in ts py; do
  ext=$lang
  expect_rule "$lang/trailing.bad.$ext" trailing 1
  expect_clean "$lang/trailing.ok.$ext"
  expect_rule "$lang/body.bad.$ext" placement 2
  expect_clean "$lang/body.ok.$ext"
  expect_rule "$lang/length.bad.$ext" length 1
  expect_clean "$lang/length.ok.$ext"
  expect_rule "$lang/aside.bad.$ext" aside 1
  expect_clean "$lang/aside.ok.$ext"
  expect_rule "$lang/bracketed.bad.$ext" bracketed 1
  expect_clean "$lang/bracketed.ok.$ext"
  expect_clean "$lang/strings.ok.$ext"
  expect_clean "$lang/directives.ok.$ext"
done
expect_clean ts/jsx.ok.tsx
expect_rule ts/jsx.bad.tsx placement 2
expect_clean ts/config.ok.ts
expect_rule ts/list.bad.ts placement 3
expect_clean ts/list.ok.ts
expect_rule ts/arrow.bad.ts placement 2
expect_rule ts/nested.bad.ts placement 3
expect_clean ts/jsdoc.ok.ts
expect_rule ts/jsdoc.bad.ts length 1
expect_clean ts/coderef.ok.ts
expect_clean py/config.ok.py
expect_rule py/list.bad.py placement 3
expect_clean py/list.ok.py
expect_clean py/stub.ok.pyi
expect_rule py/stub.bad.pyi trailing 1
expect_rule py/nested.bad.py placement 3
expect_clean py/docstring.ok.py
expect_rule py/docstring.bad.py length 2
expect_clean py/coderef.ok.py

# inline <file> <content> — writes a one-file project (content goes through printf %b) and judges it; sets OUT and EC.
inline() {
  local d
  d=$(mktemp -d "$T/inl.XXXXXX")
  printf '%b' "$2" > "$d/$1"
  gate_all "$d" --full
}
# inline_rule <file> <rule> <line> <content> — exactly one finding of that rule at that line.
inline_rule() {
  inline "$1" "$4"
  check 1 "$EC" "$1 [$2]: exits 1 ($OUT)"
  check 1 "$(printf '%s\n' "$OUT" | grep -c ': comments/')" "$1 [$2]: one finding ($OUT)"
  has "$1:$3: comments/$2:" "$OUT" "$1 [$2]: names file, line and rule"
}
inline_clean() {
  inline "$1" "$2"
  check 0 "$EC" "$1: clean control exits 0 ($OUT)"
}

# directive lookalikes are prose and stay judged
inline_rule a.ts aside 1 '// eslint-disable-line -- see (note) essay prose here\nexport const a = 1;\n'
inline_rule a.ts aside 1 '// This explains the thing @ts-ignore (aside here)\nexport const a = 1;\n'
inline_rule a.ts aside 1 '// pragma is the thing (aside)\nexport const a = 1;\n'
inline_rule a.py directive 1 'x = 1  # noqa: this is an essay\n'
inline_rule a.ts length 1 '// note one @ts-ignore\n// note two @ts-ignore\n// note three @ts-ignore\n// note four @ts-ignore\n// note five @ts-ignore\nexport const a = 1;\n'
inline_rule a.ts length 1 '// @ts-expect-error because of reason one\n// @ts-expect-error because of reason two\n// @ts-expect-error because of reason three\n// @ts-expect-error because of reason four\n// @ts-expect-error because of reason five\nexport const a: number = "x";\n'
inline_rule a.py length 1 '# noqa: E501 -- because of reason one\n# noqa: E501 -- because of reason two\n# noqa: E501 -- because of reason three\n# noqa: E501 -- because of reason four\n# noqa: E501 -- because of reason five\nA = 1\n'
rlong=$(printf 'ab%02d ' $(seq 1 16))
rlong=${rlong% }
rok=$(printf 'ab%02d ' $(seq 1 12))
rok=${rok% }
inline_rule a.ts length 1 "// @ts-ignore $rlong\nexport const a = 1;\n"
inline_rule a.py length 2 "A = 1\n# noqa: E501 -- $rlong\nB = 2\n"
inline_rule a.ts length 1 '/* eslint-disable no-console -- first part of the reason\n   second part */\nexport const a = 1;\n'
inline_rule a.ts aside 1 '// @ts-ignore explained here (aside)\nexport const a = 1;\n'
inline_clean a.ts "// @ts-ignore $rok\nexport const a: number = 'x';\n"
inline_clean a.ts '// eslint-disable-next-line no-console -- logs the boot banner\nexport const a = 1;\n'
inline_clean a.py 'import os  # noqa: F401 -- kept for the plugin\n'
inline_clean a.ts 'export const a = 1; // eslint-disable-line no-console, no-undef -- logs once at boot\n'

# a suppressing directive carries a reason, in the form the message states
inline_rule a.py directive 1 'x = 1  # noqa\n'
inline_rule a.py directive 1 'x = 1  # noqa: E501\n'
inline_rule a.py directive 1 'x: int = "a"  # type: ignore\n'
inline_rule a.py directive 1 'x: int = "a"  # type: ignore[assignment]\n'
inline_rule a.py directive 1 'x: int = "a"  # pyright: ignore[reportAssignmentType]\n'
inline_rule a.py directive 2 'def f():\n    return 1  # pragma: no cover\n'
inline_rule a.py directive 1 'x = 1  # nosec B101\n'
inline_rule a.py directive 1 'x = 1  # NOSONAR\n'
inline_rule a.py directive 1 'key = "k"  # gitleaks:allow\n'
inline_rule a.ts directive 1 '// @ts-ignore\nexport const a: number = "x";\n'
inline_rule a.ts directive 1 '// @ts-expect-error\nexport const a: number = "x";\n'
inline_rule a.ts directive 1 '// @ts-nocheck\nexport const a = 1;\n'
inline_rule a.ts directive 1 'export const a = 1; // eslint-disable-line no-console\n'
inline_rule a.ts directive 1 '// eslint-disable-next-line\nexport const a = 1;\n'
inline_rule a.ts directive 1 '/* istanbul ignore next */\nexport const h = 1;\n'
inline_rule a.ts directive 1 '// c8 ignore next\nexport const h = 1;\n'
inline_rule a.ts directive 1 'export const a = 1; // NOSONAR\n'
inline_rule a.ts directive 1 "export const k = 'k'; // gitleaks:allow\n"
inline_rule a.ts directive 1 '// biome-ignore lint/suspicious/noExplicitAny\nexport const a = 1;\n'
inline_clean a.py 'x: int = "a"  # type: ignore[assignment]  # legacy shape of the data\n'
inline_clean a.py 'x: int = "a"  # pyright: ignore[reportAssignmentType]  # legacy shape of the data\n'
inline_clean a.py 'def f():\n    return 1  # pragma: no cover -- exercised by the e2e run\n'
inline_clean a.ts '// @ts-nocheck legacy file from the vendor\nexport const a = 1;\n'
inline_clean a.ts '/* istanbul ignore next -- guarded by the caller */\nexport const h = 1;\n'
inline_clean a.ts 'export function g() {\n  return 1; // NOSONAR -- reviewed by the owner\n}\n'
inline_clean a.ts '/* eslint-enable no-console */\n// prettier-ignore\nexport const m = [1, 0, 0, 1];\n'
inline_clean a.py 'x = 1  # fmt: skip\n'

# a Python docstring cannot hide prose behind a section header
inline_rule a.py length 2 'def f(a):\n    """Summary.\n\n    Args:\n        a: one\n    prose line a\n    prose line b\n    prose line c\n    prose line d\n    """\n    return 1\n'
inline_rule a.py length 2 'def f(a):\n    """Summary.\n\n    Args:\n        a: one\n            cont 1\n            cont 2\n            cont 3\n            cont 4\n            cont 5\n    """\n    return 1\n'
inline_clean a.py 'def f(a, b, c, d):\n    """Summary.\n\n    Args:\n        a: one\n        b (int): two\n            wraps here\n        c: three\n        d: four\n    Returns:\n        The sum.\n    """\n    return 1\n'
inline_rule a.py length 2 'def f():\n    """Summary.\n\n    Returns:\n        prose a\n        prose b\n        prose c\n        prose d\n    """\n    return 1\n'

# round 3: an entry is exempt only when it names a real parameter, attribute, exception or return, once
notes40=''
fields40=''
dups40=''
for n in $(seq 1 40); do
  notes40="$notes40        Note$n: long prose text here\n"
  fields40="$fields40    :param$n: prose prose\n"
  dups40="$dups40        a: again\n"
done
inline_rule a.py length 2 "def f(a):\n    \"\"\"Summary.\n\n    Args:\n$notes40    \"\"\"\n    return a\n"
inline_rule a.py length 2 "def f(a):\n    \"\"\"Summary.\n\n$fields40    \"\"\"\n    return a\n"
inline_rule a.py length 2 "def f(a):\n    \"\"\"Summary.\n\n    Args:\n$dups40    \"\"\"\n    return a\n"
inline_rule a.py length 2 'def f(a):\n    """Summary.\n\n    :param a: the value\n    :param zz: not a parameter\n    :param yy: not a parameter\n    :param xx: not a parameter\n    """\n    return a\n'
inline_clean a.py 'def f(a, b):\n    """Summary.\n\n    :param a: the value\n    :param int b: the other value\n    :type a: int\n    :returns: the sum\n    :raises ValueError: when empty\n    """\n    if not a:\n        raise ValueError("empty")\n    return a + b\n'
inline_clean a.py 'def f(a, *args, **kw) -> int:\n    """Summary.\n\n    Args:\n        a: first\n        *args: rest\n        **kw: options\n\n    Returns:\n        int: the count\n\n    Raises:\n        ValueError: when empty\n    """\n    if not a:\n        raise ValueError("empty")\n    return 1\n'
inline_clean a.py 'class C:\n    """Summary.\n\n    Attributes:\n        size: how many\n    """\n\n    size = 1\n'
inline_rule a.py length 2 'def f(a):\n    """Summary.\n\n    Args:\n        a: first prose line that is far too long to be one short entry line for a parameter so it counts as prose and not as an entry here\n        a2: x\n        a3: y\n    """\n    return a\n'

# round 3: a directive reason has at least three words, is not only filler, and stays short
inline_rule a.py directive 1 'x = 1  # noqa: E501 -- x\n'
inline_rule a.py directive 1 'x: int = "a"  # type: ignore[misc]  # TODO\n'
inline_rule a.py directive 1 'x = 1  # noqa: E501 -- TODO fix\n'
inline_rule a.ts directive 1 '// @ts-ignore TODO\nexport const a: number = "x";\n'
inline_rule a.ts directive 1 '// eslint-disable-next-line no-console -- x\nexport const a = 1;\n'
inline_rule a.ts directive 1 '/* istanbul ignore next -- FIXME */\nexport const h = 1;\n'
inline_rule a.py directive 1 'x = 1  # noqa: E501 -- TODO fix it\n'
inline_clean a.py 'x = 1  # noqa: E501 -- TODO fix the long line\n'
inline_clean a.ts '// @ts-ignore stale vendor typings\nexport const a: number = "x";\n'
r79=$rlong
r59=$rok
inline_rule a.py length 2 "def f():\n    return 1  # pragma: no cover -- $r79\n"
inline_rule a.ts length 2 "export function f() {\n  return 1; // NOSONAR -- $r79\n}\n"
inline_clean a.py "def f():\n    return 1  # pragma: no cover -- $r59\n"

# stubs are judged like other Python
inline_rule a.pyi trailing 1 'a: int  # the value\n'
inline_clean a.pyi 'a: int\n'

# JSDoc tag lines are capped
tags10=''
tags11=''
for n in 1 2 3 4 5 6 7 8 9 10; do tags10="$tags10 * @param p$n value\n"; done
tags11="$tags10 * @param p11 value\n"
inline_clean a.ts "/**\n * Summary.\n$tags10 */\nexport function f(p1: number) {\n  return p1;\n}\n"
inline_rule a.ts length 1 "/**\n * Summary.\n$tags11 */\nexport function f(p1: number) {\n  return p1;\n}\n"

# comments before the first token total at most one chain, except a licence header
inline_rule a.ts length 1 '// one\n\n// two\n\n// three\n\n// four\nexport const a = 1;\n'
inline_rule a.py length 1 '# one\n\n# two\n\n# three\n\n# four\nA = 1\n'
inline_rule a.ts length 1 '// Licensed under the MIT License.\n// two\n// three\n// four\nexport const a = 1;\n'

# the licence exemption covers copyright and SPDX lines and unbroken quotes of known licence texts only
prose80=''
for n in $(seq 1 80); do prose80="$prose80# note $n about the thing\n"; done
prose80ts=${prose80//#/\/\/}
inline_rule a.py length 1 "# Copyright 2020\n${prose80}A = 1\n"
inline_rule a.ts length 1 "// Copyright 2020\n${prose80ts}export const a = 1;\n"
inline_rule a.py length 1 '# Copyright 2020\n# note one about it\n# note two about it\n# note three about it\n# note four about it\nA = 1\n'
inline_clean a.py '# Copyright 2020\n# note one about it\n# note two about it\nA = 1\n'
inline_clean a.ts '/*\n * Copyright 2020 Example Corp.\n *\n * Licensed under the Apache License, Version 2.0 (the "License");\n * you may not use this file except in compliance with the License.\n * You may obtain a copy of the License at\n *\n *     http://www.apache.org/licenses/LICENSE-2.0\n *\n * Unless required by applicable law or agreed to in writing, software\n * distributed under the License is distributed on an "AS IS" BASIS,\n * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.\n * See the License for the specific language governing permissions and\n * limitations under the License.\n */\nexport const a = 1;\n'

# wrap_style <slash|star|hash> <width> <text> — prints the text as a comment block wrapped at the width.
wrap_style() {
  local style=$1 width=$2 text=$3 line out=''
  [[ "$style" != star ]] || out="/*"$'\n'
  while IFS= read -r line; do
    case "$style" in
      slash) out="$out// $line"$'\n' ;;
      hash) out="$out# $line"$'\n' ;;
      star) out="$out * $line"$'\n' ;;
    esac
  done < <(printf '%s\n' "$text" | fold -s -w "$width")
  [[ "$style" != star ]] || out="$out */"$'\n'
  printf '%s' "$out"
}
# inline_fails <file> <rule> <content> — exits 1 and names the rule, other findings allowed.
inline_fails() {
  inline "$1" "$3"
  check 1 "$EC" "$1 [$2]: exits 1 ($OUT)"
  has "comments/$2:" "$OUT" "$1 [$2]: names the rule"
}
NL=$'\n'
MIT_TEXT='MIT License Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.'
APACHE_TEXT='Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.'
BSD3_TEXT='Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met: 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer. 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution. 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission. THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.'
for spec in "MIT_TEXT:MIT" "APACHE_TEXT:Apache" "BSD3_TEXT:BSD3"; do
  case "${spec%%:*}" in
    MIT_TEXT) body=$MIT_TEXT ;;
    APACHE_TEXT) body=$APACHE_TEXT ;;
    *) body=$BSD3_TEXT ;;
  esac
  for form in "slash:60:a.ts" "star:80:a.ts" "hash:100:a.py" "hash:48:a.py" "star:50:a.ts"; do
    style=${form%%:*}
    rest=${form#*:}
    width=${rest%%:*}
    file=${rest#*:}
    tail_code='export const a = 1;'
    [[ "$file" != a.py ]] || tail_code='A = 1'
    head=$(wrap_style "$style" 200 "Copyright (c) 2024 Example Corp.")$NL
    block=$(wrap_style "$style" "$width" "$body")$NL
    block_more=$(wrap_style "$style" "$width" "$body This file also parses the config.")$NL
    inline_clean "$file" "$head$block$tail_code\n"
    inline_fails "$file" length "$head$block_more$tail_code\n"
  done
done
inline_clean a.ts "$(wrap_style slash 200 'SPDX-License-Identifier: MIT')${NL}export const a = 1;\n"
inline_clean a.py "$(wrap_style hash 200 'Copyright 2024 Example Corp. All rights reserved.')${NL}A = 1\n"
# a header form is exempt from the line count, so one more comment line than the limit passes only when the form is read as a header
inline_clean a.ts '// note one about it\n// note two about it\n// note three about it\n// Copyright 2020-present Example Corp.\nexport const a = 1;\n'
inline_fails a.ts length '// note one about it\n// note two about it\n// note three about it\n// Copyright 2020-presently Example Corp.\nexport const a = 1;\n'
inline_clean a.py '# note one about it\n# note two about it\n# note three about it\n# Copyright 2020-present Example Corp.\nA = 1\n'
inline_fails a.py length '# note one about it\n# note two about it\n# note three about it\n# Copyright 2020-presently Example Corp.\nA = 1\n'
inline_clean a.ts '// note one about it\n// note two about it\n// note three about it\n// Copyright 2024 Example Corp. <https://example.com/about>\nexport const a = 1;\n'
inline_fails a.ts length '// note one about it\n// note two about it\n// note three about it\n// Copyright 2024 Example Corp. <https://example.com/about\nexport const a = 1;\n'
inline_clean a.py '# note one about it\n# note two about it\n# note three about it\n# Copyright 2024 Example Corp. <https://example.com/about>\nA = 1\n'
inline_fails a.py length '# note one about it\n# note two about it\n# note three about it\n# Copyright 2024 Example Corp. <https://example.com/about\nA = 1\n'
inline_clean a.ts '// note one about it\n// note two about it\n// note three about it\n// SPDX-License-Identifier: LicenseRef-Example-Terms\nexport const a = 1;\n'
inline_fails a.ts length '// note one about it\n// note two about it\n// note three about it\n// SPDX-License-Identifier: LicenseRef-\nexport const a = 1;\n'
inline_clean a.py '# note one about it\n# note two about it\n# note three about it\n# SPDX-License-Identifier: MIT OR LicenseRef-Example-Terms\nA = 1\n'
inline_fails a.py length '# note one about it\n# note two about it\n# note three about it\n# SPDX-License-Identifier: LicenseRef-Example-Terms AND\nA = 1\n'
# keyword-stuffed prose is not a licence
inline_fails a.ts length '// Copyright 2024\n// Permission is needed from the basis owner.\n// See https://x.y for the Warranty terms.\n// Our liability is limited here.\n// Redistribution is not allowed.\nexport const a = 1;\n'
inline_fails a.py length '# Copyright 2024\n# Permission is needed from the basis owner.\n# See https://x.y for the Warranty terms.\n# Our liability is limited here.\n# Redistribution is not allowed.\nA = 1\n'
inline_fails a.ts length '// MIT License\n// Our own notes on the MIT License follow.\n// Second note.\n// Third note.\nexport const a = 1;\n'
inline_clean a.ts '// MIT License\nexport const a = 1;\n'
# at most three copyright lines and 40 licence lines
inline_fails a.py length '# Copyright 2001\n# Copyright 2002\n# Copyright 2003\n# Copyright 2004\n# Copyright 2005\n# Copyright 2006\nA = 1\n'
inline_fails a.py length '# Copyright 2001\n# Copyright 2002\n# Copyright 2003\n# Copyright 2004\nA = 1\n'
inline_clean a.py '# Copyright 2001\n# Copyright 2002\n# Copyright 2003\nA = 1\n'
inline_fails a.py length "$(wrap_style hash 25 "$BSD3_TEXT")${NL}A = 1\n"
inline_clean a.py "$(wrap_style hash 100 "$BSD3_TEXT")${NL}A = 1\n"

# round 4: JSDoc tag lines are counted over the whole chain, and only known tags are uncounted
six=''
for _ in 1 2 3 4 5 6; do six="$six/**\n$tags10 */\n"; done
inline_rule a.ts length 1 "${six}export function f(p1: number) {\n  return p1;\n}\n"
tags5=''
for n in 1 2 3 4 5; do tags5="$tags5 * @param p$n value\n"; done
inline_clean a.ts "/**\n$tags5 */\n/**\n$tags5 */\nexport function f(p1: number) {\n  return p1;\n}\n"
rem10=''
for n in 1 2 3 4 5 6 7 8 9 10; do rem10="$rem10 * @remarks arbitrary prose $n\n"; done
inline_rule a.ts length 1 "/**\n$rem10 */\nexport function f() {\n  return 1;\n}\n"
inline_clean a.ts "/**\n * @remarks one line\n * @example two\n */\nexport function f() {\n  return 1;\n}\n"
inline_rule a.ts length 1 "/**\n * @bogus one\n * @bogus two\n * @bogus three\n * @bogus four\n */\nexport function f() {\n  return 1;\n}\n"

# round 4: reason words need a letter and two characters, and cannot all be the same
inline_rule a.py directive 1 'x = 1  # noqa: E501 -- _ _ _\n'
inline_rule a.py directive 1 'x = 1  # noqa: E501 -- 1 2 3\n'
inline_rule a.py directive 1 'x = 1  # noqa: E501 -- x x x\n'
inline_rule a.py directive 1 'x = 1  # noqa: E501 -- foo foo FOO\n'
inline_clean a.py 'x = 1  # noqa: E501 -- keep this one here\n'
inline_rule a.ts directive 1 '// eslint-disable-next-line no-console -- _ _ _\nexport const a = 1;\n'
inline_rule a.ts directive 1 '// @ts-ignore 1 2 3\nexport const a: number = "x";\n'
inline_rule a.ts directive 1 '// @ts-ignore foo foo foo\nexport const a: number = "x";\n'
inline_clean a.ts '// @ts-ignore keep this one here\nexport const a: number = "x";\n'

# round 4: docstring entries are judged against the right scope
inline_rule a.py length 2 'def f(a):\n    """Summary.\n\n    Attributes:\n        v1: x\n        v2: y\n        v3: z\n    """\n    v1 = 1\n    v2 = 2\n    v3 = 3\n    return a\n'
inline_clean a.py 'class C:\n    """Summary.\n\n    Attributes:\n        v1: x\n        v2: y\n        v3: z\n    """\n\n    def __init__(self):\n        self.v1 = 1\n        self.v2 = 2\n        self.v3 = 3\n'
inline_rule a.py length 2 'class C:\n    """Summary.\n\n    Attributes:\n        v1: x\n        v2: y\n        v3: z\n    """\n\n    def run(self):\n        v1 = 1\n        v2 = 2\n        v3 = 3\n        return v1 + v2 + v3\n'
inline_rule a.py length 1 '"""Mod.\n\nAttributes:\n    v1: x\n    v2: y\n    v3: z\n"""\n\n\ndef g():\n    v1 = 1\n    v2 = 2\n    v3 = 3\n    return v1 + v2 + v3\n'
inline_clean a.py '"""Mod.\n\nAttributes:\n    v1: x\n    v2: y\n    v3: z\n"""\n\nv1 = 1\nv2 = 2\nv3 = 3\n'
inline_rule a.py length 2 'def f(a):\n    """Summary.\n\n    Details line one.\n    Details line two.\n\n    Returns:\n        count: the number\n    """\n    print(a)\n'
inline_clean a.py 'def f(a):\n    """Summary.\n\n    Details line one.\n    Details line two.\n\n    Returns:\n        count: the number\n    """\n    return a\n'
inline_rule a.py length 2 'def f(a):\n    """Summary.\n\n    Details line one.\n    Details line two.\n\n    :returns: the number\n    """\n    print(a)\n'
inline_clean a.py 'def f(a):\n    """Summary.\n\n    Details line one.\n    Details line two.\n\n    :returns: the number\n    """\n    return a\n'
inline_clean a.py 'def f(a) -> int:\n    """Summary.\n\n    Details line one.\n    Details line two.\n\n    Returns:\n        int: the number\n    """\n    raise NotImplementedError\n'
inline_clean a.py 'def f(a):\n    """Summary.\n\n    Details line one.\n    Details line two.\n\n    Yields:\n        count: the number\n    """\n    yield a\n'

# the header documents the CI wiring
has "pipeline passes the base argument on every trigger" "$(cat "$GATE")" "header: CI needs the base argument on every trigger"

# module-level elements, arguments, union members and else branches are legal targets, function bodies are not
inline_clean a.ts 'export const v = [\n  // element\n  1,\n];\n'
inline_clean a.py 'import sys\nif sys.argv:\n    A = 1\n# explains else\nelse:\n    A = 2\n'
inline_rule a.ts placement 3 'export function f() {\n  const v = [\n    // element\n    1,\n  ];\n  return v;\n}\n'
inline_rule a.ts placement 4 'declare function k(...a: number[]): void;\nexport function f() {\n  k(\n    // argument\n    1,\n  );\n}\n'
inline_rule a.py placement 3 'def f():\n    return print(\n        # keyword\n        sep="",\n    )\n'
inline_rule a.py placement 5 'import sys\ndef f():\n    if sys.argv:\n        return 1\n    # else branch\n    else:\n        return 2\n'

# round 3: function parameters and conditional branches are legal targets at module level
inline_clean a.ts 'export function f(\n  // first\n  a: number,\n) {\n  return a;\n}\n'
inline_clean a.py 'def f(\n    # first\n    a,\n):\n    return a\n'
inline_clean a.ts 'export const v = true\n  // yes\n  ? 1\n  // no\n  : 2;\n'
inline_clean a.py 'V = (\n    1\n    # yes\n    if True\n    # no\n    else 2\n)\n'
inline_rule a.ts placement 3 'export function g() {\n  const f = (\n    // first\n    a: number,\n  ) => a;\n  return f;\n}\n'
inline_rule a.py placement 3 'def g():\n    def f(\n        # first\n        a,\n    ):\n        return a\n    return f\n'
inline_rule a.ts placement 3 'export const v = [\n  1,\n  // last\n];\n'
inline_rule a.ts placement 3 'export function g() {\n  return true\n    // yes\n    ? 1\n    : 2;\n}\n'

# a comment line is capped
long130=$(printf '%0130d' 0)
inline_rule a.ts length 1 "// $long130\nexport const a = 1;\n"
inline_rule a.py length 1 "# $long130\nA = 1\n"
long120=$(printf '%0120d' 0)
inline_clean a.ts "// $long120\nexport const a = 1;\n"

# placement: one rule for both languages
inline_rule a.ts placement 3 'export const z = 0;\nexport function f() {\n  // inside\n  return 1;\n}\n'
inline_rule a.ts placement 2 'export const z = 0;\n// above a closing brace\n'
inline_clean a.ts 'export const z = 0;\n// above a statement\nexport const y = 1;\n'
inline_clean a.ts 'export class C {\n  // above a member\n  m = 1;\n}\nexport interface I {\n  // above a signature\n  k: number;\n}\n'

# BOM and CRLF are read like plain files
inline_clean a.ts '\xef\xbb\xbf// Note.\r\nexport const a = 1;\r\n'
inline_clean a.py '\xef\xbb\xbf# Note.\r\nA = 1\r\n'
inline_rule a.ts trailing 2 '\xef\xbb\xbf// Note.\r\nexport const a = 1; // bad\r\n'
inline_rule a.py trailing 2 '\xef\xbb\xbf# Note.\r\nA = 1  # bad\r\n'

# a parse failure names the interpreter or the typescript version
inline a.ts 'export const = ;\n'
has "comments/parse" "$OUT" "parse failure in ts is reported"
has "typescript $TS_VERSION" "$OUT" "parse failure names the typescript version"
inline a.py 'def (:\n'
has "comments/parse" "$OUT" "parse failure in py is reported"
has "Python 3." "$OUT" "parse failure names the Python version"

# a comment above a blank line is not directly above its declaration
d=$T/blank
mkdir -p "$d"
printf 'export const z = 0;\n// Note.\n\nexport const a = 1;\n// Second.\nexport const b = 2;\n' > "$d/a.ts"
gate_all "$d" --full
check 1 "$EC" "blank line before the declaration: exits 1"
has "a.ts:2: comments/placement" "$OUT" "blank line before the declaration: line 2 flagged"
lacks "a.ts:5:" "$OUT" "comment directly above the declaration stays clean"

# a trailing comment after a parenthetical is judged once per rule: a multi-line aside is found on its own line
d=$T/multi
mkdir -p "$d"
printf '// Starts here (an aside that\n// ends on the next line) and stops.\nexport const a = 1;\n' > "$d/a.ts"
gate_all "$d" --full
has "a.ts:1: comments/aside" "$OUT" "multi-line aside found at its opening line"

# skipped paths never produce findings
d=$T/skip
mkdir -p "$d/node_modules/x" "$d/src/components/ui" "$d/migrations" "$d/dist" "$d/src"
printf 'export const a = 1; // bad\n' | tee "$d/node_modules/x/index.js" "$d/src/components/ui/button.tsx" "$d/dist/a.js" > /dev/null
printf 'A = 1  # bad\n' > "$d/migrations/001.py"
gate_all "$d"
check 0 "$EC" "skip list: generated and vendored paths ignored ($OUT)"
printf 'export const a = 1; // bad\n' > "$d/src/a.ts"
gate_all "$d"
check 1 "$EC" "skip list control: a normal source path is judged"

# build and dist folders are skipped at the project root only
d=$T/anchor
mkdir -p "$d/src/build" "$d/src/dist"
printf 'export const a = 1; // bad\n' | tee "$d/src/build/x.ts" "$d/src/dist/y.ts" > /dev/null
gate_all "$d" --full
check 1 "$EC" "skip list: nested build and dist folders are judged"
has "src/build/x.ts:1" "$OUT" "skip list: src/build judged"
has "src/dist/y.ts:1" "$OUT" "skip list: src/dist judged"
d=$T/anchor-root
mkdir -p "$d/build" "$d/dist"
printf 'export const a = 1; // bad\n' | tee "$d/build/x.ts" "$d/dist/y.ts" > /dev/null
gate_all "$d"
check 0 "$EC" "skip list control: root build and dist folders are skipped ($OUT)"
check 0 "$(grep -c '/dev/stderr' "$GATE")" "the shell script holds no /dev/stderr write"
has "call foo() first" "$(cat "$GATE")" "header documents the code-reference allowance"

# git helpers
GIT=(git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null -c init.defaultBranch=main)
# repo <dir> — a project with a symlinked typescript, a bare origin and one base commit; files are added by the caller.
repo() {
  mkdir -p "$1/node_modules"
  ln -s "$TSPKG" "$1/node_modules/typescript"
  printf 'node_modules\n' > "$1/.gitignore"
  mkdir -p "$1/scripts"
  cp "$SHARED/template/scripts/check-comments."* "$1/scripts/"
}
commit_all() { (cd "$1" && "${GIT[@]}" add -A && "${GIT[@]}" commit -q -m "$2"); }
# gate_diff <dir> [args...] — runs the seeded copy with no CI markers; sets OUT and EC.
gate_diff() {
  local d=$1
  shift
  OUT=$(cd "$d" && "${CLEAN_ENV[@]}" bash scripts/check-comments.sh "$@" 2>&1)
  EC=$?
}

# diff scope: old violations are not flagged, new and changed lines are
for lang in ts py; do
  d=$T/diff-$lang
  repo "$d"
  mkdir -p "$d/src"
  cp "$FIX/diff/base.$lang" "$d/src/mod.$lang"
  (cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
  commit_all "$d" base
  (cd "$d" && "${GIT[@]}" checkout -q -b topic)
  gate_diff "$d" main
  check 0 "$EC" "diff[$lang]: untouched old violations pass ($OUT)"
  cp "$FIX/diff/new.$lang" "$d/src/mod.$lang"
  gate_diff "$d" main
  check 1 "$EC" "diff[$lang]: new violations fail"
  check 2 "$(printf '%s\n' "$OUT" | grep -c ': comments/')" "diff[$lang]: exactly the two new findings ($OUT)"
  lacks "mod.$lang:1:" "$OUT" "diff[$lang]: old line 1 not flagged"
  has "diff base: base ref taken from the command-line argument" "$OUT" "diff[$lang]: report states how the base was chosen"
  commit_all "$d" topic
  gate_diff "$d" main
  check 1 "$EC" "diff[$lang]: committed new violations still fail against the base"
  gate_diff "$d" HEAD
  check 0 "$EC" "diff[$lang]: nothing changed against HEAD passes ($OUT)"
  cp "$FIX/$lang/trailing.bad.$lang" "$d/src/untracked.$lang"
  gate_diff "$d" HEAD
  check 1 "$EC" "diff[$lang]: an untracked file is judged whole"
  has "untracked.$lang:1: comments/trailing" "$OUT" "diff[$lang]: untracked finding named"
done

# editing an old comment line makes it a changed line
d=$T/edit
repo "$d"
mkdir -p "$d/src"
printf '// Old note.\nexport const keep = 1;\n' > "$d/src/a.ts"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
commit_all "$d" base
printf '// Old note (reworded).\nexport const keep = 1;\n' > "$d/src/a.ts"
gate_diff "$d" main
has "a.ts:1: comments/aside" "$OUT" "edited comment line is judged"

# ADR folder changes the length message
d=$T/adr
repo "$d"
mkdir -p "$d/src"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
printf 'export const a = 1;\n' > "$d/src/a.ts"
commit_all "$d" base
cp "$FIX/ts/length.bad.ts" "$d/src/b.ts"
gate_diff "$d" main
has "comments/length" "$OUT" "adr: length finding without an ADR folder"
lacks "ADR" "$OUT" "adr: no ADR advice when the project has no ADR folder"
mkdir -p "$d/docs/adr"
gate_diff "$d" main
has "Cite the ADR by number" "$OUT" "adr: advice to cite the ADR by number when docs/adr exists"
rm -r "$d/docs/adr"
mkdir -p "$d/docs/decisions"
gate_diff "$d" main
has "Cite the ADR by number" "$OUT" "adr: docs/decisions counts as well"

# missing runtime or package fails closed with the fix named
d=$T/norun
mkdir -p "$d/bin"
for tool in bash git awk sort mktemp rm find dirname wc tr head tail cat sed; do
  ln -s "$(command -v "$tool")" "$d/bin/$tool"
done
mkdir -p "$d/tsproj" "$d/pyproj"
cp "$FIX/ts/trailing.bad.ts" "$d/tsproj/"
cp "$FIX/py/trailing.bad.py" "$d/pyproj/"
OUT=$(env PATH="$d/bin" /bin/bash "$GATE" --root "$d/tsproj" --ts-from "$T/tsroot" --all . 2>&1)
check 2 "$?" "no node: exits 2"
has "node is missing" "$OUT" "no node: message names the cause"
has "Fix:" "$OUT" "no node: message names the fix"
ln -s "$(command -v node)" "$d/bin/node"
OUT=$(env PATH="$d/bin" /bin/bash "$GATE" --root "$d/pyproj" --all . 2>&1)
check 2 "$?" "no python3: exits 2"
has "python3 is missing" "$OUT" "no python3: message names the cause"
mkdir -p "$d/node_modules"
ln -s "$TSPKG" "$d/node_modules/typescript"
OUT=$(env -u NODE_PATH PATH="$d/bin" /bin/bash "$GATE" --root "$d/tsproj" --all . 2>&1)
check 2 "$?" "no typescript package: exits 2 even with a typescript in a parent folder"
has "typescript package is missing" "$OUT" "no typescript package: message names the cause"
has "pnpm install" "$OUT" "no typescript package: message names the fix"
lacks "check-comments: check-comments:" "$OUT" "no typescript package: the message carries one prefix"
OUT=$(env NODE_PATH="$T/tsroot/node_modules" PATH="$d/bin" /bin/bash "$GATE" --root "$d/tsproj" --all . 2>&1)
check 2 "$?" "no typescript package: NODE_PATH does not supply one"
rm "$d/node_modules/typescript"
OUT=$(env PATH="$d/bin" /bin/bash "$GATE" --root "$d/pyproj" --all nonexistent 2>&1)
check 2 "$?" "a path that does not exist fails closed ($OUT)"
has "path does not exist: nonexistent" "$OUT" "missing path: message names the path"
OUT=$(env PATH="$d/bin" /bin/bash "$GATE" --root "$d/pyproj" --all . nonexistent 2>&1)
check 2 "$?" "a missing path after a valid one still fails closed"
mkdir -p "$d/pyproj/docs-only"
OUT=$(env PATH="$d/bin" /bin/bash "$GATE" --root "$d/pyproj/docs-only" --all . 2>&1)
check 2 "$?" "a folder with no source files fails closed ($OUT)"
has "no source file under the given paths" "$OUT" "no source files: names the cause"
lacks "check-comments: ok" "$OUT" "no source files: no green ok line"
mkdir -p "$d/empty"
OUT=$("${CLEAN_ENV[@]}" /bin/bash "$GATE" --root "$d/empty" 2>&1)
check 2 "$?" "outside a git work tree: exits 2"
has "not a git work tree" "$OUT" "outside a git work tree: message names the cause"

# a typescript release without the scanner API fails closed and names its version
mkdir -p "$d/fakeroot/node_modules/typescript"
printf '{"name":"typescript","version":"9.9.9","main":"index.js"}\n' > "$d/fakeroot/node_modules/typescript/package.json"
printf 'module.exports = { version: "9.9.9" };\n' > "$d/fakeroot/node_modules/typescript/index.js"
OUT=$("${CLEAN_ENV[@]}" bash "$GATE" --root "$d/tsproj" --ts-from "$d/fakeroot" --all . 2>&1)
check 2 "$?" "typescript without the scanner API: exits 2"
has "typescript 9.9.9 lacks the compiler API" "$OUT" "typescript without the scanner API: names the version"
has "ScriptTarget" "$OUT" "typescript without the scanner API: names the missing member"
OUT=$("${CLEAN_ENV[@]}" bash "$GATE" --root "$d/tsproj" --ts-from "$T/tsroot" --all . 2>&1)
check 1 "$?" "typescript with the scanner API: the control run judges the file"

# CI refuses a BASE_REF override that is not the pipeline target branch
d=$T/ci
repo "$d"
mkdir -p "$d/src" "$T/origin.git"
git init -q --bare "$T/origin.git"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
printf 'export const a = 1;\n' > "$d/src/a.ts"
commit_all "$d" base
(cd "$d" && "${GIT[@]}" remote add origin "$T/origin.git" && "${GIT[@]}" push -q origin main 2> /dev/null && "${GIT[@]}" fetch -q origin)
(cd "$d" && "${GIT[@]}" checkout -q -b topic)
cp "$FIX/ts/trailing.bad.ts" "$d/src/b.ts"
ci() { # ci <env assignments...> -- <gate args...> — runs with CI markers set.
  local envs=()
  while [[ "$1" != "--" ]]; do
    envs+=("$1")
    shift
  done
  shift
  OUT=$(cd "$d" && env -u CI -u GITHUB_ACTIONS -u TF_BUILD -u BASE_REF -u GITHUB_BASE_REF -u SYSTEM_PULLREQUEST_TARGETBRANCH -u SYSTEM_PULLREQUEST_TARGETBRANCHNAME "${envs[@]}" bash scripts/check-comments.sh "$@" 2>&1)
  EC=$?
}
ci CI=true GITHUB_ACTIONS=true BASE_REF=HEAD~5 --
check 2 "$EC" "ci: BASE_REF with no pipeline target is refused"
has "refused in CI" "$OUT" "ci: refusal message"
ci CI=true GITHUB_ACTIONS=true BASE_REF=topic GITHUB_BASE_REF=main --
check 2 "$EC" "ci: BASE_REF that is not the target branch is refused"
has "not the pipeline target branch (main)" "$OUT" "ci: message names the target"
ci CI=true GITHUB_ACTIONS=true BASE_REF=origin/main GITHUB_BASE_REF=main --
check 1 "$EC" "ci: BASE_REF equal to origin/<target> is accepted and judges the diff"
has "accepted because it names the pipeline target branch (main)" "$OUT" "ci: report states the decision"
ci TF_BUILD=True BASE_REF=main SYSTEM_PULLREQUEST_TARGETBRANCH=refs/heads/main --
check 1 "$EC" "ci: Azure target branch variable accepted"
ci TF_BUILD=True BASE_REF=topic SYSTEM_PULLREQUEST_TARGETBRANCHNAME=main --
check 2 "$EC" "ci: Azure override that is not the target is refused"
ci CI=true GITHUB_BASE_REF=main --
check 1 "$EC" "ci: no override uses the pipeline target branch"
has "pipeline target branch (main)" "$OUT" "ci: report states the target decision"
ci CI=true GITHUB_ACTIONS=true BASE_REF=topic -- main
check 1 "$EC" "ci: an explicit argument in the pipeline step is accepted"
has "command-line argument" "$OUT" "ci: report states the argument decision"
ci CI=false BASE_REF=main --
check 1 "$EC" "ci: CI=false is not CI, so a BASE_REF override works"
has "BASE_REF from the environment (not CI)" "$OUT" "ci: report states the non-CI decision"
ci CI=true GITHUB_ACTIONS=true GITHUB_BASE_REF=gone --
check 2 "$EC" "ci: target branch missing from the clone fails closed"
has "base ref not found" "$OUT" "ci: missing base message"

# CI push to the target branch: nothing to compare, said out loud
rm -rf "$T/push"
git clone -q "$T/origin.git" "$T/push" 2> /dev/null
run_push() { # run_push <env assignments...> — the gate over a clean clone whose HEAD is the base.
  OUT=$(env -u CI -u GITHUB_ACTIONS -u TF_BUILD -u BASE_REF -u GITHUB_BASE_REF -u SYSTEM_PULLREQUEST_TARGETBRANCH -u SYSTEM_PULLREQUEST_TARGETBRANCHNAME "$@" bash "$GATE" --root "$T/push" 2>&1)
  EC=$?
}
run_push CI=true GITHUB_ACTIONS=true
check 2 "$EC" "ci, no target variable and no argument: fails closed ($OUT)"
has "never guessed" "$OUT" "ci, no target: says the base is not guessed"
has "GITHUB_BASE_REF" "$OUT" "ci, no target: names the missing variable"
run_push CI=true GITHUB_ACTIONS=true GITHUB_BASE_REF=main
check 0 "$EC" "ci push: exits 0 ($OUT)"
has "nothing to compare" "$OUT" "ci push: says there is nothing to compare"
has "judges pull requests" "$OUT" "ci push: says the gate judges pull requests"
has "nothing checked" "$OUT" "ci push: final line says nothing was checked"
lacks "check-comments: ok" "$OUT" "ci push: no green ok line"
run_push A=1
check 0 "$EC" "non-ci, HEAD is the base: exits 0"
has "nothing checked: HEAD is the base" "$OUT" "non-ci, HEAD is the base: says nothing was checked and why"
lacks "check-comments: ok" "$OUT" "non-ci, HEAD is the base: no green ok line"
lacks "nothing to compare" "$OUT" "non-ci, HEAD is the base: no push message"
ci CI=true GITHUB_ACTIONS=true GITHUB_BASE_REF=main --
lacks "nothing to compare" "$OUT" "ci pull request with changes: no push message"
check 1 "$EC" "ci pull request with changes: still judged"

# a project in a git subfolder judges its own changed and new files, with paths relative to the project
d=$T/nest
mkdir -p "$d"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
repo "$d/backend"
mkdir -p "$d/backend/src" "$d/other"
printf 'export const old = 1;\n' > "$d/backend/src/old.ts"
printf 'export const x = 1;\n' > "$d/other/x.ts"
printf 'node_modules\n' > "$d/.gitignore"
commit_all "$d" base
(cd "$d" && "${GIT[@]}" checkout -q -b topic)
printf 'export const old = 1;\nexport const more = 2; // bad\n' > "$d/backend/src/old.ts"
printf 'export const n = 1; // bad\n' > "$d/backend/src/new.ts"
printf 'export const x = 1; // bad\n' > "$d/other/x.ts"
gate_diff "$d/backend" main
check 1 "$EC" "subfolder project: judged, not a runtime error ($OUT)"
has "src/old.ts:2: comments/trailing" "$OUT" "subfolder project: changed file named relative to the project"
has "src/new.ts:1: comments/trailing" "$OUT" "subfolder project: untracked file named relative to the project"
lacks "other/" "$OUT" "subfolder project: a file outside the project is not judged"
commit_all "$d" topic
gate_diff "$d/backend" main
check 1 "$EC" "subfolder project: committed changes judged ($OUT)"
check 2 "$(printf '%s\n' "$OUT" | grep -c ': comments/')" "subfolder project: exactly the two project findings"

# rename-only changes are not re-judged, a reindented line counts as changed
d=$T/rename
repo "$d"
mkdir -p "$d/src"
printf 'export const a = 1; // old\n' > "$d/src/a.ts"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
commit_all "$d" base
(cd "$d" && "${GIT[@]}" checkout -q -b topic && "${GIT[@]}" mv src/a.ts src/b.ts)
commit_all "$d" rename
gate_diff "$d" main
check 0 "$EC" "rename only: the old violation is not re-judged ($OUT)"
printf '  export const a = 1; // old\n' > "$d/src/b.ts"
gate_diff "$d" main
check 1 "$EC" "whitespace-only edit: the reindented line counts as changed"
has "src/b.ts:1: comments/trailing" "$OUT" "whitespace-only edit: finding named"

# deleted and binary files are not judged
d=$T/delbin
repo "$d"
mkdir -p "$d/src"
printf 'export const a = 1; // old\n' > "$d/src/gone.ts"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
commit_all "$d" base
(cd "$d" && "${GIT[@]}" checkout -q -b topic && "${GIT[@]}" rm -q src/gone.ts)
printf '\x89PNG\r\n\x1a\n\0\0\0' > "$d/logo.png"
commit_all "$d" "delete and binary"
gate_diff "$d" main
check 0 "$EC" "deleted and binary files: clean ($OUT)"
has "nothing checked: no source file was added, changed or renamed" "$OUT" "deleted and binary files: says nothing was checked"

# round 4: only skipped source files changed, so the message names them
d=$T/skiponly
repo "$d"
mkdir -p "$d/dist"
printf 'export const a = 1;\n' > "$d/dist/old.js"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
commit_all "$d" base
(cd "$d" && "${GIT[@]}" checkout -q -b topic)
printf 'export const a = 1; // bad\n' > "$d/dist/new.js"
printf 'A = 1  # bad\n' > "$d/dist/new.py"
commit_all "$d" "skipped only"
gate_diff "$d" main
check 0 "$EC" "skipped-only change: exits 0 ($OUT)"
has "every changed source file is on a skipped generated or vendored path" "$OUT" "skipped-only change: says why nothing was checked"
has "dist/new.js" "$OUT" "skipped-only change: lists a skipped file"
has "dist/new.py" "$OUT" "skipped-only change: lists the other skipped file"
lacks "no source file was added" "$OUT" "skipped-only change: not the misleading no-source message"

# a folder holding only a symlink to a source file is named, not followed
d=$T/linkonly
mkdir -p "$d" "$T/linktarget"
printf 'export const a = 1;\n' > "$T/linktarget/a.ts"
ln -s "$T/linktarget/a.ts" "$d/link.ts"
gate_all "$d"
check 2 "$EC" "symlink only: exits 2 ($OUT)"
has "only source files are symlinks" "$OUT" "symlink only: names the symlink case"
has "link.ts" "$OUT" "symlink only: names the link"
lacks "check-comments: ok" "$OUT" "deleted and binary files: no green ok line"

# round 5: the symlink note on the ok path, and no doubled period in the message
has "given paths (.)" "$OUT" "symlink only: the path list closes cleanly"
lacks "paths: .." "$OUT" "symlink only: no doubled period"
d=$T/linkmixed
mkdir -p "$d"
printf 'export const a = 1;\n' > "$d/real.ts"
ln -s "$T/linktarget/a.ts" "$d/link.ts"
gate_all "$d"
check 0 "$EC" "real file plus a symlink: exits 0 ($OUT)"
has "check-comments: ok (1 file(s) checked)" "$OUT" "real file plus a symlink: ok line"
has "symlinked source files were not followed" "$OUT" "real file plus a symlink: the skipped link is noted"
has "link.ts" "$OUT" "real file plus a symlink: the note names the link"

# round 5: lines with no letter or digit, and non-Latin prose, are not licence text
MITH=$(wrap_style slash 100 "$MIT_TEXT")$NL
MITP=$(wrap_style hash 100 "$MIT_TEXT")$NL
six_marks=''
six_marks_py=''
six_cjk=''
six_tilde=''
for _ in 1 2 3 4 5 6; do
  six_marks="$six_marks// ¡¡¡¡ ???? !!!!\n"
  six_marks_py="$six_marks_py# ¡¡¡¡ ???? !!!!\n"
  six_cjk="$six_cjk// 这是一个很长的解释说明\n"
  six_tilde="$six_tilde// ñ ñ ñ ñ\n"
done
inline_fails a.ts length "$MITH${six_marks}export const a = 1;\n"
inline_fails a.py length "$MITP${six_marks_py}A = 1\n"
inline_fails a.ts length "$MITH${six_cjk}export const a = 1;\n"
inline_fails a.ts length "$MITH${six_tilde}export const a = 1;\n"
MIT_MIXED=${MIT_TEXT/granted,/granted, 附加说明 附加说明 附加说明 附加说明}
inline_fails a.ts length "$(wrap_style slash 100 "$MIT_MIXED")${NL}export const a = 1;\n"
inline_fails a.py length "$(wrap_style hash 100 "$MIT_MIXED")${NL}A = 1\n"
inline_clean a.ts "$MITH// ----\nexport const a = 1;\n"
inline_clean a.ts "${MITH}export const a = 1;\n"

# round 5: Copyright and SPDX lines are anchored whole lines
long_copy=''
long_copy_py=''
long_spdx=''
for _ in 1 2 3 4; do
  long_copy="$long_copy// Copyright 2024 Acme. This file contains a long explanation of how the parser works.\n"
  long_copy_py="$long_copy_py# Copyright 2024 Acme. This file contains a long explanation of how the parser works.\n"
  long_spdx="$long_spdx// SPDX-License-Identifier: MIT this file explains how the parser works\n"
done
inline_fails a.ts length "${long_copy}export const a = 1;\n"
inline_fails a.py length "${long_copy_py}A = 1\n"
inline_fails a.ts length "${long_spdx}export const a = 1;\n"
inline_clean a.ts '// Copyright (c) 2015-2024 Acme, Inc. All rights reserved.\n// Copyright 2020 The Authors\n// SPDX-License-Identifier: Apache-2.0 OR MIT\nexport const a = 1;\n'
inline_clean a.ts '// SPDX-License-Identifier: (MIT AND BSD-3-Clause)\nexport const a = 1;\n'
inline_clean a.py '# Copyright © 2024 Example Corp\nA = 1\n'

# round 6: real copyright lines with a sentence end or "and contributors" are accepted
C1='Copyright (c) 2019-2024 Example Corp. and contributors'
C2='Copyright 2020 Foo Inc. and contributors'
C3='Copyright (c) 2023 Meta Platforms, Inc. and affiliates.'
inline_clean a.ts "// $C1\n// $C2\n// $C3\nexport const a = 1;\n"
inline_clean a.py "#!/usr/bin/env python3\n# -*- coding: utf-8 -*-\n# $C1\n# $C2\n# $C3\nA = 1\n"
inline_clean a.ts "/*\n * $C1\n * $C2\n * $C3\n */\nexport const a = 1;\n"
for lic in MIT_TEXT APACHE_TEXT; do
  body=${!lic}
  slash_b=$(wrap_style slash 100 "$body")$NL
  hash_b=$(wrap_style hash 100 "$body")$NL
  star_b=$(printf '%s' "$slash_b" | sed 's#^// # * #')$NL
  inline_clean a.ts "// $C1\n// $C2\n// $C3\n$slash_b""export const a = 1;\n"
  inline_clean a.py "#!/usr/bin/env python3\n# -*- coding: utf-8 -*-\n# $C1\n# $C2\n# $C3\n$hash_b""A = 1\n"
  inline_clean a.ts "/*\n * $C1\n * $C2\n * $C3\n *\n$star_b */\nexport const a = 1;\n"
  inline_fails a.ts length "// $C1\n// $C2\n// $C3\n$slash_b// Our own note on the licence above.\nexport const a = 1;\n"
done
# at most three Copyright lines and one SPDX line in the file
inline_fails a.ts length "// $C1\n// $C2\n// $C3\n// Copyright 2024 Fourth Corp\n// note one about it\nexport const a = 1;\n"
inline_fails a.ts length '// SPDX-License-Identifier: MIT\n// SPDX-License-Identifier: Apache-2.0\n// note one about it\n// note two about it\nexport const a = 1;\n'
inline_clean a.ts '// SPDX-License-Identifier: MIT\n// note one about it\n// note two about it\nexport const a = 1;\n'

# round 6: a Copyright holder is at most eight tokens
LONGC='Copyright 2024 Acme and this file explains how the parser works now'
inline_fails a.ts length "// $LONGC\n// $LONGC\n// $LONGC\n// note one about it\n// note two about it\nexport const a = 1;\n"
inline_fails a.py length "# $LONGC\n# $LONGC\n# $LONGC\n# note one about it\n# note two about it\nA = 1\n"
inline_clean a.ts "// $C3\n// $C3\n// $C3\n// note one about it\n// note two about it\nexport const a = 1;\n"

# round 6: an SPDX expression is built from bundled licence ids only
inline_fails a.ts length '// SPDX-License-Identifier: MIT AND parser AND walks AND trees\n// note one about it\n// note two about it\n// note three about it\nexport const a = 1;\n'
inline_fails a.py length '# SPDX-License-Identifier: MIT AND parser AND walks AND trees\n# note one about it\n# note two about it\n# note three about it\nA = 1\n'
inline_clean a.ts '// SPDX-License-Identifier: (MIT OR Apache-2.0+) AND BSD-3-Clause\n// note one about it\n// note two about it\n// note three about it\nexport const a = 1;\n'
inline_clean a.py '# SPDX-License-Identifier: MIT AND BSD-3-Clause\n# note one about it\n# note two about it\n# note three about it\nA = 1\n'

# round 7: a Copyright line has a required year and a plain holder; an SPDX line is a small grammar over closed id lists.
# hdr_clean and hdr_fails judge the same header line in a .ts and a .py file, so both readers must agree.
hdr_clean() {
  inline_clean a.ts "// $1\n// note one about it\n// note two about it\n// note three about it\nexport const a = 1;\n"
  inline_clean a.py "# $1\n# note one about it\n# note two about it\n# note three about it\nA = 1\n"
}
hdr_fails() {
  inline_fails a.ts length "// $1\n// note one about it\n// note two about it\n// note three about it\nexport const a = 1;\n"
  inline_fails a.py length "# $1\n# note one about it\n# note two about it\n# note three about it\nA = 1\n"
}
for h in 'Copyright (c) 2019-2024 Example Corp. and contributors' 'Copyright 2024 The Example Authors. All rights reserved.' '(c) 2024 Acme' '© 2024 Acme' \
  'Copyright © 2024 Acme' 'Copyright 2019, 2021-2024 Acme Corp' 'Copyright 2024 Zoë Müller' 'Copyright 2024 株式会社' 'Copyright 2024' 'Copyright 2024 Acme <dev@acme.example>' \
  'Copyright 2024 Acme https://acme.example/about' 'Copyright (c) 2023 Meta Platforms, Inc. and affiliates.' "Copyright 2024 O'Brien & Sons"; do
  hdr_clean "$h"
done
for h in 'Copyright: retries three times then gives up quietly' 'Copyright (c) Meta Platforms, Inc. and affiliates.' 'Copyright 2024 (aside here in brackets)' 'Copyright (c) 2024 Acme (a note)' \
  'Copyright 2024 Acme: a note' 'Copyright 2024 Acme; a note' 'Copyright 2024 Acme [a note]' 'Copyright 2024 one two three four five six seven eight nine' \
  'Copyright 2024 Acme <a@b.example> <c@d.example>' 'Copyright 2024 Acme https://a.example https://b.example' 'Copyright 2024 Acme "quoted"' 'Copyright retries 2024 three times' \
  'Copyright 24 Acme' 'Copyright 2024Acme' '(c) Acme Corp' '© Acme Corp' 'Copyright ２０２４ this retries because upstream flakes' 'Copyright 2024 ２０２４' 'Copyrıght 2024 Acme'; do
  hdr_fails "$h"
done
for h in 'SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0' 'SPDX-License-Identifier: GPL-3.0-or-later' 'SPDX-License-Identifier: LGPL-2.1-only' 'SPDX-License-Identifier: Unlicense' \
  'SPDX-License-Identifier: 0BSD' 'SPDX-License-Identifier: MIT OR Apache-2.0' 'SPDX-License-Identifier: (MIT OR Apache-2.0) AND BSD-3-Clause' 'SPDX-License-Identifier: GPL-2.0+' \
  'SPDX-License-Identifier: GPL-2.0-or-later WITH GCC-exception-3.1' 'SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception' 'SPDX-License-Identifier: CC0-1.0' 'SPDX-License-Identifier: MPL-2.0 OR EPL-2.0'; do
  hdr_clean "$h"
done
for h in 'SPDX-License-Identifier: MIT OR AND' 'SPDX-License-Identifier: MIT WITH MIT WITH MIT' 'SPDX-License-Identifier: MIT AND' 'SPDX-License-Identifier: AND MIT' 'SPDX-License-Identifier: (MIT OR Apache-2.0' \
  'SPDX-License-Identifier: MIT OR Apache-2.0)' 'SPDX-License-Identifier: MIT OR MIT' 'SPDX-License-Identifier: Classpath-exception-2.0' 'SPDX-License-Identifier: MIT WITH Classpath-exception-2.0 WITH LLVM-exception' \
  'SPDX-License-Identifier: GPL-2.0-only WITH MIT' 'SPDX-License-Identifier: mit' 'SPDX-License-Identifier: MIT, Apache-2.0' 'SPDX-License-Identifier: MIT Apache-2.0' 'SPDX-License-Identifier: ' 'SPDX-License-Identifier: ()' \
  'SPDX-License-Identifier: MIT WITH' 'SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0 WITH Classpath-exception-2.0'; do
  hdr_fails "$h"
done

# round 7: the licence data file must load, with texts and both id lists, or the gate cannot run
mkdir -p "$T/dat"
for variant in missing empty noids noexc; do
  d=$T/dat/$variant
  mkdir -p "$d/gate" "$d/proj"
  cp "$SHARED/template/scripts/"check-comments.* "$d/gate/"
  data=$d/gate/check-comments.licences.txt
  case "$variant" in
    missing) rm -f "$data"; want="cannot read the bundled licence texts" ;;
    empty) : > "$data"; want="hold no licence." ;;
    noids) grep -v '^licence-ids:' "$SHARED/template/scripts/check-comments.licences.txt" > "$data"; want="no licence ids or no exception ids" ;;
    noexc) grep -v '^exception-ids:' "$SHARED/template/scripts/check-comments.licences.txt" > "$data"; want="no licence ids or no exception ids" ;;
  esac
  for pair in "a.ts:export const a = 1;" "a.py:A = 1"; do
    printf '%s\n' "${pair#*:}" > "$d/proj/${pair%%:*}"
    OUT=$("${CLEAN_ENV[@]}" bash "$d/gate/check-comments.sh" --root "$d/proj" --ts-from "$T/tsroot" --full --all . 2>&1)
    EC=$?
    check 2 "$EC" "data file $variant, ${pair%%:*}: cannot run, exit 2 ($OUT)"
    has "$want" "$OUT" "data file $variant, ${pair%%:*}: names the cause"
    rm -f "$d/proj/${pair%%:*}"
  done
done

# round 5: the exempt licence block is the one at the very top, and nothing later is
frag=''
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do frag="$frag// free of charge, to any person\n\n"; done
inline_fails a.ts length "${frag}export const a = 1;\n"
inline_fails a.ts length "// Notes on this file.\n\n${MITH}export const a = 1;\n"
inline_clean a.ts "// Copyright 2024 Example Corp\n\n${MITH}export const a = 1;\n"
inline_fails a.ts length "// Copyright 2024 Example Corp\n\n${MITH}\n${MITH}export const a = 1;\n"
MIT_MID='The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY'
inline_fails a.ts length "$(wrap_style slash 40 "$MIT_MID")${NL}export const a = 1;\n"
inline_fails a.py length "$(wrap_style hash 40 "$MIT_MID")${NL}A = 1\n"

# round 5: matched licence lines are exempt from the line cap, other long lines are not
inline_clean a.ts "$(wrap_style slash 400 "$MIT_TEXT")${NL}export const a = 1;\n"
inline_clean a.py "$(wrap_style hash 400 "$BSD3_TEXT")${NL}A = 1\n"
inline_fails a.ts length "// $(printf 'word %.0s' $(seq 1 40))\nexport const a = 1;\n"

# round 5: deprecated, author, license and link are data tags, and a long tag text is prose
inline_clean a.ts '/**\n * @deprecated use g\n * @author Ann Lee\n * @license MIT\n * @link g\n */\nexport function f() {\n  return 1;\n}\n'
inline_clean a.ts '/**\n * @param p1 the first value\n * @param p2 the second value\n * @param p3 the third value\n * @param p4 the fourth value\n */\nexport function f(p1: number, p2: number, p3: number, p4: number) {\n  return p1 + p2 + p3 + p4;\n}\n'
longtag=''
for n in 1 2 3 4; do longtag="$longtag * @param p$n the value that this parameter carries into the function body here\n"; done
inline_fails a.ts length "/**\n$longtag */\nexport function f(p1: number) {\n  return p1;\n}\n"

# round 5: the tag cap counts every comment above one declaration, a blank line included
tags6=''
for n in 1 2 3 4 5 6; do tags6="$tags6 * @param p$n value\n"; done
inline_fails a.ts length "/**\n$tags6 */\n\n/**\n$tags6 */\nexport function f(p1: number) {\n  return p1;\n}\n"
inline_fails a.ts length "/**\n$tags6 */\n// eslint-disable-next-line no-console -- logs once at boot\n/**\n$tags6 */\nexport function f(p1: number) {\n  return p1;\n}\n"
inline_clean a.ts "/**\n$tags5 */\n/**\n$tags5 */\nexport function f(p1: number) {\n  return p1;\n}\n\n/**\n$tags5 */\nexport function g(p1: number) {\n  return p1;\n}\n"

# round 5: unnamed Returns, Yields and Raises entries, stub bodies, dataclass fields and properties
inline_clean a.py 'def f(xs):\n    """Summary.\n\n    Detail one.\n    Detail two.\n\n    Args:\n        xs: the numbers\n\n    Yields:\n        Each number.\n    """\n    for x in xs:\n        yield x\n'
inline_clean a.py 'def f(a):\n    """Summary.\n\n    Detail one.\n    Detail two.\n\n    Returns:\n        The sum of everything.\n    """\n    return a + 1\n'
inline_clean a.py 'def f(a):\n    """Summary.\n\n    Detail one.\n    Detail two.\n\n    Raises:\n        If the value is empty.\n    """\n    raise ValueError(a)\n'
inline_rule a.py length 2 'def f(a):\n    """Summary.\n\n    Detail one.\n    Detail two.\n\n    Returns:\n        Nothing useful here.\n    """\n    print(a)\n'
inline_rule a.py length 2 'def f(a):\n    """Summary.\n\n    Detail one.\n    Detail two.\n\n    Raises:\n        If the value is empty.\n    """\n    print(a)\n'
inline_clean a.py 'class B:\n    def run(self, a):\n        """Summary.\n\n        Detail one.\n        Detail two.\n\n        Returns:\n            count: the number\n        """\n        raise NotImplementedError\n'
inline_clean a.py 'class B:\n    def run(self, a):\n        """Summary.\n\n        Detail one.\n        Detail two.\n\n        Returns:\n            count: the number\n        """\n        ...\n'
inline_clean a.py 'class B:\n    def run(self, a):\n        """Summary.\n\n        Detail one.\n        Detail two.\n\n        Returns:\n            count: the number\n        """\n        raise NotImplementedError("subclass it")\n'
inline_clean a.py 'from dataclasses import dataclass\n\n\n@dataclass\nclass P:\n    """Summary.\n\n    Detail one.\n    Detail two.\n\n    Args:\n        x: the x\n        y: the y\n    """\n\n    x: int\n    y: int\n'
inline_clean a.py 'from dataclasses import dataclass\n\n\n@dataclass\nclass P:\n    """Summary.\n\n    Detail one.\n    Detail two.\n\n    Attributes:\n        x: the x\n        y: the y\n    """\n\n    x: int\n    y: int\n'
inline_clean a.py 'class P:\n    """Summary.\n\n    Detail one.\n    Detail two.\n\n    Attributes:\n        size: the size\n    """\n\n    @property\n    def size(self):\n        return 1\n'
inline_rule a.py length 2 'class P:\n    """Summary.\n\n    Detail one.\n    Detail two.\n\n    Attributes:\n        bogus: not here\n    """\n\n    @property\n    def size(self):\n        return 1\n'
inline_rule a.py length 6 'from dataclasses import dataclass\n\n\n@dataclass\nclass P:\n    """Summary.\n\n    Detail one.\n    Detail two.\n\n    Args:\n        z: not a field\n    """\n\n    x: int\n'

# a path with a space is read whole
d=$T/space
repo "$d"
mkdir -p "$d/src"
printf 'export const a = 1;\n' > "$d/src/a.ts"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
commit_all "$d" base
(cd "$d" && "${GIT[@]}" checkout -q -b topic)
printf 'export const a = 1;\nexport const b = 2; // bad\n' > "$d/src/a.ts"
cp "$d/src/a.ts" "$d/src/my file.ts"
commit_all "$d" "spaces"
gate_diff "$d" main
has "src/my file.ts:2: comments/trailing" "$OUT" "path with a space: judged and named"

# an extra positional argument is refused
gate_diff "$d" main extra
check 2 "$EC" "extra argument: exits 2"
has "unexpected extra argument" "$OUT" "extra argument: message names the cause"

# a shallow clone with no merge base fails closed
d=$T/hist
mkdir -p "$d"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
printf 'export const a = 1;\n' > "$d/a.ts"
commit_all "$d" one
(cd "$d" && "${GIT[@]}" checkout -q -b topic)
printf 'export const b = 1;\n' > "$d/b.ts"
commit_all "$d" two
printf 'export const c = 1;\n' > "$d/c.ts"
commit_all "$d" three
(cd "$d" && "${GIT[@]}" checkout -q main)
printf 'export const m = 1;\n' > "$d/m.ts"
commit_all "$d" four
printf 'export const n = 1;\n' > "$d/n.ts"
commit_all "$d" five
git init -q --bare "$T/hist-origin.git"
(cd "$d" && "${GIT[@]}" push -q "$T/hist-origin.git" main topic 2> /dev/null)
git clone -q --depth 1 --branch topic "file://$T/hist-origin.git" "$T/shallow" 2> /dev/null
git -C "$T/shallow" fetch -q --depth 1 origin main:refs/remotes/origin/main 2> /dev/null
OUT=$("${CLEAN_ENV[@]}" bash "$GATE" --root "$T/shallow" origin/main 2>&1)
check 2 "$?" "shallow clone: no merge base exits 2 ($OUT)"
has "no merge base" "$OUT" "shallow clone: message names the cause"
has "fetch-depth: 0" "$OUT" "shallow clone: message names the fix"
OUT=$("${CLEAN_ENV[@]}" bash "$GATE" --root "$d" main 2>&1)
check 0 "$?" "full history control: the same refs run ($OUT)"

# a non-CI BASE_REF other than main is honoured
d=$T/branches
repo "$d"
mkdir -p "$d/src"
printf 'export const a = 1;\n' > "$d/src/a.ts"
(cd "$d" && "${GIT[@]}" init -q . && "${GIT[@]}" checkout -q -b main)
commit_all "$d" base
(cd "$d" && "${GIT[@]}" checkout -q -b develop)
printf 'export const dev = 1; // bad\n' > "$d/src/dev.ts"
commit_all "$d" develop
(cd "$d" && "${GIT[@]}" checkout -q -b topic)
printf 'export const top = 1; // bad\n' > "$d/src/top.ts"
commit_all "$d" topic
OUT=$(cd "$d" && "${CLEAN_ENV[@]}" env BASE_REF=develop bash scripts/check-comments.sh 2>&1)
check 1 "$?" "BASE_REF=develop: judged"
has "src/top.ts:1" "$OUT" "BASE_REF=develop: the topic change is judged"
lacks "src/dev.ts" "$OUT" "BASE_REF=develop: the develop change is not"
has "BASE_REF from the environment (not CI)" "$OUT" "BASE_REF=develop: report states the decision"
gate_diff "$d"
has "src/dev.ts:1" "$OUT" "default base (main): the develop change is judged too"

# the project's own .venv interpreter is preferred for Python
d=$T/venv
mkdir -p "$d/.venv/bin"
printf '#!/bin/sh\ntouch "%s/venv-used"\nexec "%s" "$@"\n' "$d" "$(command -v python3)" > "$d/.venv/bin/python3"
chmod +x "$d/.venv/bin/python3"
printf 'A = 1  # bad\n' > "$d/a.py"
gate_all "$d"
check 1 "$EC" "venv: the gate still judges ($OUT)"
check yes "$(if [[ -f "$d/venv-used" ]]; then echo yes; else echo no; fi)" "venv: the project interpreter ran"
d=$T/novenv
mkdir -p "$d"
printf 'A = 1  # bad\n' > "$d/a.py"
gate_all "$d"
check no "$(if [[ -f "$d/venv-used" ]]; then echo yes; else echo no; fi)" "no venv: the system interpreter runs"

# real scaffolds parse: every stack reads through both tokenizers with no parse failure or crash
scaffold() { # scaffold <stack> <dir>
  mkdir -p "$2"
  local part
  for part in stack base agents settings late; do
    TC_STACK=$1 TC_PART=$part bash "$SHARED/tc-copy.sh" "$2" > /dev/null 2>&1
  done
}
for stack in nextjs nestjs vite-react fastapi; do
  d=$T/scaffold-$stack
  scaffold "$stack" "$d"
  gate_all "$d" --full
  if [[ "$EC" -le 1 ]]; then got=judged; else got="exit $EC"; fi
  check judged "$got" "scaffold[$stack]: reads every file without a runtime error ($OUT)"
  lacks "comments/parse" "$OUT" "scaffold[$stack]: no parse failure"
done

echo "seeded-comments.test: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
