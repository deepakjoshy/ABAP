*&---------------------------------------------------------------------*
*& Report YDJ_SQL_WRITE_DEMO
*&---------------------------------------------------------------------*
*& ABAP SQL write access - INSERT / UPDATE / MODIFY / DELETE.
*&
*& Four statements that look interchangeable and are not. Every trap
*& shown here is a DATA-CORRECTNESS bug, not a performance one, and
*& none of them raises a syntax error.
*&
*&   1. WHOLE-ROW        -> UPDATE ... FROM @wa writes EVERY column, so
*&      OVERWRITE           the fields you did not fill are blanked.
*&                          SET, BASE or set indicators are the fixes.
*&   2. SET INDICATORS   -> the mass-update form of SET. Indicator
*&                          structure must be the LAST component and
*&                          only 'X' / hex 1 counts as "update me".
*&   3. DUPLICATE KEYS   -> INSERT ... FROM TABLE has three different
*&                          outcomes; an uncaught CX_SY_OPEN_SQL_DB
*&                          rolls back the WHOLE database LUW.
*&   4. MODIFY FROM      -> platform-dependent (UPDATE-then-INSERT vs
*&      TABLE               row-by-row) when the table has a unique
*&                          secondary index.
*&   5. sy-subrc VS      -> sy-subrc = 4 after a FROM TABLE write does
*&      sy-dbcnt            NOT mean nothing happened; and an EMPTY
*&                          table gives sy-subrc = 0.
*&
*& READ-ONLY. This report executes NO write statement at all - every
*& INSERT/UPDATE/MODIFY/DELETE is shown as a comment with its expected
*& outcome beside it. The runnable parts only SELECT from the standard
*& SFLIGHT/SCUSTOM demo tables (run SAPBC_DATA_GENERATOR if empty).
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPUPDATE_SOURCE.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINSERT_SOURCE.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMODIFY_SOURCE.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPUPDATE_SET_INDICATOR.html
*&---------------------------------------------------------------------*
REPORT ydj_sql_write_demo.

CLASS lcl_write_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      whole_row_overwrite,
      set_indicator_layout,
      duplicate_key_outcomes,
      modify_platform_dependency,
      subrc_versus_dbcnt.

  PRIVATE SECTION.

    CLASS-METHODS:
      separator IMPORTING iv_title TYPE string.

ENDCLASS.


CLASS lcl_write_demo IMPLEMENTATION.

  METHOD separator.

    DATA lv_line TYPE c LENGTH 70.

    lv_line = '----------------------------------------------------------------------'.

    SKIP.
    WRITE: / lv_line.
    WRITE: / iv_title COLOR COL_HEADING.
    WRITE: / lv_line.

  ENDMETHOD.


  METHOD whole_row_overwrite.
*   TRAP 1 -------------------------------------------------------------
*   "The content of the work area is assigned to the rows found. The
*    assignment takes place without conversion, FROM LEFT TO RIGHT
*    according to the structure of the DDIC database table."
*
*   Left to right, ALL of it. A partially filled work area does not
*   mean "leave the rest alone" - it means "write initial values".

    separator( |1. UPDATE ... FROM @wa overwrites every column| ).

    SELECT SINGLE *
      FROM scustom
      INTO @DATA(ls_real).

    IF sy-subrc <> 0.
      WRITE: / 'No SCUSTOM data - run SAPBC_DATA_GENERATOR.'.
      RETURN.
    ENDIF.

*   The "targeted" change a developer thinks they are writing.
    DATA ls_partial TYPE scustom.
    ls_partial-id       = ls_real-id.
    ls_partial-discount = '003'.

*   UPDATE scustom FROM @ls_partial.
*     -> discount becomes '003'
*     -> name, city, street, telephone, email ... ALL BLANKED

    WRITE: / 'Row as it exists on the database:'.
    WRITE: /3 'id       :', ls_real-id.
    WRITE: /3 'name     :', ls_real-name.
    WRITE: /3 'city     :', ls_real-city.
    WRITE: /3 'discount :', ls_real-discount.

    WRITE: / 'Work area handed to UPDATE ... FROM @wa:'.
    WRITE: /3 'id       :', ls_partial-id.
    WRITE: /3 'name     :', ls_partial-name, '<- initial, would be WRITTEN'.
    WRITE: /3 'city     :', ls_partial-city, '<- initial, would be WRITTEN'.
    WRITE: /3 'discount :', ls_partial-discount.

*   FIX (a): SET names exactly what changes.
*   UPDATE scustom SET discount = '003' WHERE id = @ls_real-id.

*   FIX (b): BASE carries every other column across unchanged.
    DATA(ls_based) = VALUE scustom( BASE ls_real discount = '003' ).

    WRITE: / 'Same edit built with VALUE #( BASE old ... ):'.
    WRITE: /3 'id       :', ls_based-id.
    WRITE: /3 'name     :', ls_based-name, '<- preserved'.
    WRITE: /3 'city     :', ls_based-city, '<- preserved'.
    WRITE: /3 'discount :', ls_based-discount, '<- changed'.

*   NOTE: (b) is a read-modify-write. Another user can change the row
*   between the SELECT and the UPDATE, and this statement then writes
*   a stale copy of every other column over their change. The fix for
*   THAT is an enqueue lock around the pair, not a tighter WHERE.

  ENDMETHOD.


  METHOD set_indicator_layout.
*   TRAP 2 -------------------------------------------------------------
*   SET cannot be combined with FROM TABLE. Set indicators are the
*   mass-update equivalent: mark the columns to change, leave the rest
*   of the row untouched.

    separator( |2. Set indicators - layout and the 'X'-only rule| ).

*   The indicator structure must be the LAST component of the row type
*   and have one component per column of the target table.
    TYPES ty_ind_wa TYPE scustom WITH INDICATORS col_ind TYPE abap_boolean.

    DATA lt_ind TYPE STANDARD TABLE OF ty_ind_wa WITH EMPTY KEY.

    lt_ind = VALUE #(
      ( id = '00017777' discount = '003' col_ind-discount = abap_true )
      ( id = '00017778' discount = '005' col_ind-discount = abap_true ) ).

*   UPDATE scustom FROM TABLE @lt_ind INDICATORS SET STRUCTURE col_ind.
*     -> ONLY the discount column is written on those two rows.
*     -> Without the addition, both rows would be overwritten entirely.

    DATA lv_marked TYPE i.
    DATA lv_rows   TYPE i.

    lv_rows = lines( lt_ind ).

    LOOP AT lt_ind ASSIGNING FIELD-SYMBOL(<ls_ind>).
      IF <ls_ind>-col_ind-discount = abap_true.
        lv_marked = lv_marked + 1.
      ENDIF.
    ENDLOOP.

    WRITE: / 'Rows in the source table  :', lv_rows.
    WRITE: / 'Rows marking DISCOUNT     :', lv_marked.
    WRITE: / 'Columns written per row   : 1 (discount only)'.

*   The silent part: ONLY 'X' (type c) or hex 1 (type x) marks a field.
*   Any other value means "do not update" - no error, no warning.
    DATA lv_bad_flag TYPE abap_boolean.
    lv_bad_flag = 'x'.                     " lower case

    IF lv_bad_flag = abap_true.
      WRITE: / 'lower-case x would mark the field'.
    ELSE.
      WRITE: / |A flag of '{ lv_bad_flag }' is NOT 'X' -> that column | &&
               |is silently skipped|.
    ENDIF.

*   Other rules:
*     - INDICATORS NOT SET inverts: update all EXCEPT the marked ones.
*     - Key fields must be in the structure but indicators do not
*       affect them.
*     - BITFIELD (allowed for SELECT ... INDICATORS) is NOT allowed
*       for UPDATE.
*     - Set indicators enforce strict syntax-check mode from 7.81.

  ENDMETHOD.


  METHOD duplicate_key_outcomes.
*   TRAP 3 -------------------------------------------------------------
*   Three outcomes for a duplicate key in INSERT ... FROM TABLE, and
*   only one of them leaves you with usable information.

    separator( |3. INSERT ... FROM TABLE and duplicate keys| ).

    WRITE: / 'ACCEPTING DUPLICATE KEYS'.
    WRITE: /3 'insertable rows are inserted, duplicates discarded'.
    WRITE: /3 'sy-subrc = 4, sy-dbcnt = number actually inserted'.

    WRITE: / 'No addition, CX_SY_OPEN_SQL_DB CAUGHT'.
    WRITE: /3 'rows keep being inserted until the exception fires'.
    WRITE: /3 'number of inserted rows is UNDEFINED'.
    WRITE: /3 'sy-subrc and sy-dbcnt KEEP THEIR PREVIOUS VALUES'.

    WRITE: / 'No addition, exception NOT caught'.
    WRITE: /3 'runtime error -> database ROLLBACK of the whole LUW'.
    WRITE: /3 'including rows inserted before the duplicate'.

*   The safe form:
*
*     INSERT ztable FROM TABLE @lt_data ACCEPTING DUPLICATE KEYS.
*     IF sy-subrc = 4.
*       " some rows were skipped; sy-dbcnt says how many went in
*     ENDIF.
*
*   The form that needs an explicit rollback afterwards:
*
*     TRY.
*         INSERT ztable FROM TABLE @lt_data.
*       CATCH cx_sy_open_sql_db.
*         ROLLBACK WORK.   " doc: "a database rollback must be
*     ENDTRY.              "  initiated explicitly, if required"

    WRITE: / 'ACCEPTING DUPLICATE KEYS does NOT update existing rows -'.
    WRITE: / 'it only suppresses the exception. Upsert is MODIFY.'.

  ENDMETHOD.


  METHOD modify_platform_dependency.
*   TRAP 4 -------------------------------------------------------------
*   MODIFY ... FROM TABLE has TWO documented implementations and the
*   database decides which one runs.

    separator( |4. MODIFY ... FROM TABLE is platform-dependent| ).

    WRITE: / 'Implementation A: UPDATE FROM TABLE over all rows,'.
    WRITE: /3 'then INSERT FROM TABLE over all rows, duplicates ignored'.
    WRITE: / 'Implementation B: row-by-row MODIFY in a loop'.

    WRITE: / 'Doc: they can produce different results in cases where'.
    WRITE: / 'the DDIC database table has unique secondary indexes.'.

    WRITE: / 'Doc recommendation: apply MODIFY ... FROM itab only to'.
    WRITE: / 'tables WITHOUT unique secondary indexes. Otherwise code'.
    WRITE: / 'the behaviour explicitly with UPDATE + INSERT, or with'.
    WRITE: / 'LOOP AT itab + MODIFY.'.

*   So a table that behaves deterministically today stops doing so the
*   day someone adds a unique index - with no change to your code and
*   no syntax warning.

*   The name collision, same family of bug:
*     MODIFY dbtab FROM wa  and  MODIFY itab FROM wa  are identical
*     syntax. If an internal table shares its name with the database
*     table, the statement hits the INTERNAL TABLE. Never name an
*     internal table after the table it holds.

  ENDMETHOD.


  METHOD subrc_versus_dbcnt.
*   TRAP 5 -------------------------------------------------------------
*   After a FROM TABLE write, sy-subrc answers "was everything done?"
*   while sy-dbcnt answers "how much was done?". Only the second one
*   is actionable.

    separator( |5. sy-subrc = 4 does not mean nothing happened| ).

    WRITE: / 'Doc, UPDATE ... FROM TABLE:'.
    WRITE: /3 'If sy-subrc contains the value 4 ... this does not mean'.
    WRITE: /3 ' that no rows were changed. It simply means that not all'.
    WRITE: /3 ' of the rows in the internal table could be respected.'.

*   So this is wrong in both directions:
*
*     UPDATE ztable FROM TABLE @lt_data.
*     IF sy-subrc <> 0.
*       ROLLBACK WORK.   " throws away the rows that DID succeed,
*     ENDIF.             " plus everything else in this LUW
*
*   The completeness check that actually works:
*
*     UPDATE ztable FROM TABLE @lt_data.
*     IF sy-dbcnt <> lines( lt_data ).
*       " partial write - decide deliberately what to do
*     ENDIF.

    DATA lt_keys TYPE STANDARD TABLE OF scustom-id WITH EMPTY KEY.
    DATA lv_requested TYPE i.
    DATA lv_written   TYPE i.

    SELECT id
      FROM scustom
      UP TO 5 ROWS
      INTO TABLE @lt_keys.

    lv_requested = lines( lt_keys ).
    lv_written   = lv_requested - 2.       " as if two rows were skipped

    WRITE: / 'Rows handed to the statement :', lv_requested.
    WRITE: / 'Rows reported in sy-dbcnt    :', lv_written.

    IF lv_written <> lv_requested.
      DATA lv_missed TYPE i.
      lv_missed = lv_requested - lv_written.
      WRITE: / 'Incomplete write -', lv_missed, 'row(s) not applied.'.
    ENDIF.

*   The empty-table asymmetry: for all four statements, an EMPTY
*   internal table gives sy-subrc = 0 with sy-dbcnt = 0. Nothing was
*   written and the return code says success - the same shape as the
*   empty-driver trap in FOR ALL ENTRIES.
    DATA lt_empty TYPE STANDARD TABLE OF scustom WITH EMPTY KEY.

*   UPDATE scustom FROM TABLE @lt_empty.   " sy-subrc = 0, sy-dbcnt = 0

    WRITE: / 'Empty source table -> sy-subrc = 0, sy-dbcnt = 0.'.
    DATA lv_empty_lines TYPE i.
    lv_empty_lines = lines( lt_empty ).

    WRITE: / 'Guard on the line count, not on sy-subrc:', lv_empty_lines.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  WRITE: / 'ABAP SQL write access - four statements, four sets of traps'.
  WRITE: / 'Read-only: this report executes no write statement.'.

  lcl_write_demo=>whole_row_overwrite( ).
  lcl_write_demo=>set_indicator_layout( ).
  lcl_write_demo=>duplicate_key_outcomes( ).
  lcl_write_demo=>modify_platform_dependency( ).
  lcl_write_demo=>subrc_versus_dbcnt( ).
