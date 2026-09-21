*&---------------------------------------------------------------------*
*& Report YDJ_CHECKPOINT_DEMO
*&---------------------------------------------------------------------*
*& ASSERT / LOG-POINT / BREAK-POINT - the three checkpoint statements
*& and the documented rules that decide whether they dump, log, or do
*& nothing at all.
*&
*&   1. ID OR NO ID        -> ASSERT without ID is ALWAYS active and
*&                            raises an UNCATCHABLE exception
*&                            (ASSERTION_FAILED). With ID it does
*&                            nothing unless the group is activated.
*&   2. LAZY EVALUATION    -> the condition, the SUBKEY and the FIELDS
*&                            operands are evaluated ONLY when the
*&                            checkpoint is active. A side effect in
*&                            there makes behaviour depend on SAAB.
*&   3. LOG-POINT KEEPS    -> every execution OVERWRITES the previous
*&      ONE ENTRY             entry of the SAME statement and bumps a
*&                            counter. SUBKEY is the only granularity.
*&   4. FIELDS ARE CUT     -> abap/aab_log_field_size_limit, 1024 bytes
*&                            by default; internal tables lose whole
*&                            lines, with nothing marking the entry.
*&   5. BREAK-POINT IS     -> in background/update/ICF it never stops.
*&      CONTEXT DEPENDENT     Without ID it writes to the system log;
*&                            WITH ID it is ignored completely.
*&
*& Self-contained: local classes and literals only, no DDIC, no
*& database. Nothing here can terminate the program - the only
*& always-active ASSERT is one that is guaranteed TRUE, and the
*& failing case is shown as a commented-out line.
*&
*& To see traps 2/3 live: create checkpoint group YDJ_CHECKPOINTS in
*& transaction SAAB, run this report (nothing logged), then activate
*& the group with operation mode Log and run it again.
*&---------------------------------------------------------------------*
REPORT ydj_checkpoint_demo.

*&---------------------------------------------------------------------*
*& A deliberately side-effecting "check" method, so trap 2 is proved by
*& COUNTING calls rather than by asserting that something happened.
*&---------------------------------------------------------------------*
CLASS lcl_probe DEFINITION.

  PUBLIC SECTION.
    CLASS-DATA gv_calls TYPE i.
    CLASS-METHODS is_consistent RETURNING VALUE(rv_ok) TYPE abap_bool.
    CLASS-METHODS reset.

ENDCLASS.

CLASS lcl_probe IMPLEMENTATION.

  METHOD is_consistent.
    " The side effect: a functional method used inside a checkpoint
    " operand must NOT do this. It is here to make the laziness visible.
    gv_calls = gv_calls + 1.
    rv_ok    = abap_true.
  ENDMETHOD.

  METHOD reset.
    gv_calls = 0.
  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& Demo
*&---------------------------------------------------------------------*
CLASS lcl_demo DEFINITION.

  PUBLIC SECTION.
    CLASS-METHODS run.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_item,
             doc_id TYPE string,
             status TYPE string,
           END OF ty_item,
           ty_items TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY.

    CLASS-METHODS build_items RETURNING VALUE(rt_items) TYPE ty_items.
    CLASS-METHODS trap_always_active.
    CLASS-METHODS trap_lazy_evaluation.
    CLASS-METHODS trap_logpoint_overwrites.
    CLASS-METHODS trap_breakpoint_context.

ENDCLASS.

CLASS lcl_demo IMPLEMENTATION.

  METHOD build_items.
    rt_items = VALUE ty_items(
      ( doc_id = '4700000001' status = 'OPEN' )
      ( doc_id = '4700000002' status = 'BLOCKED' )
      ( doc_id = '4700000003' status = 'OPEN' ) ).
  ENDMETHOD.

  METHOD run.
    trap_always_active( ).
    trap_lazy_evaluation( ).
    trap_logpoint_overwrites( ).
    trap_breakpoint_context( ).
  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Trap 1 - with ID vs without ID
*&---------------------------------------------------------------------*
  METHOD trap_always_active.

    DATA(lt_items) = build_items( ).

    WRITE: / 'Trap 1: ASSERT with and without ID'.
    ULINE.

    " ALWAYS active - no ID, no switch, no way to catch the failure.
    " This one is an internal invariant that the code above guarantees,
    " which is exactly the case the guideline allows.
    READ TABLE lt_items INTO DATA(ls_first) INDEX 1.
    ASSERT sy-subrc = 0.

    WRITE: / '  always-active ASSERT passed, first doc:', ls_first-doc_id.

    " The failing form, left commented out on purpose. Uncommenting it
    " terminates this report with the runtime error ASSERTION_FAILED.
    " TRY / CATCH cx_root around it would NOT help - the exception
    " raised by a failed assertion is uncatchable.
*   ASSERT 1 = 2.

    " ACTIVATABLE - does nothing at all unless checkpoint group
    " YDJ_CHECKPOINTS has an activation setting in THIS client, for
    " THIS user or server, that has not yet expired. CONDITION is
    " mandatory as soon as ID is specified.
    ASSERT ID        ydj_checkpoints
           CONDITION lt_items IS NOT INITIAL.

    WRITE: / '  activatable ASSERT reached; whether it did anything'.
    WRITE: / '  depends entirely on SAAB, not on this source code.'.
    SKIP.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Trap 2 - operands are evaluated only when the checkpoint is active
*&---------------------------------------------------------------------*
  METHOD trap_lazy_evaluation.

    WRITE: / 'Trap 2: operands run only when the checkpoint is active'.
    ULINE.

    lcl_probe=>reset( ).

    " The method call sits INSIDE an activatable assertion. If the
    " group is inactive the condition is never evaluated, so the call
    " never happens and the counter stays at zero.
    ASSERT ID        ydj_checkpoints
           CONDITION lcl_probe=>is_consistent( ) = abap_true.

    DATA(lv_calls_lazy) = lcl_probe=>gv_calls.

    " Same call written as ordinary code - always executed.
    DATA(lv_ok)          = lcl_probe=>is_consistent( ).
    DATA(lv_calls_total) = lcl_probe=>gv_calls.

    WRITE: / '  calls made from inside the ASSERT :', lv_calls_lazy.
    WRITE: / '  ordinary call returned            :', lv_ok.
    WRITE: / '  calls after one ordinary call     :', lv_calls_total.
    WRITE: / '  0 and 1 means the group is inactive;'.
    WRITE: / '  1 and 2 means it is active - the SAME program,'.
    WRITE: / '  two different execution counts. That is why a'.
    WRITE: / '  side-effecting method must never be used here.'.
    SKIP.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Trap 3 and 4 - LOG-POINT overwriting, SUBKEY, truncated FIELDS
*&---------------------------------------------------------------------*
  METHOD trap_logpoint_overwrites.

    DATA(lt_items) = build_items( ).

    WRITE: / 'Trap 3: LOG-POINT keeps ONE entry per statement'.
    ULINE.

    LOOP AT lt_items INTO DATA(ls_item).

      " WRONG for a loop: every pass overwrites the previous entry of
      " this same statement and increases a counter. After three passes
      " exactly one entry survives, holding document 3.
      LOG-POINT ID     ydj_checkpoints
                FIELDS ls_item-doc_id ls_item-status.

      " RIGHT: the subkey makes the entries distinct, so an existing
      " entry is only overwritten when the subkey matches. Only the
      " first 200 characters of the subkey are evaluated.
      LOG-POINT ID     ydj_checkpoints
                SUBKEY ls_item-doc_id
                FIELDS ls_item-status.

    ENDLOOP.

    DATA(lv_rows) = lines( lt_items ).
    WRITE: / '  documents processed              :', lv_rows.
    WRITE: / '  entries from the first LOG-POINT : 1, with hit count', lv_rows.
    WRITE: / '  entries from the second one      :', lv_rows.
    SKIP.

    WRITE: / 'Trap 4: FIELDS content is truncated'.
    ULINE.

    " The whole table is passed, but each logged data object is cut at
    " abap/aab_log_field_size_limit bytes (default 1024, 0 = no limit),
    " and internal tables lose COMPLETE LINES with nothing in the entry
    " saying that it happened.
    LOG-POINT ID     ydj_checkpoints
              SUBKEY `full-table`
              FIELDS sy-uname sy-datum lt_items.

    WRITE: / '  the table above is logged whole only if it fits in'.
    WRITE: / '  abap/aab_log_field_size_limit bytes; past that, lines'.
    WRITE: / '  are dropped silently. Reference variables cannot be'.
    WRITE: / '  passed in FIELDS at all.'.
    SKIP.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Trap 5 - BREAK-POINT depends on the processing context
*&---------------------------------------------------------------------*
  METHOD trap_breakpoint_context.

    WRITE: / 'Trap 5: BREAK-POINT behaviour is context dependent'.
    ULINE.

    " Activatable form. In dialog it stops in the Debugger when the
    " group is active; in a background job, an update task or an ICF
    " session without external debugging it is IGNORED - no debugger,
    " no system log entry, nothing.
    " Left commented out so this report never interrupts itself.
*   BREAK-POINT ID ydj_checkpoints.

    " Always-active form with a system log text. Note the type: the
    " text must be a FLAT character field of length 40. A data object
    " of type STRING here is silently IGNORED, and the addition is
    " ignored in dialog processing regardless.
    TYPES ty_log_text TYPE c LENGTH 40.
    DATA(lv_log_text) = CONV ty_log_text( |checkpoint demo { sy-repid }| ).

    " Commented out as well: without ID this is flagged as an ERROR by
    " the extended program check (SLIN) and is not allowed in a
    " production program.
*   BREAK-POINT lv_log_text.

    IF sy-batch = abap_true.
      WRITE: / '  running in background: BREAK-POINT ID would be ignored'.
    ELSE.
      WRITE: / '  running in dialog: BREAK-POINT ID would open the'.
      WRITE: / '  Debugger if the group were active'.
    ENDIF.

    WRITE: / '  prepared system log text:', lv_log_text.
    SKIP.

    WRITE: / 'Reminder: activation settings are NOT transported, are'.
    WRITE: / 'client dependent, expire on their own, and do not affect'.
    WRITE: / 'programs that are already running.'.

  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  lcl_demo=>run( ).
