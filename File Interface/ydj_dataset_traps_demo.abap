*&---------------------------------------------------------------------*
*& Report YDJ_DATASET_TRAPS_DEMO
*&---------------------------------------------------------------------*
*& ABAP file interface - the traps that do not announce themselves.
*&
*& Every case below either returns a wrong-but-plausible result or
*& reports success where there is none. None of them is a syntax error.
*&
*&   1. OPEN MISSING   -> OPEN DATASET does NOT raise for a missing file,
*&                        it sets sy-subrc = 8. Without MESSAGE you never
*&                        learn WHY (missing / no rights / disk full).
*&   2. FOR OUTPUT     -> an existing file is TRUNCATED on open. FOR
*&                        UPDATE, despite being a write mode, does not
*&                        create a missing file at all (sy-subrc = 8).
*&   3. BINARY subrc 4 -> in BINARY mode sy-subrc = 4 also means "read a
*&                        SHORT final chunk". The usual EXIT-on-nonzero
*&                        loop silently drops the last partial record.
*&                        ACTUAL LENGTH is filled either way.
*&   4. TEXT MODE      -> writing to a text file DELETES trailing blanks
*&                        of every non-string object, so fixed-width
*&                        column layouts collapse on the way out.
*&   5. BOM            -> without SKIPPING BYTE-ORDER MARK the three BOM
*&                        bytes are ordinary content, so only the FIRST
*&                        field of the FIRST record is corrupted.
*&   6. TRANSFER/CLOSE -> TRANSFER always sets sy-subrc = 0, and CLOSE
*&                        DATASET on an unopened file also returns 0.
*&                        Neither return code proves anything.
*&
*& Writes ONE work file on the application server and deletes it again
*& at the end (DELETE DATASET). No database access, no changes of any
*& kind. Adjust p_path to a directory you are allowed to write to.
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPOPEN_DATASET.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPOPEN_DATASET_ACCESS.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPOPEN_DATASET_ENCODING.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPOPEN_DATASET_ERROR_HANDLING.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPREAD_DATASET.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPTRANSFER.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCLOSE_DATASET.html
*&---------------------------------------------------------------------*
REPORT ydj_dataset_traps_demo.

PARAMETERS p_path TYPE localfile
           DEFAULT '/tmp/ydj_dataset_demo.dat' LOWER CASE.

CLASS lcl_dataset_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      missing_file_subrc
        IMPORTING iv_file TYPE string,
      output_truncates
        IMPORTING iv_file TYPE string,
      binary_short_chunk
        IMPORTING iv_file TYPE string,
      text_mode_blanks
        IMPORTING iv_file TYPE string,
      byte_order_mark
        IMPORTING iv_file TYPE string,
      useless_return_codes
        IMPORTING iv_file TYPE string,
      cleanup
        IMPORTING iv_file TYPE string.

  PRIVATE SECTION.

    " Renders a value with visible delimiters so trailing blanks and
    " stray BOM bytes can be seen in the list output.
    CLASS-METHODS show
      IMPORTING iv_label TYPE string
                iv_value TYPE string.

ENDCLASS.


CLASS lcl_dataset_demo IMPLEMENTATION.

  METHOD show.

    DATA lv_line TYPE string.

    lv_line = iv_label && ` [` && iv_value && `]`.
    WRITE: / lv_line.

  ENDMETHOD.


  METHOD missing_file_subrc.
*   --------------------------------------------------------------
*   1. A missing file is NOT an exception. sy-subrc = 8, and the
*      reason for the 8 is only available through MESSAGE - it goes
*      to the developer trace otherwise, and only at trace level 2+.
*   --------------------------------------------------------------
    DATA lv_msg  TYPE string.
    DATA lv_miss TYPE string.

    WRITE: / '--- 1. Missing file: sy-subrc = 8, no exception ---'.

    lv_miss = iv_file && `.does_not_exist`.

    OPEN DATASET lv_miss FOR INPUT IN TEXT MODE ENCODING UTF-8
         SKIPPING BYTE-ORDER MARK
         MESSAGE lv_msg.

    WRITE: / '  sy-subrc after OPEN     :', sy-subrc.
    show( iv_label = `  OS message via MESSAGE` iv_value = lv_msg ).

*   Reading it anyway is what actually dumps - CX_SY_FILE_OPEN_MODE,
*   runtime error DATASET_NOT_OPEN, far away from the real cause.
    IF sy-subrc = 0.
      CLOSE DATASET lv_miss.
    ELSE.
      WRITE: / '  A READ DATASET here would dump DATASET_NOT_OPEN.'.
    ENDIF.

  ENDMETHOD.


  METHOD output_truncates.
*   --------------------------------------------------------------
*   2. FOR OUTPUT deletes the content of an existing file. FOR
*      UPDATE is a write mode that does NOT create a missing file.
*   --------------------------------------------------------------
    DATA lv_msg     TYPE string.
    DATA lv_text    TYPE string.
    DATA lv_upd     TYPE string.
    DATA lv_written TYPE i VALUE 4.

    WRITE: / '--- 2. FOR OUTPUT truncates, FOR UPDATE does not create ---'.

    OPEN DATASET iv_file FOR OUTPUT IN TEXT MODE ENCODING UTF-8
         MESSAGE lv_msg.
    IF sy-subrc <> 0.
      show( iv_label = `  cannot write, aborting section` iv_value = lv_msg ).
      RETURN.
    ENDIF.
    TRANSFER 'FIRST RUN - THREE RECORDS' TO iv_file.
    TRANSFER 'SECOND RECORD'             TO iv_file.
    TRANSFER 'THIRD RECORD'              TO iv_file.
    CLOSE DATASET iv_file.

*   Reopening FOR OUTPUT wipes all three records before writing.
    OPEN DATASET iv_file FOR OUTPUT IN TEXT MODE ENCODING UTF-8.
    TRANSFER 'SECOND RUN - ONE RECORD' TO iv_file.
    CLOSE DATASET iv_file.

    OPEN DATASET iv_file FOR INPUT IN TEXT MODE ENCODING UTF-8
         SKIPPING BYTE-ORDER MARK.
    DATA(lv_count) = 0.
    DO.
      READ DATASET iv_file INTO lv_text.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      lv_count = lv_count + 1.
    ENDDO.
    CLOSE DATASET iv_file.

    WRITE: / '  records written in total :', lv_written,
           / '  records still in file    :', lv_count.

*   FOR UPDATE on a file that does not exist: sy-subrc = 8 and no
*   file is created, unlike FOR OUTPUT and FOR APPENDING.
    lv_upd = iv_file && `.update_target`.
    OPEN DATASET lv_upd FOR UPDATE IN BINARY MODE MESSAGE lv_msg.
    WRITE: / '  FOR UPDATE on missing file, sy-subrc :', sy-subrc.
    IF sy-subrc = 0.
      CLOSE DATASET lv_upd.
      DELETE DATASET lv_upd.
    ENDIF.

  ENDMETHOD.


  METHOD binary_short_chunk.
*   --------------------------------------------------------------
*   3. BINARY mode: sy-subrc = 4 also means "short final chunk".
*      10 bytes read 4 at a time gives 4 / 4 / 2, and the 2 arrives
*      WITH sy-subrc = 4. Exiting on sy-subrc alone loses it.
*   --------------------------------------------------------------
    DATA lv_out   TYPE x LENGTH 10 VALUE 'A1A2A3A4B1B2B3B4C1C2'.
    DATA lv_chunk TYPE x LENGTH 4.
    DATA lv_max   TYPE i VALUE 4.
    DATA lv_total TYPE i VALUE 10.
    DATA lv_msg   TYPE string.

    WRITE: / '--- 3. Binary sy-subrc = 4 with data attached ---'.

    OPEN DATASET iv_file FOR OUTPUT IN BINARY MODE MESSAGE lv_msg.
    IF sy-subrc <> 0.
      show( iv_label = `  cannot write, aborting section` iv_value = lv_msg ).
      RETURN.
    ENDIF.
    TRANSFER lv_out TO iv_file.
    CLOSE DATASET iv_file.

    OPEN DATASET iv_file FOR INPUT IN BINARY MODE.

    DATA(lv_naive) = 0.
    DATA(lv_safe)  = 0.

    DO.
      READ DATASET iv_file INTO lv_chunk
           MAXIMUM LENGTH lv_max
           ACTUAL  LENGTH DATA(lv_read).

*     The correct guard: bytes were delivered, whatever sy-subrc says.
      IF lv_read > 0.
        lv_safe = lv_safe + lv_read.
      ENDIF.

*     The usual loop: exit first, so the short chunk is discarded.
      IF sy-subrc <> 0.
        WRITE: / '  final pass sy-subrc   :', sy-subrc,
               / '  final pass ACTUAL LEN :', lv_read.
        EXIT.
      ENDIF.

      lv_naive = lv_naive + lv_read.
    ENDDO.

    CLOSE DATASET iv_file.

    WRITE: / '  bytes written          :', lv_total,
           / '  bytes kept, naive loop :', lv_naive,
           / '  bytes kept, ACTUAL LEN :', lv_safe.

  ENDMETHOD.


  METHOD text_mode_blanks.
*   --------------------------------------------------------------
*   4. Writing to a TEXT file deletes trailing blanks of every
*      object except type string. Fixed-width layouts collapse.
*      TRANSFER ... LENGTH len pads back up to len.
*   --------------------------------------------------------------
    DATA lv_name TYPE c LENGTH 20.
    DATA lv_city TYPE c LENGTH 20.
    DATA lv_line TYPE string.
    DATA lv_msg  TYPE string.

    WRITE: / '--- 4. Text mode strips trailing blanks ---'.

    lv_name = 'MILLER'.
    lv_city = 'WALLDORF'.

    OPEN DATASET iv_file FOR OUTPUT IN TEXT MODE ENCODING UTF-8
         MESSAGE lv_msg.
    IF sy-subrc <> 0.
      show( iv_label = `  cannot write, aborting section` iv_value = lv_msg ).
      RETURN.
    ENDIF.

*   Intended as two 20-character columns.
    TRANSFER lv_name TO iv_file NO END OF LINE.
    TRANSFER lv_city TO iv_file.

*   Same two columns, padding preserved by LENGTH.
    TRANSFER lv_name TO iv_file LENGTH 20 NO END OF LINE.
    TRANSFER lv_city TO iv_file LENGTH 20.

    CLOSE DATASET iv_file.

    OPEN DATASET iv_file FOR INPUT IN TEXT MODE ENCODING UTF-8
         SKIPPING BYTE-ORDER MARK.

*   Functional calls are not allowed inside a WRITE list, so every
*   find( ) is hoisted into a variable first.
    READ DATASET iv_file INTO lv_line.
    show( iv_label = `  plain TRANSFER ` iv_value = lv_line ).
    DATA(lv_off_plain) = find( val = lv_line sub = 'WALLDORF' ).
    WRITE: / '  city starts at offset :', lv_off_plain.

    READ DATASET iv_file INTO lv_line.
    show( iv_label = `  LENGTH 20      ` iv_value = lv_line ).
    DATA(lv_off_fixed) = find( val = lv_line sub = 'WALLDORF' ).
    WRITE: / '  city starts at offset :', lv_off_fixed.

    CLOSE DATASET iv_file.

  ENDMETHOD.


  METHOD byte_order_mark.
*   --------------------------------------------------------------
*   5. The BOM is ordinary file content unless SKIPPING BYTE-ORDER
*      MARK is given. Only the FIRST field of the FIRST record is
*      affected, which is why this is diagnosed as a data problem.
*   --------------------------------------------------------------
    DATA lv_raw  TYPE xstring.
    DATA lv_line TYPE string.
    DATA lv_msg  TYPE string.

    WRITE: / '--- 5. Byte order mark is content by default ---'.

    OPEN DATASET iv_file FOR OUTPUT IN TEXT MODE ENCODING UTF-8
         WITH BYTE-ORDER MARK
         MESSAGE lv_msg.
    IF sy-subrc <> 0.
      show( iv_label = `  cannot write, aborting section` iv_value = lv_msg ).
      RETURN.
    ENDIF.
    TRANSFER '0000001234' TO iv_file.
    TRANSFER '0000005678' TO iv_file.
    CLOSE DATASET iv_file.

*   The raw bytes: EFBBBF followed by the UTF-8 payload.
    OPEN DATASET iv_file FOR INPUT IN BINARY MODE.
    READ DATASET iv_file INTO lv_raw.
    CLOSE DATASET iv_file.

    DATA(lv_bom) = lv_raw(3).
    WRITE: / '  first three bytes of file :', lv_bom.

*   Without SKIPPING: record 1 carries the BOM, record 2 is clean.
    OPEN DATASET iv_file FOR INPUT IN TEXT MODE ENCODING UTF-8.
    READ DATASET iv_file INTO lv_line.
    CLOSE DATASET iv_file.

    DATA(lv_len_bad) = strlen( lv_line ).
    DATA(lv_numeric) = boolc( lv_line CO '0123456789' ).
    WRITE: / '  no SKIPPING, strlen      :', lv_len_bad,
           / '  no SKIPPING, CO digits   :', lv_numeric.

*   With SKIPPING: the file pointer is set after the BOM.
    OPEN DATASET iv_file FOR INPUT IN TEXT MODE ENCODING UTF-8
         SKIPPING BYTE-ORDER MARK.
    READ DATASET iv_file INTO lv_line.
    CLOSE DATASET iv_file.

    DATA(lv_len_good) = strlen( lv_line ).
    lv_numeric = boolc( lv_line CO '0123456789' ).
    WRITE: / '  SKIPPING,    strlen      :', lv_len_good,
           / '  SKIPPING,    CO digits   :', lv_numeric.

  ENDMETHOD.


  METHOD useless_return_codes.
*   --------------------------------------------------------------
*   6. TRANSFER always sets sy-subrc = 0 or raises an exception,
*      and CLOSE DATASET on a file that is not open also returns 0.
*      Checking either one is decoration; TRY/CATCH is the real
*      error handling.
*   --------------------------------------------------------------
    DATA lv_msg  TYPE string.
    DATA lv_dead TYPE string.

    WRITE: / '--- 6. Return codes that cannot fail ---'.

    OPEN DATASET iv_file FOR OUTPUT IN TEXT MODE ENCODING UTF-8
         MESSAGE lv_msg.
    IF sy-subrc <> 0.
      show( iv_label = `  cannot write, aborting section` iv_value = lv_msg ).
      RETURN.
    ENDIF.

    TRY.
        TRANSFER 'payload' TO iv_file.
        WRITE: / '  sy-subrc after TRANSFER   :', sy-subrc,
               / '    (always 0 - only the exception is informative)'.
      CATCH cx_sy_file_io INTO DATA(lx_io).
        DATA(lv_err) = lx_io->get_text( ).
        show( iv_label = `  write failed` iv_value = lv_err ).
    ENDTRY.

    CLOSE DATASET iv_file.

*   Closing a file that was never opened: still 0.
    lv_dead = iv_file && `.never_opened`.
    CLOSE DATASET lv_dead.
    WRITE: / '  CLOSE on unopened file    :', sy-subrc.

  ENDMETHOD.


  METHOD cleanup.
*   Remove the work file. DELETE DATASET returns 4 if it could not
*   be deleted - this one IS worth checking.
    DELETE DATASET iv_file.
    WRITE: / '--- cleanup: DELETE DATASET sy-subrc :', sy-subrc.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  DATA(gv_file) = CONV string( p_path ).

  lcl_dataset_demo=>missing_file_subrc(   gv_file ).
  lcl_dataset_demo=>output_truncates(     gv_file ).
  lcl_dataset_demo=>binary_short_chunk(   gv_file ).
  lcl_dataset_demo=>text_mode_blanks(     gv_file ).
  lcl_dataset_demo=>byte_order_mark(      gv_file ).
  lcl_dataset_demo=>useless_return_codes( gv_file ).
  lcl_dataset_demo=>cleanup(              gv_file ).
