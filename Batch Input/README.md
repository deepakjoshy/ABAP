# Batch Input — `sy-subrc = 0` Does Not Mean the Data Was Saved

`CALL TRANSACTION ... USING` is still how a large amount of SAP data gets loaded:
no BAPI exists, or the BAPI does not cover the field, so a program drives the
dialog transaction screen by screen through a `BDCDATA` table. Every tutorial
ends the same way:

```abap
CALL TRANSACTION 'XK01' USING lt_bdcdata MODE 'N' MESSAGES INTO lt_messages.
IF sy-subrc <> 0.
  " error handling
ENDIF.
```

That check is not wrong, but it is far weaker than it looks. With the **default**
settings it can return `0` for a record that was never written to the database,
and the traps below are all documented — none of them produce a syntax error or a
dump at the point where the mistake was made.

Related notes: [Update Task](../Update%20Task#readme) for V1/V2 and
`SET UPDATE TASK LOCAL`, [Authorization Checks](../Authorization%20Checks#readme)
for `WITH AUTHORITY-CHECK` and `TCDCOUPLES`, and
[Messages](../Messages#readme) for `sy-msgid`/`sy-msgno` handling.

Runnable demo: [ydj_batch_input_demo.abap](ydj_batch_input_demo.abap) — builds and
inspects the `BDCDATA` table and the return-code classification. The actual
`CALL TRANSACTION` is **commented out**, so the report changes no data.

## Trap 1: the default update mode is asynchronous, so success is unverifiable

This is the headline. If you write neither `UPDATE` nor `OPTIONS FROM`, the
documentation states the effect is the same as `upd = 'A'`:

> | `upd` | Effect |
> | --- | --- |
> | `A` | Asynchronous update. Updates of the called programs are executed in the same way as if the addition `AND WAIT` were **not** specified in the statement `COMMIT WORK`. |
> | `S` | Synchronous update. ... as if the addition `AND WAIT` **were** specified. |
> | `L` | Local updates. ... as if the statement `SET UPDATE TASK LOCAL` had been executed in it. |
> | Others | As for `A`. |
>
> "If neither of the additions `UPDATE` or `OPTIONS FROM` are used, the effect is
> the same as if `upd` had the content `A`."
> — [`CALL TRANSACTION, USING`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapcall_transaction_using.htm)

Asynchronous means the dialog part hands the update off to the update service and
returns immediately. The dialog succeeded; the database write has not happened
yet and may still fail. SAP's own data-transfer guide is blunt about the
consequence:

> "Asynchronous processing is **NOT** recommended for processing any larger amount
> of data. This is because the called transaction receives no completion message
> from the update module in asynchronous updating. The calling data transfer
> program, in turn, **cannot determine whether a called transaction ended with a
> successful update of the database or not**. If you use asynchronous updating,
> then you will need to use the update management facility (Transaction `SM13`)
> to check whether updates have been terminated abnormally."
> — [Using CALL TRANSACTION USING for Data Transfer](https://help.sap.com/saphelp_snc70/helpdata/EN/4d/904f4b810314aee10000000a42189c/content.htm)

So the load program prints "5000 of 5000 records OK", and the truth is in `SM13`
where nobody looked. Worse, the failure is *per record*: the update task dies on
record 3172 for a reason the loader never sees, so the run is partially applied
with no error list to drive a rerun.

Fix: pass `UPDATE 'S'` (or `UPMODE = 'S'`) on every data-load `CALL TRANSACTION`.
It is slower — the caller waits for the V1 update — and that is exactly the point:
only then does an update failure come back in `sy-subrc` and the message table.
Use `'A'` only when you genuinely do not care whether the record landed.

Note the field name asymmetry that makes this easy to get wrong when switching to
the structure form: the `MODE`/`UPDATE` additions map to `DISMODE`/`UPMODE` in
`CTU_PARAMS`, not to fields called `MODE`/`UPDATE`.

## Trap 2: there are three `sy-subrc` ranges, and `1001` is not "error in the data"

> | `sy-subrc` | Meaning |
> | --- | --- |
> | `0` | The called transaction was processed successfully. |
> | `< 1000` | Error in the called transaction. If a message was sent within the transaction, it can be received using the addition `MESSAGES`. |
> | `1001` | Processing error. |
>
> — [`CALL TRANSACTION, USING`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapcall_transaction_using.htm)

The older data-transfer guide phrases the same split as `<= 1000` = "error in
dialog program" and `> 1000` = "batch input error", and adds that "return codes
above 1000 are reserved for data transfer".

These two ranges need different handling and usually different people:

- **`< 1000`** is a *business* failure. The transaction ran, rejected the record
  and issued a message ("Vendor already exists", "Cost centre not valid on this
  date"). The message table tells you what to fix in the source data.
- **`1001`** is a *technical* failure — the BDC driver could not process the
  screen sequence at all. Usually the screen flow changed (a new warning popup, a
  different default view, an extra confirmation dynpro), so the `BDCDATA` table no
  longer matches the transaction. No amount of data cleansing fixes it; the
  recording has to be redone.

Collapsing both into one `IF sy-subrc <> 0` error bucket is how a loader ends up
reporting 5000 "data errors" after an upgrade, when actually the screen sequence
moved and not one record was ever attempted.

### The `1001` that is a forgotten breakpoint

`MODE 'N'` has a documented trap worth knowing before you spend an afternoon on it:

> | `N` | Processing without display of the screens. If a breakpoint is reached in one of the called transactions, processing is terminated with `sy-subrc` equal to `1001`. Then, the field `sy-msgty` contains `S`, `sy-msgid` contains `00`, `sy-msgno` contains `344`, `sy-msgv1` contains `SAPMSSY3`, and `sy-msgv2` contains `0131`. |
>
> — [`CALL TRANSACTION, USING`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapcall_transaction_using.htm)

A session breakpoint left in the *called* standard transaction — not in your
loader — terminates every record with `1001` and a message that mentions
`SAPMSSY3`/`0131` and nothing about breakpoints. Recognising that exact message
combination is the whole diagnosis. (`MODE 'P'` is the sibling: same "no screens",
but a breakpoint branches into the debugger instead of terminating.)

The other `MODE` values: `A` displays all screens, `E` displays only when an error
occurs, and — importantly — **`A` is the default**, so a `CALL TRANSACTION USING`
written without `MODE` is in "display every screen" mode. Anything unattended
needs an explicit `'N'`.

## Trap 3: `COMMIT WORK` inside the transaction ends the processing early

`CTU_PARAMS` has a flag most developers never touch:

> | `RACOMMIT` | Flag to indicate whether the statement `COMMIT WORK` terminates processing or not. Values: blank (`COMMIT WORK` **terminates** processing), `X` (`COMMIT WORK` does not terminate processing). |
>
> — [`CALL TRANSACTION, USING`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapcall_transaction_using.htm)

Default is blank. So if the called transaction issues a `COMMIT WORK` partway
through its own flow — common in transactions that create a document and then
continue into a follow-on screen — batch input processing **stops there**. Any
remaining dynpros in your `BDCDATA` table are silently never processed. The first
half of the work is committed, the second half never happened, and this does not
necessarily present as a non-zero `sy-subrc`.

Set `RACOMMIT = 'X'` only when you have understood why the transaction commits
mid-flow; the flag is available through `OPTIONS FROM` and has no equivalent in
the short `MODE`/`UPDATE` form.

## Trap 4: no new database LUW — the called transaction can roll back *your* work

> "`CALL TRANSACTION` does **not** end the current database LUW. ... The statement
> `CALL TRANSACTION` opens a new SAP LUW, but it does **not** open a new database
> LUW. This means that a database rollback in this SAP LUW, in particular, can
> roll back all registration entries made by the statements `CALL FUNCTION IN
> UPDATE TASK` or `CALL FUNCTION IN BACKGROUND TASK` in the tables `VB...` or
> `ARFCSSTATE` and `ARFCSDATA`. The statement `ROLLBACK WORK` in the called
> program may also affect the interrupted SAP LUW under certain circumstances. To
> prevent this, an explicit database commit must be executed before the program is
> called. This problem does not occur during local updates."
> — [`CALL TRANSACTION`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapcall_transaction.htm)

Read that against a typical loader: it registers some of its own work with
`CALL FUNCTION ... IN UPDATE TASK`, then calls a transaction which hits an error
and rolls back. Your registrations are gone too — deleted by a rollback you did
not issue, in a program you did not write. Nothing reports this.

The documented fix is the one sentence in the middle: do an explicit
`COMMIT WORK` before the `CALL TRANSACTION`, so there is nothing of yours
registered in the current database LUW to lose.

## Trap 5: `MESSAGES INTO` collects *all* messages, not just errors

> "Using this addition, all the messages sent during batch input processing are
> stored in an internal table `itab` of the line type `BDCMSGCOLL`."
> — [`CALL TRANSACTION, USING`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapcall_transaction_using.htm)

*All* messages — including the success message that says the document was created.
So `IF lt_messages IS NOT INITIAL` is not an error test; a perfectly successful
record fills that table. Filter on `msgtyp` (`E` and `A`, plus `W` if warnings
matter to you), and use the last `E`/`A` row as the reportable reason.

Two practical points on `BDCMSGCOLL`: it carries `msgid`/`msgnr`/`msgv1..4`, not
formatted text — run it through `MESSAGE ... INTO` or function module
`FORMAT_MESSAGE` for something a user can read. And the table is **not** cleared
by the statement, so in a loop over records it must be cleared per record or the
messages from record 1 are reported again against record 2.

## Trap 6: there is no restart, and no nesting

Two hard limits worth knowing before designing around this statement.

**No restart capability.** Unlike session-based batch input (`BDC_OPEN_GROUP` /
`SM35`), which keeps faulty transactions for later correction:

> "Unlike batch input methods using sessions, `CALL TRANSACTION USING` processing
> does not provide any special handling for incorrect transactions. There is
> **no restart capability** for transactions that contain errors or produce update
> failures."
> — [Using CALL TRANSACTION USING for Data Transfer](https://help.sap.com/saphelp_snc70/helpdata/EN/4d/904f4b810314aee10000000a42189c/content.htm)

SAP's own recommended pattern is the hybrid: run with `UPDATE 'S'`, and for every
record where `sy-subrc <> 0`, write the same `BDCDATA` table into a batch input
session so a human can correct and reprocess it in `SM35`. That gives you the
speed of `CALL TRANSACTION` with the error handling of sessions.

**No nesting.** While a batch input call is running, `sy-binpt` is `'X'` in the
called program and:

> "no other transaction can be called using this addition while this transaction
> is running."

Violating that is the uncatchable `CALL_TRANSACTION_USING_NESTED`. This bites when
the transaction you drive itself contains custom code (a user exit, a BAdI) that
does its own `CALL TRANSACTION ... USING`. It works when a user runs the
transaction by hand and dumps only under the loader.

`sy-binpt` is also the flag that well-behaved code checks to suppress dialogs and
popups during batch input, and `CTU_PARAMS` can lie about it deliberately:
`NOBINPT = 'X'` makes `sy-binpt` blank in the called transaction, and
`NOBIEND = 'X'` makes it blank once the `BDCDATA` data runs out. That second one
is the documented way to hand control back to a user after driving the first few
screens — and, if set by accident, the reason custom code suddenly starts opening
popups mid-load.

## Reference: building the `BDCDATA` table

The structure and the order are documented exactly:

> - For each new dynpro, a new line with a program name in `PROGRAM`, a dynpro
>   number in `DYNPRO`, and a flag `X` in `DYNBEGIN`
> - For each input field to be filled, a line with the name of the dynpro field in
>   `FNAM` and the value in `FVAL`
> - If the cursor is to be positioned, the value `BDC_CURSOR` in `FNAM` and the
>   name of the screen element in `FVAL`
> - For each dynpro, the function code: `BDC_OKCODE` in `FNAM` and a function code
>   in `FVAL`
>
> "Any columns in a line that are not listed remain initial."
> — [`CALL TRANSACTION, Batch Input Table`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abenbatch_input_table.htm)

| Component | Meaning |
| --- | --- |
| `PROGRAM` | Name of the program of the called transaction |
| `DYNPRO` | Number of the dynpro to be processed |
| `DYNBEGIN` | Flag for the start of a new dynpro (`X` or blank) |
| `FNAM` | Name of a dynpro field, or a batch input control statement |
| `FVAL` | Value passed to the dynpro field or to the control statement |

Three details that are easy to miss:

- **Table control and step loop fields need the row number appended to the field
  name** — `MSICHTAUSW-KZSEL(01)`, not `MSICHTAUSW-KZSEL`. The same applies to
  `BDC_CURSOR` when positioning inside a table control. This is also the reason
  table-control loads are fragile: the visible row count depends on window size,
  so a recording made on one screen resolution can address rows that are not on
  screen elsewhere.
- **Subscreen fields belong to the including dynpro**, which "can produce multiple
  fields with the same name, which are then all filled".
- **`FVAL` is a character field filled in the external format the dynpro expects.**
  Dates and amounts therefore follow the *executing user's* settings — a date
  built as `31.12.2026` works for a user with `DD.MM.YYYY` and fails for
  `MM/DD/YYYY`. Batch loaders should set a fixed, known user profile, or build the
  string from the user's own format rather than a hard-coded pattern.

Transaction `SHDB` (Transaction Recorder) records a transaction into exactly this
structure and can generate a program from it — the normal starting point, and it
produces the familiar `bdc_dynpro` / `bdc_field` helper subroutines.

## A note on when *not* to use this

`CALL TRANSACTION USING` drives a UI. That makes it the most fragile integration
technique in ABAP: a support package that adds one popup breaks every loader that
touches that transaction, and `1001` is the only warning you get. Prefer, in
order: a released BAPI or API, a RAP/OData service, direct input where SAP
provides it, and batch input last. It remains genuinely necessary — but it should
be a considered choice, not the first idea.

It is also worth knowing that `CALL TRANSACTION` in general is not available in
ABAP Cloud / clean-core development. New work targeting that model has to go the
API route.

## Sources

- [`CALL TRANSACTION`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapcall_transaction.htm) — the LUW hints, the nine-session limit, the exception list
- [`CALL TRANSACTION, USING`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapcall_transaction_using.htm) — `MODE`/`UPDATE` tables and defaults, the full `CTU_PARAMS` table, the `sy-subrc` table, `MESSAGES INTO`
- [`CALL TRANSACTION, Batch Input Table`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abenbatch_input_table.htm) — `BDCDATA` layout, `BDC_CURSOR`/`BDC_OKCODE`, table control row numbering, `SHDB`
- [Using CALL TRANSACTION USING for Data Transfer](https://help.sap.com/saphelp_snc70/helpdata/EN/4d/904f4b810314aee10000000a42189c/content.htm) — the asynchronous-update warning, the return-code ranges, the no-restart statement
