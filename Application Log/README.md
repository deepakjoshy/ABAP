# The Application Log (BAL) — the log handle that is optional, the `sy-subrc` that does not mean "logged", and the log number that is a placeholder

Every interface, every batch job and every mass-posting report in an SAP system
needs somewhere to put the forty errors it found in six thousand records.
`MESSAGE` cannot do it — it shows one message and, in a report, terminates. The
Application Log (component BC-SRV-BAL, transactions `SLG0` / `SLG1` / `SLG2`) is
the infrastructure SAP provides instead, and SAP is explicit about why:

> "These messages are not to be output individually"

— [Application Log – Guidelines for Developers](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21000f35d44180e10000000a15822b.html)

That page names `MESSAGE` and `RAISE` as the two commands *not* to use here;
the messages are instead "to be collected and displayed later as a log".

The API is a set of `BAL_*` function modules. They are easy to call, which is
the problem: the dangerous ones do not raise, do not set `sy-subrc`, and produce
a log that looks right in a test system. This note is the list of ways a `BAL`
log is silently not the log you think you wrote.

Two sentences from the same page are worth reading before designing anything
around it:

> "The application log is used to temporarily store messages. The logs should be deleted in intervals. Data that, for reasons of revision security, have to be available for a long period of time, should not be stored with the application log but with the change documents."

The Application Log is **not** an audit trail. It is a bounded-lifetime
diagnostic buffer that a housekeeping job is entitled to delete (section 6).

## The cast

| Object | Role |
|---|---|
| `BAL_LOG_CREATE` | open a log in memory, returns `E_LOG_HANDLE` |
| `BAL_LOG_MSG_ADD` | add a T100 message, returns `E_S_MSG_HANDLE` |
| `BAL_LOG_MSG_ADD_FREE_TEXT` | add a message from a text literal instead of T100 |
| `BAL_LOG_EXCEPTION_ADD` | add the text of an exception object |
| `BAL_LOG_MSG_CUMULATE` | add a message, counting repeats instead of repeating them |
| `BAL_DB_SAVE` | write memory logs to the database |
| `BAL_DSP_LOG_DISPLAY` | show logs on screen (`SLG1`-style) |
| `BAL_LOG_REFRESH` | throw a log out of **memory** |
| `BAL_LOG_DELETE` | mark a log for deletion from the **database** |

| Type | Contents |
|---|---|
| `BAL_S_LOG` | log header — `OBJECT`, `SUBOBJECT`, `EXTNUMBER`, expiry, context, params |
| `BAL_S_MSG` | message — T100 fields plus `PROBCLASS` / `DETLEVEL` / `ALSORT` / context |
| `BAL_S_EXC` | exception — `EXCEPTION` reference plus `MSGTY` and the same attributes |
| `BALLOGHNDL` | log handle, `CHAR22` |
| `BALMSGHNDL` | message handle — log handle **plus** a serial number |

The full module list is in [Function Module Overview](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e23b1720771417fe10000000a15822b.html),
and SAP ships the reference documentation inside the system:

> "Detailed documentation on all function modules, and so on, can be found in the system by executing the program SBAL_DOCUMENTATION."

---

## 1. The log handle is optional — so your message lands in whoever logged last

This is the trap that makes a shared logging helper write into another
application's log, and it is documented in a `Note` box rather than in the
parameter list:

> "The log handle is optional for function modules such as BAL_LOG_MSG_ADD, BAL_LOG_MSG_CUMULATE, BAL_LOG_MSG_ADD_FREE_TEXT, etc. If you do not specify it, the default log is used. You can set it (and other defaults) with the function module BAL_GLB_MSG_DEFAULTS_SET. If no default log is defined, it is automatically set by the function module BAL_LOG_CREATE"

— [Basics](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21029235d44180e10000000a15822b.html)

The generated signature agrees: in `BAL_LOG_MSG_ADD`, `I_LOG_HANDLE` is flagged
**optional** while `I_S_MSG` is **not**
([`BAL_LOG_MSG_ADD`](https://www.sapdatasheet.org/abap/func/bal_log_msg_add.html)).
So this compiles, runs, and returns no error:

```abap
CALL FUNCTION 'BAL_LOG_MSG_ADD'          " no I_LOG_HANDLE
  EXPORTING  i_s_msg = ls_msg
  EXCEPTIONS log_not_found    = 1
             msg_inconsistent = 2
             log_is_full      = 3
             OTHERS           = 4.
```

What makes it dangerous is *whose* log the default is. The default log is set
implicitly by `BAL_LOG_CREATE` — and `BAL_LOG_CREATE` is called by SAP standard
code, by every BAdI implementation in the stack, and by any utility class
somebody else wrote. The log it points at is a property of **the whole internal
session**, not of your call stack. Consequences, in order of how long they take
to diagnose:

- A reusable `log_message( )` method that omits the handle works perfectly in a
  unit test (one log exists — yours) and appends to a standard SAP log in
  production, where your messages are invisible to your own `SLG1` selection.
- Two of your own logs open at once — one per document, say — and every message
  after the second `BAL_LOG_CREATE` goes to the newest log, so document 1 looks
  clean and document 2 carries everybody's errors.
- A BAdI that runs between your `BAL_LOG_CREATE` and your `BAL_LOG_MSG_ADD` can
  move the target without touching your code.

**Always pass `I_LOG_HANDLE`.** Treat the handle as the identity of the log and
thread it through your call stack explicitly; if that is awkward, set it once
deliberately with `BAL_GLB_MSG_DEFAULTS_SET` (function group `SBAL_TOOLBOX`,
importing `I_S_MSG_DEFAULTS`) rather than inheriting whatever was last created.

The display side has the same shape. `BAL_DSP_LOG_DISPLAY` needs no parameters
at all:

> "All messages in memory are displayed in a standard format (this standard format is used e.g. in the transaction SLG1)."

*In memory* means **all** logs in memory, including ones your program did not
create. A parameterless display call in a report that also triggers standard
postings will show the user other applications' messages.

---

## 2. `sy-subrc = 0` does not mean the message was logged

`BAL_LOG_MSG_ADD` does not express success through `sy-subrc` alone. It has
three exceptions *and* two separate boolean outputs
([signature](https://www.sapdatasheet.org/abap/func/bal_log_msg_add.html)):

| Parameter | Type | Short text |
|---|---|---|
| `E_S_MSG_HANDLE` | `BALMSGHNDL` | "Message handle" |
| `E_MSG_WAS_LOGGED` | `BOOLEAN` | "Message collected" |
| `E_MSG_WAS_DISPLAYED` | `BOOLEAN` | "Message output" |

| Exception | Short text |
|---|---|
| `LOG_NOT_FOUND` | "Log not found" |
| `MSG_INCONSISTENT` | "Message inconsistent" |
| `LOG_IS_FULL` | "Message number 999999 reached. Log is full" |

A boolean named *message collected*, returned **alongside** the exceptions, is
hard to explain unless the module can decline a message without failing. That
reading is an inference from the signature, not a sentence SAP writes anywhere —
but it costs nothing to act on. So the
usual `IF sy-subrc <> 0` guard answers a narrower question than the one you are
asking: it tells you the call did not break, not that the message is in the log.
Read `E_MSG_WAS_LOGGED` when it matters.

Two further things fall out of that table:

- **A log holds at most 999,999 messages**, and the ceiling is an exception, not
  a truncation. A mass job logging per-record information hits it at message one
  million and the `BAL_LOG_MSG_ADD` that trips it is the one that fails — in
  other words, the failure arrives nowhere near the design mistake. Use
  `BAL_LOG_MSG_CUMULATE` for repeating messages: per the header documentation,
  "If a message is cumulated, the cumulation value can be put in MSG_COUNT. The value is incremented when more of these messages occur with the function module BAL_LOG_MSG_CUMULATE."
  One row, a counter, no ceiling.
- `E_MSG_WAS_DISPLAYED` exists because the Application Log can be configured to
  display messages as they are collected, via the callback
  `BAL_CALLBACK_DISPLAY` set in `BAL_GLB_CONFIG_SET`. Note that SAP's own
  [Callback Routine Overview](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21063835d44180e10000000a15822b.html)
  puts a `Caution` on that one: "This solution is not yet available."

---

## 3. The handle is permanent immediately; the log number is a placeholder

These two sentences are from two different pages, and the contrast between them
is the whole trap.

> "The LOG_HANDLE has its permanent value immediately and remains valid after saving."

— [Basics](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21029235d44180e10000000a15822b.html)

> "When logs are saved, an internal log number is issued (field LOGNUMBER). At runtime this field has a temporary value (e.g. $00001)."

— [Database Interface](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21021635d44180e10000000a15822b.html)

The handle is a GUID and is final the moment `BAL_LOG_CREATE` returns. The log
number — the thing a user can type into `SLG1`, and the thing you want to store
on your document so support can find the log later — does not exist until the
log is saved, and until then the field is filled with a plausible-looking
placeholder beginning with `$`.

So the natural code is wrong in a way that passes review:

```abap
" WRONG: reads LOGNUMBER before the save that assigns it
CALL FUNCTION 'BAL_LOG_HDR_READ' ...     " ls_log_header-lognumber = '$00001'
UPDATE zmydoc SET log_no = ls_log_header-lognumber WHERE ...
CALL FUNCTION 'BAL_DB_SAVE' ...
```

`$00001` is `CHAR`, so it stores without complaint, and it is not initial, so an
`IS NOT INITIAL` check passes. The mapping only exists as an output of the save:

> "You can find out which number was assigned to a log, after saving."

The mapping arrives in `E_NEW_LOGNUMBERS` (type `BAL_T_LGNM`), and the row
structure `BAL_S_LGNM` makes the trap explicit: it carries **both** numbers in
separate fields — `TMP_LOGNUM` (the `$00001` placeholder) and `LOGNUMBER` (the
real one) — alongside `LOG_HANDLE` and `EXTNUMBER`
([`BAL_S_LGNM`](https://www.sapdatasheet.org/abap/tabl/bal_s_lgnm.html)).

Store the number **from `E_NEW_LOGNUMBERS` after `BAL_DB_SAVE`**, matched on your
log handle. The BAPI programming guide describes the same two fields from the
caller's side — `LOG_NO`, "Application log number", of which it notes
"This is empty if no log used." — and `LOG_MSG_NO`, filled only once the log
exists.

A related asymmetry: some header information is readable but not writable.

> "you receive other information which is not in BAL_S_LOG because it cannot be specified externally. This is, for example, the internal LOGNUMBER, the number of A, E. W, I and S messages, and the highest problem class that occurred."

(The stray period in "A, E. W" is SAP's, not a transcription error — the message
counts and the worst problem class come back from `BAL_LOG_HDR_READ` and cannot
be set by you.)

---

## 4. `BAL_DB_SAVE` is not a `COMMIT`, and by default the log dies with the error it recorded

This is the one that costs a production incident. `BAL_DB_SAVE` writes with
ordinary database updates in **your** LUW. If the business transaction fails and
you roll back, the log of why it failed rolls back with it. The BAPI programming
guide states the consequence directly:

> "Note that for type A error messages (abort), an application log is not created, as in this case there is no COMMIT WORK."

— [Return Parameters (Error Handling)](https://help.sap.com/doc/saphelp_snc70/7.0/en-US/a5/3ec9f74ac011d1894e0000e829fbbd/content.htm)

Read that twice: the failure mode the log exists to explain is exactly the
failure mode in which the log does not survive. The same page gives the standard
answer for a posting context — "If you plan to use application logs in your BAPI, you must write these using the update task."

`BAL_DB_SAVE` offers three couplings, and they behave in opposite ways. Importing
parameters, with their generated short texts
([signature](https://www.sapdatasheet.org/abap/func/bal_db_save.html)):

| Parameter | Default | Short text | LUW behaviour |
|---|---|---|---|
| *(none of the below)* | — | — | written in your LUW; needs your `COMMIT WORK`; **lost on rollback** |
| `I_IN_UPDATE_TASK` | `SPACE` | "Save in UPDATE TASK" | registered as an update module; written when *your* `COMMIT WORK` runs |
| `I_2TH_CONNECTION` | `SPACE` | "FALSE: No secondary connection" | written on a second database connection, outside your LUW |
| `I_2TH_CONNECT_COMMIT` | `SPACE` | "FALSE: No COMMIT in module" | commits that second connection inside the module |
| `I_SAVE_ALL` | `SPACE` | "Save all logs in memory" | ignores `I_T_LOG_HANDLE` and saves everything in memory |
| `I_CLIENT` | `SY-MANDT` | "Client in which the new log is to be saved" | defaults to the current client; a log *can* be written into another one |
| `I_LINK2JOB` | `'X'` | — | on by default: links the log to the current background job |

Pick by what you need to be true:

- **The log must survive a rollback of the business data** (error logs, interface
  rejections): `I_2TH_CONNECTION = 'X'` and `I_2TH_CONNECT_COMMIT = 'X'`. A
  separate connection has its own transaction, so your `ROLLBACK WORK` does not
  reach it — which is exactly why the error log survives the failed posting. See
  [Native SQL](../Native%20SQL#readme) for what a secondary connection is and
  the care it needs.
- **The log must be consistent with the posted document** (the usual business
  case): `I_IN_UPDATE_TASK = 'X'`, so the log is written by the same `COMMIT WORK`
  that posts the document, and no log appears for a document that was not posted.
  See [Update Task](../Update%20Task#readme) — including the rule that code
  running *in* the update task must not commit.
- **Report-style, nothing else at stake:** plain `BAL_DB_SAVE` followed by your
  own `COMMIT WORK`. Nothing is on disk until that commit, so a dump between the
  two leaves no log at all.

`I_LINK2JOB` defaulting to `'X'` is a pleasant default rather than a trap: a log
saved from a background job is reachable from the job in `SM37` without you
doing anything. It is worth knowing it is on, though, if you save a log from a
job on behalf of a different unit of work. See
[Background Jobs](../Background%20Jobs#readme).

---

## 5. The exception path quietly loses two features

`BAL_LOG_EXCEPTION_ADD` looks like the `BAL_LOG_MSG_ADD` of the object world, and
mostly is, but two of the message features are simply absent:

> "Context information for exceptions and cumulated addition of exceptions are not supported."

— [Basics](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21029235d44180e10000000a15822b.html)

The header-data reference says the same from the structure side: for `BAL_S_EXC`,
`MSG_COUNT` is documented as "This attribute is not used for exceptions."
So the document number you were attaching as context (section 7) and the
cumulation that keeps you under the 999,999 ceiling (section 2) both stop working
the moment you log the exception object instead of a T100 message.

And one field is required where you would not expect it. In `BAL_S_EXC`:

| Field | Documentation |
|---|---|
| `EXCEPTION` | "Exception class from which an exception text is added to the log. This field must be filled." |
| `MSGTY` | "Message type ( MSGTY ) of a T100 message. This field must also be filled for exceptions" |

An exception object carries no severity, so BAL cannot infer one — you supply
`MSGTY` yourself. The documentation says the field must be filled; it does not
say what happens if you leave it initial, and `MSG_INCONSISTENT` is the
exception that exists for malformed message data. Either way, there is no
sensible default waiting for you. For how the text comes out of the exception at
all, see [Exception Texts](../Exception%20Texts#readme); for what the T100 fields
mean and the 50-character truncation on the message variables, see
[Messages](../Messages#readme).

---

## 6. The log is temporary by design — and an initial expiry date is in the past

`SLG2` deletes Application Log data, and it is supposed to:

> "You must delete logs to avoid Application Log database table overflow."

> "A log can only be deleted when it has expired (reached or passed its expiry date)."

— both from [Deleting Logs](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21053535d44180e10000000a15822b.html)

The expiry date is a header field **you** fill, `BAL_S_LOG-DATE_DEL`. Leave it
initial and it is `00000000` — a date that has very much passed. The log is
therefore eligible for deletion from the moment it is created, and it will
survive exactly until the next housekeeping run. That is the mechanism behind
*the log was there yesterday*: nothing malfunctioned, the log simply had no
retention and something legitimately collected it.

The companion flag is `DEL_BEFORE`, and here the documentation **contradicts
itself**. The header reference says it is a prohibition:

> "which explicitly forbids deletion before this date"

— [Which Data Can Be Collected?](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e2106b735d44180e10000000a15822b.html)

The deletion page describes it as a *permission* to delete early, and so does
the archiving rule further down that same page — a log may be archived "if it has either expired (expiration date has been reached or has passed) or if the log permits a deletion before the expiration date."
I am not asserting which reading is the implemented one: the field name reads
like the deletion page, two pages outvote one, and the `SLG2` dialog offers
*Delete before expiry* as an option. **Check the behaviour in your own system
before relying on either reading**, and set `DATE_DEL` to a real retention date
regardless — that part is unambiguous in both readings.

If the data genuinely must be kept, the documentation points two ways out, and
neither of them is *set a long expiry*: archiving object `BC_SBAL` with programs
`SBAL_ARCHIVE` / `SBAL_ARCHIVE_DELETE` under `SARA`, or — for anything needed for
audit — change documents, per the quotation at the top of this note.

---

## 7. Context is a `CHAR255` container, and non-character fields break it

Message context is how a log line stops being *credit limit exceeded* and
starts being *credit limit exceeded, customer 4711, document 3000012345*. You
name a DDIC structure and pass its contents:

```abap
ls_my_context-document  = '3000012345'.
ls_msg-context-tabname  = 'MY_DDIC_STRUCTURE'.
ls_msg-context-value    = ls_my_context.          " see the warning below
```

The mechanism is a typeless byte container, and SAP says so:

> "This context consists of the name of a (flat) DDIC structure and its contents, which is held in a CHAR255 container."

— [Application Log and Unicode](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21018a35d44180e10000000a15822b.html)

Which is why the assignment above is conditionally wrong. From the same page, on
`l_s_msg-context-value = l_context.`:

> "causes problems in unicode systems if the DDIC structure contains fields that are non character-like (for example, the fields CONNID as INTEGER)."

SAP considered fixing the container and decided not to — "since most applications only operate with character-like contexts, a conversion of that kind was rejected" — leaving two supported options:

1. **Character-like context structure only.** SAP's own recommendation:
   "Only use character-like fields in the DDIC structure. This procedure is recommended."
   An `INTEGER` becomes `NUMC` and, pleasantly,
   "Coding can normally remain unchanged because moving an integer into an NUMC field automatically converts it."
2. **`ASSIGN ... CASTING`** onto the container when option 1 is impossible —
   the same casting trick the
   [File Interface](../File%20Interface#readme) note uses for mixed structures.
   See [Field Symbols](../Field%20Symbols#readme) for the mechanics.

Old data stays readable either way:
"logs written in old releases can still be read. The old context data is automatically converted into the new structure when it is read."

Storing a context is also not the same as showing one. The
[Log Display](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e2102fa35d44180e10000000a15822b.html)
page lists "Message context fields" as one of the things a display profile's
field catalogs can present, alongside the message line and the message
attributes — so a context you fill but never add to a profile is in the
database and not on the screen.

---

## 8. Finding the log again depends on three fields you probably left blank

`OBJECT`, `SUBOBJECT` and `EXTNUMBER` are not decoration; they are the access
path. From [Which Data Can Be Collected?](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e2106b735d44180e10000000a15822b.html):

| Field | Type | What it is for |
|---|---|---|
| `OBJECT` / `SUBOBJECT` | `CHAR20` | "identify the application and subapplication"; "They can be defined in transaction SLG0." |
| `EXTNUMBER` | `CHAR100` | "External ID in the log header ( CHAR100), defined by the application. It identifies a log." |

And a `Caution` that is easy to miss, because it changes the rules halfway
through the log's life:

> "These entries are optional until you save (with the function module BAL_DB_SAVE), when OBJECT (and any SUBOBJECT) must be present."

That is a validation that moves. A program can create a log, add messages, and
display them with `OBJECT` empty and nothing will complain — the whole
in-memory path works. The requirement only applies at `BAL_DB_SAVE`, so the
failure surfaces at the end of the job, in a different method from the omission,
on the one run that actually tried to persist. If a save can ever happen, fill
`OBJECT` at `BAL_LOG_CREATE` time.

Three further consequences:

- **The index is on all three together**: "The database contains an index on the fields OBJECT/SUBOBJECT/EXTNUMBER" — and specifying them is what buys you
  "a log can be read from the database efficiently". A `SLG1` search by date and
  user across an un-objected log table is the full table scan the documentation
  is warning about.
- **`OBJECT`/`SUBOBJECT` must be configured, not invented.** They are `SLG0`
  customizing, and `BAL_OBJECT_SUBOBJECT` exists to "Check whether object and subobject exist and the combination is allowed" —
  a check worth calling once at the start of a new logging implementation
  rather than discovering the combination is rejected in production.
- **`EXTNUMBER` is a grouping key, not just a label**:
  "An external ID can also combine several logs into one logical log (logical logs can be displayed like one log)."
  Putting the document number in `EXTNUMBER` makes every log for that document
  display as one; putting a timestamp in it guarantees the opposite.

One field is pure decoration, and it is the one that sounds important —
`ALSTATE`: "A log has a status specifying whether the log is finished. It is only for information and is not used anywhere."

---

## 9. Memory, roll area, and the two different deletes

The logs you build live in the global memory of function group `SBAL`
("Application Log: Collect Messages", the group that owns `BAL_LOG_CREATE` and
`BAL_LOG_MSG_ADD`), which means they are bounded by the internal session, not
by your program. Two
practical effects:

- **A log handle does not cross an internal session.** After `SUBMIT`, in an RFC
  call, or in the update task, the handle means nothing because the function
  group memory is a different one. The documented bridge is the pair
  `BAL_GLB_MEMORY_EXPORT` / `BAL_GLB_MEMORY_IMPORT`, described as
  "Put function group memory in ABAP-MEMORY" and "Get function group memory from ABAP-MEMORY"
  — i.e. the BAL state is shipped through ABAP Memory explicitly. See
  [Program Calls & ABAP Memory](../Program%20Calls#readme) for what ABAP Memory
  does and does not survive.
- **There are two deletes and they are not alternatives.** From the module
  overview: `BAL_LOG_REFRESH` is "Delete log from memory", while `BAL_LOG_DELETE`
  is "Delete log (from database also at Save)" — the second is a *marking* that
  takes effect at the next `BAL_DB_SAVE`. `BAL_GLB_MEMORY_REFRESH` is the
  nuclear option, "(Partially) reset global memory", and it does not care which
  logs were yours.

Changing a log that is already in the database is a five-step sequence, not an
update: `BAL_DB_ENQUEUE` → `BAL_DB_LOAD` → change (`BAL_LOG_MSG_CHANGE`,
`BAL_LOG_HDR_CHANGE`, `BAL_LOG_MSG_DELETE`) → `BAL_DB_SAVE` → `BAL_DB_DEQUEUE`.
Skipping the enqueue is the classic lost-update race between a dialog user in
`SLG1` and a background job appending to the same log; see
[Enqueue Locks](../Enqueue%20Locks#readme).

---

## 10. Smaller things worth knowing

- **Detail level and problem class are the display hierarchy.** `DETLEVEL` takes
  "values from 1 to 9" and `PROBCLASS` is the four-way importance scale
  ("very important, important, medium, additional information" in the display).
  `BAL_DSP_PROFILE_DETLEVEL_GET` builds a tree from `DETLEVEL`, so choosing these
  values *is* designing the log display. `ALSORT` is free-form and
  "unrestricted".
- **Four message variables are often not enough**, and there is a documented way
  out that is not string concatenation:
  "If the long text of a T100 message is not sufficient, because you need more information than the 4 message variables, you can enter a transaction SE61 'Text in dialog' in the PARAMS-ALTEXT field."
  Placeholders then come from `PARAMS-T_PAR`. SAP's example is the routine
  `MSG_ADD_WITH_EXTENDED_LONGTEXT` in program `SBAL_DEMO_02`.
- **Callbacks let a log line open your own detail screen** —
  `PARAMS-CALLBACK` with `USEREXITT` (' ' = `FORM`, 'F' = function module),
  `USEREXITP` and `USEREXITF`. Useful, and a reason to keep context data flat
  and small.
- **There are five ready-made display profiles** (`BAL_DSP_PROFILE_STANDARD_GET`,
  `..._SINGLE_LOG_GET`, `..._NO_TREE_GET`, `..._POPUP_GET`, `..._DETLEVEL_GET`).
  Reach for these before building a field catalog by hand.
- **`BAL_MSG_DISPLAY_ABAP`** turns a collected message back into an ABAP
  `MESSAGE` ("Output message as ABAP-MESSAGE") — the bridge back to
  [Messages](../Messages#readme) behaviour, with all of that note's
  context-dependent type conversions.
- **The SAP demo programs are genuinely useful**: `SBAL_DEMO_01` (simple log),
  `SBAL_DEMO_02` (collection variants), `SBAL_DEMO_03` (searching memory),
  `SBAL_DEMO_04` (+`_SUBSCREEN`, `_CONTROL`) for display, `SBAL_DEMO_05`
  (database), `SBAL_DEMO_07` (exceptions).
- **Mind the prose-vs-signature drift** when copying from the documentation —
  see the next section.

---

## 11. The parameter the documentation names does not exist

The [Basics](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21029235d44180e10000000a15822b.html)
page says:

> "You can pass the log header data to this function module in the importing parameter I_S_LOG_HEADER with the structure BAL_S_LOG."

`BAL_LOG_CREATE` has no parameter `I_S_LOG_HEADER`. Its importing parameter is
`I_S_LOG` (type `BAL_S_LOG`), with `E_LOG_HANDLE` coming back
([signature](https://www.sapdatasheet.org/abap/func/bal_log_create.html)) — and
SAP's own [Callback Routine Overview](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21063835d44180e10000000a15822b.html)
uses the real name, telling you to set
"the field I_S_LOG-PARAMS-CALLBACK in the transfer structure I_S_LOG (structure BAL_S_LOG)".

So the first line copied from SAP's quick-start prose is a syntax error. This is
the same defect class as the `SET_RECIPIENT` that
[Sending Email (BCS)](../Email%20and%20BCS#readme) documents and the misspelled
factory class in [ABAP Channels](../ABAP%20Channels#readme): hand-written prose
pages and generated signature lists have drifted, and **only the generated one
compiles**. Check parameter names in SE37 or ADT, not in the narrative.

(A smaller instance of the same drift: the Function Module Overview lists only
`BAL_GLB_MSG_DEFAULTS_GET`, while the Basics page tells you to call
`BAL_GLB_MSG_DEFAULTS_SET`. The `_SET` module does exist — function group
`SBAL_TOOLBOX` — the overview table is simply incomplete. The same table also
describes `BAL_GLB_MEMORY_REFRESH` as "(Partially) reset global memory" in one
row and "(Partially) initialize memory" in another.)

---

## Quick reference

| You want | Do this | Because |
|---|---|---|
| A message in **your** log | always pass `I_LOG_HANDLE` | the parameter is optional and defaults to the last log created *anywhere* |
| To know a message was stored | read `E_MSG_WAS_LOGGED` | `sy-subrc = 0` only means the call did not fail |
| To log 10,000 repeats | `BAL_LOG_MSG_CUMULATE` | hard ceiling: `LOG_IS_FULL` at message 999,999 |
| The log number for your document | `E_NEW_LOGNUMBERS` after `BAL_DB_SAVE` | before the save, `LOGNUMBER` is a placeholder like `$00001` |
| A log that survives `ROLLBACK WORK` | `I_2TH_CONNECTION` + `I_2TH_CONNECT_COMMIT` | the default save is in your LUW and rolls back with it |
| A log consistent with a posted document | `I_IN_UPDATE_TASK = 'X'` | written by the same `COMMIT WORK` as the document |
| A log that is still there next month | set `DATE_DEL` | an initial expiry date is already in the past |
| An audit trail | **do not use BAL** — change documents | BAL is documented as temporary storage |
| Context on a message | character-like DDIC structure only | the container is `CHAR255`; non-character fields break in Unicode |
| To find the log in `SLG1` later | fill `OBJECT`/`SUBOBJECT`/`EXTNUMBER` | that triple is the database index |
| To save a log at all | `OBJECT` must be filled and `SLG0`-registered | the fields are optional in memory and mandatory at `BAL_DB_SAVE` |
| To change a saved log | `BAL_DB_ENQUEUE` first, `BAL_DB_DEQUEUE` last | concurrent appenders otherwise lose each other's messages |
| To clear a log from memory only | `BAL_LOG_REFRESH` | `BAL_LOG_DELETE` marks it for *database* deletion at the next save |

## Related notes in this repo

- [Messages](../Messages#readme) — what `MSGTY`/`MSGID`/`MSGNO`/`MSGV1..4` mean, and the truncation
- [Update Task](../Update%20Task#readme) — `I_IN_UPDATE_TASK`, and why update code must not commit
- [Commit Work Events](../Commit%20Work%20Events#readme) — what a `COMMIT WORK` actually triggers
- [Exception Texts](../Exception%20Texts#readme) — where `BAL_LOG_EXCEPTION_ADD` gets its text
- [Native SQL](../Native%20SQL#readme) — secondary database connections
- [Background Jobs](../Background%20Jobs#readme) — `I_LINK2JOB`, and logging from a job
- [Enqueue Locks](../Enqueue%20Locks#readme) — the lock around changing a saved log
- [Program Calls & ABAP Memory](../Program%20Calls#readme) — why a log handle does not cross a `SUBMIT`
- [Field Symbols](../Field%20Symbols#readme) / [File Interface](../File%20Interface#readme) — the `ASSIGN ... CASTING` pattern
- [Sending Email (BCS)](../Email%20and%20BCS#readme) / [ABAP Channels](../ABAP%20Channels#readme) — the same prose-vs-signature drift

## Sources

All Application Log pages below are from the BC-SRV-BAL deliverable on the SAP
Help Portal (shown here on the NetWeaver 7.5 docset; the same text is served in
the S/4HANA and ABAP Platform docsets).

- [Application Log – Guidelines for Developers (BC-SRV-BAL)](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21000f35d44180e10000000a15822b.html) — temporary storage, use change documents for audit, `SBAL_DOCUMENTATION`
- [Basics](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21029235d44180e10000000a15822b.html) — handle semantics, the optional-handle `Note`, exception limitations, `I_S_LOG_HEADER`
- [Which Data Can Be Collected?](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e2106b735d44180e10000000a15822b.html) — `BAL_S_LOG` / `BAL_S_MSG` / `BAL_S_EXC` field semantics, the index, `ALSTATE`, `DATE_DEL` / `DEL_BEFORE`, extended long text, callbacks
- [Database Interface](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21021635d44180e10000000a15822b.html) — `BAL_DB_SAVE`, temporary `LOGNUMBER`, `E_NEW_LOGNUMBERS`, update task
- [Function Module Overview](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e23b1720771417fe10000000a15822b.html) — full module map, change-log sequence, roll-area-independent working
- [Application Log and Unicode](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21018a35d44180e10000000a15822b.html) — the `CHAR255` context container and the two supported fixes
- [Deleting Logs](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21053535d44180e10000000a15822b.html) — `SLG2`, expiry rules, archiving object `BC_SBAL`
- [Callback Routine Overview](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21063835d44180e10000000a15822b.html) — `BAL_CALLBACK_*`, and the real `I_S_LOG` name
- [Log Display](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e2102fa35d44180e10000000a15822b.html) / [Displaying Logs](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21041a35d44180e10000000a15822b.html) / [Analyze Logs](https://help.sap.com/docs/SAP_NETWEAVER_750/addb96cd90c945dfb3182865363bbc47/4e21048535d44180e10000000a15822b.html) — profiles, navigation tree, `SLG1` selection
- [Return Parameters (Error Handling), BAPI Programming Guide](https://help.sap.com/doc/saphelp_snc70/7.0/en-US/a5/3ec9f74ac011d1894e0000e829fbbd/content.htm) — no `COMMIT WORK` means no log; write logs via the update task; `LOG_NO` / `LOG_MSG_NO`
- Generated signatures (parameter names, optional flags, defaults and short texts): [`BAL_LOG_CREATE`](https://www.sapdatasheet.org/abap/func/bal_log_create.html), [`BAL_LOG_MSG_ADD`](https://www.sapdatasheet.org/abap/func/bal_log_msg_add.html), [`BAL_LOG_MSG_ADD_FREE_TEXT`](https://www.sapdatasheet.org/abap/func/bal_log_msg_add_free_text.html), [`BAL_DB_SAVE`](https://www.sapdatasheet.org/abap/func/bal_db_save.html), [`BAL_GLB_MSG_DEFAULTS_SET`](https://www.sapdatasheet.org/abap/func/bal_glb_msg_defaults_set.html)

Demo program: [`ydj_appl_log_demo.abap`](ydj_appl_log_demo.abap)
