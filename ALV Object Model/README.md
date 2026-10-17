# SALV (`CL_SALV_TABLE`) — the ALV with no toolbar, the button that cannot exist in fullscreen and the selection mode that must be `NONE` to select a row

Four lines display a table in ALV:

```abap
TRY.
    cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_alv)
                            CHANGING  t_table      = lt_data ).
  CATCH cx_salv_msg.
ENDTRY.
lo_alv->display( ).
```

That is genuinely all of it, and it is why `CL_SALV_TABLE` is the default answer for
"show me this internal table". It is also why the next four requirements — a sort
button, a custom pushbutton, "let the user pick a row", a saveable layout — each turn
into an afternoon. None of them are hard. All of them are documented. The problem is
that the documentation for this class lives in the *SAP List Viewer* guide rather than
in the ABAP keyword documentation, so it is the one SAP component most ABAP developers
learn entirely from blog snippets.

This note collects the parts those snippets leave out, and the parts where the
display type you chose with one boolean silently decides whether a method works at
all.

---

## 1. The ALV you just displayed has no functions. Not even sorting.

This is not a styling complaint, it is the documented starting state:

> "By default, there are no functions available to users for working with the ALV
> output. Even the basic functions, such as sorting, filtering, printing and so on are
> not available with the simplest call of an ALV output. In order to allow the user to
> make use of a function, you have to expressly make it available."
> — [SAP List Viewer (ALV), Providing Functions](https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/c28440729a68b8e10000000a42189e/content.htm)

So the four-line snippet above produces a grid the user can look at and essentially
nothing else. Two calls fix it, and they are not the same:

```abap
DATA(lo_functions) = lo_alv->get_functions( ).

lo_functions->set_all( ).        " every generic ALV function
" or
lo_functions->set_default( ).    " SAP's preset selection of the common ones
```

Both are documented, with `SET_DEFAULT` existing only for the list-type tools:

> "You have various options for displaying generic ALV functions:"
>
> - "You enable each generic ALV function individually"
> - "You enable a function group. All of the functions for this function group are enabled simultaneously"
> - "You enable all generic ALV functions simultaneously"

> "In the list-type ALV outputs (simple, two-dimensional table and hierarchical-sequential
> list), there is also a preset default selection of the most frequent generic ALV
> functions."
> — [Using Generic ALV Functions](https://help.sap.com/doc/saphelp_ewm900/9.0/en-US/4e/c20b60138f2b8fe10000000a42189d/content.htm)

The function names are not free text:

> "The names of all generic ALV functions are listed as constants in the interfaces
> IF_SALV_C_FUNCTION LIST (for the simple, two-dimensional table and the
> hierarchical-sequential list) or IF_SALV_C_FUNCTION_TREE (for the tree structure)."
> — same page

(The page's own spelling, `IF_SALV_C_FUNCTION LIST`, has a stray blank where the
underscore belongs; the interface is `IF_SALV_C_FUNCTION_LIST`.)

### The half of this that bites later

A *generic* function's greyed-out state is not yours to control:

> "Although you are able to change the activation status of self-defined functions, you
> do not have this option for generic ALV functions. Here the internal logic of ALV
> determines whether or not a function is operable."

> "When you try to change the activation status of a generic ALV function, you get an
> error."
> — same page

and the getter does not tell you what the user sees:

> "You are able to check the activation status of a self-defined function However, the
> associated method does not include the activation status that the system has set based
> on its internal logic."
> — same page

So `is_enabled( )` returns *your* setting, not the effective one. SAP's own example of
the gap:

> "You set the group *Filter*, making the functions SET_FILTER and SET_FILTER_DELETE
> visible. However, as long as you have not defined a filter, the function
> SET_FILTER_DELETE remains deactivated."
> — same page

---

## 2. `add_function( )` is documented as *not available* in a fullscreen ALV

This is the single most expensive thing on the page. Every "add a custom button to
SALV" tutorial starts with `get_functions( )->add_function( ... )`, and the
documentation's own availability matrix for *creating and displaying* a self-defined
function reads:

| ALV Tool | Display type | Function available |
|---|---|---|
| Simple, two-dimensional table | Classic ABAP List | **No** |
| | Fullscreen | **No** |
| | In the Container | Yes |
| Hierarchical-sequential list | Classic ABAP List | No |
| Tree Structure | Fullscreen | No |
| | In the Container | Yes |

— [Using Self-Defined, Application-Specific Functions](https://help.sap.com/saphelp_em92/helpdata/en/4e/c39dbb88d22b90e10000000a42189d/content.htm)

Because in fullscreen the button does not come from a method at all:

> "In the container display (simple, two-dimensional table or tree structure), you
> strictly create a function object with the desired properties and display the
> pushbutton."

> "In the other display types, you generate the function object indirectly by entering
> the self-defined function into the screen status. Here the function is display
> directly. You do not have to provide any other commands for the display."
> — same page

and stated as a hard limit on the Providing Functions page:

> "In these display types, you are only able to display those functions that you have
> also entered into the screen status."
> — [Providing Functions](https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/c28440729a68b8e10000000a42189e/content.htm)

This is why the symptom is always the same and always misread: the `added_function`
handler is registered correctly, the code is correct, and the button simply is not
there — so people conclude the event is broken and go looking at `SET HANDLER`.

### The fullscreen route, in the documented order

1. Copy the standard status. The defaults are named:

   > "For the simple, two-dimensional table and the hierarchical-sequential list of the
   > screen status SALV_TABLE_STANDARD in the function group SALV_METADATA_STATUS"

   > "For the tree structure of the screen status STANDARD_TREE in the function group
   > SLVC_FULLSCREEN"
   > — same page

   and copying is not optional advice:

   > "Do not change the original screen status. If you want to make changes to the screen
   > status, for example because you want to make custom functions available, use the
   > original screen status as a copy template and then change the copy as needed."
   > — same page

2. Add your function code to the copy in SE41, in your own program.

3. Point the ALV at it:

```abap
lo_alv->set_screen_status(
  report        = sy-cprog                 " the program that OWNS the status
  pfstatus      = 'ZDJ_SALV_STATUS'
  set_functions = lo_alv->c_functions_all ).
```

   **`set_functions` is the parameter you must not omit.** Its default is
   `C_FUNCTIONS_NONE`:

   | Method | Parameter | Optional | Type | Default |
   |---|---|---|---|---|
   | `SET_SCREEN_STATUS` | `PFSTATUS` | yes | `SYPFKEY` | — |
   | | `REPORT` | yes | `SYREPID` | — |
   | | `SET_FUNCTIONS` | yes | `SALV_DE_CONSTANT` | `C_FUNCTIONS_NONE` |

   — `CL_SALV_MODEL_BASE`, read from a public repository mirror (see Sources)

   The three constants are `C_FUNCTIONS_NONE` (0), `C_FUNCTIONS_DEFAULT` (1) and
   `C_FUNCTIONS_ALL` (2), declared as public constants on `CL_SALV_MODEL_BASE` — which
   is why `lo_alv->c_functions_all` resolves even though `CL_SALV_TABLE` does not
   declare them itself.

   So calling `set_screen_status( report = ... pfstatus = ... )` and nothing else gives
   you your custom button and **silently withdraws every generic ALV function** — the
   sort, filter, layout and export buttons your users had a moment ago. Worse, it does
   so regardless of whether you called `get_functions( )->set_all( )` earlier, because
   the screen status is what decides the fullscreen toolbar (§1 made the functions
   *available*; the status decides what is *shown*). The reported symptom is "adding my
   button removed the standard toolbar", and it is one unpassed optional parameter.

4. Register for the event:

```abap
SET HANDLER lo_handler->on_added_function FOR lo_alv->get_event( ).
```

> "If users select the pushbutton for a function that you have defined, they trigger the
> event ADDED_FUNCTION of classes CL_SALV_EVENTS_LIST or CL_SALV_EVENTS_TREE. If you
> register your application for this event, you get control in the method for the event
> handler and can start your desired function code."
> — [Using Self-Defined, Application-Specific Functions](https://help.sap.com/saphelp_em92/helpdata/en/4e/c39dbb88d22b90e10000000a42189d/content.htm)

Note what `report` means: the program in whose GUI status the function code lives. A
status copied into program A cannot be addressed from program B by name alone — which
is exactly why so many snippets borrow SAP's demo program (`report =
'SALV_DEMO_TABLE_EVENTS'`) instead of creating their own status. That works, and it
also means your application's toolbar is now owned by an SAP demo program.

### Two more asymmetries in the same matrix

For a *self-defined* function in fullscreen you may hide it but not grey it out. The
visibility matrix is `Yes` for every display type; the activation-status matrix is the
`No`/`No`/`Yes` shape above — as is "execute a generic ALV function instead of the
self-defined one". So in fullscreen, `set_function( )` works and
`enable_function( )` does not.

And the popup display type has its own status:

> "When you display the ALV output in a separate dialog box, the screen status
> SALV_TABLE_STDPOPUP (function group SALV_METADATA_STATUS) is automatically used. If
> you want to change this screen status, you have to first copy the original screen
> display in a backup copy and then make the desired changes."
> — [ALV Output Display in a Dialog Box](https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/c24e9e107868bae10000000a42189e/content.htm)

---

## 3. One boolean in `factory( )` decides which of your later method calls are legal

`LIST_DISPLAY` has a default, and it is not the classic list:

| Parameter | Pass | Optional | Type | Default |
|---|---|---|---|---|
| `CONTAINER_NAME` | by reference | yes | `STRING` | — |
| `LIST_DISPLAY` | by reference | yes | `SAP_BOOL` | `IF_SALV_C_BOOL_SAP=>FALSE` |
| `R_CONTAINER` | by reference | yes | `REF TO CL_GUI_CONTAINER` | — |
| `R_SALV_TABLE` | *exporting* | yes | `REF TO CL_SALV_TABLE` | — |
| `T_TABLE` | **changing**, by reference | yes | `TABLE` | — |

(raises `CX_SALV_MSG`)

and the combination, not the boolean alone, picks the display type:

| Display type | `LIST_DISPLAY` | `R_CONTAINER` | `CONTAINER_NAME` |
|---|---|---|---|
| Classic ABAP list | `ABAP_TRUE` | Initial | Initial |
| Fullscreen | `ABAP_FALSE` | Initial | Initial |
| In the Container | `ABAP_FALSE` | Reference to container; type `CL_GUI_CONTAINER` | Name of the container |

— [Display Types](https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/bc6ddaf39c68bbe10000000a42189e/content.htm)

Omitting all three therefore gives you a **fullscreen** ALV, which is the display type
in which `add_function( )` does not work. The four-line snippet at the top of this note
is already on the wrong side of §2.

The split is not cosmetic. It is about who owns the screen:

> "You are able to use the ALV object model to control the entire screen in the
> following display types:"
>
> - "In the classic ABAP list"
> - "In the full-screen display"

> "On the other hand, if you use the display in a GUI container, the effect of the
> methods on the area within the container is limited. The screen status and
> header/footer area of the ALV output cannot be reached from the ALV object model."
> — same page

Hence the mirror-image availability of the two toolbar mechanisms:

| | Classic list | Fullscreen | In container |
|---|---|---|---|
| `set_screen_status( )` | Yes | Yes | **No** |
| `set_screen_popup( )` | Yes | Yes | **No** |
| `add_function( )` | **No** | **No** | Yes |

(first row from [Providing Functions](https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/c28440729a68b8e10000000a42189e/content.htm),
second from [ALV Output Display in a Dialog Box](https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/c24e9e107868bae10000000a42189e/content.htm),
third from [Self-Defined Functions](https://help.sap.com/saphelp_em92/helpdata/en/4e/c39dbb88d22b90e10000000a42189d/content.htm))

There is no display type in which both work. Any snippet that calls
`set_screen_status( )` *and* `add_function( )` is wrong in one of the two calls, no
matter which display type it runs in.

How loudly it fails is the part worth knowing, and the two sources disagree in a way
that resolves usefully. The interface says no exception at all:

> `Method SET_SCREEN_STATUS on class CL_SALV_MODEL_BASE has no exception.`
> — `CL_SALV_MODEL_BASE`, public repository mirror

while community write-ups report that calling it on a container ALV raises
`CX_SALV_METHOD_NOT_SUPPORTED`, on the grounds that "in this case the PF-Status is
handled in the screen (externally of the ALV)". Both can be true only if that exception
is a **no-check** exception — one that needs no `RAISING` clause and appears in no
signature. The practical consequences of that reading, which is an inference and
labelled as one:

- it will not show up when you read the method's interface in SE24, so the matrix above
  is the only advance warning you get;
- a `TRY ... CATCH cx_salv_msg` wrapped around your `factory( )` call — the one every
  snippet has — does not catch it, because `CX_SALV_MSG` is a different branch;
- so the container/fullscreen mismatch surfaces as a short dump at the
  `set_screen_status( )` line rather than as a handled error.

Treat the exception name as community-reported (see Sources) and the no-check reasoning
as this note's inference, not as documentation.

A documented consequence worth knowing before choosing fullscreen for convenience:

> "The ALV output takes up the whole screen. This means you are only able to display one
> ALV output."
> — [Display Types](https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/bc6ddaf39c68bbe10000000a42189e/content.htm)

Two grids on one screen is a container requirement, and containers need a dynpro — see
[Dynpro Flow Logic](../Dynpro%20Flow%20Logic#readme) for the PBO/PAI side of that.

Ordering of pushbuttons flips too, in a way that quietly invalidates code review
instincts:

> "In container display (simple, simple two-dimensional table or tree structure) you are
> not able to change the sequence of the pushbuttons."

> "In the other display types, you use the screen status to set the position of a
> pushbutton or the menu entry. The pushbutton is then displayed at the position set here
> no matter in which sequence you call the SET functions."
> — [Using Generic ALV Functions](https://help.sap.com/doc/saphelp_ewm900/9.0/en-US/4e/c20b60138f2b8fe10000000a42189d/content.htm)

And menus exist on only one side of the split:

> "In the container display, you are only able to add pushbuttons in the application
> toolbar. You are not able to generate menu entries."
> — [Self-Defined Functions](https://help.sap.com/saphelp_em92/helpdata/en/4e/c39dbb88d22b90e10000000a42189d/content.htm)

---

## 4. To let the user select a single row in fullscreen, the selection mode must be `NONE`

`SET_SELECTION_MODE`'s parameter defaults to `IF_SALV_C_SELECTION_MODE=>NONE`, and
"NONE" does not mean "no selection". The documentation maps the *behaviour you want* to
the *constant you must set*, and the mapping differs per display type:

| Function required | Classic ABAP List / Hier.-Seq. List | Fullscreen / Container |
|---|---|---|
| Selecting specific columns | `NONE` | `NONE` |
| Selecting single rows | `SINGLE` | **`NONE`** |
| Select individual cell | `NONE` | `CELL` |
| Select multiple cells (with CTRL or shift key) | **Not possible** | `CELL` |
| Select one or multiple rows and one or more columns (with CTRL key) | `SINGLE` | `MULTIPLE` / `ROW_COLUMN` / `CELL` |
| Provide pushbutton or checkbox to select rows | `SINGLE` | `ROW_COLUMN` / `CELL` |

— [Selecting Cells, Rows, and Columns](https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/c3d14488d22b90e10000000a42189d/content.htm)

Read the second row twice. In a fullscreen ALV, single-row selection is the *default*
state, and explicitly setting `SINGLE` — the constant whose name says "single" — is the
setting for the classic list instead. Column one and column two disagree on four of the
six rows, and which column applies to you was decided by the `LIST_DISPLAY` boolean in
§3.

So this is the shape of the bug: a developer tests in a fullscreen report, row selection
works without any selection code, the program is later switched to `list_display =
abap_true` (or the snippet is copied into a classic-list program), and selection stops
working with no code change on the selection side at all.

The checkbox column people actually want needs `ROW_COLUMN` or `CELL` in fullscreen, not
`MULTIPLE` — note that `MULTIPLE` appears in exactly one row of that table.

Reading back what the user picked:

```abap
DATA(lo_sel) = lo_alv->get_selections( ).
lo_sel->set_selection_mode( if_salv_c_selection_mode=>row_column ).
...
DATA(lt_rows) = lo_sel->get_selected_rows( ).   " SALV_T_ROW - indexes, not keys
```

`SALV_T_ROW` is a table of **row indexes into the table you passed to `factory( )`**, not
of row contents and not of keys. That matters once the user has sorted or filtered the
display: the index is still an index into your internal table, so the mapping only holds
because ALV sorts its *own* view. Resolve each index against the original table rather
than re-sorting it yourself.

That `SALV_T_ROW` carries nothing but row numbers is visible in the method interface:
`CL_SALV_SELECTIONS->GET_SELECTED_ROWS` returns `SALV_T_ROW`, and the convenience
method `CL_SALV_TABLE->GET_SELECTED_ROWS` returns a plain table of `I`. Neither returns
a row of your structure, so there is no version of this API that hands you the selected
*data* — the lookup against your own table is always yours to write.

Also note the cursor-vs-selection distinction, which is why "get the row the user is on"
and "get the rows the user ticked" are different methods:

> "The current cell indicates the position of the cursor in the simple, two-dimensional
> table and the hierarchical-sequential list. The current cell is highlighted differently
> from the selected cells."
> — same page

---

## 5. The ALV holds your table by reference, and `refresh( )` defaults to losing the user's place

`T_TABLE` in `factory( )` is a `CHANGING` parameter passed **by reference**. The ALV does
not copy your data; it reads the table you handed it. Two consequences:

- Changing the internal table changes what the ALV will show on the next render. No
  re-`factory( )` is needed, and `display( )` is not how you redraw.
- If that table goes out of scope while the ALV lives — a local table in a method that
  returns, a `FORM`-local table — the reference outlives the data. Keep the displayed
  table in a lifetime at least as long as the ALV instance's. (This is the same
  reference-lifetime discipline as [Field Symbols](../Field%20Symbols#readme), with the
  dangling side owned by a framework instead of by your code.)

Redrawing is `refresh( )`, whose defaults are the interesting part:

| Parameter | Pass | Optional | Type | Default |
|---|---|---|---|---|
| `REFRESH_MODE` | by reference | yes | `SALV_DE_CONSTANT` | `IF_SALV_C_REFRESH=>SOFT` |
| `S_STABLE` | by reference | yes | `LVC_S_STBL` | — *(initial)* |

`S_STABLE` left initial means neither row nor column position is held stable, so a
refresh scrolls the user back to the top. The fix is the one line nobody copies:

```abap
lo_alv->refresh( s_stable = VALUE lvc_s_stbl( row = abap_true col = abap_true ) ).
```

Two details worth noting about that signature. `LVC_S_STBL` is an `LVC_*` structure —
i.e. a type from the older `CL_GUI_ALV_GRID` world, surfacing through the "new" object
model, which is a reliable hint that SALV is a wrapper rather than a reimplementation.
And `refresh( )` has **no exceptions at all**, as does `display( )`:

> `Method DISPLAY on class CL_SALV_TABLE has no parameter.`
> `Method DISPLAY on class CL_SALV_TABLE has no exception.`
> `Method REFRESH on class CL_SALV_TABLE has no exception.`
> — `CL_SALV_TABLE` interface, read from a public repository mirror (see Sources)

So `display( )` taking no parameters is also the answer to "how do I display it in a
popup" — you do not pass anything to `display( )`, you call `set_screen_popup( )`
beforehand.

### `set_data( )` is for a different table, and it is narrower than `factory( )`

| Method | `T_TABLE` typing | Exception |
|---|---|---|
| `factory( )` | `TABLE` | `CX_SALV_MSG` |
| `set_data( )` | `STANDARD TABLE` | `CX_SALV_NO_NEW_DATA_ALLOWED` |

Two things fall out of that table:

- A **sorted or hashed** table can be displayed by `factory( )` (typing `TABLE` accepts
  any table category) but cannot be passed to `set_data( )` (typing `STANDARD TABLE`).
  So "display it, then later swap the data" is available for standard tables only — a
  constraint created by the generic typing, with no runtime message explaining it.
  See [Internal Table Keys](../Internal%20Table%20Keys#readme) for why the category is
  rarely `STANDARD` by accident.
- `set_data( )` can refuse. `CX_SALV_NO_NEW_DATA_ALLOWED` ("ALV: Setting new data not
  allowed") means the usual loop of *swap the table, then refresh* has a failure mode,
  and it is a checked exception you have to handle. Changing the *contents* of the
  table you already gave `factory( )` and calling `refresh( )` has no such restriction,
  which makes it the more robust pattern.

---

## 6. Aggregation skips `NUMC` on purpose, and you get one per column

```abap
lo_alv->get_aggregations( )->add_aggregation(
  columnname  = 'SEATSOCC'
  aggregation = if_salv_c_aggregation=>total ).
```

`AGGREGATION` is in fact optional and already defaults to
`IF_SALV_C_AGGREGATION=>TOTAL`, so `add_aggregation( columnname = 'SEATSOCC' )` alone
is a total. Spelling it out is still worth doing — it is the one call on this class
whose meaning is invisible otherwise. The method also returns the
`CL_SALV_AGGREGATION` object it created, and raises three checked exceptions:
`CX_SALV_DATA_ERROR`, `CX_SALV_EXISTING` (a second aggregation on the same column) and
`CX_SALV_NOT_FOUND` (no such column).

The default eligibility rule has a carve-out that catches every "why does my total
column refuse to total" question:

> "By default, all columns with a numeric data type can be aggregated with the exception
> of columns of data type NUMC."
> — [Making Aggregation Settings](https://help.sap.com/docs/ABAP_PLATFORM_BW4HANA/b1c834a22d05483b8a75710743b5ff26/4ec2686758e968b9e10000000a42189e.html)

`NUMC` is numeric *text* — the type of document numbers, item numbers, plant codes,
posting periods. Excluding it is correct far more often than not, which is why the
override exists in both directions:

> "In columns that actually have a suitable data type, forbid aggregation"
> "In columns of data type numeric text, you explictly allow aggregation"
> — same page

via `SET_AGGREGATION_ALLOWED` and `SET_NUMERICAL_AGGREGATION` on
`CL_SALV_AGGREGATIONS`. If you find yourself reaching for `SET_NUMERICAL_AGGREGATION`,
it is worth asking first whether summing that column means anything — summing item
numbers usually does not.

Two more documented limits:

> "You are able to create a maximum of one calculation for every column."
> — same page

so Total *and* Average on the same column is not a thing, and the per-tool table says
the hierarchical-sequential list supports **only** the total — Minimum, Maximum and
Average are `No` there, while the simple table and the tree get all four.

Clearing settings has two distinct methods and they are not the same:
`CL_SALV_AGGREGATIONS->REMOVE_AGGREGATION` deletes the aggregation object, while
`CL_SALV_AGGREGATION->CLEAR` deletes "the settings for an aggregation object without
deleting the aggregation object itself".

---

## 7. Layout management: the line everyone copies is a no-op, and the one that matters is `set_key( )`

The snippet in circulation is:

```abap
DATA(lo_layout) = lo_alv->get_layout( ).
lo_layout->set_key( VALUE #( report = sy-cprog ) ).
lo_layout->set_save_restriction( cl_salv_layout=>restrict_none ).
```

The third line changes nothing. `SET_SAVE_RESTRICTION`'s parameter already defaults to
`IF_SALV_C_LAYOUT=>RESTRICT_NONE`:

| Method | Parameter | Optional | Type | Default |
|---|---|---|---|---|
| `SET_SAVE_RESTRICTION` | `VALUE` | yes | `SALV_DE_LAYOUT_RESTRICTION` | `IF_SALV_C_LAYOUT=>RESTRICT_NONE` |
| `SET_KEY` | `VALUE` | **no** | `SALV_S_LAYOUT_KEY` | — |
| `SET_DEFAULT` | `VALUE` | **no** | `SAP_BOOL` | — |
| `SET_INITIAL_LAYOUT` | `VALUE` | **no** | `SLIS_VARI` | — |

— `CL_SALV_LAYOUT`, read from a public repository mirror (see Sources)

So the restriction call is defensive documentation at best; it is `set_key( )` that is
load-bearing, its parameter is **not optional**, and without a layout key there is
nothing for a saved layout to be keyed against. That is the actual cause of "the
Save Layout button is there and does nothing".

Note the last row: `SET_INITIAL_LAYOUT` is typed `SLIS_VARI` — the layout-variant type
from the *old* function-module ALV (`REUSE_ALV_GRID_DISPLAY` and the `SLIS` type pool).
The same type you would use for a `PARAMETERS p_vari TYPE slis_vari` on the selection
screen, which is how the two generations of ALV end up in one program signature.

`CL_SALV_LAYOUT` is a small class — `SET_KEY`, `SET_DEFAULT`, `SET_INITIAL_LAYOUT`,
`SET_SAVE_RESTRICTION` and the four matching getters, plus `GET_LAYOUTS` and
`GET_CURRENT_LAYOUT`. Anything beyond that (an F4 help over existing layouts, reading
the user's default) is `CL_SALV_LAYOUT_SERVICE`, a separate class, not a method on the
ALV.

---

## 8. Column texts come from the DDIC reference, and *how much* comes depends on the typing matching

Columns of an ALV over a DDIC-typed table arrive with headers for free, and columns over
a locally-declared structure arrive bare. The rule for what transfers is in two parts,
and the split is the useful bit:

> "No matter whether the type of your column agrees with that of the referenced DDIC
> field, the following properties are always transferred to your column."
>
> - "Short, medium-length, and long text of your column title"
> - "F1 help text"

> "If the typing also matches (internal type and internal length), the remaining
> properties are also transferred, such as"
>
> - "F4 help and search help"
> - "Data element and domain"
> - "Columns for quantity, currency, decimal places, and rounding"
>
> — [Changing DDIC References for a Column](https://help.sap.com/docs/SAP_NETWEAVER_AS_ABAP_FOR_SOH_740/b1c834a22d05483b8a75710743b5ff26/4ebc6b54f39c68bbe10000000a42189e.html)

That is a partial-success mode, and it is the one that produces "the column is titled
correctly but the amount is formatted wrong". A computed column declared as
`TYPE p LENGTH 9 DECIMALS 2` and given `set_ddic_reference( )` to a `CURR` field gets
the **title** (always transferred) and loses the **currency reference column**
(typing does not match). The amount then renders without regard to the currency's
decimal places — the same class of defect as in
[Currency Amounts](../Currency%20Amounts#readme), arriving through the display layer
instead of through arithmetic.

The fix is to type the column like its DDIC field, not merely to point at it. And for
a whole structure at once:

> "If multiple columns of your ALV output have the same name as the fields in a DDIC
> structure that already exists, you assign the entire DDIC structure to your ALV
> output. Like-named columns receive the properties of the corresponding fields in the
> DDIC structure."
> — same page

that is `CL_SALV_COLUMNS->APPLY_DDIC_STRUCTURE`, matched **by name**. Which means a
column that happens to share a name with an unrelated DDIC field inherits that field's
texts — the usual by-name-matching hazard, as with
[CORRESPONDING](../Corresponding%20Operator#readme).

For a table with no DDIC typing at all, `CL_SALV_COLUMN->SET_SHORT_TEXT` /
`SET_MEDIUM_TEXT` / `SET_LONG_TEXT` are the manual route, and all three should be set:
ALV picks by available width, so setting only the long text leaves a narrow column
blank-headed. These are text literals in your program, so the
[Text Elements](../Text%20Elements#readme) caveat applies if you route them through
`TEXT-nnn`.

---

## 9. "Can I make it editable?" — no, and the workarounds are unreleased

This is the most-asked SALV question, so it is worth stating the answer plainly rather
than leaving it to be discovered after a sprint of design work: `CL_SALV_TABLE` offers
no input-ready display. The class documentation's own Recommendations and Restrictions
section is quoted as "Tables displayed with ALV are not ready for input" — a quote from
the in-system class documentation, which this note reproduces **second-hand** from a
long-standing community write-up (see Sources) rather than from a page on SAP Help
Portal, because that section is not published there.

What exists, and the honest status of each:

- **`CL_GUI_ALV_GRID`** — the older control, which does support editing and is what SALV
  wraps. This is the supported answer, with the caveat that community discussion cites
  SAP Note 695910 ("ALV Grid: Editable grid and methods that are not released") as
  limiting support for the edit methods in *custom* programs. Treat that note number as
  a pointer to look up on your own system, not as a verified quote — it is behind the
  SAP support login and was not read for this note.
- **Reaching the underlying grid out of SALV** — the classic trick of inheriting from
  `CL_SALV_MODEL_LIST` to reach the protected controller, then `get_grid( )` and
  `set_frontend_layout( )`. Community-reported, works, and explicitly a workaround
  around a documented restriction. It also depends on SALV's internal class hierarchy,
  which community reports say changed in release 7.56 — so this one has a known
  expiry date.
- **`extended_grid_api( )` / `editable_restricted( )`** — newer interface methods
  reported from 7.56 onward, with `set_attributes_for_columnname( )` and
  `validate_changed_data( )`. All of this is community-reported; it is not in the
  SAP List Viewer documentation used for the rest of this note, and one community
  comment reports an internal 5000-cell ceiling in the implementation. Verify against
  your own release in SE24 before designing around it.

The repo's position: if the requirement is "the user edits rows", that is a
`CL_GUI_ALV_GRID` requirement or a RAP/Fiori requirement, not a SALV one. If the
requirement is "the user triggers an action on selected rows", that is §2 plus §4 and
SALV is the right tool.

---

## 10. Where SALV already appears in this repo

`cl_salv_table=>factory( )` turns up twice in
[Excel Operations](../Excel%20Operations) with no explanation, used purely as a
serializer:

```abap
cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_table)
                        CHANGING  t_table      = lt_data ).
DATA(lv_xml) = lo_table->to_xml( xml_type = if_salv_bs_xml=>c_type_xlsx ).
```

That is `TO_XML` — one of `CL_SALV_TABLE`'s own 14 public methods, alongside `FACTORY`,
`DISPLAY`, `REFRESH`, `SET_DATA`, the seven `GET_*` accessors and `GET_METADATA`. The
instance is never displayed; it exists only to build the field catalogue from the
table's type and hand back an XLSX stream. It is a legitimate and very economical use
of the class, and it is also why that snippet does not need any of sections 1 through 8
— no screen, no functions, no selections.

Everything else on `CL_SALV_TABLE` — `set_screen_status( )`, `get_layout( )`,
`get_display_settings( )`, `set_screen_popup( )` — comes from its superclasses, not from
the class itself. Which is the structural reason the community workaround in §9 existed
at all, and the reason it broke when SAP changed that inheritance.

---

## Sources

SAP List Viewer (ALV) documentation on SAP Help Portal. This guide exists in both the
current `help.sap.com/docs/...` tree and the older `help.sap.com/doc/saphelp_*` tree;
the page IDs are the same and the older tree renders the availability matrices more
completely, so it is cited where the matrix is the point.

- [SAP List Viewer (ALV)](https://help.sap.com/docs/ABAP_PLATFORM_NEW/b1c834a22d05483b8a75710743b5ff26/4ec38f8788d22b90e10000000a42189d.html) — the three ALV tools, the "unified, object-oriented API" framing
- [Display Types](https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/bc6ddaf39c68bbe10000000a42189e/content.htm) — the `LIST_DISPLAY`/`R_CONTAINER`/`CONTAINER_NAME` matrix, who owns the screen, one-ALV-per-fullscreen
- [Providing Functions](https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/c28440729a68b8e10000000a42189e/content.htm) — **the no-functions-by-default quote**, `SALV_TABLE_STANDARD` / `SALV_METADATA_STATUS`, the do-not-change-the-original rule, the `set_screen_status` availability row
- [Using Generic ALV Functions](https://help.sap.com/doc/saphelp_ewm900/9.0/en-US/4e/c20b60138f2b8fe10000000a42189d/content.htm) — `SET_ALL` / `SET_DEFAULT` / groups, `IF_SALV_C_FUNCTION_LIST`, `BEFORE_SALV_FUNCTION` / `AFTER_SALV_FUNCTION`, the activation-status-is-not-yours rule and the error on trying
- [Using Self-Defined, Application-Specific Functions](https://help.sap.com/saphelp_em92/helpdata/en/4e/c39dbb88d22b90e10000000a42189d/content.htm) — **the `ADD_FUNCTION` fullscreen `No`**, the screen-status route, `ADDED_FUNCTION`, no menus in a container, the visibility-vs-activation asymmetry
- [ALV Output Display in a Dialog Box](https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/c24e9e107868bae10000000a42189e/content.htm) — `SALV_TABLE_STDPOPUP`, `SET_SCREEN_POPUP` and its container `No`
- [Selecting Cells, Rows, and Columns](https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/c3d14488d22b90e10000000a42189d/content.htm) — **the Required Selection Type table**, current cell vs selected cells, the `GET_SELECTED_*` method list
- [Making Aggregation Settings](https://help.sap.com/docs/ABAP_PLATFORM_BW4HANA/b1c834a22d05483b8a75710743b5ff26/4ec2686758e968b9e10000000a42189e.html) — the `NUMC` exclusion, one aggregation per column, the four calculation types and the hier.-seq. restriction
- [Changing DDIC References for a Column](https://help.sap.com/docs/SAP_NETWEAVER_AS_ABAP_FOR_SOH_740/b1c834a22d05483b8a75710743b5ff26/4ebc6b54f39c68bbe10000000a42189e.html) — the always-transferred vs only-if-typing-matches split, `APPLY_DDIC_STRUCTURE`
- [GUI Status in Fullscreen Display (ALV with IDA)](https://help.sap.com/docs/ABAP_PLATFORM_2020/b1c834a22d05483b8a75710743b5ff26/2ef2af0865d54605b98aeed26085cbb4.html) — the parallel ALV-with-IDA mechanism (`set_pf_status`, `function_selected`), for contrast only; IDA is a different API from `CL_SALV_TABLE`

### Method signatures

Parameter names, typings, optionality, defaults and exceptions for `CL_SALV_TABLE` and
`CL_SALV_LAYOUT` were read from **public SE24 mirrors**
([`CL_SALV_TABLE`](https://www.sapdatasheet.org/abap/clas/cl_salv_table.html),
[`CL_SALV_LAYOUT`](https://www.sapdatasheet.org/abap/clas/cl_salv_layout.html),
[`CL_SALV_SELECTIONS`](https://www.sapdatasheet.org/abap/clas/cl_salv_selections.html),
[`CL_SALV_MODEL_BASE`](https://www.sapdatasheet.org/abap/clas/cl_salv_model_base.html)),
not from a live system. They are the source for the `LIST_DISPLAY` default, the
`REFRESH_MODE = IF_SALV_C_REFRESH=>SOFT` default, the initial `S_STABLE`, the
`TABLE` vs `STANDARD TABLE` asymmetry between `FACTORY` and `SET_DATA`, the
`SET_SAVE_RESTRICTION` default and the non-optional `SET_KEY`, and for the
`SET_FUNCTIONS = C_FUNCTIONS_NONE` default and the `C_FUNCTIONS_*` constant values.
**Re-check these in SE24 on your own release** before relying on a default — mirrors
reflect one release, and §9 is a worked example of this class's signature changing
between releases.

### Community sources (used in §2, §3 and §9, and labelled at each use)

- [SALV Table (Digicracy)](https://digicracy.wordpress.com/2013/02/02/salv-table/) — the report that `set_screen_status( )` on a container ALV raises `CX_SALV_METHOD_NOT_SUPPORTED` "because in this case the PF-Status is handled in the screen (externally of the ALV)", and an independent statement of the `C_FUNCTIONS_NONE` default for `set_functions` (§2, §3)
- [Overcome the Restrictions of SALV Model](https://community.sap.com/t5/application-development-and-automation-blog-posts/power-of-abap-objects-overcome-the-restrictions-of-salv-model/ba-p/12896430) — the source of the second-hand "Tables displayed with ALV are not ready for input" quote from the in-system class documentation, and of the `CL_SALV_MODEL_LIST` inheritance workaround
- [Editable CL_SALV_TABLE after release 756](https://community.sap.com/t5/application-development-and-automation-blog-posts/editable-cl-salv-table-after-release-756/ba-p/13532790) — `extended_grid_api( )` / `editable_restricted( )` / `validate_changed_data( )`, and the comment reporting a 5000-cell ceiling
- [Make CL_SALV_TABLE column editable?](https://stackoverflow.com/questions/72113516/make-cl-salv-table-column-editable) — the "SALV offers no edit feature" answer and the pointer to SAP Note 695910

### Transcription note

Every blockquote above was re-checked by exact substring match against the text of the
pages as fetched for this note. Four deliberate deviations, disclosed rather than
silently normalised:

1. **Link markup removed inside two sentences.** The SAP pages carry a hyperlink on the
   words "screen status" mid-sentence, so the raw text reads "...you use the
   `[screen status](...)` to set the position...". The quotes here drop the link markup
   and keep the words. Affected: the two "In the other display types..." quotes in §2
   and §3.
2. **Bullet lists kept as bullets.** Where SAP's sentence is a lead-in to a bulleted
   list (the generic-function options in §1, the screen-control display types in §3,
   the two DDIC-transfer lists in §8), the lead-in and the bullets are quoted
   separately with the list structure preserved, rather than flattened into one
   sentence with inserted dashes. Flattening is what makes a quote stop matching its
   source, and it was the defect caught on read-back in this repo's SQL Hierarchies
   note.
3. **Emphasis syntax differs.** SAP's page writes the function group as `_Filter_`;
   this note writes `*Filter*`. Same word, same emphasis, different markdown dialect.
4. **The selection-type table's second column header.** The source header is rendered
   as "Fullscreen Container" with a line break between the two words and no separator;
   it is written here as "Fullscreen / Container" because the two words are two display
   types sharing one column, not a single display type named "Fullscreen Container".
   The *cell values* are transcribed exactly, including the `SINGLE` / `NONE` row that
   §4 is built on.

SAP's own typography is kept verbatim inside quotes, including "you explictly allow
aggregation" (§6) and "Here the function is display directly" (§2) — both are the
source's wording, not transcription errors introduced here. Likewise the stray blank in
`IF_SALV_C_FUNCTION LIST`, flagged in §1 where it appears.

Worked, runnable example: [ydj_salv_table_demo.abap](ydj_salv_table_demo.abap)
