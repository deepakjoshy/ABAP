*&---------------------------------------------------------------------*
*& Report YDJ_EXCEPTION_FLOW_DEMO
*&---------------------------------------------------------------------*
*& The three TRY-block statements nobody uses because the rules are
*& counter-intuitive: CLEANUP, RETRY, RESUME.
*&
*& The one fact that surprises everyone: CLEANUP is NOT a finally block.
*& It runs only when the exception leaves its own TRY structure. If the
*& very same TRY has a CATCH that handles it, CLEANUP never runs.
*&---------------------------------------------------------------------*
REPORT ydj_exception_flow_demo.

CLASS lcx_locked DEFINITION INHERITING FROM cx_static_check.
ENDCLASS.

CLASS lcx_transient DEFINITION INHERITING FROM cx_static_check.
ENDCLASS.


CLASS lcl_demo DEFINITION.

  PUBLIC SECTION.
    CLASS-METHODS:
      "! CLEANUP fires only when the exception escapes this TRY.
      "! @parameter iv_catchable_here | ABAP_TRUE -> inner CATCH matches, CLEANUP skipped
      cleanup_scope IMPORTING iv_catchable_here TYPE abap_bool,

      "! RETRY re-runs the whole TRY block from the top.
      retry_demo,

      "! RESUME continues at the statement AFTER the RAISE.
      resume_demo.

  PRIVATE SECTION.
    CLASS-DATA:
      gv_lock_held TYPE abap_bool,
      gv_attempt   TYPE i.

    CLASS-METHODS:
      "! Fails on the first two calls, succeeds on the third.
      flaky_read RETURNING VALUE(rv_value) TYPE string
                 RAISING   lcx_transient,

      "! Resumable: the caller decides whether to carry on.
      post_items RAISING RESUMABLE(lcx_locked).

ENDCLASS.


CLASS lcl_demo IMPLEMENTATION.

  METHOD cleanup_scope.

    TRY.
        " Outer structure - the real handler for lcx_transient.
        TRY.
            gv_lock_held = abap_true.
            WRITE: / '  lock acquired'.

            " Only lcx_locked has a matching CATCH in THIS structure.
            IF iv_catchable_here = abap_true.
              RAISE EXCEPTION TYPE lcx_locked.
            ELSE.
              RAISE EXCEPTION TYPE lcx_transient.
            ENDIF.

          CATCH lcx_locked.
            WRITE: / '  CATCH (inner, same TRY)'.

          CLEANUP.
            " Reached ONLY when the exception leaves this TRY structure.
            " Must run to completion: no RETURN, no EXIT, no unhandled
            " exception in here - any of those is a runtime error.
            gv_lock_held = abap_false.
            WRITE: / '  CLEANUP ran -> lock released'.
        ENDTRY.

      CATCH lcx_transient.
        WRITE: / '  CATCH (outer)'.
    ENDTRY.

    WRITE: / '  lock still held?', gv_lock_held.

  ENDMETHOD.

  METHOD flaky_read.
    gv_attempt = gv_attempt + 1.
    IF gv_attempt < 3.
      RAISE EXCEPTION TYPE lcx_transient.
    ENDIF.
    rv_value = |value read on attempt { gv_attempt }|.
  ENDMETHOD.

  METHOD retry_demo.

    gv_attempt = 0.

    TRY.
        DATA(lv_result) = flaky_read( ).
        WRITE: / '  ', lv_result.

      CATCH lcx_transient.
        WRITE: / '  attempt', gv_attempt, 'failed'.
        " Remove the cause first, otherwise RETRY loops forever - there is
        " no built-in attempt counter. Here the cause clears itself; in real
        " code guard it with your own counter.
        IF gv_attempt < 5.
          RETRY.            " restarts the TRY block from the first statement
        ENDIF.
        WRITE: / '  giving up'.
    ENDTRY.

  ENDMETHOD.

  METHOD post_items.

    WRITE: / '  posting item 1'.

    " RESUMABLE is needed at BOTH ends: here and in the RAISING clause.
    RAISE RESUMABLE EXCEPTION TYPE lcx_locked.

    " Execution comes back to exactly this line after RESUME.
    WRITE: / '  posting item 2 (resumed)'.

  ENDMETHOD.

  METHOD resume_demo.

    TRY.
        post_items( ).
        WRITE: / '  post_items returned normally'.

        " BEFORE UNWIND keeps the raising context alive, which is what makes
        " RESUME possible. Without it, RESUME is a syntax error.
      CATCH BEFORE UNWIND lcx_locked INTO DATA(lo_err).
        IF lo_err->is_resumable = abap_true.
          WRITE: / '  resumable -> continuing'.
          RESUME.                      " back to the statement after the RAISE
        ENDIF.
        WRITE: / '  not resumable -> aborting'.
    ENDTRY.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  WRITE: / '1. CLEANUP - exception handled INSIDE the same TRY'.
  lcl_demo=>cleanup_scope( iv_catchable_here = abap_true ).

  SKIP.
  WRITE: / '2. CLEANUP - exception escapes to the outer TRY'.
  lcl_demo=>cleanup_scope( iv_catchable_here = abap_false ).

  SKIP.
  WRITE: / '3. RETRY'.
  lcl_demo=>retry_demo( ).

  SKIP.
  WRITE: / '4. RESUME'.
  lcl_demo=>resume_demo( ).
