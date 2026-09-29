*&---------------------------------------------------------------------*
*& Report  YDJ_LANGU_VERSION_DEMO
*&---------------------------------------------------------------------*
*& ABAP Language Versions - inspecting the property that decides your
*& syntax scope, and the migration pairs that are safe to fix TODAY.
*&
*& The ABAP language version is metadata on the repository object, not
*& something written in the source. For programs it is stored in the
*& UCCHECK column of table TRDIR:
*&
*&     'X' = Standard ABAP               (unrestricted)
*&     '5' = ABAP for Cloud Development  (restricted)
*&     '2' = ABAP for Key Users          (restricted)
*&
*& A version ID that is NOT one of these is NOT treated as Standard
*& ABAP - the doc says it "is handled in the same way as a version that
*& does not support any language elements", i.e. maximally restrictive.
*&
*& NOTE THE IRONY, IT IS THE POINT OF THIS FOLDER: this program is
*& itself invalid in ABAP for Cloud Development. REPORT,
*& START-OF-SELECTION and WRITE are all banned there. The logic below
*& is fine; the classical report skeleton is what is gone. In ABAP
*& Cloud "most developments can be implemented in methods only".
*&
*& Read-only. Selects from TRDIR only. No COMMIT, no modification.
*&
*& Docs (help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/):
*&   ABENABAP_VERSIONS.html            - version IDs, TRDIR-UCCHECK
*&   ABENRESTRICTED_ABAP_ELEMENTS.html - the per-element whitelist
*&   ABENABAP_LANGUAGE_VERSIONS.html   - versions and API access
*&---------------------------------------------------------------------*
REPORT ydj_langu_version_demo.

CLASS lcl_demo DEFINITION FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS run.

  PRIVATE SECTION.
    " Kept as a method each so every block can be read on its own.
    CLASS-METHODS show_version_of_this_program.
    CLASS-METHODS show_version_distribution.
    CLASS-METHODS show_safe_migration_pairs.
    CLASS-METHODS decode_version
      IMPORTING iv_uccheck     TYPE c
      RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.


CLASS lcl_demo IMPLEMENTATION.

  METHOD run.
    show_version_of_this_program( ).
    show_version_distribution( ).
    show_safe_migration_pairs( ).
  ENDMETHOD.


  METHOD decode_version.
    " The three documented IDs. Anything else is deliberately NOT
    " reported as "Standard ABAP" - see the header comment.
    rv_text = SWITCH string( iv_uccheck
                WHEN 'X' THEN `Standard ABAP (unrestricted)`
                WHEN '5' THEN `ABAP for Cloud Development (restricted)`
                WHEN '2' THEN `ABAP for Key Users (restricted)`
                ELSE          `unlisted ID -> treated as supporting NO elements` ).
  ENDMETHOD.


  METHOD show_version_of_this_program.

    WRITE: / '--- 1. The language version of THIS program ---'.
    SKIP.

    " sy-repid is the current program. Both sy-repid and sy-cprog are
    " themselves allowed in the restricted versions; it is the WRITE
    " below that would be rejected, not the field access.
    SELECT SINGLE uccheck
      FROM trdir
      WHERE name = @sy-repid
      INTO @DATA(lv_uccheck).

    IF sy-subrc <> 0.
      " Not activated yet / not in TRDIR. Not an error worth a message.
      WRITE: / '  Program not found in TRDIR (not activated?).'.
      SKIP.
      RETURN.
    ENDIF.

    DATA(lv_meaning) = decode_version( lv_uccheck ).

    WRITE: / '  Program        :', sy-repid.
    WRITE: / '  TRDIR-UCCHECK  :', lv_uccheck.
    WRITE: / '  Language version:', lv_meaning.
    SKIP.
    WRITE: / '  Nothing in the source above set this. It is derived from'.
    WRITE: / '  the package / software component. Move the code to a'.
    WRITE: / '  differently-classified package and the syntax scope'.
    WRITE: / '  changes without the code changing.'.
    SKIP.

  ENDMETHOD.


  METHOD show_version_distribution.

    WRITE: / '--- 2. How the programs in THIS system are classified ---'.
    SKIP.

    " Aggregate, so one row per distinct version ID actually present.
    " COUNT( * ) is selected alongside deliberately: a list of only
    " aggregates with no GROUP BY would return a row even with no data
    " (see the repo's Null Values note). With GROUP BY, sy-subrc is 4
    " when nothing matched, which is the behaviour wanted here.
    " No ORDER BY on the aggregate alias here: sorting the result in
    " ABAP afterwards is unambiguous, and ORDER BY in a set-operator or
    " alias position has enough restrictions to not be worth guessing.
    SELECT uccheck, COUNT( * ) AS cnt
      FROM trdir
      GROUP BY uccheck
      INTO TABLE @DATA(lt_dist).

    IF sy-subrc <> 0.
      WRITE: / '  No rows in TRDIR - unexpected, but nothing to show.'.
      SKIP.
      RETURN.
    ENDIF.

    SORT lt_dist BY cnt DESCENDING.

    LOOP AT lt_dist INTO DATA(ls_dist).
      DATA(lv_label) = decode_version( ls_dist-uccheck ).
      WRITE: /   '  ID', ls_dist-uccheck,
                 'count', ls_dist-cnt,
                 '  ', lv_label.
    ENDLOOP.

    SKIP.
    WRITE: / '  On a classic on-premise system this is overwhelmingly X.'.
    WRITE: / '  Any 5 rows are already-cloud-ready objects; any other ID'.
    WRITE: / '  is worth investigating rather than assuming.'.
    SKIP.

  ENDMETHOD.


  METHOD show_safe_migration_pairs.

    WRITE: / '--- 3. Banned in Cloud, one-line fix, safe in Standard ABAP ---'.
    SKIP.

    " Each pair below is a language element allowed in Standard ABAP but
    " NOT in ABAP for Cloud Development, where the replacement is a
    " straight functional equivalent. Fixing these now costs nothing and
    " removes them from any future migration.

    " (a) DESCRIBE TABLE ... LINES  ->  lines( )
    "     The CAPABILITY is allowed; only the statement form is refused.
    DATA lt_demo TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    lt_demo = VALUE #( ( 1 ) ( 2 ) ( 3 ) ( 4 ) ).

    DATA lv_old TYPE i.
    DESCRIBE TABLE lt_demo LINES lv_old.   " banned in ABAP Cloud
    DATA(lv_new) = lines( lt_demo ).       " allowed

    WRITE: / '  (a) DESCRIBE TABLE LINES :', lv_old,
             '  vs  lines( ) :', lv_new.
    WRITE: /   '      identical result, one is banned in Cloud'.
    SKIP.

    " (b) BREAK-POINT / LOG-POINT are banned; ASSERT is allowed.
    "     ASSERT is the checkpoint that survives - see the repo's
    "     Checkpoints note for why it can still dump in production.
    ASSERT lv_old = lv_new.
    WRITE: / '  (b) ASSERT passed. BREAK-POINT and LOG-POINT are banned'.
    WRITE: /   '      in ABAP Cloud; ASSERT is not.'.
    SKIP.

    " (c) The whole classical list/selection-screen family is gone:
    "     REPORT, START-OF-SELECTION, WRITE, PARAMETERS, SELECT-OPTIONS,
    "     SELECTION-SCREEN, ULINE, SKIP, FORMAT, SUM, HIDE, TOP-OF-PAGE.
    "     These are not one-line fixes - they need a real UI layer (RAP)
    "     or a callable class. That is the honest split: (a) and (b) are
    "     free, (c) is a redesign.
    WRITE: / '  (c) REPORT / START-OF-SELECTION / WRITE / PARAMETERS /'.
    WRITE: /   '      SELECT-OPTIONS are all banned. This program uses'.
    WRITE: /   '      four of them. Not a one-line fix - a redesign.'.
    SKIP.

    " (d) Counter-intuitive direction, verified against the whitelist:
    "     FORM / ENDFORM / PERFORM are OBSOLETE yet ALLOWED in Cloud,
    "     while WRITE is neither obsolete nor allowed. Of 168 elements
    "     flagged obsolete, only 8 survive into Cloud - and FORM,
    "     ENDFORM, ADD, SUBTRACT, MULTIPLY and DIVIDE are among them.
    "     So "obsolete" and "banned in Cloud" are two different lists.
    WRITE: / '  (d) FORM/ENDFORM/PERFORM: obsolete, but LEGAL in Cloud.'.
    WRITE: /   '      WRITE: not obsolete, but ILLEGAL in Cloud.'.
    WRITE: /   '      The axis is stateless/UI-free, not old/new.'.
    SKIP.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.
  lcl_demo=>run( ).
