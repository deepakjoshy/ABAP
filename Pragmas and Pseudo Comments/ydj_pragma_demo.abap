*&---------------------------------------------------------------------*
*& Report YDJ_PRAGMA_DEMO
*&---------------------------------------------------------------------*
*& Pragmas and pseudo comments - the suppression markers whose failure
*& mode is SILENCE.
*&
*& This report is unusual: the lesson is its own SOURCE CODE. A check
*& tool cannot be invoked from ABAP, so the pragmas below are real,
*& correctly positioned examples to read, and the output is a guided
*& tour that tells you which line to look at and what it suppresses.
*&
*& One part IS genuinely executable, and it is the one people disbelieve:
*& section 3 proves that a method shadowing a built-in function really
*& does hide it, and that the hiding is scoped to the defining class.
*&
*&   1. ##NEEDED         -> the unused variable. Pragma sits BEFORE the
*&                          period; the obsolete pseudo comment sat
*&                          after it. Swap them and both stop working.
*&   2. CHAIN SCOPE      -> a pragma before a COMMA covers that chain
*&                          part. Before the COLON it would cover the
*&                          whole chain, including parts added later.
*&   3. ##SHADOW         -> a method named like a built-in function.
*&                          Executable proof: inside lcl_shadow the
*&                          name is the method, inside this class the
*&                          same name is still the built-in.
*&   4. ##NO_TEXT        -> the literal that is NOT for translation.
*&                          A user-visible text needs a text symbol
*&                          instead - the pragma is an assertion about
*&                          the literal, and it is often the wrong one.
*&   5. MARKER RULES     -> the three ways a pragma fails, printed,
*&                          because only one of the three is loud.
*&   6. OBSOLETE FORMS   -> "#EC and "#AU shown as inert comments,
*&                          with what replaced them.
*&
*& Read-only: no database access at all, no COMMIT, no locks, no
*& authority checks. Every method is a static method and prints to the
*& classic list.
*&
*& Docs: https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_CI.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_SLIN.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_TEST_CLASS.html
*&---------------------------------------------------------------------*
REPORT ydj_pragma_demo.

*&---------------------------------------------------------------------*
*& A class that deliberately hides a built-in function.
*&
*& The method name SUBSTRING shadows the built-in function of the same
*& name for the whole class. That raises a syntax-check warning on the
*& DEFINITION, which is what the pragma at the end of the RETURNING
*& line suppresses. The parameter is a FILTER, not a label:
*& ##SHADOW[FIND] here would be a correctly spelled, correctly
*& positioned pragma that suppresses nothing.
*&---------------------------------------------------------------------*
CLASS lcl_shadow DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS substring
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string ##SHADOW[SUBSTRING].

ENDCLASS.

CLASS lcl_shadow IMPLEMENTATION.

  METHOD substring.

    " Deliberately NOT what the built-in does, so the difference in
    " section 3 is visible rather than coincidental.
    rv_text = |<{ to_upper( iv_text ) }>|.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& The tour.
*&---------------------------------------------------------------------*
CLASS lcl_pragma_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      needed_variable,
      chain_scope,
      shadowed_builtin,
      no_text_literal,
      marker_rules,
      obsolete_forms.

  PRIVATE SECTION.

    " Named out_row rather than line: LINE is a keyword in list
    " processing statements and the similarity reads badly.
    CLASS-METHODS out_row
      IMPORTING iv_label TYPE string
                iv_value TYPE string.

ENDCLASS.

CLASS lcl_pragma_demo IMPLEMENTATION.

  METHOD out_row.

    DATA lv_label TYPE c LENGTH 30.

    lv_label = iv_label.
    WRITE: / lv_label, iv_value.

  ENDMETHOD.

  METHOD needed_variable.

    " The extended program check reports that there is no read access
    " to this variable. The pragma hides that message - and it sits
    " immediately BEFORE the period, which is the one position a pragma
    " is allowed to occupy at the end of a line.
    DATA lv_placeholder TYPE string ##NEEDED.

    WRITE: / 'Section 1 - ##NEEDED'.
    out_row( iv_label = 'Pragma position'
             iv_value = 'before the . , or : - never after' ).
    out_row( iv_label = 'Pseudo comment position'
             iv_value = 'after the statement, as a line-end comment' ).
    out_row( iv_label = 'Swap the two'
             iv_value = 'both stop working, and neither says so' ).

  ENDMETHOD.

  METHOD chain_scope.

    " A pragma applies to the statement that ends at the next . or ,
    " so this one covers lv_dummy and NOT lv_real. This is SAP's own
    " replacement for the obsolete "#EC NEEDED pseudo comment.
    DATA: lv_dummy TYPE string ##NEEDED,
          lv_real  TYPE string.

    lv_real = 'read below, so no warning to suppress'.

    WRITE: / 'Section 2 - chain scope'.
    out_row( iv_label = 'Before a comma'
             iv_value = 'that chain part only' ).
    out_row( iv_label = 'Before the colon'
             iv_value = 'the ENTIRE chain, incl. parts added later' ).
    out_row( iv_label = 'On a macro call'
             iv_value = 'every statement the macro expands to' ).
    out_row( iv_label = 'lv_real holds'
             iv_value = lv_real ).

  ENDMETHOD.

  METHOD shadowed_builtin.

    DATA lv_from_method  TYPE string.
    DATA lv_from_builtin TYPE string.
    DATA lv_source       TYPE string.

    lv_source = 'pragmas'.

    " Inside lcl_shadow the name SUBSTRING means the method. Inside
    " THIS class no such method exists, so the same name is still the
    " built-in function - the shadowing is scoped to the class that
    " declares it, which is exactly why the warning is worth reading
    " rather than suppressing by reflex.
    lv_from_method  = lcl_shadow=>substring( lv_source ).
    lv_from_builtin = substring( val = lv_source off = 0 len = 4 ).

    WRITE: / 'Section 3 - ##SHADOW (executable)'.
    out_row( iv_label = 'lcl_shadow=>substring'
             iv_value = lv_from_method ).
    out_row( iv_label = 'built-in substring'
             iv_value = lv_from_builtin ).
    out_row( iv_label = 'Same name, two meanings'
             iv_value = 'decided by the class you are standing in' ).

  ENDMETHOD.

  METHOD no_text_literal.

    DATA lv_separator TYPE string.
    DATA lv_heading   TYPE string.

    " A technical literal that must never be translated. The pragma
    " asserts exactly that, and here the assertion is true.
    lv_separator = '|' ##NO_TEXT.

    " A user-visible text. ##NO_TEXT would also silence the warning
    " here, and it would be a LIE - this one belongs in a text symbol.
    " Left unsuppressed on purpose: the warning is correct.
    lv_heading = 'Order overview'.

    WRITE: / 'Section 4 - ##NO_TEXT'.
    out_row( iv_label = 'Technical literal'
             iv_value = lv_separator ).
    out_row( iv_label = 'User-visible literal'
             iv_value = lv_heading ).
    out_row( iv_label = 'The pragma is a claim'
             iv_value = 'that the literal needs no translation' ).

  ENDMETHOD.

  METHOD marker_rules.

    WRITE: / 'Section 5 - how a pragma fails'.
    out_row( iv_label = 'Wrong name'
             iv_value = 'syntax warning - loud, you will see it' ).
    out_row( iv_label = 'Wrong position'
             iv_value = 'NO EFFECT, and no diagnostic at all' ).
    out_row( iv_label = 'Wrong parameter'
             iv_value = 'does not match, so suppresses nothing' ).
    out_row( iv_label = 'Widest parameter form'
             iv_value = 'omit it, or write empty brackets' ).
    out_row( iv_label = 'Where to find the code'
             iv_value = 'long text of the message being suppressed' ).

  ENDMETHOD.

  METHOD obsolete_forms.

    " Obsolete, shown as inert comments. These are comment text, so
    " they suppress nothing from here - they are here to be recognised
    " in old code:
    "
    "   DATA lv_x TYPE string.          "#EC NEEDED
    "   CLASS ltcl_x DEFINITION FOR TESTING. "#AU Risk_Level Harmless
    "
    " Replacements: ##NEEDED for the first, the RISK LEVEL addition of
    " CLASS ... FOR TESTING for the second. Run ABAP_SLIN_PRAGMAS or
    " read table SLIN_DESC for the full mapping.

    WRITE: / 'Section 6 - obsolete forms'.
    out_row( iv_label = 'Still required'
             iv_value = 'only "#EC CI_... for the Code Inspector' ).
    out_row( iv_label = '"#EC ID (ext. prog. check)'
             iv_value = 'obsolete - use the matching pragma' ).
    out_row( iv_label = '"#AU (test classes)'
             iv_value = 'obsolete - but NOT ignored if left behind' ).
    out_row( iv_label = 'Case sensitivity'
             iv_value = 'pragmas no, "#EC and "#AU yes' ).
    out_row( iv_label = '#EC * plus any pragma'
             iv_value = 'a finding that CANNOT be deactivated' ).

  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.

  WRITE: / 'YDJ_PRAGMA_DEMO - read the source alongside this output'.
  SKIP.

  lcl_pragma_demo=>needed_variable( ).
  SKIP.
  lcl_pragma_demo=>chain_scope( ).
  SKIP.
  lcl_pragma_demo=>shadowed_builtin( ).
  SKIP.
  lcl_pragma_demo=>no_text_literal( ).
  SKIP.
  lcl_pragma_demo=>marker_rules( ).
  SKIP.
  lcl_pragma_demo=>obsolete_forms( ).
