# RFC — the call that quietly becomes a local call, and the exceptions that never arrive

A remote function call is written to look exactly like a local one. That is the
problem: `CALL FUNCTION 'Z_READ_STOCK' DESTINATION lv_dest` and
`CALL FUNCTION 'Z_READ_STOCK'` differ by three words, but almost every guarantee
you rely on locally — type checking, parameter names, class-based exceptions,
your own LUW — is quietly gone in the remote form.

This note is the distributed-systems companion to
[`Update Task`](../Update%20Task#readme) (the other statement that registers instead
of calling) and [`Background Jobs`](../Background%20Jobs#readme) (the other API that
commits behind your back).

---

## 1. An empty destination is not an error — it is a local call

From the keyword documentation for `CALL FUNCTION - DESTINATION`:

> If an empty string or a text field consisting only of blanks is specified for
> `dest`, the addition `DESTINATION` is ignored and a regular `CALL FUNCTION func`
> call is made.

So a destination read from customizing that comes back blank does **not** raise,
does **not** set a non-zero `sy-subrc`, and does not warn. It runs the function
module *in the local system*:

```abap
SELECT SINGLE rfcdest FROM ztc_config INTO @DATA(lv_dest)
  WHERE area = 'STOCK'.          " row missing in QA -> lv_dest is blank

CALL FUNCTION 'Z_READ_STOCK' DESTINATION lv_dest
  EXPORTING  iv_werks  = lv_werks
  IMPORTING  ev_menge  = lv_menge
  EXCEPTIONS system_failure        = 1
             communication_failure = 2
             OTHERS                = 3.
```

If `Z_READ_STOCK` also exists locally, this returns **local** stock figures with
`sy-subrc = 0` and no indication that the remote system was never contacted. The
test passes, the numbers are wrong, and the only symptom is that production and
the remote system disagree.

A destination must therefore be validated before use, not after:

```abap
IF lv_dest IS INITIAL.
  MESSAGE e001(zrfc).          " no silent fallback to local
ENDIF.
```

Note the asymmetry with the asynchronous form — the doc states that for
`STARTING NEW TASK`, calls

> are always executed using the RFC interface \[...] This is why, unlike in
> synchronous RFC, an initial string or text field containing only blanks cannot
> be specified for `dest`.

aRFC rejects what sRFC silently accepts.

## 2. Typing is not checked, and wrong parameter names are ignored

The rules for RFC parameter passing differ from a normal function module call in
three ways that all fail silently. Quoting the doc directly:

> - Bindings of actual parameters to incorrectly specified formal parameters are
>   **ignored**.
> - Typings are **not checked**. The content of actual parameters is handled in the
>   remotely called function module and, if possible, is cast to the type of the
>   formal parameter.
> - Each formal parameter is handled implicitly like an **optional** parameter.
>   Every input parameter or input/output parameter to which no actual parameter is
>   assigned is given either its type-dependent initial value or a default value
>   specified explicitly in the definition.

Put together: misspell `iv_werks` as `iv_wekrs` and the binding is discarded, the
formal parameter takes its initial value, and the remote module runs happily with
a blank plant. Locally the same typo is a syntax error.

There is a second, subtler version for character-like parameters:

> In the called function module, a shorter actual parameter is filled with blanks
> on the right in the input and truncated in the output. If the actual parameter is
> longer, the reverse applies.

So a length mismatch between the two systems' data elements truncates rather than
raising — the same class of silent damage as `value_handling` in
[`JSON Serialization`](../JSON%20Serialization#readme).

Also documented: reference variables cannot be passed, directly or as components
of deep structures, and for internal tables with non-unique keys "the order of the
duplicate lines in relation to these keys is not retained".

The one real defence is the **extended program check** (SLIN), which the doc says
reports incorrect formal parameters and unsuitable actual parameters *where it
can* — this is one of the few places where a green SLIN run is load-bearing rather
than cosmetic.

## 3. Class-based exceptions do not survive the wire

This is the trap that turns a precise remote error into an unhelpable one:

> If a remotely called function module raises a class-based exception during
> non-class-based exception handling, this exception is **not transported** and
> raises the predefined classic exception `SYSTEM_FAILURE` instead.

And, flatly:

> Class-based exception handling in RFCs is not possible in the current release
> track.

So a remote `RAISE EXCEPTION TYPE zcx_no_authority` does not arrive as
`zcx_no_authority`. A `TRY ... CATCH zcx_no_authority` around the call catches
nothing; the call sets the `SYSTEM_FAILURE` return code instead. If you did not
list `SYSTEM_FAILURE` under `EXCEPTIONS`, the classic uncaught-exception behaviour
applies and the program terminates.

`error_message` does not help either — the doc says its specification after
`EXCEPTIONS` **is ignored in RFC**.

The only way to see *why* it failed is the `MESSAGE` addition, which captures the
first line of the remote short dump:

```abap
DATA lv_smess TYPE c LENGTH 200.
DATA lv_cmess TYPE c LENGTH 200.

CALL FUNCTION 'Z_READ_STOCK' DESTINATION lv_dest
  EXPORTING  iv_werks = lv_werks
  IMPORTING  ev_menge = lv_menge
  EXCEPTIONS system_failure        = 1 MESSAGE lv_smess
             communication_failure = 2 MESSAGE lv_cmess
             OTHERS                = 3.
```

The doc's own guidance is unambiguous — "It is strongly recommended that all
predefined exceptions are handled" — and the predefined set is `SYSTEM_FAILURE`,
`COMMUNICATION_FAILURE`, plus `RESOURCE_FAILURE` for the parallel (`IN GROUP`)
variant only. The `MESSAGE` field must be flat and character-like.

Messages behave differently across the wire too. Per `Messages - RFC Processing`,
as long as no list or dialog processing happens remotely:

- types `I`, `S` and `W` are **ignored**
- types `A`, `E` and `X` terminate processing, cause a **database rollback**, and
  raise `SYSTEM_FAILURE` in the caller

with the explicit warning that whether a type `E` message rolls back "depends on
the type of call" — the same module called locally usually does not roll back.
See [`Messages`](../Messages#readme) for why message type is context-dependent in
general.

## 4. Every RFC commits your database LUW

Three separate doc pages say the same thing in the same words:

> The synchronous RFC triggers a database commit in the calling program. An sRFC
> during the update is an exception to this.

> Asynchronous RFC triggers a database commit in the calling program.

> If the statement `WAIT` interrupts the program, the work process is changed, and
> a database commit is executed, except in updates.

So an RFC placed in the middle of a posting routine ends the database LUW at that
point. Everything written before it is committed and can no longer be rolled back;
registrations made with `CALL FUNCTION ... IN UPDATE TASK` before the call fire
early, exactly as described in [`Update Task`](../Update%20Task#readme).

It also closes every open database cursor — which is the documented reason
`WAIT` "must not be used between ABAP SQL statements that open or close a database
cursor", and the reason a `SELECT ... PACKAGE SIZE` loop with an RFC inside it
dumps with `DBSQL_INVALID_CURSOR`. That case is written up in
[`Mass Data Processing`](../Mass%20Data%20Processing#readme).

## 5. aRFC: the callback that never runs, and the connection that never closes

`CALL FUNCTION func STARTING NEW TASK task ... PERFORMING subr ON END OF TASK`
returns as soon as the remote function has *started*. Four documented traps:

**The missing `RECEIVE` leaks the connection.** The doc is explicit that a callback
routine without a `RECEIVE` statement

> behave\[s] implicitly in the same way as when the addition `KEEPING TASK` is
> specified

and calls it out as a programming error: "Callback routines without a `RECEIVE`
statement are possible in the syntax, but are to be avoided and viewed as
programming errors." The connection and the remote RFC session stay open, so a
loop over a few thousand records exhausts resources rather than failing cleanly.

**The callback only runs if you are still there.** A prerequisite is that

> the calling program still exists in its internal session when the remote function
> is terminated \[...] If the program was terminated or is located on the stack as
> part of a call sequence, the callback routine is not executed.

So results silently go missing when the caller is itself invoked from another
program.

**Order is undefined.** Multiple registered callbacks "are executed in an undefined
order", and a function module started several times has an execution order that
"depends \[on] the system availability". Anything order-sensitive needs the task ID,
which the RFC interface passes into the callback's single `clike` parameter.

**`WAIT FOR ASYNCHRONOUS TASKS` returns 4 when there is nothing to wait for.**
The `sy-subrc` table:

| `sy-subrc` | Meaning |
|---|---|
| 0 | the logical expression is true |
| 4 | expression false **and** there are no async calls with callback routines left |
| 8 | expression false and the `UP TO sec SECONDS` limit was exceeded |

The trap is that 4 does not mean "timed out" — it means the wait ended without the
condition being met, including the case where nothing was ever registered. Code
that treats non-zero as a timeout and retries will spin. `sec` expects type `f`,
and a negative value is the uncatchable runtime error `WAIT_ILLEGAL_TIME_LIMIT`.

Note also that `UP TO` expiring does not cancel anything: "it does not mean that
any outstanding callback routines are no longer executed at all" — a later work
process change in the same program can still run them.

For genuine parallelism, use `DESTINATION IN GROUP` (pRFC) rather than hand-rolled
destinations; the doc says this "makes optimal use of the available resources and
is preferable to self-programmed parallel processing", only one RFC server group
may be used per program, and resource exhaustion arrives as `RESOURCE_FAILURE`
(for which the `MESSAGE` addition is *not* permitted).

## 6. `IN BACKGROUND TASK` (tRFC) is obsolete — use bgRFC

`CALL FUNCTION ... IN BACKGROUND TASK` is classified as obsolete in the keyword
documentation, with the recommendation repeated twice:

> background RFC (bgRFC) executed with the statement `CALL FUNCTION IN BACKGROUND
> UNIT` is the enhanced successor technology of transactional RFC (tRFC) and makes
> this technology obsolete. It is strongly recommended that bgRFC is used instead
> of tRFC.

Worth knowing anyway, because existing code is full of it:

- It is a registration, like the update task: name, destination and parameters are
  written to `ARFCSSTATE` / `ARFCSDATA` under a transaction ID (**SM58**), and
  nothing runs until `COMMIT WORK`. `ROLLBACK WORK` deletes the registrations.
- Omitting the destination does **not** fall back to a local call here — the
  destination `"NONE"` is used implicitly.
- If the destination is unavailable at `COMMIT WORK`, report `RSARFCSE` retries
  every 15 minutes up to 30 times by default (changeable in SM59), then records
  `CPICERR`; the `ARFCSSTATE` entry is deleted after eight days by default.
- Execution order *within* one transaction ID is fixed, but the order of LUWs on
  the server is not — that is what qRFC (`TRFC_SET_QUEUE_NAME`) adds.
- `COMMIT WORK` and `ROLLBACK WORK` must not be executed inside the called module,
  and no implicit database commit may be triggered there.
- Registrations live in a normal database LUW, so an earlier database rollback
  discards them.

---

## Sources

- [`CALL FUNCTION - DESTINATION`](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapcall_function_destination.htm) — blank-destination fallback, sRFC database commit
- [`CALL FUNCTION DESTINATION, parameter_list`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCALL_FUNCTION_DESTINATION_PARA.html) — ignored bindings, no type check, implicit optional, `MESSAGE`, `error_message` ignored
- [`RFC - Exceptions`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENRFC_EXCEPTION.html) — class-based exceptions not transported, predefined exception set
- [`Messages - RFC Processing`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_MESSAGE_RFC.html) — I/S/W ignored, A/E/X rollback + `SYSTEM_FAILURE`
- [`CALL FUNCTION - STARTING NEW TASK`](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapcall_function_starting.htm) — task IDs, callback rules, pRFC, aRFC database commit
- [`RECEIVE`](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapreceive.htm) — `KEEPING TASK`, missing-`RECEIVE` behaviour
- [`WAIT FOR ASYNCHRONOUS TASKS`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWAIT_ARFC.html) — `sy-subrc` table, `UP TO` semantics
- [`CALL FUNCTION - IN BACKGROUND TASK`](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapcall_function_background_task.htm) — tRFC obsolescence, `ARFCSSTATE`, `RSARFCSE`
