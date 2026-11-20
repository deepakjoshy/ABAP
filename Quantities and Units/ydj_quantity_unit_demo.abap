*&---------------------------------------------------------------------*
*& Report  YDJ_QUANTITY_UNIT_DEMO
*&---------------------------------------------------------------------*
*& Quantities and units of measure: what WRITE ... UNIT actually does,
*& the case where it cancels itself, and what T006 holds behind it.
*&
*& READ-ONLY BY CONSTRUCTION
*&   The only database access is SELECT on T006 (units of measurement,
*&   customizing, client-dependent). No writes, no COMMIT WORK, no
*&   locks, no function module calls, no SUBMIT.
*&
*& WHAT THIS PROGRAM IS NOT
*&   It does not call UNIT_CONVERSION_SIMPLE, the ABAP SQL function
*&   UNIT_CONVERSION or MD_CONVERT_MATERIAL_UNIT. Those need conversion
*&   rules (and a material master) that differ per system, so they are
*&   shipped as commented reference blocks at the end instead of code
*&   that may fail on your system.
*&
*& Sources
*&   WRITE - format_options, addition UNIT
*&     help.sap.com .../ABAPWRITE_TO_OPTIONS.html
*&   DDIC - Quantity Fields
*&     help.sap.com .../ABENDDIC_QUANTITY_FIELD.html
*&   See README.md in this folder.
*&---------------------------------------------------------------------*
REPORT ydj_quantity_unit_demo LINE-SIZE 120.

CLASS lcl_demo DEFINITION FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS run.

  PRIVATE SECTION.
    CONSTANTS c_sep TYPE c LENGTH 1 VALUE '|'.

    CLASS-DATA gv_unit_0 TYPE t006-msehi.   "a unit with DECAN = 0
    CLASS-DATA gv_unit_3 TYPE t006-msehi.   "a unit with DECAN = 3

    CLASS-METHODS pick_units.
    CLASS-METHODS show_trim_rule.
    CLASS-METHODS show_ignored_cases.
    CLASS-METHODS show_currency_contrast.
    CLASS-METHODS show_t006_rule.
    CLASS-METHODS show_unit_is_inert.
    CLASS-METHODS out_row
      IMPORTING iv_label TYPE string
                iv_value TYPE string.

ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

  METHOD run.

    pick_units( ).

    IF gv_unit_0 IS INITIAL AND gv_unit_3 IS INITIAL.
      WRITE: / 'No usable units found in T006 in this client.',
             / 'Maintain units in transaction CUNI and rerun.'.
      RETURN.
    ENDIF.

    IF gv_unit_0 IS INITIAL OR gv_unit_3 IS INITIAL.
*     One of the two was not found, so the rows below that use it show
*     the blank-unit case (addition ignored) rather than the trim case.
      WRITE: / 'NOTE: one unit above is blank - this client has no',
             / 'unit with that DECAN value, so rows using it show the',
             / 'blank-unit no-op instead.'.
      SKIP.
    ENDIF.

    show_trim_rule( ).
    show_ignored_cases( ).
    show_currency_contrast( ).
    show_t006_rule( ).
    show_unit_is_inert( ).

  ENDMETHOD.

  METHOD out_row.

    DATA lv_label TYPE c LENGTH 46.
    DATA lv_value TYPE c LENGTH 60.

    lv_label = iv_label.
    lv_value = iv_value.
    WRITE: / lv_label, c_sep, lv_value.

  ENDMETHOD.

  METHOD pick_units.

*   SAP's own documented idiom for finding a zero-decimal unit:
*   "The first unit ID of the database table T006 is read for which
*    no decimal places are specified in the column DECAN"
    CLEAR gv_unit_0.
    SELECT SINGLE msehi
      FROM t006
      WHERE decan = 0
      INTO @gv_unit_0.
    IF sy-subrc <> 0.
      CLEAR gv_unit_0.
    ENDIF.

    CLEAR gv_unit_3.
    SELECT SINGLE msehi
      FROM t006
      WHERE decan = 3
      INTO @gv_unit_3.
    IF sy-subrc <> 0.
      CLEAR gv_unit_3.
    ENDIF.

    WRITE: / 'Units chosen from T006 in this client'.
    ULINE.
    out_row( iv_label = 'unit with DECAN = 0 (no decimal places)'
             iv_value = CONV string( gv_unit_0 ) ).
    out_row( iv_label = 'unit with DECAN = 3'
             iv_value = CONV string( gv_unit_3 ) ).
    SKIP.

  ENDMETHOD.

  METHOD show_trim_rule.

*   The documented rule: the addition "cuts off the decimal places that
*   have a value of 0 and that lie outside of the accuracy of a
*   measurement unit", and only "if no other places that are not equal
*   to 0 are cut off as a result". So it trims, it never rounds, and it
*   skips itself whenever trimming would lose a digit.
    DATA lv_q1  TYPE p LENGTH 8 DECIMALS 1 VALUE '1.0'.
    DATA lv_q4  TYPE p LENGTH 8 DECIMALS 4 VALUE '2.5000'.
    DATA lv_raw TYPE c LENGTH 20.
    DATA lv_fmt TYPE c LENGTH 20.
    DATA lv_txt TYPE string.

    WRITE: / 'WRITE ... UNIT: same unit, two values, two outcomes'.
    ULINE.

*   1.0 with a 0-decimal unit: the decimal is a zero, so it goes.
    WRITE lv_q1 TO lv_raw NO-GROUPING.
    WRITE lv_q1 TO lv_fmt NO-GROUPING UNIT gv_unit_0.
    CONDENSE lv_raw.
    CONDENSE lv_fmt.
    CONCATENATE lv_raw '->' lv_fmt INTO lv_txt SEPARATED BY space.
    out_row( iv_label = 'p DECIMALS 1 = 1.0 with DECAN 0 unit'
             iv_value = lv_txt ).

*   2.5000 with the same 0-decimal unit: cutting would lose the 5,
*   so the addition is ignored and all four decimals stay.
    WRITE lv_q4 TO lv_raw NO-GROUPING.
    WRITE lv_q4 TO lv_fmt NO-GROUPING UNIT gv_unit_0.
    CONDENSE lv_raw.
    CONDENSE lv_fmt.
    CONCATENATE lv_raw '->' lv_fmt INTO lv_txt SEPARATED BY space.
    out_row( iv_label = 'p DECIMALS 4 = 2.5000 with DECAN 0 unit'
             iv_value = lv_txt ).

*   2.5000 with a 3-decimal unit: one trailing zero is cut, 5 kept.
    WRITE lv_q4 TO lv_fmt NO-GROUPING UNIT gv_unit_3.
    CONDENSE lv_fmt.
    CONCATENATE '2.5000 ->' lv_fmt INTO lv_txt SEPARATED BY space.
    out_row( iv_label = 'p DECIMALS 4 = 2.5000 with DECAN 3 unit'
             iv_value = lv_txt ).

*   1.0 with a 3-decimal unit: the field has FEWER decimals than the
*   unit asks for, so nothing happens. UNIT never appends zeros.
    WRITE lv_q1 TO lv_fmt NO-GROUPING UNIT gv_unit_3.
    CONDENSE lv_fmt.
    CONCATENATE '1.0 ->' lv_fmt INTO lv_txt SEPARATED BY space.
    out_row( iv_label = 'p DECIMALS 1 = 1.0 with DECAN 3 unit'
             iv_value = lv_txt ).

    SKIP.

  ENDMETHOD.

  METHOD show_ignored_cases.

*   "unit expects a character-like field that contains a unit code from
*    the column MSEHI of the database table T006 in uppercase letters"
*   and "If the content of unit is not found in T006, the addition is
*   ignored." Both failures look exactly like success.
    DATA lv_q1    TYPE p LENGTH 8 DECIMALS 1 VALUE '1.0'.
    DATA lv_fmt   TYPE c LENGTH 20.
    DATA lv_lower TYPE t006-msehi.
    DATA lv_bogus TYPE t006-msehi.
    DATA lv_txt   TYPE string.

    lv_lower = gv_unit_0.
    TRANSLATE lv_lower TO LOWER CASE.
    lv_bogus = 'ZZZ'.

    WRITE: / 'The three silent no-ops (no sy-subrc, no message)'.
    ULINE.

*   Only meaningful if the unit actually has letters to lowercase:
*   a unit such as % or a digit-only code is its own lowercase form
*   and would still be found in T006.
    IF lv_lower <> gv_unit_0.
      WRITE lv_q1 TO lv_fmt NO-GROUPING UNIT lv_lower.
      CONDENSE lv_fmt.
      CONCATENATE 'lowercase unit ->' lv_fmt INTO lv_txt
                  SEPARATED BY space.
      out_row( iv_label = 'same unit, lowercased'
               iv_value = lv_txt ).
    ELSE.
      out_row( iv_label = 'same unit, lowercased'
               iv_value = 'skipped: this unit has no case to change' ).
    ENDIF.

    WRITE lv_q1 TO lv_fmt NO-GROUPING UNIT lv_bogus.
    CONDENSE lv_fmt.
    CONCATENATE 'ZZZ ->' lv_fmt INTO lv_txt SEPARATED BY space.
    out_row( iv_label = 'unit not in T006'
             iv_value = lv_txt ).

    CLEAR lv_bogus.
    WRITE lv_q1 TO lv_fmt NO-GROUPING UNIT lv_bogus.
    CONDENSE lv_fmt.
    CONCATENATE 'blank ->' lv_fmt INTO lv_txt SEPARATED BY space.
    out_row( iv_label = 'unit variable never filled'
             iv_value = lv_txt ).

    WRITE: / 'Each case that reached the WRITE printed 1.0 unchanged:',
           / 'the addition was accepted and then did nothing at all.'.
    SKIP.

  ENDMETHOD.

  METHOD show_currency_contrast.

*   CURRENCY is not UNIT's sibling, it is its opposite. For type p it
*   "ignores completely" the field's own decimal places and re-reads
*   the digit sequence. Full treatment in ../Currency Amounts.
    DATA lv_amt TYPE p LENGTH 8 DECIMALS 4 VALUE '2.5000'.
    DATA lv_fmt TYPE c LENGTH 20.
    DATA lv_txt TYPE string.

    WRITE: / 'Contrast: CURRENCY re-reads the digits, UNIT does not'.
    ULINE.

    WRITE lv_amt TO lv_fmt NO-GROUPING CURRENCY 'EUR'.
    CONDENSE lv_fmt.
    CONCATENATE '2.5000 ->' lv_fmt INTO lv_txt SEPARATED BY space.
    out_row( iv_label = 'same value with CURRENCY EUR'
             iv_value = lv_txt ).

    WRITE lv_amt TO lv_fmt NO-GROUPING UNIT gv_unit_3.
    CONDENSE lv_fmt.
    CONCATENATE '2.5000 ->' lv_fmt INTO lv_txt SEPARATED BY space.
    out_row( iv_label = 'same value with UNIT (DECAN 3)'
             iv_value = lv_txt ).

    WRITE: / 'CURRENCY changed which digits are decimals.',
           / 'UNIT only removed zeros; the number is untouched.'.
    SKIP.

  ENDMETHOD.

  METHOD show_t006_rule.

*   What is actually behind a unit: a dimension, two decimal-place
*   columns whose names are anagrams of each other, and a rational
*   factor plus an additive constant towards the SI base unit.
    DATA lv_unit TYPE t006-msehi.

    lv_unit = gv_unit_3.
    IF lv_unit IS INITIAL.
      lv_unit = gv_unit_0.
    ENDIF.

    SELECT SINGLE msehi, dimid, decan, andec,
                  zaehl, nennr, exp10, addko
      FROM t006
      WHERE msehi = @lv_unit
      INTO @DATA(ls_rule).

    IF sy-subrc <> 0.
      WRITE: / 'Unit not readable from T006; skipping the rule dump.'.
      RETURN.
    ENDIF.

    WRITE: / 'The T006 row behind one unit'.
    ULINE.
    out_row( iv_label = 'MSEHI   unit of measurement'
             iv_value = CONV string( ls_rule-msehi ) ).
    out_row( iv_label = 'DIMID   dimension key (check table T006D)'
             iv_value = CONV string( ls_rule-dimid ) ).
    out_row( iv_label = 'DECAN   decimal places for number display'
             iv_value = CONV string( ls_rule-decan ) ).
    out_row( iv_label = 'ANDEC   decimal places for rounding'
             iv_value = CONV string( ls_rule-andec ) ).
    out_row( iv_label = 'ZAEHL   numerator for conversion to SI unit'
             iv_value = CONV string( ls_rule-zaehl ) ).
    out_row( iv_label = 'NENNR   denominator for conversion to SI unit'
             iv_value = CONV string( ls_rule-nennr ) ).
    out_row( iv_label = 'EXP10   base ten exponent, conversion to SI'
             iv_value = CONV string( ls_rule-exp10 ) ).
    out_row( iv_label = 'ADDKO   additive constant for conversion to SI'
             iv_value = CONV string( ls_rule-addko ) ).

    WRITE: / 'DECAN drives WRITE ... UNIT. ANDEC is the rounding',
           / 'accuracy. They are different columns and can differ.',
           / 'ADDKO is why degrees Celsius can be converted at all:',
           / 'a pure multiplicative factor could not do it.'.
    SKIP.

  ENDMETHOD.

  METHOD show_unit_is_inert.

*   "The unit defined for a quantity field only plays a part in ABAP
*    programs if it is specified after the addition UNIT of the
*    statement WRITE [TO]." Everything else treats the unit key as an
*    ordinary character field sitting next to a number.
    DATA lv_a    TYPE p LENGTH 8 DECIMALS 3 VALUE '1.000'.
    DATA lv_b    TYPE p LENGTH 8 DECIMALS 3 VALUE '1.000'.
    DATA lv_sum  TYPE p LENGTH 8 DECIMALS 3.
    DATA lv_txt  TYPE string.

    lv_sum = lv_a + lv_b.

    WRITE: / 'Arithmetic ignores units entirely'.
    ULINE.
    out_row( iv_label = '1.000 of one unit + 1.000 of another'
             iv_value = CONV string( lv_sum ) ).

    IF lv_a = lv_b.
      lv_txt = 'equal'.
    ELSE.
      lv_txt = 'not equal'.
    ENDIF.
    out_row( iv_label = 'comparing the two quantities says'
             iv_value = lv_txt ).

    WRITE: / 'No dump, no message, no sy-subrc: there is no unit',
           / 'algebra in ABAP. Convert first, then calculate.'.
    SKIP.

  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.

  WRITE: / 'YDJ_QUANTITY_UNIT_DEMO - quantities and units of measure'.
  ULINE.
  SKIP.

  lcl_demo=>run( ).

*&---------------------------------------------------------------------*
*& REFERENCE BLOCKS - deliberately NOT executed
*&
*& Each of these needs conversion rules (and for the material variant a
*& material master) that differ per system, so running them here would
*& prove nothing and could dump. Syntax follows the keyword docs cited
*& in README.md.
*&---------------------------------------------------------------------*

*  A. ABAP SQL. Note the result "has the same data type as the formal
*     parameter passed to quantity", so a 0-decimal source field gives
*     a 0-decimal result and the fraction is gone. There is no round
*     and no decimal_shift parameter here - only CURRENCY_CONVERSION
*     has those.
*
*  SELECT FROM demo_expressions
*         FIELDS dec3,
*                unit_conversion(
*                  quantity    = dec3,
*                  source_unit = unit`MI`,
*                  target_unit = unit`KM`,
*                  on_error    =
*                    @sql_unit_conversion=>c_on_error-set_to_null )
*                  AS target_quantity
*         INTO TABLE @DATA(lt_converted).

*  B. The same function in a CDS view entity: => instead of =, the
*     parameter is error_handling with a character literal, and the
*     result of a QUAN input is QUAN with length 31 and 14 decimal
*     places - not the type of the source column.
*
*  @Semantics.quantity.unitOfMeasure: 'converted_unit'
*  unit_conversion( quantity       => dec3,
*                   source_unit    => abap.unit'MI',
*                   target_unit    => $parameters.to_unit,
*                   error_handling => 'SET_TO_NULL' ) as converted_value

*  C. The classic function module. UNIT_IN and UNIT_OUT are OPTIONAL
*     and default to blank, which is what UNITS_MISSING is for.
*     ROUND_SIGN defaults to blank, so commercial rounding is opt-in.
*
*  CALL FUNCTION 'UNIT_CONVERSION_SIMPLE'
*    EXPORTING  input                = lv_qty_in
*               round_sign           = 'X'
*               unit_in              = lv_unit_in
*               unit_out             = lv_unit_out
*    IMPORTING  output               = lv_qty_out
*               add_const            = lv_add_const
*               decimals             = lv_decimals
*               denominator          = lv_denominator
*               numerator            = lv_numerator
*    EXCEPTIONS conversion_not_found = 1
*               division_by_zero     = 2
*               input_invalid        = 3
*               output_invalid       = 4
*               overflow             = 5
*               type_invalid         = 6
*               units_missing        = 7
*               unit_in_not_found    = 8
*               unit_out_not_found   = 9
*               OTHERS               = 10.
*  IF sy-subrc <> 0.
*    "1 means no route between two known units; 8 and 9 mean the unit
*    "itself is not in T006. Do not collapse them into one message.
*  ENDIF.

*  D. Material-specific units (PC to KG) are a different FM, because
*     the factor lives per material in MARM, not in T006.
*
*  CALL FUNCTION 'MD_CONVERT_MATERIAL_UNIT'
*    EXPORTING  i_matnr              = lv_matnr
*               i_in_me              = lv_unit_in
*               i_out_me             = lv_unit_out
*               i_menge              = lv_qty_in
*    IMPORTING  e_menge              = lv_qty_out
*    EXCEPTIONS error_in_application = 1
*               error                = 2
*               OTHERS               = 3.
