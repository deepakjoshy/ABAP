*&---------------------------------------------------------------------*
*& Report YDJ_CONSTRUCTOR_DEMO
*&---------------------------------------------------------------------*
*& Instance and static constructors - the documented rules that differ
*& from every other OO language an ABAP developer has met.
*&
*&   1. NO VIRTUAL DISPATCH -> a method called from a constructor runs the
*&                             implementation of the CONSTRUCTOR class, not
*&                             the subclass redefinition. The exact
*&                             opposite of Java/C#.
*&   2. THE super-> SPLIT   -> before super->constructor( ) the constructor
*&                             behaves like a STATIC method: no me->, no
*&                             instance attributes.
*&   3. CONSTANTS DO NOT    -> reading a CONSTANT or a TYPE of a class is
*&      TRIGGER IT             not an access, so class_constructor does
*&                             NOT run and CLASS-DATA stays initial.
*&   4. SUBCLASS NAME,      -> lcl_sub_s=>gv_counter addresses the
*&      SUPERCLASS CTOR        SUPERCLASS, so only ITS class_constructor
*&                             runs. The subclass one does not.
*&   5. FAILED CREATE       -> an exception in the instance constructor
*&      CLEARS YOUR REF        DELETES the object and INITIALIZES oref -
*&                             including a reference that was valid before.
*&
*& Self-contained: local classes and literals only, no DDIC, no database.
*&---------------------------------------------------------------------*
REPORT ydj_constructor_demo.

*&---------------------------------------------------------------------*
*& A logger the other classes write to from class_constructor. It has no
*& static constructor of its own, so touching it proves nothing about the
*& classes under test.
*&---------------------------------------------------------------------*
CLASS lcl_log DEFINITION.

  PUBLIC SECTION.
    TYPES ty_lines TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    CLASS-DATA gt_lines TYPE ty_lines.
    CLASS-METHODS add   IMPORTING iv_text TYPE string.
    CLASS-METHODS count RETURNING VALUE(rv_count) TYPE i.

ENDCLASS.

CLASS lcl_log IMPLEMENTATION.

  METHOD add.
    APPEND iv_text TO gt_lines.
  ENDMETHOD.

  METHOD count.
    rv_count = lines( gt_lines ).
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& 1. A constructor does NOT see subclass redefinitions.
*&---------------------------------------------------------------------*
CLASS lcl_base DEFINITION.

  PUBLIC SECTION.
    METHODS constructor.
    METHODS describe     RETURNING VALUE(rv_text) TYPE string.
    METHODS get_built_as RETURNING VALUE(rv_text) TYPE string.

  PROTECTED SECTION.
    DATA mv_built_as TYPE string.

ENDCLASS.

CLASS lcl_base IMPLEMENTATION.

  METHOD constructor.
    " Implicit self reference. Looks polymorphic. Is not.
    mv_built_as = describe( ).
  ENDMETHOD.

  METHOD describe.
    rv_text = 'lcl_base'.
  ENDMETHOD.

  METHOD get_built_as.
    rv_text = mv_built_as.
  ENDMETHOD.

ENDCLASS.


CLASS lcl_derived DEFINITION INHERITING FROM lcl_base.

  PUBLIC SECTION.
    METHODS describe REDEFINITION.

ENDCLASS.

CLASS lcl_derived IMPLEMENTATION.

  METHOD describe.
    rv_text = 'lcl_derived'.
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& 2. super->constructor( ) splits the constructor into two halves.
*&---------------------------------------------------------------------*
CLASS lcl_split_base DEFINITION.

  PUBLIC SECTION.
    METHODS constructor IMPORTING iv_key TYPE string.
    DATA mv_key TYPE string READ-ONLY.

ENDCLASS.

CLASS lcl_split_base IMPLEMENTATION.

  METHOD constructor.
    mv_key = iv_key.
  ENDMETHOD.

ENDCLASS.


CLASS lcl_split_sub DEFINITION INHERITING FROM lcl_split_base.

  PUBLIC SECTION.
    METHODS constructor IMPORTING iv_raw TYPE string.
    DATA mv_raw TYPE string READ-ONLY.

ENDCLASS.

CLASS lcl_split_sub IMPLEMENTATION.

  METHOD constructor.

    " --- FIRST HALF: behaves like a STATIC method. -------------------
    " me-> does not exist yet and instance attributes are unreachable.
    " The next line is a SYNTAX ERROR here, which is why it is commented:
    "   mv_raw = iv_raw.
    " Only local data, importing parameters and static attributes are
    " usable - they exist to build the superclass actual parameters.
    DATA(lv_key) = to_upper( iv_raw ).

    super->constructor( iv_key = lv_key ).

    " --- SECOND HALF: me-> and instance attributes are now available. -
    mv_raw = iv_raw.

  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& 3. Constants do not count as an access to the class.
*&---------------------------------------------------------------------*
CLASS lcl_cfg DEFINITION.

  PUBLIC SECTION.
    CONSTANTS  c_name    TYPE string VALUE 'CFG'.
    CLASS-DATA gv_loaded TYPE string.
    CLASS-METHODS class_constructor.

ENDCLASS.

CLASS lcl_cfg IMPLEMENTATION.

  METHOD class_constructor.
    " A static constructor cannot explicitly address its OWN class, so
    " this is gv_loaded, never lcl_cfg=>gv_loaded.
    gv_loaded = 'LOADED'.
    lcl_log=>add( 'lcl_cfg class_constructor ran' ).
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& 4. A subclass name in front of an INHERITED static component
*&    addresses the superclass.
*&---------------------------------------------------------------------*
CLASS lcl_sup DEFINITION.

  PUBLIC SECTION.
    CLASS-DATA gv_counter TYPE i.
    CLASS-METHODS class_constructor.

ENDCLASS.

CLASS lcl_sup IMPLEMENTATION.

  METHOD class_constructor.
    gv_counter = 1.
    lcl_log=>add( 'lcl_sup class_constructor ran' ).
  ENDMETHOD.

ENDCLASS.


CLASS lcl_sub_s DEFINITION INHERITING FROM lcl_sup.

  PUBLIC SECTION.
    CLASS-METHODS class_constructor.

ENDCLASS.

CLASS lcl_sub_s IMPLEMENTATION.

  METHOD class_constructor.
    lcl_log=>add( 'lcl_sub_s class_constructor ran' ).
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& 5. An exception in the instance constructor initializes oref.
*&---------------------------------------------------------------------*
CLASS lcx_bad DEFINITION INHERITING FROM cx_static_check.
ENDCLASS.

CLASS lcx_bad IMPLEMENTATION.
ENDCLASS.


CLASS lcl_fragile DEFINITION.

  PUBLIC SECTION.
    METHODS constructor IMPORTING iv_ok TYPE abap_bool
                        RAISING   lcx_bad.
    DATA mv_id TYPE i READ-ONLY.

ENDCLASS.

CLASS lcl_fragile IMPLEMENTATION.

  METHOD constructor.
    IF iv_ok = abap_false.
      RAISE EXCEPTION TYPE lcx_bad.
    ENDIF.
    mv_id = 42.
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Driver. Each trap sits in its OWN method, i.e. its own processing
*& block - which matters for traps 3 and 4.
*&---------------------------------------------------------------------*
CLASS lcl_demo DEFINITION.

  PUBLIC SECTION.
    CLASS-METHODS:
      no_virtual_dispatch,
      the_super_split,
      constant_does_not_trigger,
      static_var_does_trigger,
      subclass_name_runs_super_ctor,
      failed_create_clears_ref.

ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

  METHOD no_virtual_dispatch.

    DATA(lo_obj) = NEW lcl_derived( ).

    " Set INSIDE the lcl_base constructor, on an lcl_derived instance.
    DATA(lv_during) = lo_obj->get_built_as( ).

    " The very same call, made after construction has finished.
    DATA(lv_after) = lo_obj->describe( ).

    WRITE: / '1. NO VIRTUAL DISPATCH'.
    WRITE: / '   describe( ) from the constructor :', lv_during.
    WRITE: / '   describe( ) after construction   :', lv_after.
    WRITE: / '   Same object, same method, two different answers.'.
    SKIP.

  ENDMETHOD.

  METHOD the_super_split.

    DATA(lo_obj) = NEW lcl_split_sub( 'order-4711' ).

    DATA(lv_raw) = lo_obj->mv_raw.
    DATA(lv_key) = lo_obj->mv_key.

    WRITE: / '2. THE super-> SPLIT'.
    WRITE: / '   set before super (superclass attr):', lv_key.
    WRITE: / '   set after  super (subclass attr)  :', lv_raw.
    SKIP.

  ENDMETHOD.

  METHOD constant_does_not_trigger.

    " The ONLY access to lcl_cfg in this processing block is a constant.
    DATA(lv_name) = lcl_cfg=>c_name.

    DATA(lv_logged) = lcl_log=>count( ).

    WRITE: / '3. CONSTANT ACCESS'.
    WRITE: / '   read c_name                      :', lv_name.
    WRITE: / '   class_constructor calls so far   :', lv_logged.
    SKIP.

  ENDMETHOD.

  METHOD static_var_does_trigger.

    DATA(lv_loaded) = lcl_cfg=>gv_loaded.

    DATA(lv_logged) = lcl_log=>count( ).

    WRITE: / '4. STATIC ATTRIBUTE ACCESS'.
    WRITE: / '   read gv_loaded                   :', lv_loaded.
    WRITE: / '   class_constructor calls so far   :', lv_logged.
    SKIP.

  ENDMETHOD.

  METHOD subclass_name_runs_super_ctor.

    DATA(lv_before) = lcl_log=>count( ).

    " gv_counter is INHERITED. Writing the subclass name in front of it
    " addresses lcl_sup, so lcl_sub_s class_constructor does NOT run.
    DATA(lv_counter) = lcl_sub_s=>gv_counter.

    DATA(lv_after) = lcl_log=>count( ).
    DATA(lv_new)   = lv_after - lv_before.

    WRITE: / '5. SUBCLASS NAME, SUPERCLASS CONSTRUCTOR'.
    WRITE: / '   read lcl_sub_s gv_counter        :', lv_counter.
    WRITE: / '   class_constructors triggered     :', lv_new.
    WRITE: / '   (lcl_sup only - not lcl_sub_s)'.
    SKIP.

  ENDMETHOD.

  METHOD failed_create_clears_ref.

    DATA lo_ref TYPE REF TO lcl_fragile.

    TRY.
        CREATE OBJECT lo_ref EXPORTING iv_ok = abap_true.
      CATCH lcx_bad.
    ENDTRY.

    DATA(lv_id_ok)    = lo_ref->mv_id.
    DATA(lv_bound_ok) = boolc( lo_ref IS BOUND ).

    " Re-create into the SAME reference variable, and fail.
    TRY.
        CREATE OBJECT lo_ref EXPORTING iv_ok = abap_false.
      CATCH lcx_bad.
    ENDTRY.

    DATA(lv_bound_bad) = boolc( lo_ref IS BOUND ).

    WRITE: / '6. FAILED CREATE CLEARS THE REFERENCE'.
    WRITE: / '   first object mv_id               :', lv_id_ok.
    WRITE: / '   IS BOUND after success           :', lv_bound_ok.
    WRITE: / '   IS BOUND after failed re-create  :', lv_bound_bad.
    WRITE: / '   The previously valid object is gone, not retained.'.
    SKIP.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_demo=>no_virtual_dispatch( ).
  lcl_demo=>the_super_split( ).
  lcl_demo=>constant_does_not_trigger( ).
  lcl_demo=>static_var_does_trigger( ).
  lcl_demo=>subclass_name_runs_super_ctor( ).
  lcl_demo=>failed_create_clears_ref( ).
