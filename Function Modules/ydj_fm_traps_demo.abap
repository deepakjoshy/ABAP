*&---------------------------------------------------------------------*
*& Report YDJ_FM_TRAPS_DEMO
*&---------------------------------------------------------------------*
*& Function modules - the procedure whose error handling is OPT-IN, and
*& whose failure mode when you opt out is a return code of zero.
*&
*& Every section below is executable and prints the surprising result
*& next to the expected one. The classic (non-class-based) exception
*& mechanism is demonstrated on LOCAL CLASS METHODS, because a report
*& cannot define a function group - and the mechanism is identical: the
*& ABAP documentation for RAISE uses a method for exactly this reason
*& (see the "Raising of a non-class-based exception in a method"
*& example on the RAISE page). Sections 3 to 5 then call a REAL
*& function module, DATE_CHECK_PLAUSIBILITY, which is read-only.
*&
*&   1. RETURN CODES     -> RAISE reaches the caller as sy-subrc only
*&                          because the CALLER chose to listen. The
*&                          same RAISE with exc = 0 is swallowed and
*&                          sy-subrc stays 0.
*&   2. VALUE vs REF     -> an output parameter passed BY VALUE is not
*&                          assigned when the procedure exits through
*&                          an exception. BY REFERENCE, the half-built
*&                          value is already in the caller's variable.
*&   3. REAL FM          -> DATE_CHECK_PLAUSIBILITY with a return code,
*&                          and the same call with = 0, which turns a
*&                          rejected date into sy-subrc = 0.
*&   4. MISSPELLING      -> a mistyped exception NAME is not checked at
*&                          runtime. The exception is raised, nothing
*&                          complains, and it lands in OTHERS.
*&   5. DYNAMIC NAME     -> with the function module name in a variable
*&                          a nonexistent formal parameter is ignored
*&                          at runtime instead of raising.
*&   6. sy-msg*          -> RAISE leaves the message fields untouched;
*&                          MESSAGE RAISING is the variant that carries
*&                          a text. Printed side by side.
*&
*& No DB writes, no COMMIT, no locks, no screens. DATE_CHECK_PLAUSIBILITY
*& is a pure check (function group SCON, program SAPLSCON).
*&
*& Note: every built-in call is hoisted into a variable before WRITE,
*& because functional calls are not allowed in a WRITE list.
*&
*& Docs: https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPCALL_FUNCTION.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPCALL_FUNCTION_PARAMETER.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPRAISE_EXCEPTION.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPFUNCTION-POOL.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENINTERNAL_SESSION.html
*&---------------------------------------------------------------------*
REPORT ydj_fm_traps_demo.

*&---------------------------------------------------------------------*
*& A local class standing in for a function module.
*&
*& EXCEPTIONS (not RAISING) declares NON-class-based exceptions - the
*& same kind a function module declares in the Function Builder. The
*& addition comes last in the signature, after IMPORTING/EXPORTING.
*&---------------------------------------------------------------------*
CLASS lcl_fm DEFINITION.
  PUBLIC SECTION.

    " Output parameter passed BY VALUE: the VALUE( ) is explicit.
    CLASS-METHODS build_by_value
      IMPORTING iv_limit TYPE i
      EXPORTING VALUE(ev_text) TYPE string
      EXCEPTIONS too_big.

    " Same body, output parameter passed BY REFERENCE. For methods,
    " omitting VALUE( ) means by reference - the dangerous form is the
    " one that is invisible in the code.
    CLASS-METHODS build_by_ref
      IMPORTING iv_limit TYPE i
      EXPORTING ev_text TYPE string
      EXCEPTIONS too_big.

ENDCLASS.

CLASS lcl_fm IMPLEMENTATION.

  METHOD build_by_value.
    ev_text = `partially built`.
    IF iv_limit > 5.
      RAISE too_big.
    ENDIF.
    ev_text = `completed`.
  ENDMETHOD.

  METHOD build_by_ref.
    ev_text = `partially built`.
    IF iv_limit > 5.
      RAISE too_big.
    ENDIF.
    ev_text = `completed`.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& Data
*&---------------------------------------------------------------------*
DATA: lv_text     TYPE string,
      lv_subrc    TYPE i,
      lv_msgid    TYPE sy-msgid,
      lv_msgno    TYPE sy-msgno,
      lv_msgty    TYPE sy-msgty,
      lv_good     TYPE sy-datum,
      lv_bad      TYPE sy-datum,
      lv_fm_name  TYPE c LENGTH 30,
      lv_dummy    TYPE i,
      lv_err      TYPE string,
      lx_root     TYPE REF TO cx_root.

START-OF-SELECTION.

  " 31 February never exists. '20261124' is a real date.
  lv_good = '20261124'.
  lv_bad  = '20260231'.

*&---------------------------------------------------------------------*
*& 1. The return code exists only because the caller asked for it
*&---------------------------------------------------------------------*
  WRITE: / '=== 1. RAISE reaches the caller only if the caller listens'.

  " (a) A return code is assigned, so the exception is handled.
  CLEAR lv_text.
  lcl_fm=>build_by_value(
    EXPORTING  iv_limit = 9
    IMPORTING  ev_text  = lv_text
    EXCEPTIONS too_big  = 4 ).
  lv_subrc = sy-subrc.
  WRITE: / '  too_big = 4   -> sy-subrc', lv_subrc, '(handled)'.

  " (b) The SAME RAISE, with the return code 0. The documentation calls
  "     this "the caller wants to ignore this exception": no runtime
  "     error, and sy-subrc = 0 - identical to a successful call.
  CLEAR lv_text.
  lcl_fm=>build_by_value(
    EXPORTING  iv_limit = 9
    IMPORTING  ev_text  = lv_text
    EXCEPTIONS too_big  = 0 ).
  lv_subrc = sy-subrc.
  WRITE: / '  too_big = 0   -> sy-subrc', lv_subrc,
           '(raised, but indistinguishable from success)'.

  " (c) Omitting the exception entirely is the third behaviour: for
  "     RAISE it is a runtime error (RAISE_EXCEPTION) that names the
  "     exception. Left commented out so this report cannot dump.
  "lcl_fm=>build_by_value( EXPORTING iv_limit = 9
  "                        IMPORTING ev_text  = lv_text ).

*&---------------------------------------------------------------------*
*& 2. BY VALUE is not assigned on the way out. BY REFERENCE already is.
*&---------------------------------------------------------------------*
  SKIP.
  WRITE: / '=== 2. What the caller sees in the output parameter'.

  CLEAR lv_text.
  lcl_fm=>build_by_value(
    EXPORTING  iv_limit = 9
    IMPORTING  ev_text  = lv_text
    EXCEPTIONS too_big  = 4 ).
  IF lv_text IS INITIAL.
    lv_text = `<initial>`.
  ENDIF.
  WRITE: / '  VALUE(ev_text)  ->', lv_text.

  CLEAR lv_text.
  lcl_fm=>build_by_ref(
    EXPORTING  iv_limit = 9
    IMPORTING  ev_text  = lv_text
    EXCEPTIONS too_big  = 4 ).
  IF lv_text IS INITIAL.
    lv_text = `<initial>`.
  ENDIF.
  WRITE: / '  ev_text (by ref)->', lv_text,
           '<- the failed call already wrote this'.

*&---------------------------------------------------------------------*
*& 3. A real function module, and the same = 0 swallow
*&---------------------------------------------------------------------*
  SKIP.
  WRITE: / '=== 3. DATE_CHECK_PLAUSIBILITY (real FM, read-only)'.

  CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
    EXPORTING
      date                      = lv_good
    EXCEPTIONS
      plausibility_check_failed = 1
      OTHERS                    = 2.
  lv_subrc = sy-subrc.
  WRITE: / '  20261124 (valid)   -> sy-subrc', lv_subrc.

  CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
    EXPORTING
      date                      = lv_bad
    EXCEPTIONS
      plausibility_check_failed = 1
      OTHERS                    = 2.
  lv_subrc = sy-subrc.
  WRITE: / '  20260231 (invalid) -> sy-subrc', lv_subrc.

  " The swallow, on a real function module this time.
  CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
    EXPORTING
      date                      = lv_bad
    EXCEPTIONS
      plausibility_check_failed = 0
      OTHERS                    = 0.
  lv_subrc = sy-subrc.
  WRITE: / '  20260231 with = 0  -> sy-subrc', lv_subrc,
           '<- rejected date, clean return code'.

*&---------------------------------------------------------------------*
*& 4. A mistyped exception name is not checked at runtime
*&---------------------------------------------------------------------*
  SKIP.
  WRITE: / '=== 4. Misspelled exception name falls through to OTHERS'.

  " plausibility_check_faild does not exist in the interface. The
  " documentation: "During program execution, a specified exception is
  " not checked when a function module is called. Only the extended
  " program check reports whether a specified exception is not declared
  " in its interface." So nothing complains here - but the real
  " exception is no longer matched by name and lands in OTHERS.
  CALL FUNCTION 'DATE_CHECK_PLAUSIBILITY'
    EXPORTING
      date                       = lv_bad
    EXCEPTIONS
      plausibility_check_faild   = 1
      OTHERS                     = 9.
  lv_subrc = sy-subrc.
  WRITE: / '  mistyped name      -> sy-subrc', lv_subrc,
           '<- 9, not 1. Nothing reported the typo.'.

*&---------------------------------------------------------------------*
*& 5. A variable function module name stops checking parameters too
*&---------------------------------------------------------------------*
  SKIP.
  WRITE: / '=== 5. Dynamic name: nonexistent parameter is ignored'.

  lv_fm_name = 'DATE_CHECK_PLAUSIBILITY'.
  lv_dummy   = 1.

  " no_such_param is not in the interface. With a literal function
  " module name this raises a catchable exception; with the name in a
  " variable the documentation says "the specification of an incorrect
  " formal parameter is ignored at runtime". Wrapped in TRY anyway, so
  " a system that disagrees reports instead of dumping.
  TRY.
      CALL FUNCTION lv_fm_name
        EXPORTING
          date                      = lv_bad
          no_such_param             = lv_dummy
        EXCEPTIONS
          plausibility_check_failed = 1
          OTHERS                    = 2.
      lv_subrc = sy-subrc.
      WRITE: / '  bogus parameter    -> sy-subrc', lv_subrc,
               '<- call went through, parameter ignored'.
    CATCH cx_root INTO lx_root.
      lv_err = lx_root->get_text( ).
      WRITE: / '  bogus parameter    -> exception:', lv_err.
  ENDTRY.

*&---------------------------------------------------------------------*
*& 6. RAISE carries no text. MESSAGE RAISING does.
*&
*& This section is deliberately LAST, because it depends on sy-msgid and
*& friends still holding what section 5 left in them. A plain RAISE does
*& not touch the message fields - it does not clear them either - so the
*& residue of the PREVIOUS failure is still readable after it. That is
*& the whole hazard: code that reads sy-msgid after a failed call cannot
*& tell a fresh message from a stale one.
*&---------------------------------------------------------------------*
  SKIP.
  WRITE: / '=== 6. The message fields are not reset by RAISE'.

  " Whatever the real function module in section 5 left behind.
  lv_msgid = sy-msgid.
  lv_msgno = sy-msgno.
  lv_msgty = sy-msgty.
  WRITE: / '  before the RAISE   -> msgid', lv_msgid,
           'msgno', lv_msgno, 'msgty', lv_msgty.

  " A plain RAISE, which raises no message at all.
  lcl_fm=>build_by_value(
    EXPORTING  iv_limit = 9
    IMPORTING  ev_text  = lv_text
    EXCEPTIONS too_big  = 4 ).
  lv_subrc = sy-subrc.
  lv_msgid = sy-msgid.
  lv_msgno = sy-msgno.
  lv_msgty = sy-msgty.
  WRITE: / '  after  the RAISE   -> msgid', lv_msgid,
           'msgno', lv_msgno, 'msgty', lv_msgty.
  WRITE: / '  sy-subrc is', lv_subrc,
           'but the message fields are byte-for-byte unchanged.'.
  WRITE: / '  A function module that used MESSAGE RAISING instead would',
           'have overwritten them - that is the only difference the'.
  WRITE: / '  caller can observe, and it is why MESSAGE RAISING is the',
           'variant the documentation prefers: it carries a text.'.
