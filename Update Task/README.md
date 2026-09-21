# The Update Task — the registration that is not a call

`CALL FUNCTION 'Z_...' IN UPDATE TASK` looks like a function call. It is not one.
It is a **registration**: the name and a serialized copy of the parameters are
written to the `VB...` tables, and nothing runs until `COMMIT WORK`. By then your
program has usually moved on, often into a different work process.

Almost every bug in this area comes from writing code as if the call had happened.
The statement accepts `EXCEPTIONS`, so people handle exceptions. It sets `sy-subrc`,
so people check it. Neither does anything.

This note is the update-side companion to
[`Commit Work Events`](../Commit%20Work%20Events#readme) (which event fires, and when)
and [`Enqueue Locks`](../Enqueue%20Locks#readme) (`_SCOPE = 2` is what hands a lock to
the update task).

---

## 1. The error handling you wrote on the call is dead code

From the keyword documentation for `CALL FUNCTION ... IN UPDATE TASK`, two sentences
that invalidate the usual pattern:

> The `sy-subrc` is undefined after executing the `CALL FUNCTION ... IN UPDATE TASK`
> statement.

> The additions `IMPORTING`, `CHANGING` and `EXCEPTIONS` of the general function
> module call may be specified, but they are **ignored during the execution**.

So this compiles, passes review, and checks nothing:

```abap
" WRONG - every line of error handling here is decoration
CALL FUNCTION 'Z_POST_DOCUMENT' IN UPDATE TASK
  EXPORTING  is_header = ls_header
  IMPORTING  ev_docnr  = lv_docnr        " never filled - ignored
  EXCEPTIONS posting_failed = 1          " never raised - ignored
             OTHERS         = 2.

IF sy-subrc <> 0.                        " sy-subrc is UNDEFINED here
  MESSAGE e001(zfi).                     " reads whatever the previous statement left
ENDIF.
```

`IMPORTING` being ignored is the one that changes design: **an update function module
cannot return anything to you.** No document number, no status, no error text. If the
caller needs the key, it has to be determined *before* registration (draw the number
range in the dialog part, pass it in) — which is exactly why
[`Number Ranges`](../Number%20Ranges#readme) and the update task keep showing up in the
same programs.

Only `EXPORTING` and `TABLES` are real, and `EXPORTING` has a restriction the normal
call does not have: **no reference variables**, and no data objects that contain
reference variables. An object reference cannot survive the trip.

## 2. The parameters are `EXPORT`ed, so type errors surface later and elsewhere

The doc explains the mechanism:

> When registering an update function module using `CALL FUNCTION ... IN UPDATE TASK`,
> the relevant data is exported internally to a data cluster using `EXPORT` and is
> imported again when executing the function module with `IMPORT`.

Two consequences:

- If the actual parameter types do not match the formal parameter typing, you get the
  `IMPORT` exceptions — **during the update**, in the update work process, long after
  the statement that caused them. The call site is clean.
- Too much data raises the `EXPORT` exceptions at registration time instead.

Also worth knowing before you design around it: when an internal table with a
non-unique key is passed, **the order of the duplicate rows is not retained**.

## 3. Registered twice means executed twice

> A function module that is registered more than once is also executed more than once
> with the associated parameter values.

Obvious in isolation, dangerous in a loop, and the **opposite** of the rule for
`PERFORM ... ON COMMIT`, where a subroutine registered multiple times
"is executed once in each case". Two bundling techniques in the same program, two
different duplicate semantics.

## 4. Asynchronous means the failure never reaches your program

`COMMIT WORK` without `AND WAIT` returns as soon as the update is *handed over*:

| Statement | `sy-subrc` |
|---|---|
| `COMMIT WORK` | **always 0** — says nothing about the update |
| `COMMIT WORK AND WAIT` | `0` = updates succeeded, `4` = updates failed |

So the common `COMMIT WORK. IF sy-subrc = 0. "success". ENDIF.` is testing a constant.
When an asynchronous update dies, the doc says what actually happens:

> the update work process executes a database rollback, logs this in the corresponding
> database tables, and notifies the user whose entries created the entries by SAPMail.

That is the whole feedback channel: a rollback, a `SM13` entry, and mail to whoever
happened to trigger it. Your program already reported success to the user and moved on.
If the caller must know the outcome, `AND WAIT` is not an optimization toggle — it is
the only synchronous option, and `sy-subrc = 4` is the only signal.

## 5. V1 and V2 fail differently, and only V1 is atomic

`COMMIT WORK` runs update modules in two phases by the priority set in the Function
Builder:

- **High priority ("VB1" / V1)** — executed in registration order, **in a shared
  database LUW**. All-or-nothing across every V1 module.
- **Low priority ("VB2" / V2)** — executed only *"when all high-priority update
  function modules are completed successfully"*, in a **separate** shared database LUW.

So a V2 failure rolls back the V2 work while every V1 change stays committed. That is
the intended design (V2 is for statistics, not for the document), but it means
**priority is a consistency decision, not a performance decision**. Putting a posting
step in V2 because "it can wait" silently opts it out of the document's transaction.

Ordering is by registration within a phase — there is no `LEVEL` equivalent here
(that addition belongs to `PERFORM ON COMMIT`).

## 6. `SET UPDATE TASK LOCAL` has a `sy-subrc` nobody reads

Local update runs the modules in the **current** work process instead of an update
work process. Three documented rules, each of which quietly breaks a naive use:

- **It must come before the first registration.** `sy-subrc = 1` means it did *not*
  activate, "because the program has already registered at least one update function
  module for the normal updating procedure in the current SAP LUW". No exception, no
  dump — you simply keep the asynchronous behaviour you were trying to avoid.
- **It is switched off again at the start of every SAP LUW.** After each `COMMIT WORK`
  it must be re-armed, so a loop that sets it once and commits per iteration is local
  only for the first pass.
- **It is ignored by low-priority (V2) modules.** Your V1 work becomes local, your V2
  work does not.

One genuinely useful property: local update *"performs a synchronous update after the
`COMMIT WORK` statement, independently of the addition `AND WAIT`"*. And one sharp
edge: *"If a database rollback occurs during the local update, all previous change
requests are affected"* — there is no separate update LUW to contain the damage.

There is also a profile parameter, `abap/force_local_update_task`, that turns this on
system-wide. Worth checking before concluding a system "doesn't use the update task" —
and a reason your code should not *depend* on the update being remote.

## 7. Statements that are legal everywhere else and dump inside an update

During an update there can be no database commit or rollback and the update controller
must not be disturbed. The runtime enforces this at the offending statement:

| Statement in an update FM | Runtime error |
|---|---|
| `COMMIT WORK` | `COMMIT_IN_POSTING` |
| `ROLLBACK WORK` | `ROLLBACK_IN_POSTING` |
| `CALL SCREEN`, `CALL DIALOG`, `CALL TRANSACTION`, `CALL SELECTION-SCREEN`, `SUBMIT`, `SET SCREEN`, all `LEAVE` variants | `POSTING_ILLEGAL_STATEMENT` |
| Native SQL `COMMIT WORK` / `ROLLBACK WORK` | `POSTING_ILLEGAL_STATEMENT` |
| Type `A` message caught via `error_message` | `MESSAGE_ROLLBACK_IN_POSTING` |

The `SUBMIT` row is the one that catches people reusing a working report from inside an
update module (see [`Program Calls`](../Program%20Calls#readme) for what `SUBMIT` does to
an LUW in the first place). The `error_message` row matters because catching a type A
message is the *defensive* thing to do everywhere else — here it implies a
`ROLLBACK WORK` and is therefore forbidden.

Note the asymmetry the doc calls out explicitly: `MESSAGE` of type `I`, `W`, `E` and `A`
also causes an implicit database rollback, but **no direct runtime error is raised**,
"for reasons of downward compatibility". So messages remain the quiet way to wreck an
update — the behaviour described in [`Messages`](../Messages#readme) applies instead.

## 8. `PERFORM ... ON COMMIT` is a different mechanism with different rules

Both are bundling techniques triggered by `COMMIT WORK`, and they are routinely
confused:

| | `CALL FUNCTION ... IN UPDATE TASK` | `PERFORM subr ON COMMIT` |
|---|---|---|
| Runs in | update work process (or current, if local) | **always the current work process** |
| When | after the `ON COMMIT` subroutines | **before** the update modules |
| Parameters | `EXPORTING` / `TABLES`, serialized | **none at all** — "cannot have any parameter interface" |
| Registered twice | executed twice | executed **once** |
| Ordering | registration order | registration order, or `LEVEL idx` ascending |
| DB commit/rollback inside | forbidden (`COMMIT_IN_POSTING`) | **allowed** |

The trap is the combination. From the doc:

> Especially for asynchronous update, procedures that are registered outside update
> processing are executed in different work processes and therefore in different
> database LUWs. The changes in the database LUW of the subroutine can be committed
> before the update function modules are executed and **a database rollback during an
> asynchronous update does not roll back these changes**.

So an `ON COMMIT` subroutine that writes a log row or a status flag, paired with an
update module that writes the document, is not one transaction. The update can fail
and leave the log claiming it succeeded.

Because registered subroutines have no parameter interface, data has to be smuggled in
through ABAP memory (`EXPORT ... TO MEMORY ID` / `IMPORT`) — which is the doc's own
example, and which brings the `IMPORT`-is-a-merge trap from
[`Program Calls`](../Program%20Calls#readme) along with it. The current guideline is
blunt: subroutines are obsolete, and new ones written for `ON COMMIT` / `ON ROLLBACK`
"should only be used as wrappers for a method call and must not contain any other
functional code".

## 9. No `COMMIT WORK` at all: silence

If the program ends without one:

> If the statement `COMMIT WORK` is not executed when the current program is executed
> after the registration of a function module, the function module is not executed and
> the associated entries are deleted from the corresponding database tables when the
> program ends.

No dump, no log, no `SM13` entry. The work simply never happened. `ROLLBACK WORK` does
the same deliberately — it deletes every registration for the current SAP LUW (and
every `PERFORM ON COMMIT` registration), while *executing* the `PERFORM ON ROLLBACK`
ones.

The registrations also live in a normal database LUW: *"if the database LUW is ended by
a database rollback, all registration entries of the current database LUW are deleted"* —
so an implicit rollback earlier in the program can discard registrations you are still
counting on.

## 10. `TRANSACTION_FINISHED` fires at a different moment for async updates

Worth pinning down if you use the event from
[`Commit Work Events`](../Commit%20Work%20Events#readme) to run cleanup:

- synchronous update, local update, and outside the update: the event is raised **once
  processing is finished**;
- asynchronous update: it is raised **when the update is initiated**.

The doc's warning is explicit — the handler can clean up preparation resources, but
"this is no guarantee that the update has not already been performed". Treating the
event as "the data is safe now" is wrong in exactly the asynchronous case that is the
default.

---

## Checklist

- Don't check `sy-subrc` after `IN UPDATE TASK` — it is undefined.
- Don't add `IMPORTING` / `EXCEPTIONS` to an update call — they are ignored.
- Need the outcome in the caller? `COMMIT WORK AND WAIT` and test `sy-subrc = 4`.
- Need the document key? Determine it before registering, not inside the module.
- V2 is not "V1, later" — it is a separate transaction that keeps V1's work on failure.
- `SET UPDATE TASK LOCAL` goes before the first registration, and again after every commit.
- Inside an update module: no `COMMIT`/`ROLLBACK`, no `SUBMIT`, no `CALL TRANSACTION`, no `LEAVE`, no type A/E/W/I messages.

## Sources

- [`CALL FUNCTION - IN UPDATE TASK` — ABAP Keyword Documentation](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-us/abapcall_function_update.htm)
- [`COMMIT WORK` — ABAP Keyword Documentation](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-us/abapcommit.htm)
- [`ROLLBACK WORK` — ABAP Keyword Documentation](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPROLLBACK.html)
- [`SET UPDATE TASK LOCAL` — ABAP Keyword Documentation](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-us/abapset_update_task_local.htm)
- [`PERFORM - ON COMMIT, ROLLBACK` — ABAP Keyword Documentation](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPPERFORM_ON_COMMIT.html)
- [Forbidden Statements in Updates — ABAP Keyword Documentation](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abendb_commit_during_update.htm)
