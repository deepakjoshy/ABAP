*&---------------------------------------------------------------------*
*& Report  ydj_salv_table_demo
*&---------------------------------------------------------------------*
*& SALV (CL_SALV_TABLE): the ALV that starts with no functions at all,
*& the selection mode that must be NONE to select a row, the refresh
*& that loses the user's scroll position, and the aggregation that
*& refuses to total a NUMC column.
*&
*& Pick one variant on the selection screen and run. Each variant
*& displays the SAME internal table with ONE thing changed, so the
*& difference you see is the thing the README documents.
*&
*&   1  BARE      - factory + display and nothing else.
*&                  Expect: a grid with NO toolbar. No sort, no filter,
*&                  no export, no layout. This is the documented
*&                  starting state, not a bug.
*&   2  DEFAULT   - get_functions( )->set_default( )
*&   3  ALL       - get_functions( )->set_all( )
*&   4  SELECT    - set_all + selection mode, and a readout of what
*&                  get_selected_rows( ) returns (row NUMBERS, not rows)
*&   5  AGGR      - set_all + a total on a numeric column and an
*&                  attempted total on a NUMC column (the NUMC one
*&                  needs set_numerical_aggregation to work at all)
*&   6  LAYOUT    - set_all + set_key, so Save Layout actually saves
*&   7  POPUP     - set_all + set_screen_popup, display( ) unchanged
*&
*& WHY THERE IS NO "CUSTOM BUTTON" VARIANT: in a fullscreen ALV,
*& add_function( ) is documented as not available - the pushbutton has
*& to come from a GUI status built in SE41 inside this program. That
*& cannot be shipped in a single .abap file, so variant 4 registers the
*& ADDED_FUNCTION handler and the handler simply never fires. That is
*& the lesson, not an omission: see README section 2 for the four steps
*& and for the set_functions = C_FUNCTIONS_NONE default that silently
*& removes the standard toolbar once you do build the status.
*&
*& READ-ONLY: two SELECTs against the standard flight data model
*& (SPFLI, SFLIGHT). No INSERT/UPDATE/DELETE/MODIFY, no COMMIT, no
*& file access, no RFC. Runs as a plain report - no Screen Painter
*& object and no dynpro needed.
*&
*& Refs: https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/c28440729a68b8e10000000a42189e/content.htm
*&       https://help.sap.com/saphelp_em92/helpdata/en/4e/c39dbb88d22b90e10000000a42189d/content.htm
*&       https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/c3d14488d22b90e10000000a42189d/content.htm
*&       https://help.sap.com/doc/saphelp_em900/9.0/en-US/4e/bc6ddaf39c68bbe10000000a42189e/content.htm
*&---------------------------------------------------------------------*
REPORT ydj_salv_table_demo.

*----------------------------------------------------------------------*
* The displayed row type.
*
* CARRID / CONNID / CITYFROM / CITYTO / DISTID come from SPFLI, so they
* arrive with DDIC column texts for free. CONNID is NUMC 4 - that is
* the column the aggregation variant cannot total by default.
*
* FLIGHTS and SEATS_OCC are COMPUTED here, so they have no DDIC
* reference at all and would display with blank headers. Variant 1
* shows that; set_column_texts below fixes it.
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_row,
         carrid    TYPE spfli-carrid,
         connid    TYPE spfli-connid,      " NUMC 4 - see variant 5
         cityfrom  TYPE spfli-cityfrom,
         cityto    TYPE spfli-cityto,
         distance  TYPE spfli-distance,
         distid    TYPE spfli-distid,
         flights   TYPE i,                 " computed - no DDIC ref
         seats_occ TYPE i,                 " computed - no DDIC ref
       END OF ty_row.
TYPES ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

*----------------------------------------------------------------------*
* Event handler.
*
* ADDED_FUNCTION is registered in variant 4 and will NEVER be called,
* because this report has no GUI status of its own and therefore no
* custom pushbutton exists to raise it. DOUBLE_CLICK, by contrast,
* needs no GUI status and does fire - which is a clean way to see that
* the event machinery is working and the BUTTON is what is missing.
*----------------------------------------------------------------------*
CLASS lcl_handler DEFINITION CREATE PUBLIC.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING it_rows TYPE ty_rows.

    " Fires on double-click. No GUI status required.
    METHODS on_double_click
      FOR EVENT double_click OF cl_salv_events_table
      IMPORTING row column.

    " Would fire for a self-defined function code. In a fullscreen ALV
    " there is no way to create one from ABAP, so in this report it is
    " unreachable on purpose.
    METHODS on_added_function
      FOR EVENT added_function OF cl_salv_events_table
      IMPORTING e_salv_function.

  PRIVATE SECTION.
    DATA mt_rows TYPE ty_rows.
ENDCLASS.

CLASS lcl_handler IMPLEMENTATION.

  METHOD constructor.
    mt_rows = it_rows.
  ENDMETHOD.

  METHOD on_double_click.
    " ROW is an index into the table handed to factory( ), which is why
    " this reads mt_rows by INDEX and not by key.
    DATA lv_msg TYPE string.
    DATA lv_row TYPE string.
    DATA lv_col TYPE string.

    lv_row = |{ row }|.
    lv_col = column.

    READ TABLE mt_rows INDEX row ASSIGNING FIELD-SYMBOL(<ls_row>).
    IF sy-subrc = 0.
      lv_msg = |row { lv_row }, column { lv_col } -> | &&
               |{ <ls_row>-carrid } { <ls_row>-connid }|.
    ELSE.
      " Reachable: a double-click on the aggregation/total line has a
      " row number that is not an index into the data table.
      lv_msg = |row { lv_row } is not a data row (total line?)|.
    ENDIF.

    MESSAGE lv_msg TYPE 'S'.
  ENDMETHOD.

  METHOD on_added_function.
    " Unreachable in this report - see the class comment.
    DATA lv_fcode TYPE string.
    DATA lv_msg   TYPE string.

    lv_fcode = e_salv_function.
    lv_msg   = |self-defined function { lv_fcode }|.
    MESSAGE lv_msg TYPE 'S'.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Main
*----------------------------------------------------------------------*
CLASS lcl_demo DEFINITION CREATE PUBLIC.
  PUBLIC SECTION.
    METHODS run
      IMPORTING iv_variant TYPE c.

  PRIVATE SECTION.
    DATA mt_rows   TYPE ty_rows.
    DATA mo_alv    TYPE REF TO cl_salv_table.
    DATA mo_handler TYPE REF TO lcl_handler.

    METHODS select_data.
    METHODS build_alv.
    METHODS set_column_texts.
    METHODS add_functions.
    METHODS add_selections.
    METHODS add_aggregations.
    METHODS add_layout_key.
    METHODS make_popup.
ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

  METHOD run.
    select_data( ).

    IF mt_rows IS INITIAL.
      MESSAGE 'No SPFLI data in this system - nothing to display' TYPE 'S'.
      RETURN.
    ENDIF.

    build_alv( ).
    IF mo_alv IS NOT BOUND.
      RETURN.
    ENDIF.

    " Column texts are set for every variant except the bare one, so
    " that variant 1 also shows what a missing DDIC reference looks
    " like on the two computed columns.
    IF iv_variant <> '1'.
      set_column_texts( ).
    ENDIF.

    CASE iv_variant.
      WHEN '1'.
        " Nothing. factory + display only.
      WHEN '2'.
        mo_alv->get_functions( )->set_default( ).
      WHEN '3'.
        add_functions( ).
      WHEN '4'.
        add_functions( ).
        add_selections( ).
      WHEN '5'.
        add_functions( ).
        add_aggregations( ).
      WHEN '6'.
        add_functions( ).
        add_layout_key( ).
      WHEN '7'.
        add_functions( ).
        make_popup( ).
      WHEN OTHERS.
        add_functions( ).
    ENDCASE.

    " display( ) takes no parameters at all. Everything above is how
    " you configure the output; this just renders it.
    mo_alv->display( ).
  ENDMETHOD.

  METHOD select_data.
    DATA lt_spfli TYPE STANDARD TABLE OF spfli WITH EMPTY KEY.
    DATA lv_flights   TYPE i.
    DATA lv_seats_occ TYPE i.

    " Strict ABAP SQL (comma-separated list, @-escaped host variables).
    " Clause order is fixed in strict mode: ORDER BY, then INTO, then
    " UP TO -- which reads backwards compared to the obsolete form.
    SELECT carrid, connid, cityfrom, cityto, distance, distid
      FROM spfli
      ORDER BY carrid, connid
      INTO CORRESPONDING FIELDS OF TABLE @lt_spfli
      UP TO 40 ROWS.

    LOOP AT lt_spfli ASSIGNING FIELD-SYMBOL(<ls_spfli>).

      " Aggregate the flights for this connection. Deliberately a
      " second read rather than a join, so the two computed columns
      " have no DDIC reference of any kind.
      CLEAR lv_flights.
      CLEAR lv_seats_occ.

      SELECT COUNT( * ) AS cnt, SUM( seatsocc ) AS occ
        FROM sflight
        WHERE carrid = @<ls_spfli>-carrid
          AND connid = @<ls_spfli>-connid
        INTO (@lv_flights, @lv_seats_occ).
      " A SELECT list made only of aggregates with no GROUP BY returns
      " a ROW even when nothing matched: sy-subrc = 0, SUM arrives as
      " NULL and is converted to the initial value. So lv_seats_occ = 0
      " here means "no flights" and "flights with no occupied seats"
      " indistinguishably -- see the repo's Null Values note. Harmless
      " for a display demo; not harmless in a report that branches on
      " sy-subrc after this.

      APPEND VALUE ty_row( carrid    = <ls_spfli>-carrid
                           connid    = <ls_spfli>-connid
                           cityfrom  = <ls_spfli>-cityfrom
                           cityto    = <ls_spfli>-cityto
                           distance  = <ls_spfli>-distance
                           distid    = <ls_spfli>-distid
                           flights   = lv_flights
                           seats_occ = lv_seats_occ )
             TO mt_rows.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_alv.
    " T_TABLE is a CHANGING parameter passed BY REFERENCE. The ALV does
    " not copy mt_rows - it reads it. mt_rows is an instance attribute
    " precisely so that it outlives this method; a local table here
    " would leave the ALV holding a reference to dead data.
    "
    " Omitting LIST_DISPLAY / R_CONTAINER / CONTAINER_NAME gives the
    " FULLSCREEN display type (LIST_DISPLAY defaults to FALSE), which
    " is the display type in which add_function( ) does not work.
    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = mo_alv
                                CHANGING  t_table      = mt_rows ).
      CATCH cx_salv_msg INTO DATA(lo_err).
        " get_text( ) hoisted out of the MESSAGE operand: a functional
        " call is not allowed there, same rule the repo's Regular
        " Expressions and String Processing notes record for WRITE.
        DATA(lv_err) = lo_err->get_text( ).
        MESSAGE lv_err TYPE 'S' DISPLAY LIKE 'E'.
        CLEAR mo_alv.
        RETURN.
    ENDTRY.

    " Optimise column widths. Harmless everywhere, and it makes the
    " blank headers in variant 1 easier to spot.
    mo_alv->get_columns( )->set_optimize( abap_true ).
  ENDMETHOD.

  METHOD set_column_texts.
    " The six SPFLI columns need nothing - their DDIC reference already
    " carried short/medium/long text and the F1 help.
    "
    " FLIGHTS and SEATS_OCC are computed and have no DDIC reference, so
    " they need all three texts set by hand. Setting only the long text
    " leaves a narrow column blank-headed, because ALV picks by the
    " width it has available.
    DATA lo_cols TYPE REF TO cl_salv_columns_table.
    DATA lo_col  TYPE REF TO cl_salv_column.

    lo_cols = mo_alv->get_columns( ).

    TRY.
        lo_col = lo_cols->get_column( 'FLIGHTS' ).
        lo_col->set_short_text( 'Flights' ).
        lo_col->set_medium_text( 'Flights' ).
        lo_col->set_long_text( 'Number of flights' ).

        lo_col = lo_cols->get_column( 'SEATS_OCC' ).
        lo_col->set_short_text( 'Seats' ).
        lo_col->set_medium_text( 'Seats occupied' ).
        lo_col->set_long_text( 'Total seats occupied' ).
      CATCH cx_salv_not_found.
        " Column name typo would land here. Nothing to recover.
    ENDTRY.
  ENDMETHOD.

  METHOD add_functions.
    " Without this, the ALV has no sort, no filter, no export and no
    " layout management. Not a styling choice - the documented default.
    "
    " set_all( ) enables every generic ALV function; set_default( )
    " enables SAP's preset selection of the common ones (variant 2).
    mo_alv->get_functions( )->set_all( abap_true ).
  ENDMETHOD.

  METHOD add_selections.
    DATA lo_sel TYPE REF TO cl_salv_selections.

    lo_sel = mo_alv->get_selections( ).

    " ROW_COLUMN is what gives the user a clickable row selector in a
    " FULLSCREEN ALV. Note what the documentation's table says about
    " the neighbouring cases:
    "   - single-row selection in fullscreen needs NONE (the default)
    "   - SINGLE is the setting for the CLASSIC LIST display type
    " So this one line means something different if this report is ever
    " switched to list_display = abap_true.
    lo_sel->set_selection_mode( if_salv_c_selection_mode=>row_column ).

    " Register both handlers. on_double_click will fire; on_added_
    " function cannot, because there is no GUI status and therefore no
    " self-defined function code to raise it.
    CREATE OBJECT mo_handler
      EXPORTING it_rows = mt_rows.

    DATA lo_events TYPE REF TO cl_salv_events_table.
    lo_events = mo_alv->get_event( ).

    SET HANDLER mo_handler->on_double_click   FOR lo_events.
    SET HANDLER mo_handler->on_added_function FOR lo_events.
  ENDMETHOD.

  METHOD add_aggregations.
    DATA lo_aggrs TYPE REF TO cl_salv_aggregations.

    lo_aggrs = mo_alv->get_aggregations( ).

    " SEATS_OCC is type i - aggregates with no special handling.
    TRY.
        lo_aggrs->add_aggregation( columnname  = 'SEATS_OCC'
                                   aggregation = if_salv_c_aggregation=>total ).
      CATCH cx_salv_data_error cx_salv_not_found cx_salv_existing.
        " add_aggregation is a checked call; a wrong column name or a
        " second aggregation on the same column lands here. One
        " aggregation per column is the documented maximum.
    ENDTRY.

    " CONNID is NUMC 4. By default ALV excludes NUMC from aggregation
    " even though it looks numeric, so the call below does not give you
    " a total until set_numerical_aggregation has allowed it.
    "
    " Kept here because this is the exact shape of the "why will my
    " document number column not total" question. Whether it SHOULD
    " total is a separate matter: summing connection numbers is
    " meaningless, which is why SAP's default is the sensible one.
    TRY.
        lo_aggrs->set_numerical_aggregation( abap_true ).
        lo_aggrs->add_aggregation( columnname  = 'CONNID'
                                   aggregation = if_salv_c_aggregation=>total ).
      CATCH cx_salv_data_error cx_salv_not_found cx_salv_existing.
        " Reachable on releases where NUMC stays excluded regardless.
    ENDTRY.
  ENDMETHOD.

  METHOD add_layout_key.
    DATA lo_layout TYPE REF TO cl_salv_layout.
    DATA ls_key    TYPE salv_s_layout_key.

    lo_layout = mo_alv->get_layout( ).

    " THIS is the load-bearing call. Without a layout key there is
    " nothing for a saved layout to be keyed against, so the Save
    " Layout button appears (set_all enabled it) and does nothing.
    "
    " sy-cprog, not sy-repid: sy-repid can be overwritten at runtime
    " by the name of a function group, which is the same trap the
    " Input Help note documents for DYNP_VALUES_READ.
    ls_key-report = sy-cprog.
    lo_layout->set_key( ls_key ).

    " Deliberately NOT calling set_save_restriction( restrict_none ):
    " that is already the parameter's default, so the line every
    " snippet carries changes nothing. Shown as a comment rather than
    " as code, so this file does not propagate it:
    "
    "   lo_layout->set_save_restriction( cl_salv_layout=>restrict_none ).
    "
    " Allow the user to mark one layout as their default.
    lo_layout->set_default( abap_true ).
  ENDMETHOD.

  METHOD make_popup.
    " display( ) takes no parameters, so "display it as a popup" is
    " configured beforehand and not passed in. Size is implied by the
    " four coordinates, in character columns and rows.
    mo_alv->set_screen_popup( start_column = 5
                              end_column   = 120
                              start_line   = 3
                              end_line     = 22 ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Selection screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME.
PARAMETERS: p_bare  RADIOBUTTON GROUP g1 DEFAULT 'X',  " 1 no functions
            p_deflt RADIOBUTTON GROUP g1,             " 2 set_default
            p_all   RADIOBUTTON GROUP g1,             " 3 set_all
            p_sel   RADIOBUTTON GROUP g1,             " 4 selections
            p_aggr  RADIOBUTTON GROUP g1,             " 5 aggregations
            p_layo  RADIOBUTTON GROUP g1,             " 6 layout key
            p_popup RADIOBUTTON GROUP g1.             " 7 popup
SELECTION-SCREEN END OF BLOCK b1.

*----------------------------------------------------------------------*
START-OF-SELECTION.

  DATA gv_variant TYPE c LENGTH 1.

  " No WITH FRAME TITLE above and no TEXT-nnn here: an unmaintained
  " text symbol renders as a silent blank, which the repo's Text
  " Elements note documents. Plain literals instead.
  CASE abap_true.
    WHEN p_bare.  gv_variant = '1'.
    WHEN p_deflt. gv_variant = '2'.
    WHEN p_all.   gv_variant = '3'.
    WHEN p_sel.   gv_variant = '4'.
    WHEN p_aggr.  gv_variant = '5'.
    WHEN p_layo.  gv_variant = '6'.
    WHEN p_popup. gv_variant = '7'.
    WHEN OTHERS.  gv_variant = '1'.
  ENDCASE.

  DATA(go_demo) = NEW lcl_demo( ).
  go_demo->run( gv_variant ).
