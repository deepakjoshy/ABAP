*&---------------------------------------------------------------------*
*& Program YDJ_F4_INPUT_HELP_DEMO
*&---------------------------------------------------------------------*
*& Input help (F4) - the dependent search help, built twice: once the
*& way everybody writes it, and once the way the documentation says.
*&
*& Both parameters below offer an F4 list of flight connections for the
*& airline in P_CARRID. They differ in ONE line: where the airline is
*& read from.
*&
*&   P_CONN_W ("wrong")  reads the PROGRAM variable p_carrid.
*&   P_CONN_R ("right")  reads the SCREEN field P_CARRID through the
*&                       function module DYNP_VALUES_READ.
*&
*& Why that matters - at POV / ON VALUE-REQUEST nothing is transported
*& from the screen to the program:
*&
*&   "During the events for the field help and input help no data is
*&    transported from the selection screen to the ABAP program. As with
*&    general dynpros, suitable function modules such as
*&    RS_SELECTIONSCREEN_READ and RS_SELECTIONSCREEN_UPDATE must be
*&    used."
*&      - AT SELECTION-SCREEN, selscreen_event
*&
*&   "The additional function modules DYNP_VALUES_READ and
*&    DYNP_VALUES_UPDATE read and return dynpro fields at POV time."
*&      - dynpro - Input Help in Dialog Modules
*&
*& HOW TO SEE THE DIFFERENCE
*&   1. Start the program. P_CARRID is pre-filled with 'LH'.
*&   2. Overtype P_CARRID with 'AA' but do NOT press Enter.
*&   3. F4 on P_CONN_W -> still the LH connections (the program
*&      variable still holds the value from the last dialog step).
*&      F4 on P_CONN_R -> the AA connections.
*&   4. Press Enter, then F4 on P_CONN_W again -> now it is right too.
*&      That is exactly why this defect gets reported as "the help is
*&      one step behind" instead of "the help is broken".
*&
*& Two further documented details are applied here deliberately:
*&
*&   - sy-repid is NOT passed to DYNP_VALUES_READ. Its own parameter
*&     documentation: "Note that the variable sy-repid must not be used
*&     in the call because it can be overwritten at run-time, e.g. by
*&     the names of function groups. Either use the variable sy-cprog or
*&     enter the value as a literal instead." The screen number is given
*&     as a literal for the same reason ("it can in rare cases contain
*&     screen numbers of the current function groups SHLP and SHL2").
*&     1000 is correct here: "A standard selection screen has the dynpro
*&     number 1000 and is only possible in executable programs and
*&     logical databases."
*&
*&   - VALUE_ORG = 'S' is passed EXPLICITLY although the parameter is
*&     optional, because its default is 'C' and SAP's own documentation
*&     says of 'S': "This option should be used for new developments
*&     (despite other default values)."
*&
*&   - Only ONE return route is used: RETURN_TAB. DYNPPROG / DYNPNR /
*&     DYNPROFIELD are deliberately not passed, and the chosen value is
*&     assigned to the parameter instead, which is transported by the
*&     runtime: "The selection parameters and selection criteria changed
*&     in the event blocks for ON VALUE-REQUEST are transported to the
*&     respective fields of the selection screen."
*&
*& READ-ONLY: two SELECTs on the SPFLI/SCARR flight demo tables. No
*& INSERT/UPDATE/DELETE/MODIFY, no COMMIT, no file or RFC access.
*&
*& Requires the standard flight data model (fill it with the program
*& SAPBC_DATA_GENERATOR if the tables are empty).
*&---------------------------------------------------------------------*
REPORT ydj_f4_input_help_demo.

TYPES: BEGIN OF ty_conn,
         connid   TYPE spfli-connid,
         cityfrom TYPE spfli-cityfrom,
         cityto   TYPE spfli-cityto,
       END OF ty_conn.

TYPES ty_conn_tab TYPE STANDARD TABLE OF ty_conn WITH EMPTY KEY.

* Trace of which airline each F4 call actually used. Global on purpose:
* declarative statements inside an AT SELECTION-SCREEN block create
* LOCAL data, and the trace has to survive until START-OF-SELECTION.
DATA gt_trace TYPE STANDARD TABLE OF string WITH EMPTY KEY.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME.
PARAMETERS p_carrid TYPE spfli-carrid OBLIGATORY DEFAULT 'LH'.
PARAMETERS p_conn_w TYPE spfli-connid.
PARAMETERS p_conn_r TYPE spfli-connid.
SELECTION-SCREEN END OF BLOCK b1.

*&---------------------------------------------------------------------*
*& The two F4 event blocks
*&---------------------------------------------------------------------*
* NOTE: for a SELECT-OPTIONS both halves need their own block, because
* the syntax is FOR {para|selcrit-low|selcrit-high} - a help written for
* s_conn-low does nothing when F4 is pressed in the "to" field.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_conn_w.
* The naive version: p_carrid here is the PROGRAM variable, which at
* this moment still holds the value of the last dialog step.
  PERFORM f4_connid USING p_carrid `P_CONN_W (program variable)`
                    CHANGING p_conn_w.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_conn_r.
  PERFORM f4_connid_from_screen CHANGING p_conn_r.

*&---------------------------------------------------------------------*
*& FORM f4_connid_from_screen
*&---------------------------------------------------------------------*
*& Reads P_CARRID from the SCREEN first, then builds the same help.
*&---------------------------------------------------------------------*
FORM f4_connid_from_screen CHANGING cv_connid TYPE spfli-connid.

  DATA lv_carrid TYPE spfli-carrid.

  PERFORM read_screen_carrid CHANGING lv_carrid.
  PERFORM f4_connid USING lv_carrid `P_CONN_R (screen value)`
                    CHANGING cv_connid.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM read_screen_carrid
*&---------------------------------------------------------------------*
*& DYNP_VALUES_READ - ask the screen what is currently typed into
*& P_CARRID. This is the one call that makes a dependent F4 correct.
*&---------------------------------------------------------------------*
FORM read_screen_carrid CHANGING cv_carrid TYPE spfli-carrid.

  DATA lt_fields TYPE STANDARD TABLE OF dynpread WITH EMPTY KEY.
  DATA ls_field  TYPE dynpread.
  DATA lv_prog   TYPE d020s-prog.
  DATA lv_dynnr  TYPE d020s-dnum.

* sy-cprog, never sy-repid - see the header comment.
  lv_prog  = sy-cprog.
* Literal, not sy-dynnr: 1000 is the standard selection screen.
  lv_dynnr = '1000'.

  ls_field-fieldname = 'P_CARRID'.
  APPEND ls_field TO lt_fields.

  CALL FUNCTION 'DYNP_VALUES_READ'
    EXPORTING
      dyname               = lv_prog
      dynumb               = lv_dynnr
      translate_to_upper   = 'X'
    TABLES
      dynpfields           = lt_fields
    EXCEPTIONS
      invalid_abapworkarea = 1
      invalid_dynprofield  = 2
      invalid_dynproname   = 3
      invalid_dynpronummer = 4
      invalid_request      = 5
      no_fielddescription  = 6
      invalid_parameter    = 7
      undefind_error       = 8
      double_conversion    = 9
      stepl_not_found      = 10
      OTHERS               = 11.
* undefind_error is not a typo here - that is how the exception is
* spelled in the function module interface, while the long text of the
* same function module writes UNDEFINED_ERROR. The interface wins.

  IF sy-subrc <> 0.
*   Nothing read: fall back to the program variable rather than
*   searching for an empty airline.
    cv_carrid = p_carrid.
    RETURN.
  ENDIF.

  READ TABLE lt_fields INTO ls_field INDEX 1.
  IF sy-subrc = 0.
    cv_carrid = ls_field-fieldvalue.
  ENDIF.

* FIELDVALUE arrives in EXTERNAL representation. PERFORM_CONVERSION_EXITS
* (default SPACE) is what controls that: "Flag whether the conversion
* exit stored for the screen field should be executed when the field
* values are read. The conversion is from external to internal format."
* CARRID has no conversion exit, so nothing is needed here - but a
* material or an account number would need that flag set, or an ALPHA
* conversion of its own, before it can be used in a WHERE condition.

ENDFORM.

*&---------------------------------------------------------------------*
*& FORM f4_connid
*&---------------------------------------------------------------------*
*& Builds the proposal list and hands it to the standard help dialog.
*&---------------------------------------------------------------------*
FORM f4_connid USING iv_carrid TYPE spfli-carrid
                     iv_source TYPE string
               CHANGING cv_connid TYPE spfli-connid.

  DATA lt_values TYPE ty_conn_tab.
  DATA lt_return TYPE STANDARD TABLE OF ddshretval WITH EMPTY KEY.
  DATA ls_return TYPE ddshretval.
  DATA lv_title  TYPE c LENGTH 60.
  DATA lv_count  TYPE i.
  DATA lv_trace  TYPE string.

  SELECT connid, cityfrom, cityto
         FROM spfli
         WHERE carrid = @iv_carrid
         ORDER BY connid
         INTO TABLE @lt_values.

  lv_count = lines( lt_values ).
* APPEND expects a data object, so the line is built first.
  lv_trace = |{ iv_source } used carrier "{ iv_carrid }", | &&
             |{ lv_count } connection(s) offered|.
  APPEND lv_trace TO gt_trace.

  lv_title = |Connections for { iv_carrid }|.

* Neither DDIC_STRUCTURE nor FIELD_TAB is passed: every component of
* ty_conn is typed from a DDIC field, and the function module can then
* work out the hit-list structure itself. Without such references the
* columns are named F0001, F0002 ... and RETFIELD has to match that.
  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield        = 'CONNID'
      value_org       = 'S'
      window_title    = lv_title
    TABLES
      value_tab       = lt_values
      return_tab      = lt_return
    EXCEPTIONS
      parameter_error = 1
      no_values_found = 2
      OTHERS          = 3.

  IF sy-subrc <> 0.
*   NO_VALUES_FOUND is a normal outcome (unknown airline), not a bug.
    RETURN.
  ENDIF.

* An EMPTY return table means the user pressed Cancel: "If RETURN_TAB
* does not contain any lines, the user has terminated the selection."
* A blind READ ... INDEX 1 would clear the field in that case.
  READ TABLE lt_return INTO ls_return INDEX 1.
  IF sy-subrc = 0.
    cv_connid = ls_return-fieldval.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Output
*&---------------------------------------------------------------------*
START-OF-SELECTION.

  DATA gv_line    TYPE string.
  DATA gv_name    TYPE scarr-carrname.
  DATA gv_entries TYPE i.

  SELECT SINGLE carrname
         FROM scarr
         WHERE carrid = @p_carrid
         INTO @gv_name.
  IF sy-subrc <> 0.
    gv_name = 'unknown'.
  ENDIF.

  WRITE: / 'Airline:   ', p_carrid, gv_name.
  WRITE: / 'P_CONN_W:  ', p_conn_w, '(help read the program variable)'.
  WRITE: / 'P_CONN_R:  ', p_conn_r, '(help read the screen)'.
  SKIP.

  gv_entries = lines( gt_trace ).
  IF gv_entries = 0.
    WRITE: / 'No F4 help was called in this run.'.
  ELSE.
    WRITE: / 'What each F4 call actually did:'.
    LOOP AT gt_trace INTO gv_line.
      WRITE: / '  ', gv_line.
    ENDLOOP.
  ENDIF.
