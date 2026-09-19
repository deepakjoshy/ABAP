# ABAP SQL Write Access — INSERT / UPDATE / MODIFY / DELETE

The read side of ABAP SQL is where developers spend their attention. The write
side is four statements that look almost interchangeable, and the differences
between them are mostly documented as one-line remarks in the `source` sub-pages
that nobody opens.

Every trap below is a **data-correctness** bug, not a performance one. None of
them raises a syntax error. Most of them leave `sy-subrc = 0`.

---

## 1. `UPDATE ... FROM @wa` overwrites **every** column, including the ones you never set

This is the single most expensive habit in the list, because it looks like a
targeted change and is actually a whole-row replacement.

```abap
DATA wa TYPE scustom.
wa-id       = '00017777'.
wa-discount = '003'.

UPDATE scustom FROM @wa.        " name, city, telephone, email ... all blanked
```

The documented rule is explicit: *"The content of the work area is assigned to
the rows found. The assignment takes place without conversion, from left to
right according to the structure of the DDIC database table or the view."*
Left to right, **all** of it. The fields you did not fill are not "left alone" —
they are written as initial values.

The bug survives review because the statement *reads* like "update this customer's
discount". It usually reaches production via a partially filled work area handed
in by a caller, or a `VALUE #( )` host expression that lists three fields.

**Three correct ways to change some columns:**

```abap
" (a) SET - name exactly what changes. The clearest option.
UPDATE scustom SET discount = '003' WHERE id = '00017777'.

" (b) read-modify-write - BASE keeps every other column
SELECT SINGLE * FROM scustom WHERE id = '00017777' INTO @FINAL(old).
UPDATE scustom FROM @( VALUE #( BASE old discount = '003' ) ).

" (c) set indicators - mass update of selected columns only
```

Option (b) is not free: between the `SELECT` and the `UPDATE` another user can
change the row, and you will write your stale copy of every other column back
over their change. That is a lost update, and the fix is an
[enqueue lock](../Enqueue%20Locks#readme) around the pair — not a tighter `WHERE`.

### Set indicators — the mass-update form of `SET`

`SET` cannot be used with `FROM TABLE`, so for a bulk update of two columns
across 10,000 rows the choice used to be "overwrite everything" or "loop".
`INDICATORS` is the third option:

```abap
TYPES ind_wa TYPE scustom WITH INDICATORS col_ind TYPE abap_boolean.
DATA  ind_tab TYPE TABLE OF ind_wa.

ind_tab = VALUE #( ( id = '00017777' discount = '003'
                     col_ind-discount = abap_true ) ).

UPDATE scustom FROM TABLE @ind_tab INDICATORS SET STRUCTURE col_ind.
```

Rules worth knowing before reaching for it:

- `set_ind` must be the **last** component of the work area / row type, with one
  component per column of the target, each `c LENGTH 1` or `x LENGTH 1`.
- Only `'X'` (or hex `1`) marks a field for update. **Any other value means
  "do not update"** — so a `space`, a `'x'`, or a stray `'Y'` is silently a no-op
  rather than an error.
- `INDICATORS NOT SET` inverts the logic: update everything *except* the marked
  fields.
- Key fields must be present in the indicator structure but the indicators have
  no effect on them.
- `BITFIELD` (valid for `SELECT ... INDICATORS`) is **not** allowed here.
- Set indicators enforce strict syntax-check mode from release 7.81.

---

## 2. `INSERT ... FROM TABLE` without `ACCEPTING DUPLICATE KEYS` can roll back work you already did in the LUW

The duplicate-key behaviour of `INSERT FROM TABLE` has three outcomes, and only
one of them is safe:

| Situation | Result |
|---|---|
| `ACCEPTING DUPLICATE KEYS` given | Every insertable row is inserted, duplicates discarded, `sy-subrc = 4`, `sy-dbcnt` = rows inserted |
| No addition, `CX_SY_OPEN_SQL_DB` **caught** | *"Rows continue to be inserted until the exception is raised."* The number of inserted rows is **undefined**; `sy-subrc` and `sy-dbcnt` **keep their previous values** |
| No addition, exception **not caught** | Runtime error → **database rollback undoing all changes in the current database LUW**, including rows inserted before the duplicate |

The middle row is the nasty one. After catching `CX_SY_OPEN_SQL_DB` you are
sitting on a partially written table with no way to find out how far it got —
the doc says outright that the count is undefined, and `sy-dbcnt` is stale, not
zero. The documentation's own guidance: *"If the runtime error ... is prevented
by handling an exception instead of using the addition `ACCEPTING DUPLICATE
KEYS`, a database rollback must be initiated explicitly, if required."*

The third row is worse than it looks in any program doing several writes: the
rollback is not scoped to your `INSERT`, it is the whole database LUW.

```abap
INSERT ztable FROM TABLE @itab ACCEPTING DUPLICATE KEYS.
IF sy-subrc = 4.
  " some rows were skipped; sy-dbcnt says how many DID go in
ENDIF.
```

Note what `ACCEPTING DUPLICATE KEYS` does **not** do: it does not merge or update
the existing row. *"No change is made to an existing entry as is the case when
`MODIFY` is used."* It only suppresses the exception. If you actually want
upsert semantics, that is `MODIFY` — with the caveat in §3.

---

## 3. `MODIFY ... FROM TABLE` is platform-dependent when the table has a unique secondary index

`MODIFY` is the upsert: existing key → behaves like `UPDATE`, missing key →
behaves like `INSERT`. For a single work area that is well defined. For
`FROM TABLE` it is **not**, and the doc names both implementations:

- **`UPDATE` followed by `INSERT`** — one `UPDATE FROM TABLE` pass over all rows,
  then one `INSERT FROM TABLE` pass, with duplicates ignored.
- **Row-by-row `MODIFY`** — a loop, each row handled individually.

These *"can produce different results in cases where the DDIC database table has
unique secondary indexes"*, and the database system decides which one you get.
The processing can also be split into blocks per database.

The documentation's recommendation is a design rule, not a tuning hint:

> To prevent platform-dependent behavior, `MODIFY ... FROM itab` should only be
> applied to DDIC database tables without unique secondary indexes. If not, the
> required behavior must be programmed explicitly using `UPDATE` and `INSERT` or
> using `LOOP AT itab` and `MODIFY`.

So a table that works fine today acquires nondeterministic write behaviour the
day someone adds a unique index to it — with no change to your code and no
syntax warning.

**Also note the name collision:** `MODIFY dbtab FROM wa` and
`MODIFY itab FROM wa` are *the same syntax*. If an internal table has the same
name as the database table, the statement silently accesses the **internal
table**. The same trap exists for the `DELETE FROM` form. This is the real
argument for never naming an internal table after the table it holds.

---

## 4. `sy-subrc = 4` after a `FROM TABLE` write does not mean "nothing happened"

For `UPDATE FROM TABLE` the doc spells it out:

> If `sy-subrc` contains the value 4 after the statement has been executed, this
> does not mean that no rows were changed. It simply means that not all of the
> rows in the internal table could be respected.

`UPDATE FROM TABLE` *"changes all rows for which this is possible"* and continues
past the ones it cannot. So the common cleanup pattern is wrong in both
directions:

```abap
UPDATE ztable FROM TABLE @itab.
IF sy-subrc <> 0.
  ROLLBACK WORK.      " rolls back the rows that DID succeed, plus everything
ENDIF.                " else in this LUW
```

`sy-dbcnt` is the field that carries the information — it holds the number of
rows actually processed. Compare it against `lines( itab )` to find out whether
the write was complete.

**The empty-table asymmetry.** For all four statements with `FROM TABLE`, an
**empty** internal table gives `sy-subrc = 0` with `sy-dbcnt = 0`. Nothing was
written, and the return code says success. A guard on `sy-subrc` will not catch
"the driver table came out empty" — the same shape as the empty-driver trap in
[FOR ALL ENTRIES](../For%20All%20Entries#readme).

---

## 5. A forgotten `WHERE` on the delete statement empties the whole client

```abap
DELETE FROM ztable.                  " every row in the current client
DELETE FROM ztable WHERE id = @id.   " what was meant
```

There is no syntax error, no confirmation, and no `UP TO n ROWS` safety net
unless you write one. The `WHERE` clause is genuinely optional in the syntax
diagram. This is worth a second look in any code review because the two
statements differ by one line fragment.

`sy-subrc = 4` here means *"no row was deleted ... since the database table was
already empty"* — the "condition matched nothing" case and the "table was
already empty" case collapse into the same return code.

---

## 6. Things all four statements share

**They take exclusive database locks until the next commit or rollback.** The
doc attaches the same warning to all four: *"If used incorrectly, this can
produce a deadlock."* An ABAP SQL write is not an SAP enqueue lock — it does not
protect against a second user reading the old value and writing it back. That is
what [SAP enqueue locks](../Enqueue%20Locks#readme) are for; the two mechanisms
are complementary, not alternatives.

**The row count per LUW is database-limited.** *"The number of rows that can be
inserted into the tables of a database within a database LUW is limited on a
database-dependent level, since a database system can only manage a limited
amount of locks and data in the rollback area."* Another reason mass writes are
chunked — see [Mass Data Processing](../Mass%20Data%20Processing#readme).

**`sy-dbcnt` overflows to -1** above 2,147,483,647 rows, and is also set to -1
(meaning undefined) whenever `sy-subrc` is 2 (LOB writer streams).

**Client handling is implicit and your client field is ignored.** A client ID
filled in the work area is discarded and the current client is used, unless
`USING CLIENT` or `CLIENT SPECIFIED` is given. Setting `mandt` in a work area
and expecting a cross-client write is a silent no-op.

**`INSERT`/`UPDATE` cannot be applied to `TRDIR`**, and rows written into a
global temporary table must be cleared before the next implicit commit or you
get `COMMIT_GTT_ERROR`.

---

## 7. `INSERT ... FROM ( SELECT ... )` — different rules from `FROM TABLE`

The subquery form pushes the whole operation into the database and is documented
as faster than `SELECT` into an internal table followed by `INSERT`. Its
behaviour differs in ways that matter:

- Columns are matched **by position, not by name**. *"The columns names in the
  result set are not important for assignment purposes."* Reordering the
  `SELECT` list silently writes values into the wrong columns.
- On a duplicate key, *"all previously inserted rows are discarded"* and
  `CX_SY_OPEN_SQL_DB` is raised — unlike the internal-table form, the state
  after the exception **is** well defined.
- `sy-subrc = 4` means the result set was empty.
- **It cannot be used on a table with logging enabled** — uncatchable
  `DBSQL_DBPRT_STATEMENT`. Guard with `cl_dbi_utilities=>is_logging_on( )` and
  keep an internal-table fallback path.
- Null values are never inserted: non-key columns get the initial value, key
  columns raise `CX_SY_OPEN_SQL_DB`. See [Null Values](../Null%20Values#readme).
- `MODIFY ... FROM ( SELECT ... )` is not supported by every database —
  check `cl_abap_dbfeatures=>modify_from_select`, or catch
  `CX_SY_SQL_UNSUPPORTED_FEATURE`.

---

## Quick reference

| Want | Use | Watch out for |
|---|---|---|
| Change specific columns, one row or by condition | `UPDATE ... SET ... WHERE` | Nothing — this is the safe form |
| Change specific columns, many rows | `UPDATE ... FROM TABLE ... INDICATORS SET STRUCTURE` | Indicator must be last component; only `'X'`/hex `1` counts |
| Replace a whole row | `UPDATE ... FROM @wa` | Blanks every unfilled column |
| Insert only, fail loudly on duplicates | `INSERT ... FROM TABLE` + `TRY`/`CATCH` | Undefined row count after the exception; roll back explicitly |
| Insert only, skip duplicates | `INSERT ... FROM TABLE ACCEPTING DUPLICATE KEYS` | Does *not* update existing rows |
| Upsert | `MODIFY ... FROM TABLE` | Platform-dependent if a unique secondary index exists |
| Bulk copy inside the DB | `INSERT ... FROM ( SELECT ... )` | Positional column mapping; forbidden on logged tables |

---

## Demo program

[`ydj_sql_write_demo.abap`](./ydj_sql_write_demo.abap) — a **read-only**
walkthrough. It performs no database writes at all: the write statements are
shown as commented-out code with the expected outcome next to each, and the
runnable parts demonstrate the indicator structure layout, the `BASE` work-area
pattern and the `sy-dbcnt` vs `sy-subrc` arithmetic against the standard demo
tables.

---

## Sources

- [INSERT dbtab](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINSERT_DBTAB.html) · [INSERT dbtab, source](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINSERT_SOURCE.html)
- [UPDATE dbtab](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPUPDATE.html) · [UPDATE dbtab, source](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPUPDATE_SOURCE.html) · [UPDATE, set indicators](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPUPDATE_SET_INDICATOR.html)
- [MODIFY dbtab](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMODIFY_DBTAB.html) · [MODIFY dbtab, source](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMODIFY_SOURCE.html)
- [DELETE dbtab](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPDELETE_DBTAB.html)
- [TYPES, INDICATORS](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPTYPES_INDICATORS.html)
