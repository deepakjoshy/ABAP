# Reference Casting — The Downcast That Fails and Leaves the Old Value Behind

`?=` appears in this repo four times already (`Decorator.abap`,
`ABAPConstructorExpressions.abap`, `AUnits/`, `Runtime Type Services/`) and is
never explained. It is the only assignment operator in ABAP that can fail at
runtime, and the way it fails is the interesting part:

> "If the static type of `destination_ref` is not more general or is the same as
> the dynamic type of `source_ref`, a catchable exception is raised and **the
> target variable keeps its original value**."
> — [`=`, `?=`, Upcast and Downcast](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMOVE_CAST.html)

Not cleared. Not initial. *Unchanged.* So the usual `CATCH
cx_sy_move_cast_error` handler that logs and carries on is working with the
reference the variable held before the cast — in a loop, that is the previous
row's object, still bound, still callable.

Related notes: [Runtime Type Services](../Runtime%20Type%20Services#readme) for
asking about a type instead of casting to it,
[Constructors](../Constructors#readme) for why `IS INSTANCE OF` lies during
construction, and [Exception Flow](../Exception%20Flow#readme) for what a caught
exception leaves behind generally.

Runnable demo: [ydj_ref_cast_demo.abap](ydj_ref_cast_demo.abap) — local classes
and literals only, no DDIC objects and no database access.

## The model in one table

Every reference variable has two types:

| | Set where | Used for |
|---|---|---|
| **Static type** | the declaration (`TYPE REF TO c1`) | what the syntax check allows you to call |
| **Dynamic type** | at runtime, by what it points to | what actually runs |

> "The static type of a reference variable is always less specific or the same
> as the dynamic type. This basic rule determines all assignments between
> reference variables."
> — [Assignment Rules for Reference Variables](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_REFERENCES.html)

| Direction | Target static type | Operator | Checked |
|---|---|---|---|
| **Upcast** (widening) | more general | `=` (also `?=`, `CAST`) | compile time, always succeeds |
| **Downcast** (narrowing) | more specific | `?=`, `CAST`, `WHEN TYPE ... INTO` | **runtime** |

No conversion happens either way — both variables end up pointing at the same
object. Only the *static* type differs, i.e. only what you are allowed to type
after `->`.

## Trap 1: the failed downcast keeps the previous value

```abap
DATA lo_invoice TYPE REF TO lcl_invoice.

LOOP AT lt_docs INTO DATA(lo_doc).
  TRY.
      lo_invoice ?= lo_doc.                  " lo_doc may be an lcl_order
    CATCH cx_sy_move_cast_error.
      " "not an invoice, skip" -- except lo_invoice still points at
      " the LAST invoice that cast successfully
  ENDTRY.
  IF lo_invoice IS BOUND.                    " TRUE. Wrong object.
    post( lo_invoice ).
  ENDIF.
ENDLOOP.
```

`IS BOUND` is true, the method call succeeds, and the wrong document gets
posted — with no dump and no short text in the log. The fix is either a
`CLEAR lo_invoice` before every cast, or not casting blind at all (Trap 4).

The same asymmetry shows up as three separate runtime errors, worth
recognising in a dump: `MOVE_CAST_ERROR` (type conflict), `MOVE_CAST_ERROR_DYN`
(dynamic type conflict) and `MOVE_CAST_REF_ONLY` — the last one meaning one of
the two operands was not a reference variable at all.

## Trap 2: a downcast of an initial reference never fails

> "The null reference of an initial reference variable can be assigned to every
> target variable in a downcast that can be specified here. The same applies to
> a non-initial invalid reference that no longer points to an object."
> — [`=`, `?=`, Upcast and Downcast](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMOVE_CAST.html)

So `?=` is not a type check. Cast an unbound `lcl_order` reference into an
`lcl_invoice` variable and it goes through quietly — there is no dynamic type to
conflict with. `sy-subrc` is untouched, no exception is raised, and the target
is now a bound-looking-but-null reference of the wrong conceptual type. The
failure surfaces later as `OBJECTS_OBJREF_NOT_ASSIGNED` at the first `->`,
somewhere that has nothing to do with the cast.

Guard with `IS BOUND` **before** the cast, not after it.

## Trap 3: `IS INSTANCE OF` switches to the static type when the reference is initial

The recommended pre-check has the same hole, by design:

> "The predicate expression `IS INSTANCE OF` checks whether — for a non-initial
> object reference variable `oref` the **dynamic type**, for an initial object
> reference variable `oref` the **static type** — is more specific or equal to a
> comparison type."
> — [`IS INSTANCE OF`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLOGEXP_INSTANCE_OF.html)

An initial `TYPE REF TO lcl_invoice` variable *is* an instance of
`lcl_invoice` as far as this expression is concerned. The documentation is
explicit that this is the intended use for generically typed field symbols and
formal parameters — "it is possible to detect at runtime whether the field
symbol or the formal parameter represents an object reference variable of a
certain static type" — but it makes `IF lo_ref IS INSTANCE OF lcl_invoice`
useless as a bound-ness test.

One special case inverts it: if the static type of `oref` is an **interface**
and the comparison type is a **class**, the result for an initial reference is
always false.

## Trap 4: `CASE TYPE OF` branch order is silent

`CASE TYPE OF` is shorthand for a chain of `IS INSTANCE OF`, and it has the
matching hazard:

> "In the control structure, more specific classes `class` or interfaces `intf`
> must be listed before more general classes or interfaces to enable the
> associated statement block to be executed."
> — [`CASE TYPE OF`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCASE_TYPE.html)

The *first* matching branch wins, and a superclass matches every subclass. Put
`WHEN TYPE lcl_document` at the top and every branch below it is dead code —
no syntax error, no warning, just one branch handling everything. This is the
usual cause of "my new subclass branch never runs" after someone appends a
`WHEN TYPE` to the bottom of an existing list.

The `INTO` addition folds the check and the downcast together and is the
version worth writing, because there is no failure path left to mishandle:

```abap
CASE TYPE OF lo_doc.
  WHEN TYPE lcl_credit_note INTO DATA(lo_credit).   " most specific first
    ...
  WHEN TYPE lcl_invoice INTO DATA(lo_inv).
    ...
  WHEN OTHERS.
ENDCASE.
```

Documented as exactly equivalent to `DATA(ref) = CAST class|intf( oref ).`
inside the branch.

## Trap 5: `IS INSTANCE OF` is false for the subclass during construction

> "When a subclass is instantiated, the predicate expression `IS INSTANCE OF` is
> false when the associated object reference to the subclass is checked until
> the instance constructors of all superclasses have been executed. When an
> instance constructor of a superclass is executed, `IS INSTANCE OF` is true for
> the current superclass."
> — [`IS INSTANCE OF`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLOGEXP_INSTANCE_OF.html)

A superclass constructor that registers `me` somewhere, and a listener that
type-switches on what it received, will classify a half-built object as its own
superclass. Same root cause as the no-virtual-dispatch rule in
[Constructors](../Constructors#readme): during a superclass constructor the
object is not yet its final type.

## Trap 6: `CAST` chained with `->` is the least forgiving form

`CAST` exists to remove helper variables, and in operand positions it can be
followed directly by the component selector. That chaining changes the failure
mode:

| Expression | `oref`/`dref` initial | Component missing |
|---|---|---|
| `lo_x ?= lo_src.` | assigned quietly (Trap 2) | n/a |
| `CAST cls( lo_src )->attr` | **uncatchable** `OBJECTS_OBJREF_NOT_ASSIGNED` | syntax error |
| `CAST cls( lo_src )->('ATTR')` | `CX_SY_ASSIGN_ILLEGAL_COMPONENT` | `CX_SY_ASSIGN_ILLEGAL_COMPONENT` |
| `CAST dtype( dref )->*` | **uncatchable** `DATREF_NOT_ASSIGNED` | n/a |

— [`CAST`, Casting Operator](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONSTRUCTOR_EXPRESSION_CAST.html)

A bare `CAST` with nothing chained after it is still allowed as a standalone
statement, and the docs name that as the way to *test* a downcast by catching
`CX_SY_MOVE_CAST_ERROR`.

## Smaller rules that cost an afternoon each

- **Inline declaration works with `=` and `CAST`, never with `?=`.** `DATA(x)
  ?= lo_src.` does not compile; `DATA(x) = CAST lcl_invoice( lo_src ).` does.
  That alone is the practical reason `CAST` wins in new code.
- **An explicit upcast with `CAST` is a legitimate trick**, not a redundancy:
  it is how you give an inline-declared variable a *more general* static type
  than the expression would produce — e.g. casting a factory method's concrete
  return type to the interface you actually want to program against.
- **`?=` is not allowed in multiple assignments** (`a = b = c` style).
- **If the failure is statically provable, neither operator helps.** Casting
  between classes on different branches of the inheritance tree is a syntax
  error, not a runtime exception. Likewise `IS INSTANCE OF` is a syntax error
  when the result is statically known to be false.
- **Only reference-to-reference assignment is legal.** Mixing a reference and a
  non-reference gives a syntax error or the runtime error
  `OBJECTS_MOVE_NOT_SUPPORTED`.
- **`CONV` is not `CAST`.** `CONV` converts a value into a new object of
  another type; `CAST` only relabels the static type of an existing reference.
- `MOVE ... ?TO ...` is the obsolete spelling of `?=`. If you meet it, it is
  doing exactly what `?=` does.

## Sources

- [`=`, `?=`, Upcast and Downcast](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMOVE_CAST.html)
- [Assignment Rules for Reference Variables](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_REFERENCES.html)
- [`CAST`, Casting Operator](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONSTRUCTOR_EXPRESSION_CAST.html)
- [`IS INSTANCE OF`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLOGEXP_INSTANCE_OF.html)
- [`CASE TYPE OF`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCASE_TYPE.html)
