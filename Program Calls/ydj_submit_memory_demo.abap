*&---------------------------------------------------------------------*
*& Report YDJ_SUBMIT_MEMORY_DEMO
*&---------------------------------------------------------------------*
*& Passing data between programs - SUBMIT, ABAP Memory and SPA/GPA.
*&
*& Every case below returns a wrong-but-plausible result or reports
*& success where there is none. None of them is a syntax error.
*&
*&   1. IMPORT MERGE   -> a parameter that is NOT in the cluster is
*&                        IGNORED and the target keeps its PREVIOUS
*&                        value, while sy-subrc stays 0. In a loop the
*&                        second document inherits the first one's data.
*&   2. CLUSTER ID     -> the MEMORY ID is CASE-SENSITIVE (max 60 chars),
*&                        so 'zdj_ctx' and 'ZDJ_CTX' are two different
*&                        clusters. Usual cause of a surprise subrc 4.
*&   3. EXPORT REPLACE -> EXPORT overwrites a cluster COMPLETELY. Only
*&                        IMPORT merges - exporting a subset silently
*&                        drops every parameter you did not re-export.
*&   4. RSPARAMS 45    -> RSPARAMS-LOW is CHAR(45), so a longer value is
*&                        truncated with no error. RSPARAMSL_255 is the
*&                        7.2+ replacement (CHAR(255)).
*&   5. SPA/GPA        -> GET PARAMETER INITIALIZES the target on
*&                        sy-subrc = 4 (opposite of IMPORT), the ID is
*&                        case-sensitive and capped at 20 characters.
*&   6. STRUCT TOLERANCE-> a target structure with MORE components than
*&                        the exported one is accepted; the surplus
*&                        components come back INITIAL, no exception.
*&
*& Read-only: no database access, no SUBMIT is actually executed (the
*& SUBMIT variants are shown as comments so the demo cannot start
*& another program). Only the ABAP Memory of this session is written,
*& and it is cleaned up at the end.
*&
*& Docs: https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapsubmit.htm
*&       https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapsubmit_selscreen_parameters.htm
*&       https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapsubmit_list_options.htm
*&       https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapexport_data_cluster_medium.htm
*&       https://help.sap.com/doc/abapdocu_750_index_htm/7.50/en-US/abapimport_parameterlist.htm
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPFREE_MEMORY.html
*&       https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapset_parameter.htm
*&---------------------------------------------------------------------*
REPORT ydj_submit_memory_demo.

TYPES: BEGIN OF ty_order,
         order_id TYPE c LENGTH 10,
         customer TYPE c LENGTH 10,
         note     TYPE string,
       END OF ty_order.

*   Same structure plus one component at the END - the documented
*   "target may have more components" case (trap 6).
TYPES: BEGIN OF ty_order_ext,
         order_id TYPE c LENGTH 10,
         customer TYPE c LENGTH 10,
         note     TYPE string,
         currency TYPE c LENGTH 5,
       END OF ty_order_ext.

CONSTANTS gc_id_upper TYPE c LENGTH 20 VALUE 'YDJ_DEMO_CTX'.
CONSTANTS gc_id_lower TYPE c LENGTH 20 VALUE 'ydj_demo_ctx'.


CLASS lcl_call_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      import_merges,
      id_is_case_sensitive,
      export_replaces,
      rsparams_truncates,
      spa_gpa_contract,
      structure_tolerance,
      cleanup.

ENDCLASS.


CLASS lcl_call_demo IMPLEMENTATION.

  METHOD import_merges.
*   1. IMPORT is a MERGE. A parameter missing from the cluster is
*      ignored and the target field keeps whatever it held before -
*      with sy-subrc = 0, because the CLUSTER was found.
    DATA lv_order    TYPE c LENGTH 10.
    DATA lv_customer TYPE c LENGTH 10.
    DATA lv_subrc    TYPE sy-subrc.

    WRITE: / '--- 1. IMPORT merges, it does not assign'.

*   Producer A exports BOTH parameters (the complete document).
    DATA lv_ord_a  TYPE c LENGTH 10 VALUE '4711'.
    DATA lv_cust_a TYPE c LENGTH 10 VALUE 'ACME'.
    EXPORT p_order    = lv_ord_a
           p_customer = lv_cust_a
           TO MEMORY ID gc_id_upper.

    IMPORT p_order    = lv_order
           p_customer = lv_customer
           FROM MEMORY ID gc_id_upper.
    lv_subrc = sy-subrc.
    WRITE: / '  doc 1  subrc:', lv_subrc,
             'order:', lv_order, 'customer:', lv_customer.

*   Producer B exports ONLY the order - customer is optional here.
    DATA lv_ord_b TYPE c LENGTH 10 VALUE '4712'.
    EXPORT p_order = lv_ord_b
           TO MEMORY ID gc_id_upper.

    IMPORT p_order    = lv_order
           p_customer = lv_customer
           FROM MEMORY ID gc_id_upper.
    lv_subrc = sy-subrc.

*   customer STILL shows ACME - doc 2 billed to doc 1's customer.
    WRITE: / '  doc 2  subrc:', lv_subrc,
             'order:', lv_order, 'customer:', lv_customer,
             '<- stale, not cleared'.

*   The fix is yours to make: initialize before every IMPORT.
    CLEAR: lv_order, lv_customer.
    IMPORT p_order    = lv_order
           p_customer = lv_customer
           FROM MEMORY ID gc_id_upper.
    WRITE: / '  doc 2 after CLEAR  order:', lv_order,
             'customer:', lv_customer, '<- correct (empty)'.

  ENDMETHOD.


  METHOD id_is_case_sensitive.
*   2. The MEMORY ID is a case-sensitive string of up to 60 characters.
*      Same letters, different case = a different cluster entirely.
    DATA lv_value TYPE string.
    DATA lv_subrc TYPE sy-subrc.

    WRITE: / '--- 2. MEMORY ID is case-sensitive'.

    DATA(lv_text) = `written under the UPPERCASE id`.
    EXPORT p_text = lv_text TO MEMORY ID gc_id_upper.

    IMPORT p_text = lv_value FROM MEMORY ID gc_id_lower.
    lv_subrc = sy-subrc.
    WRITE: / '  read with lowercase id  subrc:', lv_subrc,
             '<- 4, cluster not found'.

    IMPORT p_text = lv_value FROM MEMORY ID gc_id_upper.
    lv_subrc = sy-subrc.
    WRITE: / '  read with uppercase id  subrc:', lv_subrc,
             'value:', lv_value.

  ENDMETHOD.


  METHOD export_replaces.
*   3. EXPORT overwrites the whole cluster. Only IMPORT is tolerant -
*      EXPORT is all-or-nothing, so re-exporting a subset drops the rest.
    DATA lv_a TYPE string.
    DATA lv_b TYPE string.
    DATA lv_subrc TYPE sy-subrc.

    WRITE: / '--- 3. EXPORT replaces the cluster completely'.

    DATA(lv_one) = `alpha`.
    DATA(lv_two) = `beta`.
    EXPORT p_a = lv_one
           p_b = lv_two
           TO MEMORY ID gc_id_upper.

*   Re-export only p_a, e.g. from a "just refresh this one field" helper.
    DATA(lv_one_new) = `alpha (updated)`.
    EXPORT p_a = lv_one_new TO MEMORY ID gc_id_upper.

    CLEAR: lv_a, lv_b.
    IMPORT p_a = lv_a
           p_b = lv_b
           FROM MEMORY ID gc_id_upper.
    lv_subrc = sy-subrc.

    WRITE: / '  subrc:', lv_subrc, 'p_a:', lv_a.
    WRITE: / '  p_b  :', lv_b, '<- gone, never reported'.

  ENDMETHOD.


  METHOD rsparams_truncates.
*   4. RSPARAMS-LOW / -HIGH are CHAR(45). Values passed via
*      SUBMIT ... WITH SELECTION-TABLE are cut at 45 characters with
*      no error at all. RSPARAMSL_255 (7.2+) carries 255.
    DATA lt_rspar   TYPE TABLE OF rsparams.
    DATA lt_rspar_l TYPE TABLE OF rsparamsl_255.
    DATA lv_len     TYPE i.

    WRITE: / '--- 4. RSPARAMS truncates LOW at 45 characters'.

*   A 60-character value - a concatenated key, a URL, a long text.
    DATA(lv_long) = |{ repeat( val = 'X' occ = 60 ) }|.
    lv_len = strlen( lv_long ).
    WRITE: / '  source value length:', lv_len.

    APPEND VALUE rsparams( selname = 'S_MATNR'
                           kind    = 'S'
                           sign    = 'I'
                           option  = 'EQ'
                           low     = lv_long ) TO lt_rspar.

    APPEND VALUE rsparamsl_255( selname = 'S_MATNR'
                                kind    = 'S'
                                sign    = 'I'
                                option  = 'EQ'
                                low     = lv_long ) TO lt_rspar_l.

    READ TABLE lt_rspar INTO DATA(ls_rspar) INDEX 1.
    IF sy-subrc = 0.
      lv_len = strlen( ls_rspar-low ).
      WRITE: / '  stored in RSPARAMS-LOW      :', lv_len, '<- silently cut'.
    ENDIF.

    READ TABLE lt_rspar_l INTO DATA(ls_rspar_l) INDEX 1.
    IF sy-subrc = 0.
      lv_len = strlen( ls_rspar_l-low ).
      WRITE: / '  stored in RSPARAMSL_255-LOW :', lv_len.
    ENDIF.

*   For reference - the call that would consume the table. Not executed
*   here, since this demo must not start another program:
*
*     SUBMIT zreport_child WITH SELECTION-TABLE lt_rspar_l
*                          AND RETURN.
*
*   And the LUW-safe form when update modules are already registered:
*
*     COMMIT WORK.
*     SUBMIT zreport_child AND RETURN.

  ENDMETHOD.


  METHOD spa_gpa_contract.
*   5. GET PARAMETER INITIALIZES the target when the parameter does not
*      exist (sy-subrc = 4) - the opposite habit to IMPORT. The ID is
*      case-sensitive, max 20 characters, and must exist in TPARA.
    DATA lv_value TYPE c LENGTH 20.
    DATA lv_subrc TYPE sy-subrc.

    WRITE: / '--- 5. SET / GET PARAMETER'.

*   CAR (airline carrier) is an SAP-delivered TPARA entry used by the
*   flight demo data, so this runs on any system without customizing.
    DATA lv_carrier TYPE c LENGTH 3 VALUE 'LH'.
    SET PARAMETER ID 'CAR' FIELD lv_carrier.

    lv_value = 'PRESET BY CALLER'.
    GET PARAMETER ID 'CAR' FIELD lv_value.
    lv_subrc = sy-subrc.
    WRITE: / '  GET CAR  subrc:', lv_subrc, 'value:', lv_value.

*   An ID that was never set: the target is INITIALIZED, so the preset
*   value is lost - you get a blank, never stale data. The ID is held in
*   a variable on purpose - a literal that is not in TPARA is reported
*   as an error by the extended program check.
    DATA lv_pid TYPE tpara-paramid VALUE 'YDJ_NO_SUCH_PARAM'.
    lv_value = 'PRESET BY CALLER'.
    GET PARAMETER ID lv_pid FIELD lv_value.
    lv_subrc = sy-subrc.
    WRITE: / '  GET unknown  subrc:', lv_subrc,
             'value:', lv_value, '<- initialized, not stale'.

  ENDMETHOD.


  METHOD structure_tolerance.
*   6. A target structure may have MORE components at the top level
*      than the exported one. The surplus components are set to their
*      initial values - accepted silently, no exception.
    DATA ls_ext   TYPE ty_order_ext.
    DATA lv_subrc TYPE sy-subrc.

    WRITE: / '--- 6. Structure tolerance on IMPORT'.

    DATA(ls_src) = VALUE ty_order( order_id = '4711'
                                   customer = 'ACME'
                                   note     = `rush order` ).
    EXPORT p_doc = ls_src TO MEMORY ID gc_id_upper.

    ls_ext-currency = 'EUR'.
    IMPORT p_doc = ls_ext FROM MEMORY ID gc_id_upper.
    lv_subrc = sy-subrc.

    WRITE: / '  subrc:', lv_subrc,
             'order:', ls_ext-order_id, 'customer:', ls_ext-customer.
    WRITE: / '  currency:', ls_ext-currency,
             '<- wiped to initial, no error'.

  ENDMETHOD.


  METHOD cleanup.
*   DELETE FROM MEMORY needs the ID and removes exactly one cluster.
*   Bare FREE MEMORY (no ID) would delete EVERY cluster of the session,
*   including those belonging to the program that called us.
    DELETE FROM MEMORY ID gc_id_upper.
    WRITE: / '--- cleanup: one cluster removed by ID'.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_call_demo=>import_merges( ).
  lcl_call_demo=>id_is_case_sensitive( ).
  lcl_call_demo=>export_replaces( ).
  lcl_call_demo=>rsparams_truncates( ).
  lcl_call_demo=>spa_gpa_contract( ).
  lcl_call_demo=>structure_tolerance( ).
  lcl_call_demo=>cleanup( ).
