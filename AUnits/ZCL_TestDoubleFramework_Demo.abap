*&---------------------------------------------------------------------*
*& ABAP OO Test Double Framework (TDF) - end-to-end example
*&
*& Mocking a class/interface dependency with CL_ABAP_TESTDOUBLE, instead
*& of hand-writing a stub class per dependency.
*&
*& Available from SAP_BASIS 7.40 SP9 onwards.
*&
*& Docs: https://help.sap.com/docs/abap-cloud/abap-development-tools-user-guide/abap-oo-test-double-framework
*&       https://github.com/SAP-samples/abap-cheat-sheets/blob/main/14_ABAP_Unit_Tests.md
*&
*& NOTE: the three artifacts below are SEPARATE repository objects in ADT
*&       (interface pool, class pool, and the class' Test Classes include).
*&       They are kept in one file here for readability.
*&---------------------------------------------------------------------*


*&---------------------------------------------------------------------*
*& 1) The dependency (DOC) - must be a GLOBAL interface or class
*&---------------------------------------------------------------------*
INTERFACE zif_currency_converter PUBLIC.

  METHODS convert
    IMPORTING amount          TYPE i
              source_currency TYPE string
              target_currency TYPE string
    RETURNING VALUE(result)   TYPE i
    RAISING   zcx_currency_error.

  METHODS convert_to_base
    IMPORTING amount          TYPE i
              source_currency TYPE string
    EXPORTING base_currency   TYPE string
              base_amount     TYPE i.

ENDINTERFACE.


*&---------------------------------------------------------------------*
*& 2) Class under test (CUT) - takes the DOC via constructor injection
*&---------------------------------------------------------------------*
CLASS zcl_expense_manager DEFINITION PUBLIC CREATE PUBLIC.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING converter TYPE REF TO zif_currency_converter.

    METHODS total_in
      IMPORTING currency_code TYPE string
      RETURNING VALUE(total)  TYPE i
      RAISING   zcx_currency_error.

  PRIVATE SECTION.
    DATA mo_converter TYPE REF TO zif_currency_converter.
ENDCLASS.

CLASS zcl_expense_manager IMPLEMENTATION.

  METHOD constructor.
    mo_converter = converter.
  ENDMETHOD.

  METHOD total_in.
    " Two USD expenses of 100 each, converted via the injected dependency.
    DO 2 TIMES.
      total = total + mo_converter->convert( amount          = 100
                                             source_currency = `USD`
                                             target_currency = currency_code ).
    ENDDO.
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& 3) Local test class (Test Classes include of ZCL_EXPENSE_MANAGER)
*&---------------------------------------------------------------------*
CLASS ltcl_expense_manager DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_double TYPE REF TO zif_currency_converter.

    METHODS setup.
    METHODS total_uses_converter   FOR TESTING RAISING cx_static_check.
    METHODS converter_error_bubbles FOR TESTING RAISING cx_static_check.
    METHODS verify_call_count      FOR TESTING RAISING cx_static_check.
ENDCLASS.

CLASS ltcl_expense_manager IMPLEMENTATION.

  METHOD setup.
    " CREATE generates the double at runtime - no stub class to maintain.
    " It takes the interface NAME as a string, so the result must be cast.
    mo_double ?= cl_abap_testdouble=>create( 'ZIF_CURRENCY_CONVERTER' ).
  ENDMETHOD.

  METHOD total_uses_converter.
    " *** The key mental model ***
    " CONFIGURE_CALL arms the double for the *next* method call written on
    " it. That next call is a RECORDING, not a real invocation - its input
    " values form the matcher. Forgetting this line is the #1 TDF mistake.
    cl_abap_testdouble=>configure_call( mo_double )->returning( 80 )->times( 2 ).

    mo_double->convert( amount          = 100          " matcher, not a call
                        source_currency = `USD`
                        target_currency = `EUR` ).

    DATA(lo_cut) = NEW zcl_expense_manager( mo_double ).

    cl_abap_unit_assert=>assert_equals( exp = 160
                                        act = lo_cut->total_in( `EUR` ) ).
  ENDMETHOD.

  METHOD converter_error_bubbles.
    " Exceptions must be instantiated first, then handed to RAISE_EXCEPTION.
    " Only class-based exceptions are supported.
    DATA(lo_error) = NEW zcx_currency_error( ).

    cl_abap_testdouble=>configure_call( mo_double )->raise_exception( lo_error
                                      )->ignore_all_parameters( ).

    mo_double->convert( amount          = 0            " dummy - all ignored
                        source_currency = `USD`
                        target_currency = `EUR` ).

    TRY.
        NEW zcl_expense_manager( mo_double )->total_in( `EUR` ).
        cl_abap_unit_assert=>fail( 'Expected ZCX_CURRENCY_ERROR' ).
      CATCH zcx_currency_error.
        " expected
    ENDTRY.
  ENDMETHOD.

  METHOD verify_call_count.
    " AND_EXPECT turns the double into a mock: the expectation is asserted
    " by VERIFY_EXPECTATIONS at the end of the test.
    cl_abap_testdouble=>configure_call( mo_double )->returning( 80
                                      )->and_expect( )->is_called_times( 2 ).

    mo_double->convert( amount          = 100
                        source_currency = `USD`
                        target_currency = `EUR` ).

    NEW zcl_expense_manager( mo_double )->total_in( `EUR` ).

    cl_abap_testdouble=>verify_expectations( mo_double ).
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Configuration cheat sheet (chain onto CONFIGURE_CALL)
*&---------------------------------------------------------------------*
*  ->returning( value )                  RETURNING parameter
*  ->set_parameter( name = 'BASE_AMOUNT' value = 80 )
*                                        EXPORTING/CHANGING parameter;
*                                        chain one call per parameter
*  ->ignore_parameter( 'AMOUNT' )        match on the other params only
*  ->ignore_all_parameters( )            match any input
*  ->raise_exception( lo_exc )           class-based exceptions only
*  ->raise_event( ... )                  raise an event on the call
*  ->times( n )                          config applies to n calls
*  ->and_expect( )->is_called_times( n ) expectation for VERIFY_EXPECTATIONS
*  ->set_matcher( lo_matcher )           custom matching logic
*  ->set_answer( lo_answer )             custom result logic
*
*  TIMES semantics: omitted => 1. Once a configuration is exhausted, the
*  LAST matching configuration keeps being returned - calls beyond the
*  configured count do NOT fail or return initial.
*
*  CONFIGURE_CALL arms exactly one method. Configure each mocked method
*  of the interface separately.
*&---------------------------------------------------------------------*


*&---------------------------------------------------------------------*
*& Limitations - check these BEFORE designing around TDF
*&---------------------------------------------------------------------*
*  CL_ABAP_TESTDOUBLE cannot create a double for:
*    - LOCAL classes/interfaces (must be a global repository object)
*    - classes declared FINAL
*    - classes declared CREATE PRIVATE
*    - classes declared FOR TESTING
*    - classes whose constructor has mandatory parameters
*
*  Other frameworks for other dependency kinds:
*    CL_OSQL_TEST_ENVIRONMENT  - DB tables / CDS view entities in ABAP SQL
*    CL_CDS_TEST_ENVIRONMENT   - logic inside CDS entities
*    CL_BOTD_TXBUFDBL_BO_TEST_ENV / CL_BOTD_MOCKEMLAPI_BO_TEST_ENV - RAP BOs
*&---------------------------------------------------------------------*
