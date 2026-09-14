*&---------------------------------------------------------------------*
*& Report YDJ_NULL_VALUES_DEMO
*&---------------------------------------------------------------------*
*& Null values in ABAP SQL - the value ABAP cannot represent.
*&
*& A null value is "no value at all". It is NOT the type-dependent
*& initial value, and it has no ABAP counterpart: the moment it is
*& passed to a data object it becomes the initial value and the fact
*& that it was null is lost.
*&
*&   1. EMPTY AGGREGATE  -> SELECT MAX( ) over zero rows returns a ROW
*&                          with sy-subrc = 0 and sy-dbcnt = 1. Only
*&                          COUNT( * ) alone gives sy-subrc = 4.
*&   2. THREE-VALUED     -> IS NULL is the ONLY comparison that is
*&      LOGIC               true/false on a null. col = 'X' and
*&                          col <> 'X' BOTH exclude the null rows.
*&   3. NULL SOURCES     -> a CASE without ELSE, and the unmatched side
*&                          of a LEFT OUTER JOIN, are the two null
*&                          generators hiding in ordinary code.
*&   4. INDICATORS       -> the only way to tell null from initial after
*&                          the data has reached ABAP.
*&   5. COALESCE         -> substitute a default instead. Note the
*&                          mandatory blanks inside the parentheses.
*&   6. AGGREGATE NULLS  -> AVG ignores nulls, so AVG <> SUM / COUNT( * ).
*&
*& Runs on any system with the standard SFLIGHT/SPFLI/SCARR demo data
*& (run SAPBC_DATA_GENERATOR if they are empty). Read-only - the report
*& does not modify any data.
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_NULL_VALUES.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENWHERE_LOGEXP_NULL.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_COALESCE.html
*&---------------------------------------------------------------------*
REPORT ydj_null_values_demo.

CLASS lcl_null_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      empty_aggregate_trap,
      three_valued_logic,
      null_sources,
      null_indicators,
      coalesce_defaults,
      aggregates_ignore_nulls,
      check_db_support.

  PRIVATE SECTION.

    " A carrier ID that matches nothing, to force an empty result set.
    CONSTANTS c_missing_carrid TYPE sflight-carrid VALUE 'ZZ'.

ENDCLASS.


CLASS lcl_null_demo IMPLEMENTATION.

  METHOD empty_aggregate_trap.

    " ---------------------------------------------------------------
    " THE HEADLINE TRAP.
    " The database computes MAX over an empty set, correctly returns
    " null, and the transfer to ABAP turns that null into '00000000'.
    " A row WAS transferred, so sy-subrc is 0 and sy-dbcnt is 1.
    " ---------------------------------------------------------------
    SELECT MAX( fldate ) AS max_date
      FROM sflight
      WHERE carrid = @c_missing_carrid
      INTO @DATA(max_date).

    " Capture the system fields IMMEDIATELY - they describe the last
    " statement executed, and anything in between can overwrite them.
    DATA(subrc_agg) = sy-subrc.
    DATA(dbcnt_agg) = sy-dbcnt.

    WRITE: / 'Bare aggregate, no rows match:'.
    WRITE: / '  sy-subrc  =', subrc_agg,     "  0  <- NOT 4
           / '  sy-dbcnt  =', dbcnt_agg,     "  1  <- a row was passed
           / '  max_date  =', max_date.      "  00000000

    IF subrc_agg = 0.
      WRITE: / '  -> the IF sy-subrc = 0 branch is taken. This is the bug.'.
    ENDIF.

    " COUNT( * ) on its own is the documented exception: sy-subrc = 4.
    SELECT COUNT( * )
      FROM sflight
      WHERE carrid = @c_missing_carrid
      INTO @DATA(only_count).

    DATA(subrc_count) = sy-subrc.

    WRITE: / 'COUNT( * ) alone, no rows match:'.
    WRITE: / '  sy-subrc  =', subrc_count,   "  4
           / '  count     =', only_count.    "  0

    " Adding GROUP BY also flips sy-subrc back to 4 on the no-data case,
    " which silently changes the meaning of every IF sy-subrc after it.
    SELECT carrid, MAX( fldate ) AS max_date
      FROM sflight
      WHERE carrid = @c_missing_carrid
      GROUP BY carrid
      INTO TABLE @DATA(grouped).

    DATA(subrc_group) = sy-subrc.

    WRITE: / 'Same aggregate WITH GROUP BY, no rows match:'.
    WRITE: / '  sy-subrc  =', subrc_group,   "  4
           / '  lines     =', lines( grouped ).

    " THE FIX: select COUNT( * ) alongside and test that instead.
    SELECT COUNT( * ) AS cnt, MAX( fldate ) AS max_date
      FROM sflight
      WHERE carrid = @c_missing_carrid
      INTO @DATA(safe).

    IF safe-cnt = 0.
      WRITE: / 'Safe form: cnt = 0, so max_date is meaningless. Correct.'.
    ELSE.
      WRITE: / 'Safe form: max_date =', safe-max_date.
    ENDIF.

    SKIP.

  ENDMETHOD.


  METHOD three_valued_logic.

    " ---------------------------------------------------------------
    " IS NULL is the ONLY relational expression whose result is
    " true or false when the operand is null. Every other comparison
    " yields UNKNOWN, and rows whose WHERE condition is unknown are
    " not returned.
    "
    " The LEFT OUTER JOIN below produces null in spfli~cityfrom for
    " every carrier that has no flight schedule.
    " ---------------------------------------------------------------
    SELECT COUNT( * )
      FROM scarr
      LEFT OUTER JOIN spfli ON scarr~carrid = spfli~carrid
      INTO @DATA(total_rows).

    SELECT COUNT( * )
      FROM scarr
      LEFT OUTER JOIN spfli ON scarr~carrid = spfli~carrid
      WHERE spfli~cityfrom = 'NEW YORK'
      INTO @DATA(equal_rows).

    SELECT COUNT( * )
      FROM scarr
      LEFT OUTER JOIN spfli ON scarr~carrid = spfli~carrid
      WHERE spfli~cityfrom <> 'NEW YORK'
      INTO @DATA(not_equal_rows).

    SELECT COUNT( * )
      FROM scarr
      LEFT OUTER JOIN spfli ON scarr~carrid = spfli~carrid
      WHERE spfli~cityfrom IS NULL
      INTO @DATA(null_rows).

    WRITE: / 'Three-valued logic over a LEFT OUTER JOIN:'.
    WRITE: / '  total rows           =', total_rows,
           / '  cityfrom =  NEW YORK =', equal_rows,
           / '  cityfrom <> NEW YORK =', not_equal_rows,
           / '  cityfrom IS NULL     =', null_rows.

    " = and <> look like exact complements but they are not: the null
    " rows fall through BOTH. The two counts add up to total only after
    " the null count is added back in.
    IF equal_rows + not_equal_rows <> total_rows.
      WRITE: / '  -> = and <> do NOT partition the table.',
             / '     The missing rows are exactly the null ones.'.
    ENDIF.

    " To include them, say so explicitly.
    SELECT COUNT( * )
      FROM scarr
      LEFT OUTER JOIN spfli ON scarr~carrid = spfli~carrid
      WHERE spfli~cityfrom <> 'NEW YORK' OR spfli~cityfrom IS NULL
      INTO @DATA(corrected).

    WRITE: / '  corrected <> ... OR IS NULL =', corrected.

    SKIP.

  ENDMETHOD.


  METHOD null_sources.

    " ---------------------------------------------------------------
    " A CASE with no ELSE branch returns null for every row that does
    " not match a WHEN condition. This is the null generator that
    " hides in perfectly ordinary-looking SELECT lists.
    " ---------------------------------------------------------------
    SELECT carrid, connid, seatsocc,
           CASE WHEN seatsocc > 100 THEN 'FULL' END        AS no_else,
           CASE WHEN seatsocc > 100 THEN 'FULL'
                ELSE 'OK' END                              AS with_else
      FROM sflight
      ORDER BY carrid, connid
      INTO TABLE @DATA(cases)
      UP TO 5 ROWS.

    WRITE: / 'CASE without ELSE produces null (arrives as blank):'.
    LOOP AT cases ASSIGNING FIELD-SYMBOL(<case>).
      WRITE: / '  ', <case>-carrid, <case>-connid,
               'no_else=[', <case>-no_else, ']',
               'with_else=[', <case>-with_else, ']'.
    ENDLOOP.

    WRITE: / '  -> no_else is blank, indistinguishable from a stored blank.'.

    SKIP.

  ENDMETHOD.


  METHOD null_indicators.

    " ---------------------------------------------------------------
    " The only way to tell "the database had no value" from "the
    " database had an initial value" after the transfer to ABAP.
    "
    " After an inline declaration, the substructure named here is
    " generated automatically: one component of type x length 1 per
    " result column, same names, same order.
    "
    " Value hex 1 means the column WAS null.
    " Not every database supports INDICATORS - see check_db_support.
    " ---------------------------------------------------------------
    SELECT carrid, connid,
           CASE WHEN seatsocc > 100 THEN 'FULL' END AS flag
      FROM sflight
      ORDER BY carrid, connid
      INTO TABLE @DATA(itab) INDICATORS NULL STRUCTURE null_ind
      UP TO 5 ROWS.

    WRITE: / 'Null indicators (flag_null = 01 means the column was null):'.
    LOOP AT itab ASSIGNING FIELD-SYMBOL(<row>).
      WRITE: / '  ', <row>-carrid, <row>-connid,
               'flag=[', <row>-flag, ']',
               'flag_null=', <row>-null_ind-flag.
    ENDLOOP.

    " Without the NOT addition, the WHOLE indicator structure is
    " initial exactly when no column of the row contained a null.
    " That makes "this row is null-free" a single check.
    LOOP AT itab ASSIGNING <row>.
      IF <row>-null_ind IS INITIAL.
        WRITE: / '  row', sy-tabix, 'contained no null values at all'.
      ENDIF.
    ENDLOOP.

    SKIP.

  ENDMETHOD.


  METHOD coalesce_defaults.

    " ---------------------------------------------------------------
    " coalesce returns the first argument that is not null. If ALL
    " arguments are null it returns the value of the LAST one, so the
    " last argument should be your literal default.
    "
    " NOTE THE BLANKS: coalesce( a, b ) is correct,
    "                  coalesce(a, b)   is a syntax error.
    " 2 to 255 arguments, nesting depth max 10.
    " ---------------------------------------------------------------
    SELECT scarr~carrid,
           coalesce( spfli~cityfrom, 'NO SCHEDULE' ) AS cityfrom
      FROM scarr
      LEFT OUTER JOIN spfli ON scarr~carrid = spfli~carrid
      ORDER BY scarr~carrid
      INTO TABLE @DATA(defaults)
      UP TO 10 ROWS.

    WRITE: / 'coalesce( ) substituting a default for the null side:'.
    LOOP AT defaults ASSIGNING FIELD-SYMBOL(<def>).
      WRITE: / '  ', <def>-carrid, <def>-cityfrom.
    ENDLOOP.

    SKIP.

  ENDMETHOD.


  METHOD aggregates_ignore_nulls.

    " ---------------------------------------------------------------
    " Nulls are IGNORED when an aggregate is calculated. So AVG
    " divides by the count of NON-NULL values, not by the row count.
    " AVG( col ) therefore does NOT equal SUM( col ) / COUNT( * )
    " whenever the column contains nulls - a classic cross-check
    " failure between two reports that should agree.
    "
    " COUNT( col ) counts non-null values; COUNT( * ) counts rows.
    " They differ by exactly the number of nulls.
    " ---------------------------------------------------------------
    SELECT COUNT( * )              AS row_count,
           COUNT( spfli~cityfrom ) AS non_null_count
      FROM scarr
      LEFT OUTER JOIN spfli ON scarr~carrid = spfli~carrid
      INTO @DATA(counts).

    WRITE: / 'COUNT( * ) vs COUNT( col ) over a LEFT OUTER JOIN:'.
    WRITE: / '  COUNT( * )        =', counts-row_count,
           / '  COUNT( cityfrom ) =', counts-non_null_count,
           / '  difference        =',
               counts-row_count - counts-non_null_count,
               '( = the number of null values )'.

    SKIP.

  ENDMETHOD.


  METHOD check_db_support.

    " The INDICATORS addition is not supported by every database.
    " Guard it rather than assuming.
    TRY.
        IF cl_abap_dbfeatures=>use_features(
             VALUE #( ( cl_abap_dbfeatures=>indicators ) ) ) = abap_true.
          WRITE: / 'This database supports INDICATORS.'.
        ELSE.
          WRITE: / 'This database does NOT support INDICATORS.'.
        ENDIF.
      CATCH cx_root INTO DATA(lx_error).
        WRITE: / 'Feature check failed:', lx_error->get_text( ).
    ENDTRY.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_null_demo=>empty_aggregate_trap( ).
  lcl_null_demo=>three_valued_logic( ).
  lcl_null_demo=>null_sources( ).
  lcl_null_demo=>null_indicators( ).
  lcl_null_demo=>coalesce_defaults( ).
  lcl_null_demo=>aggregates_ignore_nulls( ).
  lcl_null_demo=>check_db_support( ).
