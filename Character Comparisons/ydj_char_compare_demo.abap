*&---------------------------------------------------------------------*
*& Report YDJ_CHAR_COMPARE_DEMO
*&---------------------------------------------------------------------*
*& CO / CN / CA / NA / CS / NS / CP / NP - and sy-fdpos.
*&
*& These eight operators are everyday ABAP, but almost everything about
*& them is asymmetric with the rest of the language: they set sy-fdpos
*& instead of sy-subrc, half of them are case-sensitive and half are
*& not, and they respect trailing blanks in operand positions where
*& every other statement throws them away.
*&
*&   1. SY-FDPOS      -> on a FAILED comparison sy-fdpos is the LENGTH
*&                       of the left operand, not -1 and not 0. Reading
*&                       it without checking the IF gives a valid-looking
*&                       offset that points just past the end.
*&   2. TRAILING PAD  -> CO respects trailing blanks in BOTH operands,
*&                       so a padded c field CO a literal is FALSE.
*&   3. CP            -> Conforms to Pattern, NOT Contains Pattern.
*&                       '<*>' does not find a tag; '*<*>*' does.
*&   4. ESCAPE #      -> # in a CP pattern makes the next character
*&                       literal AND case-sensitive AND blank-relevant.
*&   5. CASE          -> CS/NS/CP/NP ignore case; CO/CN/CA/NA do not.
*&                       The predicate functions ignore NOTHING, so a
*&                       one-for-one rewrite silently changes behaviour.
*&   6. BOOLC         -> boolc( ) returns a STRING, so comparing it to
*&                       abap_false is FALSE. xsdbool( ) is the fix.
*&   7. EMPTY OPERAND -> '' CO anything is always TRUE. Guard clauses
*&                       built on CO therefore pass on empty input.
*&   8. STRING LENGTH -> two strings of different length NEVER match.
*&
*& Read-only. No database access, no changes of any kind.
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLOGEXP_STRINGS.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLOGEXP_CHARACTER.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCHAR_COMP_OP_VS_FUNCT.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_PROCESSING_TRAIL_BLANKS.html
*&---------------------------------------------------------------------*
REPORT ydj_char_compare_demo.

CLASS lcl_char_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      fdpos_on_failure,
      fdpos_on_success,
      trailing_blank_padding,
      conforms_not_contains,
      escape_character,
      case_sensitivity_split,
      boolc_versus_xsdbool,
      empty_operand_rules,
      string_length_rule,
      numeric_comparison_trap.

ENDCLASS.


CLASS lcl_char_demo IMPLEMENTATION.

  METHOD fdpos_on_failure.

    " ---------------------------------------------------------------
    " THE HEADLINE.
    " sy-fdpos is not a sy-subrc. On a FAILED comparison it holds the
    " LENGTH of the left operand - a perfectly plausible offset that
    " happens to point one past the last character. Code that reads
    " sy-fdpos without first checking the IF reads a false position.
    " ---------------------------------------------------------------
    DATA(lv_text) = `ABCDEF`.

    WRITE: / '1. sy-fdpos after a FAILED comparison'.

    IF lv_text CS `XYZ`.
      WRITE: / '   found at', sy-fdpos.
    ELSE.
      WRITE: / '   not found, but sy-fdpos =', sy-fdpos,
               '( = strlen, NOT -1 )'.
    ENDIF.

    " The wrong pattern: the offset is used regardless of the result.
    " On a miss this silently becomes "offset 6" on a 6-character field.
    IF lv_text CS `XYZ`.
    ENDIF.
    WRITE: / '   read unguarded   :', sy-fdpos, '( looks like a hit )'.
    SKIP.

  ENDMETHOD.


  METHOD fdpos_on_success.

    " ---------------------------------------------------------------
    " On success the meaning of sy-fdpos changes per operator, and for
    " CO it is the length again - the same value that means "failed"
    " for CS. The operator decides what the number means.
    " ---------------------------------------------------------------
    DATA(lv_mixed) = `ABC123`.

    WRITE: / '2. sy-fdpos after a SUCCESSFUL comparison'.

    IF lv_mixed CA `0123456789`.
      WRITE: / '   CA digits -> first digit at offset', sy-fdpos.
    ENDIF.

    IF lv_mixed CS `12`.
      WRITE: / '   CS "12"   -> substring at offset  ', sy-fdpos.
    ENDIF.

    IF `123456` CO `0123456789`.
      WRITE: / '   CO digits -> TRUE, sy-fdpos =', sy-fdpos,
               '( the length, not an offset )'.
    ENDIF.

    " CN is simply "NOT CO", and it reports the first offending char.
    IF lv_mixed CN `0123456789`.
      WRITE: / '   CN digits -> first NON-digit at offset', sy-fdpos.
    ENDIF.
    SKIP.

  ENDMETHOD.


  METHOD trailing_blank_padding.

    " ---------------------------------------------------------------
    " CO/CN/CA/NA respect trailing blanks in BOTH operands. A type c
    " field is blank-padded to its declared length, so those blanks
    " are real characters that must also appear in the right operand.
    " This is the classic "why does my digit check fail?" bug.
    " ---------------------------------------------------------------
    DATA lv_c TYPE c LENGTH 10 VALUE '123'.

    WRITE: / '3. Trailing blanks of a type c field'.

    IF lv_c CO '0123456789'.
      WRITE: / '   c(10) CO digits          -> TRUE'.
    ELSE.
      WRITE: / '   c(10) CO digits          -> FALSE, sy-fdpos =',
               sy-fdpos, '( the first pad blank )'.
    ENDIF.

    " Fix A: allow the blank explicitly in the right operand.
    IF lv_c CO `0123456789 `.
      WRITE: / '   CO digits + blank        -> TRUE'.
    ENDIF.

    " Fix B: strip the padding first. condense( ) returns a string,
    " where there is no padding to begin with.
    IF condense( lv_c ) CO '0123456789'.
      WRITE: / '   condense( ) then CO      -> TRUE'.
    ENDIF.
    SKIP.

  ENDMETHOD.


  METHOD conforms_not_contains.

    " ---------------------------------------------------------------
    " CP means "Conforms to Pattern". The pattern must describe the
    " WHOLE operand, not a fragment of it. Everyone writes the
    " fragment version first and gets a silent FALSE.
    " ---------------------------------------------------------------
    DATA(lv_html) = `This is <i>italic</i>!`.

    WRITE: / '4. CP conforms, it does not contain'.

    IF lv_html CP `<*>`.
      WRITE: / '   CP "<*>"    -> TRUE'.
    ELSE.
      WRITE: / '   CP "<*>"    -> FALSE ( no leading/trailing * )'.
    ENDIF.

    IF lv_html CP `*<*>*`.
      WRITE: / '   CP "*<*>*"  -> TRUE, tag at offset', sy-fdpos,
               '( leading * ignored in sy-fdpos )'.
    ENDIF.

    " + stands for exactly one character and never for an empty one.
    IF `AB` CP `A+`.
      WRITE: / '   "AB" CP "A+" -> TRUE'.
    ENDIF.
    IF `A` NP `A+`.
      WRITE: / '   "A"  CP "A+" -> FALSE ( + is never empty )'.
    ENDIF.
    SKIP.

  ENDMETHOD.


  METHOD escape_character.

    " ---------------------------------------------------------------
    " # escapes the next character in a CP pattern. It does three
    " things at once: the character loses its wildcard meaning, the
    " comparison becomes CASE-SENSITIVE for it, and trailing blanks
    " become relevant. Needed whenever the data itself holds * or +.
    " ---------------------------------------------------------------
    DATA(lv_formula) = `TOTAL*RATE`.

    WRITE: / '5. Escaping a wildcard with #'.

    " Unescaped: * is a wildcard, so this matches almost anything.
    IF lv_formula CP `*RATE`.
      WRITE: / '   CP "*RATE"   -> TRUE  ( * is a wildcard )'.
    ENDIF.

    " Escaped: #* means a literal asterisk character.
    IF lv_formula CP `*#*RATE`.
      WRITE: / '   CP "*#*RATE" -> TRUE  ( literal * in the data )'.
    ENDIF.

    " The escape also forces case-sensitivity - but ONLY for the
    " character it escapes. Everything else in the pattern stays
    " case-insensitive, which is easy to over-read.
    IF `abc` CP `Abc`.
      WRITE: / '   "abc" CP "Abc"  -> TRUE  ( CP ignores case )'.
    ENDIF.

    IF `abc` CP `#Abc`.
      WRITE: / '   "abc" CP "#Abc" -> TRUE'.
    ELSE.
      WRITE: / '   "abc" CP "#Abc" -> FALSE ( escaped A is exact )'.
    ENDIF.
    SKIP.

  ENDMETHOD.


  METHOD case_sensitivity_split.

    " ---------------------------------------------------------------
    " CS/NS/CP/NP ignore case. CO/CN/CA/NA do NOT. The predicate
    " functions ignore case for nothing at all, so replacing CS with
    " contains( ) - which the docs list as the equivalent - changes
    " the result unless to_upper( ) is applied to both arguments.
    " ---------------------------------------------------------------
    DATA(lv_text) = `Hello World`.

    WRITE: / '6. Case handling is not uniform'.

    IF lv_text CS `WORLD`.
      WRITE: / '   CS "WORLD"                    -> TRUE  ( no case )'.
    ENDIF.

    IF contains( val = lv_text sub = `WORLD` ).
      WRITE: / '   contains( sub = "WORLD" )     -> TRUE'.
    ELSE.
      WRITE: / '   contains( sub = "WORLD" )     -> FALSE ( case! )'.
    ENDIF.

    IF contains( val = to_upper( lv_text ) sub = to_upper( `WORLD` ) ).
      WRITE: / '   contains( to_upper( .. ) )    -> TRUE  ( correct )'.
    ENDIF.

    " CA is case-sensitive, so an uppercase-only right operand misses
    " every lowercase character in the left one.
    IF `abc` CA `ABC`.
      WRITE: / '   "abc" CA "ABC"                -> TRUE'.
    ELSE.
      WRITE: / '   "abc" CA "ABC"                -> FALSE ( case )'.
    ENDIF.
    SKIP.

  ENDMETHOD.


  METHOD boolc_versus_xsdbool.

    " ---------------------------------------------------------------
    " boolc( ) returns type STRING containing either 'X' or a single
    " blank. abap_false is type c LENGTH 1 containing a blank. The
    " comparison type is string, so abap_false is converted to string
    " and its blank is DROPPED as a trailing blank - leaving an empty
    " string that never equals the one-blank result of boolc( ).
    " ---------------------------------------------------------------
    WRITE: / '7. boolc( ) compared with abap_false'.

    IF boolc( 1 = 2 ) = abap_false.
      WRITE: / '   boolc( 1 = 2 ) = abap_false   -> TRUE'.
    ELSE.
      WRITE: / '   boolc( 1 = 2 ) = abap_false   -> FALSE (!)'.
    ENDIF.

    " xsdbool( ) returns type c LENGTH 1, the same type as abap_false,
    " so no conversion happens and the comparison behaves as expected.
    IF xsdbool( 1 = 2 ) = abap_false.
      WRITE: / '   xsdbool( 1 = 2 ) = abap_false -> TRUE  ( correct )'.
    ENDIF.

    " The safe test for a boolc( ) result is against the value, not
    " against the constant.
    IF boolc( 1 = 2 ) IS INITIAL.
      WRITE: / '   boolc( .. ) IS INITIAL        -> also unreliable'.
    ELSE.
      WRITE: / '   boolc( .. ) IS INITIAL        -> FALSE, it holds a blank'.
    ENDIF.
    SKIP.

  ENDMETHOD.


  METHOD empty_operand_rules.

    " ---------------------------------------------------------------
    " The empty-operand rules differ per operator and are the reason
    " validation guards pass on empty input. "Only digits" is TRUE for
    " an empty string, so a CO-based check accepts nothing at all.
    " ---------------------------------------------------------------
    DATA(lv_empty) = ``.

    WRITE: / '8. Empty operands'.

    IF lv_empty CO `0123456789`.
      WRITE: / '   "" CO digits -> TRUE  ( vacuously "only digits" )'.
    ENDIF.

    " Documented as always true, whatever the right operand holds.
    IF lv_empty CO `anything at all`.
      WRITE: / '   "" CO <any>  -> TRUE  ( always )'.
    ENDIF.

    " CA is the opposite: an empty operand on EITHER side is false.
    IF lv_empty CA `0123456789`.
      WRITE: / '   "" CA digits -> TRUE'.
    ELSE.
      WRITE: / '   "" CA digits -> FALSE ( always )'.
    ENDIF.

    " So the guard needs its own emptiness test first.
    IF lv_empty IS NOT INITIAL AND lv_empty CO `0123456789`.
      WRITE: / '   guarded check -> TRUE'.
    ELSE.
      WRITE: / '   guarded check -> FALSE ( correct rejection )'.
    ENDIF.
    SKIP.

  ENDMETHOD.


  METHOD string_length_rule.

    " ---------------------------------------------------------------
    " Two operands of type string with different lengths NEVER match.
    " A type c field, by contrast, is padded to the longer length, so
    " the "same" comparison flips depending on the declared types.
    " ---------------------------------------------------------------
    DATA lv_c4 TYPE c LENGTH 4 VALUE 'AB'.
    DATA lv_c8 TYPE c LENGTH 8 VALUE 'AB'.
    DATA(lv_s1) = `AB`.
    DATA(lv_s2) = `AB `.

    WRITE: / '9. Length adjustment: c pads, string does not'.

    IF lv_c4 = lv_c8.
      WRITE: / '   c(4) = c(8), both "AB"   -> TRUE  ( blank padded )'.
    ENDIF.

    IF lv_s1 = lv_s2.
      WRITE: / '   "AB" = "AB " as strings  -> TRUE'.
    ELSE.
      WRITE: / '   "AB" = "AB " as strings  -> FALSE ( blank counts )'.
    ENDIF.

    " Mixing the two: comparison type is string, and the conversion
    " from c to string drops the padding - so this one is true again.
    IF lv_c8 = lv_s1.
      WRITE: / '   c(8) = string "AB"       -> TRUE  ( padding dropped )'.
    ENDIF.
    SKIP.

  ENDMETHOD.


  METHOD numeric_comparison_trap.

    " ---------------------------------------------------------------
    " A type n field compared with a c field or a string does NOT get
    " a character comparison. The documented comparison type is p, so
    " BOTH sides are converted to packed numbers first. If the
    " character side is not numeric the result is the runtime error
    " CONVT_NO_NUMBER - and for a comparison it is not catchable.
    "
    " The offending line is deliberately left commented out so this
    " demo report always runs to completion:
    "
    "   DATA lv_matnr TYPE n LENGTH 10.
    "   IF lv_matnr = 'ABC'.   " <- short dump CONVT_NO_NUMBER
    "   ENDIF.
    "
    " The fix is to force a character comparison explicitly.
    " ---------------------------------------------------------------
    DATA lv_matnr TYPE n LENGTH 10 VALUE '0000004711'.

    WRITE: / '10. Type n compared with characters uses type p'.

    " Leading zeros vanish, because this is a NUMERIC comparison.
    IF lv_matnr = '4711'.
      WRITE: / '   n(10) "0000004711" = "4711" -> TRUE  ( numeric! )'.
    ENDIF.

    " Forcing the character comparison keeps the leading zeros.
    IF CONV string( lv_matnr ) = `4711`.
      WRITE: / '   as string = "4711"          -> TRUE'.
    ELSE.
      WRITE: / '   as string = "4711"          -> FALSE ( zeros kept )'.
    ENDIF.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_char_demo=>fdpos_on_failure( ).
  lcl_char_demo=>fdpos_on_success( ).
  lcl_char_demo=>trailing_blank_padding( ).
  lcl_char_demo=>conforms_not_contains( ).
  lcl_char_demo=>escape_character( ).
  lcl_char_demo=>case_sensitivity_split( ).
  lcl_char_demo=>boolc_versus_xsdbool( ).
  lcl_char_demo=>empty_operand_rules( ).
  lcl_char_demo=>string_length_rule( ).
  lcl_char_demo=>numeric_comparison_trap( ).
