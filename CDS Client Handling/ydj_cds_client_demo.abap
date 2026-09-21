*&---------------------------------------------------------------------*
*& Report YDJ_CDS_CLIENT_DEMO
*&
*& CDS view entities: client handling traps.
*&
*& The four ABAP SQL client additions, run READ-ONLY against the
*& standard flight table SFLIGHT, plus the rules that decide which of
*& them a CDS view entity will actually accept.
*&
*& Nothing here creates, changes or deletes anything. No DDIC object
*& has to exist beyond SFLIGHT and T000.
*&
*& Notes: CDS View Entities | Client Handling (README.md in this folder)
*& Docs : ABENCDS_VIEW_CLIENT_HDL_DEF, ABAPSELECT_CLIENT,
*&        ABENABAP_SQL_CLIENT_HANDLING
*&---------------------------------------------------------------------*
REPORT ydj_cds_client_demo.

*&---------------------------------------------------------------------*
*& The two DDL artifacts this note is about (separate repository
*& objects in ADT - shown here as comments for readability only).
*&---------------------------------------------------------------------*
*  --- OLD: CDS DDIC-based view (obsolete) --------------------------
*  @AbapCatalog.sqlViewName: 'ZDJFLIGHTV1'
*  @ClientHandling.type: #CLIENT_DEPENDENT
*  @ClientHandling.algorithm: #AUTOMATED      " <- T000 cross join
*  @AccessControl.authorizationCheck: #NOT_REQUIRED
*  define view zdj_flight_v1 as select from sflight as f
*  {
*    key f.mandt,                             " <- legal here
*    key f.carrid,
*    key f.connid,
*        f.seatsocc
*  }
*
*  --- NEW: CDS view entity -----------------------------------------
*  @AccessControl.authorizationCheck: #NOT_REQUIRED
*  define view entity zdj_flight_v2 as select from sflight as f
*  {
*    key f.carrid,                            " no mandt: a client
*    key f.connid,                            " element is a SYNTAX
*        f.seatsocc                           " ERROR in a view entity
*  }
*
*  Differences that do NOT appear in this diff:
*   - no @ClientHandling in v2: dependency is derived from SFLIGHT
*   - v2 always uses the $session.client algorithm, so an outer join
*     with a client-independent side is expanded DIFFERENTLY than the
*     #AUTOMATED T000 cross join of v1 -> different row count
*   - SELECT ... USING ALL CLIENTS / CLIENT SPECIFIED are rejected on v2
*   - @AbapCatalog.buffering.* is not supported on v2 at all

DATA: lv_client       TYPE sy-mandt,
      lv_cnt_current  TYPE i,
      lv_cnt_all      TYPE i,
      lv_cnt_t000     TYPE i,
      lv_cnt_explicit TYPE i,
      lv_extra        TYPE i.

DATA: BEGIN OF ls_per_client,
        mandt TYPE sflight-mandt,
        cnt   TYPE i,
      END OF ls_per_client.
DATA lt_per_client LIKE TABLE OF ls_per_client.

START-OF-SELECTION.

*&---------------------------------------------------------------------*
*& 1) Default: implicit client handling, current client only
*&---------------------------------------------------------------------*
  SELECT COUNT( * )
    FROM sflight
    INTO @lv_cnt_current.

  WRITE: / 'Current client                :', sy-mandt.
  WRITE: / '1) rows, implicit handling    :', lv_cnt_current.

*&---------------------------------------------------------------------*
*& 2) USING ALL CLIENTS - no implicit WHERE on the client column.
*&    Works on a database table. On a CDS VIEW ENTITY this addition
*&    is NOT ALLOWED (syntax error), and neither is CLIENT SPECIFIED.
*&---------------------------------------------------------------------*
  SELECT COUNT( * )
    FROM sflight USING ALL CLIENTS
    INTO @lv_cnt_all.

  lv_extra = lv_cnt_all - lv_cnt_current.

  WRITE: / '2) rows, USING ALL CLIENTS    :', lv_cnt_all.
  WRITE: / '   rows in OTHER clients      :', lv_extra.

*&---------------------------------------------------------------------*
*& 3) USING CLIENTS IN T000 - restricted to the clients that really
*&    exist. If 2) and 3) differ, SFLIGHT holds rows with client IDs
*&    that are not in T000 at all.
*&---------------------------------------------------------------------*
  SELECT COUNT( * )
    FROM sflight USING CLIENTS IN t000
    INTO @lv_cnt_t000.

  WRITE: / '3) rows, USING CLIENTS IN T000:', lv_cnt_t000.

  IF lv_cnt_t000 <> lv_cnt_all.
    WRITE: / '   -> client IDs in SFLIGHT that are not listed in T000'.
  ENDIF.

*&---------------------------------------------------------------------*
*& 4) The client column in the SELECT list.
*&    Legal over a table. Over a CDS view entity it is impossible:
*&    "a client field is not allowed in the SELECT list of a view
*&    entity" and the result set "can never contain a client column".
*&    For an entity, the only way back to the client ID is the
*&    addition EXPOSE CLIENT AS clnt_col together with USING CLIENTS.
*&---------------------------------------------------------------------*
  SELECT mandt, COUNT( * ) AS cnt
    FROM sflight USING ALL CLIENTS
    GROUP BY mandt
    ORDER BY mandt
    INTO TABLE @lt_per_client.

  WRITE: / '4) rows per client (table only):'.
  LOOP AT lt_per_client INTO ls_per_client.
    WRITE: / '   client', ls_per_client-mandt, '->', ls_per_client-cnt.
  ENDLOOP.

*&---------------------------------------------------------------------*
*& 5) USING CLIENT clnt - the one cross-client addition a view entity
*&    still accepts, and only when CDS access control is switched off
*&    (@AccessControl.authorizationCheck: #NOT_ALLOWED) or the FROM
*&    clause uses WITH PRIVILEGED ACCESS. Otherwise: syntax error if
*&    statically recognizable, exception at runtime otherwise.
*&
*&    clnt is a c LENGTH 3 literal or HOST VARIABLE. sy-mandt cannot
*&    be specified directly, so it is copied into a local first.
*&---------------------------------------------------------------------*
  lv_client = sy-mandt.

  SELECT COUNT( * )
    FROM sflight USING CLIENT @lv_client
    INTO @lv_cnt_explicit.

  WRITE: / '5) rows, USING CLIENT @local  :', lv_cnt_explicit.

  IF lv_cnt_explicit = lv_cnt_current.
    WRITE: / '   -> same as 1): USING CLIENT with the current client'.
    WRITE: / '      is a no-op; the risk is passing a different one.'.
  ENDIF.

*&---------------------------------------------------------------------*
*& Deliberately NOT executed - each of these is a syntax error:
*&
*&   SELECT COUNT( * ) FROM sflight USING CLIENT sy-mandt INTO @lv_cnt.
*&     -> sy-mandt cannot be specified directly for clnt
*&
*&   SELECT ... FROM zdj_flight_v2 USING ALL CLIENTS ...
*&     -> USING ALL CLIENTS is not allowed for CDS view entities
*&
*&   SELECT ... FROM zdj_flight_v2 CLIENT SPECIFIED ...
*&     -> obsolete in queries, and not allowed for view entities;
*&        outside strict mode from release 7.77 it is still parsed,
*&        which is why old code compiles until the view is migrated
*&---------------------------------------------------------------------*
