# Null Values in ABAP SQL — The Value ABAP Cannot Represent

A null value is a database concept that **has no ABAP counterpart**. It is not
zero, not `space`, not `IS INITIAL` — it is "no value at all". The keyword
documentation is explicit: *"Null values do not correspond to any content of data
objects in ABAP. Especially, a null value is not the same as a type-dependent
initial value."*

That gap is the whole problem. The moment a null value crosses from the database
into an ABAP variable it is **silently converted to the type-dependent initial
value**, and the information that it was null is gone. So the null survives only
inside the SQL statement — in the `WHERE`, `GROUP BY` and `ORDER BY` clauses,
where it behaves by three-valued logic that ABAP developers do not have day-to-day
instincts for.

No syntax error, no `sy-subrc`, no dump. Just wrong numbers.

---

## 1. An aggregate over zero rows returns a row, and `sy-subrc = 0` (the headline)

This is the single most common null bug in ABAP, and it does not look like a null
bug at all.

```abap
SELECT MAX( fldate ) AS max_date
  FROM sflight
  WHERE carrid = 'ZZ'          " matches nothing
  INTO @DATA(max_date).

IF sy-subrc = 0.
  " ... this branch IS taken.
  " max_date is '00000000'.
ENDIF.
```

The documented rule: *"If aggregate functions only are used without `GROUP BY`,
the results set also contains a row if no data is found in the database. [...] The
columns for the other aggregate functions contain initial values. This row is
assigned to the data object specified after `INTO` and, unless only `COUNT( * )` is
used, `sy-subrc` is set to 0 and `sy-dbcnt` is set to 1."*

So the database computed `MAX` over an empty set, correctly returned **null**, and
the transfer to ABAP turned that null into `'00000000'`. `sy-subrc = 0` is telling
the truth — a row *was* transferred — it just is not telling you what you assumed.

**The asymmetry that makes it worse.** `COUNT( * )` alone is the exception:

| `SELECT` list | rows found | `sy-subrc` | `sy-dbcnt` | value |
|---|---|---|---|---|
| `MAX( )` / `MIN( )` / `SUM( )` / `AVG( )` | none | **0** | 1 | initial |
| `MAX( )` / `MIN( )` / `SUM( )` / `AVG( )` | some | 0 | 1 | real result |
| `COUNT( * )` only | none | **4** | 0 | 0 |
| any aggregate **with** `GROUP BY` | none | **4** | 0 | — |

Three different behaviours for what feels like the same statement. Adding a
`GROUP BY` to an existing aggregate query flips `sy-subrc` from 0 to 4 on the
no-data case, which quietly changes the meaning of every `IF sy-subrc = 0` after it.

**How to check properly:** do not check `sy-subrc` after a bare aggregate. Either
add `COUNT( * )` to the same statement and test that, or use a null indicator
(section 4).

```abap
SELECT COUNT( * ) AS cnt, MAX( fldate ) AS max_date
  FROM sflight
  WHERE carrid = @carrid
  INTO @DATA(result).

IF result-cnt = 0.
  " genuinely no rows -- max_date is meaningless
ENDIF.
```

A second, quieter consequence: `SUM( )` over an empty set gives `0`, which is a
perfectly plausible total. A report that prints "Total: 0.00" when the real answer
is "nothing was selected" is this bug.

---

## 2. `IS NULL` is the only comparison that works on a null

Every other relational expression evaluates to **unknown** — not true, not false —
when an operand is null, and rows for which the `WHERE` condition is unknown are
not returned.

> *"The relational expression `IS [NOT] NULL` is the only expression for which the
> result is true or false when the operand contains the null value. The result is
> unknown for all other possible relational expressions."*

The practical consequence catches nearly everyone:

```abap
" Rows where cancel_flag is NULL are returned by NEITHER of these.
SELECT ... WHERE cancel_flag  = 'X' ...   " excluded (unknown)
SELECT ... WHERE cancel_flag <> 'X' ...   " ALSO excluded (unknown)
```

Two queries that look like exact complements do not partition the table. The rows
with nulls fall through the gap in both. To include them you must say so:

```abap
SELECT ... WHERE cancel_flag <> 'X' OR cancel_flag IS NULL ...
```

The same applies to `NOT IN` with a null in the list, and to negation generally:
`NOT ( unknown )` is still `unknown`, so wrapping the condition in `NOT` does not
recover the missing rows.

**`IS NULL` is not `IS INITIAL`.** They are separate relational expressions with
separate documentation pages, and the doc explicitly warns not to confuse them.
`IS INITIAL` tests for the type-dependent initial value of an actual stored value;
`IS NULL` tests for the absence of a value. On a column that stores a genuine
`space`, `IS INITIAL` is true and `IS NULL` is false.

`IS NULL` also accepts operand types that other comparisons reject — `STRING`,
`RAWSTRING` and `GEOM_EWKB` — which makes it the only way to test a LOB column.
`LCHR` and `LRAW` remain excluded.

---

## 3. Where nulls actually come from

You mostly do not create nulls; you inherit them. Per the documentation, reads
with `SELECT` can produce nulls from:

- **Outer joins** — the unmatched side is all nulls. The most common source by far.
- **Aggregate functions** — `MAX`/`MIN`/`SUM`/`AVG` over an empty set (section 1).
- **SQL expressions** — most often a `CASE` whose `WHEN` conditions are all false
  and which has **no `ELSE` branch**. This is the null generator hiding in
  ordinary-looking code:
  ```abap
  CASE WHEN seatsocc > 100 THEN 'FULL' END   " no ELSE -> null for every other row
  ```
  Always write an `ELSE`.
- **CDS entities** that contain any of the above constructs.

As stored table data, nulls occur in two situations:

- **A new column appended to an already-filled DDIC table.** Existing rows have no
  value for it. The ABAP Dictionary offers a *flag for initial values* when
  inserting new columns into existing tables, which writes the type-dependent
  initial value instead of leaving nulls — set it, and this class of null never
  appears.
- **Empty strings**, which *some* database platforms represent as null. Platform
  dependent, so code that must run on more than one DB should not rely on either
  behaviour.

On the write side ABAP protects you: *"ABAP SQL statements for write access
generally do not create null values"* — the exception being writes through a
**view that does not cover all columns** of the underlying table. Null in a key
field is impossible by principle and raises a database exception if attempted;
subqueries inserted with `INSERT`/`MODIFY` have their nulls converted to initial
values, or raise an exception for a key field.

`Native SQL` and `AMDP` are **not** an escape hatch — nulls passed back from them
to ABAP objects are converted to type-dependent initial values in exactly the same
way.

---

## 4. Null indicators — the only way to tell null from initial

If you genuinely need to distinguish "the database had no value" from "the database
had a zero", the `INDICATORS` addition of the `INTO` clause is the mechanism.

```abap
SELECT SINGLE
  FROM demo_expressions
  FIELDS num1 AS x,
         CASE WHEN num1 = 0 THEN 0 ELSE 1 END AS y,
         CASE WHEN num1 = 0 THEN 0 END        AS z   " no ELSE -> null
  INTO @DATA(wa) INDICATORS NULL STRUCTURE null_ind.

" wa-null_ind-z = '01' (hex 1) -> column z was null
" wa-null_ind-x, -y are initial -> those columns were not null
```

The rules worth knowing:

- After an **inline declaration**, the substructure `null_ind` is generated for you
  with one `x`-length-1 component per result column, same names, same order. The
  name you pick must not collide with a column name in the result set.
- After an **existing** work area, you declare the substructure yourself. Without
  `CORRESPONDING FIELDS` it must be the **last** component and is filled strictly
  **by position** — component names are ignored, so a mismatched declaration
  reports the wrong column with no error. With `CORRESPONDING FIELDS` it is matched
  **by name** and may sit anywhere, but must not share a name with a result column.
- Components must be type `x` or `c`, length 1. Value hex `1` / `'X'` means the
  column **was** null.
- The optional `NOT` inverts it (`INDICATORS NOT NULL STRUCTURE ...`): hex `1` then
  means the column was **not** null. Useful because it makes "no nulls at all"
  checkable in one expression — without `NOT` the whole indicator is initial when
  no column is null; with `NOT` the whole indicator is initial when *every* column
  is null.
- `TYPES ... WITH INDICATORS ind [AS BITFIELD]` declares such a structure without
  hand-writing it. `AS BITFIELD` condenses it to one bit per component in an `x`
  field (read it with `GET BIT`) — note that a bitfield **cannot** be used with the
  `UPDATE ... INDICATORS` set-indicator variant, only an actual indicator structure
  can.
- **Not every database supports `INDICATORS`.** Guard with
  `CL_ABAP_DBFEATURES=>USE_FEATURES( ... )` passing the constant `INDICATORS`.

Note that `WITH INDICATORS` creates one indicator per **first-level** component
regardless of its type — a substructure, table or reference component gets a single
indicator, not one per nested field.

---

## 5. `coalesce( )` — substitute a value instead

Usually you do not want to know a value was null, you want a sensible default.
`coalesce` returns the first argument that is not null:

```abap
SELECT p~carrid,
       coalesce( s~cityfrom, 'UNKNOWN' ) AS cityfrom
  FROM ...
```

Verified constraints:

- **2 to 255 arguments.** If *every* argument is null, the value of the **last**
  argument is returned — so the last argument should be your literal default, and
  if it too can be null the result is null.
- **A blank is required after the opening parenthesis and before the closing one.**
  `coalesce(a, b)` is a syntax error; `coalesce( a, b )` is correct. This applies
  to ABAP SQL functions generally and is a frequent first-attempt failure.
- **Not allowed for** `STRING`, `RAWSTRING`, `LCHR`, `LRAW`, `PREC`, `ACCP`,
  `GEOM_EWKB` and the obsolete `DF16_SCL`/`DF34_SCL`.
- Argument types must match or one must fully represent the others; the **result
  takes the dictionary type of the argument with the largest value range**. Worth
  checking when mixing a column with a literal — the result type may be wider than
  the column.
- **Maximum nesting depth is ten.**
- It is pure shorthand for a searched `CASE`:
  ```abap
  CASE WHEN exp1 IS NOT NULL THEN exp1
       WHEN exp2 IS NOT NULL THEN exp2
       ELSE expn END
  ```
- It **can** be processed by the ABAP SQL in-memory engine, so unlike many
  constructs it does not force a table-buffer bypass (see
  [Table Buffering](../Table%20Buffering#readme)).

Related: the date/time conversion functions take an `on_null` parameter for the
same purpose, and the `NULL` expression (`sql_null`) lets you produce a null
deliberately — it is context-typed, so an exact type must be derivable at the
operand position, usually via `CAST( NULL AS INT1 )`. Do not confuse the expression
`NULL` with the predicate `IS NULL`; and remember that because `NULL` *is* null by
definition, comparing anything to it always yields unknown.

---

## 6. The inconsistency: `GROUP BY`/`ORDER BY` keep nulls, `INTO` does not

This is the subtlety that makes null bugs hard to reason about. Nulls are converted
to initial values **when passed to data objects** — but they are handled **as null
values** in:

- the `GROUP BY` clause,
- the `ORDER BY` clause,
- the ABAP SQL **in-memory engine**, i.e. when accessing the **table buffer** or an
  internal table via `FROM @itab`.

So within one statement, nulls and initial values are distinct for grouping and
sorting, then collapse into the same value on arrival in ABAP. Two groups can come
back looking identical — one the null group, one the genuine-initial group — and a
`LOOP ... AT NEW` or a post-hoc `COLLECT` over that result will merge rows the
database deliberately kept apart.

Also note `ORDER BY`'s null position is database-dependent; ABAP SQL does not offer
`NULLS FIRST` / `NULLS LAST`.

---

## 7. How aggregates treat nulls (when rows *are* found)

Distinct from section 1, which is about zero rows:

- **Nulls are ignored in the calculation.** `AVG( col )` divides by the count of
  *non-null* values, not by the row count. So `AVG` ≠ `SUM / COUNT( * )` whenever
  the column has nulls — a classic cross-check failure between two reports.
- **The result is null only if every row in that column is null.**
- **`COUNT` counts rows and never produces null.** `COUNT( col )` counts non-null
  values of `col`, whereas `COUNT( * )` counts rows — they differ precisely by the
  number of nulls.

---

## Rules of thumb

1. Never test `sy-subrc` after a `SELECT` whose list is only aggregates. Select
   `COUNT( * )` alongside and test that.
2. Every `CASE` in a `SELECT` list gets an `ELSE`.
3. After a `LEFT OUTER JOIN`, assume every column from the right side is a null
   source, and wrap it in `coalesce( )` unless you have handled it.
4. `WHERE col <> x` does not mean "everything else". Add `OR col IS NULL` when the
   column is nullable.
5. Set the Dictionary initial-value flag when appending a column to a populated
   table — it removes a whole class of null from the system permanently.
6. Reach for `INDICATORS` only when null and initial genuinely mean different things
   to the business. Otherwise `coalesce( )` is simpler and portable.

## Sources

- [ABAP SQL — Null Values](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_NULL_VALUES.html) — definition, sources of nulls, conversion on transfer, `GROUP BY`/`ORDER BY`/in-memory-engine exception, Native SQL and AMDP
- [`sql_cond` — `IS NULL`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENWHERE_LOGEXP_NULL.html) — the three-valued-logic rule and the `IS INITIAL` warning
- [`SELECT` — `col_spec`](https://help.sap.com/doc/abapdocu_751_index_htm/7.51/en-us/abapselect_clause_col_spec.htm) — the empty-aggregate `sy-subrc = 0` / `sy-dbcnt = 1` rule and the `COUNT( * )` exception
- [`SELECT`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT.html) — `sy-subrc` table and the "special rules apply" pointer for aggregates
- [`sql_agg` — `agg_func`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_AGG_FUNC.html) — nulls ignored in aggregation, `COUNT` never null
- [`SELECT` — indicators](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_INDICATORS.html) and [`TYPES` — `INDICATORS`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPTYPES_INDICATORS.html) — null indicator syntax, positional vs named filling, `NOT`, `AS BITFIELD`
- [`sql_func` — Coalesce](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_COALESCE.html) — argument limits, type rules, nesting depth, in-memory engine support
- [`sql_exp` — `sql_null`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_NULL.html) — the `NULL` expression and its context typing

See also: [FOR ALL ENTRIES](../For%20All%20Entries#readme) for the implicit-`DISTINCT`
data-loss trap, [Window Expressions](../Window%20Expressions#readme) for aggregating
without collapsing rows, and [Table Buffering](../Table%20Buffering#readme) for which
constructs bypass the buffer.
