*&---------------------------------------------------------------------*
*& Report ydj_algo_closest_elments
*&---------------------------------------------------------------------*
*& Given a sorted array[] and a value X, find the k closest elements to X in array[].
*
* An Optimized Solution is to find k elements in O(Logn + k) time.
* The idea is to use Binary Search to find the crossover point. Once we find index of crossover point, we can print k closest elements in O(k) time.
*&---------------------------------------------------------------------*
REPORT ydj_algo_closest_elements.


CLASS lcl_closest_elements DEFINITION.

  PUBLIC SECTION.
    TYPES : ty_input_array TYPE STANDARD TABLE OF i WITH DEFAULT KEY.

    CLASS-METHODS : find_closest_elements IMPORTING it_array TYPE ty_input_array iv_value TYPE i iv_k TYPE i RETURNING VALUE(rt_result) TYPE ty_input_array.


  PRIVATE SECTION.
    CLASS-METHODS : find_crossover_element IMPORTING it_array TYPE ty_input_array iv_value TYPE i RETURNING VALUE(rv_crossover_element) TYPE i.

ENDCLASS.


CLASS lcl_closest_elements IMPLEMENTATION.

  METHOD find_closest_elements.


    CHECK it_array IS NOT INITIAL.
    DATA(lv_crossover) = find_crossover_element( iv_value = iv_value it_array = it_array ).

    DATA : i                  TYPE i,
           j                  TYPE i,
           k                  TYPE i VALUE 1,
           temp               TYPE i,
           lv_crossover_value TYPE i.

    lv_crossover_value = it_array[ lv_crossover ].
    i = COND #( WHEN iv_value = lv_crossover_value THEN  lv_crossover - 1 ELSE lv_crossover ).
    j = lv_crossover + 1.


    WHILE i > 0 AND j LE lines( it_array ) AND k LE iv_k.

      IF ( lv_crossover_value - it_array[ i ] ) LT ( it_array[ j ] - lv_crossover_value ).
        APPEND it_array[ i ] TO rt_result.
        i -= 1.
      ELSE.
        APPEND it_array[ j ] TO rt_result.
        j += 1.
      ENDIF.
      k += 1.
    ENDWHILE.

    WHILE i > 0 AND k LE iv_k.
      APPEND it_array[ i ] TO rt_result.
      i -= 1.
      k += 1.
    ENDWHILE..

    WHILE j LE lines( it_array ) AND k LE iv_k.
      APPEND it_array[ j ] TO rt_result.
      j += 1.
      k += 1.
    ENDWHILE.

    SORT rt_result ASCENDING.

  ENDMETHOD.



  METHOD find_crossover_element.

    DATA : i   TYPE i VALUE 0,
           mid TYPE i,
           j   TYPE i.

    DESCRIBE TABLE it_array LINES j.

    mid = floor( ( i + j ) / 2 ).
    WHILE i < j.

      IF it_array[ mid ] EQ iv_value.
        EXIT.
      ELSEIF iv_value LT it_array[ mid ].
        j = mid - 1.
        mid = floor( ( i + j ) / 2 ).
      ELSE.
        i = mid + 1.
        mid = floor( ( i + j ) / 2 ).
      ENDIF.
    ENDWHILE.

    rv_crossover_element = mid.

  ENDMETHOD.


ENDCLASS.


START-OF-SELECTION.


  DATA : lt_array TYPE STANDARD TABLE OF i WITH DEFAULT KEY,
         lv_value TYPE i,
         lv_k     TYPE i.

  lt_array = VALUE #( FOR j = 1 UNTIL j > 20 ( j ) ).
  lv_value = 20.
  lv_k = 5.

  cl_demo_output=>display( lcl_closest_elements=>find_closest_elements( iv_k = lv_k iv_value = lv_value it_array = lt_array ) ).
