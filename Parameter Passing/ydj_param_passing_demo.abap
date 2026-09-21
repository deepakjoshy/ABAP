*&---------------------------------------------------------------------*
*& Report YDJ_PARAM_PASSING_DEMO
*&---------------------------------------------------------------------*
*& Pass by reference vs pass by value - the default nobody writes down.
*& Omitting VALUE( ) means REFERENCE( ), and the behaviour of the
*& parameter changes with it. None of the following is a syntax error.
*&
*& Trap numbering matches README.md in this folder.
*&
*&   1. EXPORTING BY REF IS   -> an EXPORTING parameter passed by reference
*&      NOT INITIALIZED          is NOT cleared on entry. It arrives holding
*&                               the CALLER's current value, so a method that
*&                               "leaves it alone when nothing is found"
*&                               returns the PREVIOUS record's answer.
*&   1b. THE TABLE FLAVOUR    -> same cause: a bare APPEND adds to the rows
*&                               left by the previous call, so call n
*&                               returns n * rows.
*&   2. WRITES SURVIVE AN     -> by reference the method writes the CALLER's
*&      EXCEPTION                variable directly, so a half-built value
*&                               stays put even when the method exits via
*&                               RAISE EXCEPTION. By value it does not.
*&   3. ALIASING              -> passing an ATTRIBUTE by reference makes it
*&                               reachable under TWO names at once; the
*&                               method's own reads of mv_attr see its own
*&                               writes to cv_value.
*&   4. sy-index AS AN ACTUAL -> a system field passed by reference keeps
*&      PARAMETER                MOVING inside the method. A DO loop in the
*&                               callee silently rewrites the caller's value.
*&   5. (see README)          -> IMPORTING by reference is write-protected,
*&                               IMPORTING VALUE( ) is not. A compile-time
*&                               distinction, so there is nothing to run.
*&   6. IS SUPPLIED           -> with DEFAULT, IS INITIAL cannot tell "not
*&      vs IS INITIAL            passed" from "passed the default value".
*&
*& Self-contained: local classes and literals only, no DDIC, no database.
*&---------------------------------------------------------------------*
REPORT ydj_param_passing_demo.

*&---------------------------------------------------------------------*
*& A dynamic-check exception, so it can be raised in a method that
*& declares it with RAISING without any DDIC dependency.
*&---------------------------------------------------------------------*
CLASS lcx_demo DEFINITION INHERITING FROM cx_dynamic_check.
ENDCLASS.

CLASS lcl_traps DEFINITION.

  PUBLIC SECTION.
    TYPES ty_names TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    METHODS main.

    " Trap 1 - the same body, once by reference and once by value.
    METHODS fill_by_ref
      IMPORTING iv_found TYPE abap_bool
      EXPORTING ev_text  TYPE string.
    METHODS fill_by_val
      IMPORTING iv_found       TYPE abap_bool
      EXPORTING VALUE(ev_text) TYPE string.

    " Trap 1b - appends, never clears.
    METHODS append_rows
      EXPORTING et_names TYPE ty_names.

    " Trap 2 - writes, then fails.
    METHODS build_by_ref
      EXPORTING ev_out TYPE string
      RAISING   lcx_demo.
    METHODS build_by_val
      EXPORTING VALUE(ev_out) TYPE string
      RAISING   lcx_demo.

    " Trap 6 - optional parameter with a replacement value.
    METHODS supplied_check
      IMPORTING iv_flag        TYPE i DEFAULT 0
      RETURNING VALUE(rv_text) TYPE string.

  PRIVATE SECTION.
    DATA mv_attr TYPE p LENGTH 8 DECIMALS 2.

    " Trap 3 - the doc's own aliasing example.
    METHODS alias_by_ref CHANGING cv_value        TYPE numeric.
    METHODS alias_by_val CHANGING VALUE(cv_value) TYPE numeric.

    " Trap 4 - reads its input parameter three times.
    METHODS watch_index
      IMPORTING iv_index       TYPE i
      RETURNING VALUE(rv_seen) TYPE string.

ENDCLASS.

CLASS lcl_traps IMPLEMENTATION.

*&---------------------------------------------------------------------*
*& Trap 1 - "nothing found, so I leave the output alone"
*&---------------------------------------------------------------------*
  METHOD fill_by_ref.
    IF iv_found = abap_true.
      ev_text = `row found`.
    ENDIF.
  ENDMETHOD.

  METHOD fill_by_val.
    IF iv_found = abap_true.
      ev_text = `row found`.
    ENDIF.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Trap 1b - the table equivalent. The fix is a CLEAR et_names. first.
*&---------------------------------------------------------------------*
  METHOD append_rows.
    APPEND `ALPHA` TO et_names.
    APPEND `BETA`  TO et_names.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Trap 2 - a partially built value that outlives the exception
*&---------------------------------------------------------------------*
  METHOD build_by_ref.
    ev_out = `HALF-BUILT`.
    RAISE EXCEPTION TYPE lcx_demo.
  ENDMETHOD.

  METHOD build_by_val.
    ev_out = `HALF-BUILT`.
    RAISE EXCEPTION TYPE lcx_demo.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Trap 3 - cv_value and mv_attr are the SAME data object here, so the
*& second statement reads back what the first statement just wrote.
*&---------------------------------------------------------------------*
  METHOD alias_by_ref.
    cv_value = 1.
    cv_value = mv_attr + 1.
  ENDMETHOD.

  METHOD alias_by_val.
    cv_value = 1.
    cv_value = mv_attr + 1.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Trap 4 - iv_index is read-only here, but it is not CONSTANT: it is a
*& window onto whatever the caller passed, and sy-index keeps changing.
*&---------------------------------------------------------------------*
  METHOD watch_index.
    DO 3 TIMES.
      rv_seen = |{ rv_seen } { iv_index }|.
    ENDDO.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Trap 6 - IS SUPPLIED asks a different question than IS INITIAL
*&---------------------------------------------------------------------*
  METHOD supplied_check.
    DATA lv_sup TYPE string.
    DATA lv_ini TYPE string.

    IF iv_flag IS SUPPLIED.
      lv_sup = `SUPPLIED`.
    ELSE.
      lv_sup = `not supplied`.
    ENDIF.

    IF iv_flag IS INITIAL.
      lv_ini = `INITIAL`.
    ELSE.
      lv_ini = `not initial`.
    ENDIF.

    rv_text = |{ lv_sup } / { lv_ini }|.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Driver
*&---------------------------------------------------------------------*
  METHOD main.

    DATA lv_text     TYPE string.
    DATA lt_names    TYPE ty_names.
    DATA lv_rows     TYPE i.
    DATA lv_ref_out  TYPE string.
    DATA lv_val_out  TYPE string.
    DATA lv_after_r  TYPE string.
    DATA lv_after_v  TYPE string.
    DATA lv_seen_sy  TYPE string.
    DATA lv_seen_var TYPE string.
    DATA lv_helper   TYPE i.
    DATA lv_none     TYPE string.
    DATA lv_zero     TYPE string.

    " -- Trap 1 ------------------------------------------------------
    CLEAR lv_text.
    fill_by_ref( EXPORTING iv_found = abap_true
                 IMPORTING ev_text  = lv_text ).
    WRITE: / 'Trap 1 by reference, call 1 (found)   :', lv_text.

    fill_by_ref( EXPORTING iv_found = abap_false
                 IMPORTING ev_text  = lv_text ).
    WRITE: / 'Trap 1 by reference, call 2 (NOT found):', lv_text.
    WRITE: / '        ^ stale answer from call 1, sy-subrc says nothing'.

    CLEAR lv_text.
    fill_by_val( EXPORTING iv_found = abap_true
                 IMPORTING ev_text  = lv_text ).
    fill_by_val( EXPORTING iv_found = abap_false
                 IMPORTING ev_text  = lv_text ).
    WRITE: / 'Trap 1 by value, call 2 (NOT found)   :', lv_text.
    SKIP.

    " -- Trap 1b ------------------------------------------------------
    append_rows( IMPORTING et_names = lt_names ).
    lv_rows = lines( lt_names ).
    WRITE: / 'Trap 1b rows after call 1             :', lv_rows.

    append_rows( IMPORTING et_names = lt_names ).
    lv_rows = lines( lt_names ).
    WRITE: / 'Trap 1b rows after call 2             :', lv_rows.
    WRITE: / '        ^ expected 2, got 4 - no CLEAR on entry'.
    SKIP.

    " -- Trap 2 ------------------------------------------------------
    TRY.
        build_by_ref( IMPORTING ev_out = lv_ref_out ).
      CATCH lcx_demo.
    ENDTRY.
    WRITE: / 'Trap 2 by reference after exception   :', lv_ref_out.

    TRY.
        build_by_val( IMPORTING ev_out = lv_val_out ).
      CATCH lcx_demo.
    ENDTRY.
    WRITE: / 'Trap 2 by value after exception       :', lv_val_out.
    WRITE: / '        ^ by value nothing is handed back on an early exit'.
    SKIP.

    " -- Trap 3 ------------------------------------------------------
    mv_attr = '1.23'.
    alias_by_ref( CHANGING cv_value = mv_attr ).
    lv_after_r = |{ mv_attr }|.

    mv_attr = '1.23'.
    alias_by_val( CHANGING cv_value = mv_attr ).
    lv_after_v = |{ mv_attr }|.

    WRITE: / 'Trap 3 attribute by reference         :', lv_after_r.
    WRITE: / 'Trap 3 attribute by value             :', lv_after_v.
    WRITE: / '        ^ same method body, two answers'.
    SKIP.

    " -- Trap 4 ------------------------------------------------------
    DO 1 TIMES.
      lv_seen_sy = watch_index( sy-index ).
    ENDDO.

    lv_helper   = 1.
    lv_seen_var = watch_index( lv_helper ).

    WRITE: / 'Trap 4 watch_index( sy-index )        :', lv_seen_sy.
    WRITE: / 'Trap 4 watch_index( lv_helper )       :', lv_seen_var.
    WRITE: / '        ^ the system field moves under the callee'.
    SKIP.

    " -- Trap 6 ------------------------------------------------------
    lv_none = supplied_check( ).
    lv_zero = supplied_check( 0 ).
    WRITE: / 'Trap 6 supplied_check( )              :', lv_none.
    WRITE: / 'Trap 6 supplied_check( 0 )            :', lv_zero.
    WRITE: / '        ^ IS INITIAL cannot tell these two apart'.

  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  DATA go_demo TYPE REF TO lcl_traps.
  CREATE OBJECT go_demo.
  go_demo->main( ).
