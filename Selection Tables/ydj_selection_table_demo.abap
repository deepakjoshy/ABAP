*&---------------------------------------------------------------------*
*& Report YDJ_SELECTION_TABLE_DEMO
*&---------------------------------------------------------------------*
*& Demonstrates what a ranges / selection table actually expands to.
*&
*&   1. INITIAL RANGE      -> the condition is TRUE, so every row is read.
*&                            "no entries" is NOT "no rows".
*&   2. I/E SET ARITHMETIC -> an E-only range selects everything EXCEPT,
*&                            I and E together are (OR of I) AND (NOT OR of E).
*&   3. CP CASE SPLIT      -> the SAME range filters differently on the
*&                            database (LIKE, case-sensitive) than in ABAP
*&                            (CP, case-insensitive).
*&   4. VALIDATION         -> invalid SIGN/OPTION is an UNCATCHABLE dump,
*&                            so ranges from outside must be checked first.
*&
*& Run on any system with the standard SPFLI/SCARR demo data
*& (SAPBC_DATA_GENERATOR if the tables are empty).
*&---------------------------------------------------------------------*
REPORT ydj_selection_table_demo.

TYPES ty_carrid_range TYPE RANGE OF spfli-carrid.

DATA gv_carrid TYPE spfli-carrid.

* A real selection criterion. Left blank on the screen it reads everything.
SELECT-OPTIONS s_carrid FOR gv_carrid.


CLASS lcl_seltab_demo DEFINITION.

  PUBLIC SECTION.
    CLASS-METHODS:
      trap_initial_range,
      trap_exclude_only,
      trap_cp_case_split,
      guard_before_use IMPORTING it_range         TYPE ty_carrid_range
                       RETURNING VALUE(rv_valid) TYPE abap_bool.

  PRIVATE SECTION.
    CLASS-METHODS:
      count_rows IMPORTING it_range        TYPE ty_carrid_range
                 RETURNING VALUE(rv_count) TYPE i.

ENDCLASS.


CLASS lcl_seltab_demo IMPLEMENTATION.

  METHOD count_rows.
    SELECT COUNT( * )
      FROM spfli
      WHERE carrid IN @it_range
      INTO @rv_count.
  ENDMETHOD.

*----------------------------------------------------------------------*
* 1. An initial ranges table is TRUE, not FALSE.
*----------------------------------------------------------------------*
  METHOD trap_initial_range.

    DATA lr_empty TYPE ty_carrid_range.       " deliberately left empty

    SELECT COUNT( * ) FROM spfli INTO @DATA(lv_total).

    WRITE: / 'Trap 1 - initial ranges table'.
    WRITE: / '  rows in SPFLI ..............', lv_total.
    WRITE: / '  rows WHERE carrid IN <empty>', count_rows( lr_empty ).
    WRITE: / '  -> identical. Empty means NO RESTRICTION.'.

*   The guard that is missing from most code that builds a range itself.
    IF lr_empty IS INITIAL.
      WRITE: / '  guarded: range is empty, deciding explicitly not to read.'.
    ENDIF.

    SKIP.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 2. I rows are OR-ed. E rows are OR-ed and NEGATED. Both -> AND.
*----------------------------------------------------------------------*
  METHOD trap_exclude_only.

    DATA(lr_include) = VALUE ty_carrid_range(
                         ( sign = 'I' option = 'EQ' low = 'LH' ) ).

*   Only an exclusion. This does NOT select zero rows.
    DATA(lr_exclude) = VALUE ty_carrid_range(
                         ( sign = 'E' option = 'EQ' low = 'LH' ) ).

*   Both signs: ( carrid = 'LH' ) AND carrid <> 'LH'  ->  empty result.
    DATA(lr_both) = VALUE ty_carrid_range(
                      ( sign = 'I' option = 'EQ' low = 'LH' )
                      ( sign = 'E' option = 'EQ' low = 'LH' ) ).

*   The realistic shape: an interval minus one value.
    DATA(lr_minus) = VALUE ty_carrid_range(
                       ( sign = 'I' option = 'BT' low = 'AA' high = 'LH' )
                       ( sign = 'E' option = 'EQ' low = 'DL' ) ).

    WRITE: / 'Trap 2 - I / E set arithmetic'.
    WRITE: / '  I EQ LH .................', count_rows( lr_include ),
             '  (carrid = LH)'.
    WRITE: / '  E EQ LH .................', count_rows( lr_exclude ),
             '  (carrid <> LH - everything else, NOT zero)'.
    WRITE: / '  I EQ LH + E EQ LH .......', count_rows( lr_both ),
             '  (both conditions - impossible, so zero)'.
    WRITE: / '  I BT AA-LH + E EQ DL ....', count_rows( lr_minus ),
             '  (interval minus one value)'.
    SKIP.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 3. The same CP range means different things in SQL and in ABAP.
*----------------------------------------------------------------------*
  METHOD trap_cp_case_split.

*   Lowercase pattern against uppercase carrier IDs (AA, LH, UA, ...).
    DATA(lr_lower) = VALUE ty_carrid_range(
                       ( sign = 'I' option = 'CP' low = 'l*' ) ).

*   Database side: CP becomes LIKE 'l%' ESCAPE '#', which IS case-sensitive.
    DATA(lv_sql_hits) = count_rows( lr_lower ).

*   ABAP side: CP is the character pattern operator, which IGNORES case.
    SELECT carrid FROM spfli INTO TABLE @DATA(lt_all).

    DATA lv_abap_hits TYPE i.
    LOOP AT lt_all TRANSPORTING NO FIELDS WHERE carrid IN lr_lower.
      lv_abap_hits = lv_abap_hits + 1.
    ENDLOOP.

    WRITE: / 'Trap 3 - CP is case-sensitive in SQL, case-insensitive in ABAP'.
    WRITE: / '  range: sign=I option=CP low=''l*'' against uppercase carrids'.
    WRITE: / '  WHERE carrid IN @range (database) ...', lv_sql_hits.
    WRITE: / '  LOOP  ... WHERE carrid IN range (ABAP)', lv_abap_hits.
    WRITE: / '  -> same range, different result set.'.
    SKIP.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 4. Invalid SIGN/OPTION is an uncatchable exception - validate first.
*----------------------------------------------------------------------*
  METHOD guard_before_use.

    rv_valid = abap_true.

    LOOP AT it_range INTO DATA(ls_line).

      IF ls_line-sign <> 'I' AND ls_line-sign <> 'E'.
        rv_valid = abap_false.
        EXIT.
      ENDIF.

      IF ls_line-high IS INITIAL.
*       Single comparison. BT / NB are not valid with an empty HIGH.
        IF ls_line-option <> 'EQ' AND ls_line-option <> 'NE'
       AND ls_line-option <> 'GE' AND ls_line-option <> 'GT'
       AND ls_line-option <> 'LE' AND ls_line-option <> 'LT'
       AND ls_line-option <> 'CP' AND ls_line-option <> 'NP'.
          rv_valid = abap_false.
          EXIT.
        ENDIF.
      ELSE.
*       HIGH is filled: only the interval operators are valid.
        IF ls_line-option <> 'BT' AND ls_line-option <> 'NB'.
          rv_valid = abap_false.
          EXIT.
        ENDIF.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_seltab_demo=>trap_initial_range( ).
  lcl_seltab_demo=>trap_exclude_only( ).
  lcl_seltab_demo=>trap_cp_case_split( ).

  WRITE: / 'Trap 4 - validate before use (invalid values dump uncatchably)'.

* Lowercase sign - would terminate the program if used in a condition.
  DATA(lr_bad_sign) = VALUE ty_carrid_range(
                        ( sign = 'i' option = 'EQ' low = 'LH' ) ).

* EQ with HIGH filled - also invalid.
  DATA(lr_bad_option) = VALUE ty_carrid_range(
                          ( sign = 'I' option = 'EQ' low = 'AA' high = 'LH' ) ).

  DATA(lr_good) = VALUE ty_carrid_range(
                    ( sign = 'I' option = 'BT' low = 'AA' high = 'LH' ) ).

  WRITE: / '  sign = ''i'' ................',
           lcl_seltab_demo=>guard_before_use( lr_bad_sign ).
  WRITE: / '  option = EQ with HIGH filled',
           lcl_seltab_demo=>guard_before_use( lr_bad_option ).
  WRITE: / '  sign = I, option = BT ......',
           lcl_seltab_demo=>guard_before_use( lr_good ).
  SKIP.

* And the selection criterion from the screen, for comparison.
  SELECT COUNT( * )
    FROM spfli
    WHERE carrid IN @s_carrid
    INTO @DATA(lv_screen_hits).

  WRITE: / 'Selection screen: rows matching S_CARRID', lv_screen_hits.
  IF s_carrid[] IS INITIAL.
    WRITE: / '  (S_CARRID is empty -> every row matched)'.
  ENDIF.
