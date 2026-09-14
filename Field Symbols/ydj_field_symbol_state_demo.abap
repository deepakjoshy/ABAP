*&---------------------------------------------------------------------*
*& Report YDJ_FIELD_SYMBOL_STATE_DEMO
*&---------------------------------------------------------------------*
*& Field symbols: the assignment STATE, not the performance story.
*&
*&   1. STALE READ     -> a failed READ TABLE ... ASSIGNING leaves the
*&                        field symbol on the PREVIOUS row, so
*&                        IS ASSIGNED is true and you read stale data.
*&   2. SY-SUBRC       -> static ASSIGN does not set sy-subrc at all;
*&                        dynamic ASSIGN does, but keeps the old
*&                        assignment unless ELSE UNASSIGN is given.
*&   3. CLEAR/UNASSIGN -> CLEAR <fs> does NOT detach the field symbol,
*&                        it wipes the table row it points to.
*&   4. LOOP LIFETIME  -> deleting the current row unassigns the field
*&                        symbol for the rest of that pass.
*&
*& Self-contained: no DDIC objects and no demo data needed.
*&---------------------------------------------------------------------*
REPORT ydj_field_symbol_state_demo.

CLASS lcl_fs_demo DEFINITION.

  PUBLIC SECTION.

    TYPES: BEGIN OF ty_carrier,
             carrid TYPE c LENGTH 3,
             name   TYPE c LENGTH 20,
             seats  TYPE i,
           END OF ty_carrier,
           ty_carriers TYPE STANDARD TABLE OF ty_carrier WITH EMPTY KEY.

    CLASS-METHODS:
      failed_read_keeps_old_row,
      assign_and_sy_subrc,
      clear_is_not_unassign,
      delete_inside_loop,
      build_carriers RETURNING VALUE(rt_carriers) TYPE ty_carriers.

ENDCLASS.


CLASS lcl_fs_demo IMPLEMENTATION.

  METHOD build_carriers.
    rt_carriers = VALUE #( ( carrid = 'LH' name = 'Lufthansa'    seats = 220 )
                           ( carrid = 'AA' name = 'American'     seats = 180 )
                           ( carrid = 'UA' name = 'United'       seats = 195 ) ).
  ENDMETHOD.


  METHOD failed_read_keeps_old_row.
    " TRAP 1: the second READ finds nothing, but <fs> still points at LH.
    DATA(lt_carriers) = build_carriers( ).

    FIELD-SYMBOLS <fs> TYPE ty_carrier.

    READ TABLE lt_carriers ASSIGNING <fs> WITH KEY carrid = 'LH'.
    WRITE: / '  read LH  -> sy-subrc', sy-subrc, '| <fs>-carrid', <fs>-carrid.

    READ TABLE lt_carriers ASSIGNING <fs> WITH KEY carrid = 'XX'.
    WRITE: / '  read XX  -> sy-subrc', sy-subrc.

    IF <fs> IS ASSIGNED.
      " Reached, even though the read failed. <fs> is the LH row.
      WRITE: / '  IS ASSIGNED is TRUE, <fs>-carrid still', <fs>-carrid,
             '  <- stale'.
    ENDIF.

    " Correct guard: evaluate sy-subrc, not IS ASSIGNED.
    READ TABLE lt_carriers ASSIGNING <fs> WITH KEY carrid = 'XX'.
    IF sy-subrc <> 0.
      WRITE: / '  sy-subrc guard correctly rejects the miss'.
    ENDIF.

    " Or make the state honest, then either check works.
    READ TABLE lt_carriers ASSIGNING <fs> WITH KEY carrid = 'XX'
                           ELSE UNASSIGN.
    IF <fs> IS NOT ASSIGNED.
      WRITE: / '  with ELSE UNASSIGN, IS ASSIGNED is FALSE as expected'.
    ENDIF.
  ENDMETHOD.


  METHOD assign_and_sy_subrc.
    " TRAP 2: which check is valid depends on static vs dynamic ASSIGN.
    DATA lv_text TYPE string VALUE `Hello world`.
    DATA lr_data TYPE REF TO data.

    FIELD-SYMBOLS <any> TYPE any.

    " Dynamic assignment - sy-subrc IS set.
    ASSIGN ('LV_TEXT') TO <any> ELSE UNASSIGN.
    WRITE: / '  dynamic ASSIGN hit    -> sy-subrc', sy-subrc.

    " Dynamic miss WITHOUT ELSE UNASSIGN: subrc 4, old assignment survives.
    ASSIGN ('DOES_NOT_EXIST') TO <any>.
    IF sy-subrc = 4 AND <any> IS ASSIGNED.
      WRITE: / '  dynamic miss          -> sy-subrc 4 but still ASSIGNED'.
    ENDIF.

    " Dynamic miss WITH ELSE UNASSIGN: state matches the return code.
    ASSIGN ('DOES_NOT_EXIST') TO <any> ELSE UNASSIGN.
    IF sy-subrc = 4 AND <any> IS NOT ASSIGNED.
      WRITE: / '  dynamic miss + ELSE UNASSIGN -> sy-subrc 4 and UNASSIGNED'.
    ENDIF.

    " Unbound data reference: same rule applies.
    ASSIGN lr_data->* TO <any> ELSE UNASSIGN.
    IF <any> IS NOT ASSIGNED.
      WRITE: / '  deref of unbound ref  -> sy-subrc', sy-subrc,
             'and UNASSIGNED'.
    ENDIF.

    " Static assignment: sy-subrc is NOT set, so only IS ASSIGNED is valid.
    ASSIGN lv_text TO <any>.
    IF <any> IS ASSIGNED.
      WRITE: / '  static ASSIGN         -> check IS ASSIGNED, not sy-subrc'.
    ENDIF.
  ENDMETHOD.


  METHOD clear_is_not_unassign.
    " TRAP 3: CLEAR <fs> wipes the ROW, it does not detach the pointer.
    DATA(lt_carriers) = build_carriers( ).

    LOOP AT lt_carriers ASSIGNING FIELD-SYMBOL(<row>).
      " A habit carried over from LOOP ... INTO wa. Here it blanks the
      " actual table line, every single pass.
      CLEAR <row>.
    ENDLOOP.

    LOOP AT lt_carriers ASSIGNING <row>.
      WRITE: / '  row', sy-tabix, 'carrid [', <row>-carrid, '] seats',
             <row>-seats, ' <- wiped by CLEAR'.
    ENDLOOP.

    " UNASSIGN is the one that detaches - and leaves the data alone.
    DATA(lt_intact) = build_carriers( ).
    FIELD-SYMBOLS <line> TYPE ty_carrier.

    READ TABLE lt_intact ASSIGNING <line> INDEX 1.
    UNASSIGN <line>.
    IF <line> IS NOT ASSIGNED.
      WRITE: / '  after UNASSIGN: detached, row 1 carrid still',
             lt_intact[ 1 ]-carrid.
    ENDIF.
  ENDMETHOD.


  METHOD delete_inside_loop.
    " TRAP 4: after deleting the current row the field symbol is gone.
    DATA(lt_carriers) = build_carriers( ).

    LOOP AT lt_carriers ASSIGNING FIELD-SYMBOL(<row>).

      IF <row>-carrid = 'AA'.
        DELETE lt_carriers INDEX sy-tabix.
        " <row> is now UNASSIGNED. Any use below dumps with
        " GETWA_NOT_ASSIGNED, so leave the pass immediately.
        CONTINUE.
      ENDIF.

      WRITE: / '  kept', <row>-carrid.

    ENDLOOP.

    WRITE: / '  remaining lines:', lines( lt_carriers ).
  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  WRITE: / '1. Failed READ TABLE ... ASSIGNING keeps the previous row'.
  lcl_fs_demo=>failed_read_keeps_old_row( ).

  SKIP.
  WRITE: / '2. ASSIGN and sy-subrc: static vs dynamic'.
  lcl_fs_demo=>assign_and_sy_subrc( ).

  SKIP.
  WRITE: / '3. CLEAR <fs> is not UNASSIGN <fs>'.
  lcl_fs_demo=>clear_is_not_unassign( ).

  SKIP.
  WRITE: / '4. Deleting the current row inside LOOP ... ASSIGNING'.
  lcl_fs_demo=>delete_inside_loop( ).
