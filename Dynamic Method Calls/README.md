# Dynamic Method Calls — `PARAMETER-TABLE`, the Check You Traded Away & the Name From Outside

`CALL METHOD (class)=>(meth) PARAMETER-TABLE ptab` already appears in this repo,
in [`ABAPConstructorExpressions.abap`](../ABAPConstructorExpressions.abap), as a
bare snippet with no explanation. It is a genuinely useful tool — generic
dispatchers, plugin registries, framework glue — and it is the one call form
where the syntax check stops helping you entirely.

That is the trade, and it is worth stating plainly before the details:

> "The statement `CALL METHOD` should now only be used for the dynamic method
> call. It is unnecessary, and therefore obsolete, for the static method call."
> — [`CALL METHOD`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCALL_METHOD_DYNAMIC.html)

So if you are writing `CALL METHOD` at all, you are writing the dynamic form,
and every name in it is a string the compiler never reads. The keyword
documentation lists **23 distinct runtime errors** for this one statement, all
of them reachable only at runtime. Below are the ones that reach production.

Related notes: [Runtime Type Services](../Runtime%20Type%20Services#readme) for
inspecting a signature before you call it, [Dynamic SQL](../Dynamic%20SQL#readme)
for the same trade on the database side, and
[Reference Casting](../Reference%20Casting#readme) for `?=` on the result.

Runnable demo: [ydj_dynamic_call_demo.abap](ydj_dynamic_call_demo.abap) — local
classes and literals only. No DDIC objects, no database, no `COMMIT`.

---

## The five name forms

| Form | Reaches | Note |
|---|---|---|
| `CALL METHOD (meth)` | methods of the **same** class | works like `me->(meth)` |
| `CALL METHOD oref->(meth)` | any visible method of an object | static type searched **first**, then dynamic |
| `CALL METHOD class=>(meth)` | static methods, class fixed | only the method is dynamic |
| `CALL METHOD (class)=>(meth)` | static methods, both dynamic | the risky one |
| `CALL METHOD (class)=>meth` | static methods, class dynamic | method still checked |

Two details from
[`dynamic_meth`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCALL_METHOD_METH_IDENT_DYNA.html)
that are easy to miss:

- **The pseudo reference `super` cannot be used in a dynamic method call.** If
  your dispatcher needs to reach a superclass implementation, it cannot.
- A **literal or constant** `class_name` *is* evaluated statically and the class
  is recognised as a used object. A **variable** is not. So
  `CALL METHOD ('LCL_TARGET')=>('ADD')` still registers a dependency;
  `lv_class = 'LCL_TARGET'` followed by `(lv_class)=>` does not. Same call, two
  different answers in where-used.

---

## Trap 1 — you traded the syntax check, and nothing tells you when it bites

Nothing in a dynamic call is verified at activation: not the class, not the
method, not the parameter names, not the types, not the direction. Rename
`IV_AMOUNT` to `IV_VALUE` in the callee and every dynamic caller still activates
cleanly, passes a where-used check, and fails at the first call that reaches it
with `DYN_CALL_METH_PARAM_NOT_FOUND`.

This is worse than a normal runtime error in two specific ways:

1. **The call is often in a rarely-taken branch.** A dispatcher runs one of
   twelve handlers; eleven are exercised in test.
2. **The method looks dead.** Where-used finds no callers, so it gets "cleaned
   up" in a later refactor, and the deletion also activates cleanly.

The mitigation is not cleverness, it is a comment on the callee saying it is
called dynamically and from where — plus an ABAP Unit test that actually
performs the dynamic call, so the binding is exercised at build time.

---

## Trap 2 — `VALUE` is a *reference*, resolved at the call, not at insert

This is the one that produces wrong numbers rather than dumps. `ptab` rows are
type [`abap_parmbind`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCALL_METHOD_PARAMETER_TABLES.html):

| Column | Type | Meaning |
|---|---|---|
| `NAME` | `c(30)` | formal parameter name, **upper case**, unique key of the table |
| `KIND` | `c(1)` | direction, from `CL_ABAP_OBJECTDESCR`. **Optional** — see trap 3 |
| `VALUE` | `REF TO data` | a *pointer* to the actual parameter |

`VALUE` holds a reference. The data object it points at is read **when
`CALL METHOD` executes**, not when the row was inserted. So the natural
build-it-in-a-loop shape is wrong:

```abap
DATA lv_arg TYPE i.

lv_arg = 2.
INSERT VALUE abap_parmbind( name  = 'IV_A'
                            kind  = cl_abap_objectdescr=>exporting
                            value = REF #( lv_arg ) ) INTO TABLE lt_ptab.
lv_arg = 40.
INSERT VALUE abap_parmbind( name  = 'IV_B'
                            kind  = cl_abap_objectdescr=>exporting
                            value = REF #( lv_arg ) ) INTO TABLE lt_ptab.

CALL METHOD ('LCL_TARGET')=>('ADD') PARAMETER-TABLE lt_ptab.
" 2 + 40 = 80. Both rows point at lv_arg, which now holds 40.
```

No exception, no `sy-subrc`, just a plausible answer. The fix is one distinct
data object per row — a fresh `DATA`, or `REF #( )` over a literal, or a row of
an internal table you do not reuse. The loop version of this mistake (one work
area, `APPEND` in a loop) collapses every parameter onto the final iteration's
value.

---

## Trap 3 — `KIND` is optional, and leaving it initial disables the check

> "This column is used to verify the interface. [...] If `KIND` is initial, no
> check is performed."

Omitting `KIND` does not mean "infer it". It means **do not look**. Fill it in:

| Constant | Direction, *from the caller's side* |
|---|---|
| `cl_abap_objectdescr=>exporting` | you are supplying a value (callee's `IMPORTING`) |
| `cl_abap_objectdescr=>importing` | you are receiving one (callee's `EXPORTING`) |
| `cl_abap_objectdescr=>changing` | both |
| `cl_abap_objectdescr=>receiving` | the `RETURNING` value |

Note the inversion in the first two rows: a method declared
`IMPORTING iv_in` is bound with `kind = exporting`. Getting that backwards
raises `CX_SY_DYN_CALL_ILLEGAL_TYPE` — *if* you filled `KIND` in. Leave it
initial and the wrong binding is simply accepted.

Two more rules on the table itself: it must contain **exactly one row per
non-optional formal parameter**, and it **must not contain a row naming a
parameter that does not exist**. Optional parameters may be omitted.

---

## Trap 4 — the caller owns the target of every result

There is no `IMPORTING` variable in the statement; there is a row in `ptab`
pointing at something you allocated. Two consequences:

- Forget the `RECEIVING`/`IMPORTING` row and the result is computed and
  discarded. The call succeeds.
- Point it at a local that is out of scope by the time the call runs and the
  result lands somewhere nobody reads. ABAP will not dump — the reference keeps
  the object alive — so this is silent.

A helper that *builds and returns* a `ptab` for a caller to execute is the usual
shape of this bug. Build and call in the same method, or pass the targets in.

---

## Trap 5 — `EXCEPTION-TABLE` only handles the *classic* kind

`etab` (type `abap_excpbind_tab`, columns `NAME` and `VALUE TYPE i`) maps
**non-class-based** exceptions to `sy-subrc` values. `NAME` may be a specific
exception or `OTHERS`, upper case.

It does nothing for class-based exceptions. A `RAISE EXCEPTION TYPE cx_...` in
the callee propagates straight through and needs a real `TRY`/`CATCH` around the
`CALL METHOD` — which you need anyway for the `CX_SY_DYN_CALL_*` family. So a
dynamic call to a method with both exception kinds needs `etab` *and*
`TRY`/`CATCH`, and people routinely ship only one.

The copy-paste failure here is its own trap: `etab` **must not** name an
exception the target method does not have. Reusing a working `etab` for a
second, similar method raises `CX_SY_DYN_CALL_EXCP_NOT_FOUND` — a runtime error
created purely by duplicating a line that works.

---

## Trap 6 — `sy-subrc = 0` means "called", not "succeeded"

> "Each method call sets the system field `sy-subrc` to 0 in the moment the
> method is called."

`sy-subrc` after `CALL METHOD` becomes non-zero **only** because an `etab` row
said so. With no `EXCEPTION-TABLE`, checking `sy-subrc` after a dynamic call is
dead code that always passes — the same shape as the `TRANSFER` trap in the
[File Interface](../File%20Interface#readme) note.

---

## Trap 7 — names are upper case

`class_name` "must contain the name of a class in uppercase letters". A
lower-case name raises `CX_SY_DYN_CALL_ILLEGAL_CLASS` /
`CX_SY_DYN_CALL_ILLEGAL_METHOD`, whose text says the class or method *does not
exist* — sending you to look for a transport problem instead of a
`to_upper( )`. Names arriving from a config table, a JSON payload or a
selection screen are the usual source.

---

## Trap 8 — a name from outside is an arbitrary-code hole

SAP's security note on
[Dynamic Calls](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYN_CALL_SCRTY.html)
is unusually blunt:

> "The only way of tackling this security risk is to perform a comparison with
> an include list."

Not a prefix check, not a `Z*` pattern, not "it has to end in `_HANDLER`" — an
include list. `CL_ABAP_DYN_PRG=>CHECK_WHITELIST_TAB` (or `_STR`) does it and
raises `CX_ABAP_NOT_IN_WHITELIST` on a miss:

```abap
DATA lt_allowed TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
INSERT `ZCL_ORDER_HANDLER` INTO TABLE lt_allowed.

TRY.
    DATA(lv_class) = cl_abap_dyn_prg=>check_whitelist_tab(
                       val       = lv_from_customizing
                       whitelist = lt_allowed ).
  CATCH cx_abap_not_in_whitelist.
    " reject BEFORE the call
ENDTRY.
```

The same note lists the other holes of this shape: dynamic `SUBMIT`,
`CALL TRANSACTION`, `LEAVE TO TRANSACTION`, `CREATE OBJECT`, `CALL FUNCTION`
(especially over RFC) and dynamic `PERFORM`. And it adds the part people skip —
an include list is not a substitute for an authorization check on the user.

---

## Errors you will actually see

| Exception | Cause |
|---|---|
| `CX_SY_DYN_CALL_ILLEGAL_CLASS` | class does not exist (or wrong case) |
| `CX_SY_DYN_CALL_ILLEGAL_METHOD` | not found, not visible, not static, not implemented, or is a constructor |
| `CX_SY_DYN_CALL_ILLEGAL_TYPE` | type or `KIND` mismatch |
| `CX_SY_DYN_CALL_PARAM_MISSING` | non-optional parameter absent, or `VALUE` is initial |
| `CX_SY_DYN_CALL_PARAM_NOT_FOUND` | `ptab` names a parameter that does not exist |
| `CX_SY_DYN_CALL_EXCP_NOT_FOUND` | `etab` names an exception that does not exist |
| `CX_SY_REF_IS_INITIAL` | `oref->(meth)` on an unbound reference |

All except the last are subclasses of `CX_SY_DYN_CALL_ERROR`, so one
`CATCH cx_sy_dyn_call_error` covers the family — but **not**
`CX_SY_REF_IS_INITIAL`, which sits directly under `CX_DYNAMIC_CHECK` and needs
its own `CATCH` (or a `cx_root` net) if you use the `oref->(meth)` form. Constructors are explicitly out
of reach: calling the instance or static constructor dynamically raises
`ILLEGAL_METHOD`. Instantiating dynamically is
`CREATE OBJECT oref TYPE (name)`, which has its own
`CX_SY_CREATE_OBJECT_ERROR` — and note that an **abstract** class and a
**`CREATE PRIVATE`** class both fail there, at runtime, where the static form
would have failed at activation.

---

## Rules of thumb

- Reaching for a dynamic call? Check first whether an **interface** solves it.
  A dispatcher over `lif_handler~process( )` keeps the syntax check.
- Always fill `KIND`. It is optional and it is the only free check left.
- One data object per `ptab` row. Never a reused work area.
- `to_upper( )` every name that came from data.
- Include-list anything from outside, with `CL_ABAP_DYN_PRG`.
- `TRY`/`CATCH cx_sy_dyn_call_error` around every dynamic call, always.
- `sy-subrc` after the call is meaningless unless you passed an `etab`.
- Comment the callee to say it is called dynamically, and cover the binding with
  an ABAP Unit test — it is the only thing standing in for the compiler.

---

References:
[`CALL METHOD`, dynamic](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCALL_METHOD_DYNAMIC.html) ·
[`CALL METHOD`, `dynamic_meth`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCALL_METHOD_METH_IDENT_DYNA.html) ·
[`CALL METHOD`, `parameter_tables`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCALL_METHOD_PARAMETER_TABLES.html) ·
[`CREATE OBJECT`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCREATE_OBJECT.html) ·
[Dynamic Calls — security](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYN_CALL_SCRTY.html) ·
[`CLASS`, `IMPLEMENTATION`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCLASS_IMPLEMENTATION.html)
