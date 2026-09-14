*&---------------------------------------------------------------------*
*& Report YDJ_WINDOW_EXPR_DEMO
*&---------------------------------------------------------------------*
*& ABAP SQL window expressions - aggregate without collapsing rows.
*& Available from ABAP release 7.54.
*&
*&   1. FRAME TRAP        -> adding ORDER BY inside OVER( ) silently turns
*&                           a partition total into a RUNNING total, because
*&                           the implicit frame becomes UNBOUNDED PRECEDING
*&                           .. CURRENT ROW.
*&   2. RANKING           -> ROW_NUMBER / RANK / DENSE_RANK differ only on
*&                           ties, and only RANK leaves gaps.
*&   3. LAST_VALUE TRAP   -> LAST_VALUE returns the CURRENT row unless the
*&                           frame is opened to UNBOUNDED FOLLOWING.
*&   4. TOP-N PER GROUP   -> a window result cannot be used in WHERE, so it
*&                           has to be wrapped in a CTE ( WITH +cte ).
*&   5. DB SUPPORT        -> CL_ABAP_DBFEATURES=>USE_FEATURES( WINDOWING ).
*&
*& Runs on any system with the standard SFLIGHT demo data
*& (SAPBC_DATA_GENERATOR if SFLIGHT is empty).
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_OVER.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_WIN_FUNC.html
*&---------------------------------------------------------------------*
REPORT ydj_window_expr_demo.

CLASS lcl_window_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      frame_trap,
      ranking_functions,
      last_value_trap,
      top_n_per_group,
      check_db_support.

ENDCLASS.


CLASS lcl_window_demo IMPLEMENTATION.

  METHOD frame_trap.

    " Same window function, same partition, one extra ORDER BY.
    " total   -> the sum over the WHOLE partition (no frame)
    " running -> the sum from the first row of the partition up to the
    "            current row, because ORDER BY inside OVER( ) implies
    "            the frame ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW.
    SELECT carrid, connid, fldate, seatsocc,
           SUM( seatsocc ) OVER( PARTITION BY carrid )                AS total,
           SUM( seatsocc ) OVER( PARTITION BY carrid ORDER BY fldate ) AS running
      FROM sflight
      WHERE carrid = 'LH'
      ORDER BY carrid, fldate
      INTO TABLE @DATA(lt_frames).

    WRITE: / '--- 1. ORDER BY inside OVER( ) = running total ---'.
    WRITE: / 'CARR CONN FLDATE     OCC   TOTAL RUNNING'.
    LOOP AT lt_frames INTO DATA(ls_frame).
      WRITE: / ls_frame-carrid, ls_frame-connid, ls_frame-fldate,
               ls_frame-seatsocc, ls_frame-total, ls_frame-running.
    ENDLOOP.

  ENDMETHOD.

  METHOD ranking_functions.

    " All three rank inside the carrier. They differ ONLY on ties:
    "   ROW_NUMBER - always unique, tie order undefined
    "   RANK       - ties share the lowest number, then a GAP
    "   DENSE_RANK - ties share the number, no gap
    " ORDER BY after OVER is mandatory for RANK and DENSE_RANK.
    SELECT carrid, connid, seatsocc,
           ROW_NUMBER( ) OVER( PARTITION BY carrid ORDER BY seatsocc DESCENDING ) AS rownum,
           RANK( )       OVER( PARTITION BY carrid ORDER BY seatsocc DESCENDING ) AS rank_no,
           DENSE_RANK( ) OVER( PARTITION BY carrid ORDER BY seatsocc DESCENDING ) AS dense_no
      FROM sflight
      WHERE carrid = 'LH'
      ORDER BY carrid, rownum
      INTO TABLE @DATA(lt_ranks).

    WRITE: / '--- 2. ROW_NUMBER vs RANK vs DENSE_RANK ---'.
    WRITE: / 'CARR CONN   OCC ROWNUM RANK DENSE'.
    LOOP AT lt_ranks INTO DATA(ls_rank).
      WRITE: / ls_rank-carrid, ls_rank-connid, ls_rank-seatsocc,
               ls_rank-rownum, ls_rank-rank_no, ls_rank-dense_no.
    ENDLOOP.

  ENDMETHOD.

  METHOD last_value_trap.

    " FIRST_VALUE is fine with the default frame - the first row of the
    " frame is the first row of the partition either way.
    " LAST_VALUE is NOT: the default frame ends at the CURRENT row, so it
    " keeps returning the current row's value. Open the frame explicitly.
    SELECT carrid, connid, fldate, seatsocc,
           FIRST_VALUE( seatsocc ) OVER( PARTITION BY carrid ORDER BY fldate )
             AS first_occ,
           LAST_VALUE( seatsocc )  OVER( PARTITION BY carrid ORDER BY fldate )
             AS last_wrong,
           LAST_VALUE( seatsocc )  OVER( PARTITION BY carrid ORDER BY fldate
                                         ROWS BETWEEN UNBOUNDED PRECEDING
                                                  AND UNBOUNDED FOLLOWING )
             AS last_right
      FROM sflight
      WHERE carrid = 'LH'
      ORDER BY carrid, fldate
      INTO TABLE @DATA(lt_values).

    WRITE: / '--- 3. LAST_VALUE needs an explicit frame ---'.
    WRITE: / 'CARR FLDATE       OCC FIRST WRONG RIGHT'.
    LOOP AT lt_values INTO DATA(ls_value).
      WRITE: / ls_value-carrid, ls_value-fldate, ls_value-seatsocc,
               ls_value-first_occ, ls_value-last_wrong, ls_value-last_right.
    ENDLOOP.

  ENDMETHOD.

  METHOD top_n_per_group.

    " A window expression is only allowed in the SELECT list - never in
    " WHERE, GROUP BY or HAVING. To FILTER on a rank you must materialise
    " it first, which is what the common table expression is for (7.51+).
    WITH
      +ranked AS (
        SELECT carrid, connid, fldate, seatsocc,
               ROW_NUMBER( ) OVER( PARTITION BY carrid
                                   ORDER BY seatsocc DESCENDING ) AS rownum
          FROM sflight )
      SELECT carrid, connid, fldate, seatsocc, rownum
        FROM +ranked
        WHERE rownum <= 2
        ORDER BY carrid, rownum
        INTO TABLE @DATA(lt_top).

    WRITE: / '--- 4. Top 2 flights per carrier (window + CTE) ---'.
    WRITE: / 'CARR CONN FLDATE       OCC RANK'.
    LOOP AT lt_top INTO DATA(ls_top).
      WRITE: / ls_top-carrid, ls_top-connid, ls_top-fldate,
               ls_top-seatsocc, ls_top-rownum.
    ENDLOOP.

  ENDMETHOD.

  METHOD check_db_support.

    " Window expressions are not supported by every database platform.
    " Guard the call rather than letting the statement dump.
    IF cl_abap_dbfeatures=>use_features(
         requested_features = VALUE #( ( cl_abap_dbfeatures=>windowing ) ) ) = abap_true.
      WRITE: / '--- 5. Database supports WINDOWING ---'.
    ELSE.
      WRITE: / '--- 5. Database does NOT support WINDOWING ---'.
    ENDIF.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_window_demo=>check_db_support( ).
  SKIP.

  lcl_window_demo=>frame_trap( ).
  SKIP.

  lcl_window_demo=>ranking_functions( ).
  SKIP.

  lcl_window_demo=>last_value_trap( ).
  SKIP.

  lcl_window_demo=>top_n_per_group( ).
