*&---------------------------------------------------------------------*
*& Report YDJ_RFC_CALL_TRAPS_DEMO
*&---------------------------------------------------------------------*
*& A remote call is written like a local one, so it is reviewed like a
*& local one. Almost every guarantee you rely on locally is gone in the
*& remote form, and the differences are silent.
*&
*&   1. BLANK DESTINATION -> the doc: if an empty string or a text field
*&                           consisting only of blanks is specified for
*&                           dest, the addition DESTINATION is IGNORED
*&                           and a regular local call is made. Missing
*&                           customizing therefore returns LOCAL data
*&                           with sy-subrc = 0. aRFC is the opposite:
*&                           STARTING NEW TASK rejects a blank dest.
*&   2. NO TYPE CHECK     -> bindings to incorrectly specified formal
*&                           parameters are IGNORED, typings are NOT
*&                           checked, and every formal parameter is
*&                           implicitly OPTIONAL. A misspelled parameter
*&                           name is a syntax error locally and a blank
*&                           input remotely.
*&   3. CHAR LENGTHS      -> a shorter actual parameter is filled with
*&                           blanks on input and cut short on output;
*&                           if it is longer, the reverse applies. A
*&                           data element length difference between the
*&                           two systems corrupts rather than raises.
*&   4. NO CX_ ACROSS RFC -> a class-based exception raised remotely is
*&                           NOT transported; the classic SYSTEM_FAILURE
*&                           is raised instead, so TRY/CATCH around the
*&                           call catches nothing. error_message is
*&                           ignored in RFC. MESSAGE smess is the only
*&                           route to the reason.
*&   5. RFC COMMITS       -> sRFC, aRFC and WAIT each trigger a database
*&                           commit in the CALLING program (except in
*&                           the update). That ends your LUW, fires
*&                           pending IN UPDATE TASK registrations early
*&                           and closes every open database cursor.
*&   6. WAIT SUBRC = 4    -> does NOT mean timeout. It means the
*&                           condition was not met, INCLUDING the case
*&                           where no callback routines were ever
*&                           registered. Only 8 is the UP TO timeout.
*&   7. MISSING RECEIVE   -> a callback routine without RECEIVE behaves
*&                           as if KEEPING TASK were specified, so the
*&                           connection and the remote session stay
*&                           open. The doc calls this a programming
*&                           error outright.
*&   8. tRFC IS OBSOLETE  -> CALL FUNCTION ... IN BACKGROUND TASK is
*&                           classified obsolete; bgRFC (IN BACKGROUND
*&                           UNIT) is the documented successor. Unlike
*&                           sRFC, an omitted destination there means
*&                           NONE, not a local call.
*&
*& This program performs NO remote call and NO database write. Every
*& CALL FUNCTION ... DESTINATION / STARTING NEW TASK / IN BACKGROUND
*& TASK below is a comment. The executed logic is the destination
*& validator and the character length arithmetic, both local.
*&---------------------------------------------------------------------*
REPORT ydj_rfc_call_traps_demo.

TYPES: BEGIN OF ty_dest_case,
         name    TYPE c LENGTH 20,
         value   TYPE rfcdest,
         verdict TYPE c LENGTH 40,
       END OF ty_dest_case.

DATA gt_dest   TYPE STANDARD TABLE OF ty_dest_case WITH EMPTY KEY.
DATA gs_dest   TYPE ty_dest_case.
DATA gv_local  TYPE abap_bool.
DATA gv_len    TYPE i.
DATA gv_short  TYPE c LENGTH 10.
DATA gv_long   TYPE c LENGTH 18.
DATA gv_back   TYPE c LENGTH 10.
DATA gv_subrc  TYPE sy-subrc.

*&---------------------------------------------------------------------*
*& Part 1 - the blank destination is a LOCAL call, not an error
*&---------------------------------------------------------------------*
START-OF-SELECTION.

  WRITE: / '1. DESTINATION values and what the call actually does'.
  ULINE.

  gt_dest = VALUE #(
    ( name = 'customized' value = 'QA_STOCK_SYS' )
    ( name = 'row missing' value = '' )
    ( name = 'blanks only' value = '    ' ) ).

  LOOP AT gt_dest INTO gs_dest.

*   The documented rule: DESTINATION is ignored for an empty string or a
*   text field consisting only of blanks, and a regular local call is
*   made. A blank-only field is therefore NOT distinguishable from a
*   missing one, and neither raises.
    IF gs_dest-value IS INITIAL.
      gv_local = abap_true.
    ELSE.
      gv_local = abap_false.
    ENDIF.

    IF gv_local = abap_true.
      gs_dest-verdict = 'runs LOCALLY, sy-subrc = 0, no warning'.
    ELSE.
      gs_dest-verdict = 'runs remotely as intended'.
    ENDIF.

    WRITE: / gs_dest-name, gs_dest-value, gs_dest-verdict.

  ENDLOOP.

  SKIP.
  WRITE: / 'Guard: reject an initial destination BEFORE the call.'.
  WRITE: / 'aRFC needs no guard - STARTING NEW TASK rejects a blank dest.'.

* WRONG - falls back to a local call when customizing is incomplete:
*
* SELECT SINGLE rfcdest FROM ztc_config INTO @DATA(lv_dest)
*   WHERE area = 'STOCK'.
*
* CALL FUNCTION 'Z_READ_STOCK' DESTINATION lv_dest
*   EXPORTING  iv_werks = gv_werks
*   IMPORTING  ev_menge = gv_menge
*   EXCEPTIONS system_failure        = 1 MESSAGE gv_smess
*              communication_failure = 2 MESSAGE gv_cmess
*              OTHERS                = 3.

*&---------------------------------------------------------------------*
*& Part 2 - character parameters are cut short instead of raising
*&---------------------------------------------------------------------*
  SKIP.
  WRITE: / '2. Character length mismatch between the two systems'.
  ULINE.

  gv_long = 'MATERIAL-000000123'.

* The doc states a shorter actual parameter is filled with blanks on the
* right on input and cut short on output; if longer, the reverse
* applies. The shorter side always wins, and nothing is raised.
  gv_short = gv_long.
  gv_back  = gv_short.

  gv_len = strlen( gv_long ).
  WRITE: / 'sent   (18 chars)', gv_long, gv_len.
  gv_len = strlen( gv_short ).
  WRITE: / 'landed (10 chars)', gv_short, gv_len.
  WRITE: / 'returned         ', gv_back.

  IF gv_back <> gv_long.
    WRITE: / 'Round trip LOST data - and no exception was raised.'.
  ENDIF.

  SKIP.
  WRITE: / 'Also ignored silently: a misspelled formal parameter name.'.
  WRITE: / 'Bindings to incorrect formal parameters are discarded and'.
  WRITE: / 'the parameter takes its initial value - every RFC formal'.
  WRITE: / 'parameter is implicitly OPTIONAL. Run SLIN: the extended'.
  WRITE: / 'program check is the only thing that flags this.'.

*&---------------------------------------------------------------------*
*& Part 3 - class-based exceptions do not cross the wire
*&---------------------------------------------------------------------*
  SKIP.
  WRITE: / '3. What the caller can actually catch'.
  ULINE.

  WRITE: / 'remote RAISE EXCEPTION TYPE zcx_no_authority'.
  WRITE: / '  -> arrives as the CLASSIC exception SYSTEM_FAILURE'.
  WRITE: / '  -> TRY / CATCH zcx_no_authority catches NOTHING'.
  WRITE: / '  -> error_message after EXCEPTIONS is ignored in RFC'.
  WRITE: / '  -> MESSAGE smess holds line 1 of the remote short dump'.
  SKIP.
  WRITE: / 'Always handle SYSTEM_FAILURE and COMMUNICATION_FAILURE'.
  WRITE: / '(plus RESOURCE_FAILURE for DESTINATION IN GROUP, which'.
  WRITE: / 'does not allow the MESSAGE addition).'.
  SKIP.
  WRITE: / 'Remote messages: I / S / W are ignored; A / E / X terminate'.
  WRITE: / 'with a database ROLLBACK and raise SYSTEM_FAILURE.'.

*&---------------------------------------------------------------------*
*& Part 4 - WAIT FOR ASYNCHRONOUS TASKS returns 4 for nothing to wait for
*&---------------------------------------------------------------------*
  SKIP.
  WRITE: / '4. WAIT FOR ASYNCHRONOUS TASKS sy-subrc'.
  ULINE.

* Not executed - there are no registered callback routines here, and the
* statement would trigger a database commit. Values quoted from the doc.
  gv_subrc = 0.
  WRITE: / gv_subrc, 'condition is true'.
  gv_subrc = 4.
  WRITE: / gv_subrc, 'false AND no async calls left - NOT a timeout'.
  gv_subrc = 8.
  WRITE: / gv_subrc, 'false and UP TO sec SECONDS was exceeded'.

  SKIP.
  WRITE: / 'Treating 4 as a timeout and retrying will spin forever:'.
  WRITE: / 'it is also what you get when nothing was ever registered.'.
  WRITE: / 'sec is type f; a negative value is the uncatchable'.
  WRITE: / 'runtime error WAIT_ILLEGAL_TIME_LIMIT. An expired UP TO'.
  WRITE: / 'does not cancel outstanding callbacks either.'.

* CALL FUNCTION 'Z_READ_STOCK' STARTING NEW TASK lv_task
*   DESTINATION IN GROUP DEFAULT
*   PERFORMING collect_result ON END OF TASK
*   EXPORTING  iv_werks = gv_werks
*   EXCEPTIONS resource_failure      = 1
*              system_failure        = 2
*              communication_failure = 3.
*
* WAIT FOR ASYNCHRONOUS TASKS UNTIL gv_done >= gv_sent UP TO 60 SECONDS.

*&---------------------------------------------------------------------*
*& Part 5 - the LUW the call ends behind your back
*&---------------------------------------------------------------------*
  SKIP.
  WRITE: / '5. Every RFC commits the CALLING program'.
  ULINE.

  WRITE: / 'sRFC, aRFC and an interrupting WAIT each trigger a database'.
  WRITE: / 'commit in the caller (an sRFC during the update is the'.
  WRITE: / 'documented exception). Consequences:'.
  WRITE: / '  - work written before the call cannot be rolled back'.
  WRITE: / '  - pending IN UPDATE TASK registrations fire EARLY'.
  WRITE: / '  - every open database cursor is closed, so an RFC inside a'.
  WRITE: / '    SELECT ... PACKAGE SIZE loop dumps DBSQL_INVALID_CURSOR'.

*&---------------------------------------------------------------------*
*& Part 6 - callback routine shape (registered by nothing here)
*&---------------------------------------------------------------------*
FORM collect_result USING p_task TYPE clike.

* The RFC interface fills p_task with the task ID from the call. A
* callback routine WITHOUT this RECEIVE behaves as if KEEPING TASK were
* specified: the connection and the remote RFC session stay open.
*
* RECEIVE RESULTS FROM FUNCTION 'Z_READ_STOCK'
*   IMPORTING  ev_menge = gv_menge
*   EXCEPTIONS system_failure        = 1 MESSAGE gv_smess
*              communication_failure = 2 MESSAGE gv_cmess
*              OTHERS                = 3.
*
* No statement that interrupts the routine or triggers an implicit
* database commit is allowed here, class-based exceptions must be
* handled inside, and list output statements are not executed.

ENDFORM.
