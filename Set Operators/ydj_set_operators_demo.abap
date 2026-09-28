*&---------------------------------------------------------------------*
*& Report YDJ_SET_OPERATORS_DEMO
*&---------------------------------------------------------------------*
*& ABAP SQL set operators - UNION / INTERSECT / EXCEPT.
*&
*&   1. ALL vs DISTINCT     -> DISTINCT is the DEFAULT; only UNION has ALL.
*&   2. RETROACTIVE DISTINCT-> a later UNION DISTINCT deletes the duplicates
*&                             an earlier UNION ALL produced, because the
*&                             dedupe applies to the WHOLE left-hand result
*&                             set. Parentheses are the only fix.
*&   3. EXCEPT/INTERSECT    -> both are DISTINCT by definition and have NO
*&                             ALL variant, so they deduplicate the LEFT
*&                             side too - unlike a NOT EXISTS subquery.
*&   4. TYPE ALIGNMENT      -> CHAR lengths may differ, NUMC must match
*&                             exactly, so NUMC needs an explicit CAST.
*&   5. WITH +cte WRAPPER   -> branches cannot share a WHERE, so wrap the
*&                             union in a CTE and filter once.
*&   6. RESTRICTIONS        -> no SINGLE / UP TO / OFFSET / per-branch
*&                             ORDER BY / FOR ALL ENTRIES; INTO must be
*&                             LAST (strict mode); buffer + in-memory
*&                             engine are bypassed; one FROM @itab only.
*&
*& Read-only. Runs on any system with the standard flight demo data
*& (SAPBC_DATA_GENERATOR if SCARR/SPFLI/SFLIGHT are empty).
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPUNION.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPUNION_CLAUSE.html
*&---------------------------------------------------------------------*
REPORT ydj_set_operators_demo.

CLASS lcl_setop_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      all_vs_distinct,
      retroactive_distinct,
      except_dedupes_left,
      type_alignment,
      union_in_cte,
      restrictions.

ENDCLASS.


CLASS lcl_setop_demo IMPLEMENTATION.

  METHOD all_vs_distinct.

    " The same query unioned with itself. DISTINCT is the default, so the
    " bare UNION collapses the two identical result sets back into one.
    SELECT FROM scarr FIELDS carrid WHERE carrid = 'LH'
      UNION DISTINCT
    SELECT FROM scarr FIELDS carrid WHERE carrid = 'LH'
      INTO TABLE @DATA(lt_distinct).

    SELECT FROM scarr FIELDS carrid WHERE carrid = 'LH'
      UNION ALL
    SELECT FROM scarr FIELDS carrid WHERE carrid = 'LH'
      INTO TABLE @DATA(lt_all).

    DATA(lv_n_distinct) = lines( lt_distinct ).
    DATA(lv_n_all)      = lines( lt_all ).

    WRITE: / '--- 1. UNION DISTINCT vs UNION ALL ---'.
    WRITE: / 'UNION DISTINCT rows:', lv_n_distinct.   "1
    WRITE: / 'UNION ALL      rows:', lv_n_all.        "2
    WRITE: / 'A bare UNION means UNION DISTINCT.'.

  ENDMETHOD.

  METHOD retroactive_distinct.

    " THE HEADLINE TRAP.
    " Queries are evaluated LEFT TO RIGHT, and DISTINCT is applied to the
    " ENTIRE result set accumulated so far - not just to the branch it is
    " written on. So the UNION ALL below contributes a duplicate, and the
    " following UNION DISTINCT then deletes it again.
    "   { LH } UNION ALL { LH }        -> { LH, LH }
    "          UNION DISTINCT { AA }   -> { LH, LH, AA } then dedupe -> { LH, AA }
    SELECT FROM scarr FIELDS carrid WHERE carrid = 'LH'
      UNION ALL
    SELECT FROM scarr FIELDS carrid WHERE carrid = 'LH'
      UNION DISTINCT
    SELECT FROM scarr FIELDS carrid WHERE carrid = 'AA'
      ORDER BY carrid
      INTO TABLE @DATA(lt_flat).

    " Identical three queries. One pair of parentheses makes the DISTINCT
    " step run FIRST, so the ALL step is last and its duplicate survives.
    "   { LH } UNION ALL ( { LH } UNION DISTINCT { AA } ) -> { LH, LH, AA }
    SELECT FROM scarr FIELDS carrid WHERE carrid = 'LH'
      UNION ALL
    ( SELECT FROM scarr FIELDS carrid WHERE carrid = 'LH'
        UNION DISTINCT
      SELECT FROM scarr FIELDS carrid WHERE carrid = 'AA' )
      ORDER BY carrid
      INTO TABLE @DATA(lt_nested).

    DATA(lv_n_flat)   = lines( lt_flat ).
    DATA(lv_n_nested) = lines( lt_nested ).

    WRITE: / '--- 2. DISTINCT reaches BACKWARDS over a previous ALL ---'.
    WRITE: / 'Unparenthesised rows:', lv_n_flat.     "2 - duplicate destroyed
    WRITE: / 'Parenthesised   rows:', lv_n_nested.   "3 - duplicate kept

    IF lv_n_flat <> lv_n_nested.
      WRITE: / 'Same three queries, different row count: grouping matters.'.
      WRITE: / 'So APPENDING a plain UNION branch can change what the'.
      WRITE: / 'branches ABOVE it contributed - silently.'.
    ENDIF.

  ENDMETHOD.

  METHOD except_dedupes_left.

    " SPFLI holds MANY rows per carrid. A baseline count first.
    SELECT FROM spfli FIELDS carrid WHERE carrid = 'LH'
      INTO TABLE @DATA(lt_plain).

    " EXCEPT is DISTINCT by definition - there is no EXCEPT ALL. So the
    " left side is deduplicated even though the right side excludes
    " nothing that appears on the left ('AA' is not 'LH').
    SELECT FROM spfli FIELDS carrid WHERE carrid = 'LH'
      EXCEPT
    SELECT FROM scarr FIELDS carrid WHERE carrid = 'AA'
      INTO TABLE @DATA(lt_except).

    " INTERSECT behaves the same way on the left side.
    SELECT FROM spfli FIELDS carrid WHERE carrid = 'LH'
      INTERSECT
    SELECT FROM scarr FIELDS carrid WHERE carrid = 'LH'
      INTO TABLE @DATA(lt_intersect).

    DATA(lv_n_plain)     = lines( lt_plain ).
    DATA(lv_n_except)    = lines( lt_except ).
    DATA(lv_n_intersect) = lines( lt_intersect ).

    WRITE: / '--- 3. EXCEPT / INTERSECT have no ALL variant ---'.
    WRITE: / 'Plain SELECT      rows:', lv_n_plain.
    WRITE: / 'After EXCEPT      rows:', lv_n_except.      "1
    WRITE: / 'After INTERSECT   rows:', lv_n_intersect.   "1

    IF lv_n_except < lv_n_plain.
      WRITE: / 'EXCEPT excluded nothing yet still lost rows - it'.
      WRITE: / 'deduplicated the LEFT side. NOT EXISTS would not.'.
    ENDIF.

    " NOT EXISTS keeps EVERY left row - the honest replacement when the
    " intent is "filter", not "set difference".
    " Columns in a subquery condition are resolved INSIDE OUT, so an
    " unqualified carrid here would silently mean scarr~carrid. Both
    " sides are qualified deliberately.
    SELECT FROM spfli FIELDS carrid
      WHERE carrid = 'LH'
        AND NOT EXISTS ( SELECT carrid FROM scarr
                           WHERE scarr~carrid = spfli~carrid
                             AND scarr~carrid = 'AA' )
      INTO TABLE @DATA(lt_notexists).

    DATA(lv_n_notexists) = lines( lt_notexists ).
    WRITE: / 'Same filter via NOT EXISTS:', lv_n_notexists.

  ENDMETHOD.

  METHOD type_alignment.

    " Columns matched across branches must agree on type, length and
    " decimals - with documented exceptions:
    "   CHAR lengths MAY differ  -> result takes the greatest length
    "   INT1/2/4/8 may be mixed  -> result takes the greatest value range
    "   DEC lengths may differ   -> but the DECIMALS must match
    "   NUMC and RAW             -> lengths must match EXACTLY
    "
    " SPFLI-CONNID is NUMC(4) and '-' is a character literal, so they
    " cannot share a column. The CAST is mandatory, not cosmetic.
    " Note also: * and data_source~* are NOT allowed in a set operation,
    " so every branch must name its columns explicitly.
    SELECT FROM scarr
      FIELDS carrname,
             CAST( '-' AS CHAR( 4 ) ) AS connid,
             '-'                      AS cityfrom
      WHERE carrid = 'LH'
      UNION
    SELECT FROM spfli
      FIELDS '-'                          AS carrname,
             CAST( connid AS CHAR( 4 ) )  AS connid,
             cityfrom
      WHERE carrid = 'LH'
      ORDER BY carrname DESCENDING, connid, cityfrom
      INTO TABLE @DATA(lt_mixed).

    WRITE: / '--- 4. Type alignment across branches ---'.
    WRITE: / 'CARRNAME                       CONNID CITYFROM'.
    LOOP AT lt_mixed INTO DATA(ls_mixed).
      WRITE: / ls_mixed-carrname, ls_mixed-connid, ls_mixed-cityfrom.
    ENDLOOP.
    WRITE: / 'CONNID is NUMC(4): a CAST to CHAR(4) is required to union'.
    WRITE: / 'it with a character literal. A CHAR/CHAR length mismatch'.
    WRITE: / 'would instead be accepted and widened silently.'.

  ENDMETHOD.

  METHOD union_in_cte.

    " Branches of a set operation cannot share a WHERE condition, so
    " filtering the MERGED set means repeating the condition in every
    " branch - or building the union inside a common table expression and
    " filtering once in the main query.
    "
    " The AS aliases are load-bearing here: inside a WITH definition the
    " column names ARE visible to the main query. In a standalone union a
    " name mismatch is invisible (the LEFTMOST branch's names win) - but
    " CORRESPONDING or an inline @DATA( ) target makes it an error.
    WITH +aggregates AS (
      SELECT FROM sflight
        FIELDS carrid,
               connid,
               'MAX' AS agg_kind,
               MAX( CAST( seatsocc AS DEC( 31,2 ) ) ) AS agg
        GROUP BY carrid, connid
      UNION
      SELECT FROM sflight
        FIELDS carrid,
               connid,
               'MIN' AS agg_kind,
               MIN( CAST( seatsocc AS DEC( 31,2 ) ) ) AS agg
        GROUP BY carrid, connid )
      SELECT FROM +aggregates
        FIELDS carrid, connid, agg_kind, agg
        WHERE carrid = 'LH'
        ORDER BY connid, agg_kind
        INTO TABLE @DATA(lt_agg).

    WRITE: / '--- 5. Union inside WITH +cte: one WHERE for all branches ---'.
    WRITE: / 'CARR CONN KIND        AGG'.
    LOOP AT lt_agg INTO DATA(ls_agg).
      WRITE: / ls_agg-carrid, ls_agg-connid, ls_agg-agg_kind, ls_agg-agg.
    ENDLOOP.

  ENDMETHOD.

  METHOD restrictions.

    WRITE: / '--- 6. Restrictions worth knowing before refactoring ---'.
    WRITE: / 'NOT allowed with UNION / INTERSECT / EXCEPT:'.
    WRITE: / '  SINGLE            - merged result set is always multirow'.
    WRITE: / '  UP TO n ROWS      - and OFFSET o, both excluded'.
    WRITE: / '  ORDER BY per branch - only one ORDER BY, on the merged set'.
    WRITE: / '  ORDER BY PRIMARY KEY - explicitly excluded'.
    WRITE: / '  FOR ALL ENTRIES   - in any branch WHERE condition'.
    WRITE: / '  * and tab~*       - every branch must name its columns'.
    WRITE: / 'ORDER BY columns must exist with the SAME NAME in every'.
    WRITE: / 'branch, and cannot be written with the ~ column selector.'.
    SKIP.
    WRITE: / 'STRICT MODE: the INTO clause and OPTIONS must come at the'.
    WRITE: / 'END of the whole statement. Writing INTO TABLE @DATA( )'.
    WRITE: / 'right after the first FIELDS list - legal in a single-table'.
    WRITE: / 'SELECT - stops compiling once a UNION is added below it.'.
    SKIP.
    WRITE: / 'PERFORMANCE: a set operation cannot be processed by the'.
    WRITE: / 'ABAP SQL in-memory engine and BYPASSES THE TABLE BUFFER,'.
    WRITE: / 'so adding a UNION to a statement over a fully buffered'.
    WRITE: / 'table turns every execution into a DB round trip.'.
    WRITE: / 'Also: FROM @itab is possible for ONE internal table per'.
    WRITE: / 'statement only, so two itabs cannot be unioned in the DB.'.
    SKIP.
    WRITE: / 'BRANCH COUNT: no fixed ABAP limit, but a database-dependent'.
    WRITE: / 'one, and exceeding it raises an exception AT RUNTIME - so a'.
    WRITE: / 'generated statement can pass in dev and fail in production.'.
    SKIP.
    WRITE: / 'CLIENT HANDLING is per branch: USING (and the obsolete'.
    WRITE: / 'CLIENT SPECIFIED) affect only the branch they appear in.'.
    SKIP.
    WRITE: / 'MINUS is not supported by ABAP SQL, even on SAP HANA.'.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_setop_demo=>all_vs_distinct( ).
  SKIP.

  lcl_setop_demo=>retroactive_distinct( ).
  SKIP.

  lcl_setop_demo=>except_dedupes_left( ).
  SKIP.

  lcl_setop_demo=>type_alignment( ).
  SKIP.

  lcl_setop_demo=>union_in_cte( ).
  SKIP.

  lcl_setop_demo=>restrictions( ).
