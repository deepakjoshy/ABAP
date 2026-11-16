# Change Documents (CDHDR / CDPOS) — the flag that lives on the data element, the framework that logs nothing unless you call it, and the `TABKEY` that is sometimes a GUID

Sooner or later someone asks who changed that field, and when. This repo's
[Application Log](../Application%20Log#readme) note ends by pointing at the
answer, in SAP's own words:

> "Data that, for reasons of revision security, have to be available for a long period of time, should not be stored with the application log but with the change documents."

— [Application Log – Guidelines for Developers](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21000f35d44180e10000000a15822b.html)

Change documents (component BC-SRV-ASF-CHD, transaction `SCDO`) are that
long-lived audit trail. They are also the SAP framework most often assumed to
be automatic. It is not. The single sentence that explains most empty `CDPOS`
selections is on the Concept page:

> "The document is created independently of the database changes."

— [Concept](https://help.sap.com/saphelp_ewm900/helpdata/en/48/dfd498ab14280de10000000a42189c/content.htm?no_cache=true)

Independently means *you* write both halves. Nothing watches your `UPDATE`.
This note is the list of ways a change document is silently not written, or is
written but cannot be read back correctly.

## The cast

| Object | Role |
|---|---|
| `SCDO` | maintain change document objects (**letter O**) |
| `SCD0` | function group that creates documents (**digit zero**) — see section 18 |
| `CDHDR` | change document header — one row per document |
| `CDPOS` | change document items — one row per changed field |
| `CDPOS_UID` | item supplement for a table key longer than 70 characters |
| `CDPOS_STR` | item supplement for `STRING` / `RAWSTRING` / `SHORTSTRING` fields |
| `RSSCD000` | the SAP program that generates the write module |
| `AFTER_IMP_CHDO` | the after-import method that regenerates it in the target system |

| Function group | Role |
|---|---|
| `SCD0` | **create** documents — `CHANGEDOCUMENT_OPEN` … `CHANGEDOCUMENT_CLOSE` |
| `SCD1` | **read** headers and items for one object |
| `SCD2` | read and format for an object class — `CHANGEDOCUMENT_READ`, `..._READ_RANGES` |
| `SCD3` | read **planned** changes — `PLANNED_CHANGES_READ_*` |
| `SCD4` | **delete** — `CHANGEDOCUMENT_DELETE`, `..._DELETE_V2` |
| `SCD8` | key/structure conversions — `CHANGEDOCU_KEY_CHAR2ANY` and friends (section 11) |

The whole write side is listed in
[Creating Change Documents](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa01d0493111d182b70000e829fbfe/content.htm),
the read side in
[Reading and Editing Change Documents](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa01dd493111d182b70000e829fbfe/content.htm).

---

## 1. Nothing is automatic — the framework never sees your database writes

The `SCD0` modules do not hook `UPDATE`. They compare an old image and a new
image **that you hand them**, and write the difference. The Concept page is
explicit about the trigger:

> "The change document is created when you specify the old and new status."

So a change document exists only where a developer wrote the call. Consequences
that surprise people in production:

- A row changed through `SM30`, `SE16N`, a direct `UPDATE` in a custom report,
  or a data-migration load produces **no** `CDPOS` row at all.
- Adding a table to an `SCDO` object and ticking the data-element flag changes
  nothing on its own — there is still no caller.
- The change document can be perfectly correct and the database wrong, or the
  reverse, because they are two separate writes (section 5 and section 6).

This is the difference from table logging, which *is* access-path independent:

> "The key advantage of Table Change Logging compared to the change document concept is that changes are recorded independent of how the tracked tables are accessed (for example, directly via transaction SM30 or via ABAP reports). The function modules for writing the change documents have to be implemented separately into every report that updates the corresponding business object."

— [Onapsis, *The Value of Table Change Logging For SAP Customizing Data*](https://onapsis.com/blog/value-table-change-logging-sap-customizing-data/)

**Takeaway.** *The field is flagged and the object exists* is not evidence that
a change will be logged. The evidence is a caller. Do a where-used on the
generated write module before promising an auditor anything.

---

## 2. The flag is on the data element, not on the table field

Which fields get logged is not configured in `SCDO` and not in the table. It is
a checkbox on the **data element**:

> "Now check whether the change document flag is set for the corresponding data element in the Dictionary for the fields whose changes are to be logged. This is necessary so that the object-specific function modules can identify which field of the defined object should be entered in the change document during logging."

— [Set change document flag](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa019c493111d182b70000e829fbfe/content.htm)

Two practical results:

- A field typed with a **built-in type** (`TYPE c LENGTH 20`) or with an
  unflagged data element is invisible to the framework. The write module runs,
  returns no error, and produces no item for that field. There is no warning
  anywhere.
- Two fields that look identical in `SE11` can behave differently, because what
  matters is one level deeper than the field.

### The side effect that reaches other applications

Setting the flag is not a local decision. This is the most important paragraph
on that page and it is easy to skim past:

> "If the flag is set by hand, it can have undesirable side-effects: If a table field in another application, which is based on the data element in question, belongs to a change document object, but was not previously logged, setting the flag will start logging in this application as well. It is therefore important to consider whether data elements are, or could be, change-relevant when creating them, and to set the flag accordingly. If the data element is not in any change document object via a table field, this has no negative effect on the system."

Flagging a widely reused SAP data element to fix logging in your Z object can
switch on logging in every standard object that uses it — extra `CDPOS` rows,
extra volume, in production. The doc's own advice is to decide this when the
data element is **created**, which is only available to you for your own
`Z`/`Y` elements. For a reused SAP element, prefer a dedicated data element on
your table over flagging theirs.

The flag also takes effect only after activation:

> "The flag becomes effective after the activation."

---

## 3. Change documents and table logging are two different mechanisms with similar names

They are routinely confused because both are "change logs" and both are reached
through audit transactions. They share nothing technically.

| | Change documents | Table logging |
|---|---|---|
| Stores into | `CDHDR` / `CDPOS` | `DBTABLOG` |
| Switched on by | change document flag on the **data element** + an `SCDO` object + **a caller** | `Log data changes` in technical settings (`SE13`) + profile parameter `rec/client` |
| Granularity | business object, field level | one table |
| Access-path independent | **no** — only logs what calls the module | **yes** — any insert/update/delete |
| Evaluated with | `SCDO`-object-specific displays, `CDHDR`/`CDPOS` | `SCU3` |
| Intended for | master and transaction data | customizing data |

An SAP Community answer states the independence plainly:

> "Table level logging and DE level logging both are separate things. If you flag 'change document' at DE, it will log the changes in CDHDR/CDPOS tables, whereas if you flag 'log data changes' at table level, the changes to that particular table will be visible in SCU3."

— [Log data changes – SCU3, S_AUT01, DBTABLOG](https://community.sap.com/t5/application-development-and-automation-discussions/log-data-changes-scu3-s-aut01-dbtablog/m-p/10923210)

The practical trap is diagnostic. A purchase-order table shows changes in
`CDHDR`/`CDPOS` while its `Log data changes` checkbox is **off**, so an
investigator who checks only the checkbox concludes nothing is logged:

> "Sharp-Eyed readers may have spotted there that the checkbox „Logging“ was not set – however we claimed that changes were logged in CDHDR and CDPOS. The reason is that the field “Logging” is telling us, whether log entries will be made in the table „DBTABLOG“."

— [dab:Europe, *SAP Change Tables (Part 2)*](https://www.dab-europe.com/en/articles/sap-change-tables-part-2-what-tables-and-field-changes-are-actually-getting-logged-and-where/)

Note also that table logging needs **both** switches; the table flag alone does
nothing, which is the mirror-image mistake. SAP's own page on it carries a
third name for the target table, `DBTABPRT`, where every other source says
`DBTABLOG` — see section 18.

---

## 4. You must read the old image *before* you change anything

Because the modules only compare what you pass, the old image has to be
captured while it still exists. A recent SAP Community walkthrough puts the
consequence in one sentence:

> "The method cannot read old values from the database itself — by the time you call it, your MODIFY statement may have already overwritten the old data. You must read the old values from the database before making any changes, hold them in memory, and pass them to the FM alongside the new values."

— [How to Implement SAP Change Document](https://community.sap.com/t5/abap-blog-posts/how-to-implement-sap-change-document/ba-p/14423026)

The failure mode is quiet and wrong rather than loud: pass the already-modified
row as *both* images and the framework correctly reports that nothing changed —
the document is empty, or absent (section 6), and no error is raised.

Order that works:

```abap
SELECT SINGLE * FROM ztable INTO @DATA(ls_old) WHERE id = @lv_id.   " old image first
ls_new = ls_old.
ls_new-city = lv_new_city.
MODIFY ztable FROM ls_new.
" ... then call the generated write module with BOTH images, then COMMIT WORK
```

---

## 5. The write runs in the update task — so no `COMMIT WORK` means no change document

`SCDO` does not generate a plain function module. It generates an
**object-specific update task**, and the documentation uses that word
throughout:

> "During transport, the generation of the object-specific update task is performed in the target system during import."

— [Defining Change Document Objects](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa018f493111d182b70000e829fbfe/content.htm)

> "These function modules are called in the right order by object-specific, generated update processes as soon as these are jumped to."

— [Creating Change Documents](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa01d0493111d182b70000e829fbfe/content.htm)

That places the write under ordinary update-task rules, which the ABAP keyword
documentation states without qualification:

> "If the statement `COMMIT WORK` is not executed when the current program is executed after the registration of a function module, the function module is not executed and the associated entries are deleted from the corresponding database tables when the program ends."

> "The statement `ROLLBACK WORK` deletes all previous registrations for the current SAP LUW."

— [CALL FUNCTION – IN UPDATE TASK](https://eduardocopat.github.io/abap-docs/7.54/abapcall_function_update/)

So:

- **No `COMMIT WORK`** → your `UPDATE` may still be committed by an implicit
  database commit elsewhere while the change document is thrown away. Data
  changed, audit trail empty.
- **`ROLLBACK WORK`** → registration deleted. The same asymmetry this repo
  documented for [IDoc & ALE](../IDoc%20and%20ALE#readme) and the
  [Application Log](../Application%20Log#readme).
- Failures surface **asynchronously**, in `SM13`, not as a `sy-subrc` at the
  call site. `sy-subrc` is undefined after `CALL FUNCTION ... IN UPDATE TASK`,
  so there is nothing useful to check.

The wrapper walkthrough above reaches the same conclusion from the application
side — *"Both operations must happen within the same Logical Unit of Work, so
they commit together"*.

---

## 6. `CHANGEDOCUMENT_CLOSE` raises `NO_POSITION_INSERTED` — no changes means no document

The header is written last, by `CHANGEDOCUMENT_CLOSE`, whose generated
signature carries five exceptions
([`CHANGEDOCUMENT_CLOSE`](https://www.sapdatasheet.org/abap/func/changedocument_close.html)):

| Exception | Meaning |
|---|---|
| `NO_POSITION_INSERTED` | nothing was logged, so no header is written |
| `OPEN_MISSING` | `CHANGEDOCUMENT_OPEN` was not called first |
| `OBJECT_INVALID` | object class not known |
| `HEADER_INSERT_FAILED` | header insert failed |
| `POSITION_INSERT_FAILED` | item insert failed |

`NO_POSITION_INSERTED` is the normal, healthy outcome of a save in which no
logged field changed — and it is why "the user pressed save and there is no
change document" is usually correct behaviour rather than a bug. It is also
indistinguishable, from `CDHDR`, from the case where the fields *did* change but
none of them carried the flag (section 2). The two causes have the same symptom
and completely different fixes.

`CHANGEDOCUMENT_OPEN` has exactly one exception, `SEQUENCE_INVALID`
([`CHANGEDOCUMENT_OPEN`](https://www.sapdatasheet.org/abap/func/changedocument_open.html)) —
the modules are a state machine and must be called in order.

---

## 7. Single case, multiple case, and the sort nobody checks

Per table in the `SCDO` object you choose whether one row or many rows belong
to the business object:

> "Indicator **Transmission as Internal Table** — If you wish the change data to be passed in an internal table (multiple case), select this field. If you do not select this field, the change data will be passed in a work area (single case)"

— [Defining Change Document Objects](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa018f493111d182b70000e829fbfe/content.htm)

For the multiple case there is a precondition stated twice on the Creating page,
with no mention of what happens if you ignore it:

> "The transferred tables must be sorted by key fields and must not contain any double entries."

Nothing validates this. `CHANGEDOCUMENT_MULTIPLE_CASE` walks old and new in
parallel, so unsorted input produces a document that is wrong rather than
missing: rows paired against the wrong rows, phantom inserts and deletes,
values attributed to the wrong key. `SELECT` without `ORDER BY` is enough to
trigger it, which is why it tends to appear only after data volume grows and
the database changes its access path.

`CHANGEDOCUMENT_PREPARE_TABLES` exists for exactly this preparation:

> "With this function module you can compare the rows of two tables that you are transferring as TABLE_OLD and TABLE_NEW. With a parameter you can define whether these internal tables are to be prepared for the multiple cases. Identical rows are deleted and changed rows are flagged with a processing indicator."

### `STRING` fields need the other module

> "`CHANGEDOCUMENT_MULTIPLE_CASE2` — This function module creates change document items. The change data is transferred as IMPORT parameters (TABLE_OLD, TABLE_NEW). … This module is necessary if STRINGs have to be logged in tables."

A multiple-case object containing a `STRING` field, wired to the plain
`MULTIPLE_CASE`, is a silent gap for that field only.

---

## 8. `CHNGIND` has five values, and one SAP page lists four — using `I` twice

The item change flag is `CDPOS-CHNGIND`, `CHAR 1`. The Concept page gives all
five:

> "U(pdate) — Data changed (log entry for each changed field which was flagged as "change document-relevant", in the dictionary)"
> "I(nsert) — Data inserted (log entry for the entire table entry)"
> "J (Field documentation at Insert) — Insert a table entry with field documentation. 1 log entry per field of the table entry inserted. The field contents inserted are retained"
> "D(elete) — Data deleted (log entry for the entire table entry)"
> "E (Field documentation) — Delete a table entry with field documentation. 1 log entry per field of the table entry deleted. The field contents deleted are retained"

| `CHNGIND` | Meaning | Rows written |
|---|---|---|
| `U` | update | one per changed flagged field |
| `I` | insert | **one for the whole table entry** |
| `J` | insert with field documentation | one per field |
| `D` | delete | **one for the whole table entry** |
| `E` | delete with field documentation | one per field |

The `I`-vs-`J` and `D`-vs-`E` choice is the pair of `SCDO` checkboxes
*Doc. of Individual Fields at Insertion* / *at Deletion*. Without them you get
one item for the entire record, and the field name is the literal string `KEY`:

> "If you wish to have your own log record for every single field when data is deleted, select this field. If you do not select this field, the deletion of all relevant fields is entered in a document item (in the field FNAME you have 'KEY', field TABKEY filled)."

So a report that joins `CDPOS` on `FNAME` to show per-field history shows
**nothing at all** for creates and deletes unless those boxes are ticked —
and the values are not recoverable afterwards, because they were never written.
This is a configuration decision that cannot be fixed retroactively.

Two documentation defects sit on top of this, both live:

- The data element short texts for `CDPOS-CHNGIND` and `CDHDR-CHANGE_IND` read
  **"Change Type (U, I, E, D)"** / **"Application object change type (U, I, E, D)"**
  — four values, `J` omitted — while the domain's own fixed-value list contains
  all five, `J` included
  ([`CDPOS`](https://leanx.eu/sap/table/cdpos/), [`CDHDR`](https://leanx.eu/sap/table/cdhdr/)).
  A `CASE` statement written from the field description silently falls through
  on `J`.
- The `em700` rendering of the Concept page lists only four values and spends
  the letter **`I` twice** — once for insert, once for *"I(ndividual Field
  Documentation)"* describing what is actually `E`, with `J` absent entirely
  ([Concept, em700](https://help.sap.com/saphelp_em700_ehp01/helpdata/en/2a/fa0175493111d182b70000e829fbfe/content.htm?no_cache=true)).
  The `ewm900` rendering of the same page is correct. Only the domain's fixed
  values are authoritative.

---

## 9. `TABKEY` is `CHAR 70` — and when the key is longer it holds a GUID instead

`CDPOS-TABKEY` is the primary key of the changed row, with non-character fields
converted to character and concatenated in dictionary order, client first. It is
`CHAR 70` ([`CDPOS`](https://leanx.eu/sap/table/cdpos/)). Keys do exceed that,
and SAP handles it by **replacing the contents rather than truncating**:

> "If the key of a table is longer than 70 characters, this long table key is saved in the CDPOS_UID supplementary table. … The long table key for CDPOS is in character 254 in the field TABKEY of table CDPOS_UID. The GUID for CDPOS_UID is in the field TABKEY of table CDPOS. If there is a record in CDPOS_UID, field CDHDR-VERSION = 1 or 3."

So for those rows `CDPOS-TABKEY` contains a 32-character UUID
(`CDPOS_UID-KEYGUID`, `SYSUUID_C`), not a key. Offset-based parsing code does
not fail — it reads the first three characters of a GUID as a client, the next
ten as a document number, and returns a plausible, wrong answer. The table's
short description says so in its name: *"Additional Table for Inclusion of
TABKEY>70 Characters"*, with `TABKEY` typed `CDTABKEYLO` / `CHAR 254`
([`CDPOS_UID`](https://leanx.eu/sap/table/cdpos_uid/)).

`CDHDR-VERSION` (`CHAR 3`) is the discriminator, and it is the field most
`CDHDR` reports never select:

| `CDHDR-VERSION` | Meaning |
|---|---|
| blank | items fully in `CDPOS` |
| `1` | a `CDPOS_UID` row exists — `CDPOS-TABKEY` is a GUID |
| `2` | a `CDPOS_STR` row exists |
| `3` | both |

---

## 10. `VALUE_OLD` and `VALUE_NEW` stop at 254 characters; strings live elsewhere

Both value fields are `CHAR 254` (data elements `CDFLDVALO` / `CDFLDVALN`,
domain `FIELDVAL`), confirmed across
[`CDPOS`](https://leanx.eu/sap/table/cdpos/) and
[ERPExplorer](https://www.erpexplorer.com/sap/r3/table/CDPOS). A longer value
cannot be represented, and `STRING` columns are not stored here at all:

> "If STRING fields are to be logged for a table, they are saved in the CDPOS_STR table. The fields VALUE_OLD and VALUE_NEW in table CDPOS_STR contain old and new change document values for a STRING variable. The fields VALUE_RAWSTR_OLD and VALUE_RAWSTR_NEW in table CDPOS_STR contain old and new change document values for a RAWSTRING variable … The fields VALUE_SHSTR_OLD and VALUE_SHSTR_NEW in table CDPOS_STR contain old and new change document values for a SHORTSTRING variable. If there is a record in CDPOS_STR, field CDHDR-VERSION = 2 or 3."

A change-history report that selects only from `CDPOS` is therefore complete
only for objects with no long keys and no string fields. Check `CDHDR-VERSION`
before trusting it — and note that the three string flavours use three
*different pairs* of column names, so handling `STRING` does not get you
`RAWSTRING` for free.

Values are stored in **internal** format for the type, which is why the `SCD1`
and `SCD2` read modules advertise formatting as a feature rather than assuming
you will do it:

> "This function module reads the change document items for a particular change document number belonging to a change document object and then prepares the old and new values in accordance with their type."

Reading `CDPOS` with plain Open SQL skips that step: dates arrive as `YYYYMMDD`,
amounts unscaled, and `ALPHA`-converted keys with leading zeros.

---

## 11. Do not hand-parse `TABKEY` — function group `SCD8` ships the conversion

Splitting `TABKEY` with hard-coded offsets is the standard home-grown solution
and it breaks whenever a key field is added, lengthened, or the GUID case of
section 9 appears. SAP ships both directions, with verified signatures:

| Module | Direction | Parameters |
|---|---|---|
| [`CHANGEDOCU_KEY_CHAR2ANY`](https://www.sapdatasheet.org/abap/func/changedocu_key_char2any.html) | `TABKEY` → structure | importing `IV_TABLEKEY` (`CDPOS_UID-TABKEY`), `IV_TABNAME` (`CDPOS-TABNAME`); exporting `ES_STRUCT_OUT` (`ANY`); exceptions `TABNAME_IS_EMPTY`, `NAMETAB_ERROR` |
| [`CHANGEDOCU_KEY_ANY2CHAR`](https://www.sapdatasheet.org/abap/func/changedocu_key_any2char.html) | structure → `TABKEY` | importing `IV_STRUCT_IN` (`ANY`), `IV_TABNAME`; exporting `EV_TABKEY` (`CDPOS_UID-TABKEY`) |

Both live in function group `SCD8`, package `SZD`,
and `CHAR2ANY` has existed since release 610. Note that the key parameters are
typed against **`CDPOS_UID-TABKEY`** — the `CHAR 254` variant — not
`CDPOS-TABKEY`; passing a `CDPOS-TABKEY` into them is fine, the other way round
is a truncation waiting to happen. The group also contains
`CHANGEDOCU_TABKEYLEN_GET`, `CHANGEDOCU_STRUCT_CHAR2ANY` and
`CHANGEDOCU_TABLE_CHAR2ANY` for the related cases.

The pure-ABAP equivalent, for when you want no function call, is an RTTI cast —
see part 2 of the demo report.

---

## 12. Currency and unit fields need a reference structure, or the amount is unqualified

An amount without its currency is not an audit record. If the currency or unit
key is not in the same table as the amount, the framework cannot find it and you
must declare where it lives:

> "If currency and unit fields are not defined in the passed table, but in a reference table, you must pass the name of the reference table and the referenced field to the function modules. For this purpose, create a structure in the Dictionary as INTTAB, and then define fields for this structure that are made up of names from the corresponding reference table and the reference fields."

— [Defining Change Document Objects](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa018f493111d182b70000e829fbfe/content.htm)

The doc's own example: `X4711-PRICE` takes its currency from `T001-CURR`, so you
build an `INTTAB` structure (`R4711`) containing a field named `T001WAERS` — the
reference table name concatenated with the reference field name — and fill it
yourself, old and new. `CDPOS` then has somewhere to put `CUKY_OLD` / `CUKY_NEW`
and `UNIT_OLD` / `UNIT_NEW`.

Skip it and the amount is still logged; only its currency is missing. A
reconciliation two years later cannot tell 100 EUR from 100 JPY.

---

## 13. `CHANGEDOCUMENT_READ_RANGES`: all ranges empty reads nothing, not everything

Every other selection API in ABAP treats an empty range table as "no
restriction". This one inverts it, in a one-line caveat:

> "Range tables are passed to the function module. These must be filled correctly. If all the range tables are empty, no data is read."

— [Reading and Editing Change Documents](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa01dd493111d182b70000e829fbfe/content.htm)

A caller that builds ranges from optional selection-screen fields and leaves
them all blank gets an empty result and `sy-subrc = 0`, which reads exactly like
*this object was never changed*. Guard the call: if every range is empty,
either refuse or fill one deliberately.

---

## 14. The change number is not the change document number

Stated three times across the documentation, which is a good indication of how
often it is got wrong:

> "The change number must not be confused with the change document number. The change document number is automatically assigned by the function modules of the function group SCD0 when a change document is created for a change document object. The change number is assigned when changes are planned by the user. The same change number can be used for different change document objects."

— [Deleting Change Documents and Planned Changes](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa01f7493111d182b70000e829fbfe/content.htm)

| | Assigned by | Unique across objects |
|---|---|---|
| Change document number (`CDHDR-CHANGENR`) | the framework, on create | yes |
| Change number (`CDHDR-PLANCHNGNR`) | the user, when planning a change | **no** — reusable across objects |

Because the change number is not unique, treating it as a key joins unrelated
documents together. `CDHDR` also carries `WAS_PLANND`, the flag that the
document came from planned changes, and planned changes are read with the `SCD3`
modules, not the `SCD1` ones.

---

## 15. The document number comes from a number range object, so it has gaps

> "The change document number is assigned when logging a change, i.e. when the change document creation function modules (function group SCD0) create the change document header. … It uses the NUMBER_RANGE object "CHANGEDOCU"."

— [Concept](https://help.sap.com/saphelp_ewm900/helpdata/en/48/dfd498ab14280de10000000a42189c/content.htm?no_cache=true)

That puts `CDHDR-CHANGENR` under everything in this repo's
[Number Ranges](../Number%20Ranges#readme) note: buffered number ranges produce
**gaps**, and numbers are consumed by transactions that later roll back. A
completeness check of the form "the highest `CHANGENR` is 5000, therefore there
should be 5000 documents" is wrong by construction, and an auditor who is told
the numbering is gapless has been misinformed. `CHANGENR` is `CHAR 10`, so it
also sorts as text, not as a number.

---

## 16. The generated objects are regenerated on import — never transport them

The change document object transports as `R3TR CHDO`, and everything generated
from it is rebuilt in the target system rather than shipped:

> "During transport, the generation of the object-specific update task is performed in the target system during import. The object-specific update process contains generated structures, include programs, and a function group."

> "All manual changes to generated structures, include programs, or the function group are overwritten by the generation during import."

> "Never transport the generated structures, include programs, or function group directly using their own transport objects. This can cause errors when importing the change document object."

> "The generation is executed in its own after-import method AFTER_IMP_CHDO."

— [Defining Change Document Objects](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa018f493111d182b70000e829fbfe/content.htm)

Two distinct mistakes follow from ignoring this:

- **Editing the generated write module** to add a check or a `BREAK-POINT`. It
  works in development until the next import regenerates it, then silently
  reverts. Wrap it instead; never edit it.
- **Adding the generated function group to a transport** to "make sure it gets
  there". The doc says this can break the import of the `CHDO` object itself.
  Transport the `R3TR CHDO` entry and let `AFTER_IMP_CHDO` do the rest.

A useful corollary: the object name is the only thing that travels, so the
generated module in production is whatever the *target* system's `RSSCD000`
produced — worth remembering when a module exists in `DEV` and not in `QAS`.

---

## 17. Deleting: the legal warning, the missing `COMMIT`, and the switchable authority check

`SCD4` deletes change documents, and the documentation leads with a warning
rather than a parameter list:

> "Before deleting change documents check if this is permitted by law."

> "Depending on the application, change documents are used to ensure auditing requirements. In this case it makes sense to archive change documents no longer required in the system and then to delete them."

— [Deleting Change Documents and Planned Changes](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa01f7493111d182b70000e829fbfe/content.htm)

Two technical details on `CHANGEDOCUMENT_DELETE_V2` that matter:

> "Using this function module it is possible to delete change documents on a cross-client basis in the update task. An authorization check is performed if the parameter DISABLE_AUTHORITY_CHECK = SPACE (default) remains. The object class is expected, as a minimum. In addition you can specify the object ID. Generic inputs (search string '*') are also possible. A COMMIT WORK is not performed."

- **"A COMMIT WORK is not performed."** Same shape as the rest of this note: the
  deletion is registered, not done, until the caller commits.
- **`DISABLE_AUTHORITY_CHECK`** defaults to the *safe* value, and it would be
  easy to set it while copying a template. It is the switch that turns an
  audited deletion into an unaudited one.
- **Generic `'*'`, cross-client, and "The object class is expected, as a
  minimum."** is a very wide blast radius for one call. Archive first (archiving object `CHANGEDOCU`,
  built on the ADK), then delete.

---

## 18. Documentation drift worth knowing about

Each of these is a case where SAP's prose and SAP's generated metadata — or two
renderings of the same SAP page — disagree. In every case the metadata wins.

| Where | The drift |
|---|---|
| `CDPOS-CHNGIND` / `CDHDR-CHANGE_IND` short text | reads "(U, I, E, D)" — omits the fifth fixed value `J` |
| Concept page, `em700` vs `ewm900` | `em700` lists four flag values, uses `I` twice, drops `J`; `ewm900` lists all five correctly |
| Concept page, `em700` | writes "function group **SCDO**" and "function group **SCD0**" two sentences apart. `SCDO` (letter O) is the transaction; `SCD0` (digit zero) is the function group. `ewm900` says `SCD0` in both places |
| Concept page, `em700` | "If the table key for a table **has** 70 characters" — the rule is *longer than* 70, as `ewm900` states and as `CDPOS_UID`'s own description confirms |
| Concept page, `ewm900` | an untranslated German word left in the English text: "…for a RAWSTRING variable **gespeichert**." |
| Defining Change Document Objects | the *Doc. of Individual Fields at **Insertion*** bullet describes deletion — "when data is **deleted**", "the **deletion** of all relevant fields" — copy-pasted from the bullet above it. The insertion flag controls `J`, not `E` |
| [Logging Changes to Table Data](https://help.sap.com/doc/saphelp_nw73ehp1/7.31.19/en-US/c7/69bcd2f36611d3a6510000e835363f/content.htm?no_cache=true) | "the database logs table changes in the table **DBTABPRT**" where `SCU3`, `RSTBPDEL`, `BC_DBLOGS` and every other source say **`DBTABLOG`**. Verify in your own system before coding against either name |

The `SCDO`/`SCD0` collision is worth internalising because it is not only a
typo in the doc — the two names differ by one glyph that most fonts render
almost identically, and `SCD0` is also not a transaction while `SCDO` is.

---

## 19. Checklist

Before promising that an object is audited:

1. Is there an `SCDO` object containing the table? (`SCDO`, or `CDPOS` for live data)
2. Is the **data element** of each field of interest flagged — not just the table?
3. Is there a **caller** of the generated write module on every path that
   changes the data, including loads, corrections and `SM30`?
4. Is the old image read **before** the modification?
5. Is there a `COMMIT WORK`, and is it absent from code already running in the
   update task?
6. For multiple case: are both tables **sorted by key and duplicate-free**?
7. Are the *Individual Fields at Insertion / Deletion* flags set, if creates and
   deletes need field-level history? (cannot be fixed retroactively)
8. Do any logged fields use `STRING` (→ `CDPOS_STR`, and `MULTIPLE_CASE2`) or a
   key longer than 70 characters (→ `CDPOS_UID`)? Does the reader check
   `CDHDR-VERSION`?
9. Do amounts have their currency, via a reference structure if needed?
10. Does the reader use the `SCD1`/`SCD2` modules or `SCD8` conversions rather
    than raw `CDPOS` plus hard-coded offsets?

---

## Sources

- [Change Documents](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa015b493111d182b70000e829fbfe/content.htm) — section overview
- [Concept](https://help.sap.com/saphelp_ewm900/helpdata/en/48/dfd498ab14280de10000000a42189c/content.htm?no_cache=true) (`ewm900`) and [Concept](https://help.sap.com/saphelp_em700_ehp01/helpdata/en/2a/fa0175493111d182b70000e829fbfe/content.htm?no_cache=true) (`em700`) — flag values, `CDPOS_UID` / `CDPOS_STR`, numbering
- [Defining Change Document Objects](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa018f493111d182b70000e829fbfe/content.htm) — `SCDO` fields, reference tables, transport
- [Set change document flag](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa019c493111d182b70000e829fbfe/content.htm) — the data-element flag and its side effects
- [Creating Change Documents](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa01d0493111d182b70000e829fbfe/content.htm) — function group `SCD0`
- [Reading and Editing Change Documents](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa01dd493111d182b70000e829fbfe/content.htm) — function groups `SCD1` / `SCD2`
- [Read and format planned changes](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa01ea493111d182b70000e829fbfe/content.htm) — function group `SCD3`
- [Deleting Change Documents and Planned Changes](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa01f7493111d182b70000e829fbfe/content.htm) — function group `SCD4`
- [Managing Archived Change Documents](https://help.sap.com/saphelp_SCM700_ehp01/helpdata/en/2a/fa0204493111d182b70000e829fbfe/content.htm)
- Generated signatures: [`CHANGEDOCUMENT_OPEN`](https://www.sapdatasheet.org/abap/func/changedocument_open.html), [`CHANGEDOCUMENT_CLOSE`](https://www.sapdatasheet.org/abap/func/changedocument_close.html), [`CHANGEDOCU_KEY_CHAR2ANY`](https://www.sapdatasheet.org/abap/func/changedocu_key_char2any.html), [`CHANGEDOCU_KEY_ANY2CHAR`](https://www.sapdatasheet.org/abap/func/changedocu_key_any2char.html)
- Table definitions: [`CDHDR`](https://leanx.eu/sap/table/cdhdr/), [`CDPOS`](https://leanx.eu/sap/table/cdpos/), [`CDPOS_UID`](https://leanx.eu/sap/table/cdpos_uid/)
- [CALL FUNCTION – IN UPDATE TASK](https://eduardocopat.github.io/abap-docs/7.54/abapcall_function_update/) — the `COMMIT WORK` / `ROLLBACK WORK` rules
- [How to Implement SAP Change Document](https://community.sap.com/t5/abap-blog-posts/how-to-implement-sap-change-document/ba-p/14423026) — the old-image-first rule, RAP behaviour definition
- [Onapsis, *The Value of Table Change Logging*](https://onapsis.com/blog/value-table-change-logging-sap-customizing-data/) and [dab:Europe, *SAP Change Tables (Part 2)*](https://www.dab-europe.com/en/articles/sap-change-tables-part-2-what-tables-and-field-changes-are-actually-getting-logged-and-where/) — change documents vs table logging

## See also in this repo

- [Application Log (BAL)](../Application%20Log#readme) — the diagnostic buffer that is explicitly *not* an audit trail
- [Update Task](../Update%20Task#readme) — V1/V2, registration vs call
- [Number Ranges](../Number%20Ranges#readme) — why `CHANGENR` has gaps
- [IDoc & ALE](../IDoc%20and%20ALE#readme) — change pointers (`BDCP`, `BD52`) are generated *from* change documents
- [Commit Work Events](../Commit%20Work%20Events#readme) — the LUW this all hangs off
