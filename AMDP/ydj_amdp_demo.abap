*&---------------------------------------------------------------------*
*& AMDP - ABAP Managed Database Procedures: the traps, in code
*&---------------------------------------------------------------------*
*& See README.md in this folder for the sourced explanation of each
*& numbered trap. Section numbers below match the README.
*&
*& IMPORTANT - how to use this file:
*&
*&   An AMDP class MUST be a GLOBAL class (a local class in a report
*&   cannot be an AMDP class), and AMDP classes can ONLY be created and
*&   edited in ABAP Development Tools (ADT / Eclipse) - not SE24, not
*&   SE80. So this file is in TWO parts:
*&
*&     PART 1 - the global class source. Create a class
*&              ZCL_YDJ_AMDP_DEMO in ADT and paste it there.
*&     PART 2 - a plain report that calls it. Create it with SE38 as
*&              YDJ_AMDP_DEMO, or run it in ADT.
*&
*&   Everything here only READS (OPTIONS READ-ONLY everywhere), uses
*&   the standard flight demo tables SCARR / SPFLI, and writes nothing
*&   to the database.
*&
*&   This runs on an AS ABAP whose standard database is SAP HANA. On any
*&   other database the call raises a runtime error by design - see
*&   trap 2 and the guard in IS_AMDP_SUPPORTED.
*&---------------------------------------------------------------------*


*&=====================================================================*
*& PART 1 - GLOBAL CLASS  ZCL_YDJ_AMDP_DEMO   (create in ADT)
*&=====================================================================*

*CLASS zcl_ydj_amdp_demo DEFINITION
*  PUBLIC
*  FINAL
*  CREATE PUBLIC.
*
*  PUBLIC SECTION.
*
** Trap 1: this tag interface is the ONLY thing in the declaration part
** that says "this class contains AMDP methods". The method
** declarations themselves look completely ordinary.
*    INTERFACES if_amdp_marker_hdb.
*
*    TYPES:
*      BEGIN OF ty_carrier,
*        mandt   TYPE scarr-mandt,
*        carrid  TYPE scarr-carrid,
*        carrname TYPE scarr-carrname,
*        currcode TYPE scarr-currcode,
*      END OF ty_carrier,
*      ty_carriers TYPE STANDARD TABLE OF ty_carrier WITH EMPTY KEY.
*
*    TYPES:
*      BEGIN OF ty_route_count,
*        carrid TYPE spfli-carrid,
*        routes TYPE i,
*      END OF ty_route_count,
*      ty_route_counts TYPE STANDARD TABLE OF ty_route_count WITH EMPTY KEY.
*
** Trap 8: every parameter is VALUE( ). Pass by reference - the default
** you normally get by writing nothing - is NOT PERMITTED here, and
** RETURNING is not allowed for an AMDP procedure at all.
**
** Trap 3: RAISING cx_amdp_error is the load-bearing part. Without it
** the CX_AMDP_* exceptions are NOT handleable at the call, and because
** they are CX_DYNAMIC_CHECK the compiler never warns you. A TRY/CATCH
** around a method declared without RAISING is dead code.
**
** Trap 9: iv_client is passed in explicitly. There is NO implicit
** client handling in AMDP - omit it and the procedure reads EVERY
** client's rows.
*    CLASS-METHODS select_carriers
*      IMPORTING VALUE(iv_client)   TYPE mandt
*      EXPORTING VALUE(et_carriers) TYPE ty_carriers
*      RAISING   cx_amdp_error.
*
*    CLASS-METHODS count_routes_by_carrier
*      IMPORTING VALUE(iv_client)  TYPE mandt
*                VALUE(iv_min_hops) TYPE i DEFAULT 0
*      EXPORTING VALUE(et_counts)  TYPE ty_route_counts
*      RAISING   cx_amdp_error.
*
** A REGULAR method - no AMDP. This is the documented portability
** pattern: callers use this, it decides whether the database can run
** AMDP at all and falls back to ABAP SQL if not (trap 2).
*    CLASS-METHODS get_carriers_portable
*      IMPORTING VALUE(iv_client)   TYPE mandt
*      EXPORTING VALUE(et_carriers) TYPE ty_carriers
*                VALUE(ev_used_amdp) TYPE abap_bool.
*
*    CLASS-METHODS is_amdp_supported
*      RETURNING VALUE(rv_supported) TYPE abap_bool.
*
*ENDCLASS.
*
*
*CLASS zcl_ydj_amdp_demo IMPLEMENTATION.
*
**---------------------------------------------------------------------*
** Trap 1 + 2 + 6: the implementation is where AMDP becomes visible.
**   BY DATABASE PROCEDURE - this body is NOT ABAP
**   FOR HDB              - runtime error on any other database
**   LANGUAGE SQLSCRIPT   - and it is only syntax-checked ON HANA
**   OPTIONS READ-ONLY    - reads only; contagious to methods it calls
**   USING scarr          - every ABAP-managed object must be listed,
**                          and every listed object must be USED
**---------------------------------------------------------------------*
*  METHOD select_carriers
*    BY DATABASE PROCEDURE
*    FOR HDB
*    LANGUAGE SQLSCRIPT
*    OPTIONS READ-ONLY
*    USING scarr.
*
** From here down this is SQLScript, not ABAP:
**   - a leading * in column 1 is an ABAP-style comment and is stored
**     on the database as the SQLScript -- comment (trap 10)
**   - input parameters take a leading colon in operand positions
**   - the client predicate is written BY HAND (trap 9)
*
*    et_carriers = SELECT mandt,
*                         carrid,
*                         carrname,
*                         currcode
*                    FROM scarr
*                   WHERE mandt = :iv_client
*                   ORDER BY carrid;
*
*  ENDMETHOD.
*
**---------------------------------------------------------------------*
** Trap 8: iv_min_hops is an optional input parameter, so it needs a
** DEFAULT, and that default must be a literal or a constant. An
** optional EXPORTING parameter would be rejected outright - only
** INPUT parameters may be optional.
**---------------------------------------------------------------------*
*  METHOD count_routes_by_carrier
*    BY DATABASE PROCEDURE
*    FOR HDB
*    LANGUAGE SQLSCRIPT
*    OPTIONS READ-ONLY
*    USING spfli.
*
*    et_counts = SELECT carrid,
*                       COUNT( * ) AS routes
*                  FROM spfli
*                 WHERE mandt = :iv_client
*                 GROUP BY carrid
*                HAVING COUNT( * ) >= :iv_min_hops
*                 ORDER BY carrid;
*
*  ENDMETHOD.
*
**---------------------------------------------------------------------*
** Regular ABAP from here on - no AMDP additions.
**---------------------------------------------------------------------*
*  METHOD is_amdp_supported.
*
*    rv_supported = cl_abap_dbfeatures=>use_features(
*      requested_features = VALUE #( ( cl_abap_dbfeatures=>call_amdp_method ) ) ).
*
*  ENDMETHOD.
*
*  METHOD get_carriers_portable.
*
*    CLEAR: et_carriers, ev_used_amdp.
*
*    IF is_amdp_supported( ) = abap_true.
*
** Trap 3 in practice: this CATCH only works because select_carriers
** declares RAISING cx_amdp_error. Remove the RAISING and this
** becomes a short dump instead.
*      TRY.
*          select_carriers(
*            EXPORTING iv_client   = iv_client
*            IMPORTING et_carriers = et_carriers ).
*          ev_used_amdp = abap_true.
*          RETURN.
*        CATCH cx_amdp_error.
*          CLEAR et_carriers.
*      ENDTRY.
*
*    ENDIF.
*
** Fallback: plain ABAP SQL. Note this is also what SAP's own
** guideline says to try FIRST (README section 0).
*    SELECT mandt, carrid, carrname, currcode
*      FROM scarr
*      ORDER BY carrid
*      INTO CORRESPONDING FIELDS OF TABLE @et_carriers.
*
*  ENDMETHOD.
*
*ENDCLASS.


*&=====================================================================*
*& PART 2 - CALLING REPORT  YDJ_AMDP_DEMO   (create with SE38)
*&=====================================================================*

REPORT ydj_amdp_demo.

PARAMETERS: p_hops TYPE i DEFAULT 2.

START-OF-SELECTION.

  PERFORM show_support.
  PERFORM show_carriers.
  PERFORM show_route_counts.


*&---------------------------------------------------------------------*
*& Trap 2 - never assume the database can run AMDP.
*&---------------------------------------------------------------------*
FORM show_support.

  DATA lv_supported TYPE abap_bool.
  DATA lv_text      TYPE string.

  lv_supported = zcl_ydj_amdp_demo=>is_amdp_supported( ).

  IF lv_supported = abap_true.
    lv_text = 'yes - AMDP procedures can be called here'.
  ELSE.
    lv_text = 'NO - calling an AMDP method would raise a runtime error'.
  ENDIF.

  WRITE: / 'Trap 2 - database supports AMDP:', lv_text.
  SKIP.

ENDFORM.

*&---------------------------------------------------------------------*
*& Trap 3 + 9 - the guarded call, with the client passed explicitly.
*&---------------------------------------------------------------------*
FORM show_carriers.

  DATA lt_carriers   TYPE zcl_ydj_amdp_demo=>ty_carriers.
  DATA lv_used_amdp  TYPE abap_bool.
  DATA lv_path       TYPE string.
  DATA lv_rows       TYPE i.

  zcl_ydj_amdp_demo=>get_carriers_portable(
    EXPORTING iv_client    = sy-mandt
    IMPORTING et_carriers  = lt_carriers
              ev_used_amdp = lv_used_amdp ).

  IF lv_used_amdp = abap_true.
    lv_path = 'AMDP (SQLScript on HANA)'.
  ELSE.
    lv_path = 'ABAP SQL fallback'.
  ENDIF.

  lv_rows = lines( lt_carriers ).

  WRITE: / 'Trap 3 - carriers read via:', lv_path.
  WRITE: / 'Rows returned:', lv_rows.
  SKIP.

  LOOP AT lt_carriers INTO DATA(ls_carrier) TO 5.
    WRITE: / ls_carrier-carrid, ls_carrier-carrname, ls_carrier-currcode.
  ENDLOOP.
  SKIP.

ENDFORM.

*&---------------------------------------------------------------------*
*& Trap 8 - the optional input parameter with its mandatory DEFAULT.
*&---------------------------------------------------------------------*
FORM show_route_counts.

  DATA lt_counts TYPE zcl_ydj_amdp_demo=>ty_route_counts.
  DATA lv_msg    TYPE string.

  IF zcl_ydj_amdp_demo=>is_amdp_supported( ) = abap_false.
    WRITE: / 'Trap 8 - skipped, no AMDP on this database.'.
    RETURN.
  ENDIF.

  TRY.
      zcl_ydj_amdp_demo=>count_routes_by_carrier(
        EXPORTING iv_client   = sy-mandt
                  iv_min_hops = p_hops
        IMPORTING et_counts   = lt_counts ).

      WRITE: / 'Trap 8 - carriers with at least', p_hops, 'routes:'.

      LOOP AT lt_counts INTO DATA(ls_count).
        WRITE: / ls_count-carrid, ls_count-routes.
      ENDLOOP.

    CATCH cx_amdp_error INTO DATA(lx_amdp).
      lv_msg = lx_amdp->get_text( ).
      WRITE: / 'AMDP call failed:', lv_msg.
  ENDTRY.

ENDFORM.
