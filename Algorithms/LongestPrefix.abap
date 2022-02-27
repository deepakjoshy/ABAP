*&---------------------------------------------------------------------*
*& Report ydj_algo_longest_prefix
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ydj_algo_longest_prefix.

START-OF-SELECTION.

  DATA : lt_input   TYPE STANDARD TABLE OF string WITH DEFAULT KEY,
         min_length TYPE i,
         i          TYPE i VALUE 1,
         cur_substr TYPE string,
         result     TYPE string,
         flag       TYPE boolean,
         first      TYPE string.

  lt_input = VALUE #( ( `racehorse` ) ( `race` ) ( `racecar` ) ( `raceboat` )  ).

  SORT lt_input ASCENDING.
  min_length = strlen( lt_input[ 1 ] ).
  first = lt_input[ 1 ].


  WHILE i LE min_length AND flag EQ abap_false.

    cur_substr =  first+0(i).
    LOOP AT lt_input INTO DATA(wa_input).

      IF wa_input+0(i) NE cur_substr.
        flag = abap_true.
        EXIT.
      ENDIF.

    ENDLOOP.
    IF  flag IS INITIAL.
      result =  wa_input+0(i).
    ENDIF.

    i += 1.
  ENDWHILE.


  cl_demo_output=>display( result ).
