# String Templates & Formatting Options — the `WIDTH` that cannot truncate, the `ALPHA` length that comes from the target field, and the `CURRENCY` that re-reads your digits

`|{ ... }|` is the first piece of modern ABAP most people adopt, and the last one
they read the documentation for. The traps below are not syntax errors and not
dumps: they are a column that stops lining up, a material number that loses its
leading zeros in one code shape and keeps them in another, and an amount whose
decimal point lands in the wrong place without rounding ever happening.

The repo's [String Building & Substring Access](../String%20Processing#readme) note
covers how templates are *assembled* (`&&`, trailing blanks, the quadratic append).
This note covers how an embedded expression is *formatted* on the way in.

---

## 0. The baseline: the predefined format is deliberately dumb

Before any formatting option, an embedded expression is converted by fixed rules:

> For character-like data types with fixed lengths (`c` and `n`) and the date/time
> types (`d`, `t`), the content is passed ignoring trailing blanks. The content of
> text strings with the type `string` is passed completely.

> - For negative values, the minus sign is placed on the left of the number, without a blank. No sign is placed in front of positive numbers by default.
> - The period (`.`) is always used as the decimal separator.
> - **No** thousands separators are inserted.

— [Predefined Formats](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_TEMPLATES_PREDEF_FORMAT.html)

And the sentence that explains why `|{ sy-datum }|` looks "unformatted":

> Unlike in `WRITE TO`, no formatting is applied to the data types `d` and `t` and
> no separators are inserted if no formatting options are specified explicitly.

```abap
" sy-datum = 05.10.2026 for a user with a DD.MM.YYYY mask
WRITE sy-datum.          " -> 05.10.2026   (user-dependent)
DATA(lv) = |{ sy-datum }|.  " -> 20261005   (always)
```

This is the right default for anything a machine reads — files, keys, logs, JSON.
Every trap in this note is some version of *overriding that default by accident*.

---

## 1. `WIDTH` can only make the result longer, never shorter

> If the value of `len` is less than the minimum required length, it is ignored.
> This means that the predefined length cannot be reduced but only increased.

— [`format_options`, `WIDTH`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCOMPUTE_STRING_FORMAT_OPTIONS.html)

So `WIDTH` is a **minimum**, not a field width. A fixed-width export built out of
`WIDTH =` options is correct until the first value that is one character too long,
and then that row — and only that row — shifts every column to its right. The
receiver's positional parser reads the neighbouring field's first characters as
this field's last characters, which is a data error, not a format error, so it
gets reported back as bad master data.

```abap
" Looks like a 10-character column. Is not.
DATA(ok)  = |{ 'HAMBURG'   WIDTH = 10 }|.  " 'HAMBURG   '  -> 10
DATA(bad) = |{ 'FRANKFURT-ODER' WIDTH = 10 }|. " 14 chars, WIDTH ignored
```

If you need a real column, pad **and** cut:

```abap
DATA(col) = |{ lv_city WIDTH = 10 }|.   " pads up to 10
col = col(10).                          " the ceiling WIDTH never applies
```

`ALIGN` and `PAD` only do anything when `WIDTH` is larger than the minimum length,
so a `WIDTH` that was ignored silently disables your alignment too. `PAD` takes the
first character of its argument, and blanks are used if it is an empty string.
See also the fixed-width export section of the
[File Interface](../File%20Interface#readme) note, where `TRANSFER` in text mode
deletes trailing blanks and undoes the padding a second time.

---

## 2. `ALPHA`: the result length comes from the **target field**, until it doesn't

This is the worst one, because the same value and the same option produce two
different answers depending on the *shape* of the surrounding code.

> If the formatting option `WIDTH` is not specified and a string template with a
> single embedded expression consisting of a single data object (not an
> [expression](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENEXPRESSION_GLOSRY.html))
> is assigned to a fixed-length target field of type `c`, `n`, `d`, or `t`, the
> length of the target field determines the available length. Otherwise, the length
> of the original data object or expression, including trailing blanks, is used.

Read the preconditions again — *all* of them have to hold. Each of these breaks the
rule and falls back to "length of the original data object":

- specifying `WIDTH`
- wrapping the operand in anything at all - `to_upper( x )`, a table expression, a concatenation
- adding one character of literal text to the template
- assigning to a `string` instead of a fixed-length field

The documentation's own example, with `text` of type `c LENGTH 20`:

```abap
text = |{ '1234' ALPHA = IN }|.              " length 20 -> 16 zeros, then '1234'
text = |{ to_upper( '1234' ) ALPHA = IN }|.  " length 4  -> '1234', no zeros at all
text = |ALPHA:{ '1234' ALPHA = IN }|.        " length 4  -> 'ALPHA:1234'
```

> In the first assignment, the length of the target object `20` is used for the
> result of `ALPHA` and assigned to `text`. [...] In the second assignment, the
> length `4` of the argument of the built-in function `to_upper` is used where
> _1234_ exactly fits in.

And the version that actually destroys data — same source value `'0000012345'`,
same option, two targets of `c LENGTH 5`:

```abap
DATA(text)  = '0000012345'.               " c LENGTH 10
DATA(texts) = VALUE texts( ( text ) ).    " table of the same type

target1 = |{ text ALPHA = IN }|.          " -> '12345'
target2 = |{ texts[ 1 ] ALPHA = IN }|.    " -> '00000'
```

> - _12345_ in `target1`
>   The length of the result of the string template is the length of the target
>   field which is 5. The result is the right-aligned string of digits _0000012345_
>   where the leftmost _00000_ are truncated. [...]
> - _00000_ in `target2`
>   Since the embedded expression is a table expression, the length of the result
>   of the string template is the length of the original field which is 10. The
>   result is the full content _0000012345_. When assigning this to `target2`, the
>   rightmost _12345_ is truncated.

Note *which* component truncates in each case. In `target1` the template knew the
target length and right-aligned into it. In `target2` the template produced 10
characters and the ordinary fixed-length **assignment** cut the right-hand end —
`ALPHA` is not involved in the loss at all. Reading `texts[ 1 ]` out into a
variable first is not a cosmetic refactor; it changes the output.

Two defences:

- Never let `ALPHA` infer a length. State `WIDTH` explicitly and the first rule
  cannot apply: `|{ lv_matnr ALPHA = IN WIDTH = 18 }|`.
- `ALPHA` cannot be combined with anything except `WIDTH` and `CASE`, which is a
  useful signal: if you need `ALPHA` *and* something else, you need two steps.

Behaviourally `ALPHA = IN`/`OUT` are the conversion exit:

> The formatting option `ALPHA` has the same function as the conversion routines
> `CONVERSION_EXIT_ALPHA_INPUT` or `CONVERSION_EXIT_ALPHA_OUTPUT` implementing
> conversion exit `ALPHA`.

...which is why the [Conversion Routines](../Conversion%20Routines#readme) note's
rule applies here too: if the string is not an uninterrupted run of digits, both
`IN` and `OUT` do nothing to it except left-align it and pad with blanks.

---

## 3. The embedded expression is calculation type `i` — the formatting option arrives too late

An embedded expression is a general expression position, so `{ 2 / 3 }` is an
*arithmetic expression*, and arithmetic in ABAP picks its calculation type from the
operands and the target. There is no target here:

> If the [conversion operator](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_OPERATOR_GLOSRY.html)
> is not specified, the [calculation type](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCALCULATION_TYPE_GLOSRY.html)
> of the embedded expression is `i`.

The documented outputs, with and without `DECIMALS`:

```abap
|{ - 2 / 3 }, { CONV decfloat34( - 2 / 3 ) }, { CONV f( - 2 / 3 ) }|
" -1,-0.6666666666666666666666666666666667,-0.66666666666666663

|{ - 2 / 3 DECIMALS = 3 }, { CONV decfloat34( - 2 / 3 ) DECIMALS = 3 }|
" -1.000,-0.667
```

`-1.000` is the tell. `DECIMALS = 3` did exactly what it promised — it formatted a
value that had already been commercially rounded to `-1` by integer arithmetic
before the formatter ever saw it. Adding decimal places to a report does not add
precision back; you have to fix the arithmetic (`CONV decfloat34( ... )`, or a
packed interim variable). See [Numeric Arithmetic](../Numeric%20Arithmetic#readme)
for the full calculation-type hierarchy — this is that rule reappearing in a place
where it is easy to forget there is arithmetic at all.

---

## 4. `CURRENCY` re-interprets the digits — and `+ 0` switches it to a different rule

For a packed field, `CURRENCY` does not round. It **re-reads the digit string** and
puts a separator in a different place:

> In the case of data type `p`, the formatting depends on how the value is specified:
> - If specified as a data object or as a functional method, the decimal places
>   specified in the definition of the data type are completely ignored. Regardless
>   of the actual value and without rounding, a decimal separator is inserted
>   between the digits in the places determined by `cur`.
> - When specifying a value of an arithmetic expression or a
>   [general numeric function](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENGEN_NUM_FUNCTION_GLOSRY.html),
>   `CURRENCY` works as in `DECIMALS`.

Two sentences, two different operations, selected by whether you wrote an operand
or an expression:

```abap
DATA lv_amt TYPE p LENGTH 8 DECIMALS 3 VALUE '1.234'.   " digits: 1234

|{ lv_amt     CURRENCY = 'EUR' }|   " digits re-read: 1234 -> 12.34
|{ lv_amt + 0 CURRENCY = 'EUR' }|   " value rounded to 2 decimals -> 1.23
```

Same field, same currency, the `+ 0` is semantically invisible — and the two
results differ by a factor of ten. (The demo in this folder prints both, so you
can confirm it on your own release rather than taking the arithmetic on trust.) The first form is only correct when the field's
own decimal count already matches the currency's, which is exactly the assumption
that breaks for a `DECIMALS 3` quantity-style field, for `JPY` (0 decimals), and
for the `TCURX` currencies:

> For the numeric data types `i`, `p`, and `f`, for `cur` a currency ID from the
> column `WAERS` of the DDIC database table `TCURC` is expected. Two decimal places
> are used for every currency ID specified, unless it is contained in the
> `CURRKEY` column of the DDIC database table `TCURX`. In this case, the number of
> decimal places is determined from the `CURRDEC` column of the corresponding line
> in the table `TCURX`.

The documented *intended* use is the one where the digit re-read is the point:

> The formatting option `CURRENCY` is useful with currencies from the tables
> `TCURC` or `TCURX` for formatting data objects of types (`b`, `s`), `i`, `int8`,
> or `p` **without decimal places**, whose content consists of currency amounts in
> the smallest unit of the currency.

Two more things it does quietly:

- On `decfloat16`/`decfloat34` it **adds a trailing sign**: "the formatting option
  `CURRENCY` implicitly adds the addition `STYLE cl_abap_format=>o_sign_as_postfix`".
  So a credit amount renders as `123.45-`, which a downstream numeric parser rejects
  or, worse, reads as positive. `SIGN = LEFT` overrides it.
- It does **not** add thousands separators: "The formatting option `CURRENCY` does
  not override the predefined format specifying that thousands separators are not
  inserted." Neither does `DECIMALS`.

`CURRENCY` is mutually exclusive with `DECIMALS`, `STYLE`, `TIMESTAMP`, and
`TIMEZONE`. For the TCURX shift as it affects the stored value rather than the
display, see [Currency Amounts](../Currency%20Amounts#readme).

---

## 5. `USER` and `ENVIRONMENT` make the output depend on who ran the program

`NUMBER`, `DATE`, and `TIME` all default to `RAW` — the dumb, stable format from §0.
The other values hand control to settings outside your code:

| Value | Where the format comes from |
|---|---|
| `RAW` | "The decimal separator is the period (`.`) and no thousands separators are inserted." |
| `USER` | "based on the [user master record](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENUSER_MASTER_RECORD_GLOSRY.html)" |
| `ENVIRONMENT` | the formatting setting of the language environment, i.e. `SET COUNTRY` |

For a screen, `USER` is correct and `RAW` is the bug. For a file, an interface
payload, a database key, or a log line that something else parses, it is the other
way round — and the failure is per-user, so it reproduces for the night-shift
operator in another country and not for you:

```abap
" CSV with NUMBER = USER, for a user with a comma decimal separator:
" 4711;1.234,56;EUR     <- the amount now contains the field separator
```

`DATE = USER` has the same shape: a `DD.MM.YYYY` user and a `MM/DD/YYYY` user write
different files from the same program, and `03.04.2026` is a legal date under both
masks, so nothing anywhere raises an error.

And the hint that makes this hard to catch in a test system:

> If the formatting setting of the language environment has not been set to a
> country-specific format using `SET COUNTRY`, the use of `ENVIRONMENT` has the
> same effect as the use of `USER`.

So `ENVIRONMENT` silently is `USER` until somebody adds a `SET COUNTRY` somewhere up
the call stack — which is a global, session-wide change. The per-expression
alternative with no side effects is the `COUNTRY` option:

> Unlike using the statement `SET COUNTRY` and the parameter `ENVIRONMENT`, there
> are no side-effects when using the formatting option `COUNTRY`. The country
> specification applies only to the current embedded expression and not to all
> subsequent statements from the current internal session.

`COUNTRY` expects a `LAND1` value from `T005X`, raises `CX_SY_STRG_FORMAT` if it is
neither in the table nor initial, and falls back to the user master record when
initial. `NUMBER`, `DATE`, `TIME`, `TIMESTAMP`, and `COUNTRY` are mutually
exclusive. Note also that 12-hour time is only reachable through
`USER`/`ENVIRONMENT`/`COUNTRY` — `TIME = ISO` is always 24-hour.

---

## 6. A packed time stamp is just a number until you name it

`utclong` formats itself. A time stamp stored in a packed field does not:

> Whereas the time stamp format `ISO` is already predefined for the data type
> `utclong`, and works even without a formatting option, the numeric format is
> predefined for time stamps in packed numbers. A time stamp represented as a
> packed number is identified and formatted as a time stamp only by using the
> formatting options `TIMESTAMP` or `TIMEZONE`.

```abap
DATA lv_tsp TYPE timestamp VALUE '20261005081500'.

|{ lv_tsp }|                      " -> 20261005081500        (a number)
|{ lv_tsp TIMESTAMP = ISO }|      " -> 2026-10-05T08:15:00
```

Only `p LENGTH 8` without decimals (`TIMESTAMP`) and `p LENGTH 11` with 7 decimals
(`TIMESTAMPL`) are accepted; anything else is "a syntax or runtime error".

Then the two asymmetries between the two storage forms, both of which favour the
packed field misleading you:

**Invalid values.** For `utclong`, "Invalid values raise a catchable exception from
the class `CX_SY_CONVERSION_NO_DATE_TIME`". For a packed number:

> A packed number that does not represent a valid UTC time stamp according to the
> POSIX standard is formatted as a time stamp, where for negative values the
> absolute value is respected. If the formats `USER` and `ENVIRONMENT` are used,
> an asterisk _*_ is inserted before the date and the last position of the time is
> cut off.

So garbage in a `TIMESTAMP` field is rendered as a plausible-looking time stamp,
with the only warning being a single `*` that appears in two of the four formats
and costs you the last digit of the time.

**An unknown time zone.** With `TIMEZONE = tz` where `tz` is not in `TTZZ`:

> - For the time stamp type `utclong`, a catchable exception of the class
>   `CX_SY_CONVERSION_NO_DATE_TIME` is raised.
> - For time stamps in packed numbers, the time zone UTC is used implicitly.

The packed branch produces a local time that is silently wrong by the offset you
were trying to apply. If you store time stamps as packed numbers, validate `tz`
against `TTZZ` yourself. More on both representations in
[Time Stamps](../Time%20Stamps#readme).

An initial `utclong` is not `00000000`, it is blanks: "An initial expression of the
type `utclong` is represented as a character string filled with spaces whose length
is that of the result for a valid time stamp" — so `IF lv_text IS INITIAL` on the
formatted result is true for an initial time stamp and false for a valid one, which
is usually what you want, but it also means a fixed-width file gets 27 blanks
instead of a zero-filled field.

---

## 7. `DECIMALS` outside 0..n: one branch rescales, one branch is uncatchable

> If the content of `dec` is less than 0, it is handled like 0, whereby the content
> of data objects of data types (`b`, `s`), `i`, `int8`, or `p` is multiplied by 10
> to the power of `dec` beforehand.

A negative `DECIMALS` is therefore not ignored and not an error — it **divides the
number**. `DECIMALS = -2` on an integer shows it a hundred times smaller, with no
decimal places and no indication anything happened. Same failure shape as
`UP TO 0 ROWS` in the [Row Limiting & Ordering](../Row%20Limiting%20and%20Ordering#readme)
note: a page size or precision that arrives as a negative number from configuration
turns into a silent transformation rather than a complaint.

The upper bound behaves in the opposite, louder way: for `i`/`int8`/`p`,

> The content of `dec` must not exceed 14, otherwise an uncatchable exception is
> raised.

Uncatchable — `TRY`/`CATCH` does not help, and a `DECIMALS = (lv_dec)` driven by a
customizing table can take the program down. For `f`, "If the content of `dec` is
greater than 16, it is handled like 16" — a third rule for the same option. For
`utclong`, "The content of `dec` must be between 0 and 7" and an invalid value
raises the catchable `CX_SY_CONVERSION_NO_DATE_TIME`.

---

## 8. The small print worth knowing once

**Syntax.** At least one blank is required after `{` and before `}`. In literal
text, "blanks in string templates are always significant", and `|`, `{`, `}`, `\`
must each be escaped with `\`. A template that is nothing *but* literal text is
still evaluated at runtime:

> A standalone string template that contains nothing but literal text is not
> handled like a literal but evaluated as an expression during runtime, even if it
> is not part of an expression. For such operands, a text string literal with
> backquotes should be used instead, for performance reasons.

So `lv_x = |ERROR|.` is measurably worse than `lv_x = `ERROR`.` for no benefit.

**Evaluation order.** Embedded expressions are evaluated left to right, and:

> If an embedded functional method modifies the value of data objects that are also
> used as embedded operands, the change only affects data objects on the right of
> the method.

Reordering two placeholders in a message can therefore change the values printed.

**Dynamic options.** Every keyword value has a `CL_ABAP_FORMAT` constant, specified
as `(dobj)` *in parentheses* — `|{ lv_n NUMBER = (lv_fmt) }|` where `lv_fmt` holds
`cl_abap_format=>n_user`. The parentheses are mandatory to distinguish the data
object from a keyword.

**`ZERO = NO`** renders the value zero as an empty string. Useful on a screen,
destructive in a file where an empty numeric field is not the same as `0`.

**`CASE`** applies to more than letters in text: the `e`/`E` of an exponent, the
hex digits of an `x` field, and "In a time stamp type, a `T` between date and time
is affected". It is ignored for the character supplied by `PAD`.

**`XSD = YES`** produces the asXML representation of the value — this is how you get
a real `true`/`false` out of an `XSDBOOLEAN`, and it is the one formatting option
that is nearly exclusive: it combines only with `WIDTH`, `ALIGN`, `PAD`, `CASE`, and
`ZERO`. Its exceptions behave differently from the serializer:

> Unlike `CALL TRANSFORMATION`, exceptions that can be raised during mapping are not
> wrapped but must be handled directly.

(See [JSON & XML Serialization](../JSON%20Serialization#readme) for the wrapped
case.)

**`STYLE`** is the recommended front door for numeric output — "It is best to use
the formatting option `STYLE` for the formatting of all numeric output" — with
`SIGN_AS_POSTFIX` giving commercial notation (trailing sign, trailing zeros cut),
`SCALE_PRESERVING` keeping them, and `SCIENTIFIC`/`ENGINEERING` for exponents.
`DECIMALS` "cannot be specified for output formats that preserve scaling".

---

## Quick reference

| You wrote | What actually happens |
|---|---|
| `WIDTH = 10` on a 14-char value | ignored; result stays 14, and `ALIGN`/`PAD` do nothing |
| `ALPHA = IN` with no `WIDTH` | length taken from the fixed-length target — unless the operand is an expression, or there is literal text, or the target is a `string` |
| `{ 2 / 3 DECIMALS = 3 }` | `1.000` — calculation type `i` rounded first |
| `{ p_field CURRENCY = 'X' }` | digits re-read, declared decimals ignored, no rounding |
| `{ p_field + 0 CURRENCY = 'X' }` | value rounded to the currency's decimals |
| `CURRENCY` on a `decfloat` | implicit `SIGN_AS_POSTFIX` — sign moves to the right |
| `NUMBER = USER` in a CSV | thousands separator from the user master record, inside your field |
| `ENVIRONMENT` without `SET COUNTRY` | identical to `USER` |
| `{ packed_ts }` | a 14-digit number, not a time stamp |
| `TIMEZONE = 'XXXX'` on packed | silently UTC (`utclong` raises instead) |
| `DECIMALS = -2` | value divided by 100 |
| `DECIMALS = 15` on `i`/`p` | **uncatchable** exception |
| `ZERO = NO` | `0` becomes an empty string |
| `lv = \|TEXT\|.` | runtime expression; use `` `TEXT` `` |

---

## Sources

- [String Templates (`string_tmpl`)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_TEMPLATES.html)
- [`literal_text`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_TEMPLATES_LITERALS.html)
- [`embedded_expressions`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_TEMPLATES_EXPRESSIONS.html)
- [Predefined Formats](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_TEMPLATES_PREDEF_FORMAT.html)
- [`format_options`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCOMPUTE_STRING_FORMAT_OPTIONS.html) — the full option list, every quote in §1 and §4–§8
- Runnable demo in this folder: [`ydj_string_template_demo.abap`](ydj_string_template_demo.abap)
