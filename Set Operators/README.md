# Set Operators in ABAP SQL — `UNION`, `INTERSECT`, `EXCEPT` and the duplicate rules

`UNION`, `INTERSECT` and `EXCEPT` merge the result sets of several queries into one.
They look like the SQL you already know, and most of them behave that way. The parts
that do not are all about **duplicates**, and none of them produce a syntax error:

- a `UNION DISTINCT` later in the chain **retroactively deletes** the duplicates an
  earlier `UNION ALL` was written to keep;
- `INTERSECT` and `EXCEPT` have **no `ALL` variant at all**, so they silently
  deduplicate the left-hand result set;
- column **names** are taken from the leftmost query when they disagree — invisibly,
  unless you used `CORRESPONDING` or an inline declaration, which then makes the same
  mismatch a hard error.

```abap
SELECT FROM scarr  FIELDS carrid WHERE carrid = 'LH'
  UNION
SELECT FROM sflight FIELDS carrid WHERE carrid = 'AA'
  ORDER BY carrid
  INTO TABLE @DATA(lt_carriers).
```

The queries are **evaluated from left to right**, and parentheses are the only way to
change that grouping. That single sentence is the root of the headline trap.

## Trap 1: `DISTINCT` reaches backwards over a previous `UNION ALL`

The additions control duplicates, and `DISTINCT` is the default. What is easy to miss
is the *scope* it applies to:

> "The default behavior or the addition `DISTINCT` is always applied to the entire
> existing result set of the left side. The addition `DISTINCT` also removes any
> duplicate rows produced by the addition `ALL` of preceding `UNION` additions."
> — [ABAP keyword documentation, `UNION, INTERSECT, EXCEPT`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPUNION.html)

So `ALL` is not a property of the branch it is written on. It is a property of one
merge step, and a later `DISTINCT` step undoes it:

```abap
"{ LH } UNION ALL { LH }  ->  { LH, LH }
"       UNION DISTINCT { AA }  ->  insert, then dedupe the WHOLE set  ->  { LH, AA }
SELECT FROM scarr FIELDS carrid WHERE carrid = 'LH'
  UNION ALL
SELECT FROM scarr FIELDS carrid WHERE carrid = 'LH'
  UNION DISTINCT
SELECT FROM scarr FIELDS carrid WHERE carrid = 'AA'
  INTO TABLE @DATA(lt_two).      "2 rows - the deliberate duplicate is gone
```

```abap
"Same three queries, one pair of parentheses: the ALL step now happens LAST.
SELECT FROM scarr FIELDS carrid WHERE carrid = 'LH'
  UNION ALL
( SELECT FROM scarr FIELDS carrid WHERE carrid = 'LH'
    UNION DISTINCT
  SELECT FROM scarr FIELDS carrid WHERE carrid = 'AA' )
  INTO TABLE @DATA(lt_three).    "3 rows - the duplicate survives
```

Two consequences for real code, both silent:

- **Appending a branch to an existing statement can change the rows the earlier
  branches contributed.** Adding a plain `UNION` (which means `UNION DISTINCT`) at the
  bottom of a working five-branch statement collapses every duplicate above it.
- **Reordering equal-looking branches changes the answer.** There is nothing in a diff
  that flags it, and a test over data that happens to have no duplicates passes either
  way.

If a branch must contribute duplicates, parenthesise the `DISTINCT` steps so they
cannot see it — the documentation makes the same point:

> "Prioritizations using parentheses are particularly applicable when handling
> duplicate rows using `DISTINCT`."

## Trap 2: `INTERSECT` and `EXCEPT` cannot keep duplicates

`ALL` is available for `UNION` only:

| Operator | `ALL` | `DISTINCT` | Result |
|---|---|---|---|
| `UNION` | yes | yes (default) | rows of the right query inserted into the left result set |
| `INTERSECT` | **no** | yes (default) | **distinct** rows of the left result set that also exist on the right |
| `EXCEPT` | **no** | yes (default) | **distinct** rows of the left result set that do not exist on the right |

The word *distinct* is in the definition of both operators, not an option on them. So
an `EXCEPT` used purely as a filter also deduplicates the thing it is filtering:

```abap
"SPFLI holds many rows per carrid. The left side is NOT preserved row-for-row.
SELECT FROM spfli FIELDS carrid WHERE carrid = 'LH'
  EXCEPT
SELECT FROM scarr FIELDS carrid WHERE carrid = 'AA'
  INTO TABLE @DATA(lt_left).     "1 row, not the N rows LH has in SPFLI
```

This is the failure mode to watch for when `EXCEPT` replaces a `NOT EXISTS` subquery
or a `FOR ALL ENTRIES`-plus-`DELETE` pattern during a "tidy this up" refactor: the new
statement is shorter, reads better, and quietly returns fewer rows. `NOT EXISTS` keeps
the left rows; `EXCEPT` does not.

`MINUS` is not an alternative spelling here:

> "ABAP SQL does not support the alternative syntax `MINUS` that is available for the
> SAP HANA database."

## Trap 3: type alignment is asymmetric, and `NUMC` is the strict one

All branches must have the same number of columns, and columns matched to each other
must agree on built-in type, length and decimals — with a set of documented
exceptions that are worth knowing precisely, because they decide whether a change
activates:

| Category | Lengths may differ? | Resulting column |
|---|---|---|
| `INT1` / `INT2` / `INT4` / `INT8` | yes, may be mixed | the type with the greatest value range |
| `DEC` (and `CURR`, `QUAN`) | yes, **but decimals must match** | the type with the greatest length |
| `DF16_DEC` / `DF34_DEC` | as stored, decimals must match | as for `DEC` |
| `CHAR` (and `CLNT`, `LANG`, `CUKY`, `UNIT`) | yes | the type with the greatest length |
| `NUMC`, `RAW` | **no — must match exactly** | — |
| string types | cannot be combined across categories | — |

The practical asymmetry: **widening a `CHAR` field in the DDIC leaves every `UNION`
compiling, widening a `NUMC` field breaks all of them.** A `CHAR(10)`/`CHAR(20)` pair
silently produces a `CHAR(20)` column, so the branch with the shorter field is now
padded — fine for display, not fine if something downstream compares the raw column.

`NUMC` also cannot be unioned with a character literal, which is why the
documentation's own union example has to cast:

```abap
SELECT FROM scarr
  FIELDS carrname,
         CAST( '-' AS CHAR( 4 ) ) AS connid,   "literal widened to match
         '-' AS cityfrom
  WHERE carrid = 'LH'
  UNION
SELECT FROM spfli
  FIELDS '-' AS carrname,
         CAST( connid AS CHAR( 4 ) ) AS connid, "NUMC(4) -> CHAR(4)
         cityfrom
  WHERE carrid = 'LH'
  ORDER BY carrname DESCENDING, connid
  INTO TABLE @DATA(lt_mixed).
```

`*` and `data_source~*` are **not allowed** in the select list of a set operation —
every branch has to name its columns. That is a feature: a `SELECT *` would otherwise
break the statement every time either table gained a field.

## Trap 4: column names come from the left, except when that becomes an error

> "If the column names of the result sets are not identical, the column names are used
> from the result set of the `SELECT` statement on the left of `UNION`, `INTERSECT`, or
> `EXCEPT`. In this type of case, the names are usually not visible, except for
> subqueries in the `WITH` statement."

So a name mismatch is normally invisible — the merged set just uses the leftmost
branch's names. But:

> "If the addition `CORRESPONDING` or an inline declaration `@DATA|@FINAL(...)` is used
> in the `INTO` clause, the column names of all result sets defined in the
> `query_clauses` from left to right must match."

The two most convenient `INTO` forms are exactly the two that promote the mismatch to
a syntax error. Practical reading: align the names with `AS` aliases in every branch
from the start, and the statement keeps working whichever `INTO` form it later grows.
Inside a `WITH` definition the names *are* visible to the main query, so there they
matter regardless.

## Restrictions that only bite at the call site

| Not allowed | Note |
|---|---|
| `SINGLE` | the merged result set is always multirow |
| `UP TO n ROWS`, `OFFSET o` | "not currently allowed with `UNION`, `INTERSECT`, and `EXCEPT`" |
| `ORDER BY` on an individual branch | one `ORDER BY` applies to the merged result of the main query |
| `ORDER BY PRIMARY KEY` | explicitly excluded |
| `ORDER BY col` where `col` is missing from a branch | must exist **with the same name in every** branch, and cannot be written with `~` |
| `FOR ALL ENTRIES` in any branch's `WHERE` | excluded outright |

Two more that change how the statement performs rather than whether it compiles:

> "`UNION`, `INTERSECT`, or `EXCEPT` cannot be processed by the ABAP SQL in-memory
> engine. The ABAP SQL statement bypasses the table buffer and an internal table
> accessed by `FROM @itab` must be transported to the database. This is only possible
> for **one internal table per ABAP SQL statement**."

So adding a `UNION` to a statement reading a fully buffered table **turns every
execution into a database round trip** — the same bypass the
[Table Buffering](../Table%20Buffering#readme) note catalogues, reached here by a
change that looks purely functional. And `FROM @itab` is usable in at most one branch
of the whole statement, which rules out the obvious "union two internal tables in the
database" shape.

Finally, the branch count has no fixed ABAP limit but a real database one, and it
fails late:

> "The maximum number of different `SELECT` statements that can be joined using
> `UNION`, `INTERSECT`, or `EXCEPT` depends on the database system. If this number is
> exceeded, an exception is raised when the program is executed."

A generated set operation (one branch per company code, per plant, per whatever)
therefore has a ceiling that can differ between the sandbox and production.

## Strict mode: `INTO` and `OPTIONS` go at the very end

All three operators put the statement into a stricter syntax check than a plain
`SELECT`:

> "When `UNION` is used, the syntax check is performed in a strict mode, which handles
> the statement more strictly than the regular syntax check. More specifically, the
> `INTO` clause and the additions `OPTIONS` must be specified at the end of the entire
> `SELECT` statement."

The habit of writing `INTO TABLE @DATA(...)` straight after the `FIELDS` list — legal
and common in a single-table `SELECT` — stops compiling the moment a `UNION` is added
below it. The `INTO` belongs after the last branch and after `ORDER BY`; `OPTIONS`
comes after the `INTO`.

Also worth knowing before assuming a set operation is a drop-in replacement for a
loop: **each branch has its own client handling**, and `USING` (or the obsolete
`CLIENT SPECIFIED`) in one branch's `FROM` clause "only affects the `SELECT` statement
for which it is specified". Cross-client and single-client branches can therefore sit
in one statement, each correct on its own terms — see
[CDS Client Handling](../CDS%20Client%20Handling#readme) for what that implies.

If there is no `INTO ... TABLE`, the merged result set still being multirow means a
loop is opened, to be closed with `ENDSELECT` or `ENDWITH`.

## The `WITH` wrapper: one `WHERE` for all branches

The documentation's own argument for putting a union inside a common table expression
is a good pattern to have ready: the branches cannot share a `WHERE` condition, so
filtering the merged set means repeating that condition in every branch — or building
the union in a CTE and filtering once in the main query.

```abap
WITH +aggregates AS (
  SELECT FROM sflight
    FIELDS carrid, connid, 'MAX' AS agg_kind,
           MAX( CAST( seatsocc AS DEC( 31,2 ) ) ) AS agg
    GROUP BY carrid, connid
  UNION
  SELECT FROM sflight
    FIELDS carrid, connid, 'MIN' AS agg_kind,
           MIN( CAST( seatsocc AS DEC( 31,2 ) ) ) AS agg
    GROUP BY carrid, connid )
SELECT * FROM +aggregates
  WHERE carrid = 'LH' AND connid = '0400'   "written once, not per branch
  INTO TABLE @DATA(lt_agg).
```

This is also the place where the leftmost-branch naming rule becomes visible: the CTE
exposes those names to the main query, so the `AS` aliases are load-bearing here in a
way they are not in a standalone union. See
[Window Expressions](../Window%20Expressions#readme) for the other common reason to
reach for `WITH +cte`.

## References

- [`UNION`, `INTERSECT`, `EXCEPT` — operators, `ALL`/`DISTINCT` and the duplicate rules](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPUNION.html)
- [`query_clauses` — select list, type alignment and per-branch restrictions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPUNION_CLAUSE.html)
- [`UNION` — examples](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/abenunion_abexas.html)
- [`WITH` — common table expressions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWITH.html)
- [`SELECT` — overview](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT.html)

See `ydj_set_operators_demo.abap` in this folder for a runnable version of all of the
above against the flight data model.
