# RAP Determinations & Validations — the trigger that never fires, the check that cannot check authorization, and the determination that has no way to say no

A [determination](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENBDL_DETERMINATIONS.html)
computes and writes data. A [validation](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENBDL_VALIDATIONS.html)
accepts or rejects it. Both are declared in the behavior definition (BDEF) with a
trigger condition, both are implemented in a handler method of the behavior pool,
and both are called by the RAP framework — never by you.

This note is the **provider** side of RAP. The consumer side (`MODIFY ENTITIES`,
`COMMIT ENTITIES`, `FAILED`/`MAPPED`/`REPORTED`) is in
[ABAP EML](../ABAP%20EML#readme); this folder is about the code that runs
*inside* the business object, where the rules are different and mostly
unobvious:

- `validation x on save { update; }` is not the "check on change" you think you
  wrote — the documentation states that `update` **works only in combination
  with** `create`;
- a determination cannot reject anything. `FOR DETERMINE` has no `failed`
  parameter at all, so "compute the value, and refuse if the input is bad" needs
  two objects and a hand-rolled channel between them;
- `AUTHORITY-CHECK` is **not allowed** in an `on save` determination or in a
  validation. Nor is `COMMIT`, `MESSAGE`, `WRITE`, `SUBMIT`, or
  `RAISE EXCEPTION` — the error-handling reflexes of classical ABAP are all
  runtime errors in here;
- one invalid instance does not fail one instance. It rejects the **entire**
  transactional buffer, and then **blocks every further change** until the bad
  instance is corrected or the buffer is explicitly rolled back;
- the order in which your determinations run is undefined, each must be
  idempotent, and — for performance — the framework is documented as
  **skipping** determinations and validations in the save sequence under stated
  conditions;
- and `field(mandatory)` does not check anything at runtime. The documentation's
  own fix for it is: write a validation.

Everything quoted below is from the ABAP keyword documentation ("latest") and
the RAP development guide, fetched while writing this note. The companion file
`ydj_rap_det_val_patterns.abap` holds the BDEF and behavior-pool skeletons; it
is **not** a runnable report — see its header.

**Availability.** Determinations and validations are available for
[managed](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENMANAGED_RAP_BO_GLOSRY.html)
RAP BOs, and for unmanaged BOs **only if they are draft-enabled**. The
documentation is blunt about the gap:

> **Caution** Not available for unmanaged, non-draft RAP BOs.

In an unmanaged, non-draft BO the same logic has to live in the saver methods
`finalize` and `check_before_save` by hand — which, as section 2 shows, is
exactly where the framework puts it for you in a managed BO.

## 1. `update` on its own is not a trigger condition

The trigger condition is a list of operations (`create`, `update`, `delete`) or
a list of fields. The obvious thing to write for "check whenever the instance
changes" is `{ update; }`, and that is the one combination the documentation
singles out. For validations:

> `update`: The validation is executed when an instance is updated.
>
> **Note** Update works only in combination with the trigger operation `create`.

And for determinations:

> `update`: Determination is executed when an instance is updated. For
> determinations defined as `on save`, update works only in combination with the
> trigger operation `create`.

So the dependable spellings are `{ create; update; }` (operation-triggered) or a
field list. Note the asymmetry in how the restriction is documented: for
validations it is stated unconditionally, for determinations it is stated for
`on save` specifically.

```abap
" Both triggers, so an update is actually covered:
validation validateBuyer on save { create; update; }

" Field-triggered: runs when one of these fields is changed by create or update:
determination calcTotal on modify { field GrossAmount, Currency; }
```

Two more rules on trigger conditions that produce a syntax error rather than a
silent miss:

> The fields that are used for the trigger conditions must belong to the same
> entity the determination is assigned to.

— so a determination on the item entity cannot be triggered by a header field;
you put the determination on the header and have it read down the composition.
And a field can be fenced off from ever being a trigger:

> Defines that the field in question must not be used as the trigger condition
> of a RAP determination or a RAP validation. [...] If a field defined as
> `field(notrigger)` is used in a trigger condition, a syntax check error
> occurs.

`field(notrigger:warn)` downgrades that to a warning, which is how SAP adds the
restriction to an existing BO without breaking extensions:

> This addition can be used, for example, if the field restriction is added at a
> later point in time when the field in question has potentially already been
> used in a trigger condition. In this scenario, the addition `warn` prevents an
> incompatible change.

The typical `notrigger` candidates are the administrative timestamps the
framework itself writes — a determination triggered by `LastChangedAt` is a
determination triggered by its own side effects.

Finally, the name: a determination or validation name has

> a maximum of 30 characters.

## 2. Where they actually run: `finalize` and `check_before_save`

A managed BO has no saver class to read, so the timing looks like magic. It is
not — the framework calls your determinations and validations from the two
standard saver methods, and the keyword documentation says exactly which:

> In managed scenarios, determinations with `ON SAVE` are called during the
> `finalize` method call.

> In managed scenarios, validations are called during the `check_before_save`
> method call.

`finalize` is the **first** method of the early save phase; `check_before_save`
is the next one. So the real order at save time is:

| Step | What runs | Can it change data? |
|---|---|---|
| Interaction phase | `on modify` determinations, after each buffer change | Yes |
| `finalize` | **`on save` determinations** | Yes — last chance |
| `check_before_save` | **validations** | No |
| point of no return | — | — |
| `adjust_numbers`, `save` | late numbering, persistence | Database |
| `cleanup` | buffer cleared | — |

Two consequences follow from the RAP development guide's wording, and both bite:

> The `FINALIZE` step is the last option to change data on the transactional
> buffer. After the `FINALIZE` step, EML modify requests result in runtime
> errors.

So an `on save` determination may still write (and that is what it is for), but
a validation may not — not as a matter of style, as a matter of runtime error.
The restriction table states it directly for validations:

> It is not allowed to use EML `MODIFY` statements in the implementation of
> validations.

And once the checks pass, nothing can be undone:

> If the subsequent `CHECK_BEFORE_SAVE` step is positive for all transactionally
> involved business objects, the point-of-no-return is reached. From now on, a
> successful `SAVE` must be guaranteed for all involved BOs.

> If `CL_ABAP_BEHAVIOR_SAVER` is used as the base class `base_class` from which
> the RAP saver class inherits, and if the `check_before_save` method does not
> return an error, the RAP save sequence has reached a point of no return, that
> is, the following RAP saver methods must ensure that the data is successfully
> saved to the database.

This is why "notify the outside world that the order was saved" does not belong
in a determination. The development guide says so explicitly:

> Application logic intended to notify about saved changes must be implemented
> in a provider implementation that is called after the point of no return of the
> save sequence, e.g. in the additional save implementation. It must not be
> implemented in a determination `on save`.

A determination `on save` runs *before* the decision to save has been made. If a
validation then fails, your notification has already gone out for a document
that does not exist.

## 3. A determination has no `failed` — it cannot refuse anything

Compare the two handler-method signatures. `FOR VALIDATE`:

> The `CHANGING` parameters `failed` and `reported` (RAP response parameters)
> are implicitly available.

`FOR DETERMINE`:

> The `CHANGING` parameter `reported` (RAP response parameter) is implicitly
> available.

```abap
" A validation has both channels:
METHODS validate_buyer FOR VALIDATE ON SAVE
  IMPORTING keys FOR SalesOrder~validateBuyer.
"   -> failed   : keys of the instances to reject
"   -> reported : messages for the consumer

" A determination has one:
METHODS set_id FOR DETERMINE ON SAVE
  IMPORTING keys FOR SalesOrder~setID.
"   -> reported only. There is no 'failed' to fill.
```

That is the whole story: a determination can report a message, and nothing it
does will stop the save. The development guide spells out the consequence and
the intended workaround:

> Determinations don't have a failed response. In determinations where fields
> need to be checked before their calculation can be performed, the application
> needs to store negative results of these checks. Validations then need to
> consider these negative results when returning their failed response during
> `CHECK_BEFORE_SAVE`.

So "calculate the discount, and reject the order if the customer is unknown" is
*two* objects: a determination that records the problem somewhere, and a
validation that turns that record into a `failed` entry. And the record itself
has a lifetime problem the guide also names:

> In cases where determinations are executed multiple times due to retriggered
> conditions, the check result can change during subsequent determination
> executions. This needs to be considered by the determination logic that
> maintains the failed entries for validations.

In other words the stale entry is yours to clean up: a determination that writes
"invalid" on its first run and succeeds on a later run must remove its own
marker, or the validation rejects a document that is now correct.

Two things about the `keys` parameter while we are here, both from the
`TYPE TABLE FOR` documentation. The types that carry it cannot be declared
outside the behavior pool at all —

> The access to validations is not allowed outside of the implementation class.

— which is also true for `TYPE TABLE FOR DETERMINATION`, `FOR CHANGE` and the
feature/authorization types. And the short alias you use everywhere inside the
pool is a privilege of that location:

> An alias, however, only works within handler methods of a RAP BO provider.
> Aliases do not work for explicit declarations outside of implementation
> classes.

So `TYPE TABLE FOR UPDATE SalesOrder` compiles in the handler method and the same
line in a helper class does not — there, the full entity name is required. The
`\\` notation (`root_entity\\child_entity`) is for addressing a **child**
entity, not for qualifying the root.

## 4. One invalid instance rejects everything — and then blocks the next change

A classical mass update keeps the rows that worked. A validation does not work
that way, and the second half of this is the part nobody expects:

> The operation fails and the complete content of the transactional buffer of the
> current RAP transaction is rejected. A commit to the database happens only if
> all data changes are consistent. One inconsistency leads to a rejection of all
> the content in the transactional buffer.

> No further data changes are possible as long as the invalid instances aren't
> corrected. An invalid entity instance must either be corrected using an update
> operation, or the transactional buffer must be cleared using the EML statement
> `ROLLBACK ENTITIES`. The reason for this is that the `COMMIT ENTITIES`
> statement aborts the save sequence in case of invalid instances and the
> transactional buffer is not emptied.

Read that twice if you write batch jobs. The failed `COMMIT ENTITIES` leaves the
bad instance sitting in the buffer, so the *next* document — a perfectly valid
one — is rejected too, and the one after that, until something clears the
buffer. The documentation's own demo proves it: a report creates one valid
instance, then an invalid one, then another valid one, and

> Result: Only the first valid instance is committed to the database. The second
> valid instance is blocked.

This is the provider-side explanation of `sy-subrc = 4` from
[ABAP EML](../ABAP%20EML#readme) §3 — early-phase failure, buffer retained. The
loop that logs the error and carries on is the wrong shape; the correct shape is
`ROLLBACK ENTITIES` (or a corrective `UPDATE`) before the next document. And
batching is a real decision, not just a performance one:

> The valid entity instance is created in a different RAP transaction than the
> invalid ones. If all three entity instances were created in one RAP
> transaction - in this case, with the same `COMMIT ENTITIES` statement - all
> three of them would be rejected.

## 5. What you may not do in here: authorization checks, `MESSAGE`, `RAISE EXCEPTION`

Two documentation tables govern the inside of a behavior pool —
[Restrictions in RAP Handler and Saver Methods](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINVALID_STMTS_IN_RAP_METHODS.html)
and
[Restrictions in Transactional Phases](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINVALID_STMTS_IN_TX.html).
Both are worth reading in full once. The entries that most often surprise
someone writing their first determination:

| In an `on save` determination / validation | Allowed? |
|---|---|
| ABAP SQL `SELECT` | Yes |
| EML read requests, `GET PERMISSIONS` | Yes |
| EML modify requests | **Determinations yes, validations no** |
| Enqueue locks | Yes |
| **Authorization checks** | **No** — allowed in `on modify` determinations, not in `on save` determinations or validations |
| Function modules in update task / background processing | No (in any handler method) |
| Database modifications via the standard connection | No (in any handler method) |
| `COMMIT`/`ROLLBACK WORK`, `COMMIT`/`ROLLBACK ENTITIES` | No (in any handler or saver method) |

The authorization row is the one that catches people: a validation is the
natural place to write "and check the user is allowed to release this order",
and the documentation marks exactly that as not allowed for `on save`
determinations and validations. Authorization belongs in the dedicated
authorization control implementation; see
[Authorization Checks](../Authorization%20Checks#readme) for the classical layer
and [CDS Access Control](../CDS%20Access%20Control#readme) for the declarative
one.

The second table rules out the entire classical error-reporting vocabulary,
because a behavior pool runs inside a transactional phase:

> Dynpro processing. For example, `SET SCREEN`, `CALL SCREEN`, `LEAVE SCREEN`,
> `CALL DIALOG`, `SUPPRESS DIALOG`, `MESSAGE` without `INTO`, `WRITE`, `STOP`
> [...] Not allowed in transactional contexts. Results in a runtime error.

> Raising an exception using `RAISE EXCEPTION` [...] It is not allowed to leave a
> transaction this way.

> Report processing using `SUBMIT ...` [...] Not allowed in transactional
> contexts. Results in a syntax or runtime error.

So `MESSAGE e001(zz)` — the reflex of every ABAP developer who has ever
validated anything — is a dump, not a message. The one and only channel is
`reported` (plus `failed` for validations):

```abap
" WRONG inside a behavior pool - runtime error, not a message:
" IF lv_buyer IS INITIAL.
"   MESSAGE e001(zdj_sales) WITH lv_buyer.
" ENDIF.

" RIGHT - fill the response parameters and return normally:
APPEND VALUE #( %tky = ls_order-%tky ) TO failed-salesorder.

APPEND VALUE #( %tky             = ls_order-%tky
                %state_area      = 'VALIDATE_BUYER'
                %msg             = new_message(
                                     id       = 'ZDJ_SALES'
                                     number   = '001'
                                     severity = if_abap_behv_message=>severity-error
                                     v1       = ls_order-BuyerId )
                %element-BuyerId = if_abap_behv=>mk-on )
       TO reported-salesorder.
```

`new_message( )` is inherited from `cl_abap_behavior_handler`; `%element-...`
is what makes the UI highlight the offending field rather than showing a
message with no anchor. `MESSAGE ... INTO` remains legal
precisely because it does no message processing at all; see
[Messages](../Messages#readme) for what that variant does and does not set
(notably: it does not set `sy-subrc`).

Transaction control is refused for a specific reason worth internalising:

> In the contexts of RAP (that is, where RAP is the transaction owner, for
> example, in handler and saver methods), local consumption of RAP business
> events, bgPF, and classified APIs, commit or rollback statements are not
> allowed.

You are not the transaction owner. RAP is. And the scope of "in here" is defined
as:

> In a RAP transaction, the modify transactional phase includes the RAP
> interaction phase and RAP early save phase. The save transactional phase
> includes the RAP late save phase.

These violations are not all compile-time. Two switches make them visible:

> ABAP contract checks violations are made visible in unit tests, i.e. the unit
> tests will fail if a contract check violation occurs.

> The checks of the controlled SAP LUW are applied if the checkpoint group
> `CC_STMT` is enabled.

Same activate-to-see mechanism as every other checkpoint group —
see [Checkpoints](../Checkpoints#readme).

## 6. The order is arbitrary, so every determination must be idempotent

Three hints from the determination documentation, which together forbid the most
natural way to write business logic — a chain:

> The determination result must not change if the determination is executed
> several times under the same conditions (idempotence).

> The execution order of determinations is not fixed. If there is more than one
> determination triggered by the same condition, the execution order is
> arbitrary.

> Once a determination has been triggered, it must run independently from other
> determinations.

The same is stated for validations:

> The execution order of validations is not fixed. If there is more than one
> validation triggered by the same condition, the execution order is not
> predictable.

So "determination A fills the tax code, determination B uses it" is not a
design, it is a race that happens to pass in the development system. If B needs
A's output, either merge them into one determination or have B triggered by the
*field* A writes — and then re-read the instance rather than assuming.

Idempotence is not a style guideline here either: determinations genuinely do run
more than once, because changes they make can re-satisfy trigger conditions.
That is also the root of the stale-marker problem in §3.

One more, specific to `on modify`:

> If an instance is created and deleted with the same request, it can happen that
> an EML read operation in a determination defined as `on modify` fails as
> instances with the given key cannot be found.

An `on modify` determination therefore has to tolerate its own instance being
gone by the time it reads it — check `FAILED` from the `READ ENTITIES`, do not
assume the key is still there.

## 7. They are not guaranteed to run at save at all

This one is easy to miss because it lives in a footnote of the save-sequence
diagram, and it quietly invalidates "the validation always runs before the
database is touched":

> For performance reasons, determinations and validations are not executed during
> the save sequence, if these determinations and validations have already been
> executed during a previous determine action that has been executed on the
> active instance in the same transaction.

The optimization is switched off in two cases:

> A modification performed after the determine action triggers a
> determination/validation.

> A validation in the determine action reports a failed key.

And draft handling adds its own variation:

> The runtime of the save sequence may vary with respect to determinations and
> validations depending on whether the optimized variant of the `activate` action
> is used or not.

Practical reading: the framework is allowed to deduplicate executions across the
transaction, so the number of times your code runs is not yours to predict in
either direction — which is the real reason the documentation insists on
idempotence and on identical behaviour per phase:

> The behavior of determination and validation executions must be identical,
> irrespective from the runtime phase they are executed in. A validation, for
> instance, that is part of a determine action, must provide the same reported
> result in the interaction phase and in the save sequence.

## 8. `field(mandatory)` does not check anything

A field marked mandatory in the BDEF gets a red asterisk on the Fiori screen and
nothing else:

> However, there is no runtime check for mandatory fields and no runtime error
> occurs if a mandatory field is not filled. If a runtime check is required, the
> application developer should implement it using a validation on save.

The documentation demonstrates it with an EML create that omits the mandatory
field entirely:

> Result: The mandatory field `char_field1` contains the initial value, no syntax
> check warning or syntax check error occurs.

So any BO consumed by anything other than its own Fiori app — a report, a job,
an API, a unit test — needs the validation. The sibling characteristics behave
differently again, which is why the distinction matters:

| Characteristic | Behaviour on breach |
|---|---|
| `field(mandatory)` | Nothing at runtime. UI hint only. Write a validation. |
| `field(mandatory:create)` | "a runtime error occurs" |
| `field(readonly)` | Syntax check **error** in the consumer |
| `field(readonly:update)` | Syntax check **error** in the consumer |
| `field(features:instance)` | "it is ignored. There is no error or warning message. In a managed RAP BO, there is also no entry in the response structures." |

The `features:instance` row is the second silent one: dynamic feature control is
a UI affordance, not a gate. If a rule must hold for every consumer, it is a
validation.

## 9. Draft and active instances must behave identically — use `%tky`

A draft-enabled BO runs your determinations and validations against draft
instances as well as active ones, and the development guide requires the results
to match:

> The behavior of determinations and validations must coincide for draft and
> active instances. This includes the state messages reported by determinations
> and validations.

> In order to implement determinations and validations kind independently, use
> the derived type component `%tky`. This component includes the draft indicator
> `%is_draft` which is set depending on the context by the framework.

`%tky` ("transactional key") is the key *plus* `%is_draft`. Code written against
`%key` works on active instances and silently addresses the wrong instance kind
in a draft scenario; code written against `%tky` is kind-independent by
construction.

```abap
" Kind-dependent: loses the draft indicator.
APPEND VALUE #( %key = ls_order-%key ) TO lt_update.

" Kind-independent: %tky carries %is_draft, set by the framework.
APPEND VALUE #( %tky = ls_order-%tky ) TO lt_update.
``` Setting `%is_draft` yourself is possible and is called out as a
risk:

> Before you set the draft indicator `%is_draft` manually, ensure that this does
> not lead to an unwanted difference in behavior between draft and active
> instances.

One modelling rule rounds this off. Because both object kinds typically read the
instance first and then act on what they read, the guide's advice is to make the
fields you *read* the fields you trigger on:

> Determinations and validations are commonly used to first read instance data
> and then to perform the modification/validation based on the read data.

Trigger on the inputs, not on the operation, and the object re-runs exactly when
its inputs change.

## Quick reference

| Question | Answer |
|---|---|
| `validation x on save { update; }` | Not dependable — `update` "works only in combination with" `create` |
| Can a determination be `on modify` *and* `on save`? | They are two different kinds; pick per determination |
| Where do `on save` determinations run? | Inside `finalize` (first method of the early save phase) |
| Where do validations run? | Inside `check_before_save` |
| Last point data can change | `finalize`. After it, EML modify requests are runtime errors |
| Can a determination reject a save? | **No** — `FOR DETERMINE` has only `reported`, no `failed` |
| Can a validation change data? | No — EML `MODIFY` not allowed in validations |
| `AUTHORITY-CHECK` in a validation? | Not allowed (nor in `on save` determinations) |
| `MESSAGE e...` / `WRITE` / `RAISE EXCEPTION` | Runtime error. Use `reported` |
| `COMMIT WORK` / `COMMIT ENTITIES` in a behavior pool | Not allowed anywhere in handler or saver methods |
| One invalid instance | Rejects the **whole** transactional buffer |
| After a failed save | Buffer **not** emptied — correct the instance or `ROLLBACK ENTITIES`, or the next change is blocked too |
| Execution order of several determinations | Arbitrary. Idempotence required |
| Guaranteed to run at save? | No — documented performance skip if already executed in a determine action |
| `field(mandatory)` enforced at runtime? | No. The documented fix is a validation on save |
| `field(mandatory:create)` | Runtime error if not filled |
| `field(features:instance)` breached | Silently ignored, no response entry |
| Draft-safe key component | `%tky` (includes `%is_draft`), not `%key` |
| `TYPE TABLE FOR VALIDATION`/`DETERMINATION` outside the pool | Not allowed |
| Entity alias in a derived type | Handler methods only, not helper classes |
| Available for unmanaged, non-draft BOs? | No |
| Name length limit | 30 characters |

## Related notes in this repo

- [ABAP EML](../ABAP%20EML#readme) — the consumer side: `COMMIT ENTITIES`,
  `sy-subrc` 4 vs 8, and why the buffer survives an early-phase failure
- [Authorization Checks](../Authorization%20Checks#readme) — the layer that may
  not be called from here
- [CDS Access Control](../CDS%20Access%20Control#readme) — declarative
  protection, and why it stops one layer up
- [Messages](../Messages#readme) — why `MESSAGE` without `INTO` is the wrong tool
  inside a transaction
- [Checkpoints](../Checkpoints#readme) — activating `CC_STMT` so the LUW
  violations above become visible
- [Update Task](../Update%20Task#readme) — the classical save model RAP replaces
- [Number Ranges](../Number%20Ranges#readme) — what late numbering in
  `adjust_numbers` is working around

## Sources

Quotations transcribed from the ABAP keyword documentation ("latest") and the
Development Guide for the ABAP RESTful Application Programming Model, fetched
while writing this note:

- [RAP - `determination`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENBDL_DETERMINATIONS.html)
- [RAP - `validation`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENBDL_VALIDATIONS.html)
- [`FOR DETERMINE`, RAP Handler Method](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPHANDLER_METH_DET.html)
- [`FOR VALIDATE`, RAP Handler Method](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPHANDLER_METH_VALIDATE.html)
- [`finalize`, RAP Saver Method](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSAVER_FINALIZE.html)
- [`check_before_save`, RAP Saver Method](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSAVER_CHECK_BEFORE_SAVE.html)
- [RAP early save phase](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENEARLY_RAP_SAVE_PHASE_GLOSRY.html) /
  [RAP late save phase](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLATE_RAP_SAVE_PHASE_GLOSRY.html)
- [RAP - `FieldCharacteristics`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENBDL_FIELD_CHAR.html)
- [Restrictions in RAP Handler and Saver Methods](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINVALID_STMTS_IN_RAP_METHODS.html)
- [Restrictions in Transactional Phases](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINVALID_STMTS_IN_TX.html)
- [Save Sequence Runtime (RAP Development Guide)](https://help.sap.com/docs/ABAP_Cloud/f055b8bf582d4f34b91da667bc1fcce6/ab7459048c7e4ecda98d0b6f51b01e7b?version=sap_cross_product_abap)
- [Determination and Validation Modelling (RAP Development Guide)](https://help.sap.com/docs/abap-cloud/abap-rap/determination-and-validation-modelling?locale=en-US&version=sap_cross_product_abap)
