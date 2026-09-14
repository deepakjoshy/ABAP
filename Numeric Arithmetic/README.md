# Numeric Arithmetic — why `5 / 2` is `3`, and why `-7 MOD 3` is `2` in ABAP but `-1` in ABAP SQL

ABAP does not evaluate an arithmetic expression and then store it. It first picks a
**calculation type** — *including the type of the target field you are assigning
into* — converts every operand to that type, and only then calculates.

> "The determination of a calculation type before the calculation is performed and
> while respecting all operands **including the result field** [...] is a special
> ABAP feature that differs considerably from how other programming languages
> perform calculations."
> — [Calculation Type and Calculation Rules](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENARITH_TYPE.html)

That one sentence causes most of what follows. The same expression, character for
character, produces different numbers depending on what you assign it to — with no
syntax warning, no dump, and no `sy-subrc`.

```abap
DATA lv_int  TYPE i.
DATA lv_pack TYPE p LENGTH 8 DECIMALS 2.

lv_int  = 5 / 2.   " 3      <- calculation type i,  commercial rounding
lv_pack = 5 / 2.   " 2.50   <- calculation type p
```

Neither is a bug. `lv_int` is `3` because ABAP rounds, it does not truncate.

---

## 1. Division rounds commercially — it does not truncate

This is the single biggest surprise for anyone arriving from C, Java, Python or
JavaScript, where integer division throws the remainder away.

> "In ABAP, the result of a division for the calculation types `i`, `int8`, `p`,
> and `decfloat34` is rounded commercially, whereas in most other programming
> languages any surplus decimal places are cut off."
> — [Arithmetic Operators](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENARITH_OPERATORS.html)

Worse, with calculation type `i` **every intermediate result is rounded**, not just
the final one. So multiplication and division stop being associative:

```abap
DATA lv_i TYPE i.

lv_i = 1 / 3 * 3.   " 0   <- (1/3) rounds to 0 first, then 0 * 3
lv_i = 3 * 1 / 3.   " 1   <- (3*1) = 3 first, then 3 / 3
```

Same operands, same operators, same priority, evaluated left to right — and
reordering the factors changes the answer. If you need truncation, say so
explicitly with `DIV` or `floor( )`; do not rely on `/` behaving like it does
everywhere else.

---

## 2. The calculation type hierarchy

Determined at runtime, in this order of decreasing priority:

| Priority | If any involved type is… | Calculation type |
|---|---|---|
| 1 | `decfloat16` or `decfloat34` | `decfloat34` |
| 2 | `f`, **or the operator `**` is used** | `f` |
| 3 | `p` | `p` |
| 4 | `int8` | `int8` |
| 5 | `i` (`b`, `s`) | `i` |

Non-numeric operands are dragged in too, which is how a calculation type changes
without any numeric type being involved:

| Operand type | Treated as |
|---|---|
| `d`, `t` | `i` |
| `c`, `n`, `string` | `p` |
| `x`, `xstring` | `i` |
| `utclong` | **not allowed** |

So concatenating a character field into an otherwise integer expression silently
promotes the whole thing to packed arithmetic.

**Calculation rules per type** (same source):

- `i` / `int8` — integer arithmetic, each non-integer intermediate result rounded
  commercially. Every intermediate result must fit the type or
  `CX_SY_ARITHMETIC_OVERFLOW` is raised.
- `p` — fixed point arithmetic at an internal precision of **31 places**; on
  overflow the *entire expression is recalculated* at 63 places before giving up
  with `CX_SY_ARITHMETIC_OVERFLOW`. Surplus decimal places never raise — they are
  rounded commercially per intermediate result.
- `f` — binary floating point of the current platform. Only ~15 places of
  precision, and integers are exact only to `2**53` = 9,007,199,254,740,992.
- `decfloat34` — IEEE-754-2008 decimal floating point.

---

## 3. `**` silently makes the whole expression binary floating point

`**` is the only operator that changes the calculation type by itself. If no
decimal floating point number is involved, `2 ** 10` is calculated as type `f`:

```abap
DATA(lv_pow)  = 2 ** 10.                      " type f  - a FLOAT
DATA(lv_ipow) = ipow( base = 2 exp = 10 ).    " type i  - stays integer
```

For integer exponents use the built-in function [`ipow`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENPOWER_FUNCTION.html),
whose calculation type is determined by its argument. Using `**` on large integers
is how a perfectly exact integer computation quietly acquires a floating point
rounding error.

Also note the edge cases: if the left operand is `0` the right must be `>= 0`; if
the left operand is negative the right must be an integer. Both otherwise raise a
catchable exception.

---

## 4. `DIV` and `MOD`: the ABAP result is always positive

ABAP implements the mathematical division theorem: for integers `a`, `b` with
`b <> 0` there are unique `q`, `r` with `a = qb + r` and `0 <= r < |b|`. So
`a MOD b` is **always positive**, and `DIV` is bent to match, because
`(a DIV b) * b + (a MOD b)` must reconstruct `a`.

| `operand1` | `operand2` | `DIV` | `MOD` |
|---|---|---|---|
| 7 | 3 | 2 | 1 |
| -7 | 3 | **-3** | **2** |
| 7 | -3 | -2 | 1 |
| -7 | -3 | **3** | **2** |

Note `-7 DIV 3 = -3`, not `-2`. Integer division of two negative numbers with a
non-zero remainder does not mirror the positive case.

### The trap: ABAP SQL `div( )` and `mod( )` do the opposite

`DIV`/`MOD` in ABAP are **operators**. In ABAP SQL and CDS they are **functions**
with the same names and *different sign semantics* — ABAP SQL adopted the HANA /
CPU behaviour (truncate toward zero, remainder takes the dividend's sign) because
the statement is passed largely unchanged to the database.

| `expr1` | `expr2` | SQL `div` | SQL `mod` |
|---|---|---|---|
| 7 | 3 | 2 | 1 |
| -7 | 3 | **-2** | **-1** |
| 7 | -3 | -2 | 1 |
| -7 | -3 | **2** | **-1** |

> "The ABAP operator `MOD`, on the other hand, only produces positive results."
> — [SQL Functions for Numeric Values](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_FUNCTIONS_NUMERIC.html)

Concretely: pushing a calculation down into a `SELECT` list for performance —
normally good advice — **changes the answer** for negative operands. Same-named
operation, same data, different result on each side of the SQL boundary. There is
no warning, and it only shows up for negative inputs, so it survives testing.

Two syntax details when you reach for the SQL forms: the arguments must be
`INT1`/`INT2`/`INT4`/`INT8` or `DEC`/`CURR`/`QUAN` **without decimal places**, and
ABAP SQL requires a blank after the opening parenthesis and before the closing one
— `div( @lv_a, @lv_b )`, never `div(@lv_a, @lv_b)`.

`CL_ABAP_BIGINT` splits the difference again: its `DIV`/`DIV_INT4` return
quotient/remainder pairs with the *SQL* semantics, while its `MOD`/`MOD_INT4`
implement the *ABAP* (always-positive) modulo. The two sets are unrelated.

---

## 5. The inline declaration trap with calculation type `p`

> "A calculation type `p` in assignments to an inline declaration can produce the
> data type `p` with length 8 and **no decimal places**, which can produce
> unexpected results and raise exceptions."

```abap
DATA lv_amount TYPE p LENGTH 8 DECIMALS 2 VALUE '10.50'.

DATA(lv_bad) = lv_amount / 4.                      " 3      <- p, DECIMALS 0
DATA(lv_ok)  = CONV decfloat34( lv_amount / 4 ).   " 2.625
```

`lv_bad` is not a rounding-display issue — the variable genuinely has zero decimal
places. The doc's own advice: avoid inline declarations for calculation type `p`,
or wrap the expression in `CONV`.

Generically typed field symbols and formal parameters assigned to an inline
declaration resolve as: `any`/`data`/`simple`/`numeric`/`decfloat` → `decfloat34`;
`csequence`/`clike`/`c`/`n` → `p`; `xsequence`/`x` → `i`.

---

## 6. Division by zero — except when it isn't

Division by `0` raises a catchable exception (`CX_SY_ZERODIVIDE`), **with one
exception**: if the dividend is also `0`, no exception is raised and the result is
set to `0`.

```abap
lv_i = 0 / lv_zero.   " 0, no exception
lv_i = 1 / lv_zero.   " CX_SY_ZERODIVIDE
```

This means a guard like "if the calculation didn't dump, the divisor was valid" is
wrong, and a `0 / 0` path can ship untested for years. Check the divisor, do not
rely on the exception — see SAP's own guideline,
[Prevent division by zero](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDIVISION_ZERO_GUIDL.html).

---

## 7. Conversion out of type `p` loses things quietly

From [Source Field Type p](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_P.html):

| Target | What happens |
|---|---|
| `i`, `int8` | Rounded commercially; out of range → `CX_SY_CONVERSION_OVERFLOW` |
| `p` | Rounded commercially to the **target's** decimal places |
| `n` | Rounded to an integer and the **absolute value** is stored — *the sign is silently discarded* |
| `c` | Commercial notation, right-aligned, **trailing** minus sign; if too short, truncated on the left with `*` in position 1 |
| `f` | Nearest representable binary value — `CONV f( pack )` on `'0.815'` gives `8.1499999999999995E-01` |
| `utclong` | Not supported — syntax error or `CX_SY_CONVERSION_NOT_SUPPORTED` |

The `n` row is the dangerous one: `-12.34` assigned to `TYPE n LENGTH 5` becomes
`'00012'`. No exception, no `sy-subrc`, and the number is now positive.

The `c` row is the reason totals in classic reports appear as `*` — the field was
too short, and the truncation happens on the **left**, i.e. the significant digits.

---

## 8. Fixed point arithmetic

*Fixed point arithmetic* is a **program property**, not a statement. It controls
whether the decimal separator in type `p` fields is respected at all. Switching it
off is [obsolete](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENNON_FIXED_POINT_OBSOLETE.html)
— but it is off by default in some very old programs, and when it is off the
decimal point in a `p` source field is *ignored* in every operation except
assignment to `c`/`string`. If a legacy report's amounts are wrong by a factor of
100, check the program attributes before reading a single line of code.

---

## Rules of thumb

1. Give every operand **and the target field** the same numeric type. Mixed types
   mean conversions you did not write and a calculation type you did not choose.
2. `/` rounds. If you want truncation, write `DIV` or `floor( )`.
3. Never let an integer-typed intermediate result hold a fraction — reorder so
   multiplications happen before divisions.
4. Use `ipow( )` instead of `**` whenever the exponent is an integer.
5. Never assume `MOD` means the same thing on both sides of a `SELECT`. For
   negative operands in SQL, compute in ABAP or normalise the sign explicitly.
6. Do not use `DATA(x) =` for packed calculations. Use a declared variable or
   `CONV`.
7. Check divisors. `0 / 0` does not raise.

## Sources

- [`arith_exp` — Arithmetic Operators](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENARITH_OPERATORS.html) — operator priority, the `DIV`/`MOD` sign table, commercial rounding vs other languages, division by zero, `**` edge cases
- [`arith_exp` — Calculation Type and Calculation Rules](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENARITH_TYPE.html) — the type hierarchy, non-numeric operand mapping, per-type calculation rules and precision, the inline declaration warning
- [DDIC — SQL Functions for Numeric Values](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_FUNCTIONS_NUMERIC.html) — the SQL `div`/`mod` sign table and the explicit contrast with the ABAP operators
- [Understanding DIV and MOD in ABAP and beyond](https://community.sap.com/t5/technology-blog-posts-by-sap/understanding-div-and-mod-in-abap-and-beyond/ba-p/14015181) — SAP's own explanation of *why* the three implementations differ, incl. `CL_ABAP_BIGINT`
- [Source Field Type p](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_P.html) — conversion table out of packed numbers
- [`ipow`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENPOWER_FUNCTION.html) and [fixed point arithmetic](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENFIXED_POINT_ARITHMETIC_GLOSRY.html)

See also: [Currency Amounts](../Currency%20Amounts#readme) for why money needs
`TCURX` handling on top of all of this, [Null Values](../Null%20Values#readme) for
how aggregates behave over empty sets, and [Time Stamps](../Time%20Stamps#readme)
for the packed-number arithmetic trap on timestamps.
