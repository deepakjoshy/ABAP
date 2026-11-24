*&---------------------------------------------------------------------*
*& ydj_rap_draft_patterns.abap
*& Companion to README.md in this folder.
*&
*& THIS FILE IS NOT A RUNNABLE REPORT.
*& Draft handling is declared in a behavior definition (BDEF, a CDS
*& object), stored in a DDIC table and consumed through EML. Only the
*& last part of this file is ABAP source; the rest is the surrounding
*& objects, in comment blocks, so that the whole set sits in one place.
*&
*& Layout:
*&   Part 1 - the BDEF, draft-enabled, with every mandatory element
*&            labelled (comment block - RAP BDL, not ABAP).
*&   Part 2 - the draft database table (comment block - DDIC DDL).
*&   Part 3 - the draft query view + DCL, i.e. the access control that
*&            README section 1 shows is otherwise missing.
*&   Part 4 - EML, as real ABAP, for the full draft life cycle, plus
*&            the wrong and right way to clear a draft table.
*&
*& Substitute your own names:
*&   ydj_r_salesorder                    -> your base BO (a projection
*&                                          reuses draft with: use draft)
*&   SalesOrder                          -> your root entity alias
*&   ydj_sales_order / ydj_so_draft      -> active / draft table
*&
*& The nested components of the derived types (failed-salesorder etc.)
*& are named after the entity, lower case. Check your own BDEF's derived
*& type with F2 in ADT rather than trusting the names below.
*&
*& Deliberately absent: any ABAP SQL write to the draft table outside
*& the one example that exists to show it failing (README section 2).
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& PART 1 - the behavior definition
*&---------------------------------------------------------------------*
* managed implementation in class ydj_bp_salesorder unique;
* strict ( 2 );
*
* " The switch. Header-level: draft-enables the WHOLE business object,
* " never a single entity.
* with draft;
*
* define behavior for YDJ_R_SalesOrder alias SalesOrder
* persistent table ydj_sales_order
*
* " Mandatory for a draft BO. The query addition is OPTIONAL - and
* " without it the DCL on the active view does not protect draft data.
* draft table ydj_so_draft query YDJ_SO_DRAFT_QUERY
*
* lock master
*
* " Mandatory, lock master only, and syntactically required to sit
* " DIRECTLY after lock master. Max 40 characters.
* " Field annotated @Semantics.systemDateTime.lastChangedAt: true
* " -> changes when the ACTIVE instance is persisted. Decides whether a
* "    draft may still be resumed.
* total etag ChangedAt
*
* authorization master ( instance )
*
* " NOT the same field as the total etag in a draft BO.
* " Field annotated
* " @Semantics.systemDateTime.localInstanceLastChangedAt: true
* " -> changes on EVERY write to the draft instance. This is the OData
* "    concurrency ETag. Before draft-enabling, ChangedAt was correct
* "    here; afterwards it is not (README section 4).
* etag master LocChangedAt
*
* {
*   create;
*   update;
*   delete;
*
*   " Both ETag fields are maintained by the managed framework, so no
*   " consumer may write them.
*   field ( readonly ) ChangedAt, ChangedBy, LocChangedAt;
*
*   " In strict mode the draft actions must be declared explicitly even
*   " though the framework provides them. Lock master entities only.
*   " Reserved names: an action of your own called Edit / Activate /
*   " Discard / Resume / Prepare / AdditionalSave is now a syntax error.
*   draft action Edit;
*   draft action Activate optimized;   " recommended - but see below
*   draft action Discard;
*   draft action Resume;
*
*   " Only ON SAVE determinations and validations can be assigned here,
*   " and only by being listed. Anything not listed does not run before
*   " activation - it runs during the save, and fails there instead.
*   draft determine action Prepare
*     { validation validateBuyer;
*       determination calcTotals; }
*
*   validation validateBuyer on save { create; field BuyerId; }
*   determination calcTotals  on save { create; field Amount;  }
*
*   " Prerequisite for 'optimized' above: these two must behave
*   " IDENTICALLY on draft and active instances, i.e. be written against
*   " %tky and be idempotent. optimized reduces how often they run.
*
*   " Every association in a draft BO must be draft-enabled, and then it
*   " returns draft data when followed from a draft instance and active
*   " data when followed from an active one.
*   association _Items { create; with draft; }
* }
*
* define behavior for YDJ_R_SalesOrderItem alias Item
* persistent table ydj_sales_item
* draft table ydj_so_item_draft      " its own, generated the same way
* lock dependent by _SalesOrder
* authorization dependent by _SalesOrder
*
* " No total etag here: declared once, on the lock master only. The
* " ETag can be inherited through the association that the entity body
* " below read-enables.
* etag dependent by _SalesOrder
* {
*   update;
*   delete;
*   field ( readonly ) SoKey;
*   association _SalesOrder { with draft; }
* }

*&---------------------------------------------------------------------*
*& PART 2 - the draft database table (DDIC DDL)
*&---------------------------------------------------------------------*
* " Generated by the ADT quick fix on the draft table name. Regenerating
* " it after a data model change COMPLETELY OVERWRITES this definition,
* " so nothing hand-edited survives. Keeping it aligned with the active
* " table is the developer's job, not the framework's.
* @EndUserText.label : 'Sales order - draft'
* @AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
* @AbapCatalog.tableCategory : #TRANSPARENT
* define table ydj_so_draft {
*
*   " Must be first, and must be type CLNT.
*   key mandt     : abap.clnt not null;
*
*   " One field per field of the CDS entity, same names (alias names if
*   " the entity assigns them), types and lengths matching EXACTLY.
*   " Field order is explicitly irrelevant.
*   key so_key    : ydj_so_key not null;
*   buyer_id      : ydj_buyer_id;
*   amount        : ydj_amount;
*   currency_code : abap.cuky;
*   changed_at    : timestampl;
*   loc_changed_at: abp_locinst_lastchange_tstmpl;
*
*   " With LATE NUMBERING this extra key field is mandatory:
*   " key draftuuid : sysuuid_x16;   " raw(16)
*
*   " The framework metadata. This is what ABAP SQL cannot delete, and
*   " why clearing rows with DELETE FROM leaves a duplicate key behind.
*   "%admin" : include sych_bdl_draft_admin_inc;
* }

*&---------------------------------------------------------------------*
*& PART 3 - the draft query view and its DCL
*&---------------------------------------------------------------------*
* " Why this exists: the DCL written for the view entity over the ACTIVE
* " table is not applied to draft data. Without the two objects below,
* " read access to in-progress business data is unrestricted by the
* " rules that restrict the saved version of the same data.
*
* " --- the view entity: draft table as source, ALL fields including the
* "     administrative ones, or you get a syntax check warning.
* @AccessControl.authorizationCheck: #CHECK
* @EndUserText.label: 'Draft query view - sales order'
* define view entity YDJ_SO_DRAFT_QUERY
*   as select from ydj_so_draft
* {
*   key so_key                        as SoKey,
*       buyer_id                      as BuyerId,
*       amount                        as Amount,
*       currency_code                 as CurrencyCode,
*       changed_at                    as ChangedAt,
*       loc_changed_at                as LocChangedAt,
*       draftentitycreationdatetime   as DraftEntityCreationDateTime,
*       draftentitylastchangedatetime as DraftEntityLastChangeDateTime,
*       draftadministrativedatauuid   as DraftAdministrativeDataUUID,
*       draftentityoperationcode      as DraftEntityOperationCode,
*       hasactiveentity               as HasActiveEntity,
*       draftfieldchanges             as DraftFieldChanges
* }
*
* " --- the DCL, mirroring whatever the active view's DCL grants.
* @EndUserText.label: 'Draft read access - sales order'
* @MappingRole: true
* define role YDJ_SO_DRAFT_READ {
*   grant select on YDJ_SO_DRAFT_QUERY
*     where ( BuyerId ) = aspect pfcg_auth( YDJ_SO_AUTH, BUYER_ID,
*                                           actvt = '03' );
* }

*&---------------------------------------------------------------------*
*& PART 4 - EML: the draft life cycle from ABAP (real source)
*&---------------------------------------------------------------------*
* An ADT console class (F9). Everything below runs against the BDEF of
* Part 1. The CREATE shape (AUTO FILL CID WITH, %is_draft, %control,
* %data) and the EXECUTE shape follow the documented examples cited in
* README.md; the component names are from the BDEF above.

CLASS ydj_cl_draft_lifecycle DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    CONSTANTS c_key TYPE ydj_so_key VALUE '0000000815'.

    METHODS new_draft      IMPORTING io_out TYPE REF TO if_oo_adt_classrun_out.
    METHODS edit_active    IMPORTING io_out TYPE REF TO if_oo_adt_classrun_out.
    METHODS prepare_draft  IMPORTING io_out TYPE REF TO if_oo_adt_classrun_out.
    METHODS activate_draft IMPORTING io_out TYPE REF TO if_oo_adt_classrun_out.
    METHODS discard_draft  IMPORTING io_out TYPE REF TO if_oo_adt_classrun_out.
ENDCLASS.

CLASS ydj_cl_draft_lifecycle IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
*   The new-draft path: nothing on the active table yet.
    new_draft( out ).
    prepare_draft( out ).
    activate_draft( out ).

*   The edit-draft path, now that an active instance exists: Edit
*   copies it to the draft table and locks it, Discard throws the copy
*   away again and leaves the active instance untouched.
    edit_active( out ).
    discard_draft( out ).
  ENDMETHOD.

* 1 - NEW DRAFT: no active instance exists yet. %is_draft = mk-on sends
*     the create to the draft table. The data is stored regardless of
*     whether it is complete or valid - that is the point of a draft.
  METHOD new_draft.
    MODIFY ENTITIES OF ydj_r_salesorder
      ENTITY SalesOrder
        CREATE AUTO FILL CID WITH
          VALUE #( ( %is_draft        = if_abap_behv=>mk-on
                     %control-SoKey   = if_abap_behv=>mk-on
                     %control-BuyerId = if_abap_behv=>mk-on
                     %data-SoKey      = c_key
                     %data-BuyerId    = 'B-1000' ) )
      FAILED DATA(failed).

*   A draft create can fail like any other modify: check FAILED, not
*   sy-subrc. COMMIT ENTITIES is what actually writes the draft row.
    IF failed IS NOT INITIAL.
      io_out->write( 'create of draft rejected' ).
      RETURN.
    ENDIF.

    COMMIT ENTITIES RESPONSE OF ydj_r_salesorder
      FAILED DATA(commit_failed).

    io_out->write( COND string( WHEN commit_failed IS INITIAL
                                THEN 'draft saved'
                                ELSE 'draft NOT saved' ) ).
  ENDMETHOD.

* 2 - EDIT DRAFT: the draft action Edit copies an EXISTING ACTIVE
*     instance to the draft table and sets the exclusive lock. Note the
*     draft indicator is OFF here: Edit is executed ON the active
*     instance. The same is true inside an additional implementation
*     for Edit, which is the trap in README section 7.
  METHOD edit_active.
    MODIFY ENTITIES OF ydj_r_salesorder
      ENTITY SalesOrder
        EXECUTE Edit
          FROM VALUE #( ( %tky-SoKey     = c_key
                          %tky-%is_draft = if_abap_behv=>mk-off ) )
      FAILED DATA(failed).

*   Edit is the one draft action with feature and authorization control,
*   so this is where a 'this document may not be edited' rule belongs.
*   It cannot be placed on Activate or Discard.
    IF failed IS NOT INITIAL.
      io_out->write( 'Edit rejected - locked, or feature control' ).
      RETURN.
    ENDIF.

    COMMIT ENTITIES.
    io_out->write( 'active instance copied to the draft table' ).
  ENDMETHOD.

* 3 - PREPARE: runs ONLY the on-save determinations and validations
*     listed after 'draft determine action Prepare' in the BDEF. This
*     is the user-visible consistency check before activation, and
*     anything not listed is not checked here.
  METHOD prepare_draft.
    MODIFY ENTITIES OF ydj_r_salesorder
      ENTITY SalesOrder
        EXECUTE Prepare
          FROM VALUE #( ( %tky-SoKey     = c_key
                          %tky-%is_draft = if_abap_behv=>mk-on ) )
      REPORTED DATA(reported)
      FAILED   DATA(failed).

*   Messages from the assigned validations arrive in REPORTED, keyed by
*   %state_area - the same mechanism as any other validation.
    LOOP AT reported-salesorder INTO DATA(ls_msg).
      IF ls_msg-%msg IS BOUND.
        io_out->write( ls_msg-%msg->if_message~get_text( ) ).
      ENDIF.
    ENDLOOP.

    IF failed IS NOT INITIAL.
      io_out->write( 'Prepare reports the draft as not ready' ).
    ENDIF.

    COMMIT ENTITIES.
  ENDMETHOD.

* 4 - ACTIVATE: draft -> active. Implicitly runs Prepare again, then
*     an UPDATE (edit-draft) or CREATE (new-draft) on the active side,
*     then discards the draft. No feature or authorization control:
*     authorization is checked when the active instance is saved.
  METHOD activate_draft.
    MODIFY ENTITIES OF ydj_r_salesorder
      ENTITY SalesOrder
        EXECUTE Activate
          FROM VALUE #( ( %tky-SoKey     = c_key
                          %tky-%is_draft = if_abap_behv=>mk-on ) )
      FAILED DATA(failed).

    IF failed IS NOT INITIAL.
*     Typical causes: a validation assigned to Prepare refused, or the
*     total ETag no longer matches because somebody changed the active
*     instance while the lock was expired.
      io_out->write( 'activation refused - draft not activated' ).
      RETURN.
    ENDIF.

    COMMIT ENTITIES RESPONSE OF ydj_r_salesorder
      FAILED DATA(commit_failed).

    io_out->write( COND string( WHEN commit_failed IS INITIAL
                                THEN 'activated; draft row removed'
                                ELSE 'save failed; draft still there' ) ).
  ENDMETHOD.

* 5 - DISCARD: the supported way to remove a draft instance AND its
*     metadata. No feature or authorization control is possible.
  METHOD discard_draft.
    MODIFY ENTITIES OF ydj_r_salesorder
      ENTITY SalesOrder
        EXECUTE Discard
          FROM VALUE #( ( %tky-SoKey     = c_key
                          %tky-%is_draft = if_abap_behv=>mk-on ) )
      FAILED DATA(failed).

    COMMIT ENTITIES.
    io_out->write( COND string( WHEN failed IS INITIAL
                                THEN 'draft discarded'
                                ELSE 'Discard rejected' ) ).
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& PART 4b - clearing a draft table: the wrong way and the right way
*&---------------------------------------------------------------------*
* The wrong way, written out here only because it is what everybody
* reaches for in a cleanup report or a test fixture. It is left as a
* comment on purpose: the point of the documented example is that the
* NEXT create fails with a duplicate key on a table that SELECT shows
* as empty, because the framework metadata is not in the rows you
* deleted.
*
*   DELETE FROM ydj_so_draft.            " <- rows gone, metadata not
*   COMMIT WORK.
*   " ... the following EML create of the same key now FAILS.
*
* The right way - both of these clear the entries AND the metadata:
*
*   a) the draft action Discard (method discard_draft above), or
*   b) the EML delete on the draft version:
*
*   MODIFY ENTITIES OF ydj_r_salesorder
*     ENTITY SalesOrder
*       DELETE FROM VALUE #( ( %tky-SoKey     = c_key
*                              %tky-%is_draft = if_abap_behv=>mk-on ) )
*     REPORTED DATA(reported)
*     FAILED   DATA(failed).
*   COMMIT ENTITIES.
*
* Reading the draft table with ABAP SQL for diagnostics is fine, and is
* what the documentation's own examples do to show the before/after
* state. Writing to it is not.

*&---------------------------------------------------------------------*
*& PART 4c - Resume: the one you never call
*&---------------------------------------------------------------------*
* Resume is executed automatically whenever a draft whose exclusive
* lock has expired is modified - on a Fiori elements UI, as soon as the
* user types into a draft they left open too long. It re-creates the
* lock on the active instance.
*
* Two things it does NOT do for you:
*   - re-run a RAP BO precheck. If the BO relies on one, Resume needs
*     'with additional implementation' and the handler must call the
*     precheck method itself.
*   - re-check primary key uniqueness. During the optimistic lock phase
*     another user may have created an instance with the same key.
*
* Explicitly declared in the BDEF, it is also callable:
*
*   MODIFY ENTITIES OF ydj_r_salesorder
*     ENTITY SalesOrder
*       EXECUTE Resume
*         FROM VALUE #( ( %key-SoKey = c_key ) )
*     REPORTED DATA(resume_reported)
*     FAILED   DATA(resume_failed)
*     MAPPED   DATA(resume_mapped).
*
*&---------------------------------------------------------------------*
*& End of file. The draft actions AdditionalSave and Share are not
*& shown: AdditionalSave cannot be executed from EML at all - not with
*& IN LOCAL MODE and not from its own behavior pool - and Share belongs
*& to collaborative draft handling, which this note does not cover.
*&---------------------------------------------------------------------*
