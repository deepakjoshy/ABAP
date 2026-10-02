# Row Limiting & Ordering in ABAP SQL — `UP TO`, `OFFSET`, `SINGLE` and the `ORDER BY` that sorts nothing

Reading *some* of the rows instead of all of them is the most ordinary thing a
`SELECT` does. The additions that do it — `SINGLE`, `UP TO n ROWS`, `OFFSET o`,
`ORDER BY` — are also where ABAP SQL hides an unusual number of behaviours that
produce **no syntax error, no exception and no wrong-looking code**:

- a limit of `0` in a host variable does not read zero rows, it reads **every** row —
  and the literal `0`, which would be the honest way to say it, is the one form the
  syntax check rejects;
- `ORDER BY @n` where `n` is a `DATA` variable **sorts nothing at all**, while the
  identical line with `n` declared as `CONSTANTS` really sorts;
- `SELECT SINGLE` on a non-unique selection reads *an* arbitrary row, and `ORDER BY`
  is forbidden with `SINGLE`, so there is no way to make it deterministic;
- `SELECT SINGLE ... FOR UPDATE` with an incomplete key reads nothing, locks nothing,
  and reports it as `sy-subrc = 8`;
- `UP TO n ROWS` with `FOR ALL ENTRIES` does **not** limit the database read.

All of them survive testing on small data or a dev system, which is exactly why they
are worth knowing cold.

## Trap 1: a limit of zero is not a limit

`UP TO n ROWS` takes a host variable, a host expression or a literal. The value `0`
is where it stops being obvious:

> "If `n` contains the value 0, a maximum of 2,147,483,647 rows are placed in the
> result set."
> — [ABAP keyword documentation, `SELECT, UP TO, OFFSET`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_UP_TO_OFFSET.html)

So a page size that arrives as `0` — an empty input field, a customizing row nobody
maintained, a `MIN` aggregate over an empty result — turns a bounded read into a
full table scan into memory. Nothing in the statement changes, and the only visible
symptom is that it got slow.

```abap
DATA(lv_limit) = 0.                  " from config, an input field, a calculation

SELECT carrid, connid
  FROM spfli
  INTO TABLE @DATA(lt_rows)
  UP TO @lv_limit ROWS.              " reads SPFLI in full, not zero rows
```

The asymmetry that makes this hard to catch in review: the *literal* zero cannot
even compile. From the strict mode of the syntax check in release 7.63:

> "Only the data types `b`, `s`, `i`, and `int8` are allowed for the operand `n`
> after the additions `UP TO` and `PACKAGE SIZE` of the statement `SELECT`. A literal
> or a constant cannot have the value 0 here."
> — [ABAP keyword documentation, strict mode from release 7.63](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_STRICTMODE_763.html)

`UP TO 0 ROWS` is a syntax error. `UP TO @lv_zero ROWS` is a full read. The compiler
blocks the form that is at least readable and waves through the one that is not, so
a computed limit needs its own guard before it reaches the statement:

```abap
IF lv_limit <= 0.
  lv_limit = 50.                     " or RETURN - but decide it explicitly
ENDIF.
```

The other end of the range is worse than an exception:

> "If `n` contains a negative number or +2,147,483,647, a syntax error is produced,
> or an uncatchable exception is raised."

**Uncatchable** — a `TRY ... CATCH cx_root` around the `SELECT` does not help. The
same rule applies to `OFFSET o`.

## Trap 2: `ORDER BY` with a variable position sorts nothing

A column can be named after `ORDER BY` by name, by alias, or by its **position** in
the result set. The position form looks like it should accept a variable. It does
accept one — and then ignores it:

> "If `n` is a variable or does not have an integer type, it does not specify a
> position but is handled as an SQL expression `sql_exp` that has no effect."
> — [ABAP keyword documentation, `SELECT, ORDER BY`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPORDERBY_CLAUSE.html)

and, from the same page, the rule that decides which of the two it is:

> "A single literal or host constant with an integer type is not handled as a SQL
> expression but as a column position `n`."

So the behaviour depends on the **declaration** of the operand, not on anything in
the `SELECT`. The doc spells the consequence out in a note under its own bad
example: *"If `n` were declared with `CONSTANTS` instead of `DATA`, it were a
position specification."*

```abap
SELECT carrid, carrname, currcode FROM scarr
  ORDER BY 3 DESCENDING
  INTO TABLE @DATA(lt_sorted).       " sorts by CURRCODE

DATA lv_pos TYPE i VALUE 3.
SELECT carrid, carrname, currcode FROM scarr
  ORDER BY @lv_pos DESCENDING
  INTO TABLE @DATA(lt_unsorted).     " sorts by NOTHING

CONSTANTS lc_pos TYPE i VALUE 3.
SELECT carrid, carrname, currcode FROM scarr
  ORDER BY @lc_pos DESCENDING
  INTO TABLE @DATA(lt_sorted_again). " sorts by CURRCODE again
```

Turning a `CONSTANTS` into a `DATA` because the value now comes from a parameter is
a refactoring that silently removes the sort.

The quoted variant fails the same way — a character literal is an SQL expression
with no column operand, and the doc states that as a rule such an expression *"has
no effect"*:

```abap
ORDER BY 'CURRCODE' DESCENDING       " a literal string, not the column
```

Two further hazards in the position form:

- the position counts the columns of the **result set**, and is *"independent from
  the addition `CORRESPONDING FIELDS` of the `INTO` clause"* — reordering the target
  structure changes nothing, reordering the select list changes everything;
- with `*` or `data_source~*` on a client-dependent source, *"the client column is
  part of the result set and relevant for counting the columns"* — so every position
  shifts by one.

Prefer the column name. The position form exists for expressions that have no name,
and an alias is the better answer there. Aliases have their own edge, straight from
the doc: with `SELECT col1 AS 1 col2 AS +`, an `ORDER BY 1 + 1` sorts by three
columns named `1`, `+` and `1` — so keep alias names alphanumeric.

## Trap 3: `SINGLE` cannot be made deterministic

`SELECT SINGLE` is documented in two sentences that are easy to read past:

> "If the selection of the `SELECT` statement covers exactly one row, this row is
> included in the result set. If the selection of the `SELECT` statement covers more
> than one row, one of these rows is included in the result set."
> — [ABAP keyword documentation, `SELECT, SINGLE, FOR UPDATE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_SINGLE.html)

*One of these rows* — not the first, not the lowest key, not the newest. And the
obvious fix is not available:

> "The addition `ORDER BY` cannot be specified together with `SINGLE`, which means
> that it is not possible to define which row is read from a non-unique selection.
> Instead, the addition `UP TO 1 ROWS` can be specified with the addition `ORDER BY`
> to define which row is read from a non-unique selection."

So `SELECT SINGLE ... WHERE carrid = ` with no `connid` is not *roughly* right. It
is a read whose result the database is free to change after an index is added, a
row is updated, or the data is moved to another system:

```abap
" CARRID alone is not the full key of SPFLI - whichever row comes back is luck
SELECT SINGLE connid, cityto FROM spfli WHERE carrid = 'LH'
  INTO @DATA(ls_any).

" deterministic: ORDER BY decides which of the matching rows is "the" one
SELECT connid, cityto FROM spfli WHERE carrid = 'LH'
  ORDER BY connid ASCENDING
  INTO TABLE @DATA(lt_first)
  UP TO 1 ROWS.
```

The two are not a performance trade-off. Without `ORDER BY` the result sets are
identical, and the doc says `SINGLE` is *"generally slightly faster ... since no
loop has to be opened. In practice, however, this difference can usually be
ignored"* — SAP even ships the class `CL_DEMO_SELECT_SINGLE_VS_UP_TO` to measure it
on your own system. The documented split is about **intent**:

| Intent | Addition |
|---|---|
| read exactly one **completely specified** row | `SELECT SINGLE` |
| read **at most one** row out of a set | `UP TO 1 ROWS` with `ORDER BY` |

The extended program check (SLIN / ATC) already warns when `SINGLE` is used without
a fully determined row. It is worth treating that warning as a finding rather than
noise, because the deliberate case — using `SINGLE` purely to test whether a row
exists — is documented as needing the warning suppressed with a pragma, so an
unsuppressed warning always means nobody looked. For an existence check the doc also
recommends a select list holding **nothing but a single constant**, so no data is
transported at all.

Also worth knowing: with `SINGLE`, no internal table can be the target, and the
addition is not allowed in the main query of `OPEN CURSOR` or in a subquery.

## Trap 4: `FOR UPDATE` with a partial key reads nothing and locks nothing

`SELECT SINGLE ... FOR UPDATE` sets an exclusive **database** lock on the row. Its
precondition is strict, and the failure is quiet:

> "With this addition, the `SELECT` statement is only executed if, in the `WHERE`
> condition, all primary key fields in logical expression that are joined using
> `AND` are checked for equivalence. Otherwise the result set is empty and
> `sy-subrc` is set to 8."

No exception, no dump, no lock, and an empty result set that is indistinguishable
from *no such row* if the only thing checked is `sy-subrc <> 0`. The full value set
for a `SELECT` is worth memorising, because two of the four only exist here:

| `sy-subrc` | Meaning |
|---|---|
| 0 | rows were passed to the target |
| 4 | the result set is empty (special rules apply for aggregate-only select lists) |
| 6 | `FOR UPDATE NOWAIT` could not set the lock — **nothing was read** |
| 8 | `FOR UPDATE` was used and the primary key is not fully specified after `WHERE` |

Three more facts about `FOR UPDATE` that change how a statement performs:

- it *"cannot be processed by the ABAP SQL in-memory engine"*, and a standalone
  `SELECT` with it *"bypasses the table buffer"* — adding it to a read on a fully
  buffered table turns every call into a database round trip;
- *"If set incorrectly, the lock can produce a deadlock"*;
- it is rejected on data sources that are read-only, and on `FROM @itab`.

For application-level locking the SAP lock concept is the usual answer instead —
see [Enqueue Locks](../Enqueue%20Locks#readme).

## Trap 5: `OFFSET` pagination is only as stable as the `ORDER BY`

`OFFSET o` skips the first `o` rows of the sorted result set, which makes
`ORDER BY ... UP TO @size ROWS OFFSET @skip` the natural way to page through data.
It requires an `ORDER BY` — and that requirement is weaker than it looks:

> "The order of the rows in the result set is undefined with respect to all columns
> that are not listed after `ORDER BY` and can be different in repeated executions
> of the same `SELECT` statement."

Page 1 and page 2 are two separate executions. If the sort key is not unique, the
rows that share a key value may come back in a different order each time, so a row
can appear on **both** pages while another appears on **neither** — and the user
sees a duplicate or a missing record, not an error.

```abap
" CITYFROM is not unique in SPFLI: pages may overlap or skip
SELECT carrid, connid, cityfrom FROM spfli
  ORDER BY cityfrom
  INTO TABLE @DATA(lt_page)
  UP TO @lv_size ROWS OFFSET @lv_skip.

" stable: extend the sort key until it is unique, usually with the primary key
SELECT carrid, connid, cityfrom FROM spfli
  ORDER BY cityfrom, carrid, connid
  INTO TABLE @DATA(lt_stable_page)
  UP TO @lv_size ROWS OFFSET @lv_skip.
```

The same sentence has a second consequence: *"If the `ORDER BY` clause does not sort
the result set uniquely, it is not possible to define which rows are in the result
set"* — which applies to `UP TO n ROWS` on its own, not just to paging. A top-ten
report over a non-unique ranking column returns *a* valid top ten, not *the* one.

`OFFSET` is also the most restricted of these additions. It cannot be combined with
`SINGLE`, with `FOR ALL ENTRIES`, with `UNION` / `INTERSECT` / `EXCEPT`, and it is
rejected when DDIC projection views are accessed. `o = 0` means *from the first row*
and is harmless, unlike `n = 0` for `UP TO`. Using it switches the syntax check into
the 7.63 strict mode for the whole statement, which is stricter than the regular
one — so adding `OFFSET` to an old statement can surface unrelated errors in it.

Position rules are easy to get wrong because they differ by query type: in a main
query the additions go after the `INTO` clause when `INTO` is last; in a **subquery**
`UP TO` may only follow an `ORDER BY`, and `OFFSET` may only follow `UP TO`.

## Trap 6: `UP TO n ROWS` does not limit the read under `FOR ALL ENTRIES`

Adding a row limit to a `FOR ALL ENTRIES` query looks like a memory guard. It is not:

> "If the addition `FOR ALL ENTRIES` is also specified, all selected rows are
> initially read into an internal table and the addition `UP TO n ROWS` only takes
> effect during the passing from the system table to the actual target area. This
> can produce unexpected memory bottlenecks."

The target holds `n` rows, the session held all of them a moment earlier. The same
combination also narrows sorting to one single form: with `FOR ALL ENTRIES`,
`ORDER BY` *"can only be used with the addition `PRIMARY KEY` and all columns of the
primary key, except the client column of client-dependent tables, must be specified
in the `SELECT` list"*. `OFFSET` is not allowed with it at all.

If the goal really is bounded memory, chunk the read instead — see
[Mass Data Processing](../Mass%20Data%20Processing#readme) for `PACKAGE SIZE` and
cursors, and [For All Entries](../For%20All%20Entries#readme) for the empty-driver
and implicit-`DISTINCT` traps that come with `FOR ALL ENTRIES` itself.

## Smaller things that cost an afternoon

- **Do not hand-roll a limit.** The doc prefers `UP TO n ROWS` over a `SELECT` loop
  that exits after `n` rows, because in the loop *"the last package passed from the
  database to the AS ABAP usually contains superfluous rows"* — the rows were
  already transported before the `EXIT` ran.
- **`ORDER BY PRIMARY KEY` is narrower than it sounds.** It is rejected with joins,
  path expressions, subqueries, `UNION` / `INTERSECT` / `EXCEPT` results and access
  to a `WITH` common table expression. It is refused on views *"that contain
  exactly the same number of key fields as view fields"* — and in that case *"the
  result set is sorted by all columns"* instead, which is a different and slower
  statement than the one that was written. For a CDS entity, its key elements must
  be defined at the start of the structure without gaps.
- **Sorting happens last, on the database.** It runs *"once all other actions are
  completed, such as determining the hit list using `WHERE`, calculating aggregate
  functions, and grouping using `GROUP BY`"*, and *"Only the additions `UP TO` and
  `OFFSET` are executed on the sorted hits"*. That is the whole reason `UP TO` plus
  `ORDER BY` gives a real top-n.
- **Character sorts can differ from ABAP sorts.** Database sorting follows the
  platform rules for size comparisons, so the same data sorted in ABAP and sorted in
  `ORDER BY` may not match. See
  [Sorting & Deduplication](../Sorting%20and%20Deduplication#readme).
- **Reading into a `SORTED` internal table discards the `ORDER BY`.** The doc is
  explicit: *"If a sorted resulting set is assigned to a sorted internal table, the
  internal table is sorted again according to the sorting instructions"* — so the
  database sort was paid for and thrown away.
- **A dynamic `ORDER BY` with initial content is ignored**, not an error, and
  invalid content raises `CX_SY_DYNAMIC_OSQL_ERROR`. Anything that reaches it from
  outside the program must go through `CL_ABAP_DYN_PRG` or the built-in `escape`
  before it is used — see [Dynamic SQL](../Dynamic%20SQL#readme).
- **`UP TO` is rejected with `SINGLE` and with `UNION` / `INTERSECT` / `EXCEPT`** —
  for set operations the limit has to be applied around the whole expression, see
  [Set Operators](../Set%20Operators#readme).

## Quick reference

| Goal | Write |
|---|---|
| one row, full key known | `SELECT SINGLE ... WHERE <full key>` |
| at most one row of many | `ORDER BY <unique> ... UP TO 1 ROWS` |
| does any row exist | `SELECT FROM t FIELDS 'X' ... UP TO 1 ROWS` - a constant select list transports no data |
| top n | `ORDER BY <criterion>, <unique> ... UP TO @n ROWS` |
| page n | same `ORDER BY` plus `OFFSET @skip` — sort key must be unique |
| one row plus a DB lock | `SELECT SINGLE ... FOR UPDATE`, full key only, check `sy-subrc` |
| bounded memory on mass data | `PACKAGE SIZE` or a cursor, **not** `UP TO` with `FOR ALL ENTRIES` |

## See also in this repo

- [For All Entries](../For%20All%20Entries#readme) — the empty driver table and the
  implicit `DISTINCT`
- [Mass Data Processing](../Mass%20Data%20Processing#readme) — `PACKAGE SIZE`, cursors
  and the commit that closes them
- [Set Operators](../Set%20Operators#readme) — why `UP TO` and `OFFSET` are refused
  there
- [Window Expressions](../Window%20Expressions#readme) — ranking per group, which is
  what a per-group top-n actually needs
- [Sorting & Deduplication](../Sorting%20and%20Deduplication#readme) — the ABAP-side
  counterpart, including unstable `SORT`
- [Null Values](../Null%20Values#readme) — the aggregate-only select list whose
  `sy-subrc` is 0 on no data
- [Enqueue Locks](../Enqueue%20Locks#readme) — SAP locks versus the database lock of
  `FOR UPDATE`

## References

- [`SELECT, UP TO, OFFSET`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_UP_TO_OFFSET.html)
- [`SELECT, SINGLE, FOR UPDATE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_SINGLE.html)
- [`SELECT, ORDER BY`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPORDERBY_CLAUSE.html)
- [`SELECT` — overview, `sy-subrc` and `sy-dbcnt`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT.html)
- [Strict mode of the syntax check from release 7.63](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_STRICTMODE_763.html)

See `ydj_row_limiting_demo.abap` in this folder for a runnable version of all of the
above against the flight data model. It is read-only and does not execute
`FOR UPDATE`, which would set exclusive database locks.
