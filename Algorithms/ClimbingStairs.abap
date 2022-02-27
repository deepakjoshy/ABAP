*&---------------------------------------------------------------------*
*& Report ydj_algo_climbing_stairs
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ydj_algo_climbing_stairs.

PARAMETERS : p_steps TYPE i.


START-OF-SELECTION.


  DATA : a    TYPE i VALUE 1,
         b    TYPE i VALUE 2,
         next TYPE i,
         i    VALUE 3.

  WHILE i LE p_steps.

    next = b + a.
    a = b.
    b = next.

    i += 1.
  ENDWHILE.

  next = COND #(  WHEN p_steps EQ 1 THEN a ELSE b ).

  WRITE : / next.
