*&---------------------------------------------------------------------*
*& Report ydj_algo_valid_parentheses
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ydj_algo_valid_parentheses.


PARAMETERS : p_input TYPE string.

START-OF-SELECTION.


  DATA: lv_length TYPE i,
        lt_stack  TYPE STANDARD TABLE OF c WITH EMPTY KEY,
        i         TYPE i VALUE 0,
        lv_c      TYPE c.


  lv_length = strlen( p_input ).

  DO lv_length TIMES.

    lv_c = p_input+i(1).

    CASE lv_c.
      WHEN '('.
        APPEND ')' TO lt_stack.
      WHEN '{'.
        APPEND '}' TO lt_stack.
      WHEN '['.
        APPEND ']' TO lt_stack.
      WHEN OTHERS.
        IF lt_stack IS INITIAL.
          WRITE : / 'Invalid Data'.
          RETURN.
        ENDIF.
        DESCRIBE TABLE lt_stack LINES DATA(lv_counter).
        IF  lt_stack[ lv_counter ] EQ lv_c.
          DELETE lt_stack INDEX lv_counter.
        ELSE.

        ENDIF.
    ENDCASE.

    i += 1.
  ENDDO.

  IF lt_stack IS INITIAL.
    WRITE : / 'Valid Data'.
  ELSE.
    WRITE : / 'Invalid Data'.
  ENDIF..
