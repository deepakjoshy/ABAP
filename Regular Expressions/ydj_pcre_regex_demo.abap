*&---------------------------------------------------------------------*
*& Report YDJ_PCRE_REGEX_DEMO
*&---------------------------------------------------------------------*
*& PCRE vs the obsolete POSIX regular expressions, and the FIND traps.
*&
*& The ABAP Kernel runs TWO regex libraries: PCRE2 (current, addition
*& PCRE / parameter pcre =) and Boost.Regex 1.31 for POSIX (obsolete,
*& addition REGEX / parameter regex =, warns unless ##regex_posix).
*& PCRE is not a drop-in replacement - these differences change the
*& result with no syntax error and no dump.
*&
*&   1. EXTENDED MODE -> ON by default for PCRE. Unescaped blanks are
*&                       IGNORED and # starts a comment. `Hello World`
*&                       matches 'HelloWorld', not 'Hello World'.
*&   2. LEFTMOST      -> PCRE returns the leftmost match, POSIX the
*&                       leftmost LONGEST. Same pattern, shorter result.
*&   3. THE DOT       -> In PCRE '.' does NOT match line breaks. Use
*&                       (?s) or DOT_ALL. POSIX '.' matched everything.
*&   4. UNICODE       -> Statements default to relaxed (UCS-2), so a
*&                       surrogate pair counts as two characters.
*&                       CL_ABAP_REGEX=>CREATE_PCRE defaults to STRICT.
*&   5. TOO_COMPLEX   -> CX_SY_REGEX_TOO_COMPLEX depends on the TEXT as
*&                       well as the pattern. Passes tests, dumps in
*&                       production. POSIX is far more vulnerable.
*&   6. MATCH OFFSET  -> NOT reset when the search fails; it keeps its
*&                       previous value. sy-fdpos is NOT filled by FIND.
*&   7. EMPTY MATCH   -> An empty substring raises
*&                       CX_SY_FIND_INFINITE_LOOP on ALL OCCURRENCES,
*&                       but a regex matching empty (x*) succeeds
*&                       everywhere instead of failing.
*&   8. SUBMATCHES    -> With ALL OCCURRENCES you get the LAST match
*&                       only, not the first and not all of them.
*&   9. OBJECT FORM   -> NEW cl_abap_regex( ) is deprecated AND builds
*&                       a POSIX instance. Use CREATE_PCRE( ).
*&
*& Read-only. No database access, no changes of any kind.
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENREGEX_PCRE_SYNTAX.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENREGEX_POSIX_PCRE_INCOMPAT.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPFIND_OPTIONS.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENREGEX_SYSTEM_CLASSES.html
*&---------------------------------------------------------------------*
REPORT ydj_pcre_regex_demo.

CLASS lcl_regex_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      extended_mode,
      leftmost_vs_longest,
      dot_and_line_breaks,
      unicode_surrogates,
      regex_too_complex,
      match_offset_not_reset,
      empty_match_behaviour,
      submatches_last_only,
      regex_object_form.

ENDCLASS.


CLASS lcl_regex_demo IMPLEMENTATION.

  METHOD extended_mode.

    " ---------------------------------------------------------------
    " THE HEADLINE.
    " The PCRE addition and the pcre = parameter compile the pattern
    " in EXTENDED mode: unescaped whitespace outside character classes
    " is discarded and # starts a comment. So a pattern containing a
    " blank does not match the blank - it matches the text WITHOUT it.
    " The obsolete POSIX form behaved the way you would expect.
    " ---------------------------------------------------------------
    DATA lv_r1 TYPE abap_bool.
    DATA lv_r2 TYPE abap_bool.
    DATA lv_r3 TYPE abap_bool.
    DATA lv_r4 TYPE abap_bool.
    DATA lv_r5 TYPE abap_bool.
    DATA lv_r6 TYPE abap_bool.
    DATA lv_r7 TYPE abap_bool.
    DATA lv_r8 TYPE abap_bool.

    lv_r1 = xsdbool( matches( val = `Hello World` pcre  = `Hello World` ) ).
    lv_r2 = xsdbool( matches( val = `HelloWorld`  pcre  = `Hello World` ) ).
    lv_r3 = xsdbool( matches( val = `Hello World` regex = `Hello World` ) ) ##regex_posix.
    lv_r4 = xsdbool( matches( val = `Hello World` pcre  = `Hello\sWorld` ) ).
    lv_r5 = xsdbool( matches( val = `Hello World` pcre  = `Hello\ World` ) ).
    lv_r6 = xsdbool( matches( val = `Hello World` pcre  = `(?-x)Hello World` ) ).
    lv_r7 = xsdbool( matches( val = `Hello#World` pcre  = `Hello#World` ) ).
    lv_r8 = xsdbool( matches( val = `Hello#World` pcre  = `Hello\#World` ) ).

    WRITE: / '1. Extended mode is ON by default'.
    WRITE: / '   pcre  `Hello World` vs "Hello World" ->', lv_r1,
             '( X = matched )'.
    WRITE: / '   pcre  `Hello World` vs "HelloWorld"  ->', lv_r2.
    WRITE: / '   regex `Hello World` vs "Hello World" ->', lv_r3,
             '( obsolete POSIX )'.

    " The three documented fixes.
    WRITE: / '   pcre  `Hello\sWorld`                 ->', lv_r4.
    WRITE: / '   pcre  `Hello\ World`   ( escaped )   ->', lv_r5.
    WRITE: / '   pcre  `(?-x)Hello World`             ->', lv_r6.

    " Same rule for #: it opens a comment unless escaped.
    WRITE: / '   pcre  `Hello#World` vs "Hello#World" ->', lv_r7.
    WRITE: / '   pcre  `Hello\#World`                 ->', lv_r8.

    SKIP.

  ENDMETHOD.


  METHOD leftmost_vs_longest.

    " ---------------------------------------------------------------
    " PCRE returns the LEFTMOST match. POSIX returned the leftmost
    " LONGEST one. Whenever several matches start at the same offset,
    " a migrated pattern can return a shorter - but still plausible -
    " substring. Nothing reports that anything changed.
    " ---------------------------------------------------------------
    DATA(lv_text) = `unfoldable`.

    DATA(lv_pcre_alt)   = match( val = lv_text pcre  = `un(fold|foldable)` ).
    DATA(lv_posix_alt)  = match( val = lv_text regex = `un(fold|foldable)` ) ##regex_posix.
    DATA(lv_reordered)  = match( val = lv_text pcre  = `un(foldable|fold)` ).
    DATA(lv_pcre_quant) = match( val = lv_text pcre  = `un(fold)?(foldable)?` ).
    DATA(lv_lookahead)  = match( val = lv_text pcre  = `un(fold(?!able))?(foldable)?` ).

    WRITE: / '2. Leftmost (PCRE) vs leftmost-longest (POSIX)'.
    WRITE: / '   pcre  `un(fold|foldable)`     ->', lv_pcre_alt.
    WRITE: / '   regex `un(fold|foldable)`     ->', lv_posix_alt.

    " Fix 1: reorder the alternation, longest branch first.
    WRITE: / '   pcre  `un(foldable|fold)`     ->', lv_reordered.

    " The rule is not limited to | - the ? quantifier has it too.
    WRITE: / '   pcre  `un(fold)?(foldable)?`  ->', lv_pcre_quant.

    " Fix 2: a negative look-ahead restores the longest match.
    WRITE: / '   pcre  ...(?!able) look-ahead  ->', lv_lookahead.

    SKIP.

  ENDMETHOD.


  METHOD dot_and_line_breaks.

    " ---------------------------------------------------------------
    " In PCRE the dot matches everything EXCEPT line breaks; in POSIX
    " it matched those too. Against a multi-line string - an uploaded
    " file, a long text, a payload - a migrated `.*` silently stops at
    " the first newline. (?s) restores the old behaviour.
    " ---------------------------------------------------------------
    DATA(lv_text) = |Hello{ cl_abap_char_utilities=>newline }World|.

    DATA(lv_pcre_dot)  = replace( val = lv_text pcre  = `.`     with = `x` occ = 0 ).
    DATA(lv_pcre_s)    = replace( val = lv_text pcre  = `(?s).` with = `x` occ = 0 ).
    DATA(lv_posix_dot) = replace( val = lv_text regex = `.`     with = `x` occ = 0 ) ##regex_posix.

    WRITE: / '3. The dot and line breaks'.
    WRITE: / '   pcre  `.`      ->', lv_pcre_dot.
    WRITE: / '   pcre  `(?s).`  ->', lv_pcre_s.
    WRITE: / '   regex `.`      ->', lv_posix_dot.
    WRITE: / '   ( the character the first pattern leaves behind is the newline )'.

    SKIP.

  ENDMETHOD.


  METHOD unicode_surrogates.

    " ---------------------------------------------------------------
    " ABAP strings are UTF-16. Characters outside the Basic Multilingual
    " Plane are stored as SURROGATE PAIRS - two UCS-2 units.
    " The statement / built-in function form defaults to RELAXED mode,
    " so the pair counts as TWO characters. CL_ABAP_REGEX=>CREATE_PCRE
    " defaults to STRICT, so the same pattern behaves differently
    " depending on which API you happened to use.
    " (*UTF) switches the statement form to strict.
    " ---------------------------------------------------------------
    WRITE: / '4. Unicode handling: relaxed (default) vs (*UTF)'.

    TRY.
        " U+1F47D EXTRATERRESTRIAL ALIEN, one UTF-16 character.
        DATA(lv_alien) = cl_abap_codepage=>convert_from(
                           codepage = 'UTF-8'
                           source   = CONV xstring( 'F09F91BD' ) ).

        DATA(lv_relaxed) = replace( val = lv_alien pcre = `.`       with = `X` occ = 0 ).
        DATA(lv_strict)  = replace( val = lv_alien pcre = `(*UTF).` with = `X` occ = 0 ).

        WRITE: / '   pcre  `.`       ->', lv_relaxed, '( one char counted twice )'.
        WRITE: / '   pcre  `(*UTF).` ->', lv_strict.

      CATCH cx_root INTO DATA(lo_exc).
        DATA(lv_msg) = lo_exc->get_text( ).
        WRITE: / '   skipped:', lv_msg.
    ENDTRY.

    WRITE: / '   UTF-16 + tolerate invalid input is NOT reachable from the'.
    WRITE: / '   statement form at all - it needs CL_ABAP_REGEX with'.
    WRITE: / '   UNICODE_HANDLING = IGNORE.'.

    SKIP.

  ENDMETHOD.


  METHOD regex_too_complex.

    " ---------------------------------------------------------------
    " A syntactically valid regex can exceed the kernel transition
    " limit. The doc is explicit that this depends on BOTH the pattern
    " AND the text, so a pattern that passes every unit test can dump
    " on one production record. POSIX is far more vulnerable: with
    " leftmost-longest matching, a greedy leading .* keeps every
    " candidate prefix alive internally.
    " ---------------------------------------------------------------
    DATA lv_off TYPE i.
    DATA lv_msg TYPE string.

    DATA(lv_text) = repeat( val = `a` occ = 500 ).

    WRITE: / '5. CX_SY_REGEX_TOO_COMPLEX depends on the DATA'.

    TRY.
        FIND REGEX `.*X.*` IN lv_text MATCH OFFSET lv_off ##regex_posix.
        WRITE: / '   POSIX .*X.* over 500 chars -> sy-subrc', sy-subrc.
      CATCH cx_sy_regex_too_complex INTO DATA(lo_exc).
        lv_msg = lo_exc->get_text( ).
        WRITE: / '   POSIX .*X.* over 500 chars ->', lv_msg.
    ENDTRY.

    TRY.
        FIND PCRE `.*X.*` IN lv_text MATCH OFFSET lv_off.
        WRITE: / '   PCRE  .*X.* over 500 chars -> sy-subrc', sy-subrc.
      CATCH cx_sy_regex_too_complex INTO lo_exc.
        lv_msg = lo_exc->get_text( ).
        WRITE: / '   PCRE  .*X.* over 500 chars ->', lv_msg.
    ENDTRY.

    " The real lesson from the doc's own example: this needed no regex.
    FIND SUBSTRING 'X' IN lv_text.
    WRITE: / '   FIND SUBSTRING instead     -> sy-subrc', sy-subrc,
             '( no regex library involved )'.

    SKIP.

  ENDMETHOD.


  METHOD match_offset_not_reset.

    " ---------------------------------------------------------------
    " MATCH OFFSET and MATCH LENGTH are NOT cleared when the search
    " fails - the doc says they "retain their previous value". Reusing
    " the same variable across two FINDs and reading it without first
    " checking sy-subrc gives the PREVIOUS search's offset.
    " Note also: sy-fdpos is not filled by FIND at all. That is the
    " channel of the CO/CS/CP operators, not of this statement.
    " ---------------------------------------------------------------
    DATA lv_off TYPE i.
    DATA lv_len TYPE i.

    WRITE: / '6. MATCH OFFSET survives a failed FIND'.

    FIND PCRE `\d+` IN `abc123def` MATCH OFFSET lv_off MATCH LENGTH lv_len.
    WRITE: / '   first  FIND -> sy-subrc', sy-subrc,
             'offset', lv_off, 'length', lv_len.

    " Same variables, a pattern that is not there.
    FIND PCRE `\d+` IN `no digits here` MATCH OFFSET lv_off MATCH LENGTH lv_len.
    WRITE: / '   second FIND -> sy-subrc', sy-subrc,
             'offset', lv_off, 'length', lv_len.
    WRITE: / '   ( offset and length are still the FIRST search''s values )'.

    " The guard is sy-subrc, exactly as for READ TABLE.
    IF sy-subrc = 0.
      WRITE: / '   usable offset:', lv_off.
    ELSE.
      WRITE: / '   nothing found - the offset must not be used'.
    ENDIF.

    SKIP.

  ENDMETHOD.


  METHOD empty_match_behaviour.

    " ---------------------------------------------------------------
    " An empty SUBSTRING and a REGEX that matches empty are handled
    " very differently, and neither is what a caller expects:
    "   - empty substring + ALL OCCURRENCES -> CX_SY_FIND_INFINITE_LOOP
    "   - regex matching empty (x*)         -> matches before, between
    "     and after every character, so the search ALWAYS succeeds
    "   - empty pcre pattern                -> CX_SY_INVALID_REGEX
    " A pattern assembled at runtime whose quantified part collapses to
    " "matches empty" therefore does not fail loudly. It succeeds
    " everywhere, and the match count looks like real data.
    " ---------------------------------------------------------------
    DATA lv_empty TYPE string.
    DATA lv_cnt   TYPE i.
    DATA lv_off   TYPE i.

    WRITE: / '7. Empty patterns and empty matches'.

    TRY.
        FIND ALL OCCURRENCES OF lv_empty IN `abc` MATCH COUNT lv_cnt.
        WRITE: / '   empty substring, ALL   -> count', lv_cnt.
      CATCH cx_sy_find_infinite_loop.
        WRITE: / '   empty substring, ALL   -> CX_SY_FIND_INFINITE_LOOP'.
    ENDTRY.

    FIND FIRST OCCURRENCE OF lv_empty IN `abc` MATCH OFFSET lv_off.
    WRITE: / '   empty substring, FIRST -> sy-subrc', sy-subrc,
             'offset', lv_off.

    " `x*` matches the empty string, so every gap in 'abc' is a hit:
    " before a, between a/b, between b/c, after c.
    FIND ALL OCCURRENCES OF PCRE `x*` IN `abc` MATCH COUNT lv_cnt.
    WRITE: / '   pcre `x*`, ALL         -> sy-subrc', sy-subrc,
             'count', lv_cnt, '( never fails )'.

    TRY.
        FIND PCRE lv_empty IN `abc`.
        WRITE: / '   empty pcre pattern     -> sy-subrc', sy-subrc.
      CATCH cx_sy_invalid_regex.
        WRITE: / '   empty pcre pattern     -> CX_SY_INVALID_REGEX'.
    ENDTRY.

    SKIP.

  ENDMETHOD.


  METHOD submatches_last_only.

    " ---------------------------------------------------------------
    " With ALL OCCURRENCES, SUBMATCHES evaluates the LAST occurrence -
    " not the first, and not all of them. The statement still returns
    " sy-subrc = 0 and a correct MATCH COUNT, so the only symptom is
    " that the extracted values belong to the wrong row.
    " RESULTS (MATCH_RESULT_TAB) keeps every occurrence, each with its
    " own SUBMATCHES sub-table.
    " ---------------------------------------------------------------
    DATA lv_cnt     TYPE i.
    DATA lv_sub     TYPE string.
    DATA lt_results TYPE match_result_tab.
    DATA lv_value   TYPE string.

    DATA(lv_text) = `id=11;id=22;id=33`.

    WRITE: / '8. SUBMATCHES with ALL OCCURRENCES = the LAST match'.

    FIND ALL OCCURRENCES OF PCRE `id=(\d+)` IN lv_text
         MATCH COUNT lv_cnt
         SUBMATCHES lv_sub.

    WRITE: / '   count', lv_cnt, '- submatch ->', lv_sub, '( 33, not 11 )'.

    " RESULTS keeps them all. The offsets are relative to the whole
    " text, so the value is cut out of lv_text, not out of the match.
    FIND ALL OCCURRENCES OF PCRE `id=(\d+)` IN lv_text
         RESULTS lt_results.

    LOOP AT lt_results ASSIGNING FIELD-SYMBOL(<ls_match>).
      LOOP AT <ls_match>-submatches ASSIGNING FIELD-SYMBOL(<ls_sub>).
        lv_value = substring( val = lv_text
                              off = <ls_sub>-offset
                              len = <ls_sub>-length ).
        WRITE: / '   RESULTS occurrence', sy-tabix, '->', lv_value.
      ENDLOOP.
    ENDLOOP.

    SKIP.

  ENDMETHOD.


  METHOD regex_object_form.

    " ---------------------------------------------------------------
    " NEW cl_abap_regex( ) is deprecated AND creates a POSIX instance -
    " the modern-looking call is the obsolete one. Use the factory
    " methods: CREATE_PCRE, CREATE_XPATH2, CREATE_XSD, CREATE_POSIX.
    " Two further rules for the object form:
    "   - objects go with the REGEX addition of FIND/REPLACE, never
    "     with PCRE (PCRE takes a character-like pattern only)
    "   - IGNORING/RESPECTING CASE is NOT allowed with an object; case
    "     handling comes from IGNORE_CASE on CREATE_PCRE
    " If the same pattern is used repeatedly, this form compiles once
    " instead of once per call.
    " ---------------------------------------------------------------
    DATA lv_off TYPE i.
    DATA lv_sub TYPE string.

    WRITE: / '9. CL_ABAP_REGEX: use the factory method'.

    DATA(lo_regex) = cl_abap_regex=>create_pcre(
                       pattern     = `(\d\d\d)(\D\D\D)(\d\d\d)`
                       ignore_case = abap_true ).

    DATA(lo_matcher) = lo_regex->create_matcher( text = `123abc456` ).

    IF lo_matcher->match( ) = abap_true.
      DO.
        TRY.
            lv_sub = lo_matcher->get_submatch( sy-index ).
            WRITE: / '   submatch', sy-index, '->', lv_sub.
          CATCH cx_sy_invalid_submatch.
            EXIT.
        ENDTRY.
      ENDDO.
    ENDIF.

    " The same object drives FIND through the REGEX addition.
    FIND REGEX lo_regex IN `xx123abc456xx` MATCH OFFSET lv_off.
    WRITE: / '   FIND REGEX <object> -> sy-subrc', sy-subrc, 'offset', lv_off.

    SKIP.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_regex_demo=>extended_mode( ).
  lcl_regex_demo=>leftmost_vs_longest( ).
  lcl_regex_demo=>dot_and_line_breaks( ).
  lcl_regex_demo=>unicode_surrogates( ).
  lcl_regex_demo=>regex_too_complex( ).
  lcl_regex_demo=>match_offset_not_reset( ).
  lcl_regex_demo=>empty_match_behaviour( ).
  lcl_regex_demo=>submatches_last_only( ).
  lcl_regex_demo=>regex_object_form( ).
