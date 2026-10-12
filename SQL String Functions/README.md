# String Functions in ABAP SQL — the separator that survives `&&` but not `CONCAT`, the padding function that shortens, and the search term you are not allowed to compute

Formatting a character column on the database instead of in ABAP is usually
the right move: one statement instead of a `LOOP`, no rows transported just to
be trimmed, a `WHERE` the database can evaluate. ABAP SQL has a full set of
string functions for it — `CONCAT`, `LENGTH`, `LEFT`, `RIGHT`, `SUBSTRING`,
`LPAD`, `RPAD`, `LTRIM`, `RTRIM`, `REPLACE`, `INSTR`, `LOCATE`, `UPPER`,
`LOWER`, `INITCAP` and a PCRE family.

They work. What is worth reading before you move string handling into a
`SELECT` is that **the database does not share ABAP's idea of what a character
field is**, and the functions do not even fully agree with each other:

- a blank separator survives the operator `&&` and is **silently dropped** by
  the function `CONCAT` — same concatenation, one of them unreadable;
- `LPAD` and `RPAD` cut the value short when the requested length is too
  small, and both cut on the **right** — so the left-padding function removes
  the end of the value;
- an empty padding character means "do nothing" rather than "pad with
  nothing", so the result length stops being fixed;
- `LTRIM` and `RTRIM` remove the **trailing blanks** of their argument no
  matter which end you asked about;
- the search term of `INSTR` and `LOCATE` must be a literal or a host
  **constant** — never a host variable — and it respects every trailing blank
  the declaration gave it, so the obvious `CONSTANTS` declaration never
  matches;
- `REPLACE` can be a **syntax error** because of the declared lengths of its
  arguments, with no regard for how short the real data is;
- exactly eight of these functions can be evaluated by the ABAP SQL in-memory
  engine. Every other one **bypasses table buffering** — including `&&`, but
  not `CONCAT`;
- and six of them do not exist in ABAP CDS at all, while `REPLACE_REGEXPR`
  exists only in view entities and not in DDIC-based views.

Everything below is quoted from the ABAP keyword documentation. The runnable
counterpart is `ydj_sql_string_func_demo.abap` in this folder: read-only, no
`COMMIT`, and it prints the actual values rather than asserting them.

## 0. The family, and where each member exists

From the DDIC overview table
([SQL Functions for Strings](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_FUNCTIONS_STRING.html))
and the ABAP SQL page
([`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)):

| Function | CDS DDIC-based view | CDS view entity | ABAP SQL | In-memory engine |
|---|---|---|---|---|
| `CONCAT`, `CONCAT_WITH_SPACE` | x | x | x | **x** |
| `LEFT`, `RIGHT`, `LENGTH`, `SUBSTRING` | x | x | x | **x** |
| `UPPER`, `LOWER` | x | x | x | **x** |
| `LPAD`, `RPAD`, `LTRIM`, `RTRIM` | x | x | x | — |
| `REPLACE` | x | x | x | — |
| `INSTR` | x | x | x | — |
| `INITCAP`, `LOCATE` | — | — | x | — |
| `LIKE_REGEXPR`, `LOCATE_REGEXPR`, `LOCATE_REGEXPR_AFTER` | — | — | x | — |
| `OCCURRENCES_REGEXPR`, `SUBSTRING_REGEXPR` | — | — | x | — |
| `REPLACE_REGEXPR` | — | x | x | — |

Two things fall out of that table before any behaviour does. A `SELECT` that
uses `LOCATE` or `INITCAP` **cannot be lifted into a CDS view entity**, and a
view entity that uses `REPLACE_REGEXPR` cannot be rewritten as a DDIC-based
view. The same split exists on the date side — see
[SQL Date & Time Functions](../SQL%20Date%20and%20Time%20Functions#readme),
where the generic date functions are ABAP SQL only.

Syntax note that costs everyone one failed activation: **a blank is mandatory
after the opening parenthesis and in front of the closing one.**

> "The arguments `arg1`, `arg2`, ... of the function are specified as a
> comma-separated list in parentheses. A blank must be placed after the
> opening parenthesis and in front of the closing parenthesis."
> — [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

## 1. The separator that survives `&&` and not `CONCAT`

There are two ways to concatenate in ABAP SQL: the operator `&&` and the
function `CONCAT`. They are not interchangeable, and the difference is a
character you cannot see.

The operator has an explicit exception for all-blank operands:

> "The result of the concatenation must be no longer than 255 characters.
> Trailing blanks are handled as follows:"
> - "Precisely one blank is respected in host variables declared using
>   `CONSTANTS` and in text field literals consisting only of blanks."
> - "In all other cases, trailing blanks are cut off on the right."
> — [`sql_exp` — `sql_string`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING.html)

The function does not:

> "Concatenates strings in `sql_exp1` and `sql_exp2`. Trailing blanks in
> `sql_exp1`, `sql_exp2`, and in the result are ignored."
> — [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

and the hint list says so in as many words, as a *benefit*:

> "It does not apply any special handling to constants and text field literals
> that contain only blanks."
> — [`sql_exp` — `sql_string`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING.html)

So this works:

```abap
SELECT FROM scarr
       FIELDS carrid && ' ' && '(' && carrname && ')' AS line
       INTO TABLE @DATA(lt_ok).
```

and the apparently equivalent rewrite loses the blank, not the parenthesis:

```abap
" AAAmerican Airlines - the separator is gone, no warning anywhere
SELECT FROM scarr
       FIELDS concat( carrid, carrname ) AS line
       INTO TABLE @DATA(lt_squashed).

" AA American Airlines - the function form of a separator
SELECT FROM scarr
       FIELDS concat_with_space( carrid, carrname, 1 ) AS line
       INTO TABLE @DATA(lt_fixed).
```

The rest of the differences are documented as the reason `CONCAT` exists:

| | `&&` | `CONCAT`|
|---|---|---|
| Operands | elementary SQL expressions only | "It allows any SQL expressions as operands." |
| Literal | "must be a non-empty text field literal of type `c`" | more types |
| Host variables | "must be of ABAP type `c`" | more types |
| Column types | `CHAR`, `CLNT`, `CUKY`, `LANG`, `UNIT` | also `DATS`, `NUMC`, `TIMS`, `SSTRING` |
| Max result | 255 | 1333 |
| All-blank literal | kept (exactly one blank) | ignored |
| Table buffer | always bypassed | can run in the in-memory engine |
| Null operand | "the result of the full string expression is the null value" | not stated on the function page |

The last two rows are the ones that bite in opposite directions. A
`CHAR`-only, 255-character, buffer-bypassing operator is the one that handles
your separator correctly; the flexible, buffer-friendly function is the one
that throws it away.

## 2. `LENGTH` is the length of the content, not of the column

> "Number of characters in `sql_exp` ignoring trailing blanks"
> — `LENGTH`, [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

`LENGTH( carrname )` on a `CHAR(20)` column returns 17 for `American Airlines`,
not 20. That matches ABAP's `strlen( )` on a fixed-length field — see
[String Building & Substring Access](../String%20Processing#readme) — so it is
not a surprise on its own. It becomes one in combination: **almost every
string function strips the trailing blanks of its first argument before doing
anything**, so the padding that makes a `CHAR` column a fixed-width column
does not exist from the database's point of view.

`LEFT`, `RIGHT` and the pad functions all repeat the phrase:

> "String of the length `len` with the `len` right characters of `arg`
> (ignoring the trailing blanks). The value of `len` cannot be greater than
> the length of `sql_exp`."
> — `RIGHT`, [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

So `RIGHT( carrname, 3 )` is `nes`, not three blanks — which is what the same
offset/length access in ABAP would have given you. If you want fixed-width
output you have to ask for it explicitly with `LPAD`/`RPAD`; SAP's own example
on the keyword page does exactly that, and notes that `&&` cannot do it at all.

One honest gap: the keyword page describes `INSTR` and `LOCATE` as returning a
"position" and the `*_REGEXPR` functions as returning an "offset", and
documents `LOCATE_REGEXPR_AFTER` as "the offset of the match plus *1*" —
without stating anywhere whether `SUBSTRING`'s `pos` and `INSTR`'s result are
counted from 0 or from 1. **Do not hard-code the base.** The demo prints
`left( carrname, 3 )` and `substring( carrname, 1, 3 )` next to each other so
you can read your release's convention off the list instead of guessing.

## 3. The padding functions also shorten, and they do it on the right

> "String of the length `len` with the right-aligned content of `sql_exp`
> without trailing blanks and in which leading blanks produced by the expanded
> string are replaced by the characters from the argument `src` (respecting all
> blanks). Leading blanks from `sql_exp` are preserved. If more characters are
> required than exist in `src`, the content of `src` is used repeatedly. **If
> `len` is less than the length of `sql_exp`, it is truncated on the right.** If
> `src` is empty and `len` is greater than the length of `sql_exp`, `sql_exp`
> remains unchanged."
> — `LPAD`, [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)
> (`RPAD` carries the same two sentences)

Three separate traps in one paragraph:

**It is not a padding function, it is a width function.** `LPAD( name, 10, ' ' )`
on a `CHAR(30)` column does not right-align a name into ten characters — for
any name longer than ten characters it returns the first ten and drops the
rest. No exception, no null value, no `sy-subrc`. A report column that was
wide enough on the test system silently starts producing wrong names when
someone maintains a longer description.

**The direction is the same for both functions.** `LPAD` adds on the left and
removes on the right. A left-aligned reader assumes the opposite.

**An empty pad character is a no-op, not an error.** Pass a host variable that
happens to be initial as `src` and the value "remains unchanged" — the column
you were relying on to be exactly `len` wide comes back at its natural length,
for some rows and not others.

On top of that:

> "The functions `LPAD` and `RPAD` can produce the result type `SSTRING` with
> an undefined length. This result type can be propagated to other expressions
> and functions."
> — [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

## 4. `LTRIM`/`RTRIM` take the trailing blanks either way

> "String with the content of `sql_exp` in which all leading characters that
> match the characters in `char` are removed. Trailing blanks are removed from
> `sql_exp` but are significant in `char`."
> — `LTRIM`, [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

`LTRIM` is documented as a *leading*-character operation and it still removes
the trailing blanks. That is harmless on a `CHAR` column and not harmless on
an `SSTRING` where a trailing blank was data.

The second half of that sentence is the sharper one: blanks **are** significant
inside `char`. The natural way to make the trim character configurable —

```abap
DATA lv_trim TYPE c LENGTH 10 VALUE '0'.   " nine blanks nobody typed
...  ltrim( matnr, @lv_trim )  ...
```

passes a ten-character argument, so blanks join the set of characters being
removed. Unlike `INSTR`, the `char` argument here **does** accept a host
variable ("Literal, host variable, host constant, or SQL expression"), which
is exactly why this is the one place the padded-constant problem is easy to
introduce without a syntax error stopping you.

## 5. The search term you are not allowed to compute

> "Position of the first occurrence of the string from `sub` in `sql_exp`
> (case-sensitive). `sql_exp` respects leading blanks and ignores trailing
> blanks. `sub` respects all blanks. `sub` must contain at least one
> character. If no occurrences are found, the result is 0."
> — `INSTR`, [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

and the argument column for `sub`:

> "`sub`: Literal or host constant with the ABAP type `c`, `n`, `d`, or `t`"
> — `INSTR`, [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

**A host variable is not in that list.** `INSTR( url, @lv_term )` does not
compile, so the one case everybody wants it for — a search term typed on a
selection screen — is the case it cannot do. `LOCATE` has the same
restriction on `sub`. For a value computed at runtime you are back to `LIKE`
with a host variable (see
[Selection Tables & Ranges](../Selection%20Tables#readme) for how `CP` becomes
`LIKE ... ESCAPE '#'`, and that it turns case-sensitive on the way), or
`LIKE_REGEXPR`, whose `pcre` argument may be any SQL expression.

Then the blanks. A host constant is a fixed-length field, so the obvious
declaration carries padding into the search:

```abap
CONSTANTS c_sub_exact  TYPE c LENGTH 4  VALUE 'http'.   " matches
CONSTANTS c_sub_padded TYPE c LENGTH 10 VALUE 'http'.   " never matches
```

`sub` "respects all blanks", and `sql_exp` "ignores trailing blanks", so
`http` followed by six blanks cannot occur anywhere in the value and the
result is 0 — the same 0 that means "not found" for genuinely absent text. A
filter built on `INSTR( col, @c_sub_padded ) > 0` returns an empty result set
and looks like a data problem. **Declare the constant at exactly the length of
its value**, or use a literal.

`LOCATE` is the more capable sibling (optional `start` and `occ`, negative
`start` to search right-to-left) and it differs on blanks in the first
argument too:

> "Both `sql_exp` and `sub` respect all blanks and must contain at least one
> character. [...] If `sql_exp`, `sub` or `occ` are specified as null value,
> the result is 0."
> — `LOCATE`, [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

So `INSTR` and `LOCATE` disagree about the trailing blanks of the *searched*
column as well, and `LOCATE` returns 0 both for "not found" and for a null
input — the same ambiguity as `IS_VALID` on the date side.

## 6. `REPLACE` fails at compile time on data that is never long

> "In the case of the function `REPLACE`, it should be noted that the maximum
> possible length of the result can easily reach the allowed length of 1333,
> which produces a syntax error. In general, the maximum possible length is
> calculated by dividing the length of `sql_exp1` by the length of `sql_exp2`,
> multiplied by the length of `sql_exp3`."
> — [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

The length that matters is the **declared** length of the column, not the
content. `REPLACE( text1000, '-', '<br/>' )` computes 1000 / 1 * 5 = 5000 and
is rejected by the syntax check even if every row holds four characters. The
documented way out is to stop fighting the 1333:

> "All string functions with the result type `SSTRING` can have a maximum of
> 1333 characters. This length restriction can be avoided by using the type
> conversion function `TO_CLOB` on the result, thus converting it to type
> `STRING`."
> — [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

`REPLACE` is also case-sensitive ("The replacement of letters is
case-sensitive") and ignores trailing blanks in **all three** arguments, so it
cannot be used to replace a blank-padded token.

## 7. Which functions keep the table buffer

This is the performance half of the note, and it is a short list:

> "String functions `CONCAT`, `CONCAT_WITH_SPACE`, `LEFT`, `LENGTH`, `LOWER`,
> `RIGHT`, `UPPER` and `SUBSTRING`"
> — [ABAP SQL In-Memory Engine, Supported SQL Expressions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_ENGINE_EXPR.html)

Those eight, used in a `SELECT` list or a `WHERE` clause, "does not lead to
the bypassing of table buffering and does not cause the transport of an
internal table accessed with `FROM @itab` to the database". Everything else —
`LPAD`, `RPAD`, `LTRIM`, `RTRIM`, `REPLACE`, `INSTR`, `LOCATE`, `INITCAP`, the
whole PCRE family, and the operator `&&` — does both.

Two consequences worth internalising:

- adding `RTRIM( ... )` to a `WHERE` on a **fully buffered** customizing table
  moves every read of that statement from the application server's buffer to
  the database, permanently and invisibly (see
  [Table Buffering](../Table%20Buffering#readme) for the rest of the bypass
  list);
- in a `SELECT ... FROM @itab`, a non-engine function forces the internal
  table to be **transported to the database**, and "This is only possible for
  one internal table per ABAP SQL statement" — so the second `FROM @itab` in
  the same statement turns a formatting convenience into a syntax problem.

`SUBSTRING` carries an extra sentence the others do not: "The function is
always executed in the table buffer."

## 8. Types: what is allowed, and what `UPPER` refuses

> "The possible data types are the dictionary types `CHAR`, `CLNT`, `CUKY`,
> `DATS`, `LANG`, `NUMC`, `TIMS`, `UNIT`, and `SSTRING` with the following
> exceptions:"
> - "The type `NUMC` is not allowed for `LIKE_REGEXPR`, `LOCATE_REGEXPR`,
>   `LOCATE_REGEXPR_AFTER`, `OCCURRENCES_REGEXPR`, `REPLACE_REGEXPR`,
>   `SUBSTRING_REGEXPR`."
> - "The types `NUMC`, `DATS` and `TIMS` are not allowed for `INITCAP`,
>   `LOWER`, `UPPER`."
> — [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

Points worth noting:

- `STRING` is **not** in that list. A real text/CLOB column cannot be passed to
  these functions at all; `SSTRING` (the short string, up to 1333) can.
  `TO_CLOB` converts a *result* to `STRING`, it does not make a `STRING`
  column an acceptable argument.
- `UPPER( erdat )` is a **syntax error**, not a pointless no-op. The same for
  `UPPER` on a `NUMC` material number — which is annoying precisely because
  `NUMC` is allowed for `CONCAT`, `INSTR` and `REPLACE`, so the restriction
  only shows up when someone adds the case-folding later.
- `CLNT` being allowed means you can concatenate the client column into a
  result; see [CDS View Entities](../CDS%20Client%20Handling#readme) for why
  that is usually a mistake.

## 9. Strict mode, and the PCRE that is not the ABAP PCRE

> "ABAP SQL string functions enforce the strict mode of the syntax check from
> ABAP release 7.62."
> — [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

The strict mode applies to the **whole statement**, not to the function, so
adding `CONCAT` to an old `SELECT` re-checks every other line of it against a
newer rule set — and the error you get is on a line you did not touch. The
PCRE functions raise that bar again:

> "The functions that include the `pcre` parameter access the PCRE1 library
> implemented in the SAP HANA database. They enforce the strict mode of the
> syntax check from ABAP release 7.81. The regular expressions of general ABAP
> work with the PCRE2 library implemented in the ABAP Kernel."
> — [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

**Two different regex engines, and the opposite default.** The repo's
[Regular Expressions](../Regular%20Expressions#readme) note documents that the
ABAP-side `pcre` parameter compiles in *extended* mode by default, where an
unescaped blank is ignored and `#` starts a comment. In ABAP SQL it is the
other way round:

> "The operands passed to the argument `pcre` are not interpreted in extended
> mode. The pattern `?x` can be used to enable extended mode."
> — [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

So the same pattern string means two different things depending on whether it
is matched by `FIND ... PCRE` or by `LIKE_REGEXPR`, and moving a working
pattern from ABAP into a `SELECT` changes how its blanks are read. (The page
writes the switch as `?x`; the PCRE spelling of an inline option group is
`(?x)` — quoted as printed, flagged because it matters when you copy it.)

One more documented asymmetry: `REPLACE_REGEXPR` has parameters in CDS view
entities that ABAP SQL does not accept —

> "Not all of the parameters that can be specified for the `REPLACE_REGEXPR`
> function in ABAP CDS view entities (`UNGREEDY`, for example) can be
> specified for ABAP SQL as well. This functionality can be implemented
> through the Perl Compatible Regular Expression syntax itself."
> — [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html)

## 10. What the demo does

`ydj_sql_string_func_demo.abap` is a read-only report over `SCARR` with five
parts, matching sections 1-5 above. It prints values instead of asserting
them, because the point of most of these is that the result looks plausible:

1. `&&` vs `CONCAT` vs `CONCAT_WITH_SPACE` on the same two columns.
2. `LENGTH` next to `DESCRIBE FIELD ... LENGTH`, plus `LEFT`, `RIGHT` and
   `SUBSTRING` so the counting base is visible rather than assumed.
3. `LPAD` to a width wider and narrower than the value.
4. `INSTR` with a literal, with an exactly-sized host constant, and with a
   padded host constant that returns 0.
5. `REPLACE` (case-sensitive, growing), `LTRIM`, `UPPER`, `LOWER`.

It deliberately uses only the long-available functions. `LOCATE`, `INITCAP`
and the `*_REGEXPR` family are left to this README, because an unsupported SQL
function is a **syntax** error — one of them on an older system would stop the
whole report from compiling, not just that one statement.

## Sources

- [`sql_func` — String Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html) — the full ABAP SQL table, argument types, result types and hints
- [DDIC — SQL Functions for Strings](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_FUNCTIONS_STRING.html) — the CDS / ABAP SQL / in-memory availability matrix
- [`sql_exp` — `sql_string`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING.html) — the `&&` operator, its blank rule and the `CONCAT` comparison
- [ABAP SQL In-Memory Engine, Supported SQL Expressions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_ENGINE_EXPR.html) — the eight buffer-safe functions
- [DDIC — SQL Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_FUNCTIONS.html) — overview and the table-buffer hint

Related notes in this repo: [SQL Date & Time Functions](../SQL%20Date%20and%20Time%20Functions#readme),
[String Building & Substring Access](../String%20Processing#readme),
[Regular Expressions](../Regular%20Expressions#readme),
[Table Buffering](../Table%20Buffering#readme),
[Null Values](../Null%20Values#readme).

