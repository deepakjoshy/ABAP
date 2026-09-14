# Selection Tables & Ranges — empty means ALL, and I/E is set arithmetic

A ranges table is an internal table with the four columns `SIGN`, `OPTION`, `LOW`,
`HIGH`. `SELECT-OPTIONS` declares one for a selection screen; `TYPE RANGE OF`
declares one in code. `col IN range_tab` expands the table into a combination of
comparison expressions — one per row.

Almost every report in an SAP system filters on one. The expansion rules are fully
documented and produce results most code does not expect.

## Trap 1: an initial ranges table matches everything

> "If the ranges table is initial, the comparison expression is always true."
> — [rel_exp - Tabular Comparison Operator IN](https://help.sap.com/docs/abap-cloud/abap-keyword/rel-exp-tabular-comparison-operator-in)

> "If the ranges table is initial, the expression `IN range_tab` is always true. This
> overrides the general rule that the result of a relational expression is unknown if
> an operand has the null value."
> — [sql_cond - IN range_tab](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abenwhere_logexp_seltab.htm)

Empty is *not* "no filter matched" and it is not `FALSE`. It is **no restriction**.
The user who leaves the selection screen field blank gets every row:

```abap
SELECT-OPTIONS s_werks FOR mard-werks.   " left blank on the screen

SELECT matnr, werks, labst FROM mard
  WHERE werks IN @s_werks                " <- reads ALL plants
  INTO TABLE @DATA(lt_stock).
```

That is usually the *intended* behaviour of a report selection screen, which is why
it is easy to forget when a range is built in code rather than by a user:

```abap
" Build a range from an authorization check / customizing / a prior SELECT.
LOOP AT lt_allowed_plants INTO DATA(ls_plant).
  APPEND VALUE #( sign = 'I' option = 'EQ' low = ls_plant-werks ) TO lr_werks.
ENDLOOP.

" lt_allowed_plants was empty -> lr_werks is empty -> this reads EVERY plant,
" i.e. "no plants authorised" silently becomes "all plants".
SELECT ... WHERE werks IN @lr_werks ...
```

This is the same shape as the [FOR ALL ENTRIES empty-driver
trap](../For%20All%20Entries#readme) and needs the same explicit guard:

```abap
IF lr_werks IS INITIAL.
  " decide deliberately: no data, or all data?
  RETURN.
ENDIF.
```

The doc adds the SQL-side consequence directly: *"If no conditions are specified apart
from `IN range_tab`, all rows of the data source are selected if the ranges table is
initial."*

## Trap 2: `E` rows alone do not exclude — they select everything else

The expansion is set arithmetic, not a row-by-row filter. From the same doc:

1. All rows with `sign = 'I'` are combined with `OR`. If there are no `E` rows, that
   is the whole expression.
2. All rows with `sign = 'E'` are combined with `OR`, then negated with `NOT`. If
   there are no `I` rows, **that** is the whole expression.
3. If both signs are present, the two expressions are combined with `AND`.

So a range containing *only* exclusions is not "select nothing" — it is "select
everything except":

| Range content | Effective condition |
|---|---|
| *(empty)* | true — all rows |
| `I EQ 1000` | `col = '1000'` |
| `E EQ 1000` | `col <> '1000'` — **all other rows**, not zero rows |
| `I EQ 1000` + `E EQ 1000` | `( col = '1000' ) AND col <> '1000'` — nothing |
| `I BT 1000 1999` + `E EQ 1500` | `( col BETWEEN '1000' AND '1999' ) AND col <> '1500'` |

The mental model the doc gives: `I` rows build an inclusive set, `E` rows build an
exclusive set, and the result is *inclusive minus exclusive*. With no inclusive rows,
the inclusive set is "everything".

Worked example straight from the keyword documentation:

```
SIGN  OPTION  LOW              HIGH
---------------------------------------
I     EQ      01104711
I     BT      10000000         19999999
I     GE      90000000
E     EQ      10000911
E     BT      10000810         10000815
E     CP      1%2##3#+4++5*
```

expands to

```abap
... ( ID = '01104711'                      OR
      ID BETWEEN '10000000' AND '19999999' OR
      ID >= '90000000' )                     AND
    ID <> '10000911'                         AND
    ID NOT BETWEEN '10000810' AND '10000815' AND
    ID NOT LIKE '1#%2##3+4__5%' ESCAPE '#'   ...
```

Row order is irrelevant — only the sign matters.

## Trap 3: the same range gives different results in SQL and in ABAP

`CP`/`NP` rows are the one place where `col IN r` in a `SELECT` and `col IN r` in a
`LOOP ... WHERE` genuinely disagree.

- In an **ABAP comparison expression**, `CP` is the ordinary [character pattern
  operator](../Character%20Comparisons#readme): wildcards `*` and `+`, escape `#`,
  and it **ignores case**.
- In **ABAP SQL**, the row is transformed into a `LIKE ... ESCAPE '#'` condition, and:

> "`LIKE` conditions resulting from `CP` or `NP` are case-sensitive, which is not the
> case in ABAP comparison expressions."
> — same source

```abap
DATA lr_name TYPE RANGE OF char20.
lr_name = VALUE #( ( sign = 'I' option = 'CP' low = 'ab*' ) ).

" Database filtering: case-SENSITIVE LIKE 'ab%'  -> 'ABC' does NOT match
SELECT ... WHERE name IN @lr_name ...

" In-memory filtering: case-INSENSITIVE CP      -> 'ABC' DOES match
LOOP AT lt_all INTO DATA(ls) WHERE name IN lr_name.
```

Pushing a filter down into the `SELECT` "for performance" can therefore change which
rows come back — only for `CP`/`NP` rows, only for mixed-case data, which is exactly
the combination that survives a developer test on uppercase-only master data.

The pattern translation SQL applies (documented, not folklore):

- `%` and `_` occurring in the `CP` pattern get `#` inserted in front of them.
- `*` and `+` not already escaped with `#` become `%` and `_`.
- `#` characters that escape neither themselves nor `%`/`_` are removed.

One more `CP` detail on the ABAP side: the pattern is `range_tab-low && range_tab-high`
— the two columns are **concatenated**. A leftover value in `HIGH` from an earlier row
or a careless `MOVE-CORRESPONDING` silently extends the pattern.

## Trap 4: the failure modes are uncatchable or unexpected

**Invalid `SIGN`/`OPTION` dumps, and you cannot catch it.**

> "If the ranges table contains invalid values, an uncatchable exception is raised."

Valid `OPTION` values are `EQ NE GE GT LE LT CP NP` when `HIGH` is initial, and
`BT NB` when `HIGH` is filled; `SIGN` is `I` or `E`. Anything else — lowercase `'i'`,
a blank `OPTION` from a half-filled `VALUE #( )`, `OPTION = 'EQ'` with `HIGH` still
populated — is a runtime termination, not a `sy-subrc`. Ranges assembled from external
input (RFC, OData, a spreadsheet upload) must be validated before use.

**Too many rows raises a catchable DB exception.**

> "The conditions specified in the ranges table are passed by the database interface
> to the database as SQL statement input values. The maximum number of input values
> depends on the database system and is usually between 2000 and 10000. If the maximum
> number is exceeded an exception of the class `CX_SY_OPEN_SQL_DB` is raised."

So the common "build a range from an internal table of keys" idiom has a hard ceiling
that varies by database — a job that works on the dev HANA can fail in production.
Past a few thousand entries, use `FOR ALL ENTRIES` or a subquery instead.

**Type mismatches are a syntax-check error, not a conversion.** `LOW`/`HIGH` must
match the operand type under the rules for lossless assignments; this is enforced by
the strict syntax check from 7.40 SP08 and can raise an exception.

## `SELECT-OPTIONS` specifics worth knowing

**It has a header line.** *"The statement declares a selection table in the program
with the name `selcrit`. A selection table is an internal standard table with header
line and standard key."* — [SELECT-OPTIONS](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapselect-options.htm).
A table declared with `TYPE RANGE OF` does not. Two consequences:

- `s_matnr-low` compiles for a `SELECT-OPTIONS` table (it addresses the header line)
  and is a syntax error for a `TYPE RANGE OF` one.
- **`IF s_matnr IS INITIAL` tests the header line, not the table.** The bare name of a
  table with a header line refers to the header line in an operand position. To ask
  "did the user enter anything?" the body must be addressed explicitly:

```abap
IF s_matnr[] IS INITIAL.       " correct - is the selection table empty?
IF s_matnr   IS INITIAL.       " wrong  - is the HEADER LINE empty?
```

Those two differ whenever `DEFAULT` filled the header line, or when earlier code wrote
to it. `IN` itself always evaluates the body, so the condition and the check can
disagree.

**`DEFAULT` fills the header line only.** *"Only the header line in the selection
table is filled with these values, which does not affect the selection criterion"*,
and *"If the selection table is not initial when the transfer takes place, the start
values are not transferred to the first line."* A default that a prior `INITIALIZATION`
block already populated is silently dropped.

```abap
SELECT-OPTIONS s_budat FOR bkpf-budat DEFAULT '20260101' TO '20261231'.
" OPTION defaults to BT here (EQ without TO), SIGN defaults to I.
```

With `OPTION cp` or `np`, the default value **must** contain a `*` or `+` or the
program terminates when the value is passed.

**`OBLIGATORY` is weaker than it looks.** It only forces the first input field to be
non-empty. It does not stop the user entering an `E`-only multiple selection, and it
does nothing for a range filled programmatically. To actually forbid exclusions, the
doc points at function module `SELECT_OPTIONS_RESTRICT`, which can restrict the
offered selection options and prohibit `sign = 'E'` before the screen is sent.

**Screen input is uppercased unless you say otherwise.** `LOWER CASE` *"prevents the
content of character-like fields from being converted to uppercase letters when the
data is transported from the input fields on the selection screen to the selection
table."* Without it, a range over a mixed-case field (descriptions, email, external
IDs) silently matches nothing — and combined with Trap 3, the `CP` case-sensitivity in
SQL makes this worse.

**`NO-DISPLAY` changes the typing rules.** No screen element is generated, `LOW`/`HIGH`
may then have *any flat data type*, and the 45-character limit that applies to fields
with an input field is lifted. Such a criterion can only be filled via `SUBMIT ... WITH`.

## Useful, non-obvious idioms

Fill a range directly from a `SELECT` — the columns are just aliases:

```abap
DATA lr_carrid TYPE RANGE OF scarr-carrid.

SELECT 'I' AS sign, 'EQ' AS option, carrid AS low
  FROM scarr
  INTO TABLE @lr_carrid.
```

Use a range as a reusable in-memory predicate — `IN` works anywhere a logical
expression does, including `COND`, `LOOP ... WHERE`, `DELETE ... WHERE`:

```abap
IF to_upper( lv_carrid ) IN lr_carrid.
```

Note the explicit `to_upper( )` in the doc's own example: it is there precisely
because the *data* may be mixed case, not because `CP` is case-sensitive.

Build one inline with `VALUE`:

```abap
TYPES ty_carrid_range TYPE RANGE OF spfli-carrid.
DATA(lr_range) = VALUE ty_carrid_range(
                   ( sign = 'I' option = 'BT' low = 'AA' high = 'LH' ) ).
```

## Sources

- [rel_exp - Tabular Comparison Operator IN](https://help.sap.com/docs/abap-cloud/abap-keyword/rel-exp-tabular-comparison-operator-in) — I/E combination hierarchy, initial-table rule, `CP` low/high concatenation, uncatchable exception
- [sql_cond - IN range_tab](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abenwhere_logexp_seltab.htm) — `CP`/`NP` to `LIKE` transformation, case-sensitivity, input-value limit, worked expansion example
- [TYPES, RANGE OF](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abaptypes_ranges.htm) — line type, `DDSIGN`/`DDOPTION`, `SELECT` fill example
- [SELECT-OPTIONS](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapselect-options.htm) — header line, valid `OPTION` values
- [SELECT-OPTIONS, value_options](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapselect-options_value.htm) — `DEFAULT`, `OPTION`, `SIGN`, `LOWER CASE`
- [SELECT-OPTIONS, screen_options](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapselect-options_screen.htm) — `OBLIGATORY`, `NO-DISPLAY`, `NO-EXTENSION`, `SELECT_OPTIONS_RESTRICT`
- [SAP-samples/abap-cheat-sheets — 31_WHERE_Conditions.md](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/31_WHERE_Conditions.md)
