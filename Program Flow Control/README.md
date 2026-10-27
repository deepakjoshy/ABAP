# Program flow control — the `EXIT` that means two different things, the `CHECK` that is a double negative, and the `END-OF-SELECTION` that never runs

Five statements leave something early: `CONTINUE`, `EXIT`, `CHECK`, `RETURN`,
`STOP`. Two of them decide *what* they leave by looking at their surroundings.
They are not flagged, they are not warnings, and the surroundings are exactly
what a refactoring changes.

This is the whole note in one table. Everything after it is a consequence.

| Statement | Inside a loop | Outside a loop |
|---|---|---|
| `CONTINUE.` | next loop pass | **not allowed** — "may only be used in loops" |
| `EXIT.` | exits the loop | exits the **processing block** |
| `CHECK log_exp.` (false) | next loop pass | exits the **processing block** |
| `RETURN.` | exits the processing block | exits the processing block |
| `STOP.` | exits the event block and **raises `END-OF-SELECTION`** | same |

Only `RETURN` has one meaning. SAP says so itself, in a programming guideline
rather than a reference page, which is why it is easy to miss:

> "The statement `RETURN` is used to exit procedures and always has this effect. The behavior of the `EXIT` and `CHECK` statements (conditional exit), in contrast, is context- dependent: Within a loop, only the loop is exited; outside a loop, the surrounding procedure is exited. This ambiguity limits the legibility of source code. Therefore, `EXIT` and `CHECK` should only be used to exit loops, and `RETURN` only to exit procedures. Only `RETURN` enables you to exit a procedure in a loop context."

That last sentence is the operational one: **there is no way to leave a
procedure from inside a loop except `RETURN`.** `EXIT` cannot do it. No
labelled break exists.

---

## Trap 1: the same `EXIT` statement is a loop break or a `RETURN`, depending on where it sits

The two reference pages are separate pages for the same keyword.

> "If the `EXIT` statement is listed within a loop, it exits the loop by terminating the current loop pass. The program flow resumes after the closing statement of the loop."

> "If the statement `EXIT` is outside a loop, it immediately terminates the current processing block."

SAP's own example annotates the second case in a source comment, because
without the comment nobody can see it:

```abap
METHOD meth.
  LOOP AT itab INTO FINAL(wa).
    FIND char IN wa-col1 RESPECTING CASE.
    IF sy-subrc = 0.
      EXIT.
    ENDIF.
  ENDLOOP.
  FIND to_upper( char ) IN wa-col2 RESPECTING CASE.
  IF sy-subrc <> 0.
    EXIT.                   "works as RETURN here!
  ENDIF.
  ...
ENDMETHOD.
```

Two identical statements, eight lines apart, one breaks a loop and one returns
from the method. The documentation's own hint on the loop page is itself a
garbled sentence, which says something about how awkward the rule is to state:

> "Outside of a loop, the statement `EXIT` exits the current processing block (see `EXIT` - Processing Block). `EXIT`, however, it should only be used within loops."

**The failure mode is a refactoring, not a typo.** Write `EXIT` meaning "break
the loop", then later delete or restructure the enclosing loop — the statement
stays valid, stops breaking anything, and starts returning from the procedure.
Everything after it in that procedure silently stops running.

---

## Trap 2: "a loop" is a wider category than `DO` / `WHILE` / `LOOP AT`

Before trusting any `EXIT` or `CHECK`, you have to know whether it is inside a
loop, and the answer includes a construct most people read as a `SELECT`:

> "This section describes the loops defined using the following:"
>
> - "`DO` - `ENDDO`"
> - "`WHILE` - `ENDWHILE`"
>
> "Further keywords for defining loops are:"
>
> - "`LOOP` - `ENDLOOP`"
> - "`PROVIDE` - `ENDPROVIDE` for loops across internal tables"
> - "`SELECT` - `ENDSELECT` for loops across the result set of a database access."

Combine that with Trap 1 and the consequence is direct: inside
`SELECT ... ENDSELECT`, a bare `EXIT` leaves the `SELECT`, not the method, and
a bare `CHECK` skips one database row instead of aborting the procedure.

This makes one of the most routine modernisations dangerous:

```abap
" before - EXIT breaks the SELECT loop
SELECT * FROM spfli INTO @DATA(ls_old).
  IF ls_old-cityfrom = 'FRANKFURT'. EXIT. ENDIF.
ENDSELECT.

" after - the loop is gone, so the SAME statement now returns from the method
SELECT * FROM spfli INTO TABLE @DATA(lt_new).
IF lt_new IS INITIAL. EXIT. ENDIF.   " <- no longer a loop break
```

Replacing `SELECT ... ENDSELECT` with `SELECT ... INTO TABLE` is standard
HANA-era cleanup. Any `EXIT` or `CHECK` whose enclosing loop disappears in that
edit changes meaning with no syntax error, and nothing in the diff that looks
like a behaviour change.

---

## Trap 3: `CHECK` exits when the expression is **false**

`CHECK` is the only one of the five whose condition is inverted, which forces a
double negative on every guard clause. SAP files this under **Bad Example**:

> "The following source code shows how a method is left early with a `CHECK` statement, whose meaning cannot be identified by simply looking at it. You have to know that `CHECK` exits the procedure if the following logical expression is false, which is why a double negation is necessary here."

```abap
METHOD some_method.
   ...
   CHECK is_finished = abap_false.    " SAP's bad example
   ...
ENDMETHOD.
```

The documented equivalences are worth memorising in both directions, because
they are different statements:

> "In a procedure (a method, function module, or subroutine), `CHECK log_exp` works outside a loop in the same way as: `IF NOT log_exp. RETURN. ENDIF.`"

> "Within a loop, `CHECK log_exp` has the same effect as: `IF NOT log_exp. CONTINUE. ENDIF.`"

So one keyword, one condition, and the body expands to `RETURN` or `CONTINUE`
depending on nesting.

There is exactly one place the guideline still allows it, and the carve-out is
narrow:

> "An exception to the rule to only use `RETURN` to exit procedures are `CHECK` statements that are located at the beginning of a procedure and that check the prerequisites for the execution of the procedure there. Using the `CHECK` statement in such a way does not impair the legibility and is thus allowed. However, this exception does not apply to other positions within a procedure and outside loops."

A `CHECK` on the first line of a method is fine. The same `CHECK` two hundred
lines down is not.

---

## Trap 4: the early exit still hands your caller the half-filled output

A guard clause feels like "nothing happened". It is not:

> "Exiting a procedure using `RETURN`, `EXIT` or `CHECK` is the error-free termination of the procedure. Formal parameters for which the pass by value is defined are not passed to the assigned actual parameters only if the procedure terminates after an error (an exception is raised or a message is sent)."

> "These statements end a procedure properly, that is, the system passes output parameters for which passing by value is specified and returns values to the assigned actual parameters."

Read the first quote carefully — the *only* case where a by-value output is
withheld is an exception or a message. A plain `RETURN` is an **error-free**
termination, so whatever the `EXPORTING` parameter contains at that moment is
delivered. Bail out after half-filling a result table and the caller receives
the half-filled table, not its own previous value.

This is the mirror image of the trap in
[Parameter Passing](../Parameter%20Passing#readme): outputs are initialized at
procedure *start*, and delivered at procedure *end*, including an early one.
If "nothing happened" has to mean "the caller's variable is untouched", raise
an exception — do not `RETURN`.

---

## Trap 5: in a report, `RETURN`/`EXIT` skip `END-OF-SELECTION`; `STOP` runs it

Three statements, three different effects on the surrounding event sequence.

> "After the reporting event block `START-OF-SELECTION` is terminated using `RETURN`, the runtime framework does not raise any more reporting events and instead calls the list processor directly to display the basic list."

> "After the reporting event blocks `START-OF-SELECTION` and `GET` have been terminated using `EXIT`, the runtime framework does not raise any more reporting events and instead calls the list processor directly to display the basic list."

> "These event blocks are exited immediately using `STOP` and the runtime framework raises the event `END-OF-SELECTION`."

| Leaving `START-OF-SELECTION` with | Further reporting events | `END-OF-SELECTION` runs |
|---|---|---|
| reaching its end | yes | yes |
| `RETURN` | no | **no** |
| `EXIT` | no | **no** |
| `STOP` | — | **yes, deliberately** |

So any summary, totals line, log flush or `COMMIT WORK` parked in
`END-OF-SELECTION` is silently skipped by an early `RETURN` upstream. `STOP`
exists precisely to get there, and that is the only reason to use it.

**A documented asymmetry, flagged rather than resolved.** The `EXIT` and
`RETURN` pages both list `START-OF-SELECTION` among the event blocks whose
regular-exit behaviour does not apply. The `CHECK` page lists only
`LOAD-OF-PROGRAM` and `GET` — `START-OF-SELECTION` is absent. Taken literally
that means `CHECK` outside a loop in `START-OF-SELECTION` exits *regularly* and
`END-OF-SELECTION` still runs, unlike `EXIT`. I have not tested this and would
not build on it; the safe reading is that the difference between these three
statements in event blocks is not something to encode in application logic.

All three pages agree on one absolute:

> "The event block `LOAD-OF-PROGRAM` cannot be exited using `EXIT`."

With the keyword swapped, the same sentence appears on the `RETURN` page and on
the `CHECK` page.

---

## Trap 6: `STOP` is forbidden in methods and dumps uncatchably

`STOP` is not a general-purpose "stop here".

> "The statement `STOP` is only to be used in executable programs and in the following event blocks:"
>
> - "`AT SELECTION-SCREEN` (without additions)"
> - "`START-OF-SELECTION`"
> - "`GET`"

> "The statement `STOP` is forbidden in methods and raises a uncatchable exception when processing dynpros called using `CALL SCREEN`, during a `LOAD-OF-PROGRAM` event, and in programs not called using `SUBMIT`."

The two documented runtime errors, with the documentation's own causes:

| Runtime error | Cause (verbatim) |
|---|---|
| `STOP_NO_REPORT` | "The statement `STOP` was executed outside the process flow for an executable program." |
| `STOP_WITHIN_CALLED_DYNPRO` | "The statement `STOP` was executed during the process flow for a dynpro and therefore outside the allowed events." |

Uncatchable means no `TRY`/`CATCH` saves it. Moving report logic into a class —
again, routine modernisation — turns a working `STOP` into a short dump, and
the trigger is the *call context*, so it may well pass in the report and fail
only once something else calls the method.

---

## Trap 7: `DO n TIMES` reads `n` once, and `n <= 0` runs zero passes

> "The numeric value of n when entering the loop determines the maximum number of times the statement block is executed. The control structure ignores changes to the value n within the loop. If n contains a value less than or equal to 0, the statement block is not executed."

Three separate bugs live in that sentence:

1. **Recomputing the bound inside the loop does nothing.** `DO lv_count TIMES.`
   followed by `lv_count = lines( lt_tab ).` inside the body is a no-op for the
   loop count. It reads like a dynamic bound; it is a snapshot.
2. **`n = 0` runs zero times, silently.** Not once, not endlessly, and not a
   syntax error — so an unfilled or unset counter turns the whole block into
   dead code with no evidence anywhere.
3. **A negative `n` behaves like zero**, so a subtraction that went the wrong
   way also just skips the work.

Dropping `n TIMES` entirely is the opposite failure:

> "If the addition `n TIMES` is not specified, the loop has to be terminated by a statement; otherwise it is executed endlessly. A maximum runtime can be configured using the profile parameters `rdisp/scheduler/prio_low/max_runtime`, `rdisp/scheduler/prio_normal/max_runtime`, and `rdisp/scheduler/prio_high/max_runtime`. If this is exceeded, the program is terminated by the runtime framework."

`WHILE` carries the identical note. The runaway `DO.` is therefore bounded by a
*profile parameter*, not by anything in your code — which means it behaves
differently in dialog and in background, and the fix is never "wait for it".

---

## Trap 8: `sy-index` and `sy-tabix` are different fields for different loops

> "Within the statement block, the system field sy-index contains the number of previous loop passes, including the current pass. In nested loops, sy-index always refers to the current loop."

(`DO` and `WHILE` both carry this sentence.) `LOOP AT` does not set it:

> "The lines are read by ascending line numbers in the primary table index. In each loop pass, the system field `sy-tabix` contains the line number of the current line in the primary table index."

> "The lines are processed in the order in which they were inserted into the table... In each loop pass, the system field `sy-tabix` contains the value 0."

| Loop | Counter field | Caveat |
|---|---|---|
| `DO` / `WHILE` | `sy-index` | refers to the **current** loop only |
| `LOOP AT` standard / sorted | `sy-tabix` | primary-index line number |
| `LOOP AT` **hashed** | `sy-tabix` | **always 0** — no index exists |
| `SELECT ... ENDSELECT` | not either of these | none of the pages cited below documents a pass counter for it — keep your own |

Two consequences. A progress counter written as `sy-tabix` over a hashed table
prints zero on every pass — that one is stated outright on the `LOOP AT` page.

The second is a reading rather than a quote, so treat it as such: because
`sy-index` "always refers to the current loop", a value read *after* an inner
`ENDDO` should belong to the outer loop again. The documentation says what
`sy-index` means inside a loop; it does not spell out the value immediately
after a nested `ENDDO`, and I have no system to test it on. The accompanying
demo prints the outer counter, the last inner counter and the value after
`ENDDO` side by side so you can confirm it on yours. Either way the safe habit
is the same: if you need the inner count afterwards, copy it into a variable
before `ENDDO`.

---

## Trap 9: statements that exit the *program* are illegal exactly where you test

> "The statements for exiting programs are not recommended inside procedures. They are not allowed in contexts like unit tests or during update and lead to exceptions if a procedure is called from such a context."

So a `LEAVE PROGRAM` buried in a utility method does not merely end the
program — it makes that method **impossible to unit test** and illegal in the
update task. Compare [AUnits](../AUnits#readme) and
[Update Task](../Update%20Task#readme), which hit the same restriction from the
other side.

And a quieter group: statements that end the processing block without looking
like it.

> "In addition to the statements described here, statements that call other units without returning to the caller after the call is made, also terminate their processing block. These include:"
>
> - "`LEAVE [TO] SCREEN`"
> - "`LEAVE LIST-PROCESSING`"
> - "`LEAVE TO TRANSACTION`"
> - "`SUBMIT` without `AND RETURN`"

> "Messages and raised exceptions can also exit processing blocks."

`SUBMIT` without `AND RETURN` is the one that catches people: it reads like a
call, so the lines after it look reachable. They are not. See
[Program Calls](../Program%20Calls#readme) for what else that statement
changes, and [MESSAGE](../Messages#readme) for the message half.

---

## Trap 10: the two obsolete ones, and why `REJECT` is still worth recognising

`CHECK SELECT-OPTIONS` and `REJECT` exist only for logical databases and are
flagged obsolete. One documented property of `REJECT` is genuinely surprising
and explains old code that looks broken:

> "The `REJECT` statement always refers to the current `GET` event, not to the location where it is specified. If a procedure is called in a `GET` event block, and the `REJECT` statement is executed there, the calling event block is affected."

A statement inside a called procedure that terminates an event block further up
the stack. Also:

> "`REJECT` is forbidden in methods."

And the documentation's own retirement note:

> "If logical databases are no longer used, it is no longer necessary to use the statement `REJECT`."

---

## One more context dependency: `RETURN expr`

In a functional method only, `RETURN` takes an operand:

> "The statement"
>
> `RETURN expr.`
>
> "acts as a short form of the statements:"
>
> ```abap
> r = expr.
> RETURN.
> ```

> "In any other context than a functional method, the `RETURN` statement has no addition."

> "If `RETURN` is the last statement in front of `ENDMETHOD`, it is skipped internally and `RETURN expr` works in the same way as `r = expr`."

Which makes the guard-clause pattern read properly, including with a
constructor expression whose type is inferred from the return value:

```abap
METHOD main.
  TRY.
      RETURN VALUE #( FOR i = 1 UNTIL i > limit
              ( num = i square = ipow( base = i exp = 2 ) ) ).
    CATCH cx_sy_arithmetic_error.
      RETURN VALUE #( ).
  ENDTRY.
ENDMETHOD.
```

So even `RETURN` is context-dependent — but in its *syntax*, which the compiler
checks, rather than in its *meaning*, which it does not.

---

## Checklist

- `EXIT` and `CHECK` only to leave **loops**. `RETURN` only to leave
  **procedures**. Never the other way round.
- The one allowed `CHECK` is a prerequisite check on the **first lines** of a
  procedure. Anywhere else, write `IF ... RETURN. ENDIF.`
- Before trusting an `EXIT`, confirm the enclosing loop: `SELECT ... ENDSELECT`
  and `PROVIDE` count as loops; `SELECT ... INTO TABLE` does not.
- When you delete a loop, grep the block for `EXIT`/`CHECK` — their meaning
  just changed, silently.
- An early `RETURN` still delivers by-value outputs. If the caller must see no
  change, raise an exception instead.
- Nothing parked in `END-OF-SELECTION` survives an early `RETURN`/`EXIT` in
  `START-OF-SELECTION`. Use `STOP` if you need that event.
- No `STOP` and no `REJECT` in methods. No `LEAVE PROGRAM` in anything you
  intend to unit test or run in the update task.
- `DO n TIMES` snapshots `n` on entry; `n <= 0` executes zero passes without
  complaint. Guard the bound before the loop, not inside it.
- `DO`/`WHILE` set `sy-index`; `LOOP AT` sets `sy-tabix`, and that is `0` for
  every pass over a hashed table.
- Copy `sy-index` into a variable before `ENDDO` if you need it afterwards.

## Sources

- [`EXIT`, loop](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/exit-loop) — loop break, and the hint that it should only be used in loops
- [`EXIT`, processing_block](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/exit-processing-block) — the `"works as RETURN here!"` example, `START-OF-SELECTION`/`GET` behaviour
- [`CHECK`, loop](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/check-loop) — `IF NOT log_exp. CONTINUE. ENDIF.` equivalence
- [`CHECK`, processing_block](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/check-processing-block) — `IF NOT log_exp. RETURN. ENDIF.` equivalence, `CHECK SELECT-OPTIONS`
- [`CONTINUE`](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/continue) — loops only
- [`RETURN`](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/return) — position independence, event-block exceptions, the `expr` addition
- [`STOP`](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/stop) — allowed event blocks, `END-OF-SELECTION`, `STOP_NO_REPORT` / `STOP_WITHIN_CALLED_DYNPRO`
- [`REJECT`](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/reject) — refers to the current `GET` event, not to its own location
- [`DO`](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/do) — `n` read once, `n <= 0`, endless loop and the `max_runtime` profile parameters, `sy-index`
- [`WHILE`](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/while) — same `sy-index` and `max_runtime` rules
- [Loops](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/loops) — `SELECT`-`ENDSELECT` and `PROVIDE` are loops
- [`LOOP AT itab`, Basic Form](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/loop-at-itab-basic-form) — `sy-tabix`, and `sy-tabix = 0` for hashed tables
- [Exiting Processing Blocks](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/exiting-processing-blocks) — by-value outputs on an error-free exit, `SUBMIT` without `AND RETURN`
- [Exiting Procedures (programming guideline)](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/exiting-procedures) — the context-dependence rule, the bad/good example, the first-lines-`CHECK` exception
- [Exiting Programs](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/exiting-programs) — `LEAVE PROGRAM`, and "not possible in some contexts as for example during unit tests or during update" (the longer wording quoted in Trap 9 is from Exiting Processing Blocks / Exiting Procedures, which carry it verbatim)
- [Regular Exiting of a Processing Block](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/regular-exiting-of-processing-block) — the baseline the exceptions above are measured against

## Related notes in this repo

[Loop Modification](../Loop%20Modification#readme) for changing a table inside
its own `LOOP`, [Internal Table Grouping](../Internal%20Table%20Grouping#readme)
and [Control Level Processing](../Control%20Level%20Processing#readme) for the
loop bodies themselves, [Parameter Passing](../Parameter%20Passing#readme) for
what an early exit delivers, [Exception Flow](../Exception%20Flow#readme) for
leaving a `TRY` block, [Program Calls](../Program%20Calls#readme) for `SUBMIT`,
and [Enhancement Framework](../Enhancement%20Framework#readme) for why an early
`RETURN` in a standard method does **not** stop a post-exit.
