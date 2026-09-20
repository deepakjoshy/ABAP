*&---------------------------------------------------------------------*
*& Report YDJ_BACKGROUND_JOB_DEMO
*&---------------------------------------------------------------------*
*& Scheduling background jobs from ABAP - JOB_OPEN / JOB_SUBMIT /
*& JOB_CLOSE, and the ways a job is created successfully and then
*& never runs.
*&
*& Every case below returns sy-subrc = 0 or is otherwise indis-
*& tinguishable from success at the call site. None of them is a
*& syntax error.
*&
*&   1. IMPLICIT COMMIT -> all three function modules carry a COMMIT
*&                         WORK, so your own uncommitted changes are
*&                         made durable at JOB_OPEN and a later
*&                         ROLLBACK WORK in the error branch is dead
*&                         code. Registered update modules fire there
*&                         too, not where you wrote the commit.
*&   2. NO START COND.  -> every start parameter of JOB_CLOSE is
*&                         OPTIONAL. Supply none and the call succeeds
*&                         with sy-subrc = 0, creating a job in status
*&                         'P' (Scheduled) that has no trigger and will
*&                         never run. This is the usual 'the job is in
*&                         SM37 but nothing happens' report.
*&   3. NOT RELEASED    -> releasing needs S_BTCH_JOB activity RELE. A
*&                         user without it gets a CREATED but UNRELEASED
*&                         job - no exception, no sy-subrc. The only
*&                         indication is the optional IMPORTING
*&                         parameter JOB_WAS_RELEASED, which nearly
*&                         every copy-pasted example omits.
*&   4. CANT_START_IMM  -> STRTIMMED = 'X' can be refused when no
*&                         background work process is free. The job and
*&                         its steps already exist and were already
*&                         committed, so returning from the error branch
*&                         leaves an inert job behind - one per attempt.
*&   5. START WINDOW    -> LASTSTRTDT/LASTSTRTTM are 'No Start AFTER',
*&                         a deadline on the START, not a timeout on the
*&                         run. Miss the window and the job does not
*&                         start late, it does not start at all.
*&   6. NAME NOT UNIQUE -> TBTCO is keyed on JOBNAME *and* JOBCOUNT, so
*&                         scheduling the same name twice creates two
*&                         independent jobs. There is no duplicate
*&                         protection anywhere in the API.
*&   7. VIA JOB TWICE   -> SUBMIT ... VIA JOB executes everything before
*&                         START-OF-SELECTION at SCHEDULING time in the
*&                         caller's session, then the whole program
*&                         again in the background - so INITIALIZATION
*&                         side effects happen twice.
*&
*& Read-only: this program SCHEDULES NOTHING. Every JOB_OPEN /
*& JOB_SUBMIT / JOB_CLOSE / SUBMIT VIA JOB call is shown as a comment
*& so the demo cannot create jobs in your system. The only executed
*& database access is a SELECT over TBTCO that decodes the status
*& characters, which shows how many jobs in this system are sitting
*& unreleased in status 'P'.
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSUBMIT_VIA_JOB.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSUBMIT.html
*&       https://www.stechno.net/repository/sap-functions.html?id=JOB_CLOSE
*&---------------------------------------------------------------------*
REPORT ydj_background_job_demo.

* Status values of TBTCO-STATUS, as defined in the standard include
* LBTCHDEF. 'P' and 'S' are the two that matter when a job does not run.
CONSTANTS: c_scheduled     TYPE btcstatus VALUE 'P',
           c_released      TYPE btcstatus VALUE 'S',
           c_ready         TYPE btcstatus VALUE 'Y',
           c_running       TYPE btcstatus VALUE 'R',
           c_finished      TYPE btcstatus VALUE 'F',
           c_aborted       TYPE btcstatus VALUE 'A',
           c_put_active    TYPE btcstatus VALUE 'Z',
           c_unknown_state TYPE btcstatus VALUE 'X'.

TYPES: BEGIN OF ty_status_count,
         status TYPE btcstatus,
         text   TYPE c LENGTH 40,
         count  TYPE i,
       END OF ty_status_count.

DATA: gt_status TYPE STANDARD TABLE OF ty_status_count WITH EMPTY KEY,
      gs_status TYPE ty_status_count.

DATA: gv_text  TYPE c LENGTH 40,
      gv_count TYPE i,
      gv_total TYPE i.

START-OF-SELECTION.

*----------------------------------------------------------------------*
* 1. The implicit COMMIT WORK inside the job API.
*----------------------------------------------------------------------*
  WRITE: / '1. ALL THREE JOB FUNCTION MODULES COMMIT YOUR LUW'.
  ULINE.
  WRITE: / '   JOB_OPEN   - Open Background Request With COMMIT WORK'.
  WRITE: / '   JOB_SUBMIT - Insert Background Task ... With COMMIT WORK'.
  WRITE: / '   JOB_CLOSE  - Close Background Request With COMMIT WORK'.
  SKIP.
  WRITE: / '   So this is NOT one unit of work:'.
  WRITE: / '     INSERT zdoc FROM ls_doc.'.
  WRITE: / '     CALL FUNCTION ''JOB_OPEN'' ...   <- commits zdoc here'.
  WRITE: / '     ...'.
  WRITE: / '     IF sy-subrc <> 0. ROLLBACK WORK. ENDIF.  <- dead code'.
  SKIP.
  WRITE: / '   COMMIT WORK also EXECUTES anything registered with'.
  WRITE: / '   CALL FUNCTION ... IN UPDATE TASK, so update modules fire'.
  WRITE: / '   at JOB_OPEN, not where the commit was written.'.
  SKIP.
  WRITE: / '   Fix: finish your own LUW first, schedule last.'.
  WRITE: / '     COMMIT WORK AND WAIT.   (or ROLLBACK WORK and RETURN)'.
  WRITE: / '     CALL FUNCTION ''JOB_OPEN'' ...'.
  SKIP 2.

*----------------------------------------------------------------------*
* 2. JOB_CLOSE without a start condition.
*----------------------------------------------------------------------*
  WRITE: / '2. NO START CONDITION = STATUS ''P'', FOREVER, subrc = 0'.
  ULINE.
  WRITE: / '   Every start parameter of JOB_CLOSE is optional:'.
  SKIP.
  WRITE: /5 'STRTIMMED', 30 'SPACE', 45 'immediate execution'.
  WRITE: /5 'SDLSTRTDT', 30 'NO_DATE', 45 'start date'.
  WRITE: /5 'SDLSTRTTM', 30 'NO_TIME', 45 'start time'.
  WRITE: /5 'EVENT_ID', 30 'SPACE', 45 'start after event'.
  WRITE: /5 'PRED_JOBNAME', 30 'SPACE', 45 'start after predecessor'.
  WRITE: /5 'DONT_RELEASE', 30 'SPACE', 45 'create but do not release'.
  SKIP.
  WRITE: / '   Supply none of them and the call SUCCEEDS: sy-subrc = 0,'.
  WRITE: / '   a row in TBTCO, a job in SM37 - in status ''Scheduled'','.
  WRITE: / '   which means created and NOT released. Nothing will ever'.
  WRITE: / '   trigger it. It is not waiting; it is inert.'.
  SKIP.
  WRITE: / '   Minimum viable start condition:'.
  WRITE: / '     strtimmed = abap_true'.
  WRITE: / '   or BOTH of sdlstrtdt AND sdlstrttm - a date alone is not'.
  WRITE: / '   a start condition.'.
  SKIP 2.

*----------------------------------------------------------------------*
* 3. JOB_WAS_RELEASED - the only signal that release was refused.
*----------------------------------------------------------------------*
  WRITE: / '3. sy-subrc = 0 DOES NOT MEAN RELEASED'.
  ULINE.
  WRITE: / '   Releasing needs S_BTCH_JOB activity RELE (and S_BTCH_NAM'.
  WRITE: / '   to run as another user). Without it, JOB_CLOSE raises no'.
  WRITE: / '   exception and sets no sy-subrc - it creates the job,'.
  WRITE: / '   declines to release it, and says so ONLY here:'.
  SKIP.
  WRITE: / '     IMPORTING job_was_released = lv_released'.
  SKIP.
  WRITE: / '   The parameter is optional, so it is usually omitted, and'.
  WRITE: / '   the code works in the developer''s own system - where the'.
  WRITE: / '   developer happens to hold RELE. It then ships to a system'.
  WRITE: / '   with a restricted batch user and silently stops running.'.
  SKIP.
  WRITE: / '   Two distinct failures need two distinct checks:'.
  WRITE: / '     IF sy-subrc <> 0.                scheduling failed'.
  WRITE: / '     ELSEIF lv_released <> abap_true.  created, not released'.
  WRITE: / '     ENDIF.'.
  SKIP 2.

*----------------------------------------------------------------------*
* 4. cant_start_immediate leaves the job behind.
*----------------------------------------------------------------------*
  WRITE: / '4. cant_start_immediate DOES NOT UNDO JOB_OPEN/JOB_SUBMIT'.
  ULINE.
  WRITE: / '   STRTIMMED = ''X'' is refused when no background work'.
  WRITE: / '   process is free. But the job and its steps already exist'.
  WRITE: / '   and were already COMMITTED (see 1), so returning from the'.
  WRITE: / '   error branch strands one inert job per failed attempt.'.
  SKIP.
  WRITE: / '   Under load - exactly when this exception fires - that'.
  WRITE: / '   quietly fills SM37 with hundreds of ghosts.'.
  SKIP.
  WRITE: / '   Handle it: re-close with a real start condition ...'.
  WRITE: / '     IF sy-subrc = 1.'.
  WRITE: / '       CALL FUNCTION ''JOB_CLOSE'''.
  WRITE: / '         EXPORTING jobname   = lv_jobname'.
  WRITE: / '                   jobcount  = lv_jobcount'.
  WRITE: / '                   sdlstrtdt = sy-datum'.
  WRITE: / '                   sdlstrttm = sy-uzeit ...'.
  WRITE: / '     ENDIF.'.
  WRITE: / '   ... or delete it with BP_JOB_DELETE. Doing neither is the'.
  WRITE: / '   default, and it is wrong.'.
  SKIP 2.

*----------------------------------------------------------------------*
* 5. The start-time window is a deadline on the START.
*----------------------------------------------------------------------*
  WRITE: / '5. LASTSTRTDT/LASTSTRTTM MEAN NO START AFTER'.
  ULINE.
  WRITE: / '   Not a timeout on the running job - a deadline on the'.
  WRITE: / '   START. If the scheduler finds no free process before that'.
  WRITE: / '   moment (queue backed up, target server down, operation'.
  WRITE: / '   mode without BTC processes), the job does not start late.'.
  WRITE: / '   It does not start at all.'.
  SKIP.
  WRITE: / '   A five-minute window given because it starts instantly'.
  WRITE: / '   anyway silently skips runs under load - which is exactly'.
  WRITE: / '   when the run mattered. Leave it off, or make it wide.'.
  SKIP 2.

*----------------------------------------------------------------------*
* 6. Job name is not a key. Live proof from TBTCO.
*----------------------------------------------------------------------*
  WRITE: / '6. TBTCO IS KEYED ON JOBNAME *AND* JOBCOUNT'.
  ULINE.
  WRITE: / '   Scheduling the same name twice creates two independent'.
  WRITE: / '   jobs. No duplicate-key error, no uniqueness anywhere in'.
  WRITE: / '   the API - a re-run guard is yours to write (check TBTCO,'.
  WRITE: / '   or take an enqueue lock). Store the jobcount JOB_OPEN'.
  WRITE: / '   returns, or you cannot find the job again.'.
  SKIP.
  WRITE: / '   Status distribution in THIS system (TBTCO, read-only):'.
  SKIP.

  SELECT status, COUNT( * ) AS count
    FROM tbtco
    GROUP BY status
    INTO TABLE @DATA(lt_raw).

  IF sy-subrc <> 0.
    WRITE: /5 'No rows in TBTCO (or no read authorization).'.
  ELSE.
    LOOP AT lt_raw ASSIGNING FIELD-SYMBOL(<ls_raw>).
      CLEAR gv_text.
      PERFORM status_text USING    <ls_raw>-status
                          CHANGING gv_text.
      CLEAR gs_status.
      gs_status-status = <ls_raw>-status.
      gs_status-text   = gv_text.
      gs_status-count  = <ls_raw>-count.
      APPEND gs_status TO gt_status.
      gv_total = gv_total + gs_status-count.
    ENDLOOP.

    SORT gt_status BY count DESCENDING.

    LOOP AT gt_status ASSIGNING FIELD-SYMBOL(<ls_status>).
      WRITE: /5  <ls_status>-status,
              10 <ls_status>-text,
              55 <ls_status>-count.
    ENDLOOP.

    SKIP.
    WRITE: /5 'Total jobs', 55 gv_total.

    CLEAR gv_count.
    LOOP AT gt_status ASSIGNING <ls_status>
         WHERE status = c_scheduled.
      gv_count = gv_count + <ls_status>-count.
    ENDLOOP.

    SKIP.
    IF gv_count > 0.
      WRITE: /5 'In status ''P'' - created, unreleased, will NEVER run:',
              55 gv_count.
    ELSE.
      WRITE: /5 'No jobs stranded in status ''P'' in this system.'.
    ENDIF.
  ENDIF.

  SKIP 2.

*----------------------------------------------------------------------*
* 7. SUBMIT ... VIA JOB executes the callee twice.
*----------------------------------------------------------------------*
  WRITE: / '7. SUBMIT ... VIA JOB RAISES INITIALIZATION TWICE'.
  ULINE.
  WRITE: / '   VIA JOB loads the called program in a separate internal'.
  WRITE: / '   session AT SCHEDULING TIME and executes everything before'.
  WRITE: / '   START-OF-SELECTION - LOAD-OF-PROGRAM, INITIALIZATION and'.
  WRITE: / '   selection screen processing - in YOUR session. Then the'.
  WRITE: / '   background run raises all events again.'.
  SKIP.
  WRITE: / '   So a log row, a number-range draw or a notification in'.
  WRITE: / '   INITIALIZATION happens twice, and the first copy is'.
  WRITE: / '   attributed to the scheduling user at the wrong time.'.
  SKIP.
  WRITE: / '   VIA JOB can ONLY be used together with AND RETURN.'.
  WRITE: / '   Its sy-subrc: 0 scheduled, 4 cancelled on the selection'.
  WRITE: / '   screen, 8 JOB_SUBMIT error, 12 number assignment error.'.
  WRITE: / '   The reason for 8/12 is only available from'.
  WRITE: / '   cl_abap_submit_handling=>get_error_message( ).'.
  SKIP 2.

*----------------------------------------------------------------------*
* The shape that works - shown, never executed.
*----------------------------------------------------------------------*
  WRITE: / 'THE SHAPE THAT WORKS (commented out - nothing is scheduled)'.
  ULINE.
  WRITE: / '  COMMIT WORK AND WAIT.           0. your LUW first'.
  SKIP.
  WRITE: / '  CALL FUNCTION ''JOB_OPEN''        1. get the jobcount'.
  WRITE: / '    EXPORTING  jobname  = lv_jobname'.
  WRITE: / '    IMPORTING  jobcount = lv_jobcount'.
  WRITE: / '    EXCEPTIONS cant_create_job = 1 invalid_job_data = 2'.
  WRITE: / '               jobname_missing = 3 OTHERS = 4.'.
  SKIP.
  WRITE: / '  CALL FUNCTION ''JOB_SUBMIT''      2. authcknam = job user'.
  WRITE: / '    EXPORTING  authcknam = lv_batch_user'.
  WRITE: / '               jobname   = lv_jobname'.
  WRITE: / '               jobcount  = lv_jobcount'.
  WRITE: / '               report    = ''ZDJ_LOAD_REPORT'''.
  WRITE: / '               variant   = ''NIGHTLY'' ...'.
  SKIP.
  WRITE: / '  CALL FUNCTION ''JOB_CLOSE''       3. START CONDITION'.
  WRITE: / '    EXPORTING  jobname   = lv_jobname'.
  WRITE: / '               jobcount  = lv_jobcount'.
  WRITE: / '               strtimmed = abap_true'.
  WRITE: / '    IMPORTING  job_was_released = lv_released'.
  WRITE: / '    EXCEPTIONS cant_start_immediate = 1 ... OTHERS = 9.'.
  SKIP.
  WRITE: / '  IF sy-subrc <> 0.                4. scheduling failed'.
  WRITE: / '  ELSEIF lv_released <> abap_true.     created, not released'.
  WRITE: / '  ENDIF.'.
  SKIP.
  WRITE: / '  Four differences from the usual forum version: the commit'.
  WRITE: / '  before JOB_OPEN, a start condition in JOB_CLOSE, AUTHCKNAM'.
  WRITE: / '  chosen deliberately, and JOB_WAS_RELEASED actually read.'.

*----------------------------------------------------------------------*
* Decode one TBTCO-STATUS character into its LBTCHDEF meaning.
*----------------------------------------------------------------------*
FORM status_text USING iv_status TYPE btcstatus
              CHANGING cv_text   TYPE c.

  CASE iv_status.
    WHEN c_scheduled.
      cv_text = 'Scheduled - NO start condition'.
    WHEN c_released.
      cv_text = 'Released - waiting for condition'.
    WHEN c_ready.
      cv_text = 'Ready - waiting for a process'.
    WHEN c_running.
      cv_text = 'Active'.
    WHEN c_finished.
      cv_text = 'Finished'.
    WHEN c_aborted.
      cv_text = 'Cancelled'.
    WHEN c_put_active.
      cv_text = 'Put active'.
    WHEN c_unknown_state.
      cv_text = 'Unknown state'.
    WHEN OTHERS.
      cv_text = 'Not documented in LBTCHDEF'.
  ENDCASE.

ENDFORM.
