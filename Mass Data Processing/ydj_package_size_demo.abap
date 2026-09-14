*&---------------------------------------------------------------------*
*& Report YDJ_PACKAGE_SIZE_DEMO
*&---------------------------------------------------------------------*
*& Mass data processing: PACKAGE SIZE and OPEN CURSOR semantics, shown
*& against the standard flight data model (SPFLI / SFLIGHT).
*&
*&   1. INTO TABLE ... PACKAGE SIZE  -> target is CLEARED each pass.
*&      This is the only form that caps memory.
*&   2. APPENDING TABLE ... PACKAGE SIZE -> target GROWS every pass, so
*&      it gives package-sized loop passes but NO memory protection.
*&   3. OPEN CURSOR / FETCH -> sy-dbcnt is CUMULATIVE, not the package
*&      size; sy-subrc = 4 ends the loop; CLOSE CURSOR explicitly.
*&   4. The safe commit pattern: read keys, close the read, THEN chunk
*&      and COMMIT WORK. A commit inside 1-3 kills the cursor with
*&      DBSQL_INVALID_CURSOR.
*&
*& Nothing here writes to the database. The COMMIT WORK in the safe
*& pattern is deliberately left as a comment so the demo is read-only.
*&
*& Run on any system with the SFLIGHT demo data (SAPBC_DATA_GENERATOR
*& if the tables are empty).
*&---------------------------------------------------------------------*
REPORT ydj_package_size_demo.

CONSTANTS gc_pkg TYPE i VALUE 10.

CLASS lcl_mass_demo DEFINITION.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_flight,
             carrid   TYPE spfli-carrid,
             connid   TYPE spfli-connid,
             cityfrom TYPE spfli-cityfrom,
             cityto   TYPE spfli-cityto,
           END OF ty_flight,
           ty_flights TYPE STANDARD TABLE OF ty_flight WITH EMPTY KEY.

    TYPES: BEGIN OF ty_key,
             carrid TYPE spfli-carrid,
             connid TYPE spfli-connid,
           END OF ty_key,
           ty_keys TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.

    CLASS-METHODS:
      "! INTO form: target holds only the CURRENT package.
      packaged_into,
      "! APPENDING form: target accumulates. Not a memory guard.
      packaged_appending,
      "! OPEN CURSOR / FETCH: cumulative sy-dbcnt, explicit CLOSE.
      cursor_fetch,
      "! Keys first, then chunk - the only shape that may COMMIT WORK.
      safe_commit_pattern.

ENDCLASS.


CLASS lcl_mass_demo IMPLEMENTATION.

  METHOD packaged_into.

    DATA lv_pass TYPE i.

    WRITE: / '--- 1. INTO TABLE ... PACKAGE SIZE (target cleared each pass) ---'.

    SELECT carrid, connid, cityfrom, cityto
      FROM spfli
      ORDER BY carrid, connid
      INTO TABLE @DATA(lt_pkg) PACKAGE SIZE @gc_pkg.

      lv_pass = lv_pass + 1.

      " lines( lt_pkg ) never exceeds gc_pkg: the table was initialized
      " before this package was inserted.
      WRITE: / '  pass', lv_pass,
               'lines in target:', lines( lt_pkg ),
               'sy-dbcnt (cumulative):', sy-dbcnt.

    ENDSELECT.

    " Deliberately NOT reading lt_pkg here. After ENDSELECT the content of
    " an INTO target is undefined - it may hold the last package or be
    " initial. Relying on it is a bug that happens to work on some DBs.
    WRITE: / '  ->', lv_pass, 'passes. Target undefined after ENDSELECT.'.

  ENDMETHOD.


  METHOD packaged_appending.

    DATA lv_pass TYPE i.

    WRITE: / '--- 2. APPENDING TABLE ... PACKAGE SIZE (target grows) ---'.

    DATA lt_all TYPE ty_flights.

    SELECT carrid, connid, cityfrom, cityto
      FROM spfli
      ORDER BY carrid, connid
      APPENDING TABLE @lt_all PACKAGE SIZE @gc_pkg.

      lv_pass = lv_pass + 1.

      " lines( lt_all ) climbs by gc_pkg every pass. If the result set is
      " too large for memory this still ends in TSV_TNEW_PAGE_ALLOC_FAILED
      " - PACKAGE SIZE cannot prevent it after APPENDING.
      WRITE: / '  pass', lv_pass,
               'lines in target:', lines( lt_all ),
               'sy-dbcnt (cumulative):', sy-dbcnt.

    ENDSELECT.

    " Unlike INTO, the APPENDING target IS defined after ENDSELECT: it
    " retains the state of the last loop pass.
    WRITE: / '  -> total rows retained after ENDSELECT:', lines( lt_all ).

  ENDMETHOD.


  METHOD cursor_fetch.

    DATA lt_pkg  TYPE ty_flights.
    DATA lv_pass TYPE i.

    WRITE: / '--- 3. OPEN CURSOR / FETCH ---'.

    OPEN CURSOR @DATA(lv_cursor) FOR
      SELECT carrid, connid, cityfrom, cityto
        FROM spfli
        ORDER BY carrid, connid.

    " No commit may occur between here and CLOSE CURSOR - including any
    " MESSAGE of type E/I/W, any WAIT, any RFC and any HTTP call. Note a
    " commit BEFORE the first FETCH would still be harmless.
    DO.

      FETCH NEXT CURSOR @lv_cursor
        INTO TABLE @lt_pkg PACKAGE SIZE @gc_pkg.

      IF sy-subrc <> 0.
        " 4 = no row extracted. INTO/APPENDING targets are untouched.
        EXIT.
      ENDIF.

      lv_pass = lv_pass + 1.

      WRITE: / '  fetch', lv_pass,
               'rows this package:', lines( lt_pkg ),
               'sy-dbcnt (cumulative):', sy-dbcnt.

    ENDDO.

    " Whether the DB closes the cursor itself after the last row is
    " database-dependent, so close it explicitly, always.
    CLOSE CURSOR @lv_cursor.

    WRITE: / '  -> cursor closed after', lv_pass, 'fetches.'.

  ENDMETHOD.


  METHOD safe_commit_pattern.

    CONSTANTS lc_chunk TYPE i VALUE 20.

    WRITE: / '--- 4. Keys first, then chunk (commit-safe) ---'.

    " Phase 1: one bounded read. The cursor is closed when it completes,
    " so nothing is held open across the processing below.
    DATA lt_keys TYPE ty_keys.

    SELECT carrid, connid
      FROM spfli
      ORDER BY carrid, connid
      INTO TABLE @lt_keys.

    IF lt_keys IS INITIAL.
      WRITE: / '  no keys - nothing to do.'.
      RETURN.
    ENDIF.

    DATA(lv_idx) = 1.

    WHILE lv_idx <= lines( lt_keys ).

      DATA(lv_last) = nmin( val1 = lv_idx + lc_chunk - 1
                            val2 = lines( lt_keys ) ).

      DATA(lt_chunk) = VALUE ty_keys(
        FOR i = lv_idx WHILE i <= lv_last ( lt_keys[ i ] ) ).

      " The FOR ALL ENTRIES guard still applies - an empty chunk would
      " drop the ENTIRE WHERE. It cannot be empty here, but the check
      " belongs with the statement, not with the caller's assumptions.
      IF lt_chunk IS NOT INITIAL.

        SELECT carrid, connid, fldate, seatsocc
          FROM sflight
          FOR ALL ENTRIES IN @lt_chunk
          WHERE carrid = @lt_chunk-carrid
            AND connid = @lt_chunk-connid
          INTO TABLE @DATA(lt_data).

        WRITE: / '  chunk', lv_idx, '-', lv_last,
                 'flights read:', lines( lt_data ).

        " ... process and update here ...
        " COMMIT WORK.   <- safe at this point: no cursor is open.
        "                   Inside methods 1-3 this same statement would
        "                   dump the next pass with DBSQL_INVALID_CURSOR.

      ENDIF.

      lv_idx = lv_last + 1.

    ENDWHILE.

    WRITE: / '  ->', lines( lt_keys ), 'keys processed in chunks of', lc_chunk.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_mass_demo=>packaged_into( ).
  SKIP.
  lcl_mass_demo=>packaged_appending( ).
  SKIP.
  lcl_mass_demo=>cursor_fetch( ).
  SKIP.
  lcl_mass_demo=>safe_commit_pattern( ).
