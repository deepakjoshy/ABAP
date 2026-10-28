*&---------------------------------------------------------------------*
*& Report YDJ_BCS_MAIL_DEMO
*&---------------------------------------------------------------------*
*& The three email traps that can be proved without sending anything,
*& plus a complete send request that stops short of sending.
*&
*& This report performs NO database access. SEND and COMMIT WORK run
*& ONLY if P_SEND is ticked, so the default run is side-effect free.
*&
*&   1. THE SUBJECT IS A DDIC FIELD -> I_SUBJECT of CREATE_DOCUMENT is
*&                       typed SO_OBJ_DES, documented as "maximum
*&                       length 50". A longer subject is truncated on
*&                       assignment: no sy-subrc, no message. The long
*&                       subject belongs on the REQUEST instead, via
*&                       SET_MESSAGE_SUBJECT (255 chars, SMTP only).
*&   2. SOLI_TAB IS TWO FORMATS   -> a line-oriented table (one row =
*&                       one mail line) and a running-text table (255-
*&                       character chunks of one stream) have the SAME
*&                       type. Part 2 builds both from the same text
*&                       and prints the row counts side by side.
*&   3. SOLIX PADS THE LAST ROW   -> a 255-byte table cannot express
*&                       its own length, so the real byte count comes
*&                       back separately as EV_SIZE. That value is what
*&                       I_ATTACHMENT_SIZE wants; omit it and the
*&                       padding travels as part of the file.
*&   4. THE REQUEST, UNSENT      -> builds document, subject, recipient
*&                       and request in the documented order, then
*&                       stops. ADD_RECIPIENT, not SET_RECIPIENT: the
*&                       latter appears in the SAP process documentation
*&                       and does not exist in CL_BCS.
*&
*& Notes:
*&   - CL_BCS_CONVERT exists as of SAP_BASIS 7.00 EHP2. On an older
*&     system parts 2 and 3 do not compile; the README explains the
*&     same points without it.
*&   - COMMIT WORK below is correct for a report. The same code called
*&     IN the update task must NOT commit - see the README.
*&---------------------------------------------------------------------*
REPORT ydj_bcs_mail_demo.

PARAMETERS p_to   TYPE ad_smtpadr LOWER CASE
                                  DEFAULT 'nobody@example.com'.
PARAMETERS p_send AS CHECKBOX     DEFAULT space.

*&---------------------------------------------------------------------*
CLASS lcl_demo DEFINITION FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS run
      IMPORTING
        iv_to   TYPE ad_smtpadr
        iv_send TYPE abap_bool.

  PRIVATE SECTION.
    CLASS-METHODS head
      IMPORTING iv_text TYPE string.

    CLASS-METHODS subject_truncation.
    CLASS-METHODS text_formats.
    CLASS-METHODS binary_padding.
    CLASS-METHODS build_request
      IMPORTING
        iv_to   TYPE ad_smtpadr
        iv_send TYPE abap_bool.

ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

  METHOD run.
    subject_truncation( ).
    text_formats( ).
    binary_padding( ).
    build_request( iv_to = iv_to iv_send = iv_send ).
  ENDMETHOD.

  METHOD head.
    SKIP.
    WRITE: / iv_text.
    ULINE.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& 1. The subject is a 50-character DDIC field, not a string.
*&---------------------------------------------------------------------*
  METHOD subject_truncation.

    DATA lv_doc_title TYPE so_obj_des.      "<- I_SUBJECT of the document

    head( '1. SO_OBJ_DES truncates the subject at 50 characters' ).

    DATA(lv_wanted) =
      CONV string(
        'Order 4711 could not be posted - credit limit exceeded' ).

    lv_doc_title = lv_wanted.               "<- silent truncation here

    DATA(lv_len_wanted) = strlen( lv_wanted ).
    DATA(lv_len_title)  = strlen( lv_doc_title ).
    DATA(lv_arrived)    = CONV string( lv_doc_title ).

    WRITE: /  'wanted   :', lv_wanted.
    WRITE: /  'length   :', lv_len_wanted.
    WRITE: /  'arrived  :', lv_arrived.
    WRITE: /  'length   :', lv_len_title.

    IF lv_arrived = lv_wanted.
      WRITE: / 'The subject survived - it was short enough.'.
    ELSE.
      WRITE: / 'Truncated. The assignment raises nothing and sets',
               'no return code - there is nothing to check.'.
      WRITE: / 'Put the long text on the REQUEST with',
               'SET_MESSAGE_SUBJECT instead (255 chars, SMTP nodes only).'.
    ENDIF.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& 2. One type, two formats: line-oriented SOLI vs running-text SOLI.
*&---------------------------------------------------------------------*
  METHOD text_formats.

    DATA lt_line_oriented TYPE soli_tab.    "<- what a RAW body needs

    head( '2. SOLI_TAB: line-oriented vs running text' ).

*   The line-oriented form: one APPEND is one line of the mail.
    APPEND 'Order 4711 could not be posted.' TO lt_line_oriented.
    APPEND 'Please check the application log.' TO lt_line_oriented.

*   The same content as ONE string, converted by CL_BCS_CONVERT. Its own
*   short text calls the result "Running Text (SOLI)" - same type, other
*   meaning: the rows are 255-character chunks, not lines.
    DATA(lv_stream) = |Order 4711 could not be posted.|
                   && cl_abap_char_utilities=>cr_lf
                   && |Please check the application log.|.

    DATA(lt_running) = cl_bcs_convert=>string_to_soli(
                           iv_string = lv_stream ).

    DATA(lv_rows_lines)   = lines( lt_line_oriented ).
    DATA(lv_rows_running) = lines( lt_running ).

    WRITE: / 'line-oriented rows:', lv_rows_lines,
             '(2 lines of mail)'.
    WRITE: / 'running-text rows :', lv_rows_running,
             '(the SAME two lines, in one row)'.

*   Now a long stream, to show where the chunk boundary falls.
    DATA(lv_long) = repeat( val = `word ` occ = 120 ).
    DATA(lt_chunks) = cl_bcs_convert=>string_to_soli(
                          iv_string = lv_long ).
    DATA(lv_rows_chunks) = lines( lt_chunks ).
    DATA(lv_len_long)    = strlen( lv_long ).

    WRITE: / 'a', lv_len_long, 'character stream becomes',
             lv_rows_chunks, 'rows of 255'.

    LOOP AT lt_chunks INTO DATA(ls_chunk).
      DATA(lv_tail) = ls_chunk-line+245(10).
      WRITE: / '  row', sy-tabix, 'ends with:', lv_tail.
    ENDLOOP.

    WRITE: / 'Feeding that into CREATE_DOCUMENT as a RAW body makes',
             'every chunk a line of the mail - mid-word.'.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& 3. SOLIX pads: the table cannot express the length of its content.
*&---------------------------------------------------------------------*
  METHOD binary_padding.

    DATA lt_solix TYPE solix_tab.
    DATA lv_size  TYPE so_obj_len.          "<- I_ATTACHMENT_SIZE wants this

    head( '3. SOLIX_TAB pads the last row - EV_SIZE is the real length' ).

    DATA(lv_csv) = |matnr;werks;menge|
                && cl_abap_char_utilities=>cr_lf
                && |4711;1000;12,500|.

    cl_bcs_convert=>string_to_solix(
      EXPORTING
        iv_string   = lv_csv
        iv_codepage = '4110'               "<- SAP codepage for UTF-8
        iv_add_bom  = abap_true            "<- or Excel mangles it
      IMPORTING
        et_solix    = lt_solix
        ev_size     = lv_size ).

    DATA(lv_rows)    = lines( lt_solix ).
    DATA(lv_capacity) = lv_rows * 255.
    DATA(lv_padding)  = lv_capacity - lv_size.

    WRITE: / 'rows in the table :', lv_rows.
    WRITE: / 'bytes they can hold:', lv_capacity.
    WRITE: / 'EV_SIZE (real bytes):', lv_size.
    WRITE: / 'padding             :', lv_padding, 'bytes'.

    WRITE: / 'Pass EV_SIZE as I_ATTACHMENT_SIZE. Leave it out and those',
             lv_padding, 'bytes are part of the attachment.'.
    WRITE: / 'IV_ADD_BOM puts three more bytes in the table before the',
             'first field - see the File Interface note.'.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& 4. A complete send request that stops before sending.
*&---------------------------------------------------------------------*
  METHOD build_request.

    DATA lt_body TYPE soli_tab.

    head( '4. The send request, built in full' ).

    TRY.
        DATA(lo_request) = cl_bcs=>create_persistent( ).

        APPEND 'Order 4711 could not be posted.' TO lt_body.
        APPEND 'Please check the application log.' TO lt_body.

        DATA(lo_document) = cl_document_bcs=>create_document(
            i_type    = 'RAW'
            i_text    = lt_body
            i_subject = 'Order 4711 not posted' ).

        lo_request->set_document( lo_document ).

*       The 255-character subject, on the request, for SMTP nodes.
        lo_request->set_message_subject(
            'Order 4711 could not be posted - credit limit exceeded' ).

*       ADD_RECIPIENT. SET_RECIPIENT is in the SAP process documentation
*       and is not a method of CL_BCS.
        DATA(lo_recipient) = cl_cam_address_bcs=>create_internet_address(
            i_address_string = iv_to
            i_address_name   = 'Order processing' ).

        lo_request->add_recipient( i_recipient = lo_recipient ).

        WRITE: / 'request, document, subject and recipient are set.'.
        WRITE: / 'recipient:', iv_to.

        IF iv_send = abap_false.
          WRITE: / 'P_SEND is not ticked: SEND and COMMIT WORK skipped.'.
          WRITE: / 'Nothing was sent and nothing was written to the',
                   'database - CREATE_PERSISTENT alone persists nothing.'.
          RETURN.
        ENDIF.

        DATA(lv_sent) = lo_request->send( ).

*       Correct in a report. Forbidden if this runs in the update task.
        COMMIT WORK.

        IF lv_sent = abap_true.
          WRITE: / 'SEND returned abap_true: the request was accepted.'.
          WRITE: / 'That is not delivery. Check SOST for the status and',
                   'SCOT for whether the send process is scheduled.'.
        ELSE.
          WRITE: / 'SEND returned abap_false. No exception was raised,',
                   'so this is the only sign that nothing went out.'.
        ENDIF.

      CATCH cx_bcs INTO DATA(lx_bcs).   "<- CX_BCS is their superclass
        DATA(lv_msg) = lx_bcs->get_text( ).
        WRITE: / 'BCS exception:', lv_msg.
    ENDTRY.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
START-OF-SELECTION.
  lcl_demo=>run( iv_to   = p_to
                 iv_send = p_send ).

