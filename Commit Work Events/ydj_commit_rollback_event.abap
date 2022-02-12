*&---------------------------------------------------------------------*
*& Report YDJ_COMMIT_ROLLBACK_EVENT
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ydj_commit_rollback_event.


CLASS lcl_commit_rollback_event DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS: execute.
    CLASS-METHODS: event_handler FOR EVENT transaction_finished OF cl_system_transaction_state IMPORTING kind.
ENDCLASS.

CLASS lcl_commit_rollback_event IMPLEMENTATION.

  METHOD execute.

    SET HANDLER lcl_commit_rollback_event=>event_handler.

    WRITE: / 'FM Execution'.
    CALL FUNCTION 'YDJ_FM_EVENT_HANDLER'.
    COMMIT WORK AND WAIT.

    SKIP 1.
    WRITE: /  'FM Execution in Update Task'.
    CALL FUNCTION 'YDJ_FM_EVENT_HANDLER' IN UPDATE TASK.
    ROLLBACK WORK.

  ENDMETHOD.


  METHOD event_handler.
    WRITE: / 'FM Execution Over | Kind = ', COND string( WHEN kind = 'C' THEN 'Commit' WHEN kind = 'R' THEN 'Rollback').
  ENDMETHOD.

ENDCLASS..


START-OF-SELECTION.
  lcl_commit_rollback_event=>execute( ).
