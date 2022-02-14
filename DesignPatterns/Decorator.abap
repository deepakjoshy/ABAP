*&---------------------------------------------------------------------*
*& Report YDJ_OO_DECORATOR
*&---------------------------------------------------------------------*
*& Decorator Pattern allows behavior to be added to an individual object, dynamically, without affecting the behavior of other objects from the same class.
*&---------------------------------------------------------------------*
REPORT ydj_oo_decorator.

*-------------Start: Beverage Super Class ------------------------
CLASS lcl_beverage DEFINITION ABSTRACT.
  PUBLIC SECTION.
    DATA : lv_decription TYPE string.

    METHODS: get_description RETURNING VALUE(ev_description) TYPE string,
      cost ABSTRACT RETURNING VALUE(ev_cost) TYPE curr13_2.
ENDCLASS.

CLASS lcl_beverage IMPLEMENTATION.
  METHOD get_description.
    ev_description = lv_decription.
  ENDMETHOD.
ENDCLASS.
*-------------End: Beverage Super Class ------------------------


*-------------Start: Condiment Decorator Abstract Class ------------------------
CLASS lcl_condimentdecorator DEFINITION ABSTRACT INHERITING FROM lcl_beverage.
  PUBLIC SECTION.
    DATA : beverage TYPE REF TO lcl_beverage.
ENDCLASS.
*-------------End: Condiment Decorator Abstract Class --------------------------


*-------------Start: Basic Coffee Type -> Expressoo --------------------------------
CLASS lcl_expresso DEFINITION INHERITING FROM lcl_beverage.
  PUBLIC SECTION.
    METHODS: constructor,
      cost REDEFINITION.
ENDCLASS.
CLASS lcl_expresso IMPLEMENTATION.
  METHOD constructor.
    super->constructor( ).
    lv_decription = 'Expresso'.
  ENDMETHOD.
  METHOD cost.
    ev_cost = '2'.
  ENDMETHOD.
ENDCLASS.
*-------------End: Basic Coffee Type -> Expressoo -----------------------------------


*-------------Start: Basic Coffee Type -> House Blend Coffee ------------------------
CLASS lcl_houseblend DEFINITION INHERITING FROM lcl_beverage.
  PUBLIC SECTION.
    METHODS: constructor,
      cost REDEFINITION.
ENDCLASS.
CLASS lcl_houseblend IMPLEMENTATION.
  METHOD constructor.
    super->constructor( ).
    lv_decription = 'House Blend Coffee'.
  ENDMETHOD.
  METHOD cost.
    ev_cost = '3'.
  ENDMETHOD.
ENDCLASS.
*-------------End: Basic Coffee Type -> House Blend Coffee ------------------------



*-------------Start: Condiment -> Mocha ------------------------
CLASS lcl_mocha DEFINITION INHERITING FROM lcl_condimentdecorator.
  PUBLIC SECTION.
    METHODS: get_description REDEFINITION,
      cost REDEFINITION,
      constructor IMPORTING REFERENCE(io_beverage) TYPE REF TO lcl_beverage .
ENDCLASS.

CLASS lcl_mocha IMPLEMENTATION.

  METHOD constructor.
    super->constructor( ).
    me->beverage = io_beverage.
  ENDMETHOD.

  METHOD cost.
    ev_cost = beverage->cost( ) + 1.
  ENDMETHOD.

  METHOD get_description.
    ev_description = | {  beverage->get_description( ) } + Mocha |.
  ENDMETHOD.

ENDCLASS.
*-------------End: Condiment -> Mocha ----------------------------

*-------------Start: Condiment -> Mocha ------------------------
CLASS lcl_cream DEFINITION INHERITING FROM lcl_condimentdecorator.
  PUBLIC SECTION.
    METHODS: get_description REDEFINITION,
      cost REDEFINITION,
      constructor IMPORTING REFERENCE(io_beverage) TYPE REF TO lcl_beverage .
ENDCLASS.

CLASS lcl_cream IMPLEMENTATION.

  METHOD constructor.
    super->constructor( ).
    me->beverage = io_beverage.
  ENDMETHOD.

  METHOD cost.
    ev_cost = beverage->cost( ) + 3.
  ENDMETHOD.

  METHOD get_description.
    ev_description = | {  beverage->get_description( ) } + Cream |.
  ENDMETHOD.

ENDCLASS.
*-------------End: Condiment -> Mocha ----------------------------


START-OF-SELECTION.

  "Simple Expresso
  DATA : lo_beverage1 TYPE REF TO lcl_beverage.
  lo_beverage1 ?= NEW lcl_expresso( ).
  WRITE : / | Beverage 1 : { lo_beverage1->get_description( )  }|.
  WRITE : / | Cost : { lo_beverage1->cost( )  }|.

  SKIP 2.

  "Expresso + Mocha
  DATA : lo_beverage2 TYPE REF TO lcl_beverage.
  lo_beverage2 ?= NEW lcl_expresso( ).
  lo_beverage2 ?= NEW lcl_mocha( lo_beverage2 ).
  WRITE : / | Beverage 2 : { lo_beverage2->get_description( )  }|.
  WRITE : / | Cost : { lo_beverage2->cost( )  }|.

  SKIP 2.

  "House Blend + Mocha + Cream
  DATA : lo_beverage3 TYPE REF TO lcl_beverage.
  lo_beverage3 ?= NEW lcl_houseblend( ).
  lo_beverage3 ?= NEW lcl_mocha( lo_beverage3 ).
  lo_beverage3 ?= NEW lcl_cream( lo_beverage3 ).
  WRITE : / | Beverage 3 : { lo_beverage3->get_description( )  }|.
  WRITE : / | Cost : { lo_beverage3->cost( )  }|.
