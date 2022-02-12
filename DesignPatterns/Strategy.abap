*&---------------------------------------------------------------------*
*& Report YDJ_OO_STRATEGY
*&---------------------------------------------------------------------*
*& Strategy Pattern allows one of a family of algorithms to be selected on-the-fly at runtime.
*&---------------------------------------------------------------------*
REPORT ydj_oo_strategy.


*----------------Start: Fly Behaviour Interface and Implementaions---------------------------
INTERFACE if_flybehaviour.
  METHODS : fly .
ENDINTERFACE.

*---------Start: Fly Implementaion 1 -> Fly with Wings
CLASS lcl_flywithwings DEFINITION.
  PUBLIC SECTION.
    INTERFACES: if_flybehaviour.
ENDCLASS.
CLASS lcl_flywithwings IMPLEMENTATION.
  METHOD if_flybehaviour~fly.
    WRITE : / 'Fly Behaviour -> Fly With Wings'.
  ENDMETHOD.
ENDCLASS.
*---------End: Fly Implementaion 1 -> Fly with Wings

*---------Start: Fly Implementaion 2 -> No Fly
CLASS lcl_nofly DEFINITION.
  PUBLIC SECTION.
    INTERFACES: if_flybehaviour.
ENDCLASS.

CLASS lcl_nofly IMPLEMENTATION.
  METHOD if_flybehaviour~fly.
    WRITE : / 'Fly Behaviour -> No Fly!!'.
  ENDMETHOD.
ENDCLASS.
*---------End: Fly Implementaion 2 -> No Fly
*----------------End: Fly Behaviour Interface and Implementaions-----------------------------


*----------------Start: Quack Behaviour Interface and Implementaions-------------------------
INTERFACE if_quackbehaviour.
  METHODS : quack.
ENDINTERFACE.

*---------Start: Quack Implementaion 1 -> Normal Quack
CLASS lcl_quack DEFINITION.
  PUBLIC SECTION.
    INTERFACES if_quackbehaviour.
ENDCLASS.

CLASS lcl_quack IMPLEMENTATION.
  METHOD if_quackbehaviour~quack.
    WRITE : / 'Quack Behaviour -> Quack!'.
  ENDMETHOD.
ENDCLASS.
*---------End: Quack Implementaion 1 -> Normal Quack

*---------Start: Quack Implementaion 2 -> Squeek
CLASS lcl_squeek DEFINITION.
  PUBLIC SECTION.
    INTERFACES if_quackbehaviour.
ENDCLASS.

CLASS lcl_squeek IMPLEMENTATION.
  METHOD if_quackbehaviour~quack.
    WRITE : / 'Quack Behaviour -> Squeek!!!'.
  ENDMETHOD.
ENDCLASS.
*---------End: Quack Implementaion 2 -> Squeek
*----------------End: Quack Behaviour Interface and Implementaions---------------------------


*----------------Start: Duck Abstact Class-------------------------
CLASS lcl_duck DEFINITION ABSTRACT.
  PUBLIC SECTION.
    DATA: flybehaviour   TYPE REF TO if_flybehaviour,
          quackbehaviour TYPE REF TO if_quackbehaviour.

    METHODS :
      fly,
      quack,
      display ABSTRACT.
ENDCLASS.

CLASS lcl_duck IMPLEMENTATION.

  METHOD fly.
    flybehaviour->fly( ).           "Generic Fly Method
  ENDMETHOD.

  METHOD quack.
    quackbehaviour->quack( ).       "Generic Quack Method
  ENDMETHOD.

ENDCLASS.
*----------------End: Duck Abstact Class-------------------------



*----------------Start: Normal Duck Class-------------------------
CLASS lcl_normalduck DEFINITION INHERITING FROM lcl_duck.
  PUBLIC SECTION.
    METHODS : display REDEFINITION,
      constructor.
ENDCLASS.

CLASS lcl_normalduck IMPLEMENTATION.
  METHOD constructor.
    super->constructor(  ).
    flybehaviour   = NEW lcl_flywithwings(  ).     "Fly with Wings Behaviour provided during object creation
    quackbehaviour = NEW lcl_quack( ).             "Quack Behaviour provided during object creation
  ENDMETHOD.

  METHOD display.
    WRITE : / 'Normal Duck'.
  ENDMETHOD.
ENDCLASS.
*----------------End: Normal Duck Class-------------------------



*----------------Start: Rubber Duck Class-------------------------
CLASS lcl_rubberduck DEFINITION INHERITING FROM lcl_duck.
  PUBLIC SECTION.
    METHODS : display REDEFINITION,
      constructor .
ENDCLASS.

CLASS lcl_rubberduck IMPLEMENTATION.
  METHOD constructor.
    super->constructor(  ).
    flybehaviour   = NEW lcl_nofly(  ).             "No Fly Behaviour provided during object creation
    quackbehaviour = NEW lcl_squeek( ).             "Squeek Behaviour provided during object creation
  ENDMETHOD.

  METHOD display.
    WRITE : / 'Rubber Duck'.
  ENDMETHOD.
ENDCLASS.
*----------------End: Rubber Duck Class-------------------------


*----------------Start: Dynamic Duck Class-------------------------
CLASS lcl_dynamicduck DEFINITION INHERITING FROM lcl_duck.
  PUBLIC SECTION.
    METHODS : display REDEFINITION,
      constructor IMPORTING io_fly_behaviour TYPE REF TO if_flybehaviour OPTIONAL io_quack_behaviour TYPE REF TO if_quackbehaviour OPTIONAL.
ENDCLASS.

CLASS lcl_dynamicduck IMPLEMENTATION.
  METHOD constructor.
    super->constructor(  ).
    flybehaviour   = io_fly_behaviour.               "Fly Behaviour Priovided during Object Creation
    quackbehaviour = io_quack_behaviour.             "Quack Behaviour Priovided during Object Creation
  ENDMETHOD.

  METHOD display.
    WRITE : / 'Dynamic Duck'.
  ENDMETHOD.
ENDCLASS.
*----------------End: Dynamic Duck Class-------------------------



START-OF-SELECTION.

  "Normal Duck
  DATA(lo_normal_duck) = NEW  lcl_normalduck( ).
  lo_normal_duck->display(  ).
  lo_normal_duck->fly( ).
  lo_normal_duck->quack( ).

  SKIP 2.

  "Rubber Duck
  DATA(lo_rubber_duck) = NEW  lcl_rubberduck( ).
  lo_rubber_duck->display(  ).
  lo_rubber_duck->fly( ).
  lo_rubber_duck->quack( ).

  SKIP 2.

  "Dynamic Duck
  DATA(lo_dynamic_duck) = NEW  lcl_dynamicduck( io_fly_behaviour = NEW lcl_flywithwings(  ) io_quack_behaviour = NEW lcl_squeek( ) ). "Behaviour provided during object creation
  lo_dynamic_duck->display(  ).
  lo_dynamic_duck->fly( ).
  lo_dynamic_duck->quack( ).
