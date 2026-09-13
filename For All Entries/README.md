# FOR ALL ENTRIES — the empty-table and implicit-DISTINCT traps

`SELECT ... FOR ALL ENTRIES IN @itab` (FAE) is the everyday way to read a child
table for a set of parent keys. It has two behaviours that are **documented, correct,
and silently wrong for what most code intends**. Both are data-correctness bugs, not
performance issues — they return the wrong rows rather than being slow.

## Trap 1: an empty driver table reads the whole table

> "If the internal table `itab` is empty, the entire `WHERE` condition is ignored.
> This means that none of the rows in the database table are skipped and are placed
> in the results set."
> — [ABAP keyword documentation, SELECT - FOR ALL ENTRIES](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abenwhere_logexp_itab.htm)

The **entire** `WHERE` is dropped — not just the FAE comparison. Every other
condition you wrote goes with it:

```abap
" it_keys IS INITIAL  ->  this reads ALL of vbap, every plant, every status.
SELECT vbeln, posnr, matnr FROM vbap
  FOR ALL ENTRIES IN @it_keys
  WHERE vbeln  = @it_keys-vbeln
    AND werks  = '1000'          " <- also ignored
    AND matnr <> @space          " <- also ignored
  INTO TABLE @DATA(lt_items).
```

On a production `VBAP`/`BSEG`/`MSEG` that is a full table scan into memory, usually
ending in `TSV_TNEW_PAGE_ALLOC_FAILED`. The fix is one line, every time:

```abap
IF it_keys IS NOT INITIAL.
  SELECT ... FOR ALL ENTRIES IN @it_keys ...
ENDIF.
```

Client handling is the one thing that survives: the implicit client condition still
applies, so you read all rows **of the current client**. But under
`CLIENT SPECIFIED` there is no implicit condition, and an explicitly coded client
condition *is* dropped with the rest — so an empty driver table reads **all clients**.

## Trap 2: FAE implies DISTINCT — rows you expected go missing

> "With respect to rows occurring more than once in the results set, the addition
> `FOR ALL ENTRIES` has the same effect as when the addition `DISTINCT` is specified."
> — same source

Duplicate rows are removed from the **result set**, comparing the full selected row.
This is the trap: if your field list is not unique, legitimately distinct database
rows collapse into one.

```abap
" Two different items can share matnr + quantity. This silently loses rows:
SELECT matnr, kwmeng FROM vbap
  FOR ALL ENTRIES IN @it_keys
  WHERE vbeln = @it_keys-vbeln
  INTO TABLE @DATA(lt_qty).       " <- deduplicated. SUM over this is WRONG.
```

**Rule: always include the full key of the selected table in the field list**
(`vbeln, posnr` here), or aggregate after the read. This matters most when you are
about to total an amount or count rows — the dedup happens before you ever see it.

Note this is about *result* rows, not driver rows. Duplicates in the **driver**
table are harmless for correctness, but they generate redundant work — `SORT` +
`DELETE ADJACENT DUPLICATES` on the driver's comparison fields before the `SELECT`.

## Restrictions worth knowing before you write it

| Addition | Behaviour with FOR ALL ENTRIES |
|---|---|
| `SINGLE` | not allowed |
| `UNION` | not allowed |
| SQL expressions | not allowed |
| `GROUP BY` | **no effect** — silently ignored, not an error |
| `ORDER BY` | only `ORDER BY PRIMARY KEY`, single table, all key fields in the field list |
| `PACKAGE SIZE` / `UP TO` / `OFFSET` | do **not** limit what the DB returns — see below |
| `STRING`, `RAWSTRING`, `LCHR`, `LRAW` in the field list | syntax-check warning; forces dedup on the app server |

The `PACKAGE SIZE` one deserves emphasis: when dedup happens on the application
server, all matching rows are first moved into an internal system table and only
*then* handed to your target in packages. `PACKAGE SIZE` therefore gives you no
memory protection here, and exceeding the internal table size limit is a runtime
error. `UP TO n ROWS` is not a safety net either.

## How it executes, and when a JOIN is better

FAE is not sent to the database as one statement. The driver table is split into
blocks and each block becomes a separate `SQL` statement (an `OR`/`IN` list),
governed by the profile parameters `rsdb/max_blocking_factor` and
`rsdb/max_in_blocking_factor` (see
[SAP Note 634263](https://www.stechno.net/repository/sap-notes.html?id=634263) and
[Note 48230](https://userapps.support.sap.com/sap/support/knowledge/en/2423689)).
The results of all blocks are unioned and then deduplicated.

Practical consequences:

- **Ensure the `WHERE` can use an index.** With a driver table of 50,000 rows and a
  non-selective index, you are running many expensive statements, not one.
- **An inner JOIN is usually faster** for plain parent/child reads on the same DB —
  one statement, one optimizer plan, no dedup surprise.
- **FAE wins on buffered tables**: unlike a JOIN, FAE still uses SAP table buffering
  (except for generically buffered tables when the condition doesn't pin one generic
  area), so for small, fully-buffered customizing tables FAE avoids a DB round trip
  that a JOIN would force.
- The driver table is read **once** per query — changing it inside a `SELECT` loop
  has no effect on the condition.

## Modern alternative

A subquery on the same data source expresses the same intent without the dedup and
empty-table semantics, and stays a single database statement:

```abap
SELECT vbeln, posnr, matnr FROM vbap
  WHERE vbeln IN ( SELECT vbeln FROM vbak WHERE erdat = @lv_date )
  INTO TABLE @DATA(lt_items).
```

For two or more key fields there is a value-tuple form,
`WHERE ( carrid, connid ) IN ( SELECT carrid, connid FROM ... )`, on newer releases
(blanks just inside the parentheses are mandatory). Trade-off: a subquery bypasses
the table buffer, so for small fully-buffered tables FAE can still be the better read.

See `ydj_for_all_entries_demo.abap` in this folder for a runnable comparison of all
three forms against the flight data model.

## References

- [SELECT - FOR ALL ENTRIES — ABAP keyword documentation](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abenwhere_logexp_itab.htm)
- [FOR ALL ENTRIES — SAP Help Portal collection](https://help.sap.com/docs/SUPPORT_CONTENT/abap/3353526117.html)
- [SAP Note 634263 — Selects with FOR ALL ENTRIES](https://www.stechno.net/repository/sap-notes.html?id=634263)
