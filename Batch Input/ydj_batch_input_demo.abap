*&---------------------------------------------------------------------*
*& Report YDJ_BATCH_INPUT_DEMO
*&---------------------------------------------------------------------*
*& CALL TRANSACTION ... USING - the documented defaults that make a
*& failed load look like a successful one.
*&
*&   1. ASYNC IS THE      -> no UPDATE addition means upd = 'A', so the
*&      DEFAULT              caller CANNOT know whether the database was
*&                           actually written. Always pass UPDATE 'S'.
*&   2. THREE sy-subrc    -> 0 = ok, < 1000 = business error in the
*&      RANGES               transaction, 1001 = the screen flow itself
*&                           broke. Different causes, different fixes.
*&   3. THE 1001 THAT IS  -> in MODE 'N' a breakpoint terminates with
*&      A BREAKPOINT         1001 and message 00/344 SAPMSSY3 / 0131.
*&   4. MESSAGES INTO     -> collects SUCCESS messages too, so a
*&      IS NOT AN            non-empty table does not mean failure.
*&      ERROR FLAG           Filter on msgtyp, and CLEAR it per record.
*&   5. RACOMMIT          -> by default a COMMIT WORK inside the called
*&                           transaction ENDS processing, silently
*&                           skipping the rest of the BDCDATA table.
*&
*& The CALL TRANSACTION statement itself is COMMENTED OUT - this report
*& builds and inspects the BDCDATA table only and changes no data.
*&---------------------------------------------------------------------*
REPORT ydj_batch_input_demo.

*&---------------------------------------------------------------------*
*& Helper: the two subroutines every SHDB-generated program contains,
*& written as methods. bdc_dynpro starts a new screen, bdc_field fills
*& one field on the screen most recently started.
*&---------------------------------------------------------------------*
CLASS lcl_bdc DEFINITION.

  PUBLIC SECTION.
    TYPES ty_bdcdata TYPE STANDARD TABLE OF bdcdata WITH EMPTY KEY.
    TYPES ty_messages TYPE STANDARD TABLE OF bdcmsgcoll WITH EMPTY KEY.

    METHODS dynpro
      IMPORTING iv_program TYPE bdcdata-program
                iv_dynpro  TYPE bdcdata-dynpro.

    METHODS field
      IMPORTING iv_fnam TYPE bdcdata-fnam
                iv_fval TYPE bdcdata-fval.

    METHODS get_table
      RETURNING VALUE(rt_bdcdata) TYPE ty_bdcdata.

    METHODS reset.

  PRIVATE SECTION.
    DATA mt_bdcdata TYPE ty_bdcdata.

ENDCLASS.

CLASS lcl_bdc IMPLEMENTATION.

  METHOD dynpro.
    APPEND VALUE bdcdata( program  = iv_program
                          dynpro   = iv_dynpro
                          dynbegin = 'X' ) TO mt_bdcdata.
  ENDMETHOD.

  METHOD field.
    " No DYNBEGIN here - a blank DYNBEGIN means "field on the current
    " screen". PROGRAM and DYNPRO stay initial, per the documented rule
    " that unlisted columns remain initial.
    APPEND VALUE bdcdata( fnam = iv_fnam
                          fval = iv_fval ) TO mt_bdcdata.
  ENDMETHOD.

  METHOD get_table.
    rt_bdcdata = mt_bdcdata.
  ENDMETHOD.

  METHOD reset.
    CLEAR mt_bdcdata.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& The demo itself.
*&---------------------------------------------------------------------*
CLASS lcl_demo DEFINITION.

  PUBLIC SECTION.
    CLASS-METHODS run.

  PRIVATE SECTION.
    CLASS-METHODS show_bdcdata.
    CLASS-METHODS show_options.
    CLASS-METHODS classify_subrc.
    CLASS-METHODS filter_messages.

    CLASS-METHODS describe_subrc
      IMPORTING iv_subrc          TYPE sysubrc
      RETURNING VALUE(rv_text)    TYPE string.

ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

  METHOD run.
    show_bdcdata( ).
    show_options( ).
    classify_subrc( ).
    filter_messages( ).
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& 1. What a BDCDATA table actually looks like.
*&---------------------------------------------------------------------*
  METHOD show_bdcdata.

    DATA(lo_bdc) = NEW lcl_bdc( ).

    " Screen 1: the initial screen of a fictional transaction.
    lo_bdc->dynpro( iv_program = 'SAPMYDEMO' iv_dynpro = '0100' ).
    lo_bdc->field(  iv_fnam = 'BDC_CURSOR'  iv_fval = 'YDEMO-ID' ).
    lo_bdc->field(  iv_fnam = 'BDC_OKCODE'  iv_fval = '/00' ).
    lo_bdc->field(  iv_fnam = 'YDEMO-ID'    iv_fval = '4711' ).

    " Screen 2: a detail screen with a table control. Note the (01) -
    " a table control or step loop field MUST carry the row number.
    lo_bdc->dynpro( iv_program = 'SAPMYDEMO' iv_dynpro = '0200' ).
    lo_bdc->field(  iv_fnam = 'YDEMO-NAME'      iv_fval = 'DEMO RECORD' ).
    lo_bdc->field(  iv_fnam = 'YDEMO-ITEM(01)'  iv_fval = '000010' ).
    lo_bdc->field(  iv_fnam = 'BDC_OKCODE'      iv_fval = '=SAVE' ).

    DATA(lt_bdcdata) = lo_bdc->get_table( ).
    DATA(lv_rows)    = lines( lt_bdcdata ).

    WRITE: / '=== 1. The BDCDATA table ==='.
    SKIP.
    WRITE: / 'Rows built:', lv_rows.
    SKIP.
    WRITE: /  'PROGRAM',  12 'DYNPRO', 20 'BEG', 25 'FNAM', 48 'FVAL'.
    ULINE.

    LOOP AT lt_bdcdata INTO DATA(ls_row).
      WRITE: /  ls_row-program,
             12 ls_row-dynpro,
             20 ls_row-dynbegin,
             25 ls_row-fnam,
             48 ls_row-fval.
    ENDLOOP.

    SKIP.
    WRITE: / 'A row with DYNBEGIN = X starts a screen; PROGRAM and DYNPRO'.
    WRITE: / 'are only meaningful on those rows. Every other row fills one'.
    WRITE: / 'field of the screen most recently started.'.
    SKIP.
    WRITE: / 'BDC_OKCODE is the function code (/00 = Enter, =SAVE = a'.
    WRITE: / 'button). BDC_CURSOR positions the cursor - needed when a'.
    WRITE: / 'field only reacts with focus, or when a screen has no input'.
    WRITE: / 'fields at all.'.
    SKIP.
    WRITE: / 'FVAL is character data in the EXTERNAL format of the dynpro,'.
    WRITE: / 'so dates and amounts follow the EXECUTING user profile.'.
    SKIP.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& 2. The defaults, and the structure form that exposes the rest.
*&---------------------------------------------------------------------*
  METHOD show_options.

    WRITE: / '=== 2. MODE / UPDATE defaults ==='.
    SKIP.
    WRITE: / 'Writing neither MODE nor OPTIONS FROM means MODE = A, which'.
    WRITE: / 'DISPLAYS every screen. Unattended runs need an explicit N.'.
    SKIP.
    WRITE: / 'Writing neither UPDATE nor OPTIONS FROM means UPDATE = A,'.
    WRITE: / 'which is ASYNCHRONOUS: the caller gets control back before'.
    WRITE: / 'the database write happened, so sy-subrc = 0 proves only'.
    WRITE: / 'that the DIALOG finished. A failed update lands in SM13 and'.
    WRITE: / 'is invisible to this program. Use UPDATE S for data loads.'.
    SKIP.

    " The structure form. Every field below has no equivalent in the
    " short MODE/UPDATE syntax except the first two.
    DATA(ls_opt) = VALUE ctu_params(
      dismode  = 'N'      " no screen display
      upmode   = 'S'      " SYNCHRONOUS - wait for the V1 update
      cattmode = space    " not a CATT run
      defsize  = 'X'      " standard screen size, not the current one
      racommit = space    " blank: a COMMIT WORK inside ENDS processing
      nobinpt  = space    " blank: sy-binpt = X in the called program
      nobiend  = space ). " blank: sy-binpt stays X after the data ends

    WRITE: / 'CTU_PARAMS for OPTIONS FROM:'.
    SKIP.
    WRITE: / '  DISMODE  =', ls_opt-dismode,  '(MODE)'.
    WRITE: / '  UPMODE   =', ls_opt-upmode,   '(UPDATE)'.
    WRITE: / '  CATTMODE =', ls_opt-cattmode.
    WRITE: / '  DEFSIZE  =', ls_opt-defsize.
    WRITE: / '  RACOMMIT =', ls_opt-racommit.
    WRITE: / '  NOBINPT  =', ls_opt-nobinpt.
    WRITE: / '  NOBIEND  =', ls_opt-nobiend.
    SKIP.
    WRITE: / 'Note the names: the MODE addition is DISMODE here and the'.
    WRITE: / 'UPDATE addition is UPMODE. RACOMMIT is the one worth'.
    WRITE: / 'knowing - with it blank (the default), a COMMIT WORK issued'.
    WRITE: / 'by the called transaction terminates batch input, and every'.
    WRITE: / 'remaining screen in the BDCDATA table is never processed.'.
    SKIP.

    " The real call, deliberately commented out so this report is safe.
    " Before it, an explicit COMMIT WORK: CALL TRANSACTION opens a new
    " SAP LUW but NOT a new database LUW, so a ROLLBACK inside the called
    " transaction can delete this program's own IN UPDATE TASK entries.
    "
    " COMMIT WORK.
    "
    " CALL TRANSACTION 'XK01' WITH AUTHORITY-CHECK
    "      USING lt_bdcdata
    "      OPTIONS FROM ls_opt
    "      MESSAGES INTO lt_messages.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& 3. Classifying sy-subrc into its three documented ranges.
*&---------------------------------------------------------------------*
  METHOD classify_subrc.

    WRITE: / '=== 3. The three sy-subrc ranges ==='.
    SKIP.

    DATA lt_codes TYPE STANDARD TABLE OF sysubrc WITH EMPTY KEY.
    lt_codes = VALUE #( ( 0 ) ( 4 ) ( 12 ) ( 1001 ) ).

    LOOP AT lt_codes INTO DATA(lv_code).
      DATA(lv_text) = describe_subrc( lv_code ).
      WRITE: / lv_code, lv_text.
    ENDLOOP.

    SKIP.
    WRITE: / 'Collapsing < 1000 and 1001 into one error bucket is why a'.
    WRITE: / 'loader reports thousands of data errors after an upgrade,'.
    WRITE: / 'when in fact the screen sequence moved and no record was'.
    WRITE: / 'ever attempted.'.
    SKIP.

  ENDMETHOD.

  METHOD describe_subrc.

    rv_text = COND string(
      WHEN iv_subrc = 0    THEN `OK - dialog finished (NOT proof of a DB write in mode A)`
      WHEN iv_subrc = 1001 THEN `Processing error - screen flow broke, or a breakpoint in MODE N`
      WHEN iv_subrc < 1000 THEN `Business error in the transaction - read the message table`
      ELSE                      `Reserved for data transfer` ).

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& 4. MESSAGES INTO holds successes too.
*&---------------------------------------------------------------------*
  METHOD filter_messages.

    WRITE: / '=== 4. Filtering BDCMSGCOLL ==='.
    SKIP.

    " What a SUCCESSFUL record might leave behind: an info line and a
    " success line. Neither indicates a problem.
    DATA lt_messages TYPE lcl_bdc=>ty_messages.

    lt_messages = VALUE #(
      ( tcode = 'XK01' msgtyp = 'S' msgid = 'F2' msgnr = '064' msgv1 = '4711' )
      ( tcode = 'XK01' msgtyp = 'W' msgid = 'F2' msgnr = '118' )
      ( tcode = 'XK01' msgtyp = 'E' msgid = 'F2' msgnr = '003' msgv1 = '4711' ) ).

    DATA(lv_total) = lines( lt_messages ).

    DATA lt_errors LIKE lt_messages.
    LOOP AT lt_messages INTO DATA(ls_msg) WHERE msgtyp = 'E' OR msgtyp = 'A'.
      APPEND ls_msg TO lt_errors.
    ENDLOOP.

    DATA(lv_errors) = lines( lt_errors ).

    WRITE: / 'Messages collected:', lv_total.
    WRITE: / 'Of those, real errors (msgtyp E or A):', lv_errors.
    SKIP.

    LOOP AT lt_messages INTO ls_msg.
      WRITE: /  ls_msg-msgtyp,
             6  ls_msg-msgid,
             14 ls_msg-msgnr,
             20 ls_msg-msgv1.
    ENDLOOP.

    SKIP.
    WRITE: / 'So IF lt_messages IS NOT INITIAL is not an error test - a'.
    WRITE: / 'successful record fills this table too. Filter on msgtyp.'.
    SKIP.
    WRITE: / 'BDCMSGCOLL carries msgid/msgnr/msgv1..4, not text: format it'.
    WRITE: / 'with MESSAGE ... INTO or FORMAT_MESSAGE before showing it.'.
    SKIP.
    WRITE: / 'And the statement does NOT clear the table, so in a loop over'.
    WRITE: / 'records it must be cleared per record or record 1 errors are'.
    WRITE: / 'reported again against record 2.'.

  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  lcl_demo=>run( ).
