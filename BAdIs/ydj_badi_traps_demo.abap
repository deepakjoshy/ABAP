*&---------------------------------------------------------------------*
*& Report YDJ_BADI_TRAPS_DEMO
*&---------------------------------------------------------------------*
*& "What would GET BADI actually give me here?" -- a read-only inspector
*& for the documented BAdI behaviours that are invisible in calling code.
*&
*&   1. IMPL COUNT     -> CALL BADI on a MULTIPLE-USE BAdI with zero
*&                        implementations HAS NO EFFECT: no exception,
*&                        sy-subrc = 0, CHANGING parameters unchanged.
*&                        The only way to know is
*&                        CL_BADI_QUERY=>NUMBER_OF_IMPLEMENTATIONS.
*&   2. STALE REF      -> a FAILING GET BADI RETAINS the previous valid
*&                        reference ("If the BAdI reference variable badi
*&                        contained a valid BAdI reference before the
*&                        statement in an exception case, this is
*&                        retained"). IS BOUND stays true, so a CALL BADI
*&                        after a caught exception runs the PREVIOUS
*&                        filter's implementation. Proven live below.
*&   3. EXCEPTION MAP  -> which exception means what, and that they are
*&                        all raised at GET BADI, never at CALL BADI.
*&   4. FILTER-TABLE   -> the dynamic form needs BADI_FILTER_BINDINGS
*&                        with EXACTLY ONE line per filter, NAME in
*&                        UPPERCASE. A nonexistent filter NAME is an
*&                        UNCATCHABLE exception (so never build it from
*&                        user input) -- everything else is catchable.
*&
*& Read-only: no database access, and NO CALL BADI is ever executed (the
*& call forms are shown as comments only, since dynamically calling an
*& unknown BAdI method could do anything). GET BADI itself only builds
*& object plug-ins in the current internal session.
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPGET_BADI.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCALL_BADI.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMETHODS_DEFAULT.html
*&---------------------------------------------------------------------*
REPORT ydj_badi_traps_demo.

PARAMETERS: p_badi  TYPE c LENGTH 30 DEFAULT 'BADI_SORTER' OBLIGATORY,
            p_filtn TYPE c LENGTH 30 DEFAULT 'BADI_NAME',
            p_filtv TYPE c LENGTH 30.

*&---------------------------------------------------------------------*
CLASS lcl_badi_probe DEFINITION FINAL.

  PUBLIC SECTION.
    CLASS-METHODS main
      IMPORTING iv_badi         TYPE csequence
                iv_filter_name  TYPE csequence
                iv_filter_value TYPE csequence.

  PRIVATE SECTION.
    " Builds the BADI_FILTER_BINDINGS table for the dynamic GET BADI.
    " NAME must be UPPERCASE; VALUE is a reference to the value object.
    CLASS-METHODS build_filters
      IMPORTING iv_name        TYPE csequence
                iv_value       TYPE csequence
      RETURNING VALUE(rt_ftab) TYPE badi_filter_bindings.

    " One GET BADI attempt, every documented exception mapped to text.
    " No RETURNING here: a method with a RETURNING parameter must not
    " have EXPORTING or CHANGING parameters, and co_badi has to be
    " CHANGING to show the retained-reference behaviour.
    CLASS-METHODS try_get_badi
      IMPORTING iv_badi TYPE csequence
                it_ftab TYPE badi_filter_bindings
      EXPORTING ev_msg  TYPE string
      CHANGING  co_badi TYPE REF TO cl_badi_base.

    CLASS-DATA gv_filter_value TYPE c LENGTH 30.

ENDCLASS.

CLASS lcl_badi_probe IMPLEMENTATION.

  METHOD build_filters.

    IF iv_name IS INITIAL.
      RETURN.                                  " BAdI without filters
    ENDIF.

    " The value object must OUTLIVE the table (VALUE is a pointer), so it
    " is a CLASS-DATA attribute, not a local variable.
    gv_filter_value = iv_value.

    DATA ls_line TYPE LINE OF badi_filter_bindings.
    ls_line-name = to_upper( iv_name ).
    GET REFERENCE OF gv_filter_value INTO ls_line-value.
    INSERT ls_line INTO TABLE rt_ftab.

  ENDMETHOD.

  METHOD try_get_badi.

    DATA lv_name TYPE c LENGTH 30.
    lv_name = to_upper( iv_badi ).

    TRY.
        IF it_ftab IS INITIAL.
          GET BADI co_badi TYPE lv_name.
        ELSE.
          GET BADI co_badi TYPE lv_name FILTER-TABLE it_ftab.
        ENDIF.
        ev_msg = |OK - BAdI object created|.

      CATCH cx_badi_not_implemented.
        " single-use BAdI, hit list empty. THE case a fallback
        " implementation class is meant to prevent.
        ev_msg = |CX_BADI_NOT_IMPLEMENTED - single use, no implementation|.

      CATCH cx_badi_multiply_implemented.
        " single-use BAdI, overlapping filters, no priority resolution.
        ev_msg = |CX_BADI_MULTIPLY_IMPLEMENTED - single use, several found|.

      CATCH cx_badi_filter_error.
        " wrong number of filter lines, or a value of an incompatible type
        ev_msg = |CX_BADI_FILTER_ERROR - filter specification does not fit|.

      CATCH cx_badi_context_error.
        ev_msg = |CX_BADI_CONTEXT_ERROR - context-dependent BAdI, bad CONTEXT|.

      CATCH cx_badi_initial_context.
        ev_msg = |CX_BADI_INITIAL_CONTEXT - reference after CONTEXT is initial|.

      CATCH cx_badi_unknown_error.
        ev_msg = |CX_BADI_UNKNOWN_ERROR - no such BAdI|.

      CATCH cx_root INTO DATA(lo_err).
        DATA(lv_text) = lo_err->get_text( ).
        ev_msg = |other: { lv_text }|.
    ENDTRY.

  ENDMETHOD.

  METHOD main.

    DATA: lo_badi   TYPE REF TO cl_badi_base,
          lv_bound  TYPE abap_bool,
          lv_impls  TYPE i,
          lv_msg    TYPE string,
          lv_msg2   TYPE string,
          lv_fcount TYPE i.

    DATA(lt_ftab) = build_filters( iv_name  = iv_filter_name
                                   iv_value = iv_filter_value ).

    " ---- 1. what does GET BADI give us, and how many plug-ins? --------
    WRITE: / '=== 1. GET BADI and the implementation count ==='.

    try_get_badi( EXPORTING iv_badi = iv_badi
                            it_ftab = lt_ftab
                  IMPORTING ev_msg  = lv_msg
                  CHANGING  co_badi = lo_badi ).

    " Functional calls hoisted out of the WRITE lists on purpose.
    DATA(lv_badi_up) = to_upper( iv_badi ).
    lv_fcount = lines( lt_ftab ).

    WRITE: / 'BAdI      :', lv_badi_up,
           / 'filters   :', lv_fcount LEFT-JUSTIFIED,
           / 'result    :', lv_msg.

    IF lo_badi IS BOUND.
      " Static method, IMPORTING badi TYPE REF TO cl_badi_base,
      " RETURNING num TYPE i. Every BAdI class inherits CL_BADI_BASE,
      " so a statically typed BAdI reference can be passed directly.
      lv_impls = cl_badi_query=>number_of_implementations( badi = lo_badi ).
      WRITE: / 'plug-ins  :', lv_impls LEFT-JUSTIFIED.

      IF lv_impls = 0.
        WRITE: / '          -> a MULTIPLE-USE BAdI with 0 plug-ins is legal.',
               / '             CALL BADI would DO NOTHING here:',
               / '             no exception, sy-subrc = 0, CHANGING data unchanged.'.
      ENDIF.
    ELSE.
      WRITE: / 'plug-ins  : (no BAdI object)'.
    ENDIF.

    " The call itself, deliberately NOT executed:
    " CALL BADI lo_badi->('SOME_METHOD') CHANGING cs_data = ls_data.
    "   - method name must be UPPERCASE in the dynamic form
    "   - single use   + initial reference -> CX_BADI_INITIAL_REFERENCE
    "   - multiple use + initial reference -> no effect, silently
    "   - a method added to the interface AFTER an implementation was
    "     written behaves as an EMPTY body: pass-by-value EXPORTING and
    "     RETURNING actuals are INITIALIZED, everything else unchanged.
    "     Define such methods with DEFAULT FAIL to make that loud.

    " ---- 2. the retained-reference trap, proven live ------------------
    WRITE: / ' ',
           / '=== 2. A FAILING GET BADI keeps the PREVIOUS reference ==='.

    " xsdbool, not boolc: boolc returns a string whose blank is dropped,
    " so boolc( ) = abap_false is FALSE. See Character Comparisons.
    lv_bound = xsdbool( lo_badi IS BOUND ).
    WRITE: / 'before    : IS BOUND =', lv_bound.

    IF lv_bound = abap_false.
      WRITE: / '          -> first GET BADI did not succeed, so there is no',
             / '             valid reference to retain. Re-run with a BAdI',
             / '             that exists in this system to see the trap.'.
    ELSE.
      " Same variable, now a BAdI name that cannot exist.
      try_get_badi( EXPORTING iv_badi = 'YDJ_NO_SUCH_BADI_AT_ALL'
                              it_ftab = VALUE badi_filter_bindings( )
                    IMPORTING ev_msg  = lv_msg2
                    CHANGING  co_badi = lo_badi ).

      lv_bound = xsdbool( lo_badi IS BOUND ).
      WRITE: / 'GET BADI  :', lv_msg2,
             / 'after     : IS BOUND =', lv_bound.

      IF lv_bound = abap_true.
        WRITE: / '          -> STILL BOUND, and still pointing at', lv_badi_up,
               / '             A CALL BADI after a caught exception would run the',
               / '             PREVIOUS iteration''s implementation. IS BOUND is',
               / '             NOT a valid guard -- CLEAR the reference in the',
               / '             CATCH block, exactly like UNASSIGN after a failed',
               / '             READ TABLE ... ASSIGNING.'.
      ENDIF.
    ENDIF.

    " ---- 3. the selection cascade, as documented ----------------------
    WRITE: / ' ',
           / '=== 3. How GET BADI picks implementations ==='.
    WRITE: / '  1) implementation must be ACTIVE',
           / '  2) its enhancement''s SWITCH must be ON (no switch = on).',
           / '     An active implementation behind an off switch is SKIPPED.',
           / '  3) filter condition must match ... and if NOTHING matches,',
           / '     the framework falls back to implementations marked as',
           / '     STANDARD, then to the BAdI''s FALLBACK class. So a wrong',
           / '     filter value runs the WRONG implementation rather than',
           / '     raising CX_BADI_NOT_IMPLEMENTED.',
           / '  4) single use + several hits -> conflict resolution; equal',
           / '     priorities means it gives up and the exception fires.'.

    WRITE: / ' ',
           / 'Plug-in lifetime: whether GET BADI creates a NEW plug-in or',
           / 'reuses a per-internal-session SINGLETON is a property of the',
           / 'BAdI DEFINITION, not of your code. Write implementation',
           / 'classes as if the instance were reused: per-call data in',
           / 'local variables, never in instance attributes.'.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
START-OF-SELECTION.

  lcl_badi_probe=>main( iv_badi         = p_badi
                        iv_filter_name  = p_filtn
                        iv_filter_value = p_filtv ).
