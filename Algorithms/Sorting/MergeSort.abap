*&---------------------------------- -----------------------------------*
*& Report ydj_sort_merge
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ydj_sort_merge.

CLASS lcl_sort DEFINITION .

  PUBLIC SECTION.
    TYPES : ty_table TYPE STANDARD TABLE OF i WITH EMPTY KEY.

    CLASS-METHODS: mergesort IMPORTING it_table TYPE ty_table RETURNING VALUE(rt_table) TYPE ty_table.

  PRIVATE SECTION.
    CLASS-METHODS:  merge IMPORTING it_left TYPE ty_table it_right TYPE ty_table RETURNING VALUE(rt_table) TYPE ty_table.

ENDCLASS.


CLASS lcl_sort IMPLEMENTATION.

  METHOD mergesort.

    DATA(lv_lines) = lines(  it_table ).
    DATA(lv_half) = floor(  lv_lines / 2 ).

    DATA : lt_left  TYPE ty_table,
           lt_right TYPE ty_table.

    rt_table = it_table.
    CHECK lv_lines GT 1.

    IF lv_lines GT 1.
      APPEND LINES OF it_table FROM 1 TO lv_half TO lt_left.
      APPEND LINES OF it_table FROM ( lv_half + 1 ) TO lt_right.
    ENDIF.

    lt_left = mergesort( lt_left ).
    lt_right = mergesort( lt_right ).

    rt_table = merge( it_left = lt_left it_right = lt_right ).

  ENDMETHOD.



  METHOD merge.

    DATA(lv_left_count) = lines( it_left ).
    DATA(lv_right_count) = lines( it_right ).
    DATA lt_table TYPE lcl_sort=>ty_table.

    DATA : i TYPE i VALUE 1,
           j TYPE i VALUE 1.

    WHILE i LE lv_left_count AND j LE lv_right_count.

      IF it_left[ i ] > it_right[ j ].
        APPEND it_right[ j ] TO lt_table.
        j += 1.
      ELSE.
        APPEND it_left[ i ] TO lt_table.
        i += 1.
      ENDIF.

    ENDWHILE.

    LOOP AT it_left INTO DATA(lv_temp) FROM i.
      APPEND lv_temp TO lt_table.
    ENDLOOP.

    LOOP AT it_right INTO lv_temp FROM j.
      APPEND lv_temp TO lt_table.
    ENDLOOP.

    rt_table = lt_table.

  ENDMETHOD.

ENDCLASS.




START-OF-SELECTION.

*  DATA(lo_sort) = NEW lcl_sort( ).

  DATA(lt_table) = VALUE lcl_sort=>ty_table(  ( 4 ) ( 2 )  ( 1 )  ( 6 ) ( 5 ) ).

  DATA(lt_sorted_table) = lcl_sort=>mergesort( lt_table ).

  cl_demo_output=>display( lt_sorted_table ).
