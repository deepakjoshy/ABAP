# String Building && Substring Access — trailing blanks, `+off(len)`, and the quadratic `&&`

Everything in this note is silent. No syntax error, no dump, no `sy-subrc` — just
a string that is shorter than you expected, a number with the minus on the wrong
side, or a report that runs in 40 seconds instead of 0.4.

The repo's [Character Comparisons](../Character%20Comparisons#readme) note covers
how trailing blanks break `CO`/`CS`. This one covers the other half: what happens
when you **build** and **slice** strings.

---

## 1. The one rule underneath all of it: `c` loses trailing blanks, `string` keeps them

> All blanks are generally preserved in operations with operands of the data type
> `string`. In assignments and statements for character string processing, leading
> blanks for operands of data types with fixed lengths (`c`, `n`, `d`, and `t` or
> character-like structures) are generally preserved and **trailing blanks are
> truncated**.

— [Trailing Blanks in Character String Processing](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_PROCESSING_TRAIL_BLANKS.html)

*Leading* blanks survive, *trailing* blanks do not. Which means `space` and the text
field literal `' '` — whose entire content **is** a trailing blank — evaporate in
most operand positions. The documentation's own example:

```abap
DATA text TYPE string.
CONCATENATE space ' ' INTO text SEPARATED BY ''.
" text now contains exactly ONE blank, not three.
```

Two of the three blanks vanished. The one that survived is the separator — see §2.

A text field literal cannot even *hold* a trailing blank: they are truncated at
compile time. If you need one, use a backtick string literal (`` ` ` ``), which is
type `string` and keeps it.

---

## 2. `CONCATENATE`: the separator plays by different rules than the operands

`CONCATENATE` drops trailing blanks from `dobj1, dobj2 ...`, but for `SEPARATED BY sep`:

> In character string processing, trailing blanks are respected for separators `sep`
> of fixed length.

— [`CONCATENATE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCONCATENATE.html)

That asymmetry is why `SEPARATED BY space` works at all — and why people conclude
that `space` is "fine", then get burned the first time they use it as a normal operand.

To keep trailing blanks in the operands too, use `RESPECTING BLANKS`. The doc's
example is worth internalising, because it shows how much you are actually losing
on a table of `c LENGTH 10` lines:

| Statement | Result |
|---|---|
| `CONCATENATE LINES OF itab INTO result SEPARATED BY space.` | `When the music is over` |
| `CONCATENATE LINES OF itab INTO result RESPECTING BLANKS.` | `When······the·······music·····is········over······` |

`RESPECTING BLANKS` is not "the safe option" — it is a different operation. Pick it
deliberately, when you are rebuilding a fixed-width record.

### The truncation nobody checks

> If the target field is too short, the concatenation is truncated **on the right**.

`sy-subrc = 4` tells you this happened. Almost no production code reads it. If the
target is a `string`, the length adapts and truncation is impossible — which is the
real argument for typing string-building targets as `string` rather than `c LENGTH n`.

---

## 3. `&&` is not `CONCATENATE`, and it is definitely not `&`

Three operators that look interchangeable and are not:

| | When | Trailing blanks of fixed-length operands |
|---|---|---|
| `&` (literal operator) | **Compile time**, literals only | **Always respected** |
| `&&` (concatenation operator) | Runtime, any character-like operand | **Ignored** |
| `CONCATENATE ... RESPECTING BLANKS` | Runtime | Respected |

— [`string_exp - &&`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_OPERATORS.html),
[literal operator `&`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLITERAL_OPERATOR.html)

### The trap: `&&` does not use the conversion rules

A non-character-like operand of `&&` is treated as an **embedded expression of a
string template** — not converted with the normal assignment rules. For a negative
packed or integer value, those two disagree about where the sign goes:

```abap
ASSERT ``  && -1  =   `` && |{ -1 }|.        " TRUE  -> "-1"
ASSERT ``  && -1 <>   `` && CONV string( -1 ). " TRUE  -> CONV gives "1-"
```

Both `ASSERT`s are from the keyword documentation. So `lv_text = lv_text && lv_amount`
and `lv_text = lv_text && CONV string( lv_amount )` produce **different output** as
soon as the amount goes negative — the classic "why does the credit note print
`100.00-`" bug, in reverse.

Structures cannot be operands of `&&` at all, even if every component is character-like.

---

## 4. Building a string in a loop: the optimization you can switch off by accident

The runtime reuses the target variable in place — no interim copy — but **only** for
these two shapes:

- `str &&= dobj1 && dobj2 && ... .`
- `str = |{ str }...{ dobj1 }...{ dobj2 }...|.`

And only if all three hold:

1. `str` occurs **once**, at the **very beginning** of the expression.
2. **No format options** are applied to `str` in the template.
3. Only **directly specified data objects** follow — no functions, no expressions,
   even ones that provably do not depend on `str`.

— [`string_exp` Performance Note](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_EXPR_PERFO.html)

Break any one of them and:

> the runtime is quadratically dependent on the number of iterations, since the
> length of the string in the interim result increases in proportion with the number
> of iterations and has to be copied to the result in every loop pass.

This is the whole bug:

```abap
" QUADRATIC - the function call deactivates the optimization
DO n TIMES.
  html = |{ html }<tr><td>{ CONV string( ipow( base = sy-index exp = 2 ) ) }</td></tr>|.
ENDDO.

" LINEAR - hoist the expression into a helper variable first
DATA square TYPE string.
DO n TIMES.
  square = ipow( base = sy-index exp = 2 ).
  html   = |{ html }<tr><td>{ square }</td></tr>|.
ENDDO.
```

The two versions are visually almost identical and produce identical output. At
n = 10 000 the difference is minutes. **Inside a loop, never call a function inline
in the string expression that appends to the accumulator.**

`CONCATENATE` carries the same caveat from the other direction: the runtime optimizes
appending to an existing string, but "if the string or parts of the string itself are
appended, no optimization takes place, which causes a squared increase in runtime in
loops."

---

## 5. `strlen` vs `numofchar` — they differ on exactly one case

| Function | Fixed length (`c`, `n`, ...) | Type `string` |
|---|---|---|
| `strlen` | trailing blanks **not** counted | trailing blanks **counted** |
| `numofchar` | trailing blanks **not** counted | trailing blanks **not** counted |

— [`charlen`, `dbmaxlen`, `numofchar`, `strlen`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLENGTH_FUNCTIONS.html)

So `strlen( )` changes its answer when someone retypes a field from `c LENGTH 10` to
`string` — a refactoring that looks purely cosmetic. If you want "length of the
content", `numofchar( )` is the function that means that in both cases.

Two more from the same table:

- `charlen( )` returns the length of the **first character only** — 1, or 2 for a
  surrogate pair. It is a codepage probe, not a length function.
- `strlen( )` counts **UCS-2** units, so an emoji (a surrogate pair) counts as 2,
  while `count( val = txt pcre = ... )` under `(*UTF)` counts it as 1. Cross-reference:
  [Regular Expressions](../Regular%20Expressions#readme).

---

## 6. `dobj+off(len)` — the type of the substring is not the type of the field

Direct substring access is the fastest way to slice, and the only way to **write**
to part of a field. But the resulting type is not always what you sliced:

| Original type | Substring type |
|---|---|
| `c` | `c` |
| `n` | `n` |
| **`d`** | **`n`** |
| **`t`** | **`n`** |
| `string` | `string` |
| `x` / `xstring` | `x` / `xstring` |
| Structure | `c` |

— [Offset/Length Specifications for Substring Access](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENOFFSET_LENGTH.html)

`sy-datum+4(2)` is therefore type `n`, **not** `c` — it is numeric text, and it
obeys numeric conversion rules when assigned onward. That is usually what you want
for a month, and occasionally a surprise.

One exception worth knowing: if the substring length matches the structure length
exactly, the result is handled as the structure itself, not as `c`.

### The restrictions that actually come up

- **No write access to substrings of a `string`.** `lv_string+3(2) = 'XX'.` is not
  allowed — only flat data objects are writable at an offset. This is the single
  most common reason a `c LENGTH n` field cannot simply be retyped to `string`.
- **Structures**: only the *first character-like fragment* is addressable. Given a
  structure whose first components are `c(3) n(4) d(8) t(6)` followed by a
  `decfloat16`, `struc(21)` is legal and `struc+57(2)` is not — the non-character
  component ends the addressable fragment.
- **Out of bounds** is a syntax error when statically identifiable, otherwise
  `CX_SY_RANGE_OUT_OF_BOUNDS` (runtime error `STRING_OFFSET_TOO_LARGE`). A variable
  offset computed from data is the dangerous form.
- **Inline declarations**: with `DATA(x) = dobj+off(len).` the `off` and `len` must
  be **literals or constants**. Variables are not allowed there.
- `len` may be `*` (to the end of the field), but only if `off` is smaller than the
  field length. Length `0` is allowed only for strings.
- Substrings of strings are also barred from a few read positions: as the memory
  area of `ASSIGN`, as the operand of `GET REFERENCE` / `REF`, and as an actual
  parameter for input parameters of methods, function modules and subroutines.
- Offsets cannot be attached to literals, text symbols, or a table expression
  `itab[ ... ]` directly — only to a component after the component selector.

### Two genuinely obscure ones

`dobj+0(*)`, `dobj+0` and `dobj(*)` are all interpreted as plain `dobj` — and in
that case `dobj` may even be a data object where substring access would not
otherwise be allowed.

And the one that will cost you an afternoon: **you cannot write `cnt(len)` or
`sum(len)`** on data objects actually named `cnt` or `sum` without an explicit
offset. The compiler always reads those as the `cnt`/`sum` group-level functions of
an extract dataset. `cnt+0(len)` works.

> The documentation recommends always writing the offset explicitly —
> `dobj+0(len)` rather than `dobj(len)` — so that substring access is visually
> distinct from method calls, dynamic specifications and inline declarations,
> which also use parentheses.

---

## 7. The `substring_*` functions: convenient, slower, and empty on a miss

`substring`, `substring_from`, `substring_after`, `substring_before`, `substring_to`
always return type `string`, and can be used in operand positions where `+off(len)`
cannot (including on enumerated objects, via an implicit conversion to `string`).

The trade-off, stated in the doc: **their performance is not as good as direct
substring access.**

The failure modes are inconsistent between the two families, which is worth a table:

| Situation | `find( )` | `substring_from( )` | `find_any_of( )` |
|---|---|---|---|
| Not found | returns `-1` | returns **empty string** | returns `-1` |
| `sub` is empty | `CX_SY_STRG_PAR_VAL` | `CX_SY_STRG_PAR_VAL` | returns `-1` |
| `occ = 0` | `CX_SY_STRG_PAR_VAL` | `CX_SY_STRG_PAR_VAL` | — |

— [`find`, `find_...`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSEARCH_FUNCTIONS.html),
[`substring`, `substring_...`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSUBSTRING_FUNCTIONS.html)

So a `substring_after( )` that found nothing is indistinguishable from one that
found a match at the very end of the string. Both give `''`. If the difference
matters, test with `find( )` first.

Note also that `find_any_of` / `find_any_not_of` are **always case-sensitive** — the
`case` parameter does not apply to them, unlike `find` and the substring functions.
They are also the only two that return `-1` for an empty `sub` rather than raising.

A negative `occ` searches **right to left**, which is the clean way to get "everything
after the last separator" without a loop.

Finally, `find( )` and the `FIND` statement "can be faster than the comparison
operator `CS` by some magnitude" — so a `CS` used purely to locate a substring is
worth rewriting.

---

## 8. `CONDENSE` and the `condense( )` function

`CONDENSE text.` removes leading and trailing blanks and collapses every internal
run of blanks to exactly one. `NO-GAPS` removes internal blanks entirely.

The part that trips people: on a **fixed-length** field the freed space is padded
back with blanks on the right — the field is still 30 characters long, the content
just moved left. Only for a `string` does the length actually shrink. So
`CONDENSE lv_c30.` followed by `strlen( lv_c30 )` may return the same number it did
before, because `strlen` was already ignoring the trailing blanks.

— [`CONDENSE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCONDENSE.html)

---

## Quick decision table

| You want to | Use |
|---|---|
| Append in a loop | `str &&= dobj.` with **no** inline function calls |
| Rebuild a fixed-width record | `CONCATENATE ... RESPECTING BLANKS` |
| Join internal table lines | `concat_lines_of( )` or `CONCATENATE LINES OF` |
| Length of the *content* | `numofchar( )` |
| Slice at a known position, or write into a field | `dobj+off(len)` |
| Slice relative to a delimiter | `substring_after( )` / `substring_before( )` |
| Last occurrence of a delimiter | `find( ... occ = -1 )` |
| Strip padding before comparing | `condense( )` |

## Sources

- [Trailing Blanks in Character String Processing](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_PROCESSING_TRAIL_BLANKS.html)
- [`CONCATENATE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCONCATENATE.html)
- [`string_exp - &&`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_OPERATORS.html)
- [`string_exp` - Performance Note](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_EXPR_PERFO.html)
- [Offset/Length Specifications for Substring Access](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENOFFSET_LENGTH.html)
- [`charlen`, `dbmaxlen`, `numofchar`, `strlen`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLENGTH_FUNCTIONS.html)
- [`find`, `find_...` - Search Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSEARCH_FUNCTIONS.html)
- [`substring`, `substring_...`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSUBSTRING_FUNCTIONS.html)
- [`CONDENSE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCONDENSE.html)

Runnable demo: [`ydj_string_build_demo.abap`](ydj_string_build_demo.abap)
