*&---------------------------------------------------------------------*
*& Test Seams, Injections and the ABAP Unit test-class properties
*&
*& Two things that decide whether a unit test actually protects anything:
*&   1) TEST-SEAM / TEST-INJECTION - replacing a statement block in
*&      production code when the code cannot be made injectable.
*&   2) RISK LEVEL / DURATION / QUIT - the test-class properties that
*&      decide whether a test RUNS at all, and how far it gets.
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPTEST-SEAM.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPTEST-INJECTION.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCLASS_FOR_TESTING.html
*&
*& NOTE: the two parts below are SEPARATE repository objects in ADT - a
*&       class pool, and that class pool's Test Classes include. They are
*&       kept in one file here for readability.
*&
*&       TEST-SEAM only works in a CLASS POOL or a FUNCTION POOL, because
*&       injections must live in a test INCLUDE and only those two program
*&       types have one. A test seam in an executable report can never be
*&       injected.
*&---------------------------------------------------------------------*


*&---------------------------------------------------------------------*
*& 1) Production code - the class pool
*&---------------------------------------------------------------------*
CLASS zcl_flight_price DEFINITION PUBLIC CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS change_price
      IMPORTING carrid           TYPE s_carr_id
                connid           TYPE s_conn_id
                fldate           TYPE s_date
                factor           TYPE i
      RETURNING VALUE(new_price) TYPE s_price.

ENDCLASS.

CLASS zcl_flight_price IMPLEMENTATION.

  METHOD change_price.

    "wa and subrc are declared OUTSIDE the seam on purpose: an injection
    "can only touch data objects that are visible AT THE SEAM POSITION.
    "(A seam may declare data itself - such declarations are NOT replaced
    "by the injection and stay visible - but keeping them outside makes
    "the contract between seam and injection obvious.)
    DATA wa    TYPE sflight.
    DATA subrc TYPE sy-subrc.

    TEST-SEAM selection.
      SELECT SINGLE * FROM sflight
             WHERE carrid = @carrid
               AND connid = @connid
               AND fldate = @fldate
             INTO @wa.
      subrc = sy-subrc.
    END-TEST-SEAM.

    IF subrc <> 0.
      new_price = -1.
      RETURN.
    ENDIF.

    wa-price = wa-price * factor / 100.

    TEST-SEAM modification.
      UPDATE sflight FROM @wa.
      subrc = sy-subrc.
    END-TEST-SEAM.

    IF subrc <> 0.
      new_price = -2.
      RETURN.
    ENDIF.

    new_price = wa-price.

  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& 2) Test include of the SAME class pool (CCAU)
*&---------------------------------------------------------------------*
*  RISK LEVEL is NOT optional in practice. Leave it out and the class
*  defaults to CRITICAL - see the notes at the bottom of this file.
CLASS ltcl_flight_price DEFINITION FOR TESTING
                        RISK LEVEL HARMLESS
                        DURATION SHORT
                        FINAL.

  PRIVATE SECTION.
    METHODS setup.
    METHODS test_price_is_scaled     FOR TESTING.
    METHODS test_update_failure      FOR TESTING.
    METHODS test_selection_failure   FOR TESTING.
    METHODS invoke_and_assert
      IMPORTING exp TYPE s_price.

ENDCLASS.

CLASS ltcl_flight_price IMPLEMENTATION.

  METHOD setup.

    "An injection may be made in a test method or in SETUP - nowhere else.
    "Every replacement is cancelled at the END of each individual test, so
    "this one is re-established before each test method rather than once.
    TEST-INJECTION selection.
      wa-price = 100.
      subrc    = 0.
    END-TEST-INJECTION.

  ENDMETHOD.

  METHOD test_price_is_scaled.

    "An EMPTY injection is legal and REMOVES the seam's code - here the
    "UPDATE never runs, so the test touches no data at all. Note subrc
    "keeps the value the previous seam left it with (0), which is what
    "makes the happy-path case work.
    TEST-INJECTION modification.
    END-TEST-INJECTION.

    invoke_and_assert( exp = 90 ).

  ENDMETHOD.

  METHOD test_update_failure.

    "Same seam, different injection, same test run: a seam stays replaced
    "until the NEXT injection for it is reached.
    TEST-INJECTION modification.
      subrc = 4.
    END-TEST-INJECTION.

    invoke_and_assert( exp = -2 ).

  ENDMETHOD.

  METHOD test_selection_failure.

    TEST-INJECTION selection.
      subrc = 4.
    END-TEST-INJECTION.

    TEST-INJECTION modification.
    END-TEST-INJECTION.

    invoke_and_assert( exp = -1 ).

  ENDMETHOD.

  METHOD invoke_and_assert.

    DATA(lo_cut) = NEW zcl_flight_price( ).

    DATA(lv_new_price) = lo_cut->change_price( carrid = 'LH'
                                               connid = '0400'
                                               fldate = '20260101'
                                               factor = 90 ).

    cl_abap_unit_assert=>assert_equals( exp = exp
                                        act = lv_new_price ).

  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Injection scope - the rule that surprises everyone
*&---------------------------------------------------------------------*
*  An injection runs in the scope of the SEAM, not of the test method it
*  is written in. Types and objects of the test method are visible at the
*  TEST-INJECTION statement but NOT inside the injection block:
*
*    METHOD test_something.
*      DATA lv_expected TYPE i VALUE 42.
*      TEST-INJECTION selection.
*        wa-price = lv_expected.      "<-- does NOT compile: lv_expected
*      END-TEST-INJECTION.            "    is not visible in here
*    ENDMETHOD.
*
*  Route a value in through a static attribute of the test class, or set
*  it with a literal inside the injection.
*
*  Conversely, DATA declared INSIDE an injection survives: it is visible
*  below its declaration in that injection and in all FOLLOWING injections
*  of the test class - but never in the test class itself or in production
*  code. DATA is the only declarative statement allowed in an injection.
*&---------------------------------------------------------------------*


*&---------------------------------------------------------------------*
*& Further seam restrictions
*&---------------------------------------------------------------------*
*  - Seam names are unique per compilation unit; seams cannot be nested.
*  - A seam cannot cross a statement-block boundary (no opening an IF in
*    the seam and closing it outside), but may contain whole closed
*    control structures.
*  - Seams may sit in the global declaration part of a program, but NOT
*    in the declaration part of a class.
*  - A seam may be empty - the injection is then inserted in its place.
*  - Seams cannot be defined in test classes.
*  - Seam and injection must be in the SAME compilation unit.
*
*  Test seams are a last resort. If the dependency can be passed in, use
*  constructor injection plus a test double (see the TDF demo in this
*  folder). Seams modify production code to make it testable, and a seam
*  that is injected in every test means the production path is never the
*  one under test.
*&---------------------------------------------------------------------*


*&---------------------------------------------------------------------*
*& RISK LEVEL - the default that makes tests silently not run
*&---------------------------------------------------------------------*
*  CLASS ... DEFINITION FOR TESTING.          "no RISK LEVEL addition
*
*  defaults to RISK LEVEL CRITICAL:
*
*    CRITICAL   the test changes system settings or customizing (DEFAULT)
*    DANGEROUS  the test changes persistent data
*    HARMLESS   the test changes neither
*
*  "Tests whose risk level is higher than specified by administration in
*  transaction SAUNIT_CLIENT_SETUP are not executed."
*
*  Most systems cap the allowed level well below CRITICAL, so a test class
*  written without the addition is NOT RUN - it is reported as skipped,
*  not as failed. Always state RISK LEVEL HARMLESS explicitly.
*
*  DURATION SHORT | MEDIUM | LONG is the EXPECTED runtime (seconds / about
*  a minute / more than a minute), checked against upper limits also held
*  in SAUNIT_CLIENT_SETUP. Declare the honest expectation, not the limit:
*  a test that exceeds the limit for its DURATION can be aborted, and the
*  limits differ per system.
*&---------------------------------------------------------------------*


*&---------------------------------------------------------------------*
*& QUIT - why the second assert in a failing test never reports
*&---------------------------------------------------------------------*
*  Every method of CL_ABAP_UNIT_ASSERT takes optional MSG, LEVEL and QUIT.
*
*    QUIT = NO        continue the test method after the failure
*           METHOD    abort THIS test method                    (DEFAULT)
*           CLASS     abort the whole test class
*           PROGRAM   abort this class AND skip every other test class
*
*  Because METHOD is the default, a test method with five asserts reports
*  only the FIRST failure; fix it and the next one appears. For a method
*  that validates several independent fields, pass QUIT = if_aunit_constants=>no
*  (or better: split it into separate test methods).
*
*    LEVEL = TOLERABLE | CRITICAL (default) | FATAL
*
*  Assertion asymmetry worth knowing: ASSERT_EQUALS compares DEEPLY -
*  structures and internal tables, nested ones included - while
*  ASSERT_DIFFERS only takes elementary (SIMPLE) operands. "Assert these
*  two tables are equal" works; "assert these two tables differ" does not.
*  Floats need ASSERT_EQUALS_FLOAT with its RTOL tolerance, not
*  ASSERT_EQUALS.
*
*  Never pass a system field as ACT: by the time the parameter is
*  evaluated, sy-subrc may already belong to a different statement. That
*  is what ASSERT_SUBRC exists for.
*&---------------------------------------------------------------------*


*&---------------------------------------------------------------------*
*& Test-class facts that are easy to get wrong
*&---------------------------------------------------------------------*
*  - Test-class code is NOT generated in production systems (profile
*    parameter abap/test_generation) and is NOT counted in code coverage.
*  - Production code can never address a test class. A subclass of a test
*    class must itself be FOR TESTING. The single exception: a production
*    class may name the test class in LOCAL FRIENDS, which is how private
*    components get tested.
*  - setup / teardown / class_setup / class_teardown are fixture methods,
*    NOT test methods - the FOR TESTING addition is not allowed on them,
*    and class_setup / class_teardown must be CLASS-METHODS (see the CDS
*    test double section of this folder's README for the silent-no-op
*    failure mode).
*  - Test methods should be PRIVATE. The ABAP Unit driver is an implicit
*    friend of every test class and calls them regardless.
*  - INTERFACES ... PARTIALLY IMPLEMENTED lets a hand-written test double
*    implement only the methods a test actually needs.
*  - Production code called from a test must end regularly or via RETURN.
*    LEAVE PROGRAM, LEAVE TO TRANSACTION and SUBMIT without AND RETURN are
*    not allowed during a unit test.
*&---------------------------------------------------------------------*
