# Modifying an Internal Table Inside Its Own `LOOP` — The Rules Nobody Reads

Inserting or deleting lines of a table while looping over that same table is
something every ABAP developer does, usually without thinking about it. The
behaviour is fully documented and completely deterministic — it just isn't what
the code around it assumes.

This note is about the *loop bookkeeping*: which lines get visited, what
`sy-tabix` means afterwards, and where the line between "allowed" and "dump"
actually sits. The field-symbol lifetime rules that apply *inside* a loop
(`ASSIGNING` being locked, the deleted current row, references going stale) are
covered separately in [Field Symbols](../Field%20Symbols#readme).

Runnable demo: [`ydj_loop_modify_demo.abap`](ydj_loop_modify_demo.abap).

## The four documented rules

Straight from the keyword documentation for `LOOP AT itab`, for index tables and
sorted keys (for hashed tables and hash keys the position depends on insertion
sequence instead of the index):

| What you do inside the loop | What happens |
|---|---|
| Insert lines **after** the current line | They **are** processed in later passes. "An endless loop can result." |
| Delete lines **after** the current line | They are no longer processed. |
| Insert lines **before** the current line | The internal loop counter is **increased by one per line**, and so is `sy-tabix` in the next pass. |
| Delete the current line, or lines **before** it | The internal loop counter is **decreased by one per line**, and so is `sy-tabix` in the next pass. |

Two of these are silent correctness bugs and one is a hang. None of them produce
a warning.

## Trap 1: appending to the table you are looping over never terminates

```abap
LOOP AT lt_rows INTO DATA(ls_row).
  IF needs_split( ls_row ).
    APPEND derive_extra_row( ls_row ) TO lt_rows.   " <-- after the current line
  ENDIF.
ENDLOOP.
```

`APPEND` puts the new line at the end, which is after the current line, which
means the loop will reach it. If the new line also satisfies `needs_split( )`,
the loop generates its own work forever — and it does so while growing the table,
so the symptom is usually `TSV_TNEW_PAGE_ALLOC_FAILED` (memory) rather than a
clean hang, in a job that ran fine on test data where the condition happened to
be false for the derived rows.

The fix is always the same shape: collect into a second table, merge after
`ENDLOOP`.

```abap
DATA lt_extra LIKE lt_rows.

LOOP AT lt_rows INTO DATA(ls_row).
  IF needs_split( ls_row ).
    APPEND derive_extra_row( ls_row ) TO lt_extra.
  ENDIF.
ENDLOOP.

APPEND LINES OF lt_extra TO lt_rows.
```

## Trap 2: delete-as-you-go — and the folklore about it

```abap
LOOP AT lt_rows INTO DATA(ls_row).
  process( ls_row ).
  DELETE lt_rows INDEX sy-tabix.   " "clean up as I go"
ENDLOOP.
```

You will be told, often and confidently, that this skips every other line. **It
does not.** Deleting the current line is covered by the fourth documented rule —
the internal loop counter is *decreased by one* — so the line that moves down into
the vacated index is exactly the line read next. The loop visits all five rows.

The folklore is real, it is just about a different loop. Hand-rolled index
iteration has no loop counter for the runtime to adjust:

```abap
lv_idx = 1.
DO.
  READ TABLE lt_rows INTO ls_row INDEX lv_idx.
  IF sy-subrc <> 0. EXIT. ENDIF.
  process( ls_row ).
  DELETE lt_rows INDEX lv_idx.
  lv_idx = lv_idx + 1.          " <-- nothing decremented this
ENDDO.
```

Here the deleted line's successor slides into `lv_idx`, and `lv_idx` is then
incremented straight past it. *This* is the every-other-line bug, and it is the
version that gets misattributed to `LOOP`. The demo runs both and prints the
visited ids side by side.

Neither is worth relying on. Deletion inside a loop makes the pass count, the
line numbers and `sy-tabix` all depend on rules most readers of the code will not
know. Fixes, in order of preference:

- `DELETE lt_rows WHERE <condition>.` **after** the loop — one statement, no
  bookkeeping.
- Mark rows in the loop (`ASSIGNING` + set a flag), delete by flag afterwards.
- If you must delete inside the loop, `CONTINUE` immediately afterwards — see
  [Field Symbols](../Field%20Symbols#readme), because after a `DELETE` of the
  current line an `ASSIGNING` field symbol is left unassigned for the rest of
  that pass.

## Trap 3: `sy-tabix` after a modification is not the number you reasoned about

`sy-tabix` is a position in the table *as it is right now*, not an identity. Once
any line before the current one has been deleted, every `sy-tabix` from that
point on is offset from the value the code was written against. Code that stashes
`sy-tabix` in one pass and uses it as an index in a later pass — a very common
shape in report code that wants to "go back and fix that line" — is reading a
different line than intended.

Related, and worth stating because it reads like an oversight: `DELETE itab` does
**not set `sy-tabix` at all**, so a read of `sy-tabix` straight after a `DELETE`
returns a stale value from an earlier statement. (Documented on `DELETE itab`,
same page as the `sy-subrc` table; see also
[Sorting & Deduplication](../Sorting%20and%20Deduplication#readme).)

`LOOP AT` itself does not modify `sy-subrc` during the loop — it is set only at
`ENDLOOP`: `0` if at least one pass ran, `4` if none did. And `sy-tabix` is
restored at `ENDLOOP` to whatever it was before the loop was entered.

## Trap 4: `FROM idx1` is read once, `TO idx2` is read every pass

An asymmetry with no hint in the syntax:

> "The value of `idx1` is evaluated once when the loop is entered. Any changes to
> `idx1` during loop processing are ignored. In contrast, the value of `idx2` is
> evaluated in each loop pass and any changes made to `idx2` during loop
> processing are respected."

So `LOOP AT itab FROM lv_from TO lv_to.` with both variables reassigned inside
the loop honours exactly one of the two reassignments.

The documentation's own consequence is sharper: because the end of the loop is
decided by comparing the *current* line number against `idx2`, inserting or
deleting lines changes the number of passes. Inserting lines can make the loop
run **fewer** times than `idx2 - idx1 + 1`; deleting lines can make it run
**more**. The bounds do not mean what they look like once the table is being
modified.

Also worth knowing about the bounds: `idx1 <= 0` is silently treated as `1`, and
`idx2 > lines( itab )` is silently clamped to the line count — neither is an
error, so a miscomputed bound produces a plausible result rather than a dump.

## Trap 5: the whole-body statements — dump, syntax error, or silent corruption

Anything that replaces the **entire table body** inside a loop over that table is
forbidden:

```abap
CLEAR lt_rows.  FREE lt_rows.  REFRESH lt_rows.
SORT lt_rows BY id.  DELETE lt_rows WHERE id > 3.
lt_rows = something.  SELECT ... INTO TABLE lt_rows.
```

Note what is on that list: `SORT` and `DELETE ... WHERE` are whole-body
operations. They are not "modify some lines", and they are not allowed here even
though single-line `DELETE ... INDEX` is.

Which failure you get depends on where the code lives:

- **Inside a class**, or on a `LOOP` with a statically known secondary key →
  **syntax error**. The compiler stops you.
- **Anywhere else** (classic report, function module, subroutine) → the syntax
  check only issues a **warning**, "for compatibility reasons", and it dumps at
  runtime with `TABLE_FREE_IN_LOOP`.
- **One legacy shape does neither**: per the documentation, a runtime error does
  *not* occur when the table is specified directly, without a secondary key, and
  the loop uses `INTO wa` — i.e. the oldest possible `LOOP AT itab INTO wa`. That
  case keeps running with "unpredictable program behavior" instead of failing.

That last bullet is the one to remember. The exact loop form most likely to
appear in 20-year-old report code is the one form that neither refuses to compile
nor dumps — it just produces wrong results. Moving such code into a class is
what finally surfaces it, which is why this shows up during ABAP Cloud / clean
core migrations rather than in production.

The SAP programming guideline states the rule flatly: **"Do not modify the entire
table body in a loop."**

## Smaller things worth knowing

- **The loop is bound to the table it started on.** If the table is reached
  through a reference variable or a field symbol, re-pointing that reference or
  field symbol inside the loop does not change what is being iterated — and the
  referenced object cannot be garbage collected until the loop ends.
- **Looping over an expression.** `LOOP AT VALUE #( ... )` / a method result /
  a table expression persists the value for the duration of the loop only; after
  `ENDLOOP` the table is gone, and so is every field symbol or reference into it.
- **Hashed tables and hash keys** have no index, so `sy-tabix` is `0` in every
  pass and the position of an inserted line follows insertion sequence. A
  preceding `SORT` changes the loop order for a hashed table's primary key but
  **not** for a secondary hash key.
- **A dynamic `WHERE (cond_syntax)` is not evaluated at all for an empty table**,
  so a malformed condition raises no exception when the table happens to be
  empty — the error surfaces only on the run that has data. An initial
  `cond_syntax` is *true*, not false (same trap as elsewhere in ABAP — see
  [Dynamic SQL](../Dynamic%20SQL#readme)).

## The safe pattern

1. Read in the loop. Modify single lines in the loop if you must.
2. Never `APPEND`/`INSERT` into the looped table — collect into a second table.
3. Never delete from the looped table — mark, then `DELETE ... WHERE` after
   `ENDLOOP`.
4. Never `CLEAR`/`SORT`/assign the looped table.
5. Treat `sy-tabix` as valid only in the pass that produced it.

## Sources

- [LOOP AT itab, Basic Form — ABAP keyword documentation (7.58)](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abaploop_at_itab.htm) — the insert/delete rules, the whole-body restriction, the `INTO wa` exception, the `sy-subrc`/`sy-tabix` behaviour and the uncatchable exceptions
- [LOOP AT itab, cond (7.58)](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abaploop_at_itab_cond.htm) — `FROM` once vs `TO` every pass, bound clamping, the pass-count hint, dynamic `WHERE` on an empty table
- [LOOP AT itab, result (7.58)](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abaploop_at_itab_result.htm) — output behaviour and the deleted-current-line rule
- [DELETE itab (7.58)](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapdelete_itab.htm) — `sy-tabix` is not set, memory not released
- [Loop Processing — ABAP programming guidelines (7.58)](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abenloop_guidl.htm) — the rule and the syntax-error-in-classes detail
