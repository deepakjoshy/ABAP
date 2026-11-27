# Runtime Measurements — the clock that starts at zero, the precision switch that dumps, and the `sy-subrc` that is always 0

This repository is full of notes that end in *measure it on your own system* -
[Table Buffering](../Table%20Buffering#readme), [Mass Data Processing](../Mass%20Data%20Processing#readme),
[Row Limiting & Ordering](../Row%20Limiting%20and%20Ordering#readme),
[Table Memory](../Table%20Memory#readme), [For All Entries](../For%20All%20Entries#readme).
This one is about the instrument those notes keep pointing at, because it has its
own set of behaviours that quietly invalidate the number it prints:

- the clock **starts at 0** when the internal session is created, so a single reading
  is not a point in time — it is a distance from an event you did not choose;
- the result is **type `i`**, so a session clock runs out of range at about **2147
  seconds**, and the doc asks you to stay under 1000;
- the precision switch can only be used **before the first reading** in the session,
  and using it later is a **non-handleable** runtime error — no `TRY`/`CATCH` saves
  you — *except* when it happens to be setting the value it already had;
- the default precision, `HIGH`, is documented as capable of producing **false time
  values** on multi-processor machines outside a named platform list;
- `CL_ABAP_RUNTIME` fixes the one-shot precision problem and costs about **two
  microseconds per call** to do it, which for micro-benchmarks is bigger than the
  thing being measured;
- `SET RUN TIME ANALYZER` sets `sy-subrc` to **0 unconditionally**, so a clean call is
  not evidence that anything is being traced — and without a specific setting in SAT,
  it does nothing at all;
- and the two SAP pages that use the statement **disagree about what it counts**.

Runnable demo: [`ydj_runtime_measure_demo.abap`](ydj_runtime_measure_demo.abap) —
ten probes, no DDIC objects, no database access, which **prints** every number
rather than asserting it.

## The four instruments, and what each is for

| Instrument | Unit / precision | Scope | Use it for |
|---|---|---|---|
| `GET RUN TIME FIELD rtime` | microseconds, type `i` | one clock per internal session | measuring a code section you wrote |
| `CL_ABAP_RUNTIME` timer objects | high or low resolution per object | many timers per internal session | measurement code that lives in a library |
| `GET TIME STAMP` / `utclong` | down to 100 ns, platform permitting | wall clock, absolute | *when* something happened, not how long it took |
| Runtime analysis (SAT) / ABAP Profiler | tool-defined | whole program, statement level | finding *which* part is slow in the first place |

The first two are the subject of this note. The third is
[Time Stamps](../Time%20Stamps#readme). The fourth is a tool, and the keyword
documentation says what it is and what replaced it:

> "Tool for analyzing the execution of program parts or individual statements and for
> measuring their runtime in SAP GUI." ... "Replaced by the ABAP Profiler in the
> ABAP Development Tools (ADT)."
> — [ABAP keyword documentation, glossary `runtime analysis`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENRUNTIME_ANALYSIS_GLOSRY.htm)

## Trap 1: the first reading is zero, and zero is not a bug

> "When `GET RUN TIME` is executed for the first time after an internal session is
> created, the value 0 is passed to the variable `rtime`. After each further execution
> in the same internal session, the program runtime that has elapsed since the first
> execution, in microseconds, is passed to the variable `rtime`."
> — [ABAP keyword documentation, `GET RUN TIME`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABAPGET_RUN_TIME.htm)

So the statement does not read a clock that exists independently of your program. The
first call **is** the zero point. Three consequences that matter in practice:

1. **A single reading is meaningless.** Only differences carry information. The doc
   gives the vocabulary for that: "The sequence of statements set within limits is
   called the measuring section, and the duration calculated for it is called the
   measuring interval."
2. **The zero point belongs to the internal session, not to your code.** If anything
   in the same internal session already read the clock — a framework, a BAdI
   implementation, somebody's leftover instrumentation — your first reading is not 0,
   and any code that treats the first reading as a baseline is silently wrong by
   however much time had already passed.
3. **It resets where internal sessions reset.** A new internal session means a new
   zero. This is the same session boundary that governs `ABAP Memory`, function group
   globals and `SET`/`GET PARAMETER` — see [Program Calls](../Program%20Calls#readme)
   and [Function Modules](../Function%20Modules#readme).

The inline form is explicitly blessed, which is worth knowing because it is the
shortest correct way to write a bracket:

> "An existing variable of the data type `i` or a variable to which the type `i` can be
> converted." ... "An inline declaration `DATA(var)`, where a variable of type `i` is
> declared."

```abap
GET RUN TIME FIELD DATA(lv_t1).
" ... the measuring section ...
GET RUN TIME FIELD DATA(lv_t2).
DATA(lv_interval) = lv_t2 - lv_t1.          " the only meaningful quantity
```

Note the second half of that first sentence: the target may also be "a variable to
which the type `i` can be converted". That is a convenience and a hazard — a `TYPE p
DECIMALS 2` target will accept the assignment and will never carry a fraction of a
microsecond, because there is none to carry; the statement's own result is an integer.

## Trap 2: the clock has a ceiling, and it is closer than you think

> "The return value of the statement is of the data type `i`."

Type `i` is a 4-byte integer with the documented value range
"-2,147,483,648 to +2,147,483,647"
([predefined numeric types](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENBUILTIN_TYPES_NUMERIC.htm)),
and the unit is microseconds. So **one internal session clock covers about 2147
seconds — roughly 35 minutes.** The doc does not spell the arithmetic out, but it does
set a budget well inside it:

> "The value range of the return value of the statement must be respected. Do not
> create measuring sections that are too large (not greater than 1000 s) and also do
> not create any measuring sections using accesses to external data or using screen
> calls and so on."

Two separate instructions in one sentence, and the second is the one people break:

- **Not greater than 1000 s.** A long-running batch job is therefore *not* something
  you bracket with two `GET RUN TIME` statements. For a job that runs for hours, the
  correct instrument is the wall clock (`utclong_current( )`, see
  [Time Stamps](../Time%20Stamps#readme)) or the job's own runtime in `SM37`, not this.
- **No screen calls, no external data.** A measuring section containing a dynpro, a
  `MESSAGE` with a popup or a file read includes time that has nothing to do with your
  code, and the doc also warns that the statement "respects the time taken for an
  internal session to be rolled out of the memory". Bracketing an interactive step
  measures the user.

The demo prints `cl_abap_math=>max_int4` and divides it out, because the limit is
easier to respect once you have seen how small it is. The constant is documented:

> "The class `CL_ABAP_MATH` contains constants with the limits of the value ranges
> built-in numeric types."
> — [ABAP keyword documentation, `CL_ABAP_MATH`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENFLOATING_POINT_CLASS.htm)

(That sentence is missing a word — "the value ranges built-in numeric types" — which
is a good reminder to read SAP documentation for its facts and not its grammar. There
are more missing words below.)

## Trap 3: the precision switch is a one-shot, and getting it wrong is a dump

This is the sharpest trap in the family, because it punishes exactly the thing a
careful developer does: wrapping the measurement in a reusable helper.

> "This statement specifies the precision with which the statement `GET RUN TIME` is
> measured. It can be changed in a program only before the statement `GET RUN TIME` is
> executed for the first time, otherwise a non-handleable exception is raised."
> — [ABAP keyword documentation, `SET RUN TIME CLOCK RESOLUTION`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABAPSET_RUN_TIME_CLOCK_RESOLUTION.htm)

**Non-handleable** means what it says: the documented consequence is the runtime error
`SET_RUN_TIME_CLOCK_ERROR`, raised by

> "An attempt was made to change the level of precision after `GET RUN TIME` using
> `SET RUN TIME CLOCK RESOLUTION`."

No `TRY`/`CATCH` anywhere up the call stack contains it. A helper method that opens
with `SET RUN TIME CLOCK RESOLUTION LOW.` works perfectly in isolation, works
perfectly in its own unit test, and short-dumps the first time it is called in a
session where somebody else already measured something — which on a dialog system is
most of the time.

Now the part that makes it genuinely hard to reason about:

> "No exception is raised if `SET RUN TIME CLOCK RESOLUTION` is used after the
> statement `GET RUN TIME` as long as the level of precision is not changed."

combined with:

> "Without the preceding statement `SET RUN TIME CLOCK RESOLUTION`, `GET RUN TIME` uses
> the high precision measurement implicitly."

So the *same line of code* is either a harmless no-op or a short dump, and which one
it is depends on whether the current precision — possibly set by code you have never
read — already matches. `SET RUN TIME CLOCK RESOLUTION HIGH` after a reading is
normally the no-op case, because `HIGH` is the implicit default; `LOW` after a reading
is normally the dump. "Normally" is not a basis for library code.

**The resolution is session state, not program state.** That is why the demo
([`probe_clock_resolution`](ydj_runtime_measure_demo.abap)) deliberately does not
execute the statement at all, and only documents it: by the time that probe is
reached, eight earlier probes have read the clock.

### and `HIGH` is not simply "better"

> "Specifying `HIGH` defines a level of precision of one microsecond. If the level of
> precision is high, this can produce false time values for multi-processors, since the
> clocks of the individual processors are not always regularly synchronized on all
> platforms."

The doc then names the platforms where "The high level of precision on the following
platforms always returns correct values": AIX, SINIX, SUN-OS, Linux, IBM i5/OS
(previously OS/400), Windows. Anywhere else:

> "To avoid incorrect time values on the other platforms, `LOW` can be used to specify
> a low precision measurement whose resolution depends on each platform."

Which is a genuine fork with no free option: `HIGH` may be *precise but wrong*, `LOW`
is *right but of unstated resolution*. Note also that the guaranteed-correct list has
not been refreshed in a very long time — SINIX and OS/400 date the text more precisely
than any release note could — so on a modern platform the honest reading is "check it",
and probe 3 of the demo is how you check it.

## Trap 4: the ruler has a width — subtract it

Two readings with nothing between them already return a non-zero interval, so every
measurement of a short section is inflated by the cost of measuring. SAP's own example
for this statement treats that as a first-class step, measuring

> "An empty program segment for determining the offset of the runtime measurement"

and subtracting it from the two real measurements, before concluding:

> "The result shows that the offset of the runtime measurement can be neglected in this
> case and that reading specific columns of a table is faster than reading entire rows."
> — [ABAP keyword documentation, `Runtime Measurement of Database Reads`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENGET_RUN_TIME_ABEXA.htm)

The qualifier *in this case* is the whole point: the offset is only negligible
relative to what you measured. The same offset against a section that takes four
microseconds is the measurement. The pattern SAP uses in its example on the
`GET RUN TIME` page itself is worth copying wholesale — an inner loop of `ni`
repetitions to lift the section above the resolution, an outer loop of `no`
repetitions to average out noise, and an empty inner loop measured the same way and
subtracted:

```abap
DATA: t0 TYPE i,
      no TYPE i VALUE 100,
      ni TYPE i VALUE 1000.
DO no TIMES.
  GET RUN TIME FIELD DATA(t1).
  DO ni TIMES.
    DATA(res) = tan( 1 ).
  ENDDO.
  GET RUN TIME FIELD DATA(t2).
  GET RUN TIME FIELD DATA(t3).
  DO ni TIMES.
  ENDDO.
  GET RUN TIME FIELD DATA(t4).
  t0 += ( t2 - t1 ) - ( t4 - t3 ).
ENDDO.
DATA(tm) = CONV decfloat34( t0 / ni / no ).
```

Three things in that snippet are doing real work, and all three are easy to drop:
the empty `DO ni TIMES` loop (the loop overhead is not part of what you are measuring),
the averaging over `no`, and the `CONV decfloat34` at the end. Without that `CONV` the
target is a bare inline declaration, which contributes no type of its own, so
`t0 / ni / no` is an integer division between `i` operands and a sub-microsecond answer
is rounded to a whole number before anyone sees it. Trap 6 is that rule in full,
because it does not work the way it looks.

Why the inner loop is not optional:

> "The maximum resolution of the command `GET RUN TIME` is a microsecond. Shorter
> measuring intervals cannot be determined reliably."

A statement that takes 200 nanoseconds cannot be measured at all. It can only be
measured a thousand times and divided.

## Trap 5: `CL_ABAP_RUNTIME` — the fix for trap 3, priced per call

> "The static methods `CREATE_HR_TIMER` and `CREATE_LR_TIMER` of the class
> `CL_ABAP_RUNTIME` can be used to create objects for runtime measurements. The objects
> contain a method `GET_RUNTIME` that performs a runtime measurement in the same way as
> the statement `GET RUN TIME`."
> — [ABAP keyword documentation, `System Class for Runtime Measurements`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENCL_ABAP_RUNTIME.htm)

The reason to prefer it is precisely trap 3 — precision becomes a property of an
object instead of a one-shot setting for the whole session:

> "An object created using `CREATE_HR_TIMER` performs a measurement with high
> precision, and an object created using `CREATE_LR_TIMER` performs a measurement with
> a lower level of measurement precision." ... "In contrast to the statement
> `GET RUN TIME`, these objects can be used to perform different measurements with
> different levels of precision and parallel measurements for each internal session."

```abap
DATA(timer) = cl_abap_runtime=>create_hr_timer( ).
DATA(t1) = timer->get_runtime( ).
" ... measuring section ...
DATA(t2) = timer->get_runtime( ).
```

**Parallel measurements** is the second win and the less obvious one: with the
statement there is exactly one clock per internal session, so nested or overlapping
sections all read the same clock. Two timer objects can bracket overlapping sections
independently — the demo runs an `HR` and an `LR` timer across the same section at
once to show that they are separate instruments, not two views of one.

The price is stated outright:

> "As the execution of the method `GET_RUNTIME` is approximately two microseconds
> slower than the execution of the statement `GET RUN TIME`, in some circumstances this
> method may not be suitable for the measurement of very short periods of time."

Two microseconds is enormous on this scale. Measured against a section that itself
takes a few microseconds, the method's overhead dominates — and it is paid **twice**
per bracket. The demo measures this difference instead of restating it (probe 6), which
is also a nice demonstration that the overhead is itself measurable with the cheaper
instrument.

Practical rule: the statement for micro-benchmarks you write and throw away, the class
for anything that ships — a measurement helper, a trace wrapper, instrumentation
inside a framework — because the statement's precision setting is a landmine in shared
code and the class's two microseconds are irrelevant at the scale shared code measures.

## Trap 6: the number you divide by 1000 depends on where you write it

Measurements are taken in microseconds and reported in milliseconds or seconds, so
every measurement note ends in a division — and ABAP decides *how* to divide based on
something most languages ignore: the type of the variable you are assigning to.

> "Involved data types include: The right side of an assignment in arithmetic
> expressions: If it is not an inline declaration `DATA(var)`, the data types of all
> operands of the full arithmetic expressions, and the data type of the result field
> `result`."
> — [ABAP keyword documentation, `arith_exp - Calculation Type and Calculation Rules`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENARITH_TYPE.htm)

The same page calls this out as unusual, and it is:

> "The way a calculation type is identified before the calculation and respecting all
> operands including the result field (as the right side of an assignment or as an
> actual parameter in the case of an arithmetic expression) is a special ABAP feature
> that differs considerably from the way in which other programming languages perform
> calculations."

And when the calculation type does end up being `i`:

> "The arithmetic expression is calculated using integer arithmetic, in which each
> subtotal that is not an integer (after a division) is rounded commercially to the
> nearest integer."

Rounded, not truncated — so 0.6 ms of work is reported as **1 ms**, and 0.4 ms of work
is reported as **0**. Three ways to write the same division, with three different
results:

```abap
DATA lv_ms TYPE p LENGTH 8 DECIMALS 3.

lv_ms = lv_us / 1000.                 " result field is p -> p division, decimals kept
DATA(lv_x) = lv_us / 1000.            " inline decl contributes nothing -> i division
DATA(lv_t) = |{ lv_us / 1000 } ms|.   " string template -> i division
```

The second one is the documented inline-declaration rule — an inline target cannot
contribute a type, so only the operands count. The third is a separate, explicit
exception:

> "as an embedded expression in a string template in an arithmetic expression, only the
> operands of the expression are evaluated."

That is the one that bites in practice, because formatting a measurement *into a
message* is the last thing any benchmark does. `WRITE lv_ms` and `|{ lv_us / 1000 }|`
print different numbers from the same interval, and nothing warns you. Probe 9 of the
demo prints both side by side.

There is a related inline-declaration trap for the averaging step:

> "In the case of the calculation type `p`, the data type of the declared variable is
> always `p` with the length 8 without decimal places."

So `DATA(lv_mean) = lv_total / lv_runs.` where `lv_total` is `TYPE p DECIMALS 2` gives
you a mean **with no decimal places at all**. The doc's own advice is blunt: "It is
best to either avoid inline declarations when using the calculation type `p` or to
determine the data type by applying the conversion operator `CONV` to the arithmetic
expression." The demo declares its accumulators and means explicitly for exactly this
reason.

Where `CONV` *does* change the calculation (and why SAP's own example needs it):

> "as an argument in a constructor expression in an arithmetic expression, the
> calculation type is determined as in an assignment. The left side of the assignment
> is either the result of the constructor expression with the type `type` specified in
> front of the parentheses or a structure component."

`CONV decfloat34( t0 / ni / no )` therefore divides in `decfloat34`; the same
expression without the `CONV`, assigned to an inline declaration, divides in `i`.

## Trap 7: `SET RUN TIME ANALYZER` is not feedback

> "This statement influences the measurement of a program with the runtime analysis
> tool. If the setting `Particular Units` is activated in the runtime analysis ... the
> runtime analysis only measures statements that occur between `SET RUN TIME ANALYZER
> ON` and `SET RUN TIME ANALYZER OFF`."
> — [ABAP keyword documentation, `SET RUN TIME ANALYZER`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABAPSET_RUN_TIME_ANALYZER.htm)

Two things follow, and they point in opposite directions from what the code looks like:

- **Without that SAT setting, the statements do nothing at all.** They are a request
  that only has meaning if someone, in a different tool, restricted the trace to
  particular units. Code that looks instrumented is not instrumented.
- **The return code is worthless as a check.** "The statement `SET RUN TIME ANALYZER`
  always sets the return code `sy-subrc` to 0." A clean `sy-subrc` after the call tells
  you nothing whatsoever — it is the same 0 you get on a system where no trace is
  running. Compare [Application Log](../Application%20Log#readme), where a `sy-subrc`
  of 0 likewise does not mean "logged".

The doc is also explicit that these statements are not meant to live in your code:

> "This statement should only be used in the test phase of a program, to enable a later
> runtime measurement independently of the source code."

which is easier said than done, because nothing fails if they stay. The
programmatic alternative does not require editing the source at all:

> "Runtime analysis can be stopped and started on a program-driven basis by calling the
> static methods `ON` and `OFF` in `CL_ABAP_TRACE_SWITCH` either before or after the
> statements `SET RUN TIME ANALYZER`."

and the tool itself has moved on:

> "Runtime analysis was replaced by ABAP Profiler in the ABAP Development Tools (ADT)."

## Trap 8: what is actually being counted — two SAP pages, two answers

The `GET RUN TIME` page describes the statement in terms of processor time:

> "The statement `GET RUN TIME` does not accumulate the time taken to execute
> individual ABAP statements. Instead it defines actual points in time with respect to
> the processor time. In particular, when there are differences between these points in
> time, the statement respects the time taken for an internal session to be rolled out
> of the memory"

(That sentence really does end without a full stop in the source, running straight into
"In a conceptual sense" — the second missing word of this note.)

The `WAIT UP TO` page then brackets a one-second sleep with the same two statements and
states what it expects:

> "The output of the following example should correspond to approximately one million
> microseconds."
> — [ABAP keyword documentation, `WAIT UP TO`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABAPWAIT_UP_TO.htm)

```abap
GET RUN TIME FIELD DATA(t1).
WAIT UP TO 1 SECONDS.
GET RUN TIME FIELD DATA(t2).
cl_demo_output=>display( |{ t2 - t1 STYLE = scientific }| ).
```

A second of `WAIT` consumes essentially no processor time, so "with respect to the
processor time" and "approximately one million microseconds" cannot both be read in the
plain sense at the same time. **This note does not resolve that**, because the honest
answer is kernel-dependent and there is no ABAP system here to try it on — which is
why probe 10 of the demo prints the real figure rather than asserting one. Run it, and
you will know which reading holds on your release.

What is *not* ambiguous is the practical consequence: whatever the clock counts, it
also counts roll-out time, so a measuring section must not contain anything that lets
the session be rolled out or waited on. That is the same sentence from trap 2 —
"do not create any measuring sections using accesses to external data or using screen
calls and so on" — and it is the reason the standard advice is to measure a tight,
self-contained block and nothing else.

### and `WAIT` has a side effect you may not want inside a measurement

> "Each time this variant of the statement `WAIT` is used, a database commit is
> triggered (except in updates). For this reason, `WAIT` must not be used between ABAP
> SQL statements that open or close a database cursor."

So the common instinct - *let me put a short WAIT between runs to let the system
settle* - is a transaction-semantics change, not a pause. Inside an LUW it commits
work you had not finished ([Commit Work Events](../Commit%20Work%20Events#readme),
[Update Task](../Update%20Task#readme)); inside a `SELECT ... ENDSELECT` loop or around
a cursor it is simply forbidden
([Mass Data Processing](../Mass%20Data%20Processing#readme)). `WAIT` also "always
changes the work process", and its own `sy-subrc` is another unconditional 0.

## Trap 9: the finer instrument makes the vaguer promise

It is tempting to measure with timestamps instead, since `TIMESTAMPL` and `utclong`
have far more resolution than a microsecond. The guarantees run the other way:

| | Documented resolution | Guarantee |
|---|---|---|
| `GET RUN TIME` | 1 microsecond | "always precise to the microsecond (regardless of the platform)" |
| `TIMESTAMPL` (packed long form) | 100 ns | "The maximum time resolution depends on the operating system of the host computer of the current AS Instance and can be less." |

The `GET RUN TIME` page makes the comparison itself:

> "In a conceptual sense, a time defined using `GET RUN TIME` can be viewed as a time
> stamp. Unlike real POSIX time stamps, a time defined using `GET RUN TIME` is always
> precise to the microsecond (regardless of the platform), while also being restricted
> to the value range of the data type `i`."

Which is the trade in one sentence: **a guaranteed unit inside a 35-minute window**
versus **an unguaranteed unit with no window**. For durations, the first is almost
always what you want; for recording *when* something happened, only the second will do.
See [Time Stamps](../Time%20Stamps#readme) for the timestamp side of this, including
`utclong` and `cl_abap_tstmp`.

## Trap 10 (reasoning, not quoted): you are probably measuring a warm cache

Nothing in the keyword documentation says this, so it is flagged as my own inference
from other notes in this repository rather than presented as a sourced fact — but it
invalidates more benchmarks than any trap above.

The second execution of a measuring section is not a repeat of the first:

- a buffered table is read from the buffer the second time, not from the database
  ([Table Buffering](../Table%20Buffering#readme));
- the database has its own caches, which your first read warms;
- an internal table assignment may be sharing memory rather than copying it until
  someone writes ([Table Memory](../Table%20Memory#readme));
- a class is loaded, and a static constructor has already run
  ([Constructors](../Constructors#readme)).

So the averaging loop that trap 4 recommends for *resolution* reasons is simultaneously
the thing that makes the result unrepresentative of the first run, which is usually the
run a user experiences. Both numbers are legitimate; they are answers to different
questions, and a benchmark that does not say which one it measured has not reported
anything. Where it matters, measure the first iteration separately from the mean of the
rest.

## ABAP Cloud

`GET RUN TIME` is on the list of statements not available in ABAP for Cloud
Development — see the table in
[ABAP Language Versions](../ABAP%20Language%20Versions#readme), which pairs it with
`GET TIME` and points at `cl_abap_tstmp` / `utclong_current( )` as the cloud-safe
replacements for *time* (not for *duration*).

I could not verify the release status of `CL_ABAP_RUNTIME` for ABAP for Cloud
Development from the keyword documentation this run — the ABAP Cloud mirror of the
documentation was not reachable — so this note deliberately does not claim it either
way. In a cloud-enabled system, check the class in ADT: if it is not released, the
intended instrument is the ABAP Profiler rather than hand-rolled brackets.

## Checklist for a measurement you would show someone else

1. **Bracket as little as possible.** No screens, no file or RFC access, no `WAIT`,
   nothing that can roll the session out.
2. **Measure the empty section too**, and subtract it.
3. **Repeat the section** enough times to clear the resolution, and **repeat the whole
   measurement** enough times to average out noise. Report the mean *and* say how many
   runs it was.
4. **Keep the section well under 1000 s**, and remember one session clock covers about
   2147 s in total.
5. **Divide into a typed result field**, never inside a string template, and never into
   an inline declaration.
6. **Say whether the caches were warm**, and whether the figure is a first run or a
   steady-state mean.
7. **Use `CL_ABAP_RUNTIME` in anything reusable**, so you never touch the session-wide
   precision setting.
8. **Do not use any of this to find out what is slow.** Use the ABAP Profiler (or SAT)
   for that, then use these statements to confirm an improvement in the one place the
   profiler pointed at.

## Quick reference

| Task | Form |
|---|---|
| Open a measuring section | `GET RUN TIME FIELD DATA(t1).` |
| Close it, get the interval | `GET RUN TIME FIELD DATA(t2).` then `t2 - t1` (microseconds) |
| Offset of the measurement | two reads with nothing between them, averaged |
| Reusable / library measurement | `cl_abap_runtime=>create_hr_timer( )` then `timer->get_runtime( )` |
| Lower precision, per object | `cl_abap_runtime=>create_lr_timer( )` |
| Session-wide precision | `SET RUN TIME CLOCK RESOLUTION {HIGH\|LOW}.` — before the first read, or it dumps |
| Largest `i` microsecond value | `cl_abap_math=>max_int4` (about 2147 s) |
| Restrict a SAT trace to a section | `SET RUN TIME ANALYZER ON.` / `OFF.` (needs `Particular Units` in SAT) |
| Same, without touching the source | `CL_ABAP_TRACE_SWITCH=>ON( )` / `=>OFF( )` |
| Wall-clock instead of duration | `utclong_current( )`, `GET TIME STAMP` — see [Time Stamps](../Time%20Stamps#readme) |

## Defects in the source documentation, as of release 754

Noted so a reader who checks the originals is not confused by them:

1. The `GET RUN TIME` page sentence about roll-out ends with no full stop —
   "rolled out of the memory In a conceptual sense ..." — so two sentences read as one.
2. The same page says "The maximum resolution of the **command** `GET RUN TIME`", where
   the documentation otherwise consistently says *statement*.
3. The `CL_ABAP_MATH` page is missing a word: "constants with the limits of the value
   ranges built-in numeric types".
4. The packed-timestamp page runs two sentences together as well: "the ABAP Dictionary
   type `TIMESTAMPL` The digits of the packed number ...".
5. The `SET RUN TIME CLOCK RESOLUTION` platform list — AIX, SINIX, SUN-OS, Linux,
   IBM i5/OS (previously OS/400), Windows — has not been maintained; SINIX and OS/400
   place the text decades before the release it ships with. The *list* is therefore
   weak evidence about a modern platform, while the *warning* it belongs to is not.

## Sources

All quotations were verified verbatim against release 754 of the ABAP keyword
documentation, which is the mirror that serves this page family as static HTML:

- [`GET RUN TIME`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABAPGET_RUN_TIME.htm)
- [`SET RUN TIME CLOCK RESOLUTION`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABAPSET_RUN_TIME_CLOCK_RESOLUTION.htm)
- [`SET RUN TIME ANALYZER`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABAPSET_RUN_TIME_ANALYZER.htm)
- [`System Class for Runtime Measurements` (`CL_ABAP_RUNTIME`)](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENCL_ABAP_RUNTIME.htm)
- [`Runtime Measurements` (section overview)](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENABAP_RUNTIME_MEASUREMENTS.htm)
- [`Runtime Measurement of Database Reads` (example)](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENGET_RUN_TIME_ABEXA.htm)
- [`WAIT UP TO`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABAPWAIT_UP_TO.htm)
- [`arith_exp - Calculation Type and Calculation Rules`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENARITH_TYPE.htm)
- [`arith_exp - Arithmetic Operators`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENARITH_OPERATORS.htm)
- [`Predefined Numeric Types`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENBUILTIN_TYPES_NUMERIC.htm)
- [`System Class CL_ABAP_MATH`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENFLOATING_POINT_CLASS.htm)
- [`Representation of Time Stamps in Packed Numbers`](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENTIME_STAMPS_PACKED.htm)
- [`runtime analysis` (glossary)](https://help.sap.com/doc/abapdocu_754_index_htm/7.54/en-US/ABENRUNTIME_ANALYSIS_GLOSRY.htm)

## Related notes in this repository

- [Time Stamps](../Time%20Stamps#readme) — the wall-clock half: `utclong`, `TIMESTAMPL`, `cl_abap_tstmp`
- [Table Buffering](../Table%20Buffering#readme) — why the second measurement is faster than the first
- [Table Memory](../Table%20Memory#readme) — measurement that changes what it measures
- [Mass Data Processing](../Mass%20Data%20Processing#readme) — `PACKAGE SIZE`, cursors, and why a `WAIT` cannot go there
- [Row Limiting & Ordering](../Row%20Limiting%20and%20Ordering#readme) — `CL_DEMO_SELECT_SINGLE_VS_UP_TO`, SAP's own measurement demo
- [Numeric Arithmetic](../Numeric%20Arithmetic#readme) — calculation types, rounding and overflow in general
- [Checkpoints](../Checkpoints#readme) — assertions and log points, the other kind of instrumentation
- [Pragmas & Pseudo Comments](../Pragmas%20and%20Pseudo%20Comments#readme) — the Code Inspector side of program checking
- [ABAP Language Versions](../ABAP%20Language%20Versions#readme) — what is banned in ABAP for Cloud Development
- [Commit Work Events](../Commit%20Work%20Events#readme) and [Update Task](../Update%20Task#readme) — what an unexpected database commit costs you
