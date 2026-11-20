# Quantities & Units of Measure — the unit that formats nothing, the two decimal fields that are anagrams, and `UNIT` that is ignored when it matters

The sibling note to [Currency Amounts](../Currency%20Amounts#readme) — and almost
every intuition carried over from there is wrong.

A `CURR` field *is* an integer in the smallest unit of its currency: the currency
key decides where the decimal point goes, and `WRITE ... CURRENCY` re-reads your
digits accordingly. A `QUAN` field is the opposite. Its decimal places are fixed
in the Dictionary, the unit key has **no** say over them, and the one ABAP
statement that looks at the unit at all can only *remove* trailing zeros — and
silently declines to do even that if a non-zero digit would be lost.

> "The number of decimal places for the unit defined using the unit key of type
> UNIT only affects the formatting of a quantity field on a dynpro. It is
> independent of the number given for the quantity field of type QUAN."
> — [DDIC - Quantity Fields](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENDDIC_QUANTITY_FIELD.html)

So: 2 JPY is stored as `0.02`, but 2.5 PC is stored as `2.5` and stays `2.5`
forever, in a system where *pieces* has zero decimal places. Nothing converts
it, nothing rounds it, and nothing complains.

## 1. What a quantity field actually is

> "In case of data type QUAN, a field is automatically interpreted as quantity
> field and a reference to a unit key is mandatory. In case of the other data
> types, this reference is not mandatory, but if it is assigned, it turns the
> field into a quantity field."

Three consequences worth having straight:

- `QUAN` **must** name a reference field of type `UNIT`. You cannot create a
  `QUAN` column and decide the unit later.
- `DECFLOAT16` / `DECFLOAT34` *may* name one. The reference is what makes the
  field a quantity field, not the type.
- The number of decimals on the `QUAN` field is your choice at design time:
  "any number of decimal places can be defined. The default value is no decimal
  places." A quantity field defaulted to 0 decimals truncates every fraction
  that is ever assigned to it, which is normal packed-number behaviour
  ([Type Conversions](../Type%20Conversions#readme)) and not a unit problem at all.

Two smaller facts from the same page that save an afternoon:

> "From a technical perspective, the data type UNIT is handled like a type CHAR
> with length 2."

Do not build on that number. `T006-MSEHI`, the column the doc itself points at
everywhere else, is `UNIT` of **length 3** (data element `MSEHI`, domain
`MEINS`), and SAP's own CDS examples declare parameters as `abap.unit( 3 )`.
Both lengths exist; type your fields from the DDIC element, never from a
hand-written `c LENGTH n`.

> "As in general packed numbers, the number of places in type QUAN should be odd."

## 2. In ABAP, the unit is inert

This is the sentence to remember:

> "The unit defined for a quantity field only plays a part in ABAP programs if
> it is specified after the addition UNIT of the statement WRITE [TO]."

Outside of that one addition the unit key is a `CHAR`-like field that happens to
sit next to a number. In particular:

> "These decimal places are respected for all operations and calculations, as
> for all packed numbers."

— i.e. the *field's* decimals are respected, never the unit's. `lv_kg + lv_g`
compiles, runs, and returns a meaningless number. There is no unit algebra, no
dimension check, and no exception. The repo's
[Numeric Arithmetic](../Numeric%20Arithmetic#readme) note covers what the
packed arithmetic itself does.

And the addition is restricted:

> "The addition UNIT of the statement WRITE [TO] can be used only for quantity
> fields of data type QUAN, not for quantity fields of any other data type."

So a modern `DECFLOAT34` quantity field has *no* unit-aware output option
at all.

**Doc-state note.** The same page contains the sentence

> "When quantity currency fields with ABAP SQL, no special handling takes place."

which is missing a verb (the parallel [DDIC - Currency Fields](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENDDIC_CURRENCY_FIELD.html)
page is the one to read for what it was trying to say). The intent is clear
enough and matches the rest of the page: ABAP SQL does not do unit handling for
you. Flagging it because if you grep the docs for a rule here, this is the
sentence you will land on.

## 3. The headline: `WRITE ... UNIT` only trims, and skips itself when it would lose a digit

`CURRENCY` and `UNIT` look like siblings. They are opposites.

`CURRENCY` **reinterprets your digits** and can change the number a user sees:

> "For data objects of type p, the decimal places specified by the definition of
> the data type are ignored completely. Independently of the actual value and
> without rounding, decimal separators and thousands separators are inserted
> between the digits in the places determined by cur."

`UNIT` **never changes the value shown.** All it can do is cut zeros:

> "This addition cuts off the decimal places that have a value of 0 and that lie
> outside of the accuracy of a measurement unit when formatting data objects of
> data type p. Otherwise, the addition is ignored, except for type f."

and it only applies when nothing would be lost:

> "If the data type of source field is p and has at least as many decimal places
> as specified by unit, and if no other places that are not equal to 0 are cut
> off as a result, the content of the source field is formatted with this number
> of decimal places."

Read that as a guard clause, because that is what it is. **The formatting
depends on the data, not only on the unit.** Same program, same unit, two values:

| Source field | Value | Unit (`T006-DECAN`) | Output | Why |
|---|---|---|---|---|
| `p DECIMALS 1` | `1.0` | `PC` (0) | `1` | zero decimal, safe to cut |
| `p DECIMALS 4` | `2.5000` | `PC` (0) | `2.5000` | cutting would lose the `5` → **addition ignored** |
| `p DECIMALS 4` | `2.5000` | `KG` (3) | `2.500` | one zero cut, `5` kept |
| `p DECIMALS 1` | `1.0` | `KG` (3) | `1.0` | field has *fewer* decimals than the unit → ignored |

(`PC` and `KG` carrying 0 and 3 decimal places is illustrative: `DECAN`
is per-client configuration, not a constant — see §5.)

Nothing about the ignored rows is visible at the call site. A report that lines
up perfectly in test, where every quantity happens to be whole, goes ragged in
production the moment a partial quantity appears — and the column that looks
broken is the one formatted *correctly*.

Three more ways the addition quietly becomes a no-op:

> "unit expects a character-like field that contains a unit code from the column
> MSEHI of the database table T006 in uppercase letters."

> "The system uses column DECAN of the related line in database table T006 to
> determine the number of decimal places. If the content of unit is not found in
> T006, the addition is ignored."

- lowercase `kg` → not found → ignored.
- a unit you typed from memory (`'EA'`, `'PCS'`) that your client does not have
  in `T006` → ignored.
- `DECFLOAT` from the Dictionary → not merely ignored, but excluded:
  "Furthermore, UNIT cannot be used for decimal floating point numbers defined
  in the ABAP Dictionary, because these always have an assigned output format."

There is no `sy-subrc` for any of this. If you need to know whether the unit was
usable, read `T006` yourself first.

Mutual exclusions, because the combination you reach for first is forbidden:

> "This addition cannot be used together with additions DECIMALS, ROUND, STYLE,
> ENVIRONMENT TIME FORMAT, and TIME ZONE."

So you cannot say *format to the unit's accuracy, and round to it* in one
statement — `UNIT` plus `ROUND` is a syntax error, and `UNIT` plus `DECIMALS`
likewise. Rounding to a unit's accuracy is a separate, explicit step (§6).

Two edge behaviours documented on the same page:

> "For data objects of type f, the addition UNIT has the same effect as the
> addition DECIMALS (see above), where the number of decimal places is
> determined by unit."

— for `f`, `UNIT` *does* reformat, so the one type where the trim-only rule does
not hold is the one type you should not be storing quantities in.

> "If the addition CURRENCY is used at the same time, this addition is executed
> first for data type p, and then for the addition UNIT. In this case the
> addition is ignored for data type f as well."

**No string-template equivalent.** The format-option reference for embedded
expressions documents `CURRENCY` (and `ALPHA`, `WIDTH`, `ALIGN`, `PAD`,
`DECIMALS`, `STYLE`, `COUNTRY`, `TIMESTAMP`, ...) and lists **no** `UNIT`
option: see [embd_exp - format_options](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPCOMPUTE_STRING_FORMAT_OPTIONS.html).
Migrating a `WRITE` list to string templates ([String Templates](../String%20Templates#readme))
therefore silently drops unit formatting, while currency formatting survives.
If you need it, `WRITE ... TO lv_text ... UNIT lv_unit` into a character field
is still the documented route.

## 4. On a dynpro the unit *does* matter — via global program data

Dynpro display is the one place the unit's own accuracy is honoured, and the
mechanism is surprising:

> "To determine the unit, the global data of the current ABAP program is searched
> for the reference field associated with the field for the unit key."

> "It does not have to be present on the dynpro itself."

So the formatting of a quantity on screen depends on a *global* variable in the
program, which may be nowhere near the screen field, and which a subroutine
elsewhere can overwrite. Then:

> "If the unit ID of the reference field is found in the column MSEHI of the DDIC
> database table T006 and the quantity field does not have any decimal places
> with a value other than 0 outside the accuracy defined in the column DECAN, the
> quantity field is displayed with this accuracy."

with the same two escape hatches as `WRITE`, both ending in a silent format
change rather than an error:

> "If the quantity field has decimal places with a value other than 0 outside of
> its accuracy, however, it is displayed as a regular field of type DEC."

> "If the reference field is not found or if there is no entry in the DDIC
> database table T006 with the content of the field, the quantity field is
> displayed as a regular field of type DEC."

And a flat limitation for anyone modernising types:

> "Quantity fields of data type DECFLOAT16 or DECFLOAT34 are not supported on dynpros."

(Screen-side mechanics live in [Dynpro Flow Logic](../Dynpro%20Flow%20Logic#readme)
and [Screen Modification](../Screen%20Modification#readme).)

## 5. `T006`: two decimal-place columns whose names are anagrams

Everything above reads `T006`, so it is worth knowing what is in it. Field short
texts, verbatim from the Dictionary:

| Column | Short text | Type |
|---|---|---|
| `MSEHI` | Unit of Measurement (key; conversion routine `CUNIT`) | `UNIT` 3 |
| `DIMID` | Dimension key (check table `T006D`) | `CHAR` 6 |
| `DECAN` | "Number of decimal places for number display" | `INT2` |
| `ANDEC` | "No. of decimal places to which rounding should be performed" | `INT2` |
| `ZAEHL` | "Numerator for conversion to SI unit" | `INT4` |
| `NENNR` | "Denominator for conversion into SI unit" | `INT4` |
| `EXP10` | "base ten exponent for conversion to SI unit" | `INT2` |
| `ADDKO` | "Additive constant for conversion to SI unit" | `DEC` 9(6) |
| `EXPON` | "Base ten exponent for floating-point display" | `INT2` |
| `KZEX3` | "3-char indicator for external unit of measurement" | `CHAR` 1 |
| `KZEX6` | "6-char. ID for external unit of measurement" | `CHAR` 1 |
| `KZKEH` | "Commercial measurement unit ID" | `CHAR` 1 |
| `ISOCODE` | ISO code for unit of measurement (check table `T006I`) | `CHAR` 3 |
| `PRIMARY` | "Selection field for conversion from ISO code to int. code" | `CHAR` 1 |

Four things fall out of that list.

**`DECAN` and `ANDEC` are different columns.** One is for display, one is for
rounding, and their names are anagrams of each other. `WRITE ... UNIT` uses
`DECAN` — the doc says so explicitly. Rounding logic that reaches for *the
unit's decimals* and picks `DECAN` because it was the familiar name is wrong in
exactly the systems where the two differ.

**Conversion is a rational factor plus an offset, within a dimension.** The
numerator/denominator/exponent/additive-constant quartet converts to the SI
base unit of the unit's `DIMID`; two units with different dimensions have no
common base, which is why generic conversion of `PC` into `KG` cannot work (§9).
The additive constant is why temperature works at all — a pure multiplicative
factor cannot turn degrees Celsius into Fahrenheit. `T006` even carries
`TEMP_VALUE` / `TEMP_UNIT` and `PRESS_VAL` / `PRESS_UNIT` columns, so a unit can
be defined at a reference temperature and pressure.

**`T006` is delivery class** "C - Customising table, maintenance only by cust"
— client-dependent customizing, maintained in `CUNI`. The conversion factors
your code depends on are not SAP-delivered constants, they are per-client
configuration that someone can edit, and the conversion functions below are all
documented as using "client-dependent rules".

**The text table is language-dependent:** `T006A`, "Assign Internal to
Language-Dependent Unit". The internal key is one value; what the user types and
reads is another, per language — see §10.

## 6. `UNIT_CONVERSION` in ABAP SQL

> "The function UNIT_CONVERSION performs a unit conversion for the value passed
> to the formal parameter quantity. The result has the same data type as the
> formal parameter passed to quantity."

> "The unit conversion is performed on the basis of the client-dependent rules
> saved in the DDIC database tables T006... of package SZME. These rules can be
> edited using transaction CUNI."

The full parameter list — note what is *not* there:

| Parameter | Optional | Meaning (verbatim) | Type |
|---|---|---|---|
| `quantity` | - | "Inbound value" | `DEC, CURR, QUAN; DECFLOAT34` |
| `source_unit` | - | "Source unit from column MSEHI of the DDIC database table T006" | `UNIT` |
| `target_unit` | - | "Target unit from column MSEHI of the DDIC database table T006" | `UNIT` |
| `client` | X | "Client whose rules are used to perform the unit conversion. Default: Content of the client column of the current row" | `CLNT` |
| `on_error` | X | see below | enumerated value |

**There is no `round` and no `decimal_shift`.** `CURRENCY_CONVERSION`, on the
same page, has `round`, `decimal_shift` *and* `decimal_shift_back`, with `round`
documented as

> "Not possible for amount type D34N; if X (default value), the intermediate
> result of the conversion is rounded to the end result using commercial
> rounding; otherwise it is truncated"

Units get none of that, and it is consistent rather than an oversight: there is
no unit-driven scale to shift to, because (§1) the unit never defined the field's
decimals in the first place. The practical consequence is the trap:

**the result inherits the source field's decimal places.** The documented
result type is the same type as the input, so converting a 0-decimal `QUAN`
from `KG` to `TO` leaves nowhere to put the answer: 250 kg is 0.25 t, and a
field with no decimal places cannot hold it. Whether that lands as `0` or as
`1` depends on the rounding the platform applies — the doc promises neither,
which is itself the reason not to convert into a narrow field. If you need
the fraction, cast or target a `DECFLOAT34`, and check
[Null Values](../Null%20Values#readme) for how `SET_TO_NULL` results behave
once they reach ABAP.

`on_error` defaults to **failing**, and has one value more than its currency
counterpart:

> "Error handling. If fail (default value), an error raises an exception; if
> set_to_null, the result is reset to the null value; if keep_unconverted, the
> result is reset to the input value"

The currency cell on the same page stops after `set_to_null` — there is no
`keep_unconverted` for amounts. And `keep_unconverted` is the dangerous one of
the three: the row comes back with a number that is *silently still in the
source unit*, next to a column labelled with the target unit. Prefer `fail`, or
`set_to_null` plus an explicit null check.

In current ABAP SQL the parameter is `on_error`, values come from an enumeration,
and units are written as typed literals:

```abap
SELECT FROM demo_expressions
       FIELDS dec3,
              unit_conversion(
                quantity    = dec3,
                source_unit = unit`MI`,
                target_unit = unit`KM`,
                on_error    = @sql_unit_conversion=>c_on_error-set_to_null )
                AS actual_target_quantity
       INTO TABLE @DATA(actual_target_unit).
```

## 7. The same function in a CDS view entity — four differences and a different result type

```abap
@Semantics.quantity.unitOfMeasure: 'converted_unit'
unit_conversion( quantity       => dec3,
                 source_unit    => abap.unit'MI',
                 target_unit    => $parameters.to_unit,
                 error_handling => 'SET_TO_NULL' ) as converted_value
```

Line up the two calls:

| | ABAP SQL | CDS view entity |
|---|---|---|
| Parameter assignment | `=` | `=>` |
| Error parameter name | `on_error` | `error_handling` |
| Error parameter value | enumeration `sql_unit_conversion=>c_on_error-*` | character literal `'FAIL_ON_ERROR'` / `'SET_TO_NULL'` / `'KEEP_UNCONVERTED'` |
| Unit literal | typed literal `unit` with a backquoted value | `abap.unit'MI'` |
| Result type for a `QUAN` input | same type as `quantity` | "the result has data type QUAN with the length 31 and 14 decimal places" |

That last row is the one that bites: the identical logical conversion is
narrowed to the source column's type in ABAP SQL (§6) and arrives with 14
decimal places in a view entity. Code
reviewed in one place and copied to the other changes behaviour without changing
a visible digit.

Two more view-entity specifics:

> "Since client handling takes place implicitly for CDS view entities, it is not
> possible to explicitly specify any client column as actual parameter."

so the `client` parameter can be left out (recommended) or passed as an
expression, literal or session variable — never as a field of the data source.
See [CDS Client Handling](../CDS%20Client%20Handling#readme).

> "The function DECIMAL_SHIFT is currently not supported in CDS view entities."

And the one every CDS author eventually needs — because a quantity or amount
field cannot simply be used in arithmetic:

> "GET_NUMERIC_VALUE returns the numeric value of a currency or quantity field
> without its currency or unit key."

> "This would not be possible without the function GET_NUMERIC_VALUE, since
> elements of data type CURR are not allowed in arithmetic expressions."

> "The result of the function GET_NUMERIC_VALUE has data type DECFLOAT34 and it
> has no reference information assigned. That means that no currency or unit key
> is assigned."

Stripping the unit key is the *point* of that function, so anything you compute
from it needs its own `@Semantics.quantity.unitOfMeasure` annotation
([CDS Annotations](../CDS%20Annotations#readme)) or downstream consumers get a
bare number.

**Doc-state note.** In the view-entity reference, the `source_unit` row reads
"Source currency from column MSEHI of DDIC database table T006" — a copy-paste
from the currency block of the same table. The ABAP SQL page has it right ("Source unit from column MSEHI of the DDIC database table T006").
The parameter is a unit; the word "currency" there is a typo, not a hint.

## 8. `UNIT_CONVERSION_SIMPLE` — the two parameters that define the conversion are optional

The classic workhorse, function group `SCV0`, short-texted "Measurement unit
conversion by table T006, with rounding". Signature as generated:

| Parameter | Dir | Default | Short text |
|---|---|---|---|
| `INPUT` | import | - | "Input Value" (not optional) |
| `UNIT_IN` | import | `SPACE` | "Unit of input value" (**optional**) |
| `UNIT_OUT` | import | `SPACE` | "Unit of output value" (**optional**) |
| `ROUND_SIGN` | import | `SPACE` | "Rounding flag (+ up, - down, X comm.)" |
| `NO_TYPE_CHECK` | import | `'X'` | "Conversion factor type check" |
| `OUTPUT` | export | | "Output value" |
| `DECIMALS` | export | | "Number of decimal places for rounding" |
| `NUMERATOR` | export | | "Numerator for conversion" |
| `DENOMINATOR` | export | | "Denominator for conversion" |
| `ADD_CONST` | export | | "additive constant for conversion" |

**`UNIT_IN` and `UNIT_OUT` are optional, defaulting to blank.** The two
parameters that define what the conversion *is* can be omitted and the call
still compiles. That is what exception 7, `UNITS_MISSING`, is for — and an
unfilled unit variable (an interface field that never arrived, a `CLEAR` in the
wrong branch) reaches the same exception at runtime rather than a syntax error
at build time.

Nine exceptions, in number order: `CONVERSION_NOT_FOUND` (1, short-texted
"Conversion factor could not be determined"), `DIVISION_BY_ZERO` (2),
`INPUT_INVALID` (3), `OUTPUT_INVALID` (4), `OVERFLOW` (5), `TYPE_INVALID` (6),
`UNITS_MISSING` (7), `UNIT_IN_NOT_FOUND` (8), `UNIT_OUT_NOT_FOUND` (9). Note
that 1 and 8/9 are different failures: the unit exists but there is no route
between the two, versus the unit not being in `T006` at all. Treating them alike
loses the only diagnostic you get. Classic-exception handling rules are in
[Exception Flow](../Exception%20Flow#readme).

**Commercial rounding is not the default.** `ROUND_SIGN` defaults to `SPACE`,
which is none of the three documented flags (`+` up, `-` down, `X` commercial).
If you want commercial rounding you pass `'X'` explicitly; otherwise what you
get is decided by the `OUTPUT` field's own type.

**Two inferences, flagged as inferences.** `NO_TYPE_CHECK` defaults to `'X'`, so
the default state of a double-negative flag named "Conversion factor type check"
appears to be *check suppressed*, with `TYPE_INVALID` as the exception it would
otherwise raise; and the `DECIMALS` export, short-texted "Number of decimal
places for rounding", is evidently the `T006-ANDEC` column rather than `DECAN`,
on the strength of the matching short text. Both read clearly from the
signature and neither is stated in a document I could verify — confirm in `SE37`
and `SE11` in your own system before depending on either.

The useful thing about this FM is what it *returns*: numerator, denominator and
additive constant, i.e. the actual conversion rule it applied. That is the
cheapest way to see why a conversion produced a surprising number.

**SQL and the FM are documented to disagree.** From the keyword docs:

> "The precision of the result of the unit conversion depends on the database
> platform. The highest precision is achieved on databases that support decimal
> floating point numbers. Due to rounding, the result can be different from a
> unit conversion performed using ABAP methods, such as a standard function
> module."

So converting in a CDS view and converting in ABAP can legitimately return
different values for the same input, and a reconciliation report that does one
of each will find differences that are not bugs. Pick one layer per calculation.

## 9. Material-specific units are a different function module entirely

`UNIT_CONVERSION_SIMPLE` knows `T006` and nothing else. `PC` to `KG` has no
`T006` route — the two units sit in different dimensions — because the answer
depends on *which material*: alternative units of measure are maintained per
material in `MARM`. That conversion is:

```abap
CALL FUNCTION 'MD_CONVERT_MATERIAL_UNIT'
  EXPORTING  i_matnr  = lv_matnr      " MARA-MATNR
             i_in_me  = lv_unit_in    " MARA-MEINS
             i_out_me = lv_unit_out   " MARA-MEINS
             i_menge  = lv_qty_in     " EKPO-MENGE
  IMPORTING  e_menge  = lv_qty_out
  EXCEPTIONS error_in_application = 1
             error                = 2
             OTHERS               = 3.
```

Two things to note before using it. First, the error granularity: two
exceptions, `ERROR_IN_APPLICATION` and `ERROR`, against nine in the generic FM —
there is no *unit not maintained for this material* to branch on. Second, it is
RFC-enabled, in function group `MDR1`, and its short text is still untranslated
German; the signature is verified, but it is not a documented public API, so
check its release status in your own system before building an interface on it.

Its program `SAPLMDR1` also exposes customer exits including "User Exit for
Implementing Customer-Specific Method of Rounding" and "User Exit for Defining
Allowed Units of Measure" — meaning quantity conversion results can be
customer-modified in ways that are nowhere in your code
([Enhancement Framework](../Enhancement%20Framework#readme),
[BAdIs](../BAdIs#readme)).

## 10. The unit you store is not the unit anyone sees

Three separate representations, and interfaces trip over all three.

- **Internal vs external.** `T006-MSEHI` carries the conversion routine
  `CUNIT`, so the value in the database and the value in an input/output field
  are not the same string. The flags `KZEX3` ("3-char indicator for external
  unit of measurement") and `KZEX6` ("6-char. ID for external unit of
  measurement") control which external form a unit has. Build a `WHERE msehi =`
  from what a user typed and you can get nothing back. How conversion routines
  fire — and where they do *not* — is in
  [Conversion Routines](../Conversion%20Routines#readme).
- **Language.** The text table is `T006A`, "Assign Internal to
  Language-Dependent Unit". The same internal unit can read `ST` to a German
  user and `PC` to an English one. Never store a displayed unit.
- **ISO codes.** `ISOCODE` (check table `T006I`) is what leaves the system in
  EDI/IDoc payloads, and the mapping back is not unique — hence `PRIMARY`,
  "Selection field for conversion from ISO code to int. code", which marks the
  SAP unit that wins when several share one ISO code. See
  [IDoc and ALE](../IDoc%20and%20ALE#readme).

## Quick checklist

- Formatting a quantity for output → `WRITE ... UNIT`, and accept that it only
  trims zeros; if you need a fixed precision, use `DECIMALS` (never both).
- Need the unit's accuracy as a *number* → read `T006` yourself: `DECAN` for
  display, `ANDEC` for rounding.
- Converting in SQL → set the error parameter deliberately, avoid
  `keep_unconverted`, and watch the result type (same-as-input in ABAP SQL,
  `QUAN` 31,14 in a view entity).
- Converting in ABAP → `UNIT_CONVERSION_SIMPLE`, handle all nine exceptions,
  pass `ROUND_SIGN` if you want rounding, and never leave `UNIT_IN` / `UNIT_OUT`
  to default.
- Converting between a material's own units → `MD_CONVERT_MATERIAL_UNIT`, not
  the generic FM.
- Comparing or summing quantities → same unit, or convert first. The `+`
  operator will not stop you.
- Crossing a system boundary → convert internal/external and SAP/ISO explicitly.
- Do not mix SQL-side and ABAP-side conversion in one calculation; the docs say
  the results can differ.

## Sources

- [DDIC - Quantity Fields](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENDDIC_QUANTITY_FIELD.html) — ABAP keyword documentation
- [DDIC - Currency Fields](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENDDIC_CURRENCY_FIELD.html) — for the deliberate contrast
- [WRITE - format_options](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPWRITE_TO_OPTIONS.html) — additions `UNIT` and `CURRENCY`
- [embd_exp - format_options](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPCOMPUTE_STRING_FORMAT_OPTIONS.html) — string-template options, where `UNIT` does not appear
- [sql_func - Unit and Currency Conversion Functions](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENSQL_CURR_UNIT_CONV_FUNC.html) — ABAP SQL `UNIT_CONVERSION`
- [CDS DDL - CDS View Entity, Unit and Currency Conversion Functions](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCDS_CONV_FUNC_UNIT_CURR_V2.html) — CDS `UNIT_CONVERSION`, `GET_NUMERIC_VALUE`
- `T006` field list and delivery class, `UNIT_CONVERSION_SIMPLE` and
  `MD_CONVERT_MATERIAL_UNIT` signatures — generated Dictionary and repository
  metadata; verify in `SE11` / `SE37` in your own system. Transaction `CUNI`
  maintains the data.

## Files

- [`ydj_quantity_unit_demo.abap`](./ydj_quantity_unit_demo.abap) — runnable and
  read-only: proves the `WRITE ... UNIT` trim-only rule and the value-dependent
  case where it cancels itself, prints the `T006` conversion rule behind a unit,
  and shows that adding two different units raises nothing.
