*&---------------------------------------------------------------------*
*& Report YDJ_ADBC_DEMO
*&---------------------------------------------------------------------*
*& Native SQL through ADBC (CL_SQL_STATEMENT / CL_SQL_RESULT_SET) - the
*& three guarantees you lose the moment the statement becomes a string.
*&
*&   1. BASELINE          -> ? placeholders, SET_PARAM_STRUCT, and the
*&                           CLOSE that releases the database cursor.
*&   2. NO CLIENT         -> Native SQL does not add a client predicate.
*&                           Without one, every client is readable.
*&   3. PLACEHOLDER       -> ? + SET_PARAM vs concatenation. Concatenated
*&                           input must go through CL_ABAP_DYN_PRG.
*&   4. NEXT_PACKAGE      -> appends to the target WITHOUT clearing it,
*&                           so it is not a memory guard on its own.
*&   5. BINDING DISCARDED -> the binding is removed after every execute;
*&                           reusing a statement means re-binding.
*&   6. TRUNCATION        -> a NUMC column into a too-short field is cut
*&                           on the LEFT by ABAP SQL and on the RIGHT by
*&                           Native SQL. Same row, different answer.
*&   7. CONNECTIONS       -> one LUW per connection. Explained only, NOT
*&                           executed: the failure mode is a work process
*&                           deadlocked against itself.
*&
*& Read-only: SELECTs only. No INSERT/UPDATE/DELETE, no DDL, no COMMIT,
*& no ROLLBACK, and no secondary connection is opened. Runs on any system
*& with the standard flight demo data (SAPBC_DATA_GENERATOR if SCARR /
*& SPFLI are empty).
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENADBC.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENADBC_QUERY.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENNATIVE_SQL_TYPE_MAPPING.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDB_CONNECTIONS_TRANS.html
*&---------------------------------------------------------------------*
REPORT ydj_adbc_demo.


CLASS lcl_adbc_demo DEFINITION.

  PUBLIC SECTION.

    CONSTANTS:
      gc_carrid   TYPE spfli-carrid VALUE 'LH',
      gc_connid   TYPE spfli-connid VALUE '0017',
      gc_pkg_size TYPE i VALUE 3.

    CLASS-METHODS:
      baseline_query,
      no_client_handling,
      placeholder_vs_quote,
      next_package_appends,
      binding_is_discarded,
      numc_truncation,
      connections_and_luws.

  PRIVATE SECTION.

    TYPES:
      BEGIN OF ty_carrier,
        carrid   TYPE scarr-carrid,
        carrname TYPE scarr-carrname,
      END OF ty_carrier,
      ty_carriers TYPE STANDARD TABLE OF ty_carrier WITH EMPTY KEY.

ENDCLASS.


CLASS lcl_adbc_demo IMPLEMENTATION.

  METHOD baseline_query.

    " The client predicate is written by hand - see section 2 for why.
    " Both values are bound to ? placeholders rather than concatenated.
    DATA ls_carrier TYPE ty_carrier.
    DATA lv_carrid  TYPE scarr-carrid.

    lv_carrid = gc_carrid.

    WRITE: / '--- 1. Baseline ADBC query (standard connection) ---'.

    TRY.
        DATA(lo_stmt) = NEW cl_sql_statement( ).

        " "must be called exactly once for each placeholder ?", and the
        " order of the calls is the order of the ? from left to right.
        lo_stmt->set_param( REF #( sy-mandt ) ).
        lo_stmt->set_param( REF #( lv_carrid ) ).

        DATA(lo_result) = lo_stmt->execute_query(
          `SELECT carrid, carrname FROM scarr ` &&
          ` WHERE mandt = ? AND carrid = ?` ).

        " The structure binds to the select list positionally, so the
        " column order in the statement - not in the DDIC - is what
        " matters here.
        lo_result->set_param_struct( struct_ref = REF #( ls_carrier ) ).

        DATA(lv_hits) = lo_result->next( ).

        " An open result set is an open database cursor. Closing it is
        " not optional housekeeping - see ../Mass Data Processing.
        lo_result->close( ).

        IF lv_hits > 0.
          WRITE: / 'carrier:', ls_carrier-carrid, ls_carrier-carrname.
        ELSE.
          WRITE: / 'no row for carrier', lv_carrid.
        ENDIF.

      CATCH cx_sql_exception INTO DATA(lx_sql).
        DATA(lv_text) = lx_sql->get_text( ).
        WRITE: / 'SQL error:', lv_text.
    ENDTRY.

  ENDMETHOD.

  METHOD no_client_handling.

    " ABAP SQL would restrict this to sy-mandt automatically. ADBC does
    " not: "Native SQL does not support implicit client handling."
    " Counting the DISTINCT clients visible from one query is a safe way
    " to show it - if this prints more than 1, the same query shape in a
    " report would have been reading other clients' data all along.
    DATA lv_client   TYPE scarr-mandt.
    DATA lt_clients  TYPE STANDARD TABLE OF scarr-mandt WITH EMPTY KEY.

    WRITE: / '--- 2. No implicit client handling ---'.

    TRY.
        DATA(lo_result) = NEW cl_sql_statement( )->execute_query(
          `SELECT DISTINCT mandt FROM scarr` ).

        lo_result->set_param( REF #( lv_client ) ).

        WHILE lo_result->next( ) > 0.
          APPEND lv_client TO lt_clients.
        ENDWHILE.

        lo_result->close( ).

      CATCH cx_sql_exception INTO DATA(lx_sql).
        DATA(lv_text) = lx_sql->get_text( ).
        WRITE: / 'SQL error:', lv_text.
        RETURN.
    ENDTRY.

    DATA(lv_count) = lines( lt_clients ).

    WRITE: / 'current client   :', sy-mandt.
    WRITE: / 'clients reachable:', lv_count.

    LOOP AT lt_clients INTO DATA(lv_row).
      WRITE: / '  visible client:', lv_row.
    ENDLOOP.

    IF lv_count > 1.
      WRITE: / 'The query carried no client predicate and read them all.'.
    ELSE.
      WRITE: / 'Only one client has data here - the bug would be silent.'.
    ENDIF.

  ENDMETHOD.

  METHOD placeholder_vs_quote.

    " Same result, two risk profiles. The placeholder form never lets the
    " value become syntax. The quote( ) form is the fallback for the rare
    " position where a placeholder is not allowed; it "also adds
    " quotation marks at the start and at the end", so the literal must
    " NOT be pre-quoted in the string.
    DATA lv_input   TYPE string.
    DATA lv_carrid  TYPE scarr-carrid.
    DATA lv_name_a  TYPE scarr-carrname.
    DATA lv_name_b  TYPE scarr-carrname.

    lv_input  = gc_carrid.
    lv_carrid = gc_carrid.

    WRITE: / '--- 3. ? placeholder vs escaped concatenation ---'.

    TRY.
        DATA(lo_stmt) = NEW cl_sql_statement( ).
        lo_stmt->set_param( REF #( sy-mandt ) ).
        lo_stmt->set_param( REF #( lv_carrid ) ).

        DATA(lo_res_a) = lo_stmt->execute_query(
          `SELECT carrname FROM scarr WHERE mandt = ? AND carrid = ?` ).
        lo_res_a->set_param( REF #( lv_name_a ) ).
        lo_res_a->next( ).
        lo_res_a->close( ).

        DATA(lv_escaped) = cl_abap_dyn_prg=>quote( to_upper( lv_input ) ).
        DATA(lv_client)  = cl_abap_dyn_prg=>quote( CONV string( sy-mandt ) ).

        DATA(lo_res_b) = NEW cl_sql_statement( )->execute_query(
          `SELECT carrname FROM scarr WHERE mandt = ` && lv_client &&
          ` AND carrid = ` && lv_escaped ).
        lo_res_b->set_param( REF #( lv_name_b ) ).
        lo_res_b->next( ).
        lo_res_b->close( ).

      CATCH cx_sql_exception INTO DATA(lx_sql).
        DATA(lv_text) = lx_sql->get_text( ).
        WRITE: / 'SQL error:', lv_text.
        RETURN.
    ENDTRY.

    WRITE: / 'via ? placeholder:', lv_name_a.
    WRITE: / 'via quote( )     :', lv_name_b.
    WRITE: / 'Prefer the first. The second is only for positions where a'.
    WRITE: / 'placeholder is not possible - never for a bare value.'.

  ENDMETHOD.

  METHOD next_package_appends.

    " "In each call of NEXT_PACKAGE, the rows read are appended to the
    " internal table without deleting the previous content" - the same
    " shape as APPENDING ... PACKAGE SIZE in ABAP SQL. The target grows.
    DATA lt_carriers TYPE ty_carriers.

    WRITE: / '--- 4. NEXT_PACKAGE appends, it does not clear ---'.

    TRY.
        DATA(lo_result) = NEW cl_sql_statement( )->execute_query(
          `SELECT carrid, carrname FROM scarr ` &&
          ` WHERE mandt = '` && sy-mandt && `' ORDER BY carrid` ).

        lo_result->set_param_table( itab_ref = REF #( lt_carriers ) ).

        DATA(lv_got_1) = lo_result->next_package( upto = gc_pkg_size ).
        DATA(lv_after_1) = lines( lt_carriers ).

        DATA(lv_got_2) = lo_result->next_package( upto = gc_pkg_size ).
        DATA(lv_after_2) = lines( lt_carriers ).

        lo_result->close( ).

      CATCH cx_sql_exception INTO DATA(lx_sql).
        DATA(lv_text) = lx_sql->get_text( ).
        WRITE: / 'SQL error:', lv_text.
        RETURN.
    ENDTRY.

    WRITE: / 'package 1 returned', lv_got_1, '-> table holds', lv_after_1.
    WRITE: / 'package 2 returned', lv_got_2, '-> table holds', lv_after_2.
    WRITE: / 'The second package did not replace the first. To chunk for'.
    WRITE: / 'memory, CLEAR the target between packages yourself.'.

  ENDMETHOD.

  METHOD binding_is_discarded.

    " "After each SQL statement is executed, the binding is removed."
    " Reusing the statement object is fine; reusing the binding is not.
    DATA lv_carrid TYPE scarr-carrid.
    DATA lv_name   TYPE scarr-carrname.
    DATA lv_second TYPE scarr-carrname.

    lv_carrid = gc_carrid.

    WRITE: / '--- 5. The binding is removed after every execute ---'.

    TRY.
        DATA(lo_stmt) = NEW cl_sql_statement( ).

        lo_stmt->set_param( REF #( sy-mandt ) ).
        lo_stmt->set_param( REF #( lv_carrid ) ).
        DATA(lo_res_1) = lo_stmt->execute_query(
          `SELECT carrname FROM scarr WHERE mandt = ? AND carrid = ?` ).
        lo_res_1->set_param( REF #( lv_name ) ).
        lo_res_1->next( ).
        lo_res_1->close( ).

        " Both placeholders must be bound again here. Leaving these two
        " lines out does not reuse the previous values - the statement
        " has no bindings left at all.
        lo_stmt->set_param( REF #( sy-mandt ) ).
        lo_stmt->set_param( REF #( lv_carrid ) ).
        DATA(lo_res_2) = lo_stmt->execute_query(
          `SELECT carrname FROM scarr WHERE mandt = ? AND carrid = ?` ).
        lo_res_2->set_param( REF #( lv_second ) ).
        lo_res_2->next( ).
        lo_res_2->close( ).

      CATCH cx_sql_exception INTO DATA(lx_sql).
        DATA(lv_text) = lx_sql->get_text( ).
        WRITE: / 'SQL error:', lv_text.
        RETURN.
    ENDTRY.

    WRITE: / 'first execute :', lv_name.
    WRITE: / 'second execute:', lv_second.

  ENDMETHOD.

  METHOD numc_truncation.

    " The headline. SPFLI-CONNID is NUMC(4), so a stored '0017' is
    " left-padded. Read into a field that is two characters too short:
    "
    "   ABAP SQL   "passes the data right-aligned and truncated on the
    "              left"                       -> the digits survive
    "   Native SQL cuts on the right            -> the padding survives
    "
    " No exception, no sy-subrc, no warning. The documented result on an
    " SAP HANA database for the equivalent case is 00123 vs 00000.
    DATA lv_carrid TYPE spfli-carrid.
    DATA lv_connid TYPE spfli-connid.
    DATA lv_abap   TYPE n LENGTH 2.
    DATA lv_native TYPE n LENGTH 2.

    lv_carrid = gc_carrid.
    lv_connid = gc_connid.

    WRITE: / '--- 6. Same column, opposite truncation ---'.

    " Fully qualified key, so both reads address the same row. A bare
    " SELECT SINGLE without a complete key is not deterministic - see
    " ../Row Limiting and Ordering.
    SELECT SINGLE connid FROM spfli
      WHERE carrid = @lv_carrid AND connid = @lv_connid
      INTO @lv_abap.

    IF sy-subrc <> 0.
      WRITE: / 'no SPFLI row for', lv_carrid, lv_connid,
               '- load the flight demo data first.'.
      RETURN.
    ENDIF.

    TRY.
        DATA(lo_stmt) = NEW cl_sql_statement( ).
        lo_stmt->set_param( REF #( sy-mandt ) ).
        lo_stmt->set_param( REF #( lv_carrid ) ).
        lo_stmt->set_param( REF #( lv_connid ) ).

        DATA(lo_result) = lo_stmt->execute_query(
          `SELECT connid FROM spfli ` &&
          ` WHERE mandt = ? AND carrid = ? AND connid = ?` ).

        lo_result->set_param( REF #( lv_native ) ).
        lo_result->next( ).
        lo_result->close( ).

      CATCH cx_sql_exception INTO DATA(lx_sql).
        DATA(lv_text) = lx_sql->get_text( ).
        WRITE: / 'SQL error:', lv_text.
        RETURN.
    ENDTRY.

    WRITE: / 'stored value      :', lv_connid.
    WRITE: / 'ABAP SQL   into n2:', lv_abap.
    WRITE: / 'Native SQL into n2:', lv_native.
    WRITE: / 'Bind matching types. n, d, t and decimal floating point'.
    WRITE: / 'numbers are the ones that bite.'.

  ENDMETHOD.

  METHOD connections_and_luws.

    " Explained, deliberately NOT executed. Opening a second connection
    " and touching a row already changed on the first one deadlocks the
    " work process against itself, and for a background job that has to
    " be cleared by hand.
    "
    " The shape of the problem:
    "
    "   DATA(lo_con) = cl_sql_connection=>get_abap_connection( `R/3*LOG` ).
    "   DATA(lo_log) = NEW cl_sql_statement( con_ref = lo_con ).
    "   ... write the audit row on lo_con ...
    "   lo_con->commit( ).              " this connection only
    "   lo_con->close_no_disconnect( ). " AFTER the commit, never before
    "
    " Four rules behind those five lines:
    "
    "   a) COMMIT WORK acts on ALL active connections, not just the
    "      standard one. COMMIT CONNECTION and CL_SQL_CONNECTION->COMMIT
    "      are the per-connection switches.
    "   b) CLOSE and CLOSE_NO_DISCONNECT both end the LUW with a
    "      ROLLBACK, discarding anything not yet committed - and both are
    "      silently IGNORED on the standard connection, so the same line
    "      loses data on one connection and does nothing on the other.
    "   c) Never pass COMMIT or ROLLBACK to CL_SQL_STATEMENT: they "are
    "      not detected by the database interface", so the work it owes
    "      the end of the transaction never happens.
    "   d) Connection names are uppercased by ABAP SQL but are
    "      case-sensitive in Native SQL. `R/3*log` in ADBC and
    "      CONNECTION 'R/3*LOG' in ABAP SQL are two connections, two
    "      LUWs, and a lock situation if they touch the same row.
    WRITE: / '--- 7. One LUW per connection (explanation only) ---'.
    WRITE: / 'Nothing is executed here - see the comments in the source'.
    WRITE: / 'and the README. Opening a second connection to the same'.
    WRITE: / 'rows can hang the work process with no second user'.
    WRITE: / 'involved, and a background job must then be killed by hand.'.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_adbc_demo=>baseline_query( ).
  SKIP.
  lcl_adbc_demo=>no_client_handling( ).
  SKIP.
  lcl_adbc_demo=>placeholder_vs_quote( ).
  SKIP.
  lcl_adbc_demo=>next_package_appends( ).
  SKIP.
  lcl_adbc_demo=>binding_is_discarded( ).
  SKIP.
  lcl_adbc_demo=>numc_truncation( ).
  SKIP.
  lcl_adbc_demo=>connections_and_luws( ).
