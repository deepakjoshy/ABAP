*&---------------------------------------------------------------------*
*& Report YDJ_ROW_LIMITING_DEMO
*&---------------------------------------------------------------------*
*& Row limiting and ordering in ABAP SQL - UP TO, OFFSET, SINGLE, ORDER BY.
*&
*&   1. UP TO @n ROWS, n = 0  -> NO limit at all. A host variable holding
*&                              0 reads up to 2,147,483,647 rows, while a
*&                              LITERAL or CONSTANTS 0 is rejected by the
*&                              syntax check in strict mode from 7.63.
*&   2. ORDER BY @n (DATA)    -> silently NO SORT. Only a literal or a
*&                              CONSTANTS integer is a position; a
*&                              variable is handled as an SQL expression
*&                              without a column, which has no effect.
*&   3. SINGLE vs UP TO 1     -> SINGLE on a non-unique selection returns
*&                              one of the matching rows and cannot take
*&                              ORDER BY, so WHICH row is undefined.
*&                              UP TO 1 ROWS + ORDER BY is the
*&                              deterministic form.
*&   4. OFFSET pagination     -> OFFSET needs ORDER BY, and whatever the
*&                              ORDER BY does not sort uniquely stays
*&                              undefined ACROSS EXECUTIONS, so pages can
*&                              repeat or skip rows.
*&   5. UP TO with FOR ALL    -> the limit applies when rows move from the
*&                              internal system table to the target, NOT
*&                              on the database read.
*&   6. Restrictions          -> FOR UPDATE with a partial key: empty
*&                              result set, sy-subrc = 8 and NO lock.
*&
*& Read-only. No COMMIT. FOR UPDATE is deliberately NOT executed here - it
*& would set exclusive database locks. Needs the standard flight demo data
*& (SAPBC_DATA_GENERATOR if SCARR/SPFLI/SFLIGHT are empty).
*&
*& Doc: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_UP_TO_OFFSET.html
*&      https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_SINGLE.html
*&      https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPORDERBY_CLAUSE.html
*&---------------------------------------------------------------------*
REPORT ydj_row_limiting_demo.

CLASS lcl_limit_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      zero_limit_reads_all,
      order_by_variable_no_op,
      single_vs_up_to_one,
      offset_pagination,
      up_to_with_fae,
      restrictions.

ENDCLASS.


CLASS lcl_limit_demo IMPLEMENTATION.

  METHOD zero_limit_reads_all.

    WRITE: / '1. UP TO @n ROWS where n = 0'.
    SKIP.

    SELECT COUNT( * ) FROM spfli INTO @DATA(lv_total).

    " A limit that came out as 0: an empty input field, a config row
    " nobody maintained, a page size read from customizing. The literal
    " 0 would not compile in strict mode - a variable holding 0 does.
    DATA(lv_limit) = 0.

    SELECT carrid, connid
      FROM spfli
      INTO TABLE @DATA(lt_limited)
      UP TO @lv_limit ROWS.

    DATA(lv_read) = lines( lt_limited ).

    WRITE: / 'rows in SPFLI                       ', lv_total.
    WRITE: / 'rows read with UP TO @lv_limit ROWS  ', lv_read.

    IF lv_read = lv_total.
      SKIP.
      WRITE: / 'Identical. The limit limited nothing: n = 0 means a'.
      WRITE: / 'maximum of 2,147,483,647 rows, not zero rows.'.
    ENDIF.

  ENDMETHOD.


  METHOD order_by_variable_no_op.

    WRITE: / '2. ORDER BY with a variable position'.
    SKIP.

    " control: whatever order the database feels like
    SELECT carrid, carrname, currcode
      FROM scarr
      INTO TABLE @DATA(lt_unsorted).

    " a LITERAL integer IS a position specification - 3 = CURRCODE
    SELECT carrid, carrname, currcode
      FROM scarr
      ORDER BY 3 DESCENDING
      INTO TABLE @DATA(lt_by_literal).

    " the same 3 in a DATA variable is NOT a position. It is an SQL
    " expression with no column operand, and that has no effect. A
    " CONSTANTS n TYPE i VALUE 3 would be a position again.
    DATA lv_pos TYPE i VALUE 3.

    SELECT carrid, carrname, currcode
      FROM scarr
      ORDER BY @lv_pos DESCENDING
      INTO TABLE @DATA(lt_by_variable).

    " a quoted column NAME is a character literal, not a column either
    SELECT carrid, carrname, currcode
      FROM scarr
      ORDER BY 'CURRCODE' DESCENDING
      INTO TABLE @DATA(lt_by_name_literal).

    DATA(lv_lit) = xsdbool( lt_by_literal <> lt_unsorted ).
    DATA(lv_var) = xsdbool( lt_by_variable <> lt_unsorted ).
    DATA(lv_nam) = xsdbool( lt_by_name_literal <> lt_unsorted ).

    WRITE: / 'ORDER BY 3 DESCENDING changed the order        ', lv_lit.
    WRITE: / 'ORDER BY @lv_pos DESCENDING changed the order  ', lv_var.
    WRITE: / 'ORDER BY (quoted name) changed the order       ', lv_nam.
    SKIP.
    WRITE: / 'The last two statements compile, run, and sort nothing.'.
    WRITE: / 'Changing DATA to CONSTANTS turns the second one back into'.
    WRITE: / 'a real sort - same source line, different behaviour.'.

  ENDMETHOD.


  METHOD single_vs_up_to_one.

    WRITE: / '3. SINGLE vs UP TO 1 ROWS on a non-unique selection'.
    SKIP.

    " CARRID alone is not the full primary key of SPFLI, so the doc says
    " "one of these rows is included in the result set". The extended
    " program check warns when no exact row is determined.
    SELECT SINGLE connid, cityto
      FROM spfli
      WHERE carrid = 'LH'
      INTO @DATA(ls_single).

    " the deterministic form: ORDER BY decides WHICH row is the one
    SELECT connid, cityto
      FROM spfli
      WHERE carrid = 'LH'
      ORDER BY connid ASCENDING
      INTO TABLE @DATA(lt_first)
      UP TO 1 ROWS.

    SELECT connid, cityto
      FROM spfli
      WHERE carrid = 'LH'
      ORDER BY connid DESCENDING
      INTO TABLE @DATA(lt_last)
      UP TO 1 ROWS.

    WRITE: / 'SELECT SINGLE                  ', ls_single-connid.

    DATA(lv_cnt_first) = lines( lt_first ).
    DATA(lv_cnt_last)  = lines( lt_last ).

    IF lv_cnt_first = 1.
      DATA(lv_asc) = lt_first[ 1 ]-connid.
      WRITE: / 'UP TO 1 ROWS, ORDER BY ASC     ', lv_asc.
    ENDIF.

    IF lv_cnt_last = 1.
      DATA(lv_desc) = lt_last[ 1 ]-connid.
      WRITE: / 'UP TO 1 ROWS, ORDER BY DESC    ', lv_desc.
    ENDIF.

    SKIP.
    WRITE: / 'The first value is whatever the database handed over, and'.
    WRITE: / 'ORDER BY cannot be combined with SINGLE at all - so there'.
    WRITE: / 'is no way to make that read deterministic. Result sets of'.
    WRITE: / 'SINGLE and of UP TO 1 ROWS without ORDER BY are the same.'.

  ENDMETHOD.


  METHOD offset_pagination.

    WRITE: / '4. OFFSET pagination over a non-unique sort key'.
    SKIP.

    DATA(lv_page_size) = 5.

    " CITYFROM is not unique in SPFLI. Everything the ORDER BY does not
    " order stays undefined, and the doc states it can be different in
    " repeated executions of the SAME SELECT statement.
    SELECT carrid, connid, cityfrom
      FROM spfli
      ORDER BY cityfrom
      INTO TABLE @DATA(lt_page1)
      UP TO @lv_page_size ROWS.

    SELECT carrid, connid, cityfrom
      FROM spfli
      ORDER BY cityfrom
      INTO TABLE @DATA(lt_page2)
      UP TO @lv_page_size ROWS OFFSET @lv_page_size.

    DATA lv_overlap TYPE i.

    LOOP AT lt_page1 INTO DATA(ls_row).
      IF line_exists( lt_page2[ carrid = ls_row-carrid
                                connid = ls_row-connid ] ).
        lv_overlap = lv_overlap + 1.
      ENDIF.
    ENDLOOP.

    DATA(lv_cnt_p1) = lines( lt_page1 ).
    DATA(lv_cnt_p2) = lines( lt_page2 ).

    WRITE: / 'page 1 rows                   ', lv_cnt_p1.
    WRITE: / 'page 2 rows                   ', lv_cnt_p2.
    WRITE: / 'rows appearing on BOTH pages   ', lv_overlap.
    SKIP.
    WRITE: / 'An overlap of 0 here is luck, not a guarantee. The two'.
    WRITE: / 'pages are two independent sorts, and rows with equal'.
    WRITE: / 'CITYFROM may be ordered differently in each of them.'.
    SKIP.
    WRITE: / 'Deterministic form - extend the ORDER BY until it is'.
    WRITE: / 'unique, normally by appending the primary key:'.

    SELECT carrid, connid, cityfrom
      FROM spfli
      ORDER BY cityfrom, carrid, connid
      INTO TABLE @DATA(lt_stable)
      UP TO @lv_page_size ROWS OFFSET @lv_page_size.

    DATA(lv_cnt_stable) = lines( lt_stable ).
    WRITE: / 'stable page 2 rows            ', lv_cnt_stable.

  ENDMETHOD.


  METHOD up_to_with_fae.

    WRITE: / '5. UP TO n ROWS together with FOR ALL ENTRIES'.
    SKIP.

    SELECT carrid FROM scarr INTO TABLE @DATA(lt_driver).

    " an empty driver table reads EVERYTHING - see the For All Entries
    " note in this repo. Always guard it.
    IF lt_driver IS INITIAL.
      WRITE: / 'SCARR is empty - skipped.'.
      RETURN.
    ENDIF.

    SELECT carrid, connid
      FROM spfli
      FOR ALL ENTRIES IN @lt_driver
      WHERE carrid = @lt_driver-carrid
      INTO TABLE @DATA(lt_rows)
      UP TO 5 ROWS.

    DATA(lv_cnt_rows) = lines( lt_rows ).
    WRITE: / 'rows in the target            ', lv_cnt_rows.
    SKIP.
    WRITE: / 'The target holds 5 rows, but every selected row was read'.
    WRITE: / 'into an internal system table FIRST. UP TO only takes'.
    WRITE: / 'effect when rows move from there into the target, so it'.
    WRITE: / 'is no guard against a memory bottleneck. OFFSET is not'.
    WRITE: / 'allowed with FOR ALL ENTRIES at all.'.

  ENDMETHOD.


  METHOD restrictions.

    WRITE: / '6. Restrictions and sy-subrc values worth knowing'.
    SKIP.
    WRITE: / 'SELECT SINGLE ... FOR UPDATE is executed ONLY if every'.
    WRITE: / 'primary key field is checked for equality with AND in the'.
    WRITE: / 'WHERE condition. Otherwise the result set is EMPTY and'.
    WRITE: / 'sy-subrc = 8 - no data, no lock, no exception. With the'.
    WRITE: / 'addition NOWAIT, sy-subrc = 6 means the lock could not be'.
    WRITE: / 'set and nothing was read.'.
    SKIP.
    WRITE: / 'FOR UPDATE cannot be handled by the ABAP SQL in-memory'.
    WRITE: / 'engine, and a standalone SELECT bypasses the table buffer.'.
    WRITE: / 'Set wrongly, the lock can produce a deadlock.'.
    SKIP.
    WRITE: / 'UP TO cannot be combined with SINGLE, nor with UNION /'.
    WRITE: / 'INTERSECT / EXCEPT. OFFSET additionally rules out FOR ALL'.
    WRITE: / 'ENTRIES and DDIC projection views, and REQUIRES ORDER BY.'.
    SKIP.
    WRITE: / 'A negative n, or +2,147,483,647, is a syntax error or an'.
    WRITE: / 'UNCATCHABLE exception - so a computed limit needs its own'.
    WRITE: / 'range check before it reaches the statement.'.
    SKIP.
    WRITE: / 'ORDER BY PRIMARY KEY is refused for joins, path'.
    WRITE: / 'expressions, subqueries, UNION results and CTE access. On'.
    WRITE: / 'a view whose field count equals its key count it is also'.
    WRITE: / 'refused - and the result set is then sorted by ALL columns.'.
    SKIP.
    WRITE: / 'Sorting happens on the database, AFTER WHERE, aggregates'.
    WRITE: / 'and GROUP BY; only UP TO and OFFSET act on the sorted set.'.
    WRITE: / 'Character sorts are platform dependent and can differ from'.
    WRITE: / 'an ABAP SORT. Reading a sorted result set INTO a SORTED'.
    WRITE: / 'internal table sorts it again, discarding the DB order.'.
    SKIP.
    WRITE: / 'A position n counts the columns of the RESULT SET, which'.
    WRITE: / 'is independent of CORRESPONDING FIELDS in the INTO clause -'.
    WRITE: / 'and with * on a client-dependent source the client column'.
    WRITE: / 'counts too, which shifts every position by one.'.
    SKIP.
    WRITE: / 'Existence check: UP TO 1 ROWS with a SELECT list holding'.
    WRITE: / 'nothing but a single constant avoids transporting data.'.
    WRITE: / 'Prefer it over a SELECT loop with EXIT: the last package'.
    WRITE: / 'sent from the database then carries superfluous rows.'.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_limit_demo=>zero_limit_reads_all( ).
  SKIP 2.

  lcl_limit_demo=>order_by_variable_no_op( ).
  SKIP 2.

  lcl_limit_demo=>single_vs_up_to_one( ).
  SKIP 2.

  lcl_limit_demo=>offset_pagination( ).
  SKIP 2.

  lcl_limit_demo=>up_to_with_fae( ).
  SKIP 2.

  lcl_limit_demo=>restrictions( ).
