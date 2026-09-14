*&---------------------------------------------------------------------*
*& Report YDJ_TABLE_BUFFER_DEMO
*&---------------------------------------------------------------------*
*& Table buffering: will this SELECT actually reach the buffer?
*&
*& Buffering is invisible in the code, so this report makes it visible.
*& For any table it reads the technical settings from DD09L/DD03L and
*& answers, for a list of fields you restrict with "=", whether the
*& statement is served from the table buffer or handed to the database.
*&
*&   1. BUFFERING TYPE -> DD09L-PUFFERUNG: ' ' none, P single record,
*&                        G generic (DD09L-SCHFELDANZ key fields),
*&                        X full. BUFALLOW says whether it is switched
*&                        on at all.
*&   2. KEY RULE       -> P needs ALL primary key fields with "=" AND;
*&                        G needs the generic key completely;
*&                        X needs nothing.
*&   3. STATEMENT RULE -> JOIN / subquery / UNION / GROUP BY / DISTINCT /
*&                        FOR UPDATE bypass the buffer regardless of the
*&                        WHERE clause.
*&
*& Note: SELECT SINGLE has NOTHING to do with single record buffering.
*& Only the WHERE clause decides. See README.md.
*&
*& Prerequisite: none. DD09L/DD03L exist in every AS ABAP system.
*&---------------------------------------------------------------------*
REPORT ydj_table_buffer_demo.

PARAMETERS: p_tab   TYPE dd09l-tabname OBLIGATORY DEFAULT 'T001',
            p_f1    TYPE dd03l-fieldname,
            p_f2    TYPE dd03l-fieldname,
            p_f3    TYPE dd03l-fieldname,
            p_join  AS CHECKBOX,
            p_group AS CHECKBOX,
            p_dist  AS CHECKBOX.


CLASS lcl_buffer_check DEFINITION.

  PUBLIC SECTION.

    TYPES: ty_fields TYPE STANDARD TABLE OF dd03l-fieldname WITH EMPTY KEY,

           BEGIN OF ty_settings,
             tabname    TYPE dd09l-tabname,
             pufferung  TYPE dd09l-pufferung,
             schfeldanz TYPE dd09l-schfeldanz,
             bufallow   TYPE dd09l-bufallow,
             speichpuff TYPE dd09l-speichpuff,
           END OF ty_settings.

    CLASS-METHODS:
      "! Technical settings of the activated version of the table.
      read_settings IMPORTING iv_tabname         TYPE dd09l-tabname
                    RETURNING VALUE(rs_settings) TYPE ty_settings,

      "! Primary key fields, in key order. MANDT is skipped: the client
      "! column is supplied implicitly by ABAP SQL.
      read_key_fields IMPORTING iv_tabname       TYPE dd09l-tabname
                      RETURNING VALUE(rt_fields) TYPE ty_fields,

      "! Human-readable buffering type.
      describe_type IMPORTING is_settings   TYPE ty_settings
                    RETURNING VALUE(rv_txt) TYPE string,

      "! Comma-separated field list. concat_lines_of( ) is not used here
      "! because DD03L-FIELDNAME is CHAR 30 and would keep its padding.
      join_fields IMPORTING it_fields     TYPE ty_fields
                  RETURNING VALUE(rv_txt) TYPE string,

      "! The fields that must all be supplied with "=" for the buffer
      "! to be used. Empty for full buffering.
      required_fields IMPORTING is_settings      TYPE ty_settings
                                it_key_fields    TYPE ty_fields
                      RETURNING VALUE(rt_fields) TYPE ty_fields,

      verdict IMPORTING iv_tabname       TYPE dd09l-tabname
                        it_where_fields  TYPE ty_fields
                        iv_join          TYPE abap_bool DEFAULT abap_false
                        iv_group_by      TYPE abap_bool DEFAULT abap_false
                        iv_distinct      TYPE abap_bool DEFAULT abap_false,

      execute.

ENDCLASS.


CLASS lcl_buffer_check IMPLEMENTATION.

  METHOD read_settings.
    " DD09L is cross-client. AS4LOCAL = 'A' is the activated version;
    " without it you can pick up an inactive or backup version.
    SELECT SINGLE tabname, pufferung, schfeldanz, bufallow, speichpuff
      FROM dd09l
      WHERE tabname  = @iv_tabname
        AND as4local = 'A'
      INTO CORRESPONDING FIELDS OF @rs_settings.

    IF sy-subrc <> 0.
      CLEAR rs_settings.
      rs_settings-tabname = iv_tabname.
    ENDIF.
  ENDMETHOD.


  METHOD read_key_fields.
    SELECT fieldname
      FROM dd03l
      WHERE tabname  = @iv_tabname
        AND as4local = 'A'
        AND keyflag  = 'X'
        AND fieldname <> 'MANDT'
      ORDER BY position
      INTO TABLE @rt_fields.
  ENDMETHOD.


  METHOD describe_type.
    rv_txt = SWITCH string( is_settings-pufferung
                            WHEN 'P' THEN |single record buffering|
                            WHEN 'G' THEN |generic buffering, { is_settings-schfeldanz } key field(s) incl. client|
                            WHEN 'X' THEN |full buffering|
                            ELSE          |not buffered| ).

    rv_txt = rv_txt && SWITCH string( is_settings-bufallow
                                      WHEN 'X' THEN | (switched on)|
                                      WHEN 'A' THEN | (ALLOWED BUT SWITCHED OFF)|
                                      WHEN 'N' THEN | (buffering NOT ALLOWED)|
                                      ELSE          || ).
  ENDMETHOD.


  METHOD join_fields.
    LOOP AT it_fields INTO DATA(lv_field).
      rv_txt = COND string( WHEN rv_txt IS INITIAL
                            THEN |{ lv_field }|
                            ELSE |{ rv_txt }, { lv_field }| ).
    ENDLOOP.
  ENDMETHOD.


  METHOD required_fields.
    CASE is_settings-pufferung.
      WHEN 'P'.
        " Every primary key field, with "=", joined by AND.
        rt_fields = it_key_fields.

      WHEN 'G'.
        " The left-aligned generic key only. SCHFELDANZ counts key
        " fields from the START of the primary key, and on a
        " client-dependent table the first key field is the client
        " column - which ABAP SQL supplies implicitly. So one fewer
        " field has to be named in the WHERE clause than the number says.
        DATA(lv_needed) = COND i( WHEN is_settings-schfeldanz > 0
                                  THEN is_settings-schfeldanz - 1
                                  ELSE 0 ).

        LOOP AT it_key_fields INTO DATA(lv_field).
          IF sy-tabix > lv_needed.
            EXIT.
          ENDIF.
          APPEND lv_field TO rt_fields.
        ENDLOOP.

      WHEN OTHERS.
        " Full buffering: no WHERE restriction needed. Not buffered:
        " nothing can help.
        CLEAR rt_fields.
    ENDCASE.
  ENDMETHOD.


  METHOD verdict.
    DATA(ls_settings) = read_settings( iv_tabname ).
    DATA(lt_keys)     = read_key_fields( iv_tabname ).
    DATA(lt_required) = required_fields( is_settings   = ls_settings
                                         it_key_fields = lt_keys ).

    DATA(lv_type)  = describe_type( ls_settings ).
    DATA(lv_keys)   = COND string( WHEN lt_keys IS INITIAL
                                   THEN `(none found)`
                                   ELSE join_fields( lt_keys ) ).
    DATA(lv_where)  = COND string( WHEN it_where_fields IS INITIAL
                                   THEN `(none)`
                                   ELSE join_fields( it_where_fields ) ).

    WRITE: / '---------------------------------------------------------'.
    WRITE: / 'Table      :', iv_tabname.
    WRITE: / 'Buffering  :', lv_type.
    WRITE: / 'Primary key:', lv_keys.
    WRITE: / 'WHERE "="  :', lv_where.

    " Rule 1: the table has to be buffered in the first place.
    IF ls_settings-pufferung IS INITIAL OR ls_settings-bufallow <> 'X'.
      WRITE: / 'Verdict    : DATABASE - table is not actively buffered.'.
      RETURN.
    ENDIF.

    " Rule 2: statement-level bypasses beat everything else. These are
    " not exhaustive - subqueries, UNION/INTERSECT/EXCEPT, WITH over
    " database tables, FOR UPDATE, CLIENT SPECIFIED without the client
    " column and CDS table functions bypass the buffer too.
    IF iv_join = abap_true.
      WRITE: / 'Verdict    : DATABASE - JOIN expressions always bypass the buffer.'.
      RETURN.
    ENDIF.

    IF iv_group_by = abap_true.
      WRITE: / 'Verdict    : DATABASE - GROUP BY/HAVING is not supported in the buffer.'.
      RETURN.
    ENDIF.

    IF iv_distinct = abap_true.
      WRITE: / 'Verdict    : DATABASE - DISTINCT is not supported in the buffer.'.
      RETURN.
    ENDIF.

    " Rule 3: the WHERE clause has to cover the required key fields.
    LOOP AT lt_required INTO DATA(lv_required).
      IF NOT line_exists( it_where_fields[ table_line = lv_required ] ).
        DATA(lv_req_txt) = join_fields( lt_required ).
        WRITE: / 'Verdict    : DATABASE - key field', lv_required,
                 'is not restricted with "=" (required:', lv_req_txt, ').'.
        RETURN.
      ENDIF.
    ENDLOOP.

    WRITE: / 'Verdict    : BUFFER - served from the table buffer.'.

    IF ls_settings-pufferung = 'G'.
      WRITE: / '             (generic area is fully specified)'.
    ENDIF.
  ENDMETHOD.


  METHOD execute.
    DATA lt_where TYPE ty_fields.

    " Only non-empty parameters count as restrictions.
    DATA(lt_params) = VALUE ty_fields( ( p_f1 ) ( p_f2 ) ( p_f3 ) ).

    LOOP AT lt_params INTO DATA(lv_field).
      IF lv_field IS NOT INITIAL.
        APPEND to_upper( lv_field ) TO lt_where.
      ENDIF.
    ENDLOOP.

    verdict( iv_tabname      = to_upper( p_tab )
             it_where_fields = lt_where
             iv_join         = p_join
             iv_group_by     = p_group
             iv_distinct     = p_dist ).

    " The point of the whole exercise, in one comparison: the same read,
    " once as the buffer can serve it and once as a JOIN.
    SKIP.
    WRITE: / 'Same read, two shapes:'.
    verdict( iv_tabname      = 'T001'
             it_where_fields = VALUE ty_fields( ( 'BUKRS' ) ) ).
    verdict( iv_tabname      = 'T001'
             it_where_fields = VALUE ty_fields( ( 'BUKRS' ) )
             iv_join         = abap_true ).
  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.
  lcl_buffer_check=>execute( ).

