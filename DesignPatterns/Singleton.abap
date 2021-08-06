REPORT ydj_oo_singleton.

CLASS lcl_singleton DEFINITION CREATE PRIVATE.
  PUBLIC SECTION.
    CLASS-METHODS: get_instance RETURNING VALUE(ro_instance) TYPE REF TO lcl_singleton.

    METHODS: set_value IMPORTING iv_value TYPE char10,
      get_value RETURNING VALUE(ev_value) TYPE char10.

  PRIVATE SECTION.
    CLASS-DATA: go_instance TYPE REF TO lcl_singleton.
    DATA : lv_data TYPE char10.
ENDCLASS.


CLASS lcl_singleton IMPLEMENTATION.

  METHOD get_instance.
    IF go_instance IS INITIAL.
      CREATE OBJECT go_instance.
    ENDIF.
    ro_instance = go_instance.
  ENDMETHOD.

  METHOD get_value.
    ev_value = me->lv_data.
  ENDMETHOD.

  METHOD set_value.
    me->lv_data = iv_value.
  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  DATA : lo_object_1 TYPE REF TO lcl_singleton.
  WRITE : / 'Object: Object 1'.
  lo_object_1 = lcl_singleton=>get_instance( ).
  lo_object_1->set_value( 'Value 1' ).
  DATA(lv_result1) = lo_object_1->get_value( ).
  WRITE : / 'Result: ' && lv_result1.

  SKIP 2.

  DATA : lo_object_2 TYPE REF TO lcl_singleton.
  WRITE : / 'Object: Object 2'.
  lo_object_2 = lcl_singleton=>get_instance( ).
  DATA(lv_result2) = lo_object_2->get_value( ).
  WRITE : / 'Result: ' && lv_result2.
