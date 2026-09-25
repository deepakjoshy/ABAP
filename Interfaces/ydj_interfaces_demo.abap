*&---------------------------------------------------------------------*
*& Report YDJ_INTERFACES_DEMO
*&---------------------------------------------------------------------*
*& INTERFACES, ALIASES and the composition rules -- the parts that are
*& not "an interface is a contract with no implementation".
*&
*& Every trap below COMPILES. The interesting failures are the ones the
*& syntax check does not stop.
*&
*& Trap numbering matches README.md in this folder.
*&
*&   1. NESTING IS FLAT         -> i1 inside i2 inside i3 is NOT three
*&                                 levels. The component keeps the name of
*&                                 the interface that DECLARED it, so the
*&                                 name is i1~m1 even from i3.
*&                                 i3~i1~m1 is not valid syntax at all.
*&   2. THE DIAMOND IS NOT A    -> two composites both containing i1 give
*&      DIAMOND                    ONE i1 in the class, implemented ONCE.
*&                                 There is no ambiguity to resolve, and
*&                                 no way to give the two paths different
*&                                 behaviour.
*&   3. ALIASES ARE RENAMES,    -> an alias is a second NAME for the same
*&      NOT COMPONENTS             component, in the same namespace. It
*&                                 cannot narrow visibility and it cannot
*&                                 give two interfaces separate storage.
*&   4. DATA VALUES IS AN       -> INTERFACES ... DATA VALUES sets start
*&      INITIAL VALUE, NOT A       values for interface ATTRIBUTES per
*&      SHARED SETTING             implementing class. CONSTANTS cannot be
*&                                 listed there at all.
*&   5. DEFAULT IGNORE FILLS    -> a non-implemented DEFAULT IGNORE method
*&      THE RESULT                 behaves like an empty body: a RETURNING
*&                                 parameter comes back INITIAL, not
*&                                 unset. 0 is a plausible number.
*&   6. STATIC ATTRIBUTES ARE   -> CLASS-DATA in an interface exists once
*&      PER CLASS, NOT PER         PER IMPLEMENTING CLASS. Two classes
*&      INTERFACE                  implementing the same interface do NOT
*&                                 share a counter.
*&   7. intf=>const WORKS,      -> the class component selector reaches an
*&      intf=>class_data DOES      interface's TYPES and CONSTANTS, but
*&      NOT                        NOT its CLASS-DATA. The working half
*&                                 runs; the failing half is a syntax
*&                                 error, so it stays a comment.
*&
*& Self-contained: local interfaces, local classes and literals only.
*& No DDIC objects, no database access, no COMMIT.
*&---------------------------------------------------------------------*
REPORT ydj_interfaces_demo.

*&---------------------------------------------------------------------*
*& The interface hierarchy used by traps 1 and 2.
*&
*&   lif_readable   -- the leaf, declares read( )
*&   lif_auditable  -- composite: INCLUDES lif_readable, adds audit( )
*&   lif_archivable -- composite: INCLUDES lif_readable, adds archive( )
*&
*& lcl_document implements BOTH composites. lif_readable therefore
*& arrives by two different paths -- and still exists exactly once.
*&---------------------------------------------------------------------*
INTERFACE lif_readable.
  METHODS read RETURNING VALUE(rv_text) TYPE string.
ENDINTERFACE.

INTERFACE lif_auditable.
  INTERFACES lif_readable.
  " An alias declared INSIDE an interface. Note what it aliases:
  " lif_readable~read, using the name of the interface that DECLARED
  " the method -- not a path through lif_auditable.
  ALIASES read_it FOR lif_readable~read.
  METHODS audit RETURNING VALUE(rv_text) TYPE string.
ENDINTERFACE.

INTERFACE lif_archivable.
  INTERFACES lif_readable.
  METHODS archive RETURNING VALUE(rv_text) TYPE string.
ENDINTERFACE.

*&---------------------------------------------------------------------*
*& Trap 4: DATA VALUES. lif_labelled declares two plain ATTRIBUTES and
*& one CONSTANT. Implementing classes may set start values for the
*& attributes -- and may NOT list the constant there.
*&---------------------------------------------------------------------*
INTERFACE lif_labelled.
  DATA gv_label  TYPE string.
  DATA gv_prefix TYPE string.
  CONSTANTS gc_fixed TYPE string VALUE `cannot be overridden`.
  METHODS describe RETURNING VALUE(rv_text) TYPE string.
ENDINTERFACE.

*&---------------------------------------------------------------------*
*& Trap 5 + 6: optional methods and interface static data.
*&---------------------------------------------------------------------*
INTERFACE lif_countable.
  " CLASS-DATA in an interface. It looks global. It is not -- see trap 6.
  CLASS-DATA gv_calls TYPE i.

  " A constant, for the intf=>const access in trap 7.
  CONSTANTS gc_kind TYPE string VALUE `countable`.

  METHODS bump.

  " DEFAULT makes the implementation OPTIONAL. IGNORE = behave like an
  " empty body when not implemented; FAIL = raise
  " CX_SY_DYN_CALL_ILLEGAL_METHOD instead.
  METHODS score DEFAULT IGNORE RETURNING VALUE(rv_score) TYPE i.
  METHODS verify DEFAULT FAIL RETURNING VALUE(rv_ok) TYPE abap_bool.
ENDINTERFACE.

*&---------------------------------------------------------------------*
*& lcl_document -- implements two composite interfaces that BOTH contain
*& lif_readable.
*&
*& There is exactly ONE lif_readable~read method to implement. Writing
*& two implementations is not possible: there is no second component to
*& implement. This is the whole of ABAP's answer to the diamond problem
*& -- it refuses to create the diamond in the first place.
*&---------------------------------------------------------------------*
CLASS lcl_document DEFINITION.
  PUBLIC SECTION.
    " Both composites listed. lif_readable arrives through both and
    " exists once.
    INTERFACES: lif_auditable,
                lif_archivable.

    " Aliases in the CLASS. Same rule again: the alias target uses the
    " name of the DECLARING interface.
    ALIASES: read    FOR lif_readable~read,
             audit   FOR lif_auditable~audit,
             archive FOR lif_archivable~archive.

    METHODS constructor IMPORTING iv_id TYPE string.

  PRIVATE SECTION.
    DATA mv_id TYPE string.
ENDCLASS.

CLASS lcl_document IMPLEMENTATION.
  METHOD constructor.
    mv_id = iv_id.
  ENDMETHOD.

  " Implemented ONCE, under the name of the declaring interface.
  " METHOD lif_auditable~lif_readable~read would not be valid syntax.
  METHOD lif_readable~read.
    rv_text = |document { mv_id } read|.
  ENDMETHOD.

  METHOD lif_auditable~audit.
    rv_text = |document { mv_id } audited|.
  ENDMETHOD.

  METHOD lif_archivable~archive.
    rv_text = |document { mv_id } archived|.
  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
*& Two classes implementing lif_countable, to show that its CLASS-DATA
*& is NOT shared between them (trap 6).
*&
*& lcl_counter_a implements everything.
*& lcl_counter_b deliberately implements only bump( ) -- score( ) and
*& verify( ) are optional, and their two DEFAULT kinds behave very
*& differently at runtime (trap 5).
*&---------------------------------------------------------------------*
CLASS lcl_counter_a DEFINITION.
  PUBLIC SECTION.
    INTERFACES lif_countable.
    ALIASES bump FOR lif_countable~bump.
ENDCLASS.

CLASS lcl_counter_a IMPLEMENTATION.
  METHOD lif_countable~bump.
    " gv_calls is reached as lif_countable~gv_calls -- but the storage
    " is lcl_counter_a's OWN. lcl_counter_b writes a different integer
    " through an identically spelled name. See trap 6.
    lif_countable~gv_calls = lif_countable~gv_calls + 1.
  ENDMETHOD.

  METHOD lif_countable~score.
    rv_score = 42.
  ENDMETHOD.

  METHOD lif_countable~verify.
    rv_ok = abap_true.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_counter_b DEFINITION.
  PUBLIC SECTION.
    " score( ) and verify( ) are NOT implemented below. That compiles,
    " because both were declared with DEFAULT in the interface.
    INTERFACES lif_countable.
    ALIASES bump FOR lif_countable~bump.
ENDCLASS.

CLASS lcl_counter_b IMPLEMENTATION.
  METHOD lif_countable~bump.
    lif_countable~gv_calls = lif_countable~gv_calls + 1.
  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
*& Two classes implementing lif_labelled with DIFFERENT start values
*& for the same interface attributes (trap 4).
*&
*& NOT POSSIBLE in either class -- a constant cannot be listed after
*& DATA VALUES, so this is a syntax error and stays commented:
*&     INTERFACES lif_labelled DATA VALUES gc_fixed = `something`.
*&---------------------------------------------------------------------*
CLASS lcl_invoice DEFINITION.
  PUBLIC SECTION.
    INTERFACES lif_labelled
      DATA VALUES gv_label  = `Invoice`
                  gv_prefix = `INV-`.
    ALIASES describe FOR lif_labelled~describe.
ENDCLASS.

CLASS lcl_invoice IMPLEMENTATION.
  METHOD lif_labelled~describe.
    rv_text = |{ lif_labelled~gv_prefix }{ lif_labelled~gv_label }|.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_credit_note DEFINITION.
  PUBLIC SECTION.
    " Same interface, same attributes, different start values.
    INTERFACES lif_labelled
      DATA VALUES gv_label  = `Credit note`
                  gv_prefix = `CRN-`.
    ALIASES describe FOR lif_labelled~describe.
ENDCLASS.

CLASS lcl_credit_note IMPLEMENTATION.
  METHOD lif_labelled~describe.
    rv_text = |{ lif_labelled~gv_prefix }{ lif_labelled~gv_label }|.
  ENDMETHOD.
ENDCLASS.

*&---------------------------------------------------------------------*
*& Driver
*&---------------------------------------------------------------------*
CLASS lcl_demo DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS main.
  PRIVATE SECTION.
    CLASS-METHODS trap_1_flat_nesting.
    CLASS-METHODS trap_2_one_instance.
    CLASS-METHODS trap_3_aliases.
    CLASS-METHODS trap_4_data_values.
    CLASS-METHODS trap_5_default_kinds.
    CLASS-METHODS trap_6_static_per_class.
ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

  METHOD main.
    trap_1_flat_nesting( ).
    trap_2_one_instance( ).
    trap_3_aliases( ).
    trap_4_data_values( ).
    trap_5_default_kinds( ).
    trap_6_static_per_class( ).
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& TRAP 1 -- nesting is flat, and the name never chains.
*&
*& lif_readable is two "levels" down (readable in auditable, auditable
*& in the class). The access name is still lif_readable~read.
*&---------------------------------------------------------------------*
  METHOD trap_1_flat_nesting.
    DATA lo_doc TYPE REF TO lcl_document.

    WRITE: / '=== TRAP 1: nesting is flat ==='.
    SKIP.

    lo_doc = NEW lcl_document( iv_id = 'D-1' ).

    " The declaring interface's name, not a path.
    DATA(lv_via_declaring) = lo_doc->lif_readable~read( ).
    WRITE: / 'lo_doc->lif_readable~read( ) :', lv_via_declaring.

    " NOT POSSIBLE -- the interface component selector cannot be chained:
    "   lo_doc->lif_auditable~lif_readable~read( )
    " Keyword docs, Interface Component Selector: "A direct chaining of
    " interface names intf1~...~intfn~comp is not possible."
    WRITE: / 'lo_doc->lif_auditable~lif_readable~read( ) : not valid syntax'.

    " An interface reference of the INNER interface binds directly to
    " the object, even though the class never named lif_readable in its
    " INTERFACES statement.
    DATA li_read TYPE REF TO lif_readable.
    li_read = lo_doc.
    DATA(lv_via_iref) = li_read->read( ).
    WRITE: / 'li_read->read( ) (iref of the INNER interface) :', lv_via_iref.

    SKIP.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& TRAP 2 -- the diamond that is not a diamond.
*&
*& lif_readable reaches lcl_document through lif_auditable AND through
*& lif_archivable. It exists ONCE. Both interface references below point
*& at the same single implementation, so the two paths can never
*& disagree -- and you cannot make them disagree even if you want to.
*&---------------------------------------------------------------------*
  METHOD trap_2_one_instance.
    DATA li_audit   TYPE REF TO lif_auditable.
    DATA li_archive TYPE REF TO lif_archivable.
    DATA li_r1      TYPE REF TO lif_readable.
    DATA li_r2      TYPE REF TO lif_readable.

    WRITE: / '=== TRAP 2: one component, two paths ==='.
    SKIP.

    DATA(lo_doc) = NEW lcl_document( iv_id = 'D-2' ).

    li_audit   = lo_doc.
    li_archive = lo_doc.

    " Narrow from each composite down to the shared component interface.
    li_r1 = li_audit.
    li_r2 = li_archive.

    DATA(lv_text_1) = li_r1->read( ).
    DATA(lv_text_2) = li_r2->read( ).

    WRITE: / 'via lif_auditable   :', lv_text_1.
    WRITE: / 'via lif_archivable  :', lv_text_2.

    " Same object, same single method. Reference identity proves it.
    DATA(lv_same) = xsdbool( li_r1 = li_r2 ).
    WRITE: / 'li_r1 = li_r2       :', lv_same.
    WRITE: / '(one implementation of read( ), reached two ways)'.

    SKIP.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& TRAP 3 -- an alias is a second name, not a second component.
*&
*& read( ) and lif_readable~read( ) are the SAME method. The alias is a
*& component of the class in the SAME namespace as everything else, so
*& it cannot be used to have both a "read" of your own and an interface
*& "read".
*&---------------------------------------------------------------------*
  METHOD trap_3_aliases.
    WRITE: / '=== TRAP 3: aliases rename, they do not duplicate ==='.
    SKIP.

    DATA(lo_doc) = NEW lcl_document( iv_id = 'D-3' ).

    " NOTE: using the full name AND the alias in one method is exactly
    " what the syntax check warns about. Done deliberately here, once,
    " to show they resolve to the same method. Do not copy the pattern.
    DATA(lv_long)  = lo_doc->lif_readable~read( ).
    DATA(lv_short) = lo_doc->read( ).          " the class alias

    WRITE: / 'lif_readable~read( ) :', lv_long.
    WRITE: / 'read( )  (alias)     :', lv_short.

    DATA(lv_identical) = xsdbool( lv_long = lv_short ).
    WRITE: / 'identical result     :', lv_identical.

    " The interface lif_auditable also declared an alias (read_it) for
    " the SAME method. Three names, one method.
    DATA li_audit TYPE REF TO lif_auditable.
    li_audit = lo_doc.
    DATA(lv_via_intf_alias) = li_audit->read_it( ).
    WRITE: / 'read_it( ) (intf alias) :', lv_via_intf_alias.

    WRITE: / 'NOTE: using BOTH the alias and intf~comp in one context'.
    WRITE: / '      raises a syntax-check WARNING. Pick one per context.'.

    SKIP.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& TRAP 4 -- DATA VALUES is a per-class initial value.
*&
*& Two classes, one interface, two different start values for the SAME
*& interface attribute. This is an initial value like DATA ... VALUE,
*& not shared configuration and not a constant override.
*&---------------------------------------------------------------------*
  METHOD trap_4_data_values.
    DATA li_inv TYPE REF TO lif_labelled.
    DATA li_crn TYPE REF TO lif_labelled.

    WRITE: / '=== TRAP 4: DATA VALUES sets start values per class ==='.
    SKIP.

    li_inv = NEW lcl_invoice( ).
    li_crn = NEW lcl_credit_note( ).

    DATA(lv_inv) = li_inv->describe( ).
    DATA(lv_crn) = li_crn->describe( ).

    WRITE: / 'lcl_invoice     describe( ) :', lv_inv.
    WRITE: / 'lcl_credit_note describe( ) :', lv_crn.

    " The constant is the same everywhere -- no class could change it,
    " because CONSTANTS cannot appear after DATA VALUES at all.
    DATA(lv_fixed) = lif_labelled=>gc_fixed.
    WRITE: / 'lif_labelled=>gc_fixed      :', lv_fixed.

    SKIP.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& TRAP 5 -- DEFAULT IGNORE returns a FILLED result.
*&
*& lcl_counter_b implements neither score( ) nor verify( ). The two
*& DEFAULT kinds then behave in opposite ways:
*&   IGNORE -> runs as an empty body, RETURNING comes back INITIAL (0)
*&   FAIL   -> raises CX_SY_DYN_CALL_ILLEGAL_METHOD
*&
*& IGNORE is the dangerous one: 0 is a perfectly plausible score, and
*& nothing anywhere reports that no code ran.
*&---------------------------------------------------------------------*
  METHOD trap_5_default_kinds.
    DATA li_a TYPE REF TO lif_countable.
    DATA li_b TYPE REF TO lif_countable.

    WRITE: / '=== TRAP 5: DEFAULT IGNORE vs DEFAULT FAIL ==='.
    SKIP.

    li_a = NEW lcl_counter_a( ).
    li_b = NEW lcl_counter_b( ).

    DATA(lv_score_a) = li_a->score( ).
    DATA(lv_score_b) = li_b->score( ).      " NOT implemented -> IGNORE

    WRITE: / 'counter_a score( ) (implemented)     :', lv_score_a.
    WRITE: / 'counter_b score( ) (DEFAULT IGNORE)  :', lv_score_b.
    WRITE: / '  -> no exception, no log, a filled 0.'.

    SKIP.

    " Same class, same non-implementation, opposite outcome.
    TRY.
        DATA(lv_ok) = li_b->verify( ).       " NOT implemented -> FAIL
        WRITE: / 'counter_b verify( ) returned    :', lv_ok.
      CATCH cx_sy_dyn_call_illegal_method INTO DATA(lx_call).
        DATA(lv_msg) = lx_call->get_text( ).
        WRITE: / 'counter_b verify( ) (DEFAULT FAIL) raised:'.
        WRITE: / '  ', lv_msg.
    ENDTRY.

    SKIP.
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& TRAP 6 -- interface CLASS-DATA is per implementing class.
*&
*& lif_countable declares ONE gv_calls. Two classes implement it. Each
*& gets its OWN gv_calls. Bumping one does not move the other.
*&
*& This is the "shared registry in the interface" idea failing silently:
*& the number is always plausible, just always partial.
*&---------------------------------------------------------------------*
  METHOD trap_6_static_per_class.
    WRITE: / '=== TRAP 6: interface CLASS-DATA is NOT shared ==='.
    SKIP.

    DATA(lo_a) = NEW lcl_counter_a( ).
    DATA(lo_b) = NEW lcl_counter_b( ).

    " Three calls on A, one on B. A single shared counter would read 4.
    lo_a->bump( ).
    lo_a->bump( ).
    lo_a->bump( ).
    lo_b->bump( ).

    " Addressed through the CLASS name -- the only way that works for
    " interface CLASS-DATA. See trap 7.
    DATA(lv_a) = lcl_counter_a=>lif_countable~gv_calls.
    DATA(lv_b) = lcl_counter_b=>lif_countable~gv_calls.
    DATA(lv_total) = lv_a + lv_b.

    WRITE: / 'bumps issued                          : 4'.
    WRITE: / 'lcl_counter_a=>lif_countable~gv_calls :', lv_a.
    WRITE: / 'lcl_counter_b=>lif_countable~gv_calls :', lv_b.
    WRITE: / 'sum                                   :', lv_total.
    WRITE: / '  -> two counters, not one. No error anywhere.'.

    SKIP.

    " TRAP 7, the half that works: the class component selector reaches
    " an interface's CONSTANTS and TYPES directly.
    DATA(lv_kind) = lif_countable=>gc_kind.
    WRITE: / 'lif_countable=>gc_kind (CONSTANTS)    :', lv_kind.

    " NOT POSSIBLE -- and this is a syntax error, so it stays commented:
    "   DATA(lv_x) = lif_countable=>gv_calls.
    " Keyword docs, CLASS-DATA: "Static attributes declared using
    " CLASS-DATA can be accessed using the class component selector only
    " with class names, not with interface names."
    WRITE: / 'lif_countable=>gv_calls (CLASS-DATA)  : not valid syntax'.

    SKIP.
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  lcl_demo=>main( ).
