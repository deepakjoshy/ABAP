*&---------------------------------------------------------------------*
*& Report YDJ_SQL_JOIN_DEMO
*&---------------------------------------------------------------------*
*& ABAP SQL joins - INNER / LEFT OUTER / CROSS and what they do to the
*& result set.
*&
*&   1. INNER vs OUTER      -> the outer join adds one padded row per
*&                             left row that has no match.
*&   2. WHERE CANCELS OUTER -> a WHERE on a RIGHT-hand column drops every
*&                             padded row, because a null compares as
*&                             unknown to everything except IS NULL. The
*&                             LEFT OUTER JOIN degrades to an inner join.
*&                             Fix: put the restriction in ON.
*&   3. ANTI-JOIN           -> IS NULL is the one predicate that keeps the
*&                             padded rows, so it answers "no match".
*&   4. FAN-OUT             -> the join multiplies rows, so an aggregate
*&                             over a LEFT column is counted once per
*&                             match. The wrong total is LARGER.
*&   5. CROSS JOIN          -> row count is the product. Between two
*&                             client-dependent tables it is converted
*&                             internally to an inner join on the client.
*&   6. ON RESTRICTIONS     -> no IN range_tab, no subqueries, no path
*&                             expressions; dynamic condition only with a
*&                             static FROM.
*&
*& Read-only: 14 SELECTs, no writes, no COMMIT. Runs on any system with
*& the standard flight demo data (SAPBC_DATA_GENERATOR if SCARR / SPFLI /
*& SFLIGHT are empty).
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_JOIN.html
*&---------------------------------------------------------------------*
REPORT ydj_sql_join_demo.


CLASS lcl_join_demo DEFINITION.

  PUBLIC SECTION.

    CONSTANTS gc_city TYPE spfli-cityfrom VALUE 'FRANKFURT'.

    CLASS-METHODS:
      inner_vs_outer,
      where_cancels_outer,
      anti_join,
      fan_out,
      cross_join_size,
      on_restrictions.

ENDCLASS.


CLASS lcl_join_demo IMPLEMENTATION.

  METHOD inner_vs_outer.

    " Baseline: how many airlines are there at all.
    SELECT FROM scarr
      FIELDS COUNT( * )
      INTO @DATA(lv_airlines).

    " Inner join: only airlines that have at least one connection, and one
    " row PER connection.
    SELECT FROM scarr AS s
           INNER JOIN spfli AS p ON p~carrid = s~carrid
      FIELDS COUNT( * )
      INTO @DATA(lv_inner).

    " Left outer join: the same rows, plus one padded row for every airline
    " with no connection at all. So lv_outer >= lv_inner, always.
    SELECT FROM scarr AS s
           LEFT OUTER JOIN spfli AS p ON p~carrid = s~carrid
      FIELDS COUNT( * )
      INTO @DATA(lv_outer).

    WRITE: / '--- 1. INNER vs LEFT OUTER ---'.
    WRITE: / 'Airlines in SCARR      :', lv_airlines.
    WRITE: / 'INNER JOIN rows        :', lv_inner.
    WRITE: / 'LEFT OUTER JOIN rows   :', lv_outer.
    WRITE: / 'The difference is the airlines with no connection row.'.

  ENDMETHOD.

  METHOD where_cancels_outer.

    " THE HEADLINE TRAP.
    " Intent of all three queries: "every airline, with its Frankfurt
    " departures where it has any".
    DATA(lv_city) = gc_city.

    " (a) Restriction in WHERE, on a column of the RIGHT table.
    "     The padded rows carry a null in p~cityfrom, and comparing a null
    "     for equality is UNKNOWN - not true - so those rows are filtered
    "     out again. This is an inner join with extra steps.
    SELECT FROM scarr AS s
           LEFT OUTER JOIN spfli AS p ON p~carrid = s~carrid
      FIELDS COUNT( DISTINCT s~carrid )
      WHERE p~cityfrom = @lv_city
      INTO @DATA(lv_where).

    " (b) Same restriction, moved into the ON condition. The join now
    "     matches only Frankfurt connections, and every airline WITHOUT
    "     one still contributes its padded row. This is the intent.
    SELECT FROM scarr AS s
           LEFT OUTER JOIN spfli AS p ON p~carrid   = s~carrid
                                     AND p~cityfrom = @lv_city
      FIELDS COUNT( DISTINCT s~carrid )
      INTO @DATA(lv_on).

    " (c) The plain inner join, for comparison with (a).
    SELECT FROM scarr AS s
           INNER JOIN spfli AS p ON p~carrid   = s~carrid
                                AND p~cityfrom = @lv_city
      FIELDS COUNT( DISTINCT s~carrid )
      INTO @DATA(lv_inner).

    WRITE: / '--- 2. The WHERE that cancels the outer join ---'.
    WRITE: / '(a) OUTER + WHERE right col :', lv_where.
    WRITE: / '(c) INNER + same condition  :', lv_inner,
             '<== (a) equals (c)'.
    WRITE: / '(b) OUTER + condition in ON :', lv_on,
             '<== what was intended'.

  ENDMETHOD.

  METHOD anti_join.

    " The one deliberate use of a WHERE on the right-hand side: IS NULL is
    " the single predicate that is TRUE on a padded row, so it selects
    " exactly the left rows that found no match.
    DATA(lv_city) = gc_city.

    SELECT FROM scarr AS s
           LEFT OUTER JOIN spfli AS p ON p~carrid   = s~carrid
                                     AND p~cityfrom = @lv_city
      FIELDS s~carrid, s~carrname
      WHERE p~connid IS NULL
      ORDER BY s~carrid
      INTO TABLE @DATA(lt_no_fra).

    " Note where each condition sits: cityfrom in ON defines what counts as
    " a match, IS NULL in WHERE keeps only the non-matches. Swapping them
    " answers a different question.
    DATA(lv_count) = lines( lt_no_fra ).

    WRITE: / '--- 3. Anti-join: airlines with no Frankfurt departure ---'.
    WRITE: / 'Airlines found         :', lv_count.
    LOOP AT lt_no_fra INTO DATA(ls_row).
      WRITE: / '   ', ls_row-carrid, ls_row-carrname.
    ENDLOOP.

  ENDMETHOD.

  METHOD fan_out.

    " Aggregate over a LEFT-hand column, with and without a join to the
    " child table. SPFLI holds one row per connection; SFLIGHT holds one
    " row per actual flight date of that connection.
    "
    " NOTE: distance carries a unit (SPFLI-DISTID is a mix of KM and MI),
    " so this total is not a meaningful distance - it is only here to show
    " the inflation. See the Currency Amounts note for unit handling.

    SELECT FROM spfli AS p
      FIELDS SUM( p~distance )
      INTO @DATA(lv_true_total).

    " Same column, same aggregate, one join added. Each connection is now
    " counted once PER FLIGHT, so the total is multiplied - and a total
    " that is too LARGE reads like more complete data, not like a bug.
    SELECT FROM spfli AS p
           INNER JOIN sflight AS f ON f~carrid = p~carrid
                                  AND f~connid = p~connid
      FIELDS SUM( p~distance )
      INTO @DATA(lv_inflated).

    " Row counts that explain the factor.
    SELECT FROM spfli
      FIELDS COUNT( * )
      INTO @DATA(lv_conn_rows).

    SELECT FROM spfli AS p
           INNER JOIN sflight AS f ON f~carrid = p~carrid
                                  AND f~connid = p~connid
      FIELDS COUNT( * )
      INTO @DATA(lv_joined_rows).

    " COUNT( DISTINCT col ) is the usual quick fix, but it only works over
    " a column that identifies a row ON ITS OWN. An SPFLI row is
    " identified by carrid AND connid, so DISTINCT over connid alone
    " under-counts instead: connid 0400 exists for several airlines and is
    " collapsed into one value.
    SELECT FROM spfli AS p
           INNER JOIN sflight AS f ON f~carrid = p~carrid
                                  AND f~connid = p~connid
      FIELDS COUNT( DISTINCT p~connid )
      INTO @DATA(lv_distinct_conn).

    WRITE: / '--- 4. Fan-out: the join multiplies your aggregate ---'.
    WRITE: / 'SPFLI rows             :', lv_conn_rows.
    WRITE: / 'After join to SFLIGHT  :', lv_joined_rows,
             '<== one row per flight'.
    WRITE: / 'SUM( distance ) plain  :', lv_true_total.
    WRITE: / 'SUM( distance ) joined :', lv_inflated,
             '<== inflated'.
    WRITE: / 'COUNT( DISTINCT connid):', lv_distinct_conn,
             '<== NOT the row count either'.
    WRITE: / 'Only fix that always works: aggregate the child table in a'.
    WRITE: / 'CTE or subquery FIRST, then join the 1:1 result.'.


  ENDMETHOD.

  METHOD cross_join_size.

    " A cross join has no ON condition, so the row count is the product of
    " both sides. SCARR joined to itself needs two different alias names.
    SELECT FROM scarr
      FIELDS COUNT( * )
      INTO @DATA(lv_airlines).

    SELECT FROM scarr AS a
           CROSS JOIN scarr AS b
      FIELDS COUNT( * )
      INTO @DATA(lv_cross).

    DATA(lv_expected) = lv_airlines * lv_airlines.

    WRITE: / '--- 5. CROSS JOIN: the row count is the product ---'.
    WRITE: / 'SCARR rows             :', lv_airlines.
    WRITE: / 'CROSS JOIN rows        :', lv_cross.
    WRITE: / 'n * n                  :', lv_expected.
    WRITE: / 'Both sides are client-dependent, so the cross join is'.
    WRITE: / 'converted internally to an inner join on the client column'.
    WRITE: / '- which is why the product stays within this client.'.

  ENDMETHOD.

  METHOD on_restrictions.

    " Not executed - these are the shapes that do NOT compile, kept here
    " because the error messages are not obvious.
    "
    " (1) A selection range cannot be used in ON:
    "        ... INNER JOIN spfli AS p ON p~carrid IN @s_carrid
    "     -> [NOT] IN range_tab is not allowed in a join condition. The
    "        range has to go in WHERE, which for an OUTER join puts you
    "        straight back into section 2 above. Pre-filter in a CTE instead.
    "
    " (2) No subqueries in an ON condition at all.
    "
    " (3) No path expressions in ON, so CDS associations cannot be
    "     dereferenced there.
    "
    " (4) At least one comparison is required, so there is no ON 1 = 1
    "     placeholder - use CROSS JOIN and accept that all data is read
    "     before the WHERE condition is evaluated.
    "
    " (5) The client column cannot be an operand of ON. The equality on
    "     the client column is added implicitly for you.
    "
    " (6) A dynamic condition in brackets is allowed only when the FROM
    "     clause itself is static.

    WRITE: / '--- 6. ON condition restrictions ---'.
    WRITE: / 'no IN range_tab / no subquery / no path expression /'.
    WRITE: / 'at least one comparison / no client column /'.
    WRITE: / 'dynamic condition only with a static FROM clause.'.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_join_demo=>inner_vs_outer( ).
  SKIP.
  lcl_join_demo=>where_cancels_outer( ).
  SKIP.
  lcl_join_demo=>anti_join( ).
  SKIP.
  lcl_join_demo=>fan_out( ).
  SKIP.
  lcl_join_demo=>cross_join_size( ).
  SKIP.
  lcl_join_demo=>on_restrictions( ).
