*&---------------------------------------------------------------------*
*& Report YDJ_CONTROL_LEVEL_DEMO
*&---------------------------------------------------------------------*
*& Control level (group level) processing with AT NEW / AT END OF / SUM,
*& and the reason ON CHANGE OF is not a substitute for it.
*&
*&   1. ASTERISKS      -> inside an AT block, every component to the RIGHT
*&                        of the group key is overwritten: character-like
*&                        with '*', everything else with its initial value.
*&   2. POSITIONAL KEY -> AT NEW connid means "carrid AND connid": the group
*&                        key is compi PLUS every component left of it.
*&   3. INTO vs ASSIGNING -> the '*' filling only happens with INTO wa.
*&                        With ASSIGNING the same block reads real values,
*&                        and SUM is not allowed at all (SUM_NO_ASSIGNING).
*&   4. WHERE          -> a group break whose first/last row is filtered out
*&                        never fires, so totals silently go missing.
*&   5. ON CHANGE OF   -> hidden helper variable that is global to the
*&                        PROGRAM and outlives the procedure, so a second
*&                        pass over the same values fires nothing.
*&
*& Self-contained: no DDIC tables needed.
*&---------------------------------------------------------------------*
REPORT ydj_control_level_demo.

TYPES: ty_carrid TYPE c LENGTH 3.

TYPES: BEGIN OF ty_flight,
         carrid   TYPE ty_carrid,             " group key candidate 1
         connid   TYPE n LENGTH 4,            " group key candidate 2
         fldate   TYPE d,
         seatsocc TYPE i,
         paymnt   TYPE p LENGTH 9 DECIMALS 2,
       END OF ty_flight,
       ty_flights TYPE STANDARD TABLE OF ty_flight WITH EMPTY KEY.


CLASS lcl_ctrl_demo DEFINITION.

  PUBLIC SECTION.
    CLASS-METHODS:
      asterisks_and_sum,
      group_key_is_positional,
      assigning_changes_the_rules,
      where_skips_the_break.

  PRIVATE SECTION.
    " Control level processing requires the table to be sorted in the
    " order of the components of its LINE TYPE - first component first.
    " Nothing checks this at runtime; an unsorted table just produces
    " repeated group breaks for the same key.
    CLASS-METHODS get_data RETURNING VALUE(rt_flights) TYPE ty_flights.

ENDCLASS.


CLASS lcl_ctrl_demo IMPLEMENTATION.

  METHOD get_data.
    rt_flights = VALUE #(
      ( carrid = 'LH' connid = '0400' fldate = '20260101' seatsocc = 10 paymnt = '100.00' )
      ( carrid = 'LH' connid = '0400' fldate = '20260102' seatsocc = 20 paymnt = '200.00' )
      ( carrid = 'LH' connid = '0402' fldate = '20260101' seatsocc =  5 paymnt = '50.00'  )
      ( carrid = 'UA' connid = '0941' fldate = '20260101' seatsocc = 30 paymnt = '300.00' )
      ( carrid = 'UA' connid = '0941' fldate = '20260102' seatsocc = 40 paymnt = '400.00' ) ).
  ENDMETHOD.


  METHOD asterisks_and_sum.
    DATA ls_row TYPE ty_flight.

    WRITE: / '--- 1. asterisk filling and SUM ---'.

    DATA(lt_flights) = get_data( ).

    LOOP AT lt_flights INTO ls_row.

      AT NEW carrid.
        " THE TRAP: the group key here is CARRID only. Everything to its
        " right has been overwritten for the duration of this block -
        " CONNID is character-like (type n) so it reads '****', FLDATE
        " '00000000', SEATSOCC 0, PAYMNT 0.00. Printing ls_row-connid
        " here is the classic "why is my report full of stars" bug.
        WRITE: / 'AT NEW carrid  :', ls_row-carrid,
                 'connid=', ls_row-connid,
                 'seats=',  ls_row-seatsocc.
      ENDAT.

      " Outside the AT blocks the work area holds the real row again.
      WRITE: / '  row          :', ls_row-carrid, ls_row-connid,
                                   ls_row-fldate, ls_row-seatsocc.

      AT END OF carrid.
        " SUM totals the NUMERIC components to the right of the current
        " group key over the rows of this group - SEATSOCC and PAYMNT.
        " It needs LOOP ... INTO with a work area COMPATIBLE with the
        " line type, and it dumps (SUM_OVERFLOW / CX_SY_ARITHMETIC_OVERFLOW)
        " if the target component is too small for the total.
        SUM.
        WRITE: / 'AT END OF carrid:', ls_row-carrid,
                 'seats=', ls_row-seatsocc,
                 'paid=',  ls_row-paymnt.
      ENDAT.

    ENDLOOP.
  ENDMETHOD.


  METHOD group_key_is_positional.
    DATA ls_row TYPE ty_flight.

    WRITE: / '--- 2. AT NEW connid also breaks on carrid ---'.

    DATA(lt_flights) = get_data( ).

    LOOP AT lt_flights INTO ls_row.
      " The group key of AT NEW connid is CARRID + CONNID, because the
      " key is compi plus every component to the LEFT of it in the line
      " type. Two carriers that happen to reuse the same connid are
      " therefore still two groups - and conversely, moving a field in
      " the structure silently changes what your AT statements mean.
      AT NEW connid.
        WRITE: / 'AT NEW connid  :', ls_row-carrid, ls_row-connid.
      ENDAT.
    ENDLOOP.
  ENDMETHOD.


  METHOD assigning_changes_the_rules.
    WRITE: / '--- 3. same block, ASSIGNING: no asterisks ---'.

    DATA(lt_flights) = get_data( ).

    LOOP AT lt_flights ASSIGNING FIELD-SYMBOL(<ls_row>).
      " With ASSIGNING (and with REFERENCE INTO) the referenced table row
      " is NOT modified on entering/leaving the AT block, so CONNID is the
      " real value here, not '****'. Handy - but it means the behaviour of
      " an AT block depends on how the LOOP was written, and SUM cannot be
      " used at all: it raises the runtime error SUM_NO_ASSIGNING.
      AT NEW carrid.
        WRITE: / 'AT NEW carrid  :', <ls_row>-carrid,
                 'connid=', <ls_row>-connid,
                 'seats=',  <ls_row>-seatsocc.
      ENDAT.
    ENDLOOP.
  ENDMETHOD.


  METHOD where_skips_the_break.
    DATA ls_row TYPE ty_flight.

    WRITE: / '--- 4. WHERE suppresses group breaks ---'.

    " Group levels are defined over ALL rows of the table, ignoring the
    " WHERE. But the AT block only runs if the row that carries the break
    " is actually read. LH's first row has seatsocc = 10 and is filtered
    " out, so AT NEW carrid never fires for LH - while its remaining rows
    " are processed normally. The extended syntax check (SLIN) flags this.
    DATA(lt_flights) = get_data( ).

    LOOP AT lt_flights INTO ls_row WHERE seatsocc >= 20.
      AT NEW carrid.
        WRITE: / 'AT NEW carrid  :', ls_row-carrid.
      ENDAT.
      WRITE: / '  row read     :', ls_row-carrid, ls_row-connid,
                                   ls_row-seatsocc.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& ON CHANGE OF lives here and not in the class: it is FORBIDDEN inside
*& classes. That restriction is the hint - the helper variable it uses is
*& global to the program and survives the procedure.
*&---------------------------------------------------------------------*
FORM show_break USING pv_carrid TYPE ty_carrid.
  ON CHANGE OF pv_carrid.
    WRITE: / '  ON CHANGE OF fired for', pv_carrid.
  ENDON.
ENDFORM.


START-OF-SELECTION.

  lcl_ctrl_demo=>asterisks_and_sum( ).
  SKIP.
  lcl_ctrl_demo=>group_key_is_positional( ).
  SKIP.
  lcl_ctrl_demo=>assigning_changes_the_rules( ).
  SKIP.
  lcl_ctrl_demo=>where_skips_the_break( ).
  SKIP.

  WRITE: / '--- 5. ON CHANGE OF keeps state across calls ---'.

  " Pass 1 over a fresh "document": the first LH is a change (the hidden
  " helper is still initial), the second is not.
  WRITE: / 'Document 1:'.
  PERFORM show_break USING 'LH'.
  PERFORM show_break USING 'LH'.

  " Pass 2 is a different document and should start clean. It does not:
  " the helper variable belonging to that one ON CHANGE OF statement still
  " holds 'LH', so NOTHING is printed for document 2. There is no way to
  " reset it - the variable is not addressable from the program. Inside a
  " nested loop this is the bug that eats the first line of every group
  " after the first. Use AT NEW, or a helper variable you declared and can
  " CLEAR yourself.
  WRITE: / 'Document 2:'.
  PERFORM show_break USING 'LH'.
  PERFORM show_break USING 'LH'.
