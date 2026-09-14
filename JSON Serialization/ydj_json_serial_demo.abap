*&---------------------------------------------------------------------*
*& Report YDJ_JSON_SERIAL_DEMO
*&---------------------------------------------------------------------*
*& JSON/XML serialization with the identity transformation ID, and the
*& asJSON behaviours that surprise both sides of an interface.
*&
*& asJSON is the canonical JSON format produced ONLY by CALL
*& TRANSFORMATION id. It is not configurable - what it emits is what
*& the consumer gets.
*&
*&   1. NAMES        -> Object names are the SOURCE/RESULT PARAMETER
*&                      names, not the ABAP variable names. Renaming a
*&                      parameter breaks the payload contract with no
*&                      syntax error. Static binding UPPER-CASES the
*&                      name; dynamic binding via ABAP_TRANS_SRCBIND_TAB
*&                      preserves the case it is given.
*&   2. NO BOOLEANS  -> "Representations of Boolean values and zero are
*&                      not used." abap_bool is char1, so it becomes
*&                      "X" / "" - never true / false. NUMC keeps its
*&                      leading zeros because n is character-like.
*&   3. CLEAR        -> Defaults to none. RESULT target fields are NOT
*&                      initialized (except internal tables), so a
*&                      field missing from the payload silently keeps
*&                      the PREVIOUS record value. Use clear = all.
*&   4. SUPPRESS     -> initial_components = suppress drops initial
*&                      components from the payload entirely, incl.
*&                      a meaningful XSDBOOLEAN abap_false.
*&   5. DATA LOSS    -> value_handling = accept_data_loss truncates
*&                      c and x on the RIGHT but n on the LEFT. The
*&                      default raises CX_SY_CONVERSION_DATA_LOSS,
*&                      which arrives packed in CX_TRANSFORMATION_ERROR
*&                      and cannot be caught as itself.
*&
*& Read-only. No database access, no changes of any kind.
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCALL_TRANSFORMATION.html
*&       https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapcall_transformation_options.htm
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_ASJSON.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_ASJSON_ABAP_TYPES_ELEM.html
*&---------------------------------------------------------------------*
REPORT ydj_json_serial_demo.

CLASS lcl_json_demo DEFINITION.

  PUBLIC SECTION.

    TYPES:
      " Deliberately mixed types: one of every asJSON mapping class.
      BEGIN OF ty_order,
        order_id TYPE i,              " numeric  -> unquoted number
        customer TYPE string,         " char     -> quoted string
        matnr    TYPE n LENGTH 8,     " NUMC     -> quoted, zeros kept
        urgent   TYPE abap_bool,      " char1    -> "X" / "", NOT bool
        amount   TYPE p LENGTH 8 DECIMALS 2,
      END OF ty_order,

      " Short targets, to show the truncation directions.
      BEGIN OF ty_short,
        txt TYPE c LENGTH 4,          " cut on the RIGHT
        num TYPE n LENGTH 4,          " cut on the LEFT
      END OF ty_short.

    CLASS-METHODS:
      uppercase_names,
      no_json_booleans,
      clear_option_bleed,
      suppress_initial_components,
      value_handling_truncation.

  PRIVATE SECTION.

    " Serialize any data object to a JSON string via an sXML JSON writer.
    " Kept in one place because every section needs it.
    CLASS-METHODS to_json
      IMPORTING iv_name        TYPE string
                is_data        TYPE any
      RETURNING VALUE(rv_json) TYPE string.

ENDCLASS.


CLASS lcl_json_demo IMPLEMENTATION.

  METHOD to_json.

    " The type constant is the ONLY thing that decides XML vs JSON.
    " if_sxml=>co_xt_xml10 would emit asXML from the very same call.
    DATA(lo_writer) = cl_sxml_string_writer=>create( type = if_sxml=>co_xt_json ).

    " Dynamic source binding: a table of name/data-reference pairs,
    " typed ABAP_TRANS_SRCBIND_TAB from type group ABAP. This is the
    " ONLY form that lets the name be decided at runtime - there is no
    " "SOURCE (lv_name) = data" syntax.
    DATA(lt_source) = VALUE abap_trans_srcbind_tab(
                        ( name = iv_name value = REF #( is_data ) ) ).

    " Note: the addition is RESULT XML even though this is a JSON writer.
    CALL TRANSFORMATION id
      SOURCE (lt_source)
      RESULT XML lo_writer.

    " get_output( ) always returns xstring, never string.
    " On releases before cl_abap_conv_codepage, use cl_abap_conv_in_ce.
    rv_json = cl_abap_conv_codepage=>create_in( )->convert( lo_writer->get_output( ) ).

  ENDMETHOD.


  METHOD uppercase_names.

    WRITE: / '1. asJSON NAMES COME FROM THE PARAMETER, NOT THE VARIABLE'.
    SKIP.

    DATA(ls_order) = VALUE ty_order( order_id = 4711
                                     customer = 'ACME'
                                     matnr    = '12345'
                                     urgent   = abap_true
                                     amount   = '99.50' ).

    " Static binding: the parameter name, always upper-cased.
    DATA(lo_static) = cl_sxml_string_writer=>create( type = if_sxml=>co_xt_json ).
    CALL TRANSFORMATION id
      SOURCE order = ls_order
      RESULT XML lo_static.

    DATA(lv_static) = cl_abap_conv_codepage=>create_in( )->convert( lo_static->get_output( ) ).
    WRITE: / '   SOURCE order = ...   ->', lv_static.

    " Same data, a different name - via the dynamic bind table.
    DATA(lv_dyn_pay) = to_json( iv_name = `payload` is_data = ls_order ).
    WRITE: / '   dynamic name payload ->', lv_dyn_pay.

    " And the escape hatch: dynamic binding PRESERVES the case given,
    " where static binding always upper-cases. This is the only way to
    " get a lowercase key out of the identity transformation.
    DATA(lv_dyn_ord) = to_json( iv_name = `order` is_data = ls_order ).
    WRITE: / '   dynamic name order   ->', lv_dyn_ord.

    SKIP.
    WRITE: / '   The ABAP variable is called ls_order every time.'.
    WRITE: / '   The JSON key changed anyway - the contract is the'.
    WRITE: / '   parameter name, not the variable name. Renaming it for'.
    WRITE: / '   readability is a breaking interface change.'.
    WRITE: / '   Note the case: static gives ORDER, dynamic gives order.'.

    SKIP 2.

  ENDMETHOD.


  METHOD no_json_booleans.

    WRITE: / '2. NO JSON BOOLEANS, AND NUMC KEEPS ITS LEADING ZEROS'.
    SKIP.

    DATA(ls_true)  = VALUE ty_order( order_id = 1 urgent = abap_true  matnr = '12345' ).
    DATA(ls_false) = VALUE ty_order( order_id = 2 urgent = abap_false matnr = '12345' ).

    DATA(lv_json_true)  = to_json( iv_name = `o` is_data = ls_true ).
    DATA(lv_json_false) = to_json( iv_name = `o` is_data = ls_false ).

    WRITE: / '   urgent = abap_true  ->', lv_json_true.
    WRITE: / '   urgent = abap_false ->', lv_json_false.

    SKIP.
    WRITE: / '   URGENT is "X" and "" - never true / false, because'.
    WRITE: / '   abap_bool is char1 and the doc states outright that'.
    WRITE: / '   Boolean representations are not used.'.
    WRITE: / '   MATNR is quoted with its zeros because n is'.
    WRITE: / '   character-like. /ui2/cl_json drops them by default.'.

    SKIP 2.

  ENDMETHOD.


  METHOD clear_option_bleed.

    WRITE: / '3. clear = none (THE DEFAULT) LEAKS THE PREVIOUS RECORD'.
    SKIP.

    " Payload for a second order that legitimately carries no customer.
    DATA(lv_json) = `{"ORDER":{"ORDER_ID":4712,"MATNR":"00099999"}}`.

    " --- the way it is usually written -------------------------------
    DATA(ls_reused) = VALUE ty_order( order_id = 4711 customer = 'ACME' ).

    CALL TRANSFORMATION id
      SOURCE XML lv_json
      RESULT order = ls_reused.

    WRITE: / '   default       -> ORDER_ID', ls_reused-order_id,
             'CUSTOMER', ls_reused-customer.

    " --- the same call with the recommended option -------------------
    DATA(ls_cleared) = VALUE ty_order( order_id = 4711 customer = 'ACME' ).

    CALL TRANSFORMATION id
      SOURCE XML lv_json
      RESULT order = ls_cleared
      OPTIONS clear = 'all'.

    WRITE: / '   clear = all   -> ORDER_ID', ls_cleared-order_id,
             'CUSTOMER', ls_cleared-customer.

    SKIP.
    WRITE: / '   The payload has NO customer node. Without clear = all'.
    WRITE: / '   order 4712 is still billed to ACME - sy-subrc = 0, no'.
    WRITE: / '   exception, nothing to see in a trace.'.
    WRITE: / '   Why this survives testing: internal tables ARE cleared'.
    WRITE: / '   by default, so only flat-structure targets bleed.'.

    SKIP 2.

  ENDMETHOD.


  METHOD suppress_initial_components.

    WRITE: / '4. initial_components = suppress DROPS REAL VALUES'.
    SKIP.

    " Only order_id is filled; everything else is initial.
    DATA(ls_sparse) = VALUE ty_order( order_id = 4713 ).

    DATA(lo_default)  = cl_sxml_string_writer=>create( type = if_sxml=>co_xt_json ).
    DATA(lo_suppress) = cl_sxml_string_writer=>create( type = if_sxml=>co_xt_json ).

    CALL TRANSFORMATION id
      SOURCE order = ls_sparse
      RESULT XML lo_default.

    CALL TRANSFORMATION id
      SOURCE order = ls_sparse
      RESULT XML lo_suppress
      OPTIONS initial_components = 'suppress'.

    DATA(lv_def) = cl_abap_conv_codepage=>create_in( )->convert( lo_default->get_output( ) ).
    DATA(lv_sup) = cl_abap_conv_codepage=>create_in( )->convert( lo_suppress->get_output( ) ).

    WRITE: / '   suppress_boxed ->', lv_def.
    WRITE: / '   suppress       ->', lv_sup.

    SKIP.
    WRITE: / '   Smaller payload, two documented costs: a receiver on'.
    WRITE: / '   clear = none keeps its old values for every missing'.
    WRITE: / '   field (trap 3, now triggered by the SENDER), and an'.
    WRITE: / '   XSDBOOLEAN component holding abap_false - a real,'.
    WRITE: / '   meaningful false - vanishes from the payload too.'.

    SKIP 2.

  ENDMETHOD.


  METHOD value_handling_truncation.

    WRITE: / '5. accept_data_loss TRUNCATES c AND n IN OPPOSITE DIRECTIONS'.
    SKIP.

    " Both incoming values are twice as long as their targets.
    DATA(lv_json) = `{"S":{"TXT":"ABCDEFGH","NUM":"98765432"}}`.

    " --- default: strict, and the exception is not what you expect ---
    DATA ls_strict TYPE ty_short.

    TRY.
        CALL TRANSFORMATION id
          SOURCE XML lv_json
          RESULT s = ls_strict
          OPTIONS clear = 'all'.

        WRITE: / '   default          -> no exception (unexpected)'.

      CATCH cx_transformation_error INTO DATA(lx_trans).
        " CX_SY_CONVERSION_DATA_LOSS cannot be caught as itself here -
        " it arrives packed inside CX_TRANSFORMATION_ERROR.
        DATA(lv_err) = lx_trans->get_text( ).
        WRITE: / '   default          -> CX_TRANSFORMATION_ERROR:', lv_err.
    ENDTRY.

    " --- tolerant: succeeds, and mangles the data ---------------------
    DATA ls_lossy TYPE ty_short.

    TRY.
        CALL TRANSFORMATION id
          SOURCE XML lv_json
          RESULT s = ls_lossy
          OPTIONS clear          = 'all'
                  value_handling = 'accept_data_loss'.

        WRITE: / '   accept_data_loss -> TXT', ls_lossy-txt,
                 '(from ABCDEFGH, cut on the RIGHT)'.
        WRITE: / '                       NUM', ls_lossy-num,
                 '(from 98765432, cut on the LEFT)'.

      CATCH cx_transformation_error INTO DATA(lx_lossy).
        DATA(lv_err2) = lx_lossy->get_text( ).
        WRITE: / '   accept_data_loss -> unexpected:', lv_err2.
    ENDTRY.

    SKIP.
    WRITE: / '   n is cut at the START because its rightmost digits are'.
    WRITE: / '   the significant ones. Applied to a too-short material'.
    WRITE: / '   number that yields a valid-looking DIFFERENT number,'.
    WRITE: / '   not an obviously broken one.'.
    WRITE: / '   Only CX_SY_TRANS_OPTION_ERROR (a bad option name or'.
    WRITE: / '   value) is raised directly and catchable as itself.'.

    SKIP 2.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_json_demo=>uppercase_names( ).
  lcl_json_demo=>no_json_booleans( ).
  lcl_json_demo=>clear_option_bleed( ).
  lcl_json_demo=>suppress_initial_components( ).
  lcl_json_demo=>value_handling_truncation( ).
