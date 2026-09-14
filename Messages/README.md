# MESSAGE — The Type You Ask For Is Not Always the Type You Get

`MESSAGE` looks like the simplest statement in ABAP: pick a letter, ship a text.
It is not. The letter is a **request**, and the runtime context is free to convert
it, to terminate your program, or to ignore it entirely — with no syntax error and
no `sy-subrc` to check. The same `MESSAGE e001` line is a harmless status line in
one processing block, a program termination in another, and a silent no-op in a
third.

This note collects the behaviours that bite, all verified against the ABAP keyword
documentation (links at the bottom).

---

## 1. The message type is context-dependent (the headline)

The type you write is what the *program flow* is derived from, but the context
decides the actual outcome. From the dialog-processing behaviour table:

| Where you send it | `E` actually does | `W` actually does | `I` actually does |
|---|---|---|---|
| `START-OF-SELECTION`, `GET`, `END-OF-SELECTION`, `TOP-OF-PAGE` | **Terminates the program**, shows an empty screen with an empty GUI status | converted to `E` — so also terminates | dialog box, then continues |
| `PROCESS AFTER INPUT` module | ends PAI, returns to the same screen without PBO | same, but Enter on unchanged input continues | dialog box, then continues |
| `AT SELECTION-SCREEN` | back to the selection screen, `AT SELECTION-SCREEN OUTPUT` **not** raised | same, but Enter on unchanged input continues | dialog box, then continues |
| `PROCESS BEFORE OUTPUT`, `AT SELECTION-SCREEN OUTPUT`, `INITIALIZATION` | converted to **`A`** (terminate + rollback) | converted to **`S`** | converted to **`S`** |
| `POH` / `POV` / `AT EXIT-COMMAND` modules | **uncatchable exception** — not allowed here | uncatchable exception | dialog box, then continues |
| `AT LINE-SELECTION`, `AT USER-COMMAND` | ends the event block, list stays displayed | converted to `E` | dialog box, then continues |
| `LOAD-OF-PROGRAM` | runtime error `SYSTEM_LOAD_OF_PROGRAM_FAILED` | depends on loading context | depends on loading context |

Three consequences worth internalising:

- **`MESSAGE e...` in `START-OF-SELECTION` kills the report.** It does not "show an
  error and carry on". The user gets a blank screen with the text in the status bar.
  This is why error handling in reports belongs in a collected message table (BAL /
  `BAPIRET2`) displayed at the end, not in scattered `MESSAGE e` statements.
- **`W` does not exist in list processing.** It is converted to `E` *before* any
  other handling. List processing is active in every program started with `SUBMIT`
  and during reporting events — so a warning in a report is an error in a report.
- **`E` and `W` in PBO become `A` and `S`.** The severity is silently inverted:
  the error terminates harder than you asked, the warning becomes cosmetic.

**And the system field lies about it.** Conversion of the output type does *not*
change `sy-msgty` — that always holds the type you wrote in the statement. So code
downstream that inspects `sy-msgty` sees `W` even when the user was shown, and the
flow behaved like, an `E`.

## 2. Background jobs: `E` and `A` both kill the job, but only one rolls back

In background processing messages are written to the job log instead of displayed:

- `S`, `I`, `W` → logged, program continues (the required Enter is generated
  automatically).
- `E`, `A` → logged, then — unless the caller is handling them via `error_message`
  — logged again as message `00 564` and **the job is terminated**. A type `A`
  performs a database rollback; a type `E` **does not**. That asymmetry is the bug
  farm: an `E` that terminates a job midway leaves everything already committed in
  place, half-processed.
- `X` → runtime error plus rollback, job cancelled.

Remember list processing is active in jobs too (they start via `SUBMIT`), so `W`
has already become `E` by this point.

## 3. Messages in update function modules

- In a real update work process (sync or async update), **every type except `S`
  terminates the update** — without a runtime error. The work process rolls back,
  writes remarks into the `VB*` tables, and notifies the originating user by
  SAPmail. Your program has long since moved on and sees nothing.
- In a **local update** (`SET UPDATE TASK LOCAL`), everything except `S` and `X` is
  converted to `A` and behaves as in dialog processing — terminate plus rollback.
  So the same update FM behaves differently depending on a setting made by the
  caller.
- Catching a type `A` there with `EXCEPTIONS error_message` does not help: that
  handling implies an implicit `ROLLBACK WORK`, which is forbidden in updates, so
  you get the runtime error `MESSAGE_ROLLBACK_IN_POSTING`. Types `I`, `W` and `E`
  *can* be caught this way.

## 4. `INTO` — no flow change, and no `sy-subrc`

```abap
MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
        INTO DATA(lv_text)
        WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
```

With `INTO`, the short text is resolved into the target field, the program flow is
**not** interrupted and **no message processing takes place at all** — the message
type is irrelevant. `MESSAGE e...` and `MESSAGE i...` into a variable do exactly the
same thing.

Two traps:

- **It does not set `sy-subrc`.** `MESSAGE ... INTO` is text formatting, not a
  check. Any `IF sy-subrc <> 0` after it is reading the result of whatever statement
  ran *before* the `MESSAGE` — usually the `CALL FUNCTION` you were trying to
  evaluate, which is sometimes accidentally right and sometimes silently wrong.
- **`INTO` cannot be combined with the free-text variant** (`MESSAGE 'text' TYPE 'I'`)
  or with `MESSAGE oref`. If you need the text of an exception object, use
  `oref->get_text( )` directly.

This is the only form of `MESSAGE` that belongs in application logic. The keyword
documentation is explicit: apart from type `X`, `MESSAGE` should be used
*exclusively in the presentation layer*.

## 5. `WITH` truncates every placeholder at 50 characters

Operands after `WITH` are formatted like a `WRITE TO` source **with an output length
of 50**, then assigned to `sy-msgv1` … `sy-msgv4` (which are themselves `c(50)`).
A 70-character material description passed into `&1` loses its last 20 characters,
silently.

Also:

- If you pass **fewer operands than placeholders**, the surplus placeholders are not
  displayed and the corresponding `sy-msgv*` fields are **initialized** — they are
  not left holding the previous message's values.
- If you pass an operand that has no placeholder to land in, it is ignored.
- Mixing `&1`-style and `&`-style placeholders in one short text makes a single
  operand replace two placeholders. Use one style; use `&1`…`&4` if the text will
  ever be translated, since word order changes between languages.
- To output a literal `&`, write `&&` in the short text. For compatibility, `$`
  behaves exactly like `&`, so `$$` is needed for a literal `$` too.
- Writing `sy-msgid`, `sy-msgno`, `sy-msgv1`…`sy-msgv4` *directly* after `WITH` uses
  the values set by the current statement; wrapping them in an expression
  (e.g. `|{ sy-msgv1 }|`) uses the **previous** values instead.

Display limits are separate from all of this: a dialog box fits 50 characters per
line and at most six lines (300 characters); the status bar shows whatever fits and
appends `...`.

## 6. The free-text variant destroys language independence

```abap
MESSAGE 'Customer is blocked' TYPE 'I'.       " works, but...
```

Only the first 300 characters are used, no long text can exist, and `WITH` / `INTO`
are not allowed. Critically, the system fields are filled non-specifically:
`sy-msgid` becomes `00`, `sy-msgno` becomes `001`, and `sy-msgv1`…`sy-msgv4` receive
the **first 200 characters** of the text. Any caller that logs or forwards messages
by ID/number — which is how function modules, BAPIs and application logs pass
messages around — can no longer identify or re-translate the message. Use a real
T100 message class unless the ID genuinely does not matter.

The one legitimate everyday use is displaying an already-formatted exception text:

```abap
CATCH cx_sy_arithmetic_error INTO DATA(lo_err).
  MESSAGE lo_err->get_text( ) TYPE 'I'.
```

## 7. `RAISING` is ignored if the caller does not catch it

```abap
MESSAGE e001(zmsg) RAISING invalid_input.
```

If the caller assigns a return code to `invalid_input` via `EXCEPTIONS`, this
behaves exactly like `RAISE` — no message is displayed, `sy-subrc` is set, and the
`sy-msg*` fields are filled for the caller to format later. If the caller **does
not** list that exception, the `RAISING` addition is silently ignored and the
message is sent normally — which in a report means your "safe" function module has
just terminated the calling program. The behaviour of your FM is therefore decided
by its callers, which is exactly why the documentation says to treat
`MESSAGE ... RAISING` as a statement for raising exceptions, not for sending messages.

Additional constraints:

- It cannot appear in the same processing block as `RAISE EXCEPTION` / `THROW` for
  class-based exceptions.
- `RAISING` combined with `INTO` is ignored — `INTO` wins.
- When a procedure is left by a message or a raised exception, **pass-by-value
  parameters are not returned** to the caller. Anything you filled into an
  `EXPORTING VALUE(...)` parameter before the message is lost.

## 8. Type `X` and invalid types

`MESSAGE ... TYPE 'X'` always produces the runtime error `MESSAGE_TYPE_X` with a
database rollback, in every context, including `INTO`-less background jobs. It is a
deliberate dump. Modern alternatives are `ASSERT`, `RAISE SHORTDUMP` and
`THROW SHORTDUMP`.

A message type that is not one of `A E I S W X` — for example from a dynamic
`TYPE lv_type` where the variable is lowercase or blank — raises the uncatchable
`MESSAGE_TYPE_UNKNOWN`. Dynamic types must be uppercase.

---

## Rules of thumb

1. In application logic, never send a message. Collect them (`BAPIRET2`, BAL) and
   let the presentation layer decide.
2. If you must resolve text, use `MESSAGE ... INTO` — and do not check `sy-subrc`
   after it.
3. Never use `W` where list processing can be active; it is an `E`.
4. Never use `E` in `START-OF-SELECTION` unless you actually mean "end the report now".
5. Keep placeholder values under 50 characters, or they are cut.
6. Prefer a T100 message class over free text so the ID survives the call chain.

## Sources

- [`MESSAGE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMESSAGE.html) — system fields, `WITH`, `DISPLAY LIKE`, uncatchable exceptions
- [Messages — Behavior](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_MESSAGES_TYPES.html) and [Dialog Processing](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_MESSAGE_DIALOG.html) — the behaviour table
- [Messages — List Processing](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_MESSAGE_LIST_PROCESSING.html) — the `W` to `E` conversion
- [Messages — Background Processing](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_MESSAGE_BATCH_JOB.html) — job log, `00 564`, rollback asymmetry
- [Messages — Updates](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_MESSAGE_UPDATE.html) — `MESSAGE_ROLLBACK_IN_POSTING`
- [Messages — Procedures](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_MESSAGE_PROCEDURE.html) — context inheritance, pass-by-value
- [`MESSAGE ... INTO`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMESSAGE_INTO.html), [`MESSAGE ... RAISING`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMESSAGE_RAISING.html), [`MESSAGE text`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMESSAGE_TEXT.html)

See also: [Exception Flow](../Exception%20Flow#readme) for `CLEANUP`/`RETRY`/`RESUME`,
and [Commit Work Events](../Commit%20Work%20Events#readme) for the LUW side of the
rollback behaviour described above.
