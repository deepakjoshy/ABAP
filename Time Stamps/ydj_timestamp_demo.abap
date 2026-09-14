*&---------------------------------------------------------------------*
*& Report YDJ_TIMESTAMP_DEMO
*&---------------------------------------------------------------------*
*& Time stamps and time zones: the traps that compile cleanly.
*&
*&   1. PACKED ARITHMETIC -> a TIMESTAMP is yyyymmddhhmmss packed into a
*&                           number, NOT a second count. ts + 3600 and
*&                           ts1 - ts2 both produce nonsense, silently.
*&   2. ROUNDING          -> TIMESTAMPL -> TIMESTAMP is a p-to-p
*&                           assignment, so it rounds commercially and
*&                           can produce second 60.
*&   3. DOUBLE HOUR       -> one local wall-clock time in the DST
*&                           changeover hour maps to TWO UTC instants.
*&                           Omitting DAYLIGHT SAVING TIME picks one.
*&   4. ERROR CHANNELS    -> CONVERT TIME STAMP reports via sy-subrc
*&                           (and 4 is NOT success); CONVERT UTCLONG
*&                           does not set sy-subrc at all, it throws.
*&   5. SYSTEM FIELDS     -> sy-datum is the SYSTEM time zone,
*&                           sy-datlo is the USER time zone.
*&
*& Self-contained apart from the time zone entries in TTZZ, which exist
*& in every AS ABAP system. Requires 7.54+ for the utclong parts.
*&---------------------------------------------------------------------*
REPORT ydj_timestamp_demo.

PARAMETERS: p_tz TYPE timezone OBLIGATORY DEFAULT 'EST'.


CLASS lcl_tstmp_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS execute
      IMPORTING iv_tz TYPE timezone.

  PRIVATE SECTION.

    " 1. The packed form is not a number of seconds
    CLASS-METHODS packed_arithmetic_lies.

    " 2. Long -> short assignment rounds, and can round to second 60
    CLASS-METHODS long_to_short_rounds.

    " 3. The same local time exists twice, and once not at all
    CLASS-METHODS double_hour
      IMPORTING iv_tz TYPE timezone.

    " 4. sy-subrc = 4 means "no conversion happened"
    CLASS-METHODS convert_error_channels
      IMPORTING iv_tz TYPE timezone.

    " 5. System time zone vs user time zone
    CLASS-METHODS system_vs_user_fields.

ENDCLASS.


CLASS lcl_tstmp_demo IMPLEMENTATION.

  METHOD execute.
    packed_arithmetic_lies( ).
    long_to_short_rounds( ).
    double_hour( iv_tz ).
    convert_error_channels( iv_tz ).
    system_vs_user_fields( ).
  ENDMETHOD.


  METHOD packed_arithmetic_lies.

    ULINE.
    WRITE: / '1. Arithmetic on a packed TIMESTAMP'.
    SKIP.

    " A fixed value so the output is reproducible: 2016-10-04 13:07:33 UTC
    DATA(lv_ts) = CONV timestamp( '20161004130733' ).

    " WRONG: the digits are shifted, not the point in time
    DATA(lv_wrong) = lv_ts.
    lv_wrong = lv_wrong + 3600.

    " RIGHT: the class knows these digits are a date and a time
    DATA(lv_right) = cl_abap_tstmp=>add( tstmp = lv_ts
                                         secs  = 3600 ).

    WRITE: / 'start           :', (14) lv_ts,
           / 'ts + 3600       :', (14) lv_wrong, '<- 3600 added to the DIGITS',
           / 'tstmp=>add 3600 :', (14) lv_right, '<- one hour later'.
    SKIP.

    " And the same trap in reverse: plain subtraction of two valid
    " stamps one hour apart does NOT give 3600.
    DATA(lv_naive_diff) = lv_right - lv_ts.
    DATA(lv_real_diff)  = cl_abap_tstmp=>subtract( tstmp1 = lv_right
                                                   tstmp2 = lv_ts ).

    WRITE: / 'ts2 - ts1       :', lv_naive_diff, '<- meaningless',
           / 'tstmp=>subtract :', lv_real_diff,  '<- seconds'.
    SKIP.

    " Adding "two days and three hours" the naive way can produce an
    " hour of 31 - an invalid stamp, created without any error at all.
    DATA(lv_broken) = lv_ts.
    lv_broken = lv_broken + 86400 * 2 + 3600 * 3.
    WRITE: / 'ts + 2d3h naive :', (14) lv_broken, '<- not a valid time stamp'.

    " NORMALIZE repairs an out-of-range value into a real time stamp.
    DATA(lv_fixed) = cl_abap_tstmp=>normalize( tstmp_in = lv_broken ).
    WRITE: / 'after normalize :', (21) lv_fixed, '<- returns the LONG form'.
    SKIP.

  ENDMETHOD.


  METHOD long_to_short_rounds.

    ULINE.
    WRITE: / '2. TIMESTAMPL -> TIMESTAMP rounds commercially'.
    SKIP.

    " 2026-09-14 11:59:59.7 - note the fraction above .5
    DATA(lv_long) = CONV timestampl( '20260914115959.7000000' ).

    " Plain assignment: p -> p conversion rule, so it ROUNDS UP.
    DATA lv_short_assigned TYPE timestamp.
    lv_short_assigned = lv_long.

    " Same rounding, but through a method that guards validity
    DATA(lv_short_move) = cl_abap_tstmp=>move_to_short( tstmp_src = lv_long ).

    " Truncating: keep the integer part, which is what you almost always
    " actually meant. Newer releases also offer MOVE_TO_SHORT_TRUNC,
    " ADD_TO_SHORT_TRUNC and SUBTRACTSECS_TO_SHORT_TRUNC for this.
    DATA lv_short_trunc TYPE timestamp.
    lv_short_trunc = trunc( lv_long ).

    WRITE: / 'long value      :', (21) lv_long,
           / 'plain assignment:', (14) lv_short_assigned, '<- second 60!',
           / 'move_to_short   :', (14) lv_short_move,     '<- same rounding',
           / 'trunc( )        :', (14) lv_short_trunc,    '<- integer part kept'.
    SKIP.

  ENDMETHOD.


  METHOD double_hour.

    ULINE.
    WRITE: / '3. The double hour -', iv_tz.
    SKIP.

    " In EST, 2019-11-03 01:30 local occurred twice: 05:30 and 06:30 UTC.
    DATA(lv_date) = CONV d( '20191103' ).
    DATA(lv_time) = CONV t( '013000' ).

    CONVERT DATE lv_date TIME lv_time
            DAYLIGHT SAVING TIME 'X'
            INTO TIME STAMP DATA(lv_ts_dst) TIME ZONE iv_tz.
    DATA(lv_subrc_dst) = sy-subrc.

    CONVERT DATE lv_date TIME lv_time
            DAYLIGHT SAVING TIME ' '
            INTO TIME STAMP DATA(lv_ts_std) TIME ZONE iv_tz.
    DATA(lv_subrc_std) = sy-subrc.

    " No DAYLIGHT SAVING TIME addition: the system picks daylight saving
    " time in the double hour. It does not warn you that it chose.
    CONVERT DATE lv_date TIME lv_time
            INTO TIME STAMP DATA(lv_ts_default) TIME ZONE iv_tz.
    DATA(lv_subrc_def) = sy-subrc.

    WRITE: / 'local           :', lv_date, lv_time, '(', iv_tz, ')',
           / 'DST = X         :', (14) lv_ts_dst,     'subrc', lv_subrc_dst,
           / 'DST = blank     :', (14) lv_ts_std,     'subrc', lv_subrc_std,
           / 'no DST addition :', (14) lv_ts_default, 'subrc', lv_subrc_def.
    SKIP.

    IF lv_ts_dst <> lv_ts_std AND lv_subrc_dst = 0 AND lv_subrc_std = 0.
      WRITE: / 'One local time, two real instants - a local date+time is',
             / 'not a point in time. Store the UTC time stamp instead.'.
    ELSE.
      WRITE: / 'This time zone has no DST rule for that date - try EST or CET.'.
    ENDIF.
    SKIP.

    " The spring gap: the hour that never happened. Converting a local
    " time inside it fails outright.
    CONVERT DATE CONV d( '20190310' ) TIME CONV t( '023000' )
            INTO TIME STAMP DATA(lv_ts_gap) TIME ZONE iv_tz.
    WRITE: / 'gap 2019-03-10 02:30 ->', (14) lv_ts_gap,
             'subrc', sy-subrc, '( 12 = no such local time )'.
    SKIP.

  ENDMETHOD.


  METHOD convert_error_channels.

    ULINE.
    WRITE: / '4. sy-subrc after CONVERT TIME STAMP'.
    SKIP.

    DATA(lv_ts) = CONV timestamp( '20260914113000' ).

    " subrc 0 - converted into the requested zone
    CONVERT TIME STAMP lv_ts TIME ZONE iv_tz
            INTO DATE DATA(lv_d0) TIME DATA(lv_t0)
            DAYLIGHT SAVING TIME DATA(lv_dst0).
    WRITE: / 'zone', iv_tz, ':', lv_d0, lv_t0, 'dst', lv_dst0,
             'subrc', sy-subrc.

    " subrc 4 - EMPTY time zone. No shift happened. This is NOT success,
    " and the values you get back are plain UTC.
    DATA lv_empty_tz TYPE timezone.
    CONVERT TIME STAMP lv_ts TIME ZONE lv_empty_tz
            INTO DATE DATA(lv_d4) TIME DATA(lv_t4).
    WRITE: / 'empty zone   :', lv_d4, lv_t4,
             'subrc', sy-subrc, '<- 4: values are UTC, not local'.

    " subrc 8 - the zone is not in TTZZ
    CONVERT TIME STAMP lv_ts TIME ZONE 'NOZONE'
            INTO DATE DATA(lv_d8) TIME DATA(lv_t8).
    WRITE: / 'bogus zone   :', lv_d8, lv_t8,
             'subrc', sy-subrc, '<- 8: targets UNCHANGED'.

    " subrc 12 - an initial packed value is not a valid time stamp.
    " Note the targets keep whatever they held before the statement.
    DATA lv_initial TYPE timestamp.
    DATA(lv_d12) = CONV d( '19991231' ).
    DATA(lv_t12) = CONV t( '235959' ).
    CONVERT TIME STAMP lv_initial TIME ZONE iv_tz
            INTO DATE lv_d12 TIME lv_t12.
    WRITE: / 'initial stamp:', lv_d12, lv_t12,
             'subrc', sy-subrc, '<- 12: stale values still there'.
    SKIP.

    " The utclong statements use exceptions instead. sy-subrc is never
    " set here, so testing it after CONVERT INTO UTCLONG is meaningless.
    TRY.
        CONVERT DATE CONV d( '20260914' ) TIME CONV t( '113000' )
                TIME ZONE 'NOZONE'
                INTO UTCLONG DATA(lv_u).
        WRITE: / 'utclong      :', lv_u.
      CATCH cx_sy_conversion_no_date_time INTO DATA(lo_err).
        WRITE: / 'CONVERT INTO UTCLONG raised:', lo_err->get_text( ).
    ENDTRY.
    SKIP.

  ENDMETHOD.


  METHOD system_vs_user_fields.

    ULINE.
    WRITE: / '5. System time zone vs user time zone'.
    SKIP.

    DATA lv_system_tz TYPE timezone.
    CALL FUNCTION 'GET_SYSTEM_TIMEZONE'
      IMPORTING
        timezone = lv_system_tz.

    WRITE: / 'sy-datum / sy-uzeit :', sy-datum, sy-uzeit, '(system zone',
             lv_system_tz, ')',
           / 'sy-datlo / sy-timlo :', sy-datlo, sy-timlo, '(user zone',
             sy-zonlo, ')',
           / 'sy-tzone (s, no DST):', sy-tzone,
           / 'sy-dayst            :', sy-dayst.
    SKIP.

    IF sy-zonlo IS INITIAL.
      WRITE: / 'No user time zone maintained, so sy-datlo/sy-timlo just',
             / 'mirror sy-datum/sy-uzeit. Mixing the two pairs looks',
             / 'correct on this system and breaks for users elsewhere.'.
    ELSEIF sy-zonlo = lv_system_tz.
      WRITE: / 'User zone = system zone, so both pairs agree here.',
             / 'That is exactly when the bug stays invisible.'.
    ELSE.
      WRITE: / 'User zone differs from the system zone - stamping with',
             / 'sy-datum and displaying with sy-datlo shifts every value.'.
    ENDIF.
    SKIP.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_tstmp_demo=>execute( p_tz ).
