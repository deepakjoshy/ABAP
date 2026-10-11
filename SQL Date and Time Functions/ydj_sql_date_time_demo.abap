*&---------------------------------------------------------------------*
*& Report YDJ_SQL_DATE_TIME_DEMO
*&---------------------------------------------------------------------*
*& Date and time functions in ABAP SQL - what happens to the dates that
*& are not dates.
*&
*&   1. DATS_IS_VALID( '00000000' ) = 0   -> the INITIAL date is not a
*&                              valid date, while 00010101 is. An
*&                              optional date column is therefore
*&                              "invalid" in every row nobody filled.
*&   2. The DATS_* calculations do not  -> "Any invalid date is
*&      report that at all                initialized and set to the
*&                              value 00010101 before the calculation",
*&                              so DATS_DAYS_BETWEEN over an empty date
*&                              returns ~739,000 days with sy-subrc = 0.
*&   3. The failure mode is chosen   -> DATS_ADD_DAYS resets the initial
*&      by the dictionary type         value on overflow; DATN_ADD_DAYS
*&                              and the UTCLONG forms raise
*&                              CX_SY_OPEN_SQL_DB for the same overflow.
*&   4. DATS_ADD_MONTHS clamps       -> 31.01 + 1 month = 28.02, and
*&                              28.02 - 1 month = 28.01. Adding and
*&                              subtracting a month is not a round trip.
*&   5. A null date (outer join)     -> DATS_IS_VALID returns 0, every
*&                              other function returns the null value,
*&                              which arrives in ABAP as 00000000. Null
*&                              and garbage are indistinguishable.
*&   6. On the ABAP side             -> an invalid date converts to the
*&                              number 0 with no exception, 00000000 and
*&                              00010101 both convert to 0, and the
*&                              conversion back produces 00000000.
*&
*& Read-only. No INSERT/UPDATE/DELETE/COMMIT anywhere. SFLIGHT and SPFLI
*& are used only to give the statements a FROM clause and one outer join
*& (SAPBC_DATA_GENERATOR if the flight demo data is empty).
*&
*& Chiefly the DATS_* functions are used here, because they are the oldest
*& and least release-sensitive of the family. The generic functions
*& (IS_VALID, EXTRACT_*, DAYNAME, WEEKDAY, ADD_DAYS, ADD_MONTHS) enforce
*& the strict mode from release 7.83 and an unsupported SQL function is a
*& SYNTAX error, not a runtime one - it would stop this whole report from
*& compiling on an older system. They are written up in README.md instead.
*&
*& One exception: part 2 calls TIMS_IS_VALID, which the documentation says
*& enforces the strict mode from release 7.71. On an older system, comment
*& that one SELECT out - the rest of the report does not need it.
*&
*& Doc: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_DATS_DATE_FUNC.html
*&      https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_GEN_DATE_FUNC.html
*&      https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_D.html
*&---------------------------------------------------------------------*
REPORT ydj_sql_date_time_demo.

CLASS lcl_date_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      empty_date_becomes_year_one,
      is_valid_disagrees,
      add_days_vs_add_months,
      month_end_not_invertible,
      null_date_from_outer_join,
      the_abap_side.

ENDCLASS.


CLASS lcl_date_demo IMPLEMENTATION.

  METHOD empty_date_becomes_year_one.

    WRITE: / '1. The empty date and the date 00010101'.
    SKIP.

    " An optional date column: a delivery date not yet confirmed, a
    " closing date on an open item, a termination date on an active
    " contract. In the database it is 00000000.
    DATA lv_empty TYPE d.
    DATA lv_first TYPE d VALUE '00010101'.

    " SFLIGHT only supplies the FROM clause - every value below comes
    " from the host variables. A type-compliant literal such as
    " '00000000' would be accepted in the same operand positions.
    SELECT SINGLE
           FROM sflight
           FIELDS dats_is_valid( @lv_empty )                AS empty_valid,
                  dats_is_valid( @lv_first )                AS first_valid,
                  dats_days_between( @lv_empty, @sy-datum ) AS from_empty,
                  dats_days_between( @lv_first, @sy-datum ) AS from_first
           INTO @DATA(ls_res).

    WRITE: / 'dats_is_valid( 00000000 )          ', ls_res-empty_valid.
    WRITE: / 'dats_is_valid( 00010101 )          ', ls_res-first_valid.
    WRITE: / 'dats_days_between( 00000000, today)', ls_res-from_empty.
    WRITE: / 'dats_days_between( 00010101, today)', ls_res-from_first.
    SKIP.

    IF ls_res-from_empty = ls_res-from_first.
      WRITE: / 'The two differences are identical. The empty date was'.
      WRITE: / 'silently replaced by 00010101 before the subtraction -'.
      WRITE: / 'and dats_is_valid had already said it was not a date.'.
      WRITE: / 'No exception, no null value, no sy-subrc <> 0: just an'.
      WRITE: / 'age in days that is off by about two thousand years.'.
    ENDIF.

  ENDMETHOD.


  METHOD is_valid_disagrees.

    WRITE: / '2. "Valid" does not mean the same thing for a time'.
    SKIP.

    DATA lv_empty_date TYPE d.
    DATA lv_empty_time TYPE t.

    " Same question, same answer shape (INT4 1 or 0), opposite verdict
    " on the initial value - because the two functions document the
    " initial value differently, not because the data differs.
    SELECT SINGLE
           FROM sflight
           FIELDS dats_is_valid( @lv_empty_date ) AS date_valid,
                  tims_is_valid( @lv_empty_time ) AS time_valid
           INTO @DATA(ls_valid).

    WRITE: / 'dats_is_valid( 00000000 )          ', ls_valid-date_valid.
    WRITE: / 'tims_is_valid( 000000   )          ', ls_valid-time_valid.
    SKIP.
    WRITE: / 'An initial TIME is valid (1). An initial DATE is not (0).'.
    WRITE: / 'A validity flag is therefore only readable next to the'.
    WRITE: / 'type of the column it came from.'.

  ENDMETHOD.


  METHOD add_days_vs_add_months.

    WRITE: / '3. Overflow: one function resets, its neighbour raises'.
    SKIP.

    DATA lv_last TYPE d VALUE '99991231'.

    " DATS_ADD_DAYS: "If the calculation produces an invalid date, the
    " initial value is reset." So the result of 9999-12-31 + 10 days is
    " 00000000 - which is also the value an empty column has.
    SELECT SINGLE
           FROM sflight
           FIELDS dats_add_days( @lv_last, 10 ) AS overflowed
           INTO @DATA(lv_overflowed).

    WRITE: / 'dats_add_days( 99991231, 10 )      ', lv_overflowed.
    SKIP.

    " DATS_ADD_MONTHS for the same overflow is documented twice, and not
    " identically: the DATS page says "If the calculation produces an
    " invalid date, an error occurs", while the generic ADD_MONTHS page
    " says a DATS argument "returns the initial date". So catch the
    " exception and report which of the two this system does.
    TRY.
        SELECT SINGLE
               FROM sflight
               FIELDS dats_add_months( @lv_last, 2 ) AS overflowed
               INTO @DATA(lv_months).

        WRITE: / 'dats_add_months( 99991231, 2 )     ', lv_months.
        WRITE: / '-> no exception on this system'.

      CATCH cx_sy_open_sql_db INTO DATA(lo_err).
        DATA(lv_text) = lo_err->get_text( ).
        WRITE: / 'dats_add_months( 99991231, 2 ) raised CX_SY_OPEN_SQL_DB'.
        WRITE: / lv_text.
    ENDTRY.

    SKIP.
    WRITE: / 'The DATN_* and UTCLONG forms of the same operations are'.
    WRITE: / 'documented as raising an error in both cases. Which'.
    WRITE: / 'dictionary type the column has decides whether bad'.
    WRITE: / 'arithmetic is loud or silent.'.

  ENDMETHOD.


  METHOD month_end_not_invertible.

    WRITE: / '4. Adding and subtracting a month is not a round trip'.
    SKIP.

    DATA lv_jan31 TYPE d VALUE '20260131'.

    " "If the target month has fewer days than the source month, the
    " last day of the target month is returned."
    SELECT SINGLE
           FROM sflight
           FIELDS dats_add_months( @lv_jan31, 1 ) AS plus_one
           INTO @DATA(lv_feb).

    SELECT SINGLE
           FROM sflight
           FIELDS dats_add_months( @lv_feb, -1 ) AS minus_one
           INTO @DATA(lv_back).

    WRITE: / 'start                              ', lv_jan31.
    WRITE: / '+ 1 month                          ', lv_feb.
    WRITE: / '- 1 month again                    ', lv_back.
    SKIP.

    IF lv_back <> lv_jan31.
      WRITE: / 'The clamp to the end of the short month is not undone by'.
      WRITE: / 'subtracting the month again. A monthly due date derived'.
      WRITE: / 'by repeated + 1 month walks backwards to the 28th and'.
      WRITE: / 'stays there for the rest of the year.'.
    ENDIF.

  ENDMETHOD.


  METHOD null_date_from_outer_join.

    WRITE: / '5. A null date is reported as an invalid date'.
    SKIP.

    " The ON condition can never be true, so every SFLIGHT column in the
    " result is the null value - the ordinary shape of an unmatched left
    " outer join, no special test data needed.
    SELECT FROM spfli AS p
             LEFT OUTER JOIN sflight AS f
               ON  f~carrid = p~carrid
               AND f~connid = p~connid
               AND f~fldate = '19000101'
           FIELDS p~carrid                     AS carrid,
                  p~connid                     AS connid,
                  f~fldate                     AS fldate,
                  dats_is_valid( f~fldate )    AS valid,
                  dats_add_days( f~fldate, 1 ) AS plus_one
           INTO TABLE @DATA(lt_rows)
           UP TO 3 ROWS.

    WRITE: / 'carrid connid fldate     valid plus_one'.

    LOOP AT lt_rows INTO DATA(ls_row).
      WRITE: /  ls_row-carrid,
                ls_row-connid,
                ls_row-fldate,
                ls_row-valid,
                ls_row-plus_one.
    ENDLOOP.

    SKIP.
    WRITE: / 'FLDATE and PLUS_ONE both arrive as 00000000: the null'.
    WRITE: / 'value is converted to the initial value on the way into'.
    WRITE: / 'ABAP. VALID is 0 - the same 0 a genuinely corrupt date'.
    WRITE: / 'gets. To tell "no row" from "bad date" apart, ask for the'.
    WRITE: / 'null explicitly (IS NULL, or a null indicator).'.

  ENDMETHOD.


  METHOD the_abap_side.

    WRITE: / '6. The same arithmetic inside ABAP'.
    SKIP.

    DATA lv_empty TYPE d.
    DATA lv_first TYPE d VALUE '00010101'.

    " "If the source field contains an invalid date, the target field is
    " assigned the value 0" - and 00000000 and 00010101 both produce 0.
    DATA(lv_n_empty) = CONV i( lv_empty ).
    DATA(lv_n_first) = CONV i( lv_first ).

    " The way back is not symmetrical: 0 becomes 00000000, never
    " 00010101. The conversion of 00010101 to a number is one-way.
    DATA lv_back TYPE d.
    lv_back = 0.

    WRITE: / 'CONV i( 00000000 )                 ', lv_n_empty.
    WRITE: / 'CONV i( 00010101 )                 ', lv_n_first.
    WRITE: / 'date field assigned the number 0   ', lv_back.
    SKIP.

    " An invalid date is storable, usable and silent. 30 February is a
    " plausible typo and converts to day number 0.
    DATA lv_bad TYPE d VALUE '20260230'.

    " Declared as i on purpose: with an inline DATA( ) the type comes
    " from the calculation type, which is the trap the Numeric
    " Arithmetic note in this repo documents.
    DATA lv_days TYPE i.
    lv_days = lv_bad - sy-datum.

    WRITE: / '30 February minus today, in days   ', lv_days.
    WRITE: / '(the invalid operand counted as day 0, no exception)'.
    SKIP.

    " The calendar reform is respected, which makes the day numbering
    " non-injective: ten dates that never existed share their day
    " numbers with ten that did.
    DATA lv_pre  TYPE d VALUE '15821004'.
    DATA lv_gap  TYPE d VALUE '15821005'.
    DATA lv_post TYPE d VALUE '15821015'.

    DATA(lv_n_pre)  = CONV i( lv_pre ).
    DATA(lv_n_gap)  = CONV i( lv_gap ).
    DATA(lv_n_post) = CONV i( lv_post ).

    WRITE: / '04.10.1582                         ', lv_n_pre.
    WRITE: / '05.10.1582 (never existed)         ', lv_n_gap.
    WRITE: / '15.10.1582                         ', lv_n_post.

    IF lv_n_gap = lv_n_post.
      SKIP.
      WRITE: / 'Two different dates, one day number. Day arithmetic'.
      WRITE: / 'cannot be reversed into a unique date across the'.
      WRITE: / 'Julian/Gregorian cut-over.'.
    ENDIF.

    SKIP.
    " Not executed: a date has no conversion to a time or to utclong.
    "   CONV t( lv_pre )       -> syntax error, or MOVE_NOT_SUPPORTED
    "   CONV utclong( lv_pre ) -> CX_SY_CONVERSION_NOT_SUPPORTED
    " A date-to-utclong step always needs a time zone - see the
    " Time Stamps note.
    DATA lv_year TYPE n LENGTH 4.
    lv_year = sy-datum.

    WRITE: / 'sy-datum assigned to n LENGTH 4    ', lv_year.
    WRITE: / '(a date assigned to a shorter n is cut on the RIGHT, so'.
    WRITE: / 'this is the year and not the day - the rule comes from the'.
    WRITE: / 'd-to-n conversion table, not from the value.)'.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_date_demo=>empty_date_becomes_year_one( ).
  SKIP 2.

  lcl_date_demo=>is_valid_disagrees( ).
  SKIP 2.

  lcl_date_demo=>add_days_vs_add_months( ).
  SKIP 2.

  lcl_date_demo=>month_end_not_invertible( ).
  SKIP 2.

  lcl_date_demo=>null_date_from_outer_join( ).
  SKIP 2.

  lcl_date_demo=>the_abap_side( ).
