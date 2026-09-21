# Dynamic SQL Tokens — initial means ALL, and the header-line rule flips

Almost every clause of an ABAP SQL statement can be replaced by a parenthesised
data object holding the clause as text: `SELECT (column_syntax) FROM (source_syntax)
WHERE (cond_syntax) ORDER BY (column_syntax)`. It is how generic downloaders,
selection-screen-driven reports and table-display utilities get written.

The syntax check moves to runtime, which everyone expects. What is less expected is
that three of these tokens treat an **initial** value as a wildcard rather than an
error, and that two tokens with near-identical documentation read an internal table
**differently**.

## Trap 1: an initial token is not an error — it is "everything"

`(cond_syntax)`:

> "The data object `cond_syntax` [...] is initial when the statement is executed.
> [...] If `cond_syntax` is initial when the statement is executed, the relational
> expression is true."
> — [sql_cond - (cond_syntax)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENWHERE_LOGEXP_DYNAMIC.html)

`(column_syntax)`:

> "If `column_syntax` is initial when the statement is executed, `select_list` is set
> implicitly to `*` and all columns are read."
> — [SELECT, select_list](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_LIST.html)

So the failure mode of "I built the filter and it came out empty" is a **full table
read**, not a short dump and not an empty result set:

```abap
" Build a WHERE condition from whatever the caller restricted on.
DATA lv_where TYPE string.

IF iv_carrid IS NOT INITIAL.
  lv_where = |carrid = { cl_abap_dyn_prg=>quote( iv_carrid ) }|.
ENDIF.
" ... no ELSE. iv_carrid was blank, so lv_where stays initial.

SELECT * FROM sflight
  WHERE (lv_where)          " <- reads EVERY row of SFLIGHT
  INTO TABLE @DATA(lt_flights).
```

Both halves can fail at once. A generic "export this table" utility that builds an
empty column list *and* an empty WHERE degrades to `SELECT * FROM dbtab` with no
restriction — on a production document table that is the read that brings the work
process down, and nothing in the code looks wrong.

This is the same shape as the [initial ranges table that matches
everything](../Selection%20Tables#readme) and needs the same explicit guard:

```abap
IF lv_where IS INITIAL.
  " decide deliberately: no rows, or all rows?
  RETURN.
ENDIF.
```

Note the asymmetry: `(source_syntax)` after `FROM` has **no** initial rule. A blank
table name raises `CX_SY_DYNAMIC_OSQL_SYNTAX` — the one token of the three that fails
loudly.

## Trap 2: the header-line rule is inverted between FROM and WHERE

All these tokens accept "a character-like data object or a standard table with a
character-like line type". If that internal table has a header line, the two clauses
disagree about which one they read.

`(source_syntax)` after `FROM`:

> "If `source_syntax` is an internal table with a header line, the **header line** and
> not the table body is evaluated."
> — [SELECT, FROM](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPFROM_CLAUSE.html)

`(cond_syntax)` after `WHERE`:

> "If `cond_syntax` is an internal table with a header line, the **table body** is
> evaluated, and not the header line."
> — [sql_cond - (cond_syntax)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENWHERE_LOGEXP_DYNAMIC.html)

`(column_syntax)` follows the `WHERE` rule — table body — per the `select_list` doc.

So `FROM` is the odd one out. In legacy code (header lines come from `OCCURS` tables
and classic `TABLES` work areas, which is exactly where this style of dynamic SQL
lives), one token reads the work area and the next reads the rows. Feeding the same
header-line table to both produces a statement half-built from the header and half
from the body.

There is no fix to apply here beyond knowing it — use tables without header lines
(`TYPE STANDARD TABLE OF string`) and the question never arises.

## Trap 3: SELECT SINGLE loses its single-row-ness

> "If columns are specified dynamically without the addition `SINGLE`, the result set
> is always regarded as having multiple rows."
> — [SELECT, select_list](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_LIST.html)

Static `SELECT col1, col2 ... INTO @ls_wa` with a fully-qualified key is a single-row
read. Replace the list with `(column_syntax)` and drop `SINGLE`, and the same
statement is now a multirow query — so the `INTO` target must be a table, and a
structure target is a syntax error rather than "the first row". Converting a
hard-coded read to a dynamic one is therefore not a drop-in change.

## Trap 4: `"` and `*` are comment characters inside the token

This one has no static equivalent at all — these are *runtime* comment rules applied
to the token's content:

> "In a dynamic token specified as a character-like data object, all content is
> ignored from the first comment character `"`. In a dynamic token specified as an
> internal table, all rows are ignored that start with the comment character `*`. In
> the row, all content is ignored from the first comment character `"`."
> — [SELECT, FROM](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPFROM_CLAUSE.html)

A double quote arriving in user input therefore does not corrupt the statement — it
**truncates** it. Everything after it silently disappears:

```abap
" User typed:  LH" or the value came from a text field containing a quote
DATA(lv_where) = |carrid = '{ iv_input }' AND connid = '0400'|.
" Token content: carrid = 'LH" and connid = '0400'
" Everything from the " onwards is comment -> the statement executed is
"   ... WHERE carrid = 'LH
" which is an unterminated literal -> CX_SY_DYNAMIC_OSQL_SYNTAX, or worse,
" a syntactically valid but much broader condition.
```

Comment characters *inside* a literal are part of the literal, so the danger is only
for quotes that escape their literal — which is precisely the SQL injection case
below.

## Trap 5: catching the wrong exception class

Dynamic tokens raise `CX_SY_DYNAMIC_OSQL_ERROR`, which has two subclasses:

```
CX_SY_OPEN_SQL_DB
 |--CX_SY_DYNAMIC_OSQL_ERROR
     |--CX_SY_DYNAMIC_OSQL_SEMANTICS
     |--CX_SY_DYNAMIC_OSQL_SYNTAX
```

`CX_SY_DYNAMIC_OSQL_SYNTAX` is the one everybody catches, because it is the one that
fires while you are developing (malformed text). `CX_SY_DYNAMIC_OSQL_SEMANTICS` is
the one that fires in production: the text parses fine but names a column that does
not exist on this system, or a table the statement may not read. A `CATCH
cx_sy_dynamic_osql_syntax` handler does not catch it, and the program dumps with
`SAPSQL_PARSE_ERROR`.

Catch the common superclass:

```abap
TRY.
    SELECT (lv_columns) FROM (lv_table) WHERE (lv_where)
      INTO CORRESPONDING FIELDS OF TABLE @<lt_data>.
  CATCH cx_sy_dynamic_osql_error INTO DATA(lx_sql).
    MESSAGE lx_sql->get_text( ) TYPE 'I'.
ENDTRY.
```

Two more documented notes: a dynamically specified **subquery** is checked in
[strict mode](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_STRICTMODE_740_SP08.html),
which is stricter than the regular check — so a subquery that compiles statically can
raise at runtime once moved into a token. And in dynamic tokens, static attributes or
constants of a class cannot be accessed from outside if that class has a static
constructor that has not yet run.

## Trap 6: `cond_syntax` is read once, not per row

> "If a dynamic SQL condition `(cond_syntax)` is used for a read, the content of
> `cond_syntax` is evaluated once for each query. Any changes made to the content of
> `cond_syntax` in a `SELECT` loop or `WITH` loop are ignored by the relational
> expression."
> — [sql_cond - (cond_syntax)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENWHERE_LOGEXP_DYNAMIC.html)

Rewriting the condition variable inside a `SELECT ... ENDSELECT` loop changes nothing
about which rows come back. The loop keeps running the condition it was opened with.

Also: **host expressions are not allowed** in dynamic logical expressions. `@( ... )`
inside a token does not compile at runtime, so any value must either be concatenated
in as a literal (the injection risk) or referenced by host *variable*.

## The injection fix: name the variable, do not paste the value

The doc's own preference, stated as a hint:

> "In a dynamic token, it is more secure to specify the name of an ABAP data object as
> an operand, instead of entering a value as a literal."
> — [SQL Injections Using Dynamic Tokens in ABAP SQL](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_INJ_DYN_TOKENS_SCRTY.html)

```abap
" Insecure if `input` comes from outside and is unchecked:
DATA(sql_cond1) = `CARRID = '` && input && `'`.

" Secure without any escaping - the token names the host variable:
DATA(sql_cond2) = `CARRID = @input`.

SELECT SINGLE * FROM scarr WHERE (sql_cond2) INTO @wa.
```

The second form needs no `quote( )` at all, because the value never becomes part of
the statement text. Prefer it whenever the *column* is dynamic but the *value* is not.

When the value genuinely must be concatenated, `CL_ABAP_DYN_PRG=>QUOTE` both escapes
and adds the delimiting quotation marks. The doc works through the attack: with
`CARRID` in `column` and `LH' OR CARRID <> 'LH` in `value`, the unescaped condition is
`CARRID = 'LH' OR CARRID <> 'LH'` — always true. After `QUOTE`, it becomes
`CARRID = 'LH'' OR CARRID <> ''LH'`, a comparison against one long literal, always
false.

### CL_ABAP_DYN_PRG — the methods worth knowing

All are static, all `RETURNING` (so they are usable inline), and the check methods
return the validated value rather than a flag:

| Method | Importing | Returns / raises |
|---|---|---|
| `quote` | `val TYPE csequence` | `out TYPE string` — escapes `'` and wraps in `'...'` |
| `quote_str` | `val` | as `quote`, for backtick/string literals |
| `escape_quotes` | `val` | escapes only, no wrapping |
| `check_column_name` | `val`, `strict` (opt.) | `val_str`; raises `CX_ABAP_INVALID_NAME` |
| `check_whitelist_tab` | `val`, `whitelist TYPE string_hashed_table` | `val_str`; raises `CX_ABAP_NOT_IN_WHITELIST` |
| `check_whitelist_str` | `val`, `whitelist TYPE csequence` | as above, comma-separated list form |
| `check_table_name_str` | `val`, `packages TYPE csequence`, `incl_sub_packages` (opt.) | `val_str`; raises `CX_ABAP_NOT_A_TABLE`, `CX_ABAP_NOT_IN_PACKAGE` |
| `mass_check_whitelist_tab` | `values TYPE string_table`, `whitelist` | `values_ret` — validates a whole column list in one call |

`check_column_name` validates *shape*, not existence — it rejects
`CARRID <> value OR CARRID` because that is not a valid name, which is exactly the
injection the doc warns about for a dynamic column. It does **not** confirm the column
exists on the table, so a wrong-but-well-formed name still reaches the database and
comes back as `CX_SY_DYNAMIC_OSQL_SEMANTICS`.

For a fixed set of allowed columns, the allow-list is stronger than a name check:

```abap
TRY.
    column = cl_abap_dyn_prg=>check_whitelist_tab(
               val       = to_upper( column )
               whitelist = VALUE string_hashed_table( ( `CITYFROM` ) ( `CITYTO` ) ) ).
  CATCH cx_abap_not_in_whitelist.
    MESSAGE 'Not allowed' TYPE 'E'.
ENDTRY.
```

Note `to_upper( )`: the allow-list comparison is case-sensitive even though the
**token syntax itself is not** ("The syntax in `cond_syntax` is not case-sensitive as
in the static syntax"). Skipping the upper-casing rejects the lower-case input that
the SQL statement would have accepted perfectly well.

For a dynamic table name, `check_table_name_str` restricted to a package is the
documented pattern — it rejects nonexistent tables *and* tables outside the packages
you nominate, which is the only practical defence against a user typing `USR02`.

## Fully dynamic statements

`WITH` and `OPEN CURSOR` accept **all** clauses except `INTO` in a single token. That
maximises the injection surface in one place, and the security doc's guidance is to
keep the externally-sourced share of that token as small as possible, checking each
part as above.

## Quick reference

| Token | Position | Initial value means | Header-line table reads |
|---|---|---|---|
| `(column_syntax)` | `SELECT` list | `*` — all columns | table body |
| `(source_syntax)` | `FROM` | *(no rule — raises)* | **header line** |
| `(cond_syntax)` | `WHERE`, `HAVING`, `ON` | condition is **true** | table body |
| `(column_syntax)` | `ORDER BY`, `GROUP BY` | *(no rule)* | table body |

- Guard every dynamic token for `IS INITIAL` before the statement, not after.
- Catch `CX_SY_DYNAMIC_OSQL_ERROR`, not just `...SYNTAX`.
- Prefer `@host_variable` inside the token over a concatenated literal.
- Validate names with `CL_ABAP_DYN_PRG`; upper-case before comparing to an allow-list.

## Sources

- [SELECT, select_list — `(column_syntax)`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_LIST.html)
- [SELECT, FROM — `(source_syntax)`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPFROM_CLAUSE.html)
- [sql_cond — `(cond_syntax)`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENWHERE_LOGEXP_DYNAMIC.html)
- [SELECT, ORDER BY — `ORDER BY (column_syntax)`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPORDERBY_CLAUSE.html)
- [SQL Injections Using Dynamic Tokens in ABAP SQL](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_INJ_DYN_TOKENS_SCRTY.html)
- [CL_ABAP_DYN_PRG signatures (abapedia)](https://abapedia.org/steampunk-2111-api/cl_abap_dyn_prg.clas.html)

See also: [Selection Tables & Ranges](../Selection%20Tables#readme) for the initial
ranges table, [Mass Data Processing](../Mass%20Data%20Processing#readme) for
`OPEN CURSOR`, and [Runtime Type Services](../Runtime%20Type%20Services#readme) for
building the `INTO` target of a dynamic read.
