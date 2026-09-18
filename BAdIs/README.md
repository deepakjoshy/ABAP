# BAdIs — the silent `CALL BADI`, the retained reference and the filter fallback cascade

A BAdI (Business Add-In) is the supported way into standard SAP code, and the two
statements that drive it look reassuringly simple:

```abap
GET BADI  lo_badi FILTERS bukrs = lv_bukrs.
CALL BADI lo_badi->check_document CHANGING cs_doc = ls_doc.
```

Neither behaves like the ordinary object call it resembles. `GET BADI` runs a
four-stage selection with a **fallback cascade** that can hand you an implementation
you did not ask for; `CALL BADI` on a multiple-use BAdI is closer to `RAISE EVENT`
than to a method call and **does nothing at all, with `sy-subrc = 0`**, when nobody
implemented it; and an exception in `GET BADI` **keeps the previous BAdI reference**
instead of clearing it.

All three are documented. All three are invisible in the calling code.

---

## 1. `CALL BADI` on a multiple-use BAdI is allowed to do nothing

For a BAdI defined for **multiple use**, the reference may legitimately hold zero
object plug-ins — and then:

> If the referenced BAdI object does not reference object plug-ins, or the `badi` is
> initial, the statement has no effect.

— [`CALL BADI`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCALL_BADI.html)

No exception, no `sy-subrc <> 0`. The doc spells out the mental model:

> The call of a BAdI method of a BAdI defined for single use behaves like a method
> call with `meth( ...)`: the called method must exist. In contrast, calls of a BAdI
> method defined for multiple use are more like raising an event using `RAISE EVENT`:
> One or more methods can exist, or no methods at all.

So this code cannot tell the two cases apart:

```abap
ls_doc-blocked = abap_false.
CALL BADI lo_badi->check_document CHANGING cs_doc = ls_doc.

IF ls_doc-blocked = abap_false.
  " Did an implementation run and approve the document,
  " or did NOTHING run at all? These are indistinguishable.
  perform_posting( ls_doc ).
ENDIF.
```

The distinction matters most in the case you care about: a customer switched their
enhancement off, the transport of the implementation is stuck in QA, or a filter
value stopped matching — and your validation BAdI silently approves everything.

**The check is explicit, not implicit:**

```abap
DATA(lv_impls) = cl_badi_query=>number_of_implementations( badi = lo_badi ).
IF lv_impls = 0.
  " decide deliberately: default-allow or default-deny
ENDIF.
```

`CL_BADI_QUERY=>NUMBER_OF_IMPLEMENTATIONS` is a static method taking
`BADI TYPE REF TO CL_BADI_BASE` and returning `NUM TYPE i` — and since every BAdI
class inherits from `CL_BADI_BASE`, a statically typed BAdI reference can be passed
straight in.

### The related asymmetry on an initial reference

| BAdI kind | `CALL BADI` with an **initial** reference |
|---|---|
| single use, static call | catchable `CX_BADI_INITIAL_REFERENCE` |
| multiple use, static call | **allowed — statement has no effect** |
| any, dynamic call | catchable exception, always |

An initial reference is the state you are left in when `GET BADI` failed and you
swallowed the exception — which for a multiple-use BAdI then fails quietly forever.

---

## 2. A failed `GET BADI` keeps the *previous* reference

This is the one that produces wrong results rather than no results:

> If the BAdI reference variable `badi` contained a valid BAdI reference before the
> statement in an exception case, this is retained, otherwise it is initialized.

— [`GET BADI`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPGET_BADI.html)

The natural loop shape is therefore unsafe:

```abap
LOOP AT lt_items INTO ls_item.

  TRY.
      GET BADI lo_badi FILTERS werks = ls_item-werks.
    CATCH cx_badi_not_single_use.
      " logged and skipped -- but lo_badi STILL POINTS AT THE PREVIOUS PLANT
  ENDTRY.

  CALL BADI lo_badi->price_item CHANGING cs_item = ls_item.  "<-- wrong plant's logic

ENDLOOP.
```

Item 2 is priced by plant 1's implementation. `IS BOUND` is `abap_true`, so the
usual guard does not help; only clearing the reference in the handler does:

```abap
  CATCH cx_badi_not_single_use.
    CLEAR lo_badi.          " or CONTINUE -- do not fall through to CALL BADI
```

This is the same shape as the stale field symbol after a failed `READ TABLE`
(see [Field Symbols](../Field%20Symbols#readme)): the statement failed, but the
variable still looks valid because it holds the *last successful* binding.

---

## 3. `GET BADI` on a single-use BAdI dumps in a system that never enhanced it

Selection happens in four documented stages — active implementation, switch state,
filter match, conflict resolution — and for a **single-use** BAdI the hit list must
end up with *exactly one* class. Both failures are catchable exceptions raised at
`GET BADI`, not at the call:

| Exception | Cause | Parent |
|---|---|---|
| `CX_BADI_NOT_IMPLEMENTED` | no implementation class found | `CX_BADI_NOT_SINGLE_USE` |
| `CX_BADI_MULTIPLY_IMPLEMENTED` | several found for a single-use BAdI | `CX_BADI_NOT_SINGLE_USE` |
| `CX_BADI_FILTER_ERROR` | bad filter information (dynamic variant) | — |
| `CX_BADI_CONTEXT_ERROR` | context error (dynamic variant) | — |
| `CX_BADI_INITIAL_CONTEXT` | reference after `CONTEXT` is initial | — |
| `CX_BADI_UNKNOWN_ERROR` | BAdI does not exist (dynamic variant) | — |

Catching the common pair is one handler: `CATCH cx_badi_not_single_use`.

If you are the BAdI *provider*, the doc gives the structural fix rather than a
handler:

> To prevent the exception for BAdIs that are defined for single use in systems in
> which no corresponding enhancement is made, it is recommended that a fallback BAdI
> implementation class is specified for these BAdIs. The fallback BAdI implementation
> class is part of the BAdI and is independent of enhancements.

A fallback class ships *with the BAdI definition*, so it is not a transportable
enhancement someone can forget. Without one, your own reusable BAdI works in the
sandbox where you implemented it and dumps in every system that did not.

`CX_BADI_MULTIPLY_IMPLEMENTED` has the opposite trigger and is a design smell:
two implementations whose filter conditions overlap, and no priority-resolving
enhancement implementation to break the tie. The doc is explicit that conflict
resolution simply gives up when priorities are equal — multiple classes then remain
in the hit list and the exception fires.

---

## 4. A filter that matches nothing does not give you nothing

Stage 3 of selection is a cascade, not a lookup:

> All BAdI implementation classes are selected that satisfy the above requirements
> and for which the filter condition of the BAdI implementation matches the values
> specified after `FILTERS` or in `ftab`. **If no BAdI implementations are found with
> the filter specifications, the system searches for BAdI implementations that are
> marked as standard implementations. If non are found, the fallback BAdI
> implementation class of the BAdI is used** (if available).

So a typo in a filter value, a company code that was renamed, or an uninitialised
filter variable does **not** produce `CX_BADI_NOT_IMPLEMENTED` — it quietly runs the
standard implementation, or the fallback. The BAdI fires, the log says an
implementation ran, and it is the wrong one. (Compare the
[Selection Tables](../Selection%20Tables#readme) note: an empty range means *all*,
not *none*. The framework consistently prefers "do something plausible" to "fail".)

Two more selection-stage surprises worth knowing:

- **Switch state beats the active flag.** An implementation assigned to an
  enhancement whose switch is *off* is skipped, even though SE19 shows it as active.
  An implementation with no switch at all is treated as switched *on*.
- **Filter typing.** `FILTERS` operands must be *compatible* with the filter's data
  type, and a filter flagged *Constant Filter Value at Call* accepts only literals
  and constants — not a variable holding the same value.

---

## 5. Multiple use forbids `EXPORTING` and `RETURNING`, and `CHANGING` is last-wins

This is a hard restriction on the *definition*, not a guideline:

> In the case of a multiple use, there is a general restriction [...] that the BAdI
> methods must not have any `EXPORTING` or `RETURNING` parameters. The reason for this
> is that if you have a call with `CALL BADI`, the methods of all the object plug-ins
> referenced by the BAdI object are called and that there is no definition regarding
> from which of the implementations a returned value will actually come. `CHANGING`
> parameters, on the other hand, are allowed since these are changed by all the
> calling methods, one after the other, so that a method can also access the
> parameter changed in a previous method.

— [The Multiple Use Property](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/46a2cfc13d25463b8b9a3d2a3c3ba0d9/e45c3642eca5033be10000000a1550b0.html)

Two practical consequences:

1. **Single use → multiple use is a breaking change.** Every `EXPORTING`/`RETURNING`
   parameter has to become `CHANGING`, so every existing implementation and caller
   is touched. Decide multiplicity when you define the BAdI.
2. **Implementations silently overwrite each other.** With `CHANGING`, plug-in B sees
   and can undo whatever plug-in A wrote. Implementation A's author has no idea B
   exists. The only defence is a documented contract ("append to the message table,
   never clear it") plus an ordering guarantee.

### Ordering is repeatable but not specified

> If the referenced BAdI object refers to multiple object plug-ins, the call order is
> the same for every `CALL BADI` statement. The exact call order can be determined in
> the definition of the associated BAdI implementations if the predefined BAdI
> `BADI_SORTER` of the identically named enhancement spot was implemented for the
> current BAdI.

"The same for every `CALL BADI`" is not "the order you created them in" and not
"stable across transports". If order matters, implement `BADI_SORTER` — filter it on
`BADI_NAME` = your BAdI and supply a sort criterion per implementation — or, better,
design the implementations to be order-independent.

---

## 6. A method added to the BAdI interface later is silently empty everywhere

Extending a released BAdI interface does not break existing implementations. It also
does not tell you they are missing it:

> If a method is added to a BAdI afterwards, it may be missing in a BAdI
> implementation. In this case the call is executed as if the method existed with an
> empty implementation. Actual parameters that are bound to `EXPORTING` or
> `RETURNING` parameters passed by value are initialized. All other actual parameters
> remain unchanged.

So the new method returns **initial** values from every pre-existing implementation —
an initial amount, an initial flag, an empty message table — and there is no way to
distinguish that from a deliberate answer. Worse, the rule is asymmetric: pass-by-value
outputs are cleared, `CHANGING`/reference parameters keep whatever the caller put in.

If you *define* BAdI methods, make the behaviour explicit with `DEFAULT`, which is
allowed in interfaces (including BAdI interfaces) and not in classes:

```abap
METHODS calculate_discount DEFAULT FAIL     " non-implemented call -> CX_SY_DYN_CALL_ILLEGAL_METHOD
  IMPORTING is_order TYPE ty_order
  CHANGING  cv_pct   TYPE p.

METHODS log_event DEFAULT IGNORE            " non-implemented call -> empty body
  IMPORTING iv_text TYPE string.
```

`DEFAULT FAIL` raises `CX_SY_DYN_CALL_ILLEGAL_METHOD` (runtime error
`CALL_METHOD_NOT_IMPLEMENTED` if unhandled) — a loud failure instead of a wrong zero.
Note the default: per the keyword docs, `DEFAULT IGNORE` *is* the built-in behaviour
of `CALL BADI`, so silence is what you get unless you ask for `FAIL`.

---

## 7. Object plug-ins may be singletons — state survives your call

Whether `GET BADI` gives you a fresh implementation instance is a property of the
**BAdI definition**, not of your code:

> Without the addition `CONTEXT`, that is, for context-free BAdIs, the way the object
> plug-ins are created is based on the setting of the BAdI. Either new plug-ins are
> created every time the statement `GET BADI` is executed, or an object plug-in that
> has already been created in the current internal session is reused, if it is
> required again. An object plug-in of this type is a singleton in terms of its BAdI
> implementation class.

If reuse is on, instance attributes of the implementation class persist across every
`GET BADI` in the internal session — so an implementation that caches a customer's
data in an attribute serves it to the *next* customer. The doc frames it as
"stateful or stateless with reference to a BAdI or a context".

There is a second sharing path that surprises people: if one implementation class
implements several BAdI interfaces and you `GET BADI` more than one of them in the
same internal session, **multiple BAdI objects can point to the same object plug-in**
— which the doc notes "enables the sharing of data between different BAdIs".

Practical rule for implementers: treat a BAdI implementation class as if it were
reused, and keep per-call data in local variables, not instance attributes.

For **context-dependent** BAdIs, `CONTEXT con` is mandatory (and forbidden on
context-free ones); the same plug-ins are reused for the same context object, and an
initial `con` raises `CX_BADI_INITIAL_CONTEXT`.

---

## 8. Dynamic `GET BADI`: the one uncatchable case

The dynamic variant replaces `FILTERS` with `FILTER-TABLE ftab` of DDIC table type
`BADI_FILTER_BINDINGS` — a sorted table keyed on `NAME`:

| Column | Type | Note |
|---|---|---|
| `NAME` | `c` length 30 | filter name, **uppercase**; a nonexistent name is an **uncatchable** exception |
| `VALUE` | `REF TO data` | reference to a data object holding the value |

The table must contain **exactly one line per filter** of the BAdI. Everything else
in the dynamic form is catchable (`CX_BADI_UNKNOWN_ERROR` for a bad BAdI name,
`CX_BADI_FILTER_ERROR` for bad filter data) — but a misspelled *filter* name is not,
so build that name from a constant or a DDIC reference, never from user input.

The reference variable in the dynamic form must be typed `CL_BADI_BASE`, and
`CALL BADI ... (meth_name)` needs the method name in **uppercase** or you get
`CX_SY_DYN_CALL_ILLEGAL_METHOD` / `DYN_CALL_METH_NOT_FOUND`.

---

## 9. Classic BAdIs: `CL_EXITHANDLER` does not fail either

Pre-Enhancement-Framework BAdIs (SE18/SE19, adapter classes) are called through
`CL_EXITHANDLER=>GET_INSTANCE`, and the same "quietly does nothing" shape applies:
the `GET_INSTANCE` call and the subsequent method calls still run when there is no
active implementation — the adapter class simply finds none, so the method body is
empty. Standard code littered with `CL_EXITHANDLER=>GET_INSTANCE` is therefore *not*
evidence that anything is enhanced.
([SAP Community discussion](https://community.sap.com/t5/application-development-and-automation-discussions/difference-between-classic-badi-and-kernal-based-badi/m-p/4192620/highlight/true))

New development should use kernel BAdIs: they are statically typed (`GET BADI` on a
typed reference is checked at compile time), filter evaluation is in the kernel, and
the failure modes above are at least *documented* exceptions rather than silence.

---

## Checklist

- Multiple-use BAdI whose result you depend on → check
  `cl_badi_query=>number_of_implementations( )`, do not infer from unchanged data.
- `CATCH cx_badi_not_single_use` → `CLEAR` the reference in the handler.
- Own a single-use BAdI others consume → give it a **fallback implementation class**.
- Order matters between implementations → `BADI_SORTER`, or redesign for
  order-independence.
- Adding a method to a released BAdI interface → `DEFAULT FAIL`, not the implicit
  `IGNORE`.
- Writing an implementation class → assume the instance is reused; no per-call state
  in instance attributes.
- Filter values must be *right*, not merely present: a non-matching filter runs the
  standard or fallback implementation instead of raising.

See [`ydj_badi_traps_demo.abap`](ydj_badi_traps_demo.abap) for a runnable
"what would `GET BADI` actually give me?" inspector, including a live demonstration
of the retained-reference behaviour.

## Sources

- [`GET BADI`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPGET_BADI.html) — selection stages, fallback cascade, retained reference, plug-in reuse, exceptions, `FILTER-TABLE`
- [`CALL BADI`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCALL_BADI.html) — no-effect rule, initial-reference table, added-method behaviour, `BADI_SORTER`
- [`METHODS, DEFAULT`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMETHODS_DEFAULT.html) — `IGNORE` vs `FAIL`
- [The Multiple Use Property](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/46a2cfc13d25463b8b9a3d2a3c3ba0d9/e45c3642eca5033be10000000a1550b0.html) — `EXPORTING`/`RETURNING` restriction, `CHANGING` chaining
- [Calling BAdIs (Enhancement Framework)](https://help.sap.com/doc/saphelp_nw70/7.0.12/ja-JP/79/623a42949fb56be10000000a155106/content.htm?no_cache=true) — `BADI_SORTER` setup steps
