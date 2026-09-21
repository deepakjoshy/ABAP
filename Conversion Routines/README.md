# Conversion Routines — the ALPHA conversion that silently does nothing

Almost every SAP key field is stored padded: material `000000000000004711`,
customer `0000001000`, sales document `0000004711`. The padding is *not* a
property of the data type — `matnr` is plain `CHAR 18`. It is a property of the
**domain**, which carries a five-character conversion routine name, and that
routine only runs in a small, specific set of places.

Everywhere else — and "everywhere else" includes every `SELECT`, every internal
table comparison, and every JSON payload — you are on your own. The result is
the single most common class of "works in SE16, returns nothing in my program"
bug in ABAP.

This note is the storage-format companion to
[`Character Comparisons`](../Character%20Comparisons#readme) (which covers why
`n` and `c` compare the way they do) and
[`String Building`](../String%20Processing#readme).

---

## 1. Where a conversion routine actually runs

A conversion routine `CNVRT` is two function modules,
`CONVERSION_EXIT_CNVRT_INPUT` (display → ABAP) and
`CONVERSION_EXIT_CNVRT_OUTPUT` (ABAP → display). The keyword documentation lists
exactly where they fire automatically:

> If a dynpro field is defined using a reference to a domain with a conversion
> routine [...] the INPUT function module is executed automatically when entries
> made in the associated screen field are passed to ABAP and the OUTPUT function
> module is executed automatically when ABAP output is passed to the screen field.
>
> If an ABAP data object is declared with reference to a domain with a conversion
> routine, the OUTPUT function module is executed by default when formatting the
> content using `WRITE` or `WRITE TO`.

That is the complete automatic list: **dynpro field in, dynpro field out, `WRITE`,
`WRITE TO`.** Note what is *not* on it:

| Operation | Conversion applied? |
|---|---|
| Dynpro / selection-screen input | **Yes** (INPUT) |
| Dynpro output, `WRITE`, `WRITE TO` | **Yes** (OUTPUT) |
| `SELECT ... WHERE matnr = lv_matnr` | **No** |
| `READ TABLE ... WITH KEY matnr = ...` | **No** |
| `INSERT`/`UPDATE`/`MODIFY` a DDIC table | **No** |
| Assignment `lv_a = lv_b` | **No** |
| String template `\|{ lv_matnr }\|` | **No** (unless `ALPHA =` is given) |
| `CALL TRANSFORMATION` / asJSON | **No** |
| RFC / BAPI parameters | **No** |

So the value that arrived from a dynpro is already internal, and the value you
typed as a literal in your own code is not. This is why the classic bug looks
like this:

```abap
PARAMETERS p_matnr TYPE mara-matnr.       " dynpro -> ALPHA INPUT runs, padded

START-OF-SELECTION.
  SELECT SINGLE * FROM mara INTO @DATA(ls_mara)
    WHERE matnr = @p_matnr.               " works
```

...and the "same" code fails the moment the value stops coming from a screen:

```abap
  DATA(lv_matnr) = CONV matnr( '4711' ).  " literal -> NOT padded
  SELECT SINGLE * FROM mara INTO @DATA(ls_mara)
    WHERE matnr = @lv_matnr.              " sy-subrc = 4, row exists
```

`'4711'` is a perfectly valid `CHAR 18` value. There is no syntax error, no
warning, no short dump — just an empty result set for a row you can see in SE16.
The same applies to a value read from a file, a CSV upload, an RFC parameter, an
OData payload, or a hard-coded customizing constant.

**There is no `WHERE` clause fix.** Do not reach for `LIKE '%4711'` — it is
unindexed, and it also matches `14711`. Convert the value *before* the `SELECT`.

---

## 2. `ALPHA = IN` is not a conversion — it is a conditional conversion

The modern replacement for the two function modules is the `ALPHA` formatting
option in a string template. It is the same logic (the doc says it "has the same
function as the conversion routines `CONVERSION_EXIT_ALPHA_INPUT` or
`CONVERSION_EXIT_ALPHA_OUTPUT`"), but the rule it implements is conditional:

> **IN** — If the character string of the embedded expression only contains an
> uninterrupted string of digits apart from leading and trailing blanks, the
> string of digits is right-aligned in a character string of a certain length,
> which is padded on the left with the digit `0`, if necessary. **Otherwise, the
> characters of the character string of the embedded expression are left-aligned
> in the character string and padded with blanks on the right.**

The `Otherwise` branch is the trap. A non-numeric value is **not** padded and
**not** rejected — it is returned unchanged:

```abap
DATA(lv_num) = |{ '4711'   ALPHA = IN WIDTH = 18 }|.  " 000000000000004711
DATA(lv_alp) = |{ 'A4711'  ALPHA = IN WIDTH = 18 }|.  " 'A4711' + blanks
```

This is correct behaviour — alphanumeric material numbers genuinely are stored
left-aligned — but it means `ALPHA = IN` cannot be used as a validation step.
Garbage in, garbage out, `sy-subrc` untouched. Validate first
(`lv_in CO ' 0123456789'`, see
[`Character Comparisons`](../Character%20Comparisons#readme) for why the leading
blank matters), then convert.

`ALPHA` may only be applied to `string`, `c` or `n`, and the doc states it
"cannot be specified together with other formatting options; apart from `WIDTH`
and `CASE`". Anything else is a syntax error.

---

## 3. The `WIDTH` trap: same value, same option, two different answers

This is the subtlest one, and it is in the documentation as a worked example.
The length of the result is determined as follows:

> If the formatting option `WIDTH` is not specified and a string template with an
> embedded expression **consisting of a single data object (not an expression or
> function call)** is assigned to a fixed-length target field of type `c`, `n`,
> `d`, or `t`, the length of the target field determines the available length.
> **Otherwise, the length of the original field, including trailing blanks, is
> used.**

So the padding width comes from the *target* in one case and from the *source*
in the other — and which one applies depends on the syntactic shape of what you
wrote inside the braces. The doc's own example:

```abap
TYPES text  TYPE c LENGTH 10.
TYPES texts TYPE STANDARD TABLE OF text WITH EMPTY KEY.

DATA(text)  = '0000012345'.
DATA(texts) = VALUE texts( ( text ) ).

DATA target1 TYPE c LENGTH 5.
DATA target2 TYPE c LENGTH 5.

target1 = |{ text        ALPHA = IN }|.   " -> '12345'
target2 = |{ texts[ 1 ]  ALPHA = IN }|.   " -> '00000'
```

Same value, same option, same target type — and the results share no characters.
`target1` uses the target length 5, builds `0000012345`, and truncates on the
**left**, giving `12345`. `target2` is a table expression, so it uses the source
length 10, builds the same `0000012345`, and this time the assignment truncates
on the **right**, giving `00000`.

The practical rules:

- **Always specify `WIDTH` explicitly.** It removes the whole ambiguity.
- Wrapping the operand in *anything* — `CONV`, a method call, a table
  expression, or even adding literal text to the template — flips you out of the
  target-length rule silently.
- `|{ lv_matnr ALPHA = IN }|` assigned to an inline `DATA(...)` is a `string`
  target, not a fixed-length one, so it does **not** pad at all. This is the
  most common form of the mistake:

```abap
DATA(lv_key) = |{ '4711' ALPHA = IN }|.              " '4711' - no padding!
DATA(lv_key) = |{ '4711' ALPHA = IN WIDTH = 18 }|.   " correct
```

Note also that when `WIDTH` *is* specified, it is only used "if it is greater
than the length of the uninterrupted string of digits without leading zeros" — a
`WIDTH` that is too small is ignored rather than truncating, so the output can be
longer than you asked for.

---

## 4. `ALPHA = OUT` loses information

`OUT` strips leading zeros and left-aligns. That is a lossy, one-way trip: once
`0000012345` has become `12345`, the original field length is gone, and re-running
`IN` without the correct `WIDTH` will not restore it. Never store an `OUT`-format
value, never send one to an interface, and never use one as a key. It is a
display format only.

Because it is lossy in exactly this way, `OUT` values that get round-tripped
through a spreadsheet are a standing source of corruption — Excel additionally
strips zeros from anything that looks numeric, so a column of `OUT`-converted
material numbers cannot be reliably converted back at all.

---

## 5. `WRITE` applies the exit — which is why lists and programs disagree

Because `WRITE` and `WRITE TO` run the OUTPUT exit by default, a debugging
`WRITE lv_matnr.` shows `4711` while the variable actually contains
`000000000000004711`. Two consequences:

- Comparing a value you saw in a list against a value you saw in the debugger is
  not a like-for-like comparison. The debugger shows the raw content; `WRITE`
  shows the converted one.
- `WRITE ... TO lv_target` silently produces a *display*-format value that then
  fails as a database key. The keyword doc warns about this statement in general
  terms — it "is mainly suited for formatting data for output purposes but not
  for further internal processing" — and the hidden conversion exit is a large
  part of why.

The default can be overridden per statement with `USING NO EDIT MASK`, and a
routine can be forced with `USING EDIT MASK 'CNVRT'` even on a field whose domain
has none. Note that when `WRITE USING EDIT MASK` is used, the optional `REFVAL`
parameter of the exit is **not** filled — so currency/quantity exits that depend
on the reference field behave differently there than on a dynpro.

---

## 6. Writing your own exit: the constraints are unusually tight

If you implement a `Z` conversion routine, the documented requirements are
stricter than a normal function module:

- Both function modules must live in **the same function group**, and that group
  **cannot contain any other function modules**.
- Mandatory parameters `INPUT` and `OUTPUT`. The `INPUT` parameter must be
  generic in the INPUT conversion, and `OUTPUT` generic in the OUTPUT conversion,
  because the assigned field's type varies by usage.
- `REFVAL` is the one optional parameter filled automatically — for `CURR`/`QUAN`
  dynpro fields it receives the associated `CUKY`/`UNIT` reference field. Any
  other optional parameter is **never** filled automatically.
- **No statement that interrupts the program flow or terminates an SAP LUW.** In
  OUTPUT conversions only termination messages are allowed; INPUT conversions may
  also send error and status messages. No `COMMIT WORK`, no `CALL SCREEN`, no
  `SUBMIT` — see [`Update Task`](../Update%20Task#readme) for the same class of
  restriction.
- No external subroutines, because the program group cannot be determined.
- **Any exception raised in a conversion routine always terminates the program**,
  and these routines can only be debugged with the two-process debugger — which
  is why a faulty exit presents as an un-debuggable dump in unrelated code.

The doc also notes that OUTPUT conversions "need to display very good
performance, since an OUTPUT function module can be called very often in list
output" — a database read inside one will destroy an ALV with 50,000 rows.

---

## Rules of thumb

1. **Convert at the boundary, not at the point of use.** Everything crossing into
   your program (file, RFC, OData, CSV, hard-coded constant) gets converted to
   internal format once, on arrival. Everything inside stays internal.
2. **Always write `WIDTH` explicitly** with `ALPHA = IN`.
3. **Validate before converting** — `ALPHA = IN` will not tell you the input was
   wrong.
4. **Never persist or transmit an `OUT` value.** Display format is for display.
5. When a `SELECT` returns nothing for a key you can see in SE16, check the
   domain for a conversion routine before checking anything else.

---

## Sources

- [Conversion Routines](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-us/abenconversion_exits.htm) — where exits run, function-module requirements, `REFVAL`, LUW restrictions, debugging
- [`embd_exp - format_options`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapcompute_string_format_options.htm) — `ALPHA = IN/OUT/RAW`, the conditional digit rule, the length-determination rule and the `target1`/`target2` example
- [`WRITE, TO`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapwrite_to.htm) — the hint that `WRITE TO` may execute a conversion exit, and that it is unsuited to internal processing
