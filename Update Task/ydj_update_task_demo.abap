*&---------------------------------------------------------------------*
*& Report YDJ_UPDATE_TASK_DEMO
*&---------------------------------------------------------------------*
*& CALL FUNCTION ... IN UPDATE TASK is a REGISTRATION, not a call. The
*& statement accepts EXCEPTIONS and leaves a sy-subrc behind, so the
*& usual error handling gets written - and none of it does anything.
*&
*& The cases below are all documented behaviour. Every one of them is
*& silent at the call site.
*&
*&   1. NO RETURN CHANNEL -> sy-subrc is UNDEFINED after the statement,
*&                           and IMPORTING / CHANGING / EXCEPTIONS "may
*&                           be specified, but they are ignored during
*&                           the execution". An update module cannot
*&                           hand a document number back to you.
*&   2. SERIALIZED PARAMS -> the actual parameters are EXPORTed to a
*&                           data cluster and IMPORTed again in the
*&                           update, so a typing mismatch dumps THERE,
*&                           not here. Reference variables are not
*&                           allowed at all.
*&   3. TWICE MEANS TWICE -> a module registered n times runs n times.
*&                           PERFORM ON COMMIT is the opposite: a
*&                           subroutine registered n times runs ONCE.
*&   4. ASYNC IS SILENT   -> plain COMMIT WORK always sets sy-subrc = 0.
*&                           Only COMMIT WORK AND WAIT reports the
*&                           update outcome (4 = failed). A failed
*&                           async update reaches the user by SAPMail
*&                           and SM13, never by your program.
*&   5. V1 VS V2          -> V1 modules share one database LUW; V2 runs
*&                           in a SEPARATE one, and only after all V1
*&                           modules succeeded. A V2 failure leaves the
*&                           V1 work committed. Priority is a
*&                           consistency decision, not a tuning knob.
*&   6. LOCAL UPDATE      -> SET UPDATE TASK LOCAL returns sy-subrc = 1
*&                           if anything was already registered, is
*&                           switched off again at the start of every
*&                           SAP LUW, and is ignored by V2 modules.
*&   7. FORBIDDEN INSIDE  -> COMMIT/ROLLBACK WORK, SUBMIT, CALL SCREEN,
*&                           CALL TRANSACTION and every LEAVE variant
*&                           dump inside an update module. So does a
*&                           type A message caught via error_message.
*&   8. NO COMMIT AT ALL  -> if the program ends without COMMIT WORK the
*&                           registrations are simply deleted. No dump,
*&                           no log, no SM13 entry. The work never
*&                           happened and nothing says so.
*&
*& Read-only: this program REGISTERS NOTHING and COMMITS NOTHING. Every
*& CALL FUNCTION ... IN UPDATE TASK, PERFORM ... ON COMMIT and COMMIT
*& WORK is shown as a comment, and there is no database access at all.
*& The one thing it really executes is part 1, which demonstrates on a
*& harmless statement why reading an undefined sy-subrc is dangerous:
*& the field still holds the PREVIOUS statement's value, so the check
*& looks like it works.
*&
*& Docs: https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-us/abapcall_function_update.htm
*&       https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-us/abapcommit.htm
*&       https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-us/abapset_update_task_local.htm
*&       https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abendb_commit_during_update.htm
*&---------------------------------------------------------------------*
REPORT ydj_update_task_demo.

DATA: gt_numbers TYPE STANDARD TABLE OF i WITH EMPTY KEY,
      gv_subrc   TYPE sy-subrc,
      gv_stale   TYPE sy-subrc,
      gv_dummy   TYPE i.

START-OF-SELECTION.

*----------------------------------------------------------------------*
* 1. sy-subrc after the registration is undefined - and undefined does
*    NOT mean initial. It means whatever the last statement that did
*    set it left behind. Demonstrated here with an ordinary READ TABLE
*    followed by an assignment, which sets no sy-subrc of its own.
*----------------------------------------------------------------------*
  WRITE: / '1. The undefined sy-subrc'.
  WRITE: / '   ---------------------------------------------------'.

  APPEND 1 TO gt_numbers.
  APPEND 2 TO gt_numbers.

  READ TABLE gt_numbers WITH KEY table_line = 99 TRANSPORTING NO FIELDS.
  gv_subrc = sy-subrc.

* An assignment does not touch sy-subrc, so the old value survives.
* Both values are captured BEFORE any output, so no statement in
* between can be blamed for the result.
  gv_dummy = 1.
  gv_stale = sy-subrc.

  WRITE: / '   after a failing READ TABLE   sy-subrc =', gv_subrc.
  WRITE: / '   after an assignment          sy-subrc =', gv_stale,
           '(stale)'.

  WRITE: / '   CALL FUNCTION ... IN UPDATE TASK behaves the same way:'.
  WRITE: / '   the doc says sy-subrc is UNDEFINED afterwards, so an'.
  WRITE: / '   IF sy-subrc <> 0 tests the PREVIOUS statement.'.
  SKIP.

* WRONG - none of this error handling exists at runtime:
*
*   CALL FUNCTION 'Z_POST_DOCUMENT' IN UPDATE TASK
*     EXPORTING  is_header      = ls_header
*     IMPORTING  ev_docnr       = lv_docnr     "<-- ignored, stays initial
*     EXCEPTIONS posting_failed = 1            "<-- ignored, never raised
*                OTHERS         = 2.
*
*   IF sy-subrc <> 0.                          "<-- undefined, not the FM
*     MESSAGE e001(zfi).
*   ENDIF.
*
* RIGHT - only EXPORTING and TABLES are real, no reference variables,
* and the key must be known BEFORE registering:
*
*   CALL FUNCTION 'Z_POST_DOCUMENT' IN UPDATE TASK
*     EXPORTING is_header = ls_header          " lv_docnr already drawn
*     TABLES    it_items  = lt_items.

*----------------------------------------------------------------------*
* 2. Which additions survive the registration.
*----------------------------------------------------------------------*
  WRITE: / '2. What the statement actually accepts'.
  WRITE: / '   ---------------------------------------------------'.
  WRITE: / '   EXPORTING   real - but no reference variables, and no'.
  WRITE: / '               structures containing references'.
  WRITE: / '   TABLES      real - duplicate row order is NOT retained'.
  WRITE: / '               for non-unique keys'.
  WRITE: / '   IMPORTING   accepted by the syntax check, ignored at'.
  WRITE: / '               runtime - no value ever comes back'.
  WRITE: / '   CHANGING    same - accepted, ignored'.
  WRITE: / '   EXCEPTIONS  same - accepted, never raised'.
  WRITE: / '   dynamic     not allowed at all'.
  SKIP.
  WRITE: / '   Parameters travel via EXPORT to a data cluster and'.
  WRITE: / '   IMPORT in the update, so a typing mismatch raises its'.
  WRITE: / '   exception in the UPDATE work process, not at the call.'.
  SKIP.

*----------------------------------------------------------------------*
* 3. Duplicate registrations - and the opposite rule for ON COMMIT.
*----------------------------------------------------------------------*
  WRITE: / '3. Registering the same thing twice'.
  WRITE: / '   ---------------------------------------------------'.
  WRITE: / '   IN UPDATE TASK    registered n times -> runs n times'.
  WRITE: / '   PERFORM ON COMMIT registered n times -> runs ONCE'.
  SKIP.
  WRITE: / '   Two bundling techniques in one program, two different'.
  WRITE: / '   duplicate semantics. A retry loop that re-registers is'.
  WRITE: / '   a double posting with the first, a no-op with the'.
  WRITE: / '   second.'.
  SKIP.

*----------------------------------------------------------------------*
* 4. The commit variants. Only one of them reports anything.
*----------------------------------------------------------------------*
  WRITE: / '4. COMMIT WORK vs COMMIT WORK AND WAIT'.
  WRITE: / '   ---------------------------------------------------'.
  WRITE: / '   COMMIT WORK           sy-subrc ALWAYS 0 - says nothing'.
  WRITE: / '                         about the update at all'.
  WRITE: / '   COMMIT WORK AND WAIT  0 = updates succeeded'.
  WRITE: / '                         4 = updates FAILED'.
  SKIP.
  WRITE: / '   When an async update dies the update work process does'.
  WRITE: / '   a database rollback, logs it (SM13) and notifies the'.
  WRITE: / '   user by SAPMail. The program that scheduled it has'.
  WRITE: / '   already told the user it worked.'.
  SKIP.

*----------------------------------------------------------------------*
* 5. V1 / V2 priority is a transaction boundary.
*----------------------------------------------------------------------*
  WRITE: / '5. High priority (V1) vs low priority (V2)'.
  WRITE: / '   ---------------------------------------------------'.
  WRITE: / '   V1  registration order, ONE shared database LUW,'.
  WRITE: / '       all-or-nothing across every V1 module'.
  WRITE: / '   V2  runs only after ALL V1 modules succeeded, in a'.
  WRITE: / '       SEPARATE shared database LUW'.
  SKIP.
  WRITE: / '   So a V2 failure rolls back the V2 work and leaves'.
  WRITE: / '   every V1 change committed. Moving a posting step to'.
  WRITE: / '   V2 because it can wait takes it out of the document'.
  WRITE: / '   transaction.'.
  SKIP.

*----------------------------------------------------------------------*
* 6. SET UPDATE TASK LOCAL - the sy-subrc nobody reads.
*----------------------------------------------------------------------*
  WRITE: / '6. SET UPDATE TASK LOCAL'.
  WRITE: / '   ---------------------------------------------------'.
  WRITE: / '   sy-subrc = 0  local update is active'.
  WRITE: / '   sy-subrc = 1  NOT active - something was already'.
  WRITE: / '                 registered in this SAP LUW'.
  SKIP.
  WRITE: / '   It is switched off again at the start of every SAP'.
  WRITE: / '   LUW, so a loop that commits per iteration is local'.
  WRITE: / '   only on the first pass. V2 modules ignore it. A'.
  WRITE: / '   rollback during a local update affects ALL previous'.
  WRITE: / '   change requests - there is no separate update LUW to'.
  WRITE: / '   contain it.'.
  SKIP.
  WRITE: / '   Profile parameter abap/force_local_update_task can'.
  WRITE: / '   switch this on for the whole system, so do not write'.
  WRITE: / '   code that depends on the update being remote.'.
  SKIP.

* Correct sequence - the SET comes FIRST and its sy-subrc is checked:
*
*   SET UPDATE TASK LOCAL.
*   IF sy-subrc <> 0.
*     " too late - a module was already registered asynchronously
*   ENDIF.
*
*   CALL FUNCTION 'Z_POST_DOCUMENT' IN UPDATE TASK
*     EXPORTING is_header = ls_header.
*
*   COMMIT WORK.                  " local update runs synchronously here

*----------------------------------------------------------------------*
* 7. Statements that are legal everywhere else and dump in an update.
*----------------------------------------------------------------------*
  WRITE: / '7. Forbidden inside an update function module'.
  WRITE: / '   ---------------------------------------------------'.
  WRITE: / '   COMMIT WORK                   COMMIT_IN_POSTING'.
  WRITE: / '   ROLLBACK WORK                 ROLLBACK_IN_POSTING'.
  WRITE: / '   SUBMIT / CALL SCREEN /'.
  WRITE: / '   CALL DIALOG / CALL TRANSACTION /'.
  WRITE: / '   CALL SELECTION-SCREEN /'.
  WRITE: / '   SET SCREEN / any LEAVE        POSTING_ILLEGAL_STATEMENT'.
  WRITE: / '   Native SQL COMMIT/ROLLBACK    POSTING_ILLEGAL_STATEMENT'.
  WRITE: / '   type A msg via error_message  MESSAGE_ROLLBACK_IN_POSTING'.
  SKIP.
  WRITE: / '   Asymmetry worth remembering: MESSAGE of type I, W, E'.
  WRITE: / '   and A also forces an implicit database rollback, but'.
  WRITE: / '   raises NO runtime error, for downward compatibility.'.
  WRITE: / '   Messages stay the quiet way to wreck an update.'.
  SKIP.

*----------------------------------------------------------------------*
* 8. The missing COMMIT WORK, and what ROLLBACK WORK really discards.
*----------------------------------------------------------------------*
  WRITE: / '8. No COMMIT WORK at all'.
  WRITE: / '   ---------------------------------------------------'.
  WRITE: / '   Program ends without a commit: the registrations are'.
  WRITE: / '   deleted when the program ends. The module never runs.'.
  WRITE: / '   No dump, no log, no SM13 entry - nothing reports it.'.
  SKIP.
  WRITE: / '   ROLLBACK WORK does it deliberately: it EXECUTES the'.
  WRITE: / '   PERFORM ON ROLLBACK subroutines, and DELETES every'.
  WRITE: / '   PERFORM ON COMMIT registration and every update'.
  WRITE: / '   module registered in this SAP LUW.'.
  SKIP.
  WRITE: / '   The registrations also live in a normal database LUW,'.
  WRITE: / '   so an implicit rollback earlier in the program can'.
  WRITE: / '   discard registrations you are still counting on.'.
  SKIP.

*----------------------------------------------------------------------*
* 9. IN UPDATE TASK vs PERFORM ON COMMIT - same trigger, different
*    process, different LUW.
*----------------------------------------------------------------------*
  WRITE: / '9. IN UPDATE TASK vs PERFORM ON COMMIT'.
  WRITE: / '   ---------------------------------------------------'.
  WRITE: / '   runs in     update work process  /  CURRENT process'.
  WRITE: / '   when        after ON COMMIT      /  BEFORE the updates'.
  WRITE: / '   parameters  EXPORTING, TABLES    /  none at all'.
  WRITE: / '   twice       runs twice           /  runs once'.
  WRITE: / '   ordering    registration order   /  order or LEVEL idx'.
  WRITE: / '   COMMIT in   forbidden            /  allowed'.
  SKIP.
  WRITE: / '   Mixing them is not one transaction: for an async'.
  WRITE: / '   update the two run in different work processes and'.
  WRITE: / '   different database LUWs, and a rollback during the'.
  WRITE: / '   update does NOT undo what the subroutine committed.'.
  WRITE: / '   A log row written ON COMMIT can outlive the document'.
  WRITE: / '   it claims was posted.'.
  SKIP.
  WRITE: / '   Registered subroutines have no parameter interface at'.
  WRITE: / '   all, so data goes through ABAP memory - which brings'.
  WRITE: / '   the IMPORT-is-a-merge trap with it. Current guidance:'.
  WRITE: / '   subroutines are obsolete, use them only as a wrapper'.
  WRITE: / '   around a method call.'.
