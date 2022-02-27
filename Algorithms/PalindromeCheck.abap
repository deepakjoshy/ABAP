*&---------------------------------------------------------------------*
*& Report ydj_algo_palindrome_check
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ydj_algo_palindrome_check.

PARAMETERS : p_string TYPE string.



START-OF-SELECTION.

  DATA: lv_length TYPE i,
        i         TYPE i VALUE 0,
        j         TYPE i.

  j = lv_length = strlen( p_string ).
  j -= 1.

  WHILE i < floor( lv_length / 2 ).

    IF p_string+i(1) NE p_string+j(1).
      WRITE : / 'Not a Palindrome'.
      RETURN.
    ENDIF.

    j -= 1.
    i += 1.

  ENDWHILE.

  WRITE : / 'Palindrome'.
  RETURN.
