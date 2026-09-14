*&---------------------------------------------------------------------*
*& Report YDJ_ENQUEUE_LOCK_DEMO
*&---------------------------------------------------------------------*
*& Setting and releasing SAP locks (ENQUEUE_/DEQUEUE_) the way the
*& parameters actually behave, not the way the call looks.
*&
*& Three things this demo makes explicit, because all three fail SILENTLY
*& - no dump, no sy-subrc, just a lock that protects the wrong thing:
*&   1. _SCOPE defaults differ per module: 2 for ENQUEUE, 3 for DEQUEUE.
*&      _SCOPE = 2 only survives COMMIT WORK if an update FM was actually
*&      registered; with no update, the lock stays a dialog lock.
*&   2. An unfilled key field gives a GENERIC lock over that field. To
*&      lock on a genuinely initial value, pass X_<field> = 'X'.
*&   3. FOREIGN_LOCK carries the competing user's name in sy-msgv1 - read
*&      it there. SYSTEM_FAILURE means the lock was NOT set; never log
*&      and continue past it.
*&
*& Prerequisite: the SAP demo lock object EDEMOFLHT (table SFLIGHT,
*& key CARRID / CONNID / FLDATE). Swap in your own lock object as needed.
*&---------------------------------------------------------------------*
REPORT ydj_enqueue_lock_demo.

CLASS lcx_locked DEFINITION INHERITING FROM cx_static_check.
  PUBLIC SECTION.
    DATA mv_owner TYPE sy-msgv1 READ-ONLY.
    METHODS constructor IMPORTING iv_owner TYPE sy-msgv1 OPTIONAL.
ENDCLASS.

CLASS lcx_locked IMPLEMENTATION.
  METHOD constructor.
    super->constructor( ).
    mv_owner = iv_owner.
  ENDMETHOD.
ENDCLASS.


CLASS lcl_flight_lock DEFINITION.

  PUBLIC SECTION.
    CLASS-METHODS:
      "! Locks exactly one flight. FLDATE initial would lock the whole
      "! connection, so iv_exact forces X_FLDATE = 'X' instead.
      "! @parameter iv_scope  | '1' dialog, '2' update, '3' both
      "! @parameter iv_wait   | abap_true = retry before giving up (batch only)
      "! @parameter iv_exact  | abap_true = lock initial FLDATE, not generically
      lock   IMPORTING iv_carrid TYPE sflight-carrid
                       iv_connid TYPE sflight-connid
                       iv_fldate TYPE sflight-fldate OPTIONAL
                       iv_scope  TYPE ddenq_like-scope DEFAULT '1'
                       iv_wait   TYPE abap_bool        DEFAULT abap_false
                       iv_exact  TYPE abap_bool        DEFAULT abap_false
             RAISING   lcx_locked,

      "! _SCOPE on DEQUEUE must be >= the _SCOPE used on ENQUEUE.
      "! _SYNCHRON = 'X' waits until the entry is really gone, so a
      "! following SM12 / lock-table read does not still show it.
      unlock IMPORTING iv_carrid TYPE sflight-carrid
                       iv_connid TYPE sflight-connid
                       iv_fldate TYPE sflight-fldate OPTIONAL
                       iv_scope  TYPE ddenq_like-scope DEFAULT '1'.

ENDCLASS.


CLASS lcl_flight_lock IMPLEMENTATION.

  METHOD lock.

    " '@' is a wildcard during collision checks - a key value carrying it
    " silently collides with unrelated rows. Sanitise before locking.
    IF iv_carrid CA '@' OR iv_connid CA '@'.
      RAISE EXCEPTION TYPE lcx_locked.
    ENDIF.

    CALL FUNCTION 'ENQUEUE_EDEMOFLHT'
      EXPORTING
        mode_sflight   = 'E'            " E = exclusive, cumulative.
                                        " X would be REJECTED on a second
                                        " request in the same LUW - wrong
                                        " for a reusable helper like this.
        carrid         = iv_carrid
        connid         = iv_connid
        fldate         = iv_fldate
        x_fldate       = iv_exact       " ' ' + initial FLDATE = generic lock
                                        " 'X' + initial FLDATE = that value
        _scope         = iv_scope
        _wait          = iv_wait
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.

    CASE sy-subrc.
      WHEN 0.
        " locked
      WHEN 1.
        " The competing user's name is in sy-msgv1 - nowhere else.
        RAISE EXCEPTION TYPE lcx_locked EXPORTING iv_owner = sy-msgv1.
      WHEN OTHERS.
        " SYSTEM_FAILURE: the lock was NOT set. Same severity as a
        " foreign lock - never treat it as a warning and carry on.
        RAISE EXCEPTION TYPE lcx_locked.
    ENDCASE.

  ENDMETHOD.

  METHOD unlock.

    CALL FUNCTION 'DEQUEUE_EDEMOFLHT'
      EXPORTING
        mode_sflight = 'E'              " must match the ENQUEUE mode
        carrid       = iv_carrid
        connid       = iv_connid
        fldate       = iv_fldate
        _scope       = iv_scope
        _synchron    = 'X'
      EXCEPTIONS
        OTHERS       = 1.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  DATA lv_fldate TYPE sflight-fldate.

  " --- 1. Dialog lock, released explicitly ----------------------------
  " _SCOPE = 1: COMMIT WORK / ROLLBACK WORK do NOT touch this lock. It
  " lives until the DEQUEUE below, or until the program ends.
  TRY.
      lcl_flight_lock=>lock( iv_carrid = 'LH'
                             iv_connid = '0400'
                             iv_fldate = '20260601'
                             iv_scope  = '1' ).
      WRITE: / 'dialog lock (_SCOPE 1) held - visible in SM12'.

      lcl_flight_lock=>unlock( iv_carrid = 'LH'
                               iv_connid = '0400'
                               iv_fldate = '20260601'
                               iv_scope  = '1' ).
      WRITE: / 'dialog lock released'.

    CATCH lcx_locked INTO DATA(lo_err).
      WRITE: / 'locked by', lo_err->mv_owner.
  ENDTRY.

  " --- 2. Generic vs exact lock on an initial key field ---------------
  " lv_fldate is initial here. Without x_fldate this locks EVERY date of
  " LH 0400, not one flight - the classic "a blank input field widened
  " my lock to the whole connection" bug.
  TRY.
      lcl_flight_lock=>lock( iv_carrid = 'LH'
                             iv_connid = '0400'
                             iv_fldate = lv_fldate
                             iv_exact  = abap_true ).   " <- exactly 00000000
      WRITE: / 'exact lock on initial FLDATE (x_fldate = X)'.

      lcl_flight_lock=>unlock( iv_carrid = 'LH'
                               iv_connid = '0400'
                               iv_fldate = lv_fldate ).

    CATCH lcx_locked.
      WRITE: / 'generic/exact lock rejected'.
  ENDTRY.

  " --- 3. Handing the lock to the update task -------------------------
  " _SCOPE = 2 is only meaningful if an update FM is registered BEFORE
  " the COMMIT. With no CALL FUNCTION ... IN UPDATE TASK, the commit has
  " no effect on the lock and it stays a dialog lock until program end -
  " which is the real answer to "I committed, why is it still locked?".
  TRY.
      lcl_flight_lock=>lock( iv_carrid = 'LH'
                             iv_connid = '0400'
                             iv_fldate = '20260601'
                             iv_scope  = '2' ).

      " CALL FUNCTION 'Z_POST_FLIGHT' IN UPDATE TASK
      "   EXPORTING is_flight = ls_flight.

      COMMIT WORK.                      " hands the lock to the update task;
                                        " the update releases it when done.
      WRITE: / 'lock passed to update task (_SCOPE 2)'.

    CATCH lcx_locked.
      WRITE: / 'could not acquire update-scope lock'.
  ENDTRY.
