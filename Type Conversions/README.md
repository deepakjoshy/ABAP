# Type Conversions & Lossless Assignment | The Text That Becomes 42, the Date Difference That Is 0 & the `EXACT` That Checks Nothing

ABAP will assign almost anything to almost anything. That is a deliberate design
decision, not an accident, and the keyword documentation says so in the
programming guideline itself:

> "The ABAP conversion rules are based on the philosophy that assignments should
> be allowed between as many combinations of values as possible, without raising
> exceptions. In this situation, ABAP behaves quite differently from other
> programming languages."
> -- [Using Conversion Rules](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/using-conversion-rules?locale=en-US&version=classic_2025)

The consequence is that the dangerous conversions are the ones that **succeed**.
A conversion that dumps is a bug you fix on the first test run. A conversion that
quietly invents a plausible number is a bug that reaches production, because
`sy-subrc` is untouched, no exception is raised and the field is populated with
something that looks deliberate.

SAP ships the canonical example in its own *Bad Example* section:

```abap
DATA text     TYPE string,
     num_text TYPE n LENGTH 8.

text = '4 Apples + 2 Oranges'.
num_text = text.                 " 00000042  -- no exception, no warning
```

> "Anyone who is familiar with all the details of the ABAP conversion rules would
> probably expect an exception when the text in the following source code is
> assigned to the numeric text. However, only the digits of the text are
> respected. Therefore, the target field is given the value *00000042* instead of
> the value *00000007*, which might also be expected."
> -- [Using Conversion Rules](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/using-conversion-rules?locale=en-US&version=classic_2025)

Note that even the *expected wrong answer* is wrong. There is no reading of that
string under which `42` is the number in it.

---

## 1. The same source field is a number or not, depending on the target type

The rule that produced `00000042` is the character-to-`n` rule, and it does not
look for a number at all:

> "The characters in the source field that represent digits are passed
> right-aligned to the target field. Other characters are ignored."
> -- [Source Field Type c](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-c?locale=en-US&version=classic_2025), character-like target fields

Send the *same* string to an `i` instead and ABAP suddenly becomes strict:

> "The source field must contain a number in mathematical or commercial notation,
> otherwise the catchable exception `CX_SY_CONVERSION_NO_NUMBER` is raised."
> -- [Source Field Type c](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-c?locale=en-US&version=classic_2025), numeric target fields

So one source value, two target types, two completely different behaviours:

| Source `'4 Apples + 2 Oranges'` | Target | Result |
|---|---|---|
| digits harvested, everything else dropped | `n LENGTH 8` | `00000042` |
| parsed as a number, fails | `i` | `CX_SY_CONVERSION_NO_NUMBER` |

This matters because `n` is the type of almost every SAP key field --- document
numbers, material numbers, plant, company code. The field most likely to be on
the receiving end of a hand-built string is exactly the field with the rule that
never complains.

`n` is equally relaxed as a *source*. The documentation states plainly that it
does not police its own content:

> "Valid data for data objects of type `n` is in the form of digit-only strings.
> [...] The conversion rules, however, also allow the assignment of numeric text
> fields that contain invalid data. The latter is not recommended."
> -- [Source Field Type n](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-n?locale=en-US&version=classic_2025)

---

## 2. A blank field is the number zero

Every character-to-numeric rule carries the same exception, and it is the one
that costs money:

> "**Exception:** A source field that contains only blank characters is
> interpreted as the number zero."
> -- [Source Field Type c](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-c?locale=en-US&version=classic_2025)

For `string` the same thing is spelled out for the empty case:

> "If the source field has a length of 0, the target field is assigned the value 0."
> -- [Source Field Type string](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-string?locale=en-US&version=classic_2025)

Put the two rules side by side and the asymmetry is the problem:

- **Garbage input raises an exception.** You will find this in testing, because
  testers type garbage.
- **Missing input silently becomes `0`.** Nobody tests the empty field, and `0`
  is a legal quantity, a legal amount and a legal percentage.

An interface field that failed to arrive therefore does not fail --- it books a
zero. If the number is a quantity you ship nothing; if it is a price you invoice
nothing; if it is a divisor you get a different dump much later, in unrelated
code. The guard is a lossless assignment (section 5) or an explicit
`IS INITIAL` check *before* the conversion, not after it.

---

## 3. Whether a literal is a number depends on the target type too

`1.123E+3` is a number in scientific notation. Whether ABAP agrees depends
entirely on what you are assigning it to --- and the documentation makes the
point with its own example:

```abap
DATA(scientific) = '1.123E+3'.

TRY.
    DATA(result) = CONV i( scientific ).          " CX_SY_CONVERSION_NO_NUMBER
  CATCH cx_sy_conversion_no_number.
    result = CONV decfloat34( '1.123E+3' ).       " 1123
ENDTRY.
```

> "The first conversion raises an exception, since numbers in scientific notation
> cannot be converted to the type `i`."
> -- [Source Field Type c](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-c?locale=en-US&version=classic_2025)

The three notations are not interchangeable. For an `i` or `p` target,
"Scientific notation is not allowed, unless it can be interpreted as a
mathematical notation"; for an `f` target it is the reverse --- scientific is
required and "Mathematical or commercial notation is not allowed unless it can
be interpreted as scientific notation". A CSV column that sometimes contains
`1.2E+3` because a spreadsheet reformatted it will convert cleanly into a
`decfloat34` and dump into an `i`.

---

## 4. `n`, `d` and `t` can hold values that are not valid for their own type

This is the structural reason the rest of this note exists. ABAP does not verify
that a field contains something its type permits:

> "For performance reasons, the ABAP runtime framework does not check whether the
> target field contains a valid value after each and every assignment.
> Particularly for target fields of the character-like data type `n` and the
> date/time types `d` and `t`, the conversion rules allow any characters as the
> result of an assignment."
> -- [Avoiding Invalid Values](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/avoiding-invalid-values?locale=en-US&version=classic_2025)

Only digits are valid in `n`, only `YYYYMMDD` in `d`, only `HHMMSS` in `t`. A
`d` field holding `'31'` followed by six blanks is perfectly constructible, and nothing
will tell you until arithmetic touches it. SAP ships the worked example:

```abap
DATA: date1  TYPE d,
      date2  TYPE d,
      result TYPE i.
date1 = '07092009'.
date2 = '16092009'.
result = date2 - date1.          " 0, not 9
```

> "The literals can be transferred to the date fields, without raising an
> exception, to give the values 07092009 and 16092009. Unfortunately, these are
> interpreted as 09.20.0709 and 09.20.1609, which are invalid dates. During the
> calculation, they are both converted to the value 0 and the result is 0.
> Looking at the dates, you would expect the result to be 9."
> -- [Avoiding Invalid Values](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/avoiding-invalid-values?locale=en-US&version=classic_2025)

Two invalid dates subtract to `0`, which is also what two *identical* dates
subtract to. The failure is indistinguishable from the legitimate same-day case.
A day-count that silently reads `0` will pass an SLA check, skip a dunning run
or classify an invoice as current.

The character-to-`d` rule is the one that let it through:

> "If, when converting to the type `d`, the source field does not contain a valid
> date in the format *yyyymmdd* in the first eight places, the target field
> contains an invalid date after the conversion."
> -- [Source Field Type c](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-c?locale=en-US&version=classic_2025)

Two further points on `d` that catch people:

- **The initial value of a `d` field is itself invalid.** "Since the initial
  value for variables of type `d` is itself not a valid value, a suitable start
  value must always be specified by using the addition `VALUE`." So
  `DATA ld_x TYPE d.` starts life holding something no calendar
  accepts, which is why a date field that is never explicitly filled needs
  an `IS INITIAL` branch before any arithmetic touches it.
- **The valid-date boundary differs between ABAP and ABAP SQL.** The initial
  value "is interpreted as valid for a lossless assignment, but the value
  *00010101* is considered to be a valid date only in ABAP SQL". Same byte
  pattern, two verdicts, depending on which layer is looking.

---

## 5. `EXACT` --- the one operator that checks

`EXACT type( dobj )` performs a **lossless assignment**: it checks the value
before converting it, and raises instead of inventing something.

> "A lossless assignment checks the assigned content, before its conversion to an
> incompatible target object, to determine whether the assignment is possible
> without losses, that is:
> - whether it is a valid value for the data type of the source
> - whether a conversion to the target field would lead to a loss of values
> - whether the value is valid for the target field after conversion"
>
> "If the source contains a valid value and no values are lost, the conversion is
> performed in accordance with the associated conversion rules. Otherwise no
> assignment is made."
> -- [Lossless Assignments, Rules](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/lossless-assignments-rules?locale=en-US&version=classic_2025)

The same two lines of the earlier bad example, fixed:

```abap
TRY.
    num_text = EXACT #( text ).
  CATCH cx_sy_conversion_error.
    " 4 Apples + 2 Oranges never silently becomes 42
ENDTRY.
```

Catch `CX_SY_CONVERSION_ERROR` rather than a leaf class: the exception raised "is
generally a subclass of `CX_SY_CONVERSION_ERROR`", and which subclass you get
depends on the type pair.

Two conveniences worth knowing:

- The offending value is **on the exception object**: "the VALUE attribute of the
  exception object is assigned this value in character form and this value is
  generally also included in the exception text". You can log what arrived
  without re-reading the source field.
- Static detection is a syntax error, not a runtime surprise: "If it is already
  known statically that one of the prerequisites is violated, a syntax error
  occurs."

`EXACT` also upgrades failure modes. For a conversion that is forbidden outright
(section 8), the documentation notes:

> "When the operator `EXACT` is used, a catchable exception is always raised at
> runtime when a forbidden conversions is made, in particular, when an attempt is
> made to convert between `d` and `t`. In all other cases, an attempted conversion
> of this type raises an uncatchable exception."
> -- [Checking Elementary Data Objects](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/checking-elementary-data-objects?locale=en-US&version=classic_2025)

(The grammatical slip is SAP's, quoted as printed.) So `EXACT` turns a short dump
into something `TRY` can handle.

---

## 6. `EXACT` on a field of the right type checks **nothing**

This is the trap worth remembering from this whole note. Lossless checks only
happen when a conversion happens. Hand `EXACT` a value that is already the target
type and it validates nothing at all:

> "No checks are made for:
> - compatible data types
>
> The content of the argument is passed to the return value without being
> converted, even if it already contains an invalid value."
> -- [Lossless Assignments, Rules](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/lossless-assignments-rules?locale=en-US&version=classic_2025)

So the instinctive defensive move --- wrapping the suspicious date field you were
handed in `EXACT d( ... )` --- is a no-op. The invalid date passes straight
through, and you have added a `TRY` block that can never trigger. ABAP will tell
you, but only as a warning: "A syntax check warning is produced if it is known
statically that no checks are performed for the combination of argument and
target type, making EXACT superfluous."

The documented workaround is to force an incompatible pair by routing through a
string first, which is why SAP's own *Good Example* looks redundant but is not:

```abap
TRY.
    result = EXACT d( CONV string( date2 ) ) -
             EXACT d( CONV string( date1 ) ).
  CATCH cx_sy_conversion_no_date.
    ...
ENDTRY.
```

> "Since the EXACT operator does not perform a check for compatible types, the
> data fields are first converted to temporary text strings, and these are
> checked."
> -- [Avoiding Invalid Values](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/avoiding-invalid-values?locale=en-US&version=classic_2025)

`CONV string( date )` is not decoration. It is what makes the following `EXACT`
do any work.

The same rule has a second edge: `EXACT` cannot protect a field at its point of
*declaration*, because a `VALUE` start value is a compatible assignment.

> "Other types of assignments that require a start value to be specified in the
> declaration using `VALUE` can create invalid values that are then not
> recognized when a lossless assignment is made to a compatible target field."
> -- [Lossless Assignments, Rules](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/lossless-assignments-rules?locale=en-US&version=classic_2025)

And after a caught exception, do not read the target --- in either direction:

> "After an exception, the content of the target field is undefined and should not
> be used. After an exception, the target field can contain either the previous
> value or an invalid value (the latter is the case after an overflow of a
> floating point number, for example)."
> -- [Conversion Rules for Elementary Data Objects](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/conversion-rules-for-elementary-data-objects?locale=en-US&version=classic_2025)

> "If an operand contains an invalid or inappropriate value, this is assigned to
> its return value, even if the operator `EXACT` is used."
> -- [Checking Elementary Data Objects](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/checking-elementary-data-objects?locale=en-US&version=classic_2025)

---

## 7. A unary plus changes which rule set `EXACT` applies

`EXACT` is two operators wearing one name. Which one you get depends on whether
its argument parses as an arithmetic expression:

> "A constructor expression with the lossless operator `EXACT` performs either a
> lossless assignment or a lossless calculation, depending on the specified
> operand `dobj`"
> -- [EXACT, Lossless Operator](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/exact-lossless-operator?locale=en-US&version=classic_2025)

The documentation demonstrates the difference with one character. For a generic
`TYPE data` parameter holding a time being assigned to a `d` field,
`p2 = EXACT #( p1 )` raises `CX_SY_CONVERSION_EXACT_NOT_SUP` --- but:

> "If the assignment is replaced with `p2 = EXACT #( + p1 )`, a lossless
> calculation is produced and no exception is raised."
> -- [EXACT, Lossless Operator](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/exact-lossless-operator?locale=en-US&version=classic_2025)

A leading `+` that looks like formatting noise reroutes the operand through the
calculation path, where the calculation type is `decfloat34` and the forbidden
type pair never arises. Do not add or remove a sign to tidy up an `EXACT`.

The calculation form has its own exception, and it is the useful one:

```abap
TRY.
    DATA(exact_result) = EXACT #( 3 * ( 1 / 3 ) ).
  CATCH cx_sy_conversion_rounding INTO DATA(exc).
    DATA(rounded_result) = exc->value.      " the rounded result, recoverable
ENDTRY.
```

`3 * ( 1 / 3 )` cannot be represented exactly, so `EXACT` refuses to pretend --- and
hands you the rounded value on the exception if you want it anyway. This is the
direct counterpart to the silent interim rounding documented in the
[Numeric Arithmetic](../Numeric%20Arithmetic#readme) note: there, calculation
type `i` rounds every step and says nothing.

One more default worth knowing: with `EXACT #( )`, if the type cannot be derived
from context, "the calculation type `decfloat34` is used in lossless calculations
and the data type of the operand is used in lossless assignments" --- two
different fallbacks for the same `#`.

---

## 8. Some conversions are forbidden regardless of the value

`EXACT` rejects these pairs on type grounds alone, before looking at content:

> "- From `x`, `xstring` to `n`, `d`, `t`, and vice versa.
> - From `x`, `xstring` to all numeric data types, and vice versa.
> - From `d` and `t` to `b` and `s`"
> -- [Checking Elementary Data Objects](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/checking-elementary-data-objects?locale=en-US&version=classic_2025)

The stated reason is that these are the pairs "for which the values are always
lost when the conversion rules are applied" --- the ordinary rules will happily
produce a result, so `EXACT` refuses rather than endorse it. Converting `x` to a
numeric type and back is the classic bit-twiddling idiom in legacy code, and
`EXACT` will not bless it.

The same page adds a restriction that is *not* presented as `EXACT`-only:
"Other conversions that are not allowed are conversions in which byte-like
fields are converted directly or as an interim result to the data type i and
vice versa." Read strictly, that is wider than the list above, so treat any
byte-like-to-numeric step as suspect in both directions rather than assuming a
plain assignment is safe.

Independent of `EXACT`, two pairs are simply not allowed: "Conversions from d to
t and vice versa, and most conversions for UTC time stamps of the type utclong
are prohibited regardless of the operator EXACT". Assigning a `p` or an `i` to a
`utclong` is "Not supported. Produces a syntax error or raises the exception
`CX_SY_CONVERSION_NOT_SUPPORTED`" --- use `CL_ABAP_TSTMP=>TSTMP2UTCLONG` or
`CONVERT ... INTO UTCLONG`, as the [Time Stamps](../Time%20Stamps#readme) note
covers.

---

## 9. Character to byte: the first bad character turns the rest into zeros

A hex string arriving from an interface is usually assigned straight into an
`xstring`. If one character is not a hex digit, the conversion does not fail --- it
stops and pads:

> "The first invalid character terminates the conversion from the position of
> this character and the half-bytes not filled up to that point are padded with
> hexadecimal 0."
> -- [Source Field Type c](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-c?locale=en-US&version=classic_2025)

The guideline page calls this out as its illustration of the whole problem:

> "One example of this is the handling of invalid content in the source field in
> assignments from a character-like type to a byte-like type. Instead of exiting
> the assignment with an exception, hexadecimal zeros are passed from the first
> invalid character."
> -- [Using Conversion Rules](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/using-conversion-rules?locale=en-US&version=classic_2025)

So a truncated or whitespace-contaminated hex payload becomes a valid-looking
byte string of the right length, zero-filled from the point of corruption. A
checksum over it will differ; nothing else will complain. SAP's own example
converts `'0123456789ABCDEFXXXXXXX'` and documents the result as
`0123456789ABCDEF` --- the `X` characters vanish silently, and the only safety net
is that a *literal* like that "would produce a warning" in the syntax check,
which a runtime value never does. See [Byte Strings](../Byte%20Strings#readme)
for the code-page side of the same boundary.

---

## 10. Trailing blanks: retyping `c` to `string` changes what assignments do

ABAP ignores trailing blanks in `c` fields and respects them in `string` fields,
and that difference leaks into the conversion rules in both directions:

| Assignment | Trailing blanks |
|---|---|
| `c` -> `c` / `string` / `d` | dropped --- "Trailing blanks in the source field are not passed" |
| `c` -> `t` | **passed** --- the documented exception |
| `string` -> `c` / `d` / `t` | passed --- "with the difference that trailing blanks are passed" |
| `string` -> `utclong` | ignored again |

> "In ABAP, the trailing blanks in source fields of type `c` are ignored, by
> default. An assignment from source type `c` to target type `t` is an exception
> to this rule."
> -- [Source Field Type c](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-c?locale=en-US&version=classic_2025)

So `CONV string( 'abcd    ' )` has length 4 while the literal `` `abcd    ` ``
has length 8. Changing a field from `c LENGTH 20` to `string` --- a common
modernisation --- silently changes the content of everything downstream that is
padded. The [String Processing](../String%20Processing#readme) note covers the
same boundary from the `CONCATENATE` and offset/length side.

One subtlety for non-Unicode double-byte data: right-hand truncation can cut a
character in half, "which generally produces an invalid character at the right
margin"; the documented fix is
`CL_SCP_LINEBREAK_UTIL=>STRING_SPLIT_AT_POSITION`.

And `string` to `string` is not a copy at all --- "the internal reference of the
target field points to the same string as the source field", with a new string
created only on change. That is the same copy-on-write behaviour the
[Table Memory](../Table%20Memory#readme) note documents for internal tables.

---

## 11. Numbers are day counts and second counts, and `0` is not day zero

Assigning an integer to a `d` or `t` field is a documented conversion, not a
mistake, and it is how legacy date arithmetic is written:

> "If the value of the integer is between 1 and 3,652,060, it is interpreted as
> the number of days since 01.01.0001 and the resulting date is placed in the
> target field in the format *yyyymmdd*. If the value is outside this range, the
> target field is padded with the character *0*."
> -- [Source Field Type i, int8, (b, s)](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-i-int8-b-s?locale=en-US&version=classic_2025)

Out of range does not raise --- it fills the field with the character zero, which
is the invalid date from section 4. And the off-by-one at the bottom of the range
is documented explicitly:

> "The assignment of the value 0 to a target field of type `d` produces the value
> *0000000* for an invalid date and not *00010101* for 01.01.0001. The earliest
> valid date that can be created by assigning a number is 02.01.0001 by assigning
> the number 1."
> -- [Source Field Type i, int8, (b, s)](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-i-int8-b-s?locale=en-US&version=classic_2025)

(That `0000000` is seven zeros as printed in the documentation; a `d` field holds
eight characters.) Day `1` is the 2nd of January, not the 1st --- so an
epoch-style day count built by hand is one day out unless you account for it.
Dates in the Julian-to-Gregorian gap cannot be produced at all: 577736 gives
4.10.1582 and 577737 gives 15.10.1582.

For `t`, the value is taken modulo a day: "The value of the integer is divided by
the number of seconds in a day (86,400) and the integer remainder of the division
is interpreted as the number of seconds since midnight". A duration of 25 hours
therefore becomes 01:00:00 with no indication that a day was discarded.

The reverse direction --- numbers formatted into character fields, with the
trailing minus sign and the `*` overflow marker in the first position --- is
covered in the [Numeric Arithmetic](../Numeric%20Arithmetic#readme) note, along
with the `p` to `n` conversion that stores the absolute value and throws the sign
away.

---

## Quick reference

| Situation | What actually happens | What to write instead |
|---|---|---|
| String with digits in it -> `n` | digits harvested, rest ignored, no error | `EXACT #( )` in a `TRY` |
| Blank or empty field -> numeric | silently `0` | check `IS INITIAL` first, or `EXACT` |
| Non-numeric text -> `i` / `p` | `CX_SY_CONVERSION_NO_NUMBER` (catchable) | catch `CX_SY_CONVERSION_ERROR` |
| `'1.2E+3'` -> `i` | raises; the same text into `decfloat34` works | pick the type that matches the notation |
| Reversed date text -> `d` | accepted, invalid, arithmetic yields `0` | `EXACT d( CONV string( x ) )` |
| `EXACT d( some_d_field )` | **no check at all**, plus a syntax warning | route through `CONV string( )` |
| `EXACT #( p1 )` vs `EXACT #( + p1 )` | assignment rules vs calculation rules | do not touch the sign |
| Bad hex text -> `xstring` | truncated at the bad character, zero-padded | validate before converting |
| `c` -> `string` round trip | trailing blanks dropped one way, kept the other | `CONCATENATE ... RESPECTING BLANKS` |
| Integer -> `d` out of range | field filled with character `0` | range-check, remember day 1 = 02.01.0001 |
| Reading the target after a caught conversion error | undefined content | use `exc->value` |

---

## Demo program

[`ydj_type_conversion_demo.abap`](ydj_type_conversion_demo.abap) is a runnable,
read-only report (no database access at all) that reproduces each behaviour above
and prints the result next to the expectation, so the surprising ones can be
confirmed rather than taken on trust:

1. `'4 Apples + 2 Oranges'` into `n LENGTH 8`, and the same value into an `i`.
2. Blank and empty sources into numeric targets.
3. Scientific notation into `i` and into `decfloat34`.
4. The reversed-date subtraction that yields `0`.
5. The same subtraction guarded with `EXACT d( CONV string( ... ) )`.
6. `EXACT #( 3 * ( 1 / 3 ) )` and the rounded value off `exc->value`.
7. A hex string with an invalid character into an `xstring`.
8. Trailing blanks through `c` and through `string`.
9. Integer day counts into `d`, including `0` and an out-of-range value.

Every conversion that can raise is wrapped in `TRY`, so the report runs to
completion and prints the exception text where one occurs.

---

## Sources

All quotations are from the ABAP keyword documentation (Standard ABAP,
`classic_2025`):

- [Conversion Rules for Elementary Data Objects](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/conversion-rules-for-elementary-data-objects?locale=en-US&version=classic_2025) --- the `CX_SY_CONVERSION_ERROR` family, undefined target after an exception
- [Using Conversion Rules](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/using-conversion-rules?locale=en-US&version=classic_2025) --- the programming guideline, the philosophy quote, the 42 example
- [Avoiding Invalid Values](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/avoiding-invalid-values?locale=en-US&version=classic_2025) --- no validity check after assignment, the date subtraction that yields 0
- [Source Field Type c](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-c?locale=en-US&version=classic_2025) --- the full conversion table used throughout this note
- [Source Field Type n](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-n?locale=en-US&version=classic_2025) --- numeric text fields with invalid data
- [Source Field Type string](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-string?locale=en-US&version=classic_2025) --- zero-length sources, trailing blanks, string sharing
- [Source Field Type p](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-p?locale=en-US&version=classic_2025) --- packed sources, `utclong` not supported
- [Source Field Type i, int8, (b, s)](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/source-field-type-i-int8-b-s?locale=en-US&version=classic_2025) --- day counts, the 86,400 rule, big-endian byte targets
- [Character-Like Source Fields](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/character-like-source-fields?locale=en-US&version=classic_2025) --- the three notations
- [EXACT, Lossless Operator](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/exact-lossless-operator?locale=en-US&version=classic_2025) --- assignment vs calculation, `CX_SY_CONVERSION_EXACT_NOT_SUP`
- [Lossless Assignments, Rules](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/lossless-assignments-rules?locale=en-US&version=classic_2025) --- what is checked, what is not
- [Checking Elementary Data Objects](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/checking-elementary-data-objects?locale=en-US&version=classic_2025) --- forbidden type pairs, catchable vs uncatchable
- [Lossless Assignment](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/lossless-assignment?locale=en-US&version=classic_2025) --- the executable `CL_DEMO_MOVE_EXACT` example

---

See also: [Numeric Arithmetic](../Numeric%20Arithmetic#readme) for the calculation
type that decides a result before any conversion happens,
[Currency Amounts](../Currency%20Amounts#readme) for the `TCURX` decimal shift
that no conversion rule knows about,
[Time Stamps](../Time%20Stamps#readme) for `utclong` and the time-zone
conversions that are statements rather than assignments,
[String Processing](../String%20Processing#readme) for trailing blanks in
`CONCATENATE` and offset/length access,
[Character Comparisons](../Character%20Comparisons#readme) for the comparison
type rules, which are a separate set from these assignment rules,
[Byte Strings](../Byte%20Strings#readme) for the code-page conversions behind
`string` to `xstring`,
[Conversion Routines](../Conversion%20Routines#readme) for conversion *exits*
(`ALPHA`), which are a display-layer mechanism and unrelated to these rules,
[Reference Casting](../Reference%20Casting#readme) for `?=`, which is assignment
between *reference* variables and is deliberately excluded from `EXACT`, and
[Corresponding Operator](../Corresponding%20Operator#readme) for the
component-by-component case, where every field pair follows the rules above.

