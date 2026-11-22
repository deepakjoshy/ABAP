# Enumerated Types | The Assignment That Gives You a Name Instead of a Value, the CONV Whose Meaning Flips With Its Target & the Cross-Type Cast Nothing Rejects

ABAP got real enumerated types in 7.51, and they look familiar enough that most
developers write one from memory and move on:

```abap
TYPES:
  BEGIN OF ENUM ty_size STRUCTURE sz,
    small, medium, large, xlarge,
  END OF ENUM ty_size STRUCTURE sz.
```

That part behaves. The surprises all come from one design decision, and the
documentation states it as a flat rule:

> "Within ABAP, enumerated objects are never interpreted in accordance with their
> base type."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

So an enumerated variable over base type `i` is **not** a number. It cannot be
added to, compared with `3`, or passed where an `i` is expected. Good — that is
the whole point:

> "Enumerated objects are mainly used to check allowed values."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

But there is exactly one hole in that wall, and because it is the single
exception, it is where every real bug lives:

> "The only exception to this rule is the assignment of source fields with
> enumerated types to character-like variables of the types c and string."
> -- [Conversion Rules for Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONVERSION_ENUMERATED.html)

An enum will not quietly become a number. It *will* quietly become text. And the
text is not what most people expect.

---

## 0. What the declaration actually creates

| Syntax | Creates |
|---|---|
| `BEGIN OF ENUM ty_size, small, ... END OF ENUM ty_size.` | the type `ty_size` **plus** loose constants `small`, `medium`, ... in the current context |
| `BEGIN OF ENUM ty_size STRUCTURE sz, ...` | the type `ty_size` **plus** one constant structure `sz` with components `sz-small`, ... |
| `... BASE TYPE dtype` | storage type of the values. Default is `i` |

Two things worth pinning down.

**The enumerated structure is a data object, not a type.** `sz` cannot be used
after `TYPE`; the type is still `ty_size`, which stays elementary even when a
structure exists. Use `STRUCTURE` by default: it keeps the constant names out of
the program namespace, and it is the only form a CDS enumerated type offers, so
it is the form your code will end up matching anyway.

**The `VALUE` rules are all-or-nothing, and the initial value is not positional:**

> "The IS INITIAL addition must be specified for exactly one constant."
> -- [TYPES, BEGIN OF ENUM enum_type](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPTYPES_ENUM.html)

> "The order of the specified values is not important."
> -- [TYPES, BEGIN OF ENUM enum_type](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPTYPES_ENUM.html)

> "For non-numeric base types, the VALUE addition must be specified for each
> enumerated constant."
> -- [TYPES, BEGIN OF ENUM enum_type](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPTYPES_ENUM.html)

So the constant carrying `VALUE IS INITIAL` can sit anywhere in the list, and
`IS INITIAL` on an enumerated variable tests *that* constant, not the first one
declared. Declaration order and value order are independent, and only
declaration order drives `sz` component order.

---

## 1. The assignment gives you the NAME, in uppercase

This is the trap that produces wrong data rather than a dump:

> "The name and length of the enumerated constant or the component of the
> enumerated structure in which the current value of the source field is stored
> during the definition of the enumerated type, are assigned to the target field
> in uppercase letters."
> -- [Conversion Rules for Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONVERSION_ENUMERATED.html)

```abap
DATA lv_text TYPE string.
lv_text = sz-large.          " 'LARGE'  <-- the identifier, not 2
```

Read that again against the base type. `sz-large` *stores* the integer 2. Assign
it to a string and you get `LARGE`. Nothing in the statement hints at it, and the
documentation says so outright:

> "This type of conversion to a character-like type can produce unexpected
> results."
> -- [Conversion Rules for Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONVERSION_ENUMERATED.html)

Three consequences people hit in order:

**(a) Your source code identifiers became data.** The uppercase name of a
constant is now flowing into a log, a message variable, an output column, or a
JSON payload. Renaming `large` to `size_large` in a refactoring — a rename an
IDE will happily do, with no callers affected — changes a *value* that a
downstream system may be comparing against.

**(b) The name is unqualified, so different enums collide.** No structure
prefix, no class prefix, 30 characters maximum:

> "Therefore, the conversion of enumerated objects of different enumerated types
> can have the same result if the names of the enumerated constants match."
> -- [Conversion Rules for Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONVERSION_ENUMERATED.html)

Two unrelated enums that each define `released` both convert to `RELEASED`. The
type system that was keeping them apart is bypassed the moment either one is
turned into text, so a string-keyed dispatch table or a text comparison merges
two domains that cannot be assigned to each other at all.

**(c) It is a one-way street.** There is no route back:

> "There is no reverse conversion rule for assignments between character-like
> source fields and enumerated variables."
> -- [Conversion Rules for Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONVERSION_ENUMERATED.html)

So the round trip `enum -> string -> enum` has no supported second half. Code that
persists the name has to re-map it by hand, forever.

The extended program check does flag this, when it can see it:

> "a conversion of this type produces a message from the extended program check
> if it is known statically. This message can be hidden using the pragma
> ##types."
> -- [Conversion Rules for Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONVERSION_ENUMERATED.html)

*If it is known statically* is doing a lot of work in that sentence — route the
enum through a generically typed parameter or field symbol and the warning
disappears while the behaviour does not. And `##types` is a pragma, so the usual
positioning rules apply; see [Pragmas & Pseudo Comments](../Pragmas%20and%20Pseudo%20Comments#readme)
for why a marker in the wrong place suppresses nothing and says nothing.

Everything else is a hard stop, which is the reassuring half of the design:

> "Assignments between enumerated data objects and data objects that are not
> enumerated data objects lead to a syntax error or the runtime error
> UC_OBJECTS_NOT_CONVERTIBLE."
> -- [Conversion Rules for Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONVERSION_ENUMERATED.html)

---

## 2. The same operand, the same target, opposite results

Now add a character-like base type, which is the normal choice when an enum
replaces a legacy domain of one-character codes:

```abap
TYPES:
  ty_code_base TYPE c LENGTH 3,
  BEGIN OF ENUM ty_code STRUCTURE cd BASE TYPE ty_code_base,
    unknown  VALUE IS INITIAL,
    created  VALUE 'CRE',
    released VALUE 'REL',
  END OF ENUM ty_code STRUCTURE cd.
```

Two assignments that differ by three characters of source code:

```abap
DATA lv_name TYPE c LENGTH 10.
DATA lv_val  TYPE ty_code_base.

lv_name = cd-released.            " 'RELEASED'   <-- the name
lv_val  = CONV #( cd-released ).  " 'REL'        <-- the value
```

`CONV #( )` is normally a no-op you add to satisfy a typing rule. Here it
*inverts the meaning of the expression*, because enumerated types opt out of
CONV's defining promise:

> "Using CONV for enumerated types deviates from the rule that CONV always
> behaves according to the regular conversion rules in assignments."
> -- [CONV, Conversion of Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONV_CONSTRUCTOR_ENUM.html)

> "If the operand is an enumerated type with a character-like base type, and this
> base type is specified as type, the special rule above applies instead of the
> general conversion rule. That is, the enumerated value is returned, not the
> name."
> -- [CONV, Conversion of Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONV_CONSTRUCTOR_ENUM.html)

The `#` resolves to the target type, so **the target declaration decides whether
you get the name or the value**, and the deciding factor is whether that type is
*exactly* the base type. Widen `lv_val` from `ty_code_base` to `c LENGTH 10`
during a *the code field got longer* change and the same `CONV #( )` line stops
returning `REL` and starts returning `RELEASED`. Nothing else in the statement
changed. Spell the type out — `CONV ty_code_base( cd-released )` — and the
decision is at least visible at the point of use.

With a numeric base type the two results are a number and a word, so the bug
announces itself on first run. With a character-like base type both results are
short uppercase strings in the same field, which is why this one reaches
production.

---

## 3. `CONV enum_type( )` converts first and validates second

The reverse direction looks like a guarded gate, and it is often used as one —
take a value off a database field or an interface and turn it into an enum, so
that everything downstream is type-safe:

> "If the value is not valid, an exception CX_SY_CONVERSION_NO_ENUM_VALUE
> occurs."
> -- [CONV, Conversion of Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONV_CONSTRUCTOR_ENUM.html)

The gate is real, but it is the *second* step. The first step is an ordinary
conversion to the base type, with ordinary lossy behaviour — and the validity
check only ever sees the result:

> "If the conversion operator is used, the operand is converted to the base type
> c with length 4, cutting off any surplus places. If the lossless operator is
> used, this results in an exception."
> -- [EXACT, Lossless Conversion of Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENEXACT_CONSTRUCTOR_ENUM.html)

So with the `ty_code` above (base type `c LENGTH 3`):

```abap
DATA(lv_ok) = CONV ty_code( `REL` && `X` ).   " -> cd-released. No exception.
```

`RELX` is not a valid code. It is truncated to `REL`, which *is* a valid
enumerated value, so `CX_SY_CONVERSION_NO_ENUM_VALUE` is never raised and the
enum now holds a confidently wrong value. The documentation's numeric example is
the same shape with rounding instead of truncation: an operand of `+ '1.2'` is
converted to base type `i` "cutting off the decimal places", landing on the
constant with value 1.

This matters precisely because the operand is usually *not* a literal — it is a
field from an inbound payload, a legacy `CHAR` column, or a user entry. Overlong
or fractional input does not bounce; it collapses onto whichever neighbouring
constant the conversion happens to produce.

`EXACT` is the version that behaves like a gate, raising
`CX_SY_CONVERSION_DATA_LOSS` for the truncation case and
`CX_SY_CONVERSION_ROUNDING` for the fractional one. **If you are converting
external data into an enum, `EXACT` is the correct operator and `CONV` is a
silent coercion.** That is the opposite of the usual advice, where `EXACT` is the
cautious extra and `CONV` the default. See
[Type Conversions & Lossless Assignment](../Type%20Conversions#readme) for the
general lossless rules these two exceptions come from.

---

## 4. The short form that casts between unrelated enumerated types

Two enumerations with the same base type can be converted into each other, and
the syntax for it is indistinguishable from an ordinary conversion:

> "Provided that different enumerated types can have the same base type, an
> enumerated object of an enumerated type can be converted to the corresponding
> enumerated object of a different enumerated type."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

The documentation's own example is worth keeping, because it is deliberately
absurd. Given `fruit` (`apple, peach, orange`) and `animal` (`cat, dog, cow`):

```abap
cl_demo_output=>display( CONV animal( peach ) ).
```

> "The output shows the associated name DOG."
> -- [CONV, Conversion of Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONV_CONSTRUCTOR_ENUM.html)

A fruit went in and an animal came out. No syntax error, no exception, no
warning — because the short form is defined as
`CONV enum_type( CONV base_type( enum_dobj ) )`, and once the value is a bare
integer the two value sets are interchangeable. The matching happens **by stored
value**, so the constant names, their order and their meaning are all irrelevant.

The realistic version is two enums in the same domain that drifted — an *old*
and a *new* status enum, or a BO status and a UI status — where a plausible
`CONV ty_new_status( ls-old_status )` compiles and silently maps position 3 to
position 3 even after somebody inserts a constant in the middle of one of them.
Enumerated types stop type errors between an enum and everything else; they do
*not* stop them between two enums.

---

## 5. Comparisons never convert — and reads disagree about that

Assignment converts to text. Comparison does not:

> "There is no implicit conversion."
> -- [rel_exp - Comparing Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENLOGEXP_RULES_OPERANDS_ENUM.html)

```abap
IF lv_size = sz-xlarge.         " fine
IF lv_size = `XLARGE`.          " syntax error
IF CONV string( lv_size ) = `XLARGE`.  " fine, explicit
```

`<`, `>` and friends also work between two objects of the same enumerated type,
comparing by stored value — which is why the planet example in the keyword
documentation can declare its constants alphabetically, give them orbital-order
values, and still assert `p-mercury < p-venus`. Order comparisons on an enum are
a comparison of the *values*, so they only mean something if the values were
chosen to mean something.

Now the asymmetry that is almost impossible to guess, and the real reason this
note exists:

> "This difference between assignments and comparisons is particularly
> significant when reading from internal tables using the statement READ TABLE or
> table expressions and the statement LOOP AT or a FOR statement. When individual
> lines are read, the comparison fields of conditions are converted implicitly;
> this is not the case when multiple lines are read."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

Same table, same character-like column, same enum operand:

| Statement | Rows | Enum in the condition |
|---|---|---|
| `READ TABLE ... WITH KEY col = sz-large` | one | converted implicitly to `LARGE` |
| `itab[ col = sz-large ]` | one | converted implicitly to `LARGE` |
| `LOOP AT itab WHERE col = sz-large` | many | **not** converted |
| `FOR wa IN itab WHERE ( col = sz-large )` | many | **not** converted |

So a working single-row lookup, rewritten into a loop because the requirement
grew from *find the one* to *process all of them*, stops being the same
expression. The multi-row form follows the comparison rule, so it needs an
explicit `CONV string( )` — and in the converting direction the implicit
conversion triggers the extended check message from section 1, which is the only
warning you will get that these two statements are not equivalent.

---

## 6. Generic typing is a one-way valve

Enumerated types are covered by `any`, `data` and `simple`, and a generically
typed field symbol or parameter inherits the enumerated type when one is
assigned to it. What it cannot do is hand it back:

```abap
FIELD-SYMBOLS <fs1> TYPE simple.
DATA(lv_size) = sz-xlarge.

ASSIGN lv_size TO <fs1>.
<fs1> = lv_size.          " allowed
"lv_size = <fs1>.         " syntax error
"ASSERT lv_size = <fs1>.  " syntax error
```

The rule is that a read position expecting a statically known enumerated object
only accepts a statically known operand of the same enumerated type, so a
generic operand is rejected on the *source* side of an assignment to an enum and
in comparisons against one, while remaining fine as a target. Where the type is
not statically known the check moves to runtime instead of disappearing.

Two related restrictions:

> "In assignments to field symbols, no castings with the CASTING addition can be
> performed and an enumerated type cannot be specified after this addition."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

> "Substring access is not possible."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

Together with the structure rule — "In structures, each component with an
enumerated type forms a separate fragment of the structure fragment view" — this
means a generic utility that moves data around by casting or by offset/length
cannot be pointed at an enum, and two structures only assign to each other if
their enumerated components have the *same* enumerated type, not merely the same
base type. See [Field Symbols](../Field%20Symbols#readme) and
[Reference Casting](../Reference%20Casting#readme) for the generic-handling
patterns this blocks.

---

## 7. Where enumerated types simply do not exist

This is the section to read *before* choosing an enum for a field, because none
of it is negotiable at the point you discover it.

> "Enumerated types are not currently supported by the ABAP Dictionary.
> Accordingly, no database tables whose columns have an enumerated type can be
> defined in the ABAP Dictionary."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

So an enum is an *in-program* type. Persisting it means converting it, and
section 1 says the only implicit conversion available produces the name while
section 3 says the way back is lossy unless you use `EXACT`.

Then the asymmetry that catches people who did everything right — an ABAP enum
cannot even be a host variable:

> "Host variables and operands of host expressions can have a CDS enumerated type
> but not an ABAP enumerated type."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

`SELECT ... WHERE status = @lv_abap_enum` is a syntax error; the identical
statement with a CDS enumerated type is legal. **If the value is going anywhere
near ABAP SQL, define the enumeration in CDS, not in ABAP.** That single choice
decides whether the type is usable in the persistence layer, and it is made at
the very start.

The rest of the exclusion list:

| Place | Status |
|---|---|
| ABAP Dictionary / DB table columns | not supported |
| Host variables, ABAP enum | not possible |
| Host variables, CDS enum | **possible** |
| Native SQL (`EXEC SQL`), ADBC | no host variables or references |
| AMDP method parameters | cannot be typed with an enum |
| Selection screen input fields | not supported |
| Classic dynpro fields | "known gap" — see below |
| List buffer inheritance | no conversion rule exists |

> "In Native SQL ( EXEC SQL , ADBC ), no host variables or references to ABAP
> variables with enumerated type can be used. The actual parameters of AMDP
> methods cannot be typed using enumerated types."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

> "No enumerated types are supported for the input fields of selection screens."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

> "It is not possible to inherit enumerated values from lists in the list buffer,
> since there are no conversion rules between character-like types and enumerated
> types."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

The dynpro entry is the dangerous one, because it does not fail — it writes:

> "Enumerated types are not supported by dynpros. If dynpro input fields are
> defined by referring to enumerated objects of a program, they are handled like
> an object of the base type. Any invalid values are passed to the associated
> enumerated object at the event PAI without being checked. For this reason,
> enumerated objects should never be linked with classic dynpros."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

A dynpro field bound to an enum is treated as its base type, so the screen will
accept any integer in range and hand it straight to the enumerated variable at
PAI. The one guarantee an enum exists to provide is gone, silently, through the
screen layer. That *should never* is unusually blunt for the keyword documentation;
take it literally. [Dynpro Flow Logic](../Dynpro%20Flow%20Logic#readme) covers
what PAI does and does not check.

---

## 8. What an invalid value does once it is in there

An enum should never hold a value outside its set, but the documentation
specifies the behaviour anyway, which tells you the gaps in section 7 are real.

> "The result of a conversion to c or string is the string <illegal enum value>"
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

> "An enumerated object with an invalid value can be assigned to other enumerated
> objects with the same enumerated type without being checked."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

So the invalid value *propagates*: every same-type assignment copies it along
unchecked, and `CONV`/`EXACT` to the base type faithfully return it. The only
visible symptom is the literal text `<illegal enum value>` appearing wherever the
value gets converted to a character field — in a log, a list, an ALV column, a
JSON payload — far from the dynpro or interface that introduced it. Searching for
that exact string is the diagnostic.

Note what this means for a `CASE` over an enum: an invalid value matches no
`WHEN` branch and falls into `WHEN OTHERS`. The keyword documentation's own
`CASE` example relies on `WHEN OTHERS` catching the two constants it did not
list, so an `OTHERS` branch written as *the remaining valid values* quietly
doubles as the handler for corrupt ones. Keep it, and make it loud.

---

## 9. ABAP enums vs CDS enums

They are deliberately interchangeable at the point of use and different
everywhere else.

| | ABAP `TYPES BEGIN OF ENUM` | CDS `DEFINE TYPE ... ENUM` |
|---|---|---|
| Base type | optional, defaults to `i` | **mandatory**, no default |
| Base types allowed | flat elementary, max 16 bytes | `abap.int1/int2/int4`, `abap.char(1..8)`, `abap.numc(1..8)` |
| Enumerated structure | optional (`STRUCTURE struc`) | always, named after the type |
| Component order in that structure | order of definition | **alphabetical** |
| Usable as SQL host variable | no | yes |
| Scope | program, or class/interface component | global type namespace |
| `VALUE IS INITIAL` | exactly one constant | `INITIAL` on exactly one constant |

> "In ABAP CDS, the base type must be specified and there is no default."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

> "In contrast to an ABAP enumeration type, the components of the enumerated
> structure derived from an CDS enumerated structure are ordered alphabetically
> instead of following the order of the definition."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

That last row is a live trap, because the documented idiom for walking every
member of an enum is positional:

```abap
DO.
  ASSIGN sz-(sy-index) TO FIELD-SYMBOL(<p>).
  IF sy-subrc <> 0.
    EXIT.
  ENDIF.
  ...
ENDDO.
```

Against an ABAP enum this yields declaration order. Against a CDS enum it yields
alphabetical order. Port the loop from one to the other — or convert an ABAP enum
to a CDS enum so that it can be used in SQL, which section 7 pushes you to do —
and any logic that depended on position (a severity ladder, a sort sequence, a
*first entry is the default* dropdown) silently reorders. Walk the `MEMBERS`
table from RTTI if you need the values, and never treat component position as
meaning. The documentation's own guidance is blunt about the whole-structure
case: "Normally, an enumerated structure should not be accessed as a whole and
the order of its components is not important."

The CDS form also brings `@EndUserText.label` per constant, which is the piece
the ABAP form has no answer to — an ABAP enum has no translatable text at all,
only an identifier that section 1 will happily expose to users in uppercase.
See [CDS Annotations](../CDS%20Annotations#readme) and
[Text Elements](../Text%20Elements#readme).

---

## 10. RTTI, RTTC and DESCRIBE FIELD

> "The type returned by the statement DESCRIBE FIELD for an enumerated object is
> k."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

Type kind `k` is the thing to recognise: generic code that switches on
`DESCRIBE FIELD ... TYPE` and handles `I`, `C`, `N`, `P`, `D`, `T`, `X` with a
`WHEN OTHERS` fallback will route every enum into the fallback.

`CL_ABAP_ENUMDESCR` (a subclass of `CL_ABAP_ELEMDESCR`) is the type description
object:

| Attribute | Value |
|---|---|
| `KIND` | always `E` |
| `TYPE_KIND` | always `k` |
| `BASE_TYPE_KIND` | the base type's kind |
| `MEMBERS` | table of the constants and their values (`NAME`, `VALUE`) |

```abap
DATA(lo_enum) = CAST cl_abap_enumdescr(
                  cl_abap_typedescr=>describe_by_data( lv_size ) ).
LOOP AT lo_enum->members ASSIGNING FIELD-SYMBOL(<ls_member>).
  " <ls_member>-name / <ls_member>-value
ENDLOOP.
```

This is the supported way to get the name/value pairs — and the only one that
does not depend on component order. A CDS enumerated type can be described
directly with `DESCRIBE_BY_NAME`, which an ABAP enum cannot be, since it has no
global name.

RTTC exists (`CL_ABAP_ENUMDESCR=>CREATE`, raising `CX_SY_ENUM_CREATION`) with one
catch that makes it near-useless for interoperability:

> "An enumerated type created using RTTC methods is never identical to a type
> defined using TYPES."
> -- [Conversion Rules for Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONVERSION_ENUMERATED.html)

> "Like any enumerated type, an enumerated type created using RTTC is only
> compatible with itself."
> -- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)

Since assignment between enums requires *exactly* the same enumerated type, a
dynamically built enum can never be assigned to a statically declared one, even
with an identical base type and identical members. See
[Runtime Type Services](../Runtime%20Type%20Services#readme).

---

## 11. Serialization sends the name

Consistent with section 1, and worth knowing before an enum appears in an
interface:

> "the content of an enumerated object is represented by the uppercase name of
> the enumerated value with a maximum of 30 characters"
> -- [asJSON - Mapping of Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_ASJSON_ABAP_TYPES_ENUM.html)

So `CALL TRANSFORMATION id` on a table of an enumerated type produces
`["RED","BLUE","GREEN"]`, not `[0,1,2]`, and deserialization matches on the name.
The payload contract is therefore your ABAP identifiers — renaming a constant is
a breaking interface change, and `abap_bool`-style enums serialize as `TRUE`/
`FALSE` strings rather than JSON booleans. [JSON & XML Serialization](../JSON%20Serialization#readme)
covers the rest of the asJSON mapping rules.

---

## Quick reference

| Goal | Write this |
|---|---|
| Get the constant's name | `CONV string( enum )` (or plain assignment to `c`/`string`) |
| Get the stored value | `CONV base_type( enum )` — spell the type out, not `#` |
| Validate external input into an enum | `EXACT enum_type( x )`, catching `CX_SY_CONVERSION_*` |
| Coerce external input into an enum | `CONV enum_type( x )` — truncates/rounds onto a valid value |
| Reset to the initial constant | `CLEAR enum_var.` or `VALUE enum_type( )` |
| Test the initial constant | `IF enum_var IS INITIAL.` |
| Compare against text | `IF CONV string( enum_var ) = \`NAME\`.` |
| Enumerate all members | `LOOP AT lo_enumdescr->members` (not `ASSIGN struc-(idx)`) |
| Use it in ABAP SQL | define the enum in CDS, not ABAP |
| Suppress the extended check message | `##types` on the converting statement |

## Related notes in this repo

- [Type Conversions & Lossless Assignment](../Type%20Conversions#readme) — the general `CONV`/`EXACT` rules this type opts out of
- [Pragmas & Pseudo Comments](../Pragmas%20and%20Pseudo%20Comments#readme) — `##types` and why a misplaced pragma is silent
- [Runtime Type Services](../Runtime%20Type%20Services#readme) — `CL_ABAP_ENUMDESCR` in the RTTS hierarchy
- [JSON & XML Serialization](../JSON%20Serialization#readme) — asJSON mapping
- [CDS Annotations](../CDS%20Annotations#readme) — `@EndUserText.label` on CDS enumerated constants
- [Field Symbols](../Field%20Symbols#readme) / [Reference Casting](../Reference%20Casting#readme) — generic handling, and the casts an enum refuses
- [Dynpro Flow Logic](../Dynpro%20Flow%20Logic#readme) — the PAI event that writes unchecked values
- [List Processing](../List%20Processing#readme) — output length 30 for an enumerated type in a `WRITE`

## Sources

- [TYPES, BEGIN OF ENUM enum_type](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPTYPES_ENUM.html)
- [Enumerated Objects (enum)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENENUMERATED_TYPES_USAGE.html)
- [Conversion Rules for Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONVERSION_ENUMERATED.html)
- [CONV, Conversion of Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCONV_CONSTRUCTOR_ENUM.html)
- [EXACT, Lossless Conversion of Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENEXACT_CONSTRUCTOR_ENUM.html)
- [rel_exp - Comparing Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENLOGEXP_RULES_OPERANDS_ENUM.html)
- [CDS TDL - DEFINE TYPE ENUM](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCDS_DEFINE_ENUM_TYPE.html)
- [asJSON - Mapping of Enumerated Types](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_ASJSON_ABAP_TYPES_ENUM.html)
- [DESCRIBE FIELD](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPDESCRIBE_FIELD.html)

Runnable demo: [`ydj_enum_demo.abap`](ydj_enum_demo.abap)
