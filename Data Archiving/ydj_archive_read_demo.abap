*&---------------------------------------------------------------------*
*& Report YDJ_ARCHIVE_READ_DEMO
*&---------------------------------------------------------------------*
*& A read-only ADK read program. It opens an existing archiving object
*& for reading and walks every data object in the selected archive
*& files. Nothing is written, nothing is deleted, there is no
*& COMMIT WORK and no write-side ADK module is called.
*&
*& WHY THERE IS NO WRITE OR delete DEMO HERE: a correct delete program
*& removes production rows, and ADK is explicit that the write program
*& must not delete anything itself. Shipping either as runnable code in
*& a cheat-sheet repo would be irresponsible. The verified call
*& sequence for both is in README.md instead.
*&
*& WHAT IT DEMONSTRATES
*&
*&   1. TWO LOOPS, TWO EXCEPTIONS -> the outer loop ends on
*&                     END_OF_FILE (ARCHIVE_GET_NEXT_OBJECT), the
*&                     inner one on END_OF_OBJECT
*&                     (ARCHIVE_GET_NEXT_RECORD). Both are exception
*&                     number 1 in the usual copy-paste, and swapping
*&                     them gives either one data object or an endless
*&                     loop. Each is named and handled separately
*&                     below so the difference is visible.
*&   2. ONE HANDLE, MANY FILES -> END_OF_FILE does not fire per file.
*&                     ARCHIVE_GET_NEXT_OBJECT reads "all archived
*&                     data objects from all opened archive files",
*&                     so it fires once, at the end of the whole set.
*&                     The report counts files seen via ARCHIVE_NAME
*&                     to make that concrete.
*&   3. TYPED VS GENERIC -> P_BYREC off uses ARCHIVE_GET_TABLE, which
*&                     takes the structure name as input and returns a
*&                     properly typed internal table. P_BYREC on uses
*&                     ARCHIVE_GET_NEXT_RECORD, where the structure
*&                     name is OUTPUT and you must CASE on it. The
*&                     data arrives through RECORD_REF and a typed
*&                     field symbol, which is the Unicode-safe route;
*&                     the old generic CHAR buffer is not valid for
*&                     structures with non-character-like fields.
*&   4. EXCEPTION MAPPED TO ZERO -> for ARCHIVE_GET_TABLE,
*&                     END_OF_OBJECT only means "this data object has
*&                     no rows of that structure", which is normal.
*&                     SAP's own samples map it to 0. Here it is
*&                     mapped to 1 and handled explicitly, so the
*&                     count of objects without SBOOK rows is visible
*&                     rather than silently swallowed.
*&
*& PREREQUISITE: at least one completed archiving session for the
*& archiving object in P_OBJ. BC_SBOOK is SAP's own demo object over
*& the flight-booking tables. With no archive files present,
*& ARCHIVE_OPEN_FOR_READ raises NO_FILES_AVAILABLE (sy-subrc = 4) and
*& the report says so and stops.
*&
*& NOTE ON THE POPUP: ARCHIVE_OPEN_FOR_READ is called without the
*& optional ARCHIVE_FILES / SELECTED_FILES tables, so in dialog mode
*& ADK puts up its own archive-file selection screen. That is the
*& documented behaviour, not a bug in this report.
*&---------------------------------------------------------------------*
REPORT ydj_archive_read_demo.

PARAMETERS:
  p_obj   TYPE arch_obj-object DEFAULT 'BC_SBOOK' OBLIGATORY,
  p_max   TYPE i              DEFAULT 20,
  p_byrec AS CHECKBOX         DEFAULT space,
  p_show  AS CHECKBOX         DEFAULT 'X'.

*&---------------------------------------------------------------------*
CLASS lcl_reader DEFINITION.

  PUBLIC SECTION.
    METHODS run.

  PRIVATE SECTION.
    DATA mv_handle    TYPE sy-tabix.
    DATA mv_objects   TYPE i.
    DATA mv_records   TYPE i.
    DATA mv_empty     TYPE i.
    DATA mv_last_file TYPE heada-arkey.
    DATA mv_files     TYPE i.

    METHODS open
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    METHODS note_file
      IMPORTING iv_file TYPE heada-arkey.

    METHODS read_by_table
      IMPORTING iv_object_id TYPE clike.

    METHODS read_by_record
      IMPORTING iv_object_id TYPE clike.

    METHODS close.

    METHODS summary.

ENDCLASS.

*&---------------------------------------------------------------------*
CLASS lcl_reader IMPLEMENTATION.

  METHOD run.

    DATA lv_object_id TYPE arch_idx-object_id.
    DATA lv_file      TYPE heada-arkey.
    DATA lv_ok        TYPE abap_bool.

    lv_ok = open( ).
    IF lv_ok = abap_false.
      RETURN.
    ENDIF.

*   OUTER LOOP - one pass per data object, across ALL open files.
*   Terminates on END_OF_FILE, which fires once for the whole set.
    DO.

      CLEAR lv_object_id.
      CLEAR lv_file.

      CALL FUNCTION 'ARCHIVE_GET_NEXT_OBJECT'
        EXPORTING
          archive_handle          = mv_handle
        IMPORTING
          object_id               = lv_object_id
          archive_name            = lv_file
        EXCEPTIONS
          end_of_file             = 1
          file_io_error           = 2
          internal_error          = 3
          open_error              = 4
          wrong_access_to_archive = 5
          OTHERS                  = 6.

      IF sy-subrc = 1.
*       Not "end of one file" - end of every file on this handle.
        EXIT.
      ELSEIF sy-subrc <> 0.
        WRITE: / 'ARCHIVE_GET_NEXT_OBJECT failed, sy-subrc =', sy-subrc.
        EXIT.
      ENDIF.

      note_file( lv_file ).
      mv_objects = mv_objects + 1.

      IF p_byrec = abap_true.
        read_by_record( lv_object_id ).
      ELSE.
        read_by_table( lv_object_id ).
      ENDIF.

      IF mv_objects >= p_max.
        WRITE: / 'Stopped at P_MAX =', p_max,
                 '- the archive may hold more data objects.'.
        EXIT.
      ENDIF.

    ENDDO.

    close( ).
    summary( ).

  ENDMETHOD.

  METHOD open.

    rv_ok = abap_false.

*   No ARCHIVE_FILES / SELECTED_FILES passed on purpose: in dialog mode
*   ADK then shows its own archive-file selection screen.
    CALL FUNCTION 'ARCHIVE_OPEN_FOR_READ'
      EXPORTING
        object                       = p_obj
      IMPORTING
        archive_handle               = mv_handle
      EXCEPTIONS
        file_already_open            = 1
        file_io_error                = 2
        internal_error               = 3
        no_files_available           = 4
        object_not_found             = 5
        open_error                   = 6
        not_authorized               = 7
        archiving_standard_violation = 8
        OTHERS                       = 9.

    CASE sy-subrc.
      WHEN 0.
        rv_ok = abap_true.
        WRITE: / 'Archiving object', p_obj,
                 'opened for reading, handle', mv_handle.
        SKIP.
      WHEN 4.
        WRITE: / 'No archive files exist for archiving object', p_obj,
                 '- run a write session first.'.
      WHEN 5.
        WRITE: / 'Archiving object', p_obj,
                 'is not defined - check transaction AOBJ.'.
      WHEN 7.
        WRITE: / 'Not authorized to read archiving object', p_obj.
      WHEN OTHERS.
        WRITE: / 'ARCHIVE_OPEN_FOR_READ failed, sy-subrc =', sy-subrc.
    ENDCASE.

  ENDMETHOD.

  METHOD note_file.

    IF iv_file IS INITIAL.
      RETURN.
    ENDIF.

    IF iv_file <> mv_last_file.
      mv_files     = mv_files + 1.
      mv_last_file = iv_file.
      IF p_show = abap_true.
        WRITE: / 'archive file:', iv_file.
      ENDIF.
    ENDIF.

  ENDMETHOD.

  METHOD read_by_table.

*   TYPED ROUTE. The structure name is an INPUT, so the target table is
*   declared with its real type and no CASE is needed.
    DATA lt_sbook TYPE STANDARD TABLE OF sbook.
    DATA lv_rows  TYPE i.

    CALL FUNCTION 'ARCHIVE_GET_TABLE'
      EXPORTING
        archive_handle          = mv_handle
        record_structure        = 'SBOOK'
        all_records_of_object   = abap_true
      TABLES
        table                   = lt_sbook
      EXCEPTIONS
        end_of_object           = 1
        internal_error          = 2
        wrong_access_to_archive = 3
        OTHERS                  = 4.

    IF sy-subrc = 1.
*     Normal, not an error: this data object carries no SBOOK rows.
*     SAP's own samples map this exception to 0 and never see it.
      mv_empty = mv_empty + 1.
      RETURN.
    ELSEIF sy-subrc <> 0.
      WRITE: / 'ARCHIVE_GET_TABLE failed, sy-subrc =', sy-subrc.
      RETURN.
    ENDIF.

    lv_rows    = lines( lt_sbook ).
    mv_records = mv_records + lv_rows.

    IF p_show = abap_true.
      WRITE: /4 'object', iv_object_id, 'SBOOK rows:', lv_rows.
    ENDIF.

  ENDMETHOD.

  METHOD read_by_record.

*   GENERIC ROUTE. The structure name is an OUTPUT, so dispatch is a
*   CASE over DDIC names and anything new added to the archiving
*   object lands in WHEN OTHERS with no syntax error and no exception.
    DATA lv_structure TYPE arc_buffer-rname.
*   RECORD_REF is documented as "the reference returned" for
*   Unicode-safe reading, so it is received into a data reference.
*   If your system's SE37 signature for this parameter differs, the
*   documented alternative is the untyped field symbol route - SAP
*   sample SBOOKR_2 - rather than the old CHAR buffer.
    DATA lr_record    TYPE REF TO data.
    DATA lv_rows      TYPE i.

    FIELD-SYMBOLS <ls_sbook> TYPE sbook.

*   INNER LOOP - one pass per record of the CURRENT data object.
*   Terminates on END_OF_OBJECT, not END_OF_FILE.
    DO.

      CLEAR lv_structure.
      CLEAR lr_record.

      CALL FUNCTION 'ARCHIVE_GET_NEXT_RECORD'
        EXPORTING
          archive_handle          = mv_handle
        IMPORTING
          record_structure        = lv_structure
          record_ref              = lr_record
        EXCEPTIONS
          end_of_object           = 1
          internal_error          = 2
          wrong_access_to_archive = 3
          OTHERS                  = 4.

      IF sy-subrc = 1.
*       End of THIS data object only. The outer loop continues.
        EXIT.
      ELSEIF sy-subrc <> 0.
        WRITE: / 'ARCHIVE_GET_NEXT_RECORD failed, sy-subrc =', sy-subrc.
        EXIT.
      ENDIF.

      mv_records = mv_records + 1.
      lv_rows    = lv_rows + 1.

      CASE lv_structure.

        WHEN 'SBOOK'.
*         Unicode-safe: dereference RECORD_REF into a TYPED field
*         symbol. The CASE above is what makes this assignment safe;
*         assigning a reference of another structure to <ls_sbook>
*         would raise.
          UNASSIGN <ls_sbook>.
          IF lr_record IS BOUND.
            ASSIGN lr_record->* TO <ls_sbook>.
          ENDIF.

          IF <ls_sbook> IS ASSIGNED AND p_show = abap_true.
            WRITE: /6 iv_object_id,
                      <ls_sbook>-carrid,
                      <ls_sbook>-connid,
                      <ls_sbook>-bookid,
                      <ls_sbook>-fldate.
          ENDIF.

        WHEN OTHERS.
*         A table added to the archiving object after this program was
*         written arrives here. Silently, in most real read programs.
          IF p_show = abap_true.
            WRITE: /6 iv_object_id,
                      'unhandled structure:', lv_structure.
          ENDIF.

      ENDCASE.

    ENDDO.

    IF lv_rows = 0.
      mv_empty = mv_empty + 1.
    ENDIF.

  ENDMETHOD.

  METHOD close.

*   On the READ side the close only releases the handle. On the WRITE
*   side skipping it loses the last physical archive file - see
*   README.md section 6.
    CALL FUNCTION 'ARCHIVE_CLOSE_FILE'
      EXPORTING
        archive_handle               = mv_handle
      EXCEPTIONS
        internal_error               = 1
        wrong_access_to_archive      = 2
        archiving_standard_violation = 3
        OTHERS                       = 4.

    IF sy-subrc <> 0.
      WRITE: / 'ARCHIVE_CLOSE_FILE failed, sy-subrc =', sy-subrc.
    ENDIF.

  ENDMETHOD.

  METHOD summary.

    DATA lv_mode TYPE string.

    IF p_byrec = abap_true.
      lv_mode = 'ARCHIVE_GET_NEXT_RECORD (generic, RECORD_REF)'.
    ELSE.
      lv_mode = 'ARCHIVE_GET_TABLE (typed)'.
    ENDIF.

    SKIP.
    ULINE.
    WRITE: / 'read mode          :', lv_mode.
    WRITE: / 'archive files seen :', mv_files.
    WRITE: / 'data objects read  :', mv_objects.
    WRITE: / 'records read       :', mv_records.
    WRITE: / 'objects w/o SBOOK  :', mv_empty.
    ULINE.
    WRITE: / 'One END_OF_FILE ended the outer loop for all',
             mv_files, 'file(s) - not one per file.'.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
START-OF-SELECTION.

  DATA(go_reader) = NEW lcl_reader( ).
  go_reader->run( ).
