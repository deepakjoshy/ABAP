*&---------------------------------------------------------------------*
*& Report YDJ_CHANGE_DOC_DEMO
*&---------------------------------------------------------------------*
*& The change document (CDHDR / CDPOS) traps that can be proved
*& without an SCDO object and without writing anything.
*&
*& By default this report performs NO database write, NO COMMIT and
*& NO database read. Parts 1-4 work on the ABAP Dictionary and in
*& memory only. Part 5 runs a read-only SELECT on CDHDR and ONLY if
*& P_READ is ticked and P_CLASS is filled.
*&
*& Why there is no write demo: the module that writes a change
*& document is GENERATED per object by program RSSCD000, so its name
*& and signature are system-specific. Inventing one here would be
*& inventing an SAP signature. The verified call template is in the
*& comment block at the end of this report instead.
*&
*&   1. FIVE FLAG VALUES   -> CDPOS-CHNGIND has U, I, J, D, E. The
*&                     data element short text says "(U, I, E, D)"
*&                     and omits J. Part 1 runs both a complete
*&                     CASE and the four-value CASE a developer
*&                     writes from that short text, and shows the
*&                     second one falling through on J.
*&   2. TABKEY ROUND TRIP -> CDPOS-TABKEY is the key fields converted
*&                     to character and concatenated. Part 2 does
*&                     structure -> TABKEY -> structure through the
*&                     two SAP conversion modules in function group
*&                     SCD8 and compares the result, instead of
*&                     computing byte offsets by hand.
*&   3. THE 70 CEILING    -> Part 3 sums the DDIC key length of the
*&                     table and reports whether this table's keys
*&                     land in CDPOS_UID, in which case CDPOS-TABKEY
*&                     holds a GUID rather than a key.
*&   4. THE 254 CEILING   -> VALUE_OLD / VALUE_NEW are CHAR 254.
*&                     Part 4 assigns a 300 character value and
*&                     measures what survives. Nothing is raised.
*&   5. CDHDR-VERSION     -> only with P_READ. Reads up to 20 headers
*&                     for an object class and decodes VERSION, the
*&                     field that says whether CDPOS alone is the
*&                     whole story.
*&
*& Notes:
*&   - describe_by_name and get_ddic_field_list raise CLASSIC
*&     exceptions, so they use CALL METHOD ... EXCEPTIONS and a
*&     sy-subrc check. See this repo's Runtime Type Services note.
*&   - sy-subrc is captured into a local immediately after every
*&     CALL FUNCTION / CALL METHOD.
*&   - strlen( ) and other built-ins are hoisted out of WRITE lists,
*&     per this repo's String Processing note.
*&---------------------------------------------------------------------*
REPORT ydj_change_doc_demo.

PARAMETERS: p_tab   TYPE tabname DEFAULT 'T001' OBLIGATORY,
            p_class TYPE cdhdr-objectclas,
            p_read  AS CHECKBOX DEFAULT space.

*---------------------------------------------------------------------*
CLASS lcl_demo DEFINITION FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS run.

  PRIVATE SECTION.
    CLASS-METHODS:
      part1_five_flag_values,
      part2_tabkey_round_trip,
      part3_the_70_ceiling,
      part4_the_254_ceiling,
      part5_cdhdr_version,

      "! Complete decode - all five domain fixed values.
      decode_full
        IMPORTING iv_chngind     TYPE cdpos-chngind
        RETURNING VALUE(rv_text) TYPE string,

      "! The decode a developer writes from the field's own short
      "! text "Change Type (U, I, E, D)". J is missing.
      decode_from_short_text
        IMPORTING iv_chngind     TYPE cdpos-chngind
        RETURNING VALUE(rv_text) TYPE string,

      decode_version
        IMPORTING iv_version     TYPE cdhdr-version
        RETURNING VALUE(rv_text) TYPE string,

      "! Resolves P_TAB to a structure description, or returns
      "! initial after reporting why.
      struct_for_table
        RETURNING VALUE(ro_struct) TYPE REF TO cl_abap_structdescr.

ENDCLASS.

*---------------------------------------------------------------------*
CLASS lcl_demo IMPLEMENTATION.

  METHOD run.
    part1_five_flag_values( ).
    part2_tabkey_round_trip( ).
    part3_the_70_ceiling( ).
    part4_the_254_ceiling( ).
    part5_cdhdr_version( ).
  ENDMETHOD.

  METHOD decode_full.
    CASE iv_chngind.
      WHEN 'U'. rv_text = 'Update - one item per changed flagged field'.
      WHEN 'I'. rv_text = 'Insert - ONE item for the whole table entry'.
      WHEN 'J'. rv_text = 'Insert with field documentation - one per field'.
      WHEN 'D'. rv_text = 'Delete - ONE item for the whole table entry'.
      WHEN 'E'. rv_text = 'Delete with field documentation - one per field'.
      WHEN OTHERS. rv_text = 'unknown'.
    ENDCASE.
  ENDMETHOD.

  METHOD decode_from_short_text.
    " Written from "Change Type (U, I, E, D)". There is no WHEN 'J'
    " and - the real defect - no WHEN OTHERS either, so an unhandled
    " value returns an empty string rather than announcing itself.
    CASE iv_chngind.
      WHEN 'U'. rv_text = 'Update'.
      WHEN 'I'. rv_text = 'Insert'.
      WHEN 'E'. rv_text = 'Delete (single field documentation)'.
      WHEN 'D'. rv_text = 'Delete'.
    ENDCASE.
  ENDMETHOD.

  METHOD decode_version.
    CASE iv_version.
      WHEN space. rv_text = 'items are entirely in CDPOS'.
      WHEN '1'.   rv_text = 'CDPOS_UID row exists - CDPOS-TABKEY is a GUID'.
      WHEN '2'.   rv_text = 'CDPOS_STR row exists - string values live there'.
      WHEN '3'.   rv_text = 'BOTH CDPOS_UID and CDPOS_STR rows exist'.
      WHEN OTHERS. rv_text = 'undocumented value - check the domain'.
    ENDCASE.
  ENDMETHOD.

  METHOD struct_for_table.

    DATA lo_type TYPE REF TO cl_abap_typedescr.

    " TYPE_NOT_FOUND is a CLASSIC exception: TRY ... CATCH cx_root
    " does NOT intercept it. See Runtime Type Services, section 2.
    CALL METHOD cl_abap_typedescr=>describe_by_name
      EXPORTING  p_name         = p_tab
      RECEIVING  p_descr_ref    = lo_type
      EXCEPTIONS type_not_found = 4.
    DATA(lv_subrc) = sy-subrc.

    IF lv_subrc <> 0.
      WRITE: / '  table/type', p_tab, 'not found, sy-subrc =', lv_subrc.
      RETURN.
    ENDIF.

    " The cast IS class-based, so this one belongs in a TRY.
    TRY.
        ro_struct ?= lo_type.
      CATCH cx_sy_move_cast_error.
        WRITE: / '  ', p_tab, 'is not a structure or table type'.
        CLEAR ro_struct.
    ENDTRY.

  ENDMETHOD.

  METHOD part1_five_flag_values.

    DATA lt_values TYPE STANDARD TABLE OF cdpos-chngind WITH EMPTY KEY.

    WRITE: / '1. CDPOS-CHNGIND has FIVE values, the short text lists four'.
    SKIP.

    lt_values = VALUE #( ( 'U' ) ( 'I' ) ( 'J' ) ( 'D' ) ( 'E' ) ).

    WRITE: / '  flag  complete decode'.
    LOOP AT lt_values INTO DATA(lv_ind).
      DATA(lv_full) = decode_full( lv_ind ).
      WRITE: / '   ', lv_ind, lv_full.
    ENDLOOP.
    SKIP.

    WRITE: / '  flag  decode written from "Change Type (U, I, E, D)"'.
    LOOP AT lt_values INTO lv_ind.
      DATA(lv_short) = decode_from_short_text( lv_ind ).
      IF lv_short IS INITIAL.
        WRITE: / '   ', lv_ind, '<EMPTY> - fell through, no WHEN OTHERS'.
      ELSE.
        WRITE: / '   ', lv_ind, lv_short.
      ENDIF.
    ENDLOOP.
    SKIP.

    WRITE: / '  J is "Insert with field documentation". It appears'.
    WRITE: / '  whenever the SCDO flag "Doc. of Individual Fields at'.
    WRITE: / '  Insertion" is ticked - so the four-value decode works'.
    WRITE: / '  until somebody ticks a checkbox in a later release.'.
    SKIP.

  ENDMETHOD.

  METHOD part2_tabkey_round_trip.

    " CHANGEDOCU_KEY_ANY2CHAR / _CHAR2ANY, function group SCD8.
    " Verified signatures - EV_TABKEY and IV_TABLEKEY are both typed
    " CDPOS_UID-TABKEY (CHAR 254), NOT CDPOS-TABKEY (CHAR 70).
    DATA: lv_tabkey TYPE cdpos_uid-tabkey,
          lr_out    TYPE REF TO data.

    WRITE: / '2. TABKEY round trip through function group SCD8'.
    SKIP.

    DATA(lo_struct) = struct_for_table( ).
    IF lo_struct IS INITIAL.
      SKIP.
      RETURN.
    ENDIF.

    CREATE DATA lr_out TYPE HANDLE lo_struct.
    ASSIGN lr_out->* TO FIELD-SYMBOL(<ls_in>).

    " Fill the client, and the two T001 key fields by name when they
    " are there. Any other table keeps its remaining keys initial -
    " the round trip is still a round trip.
    ASSIGN COMPONENT 'MANDT' OF STRUCTURE <ls_in> TO FIELD-SYMBOL(<lv_f>).
    IF sy-subrc = 0.
      <lv_f> = sy-mandt.
    ENDIF.
    ASSIGN COMPONENT 'BUKRS' OF STRUCTURE <ls_in> TO <lv_f>.
    IF sy-subrc = 0.
      <lv_f> = '1000'.
    ENDIF.

    CALL FUNCTION 'CHANGEDOCU_KEY_ANY2CHAR'
      EXPORTING  iv_struct_in     = <ls_in>
                 iv_tabname       = p_tab
      IMPORTING  ev_tabkey        = lv_tabkey
      EXCEPTIONS tabname_is_empty = 1
                 nametab_error    = 2
                 OTHERS           = 3.
    DATA(lv_subrc) = sy-subrc.

    IF lv_subrc <> 0.
      WRITE: / '  ANY2CHAR failed, sy-subrc =', lv_subrc.
      SKIP.
      RETURN.
    ENDIF.

    DATA(lv_len) = strlen( lv_tabkey ).
    WRITE: / '  structure -> TABKEY ok. TABKEY =', lv_tabkey.
    WRITE: / '  trimmed length                 :', lv_len.

    " ... and back again, into a SECOND structure of the same type.
    DATA lr_back TYPE REF TO data.
    CREATE DATA lr_back TYPE HANDLE lo_struct.
    ASSIGN lr_back->* TO FIELD-SYMBOL(<ls_back>).

    CALL FUNCTION 'CHANGEDOCU_KEY_CHAR2ANY'
      EXPORTING  iv_tablekey      = lv_tabkey
                 iv_tabname       = p_tab
      IMPORTING  es_struct_out    = <ls_back>
      EXCEPTIONS tabname_is_empty = 1
                 nametab_error    = 2
                 OTHERS           = 3.
    lv_subrc = sy-subrc.

    IF lv_subrc <> 0.
      WRITE: / '  CHAR2ANY failed, sy-subrc =', lv_subrc.
      SKIP.
      RETURN.
    ENDIF.

    ASSIGN COMPONENT 'MANDT' OF STRUCTURE <ls_back> TO <lv_f>.
    IF sy-subrc = 0.
      WRITE: / '  TABKEY -> structure ok. MANDT came back as', <lv_f>.
    ENDIF.
    ASSIGN COMPONENT 'BUKRS' OF STRUCTURE <ls_back> TO <lv_f>.
    IF sy-subrc = 0.
      WRITE: / '                          BUKRS came back as', <lv_f>.
    ENDIF.

    " The point of the exercise: no offsets were written down. Adding
    " a key field, or lengthening one, changes the layout and this
    " code does not care. Hard-coded lv_tabkey+3(10) does.
    WRITE: / '  No offsets appear anywhere above. That is the point -'.
    WRITE: / '  the layout is a DDIC fact, so let the DDIC supply it.'.

    " CDPOS-TABKEY is the NARROW one. Round-tripping through it is
    " where a long key quietly loses its tail.
    DATA lv_narrow TYPE cdpos-tabkey.
    lv_narrow = lv_tabkey.
    DATA(lv_nlen) = strlen( lv_narrow ).
    WRITE: / '  same value in a CDPOS-TABKEY field, length  :', lv_nlen.
    SKIP.

  ENDMETHOD.

  METHOD part3_the_70_ceiling.

    DATA lt_ddic TYPE ddfields.

    WRITE: / '3. The 70 character key ceiling'.
    SKIP.

    DATA(lo_struct) = struct_for_table( ).
    IF lo_struct IS INITIAL.
      SKIP.
      RETURN.
    ENDIF.

    " get_ddic_field_list raises the CLASSIC exceptions NOT_FOUND and
    " NO_DDIC_TYPE, which a TRY block would not catch. Rather than
    " handle them, rule them out: a type that is a DDIC type has a
    " DDIC field list. is_ddic_type( ) is a predicative method call.
    IF lo_struct->is_ddic_type( ) = abap_false.
      WRITE: / '  ', p_tab, 'is not a DDIC type, so it has no DDIC'.
      WRITE: / '  field list and no TABKEY to speak of.'.
      SKIP.
      RETURN.
    ENDIF.

    lt_ddic = lo_struct->get_ddic_field_list( ).

    DATA lv_total TYPE i.

    WRITE: / '  key fields of', p_tab, 'in dictionary order:'.
    LOOP AT lt_ddic ASSIGNING FIELD-SYMBOL(<ls_f>) WHERE keyflag = abap_true.
      WRITE: / '   ', <ls_f>-fieldname, <ls_f>-datatype, <ls_f>-leng.
      lv_total = lv_total + <ls_f>-leng.
    ENDLOOP.

    WRITE: / '  summed DDIC key length           :', lv_total.
    WRITE: / '  CDPOS-TABKEY capacity            : 70'.

    IF lv_total > 70.
      WRITE: / '  -> OVER 70. This table''s keys go to CDPOS_UID, and'.
      WRITE: / '     CDPOS-TABKEY holds a 32 character GUID instead of'.
      WRITE: / '     a key. CDHDR-VERSION is then 1 or 3. Offset'.
      WRITE: / '     parsing reads the GUID as a key and succeeds.'.
    ELSE.
      WRITE: / '  -> within 70, so CDPOS-TABKEY holds the real key'.
      WRITE: / '     here. That is a property of THIS table, not a'.
      WRITE: / '     guarantee: a reader must still check VERSION.'.
    ENDIF.

    " Honesty note, and the reason part 2 uses the SAP modules:
    WRITE: / '  Caution: the sum above is the DDIC length. The'.
    WRITE: / '  character length a non-character key field occupies'.
    WRITE: / '  inside TABKEY is type dependent, so treat this as an'.
    WRITE: / '  indicator, not an offset table. Use SCD8 (part 2) or'.
    WRITE: / '  CHANGEDOCU_TABKEYLEN_GET for an exact answer.'.
    SKIP.

  ENDMETHOD.

  METHOD part4_the_254_ceiling.

    DATA lv_stored TYPE cdpos-value_new.

    WRITE: / '4. VALUE_OLD / VALUE_NEW are CHAR 254'.
    SKIP.

    DATA(lv_long)    = repeat( val = 'X' occ = 300 ).
    DATA(lv_long_len) = strlen( lv_long ).

    lv_stored = lv_long.
    DATA(lv_kept) = strlen( lv_stored ).

    DATA(lv_lost) = lv_long_len - lv_kept.

    WRITE: / '  value handed to the framework, length :', lv_long_len.
    WRITE: / '  length that fits in CDPOS-VALUE_NEW   :', lv_kept.
    WRITE: / '  characters lost                       :', lv_lost.

    IF lv_stored = lv_long.
      WRITE: / '  the two are equal'.
    ELSE.
      WRITE: / '  -> the stored value is NOT the value. No exception,'.
      WRITE: / '     no sy-subrc, no truncation warning anywhere.'.
    ENDIF.

    WRITE: / '  A true STRING field is not stored here at all: it'.
    WRITE: / '  goes to CDPOS_STR, and RAWSTRING / SHORTSTRING use'.
    WRITE: / '  their own column pairs there. CDHDR-VERSION = 2 or 3.'.
    SKIP.

  ENDMETHOD.

  METHOD part5_cdhdr_version.

    WRITE: / '5. CDHDR-VERSION, the field most readers never select'.
    SKIP.

    IF p_read <> abap_true.
      WRITE: / '  skipped - tick P_READ and fill P_CLASS to run the'.
      WRITE: / '  read-only SELECT on CDHDR.'.
      SKIP.
      RETURN.
    ENDIF.

    IF p_class IS INITIAL.
      WRITE: / '  P_CLASS is empty, so there is nothing to restrict'.
      WRITE: / '  the read to. Refusing rather than scanning CDHDR.'.
      SKIP.
      RETURN.
    ENDIF.

    " INTO must be the LAST clause in strict mode, with UP TO after
    " it. The older ordering is a syntax error inside a class.
    SELECT objectclas, objectid, changenr, username,
           udate, change_ind, version
      FROM cdhdr
      WHERE objectclas = @p_class
      ORDER BY changenr DESCENDING
      INTO TABLE @DATA(lt_hdr)
      UP TO 20 ROWS.
    DATA(lv_subrc) = sy-subrc.

    IF lv_subrc <> 0 OR lt_hdr IS INITIAL.
      WRITE: / '  no change documents for object class', p_class.
      WRITE: / '  Note: that is NOT proof nothing changed. It can'.
      WRITE: / '  equally mean no caller ever wrote one. See the'.
      WRITE: / '  README, section 1.'.
      SKIP.
      RETURN.
    ENDIF.

    LOOP AT lt_hdr ASSIGNING FIELD-SYMBOL(<ls_h>).
      DATA(lv_ind_txt) = decode_full( <ls_h>-change_ind ).
      DATA(lv_ver_txt) = decode_version( <ls_h>-version ).
      WRITE: / '  ', <ls_h>-changenr, <ls_h>-udate, <ls_h>-username.
      WRITE: / '     objectid   :', <ls_h>-objectid.
      WRITE: / '     CHANGE_IND :', <ls_h>-change_ind, lv_ind_txt.
      WRITE: / '     VERSION    :', <ls_h>-version, lv_ver_txt.
    ENDLOOP.
    SKIP.

  ENDMETHOD.

ENDCLASS.

*---------------------------------------------------------------------*
* The write side, for reference.
*
* The module below is GENERATED by program RSSCD000 from the SCDO
* object, so <OBJECT> and the UPD_<TABLE> / <TABLE> parameter names
* are whatever your object is called. Check the real signature in
* SE37, or SCDO -> Goto -> Generation Info. Do not copy names from
* a blog, including this one.
*
* Parameter names below are the ones that recur in SAP's own
* generated modules and that match the CHANGEDOCUMENT_CLOSE
* signature (OBJECT_CHANGE_INDICATOR, PLANNED_OR_REAL_CHANGES,
* NO_CHANGE_POINTERS, TCODE, USERNAME).
*
*   " 1. OLD image FIRST, while it still exists.
*   SELECT SINGLE * FROM ztable INTO @DATA(ls_old)
*          WHERE id = @lv_id.
*
*   " 2. your own database change
*   ls_new = ls_old.
*   ls_new-city = lv_new_city.
*   MODIFY ztable FROM ls_new.
*
*   " 3. the change document, with BOTH images
*   CALL FUNCTION 'Z<OBJECT>_WRITE_DOCUMENT'
*     EXPORTING objectid                = lv_objectid
*               tcode                   = sy-tcode
*               utime                   = sy-uzeit
*               udate                   = sy-datum
*               username                = sy-uname
*               object_change_indicator = 'U'
*               upd_ztable              = 'U'
*               ztable                  = ls_new      " new image
*               o_ztable                = ls_old.     " old image
*
*   " 4. both halves commit together, or neither does
*   COMMIT WORK.
*
* Without step 4 the registration is discarded and the change
* document is never written - see README section 5. Code already
* running IN the update task must NOT commit.
*
* For the multiple case the images are internal tables and they must
* be sorted by key and free of duplicates, or the document is wrong
* rather than missing - README section 7.
*---------------------------------------------------------------------*

*---------------------------------------------------------------------*
START-OF-SELECTION.
  lcl_demo=>run( ).
