*&---------------------------------------------------------------------*
*& Report YDJ_SORT_DEDUP_DEMO
*&---------------------------------------------------------------------*
*& SORT and DELETE ADJACENT DUPLICATES - the documented behaviours that
*& the surrounding code usually assumes away.
*&
*&   1. TWO-STAGE SORT -> SORT is UNSTABLE by default, so a second SORT
*&                        is entitled to discard the order the first one
*&                        established. STABLE, or one full key, is the fix.
*&   2. SY-SUBRC       -> DELETE ADJACENT DUPLICATES returns 4 when there
*&                        was nothing to delete. That is the NORMAL case,
*&                        not an error, and sy-tabix is not set at all.
*&   3. ADJACENT       -> duplicates that are not neighbours survive. An
*&                        unsorted table is deduplicated by coincidence.
*&   4. EMPTY KEY      -> with no COMPARING and an empty primary key, NO
*&                        lines are deleted and SORT does nothing either.
*&   5. USING KEY      -> a secondary sorted key supplies its own order,
*&                        so the preceding SORT stops mattering.
*&
*& Self-contained: literals only, no DDIC tables, no database access.
*&---------------------------------------------------------------------*
REPORT ydj_sort_dedup_demo.

TYPES: BEGIN OF ty_item,
         vbeln TYPE c LENGTH 10,
         posnr TYPE n LENGTH 6,
         matnr TYPE c LENGTH 8,
       END OF ty_item.

" EMPTY KEY is what SELECT ... INTO TABLE @DATA( ) gives you.
TYPES ty_items_empty TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY.

" Same line type, but with a secondary sorted key on matnr.
TYPES ty_items_seckey TYPE STANDARD TABLE OF ty_item
        WITH EMPTY KEY
        WITH NON-UNIQUE SORTED KEY mat COMPONENTS matnr.


CLASS lcl_sort_demo DEFINITION.

  PUBLIC SECTION.
    CLASS-METHODS:
      two_stage_sort,
      subrc_is_not_an_error,
      adjacent_is_the_contract,
      empty_key_deletes_nothing,
      using_key_overrides_sort.

  PRIVATE SECTION.
    CLASS-METHODS get_items RETURNING VALUE(rt_items) TYPE ty_items_empty.
    CLASS-METHODS dump      IMPORTING it_items TYPE ty_items_empty.

ENDCLASS.


CLASS lcl_sort_demo IMPLEMENTATION.

  METHOD get_items.
    " Deliberately NOT in key order: two documents interleaved, and the
    " same matnr appearing in non-adjacent rows.
    rt_items = VALUE #(
      ( vbeln = '0000004711' posnr = '000020' matnr = 'M-01' )
      ( vbeln = '0000004712' posnr = '000010' matnr = 'M-02' )
      ( vbeln = '0000004711' posnr = '000010' matnr = 'M-01' )
      ( vbeln = '0000004712' posnr = '000020' matnr = 'M-01' )
      ( vbeln = '0000004711' posnr = '000030' matnr = 'M-02' ) ).
  ENDMETHOD.


  METHOD dump.
    LOOP AT it_items ASSIGNING FIELD-SYMBOL(<ls_item>).
      WRITE: / '    ', <ls_item>-vbeln, <ls_item>-posnr, <ls_item>-matnr.
    ENDLOOP.
  ENDMETHOD.


  METHOD two_stage_sort.
    WRITE: / '--- 1. the two-stage sort ---'.

    DATA(lt_a) = get_items( ).

    " The intent is "by document, and by item within document". It is not
    " expressed anywhere: after the second SORT, rows that TIE on vbeln
    " have no defined relative order, so the posnr ordering the first
    " SORT produced may or may not survive. The docs allow this to differ
    " per platform AND between two runs of the same code.
    SORT lt_a BY posnr.
    SORT lt_a BY vbeln.

    WRITE: / '  two SORTs (posnr order is not guaranteed to survive):'.
    dump( lt_a ).

    " Fix A - say the whole key in one statement. Always prefer this.
    DATA(lt_b) = get_items( ).
    SORT lt_b BY vbeln posnr.
    WRITE: / '  SORT BY vbeln posnr (deterministic):'.
    dump( lt_b ).

    " Fix B - when the secondary criterion cannot be expressed as a key
    " (it came from the database ORDER BY, or from insertion sequence),
    " STABLE preserves the relative order of tied rows.
    DATA(lt_c) = get_items( ).
    SORT lt_c BY posnr.
    SORT lt_c STABLE BY vbeln.
    WRITE: / '  SORT BY posnr then STABLE BY vbeln (also deterministic):'.
    dump( lt_c ).
  ENDMETHOD.


  METHOD subrc_is_not_an_error.
    DATA lv_subrc TYPE i.
    DATA lv_lines TYPE i.

    WRITE: / '--- 2. sy-subrc = 4 is the normal case ---'.

    " A table that is already clean: every vbeln/posnr pair is distinct.
    DATA(lt_clean) = get_items( ).
    SORT lt_clean BY vbeln posnr.

    DELETE ADJACENT DUPLICATES FROM lt_clean COMPARING vbeln posnr.
    " Captured IMMEDIATELY - any intervening statement would overwrite it.
    lv_subrc = sy-subrc.
    lv_lines = lines( lt_clean ).

    WRITE: / '  clean table  : sy-subrc =', lv_subrc,
             'lines =', lv_lines.
    IF lv_subrc = 4.
      WRITE: / '  -> 4 means NOTHING NEEDED DELETING. Nothing failed.'.
    ENDIF.

    " The same statement on a table that does contain duplicates.
    DATA(lt_dupes) = get_items( ).
    SORT lt_dupes BY matnr.

    DELETE ADJACENT DUPLICATES FROM lt_dupes COMPARING matnr.
    lv_subrc = sy-subrc.
    lv_lines = lines( lt_dupes ).

    WRITE: / '  with dupes   : sy-subrc =', lv_subrc,
             'lines =', lv_lines.

    " sy-tabix is NOT set by DELETE. Reading it here returns whatever the
    " last statement that did set it left behind - it is not a position
    " in the table and must never be used as one.
  ENDMETHOD.


  METHOD adjacent_is_the_contract.
    DATA lv_before TYPE i.
    DATA lv_after  TYPE i.

    WRITE: / '--- 3. ADJACENT means adjacent ---'.

    " NO SORT. matnr M-01 appears in rows 1, 4 and M-02 in rows 2, 5 -
    " never as neighbours, so nothing at all is removed.
    DATA(lt_unsorted) = get_items( ).
    lv_before = lines( lt_unsorted ).
    DELETE ADJACENT DUPLICATES FROM lt_unsorted COMPARING matnr.
    lv_after = lines( lt_unsorted ).

    WRITE: / '  unsorted : before', lv_before, '-> after', lv_after,
             '(duplicates survive)'.

    " Same data, same statement, sorted first by the SAME component the
    " COMPARING clause names. That prerequisite is the entire contract
    " and nothing in the system enforces it.
    DATA(lt_sorted) = get_items( ).
    lv_before = lines( lt_sorted ).
    SORT lt_sorted BY matnr.
    DELETE ADJACENT DUPLICATES FROM lt_sorted COMPARING matnr.
    lv_after = lines( lt_sorted ).

    WRITE: / '  sorted   : before', lv_before, '-> after', lv_after,
             '(one row per matnr)'.
    dump( lt_sorted ).
  ENDMETHOD.


  METHOD empty_key_deletes_nothing.
    DATA lv_before TYPE i.
    DATA lv_after  TYPE i.

    WRITE: / '--- 4. no COMPARING + empty primary key ---'.

    " lt_empty has WITH EMPTY KEY, exactly like a table created by
    " SELECT ... INTO TABLE @DATA(lt_x). Its primary key has no fields.
    DATA(lt_empty) = get_items( ).

    " SORT without BY sorts by the primary table key. That key is empty,
    " so no sort takes place - the table comes back untouched.
    SORT lt_empty.

    " And with no COMPARING the groups come from that same empty key, so
    " the documented outcome is that NO lines are deleted. Both statements
    " are complete no-ops, and neither says so.
    " Because the emptiness of the key is known statically here, the
    " syntax check does flag both statements with a warning - that
    " warning is the only signal you ever get, and it disappears the
    " moment the table type is only known at runtime.
    lv_before = lines( lt_empty ).
    DELETE ADJACENT DUPLICATES FROM lt_empty.
    lv_after = lines( lt_empty ).

    WRITE: / '  empty key, no COMPARING : before', lv_before,
             '-> after', lv_after, '(no-op)'.

    " The explicit form does what was meant. COMPARING ALL FIELDS is the
    " whole-row variant; COMPARING table_line has the same effect.
    DATA(lt_named) = get_items( ).
    SORT lt_named BY matnr.
    lv_before = lines( lt_named ).
    DELETE ADJACENT DUPLICATES FROM lt_named COMPARING matnr.
    lv_after = lines( lt_named ).

    WRITE: / '  explicit COMPARING matnr : before', lv_before,
             '-> after', lv_after.
  ENDMETHOD.


  METHOD using_key_overrides_sort.
    DATA lt_seckey TYPE ty_items_seckey.
    DATA lv_after  TYPE i.

    WRITE: / '--- 5. USING KEY supplies its own order ---'.

    lt_seckey = VALUE #(
      ( vbeln = '0000004711' posnr = '000020' matnr = 'M-01' )
      ( vbeln = '0000004712' posnr = '000010' matnr = 'M-02' )
      ( vbeln = '0000004711' posnr = '000010' matnr = 'M-01' )
      ( vbeln = '0000004712' posnr = '000020' matnr = 'M-01' )
      ( vbeln = '0000004711' posnr = '000030' matnr = 'M-02' ) ).

    " The secondary SORTED key 'mat' maintains its own index on matnr, so
    " the rows are visited in matnr order regardless of the primary index
    " - no SORT is needed, and any SORT done beforehand is irrelevant to
    " this statement. Secondary keys can never be used as SORT keys, but
    " they CAN be used here.
    DELETE ADJACENT DUPLICATES FROM lt_seckey USING KEY mat COMPARING matnr.
    lv_after = lines( lt_seckey ).

    WRITE: / '  USING KEY mat : lines after =', lv_after,
             '(deduplicated without any SORT)'.
  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_sort_demo=>two_stage_sort( ).
  SKIP.
  lcl_sort_demo=>subrc_is_not_an_error( ).
  SKIP.
  lcl_sort_demo=>adjacent_is_the_contract( ).
  SKIP.
  lcl_sort_demo=>empty_key_deletes_nothing( ).
  SKIP.
  lcl_sort_demo=>using_key_overrides_sort( ).
