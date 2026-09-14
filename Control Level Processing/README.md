# Control Level Processing — AT NEW / AT END OF, SUM, and the ON CHANGE OF trap

`AT NEW` / `AT END OF` inside a `LOOP` are the classic way to print group headers
and subtotals. Four of their behaviours are documented, correct, and almost never
what the code around them assumes — and the "simpler" alternative, `ON CHANGE OF`,
is worse than its reputation.

## The prerequisite nobody enforces

Group levels are derived from the **order of the components in the line type** and
the **processing order of the loop**. The table must be sorted first by its first
component, then by its second, and so on. Nothing checks this: an unsorted table
just gives you the same group key breaking several times, with no error.

Two more silent restrictions from the keyword docs:

- The internal table **must not be modified** inside the loop.
- The work area after `INTO` must be **compatible** with the line type (not merely
  convertible), and **its content must not be modified** inside the loop.
- `STEP` is not allowed, and `AT` cannot be combined with `LOOP ... GROUP BY`
  (including `LOOP AT GROUP` member loops) at all.

## Trap 1: the group key is positional, not the field you named

`AT NEW connid` does **not** mean "when connid changes". The group key is `connid`
**plus every component to its left** in the line type. For a line type
`carrid, connid, fldate, ...` that is `carrid` *and* `connid`.

The consequence worth remembering: **moving a field in the structure silently
changes what every `AT` statement in the program means.** A new field inserted
before `connid` joins the group key of every `AT NEW connid` in the codebase, with
no syntax error and no warning.

For an elementary line type the only thing you can name is `table_line`.

## Trap 2: everything right of the group key becomes `*`

> "All components with a character-like flat data type on the right of the current
> control key are set to the character `*` in every place. All the other components
> to the right of the current group key are set to their initial value."
> — [ABAP keyword documentation, AT, Group Level Processing](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPAT_ITAB.html)

So inside `AT NEW carrid`, a `connid` of type `n` reads `****`, a date reads
`00000000`, and a quantity reads `0`. This is the "why is my report full of stars"
bug. The components of the group key itself are untouched, and on leaving the block
the real row content is restored.

`AT FIRST` and `AT LAST` are the extreme case: their group key contains **no**
components, so the *entire* work area is `*`-filled / initialised.

## Trap 3: `INTO` and `ASSIGNING` behave differently

The `*` filling only happens with `INTO wa`. With `ASSIGNING <fs>` or
`REFERENCE INTO`, the referenced table row is not touched on entering or leaving the
`AT` block — so the same `AT` block prints real values under one loop form and stars
under the other.

And `SUM` is not merely useless with `ASSIGNING`, it is a runtime error:
`SUM_NO_ASSIGNING`.

## Trap 4: a `WHERE` condition suppresses the break, not the group

Group levels are computed over **all** rows of the table, ignoring the restricting
condition. But the `AT` block only runs if the row carrying the break is actually
read. Filter out the first row of a group and its `AT NEW` never fires; filter out
the last and the `AT END OF` subtotal never prints — while the rest of the group is
processed normally. The extended syntax check (SLIN) warns about this; the compiler
does not. Filter before the loop, or use `GROUP BY`.

## `SUM` — what it actually totals

| Where | What `SUM` puts in `wa` |
|---|---|
| `AT NEW compi` / `AT END OF compi` | Sum of the numeric components **right of the group key**, over the rows of that group |
| `AT FIRST` / `AT LAST` / outside any `AT` | Sum of **all** numeric components over **all** rows of the table |
| Elementary numeric line type, outside `AT` | Sum of all line values |

Requirements and failure modes: needs `LOOP ... INTO wa` with a compatible `wa`;
forbidden if the line type contains table-typed components; raises
`CX_SY_ARITHMETIC_OVERFLOW` / dumps `SUM_OVERFLOW` if the target component is too
small for the total — a real risk when the field is a 4-byte `i` and the group is
large.

## `ON CHANGE OF`: a global variable you cannot reach

`ON CHANGE OF` is not control level processing and is **forbidden inside classes**.
That restriction is the tell:

> "Each time the statement `ON CHANGE OF` is executed, the content of all the
> specified data objects is stored in an internal helper variable that is global to
> the program. This helper variable is linked to this statement and cannot be
> accessed in the program. The helper variables and their content are preserved
> longer than the lifetime of procedures."
> — [ABAP keyword documentation, ON CHANGE OF](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPON.html)

Three consequences:

- **It does not reset between passes.** Run the same subroutine or the same inner
  loop a second time and the helper still holds the last value from the first pass,
  so the first row of the new pass is silently skipped. In nested loops this eats
  one row per outer iteration.
- **The first execution fires only if the value is non-initial.** A first group whose
  key is blank or zero produces nothing.
- **You cannot `CLEAR` it.** The variable is not addressable. The only fix is a
  helper variable you declared yourself:

```abap
" Instead of ON CHANGE OF spfli_wa-carrid ... ENDON:
DATA carrid_buffer TYPE spfli-carrid.
CLEAR carrid_buffer.
...
IF spfli_wa-carrid <> carrid_buffer.
  carrid_buffer = spfli_wa-carrid.
  ...
ENDIF.
```

The keyword documentation says it plainly: this control structure "is particularly
prone to errors and should be replaced by branches with explicitly declared helper
variables."

## When to use `GROUP BY` instead

Since 7.40, `LOOP AT ... GROUP BY` does the same job without depending on component
order or on the table being pre-sorted, and SAP recommends it where available. Use
`AT` when you need `SUM`'s automatic totalling or you are maintaining classic report
code; use `GROUP BY` for anything new. See
[NewABAPQuickReference.abap](../NewABAPQuickReference.abap) for the `GROUP BY` form.

Dynamic component names behind `AT` use `AT NEW (name).` — the older
`AT NEW <fs>.` field-symbol form is obsolete.

Worked, runnable examples: [ydj_control_level_demo.abap](ydj_control_level_demo.abap)

---

**References**

- [ABAP keyword docs — AT, Group Level Processing](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPAT_ITAB.html)
- [ABAP keyword docs — SUM](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSUM.html)
- [ABAP keyword docs — ON CHANGE OF](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPON.html)
- [ABAP keyword docs — AT field_symbol (obsolete dynamic form)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPAT_ITAB_OBSOLETE.html)
- [SAP Community — 'ON CHANGE OF' vs 'AT'](https://community.sap.com/t5/application-development-and-automation-discussions/on-change-of-vs-at/m-p/1462626)
