*&---------------------------------------------------------------------*
*& Report YDJ_HTTP_CLIENT_DEMO
*&---------------------------------------------------------------------*
*& Outbound HTTP with the classic ICF client (CL_HTTP_CLIENT) - the
*& three error layers that have to be checked separately, and the
*& defaults that are not what the surrounding code assumes.
*&
*&   1. THREE LAYERS   -> create, then send/receive, then the HTTP
*&                        status are three INDEPENDENT failure modes.
*&                        sy-subrc covers the first two only. A 404 or
*&                        a 500 leaves sy-subrc = 0.
*&   2. NEVER  < 0     -> the published SAP sample writes
*&                        IF sy-subrc < 0 after send( ), which can
*&                        never be true, so it swallows every send
*&                        failure. Every check below is <> 0.
*&   3. METHOD DEFAULT -> with no set_method( ) the verb is GET if the
*&                        request has no body and POST if it has one.
*&                        Both are set explicitly here.
*&   4. POPUP OFF      -> propertytype_logon_popup is documented with
*&                        default CO_ENABLED, and a background work
*&                        process has no SAP GUI to display it.
*&   5. ONE CLOSE      -> every exit path goes through close( ).
*&
*& Read-only: one GET, then the status line, two response headers and
*& the first 400 characters of the body. No database access and no
*& COMMIT WORK - but the HTTP call itself IS an implicit database
*& commit, so this logic must never sit inside a SELECT loop or
*& between OPEN CURSOR and FETCH.
*&
*& Needs outbound HTTP to be reachable (see the SICF proxy settings).
*&---------------------------------------------------------------------*
REPORT ydj_http_client_demo.

PARAMETERS: p_url(128) TYPE c LOWER CASE
                       DEFAULT 'http://www.sap.com/index.html',
            p_tout     TYPE i DEFAULT 30.

CLASS lcl_demo DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS run IMPORTING iv_url     TYPE string
                                iv_timeout TYPE i.
  PRIVATE SECTION.
    CLASS-METHODS create_failed IMPORTING iv_subrc TYPE i.
    CLASS-METHODS last_error    IMPORTING io_client TYPE REF TO if_http_client
                                          iv_step   TYPE string
                                          iv_subrc  TYPE i.
    CLASS-METHODS dump_response IMPORTING io_client TYPE REF TO if_http_client.
ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

  METHOD run.
    DATA lo_client TYPE REF TO if_http_client.
    DATA lv_code   TYPE i.
    DATA lv_reason TYPE string.

*   LAYER 1 - create. Nothing has been sent yet, so a failure here is
*   purely local: an unparsable URL, HTTP not active in this system,
*   or - with create_by_destination - a missing S_ICF authorization,
*   which arrives as destination_no_authority and NOT as a remote 403.
    cl_http_client=>create_by_url(
      EXPORTING  url                = iv_url
      IMPORTING  client             = lo_client
      EXCEPTIONS argument_not_found = 1
                 plugin_not_active  = 2
                 internal_error     = 3
                 OTHERS             = 4 ).
    IF sy-subrc <> 0.
      create_failed( sy-subrc ).
      RETURN.
    ENDIF.

*   Documented default is CO_ENABLED. In a background job there is
*   nobody to click the logon screen, so a credentials problem that
*   shows a popup in SE38 becomes an authentication failure in batch.
    lo_client->propertytype_logon_popup = if_http_client=>co_disabled.

*   Also CO_ENABLED by default: redirects are followed silently, and
*   then the status code read below is the one from the LAST hop.
    lo_client->propertytype_redirect = if_http_client=>co_disabled.

*   Say the verb and the protocol version out loud.
    lo_client->request->set_method( if_http_request=>co_request_method_get ).
    lo_client->request->set_version( if_http_request=>co_protocol_version_1_1 ).

*   LAYER 2a - send. The timeout is in SECONDS.
    lo_client->send(
      EXPORTING  timeout                    = iv_timeout
      EXCEPTIONS http_communication_failure = 1
                 http_invalid_state         = 2
                 http_processing_failed     = 3
                 OTHERS                     = 4 ).
    IF sy-subrc <> 0.
      last_error( io_client = lo_client iv_step = 'send' iv_subrc = sy-subrc ).
      lo_client->close( ).
      RETURN.
    ENDIF.

*   LAYER 2b - receive. Mandatory for every request, even when the
*   body is of no interest: without it the response object stays empty.
    lo_client->receive(
      EXCEPTIONS http_communication_failure = 1
                 http_invalid_state         = 2
                 http_processing_failed     = 3
                 OTHERS                     = 4 ).
    IF sy-subrc <> 0.
      last_error( io_client = lo_client iv_step = 'receive' iv_subrc = sy-subrc ).
      lo_client->close( ).
      RETURN.
    ENDIF.

*   LAYER 3 - the HTTP status. sy-subrc is 0 here even when the server
*   answered 404 or 500, because the conversation itself succeeded.
    lo_client->response->get_status( IMPORTING code   = lv_code
                                               reason = lv_reason ).
    WRITE: / 'sy-subrc after receive :', sy-subrc.
    WRITE: / 'HTTP status code       :', lv_code.
    WRITE: / 'HTTP reason phrase     :', lv_reason.
    IF lv_code < 200 OR lv_code >= 300.
      WRITE: / 'The CALL succeeded and the REQUEST failed - this is the'.
      WRITE: / 'case that sy-subrc alone cannot see.'.
    ENDIF.

    dump_response( lo_client ).
    lo_client->close( ).
  ENDMETHOD.

  METHOD create_failed.
    WRITE: / 'create_by_url failed, sy-subrc =', iv_subrc.
    CASE iv_subrc.
      WHEN 1.
        WRITE: / '  argument_not_found - the URL could not be parsed'.
      WHEN 2.
        WRITE: / '  plugin_not_active  - HTTP is not active here'.
      WHEN 3.
        WRITE: / '  internal_error'.
      WHEN OTHERS.
        WRITE: / '  unexpected return code'.
    ENDCASE.
  ENDMETHOD.

  METHOD last_error.
*   sy-subrc is passed IN, because get_last_error( ) below is itself a
*   method call and the caller value must not be read after it.
    DATA lv_code TYPE sysubrc.
    DATA lv_msg  TYPE string.

    io_client->get_last_error( IMPORTING code    = lv_code
                                         message = lv_msg ).
    WRITE: / 'communication failure at step', iv_step.
    WRITE: / '  sy-subrc :', iv_subrc.
    WRITE: / '  code     :', lv_code.
    WRITE: / '  message  :', lv_msg.
  ENDMETHOD.

  METHOD dump_response.
    DATA lv_ctype TYPE string.
    DATA lv_clen  TYPE string.
    DATA lv_body  TYPE string.
    DATA lv_head  TYPE string.
    DATA lv_size  TYPE i.

    lv_ctype = io_client->response->get_header_field( name = 'content-type' ).
    lv_clen  = io_client->response->get_header_field( name = 'content-length' ).
    WRITE: / 'content-type           :', lv_ctype.
    WRITE: / 'content-length         :', lv_clen.

*   get_cdata( ) hands back the body as a string, converted from the
*   code page the server announced. get_data( ) hands back the raw
*   xstring and is the only correct choice for anything not text.
    lv_body = io_client->response->get_cdata( ).
    lv_size = strlen( lv_body ).
    WRITE: / 'body characters        :', lv_size.

    IF lv_size > 400.
      lv_head = lv_body(400).
    ELSE.
      lv_head = lv_body.
    ENDIF.
    SKIP.
    WRITE: / lv_head.
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  DATA gv_url TYPE string.

  gv_url = p_url.
  CONDENSE gv_url.
  IF gv_url IS INITIAL.
    WRITE: / 'No URL supplied.'.
    RETURN.
  ENDIF.

  WRITE: / 'Requesting:', gv_url.
  SKIP.
  lcl_demo=>run( iv_url = gv_url iv_timeout = p_tout ).

*&---------------------------------------------------------------------*
*& WHAT NOT TO DO - kept as comments on purpose.
*&---------------------------------------------------------------------*
*& (a) The condition from the published SAP sample. sy-subrc is never
*&     negative, so the whole error branch is unreachable and a failed
*&     send is reported as success:
*&
*&        lo_client->send( EXCEPTIONS OTHERS = 4 ).
*&        IF sy-subrc < 0.          " never true
*&          ...error handling...    " never runs
*&        ENDIF.
*&
*& (b) Reading the status only when the transport failed. These two
*&     checks answer different questions and both are needed:
*&
*&        lo_client->receive( EXCEPTIONS OTHERS = 4 ).
*&        IF sy-subrc <> 0.
*&          lo_client->response->get_status( ... ).
*&        ENDIF.
*&
*& (c) Calling out once per row from inside a database loop. The HTTP
*&     call is an implicit database commit, which closes the cursor;
*&     the dump arrives at the next fetch as DBSQL_INVALID_CURSOR:
*&
*&        SELECT ... INTO ... FROM ... .
*&          lcl_demo=>run( ... ).
*&        ENDSELECT.
*&
*&     Collect the keys into an internal table first, then loop over
*&     the table and call out.
*&---------------------------------------------------------------------*
