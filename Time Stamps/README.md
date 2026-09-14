# Time Stamps & Time Zones — the packed number that is not a number, and the hour that happens twice

A `TIMESTAMP` field looks like a number, prints like a number, and lets you do
arithmetic on it like a number. It is none of those things. Meanwhile `sy-datum`
looks like "today" and is not — it is today in the *system* time zone, which on a
global system is somebody else's today.

Every trap below compiles cleanly, passes the extended program check, and produces
wrong data at runtime.

## 0. There are two completely different time stamp representations

| | Packed number (classic) | Time stamp field (7.54+) |
|---|---|---|
| Type | `TIMESTAMP` = `p` len 8, `TIMESTAMPL` = `p` len 11 dec 7 | built-in `utclong` |
| Looks like | `20260914113000` | `2026-09-14 11:30:00.0000000` |
| Get current | `GET TIME STAMP FIELD ts.` | `ts = utclong_current( ).` |
| Add seconds | `cl_abap_tstmp=>add( )` | `utclong_add( )` |
| Difference | `cl_abap_tstmp=>subtract( )` | `utclong_diff( )` |
| To local date/time | `CONVERT TIME STAMP` | `CONVERT UTCLONG` |
| From local date/time | `CONVERT INTO TIME STAMP` | `CONVERT INTO UTCLONG` |
| Resolution | 1 s / 100 ns | 100 ns |

> "In new programs, it is recommended that UTC time stamps in time stamp fields are
> used." — [Time Stamps](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENTIME_STAMPS.html)

You will still meet the packed form constantly, because every existing DDIC table,
BAPI and RFC interface uses it. `CL_ABAP_TSTMP=>UTCLONG2TSTMP( )` and
`TSTMP2UTCLONG( )` bridge the two — that is exactly what they exist for.

## 1. Arithmetic on a packed time stamp is arithmetic on a decimal number

This is the headline, and it is the single most common time stamp bug in ABAP.

```abap
GET TIME STAMP FIELD DATA(ts).

" WRONG - the value is not a number of seconds
ts = ts + 86400 * 2 + 3600 * 3.
```

`20161004131906` is not "a count of seconds since something". It is the *digits*
`yyyymmddhhmmss` packed into a number. Adding 3600 adds 3600 to the last digits, so
you can produce `20161004315506` — hour 31, minute 55, second 06. Not a time. Not an
error, either: no syntax warning, no runtime dump, no `sy-subrc`. The value simply
becomes invalid, and blows up later, somewhere else, in someone else's code.

The keyword documentation spells out both halves:

> "Direct calculation using UTC time stamps in packed numbers. If, for example,
> `ts1` has the value *20161004130733*, adding 3600 s in `ts2` produces the value
> *20161004140733*. Since the time stamps are interpreted as numbers of type `p` in
> the calculation, the result is `10000`, which would generally be unexpected."
> — [Time Stamps in Packed Numbers](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENTIME_STAMPS_PACKED.html)

So even a *correctly* shifted pair of time stamps gives a nonsense difference when
you subtract them with `-`. One hour apart reads as 10000.

```abap
" RIGHT - packed form
DATA(ts_later) = cl_abap_tstmp=>add( tstmp = ts
                                     secs  = 86400 * 2 + 3600 * 3 ).
DATA(secs)     = cl_abap_tstmp=>subtract( tstmp1 = ts_later
                                          tstmp2 = ts ).      " real seconds

" RIGHT - utclong form
DATA(u_later) = utclong_add( val = utclong_current( ) days = 2 hours = 3 ).
DATA(u_secs)  = utclong_diff( high = u_later low = utclong_current( ) ).
```

Two naming traps in `CL_ABAP_TSTMP` itself: the method that subtracts two *time
stamps* is `SUBTRACT`; `TD_SUBTRACT` is the "time/date" variant and takes four
parameters (`date1`, `time1`, `date2`, `time2`), not two time stamps. And `SUBTRACT`
returns `TZNTSTMPL` — a *packed* number of seconds with seven decimal places, not an
`i` — so assigning it straight into an integer variable rounds the fractional seconds
away without comment.

Note what `utclong_add` does *not* offer: `years` and `months`. That is deliberate —
they are not a fixed number of seconds. And there is no `utclong_subtract`; pass
negative numbers instead.

**The only safe direct operation on packed time stamps is comparison**, and even
that only between two stamps of the same form. Comparing a `TIMESTAMP` against a
`TIMESTAMPL` is only meaningful if the program has *fixed point arithmetic* switched
on; otherwise use `CL_ABAP_TSTMP` for the comparison too.

## 2. Assigning TIMESTAMPL to TIMESTAMP rounds — and can round to second 60

The short form is the integer part of the long form, so the obvious assignment looks
free:

```abap
DATA: ts_long  TYPE timestampl,
      ts_short TYPE timestamp.
ts_short = ts_long.        " p -> p conversion: COMMERCIAL ROUNDING
```

`20260914115959.7` rounds *up* to `20260914116000`. Second 60. An invalid time
stamp, created by an assignment that has no way to report a problem.

The `CL_ABAP_TSTMP` methods come in pairs precisely for this:

| Want | Method |
|---|---|
| Long → short, valid values, commercial rounding | `MOVE_TO_SHORT` |
| Long → short, valid values, **keep the integer part** | `MOVE_TO_SHORT_TRUNC` |
| Add seconds → short form | `ADD_TO_SHORT` / `ADD_TO_SHORT_TRUNC` |
| Subtract seconds → short form | `SUBTRACTSECS_TO_SHORT` / `..._TRUNC` |

> "`ADD_TO_SHORT` and `ADD_TO_SHORT_TRUNC` round commercially.
> `SUBTRACTSECS_TO_SHORT` and `SUBTRACTSECS_TO_SHORT_TRUNC` round down."
> — [System Class for Time Stamps in Packed Numbers](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCL_ABAP_TSTMP.html)

If you want the same wall-clock second you started with, you want a `_TRUNC` method
(or `trunc( )` on the value, which works on every release — the `_TRUNC` methods are
a later addition, so check they exist in your system before using them). If you want
nearest, you want the plain one. Picking by accident is the bug.

## 3. The double hour: one local time, two real instants

This is where `DAYLIGHT SAVING TIME` earns its keyword.

When a time zone leaves daylight saving time, the same local wall-clock hour occurs
twice. In `EST` in 2019, local `2019-11-03 01:30:00` is *both* `05:30 UTC` and
`06:30 UTC`. A local date + time is therefore **not** a unique point in time, and no
amount of careful coding makes it one.

```abap
CONVERT DATE dat TIME tim DAYLIGHT SAVING TIME 'X'
        TIME ZONE 'EST' INTO UTCLONG DATA(ts_dst).   " 05:30 UTC
CONVERT DATE dat TIME tim DAYLIGHT SAVING TIME ' '
        TIME ZONE 'EST' INTO UTCLONG DATA(ts_std).   " 06:30 UTC
```

Omitting the addition is not neutral — it silently picks one:

> "In the double hour that is caused by switching from daylight saving time to
> standard time, `tim` and `dat` are interpreted as a time specification in daylight
> saving time and `dst` is set to the value *X*."
> — [CONVERT INTO UTCLONG](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCONVERT_DATE_UTCLONG.html)

The mirror case is worse, because it *fails*. In spring an hour does not exist at
all. Converting a local time inside that gap gives `sy-subrc = 12` (packed form) or
raises `CX_SY_CONVERSION_NO_DATE_TIME` (`utclong` form). If your code stores local
dates and times and converts them later, one night a year some of your records
become unconvertible. Store the UTC time stamp instead.

The reverse direction (`CONVERT TIME STAMP` / `CONVERT UTCLONG`) is always unique —
that is the whole point of keeping UTC — and returns the `dst` flag so you can tell
the two local 01:30s apart when you display them.

## 4. `CONVERT TIME STAMP` reports failure in `sy-subrc`, `CONVERT UTCLONG` throws

Same job, two entirely different error channels. Code written for one form and then
"modernised" to the other loses its error handling in the process.

| `sy-subrc` after `CONVERT TIME STAMP` / `CONVERT INTO TIME STAMP` | Meaning |
|---|---|
| 0 | Converted using the specified time zone |
| 4 | **Time zone was initial** — no shift applied, values are UTC |
| 8 | Time zone not found in `TTZZ` |
| 12 | Invalid time stamp, invalid date/time, or inconsistent `dst` |

Two things worth pinning down:

- **`sy-subrc = 4` is not success.** You asked for a local time, you got UTC back,
  and the only difference is a return code most code never checks.
- **An initial packed time stamp (value 0) is not valid** and gives `sy-subrc = 12`,
  leaving the target fields *unchanged* — not cleared. Whatever was in `dat` and
  `tim` before is still there and now looks like a converted result.

The `utclong` statements behave in the opposite way: `CONVERT UTCLONG` and
`CONVERT INTO UTCLONG` **do not set `sy-subrc` at all**. They raise
`CX_SY_CONVERSION_NO_DATE_TIME` (and friends) instead. A bare
`IF sy-subrc = 0` after `CONVERT INTO UTCLONG` is testing a leftover value from some
earlier statement.

One asymmetry to know: an initial `utclong` produces initial results in all target
fields rather than an exception, and in *comparisons* it sorts below every real time
stamp — but passed to `utclong_add` or `utclong_diff` it is treated as the *smallest
valid* time stamp, not as "no value". `utclong_add` can therefore never return the
initial value: it returns a valid time stamp or raises `CX_SY_ARITHMETIC_OVERFLOW`.

## 5. `sy-datum` is not "today", and `sy-uzeit` is not "now, here"

| Field | What it actually is |
|---|---|
| `sy-datum`, `sy-uzeit` | System date/time — the **system time zone** of the AS instance |
| `sy-datlo`, `sy-timlo` | User date/time — the **user's** time zone (`SU3` / user master) |
| `sy-zonlo` | The user time zone; **initial if the user has none maintained** |
| `sy-tzone` | System offset from UTC in seconds, **ignoring daylight saving time** |
| `sy-dayst` | `X` if the system time zone is currently in daylight saving time |

Two consequences that bite in practice:

- Stamping a record with `sy-datum`/`sy-uzeit` and displaying it with `sy-datlo`
  silently shifts every value by the offset between the two zones. On a single-zone
  system the two agree and the bug is invisible — it appears the day the first user
  in another country logs in.
- `sy-zonlo` is *empty* when the user has no time zone maintained, and then
  `sy-datlo`/`sy-timlo` simply mirror `sy-datum`/`sy-uzeit`. So "it works for me" is
  not evidence of anything.

`sy-tzone` deliberately excludes DST, which makes it useless as a general conversion
offset. Use `CONVERT`, not arithmetic on `sy-tzone`.

These fields are refreshed when the program starts, when a dynpro screen is sent,
and when the internal session changes — **not** continuously. In a long-running
background job `sy-uzeit` can be hours stale. `GET TIME` refreshes `sy-datum`,
`sy-uzeit`, `sy-datlo` and `sy-timlo`; it does not refresh `sy-zonlo`, `sy-tzone`,
`sy-dayst` or `sy-fdayw`.

## 6. Formatting: a bare time stamp in a string template is unreadable

A packed time stamp in a string template is formatted as a *number* unless you say
otherwise:

```abap
WRITE / |{ ts }|.                      " 20.260.914.113.000  (a number)
WRITE / |{ ts TIMESTAMP = ISO }|.      " 2026-09-14T11:30:00
WRITE / |{ ts TIMESTAMP = ISO TIMEZONE = 'INDIA' }|.   " shifted to local
```

`utclong` fields format sensibly by default, which is another quiet argument for the
newer type. For a string a machine will parse, `CL_ABAP_UTCLONG=>WRITE_ISO_FORMAT_WITH_OFFSET( )`
produces real ISO-8601 with an offset suffix, and `READ_ISO_FORMAT( )` reads it back.

## Quick reference

| Want | Packed (`TIMESTAMP`) | `utclong` |
|---|---|---|
| Now | `GET TIME STAMP FIELD ts.` | `utclong_current( )` |
| Add / subtract seconds | `cl_abap_tstmp=>add( )` / `subtractsecs( )` | `utclong_add( seconds = ±n )` |
| Difference in seconds | `cl_abap_tstmp=>subtract( )` | `utclong_diff( high = low = )` |
| Difference split d/h/m/s | — | `cl_abap_utclong=>diff( )` |
| Repair an invalid value | `cl_abap_tstmp=>normalize( )` | (cannot be invalid) |
| Convert between the two forms | `cl_abap_tstmp=>utclong2tstmp( )` | `cl_abap_tstmp=>tstmp2utclong( )` |
| Error channel | `sy-subrc` (0/4/8/12) | exceptions |
| Never do | `ts + n`, `ts1 - ts2`, `ts_short = ts_long` | — |

## Sources

- [ABAP keyword documentation — Time Stamps](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENTIME_STAMPS.html)
- [ABAP keyword documentation — Time Stamps in Packed Numbers](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENTIME_STAMPS_PACKED.html)
- [ABAP keyword documentation — Time Stamp Fields with Time Stamp Type (`utclong`)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENUTCLONG.html)
- [ABAP keyword documentation — CL_ABAP_TSTMP](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCL_ABAP_TSTMP.html)
- [ABAP keyword documentation — CL_ABAP_UTCLONG](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENTIMESTAMP_SYSTEM_CLASS.html)
- [ABAP keyword documentation — CONVERT TIME STAMP](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCONVERT_TIME-STAMP.html)
- [ABAP keyword documentation — CONVERT INTO TIME STAMP](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCONVERT_DATE_TIME-STAMP.html)
- [ABAP keyword documentation — CONVERT UTCLONG](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCONVERT_UTCLONG.html)
- [ABAP keyword documentation — CONVERT INTO UTCLONG](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCONVERT_DATE_UTCLONG.html)
- [ABAP keyword documentation — utclong_add](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENUTCLONG_ADD.html)
- [ABAP keyword documentation — utclong_diff](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENUTCLONG_DIFF.html)
- [ABAP keyword documentation — System Fields for Date and Time](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENTIME_SYSTEM_FIELDS.html)
