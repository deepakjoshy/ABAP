# Spool & print parameters — the `VALID` flag that turns Cancel into a printout, two validity flags that disagree only in background, and a spool number that arrives on the first `WRITE`

Printing from ABAP is four lines of code that everyone copies:

```abap
CALL FUNCTION 'GET_PRINT_PARAMETERS'
  IMPORTING out_parameters = ls_pri.

NEW-PAGE PRINT ON PARAMETERS ls_pri NO DIALOG.
WRITE: / 'something'.
NEW-PAGE PRINT OFF.
```

That compiles, runs, and produces a spool request. It is also wrong in three
independent ways, none of which raises an exception or sets `sy-subrc`:

1. it never reads `VALID`, so a user who presses **Cancel** gets a printout
   anyway (trap 1) — and the flag it *should* read in background is a
   different one (trap 2);
2. it never captures the spool number, and the obvious place to read it is
   too early (trap 3);
3. called twice without an intervening `PRINT OFF` it raises
   `CX_SY_NESTED_PRINT_ON`, so it cannot be a reusable helper (trap 4).

This note is about what the copied version left out.

## The cast

| Object | Role |
|---|---|
| `GET_PRINT_PARAMETERS` | builds a consistent parameter set, optionally via a dialog box. The only documented way to fill `PRI_PARAMS` |
| `PRI_PARAMS` | DDIC structure of spool parameters — device, copies, retention, format |
| `ARC_PARAMS` | DDIC structure of ArchiveLink parameters, needed only when archiving |
| `NEW-PAGE PRINT ON` | redirects list output of **this** program into a spool list |
| `SUBMIT ... TO SAP-SPOOL` | redirects the basic list of **another** program into a spool list |
| `SET_PRINT_PARAMETERS` | sets a subset — see trap 6 |

Two statements consume the same `PRI_PARAMS`, and they are not
interchangeable: they suppress their dialog with different additions and they
report their spool number through different channels.

---

## Trap 1: ignoring `VALID` does not fail — it silently prints with defaults

This is the headline. `VALID` is the output parameter that tells you whether
you may print at all, and the documentation is explicit about what blank means:

> "If X, all spool parameters or archiving parameters are complete and printing or archiving is possible. If blank, the structures are empty, and printing or archiving is not possible. VALID is blank if Cancel is used to exit the spool dialog box."

So a user who presses **Cancel** gets `VALID = ' '` and — the important half —
`OUT_PARAMETERS` comes back *empty*, because the structure is all-or-nothing:

> "Set of spool parameters in a structure of the type PRI_PARAMS. Either complete or empty."

Now follow what happens if you skip the `IF`. You pass that empty structure to
`NEW-PAGE PRINT ON`, and it does **not** complain:

> "If the structures pri_params or arc_params are initial, the spool parameters or archiving parameters created by a call of the function modules GET_PRINT_PARAMETERS with initial input values are used."

An initial `PRI_PARAMS` is not an error condition. It is a documented request
for the defaults. So the user's *no, don't print this* is converted into
*print it to whatever device my user master record names*, with no message,
no `sy-subrc`, and a perfectly normal-looking spool request in `SP01`.

The structure itself carries no trace of the refusal — a cancelled
`PRI_PARAMS` and a never-filled one are byte-identical. `VALID` is the *only*
place that information exists, and it is a separate variable that is easy not
to receive at all. Part 2 of the demo proves the equality locally.

The same is true on the `SUBMIT` side, where SAP words it as a warning about
the dialog rather than about your code:

> "If the default spool dialog box is used, inconsistent spool parameters may be passed to the called program if the user exits the GUI window using Cancel."

**Rule:** the `IF` is not defensive programming, it is the only thing standing
between a cancelled dialog and an unwanted printout. SAP's own example in the
keyword documentation has it (`IF valid_flag = 'X' AND sy-subrc = 0.`) — the
version that circulates on the internet usually does not.

---

## Trap 2: there are *two* validity flags, and they disagree exactly where you cannot ask a human

`GET_PRINT_PARAMETERS` returns `VALID` **and** `VALID_FOR_SPOOL_CREATION`.
Almost nobody reads the second one. It means something genuinely different:

> "If X, enough spool parameters are available to create a spool request. There is no guarantee, however, that this request can be printed or archived."

and then the sentence that makes this operational:

> "This is different from VALID only if the spool dialog box is not displayed. If the spool dialog box is displayed, VALID_FOR_SPOOL_CREATION is filled just like VALID."

Read that carefully. The two flags are identical whenever a user is standing
there to answer — and they diverge **only** when the dialog is suppressed,
which is to say in background processing, in a job, in an RFC call: precisely
the situations where nobody can be asked and where losing the output silently
is worst.

The practical consequence is a wrong refusal rather than a wrong print. A
background job that checks only `VALID` will skip creating a spool request
that would have been created perfectly well and held in `SP01` for later —
because *printable* is a stricter condition than *spoolable*. The output is
gone, and the job's log says nothing interesting.

`spool_params_ok( )` in the demo is the guard that covers both, and switches
on whether a dialog was actually shown:

- dialog shown → `VALID` is the whole answer (the docs say so)
- dialog suppressed → accept `VALID_FOR_SPOOL_CREATION`; a held spool request
  is a normal background outcome

Both branches check `sy-subrc` first, because the classic `EXCEPTIONS` of this
function module are mapped by hand and an unmapped one leaves your structure
untouched.

---

## Trap 3: the spool number arrives on the first output statement, from a different place for each statement

`sy-spono` is where the spool request number shows up. It is typed `n`
length 10 — and SAP's own system-field table has a typo in the description,
which is a fair indication of how much attention this field gets:

> "Contains the 1o digit spool number of the spool request when spooling lists."

Being `n` matters: its initial value is `0000000000`, not blank — so it never
looks empty the way a blank character field would. **Reading note:** nothing
in the documentation says the field is cleared when spooling ends, so a stale
value reads exactly like a real one; part 3 of the demo prints the
before-value rather than asserting what it contains.

The timing is the trap. `NEW-PAGE PRINT ON` does not assign it:

> "The first output statement after NEW-PAGE PRINT ON opens a new spool request and writes to a spool list in the SAP spool system. The number of the spool request is placed after sy-spono by the first output statement."

So the natural shape — switch spooling on, grab the number, log it, then write
the list — captures the *previous* value. On the first run of a session that
is zeros; on a later run it is some other request's number. Both are
plausible, neither is yours. **Reading note:** the docs state only that the
first output statement assigns it; that a read taken *between* `PRINT ON` and
that statement therefore cannot see the new number is my inference from that
sentence, which is why part 3 of the demo samples `sy-spono` at four points
and prints the measurements rather than asserting the answer.

A corollary falls out of the same sentence: a `PRINT ON` / `PRINT OFF` pair
with no output statement between them opens no spool request at all. An empty
result set means no `WRITE`, which means no spool request, which means nothing
to report — and no error either.

`PRINT OFF` then re-points the field, for the nested case:

> "When the system returns to the spool list, the system field sy-spono is switched to the number of the associated spool request directly when the statement NEW-PAGE PRINT OFF is executed."

### And `SUBMIT` does not use `sy-spono` at all

> "After using TO SAP-SPOOL the spool number of the created spool request is contained in a SPA/GPA parameter named SPI."

Two statements that both create spool requests, two completely different
reporting channels. After `SUBMIT ... TO SAP-SPOOL` you need:

```abap
GET PARAMETER ID 'SPI' FIELD lv_spono.
```

and `sy-spono` still holds whatever it held before. (SPA/GPA parameters have
their own semantics — see the Program Calls note, which covers why they are
not shared across parallel sessions.)

---

## Trap 4: nesting raises a catchable exception, and catching it is the wrong fix

A second `PRINT ON` on top of an open one is not allowed:

> "It is not possible to use NEW-PAGE PRINT ON to stack another spool list level directly on to a spool list level created using NEW-PAGE PRINT ON."

> "If the current list is a spool list created using NEW-PAGE PRINT ON and the addition NEW-SECTION is not used, a catchable exception of the class CX_SY_NESTED_PRINT_ON is raised."

Runtime error `NESTED_PRINT_ON`. This is the failure mode of a *reusable*
print helper: it works the first time it is called and raises the second time,
so it passes every single-document test and fails on the first batch run.

The instinctive fix — wrap it in `TRY`/`CATCH` — is explicitly the worse of
the two options:

> "The addition NEW-SECTION can be used to avoid the exception CX_SY_NESTED_PRINT_ON. When using NEW-SECTION, the output can also be continued into the previous spool list, which is not possible when an exception is handled with CATCH."

So `CATCH` stops the dump and loses the output; `NEW-SECTION` keeps both. Use
the addition, not the handler.

---

## Trap 5: `NEW-SECTION` is one statement with two opposite outcomes, chosen by data

Having been told to use `NEW-SECTION`, note that it does not do one thing. The
documentation splits it into two cases with the same syntax:

If the spool parameters match the current list **and** `PRNEW` is initial:

> "no new spool request is created and the output is written to the current spool list"

with a detail worth knowing before someone counts pages:

> "If the spool parameters define the output of a cover sheet, the cover sheet is spooled again before the following output as a spacer sheet."

If the parameters differ **or** `PRNEW` is set:

> "the current spool request is closed implicitly by NEW-PAGE PRINT OFF and a new spool request is created"

So **how many spool requests your program produces is decided by the contents
of `pri_params`, not by the shape of your code.** One request or N requests,
same statement. And `PRNEW` is not a field you would have thought about,
because its default pushes you toward N:

> "If X (default) a new spool request is created, otherwise the system attempts to attach the spool request to an existing request, works only if LIST_NAME, DESTINATION, COPIES, and LAYOUT match and PROTECT_LIST is empty."

Four fields must match *and* a fifth must be empty before attaching works. If
any one of them differs you get a new request instead — silently, since this
is the documented behaviour rather than an error.

---

## Trap 6: the `PRI_PARAMS` components are not yours to set

The single most copied line in SAP printing code is some variant of
`ls_pri-pdest = 'LP01'.`, poking a component directly. The parameter reference
says not to, twice. First, in the table header that lists the components:

> "The third column contains the name of the component in the structure PRI_PARAMS whose content, however, cannot be modified directly in a program."

Then, as a closing hint, with the reason:

> "The values of the components of the structure PRI_PARAMS are usually intended for internal use only and do not always match the values specified directly, such as in the addition LINE-SIZE."

That is the part that bites: the component is not simply a copy of what you
would pass in. `LINSZ` is named after `LINE-SIZE` and is not guaranteed to
hold the number you would have written after `LINE-SIZE`. Set parameters by
passing them to `GET_PRINT_PARAMETERS` as *input parameters* and using what it
hands back.

Two further asymmetries in the same place. Some input parameters have no
component at all (`DRAFT`, `NO_FRAMES`, `PROTECT_LIST`, `DEFAULT_SPOOL_SIZE`,
`SUPPRESS_SHADING`, `UC_DISPLAY_MODE`, `WITH_STRUCTURE`, `REPORT`):

> "The input parameters of GET_PRINT_PARAMETERS that do not have a component in the structure PRI_PARAMS are not passed to a spool request explicitly during NEW-PAGE PRINT ON and SUBMIT TO SAP-SPOOL and are defined internally by the function module instead."

and consequently the other function module cannot reach them:

> "Using SET_PRINT_PARAMETERS only allows the setting those spool parameters that are stored in components of the PRI_PARAMS structure."

So `SET_PRINT_PARAMETERS` is strictly less capable than
`GET_PRINT_PARAMETERS`: `NO_FRAMES` ("No frame characters") and `DRAFT`
("Text only") are not things you can switch on after the fact.

---

## Trap 7: *when* it prints is the user's setting, not your program's

Three of the most consequential parameters default out of the user master
record, which means the same program behaves differently per user and the
developer is usually the one who cannot reproduce the ticket.

| Parameter | Component | Documented default |
|---|---|---|
| `DESTINATION` | `PDEST` | "default taken from user master data" |
| `IMMEDIATELY` | `PRIMM` | "default taken from user master data" |
| `RELEASE` | `PRREL` | "default taken from user defaults" |
| `EXPIRATION` | `PEXPI` | "default is 8" |
| `SAP_COVER_PAGE` | `PRSAP` | `D` — depends on printer settings |
| `PRIORITY` | `PRIOT` | "1 (high) to 9 (low), default is 1" |

`IMMEDIATELY` is the one that generates support calls, because it is a
three-way flag and not a boolean:

> "If X the spool request is sent immediately, if A the spool request is printed at a later time (only for non-front-end printers), if blank the spool request must be printed manually, default taken from user master data."

Blank does not mean *later*, it means **nothing will ever come out of a
printer unless a human goes into `SP01` and prints it**. A developer whose
profile sets `X` sees paper every time and cannot reproduce *the report
doesn't print* — which, for the user with a blank `PRIMM`, is a completely
accurate bug report about a correctly functioning program.

`RELEASE` deserves a glance too, since it is the difference between a
recoverable and an unrecoverable output:

> "If X, spool request is deleted immediately after output, else after EXPIRATION; default taken from user defaults."

With `PRREL = 'X'` there is no reprint. The request is gone after it prints.

Part 1 of the demo prints these components for the current user, so you can
see whose defaults you have actually been testing against.

---

## Trap 8: the list that cannot be spooled at all

Two documented ways to produce output that simply does not fit.

`LINE_COUNT` has a value you would naturally try and that is rejected:

> "0 (unlimited number of lines) is not possible; the maximum number depends on LAYOUT; default is set internally."

And in `MODE = 'BATCH'`, the format is taken from the target program's
`REPORT` statement and locked:

> "If this executable program contains the additions LINE-COUNT or LINE-SIZE in the REPORT statement, they are used as non-modifiable values in the spool dialog box."

> "In this case, the corresponding input fields in the spool dialog box are not ready for input."

followed by the actual failure:

> "If these values exceed the maximum values defined by LAYOUT, the list cannot be spooled."

So a report declared `REPORT z... LINE-SIZE 255.` can be unspoolable on a
`LAYOUT` whose maximum width is narrower, and the format fields are greyed out
so the user cannot fix it from the dialog. The fix is the page format, not the
program. Related, and useful when a downstream parser is involved:

> "If X, line break forced after the 255th column, default blank."

(that is `DEFAULT_SPOOL_SIZE`, which is `GET_PRINT_PARAMETERS`-only — see
trap 6.)

---

## Trap 9: the `PRINT OFF` you did not write, and the one that does nothing

Spooling ends on its own, in more places than you would expect:

> "At the end of the program and at every list event AT LINE-SELECTION, AT PFnn, and AT USER-COMMAND, the statement NEW-PAGE PRINT OFF is executed implicitly."

> "A spool list level created using NEW-PAGE PRINT ON can be closed by either NEW-PAGE PRINT OFF, NEW-PAGE PRINT ON NEW-SECTION, the end of the program, or by leaving a dynpro sequence."

So spooling started in `START-OF-SELECTION` does not survive into
`AT LINE-SELECTION`, and leaving a dynpro sequence closes it too. SAP's advice
is to be explicit anyway:

> "Each statement NEW-PAGE PRINT ON should be closed explicitly using NEW-PAGE PRINT OFF before the program end or before leaving a dynpro sequence."

In the other direction, `PRINT OFF` is a no-op more often than you would
think. It is ignored on levels it did not create:

> "NEW-PAGE PRINT OFF is ignored by spool list levels not been created using NEW-PAGE PRINT ON."

and it has no power over the `SUBMIT` variant at all:

> "It is not possible to switch from the spool list to the screen list in the called program. The statement NEW-PAGE PRINT OFF does not affect a spool list level created using SUBMIT TO SAP-SPOOL."

A called program that tries to stop spooling partway through and continue on
screen cannot. The `PRINT OFF` activates, runs, and changes nothing.

---

## Trap 10: the default is a dialog, and the dialog is the problem

Neither statement suppresses its popup by default, and they use different
additions to do it — `NO DIALOG` for `NEW-PAGE PRINT ON`:

> "The addition NO DIALOG suppresses the spool dialog box that by default appears when using the addition PRINT ON."

and `WITHOUT SPOOL DYNPRO` for `SUBMIT`:

> "The addition WITHOUT SPOOL DYNPRO suppresses the spool dialog box that is displayed as standard when the addition  TO SAP-SPOOL is used."

The documentation is unusually insistent that you use them:

> "These additions must always be used as shown here. It is particularly important that the standard spool dialog box is suppressed."

The reason is a navigation dead end, not aesthetics:

> "When using the default spool dialog box, the Back function is not available because the system cannot return to before a statement after spooling has been switched on by such a statement. Printing can only be exited using Exit, which ends the entire program."

> "If the user exits the GUI window by choosing Cancel, inconsistent spool parameters can be produced."

So the built-in dialog offers the user a Cancel that produces inconsistent
parameters and a Back that does not exist. The documented pattern is to
suppress it and show your own dialog by calling `GET_PRINT_PARAMETERS`, whose
whole job is to hand back a *consistent* set plus a flag saying so:

> "This function module has an output parameter VALID that indicates the consistency of the spool parameters created."

### The syntax-check warning most people never read

Suppressing the dialog without supplying parameters is almost illegal:

> "The use of the addition NO DIALOG without simultaneously passing spool parameters is allowed only outside of ABAP Objects and produces a warning in the syntax check. In other objects, the spool parameters are derived from the user master record, if possible."

"If possible" is doing a lot of work in that sentence, and the same rule
applies to `SUBMIT`:

> "Use of the addition WITHOUT SPOOL DYNPRO without simultaneously passing spool parameters is only allowed outside ABAP objects. The spool parameters are then taken from the user master record as far as possible."

In a class it is simply not available, which is the correct outcome: pass
parameters.

---

## Quick reference

| You want | Do this |
|---|---|
| Spool this program's own list | `NEW-PAGE PRINT ON PARAMETERS p NO DIALOG.` … `NEW-PAGE PRINT OFF.` |
| Spool another program's basic list | `SUBMIT r TO SAP-SPOOL WITHOUT SPOOL DYNPRO SPOOL PARAMETERS p.` |
| Get the spool number (own list) | read `sy-spono` **after** the first output statement |
| Get the spool number (`SUBMIT`) | `GET PARAMETER ID 'SPI' FIELD n.` |
| Ask the user, safely | call `GET_PRINT_PARAMETERS` with `MODE = 'PARAMS'`, check `VALID` |
| Run in background | `NO_DIALOG = 'X'`, check `VALID_FOR_SPOOL_CREATION` |
| Format from the target program | `MODE = 'BATCH'` + `REPORT = '<prog>'` |
| Inspect live spool parameters | `MODE = 'CURRENT'` |
| Append to an open spool list | `NEW-PAGE PRINT ON NEW-SECTION …` (see trap 5) |
| Archive as well as print | `ARCHIVE_MODE = '3'` + consistent `ARC_PARAMS` |

`MODE` values, verbatim from the control-parameter table: `BATCH`, `CURRENT`,
`DEFVALS`, `DISPLAY`, `PARAMS`, `PARAMSEL`. `PARAMS` is the
> "Standard setting, the user can choose Print or Cancel on the spool dialog box."

`DISPLAY` shows them read-only; `DEFVALS` "Always returns the default values";
`CURRENT` is the one for asking *what am I spooling with right now*, since it
> "is used to determine the current spool parameters after spooling has been activated. If nothing is being spooled, the default values are returned."

In `BATCH`, note the cosmetic tell that you are not printing:
> "The function Save is displayed on the spool dialog box instead of Print."

## Odds and ends worth knowing

- **Archiving is all-or-nothing.** `ARCHIVE_MODE` is "If 1 print only
  (default), if 2 archive only, if 3 print and archive", and if `pri_params`
  asks for archiving then `ARC_PARAMS` must be supplied too, consistently and
  completely. For long archived lists the docs suggest `PRINT-CONTROL
  INDEX-LINE`: "When archiving long lists, it may be useful to write index
  information to the list using PRINT-CONTROL INDEX-LINE."
- **Spool actions are authorization-checked.** `AUTHORITY`/`PRBER` is the
  "Authorization value for authorization object S_SPO_ACT", so a spool request
  can be created and still not be displayable by its own creator.
- **Do not combine `TO SAP-SPOOL` with `VIA SELECTION-SCREEN`.** The list
  options only apply to the first execution: "the basic list is displayed as a
  screen list and not as a spool list when the program is called again" — the
  output lands on screen instead of in the spool, which is covered from the
  `SUBMIT` side in the Program Calls note.
- **The obsolete additions.** Both statements accept an older inline syntax
  (`DESTINATION`, `IMMEDIATELY`, `KEEP IN SPOOL` …). The docs are blunt:
  "there is a range of other additions for an obsolete specification of spool
  parameters, which should no longer be used", and "The same obsolete
  additions are available for the statement SUBMIT TO SAP-SPOOL as to the
  statement NEW-PAGE PRINT ON." If a snippet names the printer inside the
  statement, it predates `PRI_PARAMS`.

## Transcription note

Quotes are verbatim from the pages listed below, with whitespace normalised
and SAP's own `[text](url)` link markup dropped. Three quoted spans reproduce
errors that are in SAP's source text and are not mine: "the 1o digit spool
number", "the structures a empty", and "the setting those spool parameters".
Bold emphasis inside quotes is never SAP's.

## Sources

- ABAP keyword documentation 7.58, `NEW-PAGE, spool_options` — `PRINT ON` /
  `PRINT OFF`, `NEW-SECTION`, `CX_SY_NESTED_PRINT_ON`, the `sy-spono` timing,
  the initial-structure fallback, the dialog hints:
  <https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapnew-page_print.htm>
- ABAP keyword documentation 7.58, `Lists - Overview of All Spool Parameters`
  — every parameter and default, `MODE` values, `VALID` vs
  `VALID_FOR_SPOOL_CREATION`, the "cannot be modified directly" rule:
  <https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abenprint_parameters_overview.htm>
- ABAP keyword documentation 7.58, `SUBMIT, list_options` — `TO SAP-SPOOL`,
  the SPA/GPA parameter `SPI`, the `VIA SELECTION-SCREEN` caveat:
  <https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapsubmit_list_options.htm>
- ABAP keyword documentation 7.58, `SUBMIT, spool_options` —
  `WITHOUT SPOOL DYNPRO`, the ABAP-Objects restriction, the obsolete additions:
  <https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapsubmit_print_parameters.htm>
- ABAP keyword documentation 7.58, `ABAP System Fields` — `sy-spono` typed
  `n` length 10:
  <https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abensystem_fields.htm>

## Related notes in this repo

- [List Processing](../List%20Processing#readme) — what `WRITE` actually
  produces, and the `NEW-PAGE` behaviours on the screen-list side
- [Program Calls](../Program%20Calls#readme) — `SUBMIT`, `list_options` and
  SPA/GPA parameters, the channel trap 3 relies on
- [Background Jobs](../Background%20Jobs#readme) — `VIA JOB`, and the spool
  request it invents if you do not pass parameters
- [Authorization Checks](../Authorization%20Checks#readme) — the object behind
  the `AUTHORITY` parameter
- [Messages](../Messages#readme) — why `sy-subrc` must be captured immediately
  after the call that sets it, as the demo does
