# Regular Expressions — PCRE vs the obsolete POSIX, extended mode, and the traps in `FIND`

ABAP runs **two** regex libraries side by side:

| Syntax | Library | Status |
|---|---|---|
| `PCRE` / `pcre =` | PCRE2 (currently 10.44) in the ABAP Kernel | current |
| `REGEX` *(character string)* / `regex =` | Boost.Regex **1.31** POSIX | **obsolete** |

POSIX syntax now produces a syntax-check warning, suppressible with the pragma
`##regex_posix`. So the first practical point: **if your code says `regex = ...`
in a string function, it is already on the obsolete library** — the modern
parameter is `pcre =`.

The second practical point is the one that costs time: PCRE is *not* a drop-in
replacement. Four documented differences change results with no syntax error and
no dump.

---

## 1. Extended mode is ON by default — your blanks are ignored

The `PCRE` addition of `FIND`/`REPLACE` and the `pcre =` parameter of the string
functions compile the pattern in **extended mode**. Unescaped whitespace outside
character classes is discarded, and `#` starts a comment.

```abap
" Both of these are TRUE. Neither is a typo.
ASSERT NOT matches( val = `Hello World` pcre  = `Hello World` ).
ASSERT     matches( val = `HelloWorld`  pcre  = `Hello World` ).

" POSIX did what you meant:
ASSERT     matches( val = `Hello World` regex = `Hello World` ) ##regex_posix.
```

Three fixes, all documented:

```abap
matches( val = `Hello World` pcre = `Hello\sWorld`  ).  " \s
matches( val = `Hello World` pcre = `Hello\ World`  ).  " escape the blank
matches( val = `Hello World` pcre = `(?-x)Hello World` ). " turn extended mode off
```

Same for `#`: the pattern `Hello#World` matches `Hello` and treats the rest as a
comment. Escape it (`Hello\#World`) or use `(?-x)`.

With `CL_ABAP_REGEX=>CREATE_PCRE` the switch is the parameter `EXTENDED`
(default `ABAP_TRUE`).

**The practical trap:** patterns are often built at runtime by concatenating
user-maintained customizing values. A stray blank in a config table is now
silently invisible in the pattern.

---

## 2. Leftmost vs leftmost-longest — migrating POSIX changes the match

Both libraries backtrack, but they pick a different winner when several matches
start at the same offset. **PCRE returns the leftmost match. POSIX returns the
leftmost *longest* match.**

```abap
match( val = `unfoldable` pcre  = `un(fold|foldable)` ).                 " --> 'unfold'
match( val = `unfoldable` regex = `un(fold|foldable)` ) ##regex_posix.   " --> 'unfoldable'
```

Reordering the alternation fixes that particular case (`un(foldable|fold)`), but
the rule is not limited to `|` — it applies anywhere multiple matches start at
the same place, e.g. with `?`:

```abap
match( val = `unfoldable` pcre = `un(fold)?(foldable)?` ).               " --> 'unfold'
match( val = `unfoldable` pcre = `un(fold(?!able))?(foldable)?` ).       " --> 'unfoldable'
```

A parser that extracted the right substring for ten years starts extracting a
shorter one the day someone swaps `REGEX` for `PCRE`. The output is still a
valid-looking string.

---

## 3. The dot stops at line breaks

In POSIX `.` matches anything. In PCRE `.` matches everything **except** line
breaks. For a multi-line string — an uploaded file, a long text, a SOAP payload —
`.*` silently stops at the first newline.

```abap
replace( val = |Hello\nWorld| pcre  = `.`     with = `x` occ = 0 ).  " newline survives
replace( val = |Hello\nWorld| pcre  = `(?s).` with = `x` occ = 0 ).  " newline replaced
replace( val = |Hello\nWorld| regex = `.`     with = `x` occ = 0 ) ##regex_posix. " replaced
```

Fix with `(?s)` in the pattern, or the `DOT_ALL` parameter of `CREATE_PCRE`.
Which control characters count as a line break is itself configurable
(`NEWLINE_MODE` / control verbs).

---

## 4. Unicode: the statement and the class disagree by default

ABAP strings are UTF-16; characters outside the Basic Multilingual Plane (emoji,
some CJK extensions) are stored as **surrogate pairs** — two UCS-2 units.

| API | Default | Effect |
|---|---|---|
| `FIND`/`REPLACE ... PCRE`, `pcre =` in string functions | relaxed (UCS-2) | a surrogate pair counts as **two** characters; `\C` unavailable |
| `CL_ABAP_REGEX=>CREATE_PCRE` | `UNICODE_HANDLING = STRICT` | UTF-16; invalid UTF-16 raises an exception |

So the same pattern against the same text gives different counts depending on
which API you used. For the statement form, strict mode is switched on by
prefixing the pattern with `(*UTF)`:

```abap
" One EXTRATERRESTRIAL ALIEN (U+1F47D), stored as a surrogate pair.
replace( val = alien pcre = `.`       with = `X` occ = 0 ). " --> 'XX'  (relaxed)
replace( val = alien pcre = `(*UTF).` with = `X` occ = 0 ). " --> 'X'   (strict)
```

There is no way to get *UTF-16 + tolerate invalid input* from the statement form
at all — that combination needs a `CL_ABAP_REGEX` object with
`UNICODE_HANDLING = IGNORE`.

---

## 5. `CX_SY_REGEX_TOO_COMPLEX` depends on the data, not just the pattern

A syntactically valid regex can exceed the kernel's transition limit and raise
`CX_SY_REGEX_TOO_COMPLEX` — and the doc is explicit that this **depends on both
the regular expression and the text**. A pattern that passes every unit test can
dump on one production record.

```abap
DATA(text) = repeat( val = `a` occ = 500 ).

TRY.
    FIND REGEX `.*X.*` IN text MATCH OFFSET DATA(moff) ##regex_posix.
  CATCH cx_sy_regex_too_complex.
    " POSIX raises here at ~500 characters: leftmost-longest + greedy `.*`
    " keeps every candidate prefix alive internally.
ENDTRY.
```

POSIX is markedly more vulnerable than PCRE, which is one of the stronger
arguments for migrating. But the real lesson from the doc's own example is
smaller: `.*X.*` needs no regex at all.

```abap
FIND SUBSTRING 'X' IN text.   " or:  IF text CS 'X'.
```

Reach for `FIND SUBSTRING` first. See
[Character Comparisons](../Character%20Comparisons#readme) for `CS`/`CP`, which
cover a surprising amount of what people write regexes for.

---

## 6. `FIND` traps that have nothing to do with the pattern

**`MATCH OFFSET` / `MATCH LENGTH` are not reset on failure.** If the search
fails, they *retain their previous value*. Reusing the same variable across two
`FIND`s and reading it without checking `sy-subrc` gives you the offset from the
previous search.

**`sy-fdpos` is not filled by `FIND`** — that is the `CO`/`CS`/`CP` operators'
channel. `FIND` reports through `sy-subrc` (0 found / 4 not found) plus the
`MATCH ...` additions.

**Empty matches behave differently for substrings and regexes.**

| Pattern | `FIRST OCCURRENCE` | `ALL OCCURRENCES` |
|---|---|---|
| empty `substring` | found before the first character | `CX_SY_FIND_INFINITE_LOOP` |
| regex matching empty, e.g. `a*` | found before the first character | matches before/between/after **every** character — always succeeds |
| empty `pcre` pattern | `CX_SY_INVALID_REGEX` (`CX_SY_STRG_PAR_VAL` in string functions) | same |

A pattern built at runtime whose quantified part collapses to "matches empty"
therefore does not fail loudly — it succeeds everywhere.

**`SUBMATCHES` with `ALL OCCURRENCES` gives you the LAST occurrence only.** Not
the first, not all of them. Surplus operands are blanked (fixed-length) or
initialized (`string`); surplus subgroups are ignored. To get every submatch,
use `RESULTS` (`MATCH_RESULT_TAB`, with the `SUBMATCHES` sub-table per line) or
`CL_ABAP_MATCHER`.

---

## 7. `CL_ABAP_REGEX`: the modern-looking instantiation is the obsolete one

```abap
" Deprecated - and it creates a POSIX regex, not a PCRE one.
DATA(lo_bad) = NEW cl_abap_regex( ... ).

" Correct:
DATA(lo_regex) = cl_abap_regex=>create_pcre( pattern     = `(\d\d\d)(\D\D\D)(\d\d\d)`
                                             ignore_case = abap_true ).
DATA(lo_matcher) = lo_regex->create_matcher( text = '123abc456' ).
```

`NEW` / `CREATE OBJECT` on `CL_ABAP_REGEX` is deprecated **and** silently gives
you a POSIX instance. Use the factory methods: `CREATE_PCRE`, `CREATE_XPATH2`,
`CREATE_XSD`, `CREATE_POSIX`.

Two more object-form rules:

- Objects go with the **`REGEX`** addition of `FIND`/`REPLACE`, never with
  `PCRE`. (`PCRE` takes a character-like pattern only.)
- `IGNORING CASE` / `RESPECTING CASE` are **not allowed** with an object — case
  handling comes from the object's own properties. Set `IGNORE_CASE` on
  `CREATE_PCRE`.

If the same pattern is applied repeatedly, the object form is the one to use —
it compiles once instead of per call.

---

## 8. ABAP SQL and CDS use a different regex engine

`LIKE_REGEXPR`, `REPLACE_REGEXPR` and `OCCURRENCES_REGEXPR` in ABAP SQL / CDS
also take PCRE syntax, but they execute in the **PCRE1** library inside SAP HANA,
while everything above runs on **PCRE2** in the ABAP Kernel.

Same syntax family, different implementation and different version. Pushing a
regex filter down into a `SELECT` for performance is therefore not guaranteed to
be behaviour-neutral — and the pushdown only exists on HANA. Related:
[Selection Tables](../Selection%20Tables#readme) documents the same class of
divergence for `CP` translated into SQL `LIKE`.

---

## Migration checklist (POSIX → PCRE)

1. Swap `REGEX` → `PCRE`, `regex =` → `pcre =`.
2. **Escape every meaningful blank and `#`**, or prefix `(?-x)`.
3. Check each alternation / `?` for a leftmost-longest dependency; reorder or add
   a lookahead.
4. If the text can contain line breaks, decide between `.` and `(?s).`.
5. If the text can contain non-BMP characters, decide between relaxed and
   `(*UTF)`.
6. Replacement strings: PCRE has `$0`..`$n` for the whole match and subgroups,
   but **no equivalent of POSIX ``$` `` and `$'`** (text before / after the
   match). Emulate with extra capture groups, fall back to offset arithmetic, or
   keep the POSIX pattern under `##regex_posix`.
7. Anything left that genuinely needs POSIX: keep it and pragma it. A working
   POSIX regex beats a migrated one that is subtly wrong.

---

## Files

- [`ydj_pcre_regex_demo.abap`](ydj_pcre_regex_demo.abap) — runnable report
  demonstrating the behaviours above. Read-only, no database access.

## Sources

- [regex — PCRE Syntax](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENREGEX_PCRE_SYNTAX.html)
- [regex — Migrating from POSIX to PCRE](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENREGEX_MIGRATING_POSIX.html)
- [regex — Incompatibilities Between POSIX and PCRE](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENREGEX_POSIX_PCRE_INCOMPAT.html)
- [regex — System Classes (`CL_ABAP_REGEX`, `CL_ABAP_MATCHER`)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENREGEX_SYSTEM_CLASSES.html)
- [regex — Exceptions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENREGEX_EXCEPTIONS.html)
- [`FIND`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPFIND.html) ·
  [`FIND`, pattern](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPFIND_PATTERN.html) ·
  [`FIND`, options](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPFIND_OPTIONS.html)
- [cstring_func — `pcre`, `xpath`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_FUNCTIONS_REGEX.html)
