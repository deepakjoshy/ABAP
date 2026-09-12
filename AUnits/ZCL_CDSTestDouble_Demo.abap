*&---------------------------------------------------------------------*
*& CDS Test Double Framework (CDS TDF) - end-to-end example
*&
*& Testing the logic INSIDE a CDS entity (joins, CASE, aggregations)
*& against controlled data, instead of whatever happens to be in the
*& underlying tables on the current system.
*&
*& Available from SAP NetWeaver 7.51 onwards.
*&
*& Docs: https://help.sap.com/docs/abap-cloud/abap-data-models/cds-unit-tests-creating-test-class
*&       https://help.sap.com/docs/abap-cloud/abap-development-tools-user-guide/abap-cds-test-double-framework
*&
*& NOTE: the artifacts below are SEPARATE repository objects in ADT (a
*&       DDL source, a class pool, and the class' Test Classes include).
*&       They are kept in one file here for readability.
*&
*& WHICH FRAMEWORK?
*&   Testing the CDS entity itself      -> CL_CDS_TEST_ENVIRONMENT (here)
*&   Testing ABAP code that SELECTs
*&   from a CDS entity (view = a black
*&   box you want to force a result on) -> CL_OSQL_TEST_ENVIRONMENT
*&---------------------------------------------------------------------*


*&---------------------------------------------------------------------*
*& 1) The CDS entity under test (CUT) - DDL source Z_CARRIER_REGION
*&---------------------------------------------------------------------*
*  @AccessControl.authorizationCheck: #NOT_REQUIRED
*  @EndUserText.label: 'Carrier with region derived from currency'
*  define view entity z_carrier_region
*    as select from scarr as c
*  {
*    key c.carrid,
*        c.carrname,
*        c.currcode,
*        case c.currcode
*          when 'EUR' then 'EU'
*          when 'GBP' then 'EU'
*          when 'USD' then 'AMERICAS'
*          when 'JPY' then 'ASIA'
*          else 'OTHER'
*        end as region
*  }
*
*  The CASE is the logic worth testing: every WHEN branch plus the ELSE.
*  A projection view with no expressions does not need a unit test.


*&---------------------------------------------------------------------*
*& 2) Consumer class - just reads the entity
*&---------------------------------------------------------------------*
CLASS zcl_carrier_region_reader DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES:
      BEGIN OF ts_carrier,
        carrid   TYPE scarr-carrid,
        carrname TYPE scarr-carrname,
        currcode TYPE scarr-currcode,
        region   TYPE c LENGTH 8,
      END OF ts_carrier,
      tt_carriers TYPE STANDARD TABLE OF ts_carrier WITH EMPTY KEY.

    METHODS list_regions
      RETURNING VALUE(rt_result) TYPE tt_carriers.
ENDCLASS.

CLASS zcl_carrier_region_reader IMPLEMENTATION.

  METHOD list_regions.
    SELECT carrid, carrname, currcode, region
      FROM z_carrier_region
      ORDER BY carrid
      INTO TABLE @rt_result.
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& 3) Local test class (Test Classes include of the reader class)
*&
*&    A CDS entity has no test include of its own - the test class lives
*&    in a class pool. "! @testing links it back to the entity so ADT can
*&    launch it from the CDS object's context menu.
*&---------------------------------------------------------------------*
"! @testing z_carrier_region
CLASS ltcl_carrier_region DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    " CREATE returns an INTERFACE reference - typing this as the class
    " CL_CDS_TEST_ENVIRONMENT does not compile.
    " CLASS-DATA, because it is built once in CLASS_SETUP.
    CLASS-DATA environment TYPE REF TO if_cds_test_environment.

    DATA mo_reader TYPE REF TO zcl_carrier_region_reader.

    CLASS-METHODS class_setup    RAISING cx_static_check.
    CLASS-METHODS class_teardown.

    METHODS setup.
    METHODS eur_maps_to_eu        FOR TESTING.
    METHODS chf_falls_through_else FOR TESTING.
    METHODS empty_double_no_rows  FOR TESTING.
ENDCLASS.

CLASS ltcl_carrier_region IMPLEMENTATION.

  METHOD class_setup.
    " Building the environment is EXPENSIVE - it clones the entity and its
    " data sources in the DB. Do it once per class, never per test.
    "
    " No dependency list: the framework parses the entity, finds its
    " first-level data sources (here SCARR) and doubles them itself.
    " I_DEPENDENCY_LIST is for hierarchy testing, not for unit tests.
    environment = cl_cds_test_environment=>create( i_for_entity = 'Z_CARRIER_REGION' ).
  ENDMETHOD.

  METHOD setup.
    mo_reader = NEW #( ).

    " Doubles are NOT emptied automatically between test methods.
    environment->clear_doubles( ).
  ENDMETHOD.

  METHOD class_teardown.
    " Drops the generated doubles and the entity clone. Skipping this
    " leaves artifacts behind in the database schema.
    environment->destroy( ).
  ENDMETHOD.

  METHOD eur_maps_to_eu.
    " Seed the DATA SOURCE (SCARR), not the view. The view is what you
    " assert on - it is evaluated for real by the CDS engine.
    DATA lt_scarr TYPE STANDARD TABLE OF scarr.
    lt_scarr = VALUE #( ( mandt    = sy-mandt
                          carrid   = 'LH'
                          carrname = 'Lufthansa'
                          currcode = 'EUR' ) ).
    environment->insert_test_data( lt_scarr ).

    DATA(lt_rows) = mo_reader->list_regions( ).

    cl_abap_unit_assert=>assert_equals( exp = 1
                                        act = lines( lt_rows ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'EU'
                                        act = lt_rows[ 1 ]-region ).
  ENDMETHOD.

  METHOD chf_falls_through_else.
    " The ELSE branch is the one a hand-rolled fake never covers.
    DATA lt_scarr TYPE STANDARD TABLE OF scarr.
    lt_scarr = VALUE #( ( mandt    = sy-mandt
                          carrid   = 'XX'
                          carrname = 'Mystery Air'
                          currcode = 'CHF' ) ).
    environment->insert_test_data( lt_scarr ).

    cl_abap_unit_assert=>assert_equals( exp = 'OTHER'
                                        act = mo_reader->list_regions( )[ 1 ]-region ).
  ENDMETHOD.

  METHOD empty_double_no_rows.
    " Nothing inserted: the double is empty, so the view returns nothing.
    " Proof that the test is reading the double and not the real SCARR.
    cl_abap_unit_assert=>assert_initial( mo_reader->list_regions( ) ).
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Lifecycle - the fixed shape of every CDS test class
*&---------------------------------------------------------------------*
*  CLASS_SETUP     CL_CDS_TEST_ENVIRONMENT=>CREATE( I_FOR_ENTITY = ... )
*  SETUP           environment->CLEAR_DOUBLES( )
*  <test method>   environment->INSERT_TEST_DATA( <data source rows> )
*                  SELECT FROM <the CDS entity>  +  asserts
*  CLASS_TEARDOWN  environment->DESTROY( )
*
*  Same shape as CL_OSQL_TEST_ENVIRONMENT.
*&---------------------------------------------------------------------*


*&---------------------------------------------------------------------*
*& IF_CDS_TEST_ENVIRONMENT - the rest of the interface
*&---------------------------------------------------------------------*
*  ->insert_test_data( itab )        seed a double (typed by data source)
*  ->clear_doubles( )                empty all doubles
*  ->destroy( )                      tear the environment down
*  ->get_double( 'NAME' )            handle to one specific double
*  ->get_access_control_double( )    configure DCL/authorization behaviour
*  ->enable_double_redirection( )    see the trap below
*  ->disable_double_redirection( )
*  ->set_session_variables( )        USER, CLIENT, LANGUAGE, DATE,
*                                    USER_DATE, USER_TIMEZONE - needed if
*                                    the view branches on $session.*
*  ->insert_from_tdc( )              seed from an eCATT test data container
*
*  CREATE( ) parameters worth knowing:
*    I_FOR_ENTITY               the CDS entity under test
*    I_SELECT_BASE_DEPENDENCIES double the base tables further down the
*                               hierarchy rather than the first-level
*                               sources (hierarchy testing)
*    I_DEPENDENCY_LIST          explicit leaf list - NOT for unit tests;
*                               if supplied it must cover one node in
*                               every dependency path or CREATE throws
*    TEST_ASSOCIATIONS = 'X'    also double modeled associations; they are
*                               not runtime data sources, so they are NOT
*                               doubled by default
*&---------------------------------------------------------------------*


*&---------------------------------------------------------------------*
*& The trap: redirection is OFF by default (opposite of OSQL TDF)
*&---------------------------------------------------------------------*
*  The entity under test always reads the doubles - that is the point.
*  But a direct SELECT in your test code against a DOUBLED TABLE hits the
*  REAL database, not the double:
*
*    environment->insert_test_data( lt_scarr ).     " carrid = 'ZZ'
*    SELECT SINGLE carrname FROM scarr WHERE carrid = 'ZZ' INTO @lv_name.
*    " -> lv_name is whatever is really in SCARR. Usually initial.
*
*  CL_OSQL_TEST_ENVIRONMENT redirects such selects by default; CDS TDF
*  does not. Call ->ENABLE_DOUBLE_REDIRECTION( ) to flip it on, and reset
*  it in SETUP so one test cannot leak the state into the next.
*
*  Practical rule: assert against the CDS ENTITY, never against the
*  seeded tables.
*&---------------------------------------------------------------------*


*&---------------------------------------------------------------------*
*& Other gotchas
*&---------------------------------------------------------------------*
*  - CDS TDF doubles the entity's DEPENDENCIES, never the entity itself.
*    To force a result for a view your ABAP code consumes, that is
*    CL_OSQL_TEST_ENVIRONMENT with the view in I_DEPENDENCY_LIST.
*  - CLASS_SETUP / CLASS_TEARDOWN must be CLASS-METHODS. Declaring them
*    as instance METHODS silently never runs them as fixtures.
*  - Seed rows need MANDT / CLIENT filled (sy-mandt) - primary key
*    constraints are not copied to the double, so a wrong client does not
*    error, the view just returns nothing.
*  - For aggregating views (SUM/COUNT/GROUP BY) seed the base tables and
*    assert the aggregate. That is the whole value: the DB computes it.
*  - Tests cannot be launched from the DDL editor; run them from the
*    class holding the test include.
*  - CDS TDF is not suitable for performance testing.
*  - DISABLE_DCL on CREATE( ) is obsolete and ignored on current
*    releases - use GET_ACCESS_CONTROL_DOUBLE( ) instead. The default is
*    "no access control".
*&---------------------------------------------------------------------*
