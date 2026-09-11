
TYPES: ty_numbers TYPE STANDARD TABLE OF i WITH EMPTY KEY.
DATA: lt_numbers TYPE ty_numbers.


* VALUE FOR Loop
lt_numbers = VALUE ty_numbers( FOR  i = 1 THEN i + 1  WHILE i LE 10 ( i ) ).


* REDUCE FOR Loop - Variation 1
DATA(sum1) = REDUCE i( INIT sum = 0 FOR n = 1  UNTIL n GT 10 NEXT sum = sum + lt_numbers[ n ] ).


* REDUCE FOR Loop - Variation 2
DATA(sum2) = REDUCE i( INIT sum = 0 FOR n = 1 THEN n + 1 WHILE n LE 10 NEXT sum = sum + lt_numbers[ n ] ).

* REDUCE with GROUP BY
DATA(lv_records) = REDUCE i( INIT x = 0 FOR GROUPS <group_key> OF <g> IN lt_spfli GROUP BY ( carrid = <g>-carrid ) NEXT x = x + 1 ).


* FOR Loop with WHERE condition with FIELD SYMBOLS
DATA(filter) = VALUE ty_numbers( FOR <fs> IN lt_numbers WHERE ( table_line GT 5 ) ( <fs> ) ).


* Count number of records in Internal Table with condition
DATA(lv_records_lines) = lines( FILTER #( lt_spfli WHERE carrid ='LH' ) ).


 * CORRESPONDING Operator respecting Table Key
lt_target = CORRESPONDING #( lt_target FROM lt_company_code USING bukrs = bukrs ).


* Table to Range
DATA(bukrs_range) = VALUE rsdsselopt_t( FOR line IN lt_t001
                                        sign = if_fsbp_const_range=>sign_include
                                        option = if_fsbp_const_range=>option_equal
                                      ( low = line-bukrs ) ).

* Fill Range Directly from Select Statement: 
 SELECT @if_fsbp_const_range=>sign_include AS sign,
       @if_fsbp_const_range=>option_equal AS option,
       bukrs AS low,
       CAST( @space AS CHAR( 4 ) ) AS high
    FROM t001
    INTO TABLE @DATA(range_of_comp_codes).



* Value Operator using "LINES OF" Addition
 DATA(t_1) = VALUE stringtab( ( `Line 1` )
                             ( `Line 2` ) ).
DATA(t_2) = VALUE stringtab( ( `Line 3` )
                             ( `Line 4` ) ).
DATA(t_3) = VALUE stringtab( ( LINES OF t_1 )
                             ( LINES OF t_2 FROM 2 )
                             ( `Line 5` ) ).


* Switch Operator in Where Clause
SELECT SINGLE * FROM mara
      WHERE matkl = @( SWITCH matkl( lv_material_group
                                     WHEN 'ZSPR' THEN space
                                     ELSE lv_material_group ) )
      INTO @DATA(lt_mara). 


* Loop at Structure Components using RTTI
LOOP AT CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_data( lv_structure ) )->components ASSIGNING FIELD-SYMBOL(<fs_comp>).
  WRITE:/ <fs_comp>-name,<fs_comp>-type_kind,<fs_comp>-length,<fs_comp>-decimals.
ENDLOOP.


* Call and Instance Class Method without Creating Instance Object
NEW lcl_bapi( )->execute( im_filepath       = p_file 
                          im_screen         = '0100' ).


* Get Domain's Fixed Values
DATA lv_koart TYPE bseg-koart.
IF CAST cl_abap_elemdescr( cl_abap_typedescr=>describe_by_data( lv_koart ) )->is_ddic_type( ).
  DATA(lt_domain_values) =  CAST cl_abap_elemdescr(
                                  cl_abap_typedescr=>describe_by_data( lv_koart )
                                        )->get_ddic_fixed_values( ).
ENDIF.


* Dynamic Read of Internal Table
DATA(lt_vbak)        = VALUE tab_vbak( ( vbeln = '123456789' ) ).
DATA(lv_column_name) = CONV dd03d-fieldname( 'VBELN' ).
READ TABLE lt_vbak WITH KEY (lv_column_name) = '123456789' TRANSPORTING NO FIELDS.
IF syst-subrc IS INITIAL.
  "Entry Exists
ENDIF.



* Create Dynamic Range for any Variable using RTTC
DATA lv_data TYPE vbak-vbeln.
"Create component table
DATA(lt_component) = VALUE abap_component_tab( ( name = 'SIGN'   type = CAST cl_abap_datadescr( cl_abap_elemdescr=>describe_by_name( CONV rollname( 'DDSIGN'     ) ) ) )
                                               ( name = 'OPTION' type = CAST cl_abap_datadescr( cl_abap_elemdescr=>describe_by_name( CONV rollname( 'DDOPTION'   ) ) ) )
                                               ( name = 'LOW'    type = CAST cl_abap_datadescr( cl_abap_elemdescr=>describe_by_data( lv_data ) ) )
                                               ( name = 'HIGH'   type = CAST cl_abap_datadescr( cl_abap_elemdescr=>describe_by_data( lv_data ) ) ) ).
"Create Table Type Descriptor
DATA(lo_tabledescr)  = cl_abap_tabledescr=>create( p_line_type  = cl_abap_structdescr=>create( lt_component )
                                                   p_table_kind = cl_abap_tabledescr=>tablekind_std
                                                   p_key_kind   = cl_abap_tabledescr=>keydefkind_default
                                                   p_unique     = abap_false ).

DATA lo_ref TYPE REF TO data.
CREATE DATA lo_ref TYPE HANDLE lo_tabledescr.
ASSIGN lo_ref->* TO FIELD-SYMBOL(<fs_range>).



* Corresponding with Lookup Table
TYPES:BEGIN OF t_country,
        country      TYPE i_countrytext-country,
        country_text TYPE i_countrytext-countryname,
      END OF t_country,
      tt_country TYPE STANDARD TABLE OF t_country WITH DEFAULT KEY.
DATA lookup TYPE HASHED TABLE OF i_countrytext WITH UNIQUE KEY country.
DATA(original) = VALUE tt_country( ( country = 'GR' )
                                   ( country = 'DE' ) ).
SELECT FROM i_countrytext
  FIELDS i_countrytext~*
  WHERE language EQ @SYST-LANGU
  INTO TABLE @lookup.
DATA(result) = CORRESPONDING tt_country( original
                                         FROM    lookup
                                         USING   country      = country
                                         MAPPING country_text = countryname  ).


* Advanced Filtering of Internal Table
DATA lt_flights TYPE /iwfnd/sflight_flight_t.
SELECT FROM sflight AS flight
   FIELDS carrid,
          connid,
          fldate
   INTO CORRESPONDING FIELDS OF TABLE @lt_flights.
DATA(lt_filtered_flights) = VALUE /iwfnd/sflight_flight_t( FOR <fs> IN lt_flights
                                   ( LINES OF COND #( WHEN  <fs>-fldate LE syst-datum
                                                      THEN VALUE #( ( <fs> ) ) )
                                             )
                                           ).

* Use Indicator Structure to Update Selected Fields
TYPES ty_sflight TYPE sflight WITH INDICATORS set_ind.
DATA  lt_sflight TYPE STANDARD TABLE OF ty_sflight WITH DEFAULT KEY.
SELECT FROM sflight
  FIELDS carrid, connid, fldate, price
  INTO CORRESPONDING FIELDS OF TABLE @lt_sflight
  UP TO 5 ROWS.
IF syst-subrc IS INITIAL.
  LOOP AT lt_sflight ASSIGNING FIELD-SYMBOL(<fs>).
    <fs>-price *= '10'.
    <fs>-set_ind-price = abap_true.
  ENDLOOP.
  UPDATE sflight FROM TABLE @lt_sflight INDICATORS SET STRUCTURE set_ind.
ENDIF.


* Null Indicator Structure
SELECT FROM scarr AS airline
LEFT OUTER JOIN spfli AS flight_schedule ON airline~carrid EQ flight_schedule~carrid
FIELDS airline~carrid                           AS airline_code,
            MAX( flight_schedule~distid ) AS distance
GROUP BY airline~carrid
INTO TABLE @DATA(lt_flights_per_airline)
INDICATORS NULL STRUCTURE null_indicator.


* Count Number Of Specific Data Records
DATA(lv_records) = lines( VALUE tt_spfli( FOR line IN lt_spfli WHERE ( carrid EQ 'LH' ) ( line ) ) ).

* Distinguish whether the call originates from the UI or the API - returns the C/I View name
cl_abap_behv_aux=>get_current_context(IMPORTING from_projection = DATA(lv_view_name)).


* LOOP AT ... GROUP BY - 1) Representative Binding + Member Loop
* Runs in two phases: phase 1 builds the groups silently, phase 2 loops the groups.
* With no INTO after GROUP BY, the work area holds the FIRST line of each group (its
* "representative") and is also the name that binds the group for LOOP AT GROUP.
LOOP AT lt_spfli INTO DATA(ls_rep)
     GROUP BY ( carrid = ls_rep-carrid airpfrom = ls_rep-airpfrom ).
  WRITE: / ls_rep-carrid, ls_rep-airpfrom.
  LOOP AT GROUP ls_rep INTO DATA(ls_member).
    WRITE: / '   ', ls_member-connid, ls_member-distance.
  ENDLOOP.
ENDLOOP.


* LOOP AT ... GROUP BY - 2) Group Key Binding with GROUP SIZE / GROUP INDEX
* GROUP SIZE (member count) and GROUP INDEX (1,2,3... in group creation order) are
* extra components of the key structure - they are NOT part of the key itself, and
* they are only allowed with an explicit INTO target, never with representative binding.
LOOP AT lt_spfli INTO DATA(ls_line)
     GROUP BY ( carrid = ls_line-carrid
                indx   = GROUP INDEX
                size   = GROUP SIZE )
     INTO DATA(ls_key).
  WRITE: / ls_key-indx, ls_key-carrid, ls_key-size.
* Aggregate over the members without a nested LOOP - FOR ... IN GROUP takes the group name
  DATA(lv_total_dist) = REDUCE i( INIT s = 0 FOR m IN GROUP ls_key NEXT s = s + m-distance ).
  WRITE: lv_total_dist.
ENDLOOP.


* LOOP AT ... GROUP BY - 3) WITHOUT MEMBERS (distinct-values / performance variant)
* Skips building the member assignment entirely. Use it when you only need the keys.
* Trade-off: no LOOP AT GROUP / FOR ... IN GROUP is possible, but it is the ONLY form
* in which the source table itself may be modified inside the group loop.
LOOP AT lt_spfli INTO DATA(ls_any)
     GROUP BY ls_any-carrid WITHOUT MEMBERS
     INTO DATA(lv_carrid).
  WRITE: / lv_carrid.
ENDLOOP.


* LOOP AT ... GROUP BY - Gotchas worth remembering
* - Group order = order in which each key FIRST appears; add ASCENDING / DESCENDING
*   [AS TEXT] after the key expression to force sorted group order instead.
* - Unlike AT NEW / AT END OF, GROUP BY does NOT require the table to be pre-sorted
*   and does not depend on the field order of the line type. AT group-level statements
*   are in fact forbidden inside a GROUP BY loop.
* - The source table cannot be modified inside the group loop unless WITHOUT MEMBERS.
* - LOOP AT GROUP only works when the table is written as a real data object; if the
*   source is the result of a method call or expression, only the keys survive phase 1.
* - TRANSPORTING NO FIELDS is not allowed with GROUP BY.
* - sy-tabix differs by binding: representative binding gives the tabix of the
*   representative line, group key binding counts the groups (1, 2, 3, ...).
* Ref: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/abaploop_at_itab_group_by.html


* String Templates - 1) ALPHA = IN / OUT (the leading-zero conversion, without the FM)
* Same thing CONVERSION_EXIT_ALPHA_INPUT / _OUTPUT does, inline and without a FM call.
* IN  = pad left with zeros (display value -> internal/DB value)
* OUT = strip leading zeros (internal/DB value -> display value)
* Only allowed on string / c / n, and the ONLY options that may be combined with it
* are WIDTH and CASE - anything else is a syntax error.
DATA(lv_matnr_db)   = |{ '1234' ALPHA = IN WIDTH = 18 }|.   " '000000000000001234'
DATA(lv_matnr_disp) = |{ lv_matnr_db ALPHA = OUT }|.        " '1234'

* GOTCHA: without WIDTH the result length comes from the SOURCE, not the target -
* so the pad is silently a no-op. These two are NOT the same:
DATA lv_c18 TYPE c LENGTH 18.
lv_c18 = |{ '1234' ALPHA = IN }|.               " 000000000000001234 - target length 18 is used
DATA(lv_str) = |{ '1234' ALPHA = IN }|.         " '1234' - source length 4 is used, no padding!
* The target-length rule applies only when the template is a SINGLE embedded expression
* holding a SINGLE data object, assigned to a fixed-length c/n/d/t field. Wrap it in a
* function call or add any literal text and you fall back to the source length.


* String Templates - 2) WIDTH / ALIGN / PAD (column output without OFFSET+LENGTH juggling)
* ALIGN and PAD do nothing unless WIDTH is also given and is LARGER than the value.
* WIDTH can only grow a value, never truncate it - a too-small WIDTH is ignored.
WRITE: / |{ 'Carrier' WIDTH = 12 }{ 'Distance' WIDTH = 10 ALIGN = RIGHT }|.
WRITE: / |{ 'LH' WIDTH = 12 PAD = '.' }{ 6162 WIDTH = 10 ALIGN = RIGHT }|.
* Keywords have CL_ABAP_FORMAT equivalents for the dynamic (dobj) form:
* ALIGN -> A_LEFT / A_RIGHT / A_CENTER, CASE -> C_RAW / C_UPPER / C_LOWER,
* ALPHA -> L_IN / L_OUT / L_RAW. Needed when the option is decided at runtime:
DATA(lv_align) = CL_ABAP_FORMAT=>A_RIGHT.
WRITE: / |{ 'X' WIDTH = 10 ALIGN = (lv_align) PAD = '_' }|.   " '_________X'


* String Templates - 3) Dates, times and numbers
* DATE only on type d, TIME only on type t. Default for both is RAW (yyyymmdd) -
* which is why a bare |{ sy-datum }| prints the unreadable internal form.
WRITE: / |{ sy-datum DATE = ISO }|,      " 2026-09-12  (always yyyy-mm-dd)
         |{ sy-datum DATE = USER }|,     " per the user master record
         |{ sy-uzeit TIME = ISO }|.      " hh:mm:ss
* NUMBER / DATE / TIME / TIMESTAMP and COUNTRY are MUTUALLY EXCLUSIVE - pick one.
* COUNTRY formats per T005X for this expression only, with none of the session-wide
* side effects of SET COUNTRY:
WRITE: / |{ 1000000 COUNTRY = 'DE ' }|.  " uses the DE mask from T005X
* ZERO = NO renders a zero as an empty string - handy for ALV/report columns:
WRITE: / |{ 0 ZERO = NO }|, |{ 0 ZERO = YES }|.   " '' and '0'


* String Templates - 4) DECIMALS vs CURRENCY (the amount-formatting trap)
* DECIMALS rounds to the given number of places, regardless of the type's own decimals.
WRITE: / |{ CONV decfloat34( '1234.5678' ) DECIMALS = 2 }|.   " 1234.57
* CURRENCY takes the decimal count from TCURX (default 2) - the point being currencies
* like JPY (0 places) or KWD (3 places) format correctly without hardcoding.
* THE TRAP: when a type p DATA OBJECT is passed, its declared decimal places are
* IGNORED COMPLETELY and the separator is simply inserted at the position TCURX says.
* Pass an arithmetic expression instead and CURRENCY behaves like DECIMALS.
DATA lv_amount TYPE p LENGTH 8 DECIMALS 2 VALUE '12345.67'.
WRITE: / |{ lv_amount CURRENCY = 'EUR' }|,       " digits re-split - NOT 12345.67
         |{ lv_amount * 1 CURRENCY = 'EUR' }|.   " forces the DECIMALS-style behaviour
* CURRENCY cannot be combined with DECIMALS, STYLE, TIMESTAMP or TIMEZONE.
* Note: no thousands separator is ever inserted by CURRENCY - use NUMBER/COUNTRY for that.
* Ref: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCOMPUTE_STRING_FORMAT_OPTIONS.html
