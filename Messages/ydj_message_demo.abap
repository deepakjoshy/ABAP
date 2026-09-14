*&---------------------------------------------------------------------*
*& Report YDJ_MESSAGE_DEMO
*&---------------------------------------------------------------------*
*& MESSAGE: the parts that behave differently from how they read.
*&
*&   1. INTO           -> resolves the text, does NOT interrupt the flow
*&                        and does NOT set sy-subrc. The message type is
*&                        irrelevant with INTO.
*&   2. WITH / 50      -> every operand is formatted with output length
*&                        50, so longer values are silently truncated
*&                        into sy-msgv1 .. sy-msgv4.
*&   3. SURPLUS &      -> passing fewer operands than placeholders
*&                        INITIALIZES the remaining sy-msgv* fields.
*&   4. FREE TEXT      -> MESSAGE 'text' TYPE 'x' sets sy-msgid = '00'
*&                        and sy-msgno = '001', losing the message ID.
*&   5. RAISING        -> acts like RAISE only if the caller assigns a
*&                        return code; otherwise it is IGNORED and the
*&                        message is sent (which in a report terminates).
*&
*& Everything here runs in START-OF-SELECTION, where list processing is
*& active - so note that a type 'W' would already have become 'E', and a
*& type 'E' would TERMINATE this report rather than print anything. That
*& is why only 'S' and INTO are used below.
*&
*& Uses the SAP-delivered message SABAPDEMOS 888, whose short text is
*& four placeholders separated by blanks.
*&---------------------------------------------------------------------*
REPORT ydj_message_demo.

CLASS lcl_message_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      into_does_not_set_subrc,
      with_truncates_at_fifty,
      surplus_placeholders_cleared,
      free_text_loses_the_id,
      raising_needs_a_catcher.

  PRIVATE SECTION.

    " The non-class-based exception that MESSAGE ... RAISING refers to.
    CLASS-METHODS check_input
      EXCEPTIONS invalid_input.

ENDCLASS.


CLASS lcl_message_demo IMPLEMENTATION.

  METHOD into_does_not_set_subrc.

    DATA lt_nums TYPE STANDARD TABLE OF i WITH EMPTY KEY.

    lt_nums = VALUE #( ( 1 ) ( 2 ) ).

    " Deliberately fail a READ so sy-subrc is 4 going in.
    READ TABLE lt_nums INDEX 99 TRANSPORTING NO FIELDS.
    WRITE: / '  sy-subrc after the failed READ :', sy-subrc.

    " MESSAGE ... INTO is text formatting, not a check: it neither
    " interrupts the flow nor touches sy-subrc. The 4 below is still
    " the READ's return code, not the MESSAGE's.
    MESSAGE ID 'SABAPDEMOS' TYPE 'E' NUMBER '888'
            INTO DATA(lv_text)
            WITH 'flow' 'is' 'not' 'interrupted'.

    WRITE: / '  resolved text                  :', lv_text.
    WRITE: / '  sy-subrc after MESSAGE ... INTO:', sy-subrc,
             '<- unchanged, MESSAGE never sets it'.

    " ...and the program simply continues, even though the type was 'E'.
    WRITE: / '  still running after a type E   : yes'.

  ENDMETHOD.


  METHOD with_truncates_at_fifty.

    " 60 characters - longer than the 50 that sy-msgv1 can hold and
    " longer than the output length WITH formats its operands with.
    DATA(lv_long) = 'ABCDEFGHIJ0123456789abcdefghijKLMNOPQRST9876543210klmnopqrst'.

    WRITE: / '  operand length                 :', strlen( lv_long ).

    MESSAGE ID 'SABAPDEMOS' TYPE 'S' NUMBER '888'
            INTO DATA(lv_text)
            WITH lv_long 'tail' '' ''.

    " sy-msgv1 is c(50): the last 10 characters are gone, silently.
    WRITE: / '  sy-msgv1                       :', sy-msgv1.
    WRITE: / '  chars kept                     :', strlen( sy-msgv1 ).
    WRITE: / '  chars lost                     :', strlen( lv_long ) - strlen( sy-msgv1 ).
    WRITE: / '  resolved text                  :', lv_text.

  ENDMETHOD.


  METHOD surplus_placeholders_cleared.

    " First fill all four system fields.
    MESSAGE ID 'SABAPDEMOS' TYPE 'S' NUMBER '888'
            INTO DATA(lv_text)
            WITH 'one' 'two' 'three' 'four'.

    WRITE: / '  after four operands            :',
             sy-msgv1, sy-msgv2, sy-msgv3, sy-msgv4.

    " Now send the same message with only two. The short text has four
    " placeholders, so the third and fourth have no operand - the surplus
    " fields are INITIALIZED rather than keeping the values set above.
    MESSAGE ID 'SABAPDEMOS' TYPE 'S' NUMBER '888'
            INTO lv_text
            WITH 'one' 'two'.

    WRITE: / '  after two operands             :',
             sy-msgv1, sy-msgv2, sy-msgv3, sy-msgv4.
    WRITE: / '  sy-msgv3 is initial            :',
             COND string( WHEN sy-msgv3 IS INITIAL THEN 'yes' ELSE 'no' ).
    WRITE: / '  resolved text                  :', lv_text.

  ENDMETHOD.


  METHOD free_text_loses_the_id.

    " A real T100 message: the ID and number identify it for any caller
    " that logs or forwards messages.
    MESSAGE ID 'SABAPDEMOS' TYPE 'S' NUMBER '888'
            INTO DATA(lv_text)
            WITH 'a' 'real' 'T100' 'message'.

    WRITE: / '  T100    -> sy-msgid/sy-msgno   :', sy-msgid, sy-msgno.

    " The free-text variant. Type 'S' continues the program here (in
    " START-OF-SELECTION the status message is shown on the next screen).
    " WITH and INTO are both forbidden with this variant.
    MESSAGE 'Customer is blocked' TYPE 'S'.

    " sy-msgid/sy-msgno are now filled non-specifically, and sy-msgv1
    " carries the text itself. The message can no longer be identified
    " or re-translated by ID.
    WRITE: / '  free-text -> sy-msgid/sy-msgno :', sy-msgid, sy-msgno,
             '<- not the message any more'.
    WRITE: / '  free-text -> sy-msgv1          :', sy-msgv1.
    WRITE: / '  sy-msgty                       :', sy-msgty.

  ENDMETHOD.


  METHOD check_input.

    " If the caller assigns a return code to invalid_input this behaves
    " exactly like RAISE: no message is displayed, sy-subrc is set, and
    " the sy-msg* fields are filled for the caller to format.
    "
    " If the caller does NOT list the exception, RAISING is IGNORED and
    " the message is sent normally - a type 'E' here would terminate the
    " calling report.
    MESSAGE ID 'SABAPDEMOS' TYPE 'E' NUMBER '888'
            RAISING invalid_input
            WITH 'input' 'was' 'not' 'valid'.

  ENDMETHOD.


  METHOD raising_needs_a_catcher.

    " Caught form: the exception is assigned a return code, so nothing is
    " displayed and the message travels in the system fields.
    check_input( EXCEPTIONS invalid_input = 4 ).

    WRITE: / '  sy-subrc from the caught form  :', sy-subrc.

    IF sy-subrc = 4.
      " Re-formatting the message the callee raised is the standard
      " INTO idiom - and the reason MESSAGE ... RAISING is preferred
      " over plain RAISE: it carries text with the exception.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
              INTO DATA(lv_text)
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
      WRITE: / '  message carried by the raise   :', lv_text.
    ENDIF.

    " NOT demonstrated on purpose:
    "   check_input( ).
    " Without the EXCEPTIONS assignment the RAISING addition is ignored,
    " the type 'E' message is sent, and this report would end right here
    " with an empty screen. That is the trap.
    WRITE: / '  uncaught call is omitted       : it would end the report'.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  WRITE: / '1. INTO does not interrupt and does not set sy-subrc'.
  lcl_message_demo=>into_does_not_set_subrc( ).
  SKIP.

  WRITE: / '2. WITH formats every operand with output length 50'.
  lcl_message_demo=>with_truncates_at_fifty( ).
  SKIP.

  WRITE: / '3. Surplus placeholders initialize sy-msgv*'.
  lcl_message_demo=>surplus_placeholders_cleared( ).
  SKIP.

  WRITE: / '4. Free text sets sy-msgid = 00 / sy-msgno = 001'.
  lcl_message_demo=>free_text_loses_the_id( ).
  SKIP.

  WRITE: / '5. RAISING only raises if the caller catches it'.
  lcl_message_demo=>raising_needs_a_catcher( ).
