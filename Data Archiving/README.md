# Data Archiving (ADK) - the write program that must not delete, the `COMMIT` that is not `COMMIT WORK`, and the two exceptions both numbered 1

Every SAP system eventually has a table nobody is allowed to delete from and
nobody wants to read either. The answer is **data archiving**, and underneath
almost all of it sits the **Archive Development Kit (ADK)** - component
`BC-CCM-ADK`, package `SARC`, function group `ARCH`.

ADK is unusual among SAP frameworks in that it does *less* than developers
expect, and is explicit about it:

> "These function modules cannot be used for the actual deletion of data from the database or reloading of data into the database. Your program must handle these actions."

- [ADK Interface](https://help.sap.com/doc/saphelp_em700_ehp01/7.0.1/en-US/2a/fa03ec493111d182b70000e829fbfe/content.htm?no_cache=true)

ADK writes files, manages sessions and hands your data back. The `delete`
statement is yours. Almost every trap below follows from that one split.

This note is about the **programming model** - what the ADK function modules
guarantee, what they silently do not, and the handful of rules that are stated
once in the documentation and then cost a weekend. It is not an archiving
*Customizing* guide (residence times, variants, `SARA` scheduling).

## The cast

| Name | Role |
|---|---|
| `SARA` | archive administration - schedule write / delete / read jobs |
| `AOBJ` | define the archiving object: which programs, which flags |
| `SARI` / `SARE` | Archive Information System (SAP AS) - infostructures, archive explorer |
| **Archiving object** | the business unit of archiving (`BC_SBOOK`, `MM_EKKO`), *not* a table |
| **Data object** | one business instance inside an archive file - one order, one booking |
| **Data container** | ADK's buffer holding the records of the *current* data object |
| **Archive handle** | `SY-TABIX`-typed token tying all your ADK calls to one session |
| **Archive file** | the `.ADK` file on disk or in the content server |

Note the second row of that list. You do not archive a table; you archive a
*business object*, and the records of several tables land inside one data
object. That is why `DB15` exists - to answer *which archiving object owns my
table*.

---

## 1. The write program must not delete. This is the whole design.

The single most common custom-archiving mistake is one program that selects,
writes a file and deletes the rows. SAP says this twice, in two different
places, in two different ways:

> "To avoid loss of data, the write program must not delete any data in the database itself. The data is deleted by an independent delete program."

- [Developing Write Programs](https://help.sap.com/doc/saphelp_aii710/7.1/en-US/2a/fa047b493111d182b70000e829fbfe/content.htm?no_cache=true)

> "For data security reasons, the write program must not delete any data in the database. During the delete phase, a separate delete program deletes the data from the database. This ensures that no data can be lost during the write phase, and makes online archiving possible."

- [Developing Delete Programs](https://help.sap.com/doc/saphelp_aii710/7.1/en-US/2a/fa0495493111d182b70000e829fbfe/content.htm?no_cache=true)

The reason is not bureaucratic. The delete program does not re-select the rows
it is about to delete - it learns which rows to delete **by reading the archive
file back**:

> "The delete programs determine which data is to be deleted from the database by reading the archive files. This guarantees that only data that can successfully be read from the archive files is deleted from the database."

So the round trip *is* the safety property. A file that cannot be read produces
a delete program that deletes nothing. Collapse the two programs into one and
you have deleted that guarantee along with the second program - the data is
gone whether or not the file is readable.

The write program is allowed to touch the database, but narrowly:

> "The write program can change the database, to set an archiving indicator, for example."

and the same page immediately prices it: this "should only happen when
absolutely necessary, as every change increases the database load and the
archiving runtime."

---

## 2. ADK commits your database LUW behind your back

This sentence is buried in a bullet list on the write-program page and it
invalidates most LUW assumptions people bring to a write program:

> "To update the Archive Development Kit's (ADK) administration data, ADK sends a COMMIT (not the ABAP command COMMIT WORK) to the database several times during the archiving process."

Read the parenthesis carefully. It is **not** `COMMIT WORK`, so:

- update-task modules you registered are **not** triggered by it,
- SAP LUW semantics are untouched,
- but the **database** transaction really does end, repeatedly, at times you
  do not control.

A database commit is exactly the event that invalidates an open database
cursor. This repo's [Mass Data Processing](../Mass%20Data%20Processing#readme)
note documents that rule from the `OPEN CURSOR` side: any database commit
closes every open cursor, and the next `FETCH` dumps `DBSQL_INVALID_CURSOR`.

Composing the two gives the write-program shape to avoid: a `SELECT ... PACKAGE
SIZE` or `OPEN CURSOR` loop over the source table with `ARCHIVE_SAVE_OBJECT`
called *inside* it. The safe shape is the same one that note recommends -
collect the **keys** first, close the read, then loop over the key table doing
targeted re-reads per data object.

**Honesty flag:** the two documented facts are quoted above and below; the
conclusion that an ADK administration commit will close *your* cursor is my
composition of them, not a sentence SAP writes anywhere. Treat it as the
hypothesis to test in your own system, not as a quoted guarantee.

---

## 3. In a delete program, `ROLLBACK WORK` is not yours to write

ADK ships a function module whose entire purpose is to replace a language
statement: `ARCHIVE_ROLLBACK_WORK`, short text *Execute Rollback and Report to
Archiving Classes*. It is listed among the object-specific functions on the
[ADK Interface](https://help.sap.com/doc/saphelp_em700_ehp01/7.0.1/en-US/2a/fa03ec493111d182b70000e829fbfe/content.htm?no_cache=true)
page.

The reason is in the short text: the archiving classes bundled into your
archiving object have their own in-memory state for the current data object.
A bare `ROLLBACK WORK` rolls back the database and leaves that state believing
the work happened. The function module rolls back *and* tells the classes.

**Honesty flag:** the ADK whitepaper states the rule as a flat prohibition -
that it must be done by calling this function module and not by the ABAP
statement `ROLLBACK WORK`. I could not re-fetch that PDF from a stable source
this run, so I am not presenting it as verbatim SAP documentation. What is
verified is the function module, its short text, and its place in the ADK
interface. Treat the prohibition as strong convention backed by an unverified
quote.

---

## 4. The commit counter is Customizing, not a constant you pick

delete programs commit in batches, and the batch size is not a developer
decision:

> "The delete programs must use function module ARCHIVE_GET_CUSTOMIZING_DATA to get the value of the object counter, which controls after how many data objects a COMMIT WORK is called by the delete program."

```abap
CALL FUNCTION 'ARCHIVE_GET_CUSTOMIZING_DATA'
  EXPORTING  object                      = lv_object      " ARCH_OBJ-OBJECT
  IMPORTING  commit_count_for_delete_prg  = lv_commit      " ARCH_USR-ARCH_COMIT
             maintain_index              = lv_index       " ARCH_USR-ARCH_INDEX
  EXCEPTIONS object_not_found            = 1.
```

Two things follow. First, `MAINTAIN_INDEX` arrives from the *same* call - the
index decision is Customizing too, not a program constant. Second, and this is
the trap: exactly one call inside that loop looks batchable and is not.

> "This function module must be called after every ARCHIVE_GET_NEXT_OBJECT and cannot be grouped according to <commit counter> data objects."

That is `ARCHIVE_DELETE_OBJECT_DATA`, the call that tells the archiving classes
to delete *their* data. It sits visually next to your own batched delete
subroutine and has an identical-looking signature (`archive_handle` and two
exceptions), which is precisely why it gets folded into the batch.

---

## 5. `ARCHIVE_GIVE_STATISTICS`: forbidden in one program, mandatory in the next

Same function module, opposite rules, two pages apart.

In a **write** program:

> "The function module ARCHIVE_GIVE_STATISTICS must not be called in write programs. ADK automatically collects statistics."

In a **delete** program, inside your own delete subroutine, after reporting
`sy-dbcnt`:

> "You must call this function module. Otherwise the statistics function will not work correctly."

So the archiving object's completion log is correct only if the delete program
volunteers its own row counts. Nothing enforces it; the symptom is a session
that archived 400,000 records and deleted, apparently, zero.

Then the test-mode wrinkle, stated twice on the delete page:

> "In delete programs, ARCHIVE_GET_STATISTICS only works in production mode."

> "In delete programs, ARCHIVE_WRITE_STATISTICS only works in production mode."

A test run therefore produces an empty statistics log *by design*, which is
indistinguishable from a test run that selected nothing. If your acceptance
criterion for the dry run is *the log looks right*, you have no criterion.

---

## 6. `ARCHIVE_CLOSE_FILE` is part of the write, not cleanup after it

The instinct is to treat the close as housekeeping and skip it on the error
path. The documentation is blunt:

> "This function module must be called, otherwise the last (physical) archive file to be processed is lost, and the write phase is incomplete."

An early `EXIT`, an unhandled exception, or a `MESSAGE` of type `E` between the
last `ARCHIVE_SAVE_OBJECT` and the close silently discards the final file - the
one holding the most recently written data objects. Everything up to the
previous file boundary survives, which is why this reads as *archiving randomly
loses the tail*.

Note also that `ARCHIVE_WRITE_STATISTICS` "must be called directly before
ARCHIVE_CLOSE_FILE" - the close invalidates the handle, and after it "The
archive handle becomes invalid and can no longer be used."

---

## 7. Forgetting `ARCHIVE_SAVE_OBJECT` is a *feature*, so it fails silently

Inside the write loop, `ARCHIVE_NEW_OBJECT` opens a data container and
`ARCHIVE_SAVE_OBJECT` commits it to the file. Skipping the save is the
documented way to abandon a bad data object:

> "To be able to react to a problem with the data selected for archiving, you can include an IF "error" statement that continues with the next loop before executing ARCHIVE_SAVE_OBJECT. ARCHIVE_NEW_OBJECT is called again thus discarding the data already passed."

Because discarding is intentional behaviour, it raises nothing and sets no
`sy-subrc`. A `CONTINUE` added later for an unrelated reason - a missing
customer master, a skipped currency conversion - therefore drops whole business
objects out of the archive run with no trace in the statistics log and no
entry in the file. The data stays in the database (safe), but the run reports
success and the table does not shrink by the amount anyone expected.

The write loop's own completion rule is also easy to misread. `ARCHIVE_SAVE_OBJECT`

> "Closes the archive file when it reaches the maximum size or number of objects set in Customizing, and opens a new one"

and, if Customizing says so, it "Calls the delete program after an archive file
has been closed". The delete program can therefore already be removing rows
while the write program is still writing - which is the intended design, and
also why *the write job is still running, so nothing has been deleted yet* is
not a safe assumption during an incident.

---

## 8. Reading: `END_OF_FILE` and `END_OF_OBJECT` are both exception 1

The read side is two nested loops, and each loop ends on a *different*
exception that copy-paste gives the *same* number:

| Loop | Function module | Terminating exception | Meaning |
|---|---|---|---|
| outer | `ARCHIVE_GET_NEXT_OBJECT` | `END_OF_FILE = 1` | no more data objects in **any** open file |
| inner | `ARCHIVE_GET_NEXT_RECORD` | `END_OF_OBJECT = 1` | no more records in **this** data object |

Swap them and the program either stops after the first data object or never
stops at all. The names do not help: `END_OF_FILE` does *not* mean *end of one
file* - one handle can hold many files, and `ARCHIVE_GET_NEXT_OBJECT`

> "Sequentially reads all archived data objects from all opened archive files into ADK's data container"

so the outer exception fires once, at the end of the whole set.

A related idiom worth recognising in SAP's own samples: mapping an exception to
**zero** deliberately.

```abap
CALL FUNCTION 'ARCHIVE_GET_TABLE'
  EXPORTING  archive_handle        = lv_handle
             record_structure      = 'SBOOK'
             all_records_of_object = 'X'
  TABLES     table                 = lt_sbook
  EXCEPTIONS end_of_object         = 0.   " <- not an error: this data
                                          "    object has no SBOOK rows
```

`end_of_object = 0` leaves `sy-subrc` at 0 and returns an empty table, because
*this data object contains no records of that structure* is normal, not a
failure. It is legal ABAP and it is easy to read as a typo.

---

## 9. A record's type is a string you have to switch on

`ARCHIVE_GET_NEXT_RECORD` returns the data *and*, separately, the name of the
structure it belongs to:

| Parameter | Type | Note |
|---|---|---|
| `RECORD` | untyped | the classic CHAR buffer - see the Unicode caution below |
| `RECORD_REF` | data reference | the Unicode-safe route |
| `RECORD_STRUCTURE` | `ARC_BUFFER-RNAME` | the DDIC name - `CASE` on this |
| `RECORD_FLAGS` | `ARC_BUFFER-FLAGS` | the delete indicator set by the write program |
| `RECORD_LENGTH` | `ARCH_INT-INT4` | length in `RECORD` |

Dispatch is therefore a `CASE lv_structure` over string literals: an
archiving-object change that adds a table to the object silently falls into
`WHEN OTHERS` in every read program ever written against it. There is no
syntax error and no exception - just a structure nobody consumes.

The Unicode rule removed the old shortcut:

> "In the Unicode context, it is no longer possible to use the CHAR record buffer variable for generic reading of records for structures containing non-character-like fields."

so the generic `DATA lv_buffer(5000) TYPE c` pattern found in pre-Unicode
programs is not merely ugly, it is wrong for any structure with a `P`, `I`,
`X` or `DEC` field. The documented replacements are a typed field symbol over
`RECORD_REF`, or an untyped field symbol - SAP's samples `SBOOKR` and
`SBOOKR_2` respectively.

`ARCHIVE_GET_TABLE` sidesteps all of it when you know the structure: you pass
`RECORD_STRUCTURE` in and get a properly typed internal table out. Prefer it,
and keep `ARCHIVE_GET_NEXT_RECORD` for genuinely generic readers.

---

## 10. The ADK index exists, and SAP tells you not to build one

`ARCHIVE_NEW_OBJECT` takes an `OBJECT_ID`, and that value becomes the key of
the optional ADK index that lets `ARCHIVE_READ_OBJECT` jump straight to one
data object instead of scanning. The constraints on it are strict:

> "The composition of OBJECT_ID must not be changed, and each value passed must be unique; OBJECT_ID must syntactically be CHAR"

*Must not be changed* is the sharp one - the ID is baked into every archive
file already written, so a later *improvement* to the key layout quietly
orphans the index for all historical sessions.

And then, on the page that explains how to build it:

> "We recommend you use the Archive Information System (SAP AS) instead of creating an ADK index."

SAP AS (transaction `SARI` to maintain infostructures, `SARE` to browse) is
a database table you define over fields of the archived data, filled during or
after the delete phase, and queried with ordinary SQL - the usual route is
`AS_API_READ` to resolve selection criteria into archive key plus offset pairs,
then `ARCHIVE_READ_OBJECT` per hit. Writing a read program that opens every
file and scans is the fallback, not the design.

---

## 11. `AOBJ` flags that change program semantics

The archiving object definition is not just program names. Four entries change
what your ABAP is allowed to do:

| Flag | Effect on your code |
|---|---|
| *Interruption Possible* | "If you set this, the write program must also handle the interruption request" - i.e. you must catch `TERMINATION_REQUESTED` on `ARCHIVE_SAVE_OBJECT` |
| *Do Not Start Before End of Write Phase* | mutually exclusive with the above: "This indicator must not be set if the Do Not Start Before End of Write Phase is set" - and "This indicator should not be set for most archiving objects" |
| *Prohibit New Session During Reload* | "The reload program is not authorized to call the function module ARCHIVE_SAVE_OBJECT." |
| *Index Build Allowed* | gate for section 10; the actual build is still a Customizing entry |

Note the first two are a genuine pair of opposites that `AOBJ` will let you
reason about wrongly: interruption support means the delete phase *can* start
before the write phase ends, which is exactly what the second flag forbids.

One more, for anyone maintaining very old objects:

> "As of SAP Web Application Server 6.10 write and delete programs can no longer be generated at runtime."

so an inherited archiving object marked *Archiving Object Generated* has real,
editable, un-regenerable source - treat it as hand-written code.

---

## 12. Parallelism is per file, not per object

> "A delete program always only processes one archive file at a time. Several delete programs can run in parallel, each processing one archive file."

The unit of parallelism is the archive file, whose size is Customizing. So
*the delete phase is too slow* is usually tuned by making files *smaller*, not
by making the delete program cleverer - and a single enormous file is a
delete phase with a parallelism of exactly one.

---

## Quick reference

| Task | Call | Watch out for |
|---|---|---|
| Start a write session | `ARCHIVE_OPEN_FOR_WRITE` | once per session; returns the handle |
| Start a data object | `ARCHIVE_NEW_OBJECT` | discards the previous unsaved one, silently |
| Add records | `ARCHIVE_PUT_RECORD` / `ARCHIVE_PUT_TABLE` | `RECORD_FLAGS` carries the delete indicator |
| Commit the data object | `ARCHIVE_SAVE_OBJECT` | may close the file and start the delete job |
| Finish writing | `ARCHIVE_CLOSE_FILE` | skip it and lose the last file |
| Open for delete | `ARCHIVE_OPEN_FOR_DELETE` | one file per job |
| Batch size | `ARCHIVE_GET_CUSTOMIZING_DATA` | `COMMIT_COUNT_FOR_DELETE_PRG`, not your constant |
| Class data delete | `ARCHIVE_DELETE_OBJECT_DATA` | every object, never batched |
| Report deletions | `ARCHIVE_GIVE_STATISTICS` | mandatory here, forbidden in write programs |
| Roll back | `ARCHIVE_ROLLBACK_WORK` | not the `ROLLBACK WORK` statement |
| Open for read | `ARCHIVE_OPEN_FOR_READ` | with no file table it prompts for a selection |
| Next data object | `ARCHIVE_GET_NEXT_OBJECT` | ends on `END_OF_FILE` |
| Next record | `ARCHIVE_GET_NEXT_RECORD` | ends on `END_OF_OBJECT`; `CASE` on `RECORD_STRUCTURE` |
| Records of one structure | `ARCHIVE_GET_TABLE` | typed; `END_OF_OBJECT` is often mapped to 0 |
| Direct access by index | `ARCHIVE_READ_OBJECT` | prefer SAP AS over a hand-built ADK index |

## The demo

[`ydj_archive_read_demo.abap`](ydj_archive_read_demo.abap) is a **read-only**
read program for an existing archiving object (`BC_SBOOK` by default). It opens
the archive for reading, walks every data object across all selected files, and
pulls the `SBOOK` records out two ways - typed via `ARCHIVE_GET_TABLE`, and
generically via `ARCHIVE_GET_NEXT_RECORD` plus `RECORD_REF` - so the
`END_OF_FILE` / `END_OF_OBJECT` split is visible in one program.

It performs no database write, no row deletion, no `COMMIT WORK`, and calls no
write-side ADK module. The write and delete programs are deliberately *not*
shipped as runnable code here: a correct one deletes production rows, and the
honest template for it is the documented call sequence above.

## Sources

- [ADK Interface](https://help.sap.com/doc/saphelp_em700_ehp01/7.0.1/en-US/2a/fa03ec493111d182b70000e829fbfe/content.htm?no_cache=true) - the full function-module inventory, split into object-specific / class-specific / common
- [Developing Write Programs](https://help.sap.com/doc/saphelp_aii710/7.1/en-US/2a/fa047b493111d182b70000e829fbfe/content.htm?no_cache=true) - the ADK `COMMIT`, the statistics prohibition, the close-file warning
- [Developing Delete Programs](https://help.sap.com/doc/saphelp_aii710/7.1/en-US/2a/fa0495493111d182b70000e829fbfe/content.htm?no_cache=true) - commit counter, the never-batch rule, production-mode statistics
- [Developing Read Programs](https://help.sap.com/doc/saphelp_aii710/7.1/en-US/2a/fa04af493111d182b70000e829fbfe/content.htm?no_cache=true) - the read loop and the Unicode caution
- [Creating Archiving Objects](https://help.sap.com/doc/saphelp_aii710/7.1/en-US/2a/fa043a493111d182b70000e829fbfe/content.htm?no_cache=true) - every `AOBJ` flag
- [Creating ADK Indexes and Using Them to Access Archive](https://help.sap.com/doc/saphelp_aii710/7.1/en-US/2a/fa04c9493111d182b70000e829fbfe/content.htm?no_cache=true) - the `OBJECT_ID` rules and the SAP AS recommendation
- Function module signatures verified individually: `ARCHIVE_OPEN_FOR_READ`, `ARCHIVE_GET_NEXT_OBJECT`, `ARCHIVE_GET_NEXT_RECORD`, `ARCHIVE_GET_TABLE`, `ARCHIVE_READ_OBJECT`, `ARCHIVE_CLOSE_FILE`, `ARCHIVE_GET_CUSTOMIZING_DATA`, `ARCHIVE_DELETE_OBJECT_DATA`, `ARCHIVE_GIVE_STATISTICS`
- SAP sample programs referenced by the documentation: `SBOOKA` / `SFLIGHTA` (write), `SBOOKD` / `SFLIGHTD` (delete), `SBOOKR` / `SBOOKR_2` / `SFLIGHTR` (read), `SBOOKI` (index build), `SBOOKS` (index access)

## See also in this repo

- [Mass Data Processing](../Mass%20Data%20Processing#readme) - why a database commit inside a cursor loop is fatal
- [Update Task](../Update%20Task#readme) - what `COMMIT WORK` does that ADK's `COMMIT` does not
- [Change Documents](../Change%20Documents#readme) - the audit trail that outlives the row, and which also ends up archived
- [Application Log](../Application%20Log#readme) - `SBAL_ARCHIVE`, the same mechanism applied to logs
- [Enqueue Locks](../Enqueue%20Locks#readme) - what survives a database commit and what does not
- [Background Jobs](../Background%20Jobs#readme) - how `SARA` actually launches all of this
