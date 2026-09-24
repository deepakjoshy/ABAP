# Shared Objects — The Reader You Forgot to Detach and the Commit That Is Not Visible Yet

Shared objects are ABAP's cross-session cache: an object graph that lives in the
**shared memory of one AS instance**, built once and read by every program on
that instance without touching the database. Areas are defined in transaction
`SHMA`, which generates an *area class*; you reach the data through an *area
handle* returned by `attach_for_read( )` / `attach_for_write( )`.

That is the part everybody knows. The part that produces incidents is that the
whole mechanism is built out of **locks**, and almost every default in it is
optimised for the writer rather than for the program that forgot something:

- A shared lock you never released does not just leak memory — it **blocks every
  future write** on a non-versioned area, permanently, until the session ends.
- After `detach_commit( )` your data is **not visible yet**, and on a
  non-versioned area it is not even readable, until the next database commit.
- Two of the cleanup methods terminate *other people's programs* with a runtime
  error, and they do it **by default**.

The one-sentence version: **`attach` is a lock, not an open — and the default
for "what do I do about the other guy" is almost never the safe one.**

Related notes: [Enqueue Locks](../Enqueue%20Locks#readme) for the *other* ABAP
lock concept (SAP locks are advisory and cross-instance; shared-object locks are
enforced and instance-local — they are not the same thing and do not interact),
[Internal Table Memory](../Table%20Memory#readme) for what the objects you are
about to copy into the area actually cost, [Update Task](../Update%20Task#readme)
and [Commit Work Events](../Commit%20Work%20Events#readme) for the database
commit that trap 3 hangs on, [Events](../Events#readme) for the event mechanism
that trap 8 says you may not use here at all, and
[Exception Flow](../Exception%20Flow#readme) for the `CLEANUP` shape that trap 4
needs.

Runnable demo: [ydj_shared_objects_demo.abap](ydj_shared_objects_demo.abap). It
runs **without SHMA**, using the predefined internal-session area handle — see
the honesty note in section 10 for exactly what that does and does not prove.

## The shape, in one block

```abap
" WRITE side - exclusive lock, build the graph, set the root, commit.
DATA(lo_handle) = zcl_my_area=>attach_for_write( ).

CREATE OBJECT lo_root AREA HANDLE lo_handle.   " object lands IN the area
lo_handle->set_root( lo_root ).                " MANDATORY before commit
CREATE OBJECT lo_root->child AREA HANDLE lo_handle TYPE zcl_child.

lo_handle->detach_commit( ).                   " ... and see trap 3

" READ side - shared lock, read through ->root, then LET GO.
DATA(lo_read) = zcl_my_area=>attach_for_read( ).
DATA(lt_data) = lo_read->root->get_data( ).
lo_read->detach( ).                            " see trap 1
```

Both classes involved must be declared shared-memory-enabled:

```abap
CLASS zcl_my_root DEFINITION PUBLIC FINAL CREATE PUBLIC
  SHARED MEMORY ENABLED.                       " and see trap 8
```

Everything below is a way that block goes wrong.

## Trap 1: a shared lock is held by the *session*, and forgetting `detach` blocks writers

`attach_for_read( )` does not "open" the area. It sets a **shared lock**, and
that lock belongs to the internal session, not to the reference variable. Two
consequences, and the second one is the outage.

First, attaching twice in the same session is an error, not a no-op:

> `CX_SHM_READ_LOCK_ACTIVE` — The area instance version is already locked for
> reading in the same internal session.

So a utility method that helpfully does `attach_for_read( )` per call, called
twice in one transaction, raises on the second call. The fix is to attach once
and pass the handle, or to wrap the area in a single accessor class — which the
documentation recommends anyway for a different reason (trap 7).

Second, and worse: on an area **without versioning**, a live shared lock stops
`attach_for_write( )` from succeeding at all. With the default attach mode:

> `CL_SHM_AREA=>ATTACH_MODE_DEFAULT` — If there are shared locks on the area
> instance of the specified name, these are not released. For areas with
> versioning, the system attempts to create a new version. In the case of areas
> without versioning, the exception `CX_SHM_VERSION_LIMIT_EXCEEDED` is raised.

Read that again in operational terms. One long-running dialog session that read
the cache and never called `detach( )` will make **every** refresh job on that
application server fail with `CX_SHM_VERSION_LIMIT_EXCEEDED` — not the run after
next, every single one — until that session ends. The cache goes stale and
nothing in the writer's own code is wrong.

The three ways out, in order of preference:

| | Effect |
|---|---|
| `detach( )` in a `CLEANUP` block | The actual fix. The reader always lets go, including on the exception path. |
| Enable versioning in `SHMA` | Writer builds a new version alongside the readers; old readers keep the old one. Costs memory (`MAX_VERSIONS` copies). |
| `ATTACH_MODE_DETACH_READER` | Writer **forcibly releases** the readers' locks. See trap 6 for what that does to them. |

`cl_shm_area=>detach_all_areas( )` releases everything the session holds, across
all areas, and is the right thing to call in a generic error handler.

## Trap 2: `attach_for_write` is not a wait — unless you ask, and then only one waiter

By default, a writer that meets another writer does not queue. It raises
`CX_SHM_EXCLUSIVE_LOCK_ACTIVE` immediately, with an exception text that tells
you which case you hit — `LOCKED_BY_ACTIVE_CHANGER` (someone is changing it),
`LOCKED_BY_PENDING_CHANGER` (someone is *waiting* to change it), or
`WAITING_FOR_DB_COMMIT` (trap 3).

You can ask to wait with `attach_mode = cl_shm_area=>attach_mode_wait` and
`wait_time` in **milliseconds**. Two documented constraints that surprise people:

- **Only one waiter, ever.** "Only one program with the parameter `WAIT_TIME`
  can wait for an area instance at any one time. If a different program tries to
  set another exclusive lock with the parameter `WAIT_TIME`, this raises the
  exception `CX_SHM_EXCLUSIVE_LOCK_ACTIVE` directly (exception text
  `LOCKED_BY_PENDING_CHANGER`)." So a wait time does not build a queue — the
  second waiter fails instantly. Under load this looks like the wait time being
  ignored.
- Passing a non-zero `wait_time` **without** `attach_mode_wait`, or a negative
  one, is `CX_SHM_PARAMETER_ERROR` — not a silently ignored parameter.

And an administrative one that no amount of code review will catch: if the
pending lock is deleted in transaction `SHMM` while you are waiting, your
program gets `CX_SHM_PENDING_LOCK_REMOVED`. A basis action raises an application
exception in your session.

## Trap 3: `detach_commit( )` does not publish your data — the database commit does

This is the one that makes people think shared objects are broken. Areas are
**transactional by default** (`PROPERTIES-TRANSACTIONAL = abap_true`):

> In the case of transactional areas [...] the changes that are completed when
> the method `DETACH_COMMIT` is executed are **not active until the next
> database commit**.

Between `detach_commit( )` and that database commit, the documentation lists
exactly what is possible:

| Area | Reads in that window | New change lock in that window |
|---|---|---|
| Transactional **with** versioning | Allowed — but they get the **previous** version | Not possible |
| Transactional **without** versioning | **Not possible at all** | Not possible |
| Non-transactional | Active immediately after `detach_commit( )` | Allowed |

So the natural self-test — write the cache, then immediately read it back to
prove it worked — reads stale data on a versioned area and raises
`CX_SHM_EXCLUSIVE_LOCK_ACTIVE` with text `WAITING_FOR_DB_COMMIT` on a
non-versioned one. Both look like the write silently failed. It did not; it is
waiting for a `COMMIT WORK` that a report doing no database updates may never
issue.

Two corollaries worth writing down:

- The same window blocks the *writer*: trying to take another change lock before
  the database commit gives `CX_SHM_CHANGE_LOCK_ACTIVE` with text
  `WAITING_FOR_DB_COMMIT`. A loop that refreshes several area instances per run
  has to let a commit through between them.
- `detach_rollback( )` has no such delay — "a new change lock can be set on the
  relevant area instance (even before the next database commit)".

All the time-based properties inherit this too: for transactional areas,
`IDLE_TIME` / `INVALIDATE_TIME` / `REFRESH_TIME` start counting "with the first
database commit after a lock is released using the method `DETACH_COMMIT`", not
at `detach_commit( )` itself.

## Trap 4: a failed `detach_commit( )` leaves the lock held, and you cannot commit again

Normally a failed method leaves you where you were. Not here:

> If an exception is raised when the method is executed, the change lock is
> **not released correctly**. Although it is persisted, the lock cannot be
> released a second time using the method `DETACH_COMMIT`. The
> `DETACH_ROLLBACK` can be used instead.

So the instinctive `CATCH ... retry the commit` is the one thing that is
guaranteed not to work — it raises `CX_SHM_SECONDARY_COMMIT`. Meanwhile the
exclusive lock is still there, blocking every other writer (trap 2) until the
session ends.

The handle tells you it is in this state: `get_lock_kind( )` returns
`CL_SHM_AREA=>LOCK_KIND_COMPLETION_ERROR`, which exists for precisely this
situation. So the correct error handler is *always* `detach_rollback( )`, never
a retry:

```abap
TRY.
    DATA(lo_handle) = zcl_my_area=>attach_for_write( ).
    " ... build the graph ...
    lo_handle->set_root( lo_root ).
    lo_handle->detach_commit( ).
  CATCH cx_shm_error INTO DATA(lx).
    IF lo_handle IS BOUND AND
       lo_handle->get_lock_kind( ) <> cl_shm_area=>lock_kind_detached.
      lo_handle->detach_rollback( ).       " NOT detach_commit( ) again
    ENDIF.
ENDTRY.
```

Note `cx_shm_error` rather than `cx_root`: `cx_shm_completion_error` and
`cx_shm_secondary_commit` are both subclasses of `cx_shm_detach_error`, and the
attach-side classes are subclasses of `cx_shm_attach_error`.

## Trap 5: the commit fails if *anything* in the area still points outside it

`detach_commit( )` has two preconditions, and both raise subclasses of
`CX_SHM_COMPLETION_ERROR`:

- **`CX_SHM_ROOT_OBJECT_INITIAL`** — you never called `set_root( )`. The area
  instance must contain a root object. `set_root( )` also only works on a handle
  with an exclusive lock, and passing an initial reference is
  `CX_SHM_INITIAL_REFERENCE`.
- **`CX_SHM_EXTERNAL_REFERENCE`** — "there must be no references from the area
  instance version to a different area instance of the shared objects memory or
  to the **internal session**."

The second one is the real trap, because it fails at the *end* of a build that
looked fine. Every object reachable from the root must have been created with
`CREATE OBJECT ... AREA HANDLE`. One ordinary `CREATE OBJECT lo_helper` — a
logger, a comparator, a formatter that somebody attached to a node for
convenience — and the whole build is thrown away at the last statement, with an
exception that names the condition but not the offending object.

The rule to code by: inside a build, **`CREATE OBJECT` without `AREA HANDLE` is
a bug**. And the class being instantiated must be declared
`SHARED MEMORY ENABLED`, which is only allowed on a subclass "if all its
superclasses have been defined with this addition" — and which subclasses do
**not** inherit automatically.

For anonymous data objects the equivalent statement is
`CREATE DATA dref AREA HANDLE handle`, with a restriction that catches dynamic
programming: types created at runtime via RTTC or `GENERATE SUBROUTINE POOL`
cannot be stored in a closed area instance version, and the failure again
surfaces late — `CX_SHM_EXTERNAL_TYPE` at `detach_commit( )`. (Exceptions: type
`p` always, and `c`/`n`/`x` up to 100 bytes. See
[Runtime Type Services](../Runtime%20Type%20Services#readme).)

## Trap 6: `invalidate` and `free` short-dump other people's programs — by default

The cleanup methods take a parameter `TERMINATE_CHANGER`, and its default value
is `ABAP_TRUE`. The documentation flags this as a Caution:

> Once this method is executed and `ABAP_TRUE` is passed to `TERMINATE_CHANGER`,
> all programs where there is still an exclusive lock for the invalidated area
> instance are terminated with the runtime error `SYSTEM_SHM_AREA_OBSOLETE`.

`FREE_INSTANCE` / `FREE_AREA` go further — *any* remaining area handle, not just
a change lock, gets its program terminated:

> After this method has been executed, all programs in which area handles still
> exist for the released area instance versions terminate with the runtime error
> `SYSTEM_SHM_AREA_OBSOLETE`.

That is a **runtime error**, not an exception: it does not travel through the
victim's `TRY`/`CATCH`, and it lands in `ST22` with the victim's program name on
it, hours away from the housekeeping job that actually caused it. If you write a
"clear the cache" utility, pass `terminate_changer = abap_false` unless you have
specifically decided otherwise.

The same danger arrives through the writer's side door:
`ATTACH_MODE_DETACH_READER` releases the readers' shared locks to let the write
through. It does not notify them. A reader that later dereferences its handle is
working with an invalidated handle, and `get_detach_info( )` is the only way to
find out why — it returns `DETACH_INFO_ATTACH` for exactly this case,
`DETACH_INFO_INVALIDATE` for trap 6's methods, `DETACH_INFO_FREE`,
`DETACH_INFO_HANDLE` for your own explicit detach, and
`DETACH_INFO_NOT_DETACHED` if the handle is still fine. Pair it with
`is_valid( )` / `is_active_version( )` from `CL_ABAP_MEMORY_AREA`.

Also note the distinction the names do not make: `invalidate_*` sets versions to
**obsolete** (existing shared locks keep working), `free_*` sets them to
**expired** and releases all shared locks. And both return
`RC_NOTHING_TO_BE_DONE` *always* on a transactional area, so the return code
proves nothing there.

## Trap 7: `CX_SHM_OUT_OF_MEMORY` can be raised by the *read* path

The shared objects memory is a fixed budget — profile parameter
`abap/shared_objects_size_MB`, visible in `ST02`. When it is exhausted you get a
handleable `CX_SHM_OUT_OF_MEMORY`, and the documented list of when includes one
that is easy to miss:

- when shared objects are created or changed,
- when locks are removed using `DETACH_COMMIT`,
- when locks are created using `ATTACH_FOR_WRITE` or `ATTACH_FOR_UPDATE` — "or
  even using `ATTACH_FOR_READ` if there is no longer sufficient space for the
  administration information".

So a pure reader can fail for out-of-memory. The documentation's own advice is
to funnel all shared-object access through a single wrapper class and a single
`TRY`, to check `get_lock_kind( )` in the handler, and to release with
`detach_rollback( )` if an exclusive lock is still held — and it explicitly asks
for a **fallback strategy**, "for example a strategy to create the required
objects in the internal session and copy the previous content from the shared
memory to these objects". A cache that dumps when it is full is not a cache.

Budgeting is harder than it looks, too: `MAX_AREA_SIZE` and `MAX_VERSION_SIZE`
are in **KB** and default to `0` = unlimited, there is "no memory restriction
for logical areas", and — the one that hurts during diagnosis — "the memory
consumption of shared objects in the shared memory **cannot be monitored using
Memory Inspector**". `SHMM` is the tool, not `S_MEMORY_INSPECTOR`.

## Trap 8: a shared-memory-enabled class may not have events, and its static attributes are not shared

Two restrictions on `SHARED MEMORY ENABLED` that change how you design the class:

> No events can be declared or handled in a shared-memory-enabled class. The
> statements `[CLASS-]EVENTS` and the addition `FOR EVENT` cannot be specified in
> the declaration part.

So the usual "the cache raises `changed` and listeners react" design is not
available inside the area at all (see [Events](../Events#readme)). Notification
has to come from the *area handle* instead: `CL_SHM_AREA` raises
`SHM_COMMIT_EVENT` and `SHM_ROLLBACK_EVENT` automatically. Handle them with care
— an exception escaping such a handler becomes `CX_SHM_EVENT_EXECUTION_FAILED`,
with the original reachable via `PREVIOUS`, and it fails the detach.

And the quieter one:

> The static attributes of a shared object are **not** created in the shared
> memory. Instead, they are created when the shared-memory-enabled class is
> loaded to the internal session of a program, as for every class. They can thus
> occur more than once and independently of one another in different programs.

A hit counter, a "last refreshed at", a lazily-initialised singleton held in a
static attribute of the root class: each program gets its own copy. The value is
per-session and always looks plausible, which is why it is usually discovered as
"the statistics are wrong" rather than as a bug in the cache. Anything that must
be shared has to be an **instance** attribute reachable from the root object.
The documentation adds the same warning from the other direction: do not make a
class shared-memory-enabled if it "has static attributes that contain
information about all the instances as a whole", or if it "allocates its own
memory internally".

## Trap 9: the automatic build does not make the caller wait

If the area has an area constructor (a class implementing
`IF_SHM_BUILD_INSTANCE`, configured in `SHMA`), a read against an empty area can
trigger it. What it does not do is block until the data is there:

> The area instance version does not exist and the area constructor was called
> (exception text: `BUILD_STARTED`). The system **does not wait** for the
> automatic area build to be terminated when the exception is caught.

So the first reader after an instance restart gets `CX_SHM_NO_ACTIVE_VERSION`
even though everything is configured correctly, and an immediate retry gets
`BUILD_NOT_FINISHED`. The exception texts are the whole diagnosis and are worth
logging individually:

| Text | Meaning |
|---|---|
| `NEITHER_BUILD_NOR_LOAD` | No area constructor and no displaced version — nothing will ever build it. Real configuration error. |
| `BUILD_STARTED` | A build was just kicked off. Retry later, not immediately. The doc notes that seeing this **twice in succession** means the constructor did not end correctly. |
| `BUILD_NOT_FINISHED` | A build is in progress. |
| `LOAD_STARTED` / `LOAD_NOT_FINISHED` | A displaced (serialized) version is being reloaded. |

`BUILD( )` calls the constructor **explicitly and synchronously in the current
session**, which is what a warm-up job should use — `CX_SHMA_NOT_CONFIGURED`
tells you no constructor class is bound, `CX_SHMA_INCONSISTENT` that the area
class needs regenerating in `SHMA`.

`ATTACH_FOR_UPDATE` (update lock — a change lock that starts from the *existing*
content, where `ATTACH_FOR_WRITE` starts a fresh version) needs an active version
by definition, so it starts the constructor too, and with `wait_time` set it has
its own three-way outcome: lock granted, wait cut short because the build could
not produce a version, or `BUILD_NOT_FINISHED` at the end of the wait.

## Trap 10: the cache is per application server, and lives as long as it does

`LIFE_CONTEXT` defaults to `LIFE_CONTEXT_APPSERVER`, and the restrictions page is
blunt about the consequence: "The lifetime of area instances cannot be bound to
the lifetime of user sessions, ABAP sessions, or transactions. Area instances
currently exist **as long as the AS Instance**."

Two practical results. First, a four-application-server system has **four
independent copies** of the cache, filled at different times, and a user's
answer depends on which server dispatched them. Second, invalidating after a
database change is not local: `invalidate_*` and `free_*` take `AFFECT_SERVER`,
defaulting to `AFFECT_LOCAL_SERVER`. Cross-server invalidation needs
`AFFECT_ALL_SERVERS` — or `AFFECT_ALL_SERVERS_BUT_LOCAL`, which lets the server
that just did the update keep its freshly built version instead of rebuilding it
from the database. (The older `PROPAGATE_INSTANCE` / `PROPAGATE_AREA` methods are
marked obsolete in favour of exactly this parameter.)

On displacement: `DISPLACE_KIND` defaults to `DISPLACE_KIND_NONE`.
`DISPLACE_KIND_SERIALIZABLE` serializes and persists the content before
displacing it — every class in the area must then implement
`IF_SERIALIZABLE_OBJECT`, and `CREATE OBJECT ... AREA HANDLE` raises
`CX_SHM_OBJECT_NOT_SERIALIZABLE` if one does not.
`DISPLACE_KIND_DISPLACABLE` simply **loses the content**, and only displaces
while no handle is bound.

One more, for anyone diagnosing a transport: `CX_SHM_INCONSISTENT` on attach
means the type of an object stored in the area no longer matches the type in
your session — i.e. someone activated a structure while a built cache was
sitting in memory. It is fixed by rebuilding the instance (or restarting the
program, depending on which side is newer), not by a code change.

## What the demo can and cannot show

The runnable demo in this folder does **not** need `SHMA`, because a real area
needs a global root class, a global area class and a configured area — none of
which can live in a report. Instead it uses the predefined area handle for the
current internal session:

```abap
DATA(lo_handle) = cl_imode_area=>get_imode_handle( ).
CREATE OBJECT lo_root AREA HANDLE lo_handle.
```

The documentation is explicit that in this case "the statement `CREATE OBJECT`
operates as if the addition `AREA HANDLE` were not specified". So the demo
genuinely exercises the `AREA HANDLE` syntax, the `SHARED MEMORY ENABLED`
restrictions, `CL_ABAP_MEMORY_AREA`'s inspection methods and the
`GET_HANDLE_BY_OREF` round trip — but it is **not** shared memory, there are no
locks, and it therefore cannot demonstrate traps 1-4 or 6 live. Those are shown
as commented reference blocks against a hypothetical `ZCL_MY_AREA`, in the same
style as the [AMDP](../AMDP#readme) and
[Enhancement Framework](../Enhancement%20Framework#readme) demos. Read section
numbers in the demo against the trap numbers here.

## Sources

- [Shared Objects — Restrictions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSHM_RESTRICTIONS.html)
- [Shared Objects — Memory Bottlenecks (`CX_SHM_OUT_OF_MEMORY`)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSHM_OBJECTS_OUT_OF_MEMORY.html)
- [Shared Objects — Area Class (`ATTACH_*`, `INVALIDATE_*`, `FREE_*`, `SET_ROOT`)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSHM_AREA_CLASS.html)
- [Shared Objects — `CL_SHM_AREA` (`DETACH_COMMIT`, `GET_LOCK_KIND`, `MULTI_ATTACH`, properties)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSHM_CL_SHM_AREA.html)
- [Shared Objects — `CL_ABAP_MEMORY_AREA` (`GET_DETACH_INFO`, `IS_VALID`)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSHM_CL_ABAP_MEMORY_AREA.html)
- [Shared Objects — `IF_SHM_BUILD_INSTANCE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSHM_IF_SHM_BUILD_INSTANCE.html)
- [`CREATE OBJECT` — `AREA HANDLE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCREATE_OBJECT_AREA_HANDLE.html)
- [`CREATE DATA` — `AREA HANDLE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCREATE_DATA_AREA_HANDLE.html)
- [`CLASS` — `SHARED MEMORY ENABLED`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCLASS_OPTIONS.html)
