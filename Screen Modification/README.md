# Screen Modification — The PBO Reset, the name Component That Silences MODIFY SCREEN

`LOOP AT SCREEN` / `MODIFY SCREEN` is how a classical dynpro or selection
screen is changed at runtime: hide a field, grey it out, make it mandatory,
highlight it. There is no API and no object model — you loop over a **system
table** of screen elements and write back a flat structure of type `SCREEN`.

Everything awkward about the topic follows from that. The statement does not
return a value, does not set `sy-subrc`, and does not raise an exception. The
documentation for the failure case is one clause:

> "The `name` component must contain the name of the current screen element,
> otherwise the statement is not executed."

Not executed. That is the entire diagnostic. A `MODIFY SCREEN` that does
nothing looks exactly like a `MODIFY SCREEN` that worked.

Related notes: [Selection Tables](../Selection%20Tables#readme) for the
`SELECT-OPTIONS` declarations these modifications operate on,
[Text Elements](../Text%20Elements#readme) for why the block titles in the demo
may render as blanks, and
[ABAP Language Versions](../ABAP%20Language%20Versions#readme) for why none of
this exists in ABAP Cloud.

Runnable demo: [ydj_screen_modify_demo.abap](ydj_screen_modify_demo.abap) — a
selection screen that hides half of itself, plus two modifications that are
deliberately written the broken way.

## The work area: structure SCREEN

`LOOP AT SCREEN INTO wa` needs `wa` to be of Dictionary type `SCREEN`. An
inline `DATA(wa)` or `FINAL(wa)` is allowed and is the modern form.

The components, with the values each accepts:

| Component | Type | Screen Painter property | Values |
|---|---|---|---|
| `name` | c(132) | Name | element name |
| `group1`..`group4` | c(3) | Group1..Group4 | modification group IDs |
| `required` | c(1) | Mandatory field | `0`, `1`, `2` |
| `input` | c(1) | Input | `0`, `1` |
| `output` | c(1) | Output | `0`, `1` |
| `intensified` | c(1) | Light | `0`, `1` |
| `invisible` | c(1) | Invisible | `0`, `1` |
| `length` | x(1) | VisLg | field length |
| `active` | c(1) | *(none)* | `0`, `1` |
| `display_3d` | c(1) | Two-dimensional | `0`, `1` |
| `value_help` | c(1) | Input help | `0`, `1`, `2` |
| `request` | c(1) | *(none)* | `0`, `1` |
| `values_in_combo` | c(1) | Dropdown list box | `0`, `1` |

Two of these have no corresponding screen property at all — `active` and
`request` — and those two are where the surprises live.

Everything except `name`, `group1`..`group4` and `length` is a character `0`
or `1`, **not** `abap_true`/`abap_false`. `wa-input = abap_true` assigns `X`,
which is neither of the documented values.

## Trap 1: the PBO reset — why a hide needs no un-hide, and why PAI is too late

The single most useful sentence in the topic:

> "The properties of the screen elements of the dynpro are reset to their
> static properties at the start of each PBO processing, so that the execution
> of `MODIFY SCREEN` during PAI processing does not affect the display of the
> following screen layout."

Two consequences, pulling in opposite directions.

**The good one:** modifications are *not* cumulative. Every PBO starts from the
static Screen Painter state, so the code only ever has to describe what to take
away. The symmetrical-looking `ELSE` branch that sets `input = '1'` again is
dead code:

```abap
" Correct. No ELSE needed - the reset already made it visible.
IF ls_screen-group1 = 'DYN' AND p_some = 'X'.
  ls_screen-active = '0'.
  MODIFY SCREEN FROM ls_screen.
ENDIF.
```

**The bad one:** a `MODIFY SCREEN` anywhere in PAI — a `USER-COMMAND` handler,
a validation block, `AT SELECTION-SCREEN ON field` — is discarded before the
next screen is displayed. It compiles, it runs, the work area is written, and
the reset wipes it. The documentation states plainly that `MODIFY SCREEN`
"makes sense only during PBO processing".

For a selection screen the PBO is `AT SELECTION-SCREEN OUTPUT`. For a dynpro it
is a `MODULE ... OUTPUT` called from `PROCESS BEFORE OUTPUT`. Those are the
only two places worth writing the statement.

There is also a hard scope rule that catches people moving code into a helper
class: `MODIFY SCREEN` "can be used in the statement block after
`LOOP AT SCREEN` only". It is not a free-standing statement you can call with
a prepared structure — it modifies *the current loop pass*.

## Trap 2: the name component silences the statement

Because `MODIFY SCREEN` acts on the current loop pass, it verifies that the
work area still describes that element. If `wa-name` does not match, the
statement is skipped — silently.

The dangerous shapes are all the ones that look like tidy code:

```abap
LOOP AT SCREEN INTO DATA(ls).
  IF ls-name = 'P_KEEP'.
    CLEAR ls.                      " <- name is gone. Statement dead.
    ls-intensified = '1'.
    MODIFY SCREEN FROM ls.
  ENDIF.
ENDLOOP.
```

```abap
LOOP AT SCREEN INTO DATA(ls).
  " Also dead: the work area is filled from a template or a config
  " row, which carries its OWN name - or no name at all. The
  " statement is in the right place and still does nothing.
  MOVE-CORRESPONDING gs_template TO ls.
  MODIFY SCREEN FROM ls.
ENDLOOP.
```

`CLEAR` before setting properties is a reflex worth unlearning here. The read
from `LOOP AT SCREEN` already filled the structure correctly; the only correct
move is to change the one or two components you care about and write it back
untouched otherwise.

## Trap 3: active overrides input, output and invisible

`active` has no Screen Painter equivalent. It is a convenience component that
drives three others, and it wins:

> "When PBO processing starts, the component `active` is always 1. If `active`
> is set to 0 by `MODIFY SCREEN`, `input` and `output` are set to 0 and
> `invisible` is set to 1. **Any other values in `input`, `output`, and
> `invisible` are ignored.**"

So this does not do what it reads like:

```abap
ls-active  = '0'.      " hide it
ls-output  = '1'.      " ...but still display it? No. Ignored.
MODIFY SCREEN FROM ls.
```

The rule is symmetrical, which is the part people miss: setting `input` and
`output` to 0 and `invisible` to 1 by hand "automatically sets `active` to 0
and any other values in `active` are ignored". You cannot hide a field and
keep it active, in either direction.

Use `active = '0'` for "remove this from the screen entirely" and leave the
other three alone. Use `input = '0'` alone for "display it, greyed out".

## Trap 4: two components have a third value, and one of them is not enforced

`required` and `value_help` accept `2` as well as `0`/`1`, and in both cases
`2` is the interesting one:

> "With `required`, value `2` means a recommended field which is displayed on
> the screen in the same way as a mandatory field (value `1`) but **no check is
> performed**."

> "With `value_help`, value `2` means that the input help button is always
> displayed, whereas value `1` means that the button is only displayed if the
> cursor is positioned on the dynpro field."

`required = '2'` is genuinely useful — the visual cue without blocking `F8` —
but it is indistinguishable on screen from `'1'`, so a copy-paste that turns a
`1` into a `2` removes an input check and changes nothing visible.

## The two Screen-Painter properties you cannot override

Static definition wins in two documented cases:

- A field defined as **output field only** in the Screen Painter cannot be made
  input-ready. "The assignment of the value `1` to the component `input` is
  ignored."
- If the field is statically `required`, or you set `required = '1'`, then
  `input` should stay `1`, because "setting `input` to `0` would cancel the
  required property".

That second one is a real ordering bug: greying out a mandatory field also
quietly drops its mandatory status.

## The request component: simulating user input

`request` is the other component with no screen property, and it runs in both
directions:

- The runtime sets it to `1` at PAI if the user actually entered something in
  that field.
- `MODIFY SCREEN` can set it to `1` at PBO to **simulate** user input.

Its only effect is on dialog modules called with `FIELD ... ON REQUEST` or
`ON CHAIN-REQUEST`: those run only for fields whose `request` is `1`. Setting
it at PBO is the documented way to force a validation module to run on a field
the user never touched — for instance one you just defaulted in code.

## Group by MODIF ID, never by generated name

`group1`..`group4` hold up to four 3-character IDs, assigned via `MODIF ID` on
the declaration (or the Group1..Group4 attributes in the Screen Painter). A
single `MODIF ID` stamps **every** element the declaration generates — for a
`SELECT-OPTIONS` that is both input fields, the label and the multiple-
selection pushbutton.

```abap
SELECT-OPTIONS s_carr FOR gv_carrid MODIF ID dyn.
PARAMETERS     p_note TYPE c LENGTH 20 MODIF ID dyn.
```

That is the whole reason to prefer groups over names. The generated element
names behind a `SELECT-OPTIONS` (the `low`/`high` fields and the pushbutton)
are not a documented interface, and hiding a select-option by name is how
people end up with a hidden input field and a stranded pushbutton next to it.
Run the demo and read the names off your own system before trusting any list
of them found online.

Because there are four group components, an element can belong to four
overlapping sets — e.g. `group1` for the functional area and `group2` for
"read-only in display mode" — and the PBO can apply both rules independently.

## The USER-COMMAND that makes the screen come back

A correct `AT SELECTION-SCREEN OUTPUT` block still appears to do nothing if
the user action never triggers a round trip. Radio buttons and checkboxes only
raise PAI when they are declared with `USER-COMMAND`:

```abap
PARAMETERS p_all  RADIOBUTTON GROUP g1 DEFAULT 'X' USER-COMMAND uc1.
PARAMETERS p_some RADIOBUTTON GROUP g1.
```

`USER-COMMAND` goes on the **first** parameter of the radio button group only,
and the function code arrives in `sscrfields-ucomm`, which needs
`TABLES sscrfields.`. The documentation is explicit that `sy-ucomm` is the
wrong field to read:

> "It is not recommended that the system field `sy-ucomm` instead of
> `sscrfields-ucomm` is evaluated, since this does not guarantee that
> `sy-ucomm` always contains the correct value in selection screen processing."

## Dynpro-specific behaviour worth knowing

On a real dynpro (not a selection screen) there are three extra rules:

- **Table controls:** changes affect only the *current line*. A modification
  made *before* the table control is processed does not affect it at all,
  because the values come from the structure created with `CONTROLS`.
- **Step loops:** a change made before the step loop is processed affects
  **all** groups in it — the opposite granularity to a table control.
- **Tabstrip controls:** setting `active = '0'` on a *tab title* hides the
  whole tabstrip page behind it.

Also: outside the processing of a table control or step loop, `LOOP AT SCREEN`
reports the "statically predefined properties" of its elements, not the
per-line current ones.

## Do not use the short forms

`LOOP AT SCREEN.` and `MODIFY SCREEN.` without `INTO`/`FROM` are obsolete.
They operate on a built-in structure called `screen`, and the documentation
asks for the long form with an explicitly declared work area — including a
warning not to write `LOOP AT SCREEN INTO screen` either, since that still
addresses the obsolete built-in object.

Inline `DATA(ls_screen)` sidesteps the whole question.

## None of this exists in ABAP Cloud

Counted from the restricted-ABAP whitelist: `LOOP AT SCREEN`, `MODIFY SCREEN`,
`PARAMETERS`, `SELECT-OPTIONS`, `AT SELECTION-SCREEN` (and all its variants),
`CALL SCREEN`, `LEAVE SCREEN` and `SET PF-STATUS` are all **Standard ABAP** only
— no ABAP for Cloud Development, no ABAP for Key Users. Classical UI programming
is one of the cleanest cuts in the language version split.

This note is here because the existing S/4HANA and ECC estate is full of these
screens, not as a pattern for new development. For new work the equivalent is a
RAP behaviour definition with field control, which is a different topic
entirely.

## Sources

ABAP keyword documentation (`help.sap.com`, latest):

- `ABAPLOOP_AT_SCREEN` — the loop, work area rules, table control/step loop
  granularity
- `ABAPMODIFY_SCREEN` — the `name` rule, the PBO reset, `active` precedence,
  the Screen-Painter overrides, tabstrip behaviour
- `ABENSCREEN` — the full component table, the `2` values, `active` and
  `request` semantics
- `ABENSCREEN_STRUCTURE_OBSOLETE`, `ABENMODIFY_SCREEN_OBSOLETE` — why to avoid
  the short forms and the built-in `screen`
- `ABENSELECTION_SCREEN_EVENTS`, `ABAPPARAMETERS_SCREEN`,
  `ABAPSELECT-OPTIONS_SCREEN` — `MODIF ID`, `USER-COMMAND`, `sscrfields-ucomm`
- `ABENRESTRICTED_ABAP_ELEMENTS` — the language-version availability above
- `ABENDYNPRO_MOD_SIMPLE_ABEXA` — SAP's own `group1`-driven example; the
  executable demos are `DEMO_DYNPRO_MODIFY_SIMPLE` and
  `DEMO_DYNPRO_MODIFY_SCREEN`
