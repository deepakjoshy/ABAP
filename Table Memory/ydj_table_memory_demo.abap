*&---------------------------------------------------------------------*
*& Report YDJ_TABLE_MEMORY_DEMO
*&---------------------------------------------------------------------*
*& Internal table memory: what an assignment actually costs, and why
*& CLEAR gives nothing back.
*&
*&   1. SHARING       -> lt_copy = lt_big copies NO rows. The table body
*&                       is shared. The duplication happens later, at
*&                       the first write to EITHER side (copy-on-write).
*&   2. WHO PAYS      -> modifying the ORIGINAL pays the copy too. There
*&                       is no owner that gets to write for free.
*&   3. CLEAR/FREE/   -> DELETE frees essentially nothing, CLEAR keeps
*&      DELETE           the INITIAL SIZE block, only FREE releases the
*&                       memory the rows occupied.
*&   4. BOXED         -> a static box shares ONE initial value until
*&                       something touches it - and ASSIGN, a data
*&                       reference and parameter passing all count as
*&                       touching, not just a write.
*&
*& Self-contained: no DDIC objects, no database access, no writes.
*&
*& NOTE ON THE NUMBERS
*& -------------------
*& The byte figures printed here come from
*& CL_ABAP_MEMORY_UTILITIES=>GET_MEMORY_SIZE_OF_OBJECT. They are real
*& but they are NOT stable across releases, kernels or 32/64-bit hosts,
*& and the documentation states outright that programming must never be
*& based on when table sharing occurs and when it is cancelled again.
*& Read the RELATIVE jumps (did it multiply by ~N?), not the absolutes.
*&
*& IGNORE_TABLE_SHARING is the parameter that makes this measurable at
*& all: without it you get "memory this table adds on top of what it
*& shares", with it you get "memory this table would cost alone". Every
*& scenario below prints both, because the gap IS the lesson.
*&
*& MEASURING CHANGES WHAT YOU MEASURE - the honest caveat. Handing the
*& table to the helper below is pass by REFERENCE of the whole table,
*& not of a boxed component, so it does not itself revoke the initial
*& value sharing demonstrated in scenario 4. Passing the COMPONENT
*& (ls_row-payload) to any procedure would - which is exactly trap 4.
*&---------------------------------------------------------------------*
REPORT ydj_table_memory_demo.

CLASS lcl_mem_demo DEFINITION.

  PUBLIC SECTION.

    " Row type deliberately fat-ish so the copy is visible in bytes.
    TYPES: BEGIN OF ty_row,
             id    TYPE i,
             code  TYPE c LENGTH 20,
             descr TYPE c LENGTH 80,
             value TYPE p LENGTH 8 DECIMALS 2,
           END OF ty_row,
           ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    " A substructure used twice: once plain, once BOXED. Same content,
    " same length - the ONLY difference is the BOXED addition.
    TYPES: BEGIN OF ty_payload,
             f1 TYPE c LENGTH 100,
             f2 TYPE c LENGTH 100,
             f3 TYPE c LENGTH 100,
           END OF ty_payload.

    TYPES: BEGIN OF ty_plain_row,
             id      TYPE i,
             payload TYPE ty_payload,
           END OF ty_plain_row,
           ty_plain_rows TYPE STANDARD TABLE OF ty_plain_row
                              WITH EMPTY KEY.

    TYPES: BEGIN OF ty_boxed_row,
             id      TYPE i,
             payload TYPE ty_payload BOXED,
           END OF ty_boxed_row,
           ty_boxed_rows TYPE STANDARD TABLE OF ty_boxed_row
                              WITH EMPTY KEY.

    CONSTANTS c_rows TYPE i VALUE 5000.

    CLASS-METHODS:
      assignment_shares_the_body,
      original_pays_the_copy,
      clear_free_delete,
      boxed_initial_value_sharing,
      build_rows   IMPORTING iv_count       TYPE i
                   RETURNING VALUE(rt_rows) TYPE ty_rows,
      size_of      IMPORTING iv_object      TYPE any
                             iv_ignore      TYPE abap_bool
                                            DEFAULT abap_false
                   RETURNING VALUE(rv_size) TYPE abap_msize,
      report_size  IMPORTING iv_label       TYPE string
                             iv_object      TYPE any.

ENDCLASS.


CLASS lcl_mem_demo IMPLEMENTATION.

  METHOD build_rows.
    DATA ls_row TYPE ty_row.
    DATA lv_i   TYPE i.

    DO iv_count TIMES.
      lv_i         = sy-index.
      ls_row-id    = lv_i.
      ls_row-code  = 'CODE'.
      ls_row-descr = 'Row payload kept wide so a copy is visible'.
      ls_row-value = lv_i.
      APPEND ls_row TO rt_rows.
    ENDDO.
  ENDMETHOD.


  METHOD size_of.
    " GET_MEMORY_SIZE_OF_OBJECT exports ABAP_MSIZE. The importing flags
    " IGNORE_TABLE_SHARING / IGNORE_STRING_SHARING are typed C, so an
    " abap_bool fits. LOW_MEM is the honesty flag: when it is set, the
    " kernel had too little memory to compute the REFERENCED_* figures
    " and filled only BOUND_SIZE_*. We read BOUND_SIZE_USED, which is
    " filled either way, but we still surface the flag rather than
    " quietly printing a number of unknown provenance.
    DATA lv_bound   TYPE abap_msize.
    DATA lv_low_mem TYPE c LENGTH 1.

    CALL METHOD cl_abap_memory_utilities=>get_memory_size_of_object
      EXPORTING
        object               = iv_object
        ignore_table_sharing = iv_ignore
      IMPORTING
        bound_size_used      = lv_bound
        low_mem              = lv_low_mem.

    IF lv_low_mem = abap_true.
      WRITE: / '  (low_mem was set - figures are partial)'.
    ENDIF.

    rv_size = lv_bound.
  ENDMETHOD.


  METHOD report_size.
    " Two answers to "how big is this table", both correct:
    "   shared = what it ADDS on top of what it currently shares
    "   alone  = what it would cost with sharing ignored
    " They are equal when nothing is shared, and far apart when it is.
    " A benchmark that does not say which one it measured is not
    " reproducible - which is why both are always printed here.
    DATA lv_shared TYPE abap_msize.
    DATA lv_alone  TYPE abap_msize.

    lv_shared = size_of( iv_object = iv_object iv_ignore = abap_false ).
    lv_alone  = size_of( iv_object = iv_object iv_ignore = abap_true ).

    WRITE: / iv_label, 26 'shared:', lv_shared, 52 'alone:', lv_alone.
  ENDMETHOD.


*----------------------------------------------------------------------*
* 1. The assignment that copies nothing
*----------------------------------------------------------------------*
  METHOD assignment_shares_the_body.
    DATA lt_big  TYPE ty_rows.
    DATA lt_copy TYPE ty_rows.
    DATA ls_row  TYPE ty_row.

    WRITE: / '--- 1. Assignment shares the table body -------------'.
    SKIP.

    lt_big = build_rows( c_rows ).
    report_size( iv_label = `source, filled` iv_object = lt_big ).

    " THE ASSIGNMENT. Looks expensive. Copies no rows at all.
    lt_copy = lt_big.

    report_size( iv_label = `source, after =` iv_object = lt_big ).
    report_size( iv_label = `copy, after =`   iv_object = lt_copy ).

    WRITE: / 'Both tables report a small "shared" figure and a large'.
    WRITE: / '"alone" figure: one table body, two table headers.'.
    SKIP.

    " THE WRITE. Looks cheap. This is where c_rows rows get duplicated.
    ls_row-id = -1.
    APPEND ls_row TO lt_copy.

    report_size( iv_label = `copy, after APPEND` iv_object = lt_copy ).
    WRITE: / 'The APPEND of ONE row is what paid for', c_rows, 'rows.'.
    SKIP 2.
  ENDMETHOD.


*----------------------------------------------------------------------*
* 2. Either side triggers the copy - including the original
*----------------------------------------------------------------------*
  METHOD original_pays_the_copy.
    DATA lt_big  TYPE ty_rows.
    DATA lt_copy TYPE ty_rows.

    WRITE: / '--- 2. The ORIGINAL pays the copy too ---------------'.
    SKIP.

    lt_big  = build_rows( c_rows ).
    lt_copy = lt_big.

    report_size( iv_label = `source, sharing` iv_object = lt_big ).

    " Doc: sharing is cancelled when EITHER source OR target is
    " accessed in change mode. The original has no privileged status.
    " A read-only-LOOKING loop is still change-mode access here,
    " because ASSIGNING hands out a writable field symbol.
    LOOP AT lt_big ASSIGNING FIELD-SYMBOL(<ls_big>).
      <ls_big>-value = <ls_big>-value.   " writes the same value back
      EXIT.                              " one row is enough to trigger
    ENDLOOP.

    report_size( iv_label = `source, after write` iv_object = lt_big ).
    report_size( iv_label = `copy, after write`   iv_object = lt_copy ).

    WRITE: / 'Writing to the table you "own" duplicates it, because'.
    WRITE: / 'somebody else is still pointing at the same body.'.
    SKIP.
    WRITE: / 'LOOP ... ASSIGNING is a WRITE. LOOP ... INTO is not.'.
    SKIP 2.
  ENDMETHOD.


*----------------------------------------------------------------------*
* 3. DELETE frees nothing, CLEAR keeps the block, FREE releases
*----------------------------------------------------------------------*
  METHOD clear_free_delete.
    DATA lt_a     TYPE ty_rows.
    DATA lt_b     TYPE ty_rows.
    DATA lt_c     TYPE ty_rows.
    DATA lv_rem_a TYPE i.
    DATA lv_rem_b TYPE i.
    DATA lv_rem_c TYPE i.

    WRITE: / '--- 3. DELETE vs CLEAR vs FREE ----------------------'.
    SKIP.

    lt_a = build_rows( c_rows ).
    lt_b = lt_a.
    lt_c = lt_a.

    " Force each one into its own body first, so that what we measure
    " below is the CLEAR/FREE/DELETE and not the sharing from above.
    APPEND INITIAL LINE TO lt_a.
    APPEND INITIAL LINE TO lt_b.
    APPEND INITIAL LINE TO lt_c.

    report_size( iv_label = `before, table A` iv_object = lt_a ).

    " DELETE: doc says this does NOT usually free any memory.
    DELETE lt_a WHERE id > 10.
    lv_rem_a = lines( lt_a ).
    WRITE: / 'A: rows left after DELETE WHERE id > 10 :', lv_rem_a.
    report_size( iv_label = `after DELETE` iv_object = lt_a ).

    " CLEAR: frees the rows but keeps the initial memory requirement.
    CLEAR lt_b.
    lv_rem_b = lines( lt_b ).
    WRITE: / 'B: rows left after CLEAR                :', lv_rem_b.
    report_size( iv_label = `after CLEAR` iv_object = lt_b ).

    " FREE: releases the memory area the rows occupied.
    FREE lt_c.
    lv_rem_c = lines( lt_c ).
    WRITE: / 'C: rows left after FREE                 :', lv_rem_c.
    report_size( iv_label = `after FREE` iv_object = lt_c ).

    SKIP.
    WRITE: / 'Table A is down to a handful of rows and has given back'.
    WRITE: / 'almost nothing. "I deleted them" is not "I freed them".'.
    WRITE: / 'B and C both report zero rows and differ in memory: CLEAR'.
    WRITE: / 'keeps the initial block on purpose, to make refilling'.
    WRITE: / 'cheap. FREE is the one to use when you are finished.'.
    SKIP 2.
  ENDMETHOD.


*----------------------------------------------------------------------*
* 4. BOXED: initial value sharing, and the four ways to lose it
*----------------------------------------------------------------------*
  METHOD boxed_initial_value_sharing.
    DATA lt_plain TYPE ty_plain_rows.
    DATA lt_boxed TYPE ty_boxed_rows.
    DATA ls_plain TYPE ty_plain_row.
    DATA ls_boxed TYPE ty_boxed_row.
    DATA lv_i     TYPE i.

    WRITE: / '--- 4. BOXED and initial value sharing --------------'.
    SKIP.

    " Identical content. Only the payload of lt_boxed is BOXED, and in
    " BOTH tables the payload is left INITIAL - never written to.
    DO c_rows TIMES.
      lv_i = sy-index.

      ls_plain-id = lv_i.
      APPEND ls_plain TO lt_plain.

      ls_boxed-id = lv_i.
      APPEND ls_boxed TO lt_boxed.
    ENDDO.

    report_size( iv_label = `plain substructure` iv_object = lt_plain ).
    report_size( iv_label = `BOXED substructure` iv_object = lt_boxed ).

    WRITE: / 'Same rows, same field lengths. The plain table stores an'.
    WRITE: / 'initial 300-character payload once per row; the boxed one'.
    WRITE: / 'stores it once per AS instance and keeps a reference.'.
    SKIP.

    " Revoke it on ONE row. The doc lists FOUR actions, and only the
    " first is a write:
    "   1. writing to the box or one of its components
    "   2. ASSIGN of it or a component to a field symbol
    "   3. addressing it or a component via a data reference
    "   4. using it or a component as an actual parameter
    READ TABLE lt_boxed ASSIGNING FIELD-SYMBOL(<ls_boxed>) INDEX 1.
    IF sy-subrc = 0.
      ASSIGN <ls_boxed>-payload TO FIELD-SYMBOL(<ls_payload>).
      IF <ls_payload> IS ASSIGNED.
        " Deliberately no write. The ASSIGN alone was enough.
        CLEAR lv_i.
      ENDIF.
    ENDIF.

    report_size( iv_label = `BOXED after ASSIGN` iv_object = lt_boxed ).

    WRITE: / 'Nothing was written. A read-only ASSIGN materialised the'.
    WRITE: / 'structure for that row anyway.'.
    SKIP.
    WRITE: / 'And CLEAR cannot undo it: on a box that still shares, the'.
    WRITE: / 'doc says CLEAR does not act as a write and the state is'.
    WRITE: / 'kept; once revoked, CLEAR frees no memory and only writes'.
    WRITE: / 'initial values. There is no way back into sharing.'.
    SKIP 2.
  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  WRITE: / 'INTERNAL TABLE MEMORY - sharing, copy-on-write and BOXED'.
  WRITE: / 'Figures are ABAP_MSIZE bytes (bound_size_used).'.
  WRITE: / 'Relative jumps are the point; absolutes vary by kernel.'.
  SKIP 2.

  lcl_mem_demo=>assignment_shares_the_body( ).
  lcl_mem_demo=>original_pays_the_copy( ).
  lcl_mem_demo=>clear_free_delete( ).
  lcl_mem_demo=>boxed_initial_value_sharing( ).

  WRITE: / '--- Takeaways ---------------------------------------'.
  SKIP.
  WRITE: / '1. The assignment is cheap. The next write is not.'.
  WRITE: / '2. Either side triggers the copy, the original included.'.
  WRITE: / '3. FREE when finished, CLEAR when refilling, and never'.
  WRITE: / '   expect DELETE WHERE to give memory back.'.
  WRITE: / '4. BOXED pays only while nothing touches it - ASSIGN,'.
  WRITE: / '   data references and parameter passing all count.'.
  WRITE: / '5. Never program against sharing: the documentation'.
  WRITE: / '   calls the rules deliberately vague and release-'.
  WRITE: / '   dependent, and says so in those words.'.
