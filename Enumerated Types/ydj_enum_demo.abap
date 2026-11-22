*&---------------------------------------------------------------------*
*& Report YDJ_ENUM_DEMO
*&---------------------------------------------------------------------*
*& Enumerated types (7.51+) - the value-set type that is never read as
*& its base type, EXCEPT in the one place where it silently is.
*&
*& Every section below is executable and prints a before/after pair, so
*& the surprising result is visible next to the expected one.
*&
*&   1. NAME vs VALUE    -> assigning an enum to c/string yields the
*&                          UPPERCASE IDENTIFIER, not the stored value.
*&   2. THE CONV FLIP    -> with a character-like base type, the SAME
*&                          operand and the SAME target type give the
*&                          name or the value depending on one CONV #( ).
*&   3. NAME COLLISION   -> the converted name carries no structure or
*&                          class prefix, so two unrelated enumerated
*&                          types produce the SAME string.
*&   4. CROSS-TYPE CAST  -> CONV ty_animal( fr-peach ) is legal and
*&                          matches BY STORED VALUE. A fruit goes in,
*&                          an animal comes out. No warning.
*&   5. CONV vs EXACT    -> CONV converts to the base type FIRST and
*&                          validates second, so overlong input is
*&                          truncated ONTO A VALID VALUE in silence.
*&                          EXACT is the operator that refuses.
*&   6. READ ASYMMETRY   -> single-line reads convert the comparison
*&                          field implicitly; multi-line reads do not,
*&                          so READ TABLE and LOOP AT WHERE disagree.
*&   7. RTTI             -> CL_ABAP_ENUMDESCR members, and the type
*&                          kind 'k' that generic code never handles.
*&
*& Read-only: no database access at all, no COMMIT, no locks, no
*& authority checks, no screens. Static methods only, output to the
*& classic list.
*&
*& Every functional call is hoisted into a variable before WRITE, since
*& functional calls are not allowed in a WRITE list.
*&
*& Docs: https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPTYPES_ENUM.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONVERSION_ENUMERATED.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONV_CONSTRUCTOR_ENUM.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENEXACT_CONSTRUCTOR_ENUM.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENLOGEXP_RULES_OPERANDS_ENUM.html
*&---------------------------------------------------------------------*
REPORT ydj_enum_demo.

*&---------------------------------------------------------------------*
*& Enumerated types used throughout.
*&
*& All four use the STRUCTURE addition: it keeps the constant names out
*& of the program namespace, which is also what lets ty_code and
*& ty_doc_status both define a constant called "released" (section 3).
*&---------------------------------------------------------------------*

" Default base type i, so the values are 0, 1, 2, 3 left to right.
TYPES:
  BEGIN OF ENUM ty_size STRUCTURE sz,
    small,
    medium,
    large,
    xlarge,
  END OF ENUM ty_size STRUCTURE sz.

" Character-like base type. For a non-numeric base type the VALUE
" addition is MANDATORY for every constant, and IS INITIAL must appear
" on exactly one of them - not necessarily the first.
TYPES:
  ty_code_base TYPE c LENGTH 3,
  BEGIN OF ENUM ty_code STRUCTURE cd BASE TYPE ty_code_base,
    unknown  VALUE IS INITIAL,
    created  VALUE 'CRE',
    released VALUE 'REL',
  END OF ENUM ty_code STRUCTURE cd.

" A second, unrelated status enum that happens to reuse one name.
TYPES:
  BEGIN OF ENUM ty_doc_status STRUCTURE ds,
    draft,
    released,
    archived,
  END OF ENUM ty_doc_status STRUCTURE ds.

" Two value sets with nothing in common except the base type i.
TYPES:
  BEGIN OF ENUM ty_fruit STRUCTURE fr,
    apple,
    peach,
    orange,
  END OF ENUM ty_fruit STRUCTURE fr.

TYPES:
  BEGIN OF ENUM ty_animal STRUCTURE an,
    cat,
    dog,
    cow,
  END OF ENUM ty_animal STRUCTURE an.

TYPES: BEGIN OF ty_row,
         label TYPE string,
         note  TYPE string,
       END OF ty_row.
TYPES ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

*&---------------------------------------------------------------------*
*& CLASS lcl_demo
*&---------------------------------------------------------------------*
CLASS lcl_demo DEFINITION FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS run.

  PRIVATE SECTION.
    CLASS-METHODS name_versus_value.
    CLASS-METHODS conv_flip.
    CLASS-METHODS name_collision.
    CLASS-METHODS cross_type_cast.
    CLASS-METHODS conv_versus_exact.
    CLASS-METHODS read_asymmetry.
    CLASS-METHODS type_description.
    CLASS-METHODS header IMPORTING iv_text TYPE string.

ENDCLASS.

*&---------------------------------------------------------------------*
*& CLASS lcl_demo IMPLEMENTATION
*&---------------------------------------------------------------------*
CLASS lcl_demo IMPLEMENTATION.

  METHOD run.
    name_versus_value( ).
    conv_flip( ).
    name_collision( ).
    cross_type_cast( ).
    conv_versus_exact( ).
    read_asymmetry( ).
    type_description( ).
  ENDMETHOD.

  METHOD header.
    SKIP.
    ULINE.
    WRITE: / iv_text.
    ULINE.
  ENDMETHOD.

*----------------------------------------------------------------------*
* 1. The assignment gives you the NAME, in uppercase.
*----------------------------------------------------------------------*
  METHOD name_versus_value.

    DATA lv_size TYPE ty_size.
    DATA lv_text TYPE string.
    DATA lv_val  TYPE i.

    header( '1. NAME vs VALUE - an enum assigned to text is an identifier' ).

    lv_size = sz-large.

    " The ONE implicit conversion an enumerated type allows. The pragma
    " suppresses the extended program check message that this line
    " otherwise produces; without it the check tells you the result may
    " not be what you expect - and it is right.
    lv_text = lv_size ##TYPES.

    " The stored value needs the base type spelled out.
    lv_val = CONV i( lv_size ).

    WRITE: / 'lv_size = sz-large'.
    WRITE: / '  lv_text = lv_size       ->', lv_text.
    WRITE: / '  CONV i( lv_size )       ->', lv_val LEFT-JUSTIFIED.
    WRITE: / '  the identifier is the data, the integer is hidden'.

    " WRITE of an enum uses the same rule: output length 30, the name.
    WRITE: / '  WRITE lv_size directly  ->', lv_size.

    " IS INITIAL tests the constant carrying VALUE IS INITIAL. For this
    " type that is sz-small, because an unspecified VALUE list starts at
    " the initial value of the base type.
    CLEAR lv_size.
    IF lv_size IS INITIAL AND lv_size = sz-small.
      WRITE: / '  after CLEAR: IS INITIAL is true and equals sz-small'.
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 2. Same operand, same target type, opposite results.
*----------------------------------------------------------------------*
  METHOD conv_flip.

    DATA lv_name TYPE c LENGTH 10.
    DATA lv_val  TYPE ty_code_base.
    DATA lv_wide TYPE c LENGTH 10.

    header( '2. THE CONV FLIP - one CONV #( ) inverts what you get' ).

    " General conversion rule: the NAME.
    lv_name = cd-released ##TYPES.

    " Special CONV rule: because the target type IS exactly the base
    " type, this returns the VALUE instead.
    lv_val = CONV #( cd-released ).

    WRITE: / 'cd-released, base type ty_code_base = c LENGTH 3'.
    WRITE: / '  lv_name = cd-released            ->', lv_name.
    WRITE: / '  lv_val  = CONV #( cd-released )  ->', lv_val.

    " The deciding factor is the TARGET type, not the expression. Widen
    " the target and the identical CONV #( ) silently switches back to
    " the name, because c LENGTH 10 is no longer the base type.
    lv_wide = CONV #( cd-released ) ##TYPES.
    WRITE: / '  same CONV #( ) into c LENGTH 10  ->', lv_wide.
    WRITE: / '  -> spell the type out: CONV ty_code_base( ... )'.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 3. The converted name carries no prefix, so types collide.
*----------------------------------------------------------------------*
  METHOD name_collision.

    DATA lv_from_code   TYPE string.
    DATA lv_from_status TYPE string.

    header( '3. NAME COLLISION - two enumerated types, one string' ).

    lv_from_code   = CONV string( cd-released ).
    lv_from_status = CONV string( ds-released ).

    WRITE: / 'CONV string( cd-released )  ->', lv_from_code.
    WRITE: / 'CONV string( ds-released )  ->', lv_from_status.

    IF lv_from_code = lv_from_status.
      WRITE: / '  identical text from two incompatible types'.
      WRITE: / '  (cd-released = ds-released would not even compile)'.
    ENDIF.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 4. The short form that casts between unrelated enumerated types.
*----------------------------------------------------------------------*
  METHOD cross_type_cast.

    DATA lv_animal TYPE ty_animal.
    DATA lv_in     TYPE string.
    DATA lv_out    TYPE string.
    DATA lv_number TYPE i.

    header( '4. CROSS-TYPE CAST - matched by value, not by meaning' ).

    " CONV ty_animal( fr-peach ) is the documented short form for
    " CONV ty_animal( CONV i( fr-peach ) ). Legal, silent, and it maps
    " position to position.
    lv_animal = CONV ty_animal( fr-peach ).

    lv_in     = CONV string( fr-peach ).
    lv_out    = CONV string( lv_animal ).
    lv_number = CONV i( fr-peach ).

    WRITE: / 'CONV ty_animal( fr-peach )'.
    WRITE: / '  in  ->', lv_in.
    WRITE: / '  out ->', lv_out.
    WRITE: / '  shared stored value ->', lv_number LEFT-JUSTIFIED.
    WRITE: / '  nothing rejects this: same base type is the only check'.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 5. CONV coerces onto a valid value; EXACT refuses.
*----------------------------------------------------------------------*
  METHOD conv_versus_exact.

    DATA lv_coerced TYPE ty_code.
    DATA lv_text    TYPE string.
    DATA lv_size    TYPE ty_size.
    DATA lv_sizetxt TYPE string.
    DATA lv_bad     TYPE ty_code.
    DATA lv_raw     TYPE i VALUE 9.

    header( '5. CONV vs EXACT - truncated onto a VALID value' ).

    " 'RELX' is not a code. It is cut down to the 3-character base type
    " first, which produces 'REL' - a legal enumerated value. So the
    " validity check passes and no exception is raised.
    lv_coerced = CONV ty_code( `REL` && `X` ).
    lv_text    = CONV string( lv_coerced ).

    WRITE: / 'CONV ty_code( `REL` && `X` )  ->', lv_text.
    WRITE: / '  invalid input, no exception, confidently wrong value'.

    TRY.
        lv_bad = EXACT ty_code( `REL` && `X` ).
        WRITE: / '  EXACT accepted it (unexpected)'.
      CATCH cx_sy_conversion_data_loss.
        WRITE: / '  EXACT ty_code( ... )  -> CX_SY_CONVERSION_DATA_LOSS'.
    ENDTRY.

    " The numeric mirror image: decimal places are cut off, landing on
    " a neighbouring constant.
    lv_size    = CONV ty_size( + '1.2' ).
    lv_sizetxt = CONV string( lv_size ).
    WRITE: / 'CONV ty_size( + ''1.2'' )        ->', lv_sizetxt.

    TRY.
        lv_size = EXACT ty_size( + '1.2' ).
        WRITE: / '  EXACT accepted it (unexpected)'.
      CATCH cx_sy_conversion_rounding.
        WRITE: / '  EXACT ty_size( ... )  -> CX_SY_CONVERSION_ROUNDING'.
    ENDTRY.

    " A value that survives conversion but is outside the value set is
    " the case people expect CONV to catch - and here it does. lv_raw is
    " a variable on purpose: a literal out-of-range value is rejected by
    " the syntax check instead, so it could not be demonstrated at all.
    TRY.
        lv_size = CONV ty_size( lv_raw ).
        WRITE: / '  CONV ty_size( lv_raw ) accepted (unexpected)'.
      CATCH cx_sy_conversion_no_enum_value.
        WRITE: / '  CONV ty_size( lv_raw ) -> CX_SY_CONVERSION_NO_ENUM_VALUE'.
    ENDTRY.

    WRITE: / '  -> validating external input is EXACT, not CONV'.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 6. Single-line reads convert; multi-line reads do not.
*----------------------------------------------------------------------*
  METHOD read_asymmetry.

    DATA lt_rows  TYPE ty_rows.
    DATA ls_row   TYPE ty_row.
    DATA lv_size  TYPE ty_size.
    DATA lv_key   TYPE string.
    DATA lv_count TYPE i.
    DATA lv_subrc TYPE i.

    header( '6. READ ASYMMETRY - READ TABLE and LOOP AT disagree' ).

    lt_rows = VALUE #( ( label = 'SMALL' note = 'the small one' )
                       ( label = 'LARGE' note = 'the large one' )
                       ( label = 'LARGE' note = 'another large one' ) ).

    lv_size = sz-large.

    " SINGLE line read: the comparison field is converted implicitly,
    " so the enum becomes 'LARGE' and this matches.
    READ TABLE lt_rows INTO ls_row WITH KEY label = lv_size.
    lv_subrc = sy-subrc.

    WRITE: / 'READ TABLE ... WITH KEY label = lv_size'.
    WRITE: / '  sy-subrc ->', lv_subrc LEFT-JUSTIFIED.
    WRITE: / '  note     ->', ls_row-note.

    " MULTI line read: no implicit conversion, so the same condition is
    " not accepted. Left as a comment because it does not compile.
*    LOOP AT lt_rows INTO ls_row WHERE label = lv_size.  "<-- no convert
*    ENDLOOP.

    " The multi-row form needs the conversion written out.
    lv_key = CONV string( lv_size ).
    LOOP AT lt_rows INTO ls_row WHERE label = lv_key.
      lv_count = lv_count + 1.
    ENDLOOP.

    WRITE: / 'LOOP AT ... WHERE label = CONV string( lv_size )'.
    WRITE: / '  rows     ->', lv_count LEFT-JUSTIFIED.
    WRITE: / '  -> growing a lookup into a loop changes the rules'.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 7. What the runtime says an enumerated object is.
*----------------------------------------------------------------------*
  METHOD type_description.

    DATA lv_size     TYPE ty_size.
    DATA lv_typekind TYPE c LENGTH 1.
    DATA lv_length   TYPE i.
    DATA lo_enum     TYPE REF TO cl_abap_enumdescr.

    header( '7. RTTI - type kind k, and the members table' ).

    lv_size = sz-medium.

    " DESCRIBE FIELD reports k for any enumerated object. Generic code
    " that switches on I/C/N/P/D/T/X falls through to WHEN OTHERS here.
    DESCRIBE FIELD lv_size TYPE lv_typekind LENGTH lv_length
                   IN BYTE MODE.

    WRITE: / 'DESCRIBE FIELD lv_size'.
    WRITE: / '  TYPE   ->', lv_typekind.
    WRITE: / '  LENGTH ->', lv_length LEFT-JUSTIFIED, '(base type bytes)'.

    lo_enum = CAST cl_abap_enumdescr(
                cl_abap_typedescr=>describe_by_data( lv_size ) ).

    WRITE: / 'CL_ABAP_ENUMDESCR'.
    WRITE: / '  kind            ->', lo_enum->kind.
    WRITE: / '  type_kind       ->', lo_enum->type_kind.
    WRITE: / '  base_type_kind  ->', lo_enum->base_type_kind.
    WRITE: / '  members:'.

    " The supported way to enumerate an enum. Unlike ASSIGN struc-(idx)
    " this does not depend on component order, which differs between
    " ABAP enums (definition order) and CDS enums (alphabetical).
    LOOP AT lo_enum->members ASSIGNING FIELD-SYMBOL(<ls_member>).
      WRITE: /6 <ls_member>-name, <ls_member>-value.
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  lcl_demo=>run( ).
