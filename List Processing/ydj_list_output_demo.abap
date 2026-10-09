*&---------------------------------------------------------------------*
*& Report  ydj_list_output_demo
*&---------------------------------------------------------------------*
*& Classic lists and WRITE: where the output length comes from, why the
*& minus sign is on the right, and how HIDE / READ LINE / sy-lsind
*& actually behave on an interactive list.
*&
*& Seven sections in the basic list:
*&   1  the output length comes from the TYPE, not from the value
*&   2  the rightmost column is the sign
*&   3  the / that is ignored, the pos that is ignored, the pos that
*&      produces nothing at all
*&   4  the all-blank line that is never written
*&   5  a HIDE-backed selection list, with a line-kind marker
*&   6  one line with a marker but no payload (the stale-read case)
*&   7  a line with no HIDE at all
*&
*& Then double-click any line in section 5-7 to reach AT LINE-SELECTION,
*& which shows the list-level system fields, what HIDE handed back, and
*& how a READ LINE loop OVERWRITES those same variables.
*&
*& WHY THIS DEMO IS PROCEDURAL, unlike the rest of the repo: HIDE cannot
*& be used on a local field (runtime error HIDE_NO_LOCAL, uncatchable)
*& and cannot be used on a class attribute at all - the documentation
*& rules that out explicitly. A local class version of this demo would
*& dump. So the fields below are global, on purpose.
*&
*& READ-ONLY: no SELECT, no database write, no COMMIT, no file access,
*& no RFC, no MESSAGE. Everything is in-memory formatting plus the list
*& buffer itself.
*&
*& Refs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLIST_OVERVIEW.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENWRITE_OUTPUT_LENGTH.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPHIDE.html
*&---------------------------------------------------------------------*
REPORT ydj_list_output_demo LINE-SIZE 95.

* Fields that HIDE stores must be GLOBAL and FLAT.
* - global: HIDE_NO_LOCAL / HIDE_NOT_GLOBAL otherwise
* - flat  : so gv_key is c LENGTH 10 and NOT a string
DATA: gv_kind TYPE c LENGTH 1,          " 'D' data line, 'H' header line
      gv_num  TYPE i,
      gv_key  TYPE c LENGTH 10.

* Values captured from the clicked line before anything overwrites them.
DATA: gv_sel_kind TYPE c LENGTH 1,
      gv_sel_num  TYPE i,
      gv_sel_key  TYPE c LENGTH 10.

* Formatting demo fields.
DATA: gv_date  TYPE d,
      gv_time  TYPE t,
      gv_pack  TYPE p LENGTH 8 DECIMALS 2,
      gv_int   TYPE i,
      gv_text  TYPE c LENGTH 16,
      gv_blank TYPE c LENGTH 12.

* Positioning demo fields. A literal 0 as a position would be rejected
* by the syntax check, so the ignored-position case needs a variable.
DATA: gv_col TYPE i,
      gv_len TYPE i.

* Line-counter probes. sy-linno is read into these BEFORE the next WRITE,
* because the next WRITE moves it.
DATA: gv_lin_before TYPE i,
      gv_lin_after  TYPE i.

* READ LINE loop in the event block.
DATA: gv_i    TYPE i,
      gv_seen TYPE i.


START-OF-SELECTION.

*----------------------------------------------------------------------*
* 1. The output length comes from the TYPE
*----------------------------------------------------------------------*
* Predefined output lengths: d = 8, t = 6, i = 11,
* p = 2 x length (+1 for the decimal separator).
* The documentation states plainly that the lengths for d and t "are not
* sufficient to display the corresponding separator" - so the default
* output of a date has no separators at all.
*----------------------------------------------------------------------*
  gv_date = sy-datum.
  gv_time = sy-uzeit.

  WRITE: / '--- 1. output length comes from the type'.
  WRITE: / '  date, default (8 columns) :', gv_date,
         / '  date, (10) columns        :', (10) gv_date,
         / '  time, default (6 columns) :', gv_time,
         / '  time, (8) columns         :', (8) gv_time.

* (*) asks for the minimum length that shows the whole value, (**) for
* the maximum the type could ever need. Neither is the default.
  gv_pack = '12345.67'.
  WRITE: / '  packed, default           :', gv_pack,
         / '  packed, (*)               :', (*) gv_pack,
         / '  packed, (**)              :', (**) gv_pack.

* A deliberately short output length does NOT raise for a packed number;
* it is cut and flagged with an asterisk. Only decfloat raises.
  WRITE: / '  packed, (4) - too short   :', (4) gv_pack,
         / '    ^ no exception, no sy-subrc: the asterisk IS the error'.

*----------------------------------------------------------------------*
* 2. The rightmost column is the sign
*----------------------------------------------------------------------*
* "the last place on the right is reserved for the sign ... negative
* values are given a minus - in the result and positive values a blank"
* This is where SAP spool output of the form 1,234.56- comes from.
*----------------------------------------------------------------------*
  SKIP.
  WRITE: / '--- 2. the sign lives on the RIGHT'.

  gv_pack = '-1234.56'.
  WRITE: / '  negative packed           :', gv_pack.
  gv_pack = '1234.56'.
  WRITE: / '  positive packed           :', gv_pack,
         / '    ^ same width: the positive case pays a blank for the sign'.

  gv_int = -42.
  WRITE: / '  negative integer          :', gv_int.

* The thousands and decimal separators come from the USER, not from the
* program, so this same line prints differently for a DE and a US logon.
  WRITE: / '    separators above come from the user formatting setting'.

*----------------------------------------------------------------------*
* 3. Positioning that is silently ignored
*----------------------------------------------------------------------*
  SKIP.
  WRITE: / '--- 3. positioning that is ignored'.
  gv_text = 'POSITIONED'.

* The / is dropped after SKIP, because the cursor was not placed by a
* previous output statement.
  SKIP.
  WRITE / '  this line follows SKIP and its / was IGNORED'.

* pos < 1 is ignored and the output lands at the cursor instead.
  gv_col = 0.
  gv_len = 10.
  WRITE AT gv_col(gv_len) gv_text.

* pos beyond the line width produces NO output - no dump, no sy-subrc.
  gv_col = sy-linsz + 10.
  WRITE AT gv_col(gv_len) gv_text.
  WRITE: / '  a write at column', gv_col, 'produced nothing at all',
         / '    (line width sy-linsz is', sy-linsz, ')'.

*----------------------------------------------------------------------*
* 4. The all-blank line that is never written
*----------------------------------------------------------------------*
* SET BLANK LINES is OFF by default: "all subsequent lines that contain
* only blanks after a line break are not written to the list". Empty
* checkboxes count as blank too, which is how a selection list silently
* loses rows and shifts every line number after them.
*----------------------------------------------------------------------*
  SKIP.
  WRITE: / '--- 4. the blank line that does not exist'.

  CLEAR gv_blank.
  gv_lin_before = sy-linno.
  WRITE / gv_blank.                      " all blanks -> suppressed
  gv_lin_after = sy-linno.
  WRITE: / '  blank line with SET BLANK LINES OFF (default):',
         / '    sy-linno before:', gv_lin_before,
         / '    sy-linno after :', gv_lin_after,
         / '    if those match, the line was never written at all'.

  SET BLANK LINES ON.
  gv_lin_before = sy-linno.
  WRITE / gv_blank.                      " same WRITE, now kept
  gv_lin_after = sy-linno.
  SET BLANK LINES OFF.
  WRITE: / '  same WRITE with SET BLANK LINES ON:',
         / '    sy-linno before:', gv_lin_before,
         / '    sy-linno after :', gv_lin_after.

*----------------------------------------------------------------------*
* 5-7. An interactive list: HIDE, a line-kind marker, and two lines
*      that deliberately do not carry a payload
*----------------------------------------------------------------------*
* HIDE stores a value against the CURRENT LINE NUMBER, not against the
* variable. On a list event the saved values are assigned back - and for
* a line where nothing was saved, nothing is assigned, so the variable
* still holds whatever the previous click put there. Hence gv_kind:
* a marker HIDEn on every line is the only reliable way for the handler
* to know what it is looking at.
*----------------------------------------------------------------------*
  SKIP.
  WRITE: / '--- 5. double-click any line below'.
  ULINE.

* A header line: marker only, no payload.
  gv_kind = 'H'.
  WRITE / '  HEADER (marker H, no payload HIDEn)' COLOR = 7 HOTSPOT.
  HIDE gv_kind.

* Five data lines: marker plus payload.
  DO 5 TIMES.
    gv_kind = 'D'.
    gv_num  = sy-index * 100.
    gv_key  = |KEY-{ sy-index }|.
    WRITE: / '  row' COLOR = 5 HOTSPOT, gv_num COLOR = 5 HOTSPOT.
    HIDE: gv_kind, gv_num, gv_key.
  ENDDO.

* A line with NO HIDE at all - not even a marker.
  WRITE / '  LINE WITH NO HIDE - handler sees stale values' COLOR = 6
                                                            HOTSPOT.
  ULINE.
  WRITE: / '  (Back returns here and drops one list level.)'.


*----------------------------------------------------------------------*
* Page header of the BASIC list only. Detail lists do not get this one;
* they need TOP-OF-PAGE DURING LINE-SELECTION below.
*----------------------------------------------------------------------*
TOP-OF-PAGE.

  WRITE: / 'ydj_list_output_demo - basic list, page', sy-pagno.
  ULINE.


*----------------------------------------------------------------------*
* Page header for every DETAIL list. Without this addition, detail lists
* appear with no header at all.
*----------------------------------------------------------------------*
TOP-OF-PAGE DURING LINE-SELECTION.

  WRITE: / 'detail list header - level', sy-lsind.
  ULINE.


*----------------------------------------------------------------------*
* The event is raised by the function code PICK. Defining this block is
* what wires F2 / double-click to PICK in the standard list status - add
* a SET PF-STATUS of your own and the double-click may arrive at
* AT USER-COMMAND instead, with nothing reporting the change.
*----------------------------------------------------------------------*
AT LINE-SELECTION.

* Capture FIRST. READ LINE further down assigns the HIDE values of the
* line it reads to these same variables, which destroys the values the
* click delivered.
  gv_sel_kind = gv_kind.
  gv_sel_num  = gv_num.
  gv_sel_key  = gv_key.

  WRITE: / 'list level being written (sy-lsind) :', sy-lsind,
         / 'list level displayed     (sy-listi) :', sy-listi,
         / 'absolute line clicked    (sy-lilli) :', sy-lilli,
         / 'function code            (sy-ucomm) :', sy-ucomm.
  ULINE.

  CASE gv_sel_kind.

    WHEN 'D'.
      WRITE: / 'data line. HIDE handed back:',
             / '  gv_num:', gv_sel_num,
             / '  gv_key:', gv_sel_key.

    WHEN 'H'.
      WRITE: / 'header line. Only the marker was HIDEn here, so the',
             / 'payload below is STALE - left over from an earlier click:',
             / '  gv_num:', gv_sel_num,
             / '  gv_key:', gv_sel_key,
             / 'Nothing in the runtime reports this - the marker is',
             / 'the only reason the handler can tell the difference.'.

    WHEN OTHERS.
      WRITE: / 'a line with no HIDE at all: even the marker is stale',
             / '  marker:', gv_sel_kind,
             / '  gv_num:', gv_sel_num,
             / '  gv_key:', gv_sel_key.

  ENDCASE.

* READ LINE with no INDEX reads the DISPLAYED list (sy-listi), not the
* detail list being written here. sy-lisel is the RENDERED line: output
* lengths applied, separators inserted, sign on the right. The substring
* access below is safe only because this detail line is never read back
* - on a line you intend to re-read, use an output length after AT.
  SKIP.
  WRITE: / 'READ LINE over the displayed list:'.

  gv_i    = 1.
  gv_seen = 0.
  DO.
    READ LINE gv_i.
    IF sy-subrc <> 0.
      EXIT.
    ENDIF.
    gv_seen = gv_seen + 1.
    WRITE: / '  line', gv_i, ':', sy-lisel(46).
    gv_i = gv_i + 1.
    IF gv_i > 14.
      EXIT.
    ENDIF.
  ENDDO.

  WRITE: / '  lines read:', gv_seen,
         / '  sy-subrc <> 0 was the only stop signal available'.

* Proof that the loop overwrote the click: compare live against captured.
  WRITE: / 'after the READ LINE loop, the live variables hold the LAST',
         / 'line read, not the line clicked:',
         / '  live gv_key    :', gv_key,
         / '  captured gv_key:', gv_sel_key.

* Depth guard. The list buffer holds a basic list plus 20 detail lists;
* assigning sy-lsind = 0 here would replace the basic list and delete
* the whole stack above it, so it is described rather than executed.
  IF sy-lsind >= 19.
    SKIP.
    WRITE: / 'list level', sy-lsind, 'of 20 - one level left.',
           / 'sy-lsind = 0 would collapse the stack onto the basic list;',
           / 'a value above the current level is silently reset instead.'.
  ENDIF.
