*&---------------------------------------------------------------------*
*& Report YDJ_AMC_CHANNEL_DEMO
*&---------------------------------------------------------------------*
*& ABAP Messaging Channels (AMC) - publish/subscribe between ABAP
*& sessions, and the three things about it that are not obvious.
*&
*&   1. SUBSCRIBE = COMMIT -> start_message_delivery( ) and
*&                            stop_message_delivery( ) each cause a
*&                            DATABASE COMMIT. Never call them inside
*&                            an open LUW or between OPEN CURSOR and
*&                            FETCH.
*&   2. WAIT MAY NOT WAIT -> if NO consumer is registered in this
*&                            internal session, WAIT FOR MESSAGING
*&                            CHANNELS is not interrupted at all,
*&                            UP TO ... SECONDS is IGNORED and
*&                            sy-subrc = 4. Run this report with
*&                            Receive unticked to see it return
*&                            instantly. sy-subrc 4 also means
*&                            "messages arrived, condition still
*&                            false" - the two are indistinguishable.
*&   3. ECHO IS ON        -> i_suppress_echo defaults to abap_false,
*&                            so a session that sends AND subscribes
*&                            receives its own message. Tick both
*&                            checkboxes to see that happen.
*&
*& A negative wait time raises the UNCATCHABLE runtime error
*& WAIT_ILLEGAL_TIME_LIMIT, so the value is validated BEFORE the
*& statement, not wrapped in TRY ... CATCH.
*&
*& No database access and no COMMIT WORK of its own - but see note 1:
*& the subscribe call itself ends the database LUW.
*&
*& The defaults point at SAP own demo channel DEMO_AMC / /demo_text
*& (package SABAPDEMOS). Access to an AMC channel is granted to
*& PROGRAMS in the channel definition (transaction SAMC), not to
*& users, so unless this report is added to that include list the
*& factory call raises CX_AMC_ERROR - which is caught and printed
*& here, because that failure is itself worth seeing once.
*&---------------------------------------------------------------------*
REPORT ydj_amc_channel_demo.

PARAMETERS: p_app(30)  TYPE c DEFAULT 'DEMO_AMC',
            p_chan(30) TYPE c LOWER CASE DEFAULT '/demo_text',
            p_msg(60)  TYPE c LOWER CASE DEFAULT 'hello from ydj_amc_channel_demo',
            p_secs     TYPE i DEFAULT 10,
            p_send     AS CHECKBOX DEFAULT 'X',
            p_recv     AS CHECKBOX DEFAULT 'X'.

*----------------------------------------------------------------------*
* Receiver object: the RECEIVE method is a callback. It is executed by
* the AMC framework while WAIT is suspended, never by this program.
*----------------------------------------------------------------------*
CLASS lcl_receiver DEFINITION.
  PUBLIC SECTION.
    INTERFACES if_amc_message_receiver_text.
    DATA mv_last  TYPE string READ-ONLY.
    DATA mv_count TYPE i      READ-ONLY.
ENDCLASS.

CLASS lcl_receiver IMPLEMENTATION.
  METHOD if_amc_message_receiver_text~receive.
    mv_last  = i_message.
    mv_count = mv_count + 1.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_demo DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS run IMPORTING iv_app  TYPE string
                                iv_chan TYPE string
                                iv_msg  TYPE string
                                iv_secs TYPE i
                                iv_send TYPE abap_bool
                                iv_recv TYPE abap_bool.
  PRIVATE SECTION.
    CLASS-METHODS subscribe
      IMPORTING iv_app            TYPE string
                iv_chan           TYPE string
                io_receiver       TYPE REF TO lcl_receiver
      RETURNING VALUE(ro_consumer) TYPE REF TO if_amc_message_consumer.

    CLASS-METHODS publish
      IMPORTING iv_app  TYPE string
                iv_chan TYPE string
                iv_msg  TYPE string.

    CLASS-METHODS explain_subrc
      IMPORTING iv_subrc       TYPE i
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

  METHOD run.

    DATA lo_consumer TYPE REF TO if_amc_message_consumer.
    DATA lv_secs     TYPE f.
    DATA lv_subrc    TYPE i.
    DATA lv_before   TYPE timestampl.
    DATA lv_after    TYPE timestampl.

    DATA(lo_receiver) = NEW lcl_receiver( ).

*   Step 1 - subscribe. THIS COMMITS THE DATABASE LUW.
    IF iv_recv = abap_true.
      lo_consumer = subscribe( iv_app      = iv_app
                               iv_chan     = iv_chan
                               io_receiver = lo_receiver ).
      IF lo_consumer IS NOT BOUND.
        WRITE: / 'Subscribe failed - nothing is registered, so the WAIT',
               / 'below will fall straight through with sy-subrc = 4.'.
      ENDIF.
    ELSE.
      WRITE: / 'Receive not requested: no consumer is registered.',
             / 'WAIT FOR MESSAGING CHANNELS will NOT wait and UP TO is ignored.'.
    ENDIF.

*   Step 2 - publish. Echo is NOT suppressed, so if this session is also
*   subscribed it will receive its own message.
    IF iv_send = abap_true.
      publish( iv_app  = iv_app
               iv_chan = iv_chan
               iv_msg  = iv_msg ).
    ENDIF.

*   Step 3 - wait. Validate the time BEFORE the statement: a negative
*   value is an uncatchable WAIT_ILLEGAL_TIME_LIMIT.
    IF iv_secs <= 0.
      lv_secs = 1.
      WRITE: / 'Wait time was not positive - forced to 1 second.'.
    ELSE.
      lv_secs = iv_secs.
    ENDIF.

    GET TIME STAMP FIELD lv_before.

*   The condition is a plain comparison against an attribute the
*   callback sets. A functional method call here would be re-executed
*   on EVERY arriving message, not once.
    WAIT FOR MESSAGING CHANNELS
         UNTIL lo_receiver->mv_count > 0
         UP TO lv_secs SECONDS.

    lv_subrc = sy-subrc.
    GET TIME STAMP FIELD lv_after.

*   Step 4 - unsubscribe. This commits as well.
    IF lo_consumer IS BOUND.
      TRY.
          lo_consumer->stop_message_delivery( ).
        CATCH cx_amc_error INTO DATA(lx_stop).
          DATA(lv_stop_text) = lx_stop->get_text( ).
          WRITE: / 'stop_message_delivery failed:', lv_stop_text.
      ENDTRY.
    ENDIF.

*   Results.
    DATA(lv_meaning) = explain_subrc( lv_subrc ).
    DATA(lv_count)   = lo_receiver->mv_count.
    DATA(lv_last)    = lo_receiver->mv_last.

    SKIP.
    WRITE: / 'Channel ', iv_app, '/', iv_chan.
    WRITE: / 'Timestamp before WAIT:', lv_before.
    WRITE: / 'Timestamp after  WAIT:', lv_after.
    WRITE: / 'sy-subrc after WAIT :', lv_subrc, lv_meaning.
    WRITE: / 'Messages received   :', lv_count.
    IF lv_count > 0.
      WRITE: / 'Last message        :', lv_last.
    ENDIF.
    SKIP.
    WRITE: / 'Compare the two timestamps. With no consumer registered the',
           / 'difference is microseconds even though UP TO asked for', iv_secs,
           / 'seconds - that is the documented behaviour, not a bug.'.

  ENDMETHOD.

  METHOD subscribe.
    TRY.
        ro_consumer = cl_amc_channel_manager=>create_message_consumer(
                        i_application_id = iv_app
                        i_channel_id     = iv_chan ).
*       Registers the callback object AND ends the database LUW.
        ro_consumer->start_message_delivery( i_receiver = io_receiver ).
        WRITE: / 'Subscribed. Note: the database LUW has just been committed.'.
      CATCH cx_amc_error INTO DATA(lx_amc).
        CLEAR ro_consumer.
        DATA(lv_text) = lx_amc->get_text( ).
        WRITE: / 'CX_AMC_ERROR on subscribe:', lv_text.
        WRITE: / 'Almost always the channel definition (SAMC): wrong name,',
               / 'wrong scope, or this program is not in the include list.'.
    ENDTRY.
  ENDMETHOD.

  METHOD publish.
    TRY.
*       i_suppress_echo is left at its default of abap_false on purpose:
*       a session that also subscribes WILL receive this message itself.
        CAST if_amc_message_producer_text(
          cl_amc_channel_manager=>create_message_producer(
            i_application_id = iv_app
            i_channel_id     = iv_chan )
          )->send( i_message = iv_msg ).
        WRITE: / 'Sent. A successful send means the framework accepted the',
               / 'message - NOT that anybody received it. Nothing is stored.'.
      CATCH cx_amc_error INTO DATA(lx_amc).
        DATA(lv_text) = lx_amc->get_text( ).
        WRITE: / 'CX_AMC_ERROR on send:', lv_text.
    ENDTRY.
  ENDMETHOD.

  METHOD explain_subrc.
    CASE iv_subrc.
      WHEN 0.
        rv_text = '(condition true - a message arrived, or it was already true)'.
      WHEN 4.
        rv_text = '(no consumer registered, OR condition still false)'.
      WHEN 8.
        rv_text = '(UP TO time elapsed - this is the only real timeout)'.
      WHEN OTHERS.
        rv_text = '(undocumented)'.
    ENDCASE.
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  lcl_demo=>run( iv_app  = CONV string( p_app )
                 iv_chan = CONV string( p_chan )
                 iv_msg  = CONV string( p_msg )
                 iv_secs = p_secs
                 iv_send = p_send
                 iv_recv = p_recv ).
