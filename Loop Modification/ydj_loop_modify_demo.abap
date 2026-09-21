*&---------------------------------------------------------------------*
*& Report YDJ_LOOP_MODIFY_DEMO
*&---------------------------------------------------------------------*
*& Inserting into / deleting from an internal table INSIDE a LOOP over
*& that same table. All of this is documented behaviour, none of it is
*& what the surrounding code usually assumes.
*&
*&   1. INSERT AFTER  -> new lines ARE processed by later passes, so an
*&                       insert inside the loop can never terminate.
*&   2. DELETE BEFORE -> the internal loop counter is DECREASED per
*&                       deleted line, so sy-tabix in the NEXT pass is
*&                       not the number you reasoned about.
*&   3. DELETE CURRENT-> contrary to folklore this does NOT skip lines:
*&                       the loop counter is decreased to match. The
*&                       hand-rolled DO + READ INDEX loop DOES skip.
*&   4. TO idx2       -> evaluated in EVERY pass (FROM idx1 only once),
*&                       so the pass count is not idx2 - idx1 + 1.
*&   5. WHOLE BODY    -> CLEAR/FREE/REFRESH/SORT/DELETE...WHERE/any
*&                       assignment to the table. Commented out: these
*&                       dump with TABLE_FREE_IN_LOOP.
*&
*& Self-contained: literals only, no DDIC tables, no database access.
*&---------------------------------------------------------------------*
REPORT ydj_loop_modify_demo.

TYPES: BEGIN OF ty_row,
         id   TYPE i,
         name TYPE c LENGTH 10,
       END OF ty_row.

TYPES ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.


CLASS lcl_loop_demo DEFINITION.

  PUBLIC SECTION.
    CLASS-METHODS:
      insert_after_never_ends,
      delete_before_shifts_tabix,
      delete_current_does_not_skip,
      to_is_reevaluated_every_pass,
      whole_body_is_forbidden.

  PRIVATE SECTION.
    CLASS-METHODS get_rows RETURNING VALUE(rt_rows) TYPE ty_rows.

ENDCLASS.


CLASS lcl_loop_demo IMPLEMENTATION.

  METHOD get_rows.
    rt_rows = VALUE #( ( id = 1 name = 'ALPHA' )
                       ( id = 2 name = 'BRAVO' )
                       ( id = 3 name = 'CHARLIE' )
                       ( id = 4 name = 'DELTA' )
                       ( id = 5 name = 'ECHO' ) ).
  ENDMETHOD.


  METHOD insert_after_never_ends.

    DATA lt_rows TYPE ty_rows.
    DATA ls_new  TYPE ty_row.
    DATA lv_pass TYPE i.
    DATA lv_size TYPE i.

    WRITE: / '1. INSERT AFTER THE CURRENT LINE IS PROCESSED BY THE LOOP'.
    ULINE.

    lt_rows = get_rows( ).

    " Lines inserted AFTER the current line are read by the following
    " passes. Without the guard below this loop never terminates: every
    " pass appends one more line for a later pass to find.
    LOOP AT lt_rows INTO DATA(ls_row).

      lv_pass = lv_pass + 1.

      ls_new-id   = ls_row-id + 100.
      ls_new-name = 'COPY'.
      APPEND ls_new TO lt_rows.

      " Guard. Real code does not have one - that is the whole problem.
      IF lv_pass >= 12.
        WRITE: / 'Bailed out after', lv_pass, 'passes - still going.'.
        EXIT.
      ENDIF.

    ENDLOOP.

    lv_size = lines( lt_rows ).
    WRITE: / 'Started with 5 lines, table now holds', lv_size.
    WRITE: / 'Fix: collect into a SECOND table, append after ENDLOOP.'.
    SKIP.

  ENDMETHOD.


  METHOD delete_before_shifts_tabix.

    DATA lt_rows  TYPE ty_rows.
    DATA lv_tabix TYPE sy-tabix.

    WRITE: / '2. DELETING AN EARLIER LINE DECREASES THE LOOP COUNTER'.
    ULINE.

    lt_rows = get_rows( ).

    LOOP AT lt_rows INTO DATA(ls_row).

      lv_tabix = sy-tabix.
      WRITE: / 'pass sy-tabix', lv_tabix, 'id', ls_row-id, ls_row-name.

      " Delete line 1 while standing on line 3. Everything behind it
      " moves down and the loop counter is decreased to match, so the
      " next pass reports a sy-tabix that no longer lines up with the
      " row numbers this code was written against.
      IF ls_row-id = 3.
        DELETE lt_rows INDEX 1.
        WRITE: / '   -> deleted index 1 (an EARLIER line)'.
      ENDIF.

    ENDLOOP.

    WRITE: / 'sy-tabix is a position in the CURRENT table, not a row id.'.
    SKIP.

  ENDMETHOD.


  METHOD delete_current_does_not_skip.

    DATA lt_rows  TYPE ty_rows.
    DATA lt_seen  TYPE ty_rows.
    DATA lt_seen2 TYPE ty_rows.
    DATA lv_seen  TYPE i.
    DATA lv_idx   TYPE i.

    WRITE: / '3. DELETING THE CURRENT LINE DOES NOT SKIP THE NEXT ONE'.
    ULINE.

    " Widely repeated folklore says this skips every other line. It does
    " not. Deleting the current line DECREASES the internal loop counter,
    " so the line that moves into the freed slot is read next.
    lt_rows = get_rows( ).

    LOOP AT lt_rows INTO DATA(ls_row).
      APPEND ls_row TO lt_seen.
      DELETE lt_rows INDEX sy-tabix.
    ENDLOOP.

    LOOP AT lt_seen INTO DATA(ls_seen).
      WRITE: / 'LOOP visited id', ls_seen-id, ls_seen-name.
    ENDLOOP.

    lv_seen = lines( lt_seen ).
    WRITE: / 'LOOP visited', lv_seen, 'of 5 - all of them.'.
    SKIP.

    " The hand-rolled index loop, which looks equivalent, is the one
    " that really does skip: nothing decrements lv_idx when a line
    " vanishes, so the line that moved down is stepped straight over.
    lt_rows = get_rows( ).
    lv_idx  = 1.

    DO.
      READ TABLE lt_rows INTO DATA(ls_manual) INDEX lv_idx.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      APPEND ls_manual TO lt_seen2.
      DELETE lt_rows INDEX lv_idx.
      lv_idx = lv_idx + 1.
    ENDDO.

    LOOP AT lt_seen2 INTO DATA(ls_seen2).
      WRITE: / 'DO   visited id', ls_seen2-id, ls_seen2-name.
    ENDLOOP.

    lv_seen = lines( lt_seen2 ).
    WRITE: / 'DO visited', lv_seen, 'of 5 - every other line.'.
    WRITE: / 'Either way: prefer DELETE ... WHERE once, AFTER the loop.'.
    SKIP.

  ENDMETHOD.


  METHOD to_is_reevaluated_every_pass.

    DATA lt_rows TYPE ty_rows.
    DATA lv_from TYPE i VALUE 1.
    DATA lv_to   TYPE i VALUE 4.
    DATA lv_pass TYPE i.

    WRITE: / '4. FROM IS READ ONCE, TO IS READ IN EVERY PASS'.
    ULINE.

    lt_rows = get_rows( ).

    " idx1 is evaluated when the loop is entered and later changes are
    " ignored. idx2 is evaluated in every pass, so changing it mid-loop
    " moves the end of the loop.
    LOOP AT lt_rows INTO DATA(ls_row) FROM lv_from TO lv_to.

      lv_pass = lv_pass + 1.
      WRITE: / 'pass', lv_pass, 'id', ls_row-id.

      IF ls_row-id = 2.
        lv_from = 99.   " ignored - the loop already started
        lv_to   = 3.    " respected - the loop now ends one line earlier
        WRITE: / '   -> set FROM to 99 (ignored), TO to 3 (applied)'.
      ENDIF.

    ENDLOOP.

    WRITE: / 'Ran', lv_pass, 'passes, not the 4 the bounds imply.'.
    SKIP.

  ENDMETHOD.


  METHOD whole_body_is_forbidden.

    DATA lt_rows TYPE ty_rows.

    WRITE: / '5. WHOLE-TABLE-BODY ACCESS INSIDE ITS OWN LOOP'.
    ULINE.

    lt_rows = get_rows( ).

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>).

      WRITE: / 'id', <ls_row>-id, <ls_row>-name.

      " Every statement below replaces the ENTIRE table body and is a
      " runtime error (TABLE_FREE_IN_LOOP) here. Inside a class, or on a
      " LOOP with a statically known secondary key, it is a SYNTAX error
      " instead. Left commented out so the report still runs.
      "
      "   CLEAR   lt_rows.
      "   FREE    lt_rows.
      "   REFRESH lt_rows.
      "   SORT    lt_rows BY id.
      "   DELETE  lt_rows WHERE id > 3.
      "   lt_rows = get_rows( ).
      "
      " Single-line access is fine - that is what this loop is for.

    ENDLOOP.

    WRITE: / 'Single lines: yes. The whole body: no.'.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_loop_demo=>insert_after_never_ends( ).
  lcl_loop_demo=>delete_before_shifts_tabix( ).
  lcl_loop_demo=>delete_current_does_not_skip( ).
  lcl_loop_demo=>to_is_reevaluated_every_pass( ).
  lcl_loop_demo=>whole_body_is_forbidden( ).
