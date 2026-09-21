*&---------------------------------------------------------------------*
*& Report YDJ_ALPHA_CONVERSION_DEMO
*&---------------------------------------------------------------------*
*& Conversion routines (conversion exits) and the ALPHA formatting
*& option - why a key that exists in SE16 is not found by SELECT.
*&
*& A conversion routine is a property of the DOMAIN, not of the data
*& type. It runs automatically in exactly four places: dynpro field in,
*& dynpro field out, WRITE and WRITE TO. It does NOT run in SELECT, in
*& assignments, in internal table reads, in RFC parameters or in JSON.
*&
*&   1. NOT A CONVERSION -> ALPHA = IN pads ONLY if the value is an
*&                          uninterrupted string of digits. Anything
*&                          else is returned unchanged and unpadded,
*&                          with no error. It is not a validation.
*&   2. WIDTH TRAP       -> without WIDTH the available length comes
*&                          from the TARGET field, but only if the
*&                          embedded expression is a single data object.
*&                          Wrap it in anything and the SOURCE length is
*&                          used instead - truncating at the other end.
*&   3. STRING TARGET    -> an inline DATA( ) target is a string, not a
*&                          fixed-length field, so the target-length
*&                          rule cannot apply and nothing is padded.
*&   4. OUT IS LOSSY     -> ALPHA = OUT discards the field length. It
*&                          cannot be reversed without knowing WIDTH,
*&                          so it is a display format only.
*&   5. THE SELECT BUG   -> '4711' and '000000000000004711' are both
*&                          valid CHAR 18 values. Comparing them is
*&                          FALSE, which is why the WHERE clause fails
*&                          silently on an unconverted literal.
*&   6. WIDTH TOO SMALL  -> a WIDTH below the significant length is
*&                          IGNORED, not truncated - the result can be
*&                          longer than the width requested.
*&
*& Read-only. No database access, no changes of any kind. Every value
*& used here is a literal, so the report runs in any system.
*&
*& Docs: https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-us/abenconversion_exits.htm
*&       https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapcompute_string_format_options.htm
*&       https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapwrite_to.htm
*&---------------------------------------------------------------------*
REPORT ydj_alpha_conversion_demo.

TYPES: ty_text  TYPE c LENGTH 10,
       ty_texts TYPE STANDARD TABLE OF ty_text WITH EMPTY KEY.

CLASS lcl_alpha_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      padding_is_conditional,
      width_source_vs_target,
      inline_target_is_a_string,
      out_is_lossy,
      the_select_bug,
      width_too_small.

ENDCLASS.


CLASS lcl_alpha_demo IMPLEMENTATION.

  METHOD padding_is_conditional.

    " ALPHA = IN pads only an uninterrupted string of digits. For any
    " other content the doc says the characters are left-aligned and
    " padded with BLANKS on the right - unchanged, and no error.

    DATA lv_numeric TYPE c LENGTH 18.
    DATA lv_alpha   TYPE c LENGTH 18.
    DATA lv_mixed   TYPE c LENGTH 18.

    lv_numeric = |{ '4711'   ALPHA = IN WIDTH = 18 }|.
    lv_alpha   = |{ 'A4711'  ALPHA = IN WIDTH = 18 }|.
    lv_mixed   = |{ '47 11'  ALPHA = IN WIDTH = 18 }|.

    WRITE: / '1. ALPHA = IN is conditional, not a conversion'.
    WRITE: / '   4711  ->', lv_numeric.
    WRITE: / '   A4711 ->', lv_alpha, '( unpadded, no error )'.
    WRITE: / '   47 11 ->', lv_mixed, '( interrupted, so unpadded )'.

    " So it cannot be used as a validation step. Check first:
    DATA lv_ok TYPE abap_bool.

    IF '4711' CO ' 0123456789'.
      lv_ok = abap_true.
    ELSE.
      lv_ok = abap_false.
    ENDIF.

    WRITE: / '   digits-only check first:', lv_ok.
    SKIP.

  ENDMETHOD.

  METHOD width_source_vs_target.

    " The documented length rule: without WIDTH, the TARGET length is
    " used only when the embedded expression is a SINGLE DATA OBJECT.
    " Otherwise the SOURCE length is used. Same value, same option,
    " two results that share no characters at all.

    DATA lv_text  TYPE ty_text.
    DATA lt_texts TYPE ty_texts.

    DATA lv_target1 TYPE c LENGTH 5.
    DATA lv_target2 TYPE c LENGTH 5.

    lv_text  = '0000012345'.
    lt_texts = VALUE ty_texts( ( lv_text ) ).

    " Single data object -> target length 5 -> builds 0000012345,
    " truncated on the LEFT.
    lv_target1 = |{ lv_text ALPHA = IN }|.

    " Table expression -> source length 10 -> builds 0000012345,
    " truncated on the RIGHT by the assignment.
    lv_target2 = |{ lt_texts[ 1 ] ALPHA = IN }|.

    WRITE: / '2. WIDTH omitted: source length vs target length'.
    WRITE: / '   single data object  ->', lv_target1.
    WRITE: / '   table expression    ->', lv_target2.
    WRITE: / '   same input, same option, no characters in common'.

    " The fix is always to say WIDTH explicitly.
    DATA lv_fixed TYPE c LENGTH 18.
    lv_fixed = |{ lv_text ALPHA = IN WIDTH = 18 }|.
    WRITE: / '   with WIDTH = 18     ->', lv_fixed.
    SKIP.

  ENDMETHOD.

  METHOD inline_target_is_a_string.

    " The target-length rule needs a FIXED-LENGTH c/n/d/t target. An
    " inline declaration produces a string, so there is no target
    " length to borrow and nothing is padded. This is the most common
    " form of the mistake.

    DATA(lv_inline)  = |{ '4711' ALPHA = IN }|.
    DATA(lv_correct) = |{ '4711' ALPHA = IN WIDTH = 18 }|.

    DATA lv_len_bad  TYPE i.
    DATA lv_len_good TYPE i.

    lv_len_bad  = strlen( lv_inline ).
    lv_len_good = strlen( lv_correct ).

    WRITE: / '3. Inline DATA( ) target is a string, not c LENGTH n'.
    WRITE: / '   DATA(x) = ALPHA = IN          ->', lv_inline,
             'length', lv_len_bad.
    WRITE: / '   DATA(x) = ALPHA = IN WIDTH 18 ->', lv_correct,
             'length', lv_len_good.
    SKIP.

  ENDMETHOD.

  METHOD out_is_lossy.

    " OUT strips the leading zeros and left-aligns. The field length is
    " then gone: running IN again without the right WIDTH does not give
    " the original value back.

    DATA lv_internal TYPE c LENGTH 18.
    DATA lv_display  TYPE c LENGTH 18.
    DATA lv_back     TYPE c LENGTH 18.

    lv_internal = '000000000000004711'.
    lv_display  = |{ lv_internal ALPHA = OUT }|.
    lv_back     = |{ lv_display  ALPHA = IN  }|.

    WRITE: / '4. ALPHA = OUT is a one-way, lossy display format'.
    WRITE: / '   internal ->', lv_internal.
    WRITE: / '   OUT      ->', lv_display.
    WRITE: / '   IN again ->', lv_back.

    IF lv_back = lv_internal.
      WRITE: / '   round trip restored the value'.
    ELSE.
      WRITE: / '   round trip did NOT restore the value'.
    ENDIF.
    SKIP.

  ENDMETHOD.

  METHOD the_select_bug.

    " Both of these are valid CHAR 18 contents. The database compares
    " them as characters, so the unconverted literal simply does not
    " match the stored row - sy-subrc = 4 for a row that exists.

    DATA lv_stored  TYPE c LENGTH 18.
    DATA lv_literal TYPE c LENGTH 18.
    DATA lv_fixed   TYPE c LENGTH 18.

    lv_stored  = '000000000000004711'.
    lv_literal = '4711'.
    lv_fixed   = |{ lv_literal ALPHA = IN WIDTH = 18 }|.

    WRITE: / '5. Why the WHERE clause finds nothing'.

    IF lv_literal = lv_stored.
      WRITE: / '   unconverted literal matches the stored key'.
    ELSE.
      WRITE: / '   unconverted literal does NOT match -> sy-subrc 4'.
    ENDIF.

    IF lv_fixed = lv_stored.
      WRITE: / '   converted literal matches the stored key'.
    ELSE.
      WRITE: / '   converted literal does NOT match'.
    ENDIF.

    WRITE: / '   convert at the boundary, never widen the WHERE'.
    SKIP.

  ENDMETHOD.

  METHOD width_too_small.

    " WIDTH is used only if it is GREATER than the significant length.
    " A width that is too small is ignored rather than truncating, so
    " the result can be longer than the width that was requested.

    DATA(lv_small) = |{ '1234567890' ALPHA = IN WIDTH = 4 }|.
    DATA lv_len TYPE i.

    lv_len = strlen( lv_small ).

    WRITE: / '6. A WIDTH below the significant length is ignored'.
    WRITE: / '   WIDTH = 4 on 1234567890 ->', lv_small,
             'length', lv_len.
    SKIP.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_alpha_demo=>padding_is_conditional( ).
  lcl_alpha_demo=>width_source_vs_target( ).
  lcl_alpha_demo=>inline_target_is_a_string( ).
  lcl_alpha_demo=>out_is_lossy( ).
  lcl_alpha_demo=>the_select_bug( ).
  lcl_alpha_demo=>width_too_small( ).
