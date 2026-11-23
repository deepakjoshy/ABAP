# Function Modules & Function Groups | The Global Data That Outlives Your Call, the Return Code `0` That Means Both Success and Failure & the `RAISE` in a Subroutine That Hijacks Somebody Else's Function Module

Every ABAP developer calls function modules all day and almost nobody reads the
rules for the statement that does it. `CALL FUNCTION` is pattern-pasted from the
Function Builder, the generated `EXCEPTIONS` block is kept or deleted depending
on how busy the afternoon is, and the result compiles either way.

That is the problem. A method call is checked by the syntax check; a function
module call largely is not. The compiler will accept a misspelled formal
parameter, a misspelled exception name, and an `EXCEPTIONS` block whose numbers
make a raised exception indistinguishable from success. None of it is a syntax
error, and the failure mode in each case is *silence* --- a clean `sy-subrc = 0`
on a call that did not do what you asked.

On top of that sits the part nobody is taught: a function module does not run in
isolation. It runs inside a **function group**, and that function group's global
data is loaded once and then stays for the rest of the session. The second call
is not a fresh start.

> "The system field `sy-subrc` is set to 0 when a function module is called."
> -- [`CALL FUNCTION`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPCALL_FUNCTION.html)

> "Unlike method calls, formal parameters are not fully checked by the syntax
> check. Only parameters that are recognizably misspelled, e.g. by using certain
> special characters, lead to a syntax warning."
> -- [`CALL FUNCTION, parameter_list`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPCALL_FUNCTION_PARAMETER.html)

---

## 0. The shape of the thing

A **function module** is a procedure. A **function group** (function pool) is the
program that contains it. You never execute a function group; you call one of its
function modules, and the whole group is loaded to do it.

```abap
FUNCTION-POOL ydj_demo MESSAGE-ID ydj.   " the TOP include

DATA gt_buffer TYPE TABLE OF ydj_row.    " global to the WHOLE group

FUNCTION ydj_read_row.
*"----------------------------------------------------------------------
*" Local Interface:
*"  IMPORTING
*"     VALUE(IV_KEY) TYPE YDJ_ROW-KEY
*"  EXPORTING
*"     ES_ROW TYPE YDJ_ROW
*"  EXCEPTIONS
*"     NOT_FOUND
*"----------------------------------------------------------------------
  ...
ENDFUNCTION.
```

Two structural facts worth holding on to:

- The interface is **not in the source code**. It lives in the Function Builder
  and is echoed back as a comment block, which is why no amount of reading the
  `FUNCTION ... ENDFUNCTION` body tells you whether `ES_ROW` is passed by value
  or by reference.
- `gt_buffer` is visible to *every* function module in the group. The doc for
  [`FUNCTION`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPFUNCTION.html)
  puts it plainly: within a function module "There is also access to the formal
  parameters of the function module and to the global data types and data objects
  of the function pool."

`FUNCTION-POOL` itself "must be the first statement of a standalone program after
any include programs are resolved", and the master program's real name in the
repository is the group name with `SAPL` stuck on the front --- which is why your
short dump says `SAPLSCON` when you called `DATE_CHECK_PLAUSIBILITY`.

---

## 1. The headline: the function group is loaded once, and its data stays

This is the trap that produces the bug report nobody can reproduce.

When you call a function module, its function group is loaded into the
[internal session](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENINTERNAL_SESSION.html)
as a new program group, and then:

> "An additional program group is preserved for the entire lifetime of the
> internal session."

> "A loaded program exists for as long as the internal session exists. After
> returning from a program, its data objects are retained and are available when
> a procedure of the program is called again."

So the global data of a function group is, in practice, **session-scoped static
state**. `ENDFUNCTION` does not clean anything up. The next `CALL FUNCTION`
starts with everything the previous one left behind.

The classic shape of the bug is the lazy buffer:

```abap
" In the TOP include, so it outlives every single call:
DATA gs_customer TYPE ydj_cust.

FUNCTION ydj_get_customer_name.
  " "Only read it once" - a reasonable-looking optimization
  IF gs_customer IS INITIAL.
    SELECT SINGLE * FROM ydj_cust
      WHERE id = @iv_id
      INTO @gs_customer.
  ENDIF.
  ev_name = gs_customer-name.
ENDFUNCTION.
```

Call it for customer A, then for customer B: B gets A's name, `sy-subrc` is 0,
and no exception is raised. The guard tests whether the buffer is *filled*, not
whether it is filled **with the right key**. In a unit test that calls it once
this passes forever; in a loop over 5,000 documents every row after the first is
wrong.

Two things make it worse than an ordinary caching bug:

- **The lifetime is the internal session, not the call.** It survives
  `COMMIT WORK`, it survives the end of the dialog step, it survives the
  function module returning. It is reset by leaving the session --- a new
  transaction, a new `SUBMIT`, a new RFC call with its own session.
- **It is shared across the whole group.** Any other function module in the same
  group reads and writes the same `gs_customer`. Two function modules that have
  nothing to do with each other, written years apart, interfere because somebody
  put them in the same group.

The fixes, in order of preference:

| Fix | Why |
|---|---|
| Key the buffer: `IF gs_customer-id <> iv_id.` | One-line change, keeps the optimization, and is correct |
| A hashed/sorted internal table keyed on the input | Correct for many keys, not just the last one |
| Put the state in a class instance instead | Lifetime you control, and the test can create a fresh one |
| An explicit `ydj_reset` function module | Works, but only if every caller remembers --- they will not |

If you actually *want* state that outlives the session, that is a different
mechanism entirely --- see [Shared Objects](../Shared%20Objects#readme) and
[Table Memory](../Table%20Memory#readme).

---

## 2. `EXCEPTIONS exc = 0` is a documented way to silence a failure

The numbers after `EXCEPTIONS` are return codes, and they are yours to choose.
Including zero:

```abap
CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
  EXPORTING  date                      = lv_date
  EXCEPTIONS plausibility_check_failed = 0.   " <-- note the zero
```

> "If the value 0 is assigned to an exception, this indicates that the caller
> wants to ignore this exception. If the exception is raised in the function
> module, no runtime error occurs, but the exception cannot be handled."

The exception *is* raised. The function module *did* stop early. And `sy-subrc` is
`0`, which is the same value a completely successful call produces. There is no
second channel to check --- the information is gone.

Nobody writes `= 0` on purpose. It arrives two ways:

- Someone used `OTHERS = 0` to make a nagging warning go away.
- Someone renumbered the block while editing and left a gap.

**Rule: grep your codebase for `= 0` inside `EXCEPTIONS` blocks.** Every hit is
either a deliberate, commented decision or a bug. In the demo report, section 3
runs the identical call with `= 1` and with `= 0` on a genuinely invalid date and
prints both return codes next to each other.

### The obsolete short form makes this worse

There is an older spelling in which the `= n` may be omitted, and "Each exception
specified after `EXCEPTIONS` that is not assigned to an explicit return code
using `=` is assigned the value 1 implicitly." The documentation's verdict on it
is unusually blunt --- "This short form is extremely error-prone and should never
be used." --- and its own example shows why:

```abap
CALL FUNCTION func EXCEPTIONS = 4.
```

That is syntactically valid, and it does not do what it looks like. What it
really declares is exceptions named `=` and `4`, each implicitly getting
`sy-subrc = 1`. The doc: "Since exceptions called `=` are not possible, and
exceptions called `4` are unlikely, this call will almost certainly not catch any
exceptions, even though it is designed to catch every exception." Somebody meant
`OTHERS = 4`.

---

## 3. Leaving the exception out: `RAISE` dumps, `MESSAGE RAISING` does not

If the caller assigns no return code at all, behaviour depends on **which
statement the function module used to raise**, and the two are opposites:

| Raised in the FM by | Caller assigns a return code | Caller assigns nothing |
|---|---|---|
| `RAISE exc` | `sy-subrc` = that number | **Runtime error** `RAISE_EXCEPTION`, naming the exception |
| `MESSAGE ... RAISING exc` | `sy-subrc` = that number | The **message is sent**, and processing continues per the message type |

Verbatim:

> "If the call of an exception raised by `RAISE` does not assign a return code,
> the program is terminated with a runtime error."

> "If the call of an exception raised by `MESSAGE RAISING` does not assign a
> return code, the message is sent, and the system resumes in accordance with
> the message type."

This is why deleting the generated `EXCEPTIONS` block is a coin flip. With a
`RAISE`-based function module you get a short dump --- loud, traceable, fixed on
Monday. With a `MESSAGE RAISING`-based one you get whatever the message type
does: an `E` message in a dialog is a status line the user clicks past, and in a
background job the same `E` kills the job. Same source code, two completely
different production incidents. The message-type-is-context-dependent half of
that story is in [Messages](../Messages#readme).

Note also which statement the documentation prefers. `MESSAGE RAISING` "is to be
preferred in cases in which non-class-based exceptions still have to be used,
because it offers the option of adding a text to the exception" --- a plain
`RAISE` reaches the caller as a bare number and nothing else. Section 6 of the
demo shows the consequence: it reads `sy-msgid`/`sy-msgno`/`sy-msgty` before and
after a plain `RAISE` and they come back byte-for-byte unchanged --- still
holding the *previous* call's message. Reading those fields after a failed call
is only meaningful if you know which of the two statements raised.

---

## 4. A misspelled exception name is never checked at runtime

```abap
CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
  EXPORTING  date                     = lv_date
  EXCEPTIONS plausibility_check_faild = 1   " typo: faild
             OTHERS                   = 9.
```

This compiles. It also runs:

> "During program execution, a specified exception is not checked when a function
> module is called. Only the extended program check reports whether a specified
> exception is not declared in its interface."

So the exception that actually exists is no longer matched by name. If you wrote
`OTHERS`, it lands there --- your `WHEN 1` branch with the specific error message
becomes dead code and every failure reports the generic one. If you did *not*
write `OTHERS`, nothing is assigned to the real exception, and you are back in
section 3: a dump or a message, depending.

The same looseness applies to formal parameters, with one sharp edge:

> "A catchable exception is raised whenever a formal parameter is incorrect, and
> the name of the function module is specified by a constant or as a character
> literal."

> "If the name of the function module is specified by a variable, the
> specification of an incorrect formal parameter is ignored at runtime."

Read those together. A literal function module name gives you an exception for a
bad parameter name. Move that name into a variable --- the usual refactoring when
a call becomes configurable --- and the bad parameter is **silently dropped**.
The mandatory input your function module needs is simply never passed, and it
runs with an initial value. Demo section 5 does exactly this.

Which is the real argument for the extended program check on function module
calls: it is not a style tool here, it is the *only* static check there is.
See [Pragmas & Pseudo Comments](../Pragmas%20and%20Pseudo%20Comments#readme) for
what suppressing its findings does and does not do.

---

## 5. `error_message` --- the catch-all that catches what `EXCEPTIONS` cannot

There is a predefined exception name that does not appear in any interface:

```abap
CALL FUNCTION 'ZDJ_DO_SOMETHING'
  EXPORTING  iv_key        = lv_key
  EXCEPTIONS error_message = 99
             OTHERS        = 98.
IF sy-subrc = 99.
  " sy-msgid / sy-msgty / sy-msgno / sy-msgv1..4 are filled
ENDIF.
```

Specifying `error_message` changes what happens to *messages* sent during the
call --- including messages the function module sends with a plain `MESSAGE`
statement and no `RAISING` at all, and messages sent by the runtime framework:

| Message type | With `error_message = n` |
|---|---|
| `S`, `I`, `W` | "Messages of the type S, I, or W are not sent but are flagged in the log during background processing." |
| `E`, `A` | "Messages of the type E and A raise the exception `error_message` and set `sy-subrc` to `n_error`." Message fields are filled |
| `A` additionally | "In the case of messages of type A, the statement `ROLLBACK WORK` is also executed implicitly." |
| `X` | "Messages of the type X are not affected." Still a short dump |

This is the answer to *the SAP function module pops up an error message instead
of returning a return code*. It is also the one exception name that crosses call
levels:

> "it does not matter whether the message was sent in the current function module
> or in a module that is called by it. Unlike the exceptions raised by the
> statement `RAISE`, messages sent using the statement `MESSAGE` are propagated
> across call levels."

Two boundaries on that, both easy to trip over:

- **Sessions, not call levels, are the limit.** "Only messages from the current
  internal session are handled. Messages from programs called when the function
  module is processed are not handled." A function module that internally does
  `SUBMIT` or `CALL TRANSACTION` is outside the net --- compare
  [Program Calls](../Program%20Calls#readme) and
  [Batch Input](../Batch%20Input#readme).
- **The implicit `ROLLBACK WORK` is a landmine in the wrong place.** Because
  catching a type `A` message performs a rollback, it "is therefore forbidden in
  updates and when processing subroutines after `PERFORM ON COMMIT` or
  `PERFORM ON ROLLBACK`. It also produces runtime errors." So `error_message` is
  a *caller-side* tool for dialog and report code, not something to sprinkle
  inside update modules --- see [Update Task](../Update%20Task#readme).

And note it rolls back **your** LUW, not just the called module's work. If you
had registered update modules before the call, they are gone.

---

## 6. What the caller's variables hold after a failed call

The answer depends on a decision that is invisible at the call site: whether each
parameter is passed by value or by reference.

> "In pass by value, the content of an output parameter is assigned to the
> relevant actual parameter only if the function module is completed without
> errors."

> "If a procedure is exited by raising an exception, the content of the formal
> parameter for which the pass by value is defined is not assigned to the
> respective actual parameters."

By value, then: a failed call leaves your variable exactly as it was. Which is
*not* the same as empty --- if you are looping and did not `CLEAR`, it still
holds the previous iteration's result, and `sy-subrc <> 0` is the only thing
standing between that and your output file.

By reference it is worse: the function module has been writing **directly into
your variable** all along, so whatever it had built before it gave up is already
there. Demo section 2 runs two methods with identical bodies, differing only in
`VALUE( )`, and prints what the caller ends up with.

The full treatment of the by-value/by-reference decision --- including the
`EXPORTING`-parameter-not-initialized-on-entry trap, which hits function modules
exactly as it hits methods --- is in
[Parameter Passing](../Parameter%20Passing#readme).

---

## 7. `TABLES` parameters: standard tables only, plus a header line nobody wanted

`TABLES` is obsolete for new interfaces (use `CHANGING` or `EXPORTING` with a
table type), but SAP's own interfaces are full of it, so the rules still matter:

> "For `itab1`, `itab2`, ..., only standard tables can be specified."

So a sorted or hashed table cannot be passed at all --- which is a real
constraint once you have optimized your own code with
[Internal Table Keys](../Internal%20Table%20Keys#readme) and then need to hand
the result to an SAP function module.

> "If a specified table `itab1`, `itab2`, ... has a header line, this is also
> passed. Otherwise, the header line of the corresponding table parameter `t1`,
> `t2`, ... is initial after the call."

`TABLES` parameters always have a header line on the function module side, even
when your table has none. Old SAP code reads and writes that header line, which
is where *the function module filled the header line and my modern table has
nowhere to put it* comes from.

Data is passed by reference (except over RFC, where it is copied --- see
[RFC Calls](../RFC%20Calls#readme), which also covers the parameter-name
mismatches that are *ignored* rather than reported over the wire).

---

## 8. `RAISE` in a subroutine raises in somebody else's function module

This one is genuinely strange, and it is in the documentation:

> "If the exception is raised in a subroutine, the system searches for the first
> function module in the procedures of the preceding call stack. If one is found
> and the exception is defined in it, the system behaves as if the exception were
> raised in this function module. Otherwise, a runtime error occurs."

A `RAISE` inside a `FORM` does not belong to the `FORM`. It walks up the call
stack looking for a function module, and if that function module happens to
declare an exception with the same name, the exception is attributed to it ---
so a function module appears to raise an exception it never raises, from a line
of code it does not contain.

The surrounding guidance is unambiguous. `RAISE` "should be specified in function
modules only if the non-class-based exception is defined in the interface of the
function module", and "It is possible to specify `RAISE` in all other positions,
but it is not recommended."

---

## 9. Classic and class-based exceptions do not mix

If a function module declares class-based exceptions (the *Exception Class*
checkbox in the Function Builder, which shows up as a `RAISING` comment under
`FUNCTION`), the choice is made for the caller:

> "The addition `EXCEPTIONS` cannot be specified in the call if `RAISING` is used
> to declare class-based exceptions in the parameter interface of the called
> procedure."

So it is `TRY`/`CATCH` or nothing --- no return codes. And on the implementation
side the two statements cannot share a processing block at all:

> "This form of the statement `RAISE` cannot be used in the same processing block
> as the statement `RAISE EXCEPTION` or the addition `THROW` in a conditional
> expression to raise class-based exceptions."

Which means migrating one function module from classic to class-based exceptions
is all-or-nothing per function module, and it is a **breaking interface change**
for every caller.

One more rule worth knowing, because its symptom points at the wrong place:

> "Undeclared exceptions cannot exit a procedure but can violate the interface if
> they are not handled within the procedure. A violation of the interface raises
> an exception of the predefined class `CX_SY_NO_HANDLER`, whose exception object
> contains a reference to the original exception in the attribute `PREVIOUS`."

Same mechanism as the one in [Events](../Events#readme). The real error is in
`PREVIOUS`; the doc's advice is to fix the procedure that failed to declare or
handle it rather than to handle `CX_SY_NO_HANDLER`. See also
[Exception Texts](../Exception%20Texts#readme) and
[Exception Flow](../Exception%20Flow#readme).

---

## 10. The modern-ABAP conveniences that a function module call does not have

Easy to forget when you have been writing modern ABAP all day:

```abap
" Does not work in a function module call:
CALL FUNCTION 'ZDJ_READ'
  IMPORTING es_row = DATA(ls_row).        " no inline declarations
CALL FUNCTION 'ZDJ_READ'
  EXPORTING is_key = VALUE #( id = '1' ). " no generic #
```

> "Unlike in method calls, no writable expressions and no inline declarations can
> be specified."

> "Unlike in method calls, a generic type specification `#` is not possible when a
> constructor expression is specified. This is because the typing of the
> parameters is not determined until runtime."

That last sentence is the whole reason for all of section 4 as well: the
parameter types are not known at compile time, so there is nothing for `#` to
resolve against and nothing for the syntax check to verify. Also:
"Substring access is not possible on an actual parameter of type `string` or
`xstring` specified after `EXPORTING`."

`IS SUPPLIED` *does* work inside a function module, the same way it does in a
method, to distinguish *not passed* from *passed as initial*.

---

## 11. Interface work areas: shared state whose owner depends on call order

The last piece of function-group weirdness, and the one with the best worked
example in SAP's own documentation. Data objects declared with `TABLES` (or the
obsolete `DATA ... COMMON PART`) in a program are *interface work areas*:

> "They are only created once per program group and are shared by all programs of
> a program group together."

And which program group a given program lands in is not fixed:

> "The assignment of a program to a program group, and thus the definition of the
> other programs with which it shares the interface work area, can depend on the
> usage sequence."

The documented example has a module pool, a function group and a subroutine pool
that all declare `TABLES dbtab`. Whether the subroutine pool shares its work area
with the module pool or with the function group depends on which one called it
first --- i.e. on user actions and data. The doc's conclusion: "It is not
possible to rely on a specific assignment."

The rule that falls out of this is simple, and it is SAP's own:

> "Only call procedures externally that are intended for external calls."

> "The only procedures designed for external calls are the visible methods of
> global classes and function modules."

`PERFORM ... IN PROGRAM` is the construct this is aimed at. Note the asymmetry
that makes function modules the safe option: "Class pools and function pools (and
external calls of global class methods or function modules) always create a new
program group when loaded", whereas for other program types "the programs are
loaded into the program group of the calling program."

---

## Quick reference

| Situation | Result |
|---|---|
| `CALL FUNCTION` succeeds | `sy-subrc` = 0 |
| `RAISE exc`, caller assigned `n` | `sy-subrc` = `n`, FM terminated immediately |
| `RAISE exc`, caller assigned `0` | `sy-subrc` = 0. Raised, unhandleable, invisible |
| `RAISE exc`, caller assigned nothing | Runtime error `RAISE_EXCEPTION` |
| `MESSAGE ... RAISING exc`, nothing assigned | Message sent, flow continues per message type |
| Exception name misspelled | Not checked at runtime; falls into `OTHERS`, or behaves as unassigned |
| Formal parameter wrong, FM name a literal | Catchable exception |
| Formal parameter wrong, FM name in a variable | **Ignored at runtime** |
| `EXCEPTIONS exc` with no `= n` (obsolete short form) | "If an exception is raised, the value 1 is assigned to `sy-subrc` implicitly." |
| `error_message = n`, FM sends `E`/`A` | `sy-subrc` = `n`, `sy-msg*` filled; `A` also does an implicit `ROLLBACK WORK` |
| FM declares class-based exceptions | `EXCEPTIONS` is not allowed at the call --- `TRY`/`CATCH` only |
| Output parameter by value, call failed | Actual parameter untouched (keeps its previous content) |
| Output parameter by reference, call failed | Actual parameter holds whatever the FM wrote before failing |
| `CALL FUNCTION ... IN UPDATE TASK` | "After the registration of an update function module using `CALL FUNCTION ... IN UPDATE TASK`, `sy-subrc` is undefined." |
| Second call into the same function group | Global data is still there from the first call |

### Review checklist for a `CALL FUNCTION`

1. Is there an `EXCEPTIONS` block at all, and is every number non-zero?
2. Is `OTHERS` present, and is the `sy-subrc` actually evaluated afterwards?
3. Does the function module raise with `RAISE` or `MESSAGE RAISING`? (Decides
   what happens if you get it wrong.)
4. Is `error_message` needed because the module sends messages directly?
5. Are output parameters `CLEAR`ed before the call, or at least not read when
   `sy-subrc <> 0`?
6. Has the extended program check been run on this call? Nothing else checks the
   names.
7. Does the called group hold state across calls --- and if so, is this the
   first call in the session, or the thousandth?

---

## Sources

- [`CALL FUNCTION`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPCALL_FUNCTION.html)
  --- syntax forms, `sy-subrc`, the dynamic-name security hint
- [`CALL FUNCTION, parameter_list`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPCALL_FUNCTION_PARAMETER.html)
  --- `EXPORTING`/`IMPORTING`/`TABLES`/`CHANGING`, the full `EXCEPTIONS` rules,
  the `= 0` hint, `error_message`, the differences from method calls
- [`CALL FUNCTION, EXCEPTIONS` (obsolete short form)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPCALL_FUNCTION_EXC_SHORT_FORM.html)
  --- the implicit `sy-subrc = 1`
- [`RAISE`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPRAISE_EXCEPTION.html)
  --- the four outcomes, the subroutine-walks-the-stack rule, the no-mixing rule,
  pass-by-value parameters not assigned
- [`MESSAGE ... RAISING`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPMESSAGE_RAISING.html)
- [`FUNCTION`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPFUNCTION.html)
  --- access to function pool global data, `IS SUPPLIED`
- [`FUNCTION-POOL`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPFUNCTION-POOL.html)
  --- include structure, the `SAPL` prefix, `MESSAGE-ID`
- [Programs in the Internal Session](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENINTERNAL_SESSION.html)
  --- program groups, data objects retained for the session, interface work areas
- [Internal and External Procedure Calls](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENINTERN_EXTERN_PROC_CALL_GUIDL.html)
  --- the external-call rule and the shared-work-area example
- [Class-Based Exceptions in Procedures](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENEXCEPTIONS_PROCEDURES.html)
  --- `CX_SY_NO_HANDLER`, what can and cannot be propagated

---

## Related notes in this repo

[Parameter Passing](../Parameter%20Passing#readme) for the by-value/by-reference
decision that decides half of section 6,
[Messages](../Messages#readme) for why the message type that gets sent in section
3 is not always the one that was asked for,
[Update Task](../Update%20Task#readme) for the update modules that `error_message`
can roll away under you,
[RFC Calls](../RFC%20Calls#readme) for what changes when the same
`CALL FUNCTION` crosses a system boundary,
[Exception Flow](../Exception%20Flow#readme) and
[Exception Texts](../Exception%20Texts#readme) for the class-based world section 9
points at,
[Program Calls](../Program%20Calls#readme) and
[Batch Input](../Batch%20Input#readme) for the session boundary that
`error_message` does not cross,
[Shared Objects](../Shared%20Objects#readme) and
[Table Memory](../Table%20Memory#readme) for state you actually intend to keep,
[Internal Table Keys](../Internal%20Table%20Keys#readme) for the sorted and hashed
tables a `TABLES` parameter will not accept,
[Events](../Events#readme) for the other place `CX_SY_NO_HANDLER` shows up, and
[Pragmas & Pseudo Comments](../Pragmas%20and%20Pseudo%20Comments#readme) for the
extended program check that is the only static check a `CALL FUNCTION` gets.
