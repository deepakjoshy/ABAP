# Character Comparisons — `CO` / `CA` / `CS` / `CP`, `sy-fdpos`, and the trailing-blank rules

These eight operators are everyday ABAP, but they behave unlike the rest of the
language in three ways that bite:

1. They report their result through **`sy-fdpos`**, not `sy-subrc` — and on a
   *failed* comparison `sy-fdpos` holds a plausible-looking offset.
2. **Half of them are case-sensitive and half are not.**
3. They **respect trailing blanks** in operand positions where nearly every other
   statement silently throws them away.

None of these produce a syntax error or a dump. They produce wrong answers.

---

## 1. `sy-fdpos` is not a `sy-subrc`

| Operator | If comparison is **true** | If comparison is **false** |
|---|---|---|
| `CO` | length of `operand1` | offset of first char of `operand1` **not** in `operand2` |
| `CN` | offset of first char **not** in `operand2` | length of `operand1` |
| `CA` | offset of first char of `operand1` **also** in `operand2` | length of `operand1` |
| `NA` | length of `operand1` | offset of first char also in `operand2` |
| `CS` | offset of `operand2` inside `operand1` | length of `operand1` |
| `NS` | length of `operand1` | offset of `operand2` inside `operand1` |
| `CP` | offset of the match (leading `*` ignored) | length of `operand1` |
| `NP` | length of `operand1` | offset of the match |

— [Comparison Operators for Character-Like Data Types](https://help.sap.com/doc/abapdocu_latest_index_htm/LATEST/en-US/ABENLOGEXP_STRINGS.html)

Two things fall out of that table.

**On a miss, `sy-fdpos` is the length of the left operand** — not `-1`, not `0`. On a
6-character field a failed `CS` leaves `sy-fdpos = 6`, which is indistinguishable
from a legitimate offset unless you check the `IF` first.

```abap
DATA(text) = `ABCDEF`.

IF text CS `XYZ`.
ENDIF.
" sy-fdpos = 6 here. Nothing found, but the value looks like a hit.
```

**The same number means opposite things depending on the operator.** `sy-fdpos =
strlen( )` means *failure* for `CS` and *success* for `CO`. Always branch on the
logical expression; only read `sy-fdpos` inside the branch that proves it meaningful.

> When these operators are used inside a conditional expression (`COND`) or a
> Boolean function, `sy-fdpos` holds the value set by the expression once the
> expression has been processed — which is what makes
> `COND #( WHEN abcde CS 'H' THEN sy-fdpos )` work.

---

## 2. Trailing blanks: the `CO` digit check that fails

`CO`, `CN`, `CA` and `NA` respect trailing blanks **in both operands**. A `c` field is
blank-padded to its declared length, and those pad blanks are real characters that
must also be listed on the right:

```abap
DATA lv_c TYPE c LENGTH 10 VALUE '123'.

IF lv_c CO '0123456789'.    " FALSE — sy-fdpos = 3, the first pad blank
```

Two fixes, both fine:

```abap
IF lv_c CO `0123456789 `.          " allow the blank (note the backticks)
IF condense( lv_c ) CO '0123456789'.  " strip the padding, compare as string
```

The backticks matter. A *text field literal* `'...'` of type `c` has its trailing
blanks truncated in many operand positions, so `'0123456789 '` may not carry the
blank you intended. A *text string literal* `` `...` `` is type `string` and always
preserves it.

> "All blanks are generally preserved in operations with operands of the data type
> `string`. In assignments and statements for character string processing, leading
> blanks for operands of data types with fixed lengths (`c`, `n`, `d`, and `t`) are
> generally preserved and **trailing blanks are truncated**."
> — [Trailing Blanks in Character String Processing](https://help.sap.com/doc/abapdocu_latest_index_htm/LATEST/en-US/ABENSTRING_PROCESSING_TRAIL_BLANKS.html)

This is also why SAP's own guideline is *never* to put `space` or `' '` in an operand
position where trailing blanks are cut. `CONCATENATE space ' ' INTO t SEPARATED BY ''`
yields a string with exactly **one** blank, not three, unless `RESPECTING BLANKS` is
added.

---

## 3. `CP` means *Conforms to* Pattern, not *Contains* Pattern

The pattern has to describe the **whole** operand:

```abap
DATA(html) = `This is <i>italic</i>!`.

IF html CP `<*>`.      " FALSE — the pattern must cover the entire string
IF html CP `*<*>*`.    " TRUE  — sy-fdpos = 8
```

Wildcards: `*` is any character string *including empty*; `+` is exactly one
character and **never** an empty one. Consecutive `*` behave as a single `*`. Leading
`*` characters are ignored when computing `sy-fdpos`, so the offset points at the real
match.

A pattern with no wildcards at all is pointless — use `=` instead, with
`to_upper( )`/`to_lower( )` on both sides if you wanted the case-insensitivity.

### The `#` escape does less than it looks like

`#` marks the **next single character** for direct comparison. For *that character
only*: wildcards lose their meaning, the comparison becomes case-sensitive, and
trailing blanks become relevant. The rest of the pattern is unaffected.

```abap
IF `abc` CP `Abc`.     " TRUE  — CP ignores case
IF `abc` CP `#Abc`.    " FALSE — only the escaped A is compared exactly
```

Use it whenever the data itself may contain `*`, `+` or `#`:

```abap
IF formula CP `*#*RATE`.   " literal asterisk, then RATE
```

---

## 4. Case sensitivity is split down the middle

| Case-**insensitive** | Case-**sensitive** |
|---|---|
| `CS`, `NS`, `CP`, `NP` | `CO`, `CN`, `CA`, `NA` |

So `'abc' CA 'ABC'` is **false** — no lowercase character appears in the right
operand.

### Predicate functions are not drop-in replacements

The docs map the operators onto predicate functions, but note what has to be added:

| Operator | Predicate function |
|---|---|
| `o1 CO o2` | `NOT contains_any_not_of( val = o1 sub = o2 )` |
| `o1 CN o2` | `contains_any_not_of( val = o1 sub = o2 )` |
| `o1 CA o2` | `contains_any_of( val = o1 sub = o2 )` |
| `o1 NA o2` | `NOT contains_any_of( val = o1 sub = o2 )` |
| `o1 CS o2` | `contains( val = to_upper( o1 ) sub = to_upper( o2 ) )` |
| `o1 NS o2` | `NOT contains( val = to_upper( o1 ) sub = to_upper( o2 ) )` |

— [Comparison Operators vs. Predicate Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/LATEST/en-US/ABENCHAR_COMP_OP_VS_FUNCT.html)

The `to_upper( )` wrappers on `CS`/`NS` are **mandatory**, because the functions are
case-sensitive and the operators are not. Rewriting `IF text CS 'WORLD'` as
`IF contains( val = text sub = 'WORLD' )` during a "clean up the old code" pass
silently narrows the match.

Also: **the predicate functions always ignore trailing blanks** of fixed-length
arguments, whereas the operators have documented exceptions. So the rewrite can change
behaviour in the other direction too.

`CP`/`NP` map onto `contains( ... pcre = ... )` or `matches( )` with a regular
expression — `case = ' '` restores the case-insensitivity:

```abap
ASSERT text CP `*aaa*` AND matches( val = text pcre = `.*aaa.*` case = ' ' ).
```

For plain substring searches, `FIND` and the `find( )` functions can be **orders of
magnitude faster** than `CS`.

---

## 5. Empty operands — why validation guards pass on empty input

The rules are asymmetric, and they are the reason a "digits only" check accepts an
empty field:

- **`CO`** — if `operand1` is an initial `string`, the result is **always true**,
  regardless of `operand2`. Vacuously, an empty string contains only permitted
  characters. If `operand2` is an initial `string` (and `operand1` is not), it is false.
- **`CA`** — if **either** operand is an initial `string`, the result is always false.
- **`CS`** — if `operand1` is an initial `string`, or type `c` containing only blanks,
  it is false — *unless* `operand2` is also empty/all-blank, in which case it is true.

```abap
IF value CO '0123456789'.        " passes for an EMPTY value
IF value IS NOT INITIAL AND value CO '0123456789'.   " correct guard
```

---

## 6. The comparison *type* changes the meaning

Before comparing, ABAP picks a comparison type and converts both operands to it:

| | `string` | `c` | `n` |
|---|---|---|---|
| **`string`** | `string` | `string` | `p` |
| **`c`** | `string` | `c` | `p` |
| **`n`** | `p` | `p` | `n` |

— [Comparison Type of Character-Like Data Objects](https://help.sap.com/doc/abapdocu_latest_index_htm/LATEST/en-US/ABENLOGEXP_CHARACTER.html)

**Type `n` against `c`/`string` is a *numeric* comparison.** Leading zeros disappear,
and a non-numeric character operand raises the uncatchable runtime error
`CONVT_NO_NUMBER`:

```abap
DATA matnr TYPE n LENGTH 10 VALUE '0000004711'.

IF matnr = '4711'.               " TRUE  — compared as packed numbers
IF CONV string( matnr ) = `4711`. " FALSE — compared as characters
```

**Length adjustment differs by type.** Two `c` operands of different length: the
shorter is padded right with blanks. Two `n` operands: padded **left** with `0`. Two
`string` operands of different length **never match** — if the content agrees up to the
shorter length, the shorter one sorts smaller.

### `boolc( )` vs `abap_false`

The classic instance of all of the above at once:

```abap
IF boolc( 1 = 2 ) = abap_false.    " FALSE — surprising but documented
IF xsdbool( 1 = 2 ) = abap_false.  " TRUE
```

`boolc( )` returns type `string` containing a single blank. `abap_false` is type `c`
length 1 containing a blank. The comparison type is `string`, so `abap_false` is
converted to a string — and its blank is dropped as a trailing blank, leaving an empty
string that can never equal a one-blank string. `xsdbool( )` returns type `c` length 1,
so no conversion happens.

The same reason makes `boolc( ... ) IS INITIAL` unreliable: the result holds a blank,
which is not the initial value of a `string`.

---

## Files

- [`ydj_char_compare_demo.abap`](ydj_char_compare_demo.abap) — runnable report
  demonstrating all ten behaviours above. Read-only, no database access.

## Sources

- [rel_exp — Comparison Operators for Character-Like Data Types](https://help.sap.com/doc/abapdocu_latest_index_htm/LATEST/en-US/ABENLOGEXP_STRINGS.html)
- [rel_exp — Comparison Type of Character-Like Data Objects](https://help.sap.com/doc/abapdocu_latest_index_htm/LATEST/en-US/ABENLOGEXP_CHARACTER.html)
- [rel_exp — Comparison Operators vs. Predicate Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/LATEST/en-US/ABENCHAR_COMP_OP_VS_FUNCT.html)
- [Trailing Blanks in Character String Processing](https://help.sap.com/doc/abapdocu_latest_index_htm/LATEST/en-US/ABENSTRING_PROCESSING_TRAIL_BLANKS.html)
- [Do not use trailing blanks in text field literals](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENTRAILING_BLANKS_LITERALS_GUIDL.html)
