# Currency Amounts — why 2 yen is stored as `0.02`, and every place that silently breaks

A currency field does **not** store a decimal number. It stores *an integer in the
smallest unit of the currency*, and the decimal separator you see in the field is
a display artefact of the `CURR` type, not part of the value.

> "A currency amount is an integer in the smallest unit of the currency. The
> integer is constructed from all figures in a currency field while ignoring the
> position of the decimal separator."
> — [DDIC - Currency Fields](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDDIC_CURRENCY_FIELD.html)

Every `CURR` field in the Dictionary defaults to **two** decimal places, regardless
of the currency it will hold. The actual decimal count per currency lives in
`TCURX` (`CURRKEY` / `CURRDEC`), and a currency only appears there if it differs
from two. So:

| Currency | `TCURX-CURRDEC` | Amount | Stored in the `CURR` field |
|---|---|---|---|
| `EUR` | (not in TCURX → 2) | 2.00 EUR | `2.00` |
| `JPY` | 0 | 2 JPY | `0.02` |
| `TND` | 3 | 2.000 TND | `20.00` |

`0.02` in the database *is* two yen. Nothing is wrong with the data. What is
wrong is every piece of code that reads that field and assumes the digits after
the point are cents.

This is not an exotic edge case: `JPY`, `KRW`, `CLP`, `HUF`, `JOD` are all in
`TCURX`, and SAP ships [Note 1240163](https://launchpad.support.sap.com/#/notes/1240163)
("Amount too high by factor of 100 for currency HUF, JPY, KRW, JOD, CLP")
precisely because this keeps being rediscovered.

## 1. The DDIC decimal count and the currency decimal count are unrelated

The two decimals on your `CURR` data element and the `TCURX` decimals for the
currency are *independent numbers*. The doc is explicit:

> "The number of decimal places for the currency defined by the currency key of
> type `CUKY` only determines the formatting and checking of a currency field on
> a dynpro. It is independent of the number given for the currency field of type
> `CURR`."

And it goes further — do not try to "fix" this by declaring a `CURR` field with
0 or 3 decimals:

> "It is not advisable to use any other value, since in this case any unforeseen
> operations with currency keys in ABAP programs are largely ignored."

The correct model is: the field holds integer minor units, two decimals is the
storage convention, and the *shift happens at the boundary* (output, interface,
non-SAP consumer) — never in the stored value.

## 2. Which arithmetic is safe and which silently isn't

The keyword documentation splits operations into non-critical and critical. This
list is worth memorising, because nothing here produces a syntax error or a dump
— only wrong money.

**Non-critical:**

- Comparison, addition, subtraction, division of two currency fields **with the
  same number of decimal places**.
- Multiplication or division by a plain, non-currency-dependent number
  (a quantity, a percentage, a factor).

**Critical:**

- Multiplication of two currency fields.
- Operations between two fields **in different currencies** that include assignments.
- Assigning a non-currency-dependent number to a currency field.

```abap
" Safe - both operands are amounts in the same currency, same decimals
DATA(lv_total) = ls_item-netwr + ls_item-mwsbp.

" Safe - amount times a plain factor
DATA(lv_line) = ls_item-kbetr * ls_item-menge.

" CRITICAL - literal assigned into a CURR field.
" For JPY this means 1000 yen only if TCURX-CURRDEC = 2, which it is not.
ls_item-netwr = 1000.          " actually 100000 JPY

" CRITICAL - assignment across currencies. The digits move unchanged,
" the meaning does not.
ls_target-wrbtr = ls_source-dmbtr.
```

> "Accurate results should not be expected when performing critical operations if
> the number of decimal places in the program does not match the number in the
> currency."

## 3. Output: `WRITE ... CURRENCY` and the `CURRENCY` format option do the shift for you

The one place the shift is automatic is formatted output — *if* you tell it the
currency.

```abap
DATA lv_amount TYPE wrbtr VALUE '0.02'.    " two yen, as stored

WRITE: / lv_amount.                        " 0.02        <- wrong to a human
WRITE: / lv_amount CURRENCY 'JPY'.         " 2           <- correct

" Same shift, string template form
DATA(lv_text) = |{ lv_amount CURRENCY = 'JPY' }|.     " 2
DATA(lv_eur)  = |{ lv_amount CURRENCY = 'EUR' }|.     " 0.02
```

Note what this means in reverse: a `WRITE` **without** `CURRENCY` on an amount
field is a latent bug in any system that will ever see a `TCURX` currency. Same
for ALV — an amount column needs its currency reference field
(`cfieldname` in the fieldcat, or the `@Semantics.amount.currencyCode`
annotation) or the grid formats with two decimals by default.

A caveat on the string-template option that bites: `CURRENCY` formats by digit
string, so it **ignores the declared decimals of the type `p` object**. It is not
a rounding instruction — it is a decimal-shift instruction.

## 4. Interfaces: `CURR` is forbidden in BAPIs, and that rule has teeth

The BAPI programming guide bans the type outright:

> "For these reasons, the data type `CURR` cannot be used in the BAPI interface
> [...] You must not use parameters and fields of data type `CURR` in the
> interface. All parameters and fields for currency amounts must use the domain
> `BAPICURR` with the data element `BAPICURR_D` or `BAPICUREXT` with the data
> element `BAPICUREXT`."
> — [Internal and External Data Formats](https://help.sap.com/doc/saphelp_snc70/7.0/en-US/a5/3ec9ea4ac011d1894e0000e829fbbd/content.htm)

The reason is exactly the yen case: an external system receiving `0.02` has no
`TCURX` and no way to know it means 2. So BAPI parameters carry the **external**
format — the human-readable amount — and you convert at the boundary:

| Direction | Function module |
|---|---|
| internal (`CURR`, e.g. `0.02`) → external (`2`) | `BAPI_CURRENCY_CONV_TO_EXTERNAL` |
| external (`2`) → internal (`CURR`, `0.02`) | `BAPI_CURRENCY_CONV_TO_INTERNAL` |

```abap
" external -> internal: has MAX_NUMBER_OF_DIGITS and RETURN
DATA lv_internal TYPE wrbtr.
DATA ls_return   TYPE bapireturn.

CALL FUNCTION 'BAPI_CURRENCY_CONV_TO_INTERNAL'
  EXPORTING currency             = 'JPY'
            amount_external      = lv_input          " 2
            max_number_of_digits = 23
  IMPORTING amount_internal      = lv_internal       " 0.02
            return               = ls_return.

" internal -> external: NO max_number_of_digits, NO return
DATA lv_external TYPE bapicurr-bapicurr.

CALL FUNCTION 'BAPI_CURRENCY_CONV_TO_EXTERNAL'
  EXPORTING currency             = 'JPY'
            amount_internal      = lv_db_amount      " 0.02
  IMPORTING amount_external      = lv_external.      " 2
```

Four gotchas on these:

- **The two interfaces are not symmetric, which is easy to miss when you write
  the pair together.** `..._TO_INTERNAL` takes `MAX_NUMBER_OF_DIGITS` and returns
  a `RETURN` of type `BAPIRETURN` (not `BAPIRET1`/`BAPIRET2`).
  `..._TO_EXTERNAL` takes neither — it has exactly `CURRENCY` +
  `AMOUNT_INTERNAL` in and `AMOUNT_EXTERNAL` out, and therefore **no error
  channel at all.**
- **`MAX_NUMBER_OF_DIGITS` is a real limit, not a formality.** It caps the
  internal domain length (max 23); an amount that overflows it comes back as
  return code `041` *"External currency amount is too large to be converted"*
  rather than as an exception. Check `RETURN` — the conversion fails quietly
  otherwise. Code `043` ("No currency key transferred: default conversion
  carried out") means it silently assumed two decimals, and `044` means the
  currency key was unknown.
- **`BAPICURR_D` is `P` length 12 with 2 decimals.** It is a *numeric* type, so
  it is only "external" by convention and discipline — nothing stops you
  assigning a `CURR` field straight into it, and nothing will tell you that you
  did. Use `BAPICUREXT` where the value range is larger.
- **Both function modules are technically unreleased.** Despite the `BAPI_`
  prefix and their appearance all over SAP's own documentation, they are not
  released for customer use — see
  [KBA 2659445](https://userapps.support.sap.com/sap/support/knowledge/en/2659445).
  In practice they are ubiquitous and stable, but if you need a supported API,
  wrap them, or use `CL_ABAP_DECFLOAT` (section 6) which is documented and
  released. The older pair `CURRENCY_AMOUNT_BAPI_TO_SAP` /
  `CURRENCY_AMOUNT_SAP_TO_BAPI` does the same job and is still widely used in
  SAP's own code.

### The rule that makes this simple

From a long SAP Community thread on getting JPY conversion right:

> "Use INTERNAL format for anything involving data type `CURR`. Use EXTERNAL for
> all other data types. Use `BAPI_CURRENCY_CONV*` to convert between them. [...]
> `CURR` = internal, else external. For any transition, switch."
> — [Currency conversion FM/method to rule them all?](https://community.sap.com/t5/application-development-and-automation-discussions/currency-conversion-fm-method-to-rule-them-all/m-p/592175)

## 5. Exchange-rate conversion needs the shift *around* it, not inside it

`CONVERT_TO_FOREIGN_CURRENCY` / `CONVERT_TO_LOCAL_CURRENCY` work in internal
format and apply the `OB08` rate and factors. They do **not** rebase between
currencies with different `TCURX` decimals. Convert USD → JPY and the result is
internal-format JPY; read it as a plain number and it is 100× too small.

The standard fix is the sandwich: convert to external, run the rate conversion,
convert back to internal for the target currency — the same thing SAP's own
notes recommend, and the same thing the conversion BAPIs do internally.

Do not hand-roll the shift with a `CASE` over `TCURX-CURRDEC`. It is tempting and
it is wrong in both directions the first time someone passes a 3-decimal currency
like `TND`, or the percentage pseudo-currency `%` (internally currency `3`,
maintained in `TCURX` with 3 decimals — see
[Note 886532](https://launchpad.support.sap.com/#/notes/886532)).

## 6. The modern way out: `DECFLOAT34` instead of `CURR`

SAP's own recommendation in the current documentation:

> "For currencies, one of the data types for decimal floating point numbers is
> recommended rather than the data type `CURR`."

A `DECFLOAT16`/`DECFLOAT34` field becomes an amount field simply by carrying a
currency-key reference, and it stores the amount *as written* — no shift, no
`TCURX` surprise, no 15-digit packed ceiling. Two caveats:

- `DECFLOAT16`/`DECFLOAT34` currency fields are **not supported on dynpros.**
  Classic dynpro screens still force `CURR`.
- For converting existing `CURR` values, use
  `CL_ABAP_DECFLOAT=>CONVERT_CURR_TO_DECFLOAT` and `CONVERT_DECFLOAT_TO_CURR` —
  they apply the currency-key shift, and `CONVERT_DECFLOAT_TO_CURR` behaves
  exactly like the `CURRENCY` option of `WRITE TO`.

## 7. CDS amount fields

In CDS, `CURR` requires `@Semantics.amount.currencyCode` pointing at a `CUKY`
element — that annotation is what makes it an amount field, and it propagates
automatically to views selecting from it.

```abap
define view entity ZI_Item as select from zitem
{
  key item_id,
      currency_code,
      @Semantics.amount.currencyCode: 'currency_code'
      net_amount
}
```

CDS-specific traps:

- **`CAST` does not handle amounts.** Casting away from `CURR` loses the
  currency reference; only a target type of `CURR` requires one.
- **`CURRENCY_CONVERSION` assumes two decimal places.** Per the doc: "If the
  function for currency fields is used with other amounts of decimal places,
  unexpected behavior may arise." Same yen problem, one layer up.
- `GET_NUMERIC_VALUE` strips the currency reference and hands you the raw
  number — useful deliberately, dangerous accidentally.
- `CURR_TO_DECFLOAT_AMOUNT` converts a `CURR` amount field to `DECFLOAT34`.
- `DECIMAL_SHIFT` exists only in the obsolete DDIC-based views; it is **not
  available in CDS view entities.**
- Amount handling in expressions/`UNION`/`INTERSECT` only works in **view
  entities**, not in any other CDS entity — an old DDIC-based view will not
  apply these rules at all.

## Quick checklist

- Reading an amount for **display** → `WRITE ... CURRENCY` / `{ amt CURRENCY = cuky }`.
- Sending an amount **out of SAP** → `BAPI_CURRENCY_CONV_TO_EXTERNAL`, and check `RETURN`.
- Receiving an amount **into SAP** → `BAPI_CURRENCY_CONV_TO_INTERNAL` before any `CURR` field.
- **Comparing/adding** two amounts → same currency, or convert first.
- **Never** assign a numeric literal into a `CURR` field and assume units.
- Building something new → consider `DECFLOAT34` with a currency-key reference.

## Sources

- [DDIC - Currency Fields](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDDIC_CURRENCY_FIELD.html) — ABAP keyword documentation
- [ABAP CDS - Amount Fields](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCDS_AMOUNT_FIELD.html) — ABAP keyword documentation
- [System Class CL_ABAP_DECFLOAT](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCL_ABAP_DECFLOAT_DOC.html)
- [Internal and External Data Formats](https://help.sap.com/doc/saphelp_snc70/7.0/en-US/a5/3ec9ea4ac011d1894e0000e829fbbd/content.htm) — BAPI Programming Guide
- [SAP KBA 2659445](https://userapps.support.sap.com/sap/support/knowledge/en/2659445) — Usage of BAPI_CURRENCY_CONV_TO_INTERNAL / _TO_EXTERNAL (unreleased)
- [SAP Note 1240163](https://launchpad.support.sap.com/#/notes/1240163) — Amount too high by factor of 100 for HUF, JPY, KRW, JOD, CLP
- [SAP Note 886532](https://launchpad.support.sap.com/#/notes/886532) — Pricing: Displaying and rounding numbers
- [Currency conversion FM/method to rule them all?](https://community.sap.com/t5/application-development-and-automation-discussions/currency-conversion-fm-method-to-rule-them-all/m-p/592175) — SAP Community
