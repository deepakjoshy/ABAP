# Background RFC (bgRFC) | The Unit That Is Exhausted by COMMIT WORK, the Update Record Whose Deletion Takes Your Units With It & the Web Service Call That Cannot Run Inside a Unit

This repo's [RFC Calls](../RFC%20Calls#readme) note ends by pointing here. The
keyword documentation for `CALL FUNCTION ... IN BACKGROUND UNIT` says that
bgRFC "is the enhanced successor technology of transactional RFC (tRFC) and
makes this technology obsolete" and that "It is strongly recommended to use
bgRFC instead of tRFC". So this is the note about the thing you are supposed to
use.

bgRFC looks like a cosmetic rewrite of tRFC: instead of an addition on
`CALL FUNCTION`, you build an object and pass it. That framing is what makes it
dangerous. The object has a lifetime, and the lifetime ends at `COMMIT WORK`.
The unit is coupled to the update task unless you explicitly uncouple it. There
is a runtime check that forbids a whole class of statements *inside* your
function module. And the destination `NONE`, which tRFC uses implicitly when you
omit the destination, is not supported at all --- so the migration the
documentation recommends is not a one-line edit.

Almost none of this produces a syntax error. Most of it produces either a short
dump in production or a unit that sits in the monitor forever.

> "If the same unit object is used with multiple function module calls, then all
> these function modules are executed in one unit."
> -- [`Calling a Function Module`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/96de810eec3987e10000000a421937/content.htm)

> "The unit objects are valid within an application LUW, which means they are
> valid up to the next COMMIT WORK"
> -- [`Manipulating a Background Unit`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/982d730e0e0e27e10000000a421937/content.htm)

---

## 0. The shape of the thing

Three objects, in order: a **destination**, a **unit**, and the function module
registrations you put into the unit.

```abap
" inbound = executed in THIS system by the inbound scheduler
DATA(lo_dest) = cl_bgrfc_destination_inbound=>create( 'MY_DEST' ).
DATA(lo_unit) = lo_dest->create_trfc_unit( ).

CALL FUNCTION 'RFC_FUNCTION_1' IN BACKGROUND UNIT lo_unit.
CALL FUNCTION 'RFC_FUNCTION_2' IN BACKGROUND UNIT lo_unit.

COMMIT WORK.    " <- nothing before this line has left your session
```

The `CALL FUNCTION` statements do not call anything. They *register* into the
unit, exactly as tRFC registers into `ARFCSSTATE`, and exactly as
[`CALL FUNCTION ... IN UPDATE TASK`](../Update%20Task#readme) registers an update
module. `COMMIT WORK` is what saves the unit and releases it to a scheduler.

Two flavours, and the difference is the quality of service, not the syntax:

| Method | Type | Q-o-S | Ordering |
|---|---|---|---|
| `create_trfc_unit( )` | type t | "exactly once" (EO) | none --- units run in parallel |
| `create_qrfc_unit( )` | type q | "exactly once in order" (EOIO) | serialized by queue name |

> "For bgRFC type q, the quality of service is exactly once in order (EOIO) and
> for type t the quality of service is exactly once (EO). To be able to guarantee
> the sequence of bgRFC type q units and, at the same time, parallelize
> independent units, the dependencies are implemented using queues. bgRFC type t
> units do not belong to a queue and can therefore always be processed in
> parallel."
> -- [`Creating a Destination Object and Unit Objects`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9295b8aa6b17cee10000000a421937/content.htm)

`create_qrfc_unit_outinbound( )` is the third one: an outbound unit that lands in
the *inbound* queue of the target system. It is not free --- the bgRFC overview
says the data "is recorded twice, once for the caller ( outbound processing) and
once for the called application (special type of the inbound procedure)", with
"additional load for the database, and for the application server as well due to
the scheduler".

---

## 1. The unit object is exhausted by `COMMIT WORK` --- including a `COMMIT WORK` you did not write

This is the first thing that breaks, because it breaks the obvious refactoring:
build a unit, send it, build another one from the same reference.

> "The method IS_VALID shows the current status of the unit. A unit is exhausted
> after the statement COMMIT WORK. The method CREATE_UNIT_BY_PATTERN can be
> implemented to use a unit again. This creates a new unit that belongs to the
> same destination and that contains the same queues."
> -- [`Manipulating a Background Unit`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/982d730e0e0e27e10000000a421937/content.htm)

So a second `CALL FUNCTION ... IN BACKGROUND UNIT` on a unit you already
committed raises `CX_BGRFC_INVALID_UNIT`. Fine --- that is at least loud.

The part that is not loud is the word *unintentionally*:

> "The object is valid for the duration of an application LUW. After the
> application has triggered a COMMIT WORK (intentionally or unintentionally),
> automatic processing methods will eventually invalidate the object."
> -- [`API of bgRFC Type t and bgRFC Type q`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/96dc490eec3987e10000000a421937/content.htm)

Your program is full of statements that end an SAP LUW without the word `COMMIT`
appearing anywhere near them. Anything that sends a message of type `A` or `X`,
anything that calls a function module which commits, a screen round trip --- the
list in this repo's [Program Calls](../Program%20Calls#readme) and
[Update Task](../Update%20Task#readme) notes applies unchanged. Put a unit
reference in a global variable, hold it across one of those, and the reference is
still bound, still non-initial, and no longer a unit.

`IS_VALID` exists precisely because you cannot tell by looking:

```abap
" assumes an abap_bool-like result; the docs do not state the type,
" so check it in your own system before branching on it
IF lo_unit->if_bgrfc_unit~is_valid( ) IS INITIAL.
  " the reference is fine; the unit behind it is gone
ENDIF.
```

Note the interface prefix. `IS_VALID`, `LOCK`, `DELAY`,
`SEPARATE_FROM_UPDATE_TASK` and `DISABLE_COMMIT_CHECKS` are components of
`IF_BGRFC_UNIT`, which the unit interfaces *contain* rather than redeclare; by
the flat-nesting rule in this repo's [Interfaces](../Interfaces#readme) note,
a component of a nested interface is addressed through the interface that
**defined** it unless an alias was declared. The documentation says exactly this
about `DELAY`, in a prerequisite line that is easy to read past:

> "The DELAY method has been defined in the interface IF_BGRFC_UNIT and no alias
> is used."
> -- [`Locking a bgRFC Type t Unit`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9f49b1f7ec6bb9e10000000a42189d/content.htm)

...and then prints an example that calls `my_unit->delay( 300 ).` without the
prefix. See [section 14](#14-defects-in-the-sources-and-what-i-could-not-verify).

---

## 2. One unit object means one unit --- so the obvious loop builds the wrong thing

Reuse the unit object and you have not sent five messages, you have sent one
message containing five function calls, with one fate:

```abap
" ONE unit: all five run together, in order, in one target-side LUW.
" If call 3 fails, the whole unit is marked failed and 4 and 5 do not run.
DATA(lo_unit) = lo_dest->create_trfc_unit( ).
LOOP AT lt_orders INTO DATA(ls_order).
  CALL FUNCTION 'Z_SEND_ORDER' IN BACKGROUND UNIT lo_unit
    EXPORTING is_order = ls_order.
ENDLOOP.
COMMIT WORK.
```

```abap
" FIVE units: independent, parallelizable, independently restartable.
LOOP AT lt_orders INTO DATA(ls_order).
  DATA(lo_unit) = lo_dest->create_trfc_unit( ).   " new unit per iteration
  CALL FUNCTION 'Z_SEND_ORDER' IN BACKGROUND UNIT lo_unit
    EXPORTING is_order = ls_order.
ENDLOOP.
COMMIT WORK.
```

Both compile. Both are correct code for *some* requirement. Neither announces
which one you wrote. Bundling is the documented replacement for the old
`AS SEPARATE UNIT` addition, inverted: in tRFC you opted *out* of sharing a
transaction ID, in bgRFC you opt *in* by reusing the object.

> "In this way, it is possible to use multiple unit objects in parallel within a
> single application LUW. Consequently, multiple background units can be created
> in parallel within an application LUW. In the previous version, this was
> possible using the AS SEPARATE Unit addition. The advantage of the new solution
> is that multiple background units can accept multiple function modules."
> -- [`Calling a Function Module`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/96de810eec3987e10000000a421937/content.htm)

**The destination, however, is a singleton**, which is the trap in the other
direction --- calling `create( )` again in the hope of a fresh start gives you the
same object back:

> "Destinations NONE and SPACE are not supported. Exactly one object is created
> for every execution destination within an internal mode, which means,
> destination is a singleton for every execution destination."
> -- [`Creating a Destination Object and Unit Objects`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9295b8aa6b17cee10000000a421937/content.htm)

The destination also outlives the unit: "The destination objects are valid for
the entire runtime of the program." Destination is per-program, unit is per-LUW.
The demo in this folder proves the singleton claim by comparing two references.

---

## 3. Inside a unit you may not call an RFC, an HTTP client, or `WAIT`

This is the section to read if you are putting an integration behind bgRFC,
because the natural design --- *queue it, then let the unit call the REST API* ---
is forbidden by a runtime check, and the symptom is a short dump.

> "A transactional consistency check takes place when processing bgRFC units
> (language element `CALL FUNCTION <func> IN BACKGROUND UNIT`) and this avoids
> ABAP language elements that could lead to a commit being used in the unit
> execution of the application."
> -- [`Transactional Consistency Check`](https://help.sap.com/docs/ABAP_PLATFORM_NEW/753088fc00704d0a80e7fbd6803c8adb/89be29c77d1b4b5e80678e4d2da51345.html)

The list is specific, and `CL_HTTP_CLIENT` being on it is the one that surprises
people:

> "Sychronous and asynchronous RFCs ( `CALL FUNCTION <func> DESTINATION`),
> `WAIT`, `COMMIT WORK`, `ROLLBACK WORK`, HTTP communication (using the class
> `CL_HTTP_CLIENT`), and calling the function module `DB_COMMIT` belong to these
> language elements. An explicit `ROLLBACK WORK` is not permitted. However, a
> rollback can be executed using the statement `MESSAGE`."

So the function module registered in a unit may not:

- call another system synchronously or asynchronously --- see
  [RFC Calls](../RFC%20Calls#readme)
- do HTTP with the classic client --- see [HTTP Client](../HTTP%20Client#readme)
- `WAIT` --- which rules out the `WAIT UP TO` sleep and
  `WAIT FOR ASYNCHRONOUS TASKS`
- `COMMIT WORK`, `ROLLBACK WORK`, or `DB_COMMIT`

and the two failure modes are named:

> "While calling the ABAP language elements for the ABAP runtime error
> `SYSTEM_ILLEGAL_STATEMENT`, the execution of an implicit commit creates the
> ABAP runtime error `DBIF_DSQL2_DEFAULT_CR_ERROR` using the function module call
> `DB_COMMIT`."

*(That sentence is mangled in the source; it is quoted here as published. The
usable content is the two runtime-error names.)*

The reasoning is worth keeping, because it tells you why the check cannot simply
be switched off and forgotten:

> "The reason for this check is that after a commit (for example, initiated by an
> RFC), all database actions that were previously executed in the unit (such
> `INSERT`, `MODIFY`, `UPDATE`, and `DELETE`) are persisted on the database. If
> after this action the application terminates the related unit with an error
> (such as `MESSAGE E`, `A`, or `X`) then you cannot rollback the entire unit (
> Logical Unit of Work). Executing the unit again would lead to the same database
> inconsistency."

A unit is restartable *because* it is atomic. Commit halfway through and
"exactly once" degrades into *the first half, an unknown number of times*.

**The escape hatch, and why it is a loaded gun.** The check is per unit and can
be turned off at build time:

```abap
lo_unit->if_bgrfc_unit~disable_commit_checks( ).
```

> "You can change this runtime behavior by either deactivating the transaction
> consistency check when creating bgRFC units (using the method
> `IF_BGRFC_UNIT~DISABLE_COMMIT_CHECKS`) or by modifying the application so that
> no actions are executed which could cause a commit or a rollback. Here,
> however, you are allowed to implement the language element `MESSAGE` for
> logging errors."

Note which of the two options the sentence puts first and which one it describes
in terms of what the application *should* do instead. Calling
`disable_commit_checks( )` because a dump appeared does not fix the dump's cause;
it converts a short dump at the illegal statement into a half-applied unit that
the scheduler may retry. If you need to call out to another system, the unit
should *record the intent* and a separate LUW should perform the call.

---

## 4. Your unit is chained to the update task unless you say otherwise

If the same SAP LUW that builds a unit also registers update function modules
(`CALL FUNCTION ... IN UPDATE TASK`), the unit does not run when you commit. It
runs when the *update* has succeeded --- and if the update record is thrown away,
the unit goes with it.

> "If, within the same SAP LUW, bgRFC units and also updates are executed, the
> bgRFC units are dependent on the update. Only after the update has been
> processed can the associated bgRFC also be processed. When an incorrect update
> record is deleted, the corresponding bgRFC units are also deleted. The linkage
> of bgRFC with the update can be removed using the interface method
> IF_BGRFC_UNIT~SEPARATE_FROM_UPDATE_TASK of the bgRFC object."
> -- [`CALL FUNCTION IN BACKGROUND UNIT`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/abapcall_function_background_unit.htm)

Read the third sentence as an operational procedure, because that is what it is.
Somebody looks at a failed update record in **SM13**, decides it is junk, and
deletes it. The bgRFC units from that LUW are now also gone --- not failed, not
visible in the bgRFC monitor as needing attention, *gone*. The outbound message
that was supposed to tell the neighbouring system about the document is simply
never sent, and nothing anywhere reports an error, because from bgRFC's point of
view the removal was legitimate.

The coupling is the default, and the opt-out is per unit:

> "The method SEPARATE_FROM_UPDATE_TASK removes the binding between the
> processing of a unit and the update records. If this method is not called for
> the corresponding unit, then the processing of the unit depends on the
> successful processing of the update records of the same application LUW. If
> this is not required, you have to call this method for every unit."
> -- [`Manipulating a Background Unit`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/982d730e0e0e27e10000000a421937/content.htm)

*"you have to call this method for every unit"* --- there is no destination-level
or system-level setting, and the bundling rule from
[section 2](#2-one-unit-object-means-one-unit-----so-the-obvious-loop-builds-the-wrong-thing)
means a loop creating N units needs N calls.

Which default is right depends on what the unit says. If it announces *document 4711 has been posted*, the coupling is exactly what you want --- the announcement
must not overtake the posting, and must not survive its failure. If it is an
independent errand, the coupling silently makes it hostage to an unrelated V1
module.

Related, and the same shape: a unit built inside a dialog module is not rescued
by the caller's commit.

> "bgRFCs registered in a dialog module that were not started there using
> COMMIT WORK are not executed by the COMMIT WORK of the caller either."
> -- [`CALL FUNCTION IN BACKGROUND UNIT`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/abapcall_function_background_unit.htm)

The keyword documentation states the same rule for tRFC and qRFC, so this is not
new behaviour --- but a `COMMIT WORK` that commits everything *except* the units
is a hard thing to debug from the calling side, where the code looks complete.

---

## 5. `NONE` is not a destination, so the recommended migration is not a one-line edit

The documentation recommends replacing tRFC with bgRFC. Put the two statements
side by side and the recommendation acquires a prerequisite.

tRFC, when you omit the destination:

> "If the destination has not been specified, the destination NONE is used
> implicitly."
> -- [`CALL FUNCTION - IN BACKGROUND TASK`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/8937ad84b84e6fe10000000a421937/content.htm)

bgRFC: "Destinations NONE and SPACE are not supported."

There is no destination-less bgRFC. The equivalent of *run this later, here* is
an **inbound** destination, and an inbound destination is configuration that must
exist before your code runs:

> "The destination for the outbound queue must be maintained in the transaction
> SM59 and represent an execution destination for the outbound bgRFC type t and
> type q. The destination for the inbound queue must be maintained in the
> transaction SBGRFCMAINIDST. If the destination is not valid, the exception
> `CX_BGRFC_INVALID_DESTINATION` is produced."
> -- [`Creating a Destination Object and Unit Objects`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9295b8aa6b17cee10000000a421937/content.htm)

In current releases that maintenance lives on a tab of **SBGRFCCONF**, and it
carries a second mandatory field that is easy to leave empty:

> "In addition to this you can also maintain the assignment of a queue prefix for
> the bg RFC inbound destination. By making this setting, the bgRFC (inbound)
> processing is set for a queue."
>
> "BgRFC cannot work without this assignment."
> -- [`Creating Inbound Destinations`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/973e3755493987e10000000a421937/content.htm)

The same page explains the reason for one destination per application, and it is
a namespace argument rather than an administrative preference: "When you define
an inbound destination for each application you also avoid conflicts that can
result from queues in different applications having the same name." Two
applications that both name a queue `ORDERS` are serializing against each other
through a shared dependency neither team can see.

Three consequences for a migration:

1. **It is a transport-plus-configuration change.** The code references a
   destination name that must be maintained in the target system. Unmaintained,
   it raises `CX_BGRFC_INVALID_DESTINATION` at runtime --- so a program that
   passes the syntax check, passes activation and passes the unit test in the
   development system dumps on first use in production.
2. **bgRFC needs a supervisor destination before anything works at all**, and
   that destination is subject to its own rules: it must be an ABAP or logical
   connection, a "user, password, and client must be entered for both connection
   types", the user "needs the authorizations in the SAP_BC_BGRFC_SUPERVISOR
   role", and once configured, "This destination is then locked in transaction
   SM59, which means that it cannot be modified or deleted." For a logical
   connection the page allows only `NONE` *or nothing* as the reference --- the
   one place in bgRFC where `NONE` appears legitimately.
3. **Outbound destinations may be registered behind your back.** The
   documentation is candid that this was deliberate, and that undoing it is not:
   "It was very important to automatically register destinations that had not yet
   been registered for the outbound queue, as an unregistered destination is
   always flagged as 'old'." It then warns that "Switching destinations is a
   critical operation, especially if queues to this destination have been filled
   already, or if the destination is already used in an internal mode." A stray
   `cl_bgrfc_destination_outbound=>create( )` against a destination that classic
   tRFC/qRFC is still using is therefore not a read-only probe. This is why the
   demo in this folder probes an **inbound** destination only, and ships the
   outbound call as commented reference code.

---

## 6. A queue is a sequencing device evaluated once, not a channel

Classic qRFC readers carry over a mental model in which the queue *is* the
transport. In bgRFC the queue's job finishes at `COMMIT WORK`:

> "One of the most noticeable differences to classic qRFC is the reduced
> importance of the queues in the processing of the units. The queues have
> finished their work after the sequence of the units has been determined. This
> is done when the unit is saved to the database, which is when the COMMIT WORK
> of the application is performed."
> -- [`bgRFC Programming`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/929142aa6b17cee10000000a421937/content.htm)

That is also why the dependency graph is computed at save time rather than at
processing time --- the architecture note contrasts the two directly: "The classic
qRFC model detects the dependencies among the individual units only when the data
is processed by the RFC scheduler", whereas "with the bgRFC, the dependencies are
determined when the data is stored."

Two practical consequences.

**Queue names may be assigned after the `CALL FUNCTION`.** The documentation's own
example does it, and flags the cost itself:

> "In this example, we will specify the queue names retroactively. This is
> technically correct, but the maintenance of the programs can suffer as a
> result."
> -- [`Examples for Inbound and Outbound Processing`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9620d6a0230e27e10000000a421937/content.htm)

**A unit in several queues waits for the head of every one of them.** This is the
feature most likely to deadlock a production system, and the overview page says
so in as many words:

> "A call that is placed in several queues at the same time creates a dependency
> between these queues. This leads to a synchronization point, which is similar
> to a lock. The dependent queues can be processed until the entry for processing
> is at the head of the queue that defines the dependency. This entry can only
> then be processed if it is at the head of all the queues."
>
> "This is a very powerful function (for example, for managing documents in
> logistics). If used incorrectly by application development it can stop queue
> processing."
> -- [`bgRFC (Background Remote Function Call)`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/927c2caa6b17cee10000000a421937/content.htm)

The documentation's example adds three queue names to one unit
(`DEBITOR-1234`, `PRODUCT-4711`, `PRODUCT-5432`) --- read as a dependency, that
unit is a barrier across one customer and two materials, and every other unit
mentioning any of those three is now behind it. The feature is correct for
*this document touches all three objects*; it is a mistake when the three names
were added defensively.

The method names are direction-specific, and the out-in interface is the only one
that takes both:

| Unit interface | Queue methods |
|---|---|
| `IF_QRFC_UNIT_INBOUND` | `add_queue_name_inbound`, `add_queue_names_inbound` |
| `IF_QRFC_UNIT_OUTBOUND` | `add_queue_name_outbound`, `add_queue_names_outbound` |
| `IF_QRFC_UNIT_OUTINBOUND` | both of the above |

> "One special case is an outbound bgRFC unit of type q that is to be written to
> the inbound queues in the destination system. The signature of the interface
> IF_QRFC_UNIT_OUTINBOUND is broader."
> -- [`Manipulating a Background Unit`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/982d730e0e0e27e10000000a421937/content.htm)

Adding the same name twice raises `CX_QRFC_DUPLICATE_QUEUE_NAME`, suppressible
with `ignore_duplicates = abap_true`. Suppress it in a loop that derives queue
names from data, and keep it in code where a duplicate means you have a bug.

---

## 7. Locks nobody else can find and nobody else can clear

A unit can be written to the database already locked, so that the scheduler
leaves it alone until something releases it. `LOCK` holds it indefinitely;
`DELAY` holds it for a number of seconds.

```abap
DATA(lv_lock_id) = lo_unit->if_bgrfc_unit~delay( 300 ).   " runnable in 5 min
COMMIT WORK.
```

> "The processing of a unit can be prevented by setting a lock using the method
> LOCK. You can delay the processing of a unit using the method DELAY. This is
> also done by setting a lock. The processing of the unit by the scheduler will
> only start once all locks have been canceled. Any number of locks per unit is
> possible. A unit can only be processed once all locks have been deleted. Each
> lock is represented by a unique lock_id. A method to release or detect all
> locks on a unit should not be offered. In this way, each user can only release
> his or her own locks and the runtime behavior of other programs cannot be
> influenced by the premature release of locks."
> -- [`Manipulating a Background Unit`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/982d730e0e0e27e10000000a421937/content.htm)

That last design decision is defensible and has a sharp consequence: **the
`lock_id` is the only handle, and the API deliberately offers no way to enumerate
or clear the locks on a unit.** Lose the `lock_id` --- do not persist it, or
discard it because the method result looked like a status code --- and from ABAP
the unit is now permanently unrunnable. The only route back is the bgRFC monitor
(**SBGRFCMON**). A `DATA(lv_lock_id) =` that you never store is not a cosmetic
omission; it is the difference between a delay and a leak.

Note also that `delay( 300 )` is *not* *run in 5 minutes*. It is *do not run
for 5 minutes, then become eligible* --- the scheduler decides when eligible units
actually run.

Queue-level locks are a separate mechanism, with their own classes
(`CL_QRFC_LOCK_INBOUND`, `CL_QRFC_LOCK_OUTBOUND`, `CL_QRFC_LOCK_NOSEND`) and two
directions:

> "The LOCK_QUEUE_FROM_TOP method locks the first unit at the beginning of the
> specified queue for a destination. This makes it possible to lock a queue
> retroactively. If no unit exists, an empty unit is created automatically to map
> the lock."
>
> "The LOCK_QUEUE_FROM_CURRENT_POS method locks the execution of the next unit,
> which is written to the specified queue for a destination. This makes it
> possible to lock a queue preemptively. An empty unit is created to map the
> lock."
> -- [`Using Queues to Lock and Unlock Units`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9f4b14f7ec6bb9e10000000a42189d/content.htm)

A lock is therefore *a unit* --- an empty one, fabricated to carry the lock. An
unexplained empty unit in a queue is not corruption.

---

## 8. The documented interleaving of unit locks and queue locks

Both kinds of lock take effect at `COMMIT WORK`, and when both are present in one
LUW the order is fixed: "Units are always locked and unlocked when the COMMIT
WORK is performed" and "If both unit locks as well as queue locks are created
within an application LUW, then the queue locks are always set first and then the
unit locks are assigned to the appropriate queues."

The documentation's own trace is worth copying verbatim, because it shows a lock
set *at the beginning* landing in front of a unit that was already queued:

| Operation on the Queue | Content of the Queue |
|---|---|
| Creation of Unit 1 | |
| Creation of Unit 2 | |
| COMMIT WORK | Unit 1 - Unit 2 |
| Creation of Unit 3 | |
| Setting of lock A at current position | |
| COMMIT WORK | Unit 1 - Unit 2 - Lock A - Unit 3 |
| Setting of lock B at the beginning | |
| Processing of unit 1 by the scheduler | Unit 2 - Lock A - Unit 3 |
| COMMIT WORK | Lock B - Unit 2 - Lock A - Unit 3 |

-- [`Using Queues to Lock and Unlock Units`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9f4b14f7ec6bb9e10000000a42189d/content.htm)

Lock B was requested before unit 1 had been processed but takes effect at a later
`COMMIT WORK`, by which time *the beginning* is a different place. *Lock the
queue from the top* is resolved when the commit happens, not when you call it.

---

## 9. The state value that means both finished and no-such-unit

A set of client-side classes lets a program ask what happened to a unit --- "A
class exists for each of the combinations of bgRFC type t and type q for inbound
and outbound", and their return values are the constants of `IF_BGRFC_CLIENT`.
One row of the documented result table collapses success and nonsense into one
value:

> | `IF_BGRFC_CLIENT=> UNIT_STATE_EXECUTED` | The unit unit_id has already been executed or the value of unit_id does not specify a valid unit. |
>
> -- [`RFC Client-Side Runtime Control`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9f48eaf7ec6bb9e10000000a42189d/content.htm)

So a monitoring report that asks *did unit X complete?* gets the same answer for
*it completed* and *there is no unit X* --- which is exactly what an uninitialised
or truncated unit ID produces. The same family as the `sy-subrc = 0` ambiguities
in this repo's [Authorization Checks](../Authorization%20Checks#readme) and
[Function Modules](../Function%20Modules#readme) notes: the success value is also
the didn't-happen value. Treat *executed* as *not pending* and verify completion
from your own application data.

The other values are a useful vocabulary for reading the monitor:

| Value | Meaning (abridged) |
|---|---|
| `UNIT_STATE_BLOCKED` | waiting on other queues that must run first |
| `UNIT_STATE_LOCKED` | locked, or part of a locked queue |
| `UNIT_STATE_COMMUNICATION_ERR` | destination unreachable |
| `UNIT_STATE_EXECUTION_ERR` | the unit itself failed |
| `UNIT_STATE_EXECUTED` | executed *or* unknown unit (above) |
| `UNIT_STATE_RUNNABLE` | eligible |
| `UNIT_STATE_IN_EXECUTION` | running |

and the resolution rule is a priority order, not a set:

> "If multiple return codes are possible, then the one at the top is returned."

A unit that is both locked and blocked reports `BLOCKED`, because `BLOCKED` is
listed first. Clearing the lock you can see will not make it runnable.

Restart and removal are explicit calls, with a documented asymmetry in how loud
they are:

> "A unit with errors can be started again by calling RUN_FAILED_UNIT. The method
> forces the scheduler to restart the unit and does not wait until the unit has
> been executed. The number of retroactive start attempts and the moment of the
> last start attempt of a unit is automatically logged and displayed in the
> monitor. After a unit has been processed successfully, the unit is deleted and
> the following units are potentially started by the scheduler automatically. If
> the unit was not processed successfully, then this queue keeps blocking the
> following queues."
> -- [`RFC Client-Side Runtime Control`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9f48eaf7ec6bb9e10000000a42189d/content.htm)

`RUN_FAILED_UNIT` is fire-and-forget: it returns before the outcome is known, so
a wrapper that calls it and reports success has reported nothing. Removal, by
contrast, is audited --- "A unit with errors can be deleted with the
DELETE_FAILED_UNIT method. This deletion process is always logged by a trace
record."

---

## 10. From inside the unit: `RETRY_UNIT` and the end-of-unit event

`CL_BGRFC_SERVER` is the view from within a running unit, and every method on it
has a precondition:

> "During the execution of a unit, you can use the methods of the class
> CL_BGRFC_SERVER to influence the way the unit is processed. All specified
> methods raise the exception CX_RFC_NO_LUW_EXEC if they are called outside of a
> unit started by the tRFC scheduler."
> -- [`RFC Server-Side Runtime Control`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9f3b34e6af062be10000000a42189d/content.htm)

That exception is the one you will meet in a unit test, because a function module
exercised directly is not running under a scheduler. A shared helper that calls
`GET_UNIT_ID` for logging works in production and raises in every test that calls
it the normal way --- wrap it, or inject it behind a test seam (see
[AUnits](../AUnits#readme)).

The genuinely interesting method is `RETRY_UNIT`, which gives up the current
attempt *and reshapes the dependency graph*:

> "RETRY_UNIT is used to force the RFC runtime to reschedule the current unit.
> This method is used to resolve a blocked situation in the application, for
> example, a resource conflict within parallel transactions. The parameter
> RETRY_KEY is used to form another queue to serialize former independent units
> with the same resource conflict."

So two units that collide on a resource can be made to agree, at runtime, to
queue behind the same `RETRY_KEY` --- self-serialization discovered on contention
rather than declared up front. `CX_BGRFC_INVALID_RETRY_KEY` is the matching
exception.

Completion is observable with an ordinary ABAP event: "The event END_OF_UNIT from
the class C L_BGRFC_SERVER is triggered once a unit has been successfully
processed. You can register an event handler for this event by using the ABAP
statement SET HANDLER to control the postprocessing." The handler-lifetime rules
in this repo's [Events](../Events#readme) note apply unchanged --- `SET HANDLER`
keeps a strong reference to the handler object.

---

## 11. Deleting a stuck unit is not a neutral act

The standard reflex with a blocked classic queue is to delete the offending
entry. bgRFC keeps the dependency graph when you do that, and the architecture
page spells out the result with a diagram and a caution:

> "Unlike the classic procedure, if any units or queues are deleted, the
> dependencies are retained, since the units are first flagged and only then
> deleted by the scheduler."
>
> "After deleting Unit4, Unit6 can only be executed after Unit3, as Unit4 is only
> deleted once the scheduler has processed Unit3."
>
> "Deleting a queue or unit is, therefore, always risky. In our examples, it could
> occur that Unit6 encounters an error or causes a database inconsistency in the
> target system, since the required preparations in Unit4 were canceled by the
> deletion."
> -- [`bgRFC Architecture`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9702b055493987e10000000a421937/content.htm)

Two separate points, both counter-intuitive. First, deletion is *deferred*: the
unit is flagged and removed later by the scheduler, so a queue does not unblock
the instant you delete, and the ordering guarantees of the units behind it are
preserved rather than collapsed. Second --- and this is the application-level
warning --- the successor unit still runs, but now runs against a system where its
prerequisite never happened. Exactly-once delivery of unit 6 is still honoured.
Correctness is not, and bgRFC cannot know the difference.

---

## 12. One-way doors

Three constraints that are cheap to respect at design time and expensive later:

> "A combined use of the bgRFC with tRFC and qRFC is not possible within a
> destination. However, for each destination you can define which communication
> type you want to use."
>
> "Changing back from bgRFC to qRFC is not supported."
> -- [`bgRFC (Background Remote Function Call)`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/927c2caa6b17cee10000000a421937/content.htm)

A destination is classic *or* bgRFC, so migration is per destination and
all-or-nothing for every program using it --- and it does not roll back. The
rollback plan for *switch this interface to bgRFC* cannot be *switch it back*.

During a migration phase, sharing a queue name across the two worlds loses
ordering:

> "A queue name must not be used in parallel in classic qRFC and new bgRFC, since
> no dependencies can be represented, and the classic queues are always processed
> first in a migration phase before the entries of the new queue are processed.
> Any processed classic queues are ignored."
> -- [`Migration`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9f0ac6f7ec6bb9e10000000a42189d/content.htm)

That *"no dependencies can be represented"* is the whole problem: the two mechanisms
cannot see each other's queues, so the serialization that the queue name was
supposed to provide quietly stops existing while both halves keep reporting
success.

---

## 13. The exceptions, and the ones that are not in the list

The exception overview page tabulates twelve classes and states the obligation
bluntly --- "The exceptions must be caught by the application program to prevent
the system for crashing" (published wording):

| Exception | Cause |
|---|---|
| `CX_QRFC_DUPLICATE_LOCK` | Duplicate lock in background RFC |
| `CX_QRFC_DUPLICATE_QUEUE_NAME` | Duplicate queue name of a unit in qRFC |
| `CX_QRFC_INVALID_QUEUE_NAME` | Queue name is invalid |
| `CX_BGRFC_INVALID_DESTINATION` | Destination error in background RFC |
| `CX_BGRFC_INVALID_UNIT` | Invalid unit of background RFC |
| `CX_QRFC_NO_FAILED_UNIT` | Queue does not contain any incorrect units |
| `CX_QRFC_NO_SINGLE_QUEUE_NAME` | Only one queue name is allowed |
| `CX_BGRFC_WRONG_EXEC_CONTEXT` | The function cannot be run in the current context |
| `CX_BGRFC_ILLEGAL_PERMUTATION` | Invalid permutation |
| `CX_BGRFC_INVALID_RETRY_KEY` | Invalid reason for retry |
| `CX_BGRFC_INVALID_TIME_SPEC` | Invalid date specifications |
| `CX_QRFC_NO_QUEUE_NAME` | Missing queue name |

-- [`Exception Handling`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/96e3db0eec3987e10000000a421937/content.htm)

Two things to take from it beyond the names. The messages are in the `TEXTID`,
not in the class --- "Some exceptions output detailed information about the cause
of the error using the class attribute TEXTID", so a `WHEN cx_bgrfc_invalid_unit`
handler that logs only the class name has discarded the reason (see
[Exception Texts](../Exception%20Texts#readme)).

And the table is **not complete**. The client-side page raises
`CX_RFC_NO_FAILED_LUW` and `CX_RFC_INVALID_LUW`, and the server-side page raises
`CX_RFC_NO_LUW_EXEC` --- three `CX_RFC_*` classes, none of which appear above,
sitting alongside a tabulated `CX_QRFC_NO_FAILED_UNIT` that describes the same
condition as `CX_RFC_NO_FAILED_LUW` under a different name. Catch by the name the
page documenting *the method you are calling* uses, and check the real class in
your own system before relying on either.

---

## 14. Defects in the sources, and what I could not verify

This note is built from documentation, not from a running system. Everything
above is quoted; the following is where the sources disagree with themselves or
with each other, flagged rather than smoothed over.

**The `DELAY` example contradicts its own prerequisite.** The page states "The
DELAY method has been defined in the interface IF_BGRFC_UNIT and no alias is
used" and that therefore "the call must be performed in the form specified below
(this may be subject to changes)" --- and the form specified below is
`lock_id = my_unit->delay( 300 ).`, with no interface prefix. Those two cannot
both be right: with no alias, a component of a contained interface is reached as
`my_unit->if_bgrfc_unit~delay( 300 )`. This note uses the prefixed form
throughout, on the strength of the prose plus the flat-nesting rule for
interfaces, and because a third-party report of the same API in the wild spells
`disable_commit_checks` with the prefix. *That is an inference, not an SAP
statement* --- if your system declares aliases, the short form compiles too, and
the prefixed form compiles either way.

**A method name is published as `GET_FAILD_UNIT_BY_QUEUE`.** The client-side page
reads "If a queue is blocked by a unit with an error, then the unit_id of this
unit can be detected by calling the GET_FAILD_UNIT_BY_QUEUE method." I could not
determine from documentation alone whether `FAILD` is a typo in the page or the
real (typo'd) method name shipped in the class, and SAP has shipped both kinds of
defect. If you search a class for `GET_FAILED...` and find nothing, search for
`FAILD` before concluding the method does not exist.

**The two state tables swap their `UNKNOWN` constants.** The unit-state table ends
with `IF_BGRFC_CLIENT=> QUEUE_STATE_UNKNOWN` ("The status of the unit is
unknown") while the queue-state table ends with `IF_BGRFC_CLIENT=>
UNIT_STATE_UNKNOWN`, and the queue-state table also carries four other
`UNIT_STATE_*` rows (`BLOCKED`, `EXECUTED`, `INVALID_UNIT_ID`, `RETRY`). The
prefixes are therefore unreliable in both tables. Of particular note:
`UNIT_STATE_INVALID_UNIT_ID` appears *only* in the queue table --- so whether an
unknown unit ID is distinguishable from a completed one depends on which table is
right, and the two pages disagree. Read the constants off `IF_BGRFC_CLIENT` in
your own system.

**`C L_BGRFC_SERVER`.** The stray space in the server-side page's
`END_OF_UNIT` sentence is in the published text; the class is `CL_BGRFC_SERVER`.

**Two renderings of the keyword documentation, two translations.** The
`CALL FUNCTION IN BACKGROUND UNIT` page is quoted above from the 7.54 rendering,
which is the one linked. The current 8.16 rendering of the same page states the
same facts in revised English --- *"bgRFC units and updates are executed"* for
*"bgRFC units and also updates are executed"*, *"the bgRFC units linked to it are
also deleted"* for *"the corresponding bgRFC units are also deleted"*, and
*"The bgRFC can be decoupled from the update"* for *"The linkage of bgRFC with
the update can be removed"*. Nothing turns on the difference, but if you quote
this page in a document of your own, check which rendering you are reading: the
8.16 page is delivered by client-side script and does not survive a plain fetch,
whereas the 7.5x pages are static HTML. (The three 8.16 spans in this paragraph
are the only quotations in this note taken from a script-delivered rendering;
every other quotation here was checked against a static copy of the page it
cites.)

**Transaction name drift.** The programming page says inbound destinations are
maintained in `SBGRFCMAINIDST`; the configuration page describes the same
maintenance on a tab of `SBGRFCCONF`. Both are cited above, as published. Current
systems use `SBGRFCCONF`; treat `SBGRFCMAINIDST` as the older direct-access
transaction.

**Not verified, and deliberately absent:** the exact signature of
`CREATE_UNIT_BY_PATTERN` (the page says only that it "can be implemented to use a
unit again"), the parameter list of `LOCK`, whether `IS_VALID` returns `abap_bool`
or a status code (the demo prints the raw value rather than comparing it to
`abap_true`), the scheduler timing parameters, and anything about `basXML`. There
is also no claim here about release availability beyond the one the overview page
makes --- "As of SAP NetWeaver Release 7.11 and higher, bgRFC can also be used
with the basXML communications protocol."

---

## Sources

bgRFC programming, from the SAP Help Portal RFC documentation:

- [`bgRFC (Background Remote Function Call)`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/927c2caa6b17cee10000000a421937/content.htm) --- multi-queue synchronization point, out-in double recording, no mixing with tRFC/qRFC, no way back
- [`bgRFC Architecture`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9702b055493987e10000000a421937/content.htm) --- dependencies at save time, deferred deletion, the deletion caution
- [`bgRFC Programming`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/929142aa6b17cee10000000a421937/content.htm) --- queues finish their work at COMMIT WORK
- [`API of bgRFC Type t and bgRFC Type q`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/96dc490eec3987e10000000a421937/content.htm) --- object lifetimes, "intentionally or unintentionally"
- [`Calling a Function Module`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/96de810eec3987e10000000a421937/content.htm) --- the statement, bundling, `CX_BGRFC_INVALID_UNIT`
- [`Transactional Consistency Check`](https://help.sap.com/docs/ABAP_PLATFORM_NEW/753088fc00704d0a80e7fbd6803c8adb/89be29c77d1b4b5e80678e4d2da51345.html) --- the forbidden statement list, both runtime errors, `DISABLE_COMMIT_CHECKS`
- [`Creating a Destination Object and Unit Objects`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9295b8aa6b17cee10000000a421937/content.htm) --- singleton, `NONE`/`SPACE` unsupported, EO vs EOIO, outbound auto-registration, `CREATE_GROUP`
- [`Manipulating a Background Unit`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/982d730e0e0e27e10000000a421937/content.htm) --- update-task binding, `LOCK`/`DELAY`, `IS_VALID`, out-in signature
- [`Using Queues to Lock and Unlock Units`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9f4b14f7ec6bb9e10000000a42189d/content.htm) --- queue-lock classes, the interleaving table
- [`Locking a bgRFC Type t Unit`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9f49b1f7ec6bb9e10000000a42189d/content.htm) --- `DELAY`, the alias prerequisite
- [`Locking a Queue`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9f49ecf7ec6bb9e10000000a42189d/content.htm) --- `LOCK_QUEUE_FROM_TOP` / `_FROM_CURRENT_POS`
- [`Filling Multiple Units in Parallel`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9f05f8f7ec6bb9e10000000a42189d/content.htm) --- request order vs queue dependency
- [`RFC Client-Side Runtime Control`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9f48eaf7ec6bb9e10000000a42189d/content.htm) --- state tables, priority rule, `RUN_FAILED_UNIT`
- [`RFC Server-Side Runtime Control`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9f3b34e6af062be10000000a42189d/content.htm) --- `CX_RFC_NO_LUW_EXEC`, `RETRY_UNIT`, `END_OF_UNIT`
- [`Exception Handling`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/96e3db0eec3987e10000000a421937/content.htm) --- the twelve exception classes, `TEXTID`
- [`Examples for Inbound and Outbound Processing`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9620d6a0230e27e10000000a421937/content.htm) --- all five canonical call shapes
- [`Creating Inbound Destinations`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/973e3755493987e10000000a421937/content.htm) --- mandatory queue prefix, per-application destinations
- [`Creating a Supervisor Destination`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9bfc541786062de10000000a42189d/content.htm) --- supervisor rules, SM59 lock, `SAP_BC_BGRFC_SUPERVISOR`
- [`Migration`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/9f0ac6f7ec6bb9e10000000a42189d/content.htm) --- the shared-queue-name prohibition
- [`Authorization Object S_BGRFC`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/927ad2aa6b17cee10000000a421937/content.htm) --- `BGRFC_D_IN` / `BGRFC_D_OU` / `ACTVT` / `BGRFC_TYPE`
- [`RFC`](https://help.sap.com/docs/ABAP_PLATFORM_NEW/753088fc00704d0a80e7fbd6803c8adb/4888068AD9134076E10000000A42189D) --- the variant overview, and bgRFC named as the successor to tRFC and qRFC

ABAP keyword documentation:

- [`CALL FUNCTION IN BACKGROUND UNIT`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/abapcall_function_background_unit.htm) --- update-task dependency and deletion, dialog-module rule, the unit object as `IF_BGRFC_UNIT`
- [`CALL FUNCTION, IN BACKGROUND TASK`](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/8937ad84b84e6fe10000000a421937/content.htm) --- the implicit `NONE`, `AS SEPARATE UNIT`

---

## Related notes in this repo

- [RFC Calls](../RFC%20Calls#readme) --- sRFC/aRFC/tRFC, the blank destination that runs locally, `RESOURCE_FAILURE`
- [Update Task](../Update%20Task#readme) --- V1/V2, registration-not-a-call, why section 4 matters
- [Function Modules](../Function%20Modules#readme) --- what a remote-enabled function module is, and its return codes
- [Enqueue Locks](../Enqueue%20Locks#readme) --- `_SCOPE` and lock ownership across an SAP LUW
- [Program Calls](../Program%20Calls#readme) --- what ends an SAP LUW without saying `COMMIT`
- [Background Jobs](../Background%20Jobs#readme) --- the other way to run work later, and its implicit commits
- [Events](../Events#readme) --- `SET HANDLER` semantics for `END_OF_UNIT`
- [Exception Texts](../Exception%20Texts#readme) --- getting the reason out of a `TEXTID`
- [HTTP Client](../HTTP%20Client#readme) --- the class a unit may not use
- [Messages](../Messages#readme) --- why `MESSAGE` is the one permitted way out of a unit
