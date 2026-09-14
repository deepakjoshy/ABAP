*&---------------------------------------------------------------------*
*& Report YDJ_RTTS_DEMO
*&---------------------------------------------------------------------*
*& Runtime Type Services: the traps in describe_by_*, component lists
*& and CREATE DATA ... TYPE HANDLE.
*&
*&   1. COMPONENT LISTS -> the attribute `components` and the method
*&                         `get_components( )` return DIFFERENT tables;
*&                         an INCLUDE collapses to one line in the
*&                         method, flagged with as_include = 'X'.
*&   2. CLASSIC EXC.    -> describe_by_name raises TYPE_NOT_FOUND, a
*&                         classic exception. TRY/CATCH cx_root does
*&                         NOT catch it; only EXCEPTIONS + sy-subrc.
*&   3. GET vs CREATE   -> create( ) always allocates a new type
*&                         description object, get( ) reuses one.
*&   4. RTTC            -> building a sorted table type at runtime and
*&                         filling it through field symbols.
*&   5. NAMES           -> a bound type has an absolute name of the
*&                         form \TYPE=%_... and NO relative name.
*&
*& Self-contained: no DDIC objects and no demo data needed.
*&---------------------------------------------------------------------*
REPORT ydj_rtts_demo.

TYPES: BEGIN OF ty_address,
         city TYPE c LENGTH 20,
         zip  TYPE n LENGTH 6,
       END OF ty_address.

" A structure with a named, renamed include - the case get_components( )
" does not flatten.
TYPES BEGIN OF ty_document.
TYPES docid TYPE c LENGTH 10.
INCLUDE TYPE ty_address AS addr RENAMING WITH SUFFIX _ad.
TYPES amount TYPE p LENGTH 9 DECIMALS 2.
TYPES END OF ty_document.


CLASS lcl_rtts_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      components_vs_get_components,
      describe_by_name_is_classic,
      get_is_not_create,
      build_table_type_at_runtime,
      absolute_vs_relative_name.

ENDCLASS.


CLASS lcl_rtts_demo IMPLEMENTATION.

  METHOD components_vs_get_components.

    DATA ls_doc TYPE ty_document.

    " describe_by_data returns CL_ABAP_TYPEDESCR, so a cast is needed
    " before any structure-specific member is reachable.
    DATA(lo_struct) = CAST cl_abap_structdescr(
                        cl_abap_typedescr=>describe_by_data( ls_doc ) ).

    WRITE: / '  has_include        :', lo_struct->has_include.

    " The ATTRIBUTE: flat field list, but only name/type_kind/length/decimals.
    WRITE: / '  components         :', lines( lo_struct->components ), 'line(s)'.
    LOOP AT lo_struct->components ASSIGNING FIELD-SYMBOL(<comp>).
      WRITE: /  '     ', <comp>-name,
                'kind', <comp>-type_kind,
                'len',  <comp>-length,
                'dec',  <comp>-decimals.
    ENDLOOP.

    " The METHOD: full type description objects, but the include stays
    " collapsed into a single line carrying as_include = 'X'.
    DATA(lt_comps) = lo_struct->get_components( ).
    WRITE: / '  get_components( )  :', lines( lt_comps ), 'line(s)'.
    LOOP AT lt_comps ASSIGNING FIELD-SYMBOL(<c>).
      WRITE: /  '     ', <c>-name,
                'as_include', <c>-as_include,
                'suffix',     <c>-suffix.
    ENDLOOP.

    " get_included_view( ) resolves the include; p_level says how deep.
    DATA(lt_view0) = lo_struct->get_included_view( 0 ).
    DATA(lt_view1) = lo_struct->get_included_view( 1 ).
    WRITE: / '  included_view( 0 ) :', lines( lt_view0 ), 'line(s) - include still collapsed'.
    WRITE: / '  included_view( 1 ) :', lines( lt_view1 ), 'line(s) - include resolved'.

  ENDMETHOD.

  METHOD describe_by_name_is_classic.

    DATA lo_type TYPE REF TO cl_abap_typedescr.

    " TYPE_NOT_FOUND is a CLASSIC exception. This would dump, uncaught,
    " even inside TRY ... CATCH cx_root - which is why it is commented out:
    "
    "   TRY.
    "       lo_type = cl_abap_typedescr=>describe_by_name( 'YDJ_NO_SUCH_TYPE' ).
    "     CATCH cx_root.          " never reached
    "   ENDTRY.
    "
    " The classic call form is the only way to handle it. Note that this
    " form cannot be written as an expression.
    CALL METHOD cl_abap_typedescr=>describe_by_name
      EXPORTING  p_name         = 'YDJ_NO_SUCH_TYPE'
      RECEIVING  p_descr_ref    = lo_type
      EXCEPTIONS type_not_found = 4.

    IF sy-subrc <> 0.
      WRITE: / '  unknown type handled, sy-subrc =', sy-subrc, '- no dump'.
    ELSE.
      WRITE: / '  type found:', lo_type->absolute_name.
    ENDIF.

    " A name that does exist, for contrast.
    CALL METHOD cl_abap_typedescr=>describe_by_name
      EXPORTING  p_name         = 'TY_ADDRESS'
      RECEIVING  p_descr_ref    = lo_type
      EXCEPTIONS type_not_found = 4.

    IF sy-subrc = 0.
      WRITE: / '  TY_ADDRESS kind   :', lo_type->kind,
               'ddic', lo_type->is_ddic_type( ).
    ENDIF.

  ENDMETHOD.

  METHOD get_is_not_create.

    DATA(lt_def) = VALUE abap_component_tab(
                     ( name = 'A' type = cl_abap_elemdescr=>get_i( ) ) ).

    DATA(lo_get_1) = cl_abap_structdescr=>get( lt_def ).
    DATA(lo_get_2) = cl_abap_structdescr=>get( lt_def ).
    DATA(lo_new_1) = cl_abap_structdescr=>create( lt_def ).
    DATA(lo_new_2) = cl_abap_structdescr=>create( lt_def ).

    " Comparing object references tests identity, not content.
    IF lo_get_1 = lo_get_2.
      WRITE: / '  get( )    twice -> SAME type description object'.
    ELSE.
      WRITE: / '  get( )    twice -> two objects'.
    ENDIF.

    IF lo_new_1 = lo_new_2.
      WRITE: / '  create( ) twice -> same object'.
    ELSE.
      WRITE: / '  create( ) twice -> TWO objects for one type'.
    ENDIF.

  ENDMETHOD.

  METHOD build_table_type_at_runtime.

    DATA lr_tab  TYPE REF TO data.
    DATA lr_line TYPE REF TO data.

    FIELD-SYMBOLS <tab>  TYPE ANY TABLE.
    FIELD-SYMBOLS <line> TYPE any.

    " Line type built component by component.
    DATA(lo_line) = cl_abap_structdescr=>get( VALUE #(
                      ( name = 'CARRID' type = cl_abap_elemdescr=>get_c( 3 ) )
                      ( name = 'SEATS'  type = cl_abap_elemdescr=>get_i( ) ) ) ).

    " Table type WITH an explicit key. Leaving p_key/p_key_kind out would
    " silently fall back to a standard table with a standard key.
    DATA(lo_tab) = cl_abap_tabledescr=>get(
                     p_line_type  = lo_line
                     p_table_kind = cl_abap_tabledescr=>tablekind_sorted
                     p_key        = VALUE #( ( name = 'CARRID' ) )
                     p_unique     = abap_true
                     p_key_kind   = cl_abap_tabledescr=>keydefkind_user ).

    CREATE DATA lr_tab  TYPE HANDLE lo_tab.
    CREATE DATA lr_line TYPE HANDLE lo_line.

    ASSIGN lr_tab->*  TO <tab>.
    ASSIGN lr_line->* TO <line>.

    " Nothing about the line type is known at compile time, so the
    " components are addressed dynamically.
    ASSIGN COMPONENT 'CARRID' OF STRUCTURE <line> TO FIELD-SYMBOL(<carrid>).
    ASSIGN COMPONENT 'SEATS'  OF STRUCTURE <line> TO FIELD-SYMBOL(<seats>).

    <carrid> = 'LH'. <seats> = 220.
    INSERT <line> INTO TABLE <tab>.

    <carrid> = 'AA'. <seats> = 180.
    INSERT <line> INTO TABLE <tab>.

    " Unique key: this second 'LH' must be rejected with sy-subrc = 4.
    <carrid> = 'LH'. <seats> = 999.
    INSERT <line> INTO TABLE <tab>.
    WRITE: / '  duplicate INSERT sy-subrc =', sy-subrc.

    DESCRIBE TABLE <tab> KIND DATA(lv_kind).
    WRITE: / '  table kind =', lv_kind,
             '( S = sorted )   lines =', lines( <tab> ).

    " Read back through the generated key.
    LOOP AT <tab> ASSIGNING FIELD-SYMBOL(<row>).
      ASSIGN COMPONENT 'CARRID' OF STRUCTURE <row> TO <carrid>.
      ASSIGN COMPONENT 'SEATS'  OF STRUCTURE <row> TO <seats>.
      WRITE: / '     ', <carrid>, <seats>.
    ENDLOOP.

  ENDMETHOD.

  METHOD absolute_vs_relative_name.

    " A bound (anonymous) type: declared inline, never named in the DDIC
    " or in a TYPES statement.
    DATA lv_packed TYPE p LENGTH 8 DECIMALS 2.
    DATA(lo_bound) = cl_abap_typedescr=>describe_by_data( lv_packed ).

    WRITE: / '  bound  absolute_name:', lo_bound->absolute_name.
    WRITE: / '  bound  relative_name:', lo_bound->get_relative_name( ).
    WRITE: / '  bound  is_ddic_type :', lo_bound->is_ddic_type( ).

    " A named local type, for contrast: this one has a relative name and
    " can be fed straight back into CREATE DATA ... TYPE ( ).
    DATA ls_addr TYPE ty_address.
    DATA(lo_named) = cl_abap_typedescr=>describe_by_data( ls_addr ).

    WRITE: / '  named  absolute_name:', lo_named->absolute_name.
    WRITE: / '  named  relative_name:', lo_named->get_relative_name( ).

    DATA lr_data TYPE REF TO data.
    TRY.
        CREATE DATA lr_data TYPE (lo_named->absolute_name).
        WRITE: / '  CREATE DATA from named absolute_name  -> ok'.
      CATCH cx_sy_create_data_error.
        WRITE: / '  CREATE DATA from named absolute_name  -> rejected'.
    ENDTRY.

    TRY.
        CREATE DATA lr_data TYPE (lo_bound->absolute_name).
        WRITE: / '  CREATE DATA from bound absolute_name  -> ok here,'.
        WRITE: / '     but rejected in ABAP for Cloud Development'.
      CATCH cx_sy_create_data_error.
        WRITE: / '  CREATE DATA from bound absolute_name  -> rejected'.
    ENDTRY.

    " The portable way: pass the type description object itself. TYPE HANDLE
    " needs a reference variable of type CL_ABAP_DATADESCR (or a subclass),
    " so the cast has to land in a variable first.
    DATA(lo_datadescr) = CAST cl_abap_datadescr( lo_bound ).
    CREATE DATA lr_data TYPE HANDLE lo_datadescr.
    WRITE: / '  CREATE DATA ... TYPE HANDLE           -> ok'.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  WRITE: / '1. components vs get_components( ) on a structure with an INCLUDE'.
  lcl_rtts_demo=>components_vs_get_components( ).

  SKIP.
  WRITE: / '2. describe_by_name raises a CLASSIC exception'.
  lcl_rtts_demo=>describe_by_name_is_classic( ).

  SKIP.
  WRITE: / '3. get( ) reuses a type object, create( ) always allocates'.
  lcl_rtts_demo=>get_is_not_create( ).

  SKIP.
  WRITE: / '4. RTTC: building a sorted table type at runtime'.
  lcl_rtts_demo=>build_table_type_at_runtime( ).

  SKIP.
  WRITE: / '5. absolute_name vs relative_name for a bound type'.
  lcl_rtts_demo=>absolute_vs_relative_name( ).
