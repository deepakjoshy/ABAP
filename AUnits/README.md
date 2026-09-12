# ABAP UNIT TEST CLASS | AUNITS


ABAP unit tests are methods of specially designated ABAP classes. Test methods work as scripts, with which code under test can be run, and with which the results of a test can be evaluated.

ABAP Unit is suitable for test-driven development (TDD).


#### Development Features of ABAP Unit
- The most important features of ABAP Unit for programming of unit tests are:
- The tests are programmed in ABAP. You do not have to learn any additional test script languages.
- The tests are developed in the ABAP development environment. You do not have to learn any additional interface operation.
- With the ABAP Unit Wizard, you can generate Test Classes for classes ( Class Pools) and Function Groups. For other program objects, you can create test classes manually.
- ABAP Unit test classes can be implemented in the tested development objects. This ensures that the relationship between unit test and tested code is clear. And since unit tests are transported with the code under test, they are available in all systems of the development and test landscape.




### Mocking Tables 

Sample Code


     DATA:   lo_environment TYPE REF TO if_osql_test_environment.
             lo_environment = cl_osql_test_environment=>create( i_dependency_list = VALUE #( ( 'cepc' )  ( 'cepc_bukrs' ) ) ).
      
    DATA: lt_cepc TYPE STANDARD TABLE OF cepc.  
    DATA: lt_cepc_bukrs TYPE STANDARD TABLE OF cepc_bukrs.
    
      
    lt_cepc = VALUE #( ( mandt = sy-mandt prctr = '10000001' datbi = '99993112' kokrs = 'ABCD'  bukrs = '1111' verak = '' abtei = 'ADV01' khinr = '' stras = ''  name1 = '' name2 = '' name3 = '' name4 = '' pstlz = '' ort01 = '' land1 = 'US' regio = '' telf1 = '' lock_ind = '' )  
                       ( mandt = sy-mandt prctr = '10000002' datbi = '99993112' kokrs = 'ABCD' bukrs = '1112' verak = '' abtei = 'GRS01' khinr = 'US99999A' stras = '' name1 = '' name2 = '' name3 = '' name4 = '' pstlz = '' ort01 = '' land1 = 'US' regio = '' telf1 = '' lock_ind = '' ) ).  
    lo_environment->insert_test_data( lt_cepc ).
    
    
    lt_cepc_bukrs = VALUE #( ( mandt = sy-mandt kokrs = 'ABCD' prctr = '10000001' bukrs = '1111' ) 
                             ( mandt = sy-mandt kokrs = 'ABCD' prctr = '10000002' bukrs = '111' ) ).  
    lo_environment->insert_test_data( lt_cepc_bukrs ).




### BOPF AUnit

Sample Code:

    DATA(lo_root) = /bobf/cl_bunit=>create_root( sc_bo_key ).  
    lo_root->attribute( sc_node_attribute-i_centralpurchasecontracttp-centralpurchasecontract )->set( gc_ebeln ).  
    DATA(lo_itm) = lo_root->create_child( sc_node-i_cntrlpurchasecontractitemtp ).  
    lo_itm->attribute( sc_node_attribute-i_cntrlpurchasecontractitemtp-centralpurchasecontract )->set( gc_ebeln ).  
    DATA(lo_itmcndnvaldty) = lo_itm->create_child( sc_node-i_cntrlpurcontritmcndnvaldtytp ).  
    lo_itmcndnvaldty->attribute( sc_node_attribute-i_cntrlpurcontritmcndnvaldtytp-centralpurchasecontract )->set( gc_ebeln ).  
    lo_itmcndnvaldty->attribute( sc_node_attribute-i_cntrlpurcontritmcndnvaldtytp-centralpurchasecontractitem )->set( '00010' ).  
    lo_itmcndnvaldty->attribute( sc_node_attribute-i_cntrlpurcontritmcndnvaldtytp-conditionvalidityenddate )->set( '20201231' ).  
    lo_itmcndnvaldty->attribute( sc_node_attribute-i_cntrlpurcontritmcndnvaldtytp-conditionrecord )->set( '999999999' ).  
    DATA(lo_itmcndnamount) = lo_itmcndnvaldty->create_child( sc_node-i_cntrlpurcontritmcndnamounttp ).  
    lo_itmcndnamount->attribute( sc_node_attribute-i_cntrlpurcontritmcndnamounttp-centralpurchasecontract )->set( gc_ebeln ).  
    lo_itmcndnamount->attribute( sc_node_attribute-i_cntrlpurcontritmcndnamounttp-centralpurchasecontractitem )->set( '00010' ).  
    lo_itmcndnamount->attribute( sc_node_attribute-i_cntrlpurcontritmcndnamounttp-conditionvalidityenddate )->set( '20201231' ).  
    lo_itmcndnamount->attribute( sc_node_attribute-i_cntrlpurcontritmcndnamounttp-conditionrecord )->set( '999999999' ).  
    lo_itmcndnamount->attribute( sc_node_attribute-i_cntrlpurcontritmcndnamounttp-conditionsequentialnumber )->set( '01' ).  
    DATA(lo_itmcndnamount1) = lo_itmcndnvaldty->create_child( sc_node-i_cntrlpurcontritmcndnamounttp ).  
    lo_itmcndnamount1->attribute( sc_node_attribute-i_cntrlpurcontritmcndnamounttp-centralpurchasecontract )->set( gc_ebeln ).  
    lo_itmcndnamount1->attribute( sc_node_attribute-i_cntrlpurcontritmcndnamounttp-centralpurchasecontractitem )->set( '00010' ).  
    lo_itmcndnamount1->attribute( sc_node_attribute-i_cntrlpurcontritmcndnamounttp-conditionvalidityenddate )->set( '20201231' ).  
    lo_itmcndnamount1->attribute( sc_node_attribute-i_cntrlpurcontritmcndnamounttp-conditionrecord )->set( '999999999' ).  
    lo_itmcndnamount1->attribute( sc_node_attribute-i_cntrlpurcontritmcndnamounttp-conditionsequentialnumber )->set( '02' ).  
    DATA(lo_itmcndnscales) = lo_itmcndnamount->create_child( sc_node-i_cntrlpurcontritmcndnscalestp ).  
    lo_itmcndnscales->attribute( sc_node_attribute-i_cntrlpurcontritmcndnscalestp-centralpurchasecontract )->set( gc_ebeln ).  
    lo_itmcndnscales->attribute( sc_node_attribute-i_cntrlpurcontritmcndnscalestp-centralpurchasecontractitem )->set( '00010' ).  
    lo_itmcndnscales->attribute( sc_node_attribute-i_cntrlpurcontritmcndnscalestp-conditionvalidityenddate )->set( '20201231' ).  
    lo_itmcndnscales->attribute( sc_node_attribute-i_cntrlpurcontritmcndnscalestp-conditionrecord )->set( '999999999' ).  
    lo_itmcndnscales->attribute( sc_node_attribute-i_cntrlpurcontritmcndnscalestp-conditionsequentialnumber )->set( '01' ).  
    lo_itmcndnscales->attribute( sc_node_attribute-i_cntrlpurcontritmcndnscalestp-conditionscaleline )->set( '0001' ).  
    DATA(lo_set) = /bobf/cl_bunit_node_set=>create_with_node( lo_itmcndnscales ).  
    DATA(lo_determination_result_c) = lo_set->execute_determination( sc_determination-i_cntrlpurcontritmcndnscalestp-check_and_enrich_itmcnd_scales ).  
    mo_assert->determination_result( lo_determination_result_c )->has_no_failed_keys( ).



### Mocking Class/Interface Dependencies — ABAP Test Double Framework

The mocking snippets above cover database and BOPF dependencies. For a dependency that is a **global class or interface**, use the ABAP OO Test Double Framework (`CL_ABAP_TESTDOUBLE`, SAP_BASIS 7.40 SP9+) instead of hand-writing a stub class.

Full worked example (interface, class under test, and local test class): [ZCL_TestDoubleFramework_Demo.abap](ZCL_TestDoubleFramework_Demo.abap)

The mental model that trips people up: `configure_call( )` arms the double for the **next** method call you write on it. That next call is a *recording* — its input values become the matcher — not a real invocation.

Sample Code

    "1. create the double from the interface NAME (string) -> needs a cast
    mo_double ?= cl_abap_testdouble=>create( 'ZIF_CURRENCY_CONVERTER' ).

    "2. arm it: return 80 for these exact inputs, for the next 2 calls
    cl_abap_testdouble=>configure_call( mo_double )->returning( 80 )->times( 2 ).

    "3. the recording call - defines WHICH inputs the config above matches
    mo_double->convert( amount          = 100
                        source_currency = `USD`
                        target_currency = `EUR` ).

    "4. inject and test
    DATA(lo_cut) = NEW zcl_expense_manager( mo_double ).
    cl_abap_unit_assert=>assert_equals( exp = 160 act = lo_cut->total_in( `EUR` ) ).

Chain onto `configure_call( )`: `returning( )`, `set_parameter( )` (EXPORTING/CHANGING, one call per parameter), `ignore_parameter( )`, `ignore_all_parameters( )`, `raise_exception( )` (class-based only), `raise_event( )`, `times( )`, `and_expect( )->is_called_times( )`, `set_matcher( )`, `set_answer( )`.

`times( )` defaults to 1, and once a configuration is exhausted the **last matching** configuration keeps being returned — extra calls do not fail or return initial values.

#### Limitations

`CL_ABAP_TESTDOUBLE` cannot double a local class/interface, or a class declared `FINAL`, `CREATE PRIVATE`, `FOR TESTING`, or one whose constructor has mandatory parameters. Check this before designing around it.

For other dependency kinds: `CL_OSQL_TEST_ENVIRONMENT` (DB tables/CDS view entities in ABAP SQL), `CL_CDS_TEST_ENVIRONMENT` (logic inside CDS entities), `CL_BOTD_TXBUFDBL_BO_TEST_ENV` / `CL_BOTD_MOCKEMLAPI_BO_TEST_ENV` (RAP business objects).

References: [SAP Help — ABAP OO Test Double Framework](https://help.sap.com/docs/abap-cloud/abap-development-tools-user-guide/abap-oo-test-double-framework) · [SAP ABAP Cheat Sheets — ABAP Unit Tests](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/14_ABAP_Unit_Tests.md)


### Testing Logic Inside a CDS Entity — CDS Test Double Framework

The frameworks above replace a *dependency* of your ABAP code. When the thing you actually want to test is the logic **inside a CDS entity** — a join, a `CASE`, an aggregation — use the CDS Test Double Framework (`CL_CDS_TEST_ENVIRONMENT`, SAP NetWeaver 7.51+).

It doubles the entity's data sources, lets the real CDS engine evaluate the entity against your rows, and you assert on what comes back.

Full worked example (CDS entity, reader class, test class): [ZCL_CDSTestDouble_Demo.abap](ZCL_CDSTestDouble_Demo.abap)

**Which framework?**

| You want to test | Use |
|---|---|
| Logic *inside* a CDS entity | `CL_CDS_TEST_ENVIRONMENT` — doubles its data sources |
| ABAP code that `SELECT`s *from* a CDS entity | `CL_OSQL_TEST_ENVIRONMENT` — double the view itself via `i_dependency_list` |

Sample Code

    CLASS-DATA environment TYPE REF TO if_cds_test_environment.   "interface type, not the class

    METHOD class_setup.
      "expensive - build once per class. No dependency list needed: the framework
      "derives the entity's first-level data sources and doubles them itself.
      environment = cl_cds_test_environment=>create( i_for_entity = 'Z_CARRIER_REGION' ).
    ENDMETHOD.

    METHOD setup.
      environment->clear_doubles( ).      "doubles are not emptied between tests
    ENDMETHOD.

    METHOD class_teardown.
      environment->destroy( ).
    ENDMETHOD.

    METHOD eur_maps_to_eu.
      DATA lt_scarr TYPE STANDARD TABLE OF scarr.
      lt_scarr = VALUE #( ( mandt = sy-mandt carrid = 'LH' carrname = 'Lufthansa' currcode = 'EUR' ) ).

      environment->insert_test_data( lt_scarr ).   "seed the DATA SOURCE...

      SELECT carrid, region FROM z_carrier_region INTO TABLE @DATA(lt_rows).  "...assert on the ENTITY

      cl_abap_unit_assert=>assert_equals( exp = 'EU' act = lt_rows[ 1 ]-region ).
    ENDMETHOD.

#### The trap: redirection is off by default

The entity under test always reads the doubles. But a **direct** `SELECT` in your test code against a doubled table hits the *real* database — the opposite of `CL_OSQL_TEST_ENVIRONMENT`, which redirects such selects by default. Call `enable_double_redirection( )` to flip it on, and reset it in `setup` so the state cannot leak between tests.

Practical rule: assert against the CDS entity, never against the seeded tables.

#### Other gotchas

- `class_setup` / `class_teardown` must be `CLASS-METHODS`. Declared as instance `METHODS` they silently never run as fixtures.
- Fill `MANDT`/`CLIENT` with `sy-mandt` in seed rows. Key constraints are not copied to the double, so a wrong client does not error — the view just returns nothing.
- `i_dependency_list` is for hierarchy testing, **not** unit tests. Supply it and you must cover one node in every dependency path or `create( )` throws.
- Modeled associations are not runtime data sources and are not doubled unless you pass `test_associations = 'X'`.
- Tests cannot be launched from the DDL editor — run them from the class holding the test include.
- `disable_dcl` on `create( )` is obsolete and ignored on current releases; use `get_access_control_double( )`. The default is "no access control".

References: [SAP Help — CDS Unit Tests: Creating the Test Class](https://help.sap.com/docs/abap-cloud/abap-data-models/cds-unit-tests-creating-test-class) · [SAP Help — ABAP CDS Test Double Framework](https://help.sap.com/docs/abap-cloud/abap-development-tools-user-guide/abap-cds-test-double-framework)
