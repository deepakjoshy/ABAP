*&---------------------------------------------------------------------*
*& Report YDJ_TYPE_CONVERSION_DEMO
*&---------------------------------------------------------------------*
*& Type conversions - the dangerous ones are the ones that SUCCEED.
*&
*& ABAP assigns almost anything to almost anything. A conversion that
*& dumps is found on the first test run; a conversion that invents a
*& plausible value reaches production, because sy-subrc is untouched
*& and nothing is logged.
*&
*&   1. DIGITS HARVESTED -> the same text is 00000042 in an n field and
*&                          a CX_SY_CONVERSION_NO_NUMBER in an i field.
*&   2. BLANK IS ZERO    -> garbage raises, MISSING input books a 0.
*&   3. NOTATION         -> 1.123E+3 converts into decfloat34 and
*&                          raises into i. Same text, two verdicts.
*&   4. INVALID DATES    -> two reversed date literals are accepted and
*&                          subtract to 0, which is also what two equal
*&                          dates subtract to.
*&   5. EXACT GUARD      -> the same subtraction, guarded. Note the
*&                          CONV string( ) detour: EXACT performs NO
*&                          check on a compatible type.
*&   6. EXACT CALCULATION-> EXACT #( 3 * ( 1 / 3 ) ) refuses to round,
*&                          and hands back the rounded value on the
*&                          exception attribute VALUE.
*&   7. HEX PADDING      -> one invalid character truncates the
*&                          conversion and the rest is hex zeros.
*&   8. TRAILING BLANKS  -> dropped out of a c field, kept out of a
*&                          string. Retyping a field changes results.
*&   9. NUMBERS AS DATES -> day 1 is 02.01.0001, day 0 is an INVALID
*&                          date, out of range is filled with zeros,
*&                          and a time is taken modulo 86,400 seconds.
*&
*& Read-only: no database access at all, no COMMIT, no locks. Every
*& conversion that can raise is wrapped in TRY, so the report always
*& runs to the end and prints the exception text where one occurs.
*&
*& Docs: https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/using-conversion-rules
*&       https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/avoiding-invalid-values
*&       https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-c
*&       https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/exact-lossless-operator
*&       https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/lossless-assignments-rules
*&---------------------------------------------------------------------*
REPORT ydj_type_conversion_demo.

CLASS lcl_conv_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      digits_harvested,
      blank_is_zero,
      notation_decides,
      invalid_date_arithmetic,
      lossless_guard,
      lossless_calculation,
      hex_zero_padding,
      trailing_blanks,
      numbers_as_dates.

  PRIVATE SECTION.

    CLASS-METHODS section
      IMPORTING
        iv_title TYPE string.

ENDCLASS.


CLASS lcl_conv_demo IMPLEMENTATION.

  METHOD section.

    SKIP.
    WRITE: / iv_title.
    ULINE.

  ENDMETHOD.


  METHOD digits_harvested.

    DATA lv_text    TYPE string VALUE '4 Apples + 2 Oranges'.
    DATA lv_numtext TYPE n LENGTH 8.
    DATA lv_int     TYPE i.
    DATA lo_err     TYPE REF TO cx_root.
    DATA lv_msg     TYPE string.

    section( '1. The same text: digits harvested, or not a number at all' ).

    " Character to n: "Other characters are ignored." No exception.
    lv_numtext = lv_text.
    WRITE: / 'text -> n LENGTH 8 :', lv_numtext, ' (documented: 00000042)'.

    " Character to i: must be a number in mathematical or commercial
    " notation, otherwise CX_SY_CONVERSION_NO_NUMBER.
    TRY.
        lv_int = lv_text.
        WRITE: / 'text -> i          :', lv_int, ' (no exception raised)'.
      CATCH cx_sy_conversion_error INTO lo_err.
        lv_msg = lo_err->get_text( ).
        WRITE: / 'text -> i          : exception ->', lv_msg.
    ENDTRY.

  ENDMETHOD.


  METHOD blank_is_zero.

    DATA lv_blank TYPE c LENGTH 10.
    DATA lv_empty TYPE string.
    DATA lv_junk  TYPE c LENGTH 10 VALUE 'ABC'.
    DATA lv_pack  TYPE p LENGTH 8 DECIMALS 2.
    DATA lo_err   TYPE REF TO cx_root.
    DATA lv_msg   TYPE string.

    section( '2. Missing input is zero, wrong input raises' ).

    " "A source field that contains only blank characters is interpreted
    " as the number zero."
    lv_pack = lv_blank.
    WRITE: / '10 blanks  -> p :', lv_pack, ' (silently zero)'.

    " A string of length 0 behaves the same way.
    lv_pack = lv_empty.
    WRITE: / 'empty str  -> p :', lv_pack, ' (silently zero)'.

    " Non-numeric content is the case that IS reported.
    TRY.
        lv_pack = lv_junk.
        WRITE: / 'ABC        -> p :', lv_pack, ' (no exception raised)'.
      CATCH cx_sy_conversion_error INTO lo_err.
        lv_msg = lo_err->get_text( ).
        WRITE: / 'ABC        -> p : exception ->', lv_msg.
    ENDTRY.

  ENDMETHOD.


  METHOD notation_decides.

    DATA lv_sci  TYPE string VALUE '1.123E+3'.
    DATA lv_int  TYPE i.
    DATA lv_dec  TYPE decfloat34.
    DATA lo_err  TYPE REF TO cx_root.
    DATA lv_msg  TYPE string.

    section( '3. Scientific notation: a number for one target, not for another' ).

    TRY.
        lv_int = lv_sci.
        WRITE: / '1.123E+3 -> i          :', lv_int.
      CATCH cx_sy_conversion_error INTO lo_err.
        lv_msg = lo_err->get_text( ).
        WRITE: / '1.123E+3 -> i          : exception ->', lv_msg.
    ENDTRY.

    TRY.
        lv_dec = lv_sci.
        WRITE: / '1.123E+3 -> decfloat34 :', lv_dec, ' (documented: 1123)'.
      CATCH cx_sy_conversion_error INTO lo_err.
        lv_msg = lo_err->get_text( ).
        WRITE: / '1.123E+3 -> decfloat34 : exception ->', lv_msg.
    ENDTRY.

  ENDMETHOD.


  METHOD invalid_date_arithmetic.

    DATA ld_bad1  TYPE d.
    DATA ld_bad2  TYPE d.
    DATA ld_good1 TYPE d.
    DATA ld_good2 TYPE d.
    DATA lv_days  TYPE i.
    DATA lv_raw1  TYPE c LENGTH 8.
    DATA lv_raw2  TYPE c LENGTH 8.

    section( '4. Two invalid dates subtract to zero - so do two equal dates' ).

    " DDMMYYYY written into a d field. Accepted, no exception, and read
    " back as yyyymmdd it is not a date that exists.
    ld_bad1 = '07092009'.
    ld_bad2 = '16092009'.

    " Copied into c fields so the RAW eight characters are visible
    " rather than a formatted date.
    lv_raw1 = ld_bad1.
    lv_raw2 = ld_bad2.
    WRITE: / 'stored as          :', lv_raw1, 'and', lv_raw2.

    lv_days = ld_bad2 - ld_bad1.
    WRITE: / 'difference in days :', lv_days, ' (documented: 0, expected 9)'.

    " The same two days, written in the format the type actually defines.
    ld_good1 = '20090907'.
    ld_good2 = '20090916'.
    lv_days  = ld_good2 - ld_good1.
    WRITE: / 'valid literals     :', lv_days, ' (9)'.

  ENDMETHOD.


  METHOD lossless_guard.

    DATA ld_bad1 TYPE d.
    DATA ld_bad2 TYPE d.
    DATA lv_days TYPE i.
    DATA lo_err  TYPE REF TO cx_root.
    DATA lv_msg  TYPE string.

    section( '5. EXACT - and why the CONV string( ) detour is load-bearing' ).

    ld_bad1 = '07092009'.
    ld_bad2 = '16092009'.

    " EXACT d( ld_bad1 ) would check NOTHING: the argument is already
    " type d, the types are compatible, no conversion takes place, and
    " the syntax check only warns that the EXACT is superfluous. The
    " documented workaround is to force an incompatible pair first.
    TRY.
        lv_days = EXACT d( CONV string( ld_bad2 ) ) -
                  EXACT d( CONV string( ld_bad1 ) ).
        WRITE: / 'guarded difference :', lv_days, ' (no exception raised)'.
      CATCH cx_sy_conversion_error INTO lo_err.
        lv_msg = lo_err->get_text( ).
        WRITE: / 'guarded difference : exception ->', lv_msg.
    ENDTRY.

  ENDMETHOD.


  METHOD lossless_calculation.

    DATA lv_exact   TYPE decfloat34.
    DATA lv_rounded TYPE string.
    DATA lo_round   TYPE REF TO cx_sy_conversion_rounding.
    DATA lv_msg     TYPE string.

    section( '6. EXACT on a calculation: refuses to round, returns the value' ).

    " With an arithmetic expression as its argument, EXACT performs a
    " LOSSLESS CALCULATION instead of a lossless assignment. 3 * ( 1 / 3 )
    " cannot be represented exactly, so it raises rather than quietly
    " rounding - and the rounded result is on the exception object.
    TRY.
        lv_exact = EXACT #( 3 * ( 1 / 3 ) ).
        WRITE: / 'EXACT calculation :', lv_exact, ' (no exception raised)'.
      CATCH cx_sy_conversion_rounding INTO lo_round.
        lv_msg     = lo_round->get_text( ).
        lv_rounded = lo_round->value.
        WRITE: / 'EXACT calculation : exception ->', lv_msg.
        WRITE: / 'rounded value     :', lv_rounded.
    ENDTRY.

  ENDMETHOD.


  METHOD hex_zero_padding.

    DATA lv_hextext TYPE string VALUE '0123456789ABCDEFXXXXXXX'.
    DATA lv_xstr    TYPE xstring.
    DATA lv_shown   TYPE string.

    section( '7. One invalid character, and the rest becomes hex zeros' ).

    " "The first invalid character terminates the conversion from the
    " position of this character and the half-bytes not filled up to
    " that point are padded with hexadecimal 0." No exception.
    "
    " The text is held in a VARIABLE on purpose: the documentation notes
    " that the same characters written as a literal argument would be
    " flagged by the syntax check. A runtime value never is.
    lv_xstr  = lv_hextext.
    lv_shown = lv_xstr.
    WRITE: / 'text with X -> xstring :', lv_shown.
    WRITE: / 'documented result      : 0123456789ABCDEF'.

  ENDMETHOD.


  METHOD trailing_blanks.

    DATA lv_c        TYPE c LENGTH 8 VALUE 'abcd'.
    DATA lv_from_c   TYPE string.
    DATA lv_from_str TYPE string VALUE `abcd    `.
    DATA lv_len_c    TYPE i.
    DATA lv_len_str  TYPE i.

    section( '8. Trailing blanks: dropped out of c, kept out of string' ).

    " c source: "Trailing blanks in the source field are not passed."
    lv_from_c   = lv_c.
    lv_len_c    = strlen( lv_from_c ).

    " string source: the trailing blanks ARE part of the value.
    lv_len_str  = strlen( lv_from_str ).

    WRITE: / 'c LENGTH 8 -> string : length', lv_len_c, ' (4)'.
    WRITE: / 'string literal       : length', lv_len_str, ' (8)'.

  ENDMETHOD.


  METHOD numbers_as_dates.

    DATA ld_day0  TYPE d.
    DATA ld_day1  TYPE d.
    DATA ld_dayx  TYPE d.
    DATA lv_time  TYPE t.
    DATA lv_raw0  TYPE c LENGTH 8.
    DATA lv_raw1  TYPE c LENGTH 8.
    DATA lv_rawx  TYPE c LENGTH 8.
    DATA lv_rawt  TYPE c LENGTH 6.

    section( '9. Integers as day counts: day 1 is the 2nd of January' ).

    " "The assignment of the value 0 to a target field of type d produces
    " the value 0000000 for an invalid date and not 00010101 for
    " 01.01.0001. The earliest valid date that can be created by
    " assigning a number is 02.01.0001 by assigning the number 1."
    ld_day0 = 0.
    ld_day1 = 1.

    " Outside 1 .. 3,652,060 the field is filled with the character 0
    " rather than raising anything.
    ld_dayx = 4000000.

    lv_raw0 = ld_day0.
    lv_raw1 = ld_day1.
    lv_rawx = ld_dayx.

    WRITE: / '0       -> d :', lv_raw0, ' (invalid date, not 00010101)'.
    WRITE: / '1       -> d :', lv_raw1, ' (02.01.0001)'.
    WRITE: / '4000000 -> d :', lv_rawx, ' (out of range, filled with zeros)'.

    " A time is the remainder of a division by the seconds in a day, so
    " 25 hours silently becomes 01:00:00.
    lv_time = 90000.
    lv_rawt = lv_time.
    WRITE: / '90000s  -> t :', lv_rawt, ' (25h modulo 86,400 = 010000)'.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  WRITE: / 'Type conversions - the conversions that succeed are the risk'.
  ULINE.

  lcl_conv_demo=>digits_harvested( ).
  lcl_conv_demo=>blank_is_zero( ).
  lcl_conv_demo=>notation_decides( ).
  lcl_conv_demo=>invalid_date_arithmetic( ).
  lcl_conv_demo=>lossless_guard( ).
  lcl_conv_demo=>lossless_calculation( ).
  lcl_conv_demo=>hex_zero_padding( ).
  lcl_conv_demo=>trailing_blanks( ).
  lcl_conv_demo=>numbers_as_dates( ).

