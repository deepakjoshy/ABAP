*&---------------------------------------------------------------------*
*& Report YDJ_STRING_BUILD_DEMO
*&---------------------------------------------------------------------*
*& String building and substring access - the silent behaviours.
*&
*& Nothing here produces a syntax error or a dump. Every case below
*& returns a wrong-but-plausible value, which is why these survive
*& code review and unit tests written against short sample data.
*&
*&   1. TRAILING BLANKS -> type c loses them, type string keeps them.
*&                         space and ' ' ARE a trailing blank, so they
*&                         vanish in most operand positions.
*&   2. SEPARATED BY    -> the separator is the ONE operand position of
*&                         CONCATENATE where trailing blanks survive.
*&                         RESPECTING BLANKS extends that to all operands.
*&   3. TRUNCATION      -> CONCATENATE into a too-short c field truncates
*&                         on the RIGHT and sets sy-subrc = 4. Nobody
*&                         reads that sy-subrc.
*&   4. AMPERSAND x2    -> a non-character operand is treated as an
*&                         EMBEDDED EXPRESSION, not converted. For a
*&                         negative number the sign lands on the other
*&                         side than CONV string( ) puts it.
*&   5. STRLEN          -> counts trailing blanks for type string but not
*&                         for type c. numofchar( ) never counts them.
*&                         So retyping c -> string changes strlen( ).
*&   6. SUBSTRING TYPE  -> sy-datum+4(2) is type n, not type c. Slicing
*&                         a d or t field yields n.
*&   7. FIND vs SUBSTR  -> find( ) returns -1 when not found;
*&                         substring_after( ) returns an EMPTY STRING,
*&                         indistinguishable from a match at the end.
*&   8. CONDENSE        -> on a fixed-length field the freed space is
*&                         padded back on the right. The field does not
*&                         get shorter; the content just moves left.
*&
*& Read-only. No database access, no changes of any kind.
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_PROCESSING_TRAIL_BLANKS.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCONCATENATE.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_OPERATORS.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_EXPR_PERFO.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENOFFSET_LENGTH.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLENGTH_FUNCTIONS.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSEARCH_FUNCTIONS.html
*&---------------------------------------------------------------------*
REPORT ydj_string_build_demo.

CLASS lcl_string_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      disappearing_blanks,
      separator_exception,
      silent_truncation,
      concat_operator_sign,
      strlen_versus_numofchar,
      substring_type_rule,
      find_versus_substring,
      condense_padding.

  PRIVATE SECTION.

    " Renders a string with visible padding so trailing blanks can be
    " seen in the list output. Uses a fixed marker on both ends.
    CLASS-METHODS show
      IMPORTING iv_label TYPE string
                iv_value TYPE string.

ENDCLASS.


CLASS lcl_string_demo IMPLEMENTATION.

  METHOD show.

    DATA lv_line TYPE string.

    lv_line = iv_label && ` [` && iv_value && `]`.
    WRITE: / lv_line.

  ENDMETHOD.


  METHOD disappearing_blanks.
*   --------------------------------------------------------------
*   1. space and ' ' are nothing BUT a trailing blank, so they are
*      truncated in operand positions that drop trailing blanks.
*      This is the keyword documentation's own example.
*   --------------------------------------------------------------
    DATA lv_text TYPE string.

    WRITE: / '--- 1. Disappearing blanks ---'.

    CONCATENATE space ' ' INTO lv_text SEPARATED BY ''.

    WRITE: / '  CONCATENATE space '' '' ... SEPARATED BY ''''',
           / '  expected naively : 3 blanks',
           / '  actual length    :', strlen( lv_text ).
    show( iv_label = `  result` iv_value = lv_text ).

*   The same three operands WITH the addition. Now every trailing
*   blank counts, and the length is 3.
    CONCATENATE space ' ' INTO lv_text SEPARATED BY '' RESPECTING BLANKS.

    WRITE: / '  ... RESPECTING BLANKS length :', strlen( lv_text ).

*   A text field literal cannot HOLD a trailing blank - they are cut
*   at compile time. Only a backtick string literal keeps one.
    DATA(lv_from_text)   = CONV string( ' ' ).
    DATA(lv_from_string) = ` `.

    WRITE: / '  strlen of text literal '' ''  :', strlen( lv_from_text ),
           / '  strlen of string literal ` ` :', strlen( lv_from_string ).

  ENDMETHOD.


  METHOD separator_exception.
*   --------------------------------------------------------------
*   2. The separator of SEPARATED BY is the one operand position of
*      CONCATENATE where trailing blanks of a fixed-length operand
*      are respected. That is the only reason SEPARATED BY space
*      works at all - and the reason people wrongly conclude that
*      space is generally safe.
*   --------------------------------------------------------------
    TYPES ty_word TYPE c LENGTH 10.

    DATA lt_words  TYPE TABLE OF ty_word.
    DATA lv_joined TYPE string.

    WRITE: / '--- 2. SEPARATED BY vs RESPECTING BLANKS ---'.

    APPEND 'When'  TO lt_words.
    APPEND 'the'   TO lt_words.
    APPEND 'music' TO lt_words.
    APPEND 'is'    TO lt_words.
    APPEND 'over'  TO lt_words.

    CONCATENATE LINES OF lt_words INTO lv_joined SEPARATED BY space.
    show( iv_label = `  SEPARATED BY space ` iv_value = lv_joined ).
    WRITE: / '    length:', strlen( lv_joined ).

    CONCATENATE LINES OF lt_words INTO lv_joined RESPECTING BLANKS.
    show( iv_label = `  RESPECTING BLANKS  ` iv_value = lv_joined ).
    WRITE: / '    length:', strlen( lv_joined ),
           / '    ( 5 lines x 10 chars - every pad blank kept )'.

  ENDMETHOD.


  METHOD silent_truncation.
*   --------------------------------------------------------------
*   3. A too-short target truncates on the RIGHT. sy-subrc = 4 says
*      so, and essentially no production code checks it. A string
*      target adapts its length and cannot truncate, which is the
*      real argument for typing build targets as string.
*   --------------------------------------------------------------
    DATA lv_short  TYPE c LENGTH 10.
    DATA lv_string TYPE string.
    DATA lv_subrc  TYPE sy-subrc.

    WRITE: / '--- 3. Silent truncation on a short target ---'.

    CONCATENATE 'DOCUMENT' 'NUMBER' '4711' INTO lv_short.
    lv_subrc = sy-subrc.

    show( iv_label = `  c LENGTH 10 target` iv_value = CONV string( lv_short ) ).
    WRITE: / '    sy-subrc :', lv_subrc,
           / '    ( 4 = content did NOT fit and was cut on the right )'.

    CONCATENATE 'DOCUMENT' 'NUMBER' '4711' INTO lv_string.
    lv_subrc = sy-subrc.

    show( iv_label = `  string target     ` iv_value = lv_string ).
    WRITE: / '    sy-subrc :', lv_subrc.

  ENDMETHOD.


  METHOD concat_operator_sign.
*   --------------------------------------------------------------
*   4. A non-character operand of the concatenation operator is
*      handled as an EMBEDDED EXPRESSION of a string template, not
*      converted with the normal conversion rules. The two disagree
*      about which side the minus sign goes on.
*
*      Both ASSERTs below are taken from the keyword documentation.
*   --------------------------------------------------------------
    DATA lv_amount TYPE p LENGTH 8 DECIMALS 2 VALUE '-100.00'.

    WRITE: / '--- 4. Concatenation operator and negative numbers ---'.

    ASSERT `` && -1 =   `` && |{ -1 }|.
    ASSERT `` && -1 <>  `` && CONV string( -1 ).

    DATA(lv_via_operator) = `Amount: ` && lv_amount.
    DATA(lv_via_conv)     = `Amount: ` && CONV string( lv_amount ).

    show( iv_label = `  operand directly  ` iv_value = lv_via_operator ).
    show( iv_label = `  via CONV string( )` iv_value = lv_via_conv ).
    WRITE: / '  Same source value. Different output. No warning.'.

  ENDMETHOD.


  METHOD strlen_versus_numofchar.
*   --------------------------------------------------------------
*   5. strlen( ) counts trailing blanks for type string but NOT for
*      fixed-length types. numofchar( ) never counts them. So
*      retyping a field from c LENGTH n to string silently changes
*      what strlen( ) returns - a refactoring that looks cosmetic.
*   --------------------------------------------------------------
    DATA lv_c   TYPE c LENGTH 10 VALUE '12345'.
    DATA lv_str TYPE string       VALUE `12345     `.

    WRITE: / '--- 5. strlen vs numofchar ---'.

    WRITE: / '  c LENGTH 10  strlen    :', strlen( lv_c ),
           / '  c LENGTH 10  numofchar :', numofchar( lv_c ),
           / '  string       strlen    :', strlen( lv_str ),
           / '  string       numofchar :', numofchar( lv_str ).

    WRITE: / '  Same visible content. strlen differs by type;',
           / '  numofchar( ) means "length of the content" in both.'.

*   charlen( ) is not a length function at all - it reports the
*   length of the FIRST character in the code page (2 for a
*   surrogate pair), which is how you detect one.
    WRITE: / '  charlen of the same field :', charlen( lv_str ),
           / '  ( first character only - a codepage probe )'.

  ENDMETHOD.


  METHOD substring_type_rule.
*   --------------------------------------------------------------
*   6. The type of dobj+off(len) follows the ORIGINAL type, and for
*      d and t the substring type is n - not c. That matters the
*      moment the slice is assigned onward, because n obeys numeric
*      conversion rules.
*   --------------------------------------------------------------
    DATA lv_date  TYPE d VALUE '20260916'.
    DATA lv_month TYPE n LENGTH 2.
    DATA lv_num   TYPE i.

    WRITE: / '--- 6. Substring type of a date field ---'.

    lv_month = lv_date+4(2).
    lv_num   = lv_date+4(2).

    WRITE: / '  date          :', lv_date,
           / '  date+4(2)     :', lv_month,
           / '  same, into i  :', lv_num,
           / '  ( the slice is type n, NOT type c )'.

*   The documentation recommends always writing the offset out, so
*   a substring access cannot be mistaken for a method call or an
*   inline declaration - both of which also use parentheses.
    WRITE: / '  Prefer dobj+0(len) over dobj(len) for readability.'.

*   Note: writing into a substring works only on FLAT objects.
*   lv_string+3(2) = 'XX' is not allowed for a data object of type
*   string - the single most common reason a c LENGTH n field
*   cannot simply be retyped to string.

  ENDMETHOD.


  METHOD find_versus_substring.
*   --------------------------------------------------------------
*   7. The two families report "not found" differently:
*        find( )            -> -1
*        substring_after( ) -> empty string
*      and an empty result is indistinguishable from a real match
*      at the very end of the input.
*   --------------------------------------------------------------
    DATA(lv_path) = `/usr/local/share/report.txt`.

    WRITE: / '--- 7. find( ) vs substring_after( ) ---'.

    DATA(lv_hit)  = find( val = lv_path sub = `/share/` ).
    DATA(lv_miss) = find( val = lv_path sub = `/nope/` ).

    WRITE: / '  find hit  :', lv_hit,
           / '  find miss :', lv_miss,
           / '  ( -1, unambiguous )'.

    DATA(lv_after_miss) = substring_after( val = lv_path sub = `/nope/` ).
    DATA(lv_after_end)  = substring_after( val = lv_path sub = `.txt` ).

    WRITE: / '  substring_after miss   length :', strlen( lv_after_miss ),
           / '  substring_after at end length :', strlen( lv_after_end ),
           / '  ( both 0 - the miss and the real match at the end',
           / '    are indistinguishable. Test with find( ) first. )'.

*   A negative occ searches right to left. This is the clean way to
*   take everything after the LAST separator without a loop.
    DATA(lv_last_sep) = find( val = lv_path sub = `/` occ = -1 ).
    DATA(lv_filename) = substring( val = lv_path off = lv_last_sep + 1 ).

    WRITE: / '  last separator offset :', lv_last_sep.
    show( iv_label = `  file name         ` iv_value = lv_filename ).

*   find_any_of / find_any_not_of are ALWAYS case-sensitive (the
*   case parameter does not apply to them) and return -1 rather
*   than raising when sub is empty.
    DATA(lv_any) = find_any_of( val = lv_path sub = `` ).
    WRITE: / '  find_any_of with empty sub :', lv_any,
           / '  ( -1, where find( ) would raise CX_SY_STRG_PAR_VAL )'.

  ENDMETHOD.


  METHOD condense_padding.
*   --------------------------------------------------------------
*   8. CONDENSE on a fixed-length field pads the freed space back
*      on the right. The field does not shrink - the content just
*      moves left. Only a string actually changes length.
*   --------------------------------------------------------------
    DATA lv_c30   TYPE c LENGTH 30 VALUE '   too    many    blanks   '.
    DATA lv_str   TYPE string      VALUE `   too    many    blanks   `.

    WRITE: / '--- 8. CONDENSE and padding ---'.

    WRITE: / '  c LENGTH 30 strlen before :', strlen( lv_c30 ).
    CONDENSE lv_c30.
    WRITE: / '  c LENGTH 30 strlen after  :', strlen( lv_c30 ).
    show( iv_label = `  condensed c field ` iv_value = CONV string( lv_c30 ) ).

    WRITE: / '  string strlen before      :', strlen( lv_str ).
    CONDENSE lv_str.
    WRITE: / '  string strlen after       :', strlen( lv_str ).
    show( iv_label = `  condensed string  ` iv_value = lv_str ).

    WRITE: / '  NO-GAPS removes internal blanks entirely:'.
    CONDENSE lv_str NO-GAPS.
    show( iv_label = `  NO-GAPS           ` iv_value = lv_str ).

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_string_demo=>disappearing_blanks( ).
  lcl_string_demo=>separator_exception( ).
  lcl_string_demo=>silent_truncation( ).
  lcl_string_demo=>concat_operator_sign( ).
  lcl_string_demo=>strlen_versus_numofchar( ).
  lcl_string_demo=>substring_type_rule( ).
  lcl_string_demo=>find_versus_substring( ).
  lcl_string_demo=>condense_padding( ).
