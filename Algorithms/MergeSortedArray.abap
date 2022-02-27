*&---------------------------------------------------------------------*
*& Report ydj_algo_merge_sorted_array
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ydj_algo_merge_sorted_array.



START-OF-SELECTION.

  DATA : lt_array1 TYPE SORTED TABLE OF i WITH UNIQUE DEFAULT KEY,
         lt_array2 TYPE SORTED TABLE OF i WITH UNIQUE DEFAULT KEY,
         lt_result TYPE STANDARD TABLE OF i WITH EMPTY KEY,
         i         TYPE i VALUE 1,
         j         TYPE i VALUE 1.


  lt_array1 = VALUE #(  ( 1 )  ( 3 )  ( 5 )  ( 7 ) ).
  lt_array2 = VALUE #(  ( 2 )  ( 4 )  ( 6 )  ( 8 ) ).

  DESCRIBE TABLE lt_array1 LINES DATA(lv_length1).
  DESCRIBE TABLE lt_array2 LINES DATA(lv_length2).
  DATA(lv_length) = lv_length1 + lv_length2.


  DO lv_length1 + lv_length2  TIMES.

    IF i LE lv_length1 AND j LE lv_length2.
      IF lt_array1[ i ] LE lt_array1[ j ].
        APPEND lt_array1[ i ] TO lt_result.
        i += 1.
      ELSE.
        APPEND lt_array2[ j ] TO lt_result.
        j += 1.
      ENDIF.
    ENDIF.


  ENDDO.

  WHILE i LE lv_length1.
    APPEND lt_array1[ i ] TO lt_result.
    i += 1.
  ENDWHILE.
  WHILE j LE lv_length2.
    APPEND lt_array2[ j ] TO lt_result.
    j += 1.
  ENDWHILE.


  cl_demo_output=>display( lt_result ).
