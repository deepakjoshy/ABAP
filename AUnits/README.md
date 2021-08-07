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
