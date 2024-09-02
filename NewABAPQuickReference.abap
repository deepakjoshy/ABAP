
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



