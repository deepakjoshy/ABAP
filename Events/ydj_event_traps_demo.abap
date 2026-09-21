*&---------------------------------------------------------------------*
*& Report YDJ_EVENT_TRAPS_DEMO
*&---------------------------------------------------------------------*
*& ABAP Objects events - RAISE EVENT / SET HANDLER and the documented
*& registration rules that make handlers keep firing when you think they
*& are gone, and stay silent when you think they are registered.
*&
*&   1. REGISTRATION IS A  -> SET HANDLER stores a REFERENCE to the
*&      STRONG REFERENCE      handler object. CLEARing your own variable
*&                            does NOT stop it: the object cannot be
*&                            collected while it is registered.
*&   2. DOUBLE REGISTRATION -> registering the same handler twice sets
*&      IS NOT A DOUBLE CALL  sy-subrc = 4 and the handler still runs
*&                            exactly ONCE. Nobody reads that sy-subrc.
*&   3. MASS DEREGISTRATION -> SET HANDLER ... FOR ALL INSTANCES
*&      MISSES SINGLE ONES    ACTIVATION space does NOT cancel a
*&                            registration made FOR a single oref.
*&   4. AN EXCEPTION IN ONE -> cancels event handling. The remaining
*&      HANDLER SKIPS THE     registered handlers never run, and the
*&      REST                  TRIGGER gets CX_SY_NO_HANDLER.
*&   5. FOR ALL INSTANCES    -> also covers objects created AFTER the
*&      IS RETROACTIVE        SET HANDLER statement, including the
*&                            temporary ones made with NEW.
*&
*& Self-contained: local classes and literals only, no DDIC, no database.
*&---------------------------------------------------------------------*
REPORT ydj_event_traps_demo.

*&---------------------------------------------------------------------*
*& Collector, so every trap is proved by COUNTING handler calls rather
*& than by asserting that something happened.
*&---------------------------------------------------------------------*
CLASS lcl_log DEFINITION.

  PUBLIC SECTION.
    TYPES ty_lines TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    CLASS-DATA gt_lines TYPE ty_lines.
    CLASS-METHODS add   IMPORTING iv_text TYPE string.
    CLASS-METHODS reset.
    CLASS-METHODS count RETURNING VALUE(rv_count) TYPE i.

ENDCLASS.

CLASS lcl_log IMPLEMENTATION.

  METHOD add.
    APPEND iv_text TO gt_lines.
  ENDMETHOD.

  METHOD reset.
    CLEAR gt_lines.
  ENDMETHOD.

  METHOD count.
    rv_count = lines( gt_lines ).
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& A local exception class. It inherits from CX_DYNAMIC_CHECK on
*& purpose: an event handler may NOT declare RAISING, so a
*& CX_STATIC_CHECK exception could not be raised here without a syntax
*& error. That restriction is the root of trap 4.
*&---------------------------------------------------------------------*
CLASS lcx_demo DEFINITION INHERITING FROM cx_dynamic_check.
ENDCLASS.

*&---------------------------------------------------------------------*
*& The trigger. One instance event with an output parameter, and one
*& static event to show that a static event is registered WITHOUT FOR.
*&---------------------------------------------------------------------*
CLASS lcl_order DEFINITION.

  PUBLIC SECTION.
    EVENTS       changed EXPORTING VALUE(iv_id) TYPE string.
    CLASS-EVENTS all_cleared.

    METHODS constructor IMPORTING iv_id TYPE string.
    METHODS id          RETURNING VALUE(rv_id) TYPE string.
    METHODS touch.
    CLASS-METHODS clear_all.

  PRIVATE SECTION.
    DATA mv_id TYPE string.

ENDCLASS.

CLASS lcl_order IMPLEMENTATION.

  METHOD constructor.
    mv_id = iv_id.
  ENDMETHOD.

  METHOD id.
    rv_id = mv_id.
  ENDMETHOD.

  METHOD touch.
    " RAISE EVENT is SYNCHRONOUS. Every registered handler runs to
    " completion here, in the same work process and the same LUW,
    " before the next statement of this method is executed.
    RAISE EVENT changed EXPORTING iv_id = mv_id.
  ENDMETHOD.

  METHOD clear_all.
    RAISE EVENT all_cleared.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& A well-behaved handler. sender is the IMPLICIT output parameter of
*& every instance event - it is never listed after EXPORTING at the
*& RAISE EVENT, the runtime supplies it.
*&---------------------------------------------------------------------*
CLASS lcl_watcher DEFINITION.

  PUBLIC SECTION.
    METHODS constructor IMPORTING iv_name TYPE string.
    METHODS on_changed  FOR EVENT changed     OF lcl_order
                        IMPORTING iv_id sender.
    " Handler for a STATIC event: no sender is available, and the
    " SET HANDLER statement for it must be written WITHOUT a FOR clause.
    METHODS on_cleared  FOR EVENT all_cleared OF lcl_order.

  PRIVATE SECTION.
    DATA mv_name TYPE string.

ENDCLASS.

CLASS lcl_watcher IMPLEMENTATION.

  METHOD constructor.
    mv_name = iv_name.
  ENDMETHOD.

  METHOD on_changed.
    DATA lv_sender_id TYPE string.
    IF sender IS BOUND.
      lv_sender_id = sender->id( ).
    ENDIF.
    lcl_log=>add( |{ mv_name } handled { iv_id } (sender = { lv_sender_id })| ).
  ENDMETHOD.

  METHOD on_cleared.
    lcl_log=>add( |{ mv_name } handled the static event| ).
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& A handler that fails. Note the absence of RAISING in the declaration -
*& event handlers are forbidden from declaring it, which is exactly why
*& an unhandled exception here becomes an interface violation.
*&---------------------------------------------------------------------*
CLASS lcl_bad_watcher DEFINITION.

  PUBLIC SECTION.
    METHODS on_changed FOR EVENT changed OF lcl_order IMPORTING iv_id.

ENDCLASS.

CLASS lcl_bad_watcher IMPLEMENTATION.

  METHOD on_changed.
    lcl_log=>add( |bad watcher entered for { iv_id }| ).
    RAISE EXCEPTION TYPE lcx_demo.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& The traps.
*&---------------------------------------------------------------------*
CLASS lcl_demo DEFINITION.

  PUBLIC SECTION.
    CLASS-METHODS trap_1_handler_stays_alive.
    CLASS-METHODS trap_2_double_registration.
    CLASS-METHODS trap_3_mass_deregistration.
    CLASS-METHODS trap_4_exception_in_handler.
    CLASS-METHODS trap_5_for_all_instances.

  PRIVATE SECTION.
    CLASS-METHODS dump IMPORTING iv_title TYPE string.

ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

  METHOD dump.
    DATA lv_line TYPE string.
    SKIP.
    WRITE: / iv_title COLOR COL_HEADING.
    IF lcl_log=>count( ) = 0.
      WRITE: / '  (no handler ran)'.
    ELSE.
      LOOP AT lcl_log=>gt_lines INTO lv_line.
        WRITE: / '  ', lv_line.
      ENDLOOP.
    ENDIF.
    lcl_log=>reset( ).
  ENDMETHOD.

  METHOD trap_1_handler_stays_alive.
    DATA lo_order   TYPE REF TO lcl_order.
    DATA lo_watcher TYPE REF TO lcl_watcher.

    CREATE OBJECT lo_order   EXPORTING iv_id   = 'ORD-1'.
    CREATE OBJECT lo_watcher EXPORTING iv_name = 'watcher A'.

    SET HANDLER lo_watcher->on_changed FOR lo_order.

    " Drop OUR reference. In most languages this watcher is now garbage.
    " Here the registration table still holds a reference, so the object
    " stays alive and keeps handling the event.
    CLEAR lo_watcher.

    lo_order->touch( ).
    dump( 'Trap 1 - handler still runs after CLEAR of its reference' ).

    " The only way out is deregistration - and writing that statement
    " needs a reference, which is why the variable has to be kept until
    " then. Dropping it is how a handler becomes unstoppable.
  ENDMETHOD.

  METHOD trap_2_double_registration.
    DATA lo_order   TYPE REF TO lcl_order.
    DATA lo_watcher TYPE REF TO lcl_watcher.
    DATA lv_subrc_1 TYPE sy-subrc.
    DATA lv_subrc_2 TYPE sy-subrc.
    DATA lv_calls   TYPE i.

    CREATE OBJECT lo_order   EXPORTING iv_id   = 'ORD-2'.
    CREATE OBJECT lo_watcher EXPORTING iv_name = 'watcher B'.

    SET HANDLER lo_watcher->on_changed FOR lo_order.
    lv_subrc_1 = sy-subrc.

    SET HANDLER lo_watcher->on_changed FOR lo_order.
    lv_subrc_2 = sy-subrc.

    lo_order->touch( ).
    lv_calls = lcl_log=>count( ).

    SKIP.
    WRITE: / 'Trap 2 - registering the same handler twice' COLOR COL_HEADING.
    WRITE: / '  sy-subrc after 1st SET HANDLER:', lv_subrc_1,
           / '  sy-subrc after 2nd SET HANDLER:', lv_subrc_2,
             '  (4 = already registered for the same event)',
           / '  handler calls for one RAISE EVENT:', lv_calls.
    lcl_log=>reset( ).
  ENDMETHOD.

  METHOD trap_3_mass_deregistration.
    DATA lo_order   TYPE REF TO lcl_order.
    DATA lo_watcher TYPE REF TO lcl_watcher.
    DATA lv_subrc   TYPE sy-subrc.
    DATA lv_calls   TYPE i.

    CREATE OBJECT lo_order   EXPORTING iv_id   = 'ORD-3'.
    CREATE OBJECT lo_watcher EXPORTING iv_name = 'watcher C'.

    " A SINGLE registration, for one object.
    SET HANDLER lo_watcher->on_changed FOR lo_order.

    " A MASS deregistration. Single and mass registrations live in
    " DIFFERENT system tables, so this statement does not touch the
    " registration made above.
    SET HANDLER lo_watcher->on_changed FOR ALL INSTANCES ACTIVATION space.
    lv_subrc = sy-subrc.

    lo_order->touch( ).
    lv_calls = lcl_log=>count( ).

    SKIP.
    WRITE: / 'Trap 3 - mass deregistration does not cancel a single one'
             COLOR COL_HEADING.
    WRITE: / '  sy-subrc of the mass ACTIVATION space:', lv_subrc,
             '  (8 = was not registered that way)',
           / '  handler calls after that "deregistration":', lv_calls.
    lcl_log=>reset( ).

    " The MATCHING form is what actually works.
    SET HANDLER lo_watcher->on_changed FOR lo_order ACTIVATION space.
    lo_order->touch( ).
    lv_calls = lcl_log=>count( ).
    WRITE: / '  handler calls after the matching deregistration:', lv_calls.
    lcl_log=>reset( ).
  ENDMETHOD.

  METHOD trap_4_exception_in_handler.
    DATA lo_order  TYPE REF TO lcl_order.
    DATA lo_good   TYPE REF TO lcl_watcher.
    DATA lo_bad    TYPE REF TO lcl_bad_watcher.
    DATA lv_caught TYPE string.
    DATA lv_calls  TYPE i.

    CREATE OBJECT lo_order EXPORTING iv_id   = 'ORD-4'.
    CREATE OBJECT lo_good  EXPORTING iv_name = 'watcher D'.
    CREATE OBJECT lo_bad.

    SET HANDLER lo_bad->on_changed  FOR lo_order.
    SET HANDLER lo_good->on_changed FOR lo_order.

    " The TRIGGER catches it, not the handler. An unhandled
    " CX_DYNAMIC_CHECK in a handler violates the (necessarily empty)
    " RAISING interface, which raises CX_SY_NO_HANDLER and cancels
    " event handling for the remaining handlers.
    TRY.
        lo_order->touch( ).
        lv_caught = 'nothing'.
      CATCH cx_sy_no_handler.
        lv_caught = 'CX_SY_NO_HANDLER'.
    ENDTRY.

    lv_calls = lcl_log=>count( ).

    SKIP.
    WRITE: / 'Trap 4 - one failing handler cancels event handling'
             COLOR COL_HEADING.
    WRITE: / '  the trigger caught:', lv_caught.
    WRITE: / '  handlers that logged anything:', lv_calls,
             '  (two were registered)'.
    lcl_log=>reset( ).

    " Handler ORDER is undefined and may change during runtime, so
    " whether the good handler ran before the bad one is not guaranteed
    " - which is why this failure mode is intermittent in practice.
  ENDMETHOD.

  METHOD trap_5_for_all_instances.
    DATA lo_watcher TYPE REF TO lcl_watcher.
    DATA lo_late    TYPE REF TO lcl_order.

    CREATE OBJECT lo_watcher EXPORTING iv_name = 'watcher E'.

    " No trigger object exists yet at this point.
    SET HANDLER lo_watcher->on_changed FOR ALL INSTANCES.

    " Created AFTER the registration - handled anyway.
    CREATE OBJECT lo_late EXPORTING iv_id = 'ORD-5-late'.
    lo_late->touch( ).

    " Even a temporary instance never stored in a variable.
    NEW lcl_order( 'ORD-5-temp' )->touch( ).

    dump( 'Trap 5 - FOR ALL INSTANCES covers objects created later' ).

    SET HANDLER lo_watcher->on_changed FOR ALL INSTANCES ACTIVATION space.

    " A STATIC event: the handler is an instance method, but the
    " SET HANDLER statement takes NO FOR clause. Adding one is a syntax
    " error; omitting FOR for an INSTANCE event is the runtime error
    " SET_HANDLER_E_NO_FOR.
    SET HANDLER lo_watcher->on_cleared.
    lcl_order=>clear_all( ).
    dump( 'Trap 5b - static event, registered without a FOR clause' ).

    SET HANDLER lo_watcher->on_cleared ACTIVATION space.
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.

  WRITE: / 'ABAP Objects events - RAISE EVENT / SET HANDLER traps'
           COLOR COL_POSITIVE.

  lcl_demo=>trap_1_handler_stays_alive( ).
  lcl_demo=>trap_2_double_registration( ).
  lcl_demo=>trap_3_mass_deregistration( ).
  lcl_demo=>trap_4_exception_in_handler( ).
  lcl_demo=>trap_5_for_all_instances( ).
