*&---------------------------------------------------------------------*
*& Report YDJ_CDS_ANNOTATION_DEMO
*&
*& CDS annotations: what is ACTUALLY stored and active, as opposed to
*& what the data definition says.
*&
*& Reads the element annotations of the SAP-delivered demo CDS entities
*& with CL_DD_DDL_ANNOTATION_SERVICE=>GET_ANNOS and shows two things:
*&
*&   1) annotation inheritance from the entity below, and the effect of
*&      @Metadata.ignorePropagatedAnnotations: true
*&      (DEMO_CDS_ANNO_INHERITANCE_1 vs ..._1A, which differ in that
*&       one line only)
*&   2) the same entity read with and without metadata extensions
*&      (DEMO_CDS_MDE), i.e. the MDE override of the view's own source
*& The third trap of the note - a misspelled annotation activates
*& cleanly and is then never read - cannot be shown by a report
*& without creating a CDS entity, so it is only illustrated in the
*& commented DDL below.
*&
*& Read-only. No DDIC object has to be created, nothing is written, no
*& COMMIT WORK. The entities used are the ones referenced by the ABAP
*& keyword documentation (package SABAPDEMOS); if a system does not
*& have the documentation demo content, enter any CDS entity name on
*& the selection screen instead.
*&
*& Notes: CDS Annotations (README.md in this folder)
*& Docs : ABENCDS_ANNOTATIONS_ANALYSIS (evaluation of annotations),
*&        ABENCDS_META_DATA_EXTENSIONS, ABENCDS_F1_ANNOTATE_VIEW,
*&        ABENCDS_SAP_ANNO_PROPS (meaning of the Default column)
*&---------------------------------------------------------------------*
REPORT ydj_cds_annotation_demo.

*&---------------------------------------------------------------------*
*& The CDS artifacts this note is about (separate repository objects
*& in ADT - shown here as comments for readability only).
*&---------------------------------------------------------------------*
*  --- 1) The typo that activates clean -----------------------------
*  @AccessControl.authorizationCheck: #NOT_REQUIRED
*  @EndUserText.lable: 'Flight connections'   " <- lable. No error.
*  @Metadata.allowExtensions                  " <- no value: see below
*  define view entity ydj_flight_anno
*    as select from spfli
*  {
*    key carrid as Carrier,
*    key connid as Connection,
*        cast( distance as abap.dec(9,0) ) as Distance
*                      " '- CAST cuts off annotation inheritance:
*                      "    Distance keeps NO label from s_distance
*  }
*
*  --- 2) The metadata extension that outranks the view -------------
*  @Metadata.layer: #CUSTOMER                 " mandatory
*  @EndUserText.label: 'Flight connections'   " beats the view header
*  annotate entity ydj_flight_anno with
*  {
*    @EndUserText.label: 'Airline'
*    Carrier;
*    @EndUserText.label: 'Flight number'
*    Connection;
*  }
*
*  Prerequisite for 2) is @Metadata.allowExtensions: TRUE in 1).
*  Written bare, as above, the value applied is the properties-table
*  Default (true); omitted entirely, the KTD not-specified value
*  (false) applies and the MDE does not activate. Always write it.
*&---------------------------------------------------------------------*

PARAMETERS:
  p_ent1 TYPE c LENGTH 30 DEFAULT 'DEMO_CDS_ANNO_INHERITANCE_1' LOWER CASE,
  p_ent2 TYPE c LENGTH 30 DEFAULT 'DEMO_CDS_ANNO_INHERITANCE_1A' LOWER CASE,
  p_ent3 TYPE c LENGTH 30 DEFAULT 'DEMO_CDS_MDE' LOWER CASE.

*&---------------------------------------------------------------------*
*& Local helper.
*&
*& The row type returned by GET_ANNOS is not a released API, so the
*& columns are addressed DYNAMICALLY with ASSIGN COMPONENT instead of
*& being named in the source. That keeps this report compilable even
*& if the structure differs between releases: a column that is not
*& there is simply skipped (sy-subrc = 4) rather than being a syntax
*& error.  See the Field Symbols and Dynamic Method Calls notes.
*&---------------------------------------------------------------------*
CLASS lcl_anno DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS show
      IMPORTING
        iv_entity TYPE csequence
        iv_mde    TYPE abap_bool DEFAULT abap_true
        iv_title  TYPE csequence.

  PRIVATE SECTION.

    CLASS-METHODS dump_row
      IMPORTING
        is_row TYPE any.

ENDCLASS.

CLASS lcl_anno IMPLEMENTATION.

  METHOD show.

    DATA lv_entity TYPE c LENGTH 30.

    lv_entity = iv_entity.
    TRANSLATE lv_entity TO UPPER CASE.

    SKIP.
    WRITE: / '===', iv_title.
    WRITE: / '    entity:', lv_entity, ' MDEs considered:', iv_mde.

    TRY.

*       GET_ANNOS merges, in this order: annotations from metadata
*       extensions (by layer), then the annotations of the entity
*       itself - direct, derived (from data elements) and inherited
*       (from the entities and tables it selects from).
        cl_dd_ddl_annotation_service=>get_annos(
          EXPORTING
            entityname         = lv_entity
            metadata_extension = iv_mde
          IMPORTING
            element_annos      = DATA(lt_annos) ).

      CATCH cx_root INTO DATA(lx_error).
*       The exceptions of GET_ANNOS are not documented on the pages
*       this note is based on. A class-based one lands here; a
*       CLASSIC exception would bypass TRY entirely and dump, which
*       is the trap already written up in the Runtime Type Services
*       note. Verify in SE24 before relying on this guard.
        DATA(lv_text) = lx_error->get_text( ).
        WRITE: / '    exception:', lv_text.
        RETURN.
    ENDTRY.

    DATA(lv_count) = lines( lt_annos ).
    WRITE: / '    element annotations found:', lv_count.

    IF lv_count = 0.
      WRITE: / '    (entity not found, or it carries no element',
               'annotations at all)'.
      RETURN.
    ENDIF.

    LOOP AT lt_annos ASSIGNING FIELD-SYMBOL(<ls_row>).
      dump_row( <ls_row> ).
    ENDLOOP.

  ENDMETHOD.

  METHOD dump_row.

*   Candidate column names, resolved one by one at runtime. The two
*   interesting ones are the source columns: SOURCEOBJECT names the
*   object an INHERITED annotation came from, SOURCEDDLX names the
*   metadata extension an OVERRIDDEN one came from. If both are
*   blank, the annotation is written in the entity itself.
    DATA(lt_cols) = VALUE string_table(
      ( `ELEMENTNAME` )
      ( `ANNONAME` )
      ( `NAME` )
      ( `VALUE` )
      ( `SOURCEOBJECT` )
      ( `SOURCEDDLX` ) ).

    DATA lv_line TYPE string.
    DATA lv_val  TYPE string.

    LOOP AT lt_cols INTO DATA(lv_col).

      ASSIGN COMPONENT lv_col OF STRUCTURE is_row TO FIELD-SYMBOL(<lv_val>).

      IF sy-subrc <> 0.
*       Column does not exist in this release: skip it silently.
        CONTINUE.
      ENDIF.

*     Plain assignment, not CONV: <lv_val> is GENERICALLY typed
*     (ASSIGN COMPONENT), so the conversion has to be decided at
*     runtime by the assignment, not at compile time by CONV.
      lv_val = <lv_val>.
      CONDENSE lv_val.

      IF lv_val IS INITIAL.
        CONTINUE.
      ENDIF.

      IF lv_line IS INITIAL.
        lv_line = |{ lv_col }={ lv_val }|.
      ELSE.
        lv_line = |{ lv_line }  { lv_col }={ lv_val }|.
      ENDIF.

    ENDLOOP.

    WRITE: / '      ', lv_line.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
START-OF-SELECTION.
*&---------------------------------------------------------------------*

  WRITE: / 'CDS annotations: what is stored and active'.
  WRITE: / '(every read below is read-only)'.

* Part 1 - inheritance on, inheritance off. The only difference between
*    these two SAP demo entities is the header annotation
*    @Metadata.ignorePropagatedAnnotations: true in the second one.
*    Expect the second list to be the shorter one, and the label
*    inherited from DEMO_CDS_ANNO_INHERITANCE_2 to be missing.
  lcl_anno=>show( iv_entity = p_ent1
                  iv_title  = '1) inheritance ON (annotation omitted)' ).

  lcl_anno=>show( iv_entity = p_ent2
                  iv_title  = '2) @Metadata.ignorePropagatedAnnotations: true' ).

* Part 2 - the same entity, read without and with its metadata extensions.
*    Whatever changes between the two lists is metadata that is NOT
*    in the data definition, and that nothing except
*    CL_DD_DDL_ANNOTATION_SERVICE will ever show you.
  lcl_anno=>show( iv_entity = p_ent3
                  iv_mde    = abap_false
                  iv_title  = '3) entity source only (MDEs ignored)' ).

  lcl_anno=>show( iv_entity = p_ent3
                  iv_mde    = abap_true
                  iv_title  = '4) merged with metadata extensions' ).

*&---------------------------------------------------------------------*
*& Deliberately NOT done here:
*&
*&   CL_DD_DDL_ANALYZE=>GET_ANNOTATIONS( ... )
*&     -> reads the DDL source code only. It ignores metadata
*&        extensions, derived and inherited annotations, and the
*&        translations - so it is the wrong tool for the question
*&        "which annotation is active on this field", and the right
*&        one for "what does this source text say".
*&
*&   CL_DD_DDL_ANNOTATION_SERVICE=>GET_DIRECT_ANNOS_...( ... )
*&     -> the documented exception: direct annotations only, no
*&        metadata extensions.
*&
*&   SELECT ... FROM ddfieldanno / ddheadanno / ddparameteranno
*&     -> the internal metadata tables the annotations end up in.
*&        Readable, and used by the SAP demo class, but the merge
*&        rules (layers, inheritance, null filtering) are not in the
*&        tables - they are in the API. Use the API.
*&---------------------------------------------------------------------*
