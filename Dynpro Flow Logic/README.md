# Dynpro Flow Logic — The Module That Runs Before Your Checks, the Transport You Postponed and the Error That Freezes the Screen

The flow logic is not ABAP. It is a second, much smaller language that lives on the
**Flow Logic** tab of the Screen Painter (SE51), and it is the only thing that decides
*when* a screen field reaches your program and *which* fields the user may still type
into after you reject their input.

> "The dynpro flow logic is the procedural part of a dynpro. It is created using an
> ABAP-like programming language in the Screen Painter on the Flow Logic tab page."
> — [ABAP keyword documentation, Statements in the Dynpro Flow Logic](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_DYNPROS_DYNPRO_STATEMENTS.html)

The whole language is four things: call a module (`MODULE`), control transport and
error handling (`FIELD` / `CHAIN`), loop a table control (`LOOP`), and embed a
subscreen (`CALL SUBSCREEN`). That is it. Everything else happens in the ABAP program.

Two statements are spelled the same on both sides of the fence and mean different
things, which the documentation warns about explicitly:

> "The `MODULE` statement of the dynpro flow logic must not be confused with the
> identically named statement `MODULE` for defining dialog modules in the ABAP program."
> — [ABAP keyword documentation, dynpro - MODULE](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/dynpmodule.html)

This note is about the parts that fail silently. For screen *properties*
(`LOOP AT SCREEN` / `MODIFY SCREEN`) see
[Screen Modification](../Screen%20Modification#readme); for what `MESSAGE` does to the
program flow in PBO/PAI see [MESSAGE](../Messages#readme).

---

## Trap 1: adding a FIELD statement postpones the transport, and the module above it now reads the previous dialog step

By default every field arrives before any of your code runs. One `FIELD` statement
changes that for the field it names — and only for that field:

> "By default, all dynpro fields are transported to the ABAP program directly at the
> event PAI and before the processing of the corresponding event block. If one or more
> `FIELD` statements are used, only those dynpro fields are transported directly at the
> event PAI that are not specified after a `FIELD` statement."
> — [ABAP keyword documentation, FIELD, Data Transport at PAI Time](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYNP_FIELD_DATA_TRANSPORT.html)

So the moment someone adds a validation

```
PROCESS AFTER INPUT.
  MODULE user_command_0100.          " reads customer_id
  FIELD customer_id MODULE check_customer.
```

`customer_id` stops being transported at the start of PAI and is transported at the
`FIELD` statement instead — *below* `user_command_0100`. The module above does not
fail. It reads a stale value:

> "A dynpro field must not be used in a PAI module, before it is passed by the dynpro.
> Otherwise, the ABAP field contains the same value as at the end of the previous
> dialog step."
> — same page

The previous dialog step's value is usually a *plausible* value — the last customer the
user looked at — which is why this survives testing by one person clicking through one
record. It shows up as "it saved the wrong order" on the second click of a session.

The ordering rule when a field appears more than once:

> "If a dynpro field is specified in more than one `FIELD` statement, its value is
> passed when the first corresponding `FIELD` statement is executed."
> — same page

And the OK field is exempt from all of it:

> "The statement `FIELD` is ignored by the OK field. The OK field is always transported
> directly at the event PAI."
> — same page

Transport control is independent of the module call, so `FIELD f.` on its own line is a
real statement with a real effect, not decoration:

> "The effect of the statement `FIELD` on the data transport at the event PAI is
> independent from its association with a `MODULE` statement."
> — same page

---

## Trap 2: an empty, unchanged field is not transported at all — and in a table control the whole line is skipped

> "A field whose content is empty at PBO and which is not changed by the user is not
> transported by the `FIELD` statement. This applies to the entire line in the `LOOP`
> statements for table controls and step loops."
> — [ABAP keyword documentation, FIELD, Data Transport at PAI Time](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYNP_FIELD_DATA_TRANSPORT.html)

Read the second sentence twice. In a table control, one untouched blank line means
*none* of that line's fields are transported — so a loop that clears and refills a work
area per line can carry the previous line's content into the untouched one.

The same rule is a documented *guarantee* in the other direction, and it is the only
reason the common "default it in PBO, let PAI keep it" pattern works:

> "If an empty field that has not been modified by the user is filled with a value in a
> PAI module before the `FIELD` statement is executed, this value is not overwritten by
> the `FIELD` statement using the initial value."
> — same page

"Empty" is a screen-display concept, not `IS INITIAL`:

> "Any dynpro fields, except fields of type `STRING` or `SSTRING`, are empty if they
> contain nothing but blanks in the screen display. Dynpro fields of type `STRING` or
> `SSTRING` are empty if they do not contain any characters. An initial time field with
> the characters `000000` or a numeric field with the value *0* are, for example, not
> empty and are transported by `FIELD`."
> — same page

So a blank `char10` is skipped, while a numeric field showing `0` is transported. Two
fields, both looking initial to the user, with opposite transport behaviour decided by
their declared type — the same type-decides-behaviour shape as the output lengths in
[Classic Lists & WRITE](../List%20Processing#readme). The documented way to actually
make a character field empty is `CLEAR ... WITH space`, which the page names directly.

---

## Trap 3: `TABLES` is load-bearing, and replacing it with `DATA` silently stops all transport

> "When dynpro fields are defined with reference to flat structures in the ABAP
> Dictionary, the identically named global data objects of the ABAP program must be
> declared with the statement `TABLES` as interface work areas. Otherwise, no data
> transport takes place, neither with nor without `FIELD`."
> — [ABAP keyword documentation, FIELD, Data Transport at PAI Time](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYNP_FIELD_DATA_TRANSPORT.html)

`TABLES spfli.` looks like exactly the kind of obsolete-smelling line a cleanup commit
removes in favour of `DATA spfli TYPE spfli.` The screen then shows nothing and saves
nothing, with no syntax error and no runtime error, because the dynpro field
`SPFLI-CARRID` has no interface work area to talk to.

There is one more invisible participant in the transport. If the dynpro field refers to
a data element, a customer *field exit* can rewrite the value on the way in:

> "If a dynpro field is defined with reference to a data element in the ABAP Dictionary,
> and an obsolete field exit is assigned to this field in a customer system, the
> function module of the field exit can be executed during the transport. This usually
> changes the value of the dynpro field."
> — same page

That is a value changing between the screen and your first line of code, implemented in
a different system than the one you develop in. Worth knowing it exists before spending
a day on it.

---

## Trap 4: `ON INPUT` is about emptiness, `ON REQUEST` is about typing — and four non-human sources count as typing

> "This condition specifies that the module `mod` is called only if the `dynp_field` is
> not empty for a dynpro field that is ready for input."
> — [ABAP keyword documentation, dynpro - FIELD, MODULE](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/dynpfield_module.html)

> "This condition specifies that the module `mod` is called only if the value of the
> dynpro field `dynp_field` was modified by input after the event PBO. This applies even
> when the existing input is overwritten with the same value or if the initial value of
> the field is entered explicitly."
> — same page

`ON INPUT` therefore never fires for an empty field, which means **a mandatory-field
check written as `FIELD f MODULE check_f ON INPUT.` cannot detect a missing value.** The
check is skipped exactly in the case it exists for.

`ON REQUEST` is the one with the surprises. The same page lists four value sources other
than a human typing that also trigger it:

- "Applying a default value set using *System -> User Profile -> Hold Data*. This requires the dynpro property *Hold Data* to be active."
- "Applying a default value from the User Memory. This requires that an SPA/GPA parameter is specified in the `PARAMETER-ID` property of a screen element."
- "Applying data passed when calling a dialog transaction using the addition `USING` of the statement `CALL TRANSACTION`."
- "Applying a default value predefined in the system or in the ABAP Dictionary for input/output fields of certain types."

The third one is the operationally interesting one: a batch input session fills fields
via `CALL TRANSACTION ... USING`, so **every `ON REQUEST` module fires for every field
the BDC map touches**, including ones a human user would have left alone. Validations
that effectively never run interactively run on every record in the batch — see
[Batch Input](../Batch%20Input#readme) for the other half of that story. The second one
means an SPA/GPA default (see [Program Calls & ABAP Memory](../Program%20Calls#readme))
counts as user input to the flow logic.

And your own PBO code can arm it:

> "The module `mod` is also called if the component `request` of the structure `SCREEN`
> was set to the value 1 at PBO time using `MODIFY SCREEN`."
> — same page

That is the `request` component documented from the other side in
[Screen Modification](../Screen%20Modification#readme) — simulated input, which really
does reach `ON REQUEST`.

Finally, `ON *-INPUT` takes cases away from `ON INPUT` rather than adding to it:

> "If the input field has the special property *\*-Input* and the user has entered an
> asterisk as the first character in the input field of the dynpro field `dynp_field`,
> the condition `ON INPUT` is not met. Instead, the condition `ON *-INPUT` is met."
> — same page

Chain-wide variants exist and are an OR, not an AND:

> "They check the individual conditions `ON INPUT` or `ON REQUEST` for all dynpro fields
> that are specified so far within the current chain after `FIELD`. The dialog module is
> called if at least one of the dynpro fields fulfills the respective condition."
> — [ABAP keyword documentation, dynpro - MODULE](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/dynpmodule.html)

Note "so far". A `MODULE ... ON CHAIN-REQUEST` placed in the middle of a chain sees only
the `FIELD` statements above it.

---

## Trap 5: an error message unlocks exactly the fields you chained — and in a plain module it unlocks nothing

This is the trap worth reading even if you skip the rest of the note.

Error handling in a dynpro is not written in the module. It is written in the *flow
logic position* of the module's call. `FIELD` outside a chain:

> "the input field in question becomes the only input-enabled field on the current
> dynpro and the input can be repeated."
> — [ABAP keyword documentation, Input Checks in Dialog Modules](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_DYNPROS_CHECKS_MOD.html)

Inside a `CHAIN`, the whole chain is unlocked:

> "the input fields of all dynpro fields in the processing chain become input-enabled on
> the current dynpro. This includes fields after the `MODULE` statement in `FIELD`
> statements. None of the other fields are input-enabled."
> — same page

And a `MESSAGE e...` in an ordinary unconditional module unlocks **nothing**:

> "If warnings or error messages are sent in modules without reference to `FIELD` or
> `CHAIN`, PAI processing is interrupted and the screen layout is displayed again
> without raising the event PBO and without a field on the screen layout being ready for
> input. In the event of an error message, the user must terminate the processing. To do
> this, an appropriate option must be created on the user interface, otherwise the
> program can only be terminated from outside."
> — [ABAP keyword documentation, FIELD, Handling of Messages from the PAI Event](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYNP_FIELD_MESSAGES.html)

That is a frozen screen produced by a single, entirely reasonable-looking line of ABAP:
a `MESSAGE e...` inside `MODULE user_command_0100`. The user cannot correct anything,
because no field accepts input; the only escape is a function with function type *E*
(see Trap 6), and if the developer did not provide one, "the program can only be
terminated from outside." The fix is never in the module — it is to move the check under
a `FIELD` or into a `CHAIN`, or to make the module's exit path a type *E* function.

Two more consequences of "without raising the event PBO":

- Nothing your PBO modules do is re-applied. Field properties set by `MODIFY SCREEN`, a
  recalculated title, a refilled dropdown — none of it refreshes on an error round trip.
- The flow logic compensates for exactly one thing, the field values themselves:
  "all fields linked using `FIELD` are transported back to the screen layout without PBO
  processing taking place. This ensures that any changes to the field content are
  displayed before a message." Fields *not* under a `FIELD` statement do not get that.

### Where PAI resumes is not where you think

> "If the value in the input field is changed by the user, PAI processing is continued
> after a user action with the first `FIELD` statement or `CHAIN` statement linked with
> the dynpro field `dynp_field`. If the value in the input field is not changed by the
> user, PAI processing is continued again with the current `FIELD` statement. Previous
> statements of the PAI event block are not executed again."
> — [ABAP keyword documentation, FIELD, Handling of Messages from the PAI Event](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYNP_FIELD_MESSAGES.html)

"Previous statements of the PAI event block are not executed again" is the load-bearing
sentence. A module placed at the top of PAI to prepare state runs **once**, on the first
PAI, and never again across any number of error corrections. Any later module that
depends on that state is running against stale data from here on.

If a field is mentioned in several `FIELD` statements, the rewind goes further back than
the error:

> "all `FIELD` and `CHAIN` statements containing the error field must be repeated. PAI
> processing resumes at the first `FIELD` or `CHAIN` statement containing one or more of
> the fields in the `FIELD` or `CHAIN` statement in which the error occurred and which
> were modified the last time the screen layout was displayed."
> — [ABAP keyword documentation, Input Checks in Dialog Modules](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_DYNPROS_CHECKS_MOD.html)

So a validation module can be executed two, three, or n times for one user correction,
depending on how many `FIELD` statements mention its field. Anything with a side effect
(a number range draw, a lock, an enqueue, a counter) is the wrong thing to put there —
see [Number Ranges](../Number%20Ranges#readme) and [Enqueue Locks](../Enqueue%20Locks#readme).

### A pressed button counts as a changed field

> "User actions linked with function codes that set the OK field also count as changes to
> input fields. A prerequisite for this is that the OK field is defined in the dynpro and
> that function codes are not evaluated exclusively by the system field `sy-ucomm`."
> — [ABAP keyword documentation, FIELD, Handling of Messages from the PAI Event](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYNP_FIELD_MESSAGES.html)

So clicking any toolbar button after an error rewinds PAI to the first `FIELD` statement
and re-runs the validations, even though the user changed no data. Note the second
sentence: this behaviour requires a real OK field in the dynpro. A program that reads
`sy-ucomm` instead of an OK field loses it — the same `sy-ucomm`-is-not-the-contract
point the keyword docs make for selection screens in
[Screen Modification](../Screen%20Modification#readme).

### Warnings are not errors

> "If an error message occurs after user input, the user must correct the input values
> until no error message is sent, whereas after a warning, the input values can be
> confirmed unchanged. The warning is not sent again when the `MESSAGE` statement is
> executed again."
> — same page

A `MESSAGE w...` is therefore a one-shot per round trip, not a loop. Useful, and easy to
misread as "warnings are weaker errors" — they are a different mechanism.

---

## Trap 6: `AT EXIT-COMMAND` ignores its position, skips the checks, and only the first one exists

> "The dialog module is called before the automatic input checks defined in the system
> or in the ABAP Dictionary and independently of its position in the event block. The
> only dynpro field transported to the ABAP program is the OK field."
> — [ABAP keyword documentation, dynpro - MODULE](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/dynpmodule.html)

Three separate facts in two sentences:

1. **Position is irrelevant.** Writing it third in the event block does not make it run
   third. This is the only statement in the flow logic that is not positional.
2. **It runs before the automatic checks**, which is the entire point — it is how
   *Cancel* works on a screen with unfilled mandatory fields.
3. **Only the OK field is transported.** Reading an input field in an
   `AT EXIT-COMMAND` module gives you the previous dialog step's value, by Trap 1. A
   "do you want to save your changes?" prompt built here cannot see the changes.

It fires on two triggers, the second of which is not widely known:

> "The function used to raise the event PAI has function type *E*." / "A character string
> starting with *E* was entered in the command field of the system toolbar and was
> confirmed by pressing *Enter*."
> — same page

Typing anything beginning with `E` into the command field is a documented way to reach
the exit module.

Only one can exist:

> "If multiple `MODULE` statements have the addition `AT EXIT-COMMAND`, only the first
> one is executed."
> — same page

SAP's own example spells out the consequence, including the dead module:

> "The `back` module is never called. Two module calls using `AT EXIT-COMMAND` are
> pointless in the dynpro flow logic."
> — [ABAP keyword documentation, dynpro - Unconditional Module Call](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYNPRO_AT_EXIT_COMM_ABEXA.html)

### The exit module that does not exit

> "If the dynpro processing is not terminated in the dialog module `mod`, the complete
> PAI processing is executed after the dialog module has ended."
> — [ABAP keyword documentation, dynpro - MODULE](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/dynpmodule.html)

The exit module is not an exit. It is a module that happens to run first, and if it does
not call `LEAVE`, PAI continues normally. SAP's example makes this concrete: `BACK` and
`CANCEL` both have function type *E*, the module only leaves on `CANCEL`, and so —

> "When *Back* is selected with or without input in the mandatory fields, the OK field is
> transported and the module `cancel` is called. However, the program is not exited there,
> because the function code is *BACK*. Instead, the automatic field checks are performed.
> If the mandatory fields are filled, the modules `execute1` and `execute2` are called."
> — [ABAP keyword documentation, dynpro - Unconditional Module Call](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYNPRO_AT_EXIT_COMM_ABEXA.html)

**Pressing *Back* ran the save logic.** A `CASE ok_code` in the exit module that handles
`'CANCEL'` and forgets `'BACK'` falls straight through into the rest of PAI, and the
user who pressed Back to abandon their changes has just committed them. That is one
missing `WHEN` away from a data bug that looks nothing like a flow-logic problem.

Note the `CLEAR ok_code.` in SAP's example immediately before `LEAVE PROGRAM.` The OK
field is an ordinary global variable, and the next trap shows a documented case where a
user action leaves its previous value in place — so clearing it after you have acted on
it is a cheap habit. (The documentation shows the `CLEAR`; it does not state a general
rule requiring it. Treat it as a convention with a documented motivation, not a quoted
mandate.)

---

## Trap 7: `AT CURSOR-SELECTION` does not deliver its own function code

> "The function used to raise the event PAI has the function code *CS* and function type
> *S*." / "The cursor is placed on a single input field or output field of the screen
> layout at the time of the user action."
> — [ABAP keyword documentation, dynpro - MODULE](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/dynpmodule.html)

And then:

> "If the PAI event is raised under the above circumstances, the function code is not
> passed to `sy-ucomm` and the OK field. They keep their previous values."
> — same page

Both conditions matter. The cursor must be on *exactly one* field — a double-click
elsewhere does not call the module, and nothing reports that. But the second quotation is
the bug: a double-click runs the *whole* PAI event block, and every `CASE ok_code` in it
sees the **previous** function code. Double-click a row after pressing *Save* and Save
runs again. The containment is to clear the OK field once you have handled it, which is
the practice SAP's own example shows (Trap 6).

Unlike `AT EXIT-COMMAND`, this one is positional and does not skip the input checks:

> "The call occurs as part of the usual PAI processing, that is, the automatic input
> checks defined in the system or in the ABAP Dictionary are executed and the statement
> `MODULE` is called according to its position in the event block."
> — same page

An older SAP Help page on conditional module calls adds a last-wins rule for duplicates
— "Module C2 is never executed, since the `MODULE ... AT CURSOR SELECTION` statement
occurs twice, and only the last is processed"
([Conditional Module Calls](https://help.sap.com/doc/saphelp_scm700_ehp02/7.0.2/en-US/4a/3bb5668c412baee10000000a421937/content.htm)).
That is the opposite of the first-wins rule for `AT EXIT-COMMAND`. It is **not** stated
on the current keyword documentation page, so it is recorded here with its older source
rather than presented as current documented behaviour.

---

## Trap 8: the automatic input checks run before your flow logic, in a fixed order

> "In the PAI event, the dynpro makes a series of automatic input checks. These checks
> take place before data transports to the ABAP program and before the dynpro flow logic
> is processed."
> — [ABAP keyword documentation, dynpro - Automatic Input Checks](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_DYNPROS_CHECKS_AUTO.html)

Documented order: **mandatory input**, then **input format**, then **checks defined in
the ABAP Dictionary**. And until they all pass, your code does not exist:

> "If the automatic input checks find an error, a message appears in the status bar of
> the screen, and the corresponding fields remain ready for input. The user must correct
> the input and raise PAI again. The actual PAI processing does not start until there are
> no more errors."
> — same page

This is why "let the user cancel out of a half-filled screen" is not implementable with
ordinary flow logic, and why `AT EXIT-COMMAND` exists at all.

Two details inside the Dictionary checks are routinely misremembered:

> "Does the entered value match any foreign key relationship with a different database
> table? ... This check only takes place, however, if the foreign key attribute is set for
> the input field in the Screen Painter. This input check is not necessarily identical
> with the input help. The developers must ensure that the input help represents a subset
> of the content of the check table."
> — same page

> "The value table of a domain, however, is not checked. It is only used as a default
> value for the check tables of the fields that reference the domain."
> — same page

A domain *value table* checks nothing. Fixed values do. And nothing guarantees that the
F4 help offers only valid values — that is the developer's job, stated as such.

---

## Dynpro sequences: `SET SCREEN`, `LEAVE SCREEN` and the screen that calls itself

The default is a loop, not an exit:

> "The default next dynpro in Screen Painter is always the number of the dynpro itself.
> If the default value is used and not overwritten dynamically, the dynpro calls itself
> recursively."
> — [ABAP keyword documentation, Dynpro Flow and Dynpro Sequences](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_DYNPROS_PROCESSING.html)

Setting the next dynpro does not leave the current one:

> "The `SET SCREEN` statement does not interrupt the current dynpro processing. To leave
> a dynpro, use the ABAP statement `LEAVE ...`"
> — same page

| Statement | What it does |
|---|---|
| `SET SCREEN dynnr` | Overwrites the next dynpro; "The next dynpro is called automatically when the end of PAI processing is reached for the current dynpro." |
| `LEAVE SCREEN` | Ends the current dynpro now and calls the current next dynpro |
| `LEAVE TO SCREEN dynnr` | "a short form of the statements `SET SCREEN dynnr` and `LEAVE SCREEN`" |
| `CALL SCREEN dynnr` | Starts a **new** sequence embedded in the current one; execution resumes after `CALL SCREEN` when that sequence reaches 0 |
| next dynpro `0` | Ends the sequence and returns to the caller |

Hard edges worth knowing before you hit them:

- `dynnr` is "a data object of the type `n` and the length 4" and must name a dynpro of
  the current main program or be `0`, "otherwise an uncatchable exception is raised" — so
  a computed screen number cannot be guarded with `TRY`. `CALL SCREEN` on a missing
  dynpro raises `DYNPRO_NOT_FOUND`.
- `LEAVE TO SCREEN` "must not be used when handling events of the Control Framework" —
  that is the documented reason an ALV or control event handler cannot simply branch
  screens.
- Nesting ceilings: "In a dynpro sequence started by a transaction code, up to 50 other
  dynpro sequences can be nested" and "The maximum popup level is 9" — but the
  documentation immediately tells you not to use them, because the system consumes some
  itself: "the maximum values of 50 dynpro sequences or nine popup levels within a
  program should never be used", and elsewhere "you should not exceed 40 sequences, since
  help and error dialogs also use internally implemented dynpro sequences."
- `SUPPRESS DIALOG` in a PBO module hides the screen without skipping the code: "the
  entire PBO and PAI logic is executed, but the dynpro is not displayed."

---

## Where each statement is allowed

| Statement | PBO | PAI | POH / POV |
|---|---|---|---|
| `MODULE` as a keyword | yes (modules declared `OUTPUT`) | yes (modules declared `INPUT`) | only as an addition of `FIELD` |
| `FIELD` | may be written, "is ignored in the event block at PBO" | yes — transport, conditions, error handling | yes — self-programmed F1 / F4 help |
| `CHAIN` / `ENDCHAIN` | ignored at PBO | yes | not documented for POH/POV |
| `AT EXIT-COMMAND`, `SWITCH` | n/a | yes, on standalone `MODULE` only | n/a |

Rules that are easy to violate by accident:

- "Processing chains cannot be nested."
- `AT EXIT-COMMAND` "cannot be specified with the statement `FIELD`", and neither can
  `SWITCH` — on a `FIELD`, "the switch assigned to the dynpro field in Screen Painter
  applies."
- A missing module is not a syntax error you can catch: "If the dialog module `mod` does
  not exist in the ABAP program, an uncatchable exception is raised."
- A switched-off switch silently removes the statement: "the statement `FIELD` is
  respected only if the dynpro field has been activated by the switch", and for
  `MODULE ... SWITCH`, "If the specified switch does not exist, the dialog module is not
  called."

Obsolete flow-logic statements, per the documentation: `SELECT`, `FIELD - VALUES`,
`FIELD - SELECT`, `CALL CUSTOMER SUBSCREEN`, and step loop processing. The `VALUES` and
`SELECT` value checks are worth recognising in old screens because of *when* they run:
"These checks are made before dialog modules are called."

---

## This whole topic is on SAP's obsolete list

> "The classic dynpros described here are considered obsolete by SAP for application
> programs. For new developments, only SAPUI5 or Web Dynpro should be used."
> — [ABAP keyword documentation, General Dynpros](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/abenabap_dynpros.html)

None of it exists in ABAP for Cloud Development either — see
[ABAP Language Versions](../ABAP%20Language%20Versions#readme). The reason to learn it is
that the installed base is enormous and dynpro bugs are expensive to diagnose, not that
anyone should start a new screen this way.

---

## Documentation-state notes

Recorded rather than repaired, so that re-reading the sources is not confusing:

- The `CHAIN` page states that the statement "can be specified in the event blocks at PAI
  and PBO, is ignored, however, in the event block at PBO." The `FIELD` page has the same
  shape ("can be specified in the event blocks at PBO, PAI, POH, and POV, but is ignored
  in the event block at PBO"), which reads consistently; the `CHAIN` wording omits
  POH/POV entirely. Quoted as published.
- The last-wins rule for duplicate `AT CURSOR-SELECTION` calls appears on an older SAP
  Help page, not on the current keyword documentation page (see Trap 7).
- The flow-logic statement pages live under `dynp`-prefixed names
  (`dynpfield.html`, `dynpchain.html`, `dynpmodule.html`, `dynpfield_module.html`). The
  bare `FIELD.html` / `CHAIN.html` / `MODULE.html` links used inside the documentation
  resolve to a sign-in page when followed from outside the portal, which makes these
  pages hard to find by search. The working URLs are in Sources below.

---

## Sources

- [ABAP keyword documentation — General Dynpros](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/abenabap_dynpros.html)
- [ABAP keyword documentation — Dynpro Flow and Dynpro Sequences](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_DYNPROS_PROCESSING.html)
- [ABAP keyword documentation — Statements in the Dynpro Flow Logic](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_DYNPROS_DYNPRO_STATEMENTS.html)
- [ABAP keyword documentation — dynpro - FIELD](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/dynpfield.html)
- [ABAP keyword documentation — dynpro - FIELD, MODULE](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/dynpfield_module.html)
- [ABAP keyword documentation — dynpro - FIELD, Data Transport at PAI Time](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYNP_FIELD_DATA_TRANSPORT.html)
- [ABAP keyword documentation — dynpro - FIELD, Handling of Messages from the PAI Event](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYNP_FIELD_MESSAGES.html)
- [ABAP keyword documentation — dynpro - CHAIN](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/dynpchain.html)
- [ABAP keyword documentation — dynpro - MODULE](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/dynpmodule.html)
- [ABAP keyword documentation — MODULE (defining a dialog module)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/abapmodule.html)
- [ABAP keyword documentation — Input Checks in Dialog Modules](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_DYNPROS_CHECKS_MOD.html)
- [ABAP keyword documentation — Automatic Input Checks](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_DYNPROS_CHECKS_AUTO.html)
- [ABAP keyword documentation — Input Checks (overview)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_DYNPROS_CHECKS.html)
- [ABAP keyword documentation — dynpro - Unconditional Module Call (AT EXIT-COMMAND example)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYNPRO_AT_EXIT_COMM_ABEXA.html)
- [ABAP keyword documentation — dynpro - Input Checks in Dialog Modules (FIELD/CHAIN example)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYNPRO_FIELD_CHAIN_ABEXA.html)
- [ABAP keyword documentation — Obsolete Statements in Dynpro Flow Logic](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYNPRO_OBSOLET.html)
- [ABAP keyword documentation — OK field](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENOK_FIELD_GLOSRY.html)
- [ABAP keyword documentation — SET SCREEN](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSET_SCREEN.html)
- [ABAP keyword documentation — LEAVE [TO] SCREEN](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPLEAVE_SCREEN.html)
- [ABAP keyword documentation — CALL SCREEN](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCALL_SCREEN.html)
- [SAP Help — Conditional Module Calls (older release, for the duplicate AT CURSOR-SELECTION rule)](https://help.sap.com/doc/saphelp_scm700_ehp02/7.0.2/en-US/4a/3bb5668c412baee10000000a421937/content.htm)
