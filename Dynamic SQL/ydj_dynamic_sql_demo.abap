*&---------------------------------------------------------------------*
*& Report YDJ_DYNAMIC_SQL_DEMO
*&---------------------------------------------------------------------*
*& Dynamic ABAP SQL tokens - (column_syntax), (source_syntax) and
*& (cond_syntax) - and the documented behaviours that make a generic
*& reader read more than it was asked to.
*&
*&   1. INITIAL TOKEN  -> an initial (cond_syntax) is TRUE and an initial
*&                        (column_syntax) becomes '*'. The filter that
*&                        came out empty reads the whole table.
*&   2. COMMENT CHARS  -> inside a dynamic token, a double quote comments
*&                        out the REST of the text and '*' comments out a
*&                        whole row. User input containing a quote
*&                        truncates the statement rather than corrupting
*&                        it.
*&   3. EXCEPTIONS     -> CX_SY_DYNAMIC_OSQL_SYNTAX is the development
*&                        failure; CX_SY_DYNAMIC_OSQL_SEMANTICS is the
*&                        production one. Catch the common superclass
*&                        CX_SY_DYNAMIC_OSQL_ERROR.
*&   4. INJECTION      -> naming a host variable in the token needs no
*&                        escaping at all; concatenating a value needs
*&                        CL_ABAP_DYN_PRG=>QUOTE.
*&   5. ALLOW-LIST     -> token syntax is case-INsensitive but the
*&                        allow-list comparison is not, so TO_UPPER( )
*&                        before CHECK_WHITELIST_TAB is load-bearing.
*&
*& The SELECT statements are COMMENTED OUT on purpose - this report
*& performs no database access. Only the token-building and validation
*& logic executes, which is where every one of these traps lives.
*&---------------------------------------------------------------------*
REPORT ydj_dynamic_sql_demo.

CLASS lcl_dynsql_demo DEFINITION.

  PUBLIC SECTION.
    CLASS-METHODS:
      initial_token_means_all,
      comment_char_truncates,
      exception_class_matters,
      host_variable_beats_quote,
      allow_list_needs_to_upper.

  PRIVATE SECTION.
    " Builds a WHERE token the way generic readers usually do:
    " one IF per optional restriction, and no ELSE.
    CLASS-METHODS build_where
      IMPORTING iv_carrid       TYPE c
      RETURNING VALUE(rv_where) TYPE string.

ENDCLASS.


CLASS lcl_dynsql_demo IMPLEMENTATION.

  METHOD build_where.
    IF iv_carrid IS NOT INITIAL.
      rv_where = |carrid = { cl_abap_dyn_prg=>quote( iv_carrid ) }|.
    ENDIF.
    " No ELSE. A blank carrid leaves rv_where initial.
  ENDMETHOD.


  METHOD initial_token_means_all.

    DATA lv_blank TYPE c LENGTH 3.

    WRITE: / '1. AN INITIAL TOKEN IS A WILDCARD, NOT AN ERROR'.

    DATA(lv_where_set)   = build_where( 'LH' ).
    DATA(lv_where_blank) = build_where( lv_blank ).

    WRITE: / '  restricted :', lv_where_set.

    IF lv_where_blank IS INITIAL.
      WRITE: / '  unrestricted: <initial>  ->  WHERE (token) is TRUE',
             / '                              every row is read'.
    ENDIF.

    " SELECT * FROM sflight WHERE (lv_where_blank) INTO TABLE @DATA(lt).
    "   ^ with an initial token this is SELECT * FROM sflight,
    "     no restriction, no syntax error, no warning.

    " Same rule on the column side: an initial (column_syntax) is
    " implicitly '*', so an empty column list reads ALL columns.
    DATA lt_columns TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    DATA(lv_cols)   = lines( lt_columns ).

    WRITE: / '  column list lines =', lv_cols,
             '-> select_list becomes ''*'''.

    " The guard the code above is missing.
    IF lv_where_blank IS INITIAL.
      WRITE: / '  guard: IF token IS INITIAL -> decide all rows or none'.
    ENDIF.

  ENDMETHOD.


  METHOD comment_char_truncates.

    WRITE: / '2. A COMMENT CHARACTER TRUNCATES A DYNAMIC TOKEN'.

    " A character-like token: everything from the first double quote on
    " is ignored. The literal below is built with backticks so the quote
    " character can appear inside it unambiguously.
    DATA(lv_token) = `carrid = 'LH' " AND connid = '0400'`.
    DATA(lv_len)   = strlen( lv_token ).
    DATA(lv_cut)   = find( val = lv_token sub = `"` ).

    WRITE: / '  token length      =', lv_len.
    WRITE: / '  comment starts at =', lv_cut.

    IF lv_cut >= 0.
      DATA(lv_effective) = lv_token(lv_cut).
      WRITE: / '  actually executed :', lv_effective.
      WRITE: / '  -> the connid restriction silently disappeared'.
    ENDIF.

    " An internal-table token: rows starting with * are dropped whole.
    DATA lt_token TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    lt_token = VALUE #( ( `* carrid, "commented row` )
                        ( `connid, "trailing comment` )
                        ( `cityfrom` ) ).

    DATA lv_live TYPE i.
    LOOP AT lt_token INTO DATA(lv_row).
      IF lv_row(1) <> '*'.
        lv_live = lv_live + 1.
      ENDIF.
    ENDLOOP.

    DATA(lv_rows) = lines( lt_token ).

    WRITE: / '  itab token rows   =', lv_rows,
             ' / rows honoured =', lv_live.

  ENDMETHOD.


  METHOD exception_class_matters.

    WRITE: / '3. CATCH THE SUPERCLASS, NOT JUST ...OSQL_SYNTAX'.

    WRITE: / '  CX_SY_DYNAMIC_OSQL_ERROR'.
    WRITE: / '   |-- CX_SY_DYNAMIC_OSQL_SYNTAX    (malformed text)'.
    WRITE: / '   |-- CX_SY_DYNAMIC_OSQL_SEMANTICS (column/table wrong)'.

    " TRY.
    "     SELECT (lv_cols) FROM (lv_table) WHERE (lv_where)
    "       INTO CORRESPONDING FIELDS OF TABLE @<lt_data>.
    "   CATCH cx_sy_dynamic_osql_error INTO DATA(lx_sql).
    "     MESSAGE lx_sql->get_text( ) TYPE 'I'.
    " ENDTRY.
    "
    " Catching only ...OSQL_SYNTAX passes the syntax tests during
    " development and dumps with SAPSQL_PARSE_ERROR on the system
    " where the column happens not to exist.

    WRITE: / '  -> CATCH cx_sy_dynamic_osql_error covers both'.

  ENDMETHOD.


  METHOD host_variable_beats_quote.

    DATA lv_input TYPE c LENGTH 30 VALUE 'LH'' OR CARRID <> ''LH'.

    WRITE: / '4. NAME THE VARIABLE INSTEAD OF PASTING THE VALUE'.

    " (a) concatenated raw - the classic injection.
    DATA(lv_raw) = |CARRID = '{ lv_input }'|.
    WRITE: / '  raw       :', lv_raw.

    " (b) concatenated through QUOTE - escaped and delimited.
    DATA(lv_quoted) = |CARRID = { cl_abap_dyn_prg=>quote( lv_input ) }|.
    WRITE: / '  quoted    :', lv_quoted.

    " (c) the value never enters the statement text at all.
    DATA(lv_hostvar) = `CARRID = @lv_input`.
    WRITE: / '  host var  :', lv_hostvar.
    WRITE: / '  -> (c) needs no escaping; prefer it when only the',
           / '     COLUMN is dynamic and the value is not.'.

    " SELECT SINGLE * FROM scarr WHERE (lv_hostvar) INTO @DATA(ls_carr).

  ENDMETHOD.


  METHOD allow_list_needs_to_upper.

    DATA lv_column TYPE c LENGTH 16 VALUE 'cityfrom'.

    WRITE: / '5. TOKEN SYNTAX IGNORES CASE - THE ALLOW-LIST DOES NOT'.

    DATA(lt_allowed) = VALUE string_hashed_table( ( `CITYFROM` )
                                                  ( `CITYTO` ) ).

    " Without TO_UPPER( ) this rejects input the SQL would have accepted.
    TRY.
        DATA(lv_bad) = cl_abap_dyn_prg=>check_whitelist_tab(
                         val       = lv_column
                         whitelist = lt_allowed ).
        WRITE: / '  without to_upper: accepted', lv_bad.
      CATCH cx_abap_not_in_whitelist.
        WRITE: / '  without to_upper: REJECTED (lower case)'.
    ENDTRY.

    TRY.
        DATA(lv_ok) = cl_abap_dyn_prg=>check_whitelist_tab(
                        val       = to_upper( lv_column )
                        whitelist = lt_allowed ).
        WRITE: / '  with    to_upper: accepted', lv_ok.
      CATCH cx_abap_not_in_whitelist.
        WRITE: / '  with    to_upper: REJECTED'.
    ENDTRY.

    " check_column_name validates SHAPE, not existence - it rejects
    " the injection below because it is not a valid name, but it would
    " accept any well-formed name that the table does not have.
    TRY.
        DATA(lv_inj) = cl_abap_dyn_prg=>check_column_name(
                         `CARRID <> value OR CARRID` ).
        WRITE: / '  injection accepted:', lv_inj.
      CATCH cx_abap_invalid_name.
        WRITE: / '  check_column_name: injection rejected'.
    ENDTRY.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_dynsql_demo=>initial_token_means_all( ).
  SKIP.
  lcl_dynsql_demo=>comment_char_truncates( ).
  SKIP.
  lcl_dynsql_demo=>exception_class_matters( ).
  SKIP.
  lcl_dynsql_demo=>host_variable_beats_quote( ).
  SKIP.
  lcl_dynsql_demo=>allow_list_needs_to_upper( ).
