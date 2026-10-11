# Date & Time Functions in ABAP SQL — the empty date that becomes 0001-01-01, the validity test that disagrees with itself, and the failure mode chosen by the column type

Pushing date arithmetic down to the database is normally the right call: one
statement instead of a `LOOP`, no transport of rows that get thrown away, an
aggregate over an interval the database can filter on. ABAP SQL and ABAP CDS
provide a whole family of functions for it — `DATS_ADD_DAYS`,
`DATS_DAYS_BETWEEN`, `EXTRACT_YEAR`, `DAYNAME`, `TSTMP_TO_DATS`, `UTCL_CURRENT`.

The functions work. What is worth knowing before you use them on real master
data is how they treat a date that is **not a date** — because business data is
full of those, and the family is not of one mind about them:

- the **initial** date `00000000` is *not* a valid date, but the initial **time**
  `000000` *is* a valid time, and the two validity functions say so in the same
  `INT4` column;
- the `DATS_*` calculations do not report an invalid date at all — they quietly
  replace it with `00010101` and return a plausible-looking answer about two
  thousand years wide;
- the same overflow raises a catchable exception in the `DATN_*` and `UTCLONG`
  forms and silently resets to the initial value in the `DATS` forms — **the
  dictionary type of the column decides whether bad arithmetic is loud**;
- `EXTRACT_YEAR` of an empty date is `1`, `EXTRACT_HOUR` of an empty time is `0`,
  and both dump on a non-initial invalid value;
- adding a month and subtracting it again does not get you back where you were;
- there are two "current time stamp" functions and only one of them is stable
  within a single statement;
- and adding any of these functions to an existing `SELECT` can raise the strict
  mode of the syntax check for the **whole statement**, which is how an unrelated
  line stops compiling.

Everything below is quoted from the ABAP keyword documentation. The runnable
counterpart is `ydj_sql_date_time_demo.abap` in this folder: read-only, no
`COMMIT`, and it prints the actual numbers rather than asserting them.

## 0. Six types, four function families, two engines

The date/time story has more types than it looks like from ABAP, where there is
just `d`, `t` and `utclong`. In the dictionary:

| Dictionary type | Holds | ABAP side |
|---|---|---|
| `DATS` | date as 8 characters `YYYYMMDD` | `d` |
| `DATN` | date, numeric (native DB date) | — (used via CDS/SQL) |
| `TIMS` | time as 6 characters `HHMMSS` | `t` |
| `TIMN` | time, numeric (native DB time) | — |
| `TIMESTAMP` / `TIMESTAMPL` | packed `DEC(15)` / `DEC(21,7)` | `p` |
| `UTCLONG` | time stamp, 8-byte | `utclong` |

Each gets its own function set — `DATS_*`, `DATN_*`, `TIMS_*`, `TSTMP_*`,
`UTCL_*` — plus a set of *generic* functions (`IS_VALID`, `EXTRACT_*`,
`DAYNAME`, `MONTHNAME`, `WEEKDAY`, `DAYS_BETWEEN`, `ADD_DAYS`, `ADD_MONTHS`)
that accept several of the types. Two practical consequences:

**Not all of them exist in CDS.** The
[overview table](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDDIC_DATE_TIME_FUNCTIONS.html)
marks the generic functions `ADD_DAYS`, `ADD_MONTHS`, `DAYS_BETWEEN`, `DAYNAME`,
`MONTHNAME`, `WEEKDAY`, `EXTRACT_*` and `IS_VALID` as available in **ABAP SQL
only** — with a `-` in both CDS columns. The `DATS_*`, `DATN_*`, `TSTMP_*`,
`UTCL_*` and conversion functions are available in both. So a working `SELECT`
is not automatically movable into a CDS view entity; check that table first,
not after the view fails to activate.

**The same name can run on two different engines.** For `EXTRACT_*`:

> "If the built-in data type `DATN` or `UTCLONG` is used, the function
> `EXTRACT_YEAR` calls the HANA function `EXTRACT`."
> "If the built-in data type `DATS` is used, the function `EXTRACT_YEAR`
> internally uses the ABAP SQL `SUBSTRING` function and a `CAST` expression
> afterwards. The corresponding rules apply."
> — [`sql_func` — generic date functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_GEN_DATE_FUNC.html)

One is a database date function, the other is string slicing over a character
column. That is the mechanism behind most of the asymmetries in this note.

## 1. The initial date is not a date — and the calculations do not say so

`DATS_IS_VALID` is the obvious guard, and its documentation contains the single
most useful sentence in the family:

> "A valid date produces the value 1 and all other input values (including the
> null value) produce the value 0."
> Hint: "The value *00010101* is a valid date here but the value *00000000* is
> not."
> — [`sql_func` — functions for `DATS`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_DATS_DATE_FUNC.html)

So **every row where an optional date was never filled is "invalid"**: an
unconfirmed delivery date, an open item with no clearing date, a contract with
no termination date. That is not an edge case, that is the normal state of half
the date columns in an ERP system.

Now the part that does the damage. The three `DATS` calculations each carry the
same sentence:

> "Any invalid date is initialized and set to the value *00010101* before the
> calculation."
> — [`DATS_DAYS_BETWEEN`, `DATS_ADD_DAYS`, `DATS_ADD_MONTHS`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_DATS_DATE_FUNC.html)

No exception. No null value. No `sy-subrc`. An "age in days" over an unfilled
date is computed from 1 January 0001:

```abap
SELECT SINGLE
       FROM sflight
       FIELDS dats_is_valid( @lv_empty )                AS empty_valid,
              dats_days_between( @lv_empty, @sy-datum ) AS from_empty
       INTO @DATA(ls_res).
" empty_valid = 0, from_empty = roughly 739,000
```

Both numbers come back in the same row: the validity flag says "not a date" and
the difference says "about 2,025 years old". Only one of them is usually read.

The consequences are the dull, expensive kind: an ageing report where unfilled
rows land in the oldest bucket and dominate it, an average that is destroyed by
a handful of empty columns, a dunning selection that thinks everything is
overdue. The fix is a `WHERE` clause or a `CASE`, not a different function:

```abap
SELECT FROM ekko
       FIELDS ebeln,
              CASE WHEN dats_is_valid( aedat ) = 1
                   THEN dats_days_between( aedat, @sy-datum )
                   ELSE CAST( NULL AS INT4 )
              END AS age_in_days
       WHERE aedat <> '00000000'   "and IS NOT NULL, if the column can be null
       INTO TABLE @DATA(lt_ages).
```

The `DATN_*` functions behave differently here — see trap 3 — which is why "it
worked in my other report" is not evidence.

## 2. The same validity test disagrees with itself across types

`TIMS_IS_VALID` is the exact counterpart of `DATS_IS_VALID`, same `INT4`
result, and it draws the opposite conclusion about the initial value:

> "A valid time and the initial value produce the value 1 and all other input
> values (including the null value) produce the value 0."
> — [`sql_func` — functions for `TIMS`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_TIMS_TIME_FUNC.html)

The generic `IS_VALID` repeats it, scoped explicitly to the time types:

> "A valid time and the initial value (for the data types `TIMN` and `TIMS`)
> produce the value 1 and all other input values (including the null value)
> produce the value 0."
> — [`sql_func` — generic time functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_GEN_TIME_FUNC.html)

| Argument | Initial value | Result |
|---|---|---|
| `DATS_IS_VALID( date )` | `00000000` | **0** — not valid |
| `TIMS_IS_VALID( time )` | `000000` | **1** — valid |
| either, on a null value | — | 0 |

And it is defensible: midnight *is* a time, whereas there is no zeroth day of
the zeroth month. But it means a `valid` column in a result set is only readable
next to the type of the column it was computed from, and a generic "validate
every date/time field" helper built on these functions needs a per-type branch.

The second half of both sentences matters just as much: **a null value also
produces 0**. `IS_VALID` cannot distinguish "no row matched my outer join" from
"this column contains garbage". If you need to tell those apart, ask for the
null directly — `IS NULL`, or a null indicator (see
[Null Values](../Null%20Values#readme)).

## 3. The dictionary type of the column decides whether failure is loud

Here is the full documented behaviour for "add something to a date or time
stamp, and the result does not exist":

| Function | Invalid *input* | Invalid *result* |
|---|---|---|
| `DATS_ADD_DAYS` | set to `00010101` | *"the initial value is reset"* |
| `DATS_ADD_MONTHS` | set to `00010101` | *"an error occurs"* |
| `ADD_DAYS` / `ADD_MONTHS` (generic), `DATS` argument | set to `00010101` | *"returns the initial date"* |
| `ADD_DAYS` / `ADD_MONTHS` (generic), `DATN` / `UTCLONG` argument | set to `00010101` / `0001-01-01T00:00:00.0000000` | `CX_SY_OPEN_SQL_DB` |
| `DATN_ADD_DAYS` / `DATN_ADD_MONTHS` | *"must contain a valid date"* | *"an error occurs"* |
| `TSTMP_ADD_SECONDS` | *"An invalid time stamp produces an error"* | *"If the result is invalid, an error occurs"* — `on_error` decides |
| `UTCL_ADD_SECONDS` | *"An invalid time stamp produces the initial value"* | `CX_SY_OPEN_SQL_DB` |

Sources:
[`DATS`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_DATS_DATE_FUNC.html) ·
[`DATN`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_DATN_DATE_FUNC.html) ·
[generic](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_GEN_DATE_FUNC.html) ·
[`TIMESTAMP`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_TS_TIMESTAMP_FUNC.html) ·
[`UTCLONG`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_UTC_TIMESTAMP_FUNC.html)

Read that table once more as a single statement: **the same conceptual
operation is silent on `DATS`, fatal on `DATN` and `UTCLONG`, and
configurable on `TIMESTAMP`.** Nothing about the written ABAP says which — it
is the dictionary type behind the column.

Two concrete ways this bites:

- A column is changed from `DATS` to `DATN`, or a report is copied from a
  classic table to a CDS entity exposing `DATN`, and code that silently produced
  initial dates starts dumping with `CX_SY_OPEN_SQL_DB` on exactly the rows it
  was silently mishandling before. The dump is the improvement; it just arrives
  in production, because test data has no corrupt dates.
- Only the `TIMESTAMP` family gives you a choice, and the default is the loud
  one:

  > "`SQL_TSTMP_ADD_SECONDS=>FAIL`: An error raises an exception (default)."
  > "`SQL_TSTMP_ADD_SECONDS=>SET_TO_NULL`: An error returns the null value."
  > — [`sql_func` — functions for `TIMESTAMP`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_TS_TIMESTAMP_FUNC.html)

  `SET_TO_NULL` is the right answer for a mass report that must not die on one
  bad row — but it then needs the null handled, because a null arrives in ABAP
  as the initial value, indistinguishable from a real `000000000000000`.

## 4. `EXTRACT` returns a plausible number for an empty value and dumps on a broken one

> "The function returns the value 1 for initial input values. If no valid date
> is passed as a `DATS` value, the function `EXTRACT_YEAR` raises a catchable
> exception of class `CX_SY_OPEN_SQL_DB`."
> — [`sql_func` — generic date functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_GEN_DATE_FUNC.html)

`EXTRACT_MONTH` and `EXTRACT_DAY` carry the same two sentences. The time side
differs in the number only:

> "The function returns the value 0 for initial input values. If no valid time
> is passed as a `TIMS` value, the function `EXTRACT_HOUR` raises a catchable
> exception of class `CX_SY_OPEN_SQL_DB`."
> — [`sql_func` — generic time functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_GEN_TIME_FUNC.html)

So `EXTRACT_YEAR( <empty date> )` is **1**, not 0 and not null — which is
consistent with the `00010101` substitution in trap 1, and which lands quietly
in a `GROUP BY EXTRACT_YEAR( ... )` as a bucket called "year 1" holding every
row nobody filled in. Meanwhile an actually corrupt date dumps. Empty is quiet,
broken is loud, and the quiet one is the common case.

Two more small facts about this group:

> "The generic function `DAYNAME` returns the name of a day of a date or an UTC
> time stamp **in uppercase letters in English**. […] The result of the function
> `DAYNAME` has the data type `CHAR` with length 9."
> — [`sql_func` — generic date functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_GEN_DATE_FUNC.html)

`DAYNAME` and `MONTHNAME` are not translated and do not look at `sy-langu`.
They are fine for a technical grouping key and wrong for anything a user reads;
for that you still want the day name from the calendar/text tables.

> "The generic function `WEEKDAY` returns the number of a weekday of a date or
> an UTC time stamp from 0 to 6."
> — [`sql_func` — generic date functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_GEN_DATE_FUNC.html)

The documentation gives the range but does not name which day is `0`. Do not
hard-code the mapping from the number to Monday on the strength of a single
test — put it in a constant and verify it in your own system, remembering that
for `DATN`/`UTCLONG` this function is delegated to the HANA `EXTRACT`/weekday
implementation while for `DATS` it is computed over a character column.

## 5. Month arithmetic clamps, and clamping is not reversible

> "The system tries to create a date with the same day in an earlier or later
> month. If the target month has fewer days than the source month, the last day
> of the target month is returned."
> — [`DATS_ADD_MONTHS`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_DATS_DATE_FUNC.html)

That is the behaviour you want. The thing to notice is that it is lossy:

| Start | `+ 1 month` | `- 1 month` again |
|---|---|---|
| `20260131` | `20260228` | `20260128` |

A due date computed by repeatedly adding one month to the *previous result*
therefore walks backwards — 31 Jan, 28 Feb, 28 Mar, 28 Apr — and stays on the
28th for the rest of the year. Always add `n` months to the **original**
anchor date instead of iterating, which also makes the calculation
order-independent and restartable.

The same clamp exists in `DATN_ADD_MONTHS` and the generic `ADD_MONTHS`, with
the failure modes from trap 3.

## 6. Two functions for "now", only one of them stable

| Function | Clock | Stability |
|---|---|---|
| `UTCL_CURRENT( )` | *"from the system time and the system date of AS ABAP"* | *"All columns of a query have the same time stamp."* |
| `TSTMP_CURRENT_UTCTIMESTAMP( )` | *"created from the clock on the database server"* | *"it cannot be guaranteed that every call within a database access produces the same result"* |

> "If the function `TSTMP_CURRENT_UTCTIMESTAMP` is used more than once within an
> ABAP SQL statement, it cannot be guaranteed that every call within a database
> access produces the same result. Hence, later calls can produce later time
> stamps."
> — [`sql_func` — functions for `TIMESTAMP`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_TS_TIMESTAMP_FUNC.html)

> "Selects column `CARRID` from table `SCARR` and returns a time stamp for each
> row. The time stamp is generated only once for the query and, therefore, all
> rows have the same time stamp."
> — [`sql_func` — functions for `UTCLONG`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_UTC_TIMESTAMP_FUNC.html)

So a statement that stamps rows with `TSTMP_CURRENT_UTCTIMESTAMP( )` and *also*
computes `TSTMP_SECONDS_BETWEEN( tstmp1 = tstmp_current_utctimestamp( ) ... )`
has used two different "now"s, and the difference can come out negative or one
second off for a subset of rows. Call it once, into one column, and derive
everything else from that column — or use `UTCL_CURRENT( )`, which the
documentation guarantees is per-query.

Note also that the two read *different clocks*. The documentation says the AS
ABAP and database server clocks are synchronized, which is true of a healthy
system and not a licence to mix the two inside one calculation.

## 7. The time zone you did not pass

The conversion functions (`TSTMP_TO_DATS`, `TSTMP_TO_TIMS`, `TSTMP_TO_DST`,
`DATS_TIMS_TO_TSTMP`) are the database-side version of `CONVERT TIME STAMP`:

> "These functions move the functions of the ABAP statements
> `CONVERT TIME STAMP` and `CONVERT INTO TIME STAMP` to the database."
> — [`sql_func` — date/time conversions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_DATE_TIME_CONVERSIONS.html)

Three things to carry over from the ABAP statements, plus one that is new:

> "`tzone` expects an actual parameter of the type `CHAR` with length 6, either
> initial or containing a valid time zone. **If an initial time zone is
> specified, no time shift is calculated.**"
> — [`sql_func` — date/time conversions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_DATE_TIME_CONVERSIONS.html)

An unfilled time zone variable is therefore not an error — it silently returns
the **UTC** date, which for a user in `INDIA` or `PST` is the wrong date for
part of every day. The value is plausible, the report is wrong near midnight,
and nobody notices for months.

> "The conversions follow the ABAP-specific rules for time zones. The associated
> DDIC database tables must be filled correctly."
> — [`sql_func` — date/time conversions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_DATE_TIME_CONVERSIONS.html)

The conversion happens on the database but still reads the ABAP time-zone
customizing tables, and the optional `client` parameter — defaulting to the
current client — selects which client's rules are used. A sandbox client with
unmaintained time-zone tables produces different results from production for
the same statement.

For the ABAP side of time stamps, daylight saving and the hour that happens
twice, see [Time Stamps](../Time%20Stamps#readme).

## 8. Adding a date function can raise the strict mode of the whole statement

Each group of these functions pulls the syntax check into a stricter mode:

| Functions | Enforced strict mode |
|---|---|
| `TSTMP_IS_VALID`, `TSTMP_CURRENT_UTCTIMESTAMP`, `TSTMP_SECONDS_BETWEEN`, `TSTMP_ADD_SECONDS`, `TIMS_IS_VALID`, conversions `TSTMP_TO_*` / `DATS_TIMS_TO_TSTMP` | [from 7.71](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_STRICTMODE_771.html) |
| `UTCL_CURRENT`, `UTCL_ADD_SECONDS`, `UTCL_SECONDS_BETWEEN`, `DATN_*`, type conversions `DATS_TO_DATN`, `TSTMPL_TO_UTCL`, … | [from 7.78](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_STRICTMODE_778.html) |
| **all** generic functions (`IS_VALID`, `EXTRACT_*`, `DAYNAME`, `MONTHNAME`, `WEEKDAY`, `DAYS_BETWEEN`, `ADD_DAYS`, `ADD_MONTHS`) | [from 7.83](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_STRICTMODE_783.html) |

Two practical effects:

1. **An unsupported function is a syntax error, not a runtime error.** Adding
   `extract_year( )` to a report on a system older than the release that
   supports it does not fail for one row — the program does not compile at all.
   That is why the demo in this folder deliberately restricts itself to the
   `DATS_*` functions.
2. **The strict mode applies to the whole statement.** A `SELECT` that has
   compiled for years can stop compiling the moment a date function is added to
   its field list, because the rest of the statement is now checked against a
   newer rule set. The error message points at the old line, not at your new
   one. `DATS_IS_VALID`, `DATS_DAYS_BETWEEN`, `DATS_ADD_DAYS` and
   `DATS_ADD_MONTHS` are the only ones in the family whose keyword-doc pages
   carry no strict-mode hint at all.

## 9. The ABAP side, for contrast

The database behaviour above is a deliberate imitation of the ABAP conversion
rules, which are worth knowing in their own right:

> "Only dates in the format *yyyymmdd* are valid for data objects of type `d`
> where *00010101* is the first valid value. The conversion rules, however, also
> allow the assignment of date fields that contain invalid data. The latter is
> not recommended."
> — [Source field type `d`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_D.html)

So **type `d` is not validated on assignment**. `'20260230'` is storable,
comparable and printable. In arithmetic:

> "If the source field contains a valid date in the format *yyyymmdd*, it is
> used to calculate the number of days since 01.01.0001 […] **If the source
> field contains an invalid date, the target field is assigned the value 0.**"
> — [Source field type `d`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_D.html)

An invalid operand therefore counts as day zero — the ABAP-side twin of the
`00010101` substitution, except the magnitude is different and there is still
no exception.

> "The assignment of the values *00000000* and *00010101* to a numeric type
> produces the value 0 in each case. The assignment of the value 0 to a date
> field produces *00000000*. This means that the assignment of the value
> *00010101* to a numeric type is not reversible."
> — [Source field type `d`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_D.html)

Round-tripping a date through day arithmetic can therefore turn `00010101`
into `00000000` — which the database functions will then treat as invalid and
map back to `00010101`. The two ends of the same pipeline disagree about which
of the two values they mean.

And the nicest piece of trivia in the whole topic, which is also a real
constraint:

> "The conversion of a date into the number of days since 01.01.001 is designed
> in such a way that the transition from the Julian to Gregorian calendar is
> respected: 4.10.1582 results in 577,736 and 15.10.1582 in 577,737. Converting
> the dates for the nonexistent days between 5.10.1582 and 14.10.1582 produces
> the same result as converting the existing days from 15.10.1582 to
> 24.10.1582."
> — [Source field type `d`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_D.html)

Ten dates that never existed share day numbers with ten that did, so the
mapping from date to day number is **not injective**. Day-number arithmetic
cannot be reversed into a unique date across the cut-over. Irrelevant for
business data, decisive if you ever write your own date↔integer conversion and
compare it against ABAP's.

Finally, the assignments that are not allowed at all:

| From `d` to | Result |
|---|---|
| `c`, `string` | treated as a character field |
| `n` | left-aligned, **truncated on the right** — `sy-datum` into `n LENGTH 4` is the *year* |
| `t` | *"Not supported. Produces a syntax error or runtime error"* (`MOVE_NOT_SUPPORTED`) |
| `utclong` | *"Not supported"* — `CX_SY_CONVERSION_NOT_SUPPORTED` |

The `n` row is the one that looks like a feature. It is the same rule for type
`t` (`'183056'` into `n LENGTH 2` gives `18`), and it runs the *opposite*
way round from the packed-to-character conversion, which truncates on the
left (see [Numeric Arithmetic](../Numeric%20Arithmetic#readme)) — see
[String Processing](../String%20Processing#readme) for offset/length typing and
[Numeric Arithmetic](../Numeric%20Arithmetic#readme) for the calculation-type
rules that decide what `date1 - date2` even means.

## Quick reference

| Question | Answer |
|---|---|
| Is the initial date a valid date? | No. `DATS_IS_VALID( '00000000' ) = 0`, but `00010101` → 1 |
| Is the initial time a valid time? | **Yes.** `TIMS_IS_VALID( '000000' ) = 1` |
| What do the `DATS_*` calculations do with an invalid date? | Replace it with `00010101`, silently |
| What do `DATN_*` do? | Raise an error |
| `DATS_ADD_DAYS` overflow | Initial value |
| `DATS_ADD_MONTHS` overflow | Error (generic `ADD_MONTHS` on `DATS`: initial date) |
| Null argument | Null result, except `IS_VALID`/`DATS_IS_VALID`/`TIMS_IS_VALID` → 0 |
| `EXTRACT_YEAR` of an empty date | `1` |
| `EXTRACT_HOUR` of an empty time | `0` |
| `DAYNAME` language | Uppercase English, `CHAR(9)`, not translated |
| `WEEKDAY` range | 0 to 6; the doc does not say which day is 0 |
| Per-query stable "now" | `UTCL_CURRENT( )`; `TSTMP_CURRENT_UTCTIMESTAMP( )` is not guaranteed |
| Initial `tzone` in a conversion | No time shift — you get UTC, with no error |
| Generic functions in CDS | Not available; `DATS_*`/`DATN_*`/`TSTMP_*`/`UTCL_*` are |
| Invalid date on the ABAP side | Converts to day number 0, no exception |

## Notes on the documentation itself

Recorded rather than smoothed over, because they are visible to anyone reading
the same pages:

- The generic `ADD_DAYS`/`ADD_MONTHS` descriptions name the wrong parameter when
  they get to the failure modes: *"the function raises a catchable exception of
  class `CX_SY_OPEN_SQL_DB` if the actual parameter `days` is of data type
  `DATN` or `UTCLONG`"*, and *"The result has the data type of the first actual
  parameter `days` or `utclong`"*. `days`/`months` is the `INT4` operand; the
  type-dependent behaviour obviously belongs to the date/time-stamp operand.
  Read it that way, but do not quote it as written.
- The `DATS_ADD_MONTHS` overflow outcome is documented twice and differently —
  *"an error occurs"* on the `DATS` page, *"returns the initial date"* on the
  generic page for a `DATS` argument. The demo catches `CX_SY_OPEN_SQL_DB` and
  prints whichever one the system actually does, rather than picking a winner.
- The archived
  [7.53 overview table](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-US/abenddic_date_time_functions.htm)
  lists `DATS_ADD_DAYS( date, days, on_error )` and
  `DATS_ADD_MONTHS( date, months, on_error )` **with** an `on_error` parameter;
  the current page documents two positional parameters and no `on_error`. If you
  need error control on `DATS` arithmetic, check the signature in your own
  release before designing around it.
- On the [source field type `t`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_T.html)
  page, the `xstring` example says the byte chain `010460` "is the integer
  66655", while the numeric example on the same page gives `66656` for the same
  value `'183056'` — and 18 × 3600 + 30 × 60 + 56 = 66,656, which is also what
  `0x010460` evaluates to. The prose is off by one; the arithmetic is not.
- Type `t` converts to a number if the field *"contains only digits"* — with no
  check that the hours and minutes are in range. `'997788'` is not a time and
  still produces a number.

## Related notes in this repo

- [Time Stamps](../Time%20Stamps#readme) — the ABAP side: packed vs `utclong`,
  the DST double hour, `sy-datum` vs `sy-datlo`
- [Null Values](../Null%20Values#readme) — why a null result arrives as the
  initial value, and how to see the difference
- [Numeric Arithmetic](../Numeric%20Arithmetic#readme) — the calculation type
  that turns `date1 - date2` into integer days
- [CDS View Entities](../CDS%20Client%20Handling#readme) — where the
  availability split in section 0 matters
- [Conversion Routines](../Conversion%20Routines#readme) — the other place a
  date changes shape without anyone asking

## References

- [DDIC — date functions and time functions (the availability table)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDDIC_DATE_TIME_FUNCTIONS.html)
- [`sql_func` — date functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_DATE_FUNC.html) ·
  [generic](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_GEN_DATE_FUNC.html) ·
  [`DATS`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_DATS_DATE_FUNC.html) ·
  [`DATN`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_DATN_DATE_FUNC.html)
- [`sql_func` — time functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_TIME_FUNC.html) ·
  [generic](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_GEN_TIME_FUNC.html) ·
  [`TIMS`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_TIMS_TIME_FUNC.html)
- [`sql_func` — time stamp functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_TIMESTAMP_FUNC.html) ·
  [`TIMESTAMP`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_TS_TIMESTAMP_FUNC.html) ·
  [`UTCLONG`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_UTC_TIMESTAMP_FUNC.html)
- [`sql_func` — date/time conversions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_DATE_TIME_CONVERSIONS.html)
- [Source field type `d`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_D.html) ·
  [source field type `t`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_T.html)
- Strict modes of the ABAP SQL syntax check:
  [7.71](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_STRICTMODE_771.html) ·
  [7.78](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_STRICTMODE_778.html) ·
  [7.83](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_STRICTMODE_783.html)

See `ydj_sql_date_time_demo.abap` in this folder for a runnable version of
traps 1 to 5 plus the ABAP-side conversions. It is read-only, uses the flight
data model only for a `FROM` clause and one outer join, and restricts itself to
the `DATS_*` functions so that it still compiles on older releases.
