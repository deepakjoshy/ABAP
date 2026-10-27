*&---------------------------------------------------------------------*
*& Report YDJ_FLOW_CONTROL_DEMO
*&---------------------------------------------------------------------*
*& The flow-control statements whose meaning is decided by their
*& surroundings rather than by what they say.
*&
*& This report performs NO database access and changes nothing. Every
*& part below is in-memory control flow, so the output IS the proof.
*&
*&   1. ONE KEYWORD, TWO MEANINGS -> the same EXIT statement breaks a
*&                       loop inside DO ... ENDDO and returns from the
*&                       method a few lines later, outside it. Part 1
*&                       prints what it reached and what it did not.
*&   2. CHECK IS INVERTED      -> CHECK exits when the expression is
*&                       FALSE, so every guard clause written with it
*&                       needs a double negation. Both branches run.
*&   3. CHECK IN A LOOP        -> is CONTINUE, not an abort: a CHECK
*&                       that fails on pass 1 does NOT end the loop.
*&   4. DO n TIMES SNAPSHOTS n -> the bound is read on entry and
*&                       changes inside the loop are ignored; n <= 0
*&                       executes ZERO passes and says nothing.
*&   5. sy-index IS PER LOOP   -> it always refers to the CURRENT loop,
*&                       so the value read after an inner ENDDO is the
*&                       outer loop's counter again.
*&   6. EXIT LEAVES ONE LOOP   -> the innermost. There is no labelled
*&                       break; only RETURN leaves a procedure from
*&                       inside a loop.
*&   7. EARLY RETURN DELIVERS  -> a by-value EXPORTING parameter is
*&                       initialized at procedure start and passed to
*&                       the caller on an early RETURN, so the caller
*&                       gets the half-filled result, not its own
*&                       previous value.
*&
*& Rules that cannot be demonstrated in a report, because they are
*& properties of the calling context rather than of the code (README):
*&   - STOP is forbidden in methods and raises an UNCATCHABLE exception
*&     (STOP_NO_REPORT / STOP_WITHIN_CALLED_DYNPRO);
*&   - RETURN or EXIT in START-OF-SELECTION suppresses all further
*&     reporting events, so END-OF-SELECTION never runs, while STOP
*&     exists precisely to raise it;
*&   - LOAD-OF-PROGRAM cannot be exited with RETURN, EXIT or CHECK;
*&   - LEAVE PROGRAM and friends are not allowed during a unit test or
*&     in the update task.
*&---------------------------------------------------------------------*
REPORT ydj_flow_control_demo.

TYPES: lty_t_num TYPE STANDARD TABLE OF i WITH EMPTY KEY.

CLASS lcl_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS exit_two_meanings.
    CLASS-METHODS check_is_inverted.
    CLASS-METHODS check_in_loop.
    CLASS-METHODS do_snapshots_n.
    CLASS-METHODS sy_index_scope.
    CLASS-METHODS exit_leaves_one_loop.
    CLASS-METHODS early_return_delivers.

  PRIVATE SECTION.

    " A guard written with CHECK. CHECK exits when the expression is
    " FALSE, hence the comparison against abap_false to say not-yet-
    " finished. SAP's own documentation files this exact shape under
    " the heading Bad Example, for that reason.
    CLASS-METHODS guard_with_check
      IMPORTING iv_finished TYPE abap_bool.

    " The same guard written with IF ... RETURN. Reads as it behaves.
    CLASS-METHODS guard_with_if
      IMPORTING iv_finished TYPE abap_bool.

    " Fills rows, then leaves early from INSIDE a loop. EXIT could not
    " do this - it would only break the loop. VALUE( ) makes the
    " parameter pass by value, which is the case the documentation
    " describes.
    CLASS-METHODS half_fill
      EXPORTING VALUE(et_rows) TYPE lty_t_num.

ENDCLASS.


CLASS lcl_demo IMPLEMENTATION.

*----------------------------------------------------------------------*
* 1. Two identical EXIT statements, two different effects.
*----------------------------------------------------------------------*
  METHOD exit_two_meanings.

    DATA lv_passes TYPE i.

    WRITE: / '1. One EXIT breaks a loop, the next returns from the method'.

    DO 5 TIMES.
      IF sy-index = 3.
        EXIT.               " inside DO ... ENDDO -> breaks the loop
      ENDIF.
      lv_passes = lv_passes + 1.
    ENDDO.

    WRITE: /  '   passes completed before the first EXIT :', lv_passes,
           /  '   code after ENDDO was reached           : yes'.

    IF lv_passes = 2.
      EXIT.                 " no loop encloses this -> acts as RETURN
    ENDIF.

    WRITE: / '   this line is never printed'.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 2. CHECK exits on FALSE, so the guard is a double negative.
*----------------------------------------------------------------------*
  METHOD check_is_inverted.

    WRITE: / '2. CHECK exits when its expression is FALSE'.

    WRITE: / '   guard_with_check( abap_false ) - CHECK passes:'.
    guard_with_check( abap_false ).

    WRITE: / '   guard_with_check( abap_true  ) - CHECK exits:'.
    guard_with_check( abap_true ).
    WRITE: / '      (nothing above - the method was left)'.

    WRITE: / '   guard_with_if( abap_false ) - IF passes:'.
    guard_with_if( abap_false ).

    WRITE: / '   guard_with_if( abap_true  ) - IF returns:'.
    guard_with_if( abap_true ).
    WRITE: / '      (nothing above - the method was left)'.

    WRITE: / '   -> identical behaviour. The CHECK version has to',
           / '      compare against abap_false to say not-yet-finished,',
           / '      because CHECK leaves when its expression is false.'.

  ENDMETHOD.

  METHOD guard_with_check.

    CHECK iv_finished = abap_false.
    WRITE: / '      body ran'.

  ENDMETHOD.

  METHOD guard_with_if.

    IF iv_finished = abap_true.
      RETURN.
    ENDIF.
    WRITE: / '      body ran'.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 3. The SAME CHECK inside a loop is CONTINUE, not an abort.
*----------------------------------------------------------------------*
  METHOD check_in_loop.

    DATA: lv_rem  TYPE i,
          lv_kept TYPE i.

    WRITE: / '3. CHECK inside a loop skips the pass, it does not abort'.

    DO 6 TIMES.
      lv_rem = sy-index MOD 2.
      CHECK lv_rem = 0.     " fails on pass 1 - loop carries on anyway
      lv_kept = lv_kept + 1.
    ENDDO.

    WRITE: /  '   passes that survived the CHECK :', lv_kept,
           /  '   -> 3, not 0. Had CHECK aborted on the first odd pass',
           /  '      the counter would still be zero.'.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 4. DO n TIMES reads n once; n <= 0 runs zero passes.
*----------------------------------------------------------------------*
  METHOD do_snapshots_n.

    DATA: lv_n      TYPE i,
          lv_passes TYPE i.

    WRITE: / '4. DO n TIMES takes n on entry and ignores changes to it'.

    lv_n = 3.
    DO lv_n TIMES.
      lv_n      = 99.       " ignored by the control structure
      lv_passes = lv_passes + 1.
    ENDDO.
    WRITE: /  '   n = 3, set to 99 inside the loop  -> passes:', lv_passes.

    CLEAR lv_passes.
    lv_n = 0.
    DO lv_n TIMES.
      lv_passes = lv_passes + 1.
    ENDDO.
    WRITE: /  '   n = 0                             -> passes:', lv_passes.

    CLEAR lv_passes.
    lv_n = -5.
    DO lv_n TIMES.
      lv_passes = lv_passes + 1.
    ENDDO.
    WRITE: /  '   n = -5                            -> passes:', lv_passes.

    WRITE: / '   -> zero passes is silent: no syntax error, no message,',
           / '      no runtime error. An unset bound is dead code.'.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 5. sy-index always refers to the current loop.
*----------------------------------------------------------------------*
  METHOD sy_index_scope.

    DATA: lv_outer      TYPE i,
          lv_inner_last TYPE i,
          lv_after      TYPE i.

    WRITE: / '5. sy-index belongs to the innermost running loop'.

    DO 2 TIMES.
      lv_outer = sy-index.
      DO 3 TIMES.
        lv_inner_last = sy-index.
      ENDDO.
      lv_after = sy-index.  " the outer loop's counter again
      WRITE: /  '   outer pass:', lv_outer,
                '  last inner sy-index:', lv_inner_last,
                '  sy-index after ENDDO:', lv_after.
    ENDDO.

    WRITE: / '   -> the documented rule is that sy-index always refers',
           / '      to the CURRENT loop, so column three should be the',
           / '      outer counter rather than 3. The columns above are',
           / '      the check on your own system. Either way: copy',
           / '      sy-index to a variable before ENDDO if you need it.'.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 6. EXIT leaves the innermost loop only.
*----------------------------------------------------------------------*
  METHOD exit_leaves_one_loop.

    DATA: lv_outer_entered  TYPE i,
          lv_outer_finished TYPE i.

    WRITE: / '6. EXIT leaves one loop - the innermost one'.

    DO 3 TIMES.
      lv_outer_entered = lv_outer_entered + 1.
      DO 5 TIMES.
        EXIT.               " leaves the inner loop, nothing more
      ENDDO.
      lv_outer_finished = lv_outer_finished + 1.
    ENDDO.

    WRITE: /  '   outer passes entered  :', lv_outer_entered,
           /  '   outer passes finished :', lv_outer_finished,
           /  '   -> the outer loop ran to completion. To leave the',
           /  '      method from in here you need RETURN; EXIT cannot.'.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 7. An early RETURN still hands the caller the half-filled output.
*----------------------------------------------------------------------*
  METHOD early_return_delivers.

    DATA: lt_result TYPE lty_t_num,
          lv_before TYPE i,
          lv_after  TYPE i.

    WRITE: / '7. An early RETURN delivers the by-value output anyway'.

    DO 9 TIMES.
      APPEND sy-index TO lt_result.
    ENDDO.
    lv_before = lines( lt_result ).

    half_fill( IMPORTING et_rows = lt_result ).
    lv_after = lines( lt_result ).

    WRITE: /  '   caller rows before the call :', lv_before,
           /  '   caller rows after the call  :', lv_after,
           /  '   -> 9 then 2. The output parameter was initialized at',
           /  '      procedure start and passed on at the early RETURN,',
           /  '      so the no-op path overwrote the caller value.',
           /  '      Only an exception or a message withholds it.'.

  ENDMETHOD.

  METHOD half_fill.

    DO 5 TIMES.
      APPEND sy-index TO et_rows.
      IF sy-index = 2.
        RETURN.             " from inside a loop - EXIT could not
      ENDIF.
    ENDDO.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  WRITE: / 'Program flow control: the statements that read their surroundings'.
  WRITE: / '(no database access, nothing is changed anywhere)'.
  SKIP.

  lcl_demo=>exit_two_meanings( ).
  SKIP.
  lcl_demo=>check_is_inverted( ).
  SKIP.
  lcl_demo=>check_in_loop( ).
  SKIP.
  lcl_demo=>do_snapshots_n( ).
  SKIP.
  lcl_demo=>sy_index_scope( ).
  SKIP.
  lcl_demo=>exit_leaves_one_loop( ).
  SKIP.
  lcl_demo=>early_return_delivers( ).
