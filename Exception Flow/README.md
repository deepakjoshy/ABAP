# CLEANUP, RETRY, RESUME — the TRY-block statements that behave unlike every other language

`TRY ... CATCH ... ENDTRY` everyone knows. The other three statements inside a
`TRY` control structure are rarely used, and the reason is that each one has a
rule that contradicts the instinct you brought from Java/ABAP-by-analogy.

Runnable demo: [`ydj_exception_flow_demo.abap`](ydj_exception_flow_demo.abap)

## CLEANUP is not `finally`

This is the big one. A `CLEANUP` block runs **only when the exception leaves its
own `TRY` structure** and is handled by a `CATCH` further out.

> "A `CLEANUP` block is executed exactly when a class-based exception in the `TRY`
> block of the same `TRY` control structure is raised but is handled in a `CATCH`
> block of an external `TRY` control structure."
> — [ABAP keyword documentation, CLEANUP](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCLEANUP.html)

So the three cases are:

| What happens in the TRY block | CLEANUP runs? |
|---|---|
| No exception at all | **No** |
| Exception caught by a `CATCH` of the *same* `TRY` | **No** |
| Exception propagates to an *outer* `TRY` | **Yes** |
| Resumable exception left via `RESUME` | **No** — the context is never deleted |

If you were using `CLEANUP` to release an enqueue lock or close a dataset, that
lock leaks in the two "No" cases that matter. There is no `finally` in ABAP; the
honest equivalent is doing the release in both the `CATCH` block and on the normal
path, or wrapping the resource in an object whose lifetime you control.

Ordering detail worth knowing: with plain `CATCH`, the context is deleted before
the handler runs, so `CLEANUP` executes **before** the outer `CATCH` body. With
`CATCH BEFORE UNWIND`, the context survives until the handler ends, so `CLEANUP`
executes **after** it.

Two hard constraints on the block itself:

- It must run to completion and exit via `ENDTRY`. `RETURN`, `EXIT`, `LEAVE` are
  a runtime error (a syntax error where the compiler can prove you can't come back).
  Avoid `SUBMIT` and `CALL TRANSACTION` in there too.
- Any exception raised inside `CLEANUP` must be handled inside `CLEANUP`.
- Inside a `CLEANUP` block the `is_resumable` attribute of the exception object is
  undefined, and you must not re-raise the current exception with
  `RAISE EXCEPTION oref` — that rewrites the object's attributes.

## RETRY restarts the whole TRY block — with no counter

`RETRY` may only appear in a `CATCH` block. It abandons the handler and re-executes
the `TRY` block **from its first statement**, not from the statement that failed.

Nothing in the language counts attempts. If you `RETRY` without removing the cause
first, you have written an infinite loop that looks like error handling. Always
guard it with your own counter:

```abap
DATA(lv_tries) = 0.
TRY.
    call_flaky_service( ).
  CATCH cx_http_dest_provider_error.
    lv_tries += 1.
    IF lv_tries <= 3.
      WAIT UP TO 2 SECONDS.
      RETRY.
    ENDIF.
    " out of retries - propagate or log
ENDTRY.
```

Also note the re-execution is genuinely from the top: any state the `TRY` block
mutated on the first pass is still mutated on the second. Idempotency is your
problem, not the runtime's.

## RESUME needs three things to line up

`RESUME` continues at the statement **after** the `RAISE`, inside the procedure
that raised — the only way in ABAP to hand the *caller* the decision about whether
the *callee* should carry on. It requires all three:

1. `RAISE RESUMABLE EXCEPTION TYPE ...` (or `THROW` with `RESUMABLE`) at the raise site
2. `RAISING RESUMABLE(cx_...)` in every procedure signature it propagates through
3. `CATCH BEFORE UNWIND cx_... ` at the handler — plain `CATCH` makes `RESUME` a syntax error

Miss #2 anywhere in the call chain and the exception silently arrives
non-resumable; check `lo_err->is_resumable` before calling `RESUME`. And because
`RESUME` never deletes the context, no `CLEANUP` block on the path runs.

Realistic use: a mass-posting loop where a locked record should be skipped and the
run continued, with the *caller* — not the posting method — owning that policy.

## Sources

- [ABAP keyword documentation — CLEANUP](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCLEANUP.html)
- [ABAP keyword documentation — RESUME](https://help.sap.com/docs/abap-cloud/abap-keyword/resume)
- [System Response After a Class-Based Exception](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENEXCEPTIONS_SYSTEM_RESPONSE.html)
- [SAP-samples/abap-cheat-sheets — Exceptions and Runtime Errors](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/27_Exceptions.md)
