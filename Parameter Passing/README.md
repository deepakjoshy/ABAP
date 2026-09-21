# Parameter Passing — The `VALUE( )` You Did Not Write

Every ABAP signature makes a decision that most developers never consciously
make. These two declarations are not the same method:

```abap
METHODS read_order EXPORTING ev_status TYPE string.          " by REFERENCE
METHODS read_order EXPORTING VALUE(ev_status) TYPE string.   " by VALUE
```

> "If only one name `p1` `p2` ... is specified, the parameter is passed by
> reference by default."
> — [METHODS, parameters](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapmethods_parameters.htm)

Writing `REFERENCE(ev_status)` is legal and means exactly the same thing as
writing nothing at all. So the default is the one form that is invisible in the
code, and it is the form with the sharp edges. Six of them are below, all
documented, none of them a syntax error.

Related notes: [Exception Flow](../Exception%20Flow#readme) for what an early
exit does to a procedure, [Field Symbols](../Field%20Symbols#readme) for the
other way two names end up pointing at one data object, and
[Constructors](../Constructors#readme) for `RETURNING`-style instantiation.

Runnable demo: [ydj_param_passing_demo.abap](ydj_param_passing_demo.abap) —
local classes and literals only, no DDIC objects and no database access.

## The one-paragraph model

| | Pass by reference (default) | Pass by value (`VALUE( )`) |
|---|---|---|
| Local copy created | No — the procedure works on the caller's object | Yes |
| `EXPORTING` initialized on entry | **No** | Yes |
| `CHANGING`/`EXPORTING` writes visible to caller | **Immediately, statement by statement** | Only on successful completion |
| Early exit via exception | Partial writes **stay** | Actual parameter untouched |
| `IMPORTING` writable inside | No (protected) | Yes |
| `RETURNING` | Not allowed | Mandatory |
| Cost | No copy | Copy (but *sharing* applies to strings/itabs) |

> "In the case of pass by value, a type-compliant local data object is created
> as a copy of the actual parameter for the formal parameter. The system
> initializes output parameters and return values when the procedure is started.
> ... A changed formal parameter is only passed to the actual parameter if the
> procedure is completed without errors."
> — [Passing of Formal Parameters](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENTYPE_TRANSF_FORMAL_PARA_GUIDL.html)

## Trap 1: an `EXPORTING` parameter arrives holding the caller's old value

This is the headline, and it is the one that produces wrong *data* rather than
a dump.

> "An output parameter defined for pass-by-reference behaves like an
> input/output parameter, which means that it is not initialized when the method
> is called. For this reason, no read should be performed on it before the first
> write. In addition, care should be taken when adding content to such
> parameters, for example when inserting rows into internal tables."
> — [METHODS - IMPORTING, EXPORTING, CHANGING, RAISING](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-us/abapmethods_general.htm)

So this entirely reasonable-looking method is broken:

```abap
METHOD fill_by_ref.
  IF iv_found = abap_true.
    ev_text = `row found`.
  ENDIF.
ENDMETHOD.            " nothing found -> ev_text is NOT cleared
```

Call it in a loop over 5,000 documents. Every document that finds nothing
silently reports the **previous** document's answer. No exception, `sy-subrc`
is 0, and the output is plausible — which is why this survives testing, where
the first record usually matches.

The same defect in table form is worse, because a bare `APPEND` looks harmless:

```abap
METHOD append_rows.
  APPEND `ALPHA` TO et_names.   " call 2 appends to call 1's rows
  APPEND `BETA`  TO et_names.
ENDMETHOD.
```

Two calls, four rows. The documentation's own fix is an explicit initialization
as the first statement of the method:

> "If a parameter like this is an internal table or a string, a simple write is
> not sufficient. First, an initialization must be implemented. For example, if
> new rows are to be inserted in an internal table that is supposed to be
> produced by reference, its current content needs to be deleted first. Pass by
> reference means that it cannot be guaranteed that the table is actually empty
> when the procedure is started."
> — [Pass By Reference for Output Parameters](https://help.sap.com/doc/abapdocu_750_index_htm/7.50/en-US/abenref_transf_output_param_guidl.htm)

```abap
METHOD get_some_table.
  CLEAR e_some_table.          " not optional
  ...
  INSERT new_line INTO TABLE e_some_table.
ENDMETHOD.
```

Note the strictness of the rule: it is not "clear it if you might not fill it",
it is **clear it first, always**. And if you genuinely *want* to read the
incoming value, the documentation says say so in the signature — that parameter
is a `CHANGING` parameter, not an `EXPORTING` one.

There is one documented exception. An *optional* output parameter passed by
reference only needs initializing when it was actually bound, which is what
`IS SUPPLIED` is for (the older `IS REQUESTED` is obsolete — see Trap 6).

## Trap 2: writes survive an exception

Pass by value has a transactional flavour: the caller's variable is updated only
if the procedure finishes cleanly. Pass by reference has none.

> "Writes performed on `EXPORTING` and `CHANGING` parameters with the pass by
> reference method work directly on the actual parameters. Their values are also
> modified if the procedure (method) is left early due to an exception."
> — [Passing of Formal Parameters](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENTYPE_TRANSF_FORMAL_PARA_GUIDL.html)

```abap
METHOD build_by_ref.
  ev_out = `HALF-BUILT`.
  RAISE EXCEPTION TYPE lcx_demo.
ENDMETHOD.
```

The caller catches the exception, takes its error branch — and its variable now
holds `HALF-BUILT`. A `CATCH` block that logs the error and carries on with the
old value is carrying on with a value the failed method wrote. Switch the
parameter to `VALUE( )` and the variable is untouched, which is almost always
what the error handler assumed.

## Trap 3: passing an attribute by reference creates an alias

If the actual parameter is something the procedure can *also* reach by name — a
class attribute, a global variable — then pass by reference gives it two names
for one data object, and the procedure's reads see its own writes.

The keyword documentation's own example:

```abap
METHODS do_something CHANGING c_value TYPE numeric.   " by reference

METHOD main.
  attr = '1.23'.
  do_something( CHANGING c_value = attr ).   " attr is now 2.00, not 2.23
ENDMETHOD.
```

> "If a global data object that has also been passed by reference is changed in
> a procedure (method), this also changes the formal parameter and vice versa.
> This behavior is not usually anticipated when writing the procedure."
> — [Pass by Reference of Global Data](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENREF_TRANSF_GLOBAL_DATA_GUIDL.html)

Inside `do_something`, the first assignment to `c_value` also overwrites
`attr`, so a later `attr + 1` computes from the new value instead of the
original `1.23`. Adding `VALUE( )` restores the expected `2.23`. The demo runs
both versions of an identical method body side by side.

The rule the documentation states is blunt: **do not pass global data by
reference** when the procedure can change it another way.

## Trap 4: never pass a system field

The same aliasing, but with a data object that changes on its own:

> "Never use system fields as actual parameters — especially not for passing by
> reference. ... If the value of a system field changes implicitly within a
> procedure, the value of the parameter passed by reference, which refers to
> this system field, also changes. Procedures are never prepared for this
> behavior."
> — [Using System Fields as Actual Parameters](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENUSE_ACTUAL_PARAMETERS_GUIDL.html)

```abap
DO 2 TIMES.
  do_something( sy-index ).     " bad
ENDDO.

METHOD do_something.            " IMPORTING index TYPE i
  DO 3 TIMES.
    ... index ...               " 1, 2, 3 - NOT the value that was passed
  ENDDO.
ENDMETHOD.
```

`index` is an `IMPORTING` parameter, so it is write-protected — and it still
changes, because the protection stops *the method* writing it, not the kernel.
The documentation goes further and says avoid system fields as actual parameters
even by value, because a later enhancement might change the signature to by
reference without telling any caller. Assign to a helper variable and pass that.

The same logic applies to anything else that moves during the call: `sy-subrc`,
`sy-tabix` (see [Loop Modification](../Loop%20Modification#readme)), and
`sy-datum`/`sy-uzeit` (see [Time Stamps](../Time%20Stamps#readme)).

## Trap 5: `IMPORTING` by reference is protected — `IMPORTING` by value is not

> "The content of an input parameter for which pass-by-reference is defined
> cannot be changed in the method."
> — [METHODS - IMPORTING, EXPORTING, CHANGING, RAISING](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-us/abapmethods_general.htm)

This one cuts the other way from all the traps above: the *default* is the safe
choice here. Adding `VALUE( )` to an `IMPORTING` parameter makes it a writable
local variable, so the popular habit of normalizing an input in place —

```abap
METHODS meth IMPORTING VALUE(iv_matnr) TYPE matnr.

METHOD meth.
  iv_matnr = |{ iv_matnr ALPHA = IN }|.   " compiles only because of VALUE( )
```

— compiles, is invisible to the caller, and quietly makes `iv_` a lie. If you
need a normalized form, declare a local. (See
[Conversion Routines](../Conversion%20Routines#readme) for the `ALPHA` part.)

There is one more asymmetry worth knowing: for a `RETURNING` parameter there is
no choice at all. `RETURNING` **always** requires pass by value — which is why
a functional method can never hand back a reference to its own internals, and
why returning a large internal table costs a copy unless *sharing* saves you.

## Trap 6: `IS SUPPLIED` is not `IS INITIAL`

Optional parameters have their own version of "is this value real?".

> "This predicate expression checks whether a formal parameter `para` of a
> procedure is filled or requested. The expression is true if an actual
> parameter was assigned to the formal parameter when it was called."
> — [rel_exp - IS SUPPLIED](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLOGEXP_SUPPLIED.html)

With `DEFAULT`, the usual `IF iv_flag IS INITIAL` check cannot distinguish "the
caller passed nothing" from "the caller explicitly passed 0" — the
documentation's own note on its example says the initial-value check "would not
be sufficient here, because this is the value of the replacement parameter
specified with `DEFAULT`". For a method where 0 is a meaningful input, that is a
real bug.

Three places where `IS SUPPLIED` is documented **not** to be evaluated, and
returns **true** regardless:

- a function module called with `CALL FUNCTION ... STARTING NEW TASK`
- an update function module called `IN UPDATE TASK` (see
  [Update Task](../Update%20Task#readme))
- calls from an older external RFC library such as `librfc32.dll` (see
  [RFC Calls](../RFC%20Calls#readme))

So a function module that behaves one way when called locally can take the other
branch when the identical call is made asynchronously.

Also note the documented hint that in a functionally called method,
`IS SUPPLIED` is **true** for the return value, because a temporary actual
parameter is always bound to it.

## Choosing, in practice

The guideline is a two-line rule with a real trade-off behind it:

> "Pass by value for small data sets for security reasons. Pass by reference for
> large data sets for performance reasons."
> — [Passing of Formal Parameters](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENTYPE_TRANSF_FORMAL_PARA_GUIDL.html)

Two things soften the performance half of that. First, *sharing*: for strings
and internal tables passed by value, ABAP initially passes only a reference and
skips the copy entirely if nobody writes — so the documentation notes that pass
by value costs nothing for an `EXPORTING` table the caller only reads. Second,
flat elementary parameters are cheap to copy in any case. Which leaves pass by
reference genuinely worth it mainly for large tables in mass-data paths — and
there, the `CLEAR` from Trap 1 is mandatory, not optional.

| Situation | Use |
|---|---|
| `RETURNING` | `VALUE( )` — no choice |
| `IMPORTING`, elementary | Default (by reference); it is protected |
| `IMPORTING`, needs local normalization | Declare a local, not `VALUE( )` |
| `EXPORTING`/`CHANGING`, small | `VALUE( )` — robustness, and exception safety |
| `EXPORTING`/`CHANGING`, large table, hot path | By reference **plus** `CLEAR` on entry |
| Actual parameter is an attribute/global | `VALUE( )` |
| Actual parameter is a system field | Neither — copy to a helper variable first |

## References

- [Passing of Formal Parameters (guideline)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENTYPE_TRANSF_FORMAL_PARA_GUIDL.html)
- [Pass By Reference for Output Parameters (guideline)](https://help.sap.com/doc/abapdocu_750_index_htm/7.50/en-US/abenref_transf_output_param_guidl.htm)
- [Pass by Reference of Global Data (guideline)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENREF_TRANSF_GLOBAL_DATA_GUIDL.html)
- [Using System Fields as Actual Parameters (guideline)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENUSE_ACTUAL_PARAMETERS_GUIDL.html)
- [METHODS, parameters](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapmethods_parameters.htm)
- [METHODS - IMPORTING, EXPORTING, CHANGING, RAISING](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-us/abapmethods_general.htm)
- [rel_exp - IS SUPPLIED](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLOGEXP_SUPPLIED.html)
- [FORM, parameters](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapform_parameters.htm) (subroutines: `VALUE` or by reference; no `REFERENCE( )` form)
- [Pass by value or pass by reference? — SAP Community](https://community.sap.com/t5/application-development-and-automation-blog-posts/pass-by-value-or-pass-by-reference/ba-p/13485260)
