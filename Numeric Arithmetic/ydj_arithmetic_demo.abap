*&---------------------------------------------------------------------*
*& Report YDJ_ARITHMETIC_DEMO
*&---------------------------------------------------------------------*
*& Numeric arithmetic - the calculation type decides, not the operands.
*&
*& ABAP picks a CALCULATION TYPE before it calculates, and the type of
*& the TARGET FIELD is part of that decision. The same expression
*& therefore yields different numbers depending on what it is assigned
*& to - with no syntax warning and no sy-subrc.
*&
*&   1. TARGET DECIDES   -> 5 / 2 is 3 into an i, 2.50 into a p.
*&   2. ROUNDING         -> ABAP division ROUNDS commercially, it does
*&                          not truncate, and with calc type i EVERY
*&                          interim result is rounded. So 1 / 3 * 3 = 0
*&                          while 3 * 1 / 3 = 1.
*&   3. DIV / MOD        -> the ABAP MOD result is ALWAYS positive, and
*&                          DIV is bent to match: -7 DIV 3 is -3, not -2.
*&   4. SQL DIV / MOD    -> the SQL functions of the same name use the
*&                          OPPOSITE sign rule. Pushing a calculation
*&                          into a SELECT changes the answer.
*&   5. ** OPERATOR      -> forces calculation type f all by itself.
*&                          Use ipow( ) for integer exponents.
*&   6. INLINE DECL      -> calc type p + DATA(x) gives p LENGTH 8
*&                          DECIMALS 0. Decimals are lost, not hidden.
*&   7. ZERO DIVISION    -> 1 / 0 raises, but 0 / 0 returns 0 silently.
*&   8. CONVERSION       -> assigning a negative p to an n field stores
*&                          the ABSOLUTE value. The sign just vanishes.
*&
*& Read-only. Section 4 is the only part that touches the database and
*& it reads a single row from T000 purely to get a SQL evaluation.
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENARITH_OPERATORS.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENARITH_TYPE.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_FUNCTIONS_NUMERIC.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_P.html
*&---------------------------------------------------------------------*
REPORT ydj_arithmetic_demo.

CLASS lcl_arith_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      target_type_decides,
      rounding_not_truncation,
      div_mod_signs,
      div_mod_in_sql,
      power_operator_trap,
      inline_declaration_trap,
      division_by_zero,
      conversion_out_of_packed,
      overflow_behaviour.

ENDCLASS.


CLASS lcl_arith_demo IMPLEMENTATION.

  METHOD target_type_decides.

    " ---------------------------------------------------------------
    " THE HEADLINE.
    " One expression, three targets, three different values. The
    " calculation type is derived from the operands AND the result
    " field, so the target is not just a container - it is an input.
    " ---------------------------------------------------------------
    DATA lv_int  TYPE i.
    DATA lv_pack TYPE p LENGTH 8 DECIMALS 2.
    DATA lv_dec  TYPE decfloat34.

    lv_int  = 5 / 2.
    lv_pack = 5 / 2.
    lv_dec  = 5 / 2.

    WRITE: / '1. Same expression "5 / 2", three target types'.
    WRITE: /   '   into i          :', lv_int.
    WRITE: /   '   into p DEC 2    :', lv_pack.
    WRITE: /   '   into decfloat34 :', lv_dec.
    SKIP.

  ENDMETHOD.


  METHOD rounding_not_truncation.

    " ---------------------------------------------------------------
    " ABAP rounds commercially where C/Java/Python truncate. With
    " calculation type i, EVERY interim result that is not an integer
    " is rounded - so operator order changes the answer even though
    " * and / have the same priority and run left to right.
    " ---------------------------------------------------------------
    DATA lv_i TYPE i.

    WRITE: / '2. Division rounds, it does not truncate'.

    lv_i = 1 / 3 * 3.
    WRITE: / '   1 / 3 * 3 =', lv_i, '( 1/3 rounds to 0 first )'.

    lv_i = 3 * 1 / 3.
    WRITE: / '   3 * 1 / 3 =', lv_i, '( 3*1 = 3 first, then 3/3 )'.

    " The explicit ways to get the other languages' behaviour.
    lv_i = 5 DIV 2.
    WRITE: / '   5 DIV 2   =', lv_i, '( integer part, no rounding )'.

    lv_i = floor( CONV decfloat34( 5 ) / 2 ).
    WRITE: / '   floor( )  =', lv_i, '( explicit truncation )'.
    SKIP.

  ENDMETHOD.


  METHOD div_mod_signs.

    " ---------------------------------------------------------------
    " ABAP follows the division theorem: a = q*b + r with 0 <= r < |b|.
    " MOD is therefore ALWAYS positive, and DIV is defined so that
    " ( a DIV b ) * b + ( a MOD b ) reconstructs a. Note -7 DIV 3 = -3.
    " ---------------------------------------------------------------
    TYPES: BEGIN OF ty_case,
             a TYPE i,
             b TYPE i,
           END OF ty_case.

    DATA(lt_cases) = VALUE STANDARD TABLE OF ty_case(
                       ( a =  7  b =  3 )
                       ( a = -7  b =  3 )
                       ( a =  7  b = -3 )
                       ( a = -7  b = -3 ) ).

    WRITE: / '3. ABAP DIV / MOD - the MOD result is always positive'.

    LOOP AT lt_cases ASSIGNING FIELD-SYMBOL(<ls_case>).

      DATA(lv_div) = <ls_case>-a DIV <ls_case>-b.
      DATA(lv_mod) = <ls_case>-a MOD <ls_case>-b.

      WRITE: /   '  ', <ls_case>-a, 'DIV', <ls_case>-b, '=', lv_div,
                 '   ', <ls_case>-a, 'MOD', <ls_case>-b, '=', lv_mod.

    ENDLOOP.
    SKIP.

  ENDMETHOD.


  METHOD div_mod_in_sql.

    " ---------------------------------------------------------------
    " THE CROSS-BOUNDARY TRAP.
    " div( ) and mod( ) in ABAP SQL are FUNCTIONS, not the operators,
    " and they use the HANA/CPU sign rule instead: truncate toward
    " zero, remainder takes the sign of the dividend. So -7 mod 3 is
    " -1 here but 2 in ABAP above. Moving a calculation into the
    " SELECT list for performance silently changes the result.
    " ---------------------------------------------------------------
    DATA lv_a TYPE i VALUE -7.
    DATA lv_b TYPE i VALUE 3.

    WRITE: / '4. The SAME operation in ABAP SQL uses the OPPOSITE rule'.

    TRY.
        SELECT SINGLE FROM t000
          FIELDS div( @lv_a, @lv_b ) AS sql_div,
                 mod( @lv_a, @lv_b ) AS sql_mod
          WHERE  mandt = @sy-mandt
          INTO @DATA(ls_sql).

        IF sy-subrc = 0.
          WRITE: / '   ABAP :', lv_a, 'DIV', lv_b, '=', lv_a DIV lv_b,
                     '  MOD =', lv_a MOD lv_b.
          WRITE: / '   SQL  :', lv_a, 'div', lv_b, '=', ls_sql-sql_div,
                     '  mod =', ls_sql-sql_mod.
        ENDIF.

      CATCH cx_sy_open_sql_error INTO DATA(lx_sql).
        WRITE: / '   SQL evaluation not available here:',
                 lx_sql->get_text( ).
    ENDTRY.
    SKIP.

  ENDMETHOD.


  METHOD power_operator_trap.

    " ---------------------------------------------------------------
    " ** is the only operator that sets the calculation type by
    " itself: without a decimal floating point operand it forces f,
    " i.e. binary floating point with ~15 places of precision and
    " exact integers only up to 2**53. ipow( ) takes its calculation
    " type from the argument instead.
    " ---------------------------------------------------------------
    DATA(lv_pow)  = 2 ** 10.
    DATA(lv_ipow) = ipow( base = 2 exp = 10 ).

    DATA(lv_pow_kind)  = cl_abap_typedescr=>describe_by_data(
                           lv_pow )->type_kind.
    DATA(lv_ipow_kind) = cl_abap_typedescr=>describe_by_data(
                           lv_ipow )->type_kind.

    WRITE: / '5. ** forces calculation type f'.
    WRITE: / '   2 ** 10            type kind:', lv_pow_kind,
             '( F = binary float )'.
    WRITE: / '   ipow( base=2 exp=10 ) kind:', lv_ipow_kind,
             '( I = integer )'.
    SKIP.

  ENDMETHOD.


  METHOD inline_declaration_trap.

    " ---------------------------------------------------------------
    " Calculation type p assigned to an inline declaration always
    " produces p with LENGTH 8 and NO decimal places. The decimals are
    " genuinely gone, not merely unformatted. The doc's own advice is
    " to avoid inline declarations here, or to steer the type with
    " CONV.
    " ---------------------------------------------------------------
    DATA lv_amount TYPE p LENGTH 8 DECIMALS 2 VALUE '10.50'.

    DATA(lv_bad) = lv_amount / 4.
    DATA(lv_ok)  = CONV decfloat34( lv_amount / 4 ).

    WRITE: / '6. Inline declaration with calculation type p'.
    WRITE: / '   DATA(x) = 10.50 / 4          :', lv_bad,
             '( p DECIMALS 0 )'.
    WRITE: / '   CONV decfloat34( 10.50 / 4 ) :', lv_ok.
    SKIP.

  ENDMETHOD.


  METHOD division_by_zero.

    " ---------------------------------------------------------------
    " Division by zero raises CX_SY_ZERODIVIDE - EXCEPT when the
    " dividend is also zero, where the result is defined as 0 and
    " nothing is raised. "It did not dump, so the divisor was fine"
    " is therefore not a valid inference.
    " ---------------------------------------------------------------
    DATA lv_zero   TYPE i VALUE 0.
    DATA lv_result TYPE i.

    WRITE: / '7. Division by zero'.

    TRY.
        lv_result = 0 / lv_zero.
        WRITE: / '   0 / 0 =', lv_result, '( no exception raised )'.
      CATCH cx_sy_zerodivide.
        WRITE: / '   0 / 0 raised an exception'.
    ENDTRY.

    TRY.
        lv_result = 1 / lv_zero.
        WRITE: / '   1 / 0 =', lv_result.
      CATCH cx_sy_zerodivide INTO DATA(lx_zero).
        WRITE: / '   1 / 0 raised CX_SY_ZERODIVIDE:',
                 lx_zero->get_text( ).
    ENDTRY.
    SKIP.

  ENDMETHOD.


  METHOD conversion_out_of_packed.

    " ---------------------------------------------------------------
    " Assigning a packed number to a type n field rounds it AND takes
    " the ABSOLUTE value. The sign disappears with no exception and no
    " sy-subrc. Assigning to a too-short c field truncates on the LEFT
    " and marks it with '*' - the classic "report full of stars".
    " ---------------------------------------------------------------
    DATA lv_neg   TYPE p LENGTH 8 DECIMALS 2 VALUE '-12.34'.
    DATA lv_num   TYPE n LENGTH 5.
    DATA lv_short TYPE c LENGTH 4.
    DATA lv_p3    TYPE p LENGTH 8 DECIMALS 3 VALUE '0.815'.

    lv_num   = lv_neg.
    lv_short = lv_neg.

    DATA(lv_float) = CONV f( lv_p3 ).

    WRITE: / '8. Conversion out of a packed number'.
    WRITE: / '   source p DECIMALS 2 :', lv_neg.
    WRITE: / '   into n LENGTH 5     :', lv_num,
             '( sign discarded, rounded )'.
    WRITE: / '   into c LENGTH 4     :', lv_short,
             '( truncated on the LEFT )'.
    WRITE: / '   CONV f( 0.815 )     :', lv_float,
             '( not exactly 0.815 )'.
    SKIP.

  ENDMETHOD.


  METHOD overflow_behaviour.

    " ---------------------------------------------------------------
    " Calculation type i requires every INTERIM result to fit type i.
    " Calculation type p is more forgiving: it retries the whole
    " expression at 63 places before giving up.
    " ---------------------------------------------------------------
    DATA lv_max    TYPE i VALUE 2147483647.
    DATA lv_result TYPE i.

    WRITE: / '9. Overflow of an interim result'.

    TRY.
        lv_result = lv_max + 1.
        WRITE: / '   max_int + 1 =', lv_result.
      CATCH cx_sy_arithmetic_overflow INTO DATA(lx_over).
        WRITE: / '   max_int + 1 raised CX_SY_ARITHMETIC_OVERFLOW:',
                 lx_over->get_text( ).
    ENDTRY.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_arith_demo=>target_type_decides( ).
  lcl_arith_demo=>rounding_not_truncation( ).
  lcl_arith_demo=>div_mod_signs( ).
  lcl_arith_demo=>div_mod_in_sql( ).
  lcl_arith_demo=>power_operator_trap( ).
  lcl_arith_demo=>inline_declaration_trap( ).
  lcl_arith_demo=>division_by_zero( ).
  lcl_arith_demo=>conversion_out_of_packed( ).
  lcl_arith_demo=>overflow_behaviour( ).
