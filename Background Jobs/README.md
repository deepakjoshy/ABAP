# Background Jobs — the job that schedules fine and never runs

Scheduling work from ABAP is a three-function ritual everybody copies from the
same forum post: `JOB_OPEN`, `JOB_SUBMIT`, `JOB_CLOSE`. The ritual usually works,
which is the problem — when it does not, it fails in a way that produces no dump,
no syntax error and `sy-subrc = 0` on every call. The job appears in `SM37`, looks
completely normal, and sits there forever.

Everything below is a documented behaviour, not a bug. The dangerous ones are the
three that are **silent**: the missing start condition, the missing release
authorization, and the implicit `COMMIT WORK` inside all three function modules.

---

## 1. All three function modules do a `COMMIT WORK` — your LUW is already gone

This is the trap that corrupts data rather than merely failing to run something.
Look at the function modules' own short texts:

| Function module | Short text |
|---|---|
| `JOB_OPEN`   | Open Background Request **With COMMIT WORK** |
| `JOB_SUBMIT` | Insert Background Task in Background Request **With COMMIT WORK** |
| `JOB_CLOSE`  | Close Background Request **With COMMIT WORK** |

The commit is not incidental — the job tables (`TBTCO`, `TBTCP`, `TBTCS`) have to be
durable before the batch scheduler can see the job, so the API commits on your
behalf. The consequence is that this is **not** an atomic unit of work:

```abap
" WRONG - the document is committed the moment JOB_OPEN runs.
INSERT zdoc FROM ls_doc.               " not committed yet ... or so you think

CALL FUNCTION 'JOB_OPEN' ...           " <-- COMMIT WORK here: zdoc is now durable
CALL FUNCTION 'JOB_SUBMIT' ...
CALL FUNCTION 'JOB_CLOSE'
  EXCEPTIONS cant_start_immediate = 1 OTHERS = 8.

IF sy-subrc <> 0.
  ROLLBACK WORK.                       " rolls back NOTHING - too late
ENDIF.
```

The `ROLLBACK WORK` in the error branch is decoration. The insert was committed by
`JOB_OPEN`, and so was every other uncommitted change in the LUW at that moment.
Worse, `COMMIT WORK` also *executes* whatever you registered with
`CALL FUNCTION ... IN UPDATE TASK` — so the update modules fire at `JOB_OPEN`, not
where you wrote the commit.

The rule is a sequencing one, and there is no addition that turns it off:

```abap
" RIGHT - finish your own LUW first, then schedule. The job is the LAST thing.
INSERT zdoc FROM ls_doc.
IF sy-subrc <> 0.
  ROLLBACK WORK.
  RETURN.                              " nothing scheduled, nothing written
ENDIF.
COMMIT WORK AND WAIT.                  " your data is durable and yours alone

CALL FUNCTION 'JOB_OPEN' ...           " only now
```

If the job genuinely must not exist unless the data was written, you cannot get
that from the job API — you need the job to be the thing that *checks*, or you need
`CALL FUNCTION ... IN BACKGROUND TASK` / a qRFC unit, which is registered inside
your LUW and executed by `COMMIT WORK` with the transactional semantics you wanted.

This is the same class of problem as the `SUBMIT`-ends-your-LUW trap in
[Program Calls & ABAP Memory](../Program%20Calls#readme), from the other direction:
there the commit never happens, here it happens too early.

---

## 2. No start condition = status *Scheduled*, forever, with `sy-subrc = 0`

`JOB_CLOSE` has no mandatory start condition. Every start-related parameter is
optional and defaults to blank / `NO_DATE` / `NO_TIME`:

| `JOB_CLOSE` parameter | Default | Meaning |
|---|---|---|
| `STRTIMMED` | `SPACE` | Immediate execution of background job |
| `SDLSTRTDT` | `NO_DATE` | Start date of background job |
| `SDLSTRTTM` | `NO_TIME` | Time of the start date |
| `EVENT_ID` | `SPACE` | Job start after event |
| `PRED_JOBNAME` / `PRED_JOBCOUNT` | `SPACE` | Job start after predecessor job |
| `LASTSTRTDT` / `LASTSTRTTM` | `NO_DATE` / `NO_TIME` | **No start after** this date/time |
| `DONT_RELEASE` | `SPACE` | Job not released in spite of start condition |

Supply none of them and the call succeeds. `sy-subrc = 0`, no exception, a row in
`TBTCO`, the job visible in `SM37` — in status **Scheduled**, which in SAP's
vocabulary means *created but not released*. A scheduled job has no start condition
and therefore nothing will ever trigger it. It is not waiting; it is inert.

This is why the symptom is always reported as "the job is in SM37 but it never
runs" rather than as an error: from the calling program's point of view everything
worked.

```abap
" Minimum viable start condition - run now.
CALL FUNCTION 'JOB_CLOSE'
  EXPORTING
    jobname   = lv_jobname
    jobcount  = lv_jobcount
    strtimmed = abap_true
  ...
```

```abap
" Or a specific time. Both date AND time - a date alone is not a start condition.
CALL FUNCTION 'JOB_CLOSE'
  EXPORTING
    jobname   = lv_jobname
    jobcount  = lv_jobcount
    sdlstrtdt = lv_start_date
    sdlstrttm = lv_start_time
  ...
```

### The start-time *window*, not a start time

`LASTSTRTDT` / `LASTSTRTTM` are labelled **"No Start After"**. They are not a
timeout on the running job — they are a deadline on the *start*. If the scheduler
cannot find a free background work process before that moment (batch queue is
backed up, the target server is down, the operation mode has no BTC processes),
the job is not started late — it is not started at all.

A job given a five-minute window because "it should start instantly anyway" will
silently skip runs under load, which is exactly when you wanted it. Leave the
window off unless the work is genuinely worthless when late (a pre-cutoff
snapshot, a message that expires), and when you do use one, make it wide.

---

## 3. `STRTIMMED = 'X'` can fail — and the job survives the failure

Immediate start is the one start condition that can be refused at scheduling time:
if no background work process is free to take the job right now, `JOB_CLOSE`
raises `cant_start_immediate`.

```abap
DATA lv_released TYPE btch0000-char1.

CALL FUNCTION 'JOB_CLOSE'
  EXPORTING
    jobname          = lv_jobname
    jobcount         = lv_jobcount
    strtimmed        = abap_true
  IMPORTING
    job_was_released = lv_released
  EXCEPTIONS
    cant_start_immediate = 1
    invalid_startdate    = 2
    jobname_missing      = 3
    job_close_failed     = 4
    job_nosteps          = 5
    job_notex            = 6
    lock_failed          = 7
    invalid_target       = 8
    OTHERS               = 9.
```

The part people get wrong is the cleanup. `cant_start_immediate` does not undo
`JOB_OPEN` and `JOB_SUBMIT` — the job and its steps already exist and were already
committed (see §1). Returning from the error branch leaves a permanently inert
scheduled job behind, one per failed attempt. Under load this quietly fills `SM37`
with hundreds of ghosts.

Handle it by giving the job a real start condition instead of abandoning it:

```abap
IF sy-subrc = 1.
  " No free BTC process. Do not leave the job stranded - schedule it for now
  " and let the scheduler pick it up when a process frees.
  CALL FUNCTION 'JOB_CLOSE'
    EXPORTING
      jobname   = lv_jobname
      jobcount  = lv_jobcount
      sdlstrtdt = sy-datum
      sdlstrttm = sy-uzeit
    IMPORTING
      job_was_released = lv_released
    EXCEPTIONS OTHERS = 1.
ENDIF.
```

The alternative — deleting the orphan with `BP_JOB_DELETE` — is also fine, but you
have to choose one. Doing neither is the default, and it is wrong.

---

## 4. `sy-subrc = 0` does not mean *released* — only `JOB_WAS_RELEASED` does

This is the trap that only appears in production.

Releasing a job is an authorization-protected action (`S_BTCH_JOB` with activity
`RELE`; running it under another user additionally needs `S_BTCH_NAM`). If the
calling user may *create* jobs but not *release* them, `JOB_CLOSE` does not raise
an exception and does not set `sy-subrc`. It creates the job, declines to release
it, and reports that fact **only** through the optional `IMPORTING` parameter:

> `JOB_WAS_RELEASED` — `= 'X'`, if job was released

Almost every copy-paste of the three-FM pattern omits that parameter, because it
is optional and the code works in the developer's own system — where the developer
happens to hold `RELE`. The job then ships to QA or production, runs under a
restricted batch or dialog user, and silently stops being executed. The program
reports success; an administrator has to release each job by hand in `SM37`.

Check it. It is one variable:

```abap
IF sy-subrc <> 0.
  MESSAGE e001(zbatch) WITH lv_jobname.          " scheduling failed outright
ELSEIF lv_released <> abap_true.
  " Created but NOT released - it will never run without manual intervention.
  MESSAGE e002(zbatch) WITH lv_jobname lv_jobcount.
ENDIF.
```

Note the asymmetry with §3: `cant_start_immediate` is loud (an exception) because
the *system* could not start the job; a missing release authorization is silent
because the *user* was not allowed to ask. Both end with an inert job.

---

## 5. `AUTHCKNAM` decides whose authorizations the job runs with — not `sy-uname`

`JOB_SUBMIT`'s `AUTHCKNAM` is the user the background task executes as, and it
defaults to nothing useful if you leave it out. The classic version of this bug:

- In development you pass `sy-uname` (or omit it and it lands on you). Your
  developer user has broad authorizations. Everything works.
- In production the job is scheduled by a service user with a deliberately narrow
  role. The same program now fails an `AUTHORITY-CHECK` deep inside, at run time,
  in a background session with no screen — so the failure surfaces as an aborted
  job in `SM37` and a short dump or an error message nobody is watching.

The authorization that *matters* for the failing statement is the job user's, not
the scheduling user's, and the two are never the same in a properly configured
system. Decide the job user explicitly, and remember that naming somebody else
requires `S_BTCH_NAM` — the keyword documentation describes the object's permitted
names as a whitelist:

> When the program is executed, only those names can be specified for which the
> current user has the correct authorization. The names permitted by the
> authorization object represent a type of whitelist of users whose authorizations
> allow the current user to execute a background task.

— [`SUBMIT`, `job_options`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSUBMIT_VIA_JOB.html)

For what actually happens when that check fails inside the job, see
[Authorization Checks](../Authorization%20Checks#readme) — in particular the
failure modes that still return `sy-subrc = 0`.

---

## 6. The job name is not the key — `jobname` + `jobcount` is

`JOB_OPEN` returns `JOBCOUNT`, an 8-character ID, and that is not a formality:
**`TBTCO` is keyed on `JOBNAME` *and* `JOBCOUNT`**. Scheduling `ZDJ_NIGHTLY_LOAD`
twice does not replace anything and does not raise a duplicate-key error — it
produces two independent jobs with the same name.

Two things follow:

- **A re-run guard has to be written by you.** There is no uniqueness anywhere in
  the API. If your program must not schedule a second copy while one is pending or
  running, check `TBTCO` first (or take an enqueue lock — see
  [Enqueue Locks](../Enqueue%20Locks#readme)). Jobs that re-schedule themselves at
  the end of each run are the usual source of a `SM37` list with four hundred
  identical entries.
- **Store `jobcount` if you ever want to find the job again.** Status monitoring,
  `BP_JOB_DELETE`, or chaining via `PRED_JOBNAME` / `PRED_JOBCOUNT` all need the
  pair. The name alone is ambiguous by design.

The status values in `TBTCO-STATUS` are single characters, defined as constants in
the standard include `LBTCHDEF`:

| Value | Constant | Meaning |
|---|---|---|
| `P` | `btc_scheduled` | Scheduled — **created, no start condition, will not run** |
| `S` | `btc_released` | Released — start condition exists, waiting for it |
| `Y` | `btc_ready` | Ready — condition met, waiting for a free work process |
| `R` | `btc_running` | Active |
| `F` | `btc_finished` | Finished |
| `A` | `btc_aborted` | Cancelled |
| `Z` | `btc_put_active` | Put active |
| `X` | `btc_unknown_state` | Unknown |

`P` versus `S` is the entire content of §2 and §4 compressed into one character,
and it is the first thing to look at when a job "does not run".

---

## 7. `SUBMIT ... VIA JOB` runs `INITIALIZATION` twice

`SUBMIT ... VIA JOB job NUMBER n ... AND RETURN` is the shorthand alternative to
`JOB_SUBMIT`, and it is convenient precisely because it builds the selection-screen
variant for you from `WITH` values. The cost is that it loads and partially
executes the called program **at scheduling time, in your session**:

> The addition `VIA JOB` also loads the called program in a separate internal
> session when the statement `SUBMIT` is executed, and all steps located before
> `START-OF-SELECTION` are executed. This means the events `LOAD-OF-PROGRAM` and
> `INITIALIZATION` are raised, and selection screen processing is performed.

— [`SUBMIT`, `job_options`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSUBMIT_VIA_JOB.html)

Then, at run time, the program is executed again in full — "All events are raised,
including those from selection screen processing". So any side effect in
`INITIALIZATION` or `AT SELECTION-SCREEN OUTPUT` happens **twice**: once in the
scheduling user's dialog session, once in the background session. Writing a log
row, drawing a number from a number range, or sending a notification from
`INITIALIZATION` all duplicate, and the first copy is attributed to the wrong user
at the wrong time.

Two more rules on the same statement:

- `VIA JOB` **can only be used together with `AND RETURN`**. Without it you get a
  syntax error, not a running job.
- If the called program writes a basic list, pass spool parameters explicitly with
  `TO SAP-SPOOL`. Otherwise the documentation warns that `VIA JOB` invents a spool
  request whose parameters "derive from standard values, some of which are taken
  from the user defaults, and are not necessarily consistent".

`SUBMIT ... VIA JOB` reports through `sy-subrc` rather than exceptions:

| `sy-subrc` | Meaning |
|---|---|
| 0 | Background task was scheduled successfully |
| 4 | Scheduling was terminated by the user on the selection screen |
| 8 | Error during scheduling (internal call of `JOB_SUBMIT`) |
| 12 | Error during internal number assignment |

For the 8 and 12 cases the error message key is retrievable with
`cl_abap_submit_handling=>get_error_message( )` — the only way to find out *why*
the internal `JOB_SUBMIT` failed.

---

## 8. Smaller sharp edges

- **The `PRDHOURS` / `PRDMINS` short texts are swapped in the `JOB_CLOSE`
  interface.** `PRDHOURS` is documented as "Minute Portion of Job Repetition
  Period" and `PRDMINS` as "Hour Portion". The *parameter names* are correct and
  behave as their names say; only the descriptive texts are transposed. Do not
  resolve the contradiction by trusting the F1 text.
- **A periodic job is periodic *from* its start condition.** Filling `PRDDAYS`
  etc. without also filling `SDLSTRTDT` / `SDLSTRTTM` or `STRTIMMED` recreates §2:
  a repetition period with nothing to repeat from.
- **`DONT_RELEASE = 'X'` creates the inert job deliberately** — useful when an
  administrator is meant to review and release, and a trap when copied from an
  example without noticing.
- **`TARGETSERVER` pins the job to one application server.** Set it only when the
  work genuinely requires that host (a mounted filesystem, a licensed device), and
  remember the server name is environment-specific — a transported hard-coded
  server name is a job that cannot run in production. `TARGETGROUP` (a server
  group) is the portable form.
- **Background sessions have no screen.** A `MESSAGE` of type `E` or `A` in a job
  behaves differently from a dialog session, including whether the work is rolled
  back; see [Messages](../Messages#readme) for the background-job asymmetry.

---

## The shape that works

```abap
DATA: lv_jobname  TYPE tbtcjob-jobname VALUE 'ZDJ_NIGHTLY_LOAD',
      lv_jobcount TYPE tbtcjob-jobcount,
      lv_released TYPE btch0000-char1.

" 0. Finish your own LUW first - the job API will commit it for you otherwise.
COMMIT WORK AND WAIT.

" 1. Open: returns the jobcount that, with the name, identifies this job.
CALL FUNCTION 'JOB_OPEN'
  EXPORTING  jobname  = lv_jobname
  IMPORTING  jobcount = lv_jobcount
  EXCEPTIONS cant_create_job = 1 invalid_job_data = 2 jobname_missing = 3
             OTHERS = 4.
IF sy-subrc <> 0.
  RETURN.
ENDIF.

" 2. Submit the step. AUTHCKNAM decides whose authorizations the job runs with.
CALL FUNCTION 'JOB_SUBMIT'
  EXPORTING  authcknam = lv_batch_user
             jobname   = lv_jobname
             jobcount  = lv_jobcount
             report    = 'ZDJ_LOAD_REPORT'
             variant   = 'NIGHTLY'
  EXCEPTIONS bad_priparams = 1 invalid_jobdata = 2 jobname_missing = 3
             job_notex = 4 job_submit_failed = 5 lock_failed = 6
             program_missing = 7 prog_abap_and_extpg_set = 8 OTHERS = 9.
IF sy-subrc <> 0.
  RETURN.                                  " orphan job left - delete it if it matters
ENDIF.

" 3. Close WITH a start condition, and read back whether it was released.
CALL FUNCTION 'JOB_CLOSE'
  EXPORTING  jobname   = lv_jobname
             jobcount  = lv_jobcount
             strtimmed = abap_true
  IMPORTING  job_was_released = lv_released
  EXCEPTIONS cant_start_immediate = 1 invalid_startdate = 2 jobname_missing = 3
             job_close_failed = 4 job_nosteps = 5 job_notex = 6
             lock_failed = 7 invalid_target = 8 OTHERS = 9.

" 4. Two distinct failures, two distinct checks.
IF sy-subrc <> 0.
  " Scheduling failed. sy-subrc = 1 means no free BTC process, see section 3.
ELSEIF lv_released <> abap_true.
  " Created but NOT released - no authorization. It will never run by itself.
ENDIF.
```

The four things that differ from the version on every forum: the commit before
`JOB_OPEN`, a start condition in `JOB_CLOSE`, `AUTHCKNAM` chosen deliberately, and
`JOB_WAS_RELEASED` actually being read.

---

## Demo program

[`ydj_background_job_demo.abap`](./ydj_background_job_demo.abap) — read-only. It
**schedules nothing**: every `JOB_OPEN` / `JOB_SUBMIT` / `JOB_CLOSE` call is shown
as a comment so running the demo cannot create jobs in your system. What it does
execute is a `SELECT` over `TBTCO` that decodes the status characters, so you can
see how many jobs in your own system are sitting in status `P` — created,
unreleased and never going to run.

## Sources

- [`SUBMIT`, `job_options` — ABAP Keyword Documentation](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSUBMIT_VIA_JOB.html)
  (the two-phase execution of `VIA JOB`, the `AND RETURN` requirement, the `sy-subrc`
  table, the implicit spool request, the `S_BTCH_NAM` whitelist wording,
  `CL_ABAP_SUBMIT_HANDLING`)
- [`SUBMIT` — ABAP Keyword Documentation](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSUBMIT.html)
- [`JOB_CLOSE` interface — parameter and exception list](https://www.stechno.net/repository/sap-functions.html?id=JOB_CLOSE)
  (defaults `NO_DATE` / `NO_TIME` / `SPACE`, the `JOB_WAS_RELEASED` text, the
  `LASTSTRTDT` "No Start After" semantics, the transposed `PRDHOURS` / `PRDMINS`
  short texts)
- [SAP Community — job scheduled but not released in SM37](https://community.sap.com/t5/application-development-and-automation-discussions/schedule-background-job-by-function-module-open-job-submit-job-and-close/td-p/11070777)
  (the missing start condition, and checking `JOB_WAS_RELEASED` when the user
  lacks release authorization)
- [SAP Community — status constants in include `LBTCHDEF`](https://community.sap.com/t5/application-development-and-automation-discussions/can-you-tel-me-the-exact-status-values-for-tbtco-table/td-p/5581026)
- [SAP KBA 3348468 — How to use function module `JOB_CLOSE`](https://userapps.support.sap.com/sap/support/knowledge/en/3348468)
