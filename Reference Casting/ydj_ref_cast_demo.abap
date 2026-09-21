*&---------------------------------------------------------------------*
*& Report YDJ_REF_CAST_DEMO
*&---------------------------------------------------------------------*
*& Upcast, downcast and the ways a cast fails quietly.
*& ?= is the only assignment operator in ABAP that can fail at runtime,
*& and when it fails the TARGET KEEPS ITS OLD VALUE. None of the
*& following is a syntax error.
*&
*& Trap numbering matches README.md in this folder.
*&
*&   1. FAILED DOWNCAST KEEPS -> CX_SY_MOVE_CAST_ERROR leaves the target
*&      THE PREVIOUS VALUE       untouched, so the "skip it" CATCH branch
*&                               carries on with the PREVIOUS row's object,
*&                               still bound and still callable.
*&   2. INITIAL REFERENCE      -> a downcast of a null reference ALWAYS
*&      CASTS CLEANLY            succeeds. ?= is not a type check.
*&   3. IS INSTANCE OF SWITCHES-> for an INITIAL reference the check uses
*&      TO THE STATIC TYPE       the STATIC type, so it is true for a
*&                               variable pointing at nothing.
*&   4. CASE TYPE OF BRANCH    -> first match wins and a superclass matches
*&      ORDER IS SILENT          every subclass, so a general WHEN TYPE
*&                               listed first makes the rest dead code.
*&   5. (see README)           -> IS INSTANCE OF is false for the subclass
*&                               while a superclass constructor is running.
*&   6. (see README)           -> CAST chained with -> raises UNCATCHABLE
*&                               exceptions on an initial reference.
*&
*& Self-contained: local classes and literals only, no DDIC, no database.
*&---------------------------------------------------------------------*
REPORT ydj_ref_cast_demo.

*&---------------------------------------------------------------------*
*& A three-level hierarchy. lcl_credit_note is more specific than
*& lcl_invoice, which is more specific than lcl_document.
*&---------------------------------------------------------------------*
CLASS lcl_document DEFINITION.
  PUBLIC SECTION.
    METHODS constructor IMPORTING iv_id TYPE string.
    METHODS get_id RETURNING VALUE(rv_id) TYPE string.
  PROTECTED SECTION.
    DATA mv_id TYPE string.
ENDCLASS.

CLASS lcl_document IMPLEMENTATION.
  METHOD constructor.
    mv_id = iv_id.
  ENDMETHOD.

  METHOD get_id.
    rv_id = mv_id.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_invoice DEFINITION INHERITING FROM lcl_document.
  PUBLIC SECTION.
    METHODS post RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.

CLASS lcl_invoice IMPLEMENTATION.
  METHOD post.
    rv_text = |posted invoice { mv_id }|.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_credit_note DEFINITION INHERITING FROM lcl_invoice.
ENDCLASS.

CLASS lcl_credit_note IMPLEMENTATION.
ENDCLASS.

*&---------------------------------------------------------------------*
*& The traps.
*&---------------------------------------------------------------------*
CLASS lcl_demo DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS trap_1_stale_target.
    CLASS-METHODS trap_2_initial_casts_ok.
    CLASS-METHODS trap_3_instance_of_initial.
    CLASS-METHODS trap_4_branch_order.
ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

*&---------------------------------------------------------------------*
*& Trap 1: the failed downcast keeps the previous value.
*& Two documents are processed. The first is an invoice and casts
*& cleanly. The second is a plain document, so the cast raises - and
*& lo_invoice STILL POINTS AT THE FIRST ONE. IS BOUND is true, post( )
*& runs, and the wrong document is posted with no dump.
*&---------------------------------------------------------------------*
  METHOD trap_1_stale_target.

    DATA lo_invoice TYPE REF TO lcl_invoice.
    DATA lv_cast    TYPE string.
    DATA lt_docs    TYPE STANDARD TABLE OF REF TO lcl_document WITH EMPTY KEY.

    APPEND NEW lcl_invoice( |INV-0001| )  TO lt_docs.
    APPEND NEW lcl_document( |DOC-0002| ) TO lt_docs.

    LOOP AT lt_docs INTO DATA(lo_doc).

      DATA(lv_in) = lo_doc->get_id( ).

      TRY.
          lo_invoice ?= lo_doc.
          lv_cast = |ok|.
        CATCH cx_sy_move_cast_error.
          lv_cast = |CX_SY_MOVE_CAST_ERROR|.
      ENDTRY.

      DATA(lv_bound) = COND string( WHEN lo_invoice IS BOUND
                                    THEN |bound| ELSE |initial| ).

      DATA(lv_out) = COND string( WHEN lo_invoice IS BOUND
                                  THEN lo_invoice->post( ) ELSE |-| ).

      WRITE: / 'Trap 1  in:', lv_in,
               'cast:', lv_cast,
               'target:', lv_bound,
               '->', lv_out.

    ENDLOOP.

    WRITE: / 'Trap 1  row 2 posted INV-0001: the target was never cleared.'.
    SKIP.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Trap 2: a downcast of an INITIAL reference always succeeds.
*& There is no dynamic type to conflict with, so the null reference is
*& assignable to any target. No exception, nothing to catch - and the
*& first -> afterwards dumps with OBJECTS_OBJREF_NOT_ASSIGNED.
*&---------------------------------------------------------------------*
  METHOD trap_2_initial_casts_ok.

    DATA lo_src     TYPE REF TO lcl_document.
    DATA lo_invoice TYPE REF TO lcl_invoice.
    DATA lv_cast    TYPE string.

    TRY.
        lo_invoice ?= lo_src.
        lv_cast = |succeeded|.
      CATCH cx_sy_move_cast_error.
        lv_cast = |CX_SY_MOVE_CAST_ERROR|.
    ENDTRY.

    DATA(lv_bound) = COND string( WHEN lo_invoice IS BOUND
                                  THEN |bound| ELSE |initial| ).

    WRITE: / 'Trap 2  source initial, cast', lv_cast,
             '- target is', lv_bound.
    WRITE: / 'Trap 2  guard with IS BOUND BEFORE the cast, not after it.'.
    SKIP.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Trap 3: IS INSTANCE OF uses the DYNAMIC type of a non-initial
*& reference but the STATIC type of an initial one - so an unbound
*& lcl_invoice variable is an instance of lcl_invoice.
*&---------------------------------------------------------------------*
  METHOD trap_3_instance_of_initial.

    DATA lo_empty TYPE REF TO lcl_invoice.

    DATA(lv_empty) = COND string(
      WHEN lo_empty IS INSTANCE OF lcl_invoice THEN |true| ELSE |false| ).

    DATA lo_filled TYPE REF TO lcl_document.
    lo_filled = NEW lcl_credit_note( |CRN-0003| ).

    DATA(lv_filled) = COND string(
      WHEN lo_filled IS INSTANCE OF lcl_invoice THEN |true| ELSE |false| ).

    WRITE: / 'Trap 3  initial lcl_invoice ref IS INSTANCE OF lcl_invoice:',
             lv_empty.
    WRITE: / 'Trap 3  lcl_document ref holding a credit note:', lv_filled,
             '(dynamic type wins)'.
    SKIP.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Trap 4: CASE TYPE OF takes the FIRST matching branch, and a
*& superclass matches every subclass. Listing the general type first
*& makes every branch below it unreachable - no syntax error, no
*& warning. Both orders are run over the same object.
*&---------------------------------------------------------------------*
  METHOD trap_4_branch_order.

    DATA lo_doc TYPE REF TO lcl_document.
    lo_doc = NEW lcl_credit_note( |CRN-0004| ).

    DATA lv_wrong TYPE string.
    CASE TYPE OF lo_doc.
      WHEN TYPE lcl_document.
        lv_wrong = |lcl_document|.
      WHEN TYPE lcl_invoice.
        lv_wrong = |lcl_invoice|.
      WHEN TYPE lcl_credit_note.
        lv_wrong = |lcl_credit_note|.
      WHEN OTHERS.
        lv_wrong = |none|.
    ENDCASE.

    DATA lv_right TYPE string.
    DATA lv_id    TYPE string.
    CASE TYPE OF lo_doc.
      WHEN TYPE lcl_credit_note INTO DATA(lo_credit).
        lv_right = |lcl_credit_note|.
        lv_id    = lo_credit->get_id( ).
      WHEN TYPE lcl_invoice INTO DATA(lo_inv).
        lv_right = |lcl_invoice|.
        lv_id    = lo_inv->get_id( ).
      WHEN OTHERS.
        lv_right = |none|.
    ENDCASE.

    WRITE: / 'Trap 4  general branch first ->', lv_wrong.
    WRITE: / 'Trap 4  specific branch first ->', lv_right,
             'INTO gave id', lv_id.
    SKIP.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
START-OF-SELECTION.

  WRITE: / 'Reference casting - ?= , CAST , IS INSTANCE OF , CASE TYPE OF'.
  SKIP.

  lcl_demo=>trap_1_stale_target( ).
  lcl_demo=>trap_2_initial_casts_ok( ).
  lcl_demo=>trap_3_instance_of_initial( ).
  lcl_demo=>trap_4_branch_order( ).
