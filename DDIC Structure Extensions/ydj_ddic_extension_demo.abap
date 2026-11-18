*&---------------------------------------------------------------------*
*& Report YDJ_DDIC_EXTENSION_DEMO
*&---------------------------------------------------------------------*
*& The append-structure / enhancement-category traps that can be shown
*& WITHOUT creating a Dictionary object and without changing anything.
*&
*& This report is read-only by construction: four SELECTs against the
*& Dictionary tables DD02L / DD03L plus RTTI. No write, no COMMIT, no
*& DDIC activation. Nothing here can trigger a table adjustment.
*&
*&   1. THE OFF-BY-ONE   -> DD02L-EXCLASS is a DDRANKING, fixed values
*&                    0..4, while SAP Help numbers the same five
*&                    categories 1..5. Part 1 prints the raw value
*&                    next to BOTH readings, so the mismatch is
*&                    visible on your own system rather than taken
*&                    on trust. It also prints DD02L-WRONGCL, the
*&                    flag for a declared category that no longer
*&                    matches the content.
*&   2. WHO APPENDS      -> an append structure is its own DD02L row with
*&                    TABCLASS = APPEND, and DD02L-SQLTAB on that
*&                    row names the appended table. So "what is
*&                    appended to this table" is one SELECT.
*&   3. TWO POSITIONS    -> DD03L carries POSITION and DBPOSITION, both
*&                    labelled "Position of the field in the
*&                    table". After an append they can disagree,
*&                    which is the documented consequence that the
*&                    Dictionary order is not the database order.
*&                    Part 3 lists the rows where they differ.
*&   4. IMPLIED CEILING  -> the enhancement category a structure is
*&                    ALLOWED to carry is derived from its content.
*&                    Part 4 classifies every component through RTTI
*&                    and prints the implied ceiling next to the
*&                    declared category, which is the check that
*&                    catches post-upgrade drift.
*&
*& Notes:
*&   - describe_by_name raises a CLASSIC exception, so it is called with
*&     CALL METHOD ... EXCEPTIONS and a sy-subrc check. See this repo's
*&     Runtime Type Services note for why TRY/CATCH does not help.
*&   - AS4LOCAL = A selects the ACTIVE version of a Dictionary object.
*&   - Defaults to SFLIGHT, which normally has no append at all: part 2
*&     printing nothing is the expected result, not a failure. Point it
*&     at a table you have extended to see the interesting output.
*&---------------------------------------------------------------------*
REPORT ydj_ddic_extension_demo.

PARAMETERS p_tab  TYPE tabname OBLIGATORY DEFAULT 'SFLIGHT'.
PARAMETERS p_all  AS CHECKBOX DEFAULT space.


CLASS lcl_ext_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      declared_category,
      appending_objects,
      dictionary_vs_db_order,
      implied_ceiling.

  PRIVATE SECTION.

    " The five categories as they are STORED (domain DDRANKING), with
    " the level number used by SAP Help for the same row in brackets.
    CLASS-METHODS category_text
      IMPORTING iv_exclass     TYPE dd02l-exclass
      RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.


CLASS lcl_ext_demo IMPLEMENTATION.

  METHOD category_text.

    CASE iv_exclass.
      WHEN '0'.
        rv_text = 'Not classified               (Help level 1)'.
      WHEN '1'.
        rv_text = 'Cannot be enhanced           (Help level 2)'.
      WHEN '2'.
        rv_text = 'Can be enhanced, char-type   (Help level 3)'.
      WHEN '3'.
        rv_text = 'Can be enhanced, char/numc   (Help level 4)'.
      WHEN '4'.
        rv_text = 'Can be enhanced, deep        (Help level 5)'.
      WHEN OTHERS.
        rv_text = 'unknown value - check domain DDRANKING'.
    ENDCASE.

  ENDMETHOD.

  METHOD declared_category.

    DATA lv_tabclass TYPE dd02l-tabclass.
    DATA lv_exclass  TYPE dd02l-exclass.
    DATA lv_wrongcl  TYPE dd02l-wrongcl.
    DATA lv_text     TYPE string.

    SELECT SINGLE tabclass, exclass, wrongcl
      FROM dd02l
      WHERE tabname  = @p_tab
        AND as4local = 'A'
      INTO (@lv_tabclass, @lv_exclass, @lv_wrongcl).

    IF sy-subrc <> 0.
      WRITE: / '  no active DD02L row for', p_tab,
               '- not a table or structure'.
      RETURN.
    ENDIF.

    lv_text = category_text( lv_exclass ).

    WRITE: /  '  TABCLASS         :', lv_tabclass.
    WRITE: /  '  EXCLASS (raw)    :', lv_exclass.
    WRITE: /  '  EXCLASS means    :', lv_text.

    " The trap, stated as arithmetic: a report written from the Help
    " page looks for the DOCUMENTED level number in a field that holds
    " the DOMAIN value, so it is always one row off.
    IF lv_exclass = '1'.
      WRITE: / '  read as a Help level, 1 would say "Not classified".'.
      WRITE: / '  Stored, 1 says "Cannot be enhanced". Opposite case.'.
    ENDIF.

    IF lv_wrongcl IS INITIAL.
      WRITE: / '  WRONGCL          : (blank) - declared category is',
               'consistent with the content'.
    ELSE.
      WRITE: / '  WRONGCL          :', lv_wrongcl,
               '- DECLARED CATEGORY IS INCORRECT'.
      WRITE: / '  The content now implies a more general category than'.
      WRITE: / '  the one declared. Part 4 shows which one.'.
    ENDIF.

  ENDMETHOD.

  METHOD appending_objects.

    DATA lv_count TYPE i.

    " An append structure is a Dictionary object in its own right:
    " TABCLASS = APPEND (domain TABCLASS, fixed value "Append
    " structure"), and SQLTAB on that row carries the appended table.
    SELECT tabname, exclass
      FROM dd02l
      WHERE tabclass = 'APPEND'
        AND sqltab   = @p_tab
        AND as4local = 'A'
      ORDER BY tabname
      INTO TABLE @DATA(lt_appends)
      UP TO 50 ROWS.

    lv_count = lines( lt_appends ).
    WRITE: / '  append structures:', lv_count.

    LOOP AT lt_appends ASSIGNING FIELD-SYMBOL(<app>).
      DATA(lv_app_text) = category_text( <app>-exclass ).
      WRITE: /  '    ', <app>-tabname, '|', lv_app_text.
    ENDLOOP.

    IF lv_count = 0.
      WRITE: / '    none - nothing is appended to this object'.
    ENDIF.

  ENDMETHOD.

  METHOD dictionary_vs_db_order.

    DATA lv_fields    TYPE i.
    DATA lv_structrow TYPE i.
    DATA lv_mismatch  TYPE i.
    DATA lv_first     TYPE c LENGTH 1.

    SELECT fieldname, position, dbposition, keyflag, precfield
      FROM dd03l
      WHERE tabname  = @p_tab
        AND as4local = 'A'
      ORDER BY position
      INTO TABLE @DATA(lt_fields)
      UP TO 500 ROWS.

    IF sy-subrc <> 0.
      WRITE: / '  no active DD03L rows for', p_tab.
      RETURN.
    ENDIF.

    LOOP AT lt_fields ASSIGNING FIELD-SYMBOL(<fld>).

      lv_first = <fld>-fieldname(1).

      " Rows whose field name starts with a dot are structure-level
      " rows rather than columns - SE11 shows them as .INCLUDE and
      " .APPEND, and PRECFIELD ("Name of included table") names the
      " included object. Empirical, not from the keyword docs.
      IF lv_first = '.'.
        lv_structrow = lv_structrow + 1.
        WRITE: /  '    ', <fld>-fieldname, '->', <fld>-precfield.
        CONTINUE.
      ENDIF.

      lv_fields = lv_fields + 1.

      " DBPOSITION is blank for pure structures, so only compare it
      " where the object really has a database representation.
      IF <fld>-dbposition IS NOT INITIAL
         AND <fld>-dbposition <> <fld>-position.
        lv_mismatch = lv_mismatch + 1.
        IF lv_mismatch <= 20.
          WRITE: /  '    ', <fld>-fieldname,
                    'DDIC pos', <fld>-position,
                    'DB pos',   <fld>-dbposition.
        ENDIF.
      ELSEIF p_all = 'X'.
        WRITE: /  '    ', <fld>-fieldname,
                  'pos', <fld>-position,
                  'key', <fld>-keyflag.
      ENDIF.

    ENDLOOP.

    WRITE: / '  columns          :', lv_fields.
    WRITE: / '  structure rows   :', lv_structrow.
    WRITE: / '  order mismatches :', lv_mismatch.

    IF lv_mismatch = 0.
      WRITE: / '  DDIC order and DB order agree here. They are NOT'.
      WRITE: / '  required to: appending does not re-order the'.
      WRITE: / '  physical table, so address columns by name.'.
    ELSE.
      WRITE: / '  DDIC order and DB column order DISAGREE. ABAP SQL is'.
      WRITE: / '  unaffected (it selects by name); positional access'.
      WRITE: / '  such as Native SQL without a column list is not.'.
    ENDIF.

  ENDMETHOD.

  METHOD implied_ceiling.

    DATA lo_type    TYPE REF TO cl_abap_typedescr.
    DATA lo_struct  TYPE REF TO cl_abap_structdescr.
    DATA lv_char    TYPE i.
    DATA lv_numeric TYPE i.
    DATA lv_deep    TYPE i.
    DATA lv_nested  TYPE i.
    DATA lv_unknown TYPE i.
    DATA lv_implied TYPE dd02l-exclass.
    DATA lv_declared TYPE dd02l-exclass.
    DATA lv_text    TYPE string.

    " Classic exception: TRY/CATCH cx_root would NOT catch this.
    CALL METHOD cl_abap_typedescr=>describe_by_name
      EXPORTING  p_name         = p_tab
      RECEIVING  p_descr_ref    = lo_type
      EXCEPTIONS type_not_found = 4.

    IF sy-subrc <> 0.
      WRITE: / '  RTTI does not know', p_tab, '- nothing to classify'.
      RETURN.
    ENDIF.

    IF lo_type->kind <> cl_abap_typedescr=>kind_struct.
      WRITE: / ' ', p_tab, 'is not a structured type - skipped'.
      RETURN.
    ENDIF.

    lo_struct = CAST cl_abap_structdescr( lo_type ).

    " The ATTRIBUTE components, not get_components( ): a flat list of
    " name / type_kind / length / decimals is all the classification
    " needs, and includes are already resolved in a DDIC type.
    LOOP AT lo_struct->components ASSIGNING FIELD-SYMBOL(<c>).

      CASE <c>-type_kind.

        " Character-like per SAP Help: C, D, N, T.
        WHEN cl_abap_typedescr=>typekind_char
          OR cl_abap_typedescr=>typekind_num
          OR cl_abap_typedescr=>typekind_date
          OR cl_abap_typedescr=>typekind_time.
          lv_char = lv_char + 1.

        " Numeric per the same page: F, I, P, X (plus the decfloats).
        WHEN cl_abap_typedescr=>typekind_int
          OR cl_abap_typedescr=>typekind_packed
          OR cl_abap_typedescr=>typekind_float
          OR cl_abap_typedescr=>typekind_hex
          OR cl_abap_typedescr=>typekind_decfloat16
          OR cl_abap_typedescr=>typekind_decfloat34.
          lv_numeric = lv_numeric + 1.

        " Deep: strings, references, internal tables.
        WHEN cl_abap_typedescr=>typekind_string
          OR cl_abap_typedescr=>typekind_xstring
          OR cl_abap_typedescr=>typekind_table
          OR cl_abap_typedescr=>typekind_oref
          OR cl_abap_typedescr=>typekind_dref.
          lv_deep = lv_deep + 1.

        WHEN cl_abap_typedescr=>typekind_struct1
          OR cl_abap_typedescr=>typekind_struct2.
          lv_nested = lv_nested + 1.

        WHEN OTHERS.
          " Newer flat kinds such as INT8 or UTCLONG land here. They
          " are counted and reported rather than guessed at, so the
          " ceiling below is never LOWERED by an unclassified kind.
          lv_unknown = lv_unknown + 1.

      ENDCASE.

      IF p_all = 'X'.
        WRITE: /  '    ', <c>-name, 'kind', <c>-type_kind.
      ENDIF.

    ENDLOOP.

    WRITE: / '  char-like / numeric / deep :',
             lv_char, lv_numeric, lv_deep.
    WRITE: / '  nested / unclassified      :', lv_nested, lv_unknown.

    " Derivation, in the documented order: one deep component forces
    " the most general category; otherwise one numeric component rules
    " out character-type; otherwise character-type is still reachable.
    IF lv_deep > 0.
      lv_implied = '4'.
    ELSEIF lv_numeric > 0.
      lv_implied = '3'.
    ELSE.
      lv_implied = '2'.
    ENDIF.

    lv_text = category_text( lv_implied ).
    WRITE: / '  implied ceiling  :', lv_implied, lv_text.

    SELECT SINGLE exclass
      FROM dd02l
      WHERE tabname  = @p_tab
        AND as4local = 'A'
      INTO @lv_declared.

    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    IF lv_declared = '0'.
      WRITE: / '  declared "Not classified" - every consumer gets the'.
      WRITE: / '  unclassified-structure warning until this is set.'.
    ELSEIF lv_declared > lv_implied.
      WRITE: / '  DECLARED IS MORE PERMISSIVE THAN THE CONTENT NEEDS.'.
      WRITE: / '  Nothing is wrong with the table. The cost is paid in'.
      WRITE: / '  consumers: offset/length and structure assignments'.
      WRITE: / '  on this type are flagged, and an extension that'.
      WRITE: / '  exhausts the category makes them a syntax error.'.
    ELSEIF lv_declared < lv_implied.
      WRITE: / '  DECLARED IS STRICTER THAN THE CONTENT ALLOWS - this'.
      WRITE: / '  is the inconsistency DD02L-WRONGCL exists for. It'.
      WRITE: / '  appears after an upgrade or a transport, with no'.
      WRITE: / '  local change to blame.'.
    ELSE.
      WRITE: / '  declared category equals the implied ceiling - the'.
      WRITE: / '  tightest classification this content permits.'.
    ENDIF.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  WRITE: / 'DDIC structure extensions - read-only inspection of', p_tab.
  WRITE: / '(no write, no COMMIT, no activation)'.
  SKIP.

  WRITE: / '1. Declared enhancement category (DD02L)'.
  lcl_ext_demo=>declared_category( ).
  SKIP.

  WRITE: / '2. What is appended to it (DD02L, TABCLASS = APPEND)'.
  lcl_ext_demo=>appending_objects( ).
  SKIP.

  WRITE: / '3. Dictionary order vs database order (DD03L)'.
  lcl_ext_demo=>dictionary_vs_db_order( ).
  SKIP.

  WRITE: / '4. Category implied by the content (RTTI)'.
  lcl_ext_demo=>implied_ceiling( ).
  SKIP.

  WRITE: / 'Reminder: the restrictive category is the safe one. The'.
  WRITE: / 'permissive one is what flags your own offset/length code.'.
