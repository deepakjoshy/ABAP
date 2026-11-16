*&---------------------------------------------------------------------*
*& Report YDJ_APPL_LOG_DEMO
*&---------------------------------------------------------------------*
*& The Application Log (BAL) traps that can be proved in memory,
*& without writing a single row to the database.
*&
*& By default this report performs NO database access and NO COMMIT:
*& BAL_LOG_CREATE and BAL_LOG_MSG_* work purely in the global memory
*& of function group SBAL. BAL_DB_SAVE and COMMIT WORK run ONLY if
*& P_SAVE is ticked.
*&
*&   1. TWO LOGS, TWO HANDLES  -> BAL_LOG_CREATE returns a CHAR22 GUID
*&                       that is final immediately. Part 1 opens two
*&                       logs so the following parts have somewhere
*&                       wrong to go.
*&   2. THE OPTIONAL HANDLE    -> I_LOG_HANDLE is an OPTIONAL parameter.
*&                       Part 2 adds a message WITHOUT it and prints the
*&                       log handle that comes back inside
*&                       E_S_MSG_HANDLE. It is the log created LAST,
*&                       not the log you meant. Part 2b repeats the
*&                       same call WITH the handle, for contrast.
*&   3. LOGGED IS NOT sy-subrc -> BAL_LOG_MSG_ADD has three exceptions
*&                       AND a separate boolean E_MSG_WAS_LOGGED
*&                       ("Message collected"). Part 3 prints both
*&                       channels side by side.
*&   4. THE EXPIRY THAT PASSED -> an unfilled BAL_S_LOG-DATE_DEL is
*&                       00000000, a date in the past, so the log is
*&                       deletable by SLG2 from the moment it exists.
*&                       Part 4 does that comparison in memory.
*&   5. THE NUMBER IS A STUB   -> only with P_SAVE. BAL_DB_SAVE returns
*&                       E_NEW_LOGNUMBERS, whose rows carry BOTH
*&                       TMP_LOGNUM (the $nnnnn placeholder) and
*&                       LOGNUMBER (the real number). Part 5 prints the
*&                       pair, which is the mapping you must store.
*&
*& Notes:
*&   - P_OBJECT / P_SUBOBJ are CHAR20 and must be registered in SLG0
*&     before a log can be SAVED. Leaving them blank is fine for the
*&     memory-only default run.
*&   - Parts 2 and 3 use BAL_LOG_MSG_ADD_FREE_TEXT so the report needs
*&     no T100 message of its own. Part 3 additionally uses
*&     BAL_LOG_MSG_ADD with SABAPDEMOS 888, the SAP-delivered message
*&     this repo's Messages note verified.
*&   - sy-subrc is captured into a local immediately after every
*&     CALL FUNCTION. Reading it later is the anti-pattern documented
*&     in this repo's Messages note.
*&---------------------------------------------------------------------*
REPORT ydj_appl_log_demo.

PARAMETERS: p_object TYPE c LENGTH 20 LOWER CASE,
            p_subobj TYPE c LENGTH 20 LOWER CASE,
            p_save   AS CHECKBOX DEFAULT space.

*---------------------------------------------------------------------*
CLASS lcl_demo DEFINITION FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS run.

  PRIVATE SECTION.
    CLASS-DATA gv_log_a TYPE balloghndl.
    CLASS-DATA gv_log_b TYPE balloghndl.

    CLASS-METHODS open_two_logs.
    CLASS-METHODS add_without_handle.
    CLASS-METHODS add_with_handle.
    CLASS-METHODS logged_flag_vs_subrc.
    CLASS-METHODS expiry_date_is_in_the_past.
    CLASS-METHODS save_and_show_numbers.
    CLASS-METHODS create_log
                    IMPORTING iv_extnumber     TYPE c
                    RETURNING VALUE(rv_handle) TYPE balloghndl.
    CLASS-METHODS which_log
                    IMPORTING iv_handle      TYPE balloghndl
                    RETURNING VALUE(rv_name) TYPE string.

ENDCLASS.

*---------------------------------------------------------------------*
CLASS lcl_demo IMPLEMENTATION.

  METHOD run.
    open_two_logs( ).
    add_without_handle( ).
    add_with_handle( ).
    logged_flag_vs_subrc( ).
    expiry_date_is_in_the_past( ).

    IF p_save = abap_true.
      save_and_show_numbers( ).
    ELSE.
      SKIP.
      WRITE: / 'Part 5 skipped: P_SAVE is not ticked, so nothing was'.
      WRITE: / '        written to the database and no COMMIT ran.'.
    ENDIF.
  ENDMETHOD.

  METHOD create_log.
    DATA ls_log    TYPE bal_s_log.
    DATA lv_subrc  TYPE sy-subrc.

    ls_log-object    = p_object.
    ls_log-subobject = p_subobj.
    ls_log-extnumber = iv_extnumber.
    ls_log-aldate    = sy-datum.
    ls_log-altime    = sy-uzeit.
    ls_log-aluser    = sy-uname.
    ls_log-alprog    = sy-repid.
    " DATE_DEL and DEL_BEFORE deliberately left initial - see part 4.

    CALL FUNCTION 'BAL_LOG_CREATE'
      EXPORTING  i_s_log                 = ls_log
      IMPORTING  e_log_handle            = rv_handle
      EXCEPTIONS log_header_inconsistent = 1
                 OTHERS                  = 2.
    lv_subrc = sy-subrc.

    IF lv_subrc <> 0.
      WRITE: / 'BAL_LOG_CREATE failed, sy-subrc =', lv_subrc.
      CLEAR rv_handle.
    ENDIF.
  ENDMETHOD.

  METHOD which_log.
    IF iv_handle IS INITIAL.
      rv_name = `(empty handle)`.
    ELSEIF iv_handle = gv_log_a.
      rv_name = `log A - the one we meant`.
    ELSEIF iv_handle = gv_log_b.
      rv_name = `log B - the one created LAST`.
    ELSE.
      rv_name = `a log this report did not create`.
    ENDIF.
  ENDMETHOD.

  METHOD open_two_logs.
    WRITE: / '=== 1. Two logs, two handles ========================='.

    gv_log_a = create_log( 'DJ-DEMO-A' ).
    gv_log_b = create_log( 'DJ-DEMO-B' ).

    WRITE: / '  log A handle:', gv_log_a.
    WRITE: / '  log B handle:', gv_log_b.
    WRITE: / '  Both are CHAR22 GUIDs and are final already: the'.
    WRITE: / '  handle, unlike the log number, needs no save.'.
    SKIP.
  ENDMETHOD.

  METHOD add_without_handle.
    DATA ls_msgh  TYPE balmsghndl.
    DATA lv_text  TYPE c LENGTH 200.
    DATA lv_subrc TYPE sy-subrc.
    DATA lv_owner TYPE string.

    WRITE: / '=== 2. The handle is optional ========================'.

    lv_text = 'Message added with NO I_LOG_HANDLE'.

    CALL FUNCTION 'BAL_LOG_MSG_ADD_FREE_TEXT'
      EXPORTING  i_msgty          = 'I'
                 i_text           = lv_text
      IMPORTING  e_s_msg_handle   = ls_msgh
      EXCEPTIONS log_not_found    = 1
                 msg_inconsistent = 2
                 log_is_full      = 3
                 OTHERS           = 4.
    lv_subrc = sy-subrc.

    IF lv_subrc <> 0.
      WRITE: / '  call failed, sy-subrc =', lv_subrc.
      SKIP.
      RETURN.
    ENDIF.

    " The message handle carries the log handle of the log the
    " message actually landed in - that is how we can tell.
    lv_owner = which_log( ls_msgh-log_handle ).

    WRITE: / '  returned log handle:', ls_msgh-log_handle.
    WRITE: / '  that is:', lv_owner.
    WRITE: / '  Nothing failed. The message simply went to the'.
    WRITE: / '  default log, which BAL_LOG_CREATE set implicitly.'.
    SKIP.
  ENDMETHOD.

  METHOD add_with_handle.
    DATA ls_msgh  TYPE balmsghndl.
    DATA lv_text  TYPE c LENGTH 200.
    DATA lv_subrc TYPE sy-subrc.
    DATA lv_owner TYPE string.

    WRITE: / '=== 2b. The same call, with the handle ==============='.

    lv_text = 'Message added WITH I_LOG_HANDLE = log A'.

    CALL FUNCTION 'BAL_LOG_MSG_ADD_FREE_TEXT'
      EXPORTING  i_log_handle     = gv_log_a
                 i_msgty          = 'I'
                 i_text           = lv_text
      IMPORTING  e_s_msg_handle   = ls_msgh
      EXCEPTIONS log_not_found    = 1
                 msg_inconsistent = 2
                 log_is_full      = 3
                 OTHERS           = 4.
    lv_subrc = sy-subrc.

    IF lv_subrc <> 0.
      WRITE: / '  call failed, sy-subrc =', lv_subrc.
      SKIP.
      RETURN.
    ENDIF.

    lv_owner = which_log( ls_msgh-log_handle ).

    WRITE: / '  returned log handle:', ls_msgh-log_handle.
    WRITE: / '  that is:', lv_owner.
    WRITE: / '  One extra parameter is the whole difference between'.
    WRITE: / '  a private log and a shared one.'.
    SKIP.
  ENDMETHOD.

  METHOD logged_flag_vs_subrc.
    DATA ls_msg    TYPE bal_s_msg.
    DATA ls_msgh   TYPE balmsghndl.
    DATA lv_logged TYPE boolean.
    DATA lv_shown  TYPE boolean.
    DATA lv_subrc  TYPE sy-subrc.

    WRITE: / '=== 3. Collected is a separate answer ================'.

    " SABAPDEMOS 888 is SAP-delivered; see this repo's Messages note.
    ls_msg-msgty     = 'E'.
    ls_msg-msgid     = 'SABAPDEMOS'.
    ls_msg-msgno     = '888'.
    ls_msg-msgv1     = 'Application Log demo'.
    ls_msg-probclass = '1'.          " 1 = very important
    ls_msg-detlevel  = '1'.          " documented range: 1 to 9

    CALL FUNCTION 'BAL_LOG_MSG_ADD'
      EXPORTING  i_log_handle        = gv_log_a
                 i_s_msg             = ls_msg
      IMPORTING  e_s_msg_handle      = ls_msgh
                 e_msg_was_logged    = lv_logged
                 e_msg_was_displayed = lv_shown
      EXCEPTIONS log_not_found       = 1
                 msg_inconsistent    = 2
                 log_is_full         = 3
                 OTHERS              = 4.
    lv_subrc = sy-subrc.

    WRITE: / '  sy-subrc            :', lv_subrc.
    WRITE: / '  E_MSG_WAS_LOGGED    :', lv_logged.
    WRITE: / '  E_MSG_WAS_DISPLAYED :', lv_shown.
    WRITE: / '  msg serial number   :', ls_msgh-msgnumber.
    WRITE: / '  Two independent channels. sy-subrc = 0 says the call'.
    WRITE: / '  did not break; only the flag says it was collected.'.
    WRITE: / '  Exception 3 is LOG_IS_FULL, documented as message'.
    WRITE: / '  number 999999 reached. A log has a hard ceiling, so'.
    WRITE: / '  repeating messages belong in BAL_LOG_MSG_CUMULATE.'.
    SKIP.
  ENDMETHOD.

  METHOD expiry_date_is_in_the_past.
    DATA ls_log TYPE bal_s_log.
    DATA lv_del TYPE d.

    WRITE: / '=== 4. The expiry date nobody filled ================='.

    " ls_log is untouched: exactly what create_log( ) sent for
    " DATE_DEL and DEL_BEFORE.
    lv_del = ls_log-date_del.

    WRITE: / '  BAL_S_LOG-DATE_DEL as created:', lv_del.
    WRITE: / '  today                        :', sy-datum.

    " No arithmetic here on purpose: 00000000 is not a valid date,
    " so it is compared, never subtracted.
    IF lv_del IS INITIAL.
      WRITE: / '  DATE_DEL is initial: 00000000 is a date that has'.
      WRITE: / '  passed, so this log counts as expired already.'.
      WRITE: / '  SLG2 deletes expired logs, so the log is eligible'.
      WRITE: / '  for deletion from the moment it was created.'.
    ELSEIF lv_del <= sy-datum.
      WRITE: / '  DATE_DEL has been reached or passed: expired.'.
    ELSE.
      WRITE: / '  Still within its retention period.'.
    ENDIF.

    WRITE: / '  Fix: set DATE_DEL to a real retention date before'.
    WRITE: / '  calling BAL_LOG_CREATE. For anything that must be'.
    WRITE: / '  kept for audit, do not use BAL at all.'.
    SKIP.
  ENDMETHOD.

  METHOD save_and_show_numbers.
    DATA lt_handles TYPE bal_t_logh.
    DATA lt_lognums TYPE bal_t_lgnm.
    DATA lv_subrc   TYPE sy-subrc.
    DATA lv_rows    TYPE i.

    WRITE: / '=== 5. Temporary number vs real number =============='.

    APPEND gv_log_a TO lt_handles.
    APPEND gv_log_b TO lt_handles.

    CALL FUNCTION 'BAL_DB_SAVE'
      EXPORTING  i_t_log_handle    = lt_handles
      IMPORTING  e_new_lognumbers  = lt_lognums
      EXCEPTIONS log_not_found     = 1
                 save_not_allowed  = 2
                 numbering_error   = 3
                 OTHERS            = 4.
    lv_subrc = sy-subrc.

    IF lv_subrc <> 0.
      WRITE: / '  BAL_DB_SAVE failed, sy-subrc =', lv_subrc.
      WRITE: / '  OBJECT is optional in memory but must be present'.
      WRITE: / '  at save time, and the OBJECT/SUBOBJECT combination'.
      WRITE: / '  must exist in SLG0. Nothing was committed.'.
      SKIP.
      RETURN.
    ENDIF.

    lv_rows = lines( lt_lognums ).
    WRITE: / '  E_NEW_LOGNUMBERS rows:', lv_rows.

    LOOP AT lt_lognums ASSIGNING FIELD-SYMBOL(<ls_num>).
      WRITE: / '    ext number   :', <ls_num>-extnumber.
      WRITE: / '    TMP_LOGNUM   :', <ls_num>-tmp_lognum.
      WRITE: / '    LOGNUMBER    :', <ls_num>-lognumber.
    ENDLOOP.

    WRITE: / '  TMP_LOGNUM is the $nnnnn value the log carried'.
    WRITE: / '  BEFORE the save. LOGNUMBER is the one to store on'.
    WRITE: / '  your document. Reading the header before the save'.
    WRITE: / '  gives you the first and looks like the second.'.

    " Correct for a report. Code running IN the update task must
    " NOT commit; a log that has to survive ROLLBACK WORK needs
    " I_2TH_CONNECTION instead. See the README.
    COMMIT WORK.
    WRITE: / '  COMMIT WORK done - without it, nothing is on disk.'.
    SKIP.
  ENDMETHOD.

ENDCLASS.

*---------------------------------------------------------------------*
START-OF-SELECTION.
  lcl_demo=>run( ).
