# Input Help (F4) — The Help That Silently Overrides Your Search Help, the Screen Value That Is Not There Yet and the `sy-repid` You Must Not Pass

Every ABAP developer writes an F4 help eventually, and almost everyone writes it the
same way: a `PROCESS ON VALUE-REQUEST` module (or an
`AT SELECTION-SCREEN ON VALUE-REQUEST FOR` block), a `SELECT`, and
`F4IF_INT_TABLE_VALUE_REQUEST`. That code works on the first field and then starts
behaving strangely on the second: the dependent help shows *all* connections instead of
the ones for the airline just typed, the chosen value does not land in the field, or the
list is right in development and empty in production.

None of that is mysterious. All of it is written down. This note collects the parts of
the documentation that the usual copy-paste skips.

Three mechanisms can supply an F4 list, and they are not equal:

> "These three options are ordered by ascending priority. If different techniques are
> used at the same time, the POV module calls override any definition on the dynpro,
> which in turn overrides the binding to the ABAP Dictionary."
> — [ABAP keyword documentation, dynpro - Input Help](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-input-help)

The order of *preference* is the exact reverse of the order of *priority*, which is the
first thing worth internalising:

> "If possible, a search help from ABAP Dictionary should always be defined for the
> input help and input help should only be defined in dialog modules if no other option
> is available. In particular, the enhancement of search helps using search help exits
> should be considered beforehand."
> — same page

SAP repeats that warning inside the function module everyone reaches for first:

> "Note: Before you use this module at POV (Process on Value-Request), reconsider
> whether a search help could not carry out the same task. You can implement
> self-defined value selection in a search help exit. This has the advantage that you
> can attach the search help to a data element or a field of a structure. The F4 help is
> then automatically available for all users of the data element or structure."
> — SE37 documentation of `F4IF_INT_TABLE_VALUE_REQUEST`

For the surrounding screen mechanics (PAI transport, `FIELD`, `CHAIN`) see
[Dynpro Flow Logic](../Dynpro%20Flow%20Logic#readme); for the selection screen itself see
[Selection Tables & Ranges](../Selection%20Tables#readme); for why the value you read
back may not look like the value in the database see
[Conversion Routines](../Conversion%20Routines#readme).

---

## Trap 1: at POV nothing is transported, so the field your help depends on is empty

This is the whole reason dependent F4 helps go wrong. POV is not PAI. The `FIELD`
statement that names the field does not move any data:

> "In the event blocks at POH and POV, only `FIELD` statements are possible. The
> statement `MODULE` can only be used as addition of the statement `FIELD`. In the case
> of these events, no data is transported automatically from the dynpro to the ABAP
> program and the statement `FIELD` is ignored accordingly."
> — [ABAP keyword documentation, dynpro - FIELD, Field Help and Input Help](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-field-field-help-and-input-help)

> "The content of the field specified under `FIELD` is not automatically passed to the
> called module in the event block at POH or POV."
> — [ABAP keyword documentation, dynpro - PROCESS](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-process)

> "The dialog module `mod` does not provide the content of the dynpro field `field`,
> since this content is not transported by the `FIELD` statement during event POH."
> — [ABAP keyword documentation, dynpro - Input Help in Dialog Modules](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-input-help-in-dialog-modules)

The same is true on a selection screen, where it is even easier to miss because the
parameter *is* a global variable of your program and so always has *a* value:

> "During the events for the field help and input help no data is transported from the
> selection screen to the ABAP program. As with general dynpros, suitable function
> modules such as `RS_SELECTIONSCREEN_READ` and `RS_SELECTIONSCREEN_UPDATE` must be
> used."
> — [ABAP keyword documentation, AT SELECTION-SCREEN, selscreen_event](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/at-selection-screen-selscreen-event)

So `p_carrid` inside the F4 block does not hold what the user just typed. It holds
whatever it held at the end of the last dialog step — initial on the first F4, and the
*previous* airline on every F4 after that. That is why this defect is usually reported as
"the help is one step behind" rather than "the help is broken".

The documented fix is to ask the screen, not the program:

> "The additional function modules `DYNP_VALUES_READ` and `DYNP_VALUES_UPDATE` read and
> return dynpro fields at POV time."
> — [ABAP keyword documentation, dynpro - Input Help in Dialog Modules](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-input-help-in-dialog-modules)

SAP's own demo program does exactly this. The keyword documentation describes
`DEMO_DYNPRO_F4_HELP_MODULE` as follows:

> "For the connection, the module `value_connection` is called at POV. There, the
> function module `DYNP_VALUES_READ` passes the value of the dynpro field `carrier` to
> the program."
> — [ABAP keyword documentation, dynpro - Input Help in Dialog Modules (example)](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-input-help-in-dialog-modules-abendynpro_f4_help_dial_abexa)

---

## Trap 2: the two system fields you must *not* pass

This one is a parameter-documentation footnote with teeth, and it contradicts almost
every code snippet on the internet. For `DYNP_VALUES_READ`:

> "Note that the variable sy-repid must not be used in the call because it can be
> overwritten at run-time, e.g. by the names of function groups. Either use the variable
> sy-cprog or enter the value as a literal instead."
> — SE37 parameter documentation of `DYNP_VALUES_READ`, parameter `DYNAME`

> "If the variable sy-dynnr is assigned to this parameter it can in rare cases contain
> screen numbers of the current function groups SHLP and SHL2. Avoid this situation by
> assigning a four-character literal, e.g. '0100' to the parameter."
> — same, parameter `DYNUMB`

`SHLP` and `SHL2` are the help processor's own function groups — i.e. the thing you are
standing inside while F4 runs. When it bites, `DYNP_VALUES_READ` raises
`INVALID_DYNPROFIELD` or `INVALID_DYNPRONAME` for a field that plainly exists, on some
systems and not others.

`F4IF_INT_TABLE_VALUE_REQUEST` carries the stronger version of the same warning, and here
it is not a rare case but a flat statement of fact:

> "DYNPPROG and DYNNR cannot be passed as SY-REPID and SY-DYNNR because they are only
> analyzed after the function module has been called. Instead, first copy the SY fields
> to local variables and then pass them to the function module."
> — SE37 documentation of `F4IF_INT_TABLE_VALUE_REQUEST`

Read that twice: passing `sy-repid` directly does not fail at the call, it is evaluated
*later*, by which time the system field has moved on. Copy both into local variables
first. (Note that SAP's own text writes `DYNNR` where the interface actually spells the
parameter `DYNPNR` — the parameter list is the authority, not the prose.)

For an executable program's standard selection screen the literal is known:

> "A standard selection screen has the dynpro number 1000 and is only possible in
> executable programs and logical databases."
> — [ABAP keyword documentation, standard selection screen](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/standard-selection-screen)

---

## Trap 3: `VALUE_ORG` defaults to the value SAP tells you not to use

`F4IF_INT_TABLE_VALUE_REQUEST` has exactly two non-optional parameters: `RETFIELD` and
the table `VALUE_TAB`. Everything else, including `VALUE_ORG`, is optional and defaulted
— and the default is the wrong one:

| `VALUE_ORG` | Meaning | SAP's own guidance |
|---|---|---|
| `'C'` | cell by cell (the **default**) | legacy; needs external representation |
| `'S'` | structured, one `VALUE_TAB` line per hit-list line | *"This option should be used for new developments (despite other default values)."* |

That parenthesis is SAP's, not mine — the documentation openly says the default is not
what you should pass. If you leave it defaulted while passing a structured table, every
column is read as a separate hit-list *line* instead of a separate *column*.

`'C'` also quietly changes the type contract of your table:

> "In this case the values in VALUE_TAB must be passed in external representation. This
> means that for types whose external and internal representation differ, the values
> should be passed to VALUE_TAB with the ABAP command WRITE and not with MOVE (These are
> for example all the numeric types, date, fields with conversion exit, etc.). Use the
> extension LEFT-JUSTIFIED for numbers."
> — SE37 documentation of `F4IF_INT_TABLE_VALUE_REQUEST`

So under `'C'`, a material number carrying an ALPHA conversion exit, a date, or any
packed number must be run through `WRITE ... TO` first; a plain assignment displays the
internal form (`0000000042`, `20260101`). Under `'S'` the opposite holds — "The data in
VALUE_TAB is available in internal representation." Two different contracts behind one
optional parameter. See [Conversion Routines](../Conversion%20Routines#readme) for what
the two representations actually look like.

There is a related warning about hard-coded values:

> "Caution: Do not copy any constants directly to VALUE_TAB. For example, if a date is
> defined as constant "01.01.1998", it can no loner be interpreted for other
> user-specific settings."
> — same (SAP's typo preserved)

`RETFIELD` decides which column is given back, and it is a *name*, not a position:

> "The columns of the hit list normally correspond to the fields of internal table
> VALUE_TAB, but only one of these columns contains the value to be returned to the
> screen field when a line is selected. The field name for this column must be specified
> in RETFIELD."
> — same

If neither `DDIC_STRUCTURE` nor `FIELD_TAB` is supplied, there are no meaningful names to
give it:

> "Note that the field names for the columns of VALUE_TAB are assigned internally if
> neither DDIC_STRUCTURE nor FIELD_TAB are defined. The fields are internally named
> F0001, F0002 etc. in this case."
> — same

Which is why a help built on an ad-hoc `BEGIN OF ... END OF` table sometimes only works
with `RETFIELD = 'F0001'`.

---

## Trap 4: the selected value reaches the screen only under conditions, and `RETURN_TAB` has its own failure mode

Returning the value is not automatic. It is conditional on three parameters being filled:

> "The selection of the user is either passed to the corresponding input-enabled screen
> fields, if the import parameters `DYNPPROG`, `DYNPNR`, and `DYNPROFIELD` are
> specified, or passed back in the table parameter `RETURN_TAB`."
> — [ABAP keyword documentation, dynpro - Input Help in Dialog Modules](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-input-help-in-dialog-modules)

Note *input-enabled*. A display-only field never receives the pick:

> "Normally values are only returned in input fields. This behavior can be changed with
> parameter DISPLAY (see parameter documentation)."
> — SE37 documentation of `F4IF_INT_TABLE_VALUE_REQUEST`

The Dictionary path has the same restriction plus one more, which is the usual
explanation for "the search help fills one field but not the other":

> "The values of the proposal list are passed only to input-enabled fields and to fields
> that are linked with only a single export parameter of the search help."
> — [ABAP keyword documentation, dynpro - Input Helps in the ABAP Dictionary](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-input-helps-in-abap-dictionary)

If you take the `RETURN_TAB` route instead, two things are easy to get wrong. First, an
empty table is not an error:

> "If RETURN_TAB does not contain any lines, the user has terminated the selection."
> — SE37 documentation of `F4IF_INT_TABLE_VALUE_REQUEST`

A blind `READ TABLE return_tab INDEX 1` therefore overwrites the field with an initial
value when the user presses Cancel. Check `sy-subrc` and leave the field alone.

Second, mixing both routes can make `RETURN_TAB` unreliable:

> "Caution: Despite being called with RETURN_TAB, up to Release 4.6B the help is started
> amodally as soon as the screen information DYNPPROG, DYNPNR and DYNPROFIELD is passed
> and the user has activated the ActiveX help. In this case you cannot be sure that the
> RETURN_TAB contains the selected lines of the hit list. In an amodal call, the function
> module terminates before the user has made his choice."
> — same

The modern reading of that is: pick one route. Either give the screen information and let
the module write the field, or evaluate `RETURN_TAB` yourself — not both.

On a selection screen the second route is the natural one, because assigning the
parameter is enough:

> "The selection parameters and selection criteria changed in the event blocks for ON
> VALUE-REQUEST are transported to the respective fields of the selection screen."
> — [ABAP keyword documentation, AT SELECTION-SCREEN, selscreen_event](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/at-selection-screen-selscreen-event)

---

## Trap 5: `SELECT-OPTIONS` is two fields, and F4 fires for exactly one of them

The syntax of the event names the three possible targets explicitly:

```
... ON {HELP-REQUEST|VALUE-REQUEST}
      FOR {para|selcrit-low|selcrit-high}
```

So `AT SELECTION-SCREEN ON VALUE-REQUEST FOR s_conn-low` does nothing at all when the
user presses F4 in the *to* field — that needs its own `...-high` block. A range filter
with a working help on the left half and the raw Dictionary help on the right half is
almost always this, not a configuration difference.

Two more restrictions on the same event:

> "These event blocks can only be implemented for fields of the selection screen that are
> defined in the same ABAP program and not in any linked logical database."
> — same page

> "Other selection events are not raised."
> — same page

The second one is a relief rather than a trap once known: pressing F4 does not run
`AT SELECTION-SCREEN`, so your validation logic is not executed half-way through an F4.

The dynpro side has the matching rules:

> "If multiple `FIELD` statements exist for the same dynpro field, only the first is
> executed."
> — [ABAP keyword documentation, dynpro - PROCESS](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-process)

> "After the POH or POV is processed, the system returns to the processing of the
> displayed screen layout in SAP GUI without raising the event PBO."
> — same page

No PBO after POV means anything you prepare in PBO — a `LOOP AT SCREEN` modification, a
freshly filled dropdown — is **not** refreshed when F4 closes. And the flow logic has an
ordering rule that produces a generated-code error rather than a readable message:

> "If PROCESS ON HELP-REQUEST or PROCESS ON VALUE-REQUEST are specified, PROCESS AFTER
> INPUT must have been specified before."
> — same page

---

## Trap 6: writing a POV module silently switches the Dictionary help off

The priority rule from the top of this note has a consequence that is easy to cause by
accident:

> "Specifying the event blocks at POH and POV overrides the field helps and input helps
> defined in the system or in the ABAP Dictionary. They must be specified only if the
> predefined helps are not sufficient."
> — [ABAP keyword documentation, dynpro - PROCESS](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-process)

> "If the event blocks at POH and POV are not implemented, field or input help fields are
> displayed that are defined in the system or in the ABAP Dictionary. If no help is
> defined, this is displayed in a message in the task bar."
> — [ABAP keyword documentation, dynpro - FIELD, Field Help and Input Help](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-field-field-help-and-input-help)

So a half-finished POV module — one that returns no values on some code path — does not
fall back to the search help. It replaces it. The user gets nothing, and the field looks
like it has no help at all.

---

## Trap 7: the input help and the input check are different mechanisms, and nothing keeps them in sync

The hit list and the validation that runs afterwards are two separate features that can
disagree. The documentation says so outright:

> "This input check is not necessarily identical with the input help. The developers must
> ensure that the input help represents a subset of the content of the check table."
> — [ABAP keyword documentation, dynpro - Automatic Input Checks](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-automatic-input-checks)

> "To avoid errors in the automatic input check, the bound search help should only propose
> values that also exist in a check table."
> — [ABAP keyword documentation, dynpro - Input Helps in the ABAP Dictionary](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-input-helps-in-abap-dictionary)

The failure is maddening from the user's side: F4, pick a value from SAP's own list,
press Enter, get *"Entry ... does not exist"*. Nobody mistyped anything. The search help
is simply wider than the check table.

The second half of this is the check-table/value-table confusion, which the documentation
settles in two places:

> "The value table of a domain, on the other hand, cannot be used for input helps."
> — [ABAP keyword documentation, dynpro - Input Helps in the ABAP Dictionary](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-input-helps-in-abap-dictionary)

> "The value table of a domain, however, is not checked. It is only used as a default
> value for the check tables of the fields that reference the domain."
> — [ABAP keyword documentation, dynpro - Automatic Input Checks](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-automatic-input-checks)

A value table is a *proposal to the person defining a foreign key*. It is neither a help
nor a check. And the check table itself only validates when the foreign key attribute is
set on the screen field:

> "This check only takes place, however, if the foreign key attribute is set for the input
> field in the Screen Painter."
> — same page

---

## The priority ladder, in one place

Within the Dictionary, binding a search help in different places gives different
precedence. In SAP's own ascending order:

| Priority | Source | Condition |
|---|---|---|
| lowest | Calendar / clock help | only `DATS` / `TIMS`, and only "if no other input helps are defined" |
| | Fixed values of the domain | "If neither a check table nor a search help is defined for a field" |
| | Search help of the data element | same condition as above |
| | Check table | if it has "neither a text table nor its own search help, and no dedicated search help is specified for a field" |
| | Check table with text table | adds the text "in the logon language of the user" |
| | Check table with search help | "enables a data transport of multiple parameters" |
| highest | Search help on the field itself | "this binding has the highest priority and is always used as an input help" |

— all quotes from
[dynpro - Input Helps in the ABAP Dictionary](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-input-helps-in-abap-dictionary)

Above all seven sits the dynpro binding, and above that the POV module. That is the ladder
to walk down — not up — when an F4 shows something unexpected.

---

## Before writing a POV module: search help exits

The documented middle path between "Dictionary search help" and "hand-written POV module"
is a search help exit, which keeps the help attached to the data element where every
screen inherits it:

> "A search help exit is a function module with a predefined interface and can be called
> at defined points within the input help process."
> — [ABAP keyword documentation, dynpro - Input Helps in the ABAP Dictionary](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-input-helps-in-abap-dictionary)

> "Each search help exit must have the same interface as the function module
> `F4IF_SHLP_EXIT_EXAMPLE`, which is used as a pattern for any new search exits to be
> created."
> — same page

The call points, in order, are `SELONE`, `PRESEL1`, `PRESEL`, `SELECT`, `DISP` and
`RETURN`. One of them is special:

> "SELONE event; only in collective search helps. ... This is the only event in which the
> search help exit is called for collective search helps. All other events call the search
> help exit for the selected elementary search help."
> — same page

So an exit written on a collective search help to filter the proposal list at `DISP` never
runs — it has to be attached to the elementary search helps underneath. Ready-made helpers
for the common cases exist:

> "These function modules are prefixed with F4UT_."
> — same page

---

## Checklist

- Prefer a Dictionary search help; then a search help exit; then a dynpro binding; only
  then a POV module.
- At POV, never read the dependent field from the program variable. Read the screen
  (`DYNP_VALUES_READ`, or `RS_SELECTIONSCREEN_READ` on a selection screen).
- Copy `sy-cprog` and the screen number into local variables before passing them;
  never pass `sy-repid`.
- Pass `VALUE_ORG = 'S'` explicitly. The default is `'C'`.
- Under `'C'`, fill `VALUE_TAB` with `WRITE ... TO`, not `MOVE`.
- Choose one return route: screen information, or `RETURN_TAB`. Not both.
- Treat an empty `RETURN_TAB` as "user cancelled" and change nothing.
- For `SELECT-OPTIONS`, write the event block twice: `-low` and `-high`.
- Make sure the help is a subset of the check table, or F4 will hand the user a value
  the screen then rejects.

---

## Runnable demo

[`ydj_f4_input_help_demo.abap`](ydj_f4_input_help_demo.abap) — a read-only executable
report over `SPFLI`/`SCARR` with a dependent F4: the connection help reads the airline
*from the screen* and shows only its connections, with the "obvious" wrong version
implemented alongside it so the difference is visible in one program.

---

## Sources

ABAP keyword documentation (fetched for this note):

- [dynpro - Input Help](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-input-help)
- [dynpro - Input Help in Dialog Modules](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-input-help-in-dialog-modules)
- [dynpro - Input Helps in the ABAP Dictionary](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-input-helps-in-abap-dictionary)
- [dynpro - Automatic Input Checks](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-automatic-input-checks)
- [dynpro - PROCESS](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-process)
- [dynpro - FIELD](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-field) and [dynpro - FIELD, Field Help and Input Help](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/dynpro-field-field-help-and-input-help)
- [AT SELECTION-SCREEN, selscreen_event](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/at-selection-screen-selscreen-event)
- [standard selection screen](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/standard-selection-screen)

Function module interfaces and their SE37 long texts were read from public repository
mirrors of the SAP objects, not from a live system — treat the parameter lists as
accurate and re-check them in SE37 on your own release before relying on an edge case:

- `F4IF_INT_TABLE_VALUE_REQUEST` — [interface and documentation](https://www.stechno.net/repository/sap-functions.html?id=F4IF_INT_TABLE_VALUE_REQUEST)
- `DYNP_VALUES_READ` — [interface and documentation](https://www.stechno.net/repository/sap-functions.html?id=DYNP_VALUES_READ), [parameter list](https://www.sapdatasheet.org/abap/func/dynp_values_read.html)

Two notes on how the quotes above were transcribed. Links inside SAP's own sentences
are shown as plain words (the keyword documentation renders half of its nouns as
cross-references). SE37 long texts are stored in fixed-width lines, and the public
mirrors join those lines without a space — "despite otherdefault values" in the raw
text is "despite other default values" as SAP wrote it; the spaces have been restored
and nothing else was changed, including SAP's own typo in "it can no loner be
interpreted".
