# ABAP EML — the `MODIFY` that changes nothing, the `sy-subrc` that decides whether you may carry on, and the update that is never asynchronous

ABAP EML (Entity Manipulation Language) is how a plain ABAP program — a report,
a job, a unit test, a class method — talks to a RAP business object. The
statements read like ABAP SQL and they are not ABAP SQL. They do not write to a
table, they do not raise exceptions on failure, and they do not set `sy-subrc`
except in one place where its meaning is easy to get backwards.

This note is about the **consumer** side: the code you write outside a behavior
pool. It is not an introduction to RAP, behavior definitions or draft handling.
It is the set of things that are true about `READ ENTITY`, `MODIFY ENTITY`,
`COMMIT ENTITIES` and `ROLLBACK ENTITIES` that a developer arriving from
classical `INSERT`/`UPDATE`/`COMMIT WORK` will get wrong on the first attempt:

- a `MODIFY` with no `COMMIT ENTITIES` changes **nothing** on the database — and
  a following `READ ENTITY` still shows the change, because EML reads the
  transactional buffer too. Only a plain `SELECT` tells you the truth;
- the *same* `COMMIT ENTITIES` is **mandatory** in a report and **must not be
  called** from a Fiori/OData app or a behavior pool. Whether your code is
  correct depends on who calls it;
- after `COMMIT ENTITIES`, `sy-subrc` 4 and 8 both mean "not saved" — but 4
  leaves your work in the buffer and 8 has already thrown it away, and
  continuing after an 8 without `ROLLBACK ENTITIES` can be a **runtime error**;
- a failed `MODIFY` produces no exception and no `sy-subrc`. The entire error
  channel is the optional `FAILED` parameter, and the only thing the compiler
  says if you omit it is a warning you can switch off with a pragma;
- `COMMIT ENTITIES` is **all or nothing** — one invalid instance loses the whole
  batch, where classical ABAP SQL would have kept the rows that worked;
- the resulting update is **never asynchronous**, whatever you learned about V1
  and V2 update modules;
- and the `WHERE` clause of a projection view is **ignored** by EML by default,
  which the documentation itself calls a security risk.

Everything below is quoted from the ABAP keyword documentation. The runnable
counterpart is `ydj_eml_traps_demo.abap` in this folder; it deliberately never
issues a `COMMIT ENTITIES`, so it cannot persist anything.

**Availability.** ABAP EML requires a RAP-capable release (ABAP Platform /
ABAP Cloud, 7.54 and later). The demo additionally needs the SAP-delivered demo
business object `DEMO_MANAGED_ROOT` from the ABAP demo content; on a system
without it, point the statements at a BDEF of your own.

## 1. No `COMMIT ENTITIES`, no database change — and `READ ENTITY` will not tell you

This is the first thing that happens to everybody. The `MODIFY` runs, `FAILED`
comes back empty, and the table is unchanged.

> *"If ABAP EML modify statements are used outside of behavior pools, for
> example, in ABAP programs, a `COMMIT ENTITIES` statement is necessary to
> persist data to the database. If the statement is not provided, there would
> not be any effect on the database because the modify operations are only
> performed on the transactional buffer. Hence, a manual triggering of the save
> sequence is required. This is valid for all modify operations."*
>
> *"At the end of an ABAP session, the saving of changed or created data to the
> database must be triggered, which is done by `COMMIT ENTITIES` statements.
> Otherwise, the changes are lost."*
>
> — [`MODIFY ENTITY, ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMODIFY_ENTITY_ENTITIES.html)
> and [`COMMIT ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCOMMIT_ENTITIES.html)

So far so ordinary — a buffer that needs flushing. The trap is in **how you
check**. The obvious verification is to read the instance back with EML, and
that confirms a write that is about to be lost:

> *"From a RAP BO consumer perspective, the returned data of read operations
> include the current transactional image, i. e. the currently persisted values
> in the database and, additionally, the still unsaved changes from the current
> LUW."*
>
> — [`READ ENTITY, ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPREAD_ENTITY_ENTITIES.html)

`READ ENTITY` is not a database read. It is a read of *database plus buffer*,
which is exactly what you want in business logic and exactly the wrong
instrument for answering "did that actually save?". In a test, assert with a
plain `SELECT`.

A related point, since it sends people looking for a result parameter that does
not exist:

> *"RAP modify standard operations do not return result parameters, whereas
> non-standard operations do so. The changed data can be read via a subsequent
> ABAP EML `READ` statement."*
>
> — [`MODIFY ENTITY, ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMODIFY_ENTITY_ENTITIES.html)

A `CREATE` hands you back no row. For a generated key you need `MAPPED`
(section 6); for the stored values you need a second `READ`.

## 2. The same `COMMIT ENTITIES` is required in a report and forbidden in a Fiori app

`COMMIT ENTITIES` is not a statement you can add defensively "just in case".
Its correctness is decided by the caller, not by the code containing it.

> *"`COMMIT ENTITIES` statements can be used for RAP modify operations by RAP BO
> consumers to trigger the data persistency but they cannot be used in ABAP
> behavior pools in ABAP. In case of a natively supported RAP scenario (for
> example, an SAP Fiori app using OData), the `COMMIT ENTITIES` call is not to
> be used since it is performed implicitly and automatically by the RAP
> transactional engine."*
>
> *"`COMMIT ENTITIES` statements are not allowed in RAP BO providers."*
>
> — [`COMMIT ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCOMMIT_ENTITIES.html)

`ROLLBACK ENTITIES` splits the same way:

> *"`ROLLBACK ENTITIES` cannot be called within the RAP BO implementation."*
>
> *"In case of a natively supported RAP scenario (for example, OData), the
> `ROLLBACK ENTITIES` call is performed by RAP. In other cases, for example,
> manually implemented services or applications, the `ROLLBACK ENTITIES` call
> must be done explicitly."*
>
> — [`ROLLBACK ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPROLLBACK_ENTITIES.html)

The practical consequence: a helper class that wraps "create a document and save
it" is reusable from a report and **not** reusable from a behavior
implementation. Transaction control belongs at the top of the call stack, and in
RAP that is not a style preference — the lower layers are not allowed to have it.

`MODIFY` itself has a narrower but similar restriction inside the provider:

> *"A RAP BO provider must not use ABAP EML `MODIFY` statements in the RAP saver
> methods `check_before_save`, `adjust_numbers`, `save`, `save_modified` and
> `cleanup`. The statements can only be used in the RAP interaction phase and in
> the `finalize` saver method in the RAP save sequence. Furthermore, ABAP EML
> `MODIFY` statements are not allowed in read-only RAP handler methods."*
>
> — [`MODIFY ENTITY, ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMODIFY_ENTITY_ENTITIES.html)

## 3. `sy-subrc` 4 and 8 both mean "not saved". Only one of them lets you continue

`COMMIT ENTITIES` is the one EML statement that sets `sy-subrc`, and the
documentation is explicit that success is not guaranteed:

> *"Note that when using `COMMIT ENTITIES` statements, it is not guaranteed that
> the implicit `COMMIT WORK` will be carried out successfully."*
>
> — [`COMMIT ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCOMMIT_ENTITIES.html)

The full table, transcribed:

| `sy-subrc` | Meaning (documented) |
|---|---|
| `0` | *"The implicit `COMMIT WORK` has been carried out successfully"* |
| `4` | Failure in the **early** phase of the save sequence (`finalize`, `check_before_save`). *"The value 4 for `sy-subrc` means that there are responses returned by the `failed` parameter because of failures in the RAP save sequence. Transactional changes successfully executed in the RAP interaction phase remain in the transactional buffer."* |
| `8` | Failure in the **late** phase (`save` or `save_modified`). *"Such an issue can produce inconsistencies which triggers the clearing of the transactional buffer and a `ROLLBACK WORK` internally. A subsequent RAP modify operation can then lead to a runtime error. If the RAP BO consumer is to proceed after an issue in the late phase of the RAP save sequence, an explicit `ROLLBACK ENTITIES` is required."* |
>
> — [`COMMIT ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCOMMIT_ENTITIES.html)

Read that difference carefully, because the usual `IF sy-subrc <> 0` collapses
it into one branch and the two halves need opposite handling:

- **4** — your work is still in the transactional buffer. You may fix the
  offending instance and commit again. Issuing a `ROLLBACK ENTITIES` here throws
  away work you did not have to lose.
- **8** — the buffer has already been cleared and a `ROLLBACK WORK` has already
  happened behind your back. The session is in a state where *the next* EML
  modify can dump, and the only documented way out is an explicit
  `ROLLBACK ENTITIES` — a rollback of something that was already rolled back,
  issued purely to put the RAP runtime back into a usable state.

A loop that processes documents one at a time and logs-and-continues on
`sy-subrc <> 0` therefore works fine until the first late-phase failure, after
which it can dump on an unrelated later document.

Note also that the `sy-subrc` table above is scoped:

> *"The following statements are only valid for `COMMIT ENTITIES` statements
> terminating RAP transactions that include RAP modify operations."*
>
> — [`COMMIT ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCOMMIT_ENTITIES.html)

and that the check is not optional in practice:

> *"When using `COMMIT ENTITIES` statements, a check of `sy-subrc` should be
> included to avoid syntax warnings. If responses are retrieved, it is
> recommended that the response parameter `failed` is checked so as to react
> accordingly."*
>
> — [`COMMIT ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCOMMIT_ENTITIES.html)

## 4. A failed `MODIFY` is not an exception, not a `sy-subrc`, and not reported unless you ask

`MODIFY ENTITY` does not set `sy-subrc` and does not raise. If an instance is
rejected — locked, unauthorized, failing a precheck, violating feature control —
the only place that is visible is a response parameter you have to request.

> *"If there is no response returned, for example, an operation is successful,
> there are no entries in the `failed_resp` parameter."*
>
> — [ABAP EML - `response_param`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPEML_RESPONSE.html)

An empty `FAILED` means success. **No** `FAILED` means you have no idea. And
the compiler's objection to that is a warning with a documented off-switch:

> *"In case of a non-dynamic ABAP EML `MODIFY` statement without the addition
> `IN LOCAL MODE` and without specifying the `FAILED` response parameter, it is
> recommended that the `FAILED` response parameter is specified and that proper
> error handling on the RAP BO consumer side is implemented. Otherwise, a syntax
> warning occurs, which can be suppressed using the pragma
> `##EML_FAILED_MISSING_OK`."*
>
> — [ABAP EML - `response_param`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPEML_RESPONSE.html)

That pragma is worth recognising in a code review: it is a statement that
somebody read the warning and decided not to handle errors.

Not every statement offers every response. The matrix:

| EML statement | `FAILED` | `MAPPED` | `REPORTED` |
|---|---|---|---|
| `MODIFY ENTITY, ENTITIES` | x | x | x |
| `READ ENTITY, ENTITIES` | x | — | x |
| `COMMIT ENTITIES` | x | — | x |
| `GET PERMISSIONS` | x | — | x |
| `SET LOCKS` | x | — | x |

— [ABAP EML - `response_param`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPEML_RESPONSE.html)

And one variant has no error channel at all:

> *"For `MODIFY` statements with the addition `AUGMENTING`, the additions
> `FAILED`, `MAPPED` or `REPORTED` cannot be used."*
>
> — [ABAP EML - `response_param`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPEML_RESPONSE.html)

The three parameters are deep structures — one nested internal table per entity
of the BO — typed with `TYPE RESPONSE FOR ...` and constructible inline with
`DATA(...)`. `FAILED` carries `%fail` (the cause, e.g.
`if_abap_behv=>cause-locked`, `-not_found`, `-unauthorized`, `-unspecific`);
`REPORTED` carries `%msg`, which is *"of type `REF TO if_abap_behv_message`"*.
`FAILED` tells you *that* and *why* in coarse terms; `REPORTED` carries the text
a user should see. Logging only one of them loses half the story.

## 5. `COMMIT ENTITIES` is all or nothing

> *"However, `COMMIT ENTITIES` follows an all or nothing approach, i. e. either
> all instances are valid and correct and all can be saved or none can be saved
> if at least one instance is invalid."*
>
> — [`COMMIT ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCOMMIT_ENTITIES.html)

This inverts the habit built on classical ABAP SQL, where a mass `INSERT` with
`ACCEPTING DUPLICATE KEYS` or a row-by-row loop keeps what succeeded. Bundle
10,000 creates into one RAP transaction and one bad instance costs you all
10,000. Chunking is therefore not only a memory decision, it is the unit of
failure — and the chunk boundary has to sit where a partial save is
*business-wise* acceptable, not merely where the memory is comfortable.

Note the interaction with section 3: a `sy-subrc` of 4 leaves the whole failed
batch in the buffer, so "remove the bad instance and commit the rest" is a real
recovery path, which is a good reason to keep `FAILED` and feed it back in
rather than restarting the run.

## 6. `%cid`, and the key you only find out about through `MAPPED`

`%cid` is a content ID: a caller-invented, request-local handle for an instance
that does not have a primary key yet.

> *"`%cid` must be unique within one ABAP EML request and can be specified
> manually or automatically. The specified content ID is only valid within one
> ABAP EML request. The specification of `%cid` should be done even if there are
> no further operations referring to it."*
>
> *"In `strict(2)` mode, the use of `%cid` is mandatory."*
>
> — [`%cid`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPDERIVED_TYPES_CID.html)

Omitting it is a contract violation, not a style issue — "Missing `%cid`" is a
listed RAP BO contract check, enforced via the `CC_RAP_CONTRACT` checkpoint
group with the runtime error `BEHAVIOR_CONTRACT_VIOLATION`
([RAP Implementation Rules](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPRAP_IMPL_RULES.html)).

`AUTO FILL CID` is the escape hatch, and it has two sharp edges:

> *"If the addition is specified and `%cid` is initial, `%cid` gets
> automatically filled with dummy values that have the prefix
> `%ABAP_EML_CID__`."*
>
> *"If `%cid_ref` is to be used, `%cid` must be specified manually since
> `%cid_ref` cannot refer to an automatically created value."*
>
> *"If `AUTO FILL CID` is used, `%cid` must not be filled with a value prefixed
> by `%ABAP_EML_CID__` in capital letters. Otherwise, the runtime error
> `BEHAVIOR_RESERVED_PREFIX` occurs."*
>
> — [`MODIFY ENTITY, ENTITIES`, `field_spec`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMODIFY_ENTITY_ENTITIES_FIELDS.html)

So `AUTO FILL CID` is fine for a flat batch of independent creates and unusable
the moment one operation has to refer to another — create-by-association,
create-then-update, create-then-execute-action in the same request. Those need
hand-written IDs.

For a generated key, `MAPPED` is the only channel back:

> *"For modify operations, internal tables are returned that map the key values
> of created instances to the provided content IDs (`%cid`). All subsequent
> operations must use the mapped keys."*
>
> — [`response_param`, Nondynamic Forms](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPEML_RESPONSES.html)

> *"The specification of an operand for `MAPPED` is required for create
> operations including UUID and in case of early internal numbering. It cannot
> be specified in external numbering scenarios."*
>
> — [ABAP EML - `response_param`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPEML_RESPONSE.html)

With a UUID key you supply no key and get none back from the statement itself —
without `MAPPED` you have created a row you cannot address. Conversely, asking
for `MAPPED` under external numbering is not merely useless, it is not allowed.
Whether the same line of code is required or rejected depends on the BDEF's
numbering, which is not visible at the call site.

Late numbering is a third case again, handled by
`COMMIT ENTITIES BEGIN ... CONVERT KEY OF ... END`, and the contract adds a rule
consumers break easily: *"RAP BO consumers must not request the mapping of
preliminary keys for which no final keys exist"*, including for instances
deleted later in the session
([RAP Implementation Rules](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPRAP_IMPL_RULES.html)).

## 7. The update is never asynchronous

This is where a classical-ABAP mental model actively misleads. In the
`CALL FUNCTION ... IN UPDATE TASK` world, `COMMIT WORK` hands the work to a V1
update work process and returns; the dialog step ends quickly. RAP does not do
that.

> *"For transactions where RAP is the transaction owner, `COMMIT ENTITIES`
> statements implicitly enforce local updates with `COMMIT WORK`, or
> `COMMIT WORK AND WAIT` if the local update fails. Therefore, the update is
> either a local update or a synchronous update, but never an asynchronous
> update. When RAP is involved in a transaction, but RAP is not the transaction
> owner, for example in the case of unit tests, it is up to the RAP BO consumer
> to choose between a synchronous and an asynchronous update for RAP BO
> entities."*
>
> — [`COMMIT ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCOMMIT_ENTITIES.html)

A *local update* runs the update function modules in the **current** work
process rather than handing them to an update work process. Consequences worth
planning for:

- the save time is on your dialog step, so `rdisp/max_wprun_time` applies to it;
- there is no update-task decoupling to hide a slow save behind;
- and the failure is yours to see — which is the upside, and the reason
  `sy-subrc` is meaningful at all (see the repo's
  [Update Task](../Update%20Task#readme) note for what asynchronous failure
  looks like instead: an express mail to the originating user and nothing in
  the calling program).

`COMMIT WORK` on its own still works — *"Using a `COMMIT WORK` statement also
triggers the RAP save sequence and saves RAP BO instances from the transactional
buffer to the database"* — but it gives you no responses and no key conversion,
*"the use of `COMMIT ENTITIES` statements is preferable in the context of RAP"*.

`ROLLBACK ENTITIES` is correspondingly wider than a buffer reset:

> *"Rolls back all changes of the current RAP transaction. This includes data
> changes (for example, changes stored in the transactional buffer by calling
> the `cleanup` method) and locks."*
>
> *"The rollback request (implicitly) triggers the calling of `ROLLBACK WORK` if
> the current RAP transaction includes RAP modify operations."*
>
> — [`ROLLBACK ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPROLLBACK_ENTITIES.html)

It releases **locks** as well as data. A "roll back this one document and carry
on with the next" loop silently drops the locks held for everything else in the
same RAP transaction.

## 8. The projection's `WHERE` clause does not protect anything

Documented, in identical words, on both `READ` and `MODIFY`:

> *"CDS projection views of the type transactional query or CDS transactional
> interface can define a `WHERE` clause to filter the result set. By default,
> this `WHERE` clause in the projection layer is ignored when a BDEF is accessed
> with EML `MODIFY` requests. This means that it is possible to read and modify
> entity instances that are not part of the projection BDEF's or interface
> BDEF's result set. **This behavior may pose a security risk.**"*
>
> — [`READ ENTITY, ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPREAD_ENTITY_ENTITIES.html)
> and [`MODIFY ENTITY, ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMODIFY_ENTITY_ENTITIES.html)
> (emphasis added)

A projection restricted to, say, `WHERE CompanyCode = '1000'` filters the OData
service and the Fiori list. It does not filter EML. Any ABAP code that can name
the projection BDEF can address instances outside it, by key.

The fix is a BDEF declaration, not a code change:
[`with managed instance filter`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENBDL_MNGD_INSTANCE_CHECK_PROJ.html).
This pairs with the repo's [CDS Access Control](../CDS%20Access%20Control#readme)
note — DCL protects the *view*, the projection `WHERE` does not protect the
*behavior*, and the two have to be reasoned about separately.

## 9. Do not put EML in a loop — and the reason you might want to anyway

Repeated verbatim on `READ`, `MODIFY` and `ROLLBACK ENTITIES`:

> *"ABAP EML statements should not be used in loops. Using them can have a
> performance impact because it can result in multiple single database accesses.
> There should be only one ABAP EML statement to read the necessary data, and
> then the data should be modified with an ABAP EML modify request."*
>
> — [`MODIFY ENTITY, ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMODIFY_ENTITY_ENTITIES.html)

But bundling costs you ordering, and the documentation says both things in the
same breath:

> *"When executing independent modify requests, there is no dedicated processing
> sequence. However, the processing sequence is relevant if the modify requests
> are dependent, for example, when using `%cid` or `%cid_ref` or in case of
> create-by-association operations that can be dependent on a previous
> operation. To ensure the processing sequence when executing independent modify
> requests, it is recommended that separate EML statements are used. In the
> interest of a better performance, requests should preferably be executed in a
> bundled way."*
>
> — [`MODIFY ENTITY, ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMODIFY_ENTITY_ENTITIES.html)

So: bundle for performance, split for guaranteed order, and use `%cid`/`%cid_ref`
to express a genuine dependency rather than relying on the order in which you
appended rows to the table. The order of lines in one `MODIFY` request is not a
contract.

One more performance note, this one easy to trigger by being thorough:

> *"When specifying the `REPORTED` response parameter for an ABAP EML `READ`
> request, the related RAP state messages of the instances and child entities of
> a CDS composition are returned for the instances with the keys specified. This
> leads to increased runtime and, usually, retrieving the messages of the
> `REPORTED` response parameter for read requests is not required."*
>
> — [`READ ENTITY, ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPREAD_ENTITY_ENTITIES.html)

Adding `REPORTED` to a `READ` "for completeness" walks the whole composition
tree. On `MODIFY` it is how you get your messages; on `READ` it is usually just
cost.

## 10. The contract checks are off until somebody turns them on

Most of the rules above — missing `%cid`, EML modify in the wrong saver method,
illegal statements in a transactional phase, bad `failed` entries — are *contract*
rules rather than syntax rules. They are enforced by checkpoint groups:

| Checkpoint group | Purpose | Runtime errors |
|---|---|---|
| `CC_STMT` | *"To enable the controlled SAP LUW checks. They check for invalid statements and operations in the transactional phases."* | `BEHAVIOR_ILLEGAL_STATEMENT`, `BEHAVIOR_ILLEGAL_STMT_IN_CALL` |
| `CC_RAP_CONTRACT`, `CC_RAP_INTERNAL` | *"RAP BO contract-related checkpoint groups to check for violations of RAP BO consumer and provider implementations."* | `BEHAVIOR_CONTRACT_VIOLATION` |

> *"Depending on the context (for example, `strict(2)` or implementations in the
> restricted ABAP language version scope), the checkpoint group activation is
> not required. The violations can, especially in case of `CC_STMT` and
> depending on the checkpoint group activation, result in a runtime error or
> they can be logged."*
>
> — [RAP Implementation Rules](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPRAP_IMPL_RULES.html)

This is the same activate-to-see mechanism as the repo's
[Checkpoints](../Checkpoints#readme) note, with the same consequence: a
contract-violating program runs quietly on a system where the groups are off and
dumps on one where they are on. The useful habit is to switch `CC_RAP_CONTRACT`
on in development rather than discover the rules in a test system.

A further contract item worth knowing as a consumer, because it reads like a
nicety and is enforced: *"RAP BO consumers must not request unnecessary or
ambiguous operations, that is, an update operation is unnecessary if no fields
are changed. Examples of ambiguous operations are duplicate update operations on
the same instance, duplicate delete operations, or action or function
executions."* A generic "save everything on the screen" routine that issues an
update per field, or an unconditional update for untouched rows, is a violation.

## Quick reference

| Question | Answer |
|---|---|
| Does `MODIFY ENTITY` write to the database? | No. Transactional buffer only. |
| Does `MODIFY ENTITY` set `sy-subrc`? | No. Use `FAILED`. |
| Does it raise an exception on failure? | No. |
| What happens if I omit `FAILED`? | Syntax **warning**, suppressible with `##EML_FAILED_MISSING_OK`. |
| Does `READ ENTITY` see uncommitted changes? | Yes — database **plus** transactional buffer. |
| How do I prove something was saved? | A plain `SELECT`, not an EML `READ`. |
| Which statement sets `sy-subrc`? | `COMMIT ENTITIES` (0 / 4 / 8). |
| `sy-subrc` = 4 | Early-phase failure. Buffer **retained**. Retry possible. |
| `sy-subrc` = 8 | Late-phase failure. Buffer cleared, internal `ROLLBACK WORK`. Needs explicit `ROLLBACK ENTITIES` before continuing. |
| Partial save on error? | No — all or nothing. |
| Update mode | Local, or synchronous if local fails. **Never** asynchronous. |
| `COMMIT ENTITIES` in a behavior pool / BO provider | Not allowed. |
| `COMMIT ENTITIES` in an OData/Fiori scenario | Not to be used — RAP does it. |
| `ROLLBACK ENTITIES` releases locks? | Yes, as well as data. |
| How do I get a generated key back? | `MAPPED`, keyed by `%cid`. |
| `AUTO FILL CID` with `%cid_ref`? | No — `%cid` must be manual. |
| Does the projection `WHERE` restrict EML? | No, unless `with managed instance filter`. |
| EML inside a `LOOP`? | Documented as "should not"; bundle instead. |

## Related notes in this repo

- [Update Task](../Update%20Task#readme) — what the asynchronous update RAP does
  not use actually does on failure
- [CDS Access Control](../CDS%20Access%20Control#readme) — DCL protects the view,
  not the behavior
- [Checkpoints](../Checkpoints#readme) — how checkpoint groups are activated
- [Enqueue Locks](../Enqueue%20Locks#readme) — the lock layer `ROLLBACK ENTITIES`
  releases
- [Null Values](../Null%20Values#readme) — on reading `sy-subrc` after statements
  that do not mean what you assume

## Sources

All quotations transcribed from the ABAP keyword documentation ("latest"), fetched
while writing this note:

- [`MODIFY ENTITY, ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMODIFY_ENTITY_ENTITIES.html)
- [`MODIFY ENTITY, ENTITIES`, `field_spec`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMODIFY_ENTITY_ENTITIES_FIELDS.html)
- [`READ ENTITY, ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPREAD_ENTITY_ENTITIES.html)
- [`COMMIT ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCOMMIT_ENTITIES.html)
- [`ROLLBACK ENTITIES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPROLLBACK_ENTITIES.html)
- [ABAP EML - `response_param`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPEML_RESPONSE.html)
- [`response_param`, Nondynamic Forms of ABAP EML Statements](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPEML_RESPONSES.html)
- [`%cid`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPDERIVED_TYPES_CID.html)
- [RAP Implementation Rules](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPRAP_IMPL_RULES.html)
