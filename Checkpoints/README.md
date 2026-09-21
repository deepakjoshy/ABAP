# Checkpoints — The ASSERT That Dumps in Production, and the Log That Keeps One Entry

`ASSERT`, `LOG-POINT` and `BREAK-POINT` are the three **checkpoint** statements:
instrumentation you leave permanently in the source so the state of a running
program can be inspected later, on a system you cannot debug interactively.

They look like debugging leftovers, and that is exactly why they are dangerous.
The documentation is blunt about their standing:

> "These statements have no operative character and are thus not part of the
> program logic."

Not part of the program logic — but an `ASSERT` absolutely can terminate a
production job, and whether it does depends on one optional addition and on
settings that live **outside** the transport.

The mechanism in one sentence: a checkpoint written **without** `ID` is always
active and cannot be switched off; a checkpoint written **with** `ID` is linked
to a *checkpoint group* and does nothing at all unless someone has set an
activation for that group, in this client, for this user or server, today.

Related notes: [Exception Flow](../Exception%20Flow#readme) for why an
uncatchable exception is not something you can wrap in `TRY`, and
[Messages](../Messages#readme) for the older `MESSAGE` dump patterns these
statements replace.

Runnable demo: [ydj_checkpoint_demo.abap](ydj_checkpoint_demo.abap) — no DDIC
objects, no database access, and nothing in it can terminate the program.

## The shape, in one block

```abap
" Always active. Cannot be switched off. Dumps ASSERTION_FAILED if false.
ASSERT sy-subrc = 0.

" Activatable. Ignored entirely unless the group is activated in SAAB.
ASSERT ID     ydj_checkpoints
       CONDITION lt_items IS NOT INITIAL.

" Always activatable - a logpoint has no always-active form at all.
LOG-POINT ID     ydj_checkpoints
          SUBKEY sy-uname
          FIELDS sy-datum lv_doc_id lt_items.

" Activatable. In a background job this one is not ignored - it is invisible.
BREAK-POINT ID ydj_checkpoints.
```

`CONDITION` is optional on a bare `ASSERT` but **mandatory as soon as `ID` is
specified** — `ASSERT ID grp lt_items IS NOT INITIAL.` does not compile.

## Trap 1: `ASSERT` without `ID` is a production dump you shipped on purpose

An assertion with no `ID` is always active, in every system, forever. When the
condition is false the runtime raises an **uncatchable** exception and the
program dies with `ASSERTION_FAILED`. `TRY ... CATCH cx_root` does not help;
there is no exception object to catch.

That is the intended behaviour, and SAP's own guideline defends it: if an
invariant your logic depends on is broken, continuing is worse than stopping,
because you persist bad data. The rule is about *which* conditions qualify:

> "Do not use assertions to check states that are out of the developer's
> control, such as invalid call parameter values or availability of external
> resources. In this case, use exceptions, since this enables the caller to
> react to unexpected states like these."

So the line is ownership, not severity:

| Condition | Right tool |
|---|---|
| A `READ TABLE` that the algorithm guarantees will hit | `ASSERT sy-subrc = 0.` |
| A customizing table that should never be empty | `ASSERT` — internal invariant |
| A caller passing an empty mandatory parameter | exception, not assertion |
| An RFC destination being reachable | exception, not assertion |
| A file the user selected actually existing | exception, not assertion |

The failure mode when this is ignored is specific: a method asserts on its own
importing parameter, some new caller passes something unexpected two years
later, and instead of a catchable error the whole transaction dumps in a
customer's production system.

## Trap 2: the `ID` group makes it activatable — and activation is not transported

This is the one that wastes an afternoon. You put `ASSERT ID ydj_checkpoints`
into the code, transport it to QA, reproduce the problem, and nothing happens.
Nothing is wrong with the code. The activation settings are separate:

> "Unlike the checkpoint group itself, the activation settings for a checkpoint
> group cannot be transported. When a newly created group is transported, it is
> **inactive in the target system by default**."

Four more rules from the same pages that each independently produce "it does
not fire":

- **Activation expires.** Any operation mode other than *inactive* is
  time-restricted — you choose *Today*, *This Week*, or up to 99 days/99 hours
  when saving in `SAAB`, and after that everything reverts to inactive by
  itself. A group that worked last month is off now.
- **Activation is client-dependent and context-scoped.** A setting applies
  globally, to a named user, or to a named application server. Precedence:
  user-specific beats server-specific, and either beats global. Your
  user-specific setting can therefore be quietly overridden by nobody — but a
  background job running under `WF-BATCH` is *not* your user, so a user-specific
  activation never sees it.
- **Already-running programs are unaffected.** "Changes to the activation
  settings do not affect programs that are already running." Activating a group
  while the long job is running changes nothing until the next run.
- **A compilation unit setting outranks the group.** Activation can be set for
  the surrounding compilation unit (executable program, class pool, function
  group) instead of the group, and "as soon as there is a program-specific
  activation setting, this overrides all existing group-specific settings within
  the specified compilation unit." Someone else's program-level setting can
  therefore silence your group inside that program.

One genuinely useful consequence in the other direction: a **newly created**
checkpoint group has no activation setting yet, and the documentation states a
new group "is active by default since in this case no corresponding activation
setting has yet been set." So a freshly created group in your dev system behaves
in the opposite way to the same group after transport.

## Trap 3: the operation mode is per checkpoint *type*, and `Break` silently is not a break

One activation setting covers assertions, breakpoints and logpoints at once, but
each type has its own mode:

| Checkpoint type | Available operation modes |
|---|---|
| Breakpoints | *Inactive*, *Break* |
| Logpoints | *Inactive*, *Log* |
| Assertions | *Inactive*, *Break/Log*, *Break/Abort*, *Log*, *Cancel* |

*Break* means the program stops in the Debugger — which is impossible in
background processing, in synchronous or asynchronous updates, and in HTTP
sessions without external debugging. In those contexts:

- a **breakpoint** is simply ignored;
- an **assertion** falls back to the second half of the mode you chose, which is
  why the assertion modes are *paired*. `Break/Log` writes a log entry instead;
  `Break/Abort` terminates with the runtime error instead.

Picking the wrong half of that pair is a real production decision, not a
formality: `Break/Abort` on a group that also covers an update-task assertion
means the update terminates rather than logging. The safe default for anything
that might run outside dialog is `Break/Log`.

## Trap 4: `LOG-POINT` keeps **one** entry per statement, not one per execution

The most misused checkpoint. A logpoint in a loop over 5,000 documents does not
produce 5,000 log entries:

> "During this process, any existing entry of the same `LOG-POINT` statement is
> **overwritten** by default. Each time an entry is written, a counter for the
> entry is increased."

So you get one surviving entry — the last one — plus a hit counter. The
`FIELDS` values you actually wanted from document 3172 were overwritten by 3173.

`SUBKEY` is the granularity control, and the rule is exact: existing entries
"are only overwritten if the subkeys have the same content." `SUBKEY` takes a
character-like expression, of which **the first 200 characters** are evaluated.

```abap
LOG-POINT ID ydj_checkpoints              " one entry, total
          FIELDS lv_doc_id lv_status.

LOG-POINT ID ydj_checkpoints              " one entry PER document
          SUBKEY lv_doc_id
          FIELDS lv_status.
```

Two more limits before you reach for this as a logging framework:

- `FIELDS` values are truncated by the profile parameter
  `abap/aab_log_field_size_limit` — **1024 bytes by default**, `0` meaning no
  limit. When the limit is hit the content is cut, and for internal tables
  "complete lines are removed." A large table logged this way is silently
  partial, with no marker in the entry saying so.
- Reference variables cannot be passed in `FIELDS` at all.

And the documentation closes the door explicitly:

> "Logpoints are only intended to be used for test purposes using transaction
> `SAAB`. There is no API for importing the logged data, which means that
> logpoints are **not suitable for general logging purposes**."

For real logging, use the Application Log (`BAL_*` / `SBAL`). Entries here are
collected in shared memory and written to a database table by a *periodic
background job*, so a fresh entry is not even visible immediately.

## Trap 5: expressions inside a checkpoint only run when it is active

Every operand position in these statements is lazily evaluated:

- `ASSERT` — the logical expression "is not evaluated" at all when inactive.
- `LOG-POINT SUBKEY` / `FIELDS` — "an expression or function specified here is
  executed only if the logpoint is active."
- `ASSERT SUBKEY` — evaluated "only if the assertion is active **and the logical
  expression is false**."

This is what makes activatable checkpoints cheap enough to leave in hot code,
and it is also the trap. If a functional method called inside the condition has
a side effect — fills a buffer, increments a counter, lazily loads
customizing — then **the program behaves differently depending on whether the
checkpoint group is activated**. The documentation warns about exactly this:

> "If functional methods are specified as operands ... they must not have any
> side effects. This must especially apply to assertions that can be activated
> externally, since the program behavior otherwise depends on the activation."

A Heisenbug that appears only while you are investigating it is the worst
possible outcome of a debugging aid. The demo proves the laziness by counting
calls to a method used inside an activatable assertion — run it before and after
activating the group in `SAAB` and the count changes.

## Trap 6: `BREAK-POINT` behaves differently depending on where it runs

The contexts are not symmetrical, and the difference between *with* and
*without* `ID` is the opposite of what you would expect:

| Context | `BREAK-POINT.` (no ID) | `BREAK-POINT ID grp.` |
|---|---|---|
| Dialog | stops in the Debugger | stops in the Debugger, if active |
| Background | writes *Breakpoint reached* to the **system log** | **ignored entirely** |
| Update task, no update debugging | as background | ignored |
| Update task, update debugging on | as dialog | as dialog |
| Local update | as dialog | as dialog |
| ICF/APC, external debugging off | as background | ignored |

So the always-active form leaves a trace in a background job and the activatable
form leaves nothing at all. The optional `log_text` addition after `BREAK-POINT`
is inserted into that system log text — with two sharp edges: it is **ignored in
dialog processing**, and it expects a flat character field of length 40, because
"if a data object of type `string` is specified, **it is ignored**." A `string`
there compiles, runs, and silently logs nothing.

Two more, both cheap to remember:

- `BREAK-POINT` without `ID` is flagged as an **error by the extended program
  check** (`SLIN`) — breakpoints that are always active "are not allowed in
  production programs." `ASSERT` without `ID` is not flagged; it is legitimate.
- A breakpoint inside a `SELECT` loop can raise an exception, because debugging
  may trigger a database commit and the cursor is lost. Same root cause as the
  cursor rules in [Mass Data Processing](../Mass%20Data%20Processing#readme).
- `BREAK username` is **not a statement** — it is a predefined macro, and it is
  the one every codebase still has lying around.

## Practical checklist

- `ASSERT` without `ID` only for invariants **you** own, and only where dying is
  genuinely better than continuing.
- Anything on a caller, a user, a file or a remote system gets an exception, not
  an assertion.
- `ID` on every `BREAK-POINT` you leave in the source, always.
- Create one `Z`/`Y` checkpoint group per application area and transport it;
  remember the activation itself has to be redone in each system, by hand, and
  expires on its own.
- `LOG-POINT` needs a `SUBKEY` the moment it sits inside a loop, or you get one
  entry and a counter.
- Never call anything with a side effect from inside a checkpoint operand.
- For anything a user or an auditor needs to read later, use the Application
  Log — a logpoint has no read API by design.

## Sources

- [Checkpoints](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCHECKPOINTS.html) — conditional vs unconditional checkpoints
- [ASSERT](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPASSERT.html) — always-active rule, `ASSERTION_FAILED`, operation modes, `SUBKEY` evaluation, the no-side-effects hint
- [Assertions — Programming Guideline](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENASSERTIONS_GUIDL.html) — the "out of the developer's control" rule
- [LOG-POINT](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPLOG-POINT.html) — overwrite-by-default, `SUBKEY`, `abap/aab_log_field_size_limit`, the no-API statement
- [BREAK-POINT](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPBREAK-POINT.html) — per-context behaviour table, `log_text` rules, the `SLIN` error, the `SELECT` cursor hint
- [Activatable Checkpoints](https://help.sap.com/docs/ABAP_PLATFORM_NEW/ba879a6e2ea04d9bb94c7ccd7cdac446/491c002326bc14cde10000000a42189b.html) — "no operative character", activatable vs always-active
- [Checkpoint Groups and Activation Settings](https://help.sap.com/docs/ABAP_PLATFORM_NEW/ba879a6e2ea04d9bb94c7ccd7cdac446/49205418d0fc14cfe10000000a42189b.html) — validity area/period/context, compilation-unit override, context precedence
- [Activating Checkpoint Groups](https://help.sap.com/docs/ABAP_PLATFORM_NEW/ba879a6e2ea04d9bb94c7ccd7cdac446/4920537ad0fc14cfe10000000a42189b.html) — full operation-mode list, Break fallback rules, non-transportable activation, new-group-is-active
