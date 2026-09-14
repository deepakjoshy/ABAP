*&---------------------------------------------------------------------*
*& Report YDJ_AUTHORITY_CHECK_DEMO
*&---------------------------------------------------------------------*
*& AUTHORITY-CHECK: the failure modes that also return sy-subrc = 0.
*&
*&   1. 0 IS AMBIGUOUS   -> 0 means "passed" OR "no check was performed"
*&                          because the check indicator (SU24) for this
*&                          object in this context is set to NO CHECK.
*&   2. UPDATE TASK      -> inside an update FM, AUTHORITY-CHECK ALWAYS
*&                          sets sy-subrc = 0 and checks nothing. The
*&                          check must live in the dialog part of the LUW.
*&   3. EMPTY <> ANY     -> FIELD <initial var> checks for the value
*&                          SPACE. "do not check" is spelled DUMMY.
*&   4. SUBRC = 4        -> means denied OR a wrong/duplicate/too-many
*&                          field name. Indistinguishable in ABAP.
*&   5. = 4 vs <> 0      -> failure is 4, 12 or 40. Testing for 4 alone
*&                          lets the completely unauthorized user (12)
*&                          through - the exact user being guarded against.
*&
*& Uses the SAP demo authorization object S_CARRID (fields CARRID, ACTVT)
*& which exists in any AS ABAP with the flight demo content. Swap in your
*& own Z-object if S_CARRID is not available; only the names change.
*&
*& Read-only: this report performs checks and reports them, it never
*& acts on the result.
*&---------------------------------------------------------------------*
REPORT ydj_authority_check_demo.

PARAMETERS: p_carr TYPE sflight-carrid OBLIGATORY DEFAULT 'LH',
            p_actvt TYPE char2 OBLIGATORY DEFAULT '03'.


CLASS lcl_auth_demo DEFINITION.

  PUBLIC SECTION.
    CLASS-METHODS execute IMPORTING iv_carrid TYPE sflight-carrid
                                    iv_actvt  TYPE char2.

  PRIVATE SECTION.
    CONSTANTS mc_object TYPE xuobject VALUE 'S_CARRID'.

    CLASS-METHODS:
      "! Maps sy-subrc onto what it actually means, including the
      "! cases that share a code.
      subrc_text IMPORTING iv_subrc       TYPE sysubrc
                 RETURNING VALUE(rv_text) TYPE string,

      correct_check    IMPORTING iv_carrid TYPE sflight-carrid
                                 iv_actvt  TYPE char2,
      empty_value_trap IMPORTING iv_actvt  TYPE char2,
      dummy_only_check,
      wrong_field_trap IMPORTING iv_carrid TYPE sflight-carrid,
      subrc_test_trap  IMPORTING iv_carrid TYPE sflight-carrid
                                 iv_actvt  TYPE char2.

ENDCLASS.


CLASS lcl_auth_demo IMPLEMENTATION.

  METHOD execute.

    WRITE: / 'AUTHORITY-CHECK demo - object', mc_object,
           / 'User:', sy-uname, '  Transaction context:', sy-tcode.
    SKIP.

    correct_check( iv_carrid = iv_carrid iv_actvt = iv_actvt ).
    empty_value_trap( iv_actvt ).
    dummy_only_check( ).
    wrong_field_trap( iv_carrid ).
    subrc_test_trap( iv_carrid = iv_carrid iv_actvt = iv_actvt ).

    ULINE.
    WRITE: / 'Reminder: every 0 above may also mean the check indicator',
           / 'for', mc_object, 'is set to NO CHECK in this context.',
           / 'Confirm with SU53 or STAUTHTRACE - ABAP cannot tell you.'.

  ENDMETHOD.


  METHOD subrc_text.

    rv_text = SWITCH string( iv_subrc
      WHEN 0  THEN `0  - authorized, OR no check performed (check indicator)`
      WHEN 4  THEN `4  - values not permitted, OR wrong/too many field names`
      WHEN 12 THEN `12 - no authorization for this object at all`
      WHEN 40 THEN `40 - invalid user name (FOR USER)`
      ELSE         |{ iv_subrc } - undocumented; 24 is no longer set| ).

  ENDMETHOD.


  METHOD correct_check.
    " The shape to copy: every field either FIELD or DUMMY, evaluated
    " with <> 0 on the immediately following line.

    ULINE.
    WRITE: / '1. Straightforward check'.
    SKIP.

    AUTHORITY-CHECK OBJECT 'S_CARRID'
      ID 'CARRID' FIELD iv_carrid
      ID 'ACTVT'  FIELD iv_actvt.

    DATA(lv_subrc) = sy-subrc.

    WRITE: / |CARRID = { iv_carrid }, ACTVT = { iv_actvt }|,
           / '  sy-subrc =', subrc_text( lv_subrc ).

    IF lv_subrc <> 0.
      WRITE: / '  -> would deny here (and RETURN, not just log).'.
    ELSE.
      WRITE: / '  -> would allow here.'.
    ENDIF.
    SKIP.

  ENDMETHOD.


  METHOD empty_value_trap.
    " An initial value is not a wildcard: this checks for CARRID = space,
    " which no sane role grants. The usual cause is an empty
    " selection-screen field being passed straight through.

    ULINE.
    WRITE: / '2. Initial value is a value, not "any"'.
    SKIP.

    DATA lv_empty TYPE sflight-carrid.   " deliberately left initial

    AUTHORITY-CHECK OBJECT 'S_CARRID'
      ID 'CARRID' FIELD lv_empty
      ID 'ACTVT'  FIELD iv_actvt.

    WRITE: / 'FIELD <initial>  : sy-subrc =', subrc_text( sy-subrc ),
           / '                   (checks for the value SPACE)'.

    " The intended "do not check this field" is DUMMY.
    AUTHORITY-CHECK OBJECT 'S_CARRID'
      ID 'CARRID' DUMMY
      ID 'ACTVT'  FIELD iv_actvt.

    WRITE: / 'ID ... DUMMY     : sy-subrc =', subrc_text( sy-subrc ),
           / '                   (CARRID genuinely not checked)'.
    SKIP.

  ENDMETHOD.


  METHOD dummy_only_check.
    " All fields DUMMY degenerates to an existence check: it can only
    " return 0 (some authorization for the object exists, whatever its
    " values) or 12 (none). Fine as a cheap early exit, never as the
    " only check.

    ULINE.
    WRITE: / '3. All fields DUMMY = existence check only'.
    SKIP.

    AUTHORITY-CHECK OBJECT 'S_CARRID'
      ID 'CARRID' DUMMY
      ID 'ACTVT'  DUMMY.

    WRITE: / 'sy-subrc =', subrc_text( sy-subrc ),
           / 'Only 0 or 12 are reachable here - no value is ever tested.'.
    SKIP.

  ENDMETHOD.


  METHOD wrong_field_trap.
    " A misspelt field name cannot succeed for anyone, including SAP_ALL,
    " and reports the same 4 as a genuine denial. Verify names in SU21
    " before blaming the role.

    ULINE.
    WRITE: / '4. Wrong field name is also sy-subrc = 4'.
    SKIP.

    AUTHORITY-CHECK OBJECT 'S_CARRID'
      ID 'CARRID' FIELD iv_carrid
      ID 'ACTVT1' FIELD '03'.      " typo: no such field in S_CARRID

    WRITE: / |ID 'ACTVT1' (typo) : sy-subrc =|, subrc_text( sy-subrc ),
           / 'Same code as "denied". SLIN flags some of these; the',
           / 'runtime does not distinguish them at all.'.
    SKIP.

  ENDMETHOD.


  METHOD subrc_test_trap.
    " Failure is 4, 12 or 40. Testing = 4 admits the user with no
    " authorization object whatsoever.

    ULINE.
    WRITE: / '5. IF sy-subrc = 4 lets the 12 case through'.
    SKIP.

    AUTHORITY-CHECK OBJECT 'S_CARRID'
      ID 'CARRID' FIELD iv_carrid
      ID 'ACTVT'  FIELD iv_actvt.

    DATA(lv_subrc) = sy-subrc.

    IF lv_subrc = 4.
      WRITE: / 'Buggy form  (= 4)  : denied'.
    ELSE.
      WRITE: / 'Buggy form  (= 4)  : ALLOWED   <- wrong whenever subrc is 12/40'.
    ENDIF.

    IF lv_subrc <> 0.
      WRITE: / 'Correct form (<> 0): denied'.
    ELSE.
      WRITE: / 'Correct form (<> 0): allowed'.
    ENDIF.

    WRITE: / 'Actual:', subrc_text( lv_subrc ).
    SKIP.

    WRITE: / 'Also note: sy-subrc is overwritten by the next statement',
           / 'that sets it - which is why it is saved to lv_subrc here',
           / 'before anything else runs.'.
    SKIP.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_auth_demo=>execute( iv_carrid = p_carr
                          iv_actvt  = p_actvt ).
