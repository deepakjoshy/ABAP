*&---------------------------------------------------------------------*
*& Report YDJ_SHARED_OBJECTS_DEMO
*&---------------------------------------------------------------------*
*& Shared objects: the AREA HANDLE syntax, the SHARED MEMORY ENABLED
*& restrictions, and the lock rules that decide whether your cache
*& works.
*&
*&   1. AREA HANDLE     -> CREATE OBJECT ... AREA HANDLE against the
*&                         predefined internal-session handle. Same
*&                         syntax as the real thing, no SHMA needed.
*&   2. STATIC ATTRS    -> a static attribute of a shared-memory-enabled
*&                         class is NOT in the area. Each program gets
*&                         its own. Instance attributes are shared.
*&   3. HANDLE INFO     -> IS_SHARED / IS_VALID / IS_ACTIVE_VERSION /
*&                         GET_DETACH_INFO, and GET_HANDLE_BY_OREF
*&                         finding the handle back from an object.
*&   4. LOCK RULES      -> the parts that need a real area, shown as
*&                         commented reference code with the exact
*&                         exception each mistake raises.
*&
*& WHAT THIS PROGRAM IS NOT
*& ------------------------
*& This is NOT shared memory. A real area needs a global root class, a
*& global area class and an area configured in transaction SHMA - none
*& of which can live inside a report. So the runnable half uses
*& CL_IMODE_AREA=>GET_IMODE_HANDLE( ), the predefined area handle for
*& the CURRENT INTERNAL SESSION.
*&
*& The documentation states that with that handle "the statement CREATE
*& OBJECT operates as if the addition AREA HANDLE were not specified".
*& That is exactly the point: the syntax, the class restrictions and
*& the CL_ABAP_MEMORY_AREA inspection methods are all real and all
*& exercised here - but there are no locks, so sections 5 to 8 are
*& reference blocks, not live demonstrations. Nothing below is faked;
*& the commented code is commented because it cannot compile in a
*& report, not because it was not checked.
*&
*& Self-contained: no CUSTOM DDIC objects, no database access, no writes,
*& no COMMIT WORK. (The one dictionary type it uses, SHM_DETACH_INFO, is
*& an SAP-delivered data element of the shared objects framework itself,
*& so it exists on every system - nothing has to be created to run this.)
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCREATE_OBJECT_AREA_HANDLE.html
*&---------------------------------------------------------------------*
REPORT ydj_shared_objects_demo.

*&---------------------------------------------------------------------*
*& The area root class stand-in.
*&
*& NOT a template: a real area ROOT class must be GLOBAL (the docs say it
*& "is always global"), and gets SHARED MEMORY ENABLED by ticking the
*& shared-memory-enabled attribute in Class Builder rather than by typing
*& the addition. A LOCAL class may carry the addition in source - the ABAP
*& docu's own CREATE OBJECT ... AREA HANDLE example does exactly that -
*& which is what makes this report possible at all.
*&
*& SHARED MEMORY ENABLED is the real addition, and it brings the real
*& restrictions with it:
*&   - no EVENTS and no CLASS-EVENTS may be declared here, and no
*&     method may carry FOR EVENT. Try adding one: it is a syntax
*&     error, not a warning.
*&   - it may only be put on a subclass if EVERY superclass has it too,
*&     and it is NOT inherited automatically.
*&---------------------------------------------------------------------*
CLASS lcl_cache_root DEFINITION
  FINAL
  CREATE PUBLIC
  SHARED MEMORY ENABLED.

  PUBLIC SECTION.
    " INSTANCE attribute: in a real area this lives in shared memory
    " and every session sees the same value.
    DATA mv_payload TYPE string.
    DATA mv_build_count TYPE i.

    " STATIC attribute: NOT in the area. Created per internal session
    " when the class is loaded, exactly like any other class. This is
    " trap 8 in the README and it is the quiet one.
    CLASS-DATA gv_local_hits TYPE i.

    METHODS set_payload
      IMPORTING iv_payload TYPE string.

    METHODS read_payload
      RETURNING VALUE(rv_payload) TYPE string.

ENDCLASS.

CLASS lcl_cache_root IMPLEMENTATION.

  METHOD set_payload.
    mv_payload = iv_payload.
    mv_build_count = mv_build_count + 1.
  ENDMETHOD.

  METHOD read_payload.
    " Counting reads in a STATIC attribute looks harmless and is the
    " bug: in a real area this counter is per PROGRAM, so the totals
    " are always lower than reality and always plausible.
    gv_local_hits = gv_local_hits + 1.
    rv_payload = mv_payload.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& A second shared-memory-enabled class, to show that a whole object
*& GRAPH has to be built with AREA HANDLE - one ordinary CREATE OBJECT
*& anywhere in it makes DETACH_COMMIT fail with
*& CX_SHM_EXTERNAL_REFERENCE (README trap 5).
*&---------------------------------------------------------------------*
CLASS lcl_cache_node DEFINITION
  FINAL
  CREATE PUBLIC
  SHARED MEMORY ENABLED.

  PUBLIC SECTION.
    DATA mv_key TYPE string.
    DATA mv_value TYPE string.

ENDCLASS.

CLASS lcl_cache_node IMPLEMENTATION.
ENDCLASS.

*&---------------------------------------------------------------------*
*& Driver.
*&---------------------------------------------------------------------*
CLASS lcl_demo DEFINITION FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS run.

  PRIVATE SECTION.
    CLASS-METHODS section_area_handle.
    CLASS-METHODS section_static_attributes.
    CLASS-METHODS section_handle_inspection.
    CLASS-METHODS detach_info_text
      IMPORTING iv_info        TYPE shm_detach_info
      RETURNING VALUE(rv_text) TYPE string.
    CLASS-METHODS head
      IMPORTING iv_title TYPE string.

ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

  METHOD head.
    SKIP.
    ULINE.
    WRITE / iv_title.
    ULINE.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& 1. CREATE OBJECT ... AREA HANDLE
*&---------------------------------------------------------------------*
  METHOD section_area_handle.

    DATA lo_root TYPE REF TO lcl_cache_root.
    DATA lo_node TYPE REF TO lcl_cache_node.
    DATA lv_payload TYPE string.

    head( `1. CREATE OBJECT ... AREA HANDLE` ).

    " The predefined area handle for the CURRENT INTERNAL SESSION.
    " In a real area this line would be:
    "   DATA(lo_handle) = zcl_my_area=>attach_for_write( ).
    " and it would be a LOCK, not just a handle.
    DATA(lo_handle) = cl_imode_area=>get_imode_handle( ).

    " Both objects are created THROUGH the handle. In a real area that
    " is what puts them inside it; here it is a no-op, but the syntax
    " and the SHARED MEMORY ENABLED requirement are identical.
    CREATE OBJECT lo_root AREA HANDLE lo_handle.
    CREATE OBJECT lo_node AREA HANDLE lo_handle.

    lo_node->mv_key = `CARRID`.
    lo_node->mv_value = `LH`.

    lo_root->set_payload( `flight cache v1` ).

    lv_payload = lo_root->read_payload( ).

    WRITE / 'Root object created via AREA HANDLE.'.
    WRITE / 'Payload            :'.
    WRITE lv_payload.
    WRITE / 'Node key/value     :'.
    WRITE lo_node->mv_key.
    WRITE lo_node->mv_value.

    " In a real area the build ENDS here, and both statements are
    " mandatory in this order:
    "   lo_handle->set_root( lo_root ).   " CX_SHM_ROOT_OBJECT_INITIAL
    "   lo_handle->detach_commit( ).      " ... and only NOW is it
    "                                     " pending - see section 6.
    " SET_ROOT does not exist on CL_IMODE_AREA, because there is no
    " area instance version to set a root on.
    WRITE / 'A real area would now need SET_ROOT, then DETACH_COMMIT.'.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& 2. Static vs instance attributes
*&---------------------------------------------------------------------*
  METHOD section_static_attributes.

    DATA lo_root TYPE REF TO lcl_cache_root.
    DATA lv_ignore TYPE string.
    DATA lv_hits TYPE i.
    DATA lv_builds TYPE i.

    head( `2. Static attributes are NOT in the area` ).

    DATA(lo_handle) = cl_imode_area=>get_imode_handle( ).
    CREATE OBJECT lo_root AREA HANDLE lo_handle.

    lo_root->set_payload( `airport cache` ).
    lo_root->set_payload( `airport cache v2` ).

    DO 3 TIMES.
      lv_ignore = lo_root->read_payload( ).
    ENDDO.

    lv_builds = lo_root->mv_build_count.
    lv_hits = lcl_cache_root=>gv_local_hits.

    WRITE / 'mv_build_count (INSTANCE attribute) :'.
    WRITE lv_builds.
    WRITE / '  -> in a real area: stored IN shared memory, every'.
    WRITE / '     session on this AS instance sees this number.'.

    WRITE / 'gv_local_hits  (STATIC attribute)   :'.
    WRITE lv_hits.
    WRITE / '  -> in a real area: NOT in shared memory. Created when'.
    WRITE / '     the class is loaded into each internal session, so'.
    WRITE / '     every program counts only its OWN reads. The number'.
    WRITE / '     is always too low and always looks plausible.'.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& 3. Inspecting a handle
*&---------------------------------------------------------------------*
  METHOD section_handle_inspection.

    DATA lo_root TYPE REF TO lcl_cache_root.
    DATA lv_flag TYPE abap_bool.
    DATA lv_same TYPE abap_bool.
    DATA lv_text TYPE string.

    head( `3. Handle inspection - CL_ABAP_MEMORY_AREA` ).

    DATA(lo_handle) = cl_imode_area=>get_imode_handle( ).
    CREATE OBJECT lo_root AREA HANDLE lo_handle.

    " IS_SHARED answers the question this whole program turns on:
    " am I looking at shared memory, or at my own session?
    lv_flag = lo_handle->is_shared( ).
    WRITE / 'is_shared( )           :'.
    WRITE lv_flag.
    WRITE / '  -> abap_false here, and that is correct: this handle'.
    WRITE / '     represents the internal session, not an area.'.

    lv_flag = lo_handle->is_valid( ).
    WRITE / 'is_valid( )            :'.
    WRITE lv_flag.

    lv_flag = lo_handle->is_active_version( ).
    WRITE / 'is_active_version( )   :'.
    WRITE lv_flag.
    WRITE / '  -> abap_false for an OBSOLETE version, for a released'.
    WRITE / '     handle, and also for any CHANGE handle.'.

    " GET_DETACH_INFO is the only way a reader finds out WHY its
    " handle stopped working - including the case where a writer
    " tore its lock away with ATTACH_MODE_DETACH_READER.
    lv_text = detach_info_text( lo_handle->get_detach_info( ) ).
    WRITE / 'get_detach_info( )     :'.
    WRITE lv_text.

    " Round trip: object -> handle. Useful when you are handed an
    " object and need to know which area instance it belongs to.
    DATA(lo_found) = cl_abap_memory_area=>get_handle_by_oref( lo_root ).
    " xsdbool( ) not boolc( ): boolc returns STRING, and the repo's own
    " Character Comparisons note covers why that compares wrong against
    " abap_false. xsdbool( ) returns abap_bool.
    lv_same = xsdbool( lo_found = lo_handle ).
    WRITE / 'get_handle_by_oref( )  : same handle back ->'.
    WRITE lv_same.

  ENDMETHOD.

  METHOD detach_info_text.

    CASE iv_info.
      WHEN cl_abap_memory_area=>detach_info_not_detached.
        rv_text = `NOT_DETACHED - handle still valid`.
      WHEN cl_abap_memory_area=>detach_info_handle.
        rv_text = `HANDLE - released by detach_commit/detach_rollback`.
      WHEN cl_abap_memory_area=>detach_info_area.
        rv_text = `AREA - released by detach_area/detach_all_areas`.
      WHEN cl_abap_memory_area=>detach_info_attach.
        rv_text = `ATTACH - a writer used ATTACH_MODE_DETACH_READER`.
      WHEN cl_abap_memory_area=>detach_info_invalidate.
        rv_text = `INVALIDATE - invalidate_* with terminate_changer`.
      WHEN cl_abap_memory_area=>detach_info_free.
        rv_text = `FREE - released by a free_* method`.
      WHEN OTHERS.
        rv_text = `other / propagate`.
    ENDCASE.

  ENDMETHOD.

  METHOD run.
    section_area_handle( ).
    section_static_attributes( ).
    section_handle_inspection( ).
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  lcl_demo=>run( ).

*&---------------------------------------------------------------------*
*& 4. REFERENCE: what a real area looks like
*&---------------------------------------------------------------------*
*& Everything from here down is commented out because it needs a real
*& area created in transaction SHMA (call it ZCL_MY_AREA, with root
*& class ZCL_MY_ROOT). It is reference code, checked against the
*& documentation, not a runnable part of this report.
*&
*&   SHMA  - create and configure the area (generates ZCL_MY_AREA)
*&   SHMM  - monitor instances, versions and locks at runtime
*&   ST02  - shared memory utilisation and abap/shared_objects_size_MB
*&
*& Note that ST22 is on that list too, for the reasons in section 8.
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& 5. REFERENCE: the read side, and the detach that must not be skipped
*&---------------------------------------------------------------------*
* DATA lo_read TYPE REF TO zcl_my_area.
*
* TRY.
*     lo_read = zcl_my_area=>attach_for_read( ).
*     DATA(lt_data) = lo_read->root->get_data( ).
*     lo_read->detach( ).
*
*   CATCH cx_shm_read_lock_active.
*     " ALREADY attached in THIS internal session. The lock belongs to
*     " the session, not to the variable, so a helper method that
*     " attaches per call fails the second time it is called.
*
*   CATCH cx_shm_no_active_version INTO DATA(lx_build).
*     " Nothing built yet. Read the exception TEXT, they mean very
*     " different things:
*     "   NEITHER_BUILD_NOR_LOAD - no area constructor at all. Real
*     "                            configuration error, retrying is
*     "                            pointless.
*     "   BUILD_STARTED          - a build was just kicked off and the
*     "                            system did NOT wait for it. Retry
*     "                            later. Twice in a row with this
*     "                            text = the constructor is broken.
*     "   BUILD_NOT_FINISHED     - a build is already running.
*     "   LOAD_STARTED / LOAD_NOT_FINISHED - a displaced version is
*     "                            being reloaded from its backup.
*
*   CATCH cx_shm_out_of_memory.
*     " Yes - on the READ path. Documented: it can be raised by
*     " ATTACH_FOR_READ "if there is no longer sufficient space for
*     " the administration information". Fall back to building the
*     " data in the internal session rather than dumping.
*
*   CATCH cx_shm_inconsistent.
*     " A type in the area no longer matches the type in this session
*     " - i.e. somebody activated a structure while a built cache was
*     " sitting in memory. Rebuild the instance; no code change will
*     " fix it.
*
*   CLEANUP.
*     " THE IMPORTANT ONE. A shared lock that is never released blocks
*     " every future ATTACH_FOR_WRITE on a non-versioned area, for as
*     " long as this session lives, with CX_SHM_VERSION_LIMIT_EXCEEDED
*     " on the writer's side. The writer's code is not wrong; this
*     " missing detach is.
*     IF lo_read IS BOUND.
*       lo_read->detach( ).
*     ENDIF.
* ENDTRY.

*&---------------------------------------------------------------------*
*& 6. REFERENCE: the write side, and the commit that is not visible yet
*&---------------------------------------------------------------------*
* DATA lo_write TYPE REF TO zcl_my_area.
* DATA lo_root  TYPE REF TO zcl_my_root.
*
* TRY.
*     " attach_mode_wait + wait_time (MILLISECONDS) is the only way to
*     " queue at all, and only ONE program may wait per area instance:
*     " a second waiter gets CX_SHM_EXCLUSIVE_LOCK_ACTIVE immediately
*     " with text LOCKED_BY_PENDING_CHANGER.
*     lo_write = zcl_my_area=>attach_for_write(
*                  attach_mode = cl_shm_area=>attach_mode_wait
*                  wait_time   = 2000 ).
*
*     CREATE OBJECT lo_root AREA HANDLE lo_write.
*
*     " EVERY object reachable from the root must be created this way.
*     " One plain CREATE OBJECT - a logger, a formatter, a comparator
*     " someone hung off a node - and the commit below fails with
*     " CX_SHM_EXTERNAL_REFERENCE after the whole build is done.
*     CREATE OBJECT lo_root->node AREA HANDLE lo_write TYPE zcl_my_node.
*
*     lo_write->set_root( lo_root ).      " or CX_SHM_ROOT_OBJECT_INITIAL
*     lo_write->detach_commit( ).
*
*     " NOT VISIBLE YET. The area is transactional by default, so the
*     " change becomes active at the NEXT DATABASE COMMIT. Until then:
*     "   versioned area     -> readers still get the PREVIOUS version
*     "   non-versioned area -> reads are not possible at all
*     "   either            -> no new change lock
*     "                         (CX_SHM_EXCLUSIVE_LOCK_ACTIVE /
*     "                          CX_SHM_CHANGE_LOCK_ACTIVE, text
*     "                          WAITING_FOR_DB_COMMIT)
*     " So "write it then read it back to check" reports failure on a
*     " write that was perfectly fine.
*
*   CATCH cx_shm_version_limit_exceeded.
*     " A reader is still holding a shared lock and no new version can
*     " be made. On a non-versioned area this is the forgotten-detach
*     " outage from section 5.
*
*   CATCH cx_shm_change_lock_active.
*     " THIS session already holds a change lock - or released one and
*     " is still waiting for the database commit.
*
*   CATCH cx_shm_pending_lock_removed.
*     " Somebody deleted the pending lock in SHMM while we waited. A
*     " basis action arriving as an application exception.
*
*   CATCH cx_shm_error INTO DATA(lx_shm).
*     " A FAILED detach_commit DOES NOT RELEASE THE LOCK, and it may
*     " not be committed a second time - that is CX_SHM_SECONDARY_COMMIT.
*     " The only correct recovery is a rollback.
*     IF lo_write IS BOUND AND
*        lo_write->get_lock_kind( ) <> cl_shm_area=>lock_kind_detached.
*       lo_write->detach_rollback( ).
*     ENDIF.
*     " get_lock_kind( ) returns LOCK_KIND_COMPLETION_ERROR for exactly
*     " this state, which is how you tell it apart from a clean failure.
* ENDTRY.

*&---------------------------------------------------------------------*
*& 7. REFERENCE: building the cache deliberately
*&---------------------------------------------------------------------*
*& An area constructor is a class implementing IF_SHM_BUILD_INSTANCE,
*& registered against the area in SHMA. Its BUILD method receives
*& INST_NAME and INVOCATION_MODE, so it can tell an explicit call
*& (INVOCATION_MODE_EXPLICIT) from an automatic one triggered by a
*& read (INVOCATION_MODE_AUTO_BUILD).
*&
*& The automatic path is asynchronous from the caller's point of view -
*& section 5's BUILD_STARTED. A warm-up job should therefore call the
*& constructor explicitly and synchronously instead:
*
* TRY.
*     zcl_my_area=>build( ).
*   CATCH cx_shm_build_failed.
*     " The constructor itself failed.
*   CATCH cx_shma_not_configured.
*     " No area constructor class is bound to this area in SHMA.
*   CATCH cx_shma_inconsistent.
*     " The area class needs regenerating in SHMA.
* ENDTRY.

*&---------------------------------------------------------------------*
*& 8. REFERENCE: the cleanup calls that short-dump other sessions
*&---------------------------------------------------------------------*
*& TERMINATE_CHANGER DEFAULTS TO ABAP_TRUE on all four methods below.
*& With that default, every program still holding the relevant lock is
*& terminated with the runtime error SYSTEM_SHM_AREA_OBSOLETE. That is
*& a short dump, not an exception: it does not pass through the
*& victim's TRY/CATCH, and it appears in ST22 under the victim's
*& program name, unconnected to the housekeeping job that caused it.
*
* " Mark the active version obsolete. Existing shared locks keep
* " working; the next reader triggers a rebuild.
* zcl_my_area=>invalidate_instance( terminate_changer = abap_false ).
*
* " Set ALL versions to expired and release all shared locks. Here
* " ANY surviving area handle - not just a change lock - is enough to
* " terminate the other program.
* zcl_my_area=>free_instance( terminate_changer = abap_false ).
*
* " The cache is PER APPLICATION SERVER. After a database change,
* " invalidating locally leaves every other AS instance serving stale
* " data. AFFECT_ALL_SERVERS_BUT_LOCAL lets this server keep the
* " version it just built while the others rebuild.
* zcl_my_area=>invalidate_area(
*   terminate_changer = abap_false
*   affect_server     = cl_shm_area=>affect_all_servers_but_local ).
*
* " Release everything this session holds, across every area. The
* " right call for a generic error handler.
* cl_shm_area=>detach_all_areas( ).
*
* " Multiple change locks at once are ONLY possible through
* " MULTI_ATTACH - and the doc warns that two programs taking the same
* " two locks in opposite orders will deadlock out their wait times.
* " cl_shm_area=>multi_attach( ... ).
