# SAP Locks (ENQUEUE) — _SCOPE, generic locks and the traps around them

A lock object in SE11 generates `ENQUEUE_<obj>` / `DEQUEUE_<obj>`. Calling them is
easy; the three parameters that decide whether the lock actually protects anything —
`_SCOPE`, `X_<field>` and `_WAIT` — are the ones most code gets wrong. All three
fail *silently*: no dump, no `sy-subrc`, just a lock that is broader, shorter or
longer-lived than intended.

This note is the lock-side companion to [`Commit Work Events`](../Commit%20Work%20Events#readme) —
`COMMIT WORK` is also the statement that hands locks to the update task.

## Trap 1: `_SCOPE` decides who owns the lock, and the defaults differ per module

Every SAP LUW starts with **two lock owners**: the dialog owner and the update owner.
`_SCOPE` says which of them your lock belongs to.

| `_SCOPE` | Owner | Released when |
|---|---|---|
| `1` | dialog only | explicit `DEQUEUE`, or end of program. **`COMMIT WORK` / `ROLLBACK WORK` do nothing to it.** |
| `2` | update only | `COMMIT WORK` hands it to the update task; released when the update finishes. `ROLLBACK WORK` releases it immediately. |
| `3` | both | when the *last* of the two owners releases it |

Two things bite here:

- **The defaults are asymmetric.** `_SCOPE` defaults to **`2` for ENQUEUE** and
  **`3` for DEQUEUE**. Code that calls enqueue with no `_SCOPE` and then rolls back
  has different lock behaviour from code that passes `_SCOPE = '1'` — and the
  difference is invisible until two users collide.
- **`_SCOPE = 2` only works if there is an update.** If `COMMIT WORK` runs *before*
  any `CALL FUNCTION ... IN UPDATE TASK` was registered, the commit has **no effect
  on the lock** — it stays a dialog lock (shown in black in `SM12`) until the program
  ends. "I committed, why is it still locked?" is almost always this.

`_SCOPE` is a property of the *operation*, not of the lock, so you can call
`ENQUEUE` again with `_SCOPE = '2'` on a lock you already hold with `_SCOPE = '1'`;
the result is identical to having used `_SCOPE = '3'` once. After the update
finishes, a `_SCOPE = 3` lock degrades back to `_SCOPE = 1`.

One rule when releasing: **`_SCOPE` on `DEQUEUE` must be >= the `_SCOPE` used on
`ENQUEUE`**, or the release does not cover the owner that holds the lock.

## Trap 2: an unfilled key field locks *everything*

If you pass no value for a key field, the lock is **generic** — it covers every row
matching the fields you did fill. Leave `fldate` empty and you have locked every
date of that connection, not one flight:

```abap
" Locks ALL dates of LH 0400 - almost never what the caller meant.
CALL FUNCTION 'ENQUEUE_EDEMOFLHT'
  EXPORTING mode_sflight = 'E'
            carrid       = 'LH'
            connid       = '0400'
  EXCEPTIONS foreign_lock = 1 system_failure = 2 OTHERS = 3.
```

The nasty version is a *variable* that happens to be initial — a field the user left
blank silently widens the lock from one row to a whole range.

To lock on a genuinely initial value rather than generically, use the companion
parameter generated for every lock field, **`X_<field>`**:

| `<field>` | `X_<field>` | Result |
|---|---|---|
| initial | `' '` | **generic** lock over `<field>` |
| initial | `'X'` | lock on exactly the initial value of `<field>` |
| filled | (ignored) | lock on that value |

## Trap 3: `_WAIT` and the `FOREIGN_LOCK` exception

By default a failed lock raises `FOREIGN_LOCK` immediately. The competing user's
name is in **`sy-msgv1`** — read it there, and put it in the message, so the user
knows who to call:

```abap
IF sy-subrc = 1.
  MESSAGE e888(sabapdemos) WITH 'Locked by' sy-msgv1.
ENDIF.
```

Passing `_WAIT = 'X'` retries for a while before giving up, which is right for
background jobs and usually wrong for dialog (it just freezes the screen).

The other exception, `SYSTEM_FAILURE`, means the enqueue server rejected the
request — **the lock was not set**. Treat it exactly like `FOREIGN_LOCK`, never as
a warning to log and continue past.

## Smaller things worth knowing

- **`@` is a wildcard in the lock argument.** A key value containing `@` matches
  anything in that position during collision checks, so a lock you thought was on
  one row silently collides with unrelated rows. Sanitise key values that can carry
  `@` (email-like keys, free text) before the enqueue call. Only printable
  characters are allowed in a lock argument at all.
- **Lock modes:** `S` shared, `E` exclusive (cumulative — the same owner may request
  it repeatedly and release one by one), `X` exclusive non-cumulative (a second
  request by the same owner is **rejected**), `O` optimistic (behaves as shared,
  convertible to exclusive). Reusable helper methods that may be called twice in one
  LUW want `E`, not `X`.
- **`_COLLECT = 'X'`** buffers requests in the local lock container until
  `FLUSH_ENQUEUE` — useful for mass locking, but explicitly *bad* with mode `X` when
  many locks hit the same lock table.
- **`_SYNCHRON = 'X'` on DEQUEUE** waits until the entry is really gone. Without it
  the release is asynchronous, so reading `SM12`/the lock table straight after a
  dequeue can still show the entry.
- **Never transport the generated function groups**, only the lock object — the
  modules are regenerated (into possibly different function groups) on activation in
  the target system.
- SAP locks are *advisory*. A plain `SELECT`/`UPDATE` that does not call the enqueue
  module ignores them completely. They only work if every writer agrees to ask.

## References

- [SAP Locks — ABAP keyword documentation](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSAP_LOCK.html)
- [_SCOPE Parameters — SAP Help](https://help.sap.com/doc/saphelp_nw73ehp1/7.31.19/en-us/47/daadf638793c85e10000000a42189c/content.htm)
- [Function Modules for Lock Requests — SAP Help](https://help.sap.com/saphelp_SCM700_ehp02/helpdata/en/cf/21eebf446011d189700000e8322d00/content.htm)
- [SAP Lock Concept (lock modes, wildcards, lifetime) — SAP Help](https://help.sap.com/saphelp_ewm900/helpdata/en/47/daeac909dd3020e10000000a42189d/content.htm)
- [Locking and Unlocking — executable example (EDEMOFLHT)](https://help.sap.com/doc/abapdocu_750_index_htm/7.50/en-US/abenenqueue_abexa.htm)

See `ydj_enqueue_lock_demo.abap` in this folder for a runnable version of all three
traps against the flight data model.
