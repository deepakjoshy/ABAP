*&---------------------------------------------------------------------*
*& Report YDJ_NUMBER_RANGE_DEMO
*&---------------------------------------------------------------------*
*& Drawing numbers from an SNRO number range object.
*&
*& Two things this demo makes explicit, because both are easy to get wrong:
*&   1. With QUANTITY > 1 the FM returns the LAST number of the reserved
*&      block. The block is  number - quantity + 1 .. number.
*&   2. RETURNCODE is an exporting parameter, not an exception. '1' means
*&      the number came from the critical area (interval nearly exhausted).
*&
*& Prerequisite: a number range object in SNRO (here: YDJ_DEMO) with an
*& internal interval '01'.
*&---------------------------------------------------------------------*
REPORT ydj_number_range_demo.

CLASS lcx_number_range DEFINITION INHERITING FROM cx_static_check.
  PUBLIC SECTION.
    DATA: mv_subrc TYPE sy-subrc READ-ONLY.
    METHODS constructor IMPORTING iv_subrc TYPE sy-subrc.
ENDCLASS.

CLASS lcx_number_range IMPLEMENTATION.
  METHOD constructor.
    super->constructor( ).
    mv_subrc = iv_subrc.
  ENDMETHOD.
ENDCLASS.


CLASS lcl_number_range DEFINITION.

  PUBLIC SECTION.
    TYPES: ty_numbers TYPE STANDARD TABLE OF nriv-nrlevel WITH EMPTY KEY.

    CLASS-METHODS:
      "! Reserves a block of numbers in one round trip.
      "! @parameter iv_object        | number range object (SNRO)
      "! @parameter iv_interval      | interval number, e.g. '01'
      "! @parameter iv_quantity      | how many numbers to reserve
      "! @parameter iv_ignore_buffer | abap_true = read NRIV directly, no buffer
      "! @parameter rt_numbers       | the reserved block, expanded
      get_block IMPORTING iv_object         TYPE inri-object
                          iv_interval       TYPE inri-nrrangenr DEFAULT '01'
                          iv_quantity       TYPE inri-quantity  DEFAULT 1
                          iv_ignore_buffer  TYPE abap_bool      DEFAULT abap_false
                RETURNING VALUE(rt_numbers) TYPE ty_numbers
                RAISING   lcx_number_range,

      execute.

ENDCLASS.


CLASS lcl_number_range IMPLEMENTATION.

  METHOD get_block.

    DATA: lv_last       TYPE nriv-nrlevel,
          lv_returncode TYPE inri-returncode.

    CALL FUNCTION 'NUMBER_GET_NEXT'
      EXPORTING
        nr_range_nr             = iv_interval
        object                  = iv_object
        quantity                = iv_quantity
        ignore_buffer           = iv_ignore_buffer
      IMPORTING
        number                  = lv_last          " LAST number of the block
        returncode              = lv_returncode
      EXCEPTIONS
        interval_not_found      = 1
        number_range_not_intern = 2
        object_not_found        = 3
        quantity_is_0           = 4
        quantity_is_not_1       = 5
        interval_overflow       = 6
        buffer_overflow         = 7
        OTHERS                  = 8.

    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW lcx_number_range( sy-subrc ).
    ENDIF.

    " '1' = number taken from the critical area. Not an error - the number is
    " valid - but the interval is close to exhausted (threshold is the warning
    " percentage in SNRO, 10% by default). Hook monitoring here rather than
    " waiting for INTERVAL_OVERFLOW to hit in production.
    IF lv_returncode = '1'.
      MESSAGE |Number range { iv_object }/{ iv_interval } is in its critical area.| TYPE 'I'.
    ENDIF.

    " Expand the reserved block: last - quantity + 1 .. last
    DATA(lv_first) = CONV decfloat34( lv_last ) - CONV decfloat34( iv_quantity ) + 1.

    DO CONV i( iv_quantity ) TIMES.
      APPEND CONV nriv-nrlevel( lv_first + sy-index - 1 ) TO rt_numbers.
    ENDDO.

  ENDMETHOD.


  METHOD execute.

    TRY.

        " Single number, buffered (the normal case).
        DATA(lt_one) = get_block( iv_object = 'YDJ_DEMO' ).
        WRITE: / 'Single number  :', lt_one[ 1 ].

        " Block of 5 in ONE round trip - much cheaper than 5 calls, and the
        " only safe way to pre-allocate keys for a mass insert.
        DATA(lt_block) = get_block( iv_object   = 'YDJ_DEMO'
                                    iv_quantity = 5 ).
        SKIP 1.
        WRITE: / 'Reserved block :'.
        LOOP AT lt_block INTO DATA(lv_number).
          WRITE: / '   ', lv_number.
        ENDLOOP.

        " Unbuffered draw: hits NRIV with a lock. Strictly sequential, slow -
        " never do this inside a loop.
        DATA(lt_exact) = get_block( iv_object        = 'YDJ_DEMO'
                                    iv_ignore_buffer = abap_true ).
        SKIP 1.
        WRITE: / 'Unbuffered     :', lt_exact[ 1 ].

      CATCH lcx_number_range INTO DATA(lx_error).
        WRITE: / 'NUMBER_GET_NEXT failed, sy-subrc =', lx_error->mv_subrc.
    ENDTRY.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.
  lcl_number_range=>execute( ).
