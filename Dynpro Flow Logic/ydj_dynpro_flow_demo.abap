*&---------------------------------------------------------------------*
*& Program YDJ_DYNPRO_FLOW_DEMO
*&---------------------------------------------------------------------*
*& Dynpro flow logic - the five behaviours that are decided by WHERE a
*& module is called, not by what it contains.
*&
*&   1. FIELD POSTPONES TRANSPORT -> a module above a FIELD statement
*&      reads the PREVIOUS dialog step's value. Documented: "A dynpro
*&      field must not be used in a PAI module, before it is passed by
*&      the dynpro. Otherwise, the ABAP field contains the same value
*&      as at the end of the previous dialog step."
*&   2. AT EXIT-COMMAND -> runs before the automatic input checks,
*&      regardless of its position, and "The only dynpro field
*&      transported to the ABAP program is the OK field."
*&   3. AN EXIT MODULE THAT DOES NOT LEAVE -> PAI continues normally,
*&      so a forgotten WHEN 'BACK' runs the save logic.
*&   4. ON INPUT vs ON REQUEST -> ON INPUT never fires for an EMPTY
*&      field, so it cannot be used for a mandatory-field check.
*&   5. MESSAGE e... UNLOCKS ONLY WHAT YOU CHAINED -> under a bare
*&      FIELD, one field; inside CHAIN, the whole chain; in a plain
*&      MODULE, nothing at all (the frozen screen).
*&
*& READ-ONLY: no SELECT, no INSERT/UPDATE/DELETE/MODIFY, no COMMIT,
*& no file access, no RFC. The only persistent effect is the screen.
*&
*& This file is the ABAP side only. A dynpro is a Screen Painter
*& object, so the flow logic cannot live in program source - it must be
*& typed into the Flow Logic tab of SE51. Everything needed is below.
*&
*& The dynpro fields here reference this program's own global data
*& objects, so no TABLES statement is required. TABLES IS required when
*& a dynpro field references a flat DDIC structure - without it there
*& is no data transport at all, with or without FIELD.
*&
*& SETUP (SE80 / SE51), about ten minutes
*& -------------------------------------------------------------------
*& 1. Create this program as type 1 (executable), then create dynpro
*&    100 in it. Leave the Next Dynpro attribute at 100 (the default is
*&    the dynpro itself, i.e. it loops until something leaves it).
*& 2. Layout - input/output fields, names EXACTLY as below:
*&       GV_EARLY   char 10, input
*&       GV_LATE    char 10, input
*&       GV_FROM    char 10, input
*&       GV_TO      char 10, input
*&       GV_FREEZE  char  1, input, as a checkbox
*&       GV_T1 .. GV_T6  char 72, OUTPUT ONLY (the trace display)
*& 3. Element list -> General Attributes: add a field named OK_CODE,
*&    type OK, length 20. This is the OK field. It is the thing that
*&    makes "a pressed button counts as a changed field" work; a
*&    program that reads sy-ucomm instead does not get that.
*& 4. Create GUI status STATUS_100 in the Menu Painter with:
*&       BACK   (F3)  function type E
*&       CANCEL (F12) function type E
*&       EXECUTE(F8)  function type <blank>
*&    The function TYPE is what routes a button to AT EXIT-COMMAND -
*&    not the function code, and not the icon.
*& 5. Paste this into the Flow Logic tab of dynpro 100:
*&
*&    PROCESS BEFORE OUTPUT.
*&      MODULE status_0100.
*&    PROCESS AFTER INPUT.
*&      MODULE exit_0100 AT EXIT-COMMAND.
*&      MODULE read_too_early.
*&      FIELD gv_late  MODULE check_late.
*&      FIELD gv_early MODULE check_early ON REQUEST.
*&      CHAIN.
*&        FIELD gv_from.
*&        FIELD gv_to.
*&        MODULE check_range ON CHAIN-REQUEST.
*&      ENDCHAIN.
*&      FIELD gv_freeze MODULE unlock_one ON INPUT.
*&      MODULE user_command_0100.
*&
*&    Note that MODULE exit_0100 is written FIRST only for readability.
*&    AT EXIT-COMMAND is called "independently of its position in the
*&    event block" - it is the one non-positional statement here.
*&
*& WHAT TO DO ONCE IT RUNS
*& -------------------------------------------------------------------
*& a) Type something into GV_EARLY and GV_LATE, press Execute. Read the
*&    trace: READ_TOO_EARLY saw BLANKS, because both fields are under
*&    FIELD statements further down. Press Execute again with the SAME
*&    values: now READ_TOO_EARLY shows them - they are last step's
*&    values, one dialog step late, forever.
*& b) Press Execute twice without changing GV_EARLY. CHECK_EARLY runs
*&    only the first time (ON REQUEST = changed since PBO), while
*&    CHECK_LATE runs every time (no condition).
*& c) Leave GV_FREEZE unticked: UNLOCK_ONE never runs, because ON INPUT
*&    does not fire for an empty field. Tick it: the error appears and
*&    ONLY the checkbox is input-ready. Every other field on the screen
*&    is now locked, including the ones you were asked to correct.
*& d) Put GV_FROM = 'Z' and GV_TO = 'A' and press Execute: the error
*&    unlocks BOTH chained fields. Same MESSAGE statement, different
*&    flow-logic position, different screen.
*& e) Press Back (F3). EXIT_0100 runs, finds 'BACK', does NOT leave -
*&    and the trace then shows USER_COMMAND_0100 running anyway. That
*&    is the whole bug: Back executed the action.
*& f) Press Cancel (F12) to end the program.
*&
*& NOT shipped on purpose: the frozen screen. Replacing the line
*&   FIELD gv_freeze MODULE unlock_one ON INPUT.
*& with a bare
*&   MODULE unlock_one.
*& reproduces it - the message is sent from a module with no reference
*& to FIELD or CHAIN, so NO field becomes input-ready and the only way
*& out is a function with function type E. Try it only with the CANCEL
*& button already working, and change it back afterwards.
*&
*& Messages: SAP's own dynpro examples in the keyword documentation use
*& message 103 of class SABAPDEMOS, so this demo does too rather than
*& inventing a T100 entry. If that class is missing on your system,
*& swap in any message of your own with up to three placeholders.
*&
*& Docs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_DYNPROS_DYNPRO_STATEMENTS.html
*&---------------------------------------------------------------------*
PROGRAM ydj_dynpro_flow_demo.

" Trace storage. A dialog module has no local data of its own, so the
" documented recommendation is to keep logic in procedures and call
" them from the module - here, a local class.
CLASS lcl_trace DEFINITION.
  PUBLIC SECTION.
    CLASS-DATA gt_log TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    CLASS-DATA gv_step TYPE i.
    CLASS-METHODS add IMPORTING iv_text TYPE string.
    CLASS-METHODS next_step.
ENDCLASS.

CLASS lcl_trace IMPLEMENTATION.
  METHOD add.
    DATA lv_line TYPE string.
    lv_line = |{ gv_step WIDTH = 2 } { iv_text }|.
    APPEND lv_line TO gt_log.
  ENDMETHOD.

  METHOD next_step.
    gv_step = gv_step + 1.
  ENDMETHOD.
ENDCLASS.

" Dynpro fields of dynpro 100. The names must match the screen element
" names exactly - that is the entire transport contract.
DATA: ok_code   TYPE sy-ucomm,
      gv_early  TYPE c LENGTH 10,
      gv_late   TYPE c LENGTH 10,
      gv_from   TYPE c LENGTH 10,
      gv_to     TYPE c LENGTH 10,
      gv_freeze TYPE c LENGTH 1.

" Output-only trace lines shown on the screen.
DATA: gv_t1 TYPE c LENGTH 72,
      gv_t2 TYPE c LENGTH 72,
      gv_t3 TYPE c LENGTH 72,
      gv_t4 TYPE c LENGTH 72,
      gv_t5 TYPE c LENGTH 72,
      gv_t6 TYPE c LENGTH 72.

" Message placeholders. MESSAGE ... WITH formats each operand with
" output length 50, so a longer value loses its tail with no warning.
DATA: gv_msg1 TYPE c LENGTH 30,
      gv_msg2 TYPE c LENGTH 30,
      gv_msg3 TYPE c LENGTH 30.

CALL SCREEN 100.

*&---------------------------------------------------------------------*
*& PBO
*&---------------------------------------------------------------------*
MODULE status_0100 OUTPUT.

  SET PF-STATUS 'STATUS_100'.

  " Everything the PBO does is undone-by-omission on an error round
  " trip: an error message redisplays the screen "without raising the
  " event PBO", so this module does NOT run again while the user is
  " correcting input. The trace they are reading is the one from the
  " last successful PBO.
  CLEAR: gv_t1, gv_t2, gv_t3, gv_t4, gv_t5, gv_t6.

  " A dialog module has no local data. These DATA statements are
  " written inside the module but are declared GLOBALLY for the whole
  " program, and they keep their values between dialog steps - which is
  " the same mechanism that makes a too-early field read look like a
  " plausible value rather than an empty one.
  DATA: lv_total TYPE i,
        lv_first TYPE i,
        lv_idx   TYPE i.

  lv_total = lines( lcl_trace=>gt_log ).
  lv_first = lv_total - 5.
  IF lv_first < 1.
    lv_first = 1.
  ENDIF.

  LOOP AT lcl_trace=>gt_log INTO DATA(lv_entry) FROM lv_first.
    lv_idx = sy-tabix - lv_first + 1.
    CASE lv_idx.
      WHEN 1. gv_t1 = lv_entry.
      WHEN 2. gv_t2 = lv_entry.
      WHEN 3. gv_t3 = lv_entry.
      WHEN 4. gv_t4 = lv_entry.
      WHEN 5. gv_t5 = lv_entry.
      WHEN 6. gv_t6 = lv_entry.
    ENDCASE.
  ENDLOOP.

  lcl_trace=>next_step( ).

ENDMODULE.

*&---------------------------------------------------------------------*
*& PAI - AT EXIT-COMMAND
*&---------------------------------------------------------------------*
MODULE exit_0100 INPUT.

  " Reached only by a function of type E, or by typing a string
  " starting with E into the command field. Runs BEFORE the automatic
  " input checks, which is why Cancel works on a screen with unfilled
  " mandatory fields.
  "
  " Only the OK field has been transported at this point. gv_early
  " below is therefore last dialog step's value, not what is on the
  " screen right now - a "save your changes?" prompt written here
  " cannot see the changes.
  lcl_trace=>add( |EXIT_0100 ok_code={ ok_code } gv_early(stale)=[{ gv_early }]| ).

  CASE ok_code.
    WHEN 'CANCEL'.
      " Clearing the OK field before leaving is the habit SAP's own
      " example shows. The OK field is an ordinary global variable, and
      " AT CURSOR-SELECTION is a documented case where a user action
      " leaves its PREVIOUS value in place.
      CLEAR ok_code.
      LEAVE PROGRAM.
    WHEN OTHERS.
      " Deliberately does nothing for 'BACK'. The exit module is not an
      " exit: "If the dynpro processing is not terminated in the dialog
      " module mod, the complete PAI processing is executed after the
      " dialog module has ended." Watch USER_COMMAND_0100 run below.
      lcl_trace=>add( |  -> not leaving; PAI continues as normal| ).
  ENDCASE.

ENDMODULE.

*&---------------------------------------------------------------------*
*& PAI - the module that reads its fields one dialog step too early
*&---------------------------------------------------------------------*
MODULE read_too_early INPUT.

  " gv_early and gv_late are both named in FIELD statements further
  " down the event block, so neither has been transported yet. Adding
  " those FIELD statements for validation is what broke this module,
  " and nothing reports it.
  lcl_trace=>add( |READ_TOO_EARLY gv_early=[{ gv_early }] gv_late=[{ gv_late }]| ).

ENDMODULE.

*&---------------------------------------------------------------------*
*& PAI - unconditional check (runs on every PAI)
*&---------------------------------------------------------------------*
MODULE check_late INPUT.

  " No ON condition: called "immediately after the data transport
  " specified in FIELD". So gv_late IS current here.
  lcl_trace=>add( |CHECK_LATE     gv_late=[{ gv_late }] (always runs)| ).

ENDMODULE.

*&---------------------------------------------------------------------*
*& PAI - ON REQUEST: only when the value was typed since PBO
*&---------------------------------------------------------------------*
MODULE check_early INPUT.

  " ON REQUEST counts overwriting a value with the SAME value, and
  " also counts four non-human sources: Hold Data, an SPA/GPA
  " PARAMETER-ID default, CALL TRANSACTION ... USING (so a batch input
  " session fires this for every field it maps), and a system/DDIC
  " default. MODIFY SCREEN with request = 1 at PBO arms it too.
  lcl_trace=>add( |CHECK_EARLY    gv_early=[{ gv_early }] (ON REQUEST)| ).

ENDMODULE.

*&---------------------------------------------------------------------*
*& PAI - error inside a CHAIN: the whole chain is unlocked
*&---------------------------------------------------------------------*
MODULE check_range INPUT.

  lcl_trace=>add( |CHECK_RANGE    from=[{ gv_from }] to=[{ gv_to }]| ).

  IF gv_from IS NOT INITIAL AND gv_to IS NOT INITIAL AND gv_from > gv_to.
    gv_msg1 = 'Range'.
    gv_msg2 = gv_from.
    gv_msg3 = gv_to.
    " Error sent from inside CHAIN - ENDCHAIN: every dynpro field named
    " after a FIELD statement in this chain becomes input-ready, and
    " nothing else on the screen does. PAI will resume at the CHAIN
    " statement at the latest, NOT at the top of the event block.
    MESSAGE e103(sabapdemos) WITH gv_msg1 gv_msg2 gv_msg3.
  ENDIF.

ENDMODULE.

*&---------------------------------------------------------------------*
*& PAI - error under a bare FIELD: exactly one field is unlocked
*&---------------------------------------------------------------------*
MODULE unlock_one INPUT.

  " Called ON INPUT, so an unticked checkbox (blank = empty) skips this
  " module entirely. That is the documented reason ON INPUT cannot
  " implement a mandatory-field check: it is not called in the one case
  " the check exists for.
  lcl_trace=>add( |UNLOCK_ONE     gv_freeze=[{ gv_freeze }] (ON INPUT)| ).

  gv_msg1 = 'Only this field'.
  gv_msg2 = 'is input-ready'.
  gv_msg3 = 'untick to continue'.
  " Under a bare FIELD statement: "the input field in question becomes
  " the only input-enabled field on the current dynpro". Remove the
  " FIELD and this same line freezes the screen outright.
  MESSAGE e103(sabapdemos) WITH gv_msg1 gv_msg2 gv_msg3.

ENDMODULE.

*&---------------------------------------------------------------------*
*& PAI - the ordinary command handler
*&---------------------------------------------------------------------*
MODULE user_command_0100 INPUT.

  lcl_trace=>add( |USER_COMMAND   ok_code={ ok_code }| ).

  CASE ok_code.
    WHEN 'EXECUTE'.
      lcl_trace=>add( |  -> this is where a real save would happen| ).
    WHEN OTHERS.
      lcl_trace=>add( |  -> no action for this function code| ).
  ENDCASE.

  " Clear it once handled. A double-click handled by
  " AT CURSOR-SELECTION does not deliver a function code at all -
  " sy-ucomm and the OK field "keep their previous values" - so an
  " uncleared ok_code makes the previous action run a second time.
  CLEAR ok_code.

ENDMODULE.
