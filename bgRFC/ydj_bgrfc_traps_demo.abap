*&---------------------------------------------------------------------*
*& Report YDJ_BGRFC_TRAPS_DEMO
*&---------------------------------------------------------------------*
*& Background RFC (bgRFC) - the object graph you have to build before
*& CALL FUNCTION ... IN BACKGROUND UNIT will compile, and the two
*& lifetimes that nothing in the syntax tells you about.
*&
*& WHY THIS DEMO SENDS NOTHING
*& ---------------------------
*& A bgRFC unit is saved and released to a scheduler by COMMIT WORK and
*& by nothing else. This program therefore contains NO COMMIT WORK and
*& NO CALL FUNCTION ... IN BACKGROUND UNIT statement at all: the unit
*& objects it creates hold zero function module registrations and are
*& never persisted, so there is nothing for a scheduler to execute.
*& The send sequence is shipped as commented reference code in the
*& subroutine-style blocks at the end, which is the same approach this
*& repo's Data Archiving and Application Log notes take for APIs whose
*& live call is a write.
*&
*& It also probes an INBOUND destination only. Per the documentation,
*& outbound destinations that are not yet registered may be registered
*& AUTOMATICALLY by cl_bgrfc_destination_outbound=>create( ), and the
*& same page calls switching a destination "a critical operation" when
*& queues to it have already been filled - so the outbound factory call
*& is not a read-only probe and is not executed here.
*&
*&   1. DESTINATION    -> cl_bgrfc_destination_inbound=>create( ) either
*&                        returns a handle or raises
*&                        CX_BGRFC_INVALID_DESTINATION. That exception
*&                        is CONFIGURATION, not a coding error: the name
*&                        must exist in SBGRFCCONF. Nothing in the
*&                        syntax check can tell you.
*&   2. SINGLETON      -> two create( ) calls for the same destination
*&                        return THE SAME OBJECT. Proven by comparing
*&                        the references, not asserted.
*&   3. UNITS          -> two create_trfc_unit( ) calls return DIFFERENT
*&                        objects. Destination is a singleton; the unit
*&                        is not. Reusing ONE unit object is how you
*&                        bundle several function calls into one unit.
*&   4. IS_VALID       -> called through the defining interface,
*&                        if_bgrfc_unit~is_valid( ), because IS_VALID is
*&                        a component of IF_BGRFC_UNIT and the unit
*&                        interfaces CONTAIN that interface. The raw
*&                        value is printed rather than compared with
*&                        abap_true: its type is not documented.
*&
*& Prerequisite: an inbound bgRFC destination maintained in SBGRFCCONF
*& (tab "Define Inbound Dest."), including its mandatory queue prefix.
*& Enter its name on the selection screen. With no valid destination
*& the program still runs and reports section 1 as the failure it is -
*& that report is itself the useful output.
*&
*& Docs: https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/48/
*&       (see the Sources section of this folder's README.md)
*&---------------------------------------------------------------------*
REPORT ydj_bgrfc_traps_demo.

* No LOWER CASE addition: bgRFC destination names are maintained in
* upper case, so the selection screen's default conversion is wanted.
PARAMETERS p_dest TYPE bgrfc_dest_name_inbound OBLIGATORY
                       DEFAULT 'MY_DEST'.

*----------------------------------------------------------------------*
CLASS lcl_demo DEFINITION FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS main
      IMPORTING iv_dest TYPE bgrfc_dest_name_inbound.

  PRIVATE SECTION.
    CLASS-DATA go_dest TYPE REF TO if_bgrfc_destination_inbound.

    CLASS-METHODS head
      IMPORTING iv_text TYPE string.
    CLASS-METHODS say
      IMPORTING iv_label TYPE string
                iv_value TYPE string.

    CLASS-METHODS destination_probe
      IMPORTING iv_dest        TYPE bgrfc_dest_name_inbound
      RETURNING VALUE(rv_ok)   TYPE abap_bool.
    CLASS-METHODS singleton_proof
      IMPORTING iv_dest TYPE bgrfc_dest_name_inbound.
    CLASS-METHODS unit_identity.
    CLASS-METHODS unit_validity.

ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_demo IMPLEMENTATION.

  METHOD head.
    SKIP 1.
    WRITE: / iv_text.
    WRITE: / '------------------------------------------------------'.
  ENDMETHOD.

  METHOD say.
    DATA lv_label TYPE c LENGTH 34.
    lv_label = iv_label.
    WRITE: / lv_label, iv_value.
  ENDMETHOD.

* 1 -------------------------------------------------------------------*
* The factory call is the whole test. A name that is not maintained in
* SBGRFCCONF raises CX_BGRFC_INVALID_DESTINATION - at RUNTIME, in the
* system the transport landed in, with no earlier warning anywhere.
  METHOD destination_probe.

    head( '1. DESTINATION - configuration, checked at runtime only' ).

    CLEAR rv_ok.
    TRY.
        go_dest = cl_bgrfc_destination_inbound=>create( iv_dest ).
        rv_ok = abap_true.
        say( iv_label = 'inbound destination'
             iv_value = CONV string( iv_dest ) ).
        say( iv_label = 'create( ) result'
             iv_value = `handle returned - destination is maintained` ).

      CATCH cx_bgrfc_invalid_destination INTO DATA(lo_err).
        say( iv_label = 'inbound destination'
             iv_value = CONV string( iv_dest ) ).
        say( iv_label = 'create( ) result'
             iv_value = `CX_BGRFC_INVALID_DESTINATION` ).
        say( iv_label = 'exception text'
             iv_value = lo_err->get_text( ) ).
        WRITE: / 'Maintain the name in SBGRFCCONF (Define Inbound Dest.)'.
        WRITE: / 'including its queue prefix - the docs state that bgRFC'.
        WRITE: / 'cannot work without that prefix assignment.'.
    ENDTRY.

  ENDMETHOD.

* 2 -------------------------------------------------------------------*
* "destination is a singleton for every execution destination" - so the
* second create( ) is not a second destination. Compare the references.
  METHOD singleton_proof.

    head( '2. SINGLETON - two create( ) calls, one object' ).

    TRY.
        DATA(lo_first)  = cl_bgrfc_destination_inbound=>create( iv_dest ).
        DATA(lo_second) = cl_bgrfc_destination_inbound=>create( iv_dest ).
      CATCH cx_bgrfc_invalid_destination.
        say( iv_label = 'skipped'
             iv_value = `no valid destination - see section 1` ).
        RETURN.
    ENDTRY.

    IF lo_first = lo_second.
      say( iv_label = 'lo_first = lo_second'
           iv_value = `TRUE - same object, as documented` ).
    ELSE.
      say( iv_label = 'lo_first = lo_second'
           iv_value = `FALSE - two objects (not what the docs say)` ).
    ENDIF.

    WRITE: / 'Calling create( ) again for a fresh start gives you the'.
    WRITE: / 'object you already had. The destination also lives for the'.
    WRITE: / 'whole program; only the UNIT is bound to the LUW.'.

  ENDMETHOD.

* 3 -------------------------------------------------------------------*
* Units are NOT singletons. One unit object per function call means
* independent units; one shared unit object means one bundled unit.
  METHOD unit_identity.

    head( '3. UNITS - one object per unit, and that is the bundling' ).

    IF go_dest IS NOT BOUND.
      say( iv_label = 'skipped'
           iv_value = `no valid destination - see section 1` ).
      RETURN.
    ENDIF.

    DATA(lo_unit_a) = go_dest->create_trfc_unit( ).
    DATA(lo_unit_b) = go_dest->create_trfc_unit( ).

    IF lo_unit_a = lo_unit_b.
      say( iv_label = 'lo_unit_a = lo_unit_b'
           iv_value = `TRUE - unexpected, units should differ` ).
    ELSE.
      say( iv_label = 'lo_unit_a = lo_unit_b'
           iv_value = `FALSE - two independent units` ).
    ENDIF.

    WRITE: / 'Both units are empty: no CALL FUNCTION ... IN BACKGROUND'.
    WRITE: / 'UNIT is executed anywhere in this program, and there is no'.
    WRITE: / 'COMMIT WORK, so neither unit is ever saved or scheduled.'.
    SKIP 1.
    WRITE: / 'The rule that decides your design:'.
    WRITE: / '  one unit object reused  -> one unit, one fate, ordered'.
    WRITE: / '  one unit object each    -> N units, parallel, separately'.
    WRITE: / '                             restartable'.

  ENDMETHOD.

* 4 -------------------------------------------------------------------*
* IS_VALID is a component of IF_BGRFC_UNIT, which the unit interfaces
* CONTAIN rather than redeclare - so it is addressed through the
* interface that DEFINED it. Same for LOCK, DELAY, DISABLE_COMMIT_CHECKS
* and SEPARATE_FROM_UPDATE_TASK.
  METHOD unit_validity.

    head( '4. IS_VALID - the reference outlives the unit' ).

    IF go_dest IS NOT BOUND.
      say( iv_label = 'skipped'
           iv_value = `no valid destination - see section 1` ).
      RETURN.
    ENDIF.

    DATA(lo_unit) = go_dest->create_trfc_unit( ).
    DATA(lv_valid) = lo_unit->if_bgrfc_unit~is_valid( ).

    say( iv_label = 'reference is bound'
         iv_value = `TRUE (it was just created)` ).
    say( iv_label = 'if_bgrfc_unit~is_valid( )'
         iv_value = |{ lv_valid }| ).

    SKIP 1.
    WRITE: / 'The raw value is printed rather than compared with'.
    WRITE: / 'abap_true: the documentation says only that IS_VALID'.
    WRITE: / 'shows the current status of the unit, and does not give'.
    WRITE: / 'its type. Check it in your own system before branching -'.
    WRITE: / 'if it is not character-like, the string template below'.
    WRITE: / 'needs replacing too.'.
    SKIP 1.
    WRITE: / 'After a COMMIT WORK the unit is EXHAUSTED while this'.
    WRITE: / 'reference stays bound and non-initial. That includes a'.
    WRITE: / 'COMMIT WORK you did not write - the docs say the object is'.
    WRITE: / 'invalidated when one is triggered intentionally OR'.
    WRITE: / 'unintentionally. IS_VALID is the only way to ask.'.

  ENDMETHOD.

  METHOD main.
    IF destination_probe( iv_dest ) = abap_false.
      WRITE: / 'Sections 2 to 4 need a maintained destination.'.
    ENDIF.
    singleton_proof( iv_dest ).
    unit_identity( ).
    unit_validity( ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
START-OF-SELECTION.
  lcl_demo=>main( p_dest ).

*&---------------------------------------------------------------------*
*& REFERENCE ONLY - the shapes this program deliberately does not run
*&---------------------------------------------------------------------*
*& Everything below is commented out. Each block ends in COMMIT WORK,
*& which is the statement that actually saves the unit and hands it to
*& a scheduler. Uncomment nothing in a system you do not own.
*&
*& (a) INBOUND, type t - "exactly once", no ordering, runs in parallel
*&
*&     DATA(lo_dest) = cl_bgrfc_destination_inbound=>create( 'MY_DEST' ).
*&     DATA(lo_unit) = lo_dest->create_trfc_unit( ).
*&
*&     " uncouple from the update task - must be done PER UNIT, or the
*&     " unit waits for this LUW's update records and is deleted with
*&     " them if somebody discards a failed update record in SM13
*&     lo_unit->if_bgrfc_unit~separate_from_update_task( ).
*&
*&     CALL FUNCTION 'Z_RFC_ENABLED_FM' IN BACKGROUND UNIT lo_unit
*&       EXPORTING iv_key = lv_key.
*&
*&     COMMIT WORK.
*&
*& (b) OUTBOUND, type q - "exactly once in order", serialized by queue
*&
*&     TRY.
*&         DATA(lo_odest) =
*&           cl_bgrfc_destination_outbound=>create( 'MY_DEST' ).
*&       CATCH cx_bgrfc_invalid_destination.
*&         " maintained in SM59, and may be auto-registered by create( )
*&     ENDTRY.
*&     DATA(lo_qunit) = lo_odest->create_qrfc_unit( ).
*&
*&     CALL FUNCTION 'Z_RFC_ENABLED_FM' IN BACKGROUND UNIT lo_qunit
*&       EXPORTING iv_key = lv_key.
*&
*&     " ONE name = one serialization lane. Several names means the unit
*&     " waits until it is at the head of EVERY queue named - a barrier,
*&     " not a label. Add names defensively and you stop the queues.
*&     TRY.
*&         lo_qunit->add_queue_name_outbound( 'DEBITOR-1234' ).
*&       CATCH cx_qrfc_duplicate_queue_name.
*&         " or pass ignore_duplicates = abap_true to the plural form
*&     ENDTRY.
*&
*&     COMMIT WORK.
*&
*& (c) HELD BACK - written to the database already locked
*&
*&     DATA(lv_lock_id) = lo_unit->if_bgrfc_unit~delay( 300 ).
*&     COMMIT WORK.
*&
*&     " KEEP lv_lock_id. The API offers no way to enumerate or clear
*&     " the locks on a unit - that is deliberate, so that one program
*&     " cannot release another's lock. Discard the id and the unit is
*&     " unrunnable from ABAP; only SBGRFCMON can free it.
*&
*& (d) INSIDE the unit - what the called function module may NOT do
*&
*&     A transactional consistency check forbids, in unit execution:
*&       CALL FUNCTION ... DESTINATION   (sRFC and aRFC)
*&       WAIT
*&       COMMIT WORK / ROLLBACK WORK
*&       HTTP via CL_HTTP_CLIENT
*&       the function module DB_COMMIT
*&     Failure is the runtime error SYSTEM_ILLEGAL_STATEMENT, or
*&     DBIF_DSQL2_DEFAULT_CR_ERROR for the implicit-commit case.
*&     MESSAGE is allowed, and MESSAGE is also the documented way to
*&     roll the unit back. So "queue it, then let the unit call the
*&     web service" is not a design this framework supports: the unit
*&     records the intent, a separate LUW makes the call.
*&
*&     lo_unit->if_bgrfc_unit~disable_commit_checks( ) switches the
*&     check off. It does not make the commit safe - it makes a
*&     half-applied, retryable unit possible. See README section 3.
*&
*& (e) ASKING WHAT HAPPENED - from outside, later
*&
*&     The client-side classes (one per type and direction) expose
*&     GET_UNIT_STATE, returning IF_BGRFC_CLIENT constants. Note that
*&     the documented UNIT_STATE_EXECUTED means "already executed" OR
*&     "unit_id does not specify a valid unit" - success and a bad id
*&     are the same answer, so completion must be confirmed from your
*&     own application data, not from this call.
*&---------------------------------------------------------------------*
