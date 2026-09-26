*&---------------------------------------------------------------------*
*& Report YDJ_DYNAMIC_CALL_DEMO
*&---------------------------------------------------------------------*
*& CALL METHOD (class)=>(meth) with PARAMETER-TABLE -- the dynamic
*& invoke. PARAMETER-TABLE already appears in this repo, in
*& ABAPConstructorExpressions.abap, as a bare snippet with no
*& explanation of what it costs you.
*&
*& What it costs you is the syntax check. Every mistake below is a
*& RUNTIME exception, at the call, in whatever branch finally reaches
*& it -- not an activation error.
*&
*& Trap numbering matches README.md in this folder.
*&
*&   1. THE SYNTAX CHECK IS     -> a dynamic call names nothing the
*&      GONE                       compiler can see. Where-used finds
*&                                 nothing, the method looks dead, and
*&                                 renaming a parameter breaks a caller
*&                                 that still activates cleanly.
*&   2. VALUE IS A REFERENCE,   -> ptab-value is REF TO data and the
*&      NOT A VALUE                reference is resolved AT THE CALL.
*&                                 Building ptab in a loop and reusing
*&                                 one work area binds every row to the
*&                                 SAME data object -- last value wins.
*&   3. KIND IS OPTIONAL AND    -> if KIND is left initial the interface
*&      THAT IS THE PROBLEM        direction is NOT checked. An IMPORTING
*&                                 parameter bound as if it were
*&                                 EXPORTING passes silently.
*&   4. IMPORTING NEEDS A       -> the caller must supply a data object
*&      TARGET THAT SURVIVES       for every result it wants back. A
*&                                 REF #( ) over a local that has gone
*&                                 out of scope is not caught for you.
*&   5. EXCEPTION-TABLE IS FOR  -> etab maps NON-class-based exceptions
*&      THE OLD KIND ONLY          to sy-subrc. Class-based exceptions
*&                                 ignore it entirely and still need
*&                                 TRY/CATCH around the CALL METHOD.
*&   6. sy-subrc = 0 MEANS      -> "each method call sets sy-subrc to 0
*&      "CALLED", NOT "WORKED"     in the moment the method is called".
*&                                 Only an etab entry can change it.
*&   7. THE NAME MUST BE        -> names are compared in UPPER CASE.
*&      UPPER CASE                 A lower-case method name raises
*&                                 CX_SY_DYN_CALL_ILLEGAL_METHOD even
*&                                 though the method exists.
*&   8. A NAME FROM OUTSIDE IS  -> SAP's own security note: the only
*&      AN ARBITRARY-CODE HOLE     fix is an include list, via
*&                                 CL_ABAP_DYN_PRG. Not a pattern check.
*&
*& Self-contained: local classes and literals only. No DDIC objects,
*& no database access, no COMMIT.
*&---------------------------------------------------------------------*
REPORT ydj_dynamic_call_demo.

*&---------------------------------------------------------------------*
*& The target class. Deliberately boring -- the interesting part is
*& always the CALL, never the callee.
*&
*& Note lcl_target is a LOCAL class. A dynamic call can reach it by
*& name from inside this same compilation unit; reaching a local class
*& of ANOTHER program needs the absolute type name and is explicitly
*& discouraged by the docs.
*&---------------------------------------------------------------------*

" A class that declares no methods needs no implementation part at all:
" "A class that does not have to implement any methods because of its
" declaration part either has an empty implementation part or none at
" all." -- CLASS, IMPLEMENTATION.
CLASS lcx_bad_input DEFINITION INHERITING FROM cx_static_check.
ENDCLASS.

CLASS lcl_target DEFINITION.
  PUBLIC SECTION.
    " Classic (non-class-based) exception -- this is the kind
    " EXCEPTION-TABLE can map. See trap 5.
    CLASS-METHODS convert
      IMPORTING iv_in     TYPE string
      EXPORTING ev_out    TYPE string
      EXCEPTIONS not_text.

    " Class-based exception -- EXCEPTION-TABLE cannot touch this one.
    CLASS-METHODS strict_convert
      IMPORTING iv_in         TYPE string
      RETURNING VALUE(rv_out) TYPE string
      RAISING   lcx_bad_input.

    CLASS-METHODS add
      IMPORTING iv_a          TYPE i
                iv_b          TYPE i
      RETURNING VALUE(rv_sum) TYPE i.
ENDCLASS.

CLASS lcl_target IMPLEMENTATION.
  METHOD convert.
    IF iv_in IS INITIAL.
      RAISE not_text.
    ENDIF.
    ev_out = to_upper( iv_in ).
  ENDMETHOD.

  METHOD strict_convert.
    IF iv_in IS INITIAL.
      RAISE EXCEPTION TYPE lcx_bad_input.
    ENDIF.
    rv_out = to_upper( iv_in ).
  ENDMETHOD.

  METHOD add.
    rv_sum = iv_a + iv_b.
  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
*& Helper: turn any CX_SY_DYN_CALL_ERROR subclass into one line, so the
*& demo can show WHICH exception each mistake produces rather than just
*& "it dumped".
*&---------------------------------------------------------------------*
CLASS lcl_demo DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    CLASS-METHODS trap_2_shared_work_area.
    CLASS-METHODS trap_3_kind_unchecked.
    CLASS-METHODS trap_5_exception_table.
    CLASS-METHODS trap_7_case_sensitivity.
    CLASS-METHODS trap_8_include_list.
ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

  METHOD run.
    WRITE: / '=== Dynamic method calls -- what the syntax check no longer does ==='.
    SKIP.
    trap_2_shared_work_area( ).
    SKIP.
    trap_3_kind_unchecked( ).
    SKIP.
    trap_5_exception_table( ).
    SKIP.
    trap_7_case_sensitivity( ).
    SKIP.
    trap_8_include_list( ).
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& TRAP 2 -- VALUE is REF TO data, resolved at the CALL.
*&
*& The wrong version builds two rows from one reused work area. Both
*& rows hold REF #( lv_arg ), i.e. the SAME address, so by the time
*& CALL METHOD runs, both parameters read whatever lv_arg holds LAST.
*& The right version gives each row its own data object.
*&---------------------------------------------------------------------*
  METHOD trap_2_shared_work_area.
    DATA lv_arg  TYPE i.
    DATA lv_sum  TYPE i.
    DATA lt_ptab TYPE abap_parmbind_tab.

    WRITE: / 'Trap 2 -- one work area, two rows, one address'.

    " WRONG: lv_arg is a single data object. REF #( lv_arg ) twice is
    " the same reference twice, no matter what lv_arg held in between.
    lv_arg = 2.
    INSERT VALUE abap_parmbind( name  = 'IV_A'
                                kind  = cl_abap_objectdescr=>exporting
                                value = REF #( lv_arg ) ) INTO TABLE lt_ptab.
    lv_arg = 40.
    INSERT VALUE abap_parmbind( name  = 'IV_B'
                                kind  = cl_abap_objectdescr=>exporting
                                value = REF #( lv_arg ) ) INTO TABLE lt_ptab.
    INSERT VALUE abap_parmbind( name  = 'RV_SUM'
                                kind  = cl_abap_objectdescr=>receiving
                                value = REF #( lv_sum ) ) INTO TABLE lt_ptab.

    TRY.
        CALL METHOD ('LCL_TARGET')=>('ADD') PARAMETER-TABLE lt_ptab.
        " Expect 80, not 42: both IV_A and IV_B read lv_arg = 40.
        WRITE: / '  shared work area   2 + 40 =', lv_sum LEFT-JUSTIFIED.
      CATCH cx_sy_dyn_call_error INTO DATA(lo_err_a).
        DATA(lv_txt_a) = lo_err_a->get_text( ).
        WRITE: / '  unexpected:', lv_txt_a.
    ENDTRY.

    " RIGHT: two distinct data objects, so two distinct references.
    CLEAR lt_ptab.
    CLEAR lv_sum.
    DATA lv_a TYPE i VALUE 2.
    DATA lv_b TYPE i VALUE 40.
    INSERT VALUE abap_parmbind( name  = 'IV_A'
                                kind  = cl_abap_objectdescr=>exporting
                                value = REF #( lv_a ) ) INTO TABLE lt_ptab.
    INSERT VALUE abap_parmbind( name  = 'IV_B'
                                kind  = cl_abap_objectdescr=>exporting
                                value = REF #( lv_b ) ) INTO TABLE lt_ptab.
    INSERT VALUE abap_parmbind( name  = 'RV_SUM'
                                kind  = cl_abap_objectdescr=>receiving
                                value = REF #( lv_sum ) ) INTO TABLE lt_ptab.

    TRY.
        CALL METHOD ('LCL_TARGET')=>('ADD') PARAMETER-TABLE lt_ptab.
        WRITE: / '  separate objects   2 + 40 =', lv_sum LEFT-JUSTIFIED.
      CATCH cx_sy_dyn_call_error INTO DATA(lo_err_b).
        DATA(lv_txt_b) = lo_err_b->get_text( ).
        WRITE: / '  unexpected:', lv_txt_b.
    ENDTRY.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& TRAP 3 -- KIND initial means NO interface check.
*&
*& Docs: "This column is used to verify the interface. [...] If KIND is
*& initial, no check is performed." So omitting KIND does not mean
*& "figure it out" -- it means "do not look".
*&---------------------------------------------------------------------*
  METHOD trap_3_kind_unchecked.
    DATA lv_in   TYPE string VALUE `hello`.
    DATA lv_out  TYPE string.
    DATA lt_ptab TYPE abap_parmbind_tab.

    WRITE: / 'Trap 3 -- KIND initial disables the direction check'.

    " KIND deliberately left initial on both rows. The call still works
    " here, which is exactly why this is dangerous: it also "works"
    " when the direction is genuinely wrong, until the data is wrong.
    INSERT VALUE abap_parmbind( name  = 'IV_IN'
                                value = REF #( lv_in ) ) INTO TABLE lt_ptab.
    INSERT VALUE abap_parmbind( name  = 'EV_OUT'
                                value = REF #( lv_out ) ) INTO TABLE lt_ptab.

    TRY.
        CALL METHOD ('LCL_TARGET')=>('CONVERT') PARAMETER-TABLE lt_ptab.
        WRITE: / '  no KIND given, call accepted. EV_OUT =', lv_out.
      CATCH cx_sy_dyn_call_error INTO DATA(lo_err_c).
        DATA(lv_txt_c) = lo_err_c->get_text( ).
        WRITE: / '  raised:', lv_txt_c.
    ENDTRY.

    " Now the SAME call with a deliberately wrong KIND. EV_OUT is an
    " EXPORTING parameter of the method, i.e. IMPORTING from the
    " caller's side. Claiming EXPORTING raises the type exception --
    " which is the point: filling KIND in is what buys you the check.
    CLEAR lt_ptab.
    INSERT VALUE abap_parmbind( name  = 'IV_IN'
                                kind  = cl_abap_objectdescr=>exporting
                                value = REF #( lv_in ) ) INTO TABLE lt_ptab.
    INSERT VALUE abap_parmbind( name  = 'EV_OUT'
                                kind  = cl_abap_objectdescr=>exporting
                                value = REF #( lv_out ) ) INTO TABLE lt_ptab.

    TRY.
        CALL METHOD ('LCL_TARGET')=>('CONVERT') PARAMETER-TABLE lt_ptab.
        WRITE: / '  wrong KIND was NOT rejected'.
      CATCH cx_sy_dyn_call_illegal_type INTO DATA(lo_err_d).
        DATA(lv_txt_d) = lo_err_d->get_text( ).
        WRITE: / '  wrong KIND rejected:', lv_txt_d.
    ENDTRY.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& TRAP 5 + 6 -- EXCEPTION-TABLE covers only the classic kind, and
*& sy-subrc is otherwise always 0.
*&---------------------------------------------------------------------*
  METHOD trap_5_exception_table.
    DATA lv_in   TYPE string.        " initial on purpose -> raises
    DATA lv_out  TYPE string.
    DATA lt_ptab TYPE abap_parmbind_tab.
    DATA lt_etab TYPE abap_excpbind_tab.

    WRITE: / 'Trap 5/6 -- EXCEPTION-TABLE is for classic exceptions only'.

    INSERT VALUE abap_parmbind( name  = 'IV_IN'
                                kind  = cl_abap_objectdescr=>exporting
                                value = REF #( lv_in ) ) INTO TABLE lt_ptab.
    INSERT VALUE abap_parmbind( name  = 'EV_OUT'
                                kind  = cl_abap_objectdescr=>importing
                                value = REF #( lv_out ) ) INTO TABLE lt_ptab.

    " NAME may be a specific exception or OTHERS, always upper case.
    INSERT VALUE abap_excpbind( name = 'NOT_TEXT' value = 4 ) INTO TABLE lt_etab.

    TRY.
        CALL METHOD ('LCL_TARGET')=>('CONVERT')
          PARAMETER-TABLE lt_ptab
          EXCEPTION-TABLE lt_etab.
        " sy-subrc is 4 only because the etab row said so.
        DATA(lv_subrc) = sy-subrc.
        WRITE: / '  classic exception mapped to sy-subrc =', lv_subrc LEFT-JUSTIFIED.
      CATCH cx_sy_dyn_call_error INTO DATA(lo_err_e).
        DATA(lv_txt_e) = lo_err_e->get_text( ).
        WRITE: / '  unexpected:', lv_txt_e.
    ENDTRY.

    " The class-based one. No etab entry can catch this; it propagates
    " as an exception and needs a real CATCH, alongside the dyn-call
    " CATCH -- the CALL METHOD statement can raise either family.
    "
    " Note there is NO EXCEPTION-TABLE on this call. Reusing lt_etab
    " here would itself fail: docs say etab "must not contain a line
    " with a exception name that does not exist in the method's
    " parameter interface", and STRICT_CONVERT has no NOT_TEXT. That
    " is CX_SY_DYN_CALL_EXCP_NOT_FOUND -- a second runtime-only error
    " produced purely by copy-pasting a working call.
    CLEAR lt_ptab.
    DATA lv_res TYPE string.
    INSERT VALUE abap_parmbind( name  = 'IV_IN'
                                kind  = cl_abap_objectdescr=>exporting
                                value = REF #( lv_in ) ) INTO TABLE lt_ptab.
    INSERT VALUE abap_parmbind( name  = 'RV_OUT'
                                kind  = cl_abap_objectdescr=>receiving
                                value = REF #( lv_res ) ) INTO TABLE lt_ptab.

    TRY.
        CALL METHOD ('LCL_TARGET')=>('STRICT_CONVERT')
          PARAMETER-TABLE lt_ptab.
        WRITE: / '  class-based exception did not fire'.
      CATCH lcx_bad_input.
        WRITE: / '  class-based exception needs TRY/CATCH, not an etab'.
      CATCH cx_sy_dyn_call_error INTO DATA(lo_err_f).
        DATA(lv_txt_f) = lo_err_f->get_text( ).
        WRITE: / '  dyn-call error:', lv_txt_f.
    ENDTRY.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& TRAP 7 -- the name is compared in upper case.
*&
*& The method exists. The spelling is right. The case is not, and the
*& failure text says the method does not exist, which sends people
*& looking in the wrong place.
*&---------------------------------------------------------------------*
  METHOD trap_7_case_sensitivity.
    DATA lv_sum  TYPE i.
    DATA lv_a    TYPE i VALUE 1.
    DATA lv_b    TYPE i VALUE 1.
    DATA lt_ptab TYPE abap_parmbind_tab.

    WRITE: / 'Trap 7 -- lower-case names do not resolve'.

    INSERT VALUE abap_parmbind( name  = 'IV_A'
                                kind  = cl_abap_objectdescr=>exporting
                                value = REF #( lv_a ) ) INTO TABLE lt_ptab.
    INSERT VALUE abap_parmbind( name  = 'IV_B'
                                kind  = cl_abap_objectdescr=>exporting
                                value = REF #( lv_b ) ) INTO TABLE lt_ptab.
    INSERT VALUE abap_parmbind( name  = 'RV_SUM'
                                kind  = cl_abap_objectdescr=>receiving
                                value = REF #( lv_sum ) ) INTO TABLE lt_ptab.

    DATA(lv_class) = `lcl_target`.   " lower case, on purpose
    DATA(lv_meth)  = `add`.          " lower case, on purpose

    TRY.
        CALL METHOD (lv_class)=>(lv_meth) PARAMETER-TABLE lt_ptab.
        WRITE: / '  lower case resolved (it should not have)'.
      CATCH cx_sy_dyn_call_illegal_class INTO DATA(lo_err_g).
        DATA(lv_txt_g) = lo_err_g->get_text( ).
        WRITE: / '  class not found:', lv_txt_g.
      CATCH cx_sy_dyn_call_illegal_method INTO DATA(lo_err_h).
        DATA(lv_txt_h) = lo_err_h->get_text( ).
        WRITE: / '  method not found:', lv_txt_h.
    ENDTRY.

    " to_upper( ) on both halves is the whole fix.
    DATA(lv_class_ok) = to_upper( lv_class ).
    DATA(lv_meth_ok)  = to_upper( lv_meth ).
    TRY.
        CALL METHOD (lv_class_ok)=>(lv_meth_ok) PARAMETER-TABLE lt_ptab.
        WRITE: / '  upper case resolved, 1 + 1 =', lv_sum LEFT-JUSTIFIED.
      CATCH cx_sy_dyn_call_error INTO DATA(lo_err_i).
        DATA(lv_txt_i) = lo_err_i->get_text( ).
        WRITE: / '  unexpected:', lv_txt_i.
    ENDTRY.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& TRAP 8 -- a name that came from outside is arbitrary code.
*&
*& SAP's own security note on Dynamic Calls: "The only way of tackling
*& this security risk is to perform a comparison with an include list."
*& Not a prefix check, not a pattern -- an include list.
*&---------------------------------------------------------------------*
  METHOD trap_8_include_list.
    DATA lt_allowed TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.

    WRITE: / 'Trap 8 -- validate the name against an include list'.

    INSERT `LCL_TARGET` INTO TABLE lt_allowed.

    " Pretend this arrived from a customizing table, an RFC parameter
    " or a selection screen -- anywhere the caller does not control.
    DATA(lv_requested) = `CL_GUI_FRONTEND_SERVICES`.

    TRY.
        DATA(lv_checked) = cl_abap_dyn_prg=>check_whitelist_tab(
                             val       = lv_requested
                             whitelist = lt_allowed ).
        WRITE: / '  accepted:', lv_checked.
      CATCH cx_abap_not_in_whitelist INTO DATA(lo_err_j).
        DATA(lv_txt_j) = lo_err_j->get_text( ).
        WRITE: / '  rejected before the call:', lv_txt_j.
    ENDTRY.

    " A name that IS on the list passes and can then be called.
    TRY.
        DATA(lv_ok) = cl_abap_dyn_prg=>check_whitelist_tab(
                        val       = `LCL_TARGET`
                        whitelist = lt_allowed ).
        WRITE: / '  accepted:', lv_ok.
      CATCH cx_abap_not_in_whitelist INTO DATA(lo_err_k).
        DATA(lv_txt_k) = lo_err_k->get_text( ).
        WRITE: / '  unexpected rejection:', lv_txt_k.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& Trap 1 and trap 4 have no runnable half worth printing:
*&
*&   Trap 1 is the ABSENCE of a syntax error. Renaming IV_A to IV_LEFT
*&   in lcl_target leaves every line of this program activating
*&   cleanly, and breaks trap 2, trap 7 and nothing the compiler says.
*&   The demonstration is to try it.
*&
*&   Trap 4 is a lifetime bug: REF #( ) over a local that has gone out
*&   of scope. In ABAP the reference keeps the object alive, so it does
*&   not dump -- it quietly writes the result somewhere nobody reads.
*&   A method that builds ptab and RETURNS it, expecting the caller to
*&   run the call, is the usual shape of this mistake.
*&---------------------------------------------------------------------*
START-OF-SELECTION.
  lcl_demo=>run( ).
