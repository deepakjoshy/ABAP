# Sending email from ABAP (BCS) — the `COMMIT WORK` that is your job, the subject silently cut at 50, and the `SET_RECIPIENT` that does not exist

Every SAP system sends mail, and almost every ABAP developer copies the send
routine from somewhere else. The copy usually works on the first try, which is
the problem: the parts that are wrong do not raise, do not set `sy-subrc`, and
do not show up in a test system. SAP says so itself, in a `Caution` box:

> "The occurrence of the error depends on the send infrastructure, so the error does not occur in all tests."

That sentence is about the missing `COMMIT WORK`, and it is the whole reason
this note exists.

## The cast

| Object | Role | Created by |
|---|---|---|
| `CL_BCS` | the send request — the envelope | `CREATE_PERSISTENT` (static) |
| `CL_DOCUMENT_BCS` | the document — body, subject, attachments | `CREATE_DOCUMENT` / `CREATE_FROM_TEXT` (static) |
| `CL_CAM_ADDRESS_BCS` | an external address (mail, fax, SMS, RML) | `CREATE_INTERNET_ADDRESS` (static) |
| `CL_SAPUSER_BCS` | an internal SAP user | constructor |
| `CL_BCS_CONVERT` | `STRING`/`XSTRING` to the 255-character tables BCS wants | static methods |

`CL_CAM_ADDRESS_BCS` is both ends of the wire — the page states it
"has implemented the interfaces IF_RECIPIENT_BCS and IF_SENDER_BCS", so the
same class builds the sender and the recipient. Senders and recipients that
can only be recipients are listed separately: `CL_DISTRIBUTIONLIST_BCS`,
`CL_BOR_OBJECT_BCS`, `CL_SAPROLE_BCS`.

---

## Trap 1: `COMMIT WORK` is the application's job, and nothing tells you it is missing

This is the headline. The process description ends with a plain instruction:

> "You must set a COMMIT WORK explicitly at an appropriate point."

and then a `Caution` that explains the mechanism:

> "The application must set the COMMIT WORK itself. Otherwise, the Persistence Services of Object Services are not started and essential send data is missing, which can lead to the termination of the send operation."

`CREATE_PERSISTENT` is named after exactly this: the send request is a
persistent object, and a persistent object is written by Object Services at
commit time. No commit, no row, no mail. The method reference describes it in
one line — "This method is used to create a persistent send request."

What makes this a trap rather than a rule is the next sentence of the same
`Caution`:

> "The occurrence of the error depends on the send infrastructure, so the error does not occur in all tests."

So the routine you copied may well have been genuinely broken in its original
program too, and nobody noticed. SAP even gives you the diagnostic string to
look for in the SAPconnect internal trace (`SCOT` -> `Utilities` -> `Trace`).
There should be no entry of this type:

> "No Send Request Created. Error Code:NI_SREQ"

### The two exceptions, and the inversion

> "Excepted are those applications that use the Transaction Service of Object Services and call a send interface within an OO transaction. Applications that call the send interface during update are also excepted, of course."

Read the second one twice. If your send code runs **in the update task**, the
commit has already happened and is being executed around you — so there you
must **not** write `COMMIT WORK`, and doing it anyway is an error rather than a
belt-and-braces precaution. The rule therefore reverses depending on where the
code sits, and the same utility method called from a report and from a V1
update module needs opposite handling. See [Update Task](../Update%20Task#readme)
for why a `COMMIT WORK` inside update processing is illegal, and
[Commit Work Events](../Commit%20Work%20Events#readme) for the event side.

The practical consequence for the awkward contexts — a BAdI, a user exit, a
`PERFORM ... ON COMMIT` routine — is that you cannot commit there either, so
the send has to be pushed into its own unit of work. The established shape is
a function module marked remote-enabled, called `IN BACKGROUND TASK` or with
`DESTINATION 'NONE'`, that does the BCS calls and its own `COMMIT WORK`.
See [RFC Calls](../RFC%20Calls#readme) for what `DESTINATION 'NONE'` actually
does to the LUW.

---

## Trap 2: `SEND` returns a flag, and the flag does not mean what it reads like

The method reference gives `SEND` one importing parameter and one returning
parameter, and describes both in a single line each:

> "I_WITH_ERROR_SCREEN (optional) Indicator denoting whether the send log book is to be returned in the event of an error"

> "RESULT Indicator denoting whether the sending was successful"

Three separate problems live in those two lines.

**The return value is not a `sy-subrc`, and it is not a `BOOLEAN`.** It is
typed `OS_BOOLEAN`, a one-character field, so it has to be compared against
`abap_true` — and like every character flag in ABAP, `IF lv_sent IS NOT
INITIAL` and `IF lv_sent = abap_true` are the same test only as long as nobody
puts anything else in it. The repository short text for the parameter is still
in German: "Flag zeigt an, ob erfolgreich gesendet wurde".

**"Successful" means handed over, not delivered.** By default BCS does not talk
to a mail server at all; it queues the message for the SAPconnect send process,
which is a scheduled job. The opt-out is a method whose own short text says so:

> "(De)Activates Immediate Sending Without Send Process"

`SET_SEND_IMMEDIATELY` takes `I_SEND_IMMEDIATELY` typed `OS_BOOLEAN`, described
(again in German) as "'X' = einschalten, ' ' = ausschalten". So there are three
different states a developer reads as "sent":

| State | What actually happened |
|---|---|
| `SEND` returned `abap_true` | the send request was accepted |
| `COMMIT WORK` ran | the request is on the database and visible in `SOST` |
| the SAPconnect job ran | the message was handed to the mail server |

Only the third one puts mail on the wire, and none of them is delivery. If the
send job is not scheduled in a system — which is the normal state of a fresh
sandbox — every message in `SOST` sits in a waiting status forever while the
program reports success.

**The error screen is a screen.** `I_WITH_ERROR_SCREEN` returns the send log
book *as a dialog*. In a background job or an update module there is nobody to
look at it, and the default is `SPACE`, so leave it alone and catch the
exception instead. Error handling here is class-based only: the method raises
`CX_SEND_REQ_BCS`, and the reference describes `SEND` as the non-dialog path —
"You use this method to send an object if this does not occur in dialog
processing." The interactive counterpart is `EDIT`, which opens the send screen
and lets the user press the button; `SEND` never shows anything.

---

## Trap 3: there are two subjects, with two different limits, and one of them is ignored on some nodes

The subject you pass to the document is a DDIC field, not a string. For both
`CREATE_DOCUMENT` and `CREATE_FROM_TEXT` the parameter is documented as:

> "Title of the document (maximum length 50)."

`I_SUBJECT` is typed `SO_OBJ_DES`. A 50-character fixed-length field does not
complain about a longer value — assignment truncates, silently, with no
`sy-subrc` and no message. A subject like
`Invoice 4711 for customer 10023 could not be posted` is already over the
line, and what arrives is the front half of it.

The fix is a second, separate subject on the **send request** rather than the
document. `SET_MESSAGE_SUBJECT` takes `IP_SUBJECT` typed `STRING`, and its
repository short text contains both halves of the catch:

> "Sets Message Subject (Max. 255 Characters, SMTP Nodes Only)"

So: 255, not unlimited, despite the `STRING` type — and **SMTP nodes only**.
Send the same message to a fax node, an internal SAP user, or a Business
Workplace folder and the long subject is not used; what those recipients see is
the 50-character document title. A mail routine that serves both internal and
external recipients therefore needs the short subject to be meaningful on its
own, not a truncated prefix of the long one.

Rule of thumb: set both, keep the document title short and self-contained,
and never compute one from the other.

---

## Trap 4: the method SAP tells you to call does not exist

Two pages of the BCS documentation walk you through building a send request.
Both of them name the same method for attaching a recipient:

> "You then pass this instance to BCS with the method SET_SENDER or SET_RECIPIENT of the class CL_BCS. If you want to pass several recipients, you have to call the method SET_RECIPIENT for each recipient."

`SET_SENDER` is real. `SET_RECIPIENT` is not. The method reference for the
class itself documents the recipient method as `ADD_RECIPIENT`:

> "You use this method to pass a recipient to the send request. You have to call this method for every recipient."

and the repository short text is "Adds Recipient (Entry) to Send Request".
There is no `SET_RECIPIENT` in `CL_BCS`. This matters only because the page
that gets read first is the narrative process page, not the method list — so
the failure is a syntax error on a line that was copied from SAP's own
documentation. It is the same class of defect as the misspelled factory class
noted in [ABAP Channels](../ABAP%20Channels#readme): the prose pages and the
generated method lists drifted apart, and only the generated one is binding.

The `ADD_` prefix is also the honest one. `ADD_RECIPIENT` accumulates, so
calling it in a loop is correct and there is no list-valued variant; the
send attributes are per call:

| Parameter | Effect |
|---|---|
| `I_EXPRESS` | "Indicator for the send attribute Express" |
| `I_COPY` | "Indicator for the send attribute Copy" — the CC line |
| `I_BLINDCOPY` | "Indicator for the send attribute Blind copy" — BCC |
| `I_NO_FORWARD` | "Indicator for the send attribute No forwarding" |

A recipient with no flag is a TO recipient. There is no `I_TO`.

---

## Trap 5: `SOLI_TAB` is two incompatible formats wearing the same type

The body goes in as a table, not a string. Both text parameters are documented
identically:

> "Content of the document as text, which is passed in a table with lines of length 255."

Nothing in that sentence says what a *line* is, and that is where the bodies
that arrive as one unbroken paragraph — or broken mid-word every 255
characters — come from. `CL_BCS_CONVERT` is the class that gives the game
away, because its method short texts distinguish two kinds of `SOLI_TAB` that
the type system does not:

| Method | Source | Target |
|---|---|---|
| `RAW_TO_STRING` | "Line-Oriented Text (SOLI)" | "Running Text (STRING)" |
| `TXT_TO_STRING` | "Running Text (SOLI)" | "Running Text (STRING)" |
| `STRING_TO_SOLI` | "Running Text (STRING)" | "Running Text (SOLI)" |

- **Line-oriented** (`RAW_*`): one table row is one displayed line. This is
  what a `RAW` document body is, and what `APPEND 'My line' TO lt_body` builds.
- **Running text** (`TXT_*`): the rows are 255-character chunks of one
  continuous stream, with no meaning at the row boundary.

Both are `SOLI_TAB`. The compiler cannot tell them apart, so
`STRING_TO_SOLI` output fed straight into `CREATE_DOCUMENT( i_text = ... )`
with the default document class is a category error that activates cleanly:
running text is read back as if every chunk were a line. For a plain-text mail
built in ABAP, append the lines yourself; use the converter when the content
genuinely is one long stream (HTML is the normal case, and there `i_type` is
`'HTM'`).

The document class itself is the other half of this. `I_DOCUMENTTYPE` on
`CREATE_FROM_TEXT` is described as

> "Document class, with PC documents the file extension (see table TSOTD). The default value is 'RAW'."

so an HTML body that forgets `i_type` is sent as plain text and the recipient
reads the tags.

---

## Trap 6: the attachment size is documented as optional and is not

For binary attachments the content parameter is a 255-**byte** table:

> "Content of the document in binary form, which is passed in a table with lines of length 255."

and the length sits beside it as an afterthought:

> "Size of the document in bytes."

marked `(optional)`. A `SOLIX_TAB` cannot express the length of its own
content: the last row is a full 255-byte row whatever the real tail is. Omit
`I_ATTACHMENT_SIZE` and the receiver gets the padding as part of the file — a
PDF or XLSX that is up to 254 bytes too long, which most readers either repair
silently or refuse outright, long after the ABAP side reported success.

The proof that it is not optional is in the converter signature.
`CL_BCS_CONVERT=>STRING_TO_SOLIX` has **two exporting** parameters, not one:

| Parameter | Direction | Type | Note |
|---|---|---|---|
| `ET_SOLIX` | exporting | `SOLIX_TAB` | the padded table |
| `EV_SIZE` | exporting | `SO_OBJ_LEN` | the real byte count, to pass straight to the size |
| `IV_STRING` | importing | `STRING` | the content |
| `IV_CODEPAGE` | importing | `ABAP_ENCOD` | target encoding (`4110` is UTF-8) |
| `IV_ADD_BOM` | importing | `OS_BOOLEAN` | prefix a byte order mark |

`EV_SIZE` exists for exactly one reason: so you can hand it to
`I_ATTACHMENT_SIZE`. `BIN_TO_SOLIX` carries the same idea in its short text,
which ends "(incl. Length)".

`IV_ADD_BOM` is the CSV-opens-as-mojibake-in-Excel fix, and the same byte
order mark trap documented in [File Interface](../File%20Interface#readme) —
three bytes that are either invisible metadata or the first field of your
first record, depending entirely on who opens the file.

---

## Smaller things that cost an afternoon

- **Attachments cannot nest.** The `ADD_ATTACHMENT` entry carries its own
  `Note`: "Attaching documents that have attachments themselves is not
  supported in this release." Forwarding a received mail with its attachments
  as a single attachment is therefore not a BCS operation.
- **Inline images are possible, but not through `CREATE_DOCUMENT`.** The method
  for that is `CREATE_FROM_MULTIRELATED`: "This method enables you to create
  BCS documents for the MIME type Multipart/Related." It needs the helper class
  `CL_GBT_MULTIRELATED_SERVICE`, and SAP ships a worked example —
  "See the report RSSOHTMLGIF for an implementation example."
- **Priority 9 is not just low priority.** `SET_PRIORITY` is short-texted
  "Sets Send Priority: '9' = Mass Mail", while the document-level attribute
  with the same digits is plain importance: "possible values: 1 - high
  priority, 5 - medium priority, 9 low priority". The same `9` means
  *deprioritise this in the send queue* on the request and *show a down arrow*
  on the document.
- **There is a one-call shortcut.** "You can send a short message with one or
  more attachments to one or more recipients in one step by calling the method
  SHORT_MESSAGE of the class CL_BCS." It is not configuration-free, though —
  it silently adopts a set of defaults: "The standard settings (move to outbox
  according to private office settings in SO12, request all status
  confirmations, request status confirmation as mail only in the event of
  error) are used in this."
- **Nothing is sent to the sender by default.** The sender is the current user
  unless you set one, and a user with no email address in `SU01` produces mail
  with a sender nobody can reply to. `CREATE_INTERNET_ADDRESS` takes an
  optional display name as well as the address: "Name that is displayed for the
  Internet address, for example Pia Brown".
- **The example reports are worth reading before writing anything.**
  "Programs BCS_EXAMPLE_1 to 5 (send text to Internet address, on its own,
  with attachment, with note, and with recipient input in dialog)" — and every
  one of them contains the `COMMIT WORK` from trap 1.

---

## The cloud version inverts the model

If this code is going to ABAP Cloud, none of the above transfers. The ABAP
environment documentation does not mention `CL_BCS`; the API it names is
`CL_BCS_MAIL_MESSAGE`, with `CL_BCS_MAIL_TEXTPART` and
`CL_BCS_MAIL_BINARYPART` for the parts. Two differences matter more than the
renaming:

**Sending is synchronous now.** "With the send method of the API, the mail is
sent via the mail server configured in the destination using the cloud
connector. Sending is performed synchronously." The classic model — queue it,
commit, let a job pick it up — is gone, and with it the whole class of
missing-`COMMIT WORK` bugs. In exchange, the mail server latency is now inside
your dialog step.

**The asynchronous path is the explicit one.** "An email can be sent
asynchronously with the method SEND_ASYNC", and the documentation gives the
reason in LUW terms: "because you want to send an email when the COMMIT WORK
statement is triggered at the end of a successful transaction". So the
behaviour that classic BCS gave you by accident is the one you now have to ask
for by name — which is the better design and the reason a straight port of a
`CL_BCS` routine changes when the mail goes out.

Body parts are also structured rather than typed-by-string: "A main body part
(SET_MAIN) must be set and additional body parts can be set as attachments
(ADD_ATTACHMENT) or alternatives (ADD_MAIN_ALTERNATIVE)". The alternative is
the HTML-plus-plain-text pair that classic BCS could only build through
`CREATE_FROM_MULTIRELATED`. See
[ABAP Language Versions](../ABAP%20Language%20Versions#readme) for why the old
classes are simply not callable there.

---

## The shape that is actually correct

```abap
DATA lt_body TYPE soli_tab.

TRY.
    DATA(lo_request) = cl_bcs=>create_persistent( ).

    " line-oriented: one APPEND is one line of the mail (trap 5)
    APPEND 'Order 4711 could not be posted.' TO lt_body.
    APPEND 'Please check the application log.' TO lt_body.

    DATA(lo_document) = cl_document_bcs=>create_document(
        i_type    = 'RAW'                 " 'HTM' for an HTML body
        i_text    = lt_body
        i_subject = 'Order 4711 not posted' ).  " SO_OBJ_DES, 50 (trap 3)

    lo_request->set_document( lo_document ).

    " the long subject lives on the REQUEST, and only reaches SMTP nodes
    lo_request->set_message_subject(
        'Order 4711 could not be posted - credit limit exceeded' ).

    " ADD_, not SET_ (trap 4). No flag at all means a TO recipient.
    lo_request->add_recipient(
        i_recipient = cl_cam_address_bcs=>create_internet_address(
                          i_address_string = 'team@example.com' ) ).

    DATA(lv_sent) = lo_request->send( ).         " OS_BOOLEAN, not sy-subrc

    " trap 1 - and NOT here if this code runs in the update task
    COMMIT WORK.

    IF lv_sent <> abap_true.
      " accepted by nobody: the request exists, the send did not start
    ENDIF.

  CATCH cx_bcs INTO DATA(lx_bcs).
    " the ONLY error channel - there is no sy-subrc to read.
    " CX_SEND_REQ_BCS, CX_DOCUMENT_BCS and CX_ADDRESS_BCS all have
    " CX_BCS as their superclass, so one CATCH covers the lot.
    MESSAGE lx_bcs->get_text( ) TYPE 'E'.
ENDTRY.
```

Four lines in that block are the note: the `APPEND` style, the two subjects,
`ADD_` instead of `SET_`, and the `COMMIT WORK` whose correctness depends on
the caller.

`set_send_immediately( abap_true )` is deliberately absent. Adding it bypasses
the send process entirely, which means your program waits for the mail server
and inherits its failures; the queue exists so that a slow or down SMTP host
does not become a slow or failed business transaction. Use it when the user is
staring at the screen waiting for the mail, not as a default.

---

## The demo report

[`ydj_bcs_mail_demo.abap`](ydj_bcs_mail_demo.abap) proves the three traps that
can be proved **without sending anything**: the 50-character truncation, the
line-oriented vs running-text split, and the 255-byte padding that
`I_ATTACHMENT_SIZE` exists to correct. It then builds a complete send request
and stops: `SEND` and `COMMIT WORK` run only if you tick a checkbox on the
selection screen, because a demo report that mails strangers is a bad demo
report. No database access, no writes.

---

## Sources

- SAP Help, *Connection to the Interface* (BCS) — the process walkthrough, the
  `COMMIT WORK` `Caution`, the `NI_SREQ` trace string, `SHORT_MESSAGE`
  defaults, the `BCS_EXAMPLE_*` list:
  <https://help.sap.com/doc/saphelp_gbt10/1.0/en-US/4d/3655e09b034b89e10000000a42189c/content.htm>
- SAP Help, *CL_BCS* — method reference, `SEND` parameters, `ADD_RECIPIENT`:
  <https://help.sap.com/saphelp_ewm900/helpdata/en/4d/353db0d2512304e10000000a15822b/content.htm>
- SAP Help, *CL_DOCUMENT_BCS* — the 50-character title, the 255-character
  tables, `I_ATTACHMENT_SIZE`, the no-nested-attachments note,
  `CREATE_FROM_MULTIRELATED` and `RSSOHTMLGIF`:
  <https://help.sap.com/doc/saphelp_gbt10/1.0/en-US/4d/2f022502e7230ae10000000a15822b/content.htm>
- SAP Help, *CL_CAM_ADDRESS_BCS* — `CREATE_INTERNET_ADDRESS` and the fax/SMS/RML
  variants:
  <https://help.sap.com/doc/saphelp_gbt10/1.0/en-US/4d/354674d2512304e10000000a15822b/content.htm>
- SAP Help, *Senders and Recipients* — the sender/recipient class list, and the
  `SET_RECIPIENT` wording of trap 4:
  <https://help.sap.com/doc/saphelp_gbt10/1.0/en-US/4d/3508df467e6e4ae10000000a42189c/content.htm>
- SAP Help, *Sending Mails Using SMTP* (ABAP environment) —
  `CL_BCS_MAIL_MESSAGE`, synchronous sending, `SEND_ASYNC`, body parts:
  <https://help.sap.com/docs/sap-btp-abap-environment/abap-environment/output-management-sending-mails-using-smtp>
- Repository signatures and short texts for `CL_BCS`, `CL_DOCUMENT_BCS` and
  `CL_BCS_CONVERT` (`SET_MESSAGE_SUBJECT` 255/SMTP-only,
  `SET_SEND_IMMEDIATELY`, `SET_PRIORITY`, `EV_SIZE`, the
  line-oriented/running-text split): SAP Datasheet class pages,
  <https://www.sapdatasheet.org/abap/clas/cl_bcs.html>

## Related notes in this repo

- [Update Task](../Update%20Task#readme) — why `COMMIT WORK` is illegal inside
  update processing, which is the inversion in trap 1
- [Commit Work Events](../Commit%20Work%20Events#readme) — `PERFORM ... ON
  COMMIT` and the event side of the same LUW
- [RFC Calls](../RFC%20Calls#readme) — `DESTINATION 'NONE'` and
  `IN BACKGROUND TASK`, the standard escape hatch for sending from a BAdI
- [File Interface](../File%20Interface#readme) — the byte order mark, from the
  other side of the same problem
- [Byte Strings](../Byte%20Strings#readme) — `XSTRING`, code pages and what
  `IV_CODEPAGE` is choosing
- [HTTP Client](../HTTP%20Client#readme) — the other outbound channel, with the
  same it-committed-your-LUW surprise
- [Background Jobs](../Background%20Jobs#readme) — where the SAPconnect send
  process lives
- [ABAP Language Versions](../ABAP%20Language%20Versions#readme) — why none of
  these classes exist in ABAP Cloud

