# Table Buffering — the SELECT that silently skips the buffer, and the buffer that silently serves stale data

Table buffering is the one performance feature that is **on by default, invisible
in the code, and switched off by things you wrote for unrelated reasons**. A table
marked as buffered in its technical settings is not "a fast table" — it is a table
that is fast *only* for the statements the ABAP SQL in-memory engine can process.
Everything else goes to the database, at full cost, with no warning, no syntax
check message, and no runtime error.

The other half is the mirror image: when the buffer *is* used, it can hand you
data that is up to two minutes old, and in one specific case data that is wrong
forever.

## 1. Rewriting two buffered SELECTs into one JOIN makes it slower

This is the headline, because it is the exact opposite of what every performance
guideline teaches.

```abap
" Two reads, both served from the table buffer - no database round trip
SELECT SINGLE * FROM t001  INTO @DATA(ls_bukrs) WHERE bukrs = @lv_bukrs.
SELECT SINGLE * FROM t005  INTO @DATA(ls_land)  WHERE land1 = @ls_bukrs-land1.

" "Optimised" into one statement - and now BOTH tables are read from the database
SELECT SINGLE t001~bukrs, t005~landx
  FROM t001 INNER JOIN t005 ON t005~land1 = t001~land1
  WHERE t001~bukrs = @lv_bukrs
  INTO @DATA(ls_joined).
```

> "`JOIN` expressions currently always bypass the buffer. The ABAP SQL in-memory
> engine supports join expressions for internal tables accessed by
> `SELECT ... FROM @itab` but not yet for database tables in the table buffer."
> — [Table Buffering, Restrictions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENBUFFER_RESTRICTIONS.html)

"Never SELECT in a loop, always JOIN" is good advice for transactional tables and
actively harmful for small buffered customizing tables. The rule for buffered
tables is the reverse: **keep the statement simple enough that the buffer can
serve it.**

## 2. The buffer is bypassed by additions that have nothing to do with buffering

Reads on a buffered table are handled by the *ABAP SQL in-memory engine*. If the
statement uses anything that engine cannot execute, the whole statement is handed
to the database instead. Current documented list:

| Statement uses | Buffer used? |
|---|---|
| `JOIN` on database tables | ✗ bypassed |
| Subqueries (except CTEs in `WITH`) | ✗ bypassed |
| `WITH` / common table expressions touching database tables | ✗ bypassed |
| `UNION`, `INTERSECT`, `EXCEPT` | ✗ bypassed |
| `GROUP BY`, and therefore `HAVING` | ✗ bypassed |
| `DISTINCT` | ✗ bypassed |
| `FOR UPDATE` | ✗ bypassed |
| `GROUPING SETS` | ✗ bypassed |
| `CLIENT SPECIFIED` without the client column in `WHERE` | ✗ bypassed |
| Explicit `CONNECTION` to a secondary database connection | ✗ bypassed |
| CDS table function / CDS scalar function / hierarchies | ✗ bypassed |
| Table with a DDIC replacement object | ✗ bypassed |
| `CL_OSQL_REPLACE` active during a unit test | ✗ bypassed |
| `MIN`, `MAX`, `SUM`, `COUNT( * )` **in the SELECT list** | ✓ buffer used |
| `ABS CEIL DIV FLOOR MOD`, `CONCAT[_WITH_SPACE] LEFT RIGHT LENGTH LOWER UPPER SUBSTRING` | ✓ buffer used |
| `COALESCE`, `CASE` (SELECT list only) | ✓ buffer used |
| Arithmetic expressions | ✓ buffer used |

That last block is worth a second look, because the widely repeated rule
*"aggregates and ORDER BY always bypass the buffer"* is **out of date**. In 7.40
the documented bypass list included every aggregate expression and any `ORDER BY`
whose sort key was not a left-aligned subset of the primary key
([7.40 restrictions](https://eduardocopat.github.io/abap-docs/7.40/abenbuffer_restrictions/));
in the current documentation `MIN`/`MAX`/`SUM`/`COUNT( * )` in the SELECT list are
explicitly listed as *supported* by the in-memory engine, and neither `ORDER BY`
nor `IS NULL` appears in the bypass list any more. `DISTINCT` and `GROUP BY` are
still out. Check the doc for your release rather than repeating the folklore.

## 3. `SELECT SINGLE` has nothing to do with single-record buffering

Two names, no relationship.

> "The use of single record buffering depends on the `WHERE` clause only and not
> on the use of the addition `SINGLE`."
> — [Single Record Buffering](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENBUFFER_SINGLE_BUFFERING.html)

What actually decides it:

- **Single-record buffering (`P`)** — every field of the primary key must be
  supplied, with `=`, joined by `AND`. Miss one key field and the statement goes
  to the database, even if it returns exactly one row.
- **Generic buffering (`G`)** — the *generic key* (the first *n* key fields, *n*
  from the technical settings) must be supplied completely, with `=`, joined by
  `AND`. Each generic area behaves as its own fully buffered table.
- **Full buffering (`X`)** — no `WHERE` restriction; any supported statement is
  served from the buffer.

And in all three cases the right-hand side of those equality conditions must be a
**host variable or host expression** — not another column. Same restriction applies
to the operand-list form of `IN`.

`FOR ALL ENTRIES` against a generically buffered table has an extra condition: the
generic area must still be specified exactly, and the driver table must not produce
an `OR` over several generic areas — otherwise the whole thing hits the database.

## 4. Your own writes never look stale — other application servers' writes do

This is why buffering bugs survive every test on a one-instance sandbox and then
appear in production.

Write statements always go straight to the database, and then:

- The buffers **on your own AS instance** are invalidated immediately, and until
  the next database commit every read on that instance bypasses the buffer. So
  read-after-write in your own session is always correct.
- The invalidation is written to the log table `DDLOG`.
- **Every other AS instance keeps serving the old data** until it next polls
  `DDLOG`. The default interval is **two minutes** (`rdisp/bufreftime`).
- After the invalidation clears, the next **5** reads still bypass the buffer
  before it is reloaded (`zcsa/inval_reload_c` locally, `zcsa/sync_reload_c` after
  a synchronization) — single-record buffering reloads immediately instead.

So "user A saved it, user B still sees the old value for a minute or two" is not a
bug report, it is the documented design. If the application genuinely cannot
tolerate that window, the table should not be buffered — or the specific read needs
`BYPASSING BUFFER`.

Also note the granularity of invalidation, which is coarser than people expect:
`UPDATE ... SET ... WHERE ...` and `DELETE ... WHERE ...` invalidate the **entire
table** for single-record and fully buffered tables, not just the affected rows.
Mass updates on a buffered table are therefore expensive twice over.

## 5. AMDP and Native SQL writes corrupt the buffer permanently

The one case where the data never becomes correct on its own.

> "Tables or views that can also be accessed using AMDP should not be buffered. If
> AMDP methods modify data in buffered tables or views, this is ignored by the
> database interface and the buffers are not synchronized accordingly. This can
> cause inconsistencies between the data in the buffers and on the database."
> — [ABAP SQL - Table Buffering](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSAP_PUFFERING.html)

The same applies to Native SQL (`EXEC SQL`, ADBC). No `DDLOG` entry is written, so
no instance ever learns that the data changed. The buffer stays wrong until it is
displaced, the instance restarts, or someone resets it manually with `/$TAB` in the
SAP GUI command field.

Practical rule: a table written by an AMDP method or Native SQL must not carry
buffering in its technical settings. This is easy to violate by accident — someone
adds an AMDP performance optimization years after the table was created.

## 6. Generic buffering caches misses too

A small but useful detail: if a fully specified generic key finds nothing, the
*absence* is recorded in the buffer, and the next lookup for that key does not go
to the database at all. Same for single-record buffering with a fully specified
`WHERE`. So repeatedly probing for keys that do not exist is cheap on a buffered
table and expensive on an unbuffered one.

## 7. Say what you mean: `BYPASSING BUFFER`

If a read genuinely must see current data, do not rely on the implicit bypass of
some addition you happened to use — that behaviour changes between releases, as
section 2 shows.

```abap
SELECT SINGLE * FROM t001
  WHERE bukrs = @lv_bukrs
  INTO @DATA(ls_t001)
  BYPASSING BUFFER.
```

> "To bypass the table buffer in the statement `SELECT` explicitly, the addition
> `BYPASSING BUFFER` should always be used. It is not enough to rely on the
> implicit behavior itself."

If you find yourself writing it often on the same table, the table is buffered
wrongly.

## Reading the settings

`SE11` -> table -> *Technical settings* is the UI. The underlying values live in
`DD09L` (cross-client, activated version `AS4LOCAL = 'A'`):

| `DD09L` field | Meaning |
|---|---|
| `PUFFERUNG` | `' '` not buffered · `P` single record · `G` generic · `X` full |
| `SCHFELDANZ` | number of key fields forming the generic key (`G` only) |
| `BUFALLOW` | `X` buffering on · `A` allowed but switched off · `N` not allowed |
| `SPEICHPUFF` | `X` stored compressed in the buffer |

The demo report [`ydj_table_buffer_demo.abap`](ydj_table_buffer_demo.abap) reads
those settings for any table and tells you, for a given list of `=`-restricted
fields, whether a `SELECT` would actually reach the buffer.

To see what really happened, not what should have happened: **ST05** SQL trace —
statements served from the buffer do not appear in the database trace at all, so an
"optimized" statement that suddenly shows up in ST05 is your bypass. `ST10` shows
buffered-table hit rates and `/$TAB` resets the local buffer (avoid on a
production instance: refilling a large buffer is itself a performance event).

## When not to buffer

- More than ~1% of accesses are writes — synchronization overhead outweighs the gain.
- The application cannot tolerate the asynchronous-synchronization window.
- The table is written by AMDP or Native SQL (section 5).
- Global temporary tables and non-transparent tables cannot be buffered at all.

## Sources

- [ABAP keyword documentation — ABAP SQL, Table Buffering](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSAP_PUFFERING.html)
- [ABAP keyword documentation — Table Buffering, Restrictions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENBUFFER_RESTRICTIONS.html)
- [ABAP keyword documentation — Table Buffering, Buffer Synchronization](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENBUFFER_SYNCHRO.html)
- [ABAP keyword documentation — Buffering Types](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENBUFFER_TYPE.html) · [Single Record](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENBUFFER_SINGLE_BUFFERING.html) · [Generic](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENBUFFER_GENERIC_BUFFERING.html)
- [ABAP keyword documentation — ABAP SQL In-Memory Engine, Restrictions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_ENGINE_RESTR.html) · [Supported SQL Expressions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_ENGINE_EXPR.html)
- [ABAP keyword documentation — SELECT, BYPASSING BUFFER](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_BYPASSING_BUFFER.html)
- [7.40 documentation — SAP Buffer, Restrictions](https://eduardocopat.github.io/abap-docs/7.40/abenbuffer_restrictions/) (for the older, wider bypass list)
