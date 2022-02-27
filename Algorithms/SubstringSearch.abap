*&---------------------------------------------------------------------*
*& Report ydj_algo_substring_search
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ydj_algo_substring_search.


PARAMETERS : p_string TYPE string,
             p_sub    TYPE string.


CHECK p_sub IS NOT INITIAL.
CHECK p_string IS NOT INITIAL.


START-OF-SELECTION.

  DATA : lv_flag TYPE boolean,
         i       TYPE i VALUE 0,
         j       TYPE i.

  DATA(sub_length) = strlen( p_sub ).

  WHILE i LE ( strlen( p_string ) - strlen( p_sub ) ).

    IF  p_string+i(sub_length) EQ p_sub.
      WRITE : / | Substring Found at { i }|.
      RETURN.
    ENDIF.
    i += 1.

  ENDWHILE.

  WRITE : / 'Substring not Found'.
