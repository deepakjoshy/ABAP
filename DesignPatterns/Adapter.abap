*&---------------------------------------------------------------------*
*& Report YDJ_OO_ADAPTER
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ydj_oo_adapter.


INTERFACE if_lightningphone.
  METHODS: recharge,
    uselightning.
ENDINTERFACE.

INTERFACE if_microusbphone.
  METHODS: recharge,
    usemicrousb.
ENDINTERFACE.


CLASS cl_iphone DEFINITION.
  PUBLIC SECTION.
    INTERFACES if_lightningphone.
  PRIVATE SECTION.
    DATA : connector TYPE boolean.
ENDCLASS.

CLASS cl_iphone IMPLEMENTATION.

  METHOD: if_lightningphone~uselightning.
    connector = abap_true.
    WRITE : / 'Lightning Connected'.
  ENDMETHOD.

  METHOD: if_lightningphone~recharge.
    IF connector = abap_true.
      WRITE : / 'Recharge Started.'.
      WRITE : / 'Recharge Finished.'.
    ELSE.
      WRITE : / 'Connect Lightning First'.
    ENDIF.
  ENDMETHOD.
ENDCLASS.



CLASS cl_androidphone DEFINITION.
  PUBLIC SECTION.
    INTERFACES if_microusbphone.
  PRIVATE SECTION.
    DATA : connector TYPE boolean.
ENDCLASS.

CLASS cl_androidphone IMPLEMENTATION.
  METHOD : if_microusbphone~usemicrousb.
    connector = abap_true.
    WRITE : / 'Micro USB Connected'.
  ENDMETHOD.

  METHOD: if_microusbphone~recharge.
    IF connector EQ abap_true.
      WRITE : / 'Recharge Started.'.
      WRITE : / 'Recharge Finished.'.
    ELSE.
      WRITE : / 'Connect Micro USB'.
    ENDIF.
  ENDMETHOD.

ENDCLASS.





CLASS cl_lightningtomicrousbadapter DEFINITION.

  PUBLIC SECTION.
    METHODS: CONSTRUCTOR IMPORTING iv_lightningphone TYPE REF TO if_lightningphone,
             usemicrousb,
             recharge.

  PRIVATE SECTION.
    DATA : go_lightningphone TYPE REF TO if_lightningphone.

ENDCLASS.

CLASS cl_lightningtomicrousbadapter IMPLEMENTATION.

  METHOD CONSTRUCTOR.
    me->go_lightningphone = iv_lightningphone.
  ENDMETHOD.

  METHOD usemicrousb.
    WRITE :/ 'Micro USB Connected'.
    go_lightningphone->uselightning( ).
  ENDMETHOD.

  METHOD recharge.
    go_lightningphone->recharge( ).
  ENDMETHOD.

ENDCLASS.




START-OF-SELECTION.


  WRITE: / 'Recharging iPhone with Lightning'.
  DATA(lo_iphone) = NEW cl_iphone( ).
  lo_iphone->if_lightningphone~uselightning( ).
  lo_iphone->if_lightningphone~recharge( ).


  SKIP 2.


  WRITE: / 'Recharging Android Phone with Micro USB'.
  DATA(lo_android) = NEW cl_androidphone( ).
  lo_android->if_microusbphone~usemicrousb( ).
  lo_android->if_microusbphone~recharge( ).


  SKIP 2.


  WRITE: / 'Recharging iPhone with Micro USB'.
  DATA(lo_iphone_new) = NEW cl_iphone( ).
  DATA(lo_lightning_adapter) = NEW cl_lightningtomicrousbadapter( lo_iphone_new ).
  lo_lightning_adapter->usemicrousb( ).
  lo_lightning_adapter->recharge( ).
