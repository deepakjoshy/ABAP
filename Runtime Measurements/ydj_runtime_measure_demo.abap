*&---------------------------------------------------------------------*
*& Report YDJ_RUNTIME_MEASURE_DEMO
*&---------------------------------------------------------------------*
*& Runtime measurements in ABAP - GET RUN TIME, CL_ABAP_RUNTIME,
*& SET RUN TIME CLOCK RESOLUTION, SET RUN TIME ANALYZER.
*&
*&   The probe numbers below are the probe numbers printed by the report.
*&
*&   1. The first read is 0     -> the clock is RELATIVE to the internal
*&                                session, not absolute. One GET RUN TIME
*&                                on its own measures nothing, and the
*&                                zero point moves when the session does.
*&   2. The ruler has a cost    -> two back-to-back reads are already a
*&                                non-zero interval. SAP's own example
*&                                measures an empty section and subtracts
*&                                it as an offset; so does this one.
*&   3. Documented vs observed  -> the doc promises microsecond
*&                                resolution; this probe prints the
*&                                smallest non-zero gap it can actually
*&                                see on YOUR system.
*&   4. Measuring real work     -> two ways of filling 20000 rows,
*&                                repeated and averaged, with the offset
*&                                from probe 2 subtracted. No winner is
*&                                asserted - the numbers are printed.
*&   5. The type i ceiling      -> the result is type i, so one session
*&                                clock runs out of range at max_int4
*&                                microseconds, about 2147 s. The doc
*&                                asks for sections not greater than
*&                                1000 s.
*&   6. CL_ABAP_RUNTIME         -> object timers run in PARALLEL and at
*&                                different precisions, which the
*&                                statement cannot do - but GET_RUNTIME
*&                                is documented as about two
*&                                microseconds slower per call, which
*&                                this probe measures.
*&   7. CLOCK RESOLUTION        -> deliberately NOT executed. Changing
*&                                the precision after the first
*&                                GET RUN TIME in an internal session is
*&                                a NON-HANDLEABLE exception
*&                                (SET_RUN_TIME_CLOCK_ERROR), so no
*&                                TRY/CATCH can rescue a library that
*&                                guesses wrong. See the commented block
*&                                in probe_clock_resolution.
*&   8. SET RUN TIME ANALYZER   -> sy-subrc is documented as ALWAYS 0,
*&                                so a successful call is not evidence
*&                                that anything is being traced. It only
*&                                has an effect when SAT is restricted
*&                                to Particular Units.
*&   9. Dividing the result     -> microseconds / 1000 gives DIFFERENT
*&                                answers depending on where it is
*&                                written. In an assignment the result
*&                                field counts towards the calculation
*&                                type; inside a string template it does
*&                                not, and the division is an integer
*&                                division that rounds.
*&  10. WAIT UP TO              -> the GET RUN TIME page says the
*&                                statement works "with respect to the
*&                                processor time"; the WAIT UP TO page
*&                                expects the same bracket around a
*&                                1-second WAIT to print about one
*&                                million microseconds. This probe
*&                                prints the real number so the reader
*&                                can settle it on their own kernel.
*&
*& Read-only: 0 SELECT, 0 UPDATE/INSERT/MODIFY/DELETE, 0 file access,
*& 0 RFC, 0 lock. NOTE that WAIT UP TO triggers a DATABASE COMMIT (see
*& probe 8) - harmless here because this program changes no data, but it
*& is the reason a WAIT must never be dropped into a measuring section
*& inside an LUW or between statements that open and close a database
*& cursor.
*&
*& Needs no DDIC objects and no demo data. All measured work is
*& in-memory.
*&
*& Doc: https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABAPGET_RUN_TIME.htm
*&      https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENCL_ABAP_RUNTIME.htm
*&      https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABAPSET_RUN_TIME_CLOCK_RESOLUTION.htm
*&      https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABAPSET_RUN_TIME_ANALYZER.htm
*&      https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABAPWAIT_UP_TO.htm
*&      https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENARITH_TYPE.htm
*&---------------------------------------------------------------------*
REPORT ydj_runtime_measure_demo.

CLASS lcl_measure DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS main.

  PRIVATE SECTION.

    " Mean cost of the measurement itself, in microseconds. Established
    " by probe_offset and subtracted from every later result.
    CLASS-DATA gv_offset TYPE p LENGTH 8 DECIMALS 2.

    CLASS-METHODS probe_first_call.
    CLASS-METHODS probe_offset.
    CLASS-METHODS probe_resolution.
    CLASS-METHODS probe_measure_work.
    CLASS-METHODS probe_value_range.
    CLASS-METHODS probe_class_timers.
    CLASS-METHODS probe_clock_resolution.
    CLASS-METHODS probe_analyzer.
    CLASS-METHODS probe_division.
    CLASS-METHODS probe_wait.

    CLASS-METHODS head
      IMPORTING iv_text TYPE string.

    CLASS-METHODS out_row
      IMPORTING iv_label TYPE string
                iv_value TYPE string.

ENDCLASS.

CLASS lcl_measure IMPLEMENTATION.

  METHOD main.

    " The ORDER MATTERS. probe_first_call must run before anything else
    " reads the clock, because the documented value 0 is only returned
    " by the FIRST GET RUN TIME after the internal session was created.
    probe_first_call( ).
    probe_offset( ).
    probe_resolution( ).
    probe_measure_work( ).
    probe_value_range( ).
    probe_class_timers( ).
    probe_clock_resolution( ).
    probe_analyzer( ).
    probe_division( ).

    " Last on purpose: WAIT UP TO triggers a database commit.
    probe_wait( ).

  ENDMETHOD.

  METHOD head.

    " Fixed-length target, NOT an offset/length access on a string -
    " c fields pad and truncate, while iv_text(60) would demand 60
    " characters and raise CX_SY_RANGE_OUT_OF_BOUNDS on a shorter text.
    DATA lv_text TYPE c LENGTH 72.

    lv_text = iv_text.
    SKIP.
    WRITE: / lv_text.

  ENDMETHOD.

  METHOD out_row.

    DATA lv_label TYPE c LENGTH 48.
    DATA lv_value TYPE c LENGTH 32.

    lv_label = iv_label.
    lv_value = iv_value.
    WRITE: / lv_label, lv_value.

  ENDMETHOD.

  METHOD probe_first_call.

    head( 'PROBE 1 - the first read of the clock' ).

    " Doc: "When GET RUN TIME is executed for the first time after an
    " internal session is created, the value 0 is passed to the variable
    " rtime." The inline form is explicitly allowed: "An inline
    " declaration DATA(var), where a variable of type i is declared."
    GET RUN TIME FIELD DATA(lv_t0).

    DATA(lv_txt) = |{ lv_t0 } microseconds|.
    out_row( iv_label = 'First GET RUN TIME in this session'
             iv_value = lv_txt ).

    " Not asserted as 0 - PRINTED. If it is not 0, then something else
    " in this internal session already read the clock, which is exactly
    " the condition that makes an absolute reading meaningless.
    IF lv_t0 = 0.
      out_row( iv_label = 'Interpretation'
               iv_value = 'fresh session clock' ).
    ELSE.
      out_row( iv_label = 'Interpretation'
               iv_value = 'clock already started' ).
    ENDIF.

  ENDMETHOD.

  METHOD probe_offset.

    DATA lv_sum  TYPE p LENGTH 8 DECIMALS 2.
    DATA lv_runs TYPE i VALUE 100.

    head( 'PROBE 2 - what the measurement itself costs' ).

    " SAP's own example for this statement measures "An empty program
    " segment for determining the offset of the runtime measurement"
    " and subtracts it. Two reads with nothing between them ARE that
    " empty segment.
    DO lv_runs TIMES.
      GET RUN TIME FIELD DATA(lv_a).
      GET RUN TIME FIELD DATA(lv_b).
      lv_sum = lv_sum + ( lv_b - lv_a ).
    ENDDO.

    gv_offset = lv_sum / lv_runs.

    DATA(lv_txt) = |{ gv_offset } microseconds|.
    out_row( iv_label = 'Mean offset over 100 empty sections'
             iv_value = lv_txt ).

  ENDMETHOD.

  METHOD probe_resolution.

    DATA lv_min   TYPE i VALUE 0.
    DATA lv_delta TYPE i.

    head( 'PROBE 3 - documented resolution vs observed resolution' ).

    " Doc: "The maximum resolution of the command GET RUN TIME is a
    " microsecond. Shorter measuring intervals cannot be determined
    " reliably." What the kernel actually delivers is a question for
    " the kernel, so this loop looks for the smallest non-zero gap it
    " can observe between two consecutive reads.
    DO 1000 TIMES.
      GET RUN TIME FIELD DATA(lv_c).
      GET RUN TIME FIELD DATA(lv_d).
      lv_delta = lv_d - lv_c.
      IF lv_delta > 0 AND ( lv_min = 0 OR lv_delta < lv_min ).
        lv_min = lv_delta.
      ENDIF.
    ENDDO.

    DATA(lv_txt) = |{ lv_min } microseconds|.
    out_row( iv_label = 'Smallest non-zero gap seen in 1000 tries'
             iv_value = lv_txt ).
    out_row( iv_label = 'Zero gaps mean'
             iv_value = 'section below resolution' ).

  ENDMETHOD.

  METHOD probe_measure_work.

    DATA lt_tab   TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    DATA lv_sum_a TYPE p LENGTH 8 DECIMALS 2.
    DATA lv_sum_b TYPE p LENGTH 8 DECIMALS 2.
    DATA lv_runs  TYPE i VALUE 5.
    DATA lv_rows  TYPE i VALUE 20000.
    DATA lv_mean_a TYPE p LENGTH 8 DECIMALS 2.
    DATA lv_mean_b TYPE p LENGTH 8 DECIMALS 2.

    head( 'PROBE 4 - measuring real work, offset subtracted' ).

    DO lv_runs TIMES.

      " CLEAR is deliberately OUTSIDE the brackets. Releasing the rows
      " of the previous run is not part of building the table, and
      " measuring it would attribute it to whichever variant ran second.
      CLEAR lt_tab.
      GET RUN TIME FIELD DATA(lv_e).
      DO lv_rows TIMES.
        APPEND sy-index TO lt_tab.
      ENDDO.
      GET RUN TIME FIELD DATA(lv_f).
      lv_sum_a = lv_sum_a + ( lv_f - lv_e ).

      CLEAR lt_tab.
      GET RUN TIME FIELD DATA(lv_g).
      lt_tab = VALUE #( FOR idx = 1 UNTIL idx > lv_rows ( idx ) ).
      GET RUN TIME FIELD DATA(lv_h).
      lv_sum_b = lv_sum_b + ( lv_h - lv_g ).

    ENDDO.

    lv_mean_a = lv_sum_a / lv_runs - gv_offset.
    lv_mean_b = lv_sum_b / lv_runs - gv_offset.

    DATA(lv_txt_a) = |{ lv_mean_a } microseconds|.
    DATA(lv_txt_b) = |{ lv_mean_b } microseconds|.

    out_row( iv_label = 'APPEND in a DO loop, 20000 rows, mean of 5'
             iv_value = lv_txt_a ).
    out_row( iv_label = 'VALUE #( FOR ... ), 20000 rows, mean of 5'
             iv_value = lv_txt_b ).

    " No winner is asserted here. Which of the two is faster depends on
    " the release, the kernel and the row type, and that is the point:
    " the note documents how to measure, not what the answer is.
    out_row( iv_label = 'Claim made about which is faster'
             iv_value = 'none - read your own output' ).

  ENDMETHOD.

  METHOD probe_value_range.

    DATA lv_secs TYPE decfloat34.

    head( 'PROBE 5 - where the clock runs out of range' ).

    " Doc: "The return value of the statement is of the data type i."
    " Type i is documented as "-2,147,483,648 to +2,147,483,647", and
    " the unit here is microseconds, so the usable span of one internal
    " session clock is that number divided by a million.
    DATA(lv_max) = cl_abap_math=>max_int4.

    " No CONV is needed here, and knowing WHY is the point of probe 9:
    " in an assignment, the data type of the RESULT FIELD is one of the
    " types that determine the calculation type. lv_secs is decfloat34,
    " so the division is a decimal floating point division even though
    " both operands are integers.
    lv_secs = lv_max / 1000000.

    DATA(lv_txt_max) = |{ lv_max } microseconds|.
    DATA(lv_txt_sec) = |{ lv_secs DECIMALS = 2 } seconds|.

    out_row( iv_label = 'cl_abap_math=>max_int4'
             iv_value = lv_txt_max ).
    out_row( iv_label = 'Usable span of one session clock'
             iv_value = lv_txt_sec ).
    out_row( iv_label = 'Largest section the doc recommends'
             iv_value = '1000 seconds' ).

  ENDMETHOD.

  METHOD probe_class_timers.

    DATA lv_hr_delta TYPE i.
    DATA lv_lr_delta TYPE i.
    DATA lv_acc      TYPE i.
    DATA lv_stmt     TYPE p LENGTH 8 DECIMALS 2.
    DATA lv_meth     TYPE p LENGTH 8 DECIMALS 2.

    head( 'PROBE 6 - two object timers, running at once' ).

    " Doc: in contrast to the statement, "these objects can be used to
    " perform different measurements with different levels of precision
    " and parallel measurements for each internal session".
    DATA(lo_hr) = cl_abap_runtime=>create_hr_timer( ).
    DATA(lo_lr) = cl_abap_runtime=>create_lr_timer( ).

    DATA(lv_hr1) = lo_hr->get_runtime( ).
    DATA(lv_lr1) = lo_lr->get_runtime( ).

    DO 200000 TIMES.
      lv_acc = lv_acc + 1.
    ENDDO.

    DATA(lv_lr2) = lo_lr->get_runtime( ).
    DATA(lv_hr2) = lo_hr->get_runtime( ).

    lv_hr_delta = lv_hr2 - lv_hr1.
    lv_lr_delta = lv_lr2 - lv_lr1.

    DATA(lv_txt_hr) = |{ lv_hr_delta } microseconds|.
    DATA(lv_txt_lr) = |{ lv_lr_delta } microseconds|.

    out_row( iv_label = 'Same section, CREATE_HR_TIMER'
             iv_value = lv_txt_hr ).
    out_row( iv_label = 'Same section, CREATE_LR_TIMER'
             iv_value = lv_txt_lr ).

    " Doc: "the execution of the method GET_RUNTIME is approximately two
    " microseconds slower than the execution of the statement
    " GET RUN TIME". Measured here rather than repeated as a fact.
    " lv_tmp and lv_tmp2 are written and never read on purpose: what is
    " being measured is the cost of READING the clock, so the values
    " themselves are the one part of this that does not matter.
    GET RUN TIME FIELD DATA(lv_s1).
    DO 1000 TIMES.
      GET RUN TIME FIELD DATA(lv_tmp).
    ENDDO.
    GET RUN TIME FIELD DATA(lv_s2).
    lv_stmt = ( lv_s2 - lv_s1 ) / 1000.

    DATA(lv_tmp2) = lo_hr->get_runtime( ).
    GET RUN TIME FIELD DATA(lv_m1).
    DO 1000 TIMES.
      lv_tmp2 = lo_hr->get_runtime( ).
    ENDDO.
    GET RUN TIME FIELD DATA(lv_m2).
    lv_meth = ( lv_m2 - lv_m1 ) / 1000.

    " lv_stmt and lv_meth are p with 2 decimals, and the result field
    " counts towards the calculation type, so these divisions keep their
    " decimal places. Inside a string template they would not - probe 9.
    DATA(lv_txt_stmt) = |{ lv_stmt } microseconds per call|.
    DATA(lv_txt_meth) = |{ lv_meth } microseconds per call|.

    out_row( iv_label = 'GET RUN TIME statement, 1000 calls'
             iv_value = lv_txt_stmt ).
    out_row( iv_label = 'GET_RUNTIME method, 1000 calls'
             iv_value = lv_txt_meth ).

  ENDMETHOD.

  METHOD probe_clock_resolution.

    head( 'PROBE 7 - the resolution switch, deliberately not executed' ).

    " NOTHING IS EXECUTED IN THIS METHOD, ON PURPOSE.
    "
    " SET RUN TIME CLOCK RESOLUTION { HIGH | LOW } "can be changed in a
    " program only before the statement GET RUN TIME is executed for the
    " first time, otherwise a non-handleable exception is raised" -
    " runtime error SET_RUN_TIME_CLOCK_ERROR. Non-handleable means no
    " TRY/CATCH anywhere up the stack can contain it: the program dumps.
    "
    " By the time this method runs, probes 1 to 6 have read the clock
    " many times, so the statement below would be a precision CHANGE in
    " this internal session and would short-dump the whole demo:
    "
    "   SET RUN TIME CLOCK RESOLUTION LOW.
    "
    " The quiet half of the rule is that the same statement is sometimes
    " a harmless no-op: "No exception is raised if SET RUN TIME CLOCK
    " RESOLUTION is used after the statement GET RUN TIME as long as the
    " level of precision is not changed." HIGH is the implicit default,
    " so whether this line dumps depends entirely on what ELSE ran
    " earlier in the same internal session - which is not a property of
    " your own code.
    "
    " That is why a reusable measurement helper should use
    " CL_ABAP_RUNTIME, where the precision is a property of the timer
    " object instead of a one-shot setting for the whole session.
    out_row( iv_label = 'SET RUN TIME CLOCK RESOLUTION'
             iv_value = 'not executed - see comment' ).
    out_row( iv_label = 'Why'
             iv_value = 'change after a read dumps' ).

  ENDMETHOD.

  METHOD probe_analyzer.

    DATA lv_acc TYPE i.

    head( 'PROBE 8 - SET RUN TIME ANALYZER tells you nothing' ).

    SET RUN TIME ANALYZER ON.
    DO 10 TIMES.
      lv_acc = lv_acc + sy-index.
    ENDDO.
    SET RUN TIME ANALYZER OFF.

    DATA(lv_txt) = |sy-subrc = { sy-subrc }|.
    DATA(lv_sum) = |sum = { lv_acc }|.

    " Doc: "The statement SET RUN TIME ANALYZER always sets the return
    " code sy-subrc to 0." So the 0 below is not feedback - it is the
    " same 0 you get on a system where nothing is being traced at all.
    out_row( iv_label = 'After SET RUN TIME ANALYZER OFF'
             iv_value = lv_txt ).
    out_row( iv_label = 'Traced section result'
             iv_value = lv_sum ).
    out_row( iv_label = 'Effect without SAT Particular Units'
             iv_value = 'none' ).

  ENDMETHOD.

  METHOD probe_division.

    DATA lv_acc  TYPE i.
    DATA lv_us   TYPE i.
    DATA lv_ms_p TYPE p LENGTH 8 DECIMALS 3.

    head( 'PROBE 9 - the same division, two different answers' ).

    GET RUN TIME FIELD DATA(lv_d1).
    DO 50000 TIMES.
      lv_acc = lv_acc + 1.
    ENDDO.
    GET RUN TIME FIELD DATA(lv_d2).

    lv_us = lv_d2 - lv_d1.

    " (1) Assignment: "the data types of all operands of the full
    " arithmetic expressions, and the data type of the result field
    " result" are involved, so a p result field makes this a p
    " division and the decimals survive.
    lv_ms_p = lv_us / 1000.

    " (2) The SAME division embedded in a string template. There, "only
    " the operands of the expression are evaluated" - the target plays
    " no part - so two integer operands give calculation type i, and an
    " integer division in ABAP is "rounded commercially", not
    " truncated. A sub-millisecond interval therefore prints as 0 or 1.
    DATA(lv_txt_tpl) = |{ lv_us / 1000 } ms|.
    DATA(lv_txt_p)   = |{ lv_ms_p } ms|.
    DATA(lv_txt_us)  = |{ lv_us } microseconds|.

    out_row( iv_label = 'Interval measured'
             iv_value = lv_txt_us ).
    out_row( iv_label = 'Divided into a p result field'
             iv_value = lv_txt_p ).
    out_row( iv_label = 'Same division inside | { } |'
             iv_value = lv_txt_tpl ).

  ENDMETHOD.

  METHOD probe_wait.

    DATA lv_delta TYPE i.

    head( 'PROBE 10 - processor time or elapsed time?' ).

    " The GET RUN TIME page says the statement "defines actual points in
    " time with respect to the processor time". The WAIT UP TO page
    " brackets a 1-second WAIT with the same two statements and says:
    " "The output of the following example should correspond to
    " approximately one million microseconds."
    "
    " Both cannot be read loosely at the same time, so this probe prints
    " the real number instead of choosing a side.
    "
    " WARNING, and the reason this probe runs last: "Each time this
    " variant of the statement WAIT is used, a database commit is
    " triggered (except in updates)."
    GET RUN TIME FIELD DATA(lv_w1).
    WAIT UP TO 1 SECONDS.
    GET RUN TIME FIELD DATA(lv_w2).

    lv_delta = lv_w2 - lv_w1.

    DATA(lv_txt) = |{ lv_delta } microseconds|.
    out_row( iv_label = 'Measured across WAIT UP TO 1 SECONDS'
             iv_value = lv_txt ).
    out_row( iv_label = 'Doc expects approximately'
             iv_value = '1000000 microseconds' ).

  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.

  lcl_measure=>main( ).
