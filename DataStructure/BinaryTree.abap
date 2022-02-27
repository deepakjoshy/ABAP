*&---------------------------------------------------------------------*
*& Report ydj_ds_binary_tree
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ydj_ds_binary_tree.


CLASS lcl_binary_tree DEFINITION.

  PUBLIC SECTION.
    TYPES : BEGIN OF ty_node,
              value      TYPE i,
              left_node  TYPE REF TO data,
              right_node TYPE REF TO data,
            END OF ty_node.

    DATA : node TYPE REF TO ty_node.

    METHODS: insert_element IMPORTING VALUE(iv_value) TYPE i,
      insert_node IMPORTING VALUE(iv_value) TYPE i iv_node TYPE REF TO data,
      create_node IMPORTING VALUE(iv_value) TYPE i RETURNING VALUE(ro_node) TYPE REF TO ty_node,
      display IMPORTING iv_node TYPE REF TO data OPTIONAL.

  PRIVATE SECTION.

ENDCLASS.


CLASS lcl_binary_tree IMPLEMENTATION.

  METHOD insert_element.

    IF node IS NOT BOUND.
      node = create_node( iv_value = iv_value ).
    ELSE.
      me->insert_node( iv_value = iv_value iv_node = node ).
    ENDIF.

  ENDMETHOD.



  METHOD insert_node.

    DATA lo_node TYPE REF TO ty_node.
    lo_node ?= iv_node.


    IF iv_value LT lo_node->value.

      IF lo_node->left_node IS NOT BOUND.
        lo_node->left_node ?= me->create_node( iv_value = iv_value ).
      ELSE.
        me->insert_node( iv_node =  lo_node->left_node  iv_value = iv_value ).
      ENDIF.

    ELSEIF iv_value GT lo_node->value.

      IF lo_node->right_node IS NOT BOUND.
        lo_node->right_node ?= me->create_node( iv_value = iv_value ).
      ELSE.
        me->insert_node( iv_node = lo_node->right_node iv_value = iv_value ).
      ENDIF.

    ENDIF.

  ENDMETHOD.


  METHOD create_node.

    DATA : lo_node TYPE REF TO ty_node.
    CREATE DATA lo_node.
    lo_node->value = iv_value.
    ro_node = lo_node.

  ENDMETHOD.


  METHOD display.

    DATA : lo_node TYPE REF TO ty_node.

    lo_node ?= iv_node.
    IF iv_node IS NOT SUPPLIED.
      lo_node ?= node.
    ENDIF.

    WRITE : lo_node->value.

    IF lo_node->left_node IS BOUND.
      display( lo_node->left_node ).
    ENDIF.


    IF lo_node->right_node IS BOUND.
      display( lo_node->right_node ).
    ENDIF.


  ENDMETHOD.

ENDCLASS.





START-OF-SELECTION.

  DATA : lo_tree TYPE REF TO lcl_binary_tree.
  CREATE OBJECT lo_tree.

  TRY.
      lo_tree->insert_element( 5 ).
      lo_tree->insert_element( 2 ).
      lo_tree->insert_element( 1 ).
      lo_tree->insert_element( 8 ).
      lo_tree->insert_element( 9 ).
      lo_tree->insert_element( 7 ).

    CATCH cx_root.

  ENDTRY.

  lo_tree->display(  ).
