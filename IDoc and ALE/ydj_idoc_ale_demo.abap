*&---------------------------------------------------------------------*
*& Report YDJ_IDOC_ALE_DEMO
*&---------------------------------------------------------------------*
*& IDoc programming traps that are silent at the call site.
*&
*& This report performs NO database access and sends NO IDoc. Every
*& outbound / inbound framework call is commented out; what runs is
*& pure in-memory arithmetic on the two things that actually bite:
*& the positional 1000-character SDATA field, and the fact that every
*& field in an IDoc is character-like.
*&
*&   1. SDATA IS POSITIONAL -> a segment is mapped to SDATA by
*&                             assigning the field string. Nothing in
*&                             the payload names a field. INSERTING a
*&                             field in the middle of a segment shifts
*&                             every byte after it; APPENDING one does
*&                             not. Part 1 packs with the old layout
*&                             and unpacks with both new layouts.
*&   2. BLANK IS NOT INITIAL -> an empty date in an IDoc is eight
*&                             blanks. Copied into a type d field it
*&                             "remains blank and is not initial (does
*&                             not contain zeros)", so every
*&                             IS INITIAL default branch is skipped
*&                             and the value fails much later.
*&   3. NO IDOC, NO ERROR  -> if no receiver was passed and the
*&                             distribution model finds none, ALE
*&                             raises NO exception. The only evidence
*&                             is an empty COMMUNICATION_IDOC_CONTROL.
*&                             Part 3 runs both code paths.
*&   4. SLASH MEANS SKIP   -> for reduced message types a field
*&                             containing '/' is NOT overwritten in
*&                             the receiver. A legitimate slash in
*&                             data silently suppresses an update.
*&
*& Inbound rules that cannot be demonstrated in a report, because they
*& are properties of the ALE layer calling you (see README):
*&   - the inbound function module must NOT issue COMMIT WORK;
*&   - its global variables still hold the PREVIOUS IDoc's values,
*&     because it is called more than once per run;
*&   - status 53 belongs only in the branch where the document exists.
*&---------------------------------------------------------------------*
REPORT ydj_idoc_ale_demo.

*----------------------------------------------------------------------*
* Segment layouts. Real IDoc segment fields are ALWAYS character-like:
* SDATA is a 1000-byte character field, so there are no dates, packed
* numbers or booleans in an IDoc - only characters that look like them.
*----------------------------------------------------------------------*
TYPES: BEGIN OF lty_seg_v1,
         belnr TYPE c LENGTH 10,
         matnr TYPE c LENGTH 18,
         menge TYPE c LENGTH 13,
         bldat TYPE c LENGTH 8,
       END OF lty_seg_v1.

" WRONG extension: WERKS inserted after BELNR
TYPES: BEGIN OF lty_seg_v2_inserted,
         belnr TYPE c LENGTH 10,
         werks TYPE c LENGTH 4,
         matnr TYPE c LENGTH 18,
         menge TYPE c LENGTH 13,
         bldat TYPE c LENGTH 8,
       END OF lty_seg_v2_inserted.

" RIGHT extension: WERKS appended at the end
TYPES: BEGIN OF lty_seg_v2_appended,
         belnr TYPE c LENGTH 10,
         matnr TYPE c LENGTH 18,
         menge TYPE c LENGTH 13,
         bldat TYPE c LENGTH 8,
         werks TYPE c LENGTH 4,
       END OF lty_seg_v2_appended.

TYPES lty_sdata TYPE c LENGTH 1000.   " EDIDD-SDATA

CLASS lcl_demo DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS: positional_sdata,
                   blank_date,
                   empty_return_table,
                   slash_sentinel.
ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

*----------------------------------------------------------------------*
* 1. SDATA is positional: insert vs append
*----------------------------------------------------------------------*
  METHOD positional_sdata.

    DATA ls_v1       TYPE lty_seg_v1.
    DATA ls_inserted TYPE lty_seg_v2_inserted.
    DATA ls_appended TYPE lty_seg_v2_appended.
    DATA lv_sdata    TYPE lty_sdata.

    " the sender still builds the OLD layout
    ls_v1-belnr = '4500001234'.
    ls_v1-matnr = 'PUMP-000000000017'.
    ls_v1-menge = '0000000000100'.
    ls_v1-bldat = '20261023'.

    lv_sdata = ls_v1.          " this is the whole mapping: SEGNAM + SDATA

    " the receiver was regenerated with a field INSERTED in the middle
    ls_inserted = lv_sdata.

    " ... and with the same field APPENDED at the end
    ls_appended = lv_sdata.

    WRITE: / '1. SDATA IS POSITIONAL'.
    WRITE: / '   sent (v1)      belnr =', ls_v1-belnr,
           /  '                  matnr =', ls_v1-matnr,
           /  '                  menge =', ls_v1-menge.
    WRITE: / '   WERKS inserted belnr =', ls_inserted-belnr,
           /  '                  werks =', ls_inserted-werks,
           /  '                  matnr =', ls_inserted-matnr,
           /  '                  menge =', ls_inserted-menge.
    WRITE: / '   WERKS appended belnr =', ls_appended-belnr,
           /  '                  matnr =', ls_appended-matnr,
           /  '                  menge =', ls_appended-menge,
           /  '                  werks =', ls_appended-werks.
    WRITE: / '   -> inserting a field shifts every byte after it. The',
           /  '      payload names nothing, so nothing complains:',
           /  '      material and quantity simply decode as garbage.',
           /  '      Appending is the only safe way to grow a segment.',
           /  '      Ceiling is 1000 characters - then a new segment.'.
    SKIP.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 2. An empty date field is blanks, and blanks are not initial
*----------------------------------------------------------------------*
  METHOD blank_date.

    DATA lv_idoc_date TYPE c LENGTH 8.      " the segment field
    DATA lv_unguarded TYPE d.
    DATA lv_guarded   TYPE d.
    DATA lv_shown     TYPE c LENGTH 8.
    DATA lv_flag      TYPE c LENGTH 3.

    CLEAR lv_idoc_date.                     " the IDoc field arrives empty

    " the natural one-liner
    lv_unguarded = lv_idoc_date.

    " the documented guard: clear the target when the IDoc field is empty
    IF lv_idoc_date IS INITIAL.
      CLEAR lv_guarded.
    ELSE.
      lv_guarded = lv_idoc_date.
    ENDIF.

    WRITE: / '2. BLANK IS NOT INITIAL'.

    lv_shown = lv_unguarded.
    IF lv_unguarded IS INITIAL.
      lv_flag = 'yes'.
    ELSE.
      lv_flag = 'NO '.
    ENDIF.
    WRITE: / '   unguarded  content = >', lv_shown, '<  IS INITIAL =', lv_flag.

    lv_shown = lv_guarded.
    IF lv_guarded IS INITIAL.
      lv_flag = 'yes'.
    ELSE.
      lv_flag = 'NO '.
    ENDIF.
    WRITE: / '   guarded    content = >', lv_shown, '<  IS INITIAL =', lv_flag.

    WRITE: / '   -> per the SAP doc the unguarded date remains blank',
           /  '      and is not initial - it does not contain zeros - so',
           /  '      the IS INITIAL default branch never runs and the',
           /  '      invalid value surfaces far away from the IDoc.',
           /  '      One CLEAR per date field is the entire fix.'.
    SKIP.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 3. The outbound call that creates nothing and raises nothing
*----------------------------------------------------------------------*
  METHOD empty_return_table.

    " EDIDC in a real program; a local shape keeps this report
    " runnable without touching the IDoc tables.
    TYPES: BEGIN OF lty_comm_control,
             docnum TYPE c LENGTH 16,
             status TYPE c LENGTH 2,
           END OF lty_comm_control.

    DATA lt_comm_control TYPE STANDARD TABLE OF lty_comm_control
                              WITH EMPTY KEY.
    DATA lv_rows         TYPE i.

*   CALL FUNCTION 'MASTER_IDOC_DISTRIBUTE'
*     EXPORTING  master_idoc_control            = ls_idoc_control
*     TABLES     communication_idoc_control     = lt_comm_control
*                master_idoc_data               = lt_idoc_data
*     EXCEPTIONS error_in_idoc_control          = 1
*                error_writing_idoc_status      = 2
*                error_in_idoc_data             = 3
*                sending_logical_system_unknown = 4
*                OTHERS                         = 5.
*   IF sy-subrc <> 0.        " <- diligent, and blind to the usual failure
*     ...
*   ENDIF.
*   COMMIT WORK.             " <- mandatory; end of transaction is NOT enough

    " no receiver passed + no receiver in the distribution model
    " = no exception, no IDoc, and this table left empty
    CLEAR lt_comm_control.
    lv_rows = lines( lt_comm_control ).

    WRITE: / '3. NO IDOC, NO ERROR'.
    WRITE: / '   documented case: the call returned sy-subrc = 0'.
    WRITE: / '   rows in COMMUNICATION_IDOC_CONTROL =', lv_rows.

    IF lt_comm_control IS INITIAL.
      WRITE: / '   guarded path   : no IDoc was created - raise/log it'.
    ELSE.
      WRITE: / '   guarded path   : IDoc(s) created'.
    ENDIF.
    WRITE: / '   unguarded path : logs distribution finished OK'.
    WRITE: / '   -> the doc is explicit: with an initial receiver and no',
           /  '      match in the model, an exception is not issued, and',
           /  '      if this table is empty, no IDoc was created.',
           /  '      An unmaintained BD64 model is therefore a silent',
           /  '      dead interface, not an error.'.
    SKIP.

  ENDMETHOD.

*----------------------------------------------------------------------*
* 4. '/' in a field of a reduced message type means "do not overwrite"
*----------------------------------------------------------------------*
  METHOD slash_sentinel.

    TYPES: BEGIN OF lty_field,
             name  TYPE c LENGTH 10,
             value TYPE c LENGTH 12,
           END OF lty_field.

    DATA lt_field TYPE STANDARD TABLE OF lty_field WITH EMPTY KEY.
    DATA ls_field TYPE lty_field.
    DATA lv_effect TYPE c LENGTH 30.

    ls_field-name = 'NAME1'.     ls_field-value = 'ACME GmbH'.   APPEND ls_field TO lt_field.
    ls_field-name = 'ORT01'.     ls_field-value = '/'.           APPEND ls_field TO lt_field.
    ls_field-name = 'STRAS'.     ls_field-value = ' '.           APPEND ls_field TO lt_field.
    ls_field-name = 'REGIO'.     ls_field-value = 'A/B'.         APPEND ls_field TO lt_field.

    WRITE: / '4. SLASH MEANS SKIP (reduced message types)'.
    LOOP AT lt_field INTO ls_field.
      IF ls_field-value = '/'.
        lv_effect = 'field NOT overwritten'.
      ELSEIF ls_field-value IS INITIAL.
        lv_effect = 'overwritten with blank'.
      ELSE.
        lv_effect = 'overwritten with the value'.
      ENDIF.
      WRITE: / '  ', ls_field-name, '>', ls_field-value, '<', lv_effect.
    ENDLOOP.
    WRITE: / '   -> only a field whose whole content is a slash is',
           /  '      skipped; blank really does clear the receiver field,',
           /  '      and a slash inside a longer value is ordinary data.',
           /  '      Data that is legitimately a lone slash cannot be',
           /  '      sent through a reduced message type at all.'.

  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.

  WRITE: / 'IDoc / ALE: traps that are silent at the call site'.
  WRITE: / '(no database access, no IDoc is created or sent)'.
  SKIP.

  lcl_demo=>positional_sdata( ).
  lcl_demo=>blank_date( ).
  lcl_demo=>empty_return_table( ).
  lcl_demo=>slash_sentinel( ).
