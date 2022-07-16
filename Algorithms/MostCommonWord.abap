*&---------------------------------------------------------------------*
*& Report ydj_algo_most_common_word
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ydj_algo_most_common_word.


CLASS lcl_common_word DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS : common_word IMPORTING iv_input TYPE string RETURNING VALUE(rv_result) TYPE string.

ENDCLASS.



CLASS lcl_common_word IMPLEMENTATION.

  METHOD common_word.

    TYPES : BEGIN OF ty_words,
              word  TYPE string,
              count TYPE i,
            END OF ty_words.

    DATA : lv_inp_len   TYPE i,
           lt_words     TYPE HASHED TABLE OF ty_words WITH UNIQUE KEY word,
           wa_word      TYPE ty_words,
           wa_cur_max   TYPE ty_words,
           i            TYPE i VALUE 0,
           lv_cur_char  TYPE c,
           lv_cur_word  TYPE string,
           lv_prev_char TYPE c,
           j            TYPE i,
           abcd         TYPE string.

    abcd = to_lower( sy-abcde ).

    lv_inp_len = strlen( iv_input ).

    WHILE i LT lv_inp_len.

      lv_cur_char = iv_input+i(1).

      IF lv_cur_char CO sy-abcde OR lv_cur_char CO abcd.
        lv_cur_word = |{ lv_cur_word }{ lv_cur_char }|.
      ELSE.
        IF line_exists( lt_words[ word = lv_cur_word ] ).
          wa_word = lt_words[ word = lv_cur_word ].
          wa_word-count += 1.
          MODIFY TABLE lt_words FROM wa_word.
        ELSE.
          wa_word-word = lv_cur_word.
          wa_word-count = 1.
          INSERT wa_word INTO TABLE lt_words.
        ENDIF.

        wa_cur_max = COND #( WHEN wa_cur_max-count LT wa_word-count THEN wa_word ELSE wa_cur_max ).
        CLEAR : lv_cur_word.
      ENDIF.

      CLEAR : wa_word.
      i += 1.
    ENDWHILE.

    rv_result = wa_cur_max-word.

  ENDMETHOD.

ENDCLASS.



START-OF-SELECTION.

  cl_demo_output=>display(  lcl_common_word=>common_word( 'Hi Hi Hi Hi Hello Hello Hello Hello Hello Today Today' )  ).
