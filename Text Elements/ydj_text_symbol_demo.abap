*&---------------------------------------------------------------------*
*& Report YDJ_TEXT_SYMBOL_DEMO
*&---------------------------------------------------------------------*
*& Text elements - why TEXT-xxx can print a blank with no error, and
*& what READ TEXTPOOL actually hands you.
*&
*&   1. THE TWO SPELLINGS  -> TEXT-idf becomes a BLANK when the symbol
*&                            is missing; 'Literal'(idf) falls back to
*&                            the literal. Same object when the pool is
*&                            complete, different on the bad day.
*&   2. IT IS TYPE c       -> fixed length mlen, so trailing blanks
*&                            disappear in && and a translation longer
*&                            than mlen cannot be stored at all.
*&   3. READ TEXTPOOL      -> ID/KEY decode, and the EIGHT BLANKS in
*&                            front of every non-Dictionary selection
*&                            text.
*&   4. DICTIONARY TEXTS   -> selection texts taken from the DDIC are
*&                            NOT in the pool; they carry a 'D' in
*&                            ENTRY(1).
*&   5. SET LANGUAGE       -> loads a pool for THIS program only, does
*&                            NOT load selection texts, and on failure
*&                            leaves the PREVIOUS pool active with
*&                            sy-subrc = 4.
*&
*& Self-contained: the only repository object read is this report's own
*& text pool, so trap 1 demonstrates itself even if you never maintain
*& a single text element. No database tables are written. INSERT
*& TEXTPOOL is shown as a commented-out block ONLY - it overwrites the
*& entire pool of a program and must never run by accident.
*&
*& To see the contrast fully: run it once as-is (symbols missing ->
*& blanks and literals), then maintain symbol H01 as 'Posting Run' in
*& Goto -> Text Elements -> Text Symbols and run it again.
*&---------------------------------------------------------------------*
REPORT ydj_text_symbol_demo.

PARAMETERS: p_langu TYPE sy-langu DEFAULT sy-langu.

*&---------------------------------------------------------------------*
*& Trap 1: the bare symbol vs the literal-linked symbol
*&---------------------------------------------------------------------*
CLASS lcl_demo DEFINITION.

  PUBLIC SECTION.
    CLASS-METHODS run.

  PRIVATE SECTION.
    CLASS-METHODS show_two_spellings.
    CLASS-METHODS show_type_c_nature.
    CLASS-METHODS show_textpool.
    CLASS-METHODS show_set_language.

ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

  METHOD run.

    show_two_spellings( ).
    show_type_c_nature( ).
    show_textpool( ).
    show_set_language( ).

  ENDMETHOD.

  METHOD show_two_spellings.

    " h01 is deliberately NOT maintained when this report is first
    " created. The bare form yields an initial single-character text
    " field - one blank - and the linked form yields the literal.
    DATA lv_bare    TYPE string.
    DATA lv_linked  TYPE string.
    DATA lv_bare_ln TYPE i.

    lv_bare   = text-h01.
    lv_linked = 'Posting Run'(h01).

    " strlen over the string copy, so the blank is actually visible as
    " a length rather than swallowed by the WRITE list.
    lv_bare_ln = strlen( lv_bare ).

    WRITE: / 'TRAP 1 - the two spellings'.
    ULINE.
    WRITE: / '  TEXT-h01          ->[', lv_bare, ']'.
    WRITE: / '  length of that    ->', lv_bare_ln.
    WRITE: / '  ''Posting Run''(h01) ->[', lv_linked, ']'.
    SKIP.
    WRITE: / '  Both compile. Neither sets sy-subrc. Only the second'.
    WRITE: / '  one is readable when the text pool is incomplete.'.
    SKIP.

  ENDMETHOD.

  METHOD show_type_c_nature.

    " A text symbol is type c of length mlen, NOT a string. Trailing
    " blanks of a fixed-length operand are ignored by &&, which is why
    " concatenated symbols lose the space between them.
    DATA lv_joined TYPE string.
    DATA lv_fixed  TYPE c LENGTH 20.
    DATA lv_c_len  TYPE i.
    DATA lv_s_len  TYPE i.
    DATA lv_copy   TYPE string.

    lv_fixed = 'Posting Run'.
    lv_copy  = lv_fixed.

    " Same content, two different lengths: the c field ignores its
    " trailing blanks, the string copy kept them.
    lv_c_len = strlen( lv_fixed ).
    lv_s_len = strlen( lv_copy ).

    lv_joined = lv_fixed && 'Company Code'.

    WRITE: / 'TRAP 2 - a text symbol is type c, not string'.
    ULINE.
    WRITE: / '  strlen of the c field  ->', lv_c_len.
    WRITE: / '  strlen of a string copy->', lv_s_len.
    WRITE: / '  c field && literal     ->', lv_joined.
    SKIP.
    WRITE: / '  The missing space is not a translation bug - it is the'.
    WRITE: / '  trailing-blank rule for fixed-length operands.'.
    WRITE: / '  Size mlen 30-50% above the English text or the'.
    WRITE: / '  translation cannot be stored at all.'.
    SKIP.

  ENDMETHOD.

  METHOD show_textpool.

    " READ TEXTPOOL over this very report. Line type must match the
    " DDIC structure TEXTPOOL.
    DATA lt_pool   TYPE STANDARD TABLE OF textpool.
    DATA ls_pool   TYPE textpool.
    DATA lv_kind   TYPE string.
    DATA lv_text   TYPE string.
    DATA lv_subrc  TYPE sy-subrc.
    DATA lv_prefix TYPE c LENGTH 1.
    DATA lv_count  TYPE i.

    READ TEXTPOOL sy-repid INTO lt_pool LANGUAGE sy-langu.
    lv_subrc = sy-subrc.

    WRITE: / 'TRAP 3/4 - READ TEXTPOOL of this report'.
    ULINE.
    WRITE: / '  sy-subrc ->', lv_subrc.

    IF lv_subrc <> 0.
      WRITE: / '  No text pool in this language yet - which is itself'.
      WRITE: / '  the point: missing pool, no exception.'.
      SKIP.
      RETURN.
    ENDIF.

    LOOP AT lt_pool INTO ls_pool.

      CASE ls_pool-id.
        WHEN 'I'.
          lv_kind = 'text symbol'.
        WHEN 'S'.
          lv_kind = 'selection text'.
        WHEN 'R'.
          lv_kind = 'program title'.
        WHEN 'T'.
          lv_kind = 'list header title'.
        WHEN 'H'.
          lv_kind = 'list header column'.
        WHEN OTHERS.
          lv_kind = 'unknown'.
      ENDCASE.

      " The two documented formatting rules for selection texts:
      " a leading 'D' means the text comes from the ABAP Dictionary and
      " is NOT stored in the pool; otherwise the real text starts after
      " EIGHT blanks.
      lv_text   = ls_pool-entry.
      lv_prefix = ls_pool-entry(1).

      IF ls_pool-id = 'S'.
        IF lv_prefix = 'D'.
          lv_text = '<from ABAP Dictionary - not in the pool>'.
        ELSE.
          lv_text = ls_pool-entry+8.
        ENDIF.
      ENDIF.

      WRITE: /  '  ', ls_pool-id, ls_pool-key, lv_kind, lv_text.

      lv_count = lv_count + 1.

    ENDLOOP.

    SKIP.
    WRITE: / '  rows read ->', lv_count.
    WRITE: / '  For a GLOBAL CLASS or FUNCTION POOL you must pass the'.
    WRITE: / '  MASTER PROGRAM name here, not the class name.'.
    SKIP.

    " NEVER run this. INSERT TEXTPOOL overwrites the COMPLETE pool of
    " the target language, and an empty table DELETES every text
    " element. It always sets sy-subrc = 0, so there is no signal.
    "
    " INSERT TEXTPOOL sy-repid FROM lt_pool LANGUAGE sy-langu.

  ENDMETHOD.

  METHOD show_set_language.

    DATA lv_subrc TYPE sy-subrc.
    DATA lv_after TYPE string.

    " Loads list headers and text symbols of another language for THIS
    " program only. Does NOT load selection texts. On failure the
    " PREVIOUS pool stays active - so an unchecked sy-subrc means you
    " print the old language believing you switched.
    SET LANGUAGE p_langu.
    lv_subrc = sy-subrc.

    lv_after = 'Posting Run'(h01).

    WRITE: / 'TRAP 5 - SET LANGUAGE'.
    ULINE.
    WRITE: / '  requested language ->', p_langu.
    WRITE: / '  sy-subrc           ->', lv_subrc.
    WRITE: / '  symbol h01 now     ->[', lv_after, ']'.
    SKIP.

    IF lv_subrc = 0.
      WRITE: / '  Pool of that language OR of the secondary language'.
      WRITE: / '  was loaded - sy-subrc alone does not tell you which.'.
    ELSE.
      WRITE: / '  Neither the requested nor the secondary language pool'.
      WRITE: / '  could be loaded. The PREVIOUS pool is still active.'.
    ENDIF.

    SKIP.
    WRITE: / '  Symbols present in the old pool but missing in the new'.
    WRITE: / '  one are INITIALIZED - a partial translation is worse'.
    WRITE: / '  than none. Selection texts are untouched; those need'.
    WRITE: / '  READ TEXTPOOL + SELECTION_TEXTS_MODIFY.'.
    SKIP.
    WRITE: / '  SET LANGUAGE is not SET LOCALE LANGUAGE, and there is'.
    WRITE: / '  deliberately no GET LANGUAGE statement.'.

  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  lcl_demo=>run( ).
