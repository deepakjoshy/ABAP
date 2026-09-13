*&---------------------------------------------------------------------*
*& Report YDJ_FOR_ALL_ENTRIES_DEMO
*&---------------------------------------------------------------------*
*& Demonstrates the two FOR ALL ENTRIES traps against the flight data
*& model (SPFLI / SFLIGHT), plus the subquery alternative.
*&
*&   1. EMPTY DRIVER TABLE -> the whole WHERE is ignored, every other
*&      condition included, and the full table comes back.
*&   2. IMPLICIT DISTINCT  -> duplicate result rows are removed. If the
*&      field list is not unique, real rows disappear and any SUM/COUNT
*&      taken afterwards is wrong.
*&
*& Run it on any system with the standard SFLIGHT demo data (SAPBC_DATA
*& _GENERATOR if the tables are empty).
*&---------------------------------------------------------------------*
REPORT ydj_for_all_entries_demo.

CLASS lcl_fae_demo DEFINITION.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_key,
             carrid TYPE spfli-carrid,
             connid TYPE spfli-connid,
           END OF ty_key,
           ty_keys TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.

    CLASS-METHODS:
      "! Driver keys for one departure city. May legitimately be empty.
      get_keys IMPORTING iv_city       TYPE spfli-cityfrom
               RETURNING VALUE(rt_keys) TYPE ty_keys,
      trap_empty_driver   IMPORTING it_keys TYPE ty_keys,
      trap_implicit_distinct IMPORTING it_keys TYPE ty_keys,
      safe_subquery       IMPORTING iv_city TYPE spfli-cityfrom.

ENDCLASS.


CLASS lcl_fae_demo IMPLEMENTATION.

  METHOD get_keys.
    SELECT carrid, connid
      FROM spfli
      WHERE cityfrom = @iv_city
      INTO TABLE @rt_keys.

    " Duplicates in the driver do not break correctness, but they cost
    " redundant blocks in the generated SQL. Clean them once, here.
    SORT rt_keys BY carrid connid.
    DELETE ADJACENT DUPLICATES FROM rt_keys COMPARING carrid connid.
  ENDMETHOD.


  METHOD trap_empty_driver.

    " THE GUARD. Without it, an empty it_keys drops the ENTIRE WHERE -
    " including planetype and fldate - and reads all of SFLIGHT.
    IF it_keys IS INITIAL.
      WRITE: / 'Driver table empty - SELECT skipped (this is the guard).'.
      RETURN.
    ENDIF.

    SELECT carrid, connid, fldate, planetype
      FROM sflight
      FOR ALL ENTRIES IN @it_keys
      WHERE carrid    = @it_keys-carrid
        AND connid    = @it_keys-connid
        AND planetype <> @space          " also ignored when it_keys is empty
      INTO TABLE @DATA(lt_flights).

    WRITE: / 'Guarded FAE rows :', lines( lt_flights ).

  ENDMETHOD.


  METHOD trap_implicit_distinct.

    IF it_keys IS INITIAL.
      RETURN.
    ENDIF.

    " WRONG: carrid + seatsocc is not unique. Two flights on different
    " dates with the same occupancy collapse into ONE row, so the total
    " below silently under-reports.
    SELECT carrid, seatsocc
      FROM sflight
      FOR ALL ENTRIES IN @it_keys
      WHERE carrid = @it_keys-carrid
        AND connid = @it_keys-connid
      INTO TABLE @DATA(lt_dedup).

    " RIGHT: the full key (carrid connid fldate) makes every row unique,
    " so nothing is removed by the implicit DISTINCT.
    SELECT carrid, connid, fldate, seatsocc
      FROM sflight
      FOR ALL ENTRIES IN @it_keys
      WHERE carrid = @it_keys-carrid
        AND connid = @it_keys-connid
      INTO TABLE @DATA(lt_full_key).

    DATA(lv_wrong) = REDUCE i( INIT x = 0
                               FOR <w> IN lt_dedup
                               NEXT x = x + <w>-seatsocc ).

    DATA(lv_right) = REDUCE i( INIT y = 0
                               FOR <r> IN lt_full_key
                               NEXT y = y + <r>-seatsocc ).

    WRITE: / 'Rows without full key:', lines( lt_dedup ),
           / 'Rows with full key   :', lines( lt_full_key ),
           / 'Occupancy (wrong)    :', lv_wrong,
           / 'Occupancy (correct)  :', lv_right.

    IF lv_wrong <> lv_right.
      WRITE: / '-> implicit DISTINCT removed real rows.'.
    ENDIF.

  ENDMETHOD.


  METHOD safe_subquery.

    " Same intent, one database statement, no dedup and no empty-table
    " special case to guard against. Preferred where it fits.
    " The value-tuple form ( col1, col2 ) IN ( SELECT ... ) needs a recent
    " release; on older systems use EXISTS with a correlated subquery, or
    " a single-column IN subquery. Note the mandatory blanks just inside
    " every parenthesis - ABAP SQL requires them.
    SELECT carrid, connid, fldate, seatsocc
      FROM sflight
      WHERE ( carrid, connid ) IN ( SELECT carrid, connid FROM spfli
                                      WHERE cityfrom = @iv_city )
      INTO TABLE @DATA(lt_flights).

    WRITE: / 'Subquery rows        :', lines( lt_flights ).

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  DATA(lt_keys) = lcl_fae_demo=>get_keys( 'FRANKFURT' ).

  WRITE: / 'Driver keys          :', lines( lt_keys ).
  SKIP.

  lcl_fae_demo=>trap_empty_driver( lt_keys ).
  SKIP.

  lcl_fae_demo=>trap_implicit_distinct( lt_keys ).
  SKIP.

  lcl_fae_demo=>safe_subquery( 'FRANKFURT' ).
  SKIP.

  " Proof of trap 1, deliberately unguarded: an empty driver table
  " returns rows even though cityfrom could never match.
  DATA(lt_empty) = lcl_fae_demo=>get_keys( 'NO_SUCH_CITY' ).

  SELECT carrid, connid
    FROM spfli
    FOR ALL ENTRIES IN @lt_empty
    WHERE carrid = @lt_empty-carrid
    INTO TABLE @DATA(lt_all).

  WRITE: / 'Empty driver, unguarded FAE returned:', lines( lt_all ), 'rows',
         / '(every row of SPFLI in this client - the WHERE was ignored).'.
