# Field Symbols & Data References — assignment state, not just performance

Field symbols get taught as "the fast way to loop", and then the interesting half
gets skipped: **a field symbol has a state**, that state survives statements that
look like they reset it, and the two statements that look like they clear it do
two completely different things.

Every trap below compiles, runs, and produces wrong data or a dump at runtime —
none of them is a syntax error.

## 1. A failed READ leaves the field symbol pointing at the *previous* row

This is the big one.

```abap
READ TABLE lt_flights ASSIGNING <fs> WITH KEY carrid = 'LH'.   " found
READ TABLE lt_flights ASSIGNING <fs> WITH KEY carrid = 'XX'.   " NOT found

IF <fs> IS ASSIGNED.     " <-- TRUE. And <fs> is still the LH row.
```

If no line is found, the field symbol **keeps its previous state**. `IS ASSIGNED`
is therefore useless as a "did the read work?" check — it answers a different
question. The correct check is `sy-subrc`:

```abap
READ TABLE lt_flights ASSIGNING <fs> WITH KEY carrid = 'XX'.
IF sy-subrc = 0.
  ...
ENDIF.
```

...or force the state to match reality with `ELSE UNASSIGN`, after which both
`sy-subrc` and `IS ASSIGNED` are safe:

```abap
READ TABLE lt_flights ASSIGNING <fs> WITH KEY carrid = 'XX' ELSE UNASSIGN.
```

> "If the addition `ELSE UNASSIGN` is not used, it is recommended that the return
> code `sy-subrc` is evaluated and that `IS ASSIGNED` is not used, since in case of
> an unsuccessful read, the field symbol keeps its previous state."
> — [READ TABLE, result](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPREAD_TABLE_OUTDESC.html)

Worth knowing for the inline-declaration case too: if the line type cannot be
determined statically, `READ TABLE ... ASSIGNING FIELD-SYMBOL(<fs>)` declares the
field symbol with the generic type `any` and **initially assigns it the constant
`space`** — so it is already "assigned" before the read ever runs.

## 2. Static ASSIGN does not set sy-subrc; dynamic ASSIGN does

A second reason not to reach for the wrong check.

| Form | On failure |
|---|---|
| `ASSIGN dobj TO <fs>.` (static) | `sy-subrc` **unchanged** — field symbol ends up unassigned (`ELSE UNASSIGN` is implicit and cannot be written) |
| `ASSIGN ('NAME') TO <fs>.` (dynamic) | `sy-subrc` = 4, field symbol **keeps its old assignment** unless `ELSE UNASSIGN` is given |
| `ASSIGN itab[ 1 ] TO <fs>.` (table expression) | `sy-subrc` = 0 / 8 — set, unlike other static forms |
| `ASSIGN dref->* TO <fs>.` with unbound `dref` | `sy-subrc` = 4; needs `ELSE UNASSIGN` to actually detach |

So after a *static* `ASSIGN` you check `IS ASSIGNED`, and after a *dynamic* one you
check `sy-subrc`. Getting that backwards is silently wrong in both directions.

```abap
DATA(hello) = `Hello world`.
ASSIGN ('HELLO') TO FIELD-SYMBOL(<eu>) ELSE UNASSIGN.
ASSERT sy-subrc = 0 AND <eu> IS ASSIGNED.

ASSIGN ('DOES_NOT_EXIST') TO <eu>.                    " no ELSE UNASSIGN
ASSERT sy-subrc = 4 AND <eu> IS ASSIGNED AND <eu> = `Hello world`.

ASSIGN ('DOES_NOT_EXIST') TO <eu> ELSE UNASSIGN.
ASSERT sy-subrc = 4 AND <eu> IS NOT ASSIGNED.
```

## 3. CLEAR <fs> does not clear the field symbol — it clears your table row

`CLEAR` and `UNASSIGN` read like synonyms and are opposites:

- `UNASSIGN <fs>.` — detaches the field symbol. `<fs> IS ASSIGNED` becomes false.
  The data object is untouched.
- `CLEAR <fs>.` — leaves the field symbol attached and **initializes the memory
  area it points to**.

Inside `LOOP AT itab ASSIGNING <fs>`, that memory area *is the current table line*.
A defensive-looking `CLEAR <fs>` at the top of the loop body blanks every row of
the table as it goes. The habit is harmless with `INTO wa` (it clears a copy) and
destructive with `ASSIGNING`, which is exactly why it survives a refactor from one
to the other.

`UNASSIGN` also has no effect on the garbage collector — unlike clearing a
reference variable, it never frees anything.

## 4. Inside a LOOP ... ASSIGNING, the field symbol is locked

```abap
LOOP AT itab ASSIGNING <fs>.
  ASSIGN other TO <fs>.   " not allowed
  UNASSIGN <fs>.          " not allowed
ENDLOOP.
```

No other memory area can be assigned to the field symbol within the loop, and the
assignment cannot be undone with `UNASSIGN`. Same rule for `REFERENCE INTO dref`:
the reference variable cannot be re-pointed or `CLEAR`ed inside its own loop.

Two related lifetime rules:

- **Delete the current row inside the loop** and the field symbol is left
  *unassigned* for the rest of that pass — touching it after the `DELETE` dumps
  with `GETWA_NOT_ASSIGNED`. Put a `CONTINUE` straight after the delete.
- **Loop over a table that is an expression** (functional method result,
  constructor expression, table expression) and every field symbol / reference
  into it becomes invalid when the loop ends — the table only exists for the
  duration of the loop. `READ TABLE ... ASSIGNING` isn't even allowed on such a
  table, because the value is already gone by the end of the statement.

Data references have the mirror-image problem: references into internal table
lines can become invalid when lines are deleted, so `IS BOUND` is worth checking
if the reference is not used immediately after it was obtained.

## 5. Modifying through a field symbol defers the secondary-key check

Writing to a table line through a field symbol bypasses the statements that
normally maintain the key administration:

- unique secondary keys — **delayed update**, on next access to the table
- non-unique secondary keys — **lazy update**, on next explicit use of that key

Between the write and that next access the table is inconsistent, and a duplicate
that violates a unique secondary key does not raise anything *at the assignment* —
it raises later, at some unrelated statement that happens to touch the table. Use
`CL_ABAP_ITAB_UTILITIES` to force the update where you can still handle it.

Primary key fields of sorted/hashed tables are simply read-only through the field
symbol (uncatchable exception on write). See
[Internal Table Keys](../Internal%20Table%20Keys#readme) for the key rules themselves.

## 6. ASSIGN checks access rights once, at the ASSIGN

Permission to access the assigned data object is checked **only at the position of
the `ASSIGN` statement**. The field symbol can then be passed anywhere and used to
read *and* write that memory — so a field symbol to a private or read-only
attribute, handed outside the class, is a hole in the encapsulation. Don't publish
them.

(Constants, read-only input parameters and immutable variables are the exception:
those can never be made modifiable by routing a field symbol at them.)

## Quick reference

| Want | Statement |
|---|---|
| Detach the field symbol | `UNASSIGN <fs>.` |
| Initialize the pointed-to data | `CLEAR <fs>.` |
| Did a `READ TABLE ... ASSIGNING` work? | `IF sy-subrc = 0.` — or add `ELSE UNASSIGN` |
| Did a dynamic `ASSIGN` work? | `IF sy-subrc = 0.` — add `ELSE UNASSIGN` to also fix the state |
| Did a static `ASSIGN` work? | `IF <fs> IS ASSIGNED.` (`sy-subrc` is not set) |
| Is a data reference still usable? | `IF dref IS BOUND.` |

## Sources

- [ABAP keyword documentation — ASSIGN](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPASSIGN.html)
- [ABAP keyword documentation — FIELD-SYMBOLS](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPFIELD-SYMBOLS.html)
- [ABAP keyword documentation — UNASSIGN](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPUNASSIGN.html)
- [ABAP keyword documentation — READ TABLE, result](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPREAD_TABLE_OUTDESC.html)
- [ABAP keyword documentation — LOOP AT itab, result](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPLOOP_AT_ITAB_RESULT.html)
- [SAP-samples/abap-cheat-sheets — Dynamic Programming](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/06_Dynamic_Programming.md)
