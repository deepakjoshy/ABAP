# Window Expressions in ABAP SQL — `OVER( )`, frames and the traps

An aggregate expression collapses rows. A **window expression** does not: it
computes a value from a set of related rows and writes it onto *every* row of that
set. "Each flight, plus the carrier's total" in one `SELECT`, instead of a second
query or a `LOOP ... AT END OF`.

Available from **ABAP release 7.54**. The two things that bite are both silent:
adding `ORDER BY` inside `OVER( )` changes the answer, and `LAST_VALUE` does not
return the last value.

```abap
SELECT carrid, connid, seatsocc,
       SUM( seatsocc ) OVER( PARTITION BY carrid ) AS carrier_total
  FROM sflight
  INTO TABLE @DATA(lt_flights).
```

`PARTITION BY` plays the role `GROUP BY` plays for an aggregate — but the rows
survive. Omit `PARTITION BY` and the window is the entire result set.

## The frame trap — `ORDER BY` inside `OVER( )` is not just a sort

This is the one that produces wrong numbers rather than a syntax error:

```abap
SUM( seatsocc ) OVER( PARTITION BY carrid )                  "partition total
SUM( seatsocc ) OVER( PARTITION BY carrid ORDER BY fldate )  "RUNNING total
```

`ORDER BY` after `OVER` does two things, and the second one is easy to miss. It
orders the window, **and** it introduces a *frame*, which restricts which rows the
function actually sees.

> "If no window frame is used, the default window frame is `BETWEEN UNBOUNDED
> PRECEDING AND CURRENT ROW`. That is to say that the window function computes all
> rows up to the current row. As a result, the function returns cumulative values."
> — [ABAP keyword documentation, `sql_win`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_OVER.html)

So `ORDER BY` is exactly what you want for a running total and exactly what you must
*omit* for a group total. Frames are spelled out with `ROWS BETWEEN`:

| Frame | Meaning |
|---|---|
| `UNBOUNDED PRECEDING` | start at the first row of the window |
| `UNBOUNDED FOLLOWING` | end at the last row of the window |
| `CURRENT ROW` | start or end at the current row, inclusive |
| `n PRECEDING` / `n FOLLOWING` | `n` rows above/below the current row |

```abap
" 3-row rolling average: previous, current, next
AVG( seatsocc ) OVER( ORDER BY fldate ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING )
```

`ORDER BY` is mandatory whenever a `ROWS BETWEEN` frame is given, and `n` must be 0,
a positive integer literal, or a host expression of type `b`, `s`, `i` or `int8`.

## `LAST_VALUE` returns the current row unless you widen the frame

Direct consequence of the default frame, and worth its own heading because the
result looks plausible:

```abap
LAST_VALUE( seatsocc ) OVER( PARTITION BY carrid ORDER BY fldate )
  "-> the CURRENT row's value. The frame ends at the current row.

LAST_VALUE( seatsocc ) OVER( PARTITION BY carrid ORDER BY fldate
                             ROWS BETWEEN UNBOUNDED PRECEDING
                                      AND UNBOUNDED FOLLOWING )
  "-> the partition's actual last value.
```

`FIRST_VALUE` is unaffected — the first row of the default frame *is* the first row
of the partition. Only `LAST_VALUE` needs the explicit frame. Note also that ties in
the sort column are treated as one group, so with duplicates the "last" value is the
last of the group of equals, not the last row.

## Ranking functions — pick the right one for ties

`ROW_NUMBER( )`, `RANK( )`, `DENSE_RANK( )` and `NTILE( n )` exist *only* in window
expressions. All return `INT8`. They are identical when there are no ties:

| Values | `ROW_NUMBER` | `RANK` | `DENSE_RANK` |
|---|---|---|---|
| 100 | 1 | 1 | 1 |
| 90 | 2 | 2 | 2 |
| 90 | 3 | 2 | 2 |
| 80 | 4 | **4** | **3** |

- `ROW_NUMBER( )` — always unique; the order *among* tied rows is undefined. Without
  `ORDER BY` it still numbers uniquely, just not meaningfully.
- `RANK( )` — ties share the lowest row number, so the sequence has **gaps**.
- `DENSE_RANK( )` — ties share the number, no gaps.
- `RANK` and `DENSE_RANK` **require** `ORDER BY` after `OVER`.
- `NTILE( n )` distributes rows into `n` buckets; if they do not divide evenly the
  first (`rows MOD n`) buckets get one extra, which means **equal values can land in
  different buckets**. `ORDER BY` is mandatory here too.

## Top-N per group needs a CTE

A window expression can only appear in the `SELECT` list. It is **not** allowed in
`WHERE`, `GROUP BY` or `HAVING` — unlike an aggregate, which at least works in
`HAVING`. To filter on a rank, materialise it first with a common table expression
(`WITH`, 7.51+):

```abap
WITH
  +ranked AS (
    SELECT carrid, connid, seatsocc,
           ROW_NUMBER( ) OVER( PARTITION BY carrid
                               ORDER BY seatsocc DESCENDING ) AS rownum
      FROM sflight )
  SELECT carrid, connid, seatsocc
    FROM +ranked
    WHERE rownum <= 3
    INTO TABLE @DATA(lt_top3).
```

The `+` prefix is part of the CTE name — it is what stops a CTE ever shadowing a
DDIC table. Every CTE declared must be used at least once, and a CTE cannot
reference itself or a CTE declared after it.

## Smaller gotchas

- **`ORDER BY` after `OVER` takes column names only.** No alias names defined with
  `AS`, no column positions, no expressions.
- **It is unrelated to the statement's own `ORDER BY`.** Sorting the window does not
  sort the result set. To sort the output by a window result, use its alias in the
  `SELECT` statement's `ORDER BY`.
- **`COUNT` returns `INT8` here, not `INT4`** — declaring the target as `i` can
  truncate. `DISTINCT` is allowed only for `COUNT`, and `STDDEV`/`VAR` accept only
  `FLTP` arguments in a window expression.
- **With `GROUP BY`**, every column named anywhere in the window expression must
  also be in the `GROUP BY` clause; aggregates may then be nested as the window
  function's argument.
- **Not every database supports windowing.** Guard with
  `cl_abap_dbfeatures=>use_features( VALUE #( ( cl_abap_dbfeatures=>windowing ) ) )`
  rather than letting the statement dump on an unsupported platform.
- **ABAP SQL only** — window expressions are [not supported by ABAP CDS](https://community.sap.com/t5/application-development-and-automation-blog-posts/window-expressions-in-abap-sql/ba-p/13511228);
  AMDP is the alternative if the logic has to live in a view.

## References

- [`sql_win` — window expressions, `OVER`, `ROWS BETWEEN`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_OVER.html)
- [`win_func` — ranking and value functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_WIN_FUNC.html)
- [`WITH` — common table expressions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWITH.html)
- [Window Expressions in ABAP SQL — SAP Community](https://community.sap.com/t5/application-development-and-automation-blog-posts/window-expressions-in-abap-sql/ba-p/13511228)

See `ydj_window_expr_demo.abap` in this folder for a runnable version of all of the
above against the flight data model.
