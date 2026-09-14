# Mass Data Processing — PACKAGE SIZE, OPEN CURSOR and the commit-closes-your-cursor trap

Reading a table that does not fit in memory means either `SELECT ... PACKAGE SIZE`
or `OPEN CURSOR` / `FETCH`. Both hold an **open database cursor** for the whole
loop, and almost every mass-processing program wants to `COMMIT WORK` as it goes —
which is exactly the thing that destroys the cursor.

This note is about that collision, and about the `PACKAGE SIZE` semantics that
silently change what is in your target table.

## Trap 1: any commit inside the loop closes the cursor

> "A database commit closes all opened database cursors. In particular, in `SELECT`
> loops and after the statement `OPEN CURSOR`, database commits should not be
> triggered by mistake in one of the ways listed here."
> — [ABAP keyword documentation, Database Commit](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDB_COMMIT.html)

The next `FETCH` (or the next pass of the `SELECT` loop) then dies with
`DBSQL_INVALID_CURSOR`. The obvious trigger is `COMMIT WORK`. The dangerous ones
are the **implicit** commits, because nothing in the source line looks like a
commit:

| Trigger inside the loop | Why it commits |
|---|---|
| `COMMIT WORK` / `COMMIT CONNECTION` / `DB_COMMIT` | explicit |
| End of a dialog step (any screen, any `WRITE` list shown) | program releases its work process |
| `CALL FUNCTION ... DESTINATION` (sRFC **and** aRFC) | control moves to another work process |
| `CALL FUNCTION ... STARTING NEW TASK`, and `RECEIVE` in the callback | same |
| `WAIT UP TO n SECONDS`, `WAIT FOR ASYNCHRONOUS TASKS`, `WAIT FOR MESSAGING CHANNELS` | work process is released during the wait |
| Any HTTP/HTTPS/SMTP call through ICF (so: every REST/proxy call) | commit before each response |
| `MESSAGE` of type **E**, **I** or **W** | these interrupt the dialog step |
| ABAP Messaging / Push Channel send & bind | documented commit points |

Two things follow. First, a progress message or a debugging `MESSAGE 'x' TYPE 'I'`
dropped into a cursor loop is enough to dump it — and only in the run where that
branch is reached. Second, parallelising with `STARTING NEW TASK` inside a cursor
loop cannot work as written; that is the classic BI-extractor failure.

Note the one exception in the doc: **updates**. Inside update processing, sRFC/aRFC,
`RECEIVE`, ICF and `WAIT` do *not* trigger the commit.

## Trap 2: `WITH HOLD` does not protect you from `COMMIT WORK`

`OPEN CURSOR WITH HOLD` is widely passed around as "the fix". It is not, for the
case people use it for. The doc is explicit about what it ignores:

> "The addition `WITH HOLD` is ignored by the following: Implicit database commits;
> Commits made by the statement `COMMIT WORK`; Any rollbacks. These always close the
> database cursor."
> — [ABAP keyword documentation, OPEN CURSOR](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPOPEN_CURSOR.html)

`WITH HOLD` protects against **Native SQL** database commits only — i.e. an explicit
`COMMIT CONNECTION`. Against `COMMIT WORK`, an implicit commit, or *any* rollback it
does nothing. It also cannot be combined with `CONNECTION` and works only on the
standard database.

One genuine subtlety, same source: a commit only closes the cursor **once the cursor
has been used in a `FETCH`**. A commit between `OPEN CURSOR` and the first `FETCH`
is harmless. That is why a test with a tiny data set sometimes passes.

## The pattern that actually works: keys first, then commit freely

Since you cannot commit while a cursor is open, do not hold one. Read the **keys**
in one bounded statement, close that read, then loop over the keys in chunks — the
cursor is gone by the time you commit.

```abap
" Phase 1 - one read, cursor closed when it finishes.
SELECT vbeln FROM vbak
  WHERE erdat >= @lv_from
  INTO TABLE @DATA(lt_keys).                    " bound this with UP TO if needed

" Phase 2 - chunk it yourself. COMMIT WORK here is safe: no cursor is open.
DATA(lv_from_idx) = 1.
WHILE lv_from_idx <= lines( lt_keys ).
  DATA(lt_chunk) = VALUE ty_keys(
    FOR i = lv_from_idx UNTIL i > nmin( val1 = lv_from_idx + 999
                                        val2 = lines( lt_keys ) )
    ( lt_keys[ i ] ) ).

  SELECT ... FOR ALL ENTRIES IN @lt_chunk ...   " guard against empty! see below
  " ... process, update ...
  COMMIT WORK.                                  " safe
  lv_from_idx = lv_from_idx + 1000.
ENDWHILE.
```

If phase 1 itself is too big to hold, page it with `UP TO n ROWS` + `OFFSET n`
ordered by a stable key, rather than opening a cursor.

See also [FOR ALL ENTRIES](../For%20All%20Entries#readme) — the chunk table must be
checked for `IS NOT INITIAL` before the `SELECT`, or the whole `WHERE` is dropped.

## `PACKAGE SIZE`: `INTO` clears, `APPENDING` accumulates

`PACKAGE SIZE n` after `INTO TABLE` or `APPENDING TABLE` opens a `SELECT` loop that
must be closed with `ENDSELECT`. The two forms behave in opposite ways:

> "If `INTO` is used, the internal table is initialized before each insertion and, in
> the `SELECT` loop, it only contains the rows of the current package. If `APPENDING`
> is used, a further package is added to the existing rows of the internal table for
> each `SELECT` loop or for each extraction using `FETCH`."
> — [ABAP keyword documentation, SELECT - INTO, APPENDING](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINTO_CLAUSE.html)

So `APPENDING TABLE ... PACKAGE SIZE n` **grows without bound** — it gives you
package-sized loop passes but no memory protection at all. The doc says so directly:
"`PACKAGE SIZE` cannot prevent this runtime error after `APPENDING`." Only the `INTO`
form is a memory guard.

Two more that bite:

- **After `ENDSELECT`, the `INTO` target is undefined** — "the table can either
  contain the rows of the last package or it can be initial". Never read it after the
  loop. (`APPENDING` does keep the last state.)
- **`PACKAGE SIZE` with `FOR ALL ENTRIES` is not a memory guard either**: all selected
  rows are first read into an internal *system* table, and packaging only happens when
  handing rows from that system table to your target.
- `PACKAGE SIZE` has nothing to do with the DB-to-application-server transport packet
  size set by profile parameters. Different layer.

## `OPEN CURSOR` / `FETCH` specifics worth knowing

- **Maximum 17 open cursors per program**, across the whole ABAP SQL interface, then
  `DBSQL_TOO_MANY_OPEN_CURSOR`. The interface also opens cursors *implicitly* — e.g.
  loading a buffered table — so 17 is not 17 of yours.
- `FETCH` sets `sy-subrc` = 0 (at least one row) or 4 (none), and `sy-dbcnt` to the
  **cumulative** rows fetched from that result set so far — not the rows in this
  package. It is set to `-1` on overflow past 2,147,483,647.
- Whether the database closes the cursor itself after the last row is
  **database-dependent**; the doc's advice is to always `CLOSE CURSOR` explicitly.
- Assigning one cursor variable to another links both to the *same* cursor at the same
  position. The doc recommends against it: set cursor variables only via `OPEN CURSOR`
  and `CLOSE CURSOR`.
- Writing to a table while a cursor is open on it gives a "database-dependent and
  undefined" result set. Read and write phases must be separated.
- Consecutive `FETCH`es on one cursor may mix `INTO`/`APPENDING` and different
  `PACKAGE SIZE`s, but `CORRESPONDING FIELDS` must appear in **all** of them or none,
  and every work area / row type must be identical.
- If a CDS view is a [replacement object](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDDIC_REPLACEMENT_OBJECTS.html)
  for the table named in `OPEN CURSOR`, `FETCH` reads the **CDS entity**, not the table.

## Files

- [`ydj_package_size_demo.abap`](ydj_package_size_demo.abap) — runnable comparison of
  `INTO` vs `APPENDING` packaging, cursor `sy-dbcnt` semantics, and the safe
  keys-first commit pattern, against the SPFLI/SFLIGHT demo data.

## Sources

- [OPEN CURSOR](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPOPEN_CURSOR.html) — `WITH HOLD` scope, 17-cursor limit, undefined parallel writes
- [FETCH](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPFETCH.html) — `sy-subrc`/`sy-dbcnt`, mixing `INTO`/`APPENDING`, explicit `CLOSE CURSOR`
- [SELECT - INTO, APPENDING](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINTO_CLAUSE.html) — `PACKAGE SIZE` semantics and its limits
- [Database Commit](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDB_COMMIT.html) — the implicit-commit list
- [Invalid cursor dumps - a possible solution](https://community.sap.com/t5/application-development-and-automation-blog-posts/invalid-cursor-dumps-a-possible-solution/ba-p/13359716) — SAP Community, the extractor/`STARTING NEW TASK` case
