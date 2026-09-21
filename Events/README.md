# ABAP Objects Events — The Registration That Outlives Your Reference, and the Handler That Silently Never Runs

`RAISE EVENT` / `SET HANDLER` is how ABAP does publish/subscribe: ALV reacts to a
double click, a BAdI-driven framework notifies listeners, an observer decouples
the thing that changed from the things that care. The mechanism is small — four
statements — and every one of its traps comes from the same place: **registration
is bookkeeping in a system table the runtime owns, not a variable you own.**

None of the traps below produce a syntax error. They produce a handler that keeps
firing after you thought you disposed of it, or one that never fires at all.

Related notes: [BAdIs](../BAdIs#readme) — `CALL BADI` on a multiple-use BAdI is
the framework-level version of the same idea — and
[Exception Flow](../Exception%20Flow#readme) for the `CX_STATIC_CHECK` /
`CX_DYNAMIC_CHECK` distinction that trap 4 depends on.

Runnable demo: [ydj_event_traps_demo.abap](ydj_event_traps_demo.abap) — local
classes and literals only, no DDIC objects and no database access.

## The shape, in one block

```abap
CLASS lcl_order DEFINITION.
  PUBLIC SECTION.
    EVENTS       changed     EXPORTING VALUE(iv_id) TYPE string.
    CLASS-EVENTS all_cleared.
ENDCLASS.

CLASS lcl_watcher DEFINITION.
  PUBLIC SECTION.
    METHODS on_changed FOR EVENT changed OF lcl_order
                       IMPORTING iv_id sender.
ENDCLASS.

SET HANDLER lo_watcher->on_changed FOR lo_order.   " subscribe
RAISE EVENT changed EXPORTING iv_id = mv_id.       " publish
```

Three rules worth fixing in memory immediately:

- Event parameters are **output only and always by value** — `EVENTS` accepts
  nothing but `EXPORTING`, so a handler can never hand a result back to the
  trigger. If you need a return value, you need a method, not an event.
- The handler's `IMPORTING` list may only name parameters the event declared,
  and **may not re-type them** — `TYPE`, `LIKE`, `OPTIONAL` and `DEFAULT` are all
  forbidden there; typing is inherited from the `EVENTS` statement.
- `RAISE EVENT` is **synchronous**. Every handler runs to completion, in the
  same work process and the same LUW, before the statement after `RAISE EVENT`
  executes. An event is not a queue and not a background task.

## Trap 1: registration keeps the handler object alive

`SET HANDLER` stores a reference to the handler object in a system table, and
that reference counts for garbage collection exactly like one in a variable.

> "When an instance method is registered, a reference to the corresponding
> object is added in the relevant table and then deleted again when
> deregistering. With respect to the Garbage Collector, such a reference has the
> same effect as a reference in a reference variable. **Objects registered as
> handlers are therefore not deleted as long as they are registered**"
> — [ABAP keyword documentation, SET HANDLER](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapset_handler.htm)

So this does nothing useful:

```abap
SET HANDLER lo_watcher->on_changed FOR lo_order.
CLEAR lo_watcher.          " your reference is gone
lo_order->touch( ).        " ... and the watcher handles it anyway
```

Two practical consequences. First, this is a genuine **memory leak shape**: a
long-running session that registers a handler per document and never
deregisters accumulates handler objects that nothing can collect. Second, once
you have dropped the last reference you can no longer *write* the deregistration
statement — `SET HANDLER ... ACTIVATION space` needs a reference to name the
handler. The object is unstoppable for the rest of the session.

The converse is the benign half: if the **triggering** instance is collected, its
registration table goes with it and the registrations vanish on their own.

## Trap 2: double registration is not a double call

Registering the same handler for the same event twice does not give you two
calls. The second `SET HANDLER` quietly fails:

| `sy-subrc` | Meaning |
|---|---|
| 0 | all specified handlers were registered or deregistered |
| 4 | at least one could **not be registered** — already registered for that event |
| 8 | at least one could **not be deregistered** — was not registered for that event |

This is the rare case where the *safe* behaviour is the surprising one: an
idempotent `SET HANDLER` in a method that runs twice is harmless. The reason to
know the table is the inverse situation — code that *expects* two registrations
(two handler objects, but one was accidentally a reused reference) silently gets
one, and code that deregisters defensively gets `sy-subrc = 8` and often an
error log entry for a condition that is completely normal.

## Trap 3: mass deregistration does not cancel a single registration

`SET HANDLER` maintains **separate system tables** for single registrations
(`FOR oref`), mass registrations (`FOR ALL INSTANCES`) and static events. The
cleanup statement has to match the form of the registration statement:

> "A single registration cannot, however, be deregistered using mass
> deregistration. Conversely, individual raising objects cannot be excluded from
> registration after a mass registration."
> — [ABAP keyword documentation, SET HANDLER FOR](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapset_handler_instance.htm)

```abap
SET HANDLER lo_watcher->on_changed FOR lo_order.                            " single
SET HANDLER lo_watcher->on_changed FOR ALL INSTANCES ACTIVATION space.      " no effect
lo_order->touch( ).                                                          " still handled
SET HANDLER lo_watcher->on_changed FOR lo_order ACTIVATION space.           " this works
```

The tell is `sy-subrc = 8` on the mass statement — the one nobody checks after a
`SET HANDLER`. A "disable all listeners" teardown written as a single
`FOR ALL INSTANCES ACTIVATION space` therefore leaves every per-object
subscription in place, and the second half of the trap is the same in reverse:
after a mass registration you cannot carve out one object as an exception.

`ACTIVATION` takes a single-character text-like field: `'X'` (the default)
registers, blank deregisters. Since it is a field and not a keyword, the value
can be computed — which is the supported way to write a conditional subscription
without an `IF` around two near-identical statements.

## Trap 4: an exception in one handler cancels the whole event

Trigger and handler are fully decoupled — the trigger does not know who is
listening — so ABAP forbids an event handler from declaring `RAISING` at all.
That restriction has a consequence most developers meet as a dump:

> "If a violation of the interface occurs during event handling, **event handling
> is terminated**, and the control is given back to the trigger of the event.
> Further event handlers which are still registered for the event are not
> executed."
> — [ABAP keyword documentation, Class-Based Exceptions in Event Handlers](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abenexceptions_events.htm)

An unhandled `CX_STATIC_CHECK` or `CX_DYNAMIC_CHECK` inside a handler violates
that empty `RAISING` interface, so `CX_SY_NO_HANDLER` is raised — and it surfaces
**at the trigger**, at the `RAISE EVENT` statement, with no indication of which
handler failed. Combine it with the ordering rule:

> "The order of the calls of registered event handlers is not defined and can
> change at program runtime."

and you get the actual field symptom: five listeners, one of them broken, and
which of the other four ran before the failure varies between executions. The
bug looks intermittent and looks like it lives in the trigger.

The rule that follows is unambiguous — **a handler must catch everything it can
raise.** The trigger side should not try to repair the original error after
catching `CX_SY_NO_HANDLER`; per the same page, at that point it is not even
determined which handler was running. Catching it is damage limitation against a
programming error in someone else's listener, nothing more.

Related: a `CX_NO_CHECK` exception is not an interface violation (nothing can
declare it), so it propagates to the trigger as itself.

## Trap 5: `FOR ALL INSTANCES` is retroactive, and static events take no `FOR`

`FOR ALL INSTANCES` is not "all objects that exist right now":

> "Such a registration also applies to all raising instances created after the
> statement `SET HANDLER`." … "Registration with `FOR ALL INSTANCES` applies also
> in particular to temporary instances that can be created when using the
> instantiation operator `NEW`."

So a handler registered before any trigger object exists still handles every one
created later, including `NEW lcl_order( )->touch( )` where the instance is never
stored anywhere. That is genuinely useful for tracing and logging, and it is also
how an innocuous-looking `SET HANDLER` in an initialisation routine ends up
running for objects a completely unrelated part of the program created.

Static events (`CLASS-EVENTS`) use the second syntax form, with **no `FOR`
clause** — there is no instance to bind to:

```abap
SET HANDLER lo_watcher->on_cleared.        " static event: no FOR
SET HANDLER lo_watcher->on_changed FOR lo_order.   " instance event: FOR required
```

Getting this wrong is one of the few event mistakes that fails loudly, via the
uncatchable runtime errors `SET_HANDLER_E_NO_FOR` (instance handler registered
without `FOR`) and `SET_HANDLER_FOR_CE` (handler for a static event registered
with one). The other uncatchable ones worth recognising: `SET_HANDLER_FOR_NULL`
and `SET_HANDLER_HOBJ_NULL` for an initial trigger or handler reference, and
`SET_HANDLER_DISP_OVERFLOW` when no further handlers can be registered — the
diagnostic for the leak in trap 1.

One more ceiling: a handler may raise further events, but nesting is capped at
**1023** levels, after which `RAISE_EVENT_NESTING_LIMIT` terminates the program.
Two handlers that raise each other's events hit it almost immediately.

## `sender`, and the one thing it is not

Every **instance** event has an implicit output parameter `sender`, automatically
filled with a reference to the raising object. It is never passed at the
`RAISE EVENT` — the documentation says outright it "cannot be specified
explicitly after `EXPORTING`".

The subtlety is its **static** type: `sender` is typed from whatever class or
interface the handler named after `FOR EVENT evt OF`, not from the actual class
of the raiser.

> "The dynamic type of the implicit formal parameter `sender` is always the class
> of the object in which the event is raised."
> — [ABAP keyword documentation, EVENTS](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapevents.htm)

So a handler declared `FOR EVENT changed OF lcl_order` receives `sender` typed as
`lcl_order` even when the raiser is a subclass — reaching subclass-specific
components needs a down-cast, and each handler independently decides how
narrowly its own `sender` is typed. Static events have no `sender` at all, since
no instance raised them.

Also worth knowing for inheritance: when a static event is raised in a static
method, the raising class is the class where the method is *declared*, not the
subclass whose name you used to call it.

## Practical checklist

- Deregister with the **same form** you registered with (`FOR oref` ↔ `FOR oref`,
  `FOR ALL INSTANCES` ↔ `FOR ALL INSTANCES`).
- Keep the handler reference until you have deregistered, or accept that the
  object lives for the session.
- Catch everything inside a handler. It cannot declare `RAISING`, and leaking an
  exception silently skips every other listener.
- Never depend on handler execution order. If order matters, register one handler
  and have it call the others in the order you want — that is the documentation's
  own recommendation.
- Do not use an event where you need a result back: parameters are output-only.

## Sources

- [SET HANDLER](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapset_handler.htm) — `sy-subrc` table, GC behaviour, uncatchable exceptions, undefined handler order
- [SET HANDLER, FOR](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapset_handler_instance.htm) — `FOR ALL INSTANCES` retroactivity, `ACTIVATION`, the single-vs-mass rule
- [RAISE EVENT](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapraise_event.htm) — synchronous execution, `sender`, the 1023 nesting limit
- [EVENTS](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapevents.htm) — output-only by-value parameters, `sender` static vs dynamic type
- [METHODS, FOR EVENT](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapmethods_event_handler.htm) — handler declaration rules, no re-typing, visibility rule, static-event inheritance note
- [Class-Based Exceptions in Event Handlers](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abenexceptions_events.htm) — no `RAISING`, `CX_SY_NO_HANDLER`, cancelled handling
