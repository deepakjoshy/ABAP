*&---------------------------------------------------------------------*
*& Report YDJ_CURRENCY_AMOUNT_DEMO
*&---------------------------------------------------------------------*
*& Currency amounts: what is actually stored, and what it means.
*&
*& A CURR field stores an INTEGER IN THE SMALLEST CURRENCY UNIT. The
*& decimal separator you see belongs to the type, not to the value.
*& Every CURR field defaults to 2 decimals; the real decimal count per
*& currency lives in TCURX and only differs from 2 when maintained.
*&
*& So 2 JPY sits in the database as 0.02 - and that is correct data.
*&
*& This report takes a currency key and an amount as a HUMAN would write
*& it, and shows:
*&   1. TCURX-CURRDEC for the currency (the decimal truth)
*&   2. the internal CURR value that amount is stored as
*&   3. what WRITE prints with and without the CURRENCY addition
*&   4. the BAPI external/internal round trip, RETURN code included
*&   5. the arithmetic that is safe vs the arithmetic that silently lies
*&
*& Try it with EUR (not in TCURX -> 2), JPY (0) and TND (3).
*&
*& Prerequisite: none. TCURX exists in every AS ABAP system.
*&---------------------------------------------------------------------*
REPORT ydj_currency_amount_demo.

PARAMETERS: p_waers TYPE tcurc-waers OBLIGATORY DEFAULT 'JPY',
            p_amt   TYPE bapicurr-bapicurr OBLIGATORY DEFAULT '2'.


CLASS lcl_currency_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS execute
      IMPORTING iv_waers    TYPE tcurc-waers
                iv_external TYPE bapicurr-bapicurr.

  PRIVATE SECTION.

    " CURRDEC as maintained, or 2 when the currency is not in TCURX
    CLASS-METHODS decimals_of
      IMPORTING iv_waers         TYPE tcurc-waers
      RETURNING VALUE(rv_currdec) TYPE tcurx-currdec.

    CLASS-METHODS to_internal
      IMPORTING iv_waers           TYPE tcurc-waers
                iv_external        TYPE bapicurr-bapicurr
      EXPORTING ev_internal        TYPE wrbtr
                es_return          TYPE bapireturn.

    " NOTE: TO_EXTERNAL has no RETURN and no MAX_NUMBER_OF_DIGITS -
    " its interface is not symmetric with TO_INTERNAL. See README.md.
    CLASS-METHODS to_external
      IMPORTING iv_waers           TYPE tcurc-waers
                iv_internal        TYPE wrbtr
      RETURNING VALUE(rv_external) TYPE bapicurr-bapicurr.

    CLASS-METHODS show_arithmetic
      IMPORTING iv_waers    TYPE tcurc-waers
                iv_internal TYPE wrbtr.

ENDCLASS.


CLASS lcl_currency_demo IMPLEMENTATION.

  METHOD decimals_of.

    SELECT SINGLE currdec FROM tcurx
      INTO @rv_currdec
      WHERE currkey = @iv_waers.

    IF sy-subrc <> 0.
      " Not in TCURX is not an error - it is the 2-decimal default
      rv_currdec = 2.
    ENDIF.

  ENDMETHOD.


  METHOD to_internal.

    CLEAR: ev_internal, es_return.

    CALL FUNCTION 'BAPI_CURRENCY_CONV_TO_INTERNAL'
      EXPORTING
        currency              = iv_waers
        amount_external       = iv_external
        max_number_of_digits  = 23
      IMPORTING
        amount_internal       = ev_internal
        return                = es_return.

  ENDMETHOD.


  METHOD to_external.

    CLEAR rv_external.

    CALL FUNCTION 'BAPI_CURRENCY_CONV_TO_EXTERNAL'
      EXPORTING
        currency              = iv_waers
        amount_internal       = iv_internal
      IMPORTING
        amount_external       = rv_external.

  ENDMETHOD.


  METHOD show_arithmetic.

    DATA lv_literal TYPE wrbtr.

    WRITE: / '5. ARITHMETIC'.
    ULINE.

    " SAFE: two amounts, same currency, same decimals
    DATA(lv_sum) = iv_internal + iv_internal.
    WRITE: / '  safe   amount + amount   =',
             lv_sum CURRENCY iv_waers, iv_waers.

    " SAFE: amount times a plain, non-currency-dependent factor
    DATA(lv_scaled) = iv_internal * 3.
    WRITE: / '  safe   amount * 3        =',
             lv_scaled CURRENCY iv_waers, iv_waers.

    " CRITICAL: a literal assigned straight into a CURR field.
    " The digits go in unchanged, so the MEANING depends on TCURX.
    lv_literal = 1000.
    WRITE: / '  UNSAFE literal 1000 into CURR reads back as',
             lv_literal CURRENCY iv_waers, iv_waers.
    WRITE: / '         (raw field content:', lv_literal, ')'.

  ENDMETHOD.


  METHOD execute.

    DATA lv_internal   TYPE wrbtr.
    DATA lv_roundtrip  TYPE bapicurr-bapicurr.
    DATA ls_return_in  TYPE bapireturn.

    DATA(lv_currdec) = decimals_of( iv_waers ).

    WRITE: / '1. TCURX'.
    ULINE.
    WRITE: / '  currency                 :', iv_waers.
    WRITE: / '  TCURX-CURRDEC            :', lv_currdec.
    IF lv_currdec = 2.
      WRITE: / '  (2 = either maintained as 2, or not in TCURX at all)'.
    ELSE.
      WRITE: / '  (differs from the CURR default of 2 - shift required)'.
    ENDIF.
    SKIP.

    to_internal( EXPORTING iv_waers    = iv_waers
                           iv_external = iv_external
                 IMPORTING ev_internal = lv_internal
                           es_return   = ls_return_in ).

    WRITE: / '2. EXTERNAL -> INTERNAL'.
    ULINE.
    WRITE: / '  amount as a human writes it:', iv_external.
    WRITE: / '  stored in the CURR field   :', lv_internal.
    IF ls_return_in-code IS NOT INITIAL.
      WRITE: / '  RETURN code                :', ls_return_in-code,
                                                 ls_return_in-message.
    ENDIF.
    SKIP.

    WRITE: / '3. OUTPUT'.
    ULINE.
    WRITE: / '  WRITE without CURRENCY     :', lv_internal.
    WRITE: / '  WRITE ... CURRENCY', iv_waers, ':',
             lv_internal CURRENCY iv_waers.
    WRITE: / '  string template            :',
             |{ lv_internal CURRENCY = iv_waers }|.
    SKIP.

    lv_roundtrip = to_external( iv_waers    = iv_waers
                                iv_internal = lv_internal ).

    WRITE: / '4. INTERNAL -> EXTERNAL (round trip)'.
    ULINE.
    WRITE: / '  back to external format    :', lv_roundtrip.
    IF lv_roundtrip = iv_external.
      WRITE: / '  round trip is lossless.'.
    ELSE.
      WRITE: / '  ROUND TRIP LOST PRECISION - check MAX_NUMBER_OF_DIGITS',
               'and RETURN.'.
    ENDIF.
    SKIP.

    show_arithmetic( iv_waers    = iv_waers
                     iv_internal = lv_internal ).

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.
  lcl_currency_demo=>execute( iv_waers    = p_waers
                              iv_external = p_amt ).
