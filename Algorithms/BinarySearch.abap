*&---------------------------------------------------------------------*
*& Report ydj_algo_binary_search
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*

"Complete the Alogrithm for Binary Search.
"Input -> Integer Table, Element to be searched (Integer)
"Output -> Index of the Element if Element exists, else return -1

REPORT ydj_algo_binary_search.

CLASS lcl_binary_search DEFINITION.

  PUBLIC SECTION.
    TYPES : ty_input TYPE TABLE OF i.

    CLASS-METHODS: binary_search IMPORTING it_table TYPE ty_input iv_key TYPE i RETURNING VALUE(rv_index) TYPE i.

ENDCLASS.


CLASS lcl_binary_search IMPLEMENTATION.

  METHOD binary_search.


    DATA(lv_length) = lines( it_table ).

    DATA: mid  TYPE i,
          high TYPE i,
          low  TYPE i.

    high = lv_length.
    low = 1.
    mid = high / 2.
    WHILE low LE high.

      DATA(value) = it_table[ mid ].

      IF value = iv_key.
        rv_index = mid.
        RETURN.
      ELSEIF value LT iv_key.
        low = mid + 1.
      ELSE.
        high = mid - 1.
      ENDIF.
      mid = ( low + high ) / 2.
    ENDWHILE.



  ENDMETHOD.

ENDCLASS.



START-OF-SELECTION.

  DATA : lt_input TYPE TABLE OF i,
         lv_key   TYPE i.

  lt_input = VALUE #( ( 10 ) ( 20 ) ( 40 ) ( 50 ) ( 60 )  ( 70 )  ( 90 ) ).
  lv_key = 10.
  WRITE : / lv_key , '---' , lcl_binary_search=>binary_search(  it_table = lt_input iv_key = lv_key ).

   lv_key = 15.
  WRITE : / lv_key , '---' , lcl_binary_search=>binary_search(  it_table = lt_input iv_key = lv_key ).

   lv_key = 20.
  WRITE : / lv_key , '---' , lcl_binary_search=>binary_search(  it_table = lt_input iv_key = lv_key ).

   lv_key = 30.
  WRITE : / lv_key , '---' , lcl_binary_search=>binary_search(  it_table = lt_input iv_key = lv_key ).

   lv_key = 40.
  WRITE : / lv_key , '---' , lcl_binary_search=>binary_search(  it_table = lt_input iv_key = lv_key ).

   lv_key = 50.
  WRITE : / lv_key , '---' , lcl_binary_search=>binary_search(  it_table = lt_input iv_key = lv_key ).

   lv_key = 60.
  WRITE : / lv_key , '---' , lcl_binary_search=>binary_search(  it_table = lt_input iv_key = lv_key ).

   lv_key = 70.
  WRITE : / lv_key , '---' , lcl_binary_search=>binary_search(  it_table = lt_input iv_key = lv_key ).

   lv_key = 80.
  WRITE : / lv_key , '---' , lcl_binary_search=>binary_search(  it_table = lt_input iv_key = lv_key ).

   lv_key = 90.
  WRITE : / lv_key , '---' , lcl_binary_search=>binary_search(  it_table = lt_input iv_key = lv_key ).

   lv_key = 100.
  WRITE : / lv_key , '---' , lcl_binary_search=>binary_search(  it_table = lt_input iv_key = lv_key ).
