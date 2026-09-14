*&---------------------------------------------------------------------*
*& Report YDJ_ITAB_KEYS_DEMO
*&---------------------------------------------------------------------*
*& Internal table keys - what you get when you do not specify one, and
*& what a secondary key does and does not do for you.
*&
*&   1. STANDARD KEY      -> WITH DEFAULT KEY silently keys on EVERY
*&                           character-like component, so SORT itab.
*&                           sorts by all of them.
*&   2. EMPTY KEY         -> on a numeric-only line type the standard key
*&                           is empty: SORT does nothing and READ ... FROM
*&                           returns line 1 regardless of the key values.
*&   3. SECONDARY KEY     -> never chosen automatically; you must name it
*&                           with USING KEY / KEY ... COMPONENTS.
*&   4. MODIFICATION TRAP -> DELETE TABLE ... FROM wa always matches on
*&                           the PRIMARY key unless USING KEY is given.
*&
*& Runs on any system with the standard SFLIGHT demo data
*& (SAPBC_DATA_GENERATOR if SPFLI is empty).
*&---------------------------------------------------------------------*
REPORT ydj_itab_keys_demo.

CLASS lcl_key_demo DEFINITION.

  PUBLIC SECTION.

    " Numeric-only line type: the standard key has nothing to pick up,
    " so WITH DEFAULT KEY here yields an EMPTY key.
    TYPES: BEGIN OF ty_num,
             id     TYPE i,
             amount TYPE p LENGTH 8 DECIMALS 2,
           END OF ty_num,
           ty_nums TYPE STANDARD TABLE OF ty_num WITH DEFAULT KEY.

    " Same data, three different key setups.
    TYPES: ty_flights_default TYPE STANDARD TABLE OF spfli WITH DEFAULT KEY,
           ty_flights_keyed   TYPE STANDARD TABLE OF spfli
                                WITH NON-UNIQUE KEY carrid connid
                                WITH NON-UNIQUE SORTED KEY cities
                                     COMPONENTS cityfrom cityto
                                WITH UNIQUE HASHED KEY route
                                     COMPONENTS carrid connid.

    CLASS-METHODS:
      standard_key_is_everything,
      empty_key_is_a_no_op,
      secondary_key_must_be_named,
      delete_uses_the_primary_key.

ENDCLASS.


CLASS lcl_key_demo IMPLEMENTATION.

  METHOD standard_key_is_everything.
    " SPFLI is character-like almost everywhere, so the standard key is
    " CARRID CONNID COUNTRYFR CITYFROM AIRPFROM COUNTRYTO CITYTO AIRPTO
    " ... plus every other c/n field. FLTIME (type i) is NOT in it.
    DATA lt_flights TYPE ty_flights_default.

    SELECT * FROM spfli INTO TABLE lt_flights UP TO 20 ROWS.

    " No BY -> sorts by the primary key, i.e. by all of those fields.
    SORT lt_flights.

    " RTTI makes the implicit key visible - worth running once on your
    " own structures, the result is usually wider than expected.
    DATA(lo_tab) = CAST cl_abap_tabledescr(
                     cl_abap_typedescr=>describe_by_data( lt_flights ) ).

    WRITE: / 'Standard key components of SPFLI:'.
    LOOP AT lo_tab->key ASSIGNING FIELD-SYMBOL(<ls_key>).
      WRITE: / '  ', <ls_key>-name.
    ENDLOOP.

    " Say what you mean instead - faster, and readable at the call site.
    SORT lt_flights BY carrid connid.
  ENDMETHOD.

  METHOD empty_key_is_a_no_op.
    DATA(lt_nums) = VALUE ty_nums( ( id = 3 amount = '30.00' )
                                   ( id = 1 amount = '10.00' )
                                   ( id = 2 amount = '20.00' ) ).

    DATA(lt_before) = lt_nums.

    " ty_nums has only numeric components, so DEFAULT KEY = EMPTY key.
    " Sorting by a key with no components changes nothing. A direct
    " SORT lt_nums. raises a syntax warning because the emptiness is
    " statically known - the dynamic form shows the runtime behaviour.
    FIELD-SYMBOLS <lt_any> TYPE ANY TABLE.
    ASSIGN lt_nums TO <lt_any>.
    SORT <lt_any>.

    IF lt_nums = lt_before.
      WRITE: / 'SORT on an empty key: table unchanged (no error raised).'.
    ELSE.
      WRITE: / 'SORT on an empty key: table changed.'.
    ENDIF.

    " Same cause, worse symptom: nothing to compare, so line 1 comes back.
    DATA(ls_search) = VALUE ty_num( id = 2 ).
    READ TABLE lt_nums FROM ls_search USING KEY ('primary_key')
         INTO DATA(ls_hit).
    IF sy-subrc = 0.
      WRITE: / 'READ ... FROM id = 2 returned id =', ls_hit-id,
               '(the first line, not the match).'.
    ENDIF.

    " Note the same empty key arrives via inline SELECT targets:
    "   SELECT * FROM spfli INTO TABLE @DATA(lt) -> STANDARD, EMPTY KEY.
  ENDMETHOD.

  METHOD secondary_key_must_be_named.
    DATA lt_flights TYPE ty_flights_keyed.

    SELECT * FROM spfli INTO TABLE lt_flights.

    " NOT optimized: a free key on a standard table is a linear scan,
    " the CITIES key sitting in the declaration is simply not consulted.
    READ TABLE lt_flights WITH KEY cityfrom = 'FRANKFURT'
         INTO DATA(ls_slow).
    IF sy-subrc = 0.
      WRITE: / 'Free-key read (linear scan):', ls_slow-carrid, ls_slow-connid.
    ENDIF.

    " Optimized: the key is named, so the sorted secondary index is used.
    READ TABLE lt_flights WITH TABLE KEY cities
         COMPONENTS cityfrom = 'FRANKFURT' cityto = 'NEW YORK'
         INTO DATA(ls_fast).
    IF sy-subrc = 0.
      WRITE: / 'Secondary-key read (binary search):',
               ls_fast-carrid, ls_fast-connid.
    ENDIF.

    " Table-expression form of the same thing.
    TRY.
        DATA(ls_route) = lt_flights[ KEY route carrid = 'LH' connid = '0400' ].
        WRITE: / 'Hashed-key read:', ls_route-cityfrom, '->', ls_route-cityto.
      CATCH cx_sy_itab_line_not_found.
        WRITE: / 'LH 0400 not present in this system.'.
    ENDTRY.

    " LOOP restricted through the secondary index rather than scanning all.
    LOOP AT lt_flights ASSIGNING FIELD-SYMBOL(<ls_f>) USING KEY cities
         WHERE cityfrom = 'FRANKFURT'.
      " <ls_f>-cityfrom = 'X'.  "<- would dump: key field of the key in use
      <ls_f>-fltime = <ls_f>-fltime.   "non-key fields stay writable
    ENDLOOP.

    " Lazy update, worth knowing: CITIES is NON-UNIQUE, so its index is
    " built on this first keyed access, not during the SELECT above.
    " ROUTE is UNIQUE and was maintained on every insert instead.
  ENDMETHOD.

  METHOD delete_uses_the_primary_key.
    DATA lt_flights TYPE ty_flights_keyed.

    SELECT * FROM spfli INTO TABLE lt_flights.
    DATA(lv_before) = lines( lt_flights ).

    " Phase 1 - collect through the secondary key. Do NOT delete from the
    " table inside a loop that is itself driven by that key; take the
    " rows out first, then modify.
    DATA lt_doomed TYPE STANDARD TABLE OF spfli WITH EMPTY KEY.

    LOOP AT lt_flights INTO DATA(ls_row) USING KEY cities
         WHERE cityfrom = 'FRANKFURT'.
      APPEND ls_row TO lt_doomed.
    ENDLOOP.

    " Phase 2 - delete. THE TRAP: without USING KEY, DELETE TABLE ... FROM
    " matches on the PRIMARY key (here CARRID CONNID), not on the key the
    " row was read with. When the primary key is non-unique that removes a
    " different line than the one you selected, and sy-subrc is still 0.
    LOOP AT lt_doomed INTO ls_row.
      DELETE TABLE lt_flights FROM ls_row USING KEY cities.
    ENDLOOP.

    WRITE: / 'Rows before:', lv_before,
           / 'Rows after :', lines( lt_flights ).
  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_key_demo=>standard_key_is_everything( ).
  SKIP.
  lcl_key_demo=>empty_key_is_a_no_op( ).
  SKIP.
  lcl_key_demo=>secondary_key_must_be_named( ).
  SKIP.
  lcl_key_demo=>delete_uses_the_primary_key( ).
