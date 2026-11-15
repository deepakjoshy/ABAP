*&---------------------------------------------------------------------*
*& Report YDJ_SPOOL_PARAMS_DEMO
*&---------------------------------------------------------------------*
*& What GET_PRINT_PARAMETERS actually hands back, and when sy-spono
*& really gets the spool number.
*&
*& This report performs NO database access. A spool request is created
*& ONLY if P_SPOOL is ticked, so the default run is side-effect free.
*&
*&   1. TWO VALIDITY FLAGS       -> GET_PRINT_PARAMETERS returns VALID
*&                       and VALID_FOR_SPOOL_CREATION. They differ
*&                       "only if the spool dialog box is not
*&                       displayed" - i.e. precisely in background,
*&                       the one case where nobody can be asked.
*&                       Part 1 prints both, plus the PRI_PARAMS
*&                       components they came back with.
*&   2. CANCEL IS INVISIBLE      -> on Cancel, OUT_PARAMETERS comes
*&                       back empty ("Either complete or empty").
*&                       An empty PRI_PARAMS is indistinguishable
*&                       from a never-filled one, and feeding it to
*&                       NEW-PAGE PRINT ON does not fail - the docs
*&                       say initial structures fall back to the
*&                       defaults. So an ignored VALID turns a user's
*&                       Cancel into "print with defaults".
*&   3. SY-SPONO TIMING          -> the number arrives with the FIRST
*&                       OUTPUT STATEMENT, not with NEW-PAGE PRINT ON.
*&                       Part 3 samples sy-spono at four points and
*&                       prints all four afterwards (it cannot print
*&                       them while spooling - that output would go
*&                       into the spool request itself).
*&   4. THE GUARD                -> the check that actually covers
*&                       both reporting channels of the function
*&                       module, shown as reusable code.
*&
*& Notes:
*&   - Part 3 is gated behind P_SPOOL because it genuinely creates a
*&     spool request in the SAP spool system. Whether that request is
*&     then printed, held, or deleted depends on YOUR user defaults
*&     (PRIMM/PRREL), not on this program - which is trap 7 in the
*&     README.
*&   - The nesting exception CX_SY_NESTED_PRINT_ON is documented in
*&     the README and left as a commented block below rather than
*&     executed, so this report never stacks spool list levels.
*&---------------------------------------------------------------------*
REPORT ydj_spool_params_demo NO STANDARD PAGE HEADING.

PARAMETERS p_spool AS CHECKBOX DEFAULT space.

*---------------------------------------------------------------------*
CLASS lcl_demo DEFINITION FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS run.

  PRIVATE SECTION.
    CLASS-METHODS head
      IMPORTING iv_text TYPE string.

    CLASS-METHODS part1_two_validity_flags.
    CLASS-METHODS part2_cancel_is_invisible.
    CLASS-METHODS part3_spono_timing.

    CLASS-METHODS spool_params_ok
      IMPORTING iv_dialog_shown TYPE abap_bool
                iv_subrc        TYPE sy-subrc
                iv_valid        TYPE c LENGTH 1
                iv_creatable    TYPE c LENGTH 1
      RETURNING VALUE(rv_ok)    TYPE abap_bool.

ENDCLASS.
*---------------------------------------------------------------------*
CLASS lcl_demo IMPLEMENTATION.

  METHOD head.
    SKIP.
    WRITE: / iv_text.
    ULINE.
  ENDMETHOD.

  METHOD run.
    part1_two_validity_flags( ).
    part2_cancel_is_invisible( ).

    IF p_spool = abap_true.
      part3_spono_timing( ).
    ELSE.
      head( `PART 3 - sy-spono timing (skipped)` ).
      WRITE: / 'Tick the checkbox to run part 3. It creates a real'.
      WRITE: / 'spool request, so it is off by default.'.
    ENDIF.
  ENDMETHOD.

*---------------------------------------------------------------------*
* PART 1 - the two flags, and whose defaults you are looking at
*---------------------------------------------------------------------*
  METHOD part1_two_validity_flags.

    DATA ls_pri   TYPE pri_params.
    DATA ls_arc   TYPE arc_params.
    DATA lv_valid TYPE c LENGTH 1.
    DATA lv_creat TYPE c LENGTH 1.
    DATA lv_subrc TYPE sy-subrc.
    DATA lv_ok    TYPE abap_bool.

*   MODE 'DEFVALS' is documented as "Always returns the default
*   values", and NO_DIALOG suppresses the popup. Nothing is printed
*   and nothing is spooled by this call - it only reads parameters.
    CALL FUNCTION 'GET_PRINT_PARAMETERS'
      EXPORTING
        mode                     = 'DEFVALS'
        no_dialog                = 'X'
      IMPORTING
        out_parameters           = ls_pri
        out_archive_parameters   = ls_arc
        valid                    = lv_valid
        valid_for_spool_creation = lv_creat
      EXCEPTIONS
        invalid_print_params     = 2
        OTHERS                   = 4.

*   Captured immediately. Every statement after this one - including
*   the method call below - is free to overwrite sy-subrc.
    lv_subrc = sy-subrc.

    head( `PART 1 - GET_PRINT_PARAMETERS reports three times` ).

    WRITE: / 'sy-subrc                 :', lv_subrc.
    WRITE: / 'VALID                    :', lv_valid.
    WRITE: / 'VALID_FOR_SPOOL_CREATION :', lv_creat.

    IF lv_valid <> lv_creat.
      WRITE: / 'The two flags DISAGREE. Printing is not possible,'.
      WRITE: / 'but a spool request could still be created. This is'.
      WRITE: / 'the documented difference, and it can only show up'.
      WRITE: / 'when the dialog box is suppressed.'.
    ELSE.
      WRITE: / 'Both flags agree on this system. They are allowed to'.
      WRITE: / 'disagree whenever the dialog box is suppressed, so'.
      WRITE: / 'code must not assume one implies the other.'.
    ENDIF.

    SKIP.
    WRITE: / 'PRI_PARAMS as returned - these are defaults taken from'.
    WRITE: / 'the CURRENT USER master record, not from this program:'.
    SKIP.
    WRITE: / '  PDEST (output device)  :', ls_pri-pdest.
    WRITE: / '  PRIMM (print now X/A/_):', ls_pri-primm.
    WRITE: / '  PRREL (delete after)   :', ls_pri-prrel.
    WRITE: / '  PEXPI (retention days) :', ls_pri-pexpi.
    WRITE: / '  PRCOP (copies)         :', ls_pri-prcop.
    WRITE: / '  PRIOT (priority 1-9)   :', ls_pri-priot.
    WRITE: / '  PRSAP (cover page)     :', ls_pri-prsap.
    WRITE: / '  PRNEW (new request)    :', ls_pri-prnew.
    WRITE: / '  LINSZ (columns)        :', ls_pri-linsz.
    WRITE: / '  LINCT (lines per page) :', ls_pri-linct.

    SKIP.
    IF ls_pri-primm = 'X'.
      WRITE: / 'PRIMM is X: on this user, output goes to the printer'.
      WRITE: / 'straight away. Another user with a blank PRIMM runs'.
      WRITE: / 'the SAME program and has to print it by hand.'.
    ELSE.
      WRITE: / 'PRIMM is not X: on this user, the request is held'.
      WRITE: / 'and must be printed manually. A developer whose'.
      WRITE: / 'profile says X cannot reproduce that ticket.'.
    ENDIF.

*   The guard from part 4, used in anger. iv_dialog_shown is false
*   here because NO_DIALOG was passed.
    lv_ok = spool_params_ok( iv_dialog_shown = abap_false
                             iv_subrc        = lv_subrc
                             iv_valid        = lv_valid
                             iv_creatable    = lv_creat ).

    SKIP.
    IF lv_ok = abap_true.
      WRITE: / 'Guard verdict: a spool request may be created.'.
    ELSE.
      WRITE: / 'Guard verdict: do NOT spool. Report it and stop.'.
    ENDIF.

  ENDMETHOD.

*---------------------------------------------------------------------*
* PART 2 - a cancelled dialog leaves no trace in the structure
*---------------------------------------------------------------------*
  METHOD part2_cancel_is_invisible.

    DATA ls_cancelled TYPE pri_params.
    DATA ls_untouched TYPE pri_params.

*   ls_cancelled is deliberately left initial. That is exactly what
*   GET_PRINT_PARAMETERS returns after Cancel: OUT_PARAMETERS is
*   documented as "Either complete or empty", and VALID goes blank.
*   ls_untouched was never passed to anything at all.

    head( `PART 2 - Cancel and never-asked are the same bytes` ).

    IF ls_cancelled = ls_untouched.
      WRITE: / 'The cancelled structure and the never-filled one are'.
      WRITE: / 'identical. Nothing inside PRI_PARAMS records that a'.
      WRITE: / 'user said no - only the separate VALID flag does.'.
    ELSE.
      WRITE: / 'Unexpected: two initial structures differ.'.
    ENDIF.

    SKIP.
    IF ls_cancelled IS INITIAL.
      WRITE: / 'And an initial PRI_PARAMS is not rejected by'.
      WRITE: / 'NEW-PAGE PRINT ON. The documentation states that if'.
      WRITE: / 'the structure is initial, the parameters produced by'.
      WRITE: / 'GET_PRINT_PARAMETERS with initial input values are'.
      WRITE: / 'used instead. So the statement below would print,'.
      WRITE: / 'using defaults, to whatever device the user master'.
      WRITE: / 'record names - after the user pressed Cancel:'.
      SKIP.
      WRITE: / '  NEW-PAGE PRINT ON PARAMETERS ls_cancelled'.
      WRITE: / '                    NO DIALOG.'.
      SKIP.
      WRITE: / 'It is not executed here. Read VALID instead.'.
    ENDIF.

  ENDMETHOD.

*---------------------------------------------------------------------*
* PART 3 - when does sy-spono hold the number?
*---------------------------------------------------------------------*
  METHOD part3_spono_timing.

    DATA ls_pri       TYPE pri_params.
    DATA lv_valid     TYPE c LENGTH 1.
    DATA lv_creat     TYPE c LENGTH 1.
    DATA lv_subrc     TYPE sy-subrc.
    DATA lv_before    TYPE sy-spono.
    DATA lv_after_on  TYPE sy-spono.
    DATA lv_after_wr  TYPE sy-spono.
    DATA lv_after_off TYPE sy-spono.

    CALL FUNCTION 'GET_PRINT_PARAMETERS'
      EXPORTING
        mode                     = 'DEFVALS'
        no_dialog                = 'X'
      IMPORTING
        out_parameters           = ls_pri
        valid                    = lv_valid
        valid_for_spool_creation = lv_creat
      EXCEPTIONS
        invalid_print_params     = 2
        OTHERS                   = 4.

    lv_subrc = sy-subrc.

    head( `PART 3 - sy-spono sampled at four points` ).

    IF spool_params_ok( iv_dialog_shown = abap_false
                        iv_subrc        = lv_subrc
                        iv_valid        = lv_valid
                        iv_creatable    = lv_creat ) = abap_false.
      WRITE: / 'No usable spool parameters on this user. Skipped.'.
      RETURN.
    ENDIF.

*   Everything between PRINT ON and PRINT OFF is written to the spool
*   list, NOT to the screen. So the four samples are only stored here
*   and reported after PRINT OFF has closed the level again.
    lv_before = sy-spono.

    NEW-PAGE PRINT ON PARAMETERS ls_pri NO DIALOG.

    lv_after_on = sy-spono.

*   This single statement is what opens the spool request.
    WRITE: / 'YDJ_SPOOL_PARAMS_DEMO - the first spooled line.'.

    lv_after_wr = sy-spono.

    NEW-PAGE PRINT OFF.

    lv_after_off = sy-spono.

    WRITE: / 'before NEW-PAGE PRINT ON :', lv_before.
    WRITE: / 'after  NEW-PAGE PRINT ON :', lv_after_on.
    WRITE: / 'after  the first WRITE   :', lv_after_wr.
    WRITE: / 'after  NEW-PAGE PRINT OFF:', lv_after_off.

    SKIP.
    IF lv_after_on = lv_before.
      WRITE: / 'Confirmed: PRINT ON alone did not change sy-spono.'.
      WRITE: / 'Reading it there gives you the PREVIOUS value, which'.
      WRITE: / 'on a first run is zeros and on a later run is some'.
      WRITE: / 'other request number - plausible either way.'.
    ELSE.
      WRITE: / 'On this release sy-spono already changed at PRINT ON.'.
      WRITE: / 'Note it and trust the measurement, not this comment.'.
    ENDIF.

    IF lv_after_wr <> lv_before.
      WRITE: / 'The first output statement is what assigned it.'.
    ENDIF.

    SKIP.
    WRITE: / 'A PRINT ON / PRINT OFF pair with no output statement'.
    WRITE: / 'between them opens no spool request at all, so there'.
    WRITE: / 'is no number to report and nothing fails.'.
    SKIP.
    WRITE: / 'SUBMIT ... TO SAP-SPOOL does not use sy-spono. Its'.
    WRITE: / 'number arrives in the SPA/GPA parameter SPI:'.
    WRITE: / '  GET PARAMETER ID ''SPI'' FIELD lv_spono.'.

  ENDMETHOD.

*---------------------------------------------------------------------*
* PART 4 - the guard, as reusable code
*---------------------------------------------------------------------*
  METHOD spool_params_ok.

*   Three things must be checked, and most copied snippets check one:
*     1. sy-subrc, because the classic EXCEPTIONS are mapped by hand
*        and an unhandled one leaves the structure untouched;
*     2. VALID, which is blank after Cancel and whenever printing is
*        impossible;
*     3. VALID_FOR_SPOOL_CREATION, which is the one that matters when
*        the dialog was suppressed - the documentation says the two
*        differ only in that case, and that a spool request may be
*        creatable when printing is not.
    rv_ok = abap_false.

    IF iv_subrc <> 0.
      RETURN.
    ENDIF.

    IF iv_dialog_shown = abap_true.
*     With a dialog, VALID_FOR_SPOOL_CREATION "is filled just like
*     VALID", so VALID is the whole answer.
      IF iv_valid = 'X'.
        rv_ok = abap_true.
      ENDIF.
    ELSE.
*     Without a dialog, accept a creatable request even if it cannot
*     be printed: a held spool request is the normal background
*     outcome, and refusing it loses the output entirely.
      IF iv_creatable = 'X'.
        rv_ok = abap_true.
      ENDIF.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
*---------------------------------------------------------------------*
* NOT EXECUTED - the nesting exception, for reference
*---------------------------------------------------------------------*
* Stacking a second spool list level directly on one created by
* NEW-PAGE PRINT ON raises CX_SY_NESTED_PRINT_ON (runtime error
* NESTED_PRINT_ON). This is what a reusable "spool this" helper hits
* the second time it is called without closing the first level.
*
*   NEW-PAGE PRINT ON PARAMETERS ls_pri NO DIALOG.
*   WRITE: / 'first'.
*
*   TRY.
*       NEW-PAGE PRINT ON PARAMETERS ls_pri NO DIALOG.
*     CATCH cx_sy_nested_print_on.
*       " Caught - but the output cannot be continued into the
*       " previous spool list from here. NEW-SECTION can do that,
*       " which is why the documentation recommends it over CATCH.
*   ENDTRY.
*
*   NEW-PAGE PRINT OFF.
*
* The documented alternative, which does not raise:
*
*   NEW-PAGE PRINT ON NEW-SECTION PARAMETERS ls_pri NO DIALOG.
*
* Beware that NEW-SECTION has two opposite outcomes depending on the
* data: if the spool parameters match the current list and PRNEW is
* initial, the output is appended to the SAME spool request; if they
* differ or PRNEW is set, the current request is closed implicitly
* and a new one is created. See trap 5 in the README.
*---------------------------------------------------------------------*

START-OF-SELECTION.
  lcl_demo=>run( ).
