*&---------------------------------------------------------------------*
*& Report YDJ_CORRESPONDING_DEMO
*&---------------------------------------------------------------------*
*& CORRESPONDING #( ) is NOT a drop-in replacement for MOVE-CORRESPONDING.
*& Four differences, all of which lose data quietly rather than dumping:
*&
*&   1. STRUCTURES  -> CORRESPONDING #( ) builds a NEW structure, so
*&                     target components with no source counterpart come
*&                     back INITIAL. MOVE-CORRESPONDING leaves them alone.
*&                     BASE ( ) restores the old behaviour.
*&   2. TABLES      -> MOVE-CORRESPONDING itab1 TO itab2 DELETES itab2
*&                     first. KEEPING TARGET LINES / BASE ( ) appends.
*&   3. NESTED      -> without DEEP a tabular component is assigned as one
*&                     whole body, so a nested target table is REPLACED.
*&                     DEEP APPENDING ( ) merges it instead.
*&   4. DUPLICATES  -> inserting into a target with a UNIQUE key raises
*&                     ITAB_DUPLICATE_KEY unless DISCARDING DUPLICATES.
*&
*& Plus the FROM ... USING lookup variant, which replaces the classic
*& LOOP + READ TABLE enrichment with one statement.
*&
*& Self-contained - no SFLIGHT demo data needed.
*&---------------------------------------------------------------------*
REPORT ydj_corresponding_demo.

CLASS lcl_corr_demo DEFINITION.

  PUBLIC SECTION.

    TYPES: BEGIN OF ty_item,
             item_no  TYPE n LENGTH 3,
             material TYPE c LENGTH 18,
             qty      TYPE i,
           END OF ty_item,
           ty_items TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY.

    " Source head: no STATUS, no PLANT.
    TYPES: BEGIN OF ty_src_head,
             order_id TYPE c LENGTH 10,
             customer TYPE c LENGTH 10,
             items    TYPE ty_items,
           END OF ty_src_head.

    " Target head: carries STATUS, which the source cannot supply.
    TYPES: BEGIN OF ty_tgt_head,
             order_id TYPE c LENGTH 10,
             customer TYPE c LENGTH 10,
             status   TYPE c LENGTH 1,
             items    TYPE ty_items,
           END OF ty_tgt_head.

    CLASS-METHODS:
      structure_target_is_wiped,
      table_target_is_wiped,
      nested_table_is_replaced,
      duplicates_need_discarding,
      lookup_replaces_the_loop.

  PRIVATE SECTION.
    CLASS-METHODS build_source RETURNING VALUE(rs_src) TYPE ty_src_head.

ENDCLASS.


CLASS lcl_corr_demo IMPLEMENTATION.

  METHOD build_source.
    rs_src = VALUE ty_src_head(
               order_id = '4500000001'
               customer = 'C1000'
               items    = VALUE ty_items(
                            ( item_no = '010' material = 'M-01' qty = 5 )
                            ( item_no = '020' material = 'M-02' qty = 7 ) ) ).
  ENDMETHOD.


  METHOD structure_target_is_wiped.
    DATA(ls_src) = build_source( ).

    " Target already carries a status that the source knows nothing about.
    DATA ls_tgt TYPE ty_tgt_head.
    ls_tgt-status = 'A'.

    " Old statement: components with no identically named source partner
    " keep their current value. STATUS survives.
    MOVE-CORRESPONDING ls_src TO ls_tgt.
    WRITE: / 'MOVE-CORRESPONDING  status =', ls_tgt-status, '(kept)'.

    CLEAR ls_tgt.
    ls_tgt-status = 'A'.

    " THE TRAP: the constructor expression builds a brand new structure and
    " then assigns it. STATUS has no source component, so it comes back
    " INITIAL - the value is gone, with no warning and no dump.
    ls_tgt = CORRESPONDING #( ls_src ).
    WRITE: / 'CORRESPONDING #( )  status =', ls_tgt-status, '(lost)'.

    CLEAR ls_tgt.
    ls_tgt-status = 'A'.

    " BASE ( ) seeds the result with the current target, which restores
    " MOVE-CORRESPONDING semantics while keeping the expression form.
    ls_tgt = CORRESPONDING #( BASE ( ls_tgt ) ls_src ).
    WRITE: / 'BASE ( ) form       status =', ls_tgt-status, '(kept)'.
  ENDMETHOD.


  METHOD table_target_is_wiped.
    DATA(lt_src) = VALUE ty_items( ( item_no = '030' material = 'M-03' qty = 1 ) ).

    DATA(lt_tgt) = VALUE ty_items( ( item_no = '010' material = 'M-01' qty = 5 )
                                   ( item_no = '020' material = 'M-02' qty = 7 ) ).

    " Default behaviour for tables: the target is DELETED first, then the
    " same number of lines as the source is inserted. Two rows become one.
    DATA(lt_a) = lt_tgt.
    MOVE-CORRESPONDING lt_src TO lt_a.
    WRITE: / 'MOVE-CORRESPONDING          lines =', lines( lt_a ), '(target wiped)'.

    " KEEPING TARGET LINES appends instead of replacing.
    DATA(lt_b) = lt_tgt.
    MOVE-CORRESPONDING lt_src TO lt_b KEEPING TARGET LINES.
    WRITE: / 'KEEPING TARGET LINES        lines =', lines( lt_b ), '(appended)'.

    " Asymmetry worth memorising: for TABLES the constructor expression is
    " the safe one. CORRESPONDING #( BASE ( ) ) is defined as
    " MOVE-CORRESPONDING ... KEEPING TARGET LINES, so it appends.
    DATA(lt_c) = lt_tgt.
    lt_c = CORRESPONDING #( BASE ( lt_c ) lt_src ).
    WRITE: / 'CORRESPONDING BASE ( )      lines =', lines( lt_c ), '(appended)'.

    " Without BASE ( ) it is a fresh table again - one line.
    DATA(lt_d) = lt_tgt.
    lt_d = CORRESPONDING #( lt_src ).
    WRITE: / 'CORRESPONDING #( ) no BASE  lines =', lines( lt_d ), '(replaced)'.
  ENDMETHOD.


  METHOD nested_table_is_replaced.
    DATA(ls_src) = build_source( ).          " 2 items

    DATA ls_tgt TYPE ty_tgt_head.
    ls_tgt-items = VALUE ty_items( ( item_no = '900' material = 'M-99' qty = 3 ) ).

    " ITEMS is a tabular component. Without DEEP the whole table body is
    " assigned in one go, so the existing target line is thrown away.
    DATA(ls_a) = ls_tgt.
    ls_a = CORRESPONDING #( BASE ( ls_a ) ls_src ).
    WRITE: / 'BASE ( ) only          items =', lines( ls_a-items ), '(nested replaced)'.

    " DEEP APPENDING ( ) resolves the nested table line by line and keeps
    " what was already there: 1 existing + 2 from the source = 3.
    DATA(ls_b) = ls_tgt.
    ls_b = CORRESPONDING #( DEEP APPENDING ( ls_b ) ls_src ).
    WRITE: / 'DEEP APPENDING ( )     items =', lines( ls_b-items ), '(nested merged)'.

    " Same effect with the classic statement.
    DATA(ls_c) = ls_tgt.
    MOVE-CORRESPONDING ls_src TO ls_c EXPANDING NESTED TABLES KEEPING TARGET LINES.
    WRITE: / 'EXPANDING NESTED TABLES items =', lines( ls_c-items ), '(nested merged)'.
  ENDMETHOD.


  METHOD duplicates_need_discarding.
    TYPES ty_unique_items TYPE HASHED TABLE OF ty_item
                          WITH UNIQUE KEY material.

    " Source deliberately holds the same material twice.
    DATA(lt_src) = VALUE ty_items( ( item_no = '010' material = 'M-01' qty = 5 )
                                   ( item_no = '020' material = 'M-01' qty = 7 )
                                   ( item_no = '030' material = 'M-02' qty = 9 ) ).

    DATA lt_unique TYPE ty_unique_items.

    " Unguarded, this raises CX_SY_ITAB_DUPLICATE_KEY at the second M-01.
    TRY.
        lt_unique = CORRESPONDING #( lt_src ).
        WRITE: / 'Unguarded: no exception, lines =', lines( lt_unique ).
      CATCH cx_sy_itab_duplicate_key INTO DATA(lx_dup).
        WRITE: / 'Unguarded: dumped ->', lx_dup->get_text( ).
    ENDTRY.

    " DISCARDING DUPLICATES keeps the FIRST line per key and silently drops
    " the rest. Convenient, but it is data loss - only use it when the
    " duplicates really are redundant, not when they should have been summed.
    CLEAR lt_unique.
    lt_unique = CORRESPONDING #( lt_src DISCARDING DUPLICATES ).
    WRITE: / 'DISCARDING DUPLICATES:   lines =', lines( lt_unique ),
           / '  M-01 kept qty =', lt_unique[ material = 'M-01' ]-qty,
             '(the 5, not the 7)'.
  ENDMETHOD.


  METHOD lookup_replaces_the_loop.
    TYPES: BEGIN OF ty_enriched,
             item_no  TYPE n LENGTH 3,
             material TYPE c LENGTH 18,
             qty      TYPE i,
             price    TYPE p LENGTH 8 DECIMALS 2,
           END OF ty_enriched,
           ty_enriched_tab TYPE STANDARD TABLE OF ty_enriched WITH EMPTY KEY.

    TYPES: BEGIN OF ty_price,
             material TYPE c LENGTH 18,
             price    TYPE p LENGTH 8 DECIMALS 2,
           END OF ty_price,
           " The lookup table MUST be sorted or hashed (or expose a
           " secondary key named with USING KEY) - the search runs on a
           " table key, never a linear scan.
           ty_price_tab TYPE HASHED TABLE OF ty_price
                        WITH UNIQUE KEY material.

    DATA(lt_items) = VALUE ty_enriched_tab(
                       ( item_no = '010' material = 'M-01' qty = 5 )
                       ( item_no = '020' material = 'M-02' qty = 7 )
                       ( item_no = '030' material = 'M-77' qty = 2 ) ).

    DATA(lt_prices) = VALUE ty_price_tab( ( material = 'M-01' price = '10.50' )
                                          ( material = 'M-02' price = '99.00' ) ).

    " One statement instead of LOOP AT ... READ TABLE ... MODIFY.
    " Left of the = is a column of lt_items, right of it a column of the
    " lookup table. Rows with no match (M-77) are carried over UNCHANGED -
    " they are not dropped, so this is a left outer join, not an inner one.
    lt_items = CORRESPONDING #( lt_items FROM lt_prices
                                USING material = material ).

    LOOP AT lt_items INTO DATA(ls_item).
      WRITE: / ls_item-item_no, ls_item-material, ls_item-qty, ls_item-price.
    ENDLOOP.

    WRITE: / '(M-77 has no lookup row - it survives with price 0.)'.
  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_corr_demo=>structure_target_is_wiped( ).
  SKIP.
  lcl_corr_demo=>table_target_is_wiped( ).
  SKIP.
  lcl_corr_demo=>nested_table_is_replaced( ).
  SKIP.
  lcl_corr_demo=>duplicates_need_discarding( ).
  SKIP.
  lcl_corr_demo=>lookup_replaces_the_loop( ).
