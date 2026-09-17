# Program Calls & ABAP Memory — `SUBMIT` LUW traps, the `IMPORT` value bleed and SPA/GPA

Handing work to another program is everyday ABAP: a wrapper report that submits the
standard SAP report, a job scheduler that fills a selection screen from a table, a
transaction that pre-fills the next screen through user parameters. Three mechanisms
carry the data — `SUBMIT ... WITH`, the ABAP Memory (`EXPORT`/`IMPORT ... MEMORY ID`)
and SPA/GPA parameters (`SET`/`GET PARAMETER`) — and all three have documented
behaviour that does not match the mental model most developers carry around.

The dangerous ones are silent: no dump, no syntax error, and in the `IMPORT` case
`sy-subrc = 0` on data that was never read.

---

## 1. `SUBMIT` without `AND RETURN` throws away your registered update modules

`SUBMIT` ends the SAP LUW of the calling program. If update function modules were
already registered with `CALL FUNCTION ... IN UPDATE TASK` (or `IN BACKGROUND TASK`)
and no `COMMIT WORK` has run yet, they are not executed and not rolled back — they
simply cease to exist:

> If there are still procedures registered in the current SAP LUW for `SUBMIT`
> statements without `AND RETURN`, the SAP LUW is terminated without calling or
> rolling back the procedures. Registered update function modules can no longer be
> executed. In this case, the statement `COMMIT WORK` or `ROLLBACK WORK` should be
> executed explicitly before the program is called.

— [`SUBMIT`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapsubmit.htm)

So the posting you thought you made disappears, quietly, with `sy-subrc = 0`
everywhere. This is not an exotic case: `SUBMIT` as the last statement of a wrapper
report is the normal way to chain reports.

### `AND RETURN` is not the safe version either

`AND RETURN` opens a **new SAP LUW but not a new database LUW** — the two nest
differently. Consequence, from the same page:

> This means that a database rollback in this SAP LUW, in particular, can roll back
> all registration entries made by the statements `CALL FUNCTION IN UPDATE TASK` or
> `CALL FUNCTION IN BACKGROUND TASK` in the tables `VB...` or `ARFCSSTATE` and
> `ARFCSDATA`. Under certain circumstances, the statement `ROLLBACK WORK` in the
> called program can also affect the interrupted SAP LUW.

A `ROLLBACK WORK` inside somebody else's report — a standard SAP report you do not
control — reaches back into *your* uncommitted work. The documented fix is the same
one line in both cases:

```abap
" Close your own LUW before handing control over. Do this even for AND RETURN.
COMMIT WORK.                  " or ROLLBACK WORK, whichever is correct here
SUBMIT zreport_child AND RETURN.
```

Two more consequences of the same LUW rules, worth knowing before you debug them:

- `SUBMIT` never ends the **database** LUW, with or without `AND RETURN`. A database
  commit inside the called program behaves exactly as if it had happened in yours —
  which is why `SUBMIT ... AND RETURN` **between `FETCH` statements closes your open
  cursor** (see [Mass Data Processing](../Mass%20Data%20Processing#readme); list or
  dynpro processing in the child is enough to trigger it).
- A call sequence holds at most **nine internal sessions**. Exceeding it with
  `SUBMIT ... AND RETURN` terminates the program *and deletes the entire call
  sequence*. Recursive or loop-driven submits hit this.

---

## 2. `WITH` takes values in **internal** format, and the errors are runtime errors

The values passed to a selection screen are not screen input. The doc states it for
both variants of the addition:

> When values are specified, these must have the internal format of the ABAP values,
> and not the output format of the screen display.

— [`SUBMIT, selscreen_parameters`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapsubmit_selscreen_parameters.htm)

So a date is `'20260918'`, never `'18.09.2026'`, and a customer number goes in
`'0000004711'` (with leading zeros) — a conversion exit is *not* applied. Passing the
display form usually selects nothing at all rather than failing, which is how it gets
to production.

What is easy to miss is that the mistakes here are **uncatchable runtime errors, not
syntax errors**, so the extended program check will not save you:

| Runtime error | Cause |
|---|---|
| `SUBMIT_PARAM_NOT_CONVERTIBLE` | value cannot be converted to the target field's type |
| `SUBMIT_IMPORT_ONLY_PARAMETER` | more than one value passed to a `PARAMETERS` field |
| `SUBMIT_WRONG_SIGN` | `SIGN` other than `'I'`/`'E'` |
| `SUBMIT_WRONG_TYPE` | the target program is not an executable program |
| `LOAD_PROGRAM_NOT_FOUND` | program name (often dynamic) does not exist |

— [`SUBMIT`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapsubmit.htm)

`SUBMIT_IMPORT_ONLY_PARAMETER` is the common one: a routine that builds `RSPARAMS`
rows generically appends two lines for the same name. For a `SELECT-OPTIONS` that is
a two-line ranges table; for a `PARAMETERS` field it is a dump. (With the `WITH sel`
syntax the last value silently wins instead — same input, different outcome.)

### `RSPARAMS` truncates at 45 characters

`WITH SELECTION-TABLE rspar` expects line type `RSPARAMS`, whose `LOW`/`HIGH` are
`CHAR(45)`. A longer value — a long material number, an email, a URL, a
concatenated key — is cut without complaint. Since 7.2 the fix is a different type:

```abap
DATA lt_rspar TYPE TABLE OF rsparamsl_255.   " LOW/HIGH are CHAR(255)
```

Also from that page: all `RSPARAMS` columns are type `c` and converted on transfer
(unlike a real ranges table, which is typed), `KIND` must be `'P'` for parameters and
`'S'` for select-options, and `SELNAME` must be **uppercase**. To capture the caller's
own selection screen into such a table, use `RS_REFRESH_FROM_SELECTOPTIONS`.

---

## 3. `IMPORT` is a *merge*, not an assignment — missing parameters keep the old value

This is the quiet one. If a parameter named in the `IMPORT` list is not in the data
cluster, the statement does not fail and does not clear anything:

> If a parameter `p` is specified and it is not stored in the data cluster, the
> specification will be ignored and the data object `dobj` retains its current value.

— [`IMPORT, parameter_list`](https://help.sap.com/doc/abapdocu_750_index_htm/7.50/en-US/abapimport_parameterlist.htm)

`sy-subrc` only distinguishes *cluster found* from *cluster not found*:

| `sy-subrc` | Meaning |
|---|---|
| `0` | The cluster was found; **nonexistent parameters were ignored** |
| `4` | The specified data cluster was not found |

— [`IMPORT`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapimport_data_cluster.htm)

Put that in a loop over documents, with a producer that only exports the optional
fields *sometimes*, and document 2 inherits document 1's values — a data-correctness
bug with a clean `sy-subrc = 0` in the log. This is structurally the same trap as the
`clear = 'none'` default in [JSON Serialization](../JSON%20Serialization#readme):
initialize your targets yourself, or export every parameter every time.

Two related tolerances on the same page, both of which let a mismatch through:

- Type `c` fields may differ in **length** between export and import (conversion rule
  applies — i.e. silent truncation on the right).
- The target structure may have **more components** at top level than the source; the
  surplus ones get initial values. Handy for release changes, lethal if you swapped
  two components instead of appending one. The extended check warns about this for
  enhanceable DDIC structures.

---

## 4. `FREE MEMORY` without `ID` deletes **everything**, `EXPORT` without `ID` does not

The short forms of the two statements are not symmetric, and the doc calls this out
explicitly:

> While the statement `EXPORT` without addition `ID` affects only one data cluster,
> for `FREE MEMORY`, all clusters are affected. It is safest to use the statement
> `DELETE FROM`, because here the addition `ID` is mandatory.

— [`FREE MEMORY`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPFREE_MEMORY.html)

So a tidy-up line at the end of your report wipes the ABAP Memory of every other
program in the same call sequence — including the caller that is waiting to read its
own cluster back after `SUBMIT ... AND RETURN`. Always:

```abap
DELETE FROM MEMORY ID 'ZDJ_ORDER_CONTEXT'.   " ID is mandatory here - use this form
```

Rules for the ID itself ([`EXPORT, medium`](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapexport_data_cluster_medium.htm)):
flat character-like, max **60 characters**, and **case-sensitive** — `'zdj_ctx'` and
`'ZDJ_CTX'` are two different clusters, which is the usual reason a hand-typed
`IMPORT` returns `sy-subrc = 4` while the `EXPORT` "definitely ran". An `EXPORT` to an
existing ID overwrites that cluster **completely**; it does not merge (only `IMPORT`
merges — trap 3).

Scope: the ABAP Memory is available to all programs of the same **call sequence**,
which is exactly what makes it the right channel for `SUBMIT`. It is not a cache
between users or between sessions — for that, `SHARED BUFFER`/`SHARED MEMORY` exist,
and the doc recommends shared objects over both.

---

## 5. `EXPORTING LIST TO MEMORY` works only on the first execution

The classic "run the standard report and grab its list" pattern:

```abap
DATA lt_list TYPE TABLE OF abaplist.

SUBMIT zreport_child EXPORTING LIST TO MEMORY AND RETURN.   " AND RETURN is mandatory

CALL FUNCTION 'LIST_FROM_MEMORY'
  TABLES  listobject = lt_list
  EXCEPTIONS not_found = 1 OTHERS = 2.
```

Two constraints that turn this into an empty table if ignored, from
[`SUBMIT, list_options`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapsubmit_list_options.htm):

> The additions only work the first time the called program is executed. If a
> selection screen is displayed in the called program, the runtime framework calls
> the program again after it ends and ignores the additions `list_options`.

Hence: never combine `list_options` with `VIA SELECTION-SCREEN` (the same caveat
applies to `TO SAP-SPOOL`, where the list then comes out on screen instead of in a
spool request). And the addition only works *if the Enter key is not bound to a
function code in the called program's last GUI status* — a condition your code cannot
check. `LIST_FROM_MEMORY` returning `not_found` is the symptom.

The counterpart FMs from function group `SLST` are `WRITE_LIST` (insert into the
current list), `DISPLAY_LIST` (own dynpro) and `LIST_TO_ASCI` (flatten to text).

---

## 6. `SET`/`GET PARAMETER` do not touch the user memory directly

SPA/GPA parameters look like global variables shared across the user's sessions. They
are not:

> The statement `SET PARAMETER` does not access the user memory directly. Instead, it
> accesses a local mapping of the SPA/GPA parameter in the session memory, which is
> loaded during rollup and saved in the user memory when rolled out. […] they are only
> suitable for passing data within an ABAP session and not for passing data between
> parallel ABAP sessions because programs that run in parallel can affect the state of
> the parameters in an uncontrolled manner.

— [`SET PARAMETER`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapset_parameter.htm)

Two open sessions of the same user will overwrite each other's values in an order
nobody defines. Use them for their intended job — pre-filling the next dynpro or
selection screen in the *same* session — and use ABAP Memory for program-to-program
data in a call sequence.

The rest of the contract, worth having in one place:

| | |
|---|---|
| ID | flat character-like, **max 20 chars**, **case-sensitive**, must exist in table `TPARA` |
| Not set yet | `GET PARAMETER` → `sy-subrc = 4` **and the target field is initialized** |
| Value too long | `SET_PARAMETER_VALUE_TOO_LONG` (>255 chars) — uncatchable |
| Blank / too long ID | `SET_PARAMETER_ID_SPACE`, `SET_PARAMETER_ID_TOO_LONG` |
| Memory exhausted | `SET_PARAMETER_MEMORY_OVERFLOW` |
| Inline declaration | `GET PARAMETER ID 'CAR' FIELD DATA(lv_car).` declares type `XUVALUE` |

Because the target is initialized on `sy-subrc = 4`, the unchecked `GET PARAMETER`
gives you a blank rather than stale data — the opposite of the `IMPORT` trap above,
and the reason the two statements need opposite habits. Note also that these are
**binary** transfers (`SET`: "whose binary content is passed unconverted"), so they
are for flat character-like fields only.

---

## 7. Dynamic program names are an injection point

`SUBMIT (lv_name)` is checked against authorization object `S_PROGRAM` for the
program's authorization group — which is not the same as "this name is safe". The doc
carries an explicit security hint: any name that reaches the program from outside must
be validated first, e.g. via `CL_ABAP_DYN_PRG`. The `Start Using Variant` program
property is ignored by `SUBMIT`, so relying on it as a guard does nothing. Same family
of problem as the dynamic file names in [File Interface](../File%20Interface#readme)
and the dynamic type names in [Runtime Type Services](../Runtime%20Type%20Services#readme).

---

## Quick reference

| Situation | Do this |
|---|---|
| Any `SUBMIT` after `IN UPDATE TASK` registrations | explicit `COMMIT WORK` / `ROLLBACK WORK` first |
| `SUBMIT` between `FETCH`es | don't — the child's commit closes your cursor |
| Passing values to a selection screen | internal format, uppercase `SELNAME`, `KIND = 'P'`/`'S'` |
| Values longer than 45 chars | `RSPARAMSL_255` instead of `RSPARAMS` |
| Reading a cluster back | `CLEAR` the targets first — missing parameters keep old values |
| Cleaning up ABAP Memory | `DELETE FROM MEMORY ID ...`, never bare `FREE MEMORY` |
| Grabbing the called report's list | `EXPORTING LIST TO MEMORY AND RETURN`, no `VIA SELECTION-SCREEN` |
| Data across parallel sessions | not SPA/GPA — use the database or shared objects |
| Program name from outside | validate with `CL_ABAP_DYN_PRG` |

## Sources

- [`SUBMIT`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapsubmit.htm) — `AND RETURN`, LUW rules, nine-session limit, runtime errors, security hint
- [`SUBMIT, selscreen_parameters`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapsubmit_selscreen_parameters.htm) — `RSPARAMS`/`RSPARAMSL_255`, internal format, `SIGN`/`OPTION`
- [`SUBMIT, list_options`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapsubmit_list_options.htm) — `EXPORTING LIST TO MEMORY`, `TO SAP-SPOOL`
- [`EXPORT, medium`](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapexport_data_cluster_medium.htm) — `MEMORY ID`, 60-char case-sensitive ID, shared buffers
- [`IMPORT`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapimport_data_cluster.htm) — `sy-subrc` table
- [`IMPORT, parameter_list`](https://help.sap.com/doc/abapdocu_750_index_htm/7.50/en-US/abapimport_parameterlist.htm) — ignored parameters, type tolerances
- [`IMPORT, medium`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPIMPORT_MEDIUM.html) — media, obsolete short forms
- [`FREE MEMORY`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPFREE_MEMORY.html) — deletes all clusters without `ID`
- [`SET PARAMETER`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapset_parameter.htm) / [`GET PARAMETER`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapget_parameter.htm) — session mapping, `sy-subrc`, runtime errors

Runnable demo: [`ydj_submit_memory_demo.abap`](ydj_submit_memory_demo.abap)
