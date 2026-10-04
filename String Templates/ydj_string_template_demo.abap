*&---------------------------------------------------------------------*
*& Report YDJ_STRING_TEMPLATE_DEMO
*&---------------------------------------------------------------------*
*& String templates |{ }| and their formatting options - the silent
*& behaviours.
*&
*& Nothing here dumps and nothing sets sy-subrc. Every case below
*& produces a wrong-but-plausible string, which is why these survive
*& code review: the template reads like what you meant.
*&
*&   1. PREDEFINED     -> the default format is deliberately dumb. No
*&                        thousands separator, period as decimal point,
*&                        d/t passed RAW (unlike WRITE), trailing blanks
*&                        of c/n dropped but kept for type string.
*&   2. WIDTH          -> a MINIMUM, never a maximum. A value longer
*&                        than WIDTH is left alone and ALIGN/PAD then
*&                        do nothing. Fixed-width exports shift.
*&   3. ALPHA          -> the result length is taken from the TARGET
*&                        FIELD, but only for a bare data object with
*&                        no WIDTH and no literal text. Wrapping the
*&                        operand in a function, or adding one literal
*&                        character, changes the output.
*&   4. CALC TYPE      -> { 2 / 3 } is integer arithmetic. DECIMALS
*&                        formats a value that was already rounded.
*&   5. CURRENCY       -> on a p data object the declared decimals are
*&                        IGNORED and the digits are re-read. On an
*&                        arithmetic expression it rounds instead. So
*&                        "+ 0" changes the result.
*&   6. USER/ENVIRON   -> output depends on the user master record, so
*&                        the file your program writes depends on who
*&                        scheduled it. ENVIRONMENT = USER until
*&                        somebody calls SET COUNTRY.
*&   7. TIME STAMPS    -> a packed time stamp is only a number until
*&                        TIMESTAMP or TIMEZONE is specified. An
*&                        unknown time zone raises for utclong and is
*&                        silently UTC for a packed number.
*&   8. DECIMALS       -> a negative value DIVIDES the number. Above 14
*&                        the exception is UNCATCHABLE (not executed
*&                        here). ZERO = NO yields an empty string.
*&   9. SYNTAX/ORDER   -> escaping, and the left-to-right rule where a
*&                        method's side effect only reaches operands to
*&                        its right.
*&
*& Read-only. No database writes, no COMMIT. Section 5 reads currency
*& customizing (TCURC/TCURX) implicitly through the CURRENCY option.
*& Sections 1, 6 and 7 print values that depend on the executing user
*& and the current date - that is the point of those sections.
*&
*& Verified against the ABAP keyword documentation:
*&   https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_TEMPLATES.html
*&   https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_TEMPLATES_PREDEF_FORMAT.html
*&   https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCOMPUTE_STRING_FORMAT_OPTIONS.html
*&   https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_TEMPLATES_EXPRESSIONS.html
*&---------------------------------------------------------------------*
REPORT ydj_string_template_demo.

TYPES ty_text  TYPE c LENGTH 10.
TYPES ty_texts TYPE STANDARD TABLE OF ty_text WITH EMPTY KEY.

CLASS lcl_template_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      predefined_formats,
      width_is_a_minimum,
      alpha_length_rule,
      calculation_type_trap,
      currency_digit_reread,
      user_dependent_formats,
      packed_time_stamps,
      decimals_edges,
      syntax_and_order,
      side_effect RETURNING VALUE(rv_sep) TYPE string.

  PRIVATE SECTION.

    CLASS-DATA gv_attr TYPE string VALUE `Hello`.

    " Prints a value between markers so trailing blanks stay visible
    " in the list output.
    CLASS-METHODS show
      IMPORTING iv_label TYPE string
                iv_value TYPE string.

ENDCLASS.


CLASS lcl_template_demo IMPLEMENTATION.

  METHOD show.

    DATA lv_line TYPE string.

    lv_line = iv_label && ` [` && iv_value && `]`.
    WRITE: / lv_line.

  ENDMETHOD.


  METHOD predefined_formats.
*   --------------------------------------------------------------
*   1. The format you get with no formatting option at all.
*      Documented: period is ALWAYS the decimal separator, NO
*      thousands separators, and d/t are passed without formatting
*      "unlike in WRITE TO".
*   --------------------------------------------------------------
    DATA lv_amount TYPE p LENGTH 8 DECIMALS 2 VALUE '1234567.89'.
    DATA lv_city   TYPE c LENGTH 20 VALUE 'HAMBURG'.
    DATA lv_str    TYPE string.

    WRITE: / '--- 1. Predefined formats ---'.

    lv_str = |{ lv_amount }|.
    show( iv_label = `  p DECIMALS 2        ` iv_value = lv_str ).

    lv_str = |{ sy-datum }|.
    show( iv_label = `  sy-datum (RAW)      ` iv_value = lv_str ).

    WRITE: / '  WRITE sy-datum instead:'.
    WRITE: / '   ', sy-datum.

*   Trailing blanks: dropped for type c, kept for type string.
    lv_str = |{ lv_city }|.
    show( iv_label = `  c LENGTH 20 'HAMBURG'` iv_value = lv_str ).

    lv_str = |{ CONV string( lv_city ) }|.
    show( iv_label = `  same value as string ` iv_value = lv_str ).

*   An initial utclong is blanks, not zeros.
    DATA lv_utc_init TYPE utclong.

    lv_str = |{ lv_utc_init }|.
    show( iv_label = `  initial utclong      ` iv_value = lv_str ).

  ENDMETHOD.


  METHOD width_is_a_minimum.
*   --------------------------------------------------------------
*   2. "If the value of len is less than the minimum required
*      length, it is ignored. This means that the predefined length
*      cannot be reduced but only increased."
*      So WIDTH pads but never cuts, and the column shifts.
*   --------------------------------------------------------------
    DATA lv_short TYPE c LENGTH 20 VALUE 'HAMBURG'.
    DATA lv_long  TYPE c LENGTH 20 VALUE 'FRANKFURT-ODER'.
    DATA lv_str   TYPE string.
    DATA lv_cut   TYPE string.

    WRITE: / '--- 2. WIDTH is a minimum, not a maximum ---'.

    lv_str = |{ lv_short WIDTH = 10 }|.
    show( iv_label = `  short, WIDTH = 10   ` iv_value = lv_str ).

    lv_str = |{ lv_long WIDTH = 10 }|.
    show( iv_label = `  long,  WIDTH = 10   ` iv_value = lv_str ).

*   ALIGN and PAD only act when WIDTH exceeds the minimum length,
*   so an ignored WIDTH disables them too.
    lv_str = |{ lv_long WIDTH = 10 ALIGN = RIGHT PAD = '.' }|.
    show( iv_label = `  long, RIGHT + PAD   ` iv_value = lv_str ).

*   A real fixed-width column needs the explicit ceiling as well.
    lv_str = |{ lv_long WIDTH = 10 }|.
    lv_cut = lv_str(10).
    show( iv_label = `  padded then cut to 10` iv_value = lv_cut ).

  ENDMETHOD.


  METHOD alpha_length_rule.
*   --------------------------------------------------------------
*   3. The documented rule: the target field length is used only
*      when WIDTH is absent AND the template is a single embedded
*      expression holding a single DATA OBJECT (not an expression).
*      Each variant below breaks one of those conditions.
*   --------------------------------------------------------------
    DATA lv_c20     TYPE c LENGTH 20.
    DATA lv_target1 TYPE c LENGTH 5.
    DATA lv_target2 TYPE c LENGTH 5.
    DATA lv_c10     TYPE ty_text VALUE '0000012345'.
    DATA lt_texts   TYPE ty_texts.
    DATA lv_str     TYPE string.

    WRITE: / '--- 3. ALPHA takes its length from the target ---'.

    lv_c20 = |{ '1234' ALPHA = IN }|.
    lv_str = CONV string( lv_c20 ).
    show( iv_label = `  bare literal -> c(20)` iv_value = lv_str ).

*   Same value, wrapped in a built-in function: the operand is now
*   an expression, so the length used is the argument length (4).
    lv_c20 = |{ to_upper( '1234' ) ALPHA = IN }|.
    lv_str = CONV string( lv_c20 ).
    show( iv_label = `  to_upper( ) -> c(20) ` iv_value = lv_str ).

*   One character of literal text is enough to break the rule.
    lv_c20 = |X{ '1234' ALPHA = IN }|.
    lv_str = CONV string( lv_c20 ).
    show( iv_label = `  with literal text    ` iv_value = lv_str ).

*   The data-losing pair from the documentation. Same source value,
*   two targets of c LENGTH 5. In the first the template right-
*   aligns into 5 and the leading zeros go; in the second it builds
*   all 10 characters and the ordinary ASSIGNMENT cuts the right
*   end - ALPHA is not involved in the loss at all.
    APPEND lv_c10 TO lt_texts.

    lv_target1 = |{ lv_c10 ALPHA = IN }|.
    lv_target2 = |{ lt_texts[ 1 ] ALPHA = IN }|.

    lv_str = CONV string( lv_target1 ).
    show( iv_label = `  c(5) from data object` iv_value = lv_str ).
    lv_str = CONV string( lv_target2 ).
    show( iv_label = `  c(5) from table expr ` iv_value = lv_str ).

*   The defence: state WIDTH and no inference can happen.
    lv_str = |{ lv_c10 ALPHA = OUT WIDTH = 18 }|.
    show( iv_label = `  ALPHA = OUT WIDTH 18 ` iv_value = lv_str ).

  ENDMETHOD.


  METHOD calculation_type_trap.
*   --------------------------------------------------------------
*   4. "If the conversion operator is not specified, the
*      calculation type of the embedded expression is i."
*      DECIMALS cannot restore precision that integer division
*      already threw away.
*   --------------------------------------------------------------
    DATA lv_str TYPE string.

    WRITE: / '--- 4. Embedded arithmetic is calculation type i ---'.

    lv_str = |{ - 2 / 3 }|.
    show( iv_label = `  { - 2 / 3 }          ` iv_value = lv_str ).

    lv_str = |{ - 2 / 3 DECIMALS = 3 }|.
    show( iv_label = `  ... DECIMALS = 3     ` iv_value = lv_str ).

    lv_str = |{ CONV decfloat34( - 2 / 3 ) DECIMALS = 3 }|.
    show( iv_label = `  CONV decfloat34 first` iv_value = lv_str ).

  ENDMETHOD.


  METHOD currency_digit_reread.
*   --------------------------------------------------------------
*   5. For a p DATA OBJECT: "the decimal places specified in the
*      definition of the data type are completely ignored.
*      Regardless of the actual value and without rounding, a
*      decimal separator is inserted between the digits in the
*      places determined by cur."
*      For an ARITHMETIC EXPRESSION: "CURRENCY works as in
*      DECIMALS." Hence the "+ 0" below changes the answer.
*   --------------------------------------------------------------
    DATA lv_three TYPE p LENGTH 8 DECIMALS 3 VALUE '1.234'.
    DATA lv_cent  TYPE p LENGTH 8 VALUE 12345678.
    DATA lv_str   TYPE string.

    WRITE: / '--- 5. CURRENCY re-reads the digits ---'.

    lv_str = |{ lv_three CURRENCY = 'EUR' }|.
    show( iv_label = `  p DEC 3 value 1.234  ` iv_value = lv_str ).

    lv_str = |{ lv_three + 0 CURRENCY = 'EUR' }|.
    show( iv_label = `  same value, "+ 0"    ` iv_value = lv_str ).

*   The intended use: an integer or a p field WITHOUT decimals
*   holding the amount in the smallest unit of the currency.
    lv_str = |{ lv_cent CURRENCY = 'EUR' }|.
    show( iv_label = `  12345678 as EUR      ` iv_value = lv_str ).

*   No thousands separators are added - CURRENCY does not override
*   that part of the predefined format.

  ENDMETHOD.


  METHOD user_dependent_formats.
*   --------------------------------------------------------------
*   6. RAW is the default for NUMBER, DATE and TIME. USER and
*      ENVIRONMENT delegate the format to settings outside the
*      program, so the output differs per user. ENVIRONMENT equals
*      USER until SET COUNTRY has been executed.
*   --------------------------------------------------------------
    DATA lv_million TYPE p LENGTH 8 DECIMALS 2 VALUE '1234567.89'.
    DATA lv_str     TYPE string.

    WRITE: / '--- 6. RAW vs USER vs ENVIRONMENT ---'.

    lv_str = |{ lv_million NUMBER = RAW }|.
    show( iv_label = `  NUMBER = RAW         ` iv_value = lv_str ).

    lv_str = |{ lv_million NUMBER = USER }|.
    show( iv_label = `  NUMBER = USER        ` iv_value = lv_str ).

    lv_str = |{ lv_million NUMBER = ENVIRONMENT }|.
    show( iv_label = `  NUMBER = ENVIRONMENT ` iv_value = lv_str ).

    lv_str = |{ sy-datum DATE = ISO }|.
    show( iv_label = `  DATE = ISO           ` iv_value = lv_str ).

    lv_str = |{ sy-datum DATE = USER }|.
    show( iv_label = `  DATE = USER          ` iv_value = lv_str ).

    lv_str = |{ sy-uzeit TIME = ISO }|.
    show( iv_label = `  TIME = ISO (24h only)` iv_value = lv_str ).

*   COUNTRY formats one expression with no session side effects,
*   unlike SET COUNTRY. An unknown value raises CX_SY_STRG_FORMAT,
*   so it is guarded here.
    TRY.
        lv_str = |{ lv_million COUNTRY = 'DE' }|.
        show( iv_label = `  COUNTRY = 'DE'       ` iv_value = lv_str ).
      CATCH cx_sy_strg_format.
        WRITE: / '  COUNTRY = ''DE'' not customized in T005X here'.
    ENDTRY.

  ENDMETHOD.


  METHOD packed_time_stamps.
*   --------------------------------------------------------------
*   7. "A time stamp represented as a packed number is identified
*      and formatted as a time stamp only by using the formatting
*      options TIMESTAMP or TIMEZONE."
*      And for an unknown time zone: utclong raises, while a packed
*      number silently uses UTC.
*   --------------------------------------------------------------
    DATA lv_tsp TYPE timestamp VALUE '20261005081500'.
    DATA lv_str TYPE string.

    WRITE: / '--- 7. Packed time stamps ---'.

    lv_str = |{ lv_tsp }|.
    show( iv_label = `  no option            ` iv_value = lv_str ).

    lv_str = |{ lv_tsp TIMESTAMP = SPACE }|.
    show( iv_label = `  TIMESTAMP = SPACE    ` iv_value = lv_str ).

    lv_str = |{ lv_tsp TIMESTAMP = ISO }|.
    show( iv_label = `  TIMESTAMP = ISO      ` iv_value = lv_str ).

    lv_str = |{ lv_tsp TIMESTAMP = ISO DECIMALS = 0 }|.
    show( iv_label = `  ... DECIMALS = 0     ` iv_value = lv_str ).

*   Unknown time zone on a PACKED time stamp: no exception, the
*   value is simply formatted as UTC.
    TRY.
        lv_str = |{ lv_tsp TIMEZONE = 'NOSUCH' }|.
        show( iv_label = `  TIMEZONE = 'NOSUCH'  ` iv_value = lv_str ).
      CATCH cx_sy_conversion_no_date_time.
        WRITE: / '  packed + unknown zone raised (not documented)'.
    ENDTRY.

*   The same unknown zone on a utclong is documented to raise.
    DATA lv_utc TYPE utclong.

    lv_utc = utclong_current( ).

    TRY.
        lv_str = |{ lv_utc TIMEZONE = 'NOSUCH' }|.
        show( iv_label = `  utclong, bad zone    ` iv_value = lv_str ).
      CATCH cx_sy_conversion_no_date_time.
        WRITE: / '  utclong + unknown zone -> CX_SY_CONVERSION_NO_DATE_TIME'.
    ENDTRY.

  ENDMETHOD.


  METHOD decimals_edges.
*   --------------------------------------------------------------
*   8. "If the content of dec is less than 0, it is handled like 0,
*      whereby the content of data objects of data types (b, s), i,
*      int8, or p is multiplied by 10 to the power of dec
*      beforehand." A negative DECIMALS divides the number.
*      DECIMALS above 14 on i/p raises an UNCATCHABLE exception -
*      deliberately NOT executed below.
*   --------------------------------------------------------------
    DATA lv_int   TYPE i VALUE 12345.
    DATA lv_dec   TYPE i VALUE -2.
    DATA lv_zero  TYPE i VALUE 0.
    DATA lv_str   TYPE string.

    WRITE: / '--- 8. DECIMALS edges and ZERO ---'.

    lv_str = |{ lv_int }|.
    show( iv_label = `  12345, no option     ` iv_value = lv_str ).

    lv_str = |{ lv_int DECIMALS = 2 }|.
    show( iv_label = `  DECIMALS = 2         ` iv_value = lv_str ).

    lv_str = |{ lv_int DECIMALS = lv_dec }|.
    show( iv_label = `  DECIMALS = -2        ` iv_value = lv_str ).

    lv_str = |{ lv_zero ZERO = YES }|.
    show( iv_label = `  0 with ZERO = YES    ` iv_value = lv_str ).

    lv_str = |{ lv_zero ZERO = NO }|.
    show( iv_label = `  0 with ZERO = NO     ` iv_value = lv_str ).

  ENDMETHOD.


  METHOD side_effect.
*   Changes an attribute that is also used as an embedded operand,
*   to show the left-to-right rule in section 9.
    gv_attr = ` world!`.
    rv_sep  = `,`.

  ENDMETHOD.


  METHOD syntax_and_order.
*   --------------------------------------------------------------
*   9. Escaping, and: "If an embedded functional method modifies
*      the value of data objects that are also used as embedded
*      operands, the change only affects data objects on the right
*      of the method."
*   --------------------------------------------------------------
    DATA lv_str TYPE string.

    WRITE: / '--- 9. Escaping and evaluation order ---'.

    lv_str = |Pipe \| brace \{ \} backslash \\|.
    show( iv_label = `  escaped specials     ` iv_value = lv_str ).

*   gv_attr is read, then changed by side_effect( ), then read
*   again. Only the second read sees the new value.
    gv_attr = `Hello`.
    lv_str  = |{ gv_attr }{ side_effect( ) }{ gv_attr }|.
    show( iv_label = `  left-to-right result ` iv_value = lv_str ).

*   A template of pure literal text is still evaluated at runtime.
*   Use a backtick literal for that.
    lv_str = `ERROR`.
    show( iv_label = `  backtick literal     ` iv_value = lv_str ).

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_template_demo=>predefined_formats( ).
  lcl_template_demo=>width_is_a_minimum( ).
  lcl_template_demo=>alpha_length_rule( ).
  lcl_template_demo=>calculation_type_trap( ).
  lcl_template_demo=>currency_digit_reread( ).
  lcl_template_demo=>user_dependent_formats( ).
  lcl_template_demo=>packed_time_stamps( ).
  lcl_template_demo=>decimals_edges( ).
  lcl_template_demo=>syntax_and_order( ).
