# IDoc & ALE programming — the IDoc that was never created and raised nothing, the `COMMIT WORK` you must write and the one you must not, and the blank date that is not initial

An IDoc is three record types and a 1000-character string. **Control record**
(`EDIDC`) says who, what and where; **data records** (`EDIDD` in memory, `EDID4`
on the database) carry the payload as a flat character field; **status records**
(`EDIDS`) are the processing log. Everything else — partner profiles, ports,
the distribution model, the ALE layer — is configuration that decides what
happens to those records, mostly *after* your program has already returned
`sy-subrc = 0`.

That is the theme of this note. IDoc programming is not hard; it is quiet.
The outbound call that creates nothing raises nothing, the status that says
"ready for dispatch" means "nothing was dispatched", and the one `COMMIT WORK`
the framework needs from you is the one nobody writes — while the one you
instinctively add inbound is the one the framework forbids.

> "The data records of an IDoc are created in an internal table with structure EDIDD."

The doc's own field table describes `sdata` as a "1000 byte-long character
field for the data used by the IDoc", and adds how it gets filled:

> "For each segment type of the IDoc structure, there is a DDIC structure with the same name. A field string with this structure is used for creating a data record. The application data is mapped to the field string. The segment type is written to the field SEGNAM, and the field string is written to the field SDATA."

Two consequences follow from that last quote alone, and both cause production
incidents:

1. **`SDATA` is positional.** The mapping between a segment structure and the
   1000 characters is "assign the field string". Nothing in the payload names a
   field. Insert a field in the middle of a segment and every downstream byte
   shifts.
2. **Every segment field is character-like.** There are no dates, no packed
   numbers and no booleans in an IDoc — only characters that *look* like them.

---

## Trap 1: `MASTER_IDOC_DISTRIBUTE` can create nothing, raise nothing, and report success

The canonical outbound pattern is: build the control record, build the data
records, call `MASTER_IDOC_DISTRIBUTE`, handle its exceptions. That last step
looks like diligent error handling. It does not cover the most common failure.

> "If a receiver was not passed in the control record and ALE does not find a receiver in the distribution model, an exception is not issued. If you want to react in this situation, you must query the return table COMMUNICATION_IDOC_CONTROL. If this table is empty, no IDoc was created."

So the distribution model (BD64) not being maintained — the single most common
"my IDoc did not go out" cause — is not an error. No exception, no message, no
status record, no IDoc. The function module returns, the program writes its
success log, and the interface is silently dead.

The behaviour is *asymmetric*, and the doc says why:

> "This different behavior for the initial and non-initial receiver has historical reasons. The initial receiver is the standard case for master data replication, although it is of no further interest whether an IDoc was actually created. Presetting the receiver is the standard for dispatching transaction data: if an IDoc is not created, this is interpreted as an error."

| You passed | Model allows it | Result |
|---|---|---|
| no receiver | — | **no exception**, `COMMUNICATION_IDOC_CONTROL` empty, no IDoc |
| a receiver | yes | IDoc(s) created, control records in the return table |
| a receiver | no | exception `ERROR_IN_IDOC_CONTROL` with a message |

The documented exceptions, for completeness:

| Exception | Occurrence |
|---|---|
| `error_in_idoc_control` | Incorrect or no message type specified. Incorrect or no IDoc type specified. No IDoc created, although receiver was preset by application. |
| `error_in_idoc_data` | No data records passed. |
| `error_writing_idoc_status` | Technical problems when writing status records. |
| `sending_logical_system_unknown` | Own logical system could not be determined. |

**Rule:** treat an empty `COMMUNICATION_IDOC_CONTROL` as a result, not as a
non-event. One `IF ... IS INITIAL` is the whole fix, and the doc's own hedge
("it is of no further interest whether an IDoc was actually created") is true
for master-data replication and false for every interface anyone monitors.

## Trap 2: outbound needs a `COMMIT WORK` that the end of the transaction does not provide

> "After MASTER_IDOC_DISTRIBUTE is called, a COMMIT WORK must be executed - the standard database commit at the end of the transaction is not sufficient. The COMMIT WORK does not have to directly follow the call; it can be specified at higher call levels or after multiple calls of MASTER_IDOC_DISTRIBUTE."

This is unusual enough to be worth stating plainly: the implicit database commit
at the end of a dialog step — the one that silently commits everything else in
ABAP — does **not** finish an IDoc. Without an explicit `COMMIT WORK` the
records are written and never leave. The usual explanation is that dispatch is
registered as `ON COMMIT`/update work and so needs a real SAP LUW end rather
than a bare database commit; that mechanism is an inference, the requirement
itself is stated outright.

Two riders on the same page, both easy to miss:

> "Note that the IDocs created remain locked until the called transaction has been completed. If you want to unlock them earlier, you can call one of the following function modules:"
>
> - `DEQUEUE_ALL` — "releases all locked objects"
> - `EDI_DOCUMENT_DEQUEUE_LATER` — "releases IDocs passed as parameters"

> "If the application document is created via the update program, the call to MASTER_IDOC_DISTRIBUTE must also be performed in the update task (if an update call has not already been performed at a higher level)."

That second one is the consistency rule. If the business document is written in
V1 update and the IDoc is distributed in the dialog part, a failed update leaves
an IDoc announcing a document that does not exist. The IDoc call has to travel
in the same update as the data it describes. See
[Update Task](../Update%20Task#readme) for what "in the update task" costs you
(no return channel, no `sy-subrc`), and
[Commit Work Events](../Commit%20Work%20Events#readme) for the LUW mechanics.

## Trap 3: inbound, the `COMMIT WORK` you must *not* write

Everything above inverts on the inbound side. An inbound function module is
called *by* the ALE layer, inside the ALE layer's LUW, and the framework decides
the transaction outcome after you return.

> "The function module should *not* commit the data to the database (using a commit work)."

> "If possible, do not update the database using `Call Function xxx` In Update Task – this is not required for ALE inbound processing, and only increases database load."

The reason, spelled out in SAP's application documentation for a warehousing
IDoc framework built on the same mechanism (the rule is general, the page is
EWM/SNC-specific):

> "If you create your own function module or BAdIs, make sure that you do not set any COMMIT WORK statements, as these can cause errors during IDoc processing and inconsistencies during error processing. The system returns to the ALE layer following processing, where the system updates any application errors that have occured, sets the IDoc status, and may even execute database rollbacks."

Read the failure mode carefully, because it is the worst shape a bug can have.
Your `COMMIT WORK` commits the application document. Control returns to ALE.
ALE sees the error status you reported, rolls back — and finds nothing to roll
back, because you already committed. The IDoc ends in status **51, application
document not posted**. The document exists. The IDoc says it does not. Someone
reprocesses the IDoc, and now there are two.

The contract instead is: write the data, report the outcome in `IDOC_STATUS`,
return. The status record is how you communicate, not the database.

## Trap 4: the blank date that is not initial

Because `SDATA` is character, a date in an IDoc is eight characters, and an
*empty* date is eight blanks. Moving that into a `d` field does not give you an
initial date.

> "Fields containing dates and times can lead to errors during inbound processing if the field in the IDoc is empty that is, blank: In ABAP, if a blank character field is copied to a date field, the date field remains blank and is not initial (does not contain zeros). This means the date field contains an invalid value. Errors occur in subsequent processing as soon as the field is checked for an initial value, if DateField is initial.... To avoid this, clear the date field if the IDoc field is empty, as shown in the example code."

So `IF lv_date IS INITIAL` is **false** for a date field full of blanks, and
every downstream default-value branch keyed on `IS INITIAL` is skipped. The
value then fails much later, in an application check or a database write, with
an error that points nowhere near the IDoc.

The guard is one line per date field — `IF seg-field IS INITIAL. CLEAR
target-date. ELSE. target-date = seg-field. ENDIF.` — and the demo proves the
difference. Same family of problem as the deliberate conversions the doc also
flags on the same page, which are worth reproducing because they are the fields
that actually differ between systems:

> "Special attention must be paid to fields containing:"
>
> - "Units of measure (ISO code in IDoc)"
> - "Currency codes (ISO code in IDoc)"
> - "Country codes (ISO code in IDoc)"
> - "Shipping instructions (ISO code in IDoc)"
> - "Monetary amounts (conversion factor needed)"
> - "Dates and times"

Units and currencies travel as **ISO codes**, not SAP codes — `ISO_TO_SAP_MEASURE_UNIT_CODE`
and friends exist for exactly that. And "monetary amounts (conversion factor
needed)" is the [Currency Amounts](../Currency%20Amounts#readme) problem arriving
over an interface: the number in the segment is not necessarily scaled the way
your `CURR` field is.

## Trap 5: your inbound function module is called more than once, and your globals survive

Inbound segment structures are conventionally declared as *global* data of the
function group. That convention collides with how ALE calls you.

> "Initialize/update all global variables or tables. The inbound function module can be called up more than once by a process. The global variables are therefore filled with values the second time."

In mass inbound processing — the interface even hands you a `MASS_PROCESSING`
flag — IDoc number two is processed by the same function group instance that
just processed number one. Any field the second IDoc does not
supply still holds the first IDoc's value. This is the
[JSON `clear = none`](../JSON%20Serialization#readme) bleed in a different
costume: order two is created for order one's customer, no error anywhere, and
it only ever reproduces when two IDocs arrive in the same run — never in a
single-IDoc WE19 test.

While in the neighbourhood, the first two steps of the same documented procedure
are worth copying verbatim into any new inbound module:

> "Check that the IDoc contains the correct message type (field Idoc_Contrl-Mestyp). If it does not, raise the exception Wrong_Function_Called with an appropriate message."

> "When implementing an inbound function module for master data that can be 'reduced' by customers, do not check the message type; check the basic IDoc type instead (field Idoc_Contrl-Idoctp)."

That second rule is non-obvious: a reduced message type has a *different*
message type name, so a `MESTYP` check rejects traffic the module is supposed to
handle. Check `IDOCTP` for master data.

## Trap 6: status 30 means nothing was sent, and status 03 does not mean it arrived

Outbound processing has a configurable stop built into it.

> "Outbound processing must stop when the outbound IDocs have been generated to allow the test program to intervene. You can achieve this by setting the output mode to 'Collect IDocs' in the partner profile for the IDoc interface."

> "The status of IDOC is set to 30, status text 'IDOC is ready for dispatching (ALE service)'. Internally, the constant ALE_READY_FOR_DISPATCHING represents this status."

> "Use program RSEOUT00 to start processing all selected intermediate documents."

And this is not a test-only arrangement:

> "The program is report `RSEOUT00`, which is also generally scheduled with the output mode 'Collect IDocs' in live operation."

So "Collect IDocs" in WE20 is a perfectly valid production setting (it is how
you batch dispatch), and with it every IDoc your code creates stops at **30**
until `RSEOUT00` runs. If that job is not scheduled, nothing is broken,
nothing is in error, and nothing is being sent. A monitor that alerts on error
statuses will never fire — status 30 is a success status.

Status **03, data passed to port OK**, is the next cliff: it records that the
IDoc was handed to the port, not that the partner received it. For a tRFC port
the transmission is an asynchronous RFC unit; a failed one sits in `SM58`, not
in the IDoc's status. (The follow-up status **12, dispatch OK**, is written by
the separate report `RBDMOIND`, which confirms the tRFC actually went through —
this detail is from SAP Community rather than product documentation, so verify
it against your own release before relying on it.)

| Status | Says | Actually means |
|---|---|---|
| 30 | IDoc ready for dispatch (ALE service) | nothing has been sent; waiting for `RSEOUT00` |
| 03 | Data passed to port OK | handed to the port; delivery unconfirmed |
| 12 | Dispatch OK | tRFC confirmed (written later, by `RBDMOIND`) |
| 51 | Application document not posted | inbound application error; repost with `RBDMANI2` |
| 53 | Application document posted | the only inbound success |
| 63 | Error passing IDoc to application | never reached your function module |

> "If the processing of the inbound IDoc resulted in an error (IDoc status 51 - 'Application document not posted', or 63 - 'Error passing IDoc to application'), you can use the report RBDMANI2 to resubmit the IDoc. In this program you can select specific errors. The program can also be scheduled as a periodic job to collect IDocs that could not be posted because of a lock problem."

That last sentence is the pragmatic one: lock collisions are a normal,
self-healing inbound failure, and a scheduled `RBDMANI2` is the intended fix —
not a code change.

## Trap 7: fixing the partner profile does not fix the resend

When a communication error is handled through exception handling and you resend
the IDoc from the work item:

> "The partner profiles, however, are not read again: All data required for transmission is read from the control record. If, for example, you have exchanged the port in the partner profiles, the IDoc is still sent to the original port."

This is the loop everyone has been in: the port was wrong, you corrected it in
WE20, you resend, it fails identically, you conclude the correction did not
save. The correction is fine — the existing IDoc's control record is frozen.
Old IDocs keep going to the old destination; only newly created ones read the
new profile.

## A field containing `/` means "do not change this"

One more silent data rule, for reduced message types:

> "For reduced message types field values are not overwritten in the receiving SAP system, if the corresponding IDoc field contains the character '/'."

A single slash is a sentinel for "leave the existing value alone". Which means
a mapping that legitimately needs to send `/` as data cannot, and a mapping
that accidentally emits `/` silently suppresses an update rather than writing a
slash.

## Reference: the inbound function module interface

ALE calls your module through a fixed interface. The documented example
(`IDOC_INPUT_TESTER`) defines it as:

| Formal parameter | Reference structure | Meaning |
|---|---|---|
| `INPUT_METHOD` (imp.) | `BDWFAP_PAR-INPUTMETHD` | how the module is to be processed (e.g. in the background) |
| `MASS_PROCESSING` (imp.) | `BDWFAP_PAR-MASS_PROC` | mass inbound processing indicator |
| `WORKFLOW_RESULT` (exp.) | `BDWFAP_PAR-RESULT` | "Set to 99999 if an event is to be triggered for error handling" |
| `APPLICATION_VARIABLE` (exp.) | `BDWFAP_PAR-APPL_VAR` | free variable for the workflow |
| `IN_UPDATE_TASK` (exp.) | `BDWFAP_PAR-UPDATETASK` | you did an asynchronous update |
| `CALL_TRANSACTION_DONE` (exp.) | `BDWFAP_PAR-CALLTRANS` | you used `CALL TRANSACTION` |
| `IDOC_CONTRL` (tab.) | `EDIDC` | control record |
| `IDOC_DATA` (tab.) | `EDIDD` | data records |
| `IDOC_STATUS` (tab.) | `BDIDOCSTAT` | status records you return to ALE |
| `RETURN_VARIABLES` (tab.) | `BDWFRETVAR` | IDoc/application-object keys for the workflow |
| `SERIALIZATION_INFO` (tab.) | `BDI_SER` | sequencing information |

Registration is configuration, not code: WE57 assigns the module to basic type +
message type with direction `2` (inbound), and the process code (`TBD52-FUNCNAME`)
points at it. Direct inbound processing "always includes the ALE layer", flagged
by value `6` in `TEDE2-EDIVRS`, which `IDOC_START_INBOUND` reads before calling
ALE.

Note that the status values the documented example uses are hard-coded
constants against `TEDS1-STATUS`:

```abap
DATA: BELEG_NICHT_GEBUCHT LIKE TEDS1-STATUS VALUE '51'.
DATA: BELEG_GEBUCHT       LIKE TEDS1-STATUS VALUE '53'.
```

and `WORKFLOW_RESULT` has exactly two documented values in that example —
`'0'` for OK and `'99999'` to trigger error handling.

---

## Checklist

**Outbound**
- After `MASTER_IDOC_DISTRIBUTE`, check `COMMUNICATION_IDOC_CONTROL` — empty means no IDoc, and no exception was raised.
- Write the `COMMIT WORK` yourself; the implicit end-of-transaction commit is explicitly not enough.
- Document written in the update task? Distribute in the update task too.
- Need the IDocs unlocked before the transaction ends? `EDI_DOCUMENT_DEQUEUE_LATER`.
- Status 30 across the board is a scheduling question (`RSEOUT00`), not a code bug.
- Fixed a partner profile? Existing IDocs still carry the old routing in their control record.

**Inbound**
- No `COMMIT WORK`. Avoid `IN UPDATE TASK` ("not required for ALE inbound processing"). Report the outcome in `IDOC_STATUS` and return.
- Initialize every global variable and table at entry — you will be called again in the same run.
- Check `MESTYP` (or `IDOCTP` for reducible master data) and raise `WRONG_FUNCTION_CALLED` otherwise.
- `CLEAR` a date/time target when the IDoc field is blank; blanks are not initial.
- Convert ISO units/currencies/countries; do not assume SAP codes.
- Only set 53 when the application document really exists.

**Always**
- Extend a segment by appending fields, never by inserting — `SDATA` is positional.
- 1000 characters is the hard ceiling for a segment; plan for a second segment type instead of widening forever.

## Sources

- [Call of MASTER_IDOC_DISTRIBUTE — IDoc Interface/ALE](https://help.sap.com/docs/ABAP_PLATFORM_2021/8f3819b0c24149b5959ab31070b64058/4a49eb50e97a2baee10000000a421937.html)
- [Exceptions and Export Parameters of MASTER_IDOC_DISTRIBUTE — IDoc Interface/ALE](https://help.sap.com/docs/ABAP_PLATFORM_NEW/8f3819b0c24149b5959ab31070b64058/4a686add1fef51b4e10000000a42189c.html)
- [IDoc Processing (inbound function module procedure) — SAP Help](https://help.sap.com/doc/saphelp_scm700_ehp02/7.0.2/en-US/4a/6d76aa5e9070e0e10000000a42189b/content.htm)
- [Structure of the Data Records — ALE Programming Guide](https://help.sap.com/saphelp_scm700_ehp01/helpdata/en/78/2177fd51ce11d189570000e829fbbd/content.htm)
- [Creating a Function Module (Direct Inbound Processing) — IDoc Interface/ALE](https://help.sap.com/saphelp_em700_ehp01/helpdata/en/dc/6b7df143d711d1893e0000e8323c4f/content.htm)
- [Modification Concepts: IDoc Inbound Processing (no COMMIT WORK in own modules/BAdIs)](https://help.sap.com/doc/saphelp_snc70/7.0/en-US/32/2c73412c315458e10000000a1550b0/content.htm)
- [Output Stream (Output Mode IDOC) — status 30 and RSEOUT00](https://help.sap.com/saphelp_gbt10/helpdata/EN/4e/080dcd8117001ce10000000a42189c/content.htm)
- [Test: Outbound Processing from IDoc (Collect IDocs)](https://help.sap.com/saphelp_em92/helpdata/en/4b/70de0ae19141a9e10000000a421937/content.htm)
- [Status Processing (resend reads the control record, not the partner profile)](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/4b/6a8db3aa022b5fe10000000a42189c/content.htm)
- [Error handling (RBDMANI2 for status 51 / 63)](https://help.sap.com/saphelp_aii710/helpdata/en/0b/2a6743507d11d18ee90000e8366fc2/content.htm)
- [Distribution Using Message Types (the `/` sentinel for reduced message types)](https://help.sap.com/doc/saphelp_nw73ehp1/7.31.19/en-US/4a/a718a9782c5ff4e10000000a421937/content.htm)
