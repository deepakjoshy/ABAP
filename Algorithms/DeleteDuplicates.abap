*&---------------------------------------------------------------------
*& Report ydj_algo_delete_duplicates
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ydj_algo_delete_duplicates.


START-OF-SELECTION.

  DATA : lt_input TYPE STANDARD TABLE OF i WITH EMPTY KEY,
         i        TYPE i,
         j        TYPE i,
         prev     TYPE i.


  lt_input = VALUE #( ( 2 ) ( 4 ) ( 5 ) ( 6 ) ( 6 ) ( 7 ) ( 7 ) ( 8 ) ).

  LOOP AT lt_input INTO DATA(wa_input).

    i = sy-tabix.

    IF  lt_input[ i ] EQ prev.
      DELETE lt_input INDEX i.
      CONTINUE.
    ENDIF.

    prev = wa_input.

  ENDLOOP.

  cl_demo_output=>display( lt_input ).
