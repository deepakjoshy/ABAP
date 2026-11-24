# RAP Draft Handling | The Access Control That Does Not Reach Your Draft Data, the `DELETE FROM` That Leaves a Duplicate Key Behind & the ETag Field That Stops Being Suitable the Moment You Draft-Enable

Draft handling is the one part of RAP you are explicitly told not to implement.

> "RAP draft handling is in all scenarios completely managed by the RAP
> transactional engine. The application developer is not responsible for how
> draft data is written to the draft database table."
> -- [`with draft`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENBDL_WITH_DRAFT.html)

That sentence is true, and it is why draft-enabling goes wrong. *Nothing to
implement* gets read as *nothing to know*, so `with draft;` is pasted into the
behavior definition header, the quick fix generates the draft table, the app
works in the test system, and four separate things have quietly changed:

- a second database table now holds in-progress business data, and the access
  control you wrote for the first one **does not apply to it**;
- the field you were using as `etag master` is no longer the right field for the
  job;
- an exclusive lock now outlives the ABAP session, and expires on a clock that
  has nothing to do with your transaction;
- a set of actions with reserved names exists whether you declared them or not.

None of those produce an error message. This note is the part of draft handling
that is *not* managed for you.

> "Drafts are isolated in their own persistence and do not influence existing
> business logic until activated."
> -- [Draft](https://help.sap.com/docs/abap-cloud/abap-rap/draft) (RAP
> development guide)

Isolated from your business logic, yes. Also isolated from your authorization
model, which is section 1.

---

## 0. The shape of the thing

A draft-enabled business object has **two persistences per entity**: the active
table and the draft table. Every request is routed to one of them by a single
flag.

> "During runtime, every request is marked whether it is intended for the draft
> table, or for the active with the draft indicator `%IS_DRAFT`."
> -- [Draft Database Table](https://help.sap.com/docs/abap-cloud/abap-rap/draft-database-table)

Three principles from the development guide, each of which is a design
constraint rather than a hint:

> - "There can be only up to one draft instance for each active instance at the
>   same time."
> - "The primary key value of a draft and the corresponding active instance is
>   the same."

So a draft is not a version history and not a workspace --- it is *the* copy, and
`%is_draft` is the only thing separating it from the real row. The key alone does
not identify an instance in a draft BO, which is why the derived types carry
`%tky` (key + `%is_draft`) and why every piece of logic must be written against
`%tky` --- see [RAP Determinations & Validations](../RAP%20Determinations%20and%20Validations#readme),
section 9.

Draft is all or nothing for the BO:

> "It is added in the behavior definition header as it draft-enables the entire
> business object. It is not possible to implement draft capabilities for
> individual entities within a business object."

And it drags four mandatory elements in with it:

| Element | Where | Mandatory? |
|---|---|---|
| `with draft;` | BDEF header | the switch itself |
| `draft table <tab>` | every entity's characteristics | yes |
| `total etag <field>` | lock master entity only | yes |
| draft-enabled associations | every association in the BO | yes |
| draft actions | lock master entity only | yes in strict mode |
| `query <view>` (draft query view) | after `draft table` | no --- and that is the problem |

---

## 1. Your DCL does not protect the draft table

This is the one to read even if you read nothing else.

You wrote a CDS access control (DCL) for the view entity. A user may only see
their own sales area. The EML read and the OData service honour it. Then the BO
is draft-enabled, and the user's in-progress data lands in a *second* table that
your DCL never mentions:

> "The DCL access restrictions defined for the CDS view entities selecting from
> the active database table are not applied to the draft data. A draft query
> view allows the definition of read access restrictions for draft data."
> -- [`query`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENBDL_DRAFT_QUERY_VIEW.html)

The draft query view is **optional syntax**. Leave it out and there is no syntax
error, no warning, no runtime message --- read access to draft data is simply not
restricted by the rules that restrict the active data.

The documentation's own executable example spells out what the difference looks
like from the outside: for the active instances the EML read applies the access
condition and *"Some data sets are filtered out"*; for the draft instances it
applies "the DCL access condition attached to the draft query view" --- the one
you may never have written.

```
" Without the query addition: active data restricted, draft data not.
draft table ydj_so_draft

" With it: the draft table gets its own DCL, via its own view entity.
draft table ydj_so_draft query YDJ_SO_DRAFT_QUERY
```

Two rules for the view itself:

> "The draft query view `DraftQueryView` must be a CDS view entity or a CDS
> DDIC-based view (obsolete) that specifies the RAP draft table as data source
> after `FROM`. It must contain all fields from the draft table including
> administrative fields. Otherwise, a syntax check warning occurs."

So it is a flat `SELECT *`-shaped projection over the draft table (admin fields
and all) whose only purpose is to carry a `@AccessControl.authorizationCheck`
and a DCL source. Dropping a field to tidy it up produces the warning.

It is also the gate for extensibility classification:

> "A draft query view is a prerequisite for classifying a RAP BO with the C0
> contract for extensibility in the context of RAP extensibility."

**The review question:** does every draft-enabled BO in this package have a
`query` addition on its `draft table` line? If the active data was worth a DCL,
the draft data is the same data one save earlier. See
[CDS Access Control](../CDS%20Access%20Control#readme) for the DCL layer itself,
including the related trap that access control protects the view and not the
table underneath it.

---

## 2. You cannot clear a draft table with ABAP SQL --- and the failure is a duplicate key

The draft table is an ordinary transparent table, which invites ordinary SQL:

> "A draft table is a regular DDIC database table and can be accessed as such.
> Access with ABAP SQL and AMDP is technically possible, but not recommended."

"Not recommended" undersells it. The keyword documentation ships an example
whose entire point is that the obvious cleanup is broken. It runs the same block
twice: an ABAP SQL deletion of all rows, then an EML create of key `3`, then
`COMMIT ENTITIES`.

> "The first time, this entry is written to the draft database table and
> displayed as screen output. The second time, however, the creation of the new
> draft instance fails and the draft database table remains empty. The reason is
> that the draft database table cannot be emptied using ABAP SQL. It contains
> metadata which cannot be deleted with ABAP SQL and therefore, the key is
> considered to be a duplicate, even though the draft database table was
> cleared."
> -- [`draft table`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENBDL_DRAFT_TABLE.html)

Read the failure mode carefully, because it is the worst kind: **a duplicate-key
rejection on a table that a `SELECT` shows as empty.** You check the table, it
has no rows, you re-run the create, it fails again. The metadata lives outside
the rows you deleted --- in the draft administrative data the framework maintains
alongside them --- so as far as the framework is concerned the instance still
exists.

The two supported ways to empty it, per the same page, are the draft action
`Discard` and the EML `DELETE`, *"because `Discard` and `DELETE FROM` clear the
entries of the draft table as well as the metadata"*.

Native SQL is called out separately and no more favourably --- see
[Native SQL & ADBC](../Native%20SQL#readme) for why a direct write behind the
framework's back is a bad idea even when the table is not a draft table.

The practical consequence for a cleanup job or a test fixture: do it through
EML. Reading the table with `SELECT` for diagnostics is fine. Writing to it is
not.

---

## 3. The draft table is your maintenance liability, and the quick fix overwrites it

ADT generates the draft table for you, which makes it feel generated --- as if it
will keep itself current. It will not.

> "Whenever you change the active data model in the active database table, you
> have to regenerate the draft table to align them. The behavior definition
> offers a quick fix for regeneration, but it is the responsibility of the
> application developer to keep the two database tables synchronized. When
> regenerating the draft database table it completely overwrites the existing
> one."
> -- [Draft Database Table](https://help.sap.com/docs/abap-cloud/abap-rap/draft-database-table)

Two separate hazards in one paragraph:

1. **Adding a field to the CDS entity is a two-table change.** The draft table
   must mirror the entity --- *"It contains a field for each field of the CDS
   entity that the current entity is based on"*, with the same names (alias
   names if the entity assigns them) and *"The data types and field lengths must
   match exactly."* Field *order* is explicitly irrelevant.
2. **The quick fix is destructive.** *"In case the draft database table does
   already exist, the quick fix completely overwrites the table."* Anything you
   hand-added --- an extra index, a technical field, a comment --- is gone, and it
   is gone in the same click that fixes the field you came for.

The rest of the draft table's shape is fixed by the framework:

```abap
define table ydj_so_draft {
  key client : abap.clnt not null;      " must be first, type CLNT
  ...                                   " one field per CDS entity field
  "%admin" : include sych_bdl_draft_admin_inc;
}
```

The admin include is where the metadata of section 2 lives. Its components, per
the development guide:

| Component | Meaning |
|---|---|
| `draftentitycreationdatetime` | when the draft instance was created |
| `draftentitylastchangedatetime` | last change to the **draft** |
| `draftadministrativedatauuid` | link to the draft administrative data |
| `draftentityoperationcode` | create / update / delete intent |
| `hasactiveentity` | new-draft (no active row) vs edit-draft |
| `draftfieldchanges` | which fields the user has touched |

`hasactiveentity` is worth knowing by name: it is the stored form of the
new-draft / edit-draft distinction that decides which checks `Resume` runs
(section 6).

Two more requirements that are easy to miss because they are filed as hints:

- **Late numbering needs an extra key field.** *"When using `late numbering` for
  a draft-enabled RAP BO, it is mandatory that the draft table has an additional
  key field `DRAFTUUID` of data type `raw(16)`."* The quick fix generates the
  table from the entity; this field comes from the numbering decision, not from
  the entity, so a BO switched to late numbering later keeps a draft table that
  is now wrong.
- **Suppressed fields get no draft column.** Per the SAP Learning unit on the
  draft concept, *"The RAP runtime ignores view elements which are listed after
  a `field( suppress )`. So, no corresponding field is added to in the draft
  table for those view elements"* (the garbled clause is the source's, not mine).
  Add `field ( suppress )` to an existing BO and the draft table no longer
  matches by the strict rule above --- regenerate it.

---

## 4. The field that was a fine `etag master` is the wrong one once you draft-enable

A draft BO has **two** ETag concepts, and they are not two names for the same
thing.

`etag master` is the OData optimistic-concurrency ETag: the thing a client sends
back on a change request so the server can reject a stale write. `total etag` is
a different mechanism with a different job:

> "`total etag` is available for draft-enabled business objects only and for
> these, it is mandatory. It manages the transitions from active data to draft
> data and vice versa."
>
> "If a user edits data in draft mode and returns after the exclusive lock of
> their editing session has expired, the total ETag checks whether the
> persistent data has been changed during the period of absence. Each time the
> persistent state is changed, the total ETag field is updated. To resume a
> draft version, the infrastructure first compares the total ETag of the
> persistent and the draft version and only if both values are identical the
> draft can be resumed."
> -- [`etag`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENBDL_ETAG.html)

So the total ETag is what makes a draft **invalid** rather than merely old. And
the two fields have requirements that point in opposite directions. From the SAP
Learning unit on the draft concept:

> "The field to be used as a Total ETag field has to meet the following
> requirements:
> - The Total ETag field value in the active version always changes when the
>   active version is changed
> - The Total ETag field value in a draft instance does not change during the
>   draft lifetime"

versus, two paragraphs later:

> "On the other hand, the field annotated with
> `@Semantics.systemdateTime.lastchangedAt: true` is not suitable as ETag master
> anymore if the business object is draft-enabled. To ensure the optimistic
> concurrency control of the OData protocol works properly, the ETag master
> field has to receive a new value whenever there is an update of the draft
> instance. However, the lastChangedAt time stamp only changes when the draft is
> persisted."

That is the trap in full. **`with draft;` silently invalidates your existing
`etag master`.** `LastChangedAt` was the correct choice before and is the wrong
choice after, because a draft edit does not touch it --- the OData ETag never
changes while the user is editing, and concurrency control on the draft stops
working. Nothing in the behavior definition complains: the syntax is still legal
and the field still exists.

The replacement is a second timestamp:

> "To support OData concurrency control, SAP introduced the
> `@Semantics.systemDateTime.localInstanceLastChangedAt: true` annotation. The
> RAP runtime framework updates the field that is annotated like this during
> every write access to the draft instance."

Which gives the mapping to check in every draft-enabled BDEF:

| BDEF line | CDS annotation on the field | Changes when |
|---|---|---|
| `total etag ChangedAt` | `@Semantics.systemDateTime.lastChangedAt: true` | the **active** instance is persisted |
| `etag master LocChangedAt` | `@Semantics.systemDateTime.localInstanceLastChangedAt: true` | **every write** to the draft instance |

In the managed scenario those fields are filled for you, but only if annotation
*and* type line up --- *"The data type must be `utclong`, `TIMESTAMP`, or
`TIMESTAMPL`"*. In an unmanaged BO, both are yours: *"In unmanaged RAP BOs, the
application developer must ensure that a value is provided for the total ETag
field `TotalEtagField`."*

Three mechanical rules from the keyword documentation that generate real syntax
errors:

- *"The total ETag field must be defined directly after the lock master entity
  `lock master`."* Position in the characteristics block is part of the syntax,
  not a style convention.
- It is declared once, on the lock master, and *"it controls all RAP BO entities
  of the current RAP BO"*.
- *"Additionally, it can have a length of maximally 40 characters."* A hash or a
  concatenated change-token field is a plausible choice here and 40 is a low
  ceiling.

**Two documentation defects worth knowing about, since they will mislead you if
you read only the keyword doc:**

1. Under `etag master MasterField`, the keyword documentation says *"In a
   managed RAP BO, a value for the total ETag field can be provided
   automatically if the following conditions are met"* and then lists
   `localInstanceLastChangedAt`. The `total etag` section on the same page makes
   the identical statement with `lastChangedAt`. Both cannot be right; read as a
   copy-paste slip in the `etag master` bullet, the sentence should say *ETag
   master field*, which is exactly the mapping the table above shows and the
   mapping the SAP Learning exercise builds (`etag master LocChangedAt`,
   `total etag ChangedAt`).
2. The page also hints that *"The same field can be used as ETag master field
   `MasterField` and as total ETag field `TotalEtagField`."* In a draft BO that
   contradicts the two requirement lists above --- one field cannot both stay
   constant for the draft's lifetime and change on every draft write. Treat the
   hint as applying to the non-draft usage of `etag master`, and use two fields
   in a draft BO. *(This reading is an inference from the requirement lists, not
   a sentence SAP writes anywhere; it is the only reading under which the
   requirements are satisfiable.)*

See [Time Stamps](../Time%20Stamps#readme) for what `utclong` and `TIMESTAMPL`
actually hold, and [CDS Annotations](../CDS%20Annotations#readme) for why a
misspelled annotation name activates clean and does nothing --- which, for these
two annotations, means the managed framework silently stops filling the field.

---

## 5. The lock is no longer yours: it outlives the session and expires on its own clock

Everything you know about [Enqueue Locks](../Enqueue%20Locks#readme) and about the
RAP LUW stops applying the moment a draft exists.

> "The lifetime of such an exclusive lock is tied to multiple factors:
> - ABAP session: The enqueue lock is released once the ABAP session is
>   terminated.
> - LUW: The lock is released, once the RAP LUW is terminated with a `COMMIT` or
>   `ROLLBACK`.
> - Draft: In draft scenarios, the lock is not coupled to the LUW or the ABAP
>   session, but depends on the lifetime of the draft instance."
> -- [Pessimistic Concurrency Control (Locking)](https://help.sap.com/docs/abap-cloud/abap-rap/pessimistic-concurrency-control-locking)

A draft lock therefore survives a logoff, a session timeout, and a browser
crash. It is not leaked --- it is doing its job --- but it means *wait for the
other user to log off* is no longer a workaround for a stuck document.

> "As soon as a draft instance is created for an existing active instance, the
> active instance receives an exclusive lock and cannot be modified by another
> user. This exclusive lock remains for a determined time, even if the ABAP
> session terminates. Once the exclusive lock expires after this duration time,
> the optimistic lock phase begins."

**The phase nobody designs for is the second one.** After expiry the draft still
exists, and the active instance is no longer protected. Three things can end the
optimistic phase, and two of them destroy the user's work:

> "There are three cases that end the optimistic lock phase:
> 1. The user that created a draft instance for an active instance, and thus set
>    an exclusive lock on the active instance, discards the draft explicitly. ...
> 2. The draft is discarded implicitly, when
>    1. the draft remains untouched for a certain period of time. ... By default
>       this is done after 28 days.
>    2. the corresponding active instance is changed directly without using the
>       draft (by the draft owner or by a different user). This is possible
>       during the optimistic lock phase. This change on the active instance
>       invalidates the draft document. Invalid drafts are discarded
>       automatically after a determined time by the draft life-cycle service.
>    3. a second draft is created for the corresponding active document.
> 3. The draft is resumed by the draft owner."

Case 2.3 is the one to internalise: **a colleague clicking Edit on the same
document deletes your draft**, because there can only ever be one draft per
active instance. Case 2.2 is the subtler one --- an *unrelated* update path (a
batch job, an RFC, a second app on the same BO) can invalidate a draft nobody
knew existed, and the total ETag of section 4 is the mechanism that then refuses
the resume.

The durations are deliberately written as *"a determined time"* in both the
keyword documentation and the development guide. The concrete defaults appear in
the SAP Learning unit:

> "Even though the exclusive lock is not bound to a session, it is discarded
> after a certain period of time. By default, the maximum lifetime for an
> exclusive lock is set to 15 minutes. Once the exclusive lock expires after
> this duration time, the pessimistic lock phase ends and optimistic lock phase
> begins."
>
> "If a draft remains untouched for a certain period of time, the draft life
> cycle service removes it automatically. By default, it happens after 28 days.
> It implicitly ends the optimistic lock phase of the draft."

**15 minutes is shorter than a meeting.** Any mental model along the lines of
*the document is locked while the user has it open* is wrong by roughly the
length of a coffee break, and the design consequence is that your BO must
tolerate the active row changing underneath a draft.

And since the lock is a lock master concern, it is never one row:

> "Whenever a lock is requested for a specific entity instance, its lock master
> and all dependent entity instances are locked for editing by a different
> user."

One draft on a header therefore locks the whole lockable subtree --- which is
also why draft actions may only be declared on the lock master (section 7).

---

## 6. `Resume` runs by itself, and the checks it skips are yours to re-add

`Resume` is the action nobody writes a line of code for and everybody depends
on.

> "The draft action `Resume` is executed when a user continues to work on a
> draft instance whose exclusive lock for the active data has already expired.
> It re-creates the lock for the corresponding entity instance on the active
> database table. It is executed automatically whenever there is a modification
> on a draft instance whose exclusive lock has expired."
> -- [`draft action`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENBDL_DRAFT_ACTION.html)

Which checks it runs depends on `hasactiveentity`:

> "In case of new draft instances, the same feature and authorization control is
> executed as defined for the standard operation `create`. In case of edit-draft
> instances, the same feature and authorization control is executed as defined
> for the draft action `Edit`."

Two things that are your responsibility despite the action being managed:

**Prechecks are not re-run unless you make them run.**

> "In case of an edit draft, if a RAP BO precheck is required, this precheck
> implementation must be triggered explicitly during the draft action `Resume`.
> For this, the addition `with additional implementation` is required and the
> respective RAP handler method must trigger the precheck method."

So a BO that relies on a precheck to guard an update has a hole exactly at the
point where it matters most: the user is coming back after an absence long
enough for the world to have changed.

**Key uniqueness is not re-checked for you either.**

> "When resuming draft instances it must be ensured that the primary keys of the
> instance are still unique. It might have happened that other users created an
> instance with the same primary keys during the optimistic lock phase."
> -- [Resuming Locks for Draft Instances](https://help.sap.com/docs/abap-cloud/abap-rap/resuming-locks-for-draft-instances)

For a new-draft with a user-supplied key (not managed numbering), that is a
concrete duplicate-key failure at activation time, originating from a keystroke
somebody else made half an hour ago.

---

## 7. The draft actions you did not write, and the rules that differ for each one

Draft actions exist as soon as the BO is draft-enabled --- but declaring them is
not optional in the mode everybody develops in:

> "Draft actions are actions that are implicitly available for draft business
> objects as soon as the business object is draft-enabled. In strict mode, they
> have to be explicitly declared in the behavior definition."
> -- [Draft Actions](https://help.sap.com/docs/abap-cloud/abap-rap/draft-actions)

Where they may be declared:

> "Draft actions must be specified for lock master entities that are defined
> using the keyword `lock master` only, as they refer to the whole lockable
> subtree of a business object."

And the name collision that turns an existing BO's activation red:

> "In draft-enabled scenarios, the names of the draft actions are reserved for
> the draft actions. Entities that are not draft-enabled can use the names
> `Edit`, `Activate`, and so on, as names for actions. But when the addition
> `with draft;` is used to draft-enable a business object, the names of draft
> actions are forbidden as names for actions."

An action called `Edit` is a perfectly reasonable thing to have written two
years ago. Draft-enabling the BO makes it illegal, and renaming it is a
breaking change for every consumer and UI annotation that references it.

The per-action rules are genuinely inconsistent, so they are worth a table
rather than a paragraph:

| Draft action | What it does | Feature control | Authorization | `with additional implementation` |
|---|---|---|---|---|
| `Edit` | copies an active instance to the draft table | yes --- *"For `Edit`, it is per default implicitly enabled"* | yes (`authorization:none` allowed only here) | yes |
| `Activate [optimized]` | copies draft to persistent table, clears the draft table, implicitly runs `Prepare` | no | no | yes |
| `Discard` | *"deletes the draft instance from the draft database table"* | no | no | yes |
| `Resume` | re-creates the expired lock (section 6) | as `create` / `Edit` | as `create` / `Edit` | yes |
| `Prepare` (determine action) | runs assigned on-save determinations and validations | --- | --- | --- |
| `AdditionalSave` | extra save step for draft instances | --- | --- | implementation required |

The asymmetry in rows 1 and 2 is deliberate and is explained, not just
asserted:

> "In contrast to the draft action `Edit`, the `Activate` does not allow feature
> or authorization control. Authorization is not available as the Activate only
> transfers the state of the draft buffer to the active buffer. Authorization is
> controlled when the active instance is saved to the database."

So *the user must not be allowed to activate this* is not expressible on
`Activate`. It belongs on `Edit`, or in the authorization check of the
underlying `update`/`create`. Same for `Discard`: *"No feature or authorization
control can be implemented."*

**`optimized` is recommended, and the recommendation has a precondition.**

> "It is recommended that you always use the optional addition `optimized`"
> ... "As a prerequisite, determinations and validations must be modeled
> according to the guidelines ... For example, it must be ensured that the
> validations and determinations handle draft and active instances identically."

> "Using the optimized version without considerung these guidelines can impair
> the runtime behavior."
> -- [Draft Action Activate Optimized](https://help.sap.com/docs/abap-cloud/abap-rap/draft-action-activate-optimized) (typo SAP's)

`optimized` reduces how often determinations and validations run. If one of them
was quietly relying on running repeatedly --- or behaves differently on a draft
instance --- adding the keyword changes the result rather than just the runtime.
That is the same requirement as section 9 of
[RAP Determinations & Validations](../RAP%20Determinations%20and%20Validations#readme),
seen from the performance side.

**`AdditionalSave` cannot be called from ABAP at all.**

> "It is not possible to execute this action using `MODIFY ENTITIES ... EXECUTE`
> in ABAP EML, not even when using the addition `IN LOCAL MODE` and not from the
> current RAP BO's ABAP behavior pool. The draft action `AdditionalSave` is not
> exposed in an OData service."

It is framework-only, which is why SAP recommends declaring it `internal`. Also
note it is a *static* action, so its derived type carries `%cid` and not a key
--- see [ABAP EML](../ABAP%20EML#readme), section 6, for what `%cid` is for.

**One trap in `with additional implementation` itself:** the implementation runs
on whichever version the action operates on, which is not always the draft.

> "the additional implementation is executed on the same instance version (draft
> or active), on which the default draft action is executed. For example, the
> additional implementation for Edit receives the transactional key with the
> draft indicator off, as the Edit action is executed on the active instance."

So inside the `Edit` extension, `%is_draft` is **off**. Code written there on
the assumption of *I am in a draft action, therefore I am looking at draft data*
reads the active row.

---

## 8. `Prepare` only runs what you assigned to it, and only on-save objects qualify

`Prepare` is the draft-side equivalent of a determine action:

> "The draft determine action `Prepare` executes the determinations and
> validations that are assigned to it in the behavior definition. The `Prepare`
> enables validating draft data before the transition to active data."

Two limits, both of which turn into *my validation does not run on the draft*:

> - "Only validations and determinations defined as `on save` can be assigned."
> - "The assignment of determinations and validations must be done explicitly in
>   the BDEF. Only determinations and validations that are defined and
>   implemented for the BO can be used."

An `on modify` determination is therefore *not assignable* to `Prepare`, and a
new `on save` validation added next sprint does not join `Prepare`
automatically --- somebody has to add it to the list. The failure is silent: the
draft passes `Prepare`, then fails at activation when the save sequence runs the
validation that `Prepare` skipped.

It is also explicitly legal to assign nothing (*"It is also possible to not
define any determinations or validations to the draft determine action
`Prepare`"*), which is how a BO ends up with a `Prepare` that validates
nothing at all.

Since `Activate` *"includes an implicit execution of the draft determine action
`Prepare`"*, everything assigned to `Prepare` runs twice in a save-then-activate
sequence --- one more reason the idempotency requirement from
[RAP Determinations & Validations](../RAP%20Determinations%20and%20Validations#readme)
is not optional.

---

## 9. Associations, and the list of things drafts cannot do

Every association in a draft BO has to be draft-enabled, and the enabling
changes what the association returns:

> "A draft-enabled association retrieves active data if it is followed by an
> active instance and draft data if is followed by a draft instance."
> (the missing word is SAP's)
>
> "In a draft-enabled RAP BO, it is mandatory that associations are
> draft-enabled."

So the *same* association yields different rows depending on the `%is_draft` of
the instance you started from --- the association is a function of two inputs,
not one. Compare [CDS Associations](../CDS%20Associations#readme), where the join
type is decided by where the association is used; here the persistence is
decided by what it is used on.

The development guide's restriction list is short and specific. On draft
instances, these are **not supported**:

> - "Create-by-associations via intra-BO associations that are create-enabled
>   but no compositions"
> - "Direct creates on child instances"
> - "On draft instances, client-independent CDS views aren't supported."
> - "Associations that use `NOT` in the binding condition can't be
>   draft-enabled."
> - "There's no support for transactional draft-enabled associations leading
>   from draft to active instances."

Plus one quiet data defect:

> "The aggregated admin data fields aren't updated automatically when a draft
> instance is saved."

Each of these is a feature that works on the active instance and then does not
work in the draft phase of the same BO --- i.e. the test that passes is the one
you wrote first. `NOT` in a binding condition is the sharpest: a data model
that is already in production can simply be ineligible for draft-enabling, and
the reason is one operator inside an `ON` condition.

---

## Quick reference

| Question | Answer |
|---|---|
| Can one entity of a BO be draft-enabled? | No. `with draft;` is a header addition, whole BO |
| Drafts per active instance | At most one, same primary key |
| Which table does a request hit? | Decided by `%is_draft`; key alone is not an identity --- use `%tky` |
| Does my DCL protect draft data? | **No.** Only a draft query view (`draft table ... query V`) does |
| Clearing the draft table with ABAP SQL | Leaves metadata; next create fails as a duplicate key on an empty table |
| Supported way to clear it | Draft action `Discard`, or EML `DELETE` |
| Regenerating the draft table via quick fix | *"completely overwrites the table"* |
| Keeping active and draft tables in sync | Developer's responsibility |
| Late numbering | Draft table needs key field `DRAFTUUID`, `raw(16)` |
| `total etag` | Mandatory, lock master only, directly after `lock master`, max 40 chars |
| `total etag` field annotation | `@Semantics.systemDateTime.lastChangedAt: true` |
| `etag master` field annotation (draft BO) | `@Semantics.systemDateTime.localInstanceLastChangedAt: true` |
| Exclusive lock lifetime | Not session-bound, not LUW-bound; 15 minutes by default |
| Untouched draft lifetime | Discarded by the life-cycle service after 28 days by default |
| Second user edits the same active instance | Your draft is discarded implicitly and cannot be resumed |
| Draft actions location | `lock master` entities only; explicit declaration in strict mode |
| Action named `Edit` in a non-draft BO | Becomes illegal when the BO is draft-enabled |
| Feature/authorization control on `Activate` / `Discard` | Not available |
| `AdditionalSave` from EML | Impossible, even `IN LOCAL MODE` from its own ABP |
| `%is_draft` inside the `Edit` additional implementation | **Off** --- `Edit` runs on the active instance |
| Assignable to `Prepare` | `on save` determinations and validations only, explicitly listed |

### Review checklist for draft-enabling an existing BO

1. Does the `draft table` line have a `query` addition, and does that view
   entity carry a DCL? (Section 1.)
2. Is `etag master` still pointing at the `lastChangedAt` field? Move it to a
   `localInstanceLastChangedAt` field and give `total etag` the `lastChangedAt`
   one. (Section 4.)
3. Is there an existing action named `Edit`, `Activate`, `Discard`, `Resume`,
   `Prepare` or `AdditionalSave`? It has to be renamed. (Section 7.)
4. Are all associations draft-enabled, and does any of them use `NOT` in its
   binding condition? (Section 9.)
5. Is every determination and validation written against `%tky` rather than
   `%key`, and does it behave identically on draft and active instances ---
   the precondition for `Activate optimized`? (Section 7.)
6. Which `on save` objects are assigned to `Prepare`? Is anything missing that
   the user should learn about before activation? (Section 8.)
7. Is there a precheck that needs re-triggering in `Resume`? (Section 6.)
8. Does anything in the code base write to what is now a draft table with
   ABAP SQL --- a cleanup report, a test fixture, an archiving job? (Section 2.)
9. Can the application tolerate the active row changing after 15 minutes while
   a draft is open? (Section 5.)
10. Is `late numbering` in use? Then check the draft table for `DRAFTUUID`.
    (Section 3.)

---

## Sources

ABAP Keyword Documentation (8.16):

- [`with draft`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENBDL_WITH_DRAFT.html)
  --- the header addition, the whole-BO rule, the four dependent elements,
  draft-enabled associations being mandatory
- [`draft table`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENBDL_DRAFT_TABLE.html)
  --- the table requirements, the admin include, the `DRAFTUUID` rule for late
  numbering, and the ABAP SQL duplicate-key example
- [`query` (draft query view)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENBDL_DRAFT_QUERY_VIEW.html)
  --- DCL on the active view not applying to draft data, the all-fields rule,
  the C0 contract prerequisite
- [`etag`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENBDL_ETAG.html)
  --- `etag master` / `etag dependent` / `total etag`, the resume comparison,
  position and length rules, the annotations and types
- [`draft action`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENBDL_DRAFT_ACTION.html)
  --- the per-action feature/authorization matrix, the reserved names, `Resume`
  and the precheck hint, `AdditionalSave` not being callable, `optimized`

RAP development guide:

- [Draft](https://help.sap.com/docs/abap-cloud/abap-rap/draft)
  --- the stateless motivation, the three basic principles, the restriction list
- [Draft Database Table](https://help.sap.com/docs/abap-cloud/abap-rap/draft-database-table)
  --- `%IS_DRAFT`, the admin include components, the overwriting quick fix and
  the synchronisation responsibility
- [Draft Actions](https://help.sap.com/docs/abap-cloud/abap-rap/draft-actions)
  --- strict-mode declaration, the `Activate` authorization explanation, the
  instance version seen by `with additional implementation`
- [Pessimistic Concurrency Control (Locking)](https://help.sap.com/docs/abap-cloud/abap-rap/pessimistic-concurrency-control-locking)
  --- lock lifetime factors, the optimistic phase and the three ways it ends,
  lock master / lock dependent
- [Exclusive Draft Handling](https://help.sap.com/docs/abap-cloud/abap-rap/exclusive-draft)
  --- draft instance ownership
- [Resuming Locks for Draft Instances](https://help.sap.com/docs/abap-cloud/abap-rap/resuming-locks-for-draft-instances)
  --- the EML form of `Resume`, the key-uniqueness responsibility
- [Draft Action Activate Optimized](https://help.sap.com/docs/abap-cloud/abap-rap/draft-action-activate-optimized)
  --- the modelling prerequisite

SAP Learning (course *Building Transactional Apps with the ABAP RESTful
Application Programming Model*):

- [Understanding the Draft Concept](https://learning.sap.com/courses/building-transactional-apps-with-the-abap-restful-application-programming-model/understanding-the-draft-concept)
  --- the 15-minute and 28-day defaults, the total ETag requirement list, the
  `etag master` field becoming unsuitable, `field ( suppress )` and the draft
  table, and the worked BDEF with `total etag ChangedAt` / `etag master
  LocChangedAt`

---

## Related notes in this repo

[ABAP EML](../ABAP%20EML#readme) for the statements this note's examples use ---
`COMMIT ENTITIES`, `%cid`, `FAILED`/`REPORTED`/`MAPPED`,
[RAP Determinations & Validations](../RAP%20Determinations%20and%20Validations#readme)
for `%tky`, the draft/active behavioural equality that `Activate optimized`
depends on, and what `on save` means,
[CDS Access Control](../CDS%20Access%20Control#readme) for the DCL layer that
section 1 shows does not reach the draft table,
[CDS Associations](../CDS%20Associations#readme) for the association semantics
that draft-enabling adds a second dimension to,
[CDS Annotations](../CDS%20Annotations#readme) for why a misspelled
`@Semantics.systemDateTime...` annotation activates clean and stops the managed
framework filling the field,
[Enqueue Locks](../Enqueue%20Locks#readme) for the lock concept that draft
scenarios detach from the session and the LUW,
[Time Stamps](../Time%20Stamps#readme) for `utclong` vs `TIMESTAMPL`,
[Native SQL & ADBC](../Native%20SQL#readme) and
[SQL Write Access](../SQL%20Write%20Access#readme) for why writing behind the
framework's back is the common root cause of section 2.
