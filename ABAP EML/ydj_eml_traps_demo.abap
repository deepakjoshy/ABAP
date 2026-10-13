*&---------------------------------------------------------------------*
*& Report YDJ_EML_TRAPS_DEMO
*&---------------------------------------------------------------------*
*& ABAP EML from the consumer side - what a MODIFY on a RAP business
*& object does, and more importantly what it does not do.
*&
*&   1. MODIFY writes to the         -> no COMMIT ENTITIES, no database
*&      transactional buffer only       change. There is no exception
*&                                 and no sy-subrc to tell you.
*&   2. READ ENTITY reads the        -> so reading the instance back
*&      buffer as well as the DB        CONFIRMS a write that is about
*&                                 to be lost. Only a plain SELECT
*&                                 answers "did that save?".
*&   3. Failure is a parameter,      -> FAILED is optional; omitting it
*&      not an exception                is a syntax WARNING that a
*&                                 pragma can switch off.
*&   4. MAPPED is the only way back  -> a CREATE returns no result
*&      to a generated key              parameter at all.
*&   5. ROLLBACK ENTITIES clears     -> and releases locks with it, for
*&      the buffer                      the whole RAP transaction.
*&
*& THIS REPORT CANNOT PERSIST ANYTHING. It never issues COMMIT ENTITIES
*& and never issues COMMIT WORK, and it ends with ROLLBACK ENTITIES.
*& Every SELECT below is there only to prove the database is untouched.
*&
*& PREREQUISITES - read before running:
*&   - A RAP-capable release (ABAP Platform / ABAP Cloud, 7.54+).
*&   - The SAP-delivered demo business object DEMO_MANAGED_ROOT and its
*&     persistent table DEMO_TAB_ROOT, from the ABAP demo content. On a
*&     system without the demo content, point the statements at a BDEF
*&     of your own - the behaviour being shown is not specific to this
*&     business object.
*&   - The response structures FAILED / MAPPED / REPORTED contain one
*&     nested internal table PER ENTITY of the business object, named
*&     after the entity (or its BDEF alias). Here that is
*&     -demo_managed_root. For your own BO, substitute your entity name.
*&
*& Doc: ABAP keyword documentation, latest. Base URL:
*&   https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/
*& Pages: ABAPMODIFY_ENTITY_ENTITIES.html, ABAPREAD_ENTITY_ENTITIES.html,
*&        ABAPCOMMIT_ENTITIES.html, ABAPROLLBACK_ENTITIES.html,
*&        ABAPEML_RESPONSE.html, ABAPDERIVED_TYPES_CID.html
*&---------------------------------------------------------------------*
REPORT ydj_eml_traps_demo.

CLASS lcl_eml_demo DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS:
      main,
      create_into_buffer,
      read_sees_the_buffer,
      baseline_from_database,
      rollback_and_recheck,
      what_commit_would_do.

  PRIVATE SECTION.
    CLASS-DATA:
      gv_key      TYPE demo_tab_root-key_field,
      gv_rows_pre TYPE i.
ENDCLASS.


CLASS lcl_eml_demo IMPLEMENTATION.

  METHOD main.

    gv_key = 4711.

    WRITE: / 'ABAP EML - the MODIFY that changes nothing'.
    ULINE.
    SKIP.

    baseline_from_database( ).
    create_into_buffer( ).
    read_sees_the_buffer( ).
    rollback_and_recheck( ).
    what_commit_would_do( ).

  ENDMETHOD.


* ---------------------------------------------------------------------
* 0. Baseline: how many rows are on the database before we start.
* ---------------------------------------------------------------------
  METHOD baseline_from_database.

    SELECT COUNT(*) FROM demo_tab_root
      WHERE key_field = @gv_key
      INTO @gv_rows_pre.

    WRITE: / '0. Baseline, straight from the database'.
    WRITE: / '   SELECT COUNT(*) WHERE key_field =', gv_key.
    WRITE: / '   rows on DB before the MODIFY:', gv_rows_pre.
    SKIP.

  ENDMETHOD.


* ---------------------------------------------------------------------
* 1. The MODIFY. Note what is NOT here: no TRY/CATCH, because EML does
*    not raise; no IF sy-subrc, because MODIFY does not set it. The only
*    error channel is FAILED, and it is optional - leaving it out costs
*    a syntax warning that ##EML_FAILED_MISSING_OK silences.
*
*    %cid is a request-local handle for an instance that has no key yet.
*    It is mandatory in strict(2) mode and a contract violation when
*    missing; AUTO FILL CID would generate one, but then %cid_ref cannot
*    refer to it.
* ---------------------------------------------------------------------
  METHOD create_into_buffer.

    MODIFY ENTITY demo_managed_root
      CREATE FIELDS ( key_field
                      data_field1_root
                      data_field2_root )
      WITH VALUE #( ( %cid             = 'ydj_cid_1'
                      key_field        = gv_key
                      data_field1_root = 'buffered'
                      data_field2_root = 'not saved' ) )
      FAILED   DATA(ls_failed)
      MAPPED   DATA(ls_mapped)
      REPORTED DATA(ls_reported).

    DATA(lv_failed)   = lines( ls_failed-demo_managed_root ).
    DATA(lv_mapped)   = lines( ls_mapped-demo_managed_root ).
    DATA(lv_reported) = lines( ls_reported-demo_managed_root ).

    WRITE: / '1. MODIFY ENTITY ... CREATE executed'.
    WRITE: / '   entries in FAILED  :', lv_failed.
    WRITE: / '   entries in MAPPED  :', lv_mapped.
    WRITE: / '   entries in REPORTED:', lv_reported.
    SKIP.
    WRITE: / '   An EMPTY failed table means success. NO failed table'.
    WRITE: / '   would have meant no information at all - the statement'.
    WRITE: / '   neither raises an exception nor sets sy-subrc.'.
    SKIP.

    IF lv_mapped > 0.
      READ TABLE ls_mapped-demo_managed_root INTO DATA(ls_map) INDEX 1.
      WRITE: / '   MAPPED ties the content ID back to the real key -'.
      WRITE: / '   the only route to a generated key, because a CREATE'.
      WRITE: / '   returns no result parameter:'.
      WRITE: / '     %cid     =', ls_map-%cid.
      WRITE: / '     key_field=', ls_map-key_field.
      SKIP.
    ENDIF.

  ENDMETHOD.


* ---------------------------------------------------------------------
* 2. The trap. READ ENTITY returns the "current transactional image":
*    the database PLUS the unsaved changes of this LUW. So reading the
*    instance back is not a verification that anything was saved.
* ---------------------------------------------------------------------
  METHOD read_sees_the_buffer.

    READ ENTITY demo_managed_root
      FIELDS ( key_field
               data_field1_root
               data_field2_root )
      WITH VALUE #( ( key_field = gv_key ) )
      RESULT DATA(lt_result)
      FAILED DATA(ls_read_failed).

    DATA(lv_read_rows)  = lines( lt_result ).
    DATA(lv_read_fails) = lines( ls_read_failed-demo_managed_root ).

    SELECT COUNT(*) FROM demo_tab_root
      WHERE key_field = @gv_key
      INTO @DATA(lv_rows_now).

    WRITE: / '2. The same key, asked two different ways'.
    WRITE: / '   READ ENTITY  rows returned:', lv_read_rows.
    WRITE: / '   READ ENTITY  rows failed  :', lv_read_fails.
    WRITE: / '   SELECT       rows on DB   :', lv_rows_now.
    SKIP.

    IF gv_rows_pre = 0 AND lv_read_rows > 0 AND lv_rows_now = 0.
      WRITE: / '   >> EML found the instance. The database never saw'.
      WRITE: / '      it. Both answers are correct: READ includes the'.
      WRITE: / '      transactional buffer by design, and that is why'.
      WRITE: / '      it cannot answer "did that actually save?".'.
      WRITE: / '      Assert with a plain SELECT in your unit tests.'.
    ELSEIF gv_rows_pre > 0.
      WRITE: / '   >> Key', gv_key, 'already existed on the database'.
      WRITE: / '      before this run, so the CREATE will have failed'.
      WRITE: / '      and the comparison above proves nothing. Change'.
      WRITE: / '      gv_key in METHOD main to an unused value.'.
    ENDIF.
    SKIP.

  ENDMETHOD.


* ---------------------------------------------------------------------
* 3. ROLLBACK ENTITIES clears the transactional buffer - and the locks
*    of the whole RAP transaction with it, which is why "roll back this
*    one document and carry on" is rarely as local as it reads.
* ---------------------------------------------------------------------
  METHOD rollback_and_recheck.

    ROLLBACK ENTITIES.

    READ ENTITY demo_managed_root
      FIELDS ( key_field )
      WITH VALUE #( ( key_field = gv_key ) )
      RESULT DATA(lt_after)
      FAILED DATA(ls_after_failed).

    DATA(lv_after_rows)  = lines( lt_after ).
    DATA(lv_after_fails) = lines( ls_after_failed-demo_managed_root ).

    WRITE: / '3. After ROLLBACK ENTITIES'.
    WRITE: / '   READ ENTITY rows returned:', lv_after_rows.
    WRITE: / '   READ ENTITY rows failed  :', lv_after_fails.
    SKIP.
    WRITE: / '   The buffer is empty, so EML now agrees with the'.
    WRITE: / '   database. Note the statement also released the locks'.
    WRITE: / '   held for every other instance in the same RAP'.
    WRITE: / '   transaction, not just this one.'.
    SKIP.

  ENDMETHOD.


* ---------------------------------------------------------------------
* 4. What COMMIT ENTITIES would have done - deliberately NOT executed,
*    so this report stays incapable of changing anything.
* ---------------------------------------------------------------------
  METHOD what_commit_would_do.

    WRITE: / '4. The COMMIT ENTITIES this report does not issue'.
    SKIP.
    WRITE: / '   It is the one EML statement that sets sy-subrc, and'.
    WRITE: / '   the usual IF sy-subrc <> 0 hides the distinction that'.
    WRITE: / '   actually matters:'.
    SKIP.
    WRITE: / '     0  implicit COMMIT WORK carried out successfully.'.
    WRITE: / '     4  early phase failed (finalize, check_before_save).'.
    WRITE: / '        Your changes REMAIN in the transactional buffer.'.
    WRITE: / '        Fix the bad instance and commit again. Rolling'.
    WRITE: / '        back here throws away work you could have kept.'.
    WRITE: / '     8  late phase failed (save, save_modified). The'.
    WRITE: / '        buffer has ALREADY been cleared and a ROLLBACK'.
    WRITE: / '        WORK has already happened. A later EML modify'.
    WRITE: / '        can now dump; an explicit ROLLBACK ENTITIES is'.
    WRITE: / '        required before the session is usable again.'.
    SKIP.
    WRITE: / '   The save is all or nothing: one invalid instance and'.
    WRITE: / '   none of the batch is written. Classical ABAP SQL would'.
    WRITE: / '   have kept the rows that worked.'.
    SKIP.
    WRITE: / '   And the update is a LOCAL update, or a synchronous one'.
    WRITE: / '   if the local update fails - never asynchronous. The'.
    WRITE: / '   save runs in this work process, on this dialog step,'.
    WRITE: / '   under rdisp/max_wprun_time. Nothing like V1/V2.'.
    SKIP.
    WRITE: / '   Finally, this statement is correct HERE and wrong in'.
    WRITE: / '   a behavior pool or an OData/Fiori scenario, where RAP'.
    WRITE: / '   commits for you. Transaction control belongs to the'.
    WRITE: / '   top of the call stack - in RAP that is enforced, not'.
    WRITE: / '   merely good taste.'.
    SKIP 2.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.
  lcl_eml_demo=>main( ).
