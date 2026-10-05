*&---------------------------------------------------------------------*
*& Report YDJ_CTE_DEMO
*&---------------------------------------------------------------------*
*& Common table expressions (WITH ... +cte AS ( ... ) SELECT ...) - the
*& temporary result set that lives for exactly one ABAP SQL statement.
*&
*&   1. AGGREGATE FIRST     -> aggregate in a CTE, then join. The join
*&                             cannot fan out, because the CTE already
*&                             has one row per key.
*&   2. CHAINED CTEs        -> a CTE may read CTEs defined ABOVE it only.
*&                             No self-reference, so no recursion; and an
*&                             UNUSED CTE is a syntax error.
*&   3. ENDWITH             -> a work-area target opens a SELECT loop,
*&                             closed by ENDWITH, not ENDSELECT.
*&   4. NAME LIST           -> +cte( a, b, c ) renames positionally and
*&                             OVERWRITES the AS aliases. All or nothing.
*&   5. CTE AS SUBQUERY     -> SELECT FROM subquery is not possible in
*&                             ABAP SQL; a CTE is the documented way.
*&   6. ORDER BY IN A CTE   -> not supported by every database. Guarded
*&                             with CL_ABAP_DBFEATURES and TRY/CATCH.
*&   7. CLIENT COLUMN       -> mandt selected into a CTE is an ORDINARY
*&                             column. The CTE is client-INDEPENDENT, so
*&                             USING is refused on it.
*&   8. DYNAMIC FORM        -> WITH (select_syntax) carries the MAIN
*&                             QUERY ONLY - never CTE definitions.
*&
*& Read-only: 8 SELECTs, no writes, no COMMIT. Runs on any system with
*& the standard flight demo data (SAPBC_DATA_GENERATOR if SCARR / SPFLI /
*& SFLIGHT are empty).
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWITH.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWITH_SUBQUERY.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWITH_MAINQUERY.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_DECLARE_CLIENT.html
*&---------------------------------------------------------------------*
REPORT ydj_cte_demo.


CLASS lcl_cte_demo DEFINITION.

  PUBLIC SECTION.

    CONSTANTS:
      gc_carrid    TYPE spfli-carrid VALUE 'LH',
      gc_min_seats TYPE sflight-seatsmax VALUE 200,
      gc_max_rows  TYPE i VALUE 5.

    CLASS-METHODS:
      aggregate_first,
      chained_ctes,
      loop_with_endwith,
      name_list,
      cte_as_subquery,
      order_by_in_cte,
      client_column,
      dynamic_form.

ENDCLASS.


CLASS lcl_cte_demo IMPLEMENTATION.

  METHOD aggregate_first.

    " The CTE produces one row per carrid/connid, so joining it to SPFLI
    " cannot multiply rows. Doing the SUM after the join instead would
    " count every seat once per matching SPFLI row - see ../SQL Joins.
    WITH
      +seats AS ( SELECT FROM sflight
                    FIELDS carrid, connid, SUM( seatsocc ) AS occupied
                    GROUP BY carrid, connid )
      SELECT FROM spfli AS p
             INNER JOIN +seats AS s ON s~carrid = p~carrid
                                   AND s~connid = p~connid
        FIELDS p~carrid, p~connid, p~cityfrom, p~cityto, s~occupied
        WHERE p~carrid = @gc_carrid
        ORDER BY p~connid
        INTO TABLE @DATA(lt_flights)
        UP TO @gc_max_rows ROWS.

    DATA(lv_rows) = lines( lt_flights ).

    WRITE: / '--- 1. Aggregate in a CTE, then join (no fan-out) ---'.
    WRITE: / 'rows:', lv_rows.
    LOOP AT lt_flights INTO DATA(ls_flight).
      WRITE: / ls_flight-carrid,
               ls_flight-connid,
               ls_flight-cityfrom,
               ls_flight-cityto,
               ls_flight-occupied.
    ENDLOOP.

  ENDMETHOD.

  METHOD chained_ctes.

    " +counted reads +big, which is defined above it. That is the only
    " direction allowed: a CTE "cannot be used in its own subquery or in
    " the subqueries of preceding definitions". No self-reference means
    " there is no recursive CTE in ABAP SQL - the documented alternative
    " is the hierarchy addition.
    WITH
      +big AS ( SELECT FROM sflight
                  FIELDS carrid, connid, seatsmax
                  WHERE seatsmax >= @gc_min_seats ),
      +counted AS ( SELECT FROM +big
                      FIELDS carrid, COUNT( * ) AS cnt
                      GROUP BY carrid )
      SELECT FROM +counted AS c
             INNER JOIN scarr AS s ON s~carrid = c~carrid
        FIELDS s~carrid, s~carrname, c~cnt
        ORDER BY c~cnt DESCENDING, s~carrid
        INTO TABLE @DATA(lt_counts)
        UP TO @gc_max_rows ROWS.

    DATA(lv_rows) = lines( lt_counts ).

    WRITE: / '--- 2. Chained CTEs: +counted reads +big ---'.
    WRITE: / 'carriers with large-aircraft flights:', lv_rows.
    LOOP AT lt_counts INTO DATA(ls_count).
      WRITE: / ls_count-carrid, ls_count-carrname, ls_count-cnt.
    ENDLOOP.

    " Each of the following would be a SYNTAX ERROR, not a runtime
    " problem - which is why they are comments and not code:
    "
    "   +big AS ( SELECT FROM +counted ... )   forward reference
    "   +big AS ( SELECT FROM +big ... )       self-reference
    "
    " and so would DELETING the join above while leaving +counted
    " defined, because every CTE "must be used at least once within the
    " WITH statement", and the main query must read at least one of them.
    WRITE: / 'unused CTE / forward reference / self-reference:'.
    WRITE: / 'all three are syntax errors, never runtime errors.'.

  ENDMETHOD.

  METHOD loop_with_endwith.

    " INTO a work area, not INTO TABLE, so a SELECT loop is opened. The
    " terminator is ENDWITH; ENDSELECT does not close a WITH statement.
    WRITE: / '--- 3. Work-area target opens a loop: ENDWITH ---'.

    WITH
      +carriers AS ( SELECT FROM scarr
                       FIELDS carrid, carrname, currcode )
      SELECT FROM +carriers AS c
        FIELDS c~carrid, c~carrname, c~currcode
        ORDER BY c~carrid
        INTO @DATA(ls_carrier)
        UP TO 3 ROWS.

      WRITE: / ls_carrier-carrid, ls_carrier-carrname, ls_carrier-currcode.

    ENDWITH.

    WRITE: / 'INTO TABLE @lt_x needs no terminator; INTO @ls_x does.'.

  ENDMETHOD.

  METHOD name_list.

    " The name list is positional and OVERWRITES the AS aliases below:
    " the columns arrive as carrier/flights/seats, not as c/n/s. It must
    " name EVERY column - a partial list is a syntax error - and the
    " blanks inside the parentheses are mandatory.
    WITH
      +stats( carrier, flights, seats ) AS (
        SELECT FROM sflight
          FIELDS carrid AS c, COUNT( * ) AS n, SUM( seatsocc ) AS s
          GROUP BY carrid )
      SELECT FROM +stats AS t
        FIELDS t~carrier, t~flights, t~seats
        ORDER BY t~carrier
        INTO TABLE @DATA(lt_stats)
        UP TO @gc_max_rows ROWS.

    WRITE: / '--- 4. Name list overwrites the AS aliases ---'.
    LOOP AT lt_stats INTO DATA(ls_stat).
      WRITE: / ls_stat-carrier, ls_stat-flights, ls_stat-seats.
    ENDLOOP.

    " Legal but fragile: a name list over a SELECT list of *. Appending
    " one field to the data source later turns this into a syntax error
    " in a program nobody edited.
    WRITE: / 'a name list over SELECT * breaks when the table grows.'.

  ENDMETHOD.

  METHOD cte_as_subquery.

    " SELECT FROM ( SELECT ... ) does not exist in ABAP SQL. A CTE is the
    " documented substitute, and it can be read from a WHERE subquery as
    " well as from a FROM clause.
    WITH
      +served AS ( SELECT FROM spfli
                     FIELDS cityfrom AS city
                     WHERE carrid = @gc_carrid )
      SELECT FROM spfli AS p
        FIELDS p~carrid, p~connid, p~cityfrom
        WHERE p~cityfrom IN ( SELECT city FROM +served )
          AND p~carrid <> @gc_carrid
        ORDER BY p~carrid, p~connid
        INTO TABLE @DATA(lt_others)
        UP TO @gc_max_rows ROWS.

    DATA(lv_rows) = lines( lt_others ).

    WRITE: / '--- 5. CTE read from a WHERE subquery ---'.
    WRITE: / 'other carriers departing from the same cities:', lv_rows.
    LOOP AT lt_others INTO DATA(ls_other).
      WRITE: / ls_other-carrid, ls_other-connid, ls_other-cityfrom.
    ENDLOOP.

  ENDMETHOD.

  METHOD order_by_in_cte.

    " ORDER BY inside a CTE is "not supported by all databases". The
    " extended program check warns, the pragma below hides the warning,
    " and on a database without the feature the statement raises
    " CX_SY_SQL_UNSUPPORTED_FEATURE at RUNTIME. So the pragma alone is
    " not a fix - query the feature first.
    DATA(lv_supported) = cl_abap_dbfeatures=>use_features(
      requested_features =
        VALUE #( ( cl_abap_dbfeatures=>limit_in_subselect_or_cte ) ) ).

    WRITE: / '--- 6. ORDER BY ... UP TO inside a CTE ---'.
    WRITE: / 'limit_in_subselect_or_cte supported:', lv_supported.

    IF lv_supported = abap_false.
      WRITE: / 'skipped: this database does not support it.'.
      RETURN.
    ENDIF.

    TRY.
        WITH
          +busiest AS ( SELECT FROM sflight
                          FIELDS carrid, connid, seatsocc
                          ORDER BY seatsocc DESCENDING
                          UP TO 10 ROWS )
          ##db_feature_mode[limit_in_subselect_or_cte]
          SELECT FROM +busiest AS b
                 INNER JOIN scarr AS s ON s~carrid = b~carrid
            FIELDS s~carrname, b~connid, b~seatsocc
            ORDER BY b~seatsocc DESCENDING
            INTO TABLE @DATA(lt_busiest)
            UP TO @gc_max_rows ROWS.

        LOOP AT lt_busiest INTO DATA(ls_busy).
          WRITE: / ls_busy-carrname, ls_busy-connid, ls_busy-seatsocc.
        ENDLOOP.

      CATCH cx_sy_sql_unsupported_feature INTO DATA(lo_feature_err).
        DATA(lv_feature_text) = lo_feature_err->get_text( ).
        WRITE: / 'CX_SY_SQL_UNSUPPORTED_FEATURE:', lv_feature_text.
    ENDTRY.

    " UP TO n ROWS is only allowed AFTER ORDER BY in a subquery, and
    " OFFSET only after UP TO n ROWS.

  ENDMETHOD.

  METHOD client_column.

    " mandt is selected into the CTE on purpose. It arrives as an
    " ordinary CHAR(3) column: "Even if the client column of a
    " client-dependent data source is included explicitly in the
    " subquery to its SELECT list, it does not behave as such in the
    " result set." The DB table inside the subquery still gets implicit
    " client handling, so these are the current client's rows - but the
    " CTE itself is a client-INDEPENDENT data source from here on.
    WITH
      +rows AS ( SELECT FROM spfli
                   FIELDS mandt, carrid, connid, cityfrom
                   WHERE carrid = @gc_carrid )
      SELECT FROM +rows AS r
        FIELDS r~mandt, r~carrid, r~connid, r~cityfrom
        ORDER BY r~connid
        INTO TABLE @DATA(lt_rows)
        UP TO 3 ROWS.

    WRITE: / '--- 7. The CTE has no client column ---'.
    WRITE: / 'sy-mandt:', sy-mandt.
    LOOP AT lt_rows INTO DATA(ls_row).
      WRITE: / ls_row-mandt, ls_row-carrid, ls_row-connid, ls_row-cityfrom.
    ENDLOOP.

    " Consequences, both documented:
    "
    "   SELECT FROM +rows AS r USING ALL CLIENTS ...
    "     -> refused. A query over a CTE "cannot specify the addition
    "        USING or the obsolete addition CLIENT SPECIFIED".
    "
    "   SELECT FROM +rows DECLARE CLIENT mandt ...
    "     -> nominates any CHAR(3) column as the client column and
    "        switches implicit client handling back on for the CTE.
    "
    " So USING in the subquery still works, and if the subquery reads
    " every client, nothing in the main query narrows it again unless
    " DECLARE CLIENT is used.
    WRITE: / 'USING is refused over a CTE; DECLARE CLIENT restores it.'.

  ENDMETHOD.

  METHOD dynamic_form.

    " The dynamic form carries the MAIN QUERY ONLY: "the syntax in
    " select_syntax must not contain the definition of CTEs". It is the
    " fully dynamic SELECT that ABAP SQL otherwise lacks, not a way to
    " build CTEs at runtime. Bad syntax is a catchable runtime error.
    TYPES: BEGIN OF ty_carrier,
             carrid   TYPE scarr-carrid,
             carrname TYPE scarr-carrname,
           END OF ty_carrier.

    DATA lt_dynamic TYPE STANDARD TABLE OF ty_carrier WITH EMPTY KEY.

    DATA(lv_source) =
      `SELECT FROM scarr FIELDS carrid, carrname ORDER BY carrid`.

    WRITE: / '--- 8. Dynamic form: main query only ---'.

    " The select list is only known at runtime, so the INTO target
    " cannot be an inline declaration - it has to be declared.
    TRY.
        WITH (lv_source)
          INTO TABLE @lt_dynamic
          UP TO 3 ROWS.

        LOOP AT lt_dynamic INTO DATA(ls_dynamic).
          WRITE: / ls_dynamic-carrid, ls_dynamic-carrname.
        ENDLOOP.

      CATCH cx_sy_dynamic_osql_error INTO DATA(lo_osql_err).
        DATA(lv_osql_text) = lo_osql_err->get_text( ).
        WRITE: / 'CX_SY_DYNAMIC_OSQL_ERROR:', lv_osql_text.
    ENDTRY.

    " Anything from outside the program goes through CL_ABAP_DYN_PRG or
    " escape( ) first. Also: the dynamic form cannot follow OPEN CURSOR,
    " where the static form can; and in the STATIC form, a dynamic token
    " in a CTE subquery means that CTE "can only be used in other
    " dynamic tokens of the WITH statement".
    WRITE: / 'dynamic token in a CTE subquery -> every reference to that'.
    WRITE: / 'CTE must be dynamic too.'.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_cte_demo=>aggregate_first( ).
  SKIP.
  lcl_cte_demo=>chained_ctes( ).
  SKIP.
  lcl_cte_demo=>loop_with_endwith( ).
  SKIP.
  lcl_cte_demo=>name_list( ).
  SKIP.
  lcl_cte_demo=>cte_as_subquery( ).
  SKIP.
  lcl_cte_demo=>order_by_in_cte( ).
  SKIP.
  lcl_cte_demo=>client_column( ).
  SKIP.
  lcl_cte_demo=>dynamic_form( ).
