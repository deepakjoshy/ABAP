*&---------------------------------------------------------------------*
*& Report ydj_sort_quick
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ydj_sort_quick.

CLASS lcl_quick_sort DEFINITION.

  PUBLIC SECTION.
    TYPES : ty_array TYPE STANDARD TABLE OF i WITH EMPTY KEY.

    CLASS-METHODS : sort IMPORTING it_input TYPE ty_array RETURNING VALUE(rt_output) TYPE ty_array.

  PRIVATE SECTION.
    CLASS-METHODS :
      quick_sort IMPORTING iv_start TYPE i iv_end TYPE i CHANGING it_input TYPE ty_array,
      partition IMPORTING iv_start TYPE i iv_end TYPE i CHANGING it_input TYPE ty_array RETURNING VALUE(rv_partition) TYPE i.

ENDCLASS.

CLASS lcl_quick_sort IMPLEMENTATION.

  METHOD sort.

    DATA: lv_max   TYPE i.

    rt_output[] = it_input[].
    DESCRIBE TABLE it_input LINES lv_max.
    quick_sort( EXPORTING  iv_start = 1  iv_end   = lv_max CHANGING it_input = rt_output  ).

  ENDMETHOD.


  METHOD quick_sort.

    DATA : lv_partition TYPE i,
           lt_data      TYPE ty_array.

    IF iv_start LT iv_end.

      lv_partition = partition( EXPORTING iv_start = iv_start iv_end = iv_end CHANGING it_input = it_input ).

      quick_sort( EXPORTING iv_start = iv_start         iv_end   = lv_partition - 1  CHANGING it_input = it_input  ).
      quick_sort( EXPORTING iv_start = lv_partition + 1 iv_end   = iv_end            CHANGING  it_input = it_input  ).

    ENDIF.

  ENDMETHOD.


  METHOD partition.

    DATA : lv_pivot TYPE i,
           i        TYPE i,
           j        TYPE i,
           temp     TYPE i.

    lv_pivot = it_input[ iv_end ].
    i = iv_start - 1.
    j = iv_start.

    WHILE j LE iv_end.

      IF it_input[ j ] LT lv_pivot.  "If current element is less than pivot.

        i += 1.
        temp = it_input[ i ].
        it_input[ i ] = it_input[ j ].
        it_input[ j ] = temp.

      ENDIF.

      j += 1.
    ENDWHILE.

    i += 1.
    temp = it_input[ i ].
    it_input[ i ] = it_input[ iv_end ].
    it_input[ iv_end ] = temp.

    rv_partition = i.

  ENDMETHOD.

ENDCLASS.



START-OF-SELECTION.

  DATA : lt_input TYPE lcl_quick_sort=>ty_array.
  lt_input = VALUE #( ( 3 ) ( 1 ) ( 2 ) ( 5 ) ( 4 ) ( 3 ) ( 1 ) ( 2 ) ( 5 ) ( 4 ) ).

  lt_input = lcl_quick_sort=>sort(  lt_input ).
  cl_demo_output=>display( lt_input ).
