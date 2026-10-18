*&---------------------------------------------------------------------*
*& Report YDJ_GROUP_BY_DEMO
*&---------------------------------------------------------------------*
*& LOOP AT itab ... GROUP BY - the two output bindings and the five
*& behaviours that are documented, correct, and almost never what the
*& surrounding code assumes.
*&
*&   1. TWO BINDINGS   -> with no target after GROUP BY (representative
*&                        binding) the work area is the FIRST MEMBER row,
*&                        so every non-key column is one arbitrary
*&                        member's data. Add a group key binding and that
*&                        same work area is INITIAL in the loop body.
*&   2. SIZE / INDEX   -> GROUP SIZE and GROUP INDEX need BOTH a
*&                        structured group key AND a group key binding.
*&                        GROUP INDEX keeps the ORIGINAL position when
*&                        ASCENDING reorders the groups.
*&   3. MEMBER LOOP    -> sy-subrc is ALWAYS 0 after LOOP AT GROUP, even
*&                        when a WHERE condition matched nothing; and
*&                        sy-tabix is the index in the TABLE, not a
*&                        position inside the group.
*&   4. NO AGGREGATES  -> nothing is totalled for you except GROUP SIZE.
*&                        REDUCE over FOR ... IN GROUP replaces SUM, and
*&                        skipping a group replaces HAVING.
*&   5. WITHOUT MEMBERS-> counts only: no member loop, group key binding
*&                        mandatory, and the table becomes modifiable.
*&
*& The test data is deliberately UNSORTED, so the default group order
*& (first construction of each group key: LH, UA, AA) differs from the
*& ASCENDING order (AA, LH, UA).
*&
*& Self-contained: no DDIC tables needed. Read-only.
*&---------------------------------------------------------------------*
REPORT ydj_group_by_demo.

TYPES: BEGIN OF ty_flight,
         carrid   TYPE c LENGTH 3,
         connid   TYPE n LENGTH 4,
         fldate   TYPE d,
         seatsocc TYPE i,
       END OF ty_flight,
       ty_flights TYPE STANDARD TABLE OF ty_flight WITH EMPTY KEY.


CLASS lcl_group_demo DEFINITION.

  PUBLIC SECTION.
    CLASS-METHODS:
      two_bindings,
      size_and_index,
      member_loop,
      aggregate_and_having,
      without_members.

  PRIVATE SECTION.
    " No sorting and no dependence on component order - that is the whole
    " point of GROUP BY compared with AT NEW / AT END OF.
    CLASS-METHODS get_data RETURNING VALUE(rt_flights) TYPE ty_flights.

ENDCLASS.


CLASS lcl_group_demo IMPLEMENTATION.

  METHOD get_data.
    rt_flights = VALUE #(
      ( carrid = 'LH' connid = '0400' fldate = '20260101' seatsocc = 10 )
      ( carrid = 'UA' connid = '0941' fldate = '20260102' seatsocc = 20 )
      ( carrid = 'LH' connid = '0401' fldate = '20260103' seatsocc = 30 )
      ( carrid = 'AA' connid = '0017' fldate = '20260104' seatsocc = 40 )
      ( carrid = 'UA' connid = '0942' fldate = '20260105' seatsocc = 50 )
      ( carrid = 'LH' connid = '0402' fldate = '20260106' seatsocc = 60 ) ).
  ENDMETHOD.


  METHOD two_bindings.

    DATA(lt_flights) = get_data( ).

    WRITE: / '1a. Representative binding - wa is the FIRST MEMBER of the group'.

    " Nothing after GROUP BY, so the output behaviour of the LOOP itself
    " (INTO ls_rep) is reused for the group: ls_rep is the first line that
    " was assigned to the group. carrid is meaningful; connid, fldate and
    " seatsocc belong to ONE member and say nothing about the group.
    LOOP AT lt_flights INTO DATA(ls_rep) GROUP BY ls_rep-carrid.
      DATA(lv_line) = |{ ls_rep-carrid }: first member connid { ls_rep-connid
                      }, date { ls_rep-fldate DATE = ISO
                      }, seats { ls_rep-seatsocc }|.
      WRITE: / lv_line.
    ENDLOOP.

    SKIP.
    WRITE: / '1b. Group key binding - the SAME work area is now initial'.

    " Adding INTO lv_key switches the binding. The group key is now
    " available, and ls_wa is no longer filled: the docs say it "is either
    " initial after the LOOP statement or does not point to a line".
    " Reading ls_wa-connid here yields its INITIAL value, not an error -
    " and initial is '0000' for this NUMC field, not a blank, so it does
    " not even look empty in the output.
    LOOP AT lt_flights INTO DATA(ls_wa) GROUP BY ls_wa-carrid
                       INTO DATA(lv_key).
      lv_line = |{ lv_key }: wa-connid = '{ ls_wa-connid
                }', wa-seatsocc = { ls_wa-seatsocc } <- both initial|.
      WRITE: / lv_line.
    ENDLOOP.

  ENDMETHOD.


  METHOD size_and_index.

    DATA(lt_flights) = get_data( ).

    WRITE: / '2a. Default order = order in which each group key was FIRST built'.

    " GROUP SIZE / GROUP INDEX are extra components of a STRUCTURED group
    " key and require a group key binding (INTO ls_key). Under a
    " representative binding they cannot be declared at all. They are not
    " part of the key, so they never split a group.
    " With a group key binding, sy-tabix counts GROUPS, not table rows.
    LOOP AT lt_flights INTO DATA(ls_wa)
                       GROUP BY ( carrier = ls_wa-carrid
                                  indx    = GROUP INDEX
                                  size    = GROUP SIZE )
                       INTO DATA(ls_key).
      DATA(lv_line) = |pass { sy-tabix }: { ls_key-carrier
                      } group index { ls_key-indx
                      }, size { ls_key-size }|.
      WRITE: / lv_line.
    ENDLOOP.

    SKIP.
    WRITE: / '2b. ASCENDING reorders the groups - GROUP INDEX does not follow'.

    " Same grouping, sorted by group key. The sort is a plain SORT on the
    " key, so the extra components are ignored by it, and GROUP INDEX
    " still reports where the group ORIGINALLY appeared. Use sy-tabix (or
    " your own counter) if you want 1, 2, 3 in output order.
    LOOP AT lt_flights INTO DATA(ls_wa2)
                       GROUP BY ( carrier = ls_wa2-carrid
                                  indx    = GROUP INDEX
                                  size    = GROUP SIZE )
                       ASCENDING
                       INTO DATA(ls_key2).
      lv_line = |pass { sy-tabix }: { ls_key2-carrier
                } group index { ls_key2-indx
                }, size { ls_key2-size }|.
      WRITE: / lv_line.
    ENDLOOP.

  ENDMETHOD.


  METHOD member_loop.

    DATA(lt_flights) = get_data( ).

    WRITE: / '3. Member loop: sy-tabix is the TABLE index, sy-subrc is always 0'.

    LOOP AT lt_flights INTO DATA(ls_wa) GROUP BY ls_wa-carrid
                       INTO DATA(lv_carrier).

      DATA(lv_line) = |{ lv_carrier }:|.
      WRITE: / lv_line.

      " sy-tabix inside the member loop is "the value that would be set
      " for the current line in the LOOP without grouping" - the position
      " in lt_flights. There is no built-in counter for the position
      " within the group.
      LOOP AT GROUP lv_carrier INTO DATA(ls_member).
        lv_line = |    connid { ls_member-connid
                  } - sy-tabix { sy-tabix } (index in lt_flights)|.
        WRITE: / lv_line.
      ENDLOOP.

      " A WHERE condition that matches NO member still leaves sy-subrc 0:
      " a group loop never creates empty groups, and the filtering is only
      " noticed at the start of the first pass. So IF sy-subrc = 0 here is
      " always true and proves nothing - count instead.
      DATA(lv_matches) = 0.
      LOOP AT GROUP lv_carrier INTO ls_member WHERE seatsocc > 1000.
        lv_matches = lv_matches + 1.
      ENDLOOP.
      DATA(lv_subrc) = sy-subrc.

      lv_line = |    members with seatsocc > 1000: { lv_matches
                } - but sy-subrc after the member loop = { lv_subrc }|.
      WRITE: / lv_line.

    ENDLOOP.

  ENDMETHOD.


  METHOD aggregate_and_having.

    DATA(lt_flights) = get_data( ).

    WRITE: / '4. REDUCE over the members replaces SUM; skipping a group replaces HAVING'.

    " Nothing is aggregated implicitly except GROUP SIZE. The group key
    " binding here is a FIELD SYMBOL, and LOOP AT GROUP / FOR ... IN GROUP
    " must name it exactly as bound - with the angle brackets.
    LOOP AT lt_flights INTO DATA(ls_wa) GROUP BY ls_wa-carrid
                       ASCENDING
                       ASSIGNING FIELD-SYMBOL(<carrier>).

      DATA(lv_seats) = REDUCE i( INIT s = 0
                                 FOR ls_f IN GROUP <carrier>
                                 NEXT s = s + ls_f-seatsocc ).

      DATA(lv_count) = REDUCE i( INIT c = 0
                                 FOR ls_g IN GROUP <carrier>
                                 NEXT c = c + 1 ).

      " There is no HAVING for internal tables: filter the group yourself.
      IF lv_count < 2.
        DATA(lv_skip) = |{ <carrier> }: { lv_count
                        } flight - skipped (HAVING COUNT( * ) >= 2)|.
        WRITE: / lv_skip.
        CONTINUE.
      ENDIF.

      DATA(lv_line) = |{ <carrier> }: { lv_count } flights, { lv_seats
                      } seats occupied|.
      WRITE: / lv_line.

    ENDLOOP.

  ENDMETHOD.


  METHOD without_members.

    DATA(lt_flights) = get_data( ).

    WRITE: / '5. WITHOUT MEMBERS - counts only, and the table becomes modifiable'.

    " WITHOUT MEMBERS skips the internal line-to-group assignment, so:
    "   - a group key binding is mandatory (no representative possible),
    "   - LOOP AT GROUP / FOR ... IN GROUP are not allowed,
    "   - lt_flights MAY be modified in this loop (it may not be in any of
    "     the loops above),
    "   - GROUP SIZE still works, which makes this the cheap way to get a
    "     count per key.
    " The INTO ls_wa output behaviour is still required, because the group
    " key expression refers to it.
    LOOP AT lt_flights INTO DATA(ls_wa)
                       GROUP BY ( carrier = ls_wa-carrid
                                  size    = GROUP SIZE )
                       WITHOUT MEMBERS
                       INTO DATA(ls_key).
      DATA(lv_line) = |{ ls_key-carrier }: { ls_key-size } flight(s)|.
      WRITE: / lv_line.
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  WRITE: / '=== 1. The two output bindings ==='.
  lcl_group_demo=>two_bindings( ).
  SKIP 2.

  WRITE: / '=== 2. GROUP SIZE and GROUP INDEX ==='.
  lcl_group_demo=>size_and_index( ).
  SKIP 2.

  WRITE: / '=== 3. The member loop ==='.
  lcl_group_demo=>member_loop( ).
  SKIP 2.

  WRITE: / '=== 4. Aggregation and HAVING ==='.
  lcl_group_demo=>aggregate_and_having( ).
  SKIP 2.

  WRITE: / '=== 5. WITHOUT MEMBERS ==='.
  lcl_group_demo=>without_members( ).
