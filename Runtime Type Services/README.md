# Runtime Type Services (RTTI / RTTC) — the traps in `describe_by_*`, `components` and `TYPE HANDLE`

RTTS is two things in one class hierarchy: **RTTI** (ask an existing type what it
looks like) and **RTTC** (build a brand-new type at runtime and instantiate it).
Every ALV column builder, every generic mapper, every "upload any structure"
utility in an SAP system is built on it.

The class hierarchy, for reference:

```
CL_ABAP_TYPEDESCR
 |--CL_ABAP_DATADESCR
 |   |--CL_ABAP_ELEMDESCR
 |   |   |--CL_ABAP_ENUMDESCR
 |   |--CL_ABAP_REFDESCR
 |   |--CL_ABAP_COMPLEXDESCR
 |       |--CL_ABAP_STRUCTDESCR
 |       |--CL_ABAP_TABLEDESCR
 |--CL_ABAP_OBJECTDESCR
     |--CL_ABAP_CLASSDESCR
     |--CL_ABAP_INTFDESCR
```

The entry points are `describe_by_data( )`, `describe_by_name( )`,
`describe_by_data_ref( )` and `describe_by_object_ref( )`. They all return the
*static* type `CL_ABAP_TYPEDESCR`, so you almost always need a `CAST` to get at
the interesting attributes.

Everything below compiles. The failures are runtime failures — wrong field
lists, uncatchable dumps, silently duplicated type objects.

## 1. `components` and `get_components( )` are not two names for one thing

`CL_ABAP_STRUCTDESCR` offers both. They return **different tables with different
content**, and picking the wrong one is the single most common RTTI bug.

| | `components` (attribute) | `get_components( )` (method) |
|---|---|---|
| Type | `abap_compdescr_tab` | `abap_component_tab` |
| Per component | `name`, `type_kind`, `length`, `decimals` | `name`, `type` (a full type description object), `as_include`, `suffix` |
| Included structures | flattened into individual fields | **one single line** for the whole include |

So if you need real type information per component (to recurse into a nested
table, to read a DDIC data element), `components` cannot give it to you — there
is no `type` reference in it at all.

And if you need a flat field list of a DDIC structure, `get_components( )` will
quietly hand you two lines for a structure with forty fields:

```abap
DATA(lo) = CAST cl_abap_structdescr(
             cl_abap_typedescr=>describe_by_name( 'P0008' ) ).

DATA(lt) = lo->get_components( ).   " <- 2 lines, not 40
```

From the keyword documentation on `INCLUDE`:

> A structure that is included using `INCLUDE` is handled by the method
> `GET_COMPONENTS` of the class `CL_ABAP_STRUCTDESCR` of RTTI like a
> substructure. The returned component table only contains one line for an
> included structure. The component type is represented by an object from
> `CL_ABAP_STRUCTDESCR`, but the `AS_INCLUDE` column contains the value *X*.

That `as_include = 'X'` flag is the tell. Check `has_include` first; if it is
set, either recurse yourself on every `as_include` line, or use the method built
for it:

```abap
DATA(lt_view0) = lo->get_included_view( 0 ).
DATA(lt_view1) = lo->get_included_view( 1 ).
```

`p_level` controls how many include levels get resolved. The assertions in SAP's
own cheat sheet make the difference concrete for a structure with a named include
`INCLUDE TYPE demo_struc_type AS incl_struct RENAMING WITH SUFFIX _incl`:

- at level `0` the component `INCL_STRUCT` is still present, and `COMP1_INCL` is not
- at level `1` `INCL_STRUCT` is gone and `COMP1_INCL` is there in its place

There is also `get_symbols( )`, which returns the component names of all
components *and* substructures, and `get_ddic_field_list( )` with
`p_including_substructres` for the DDIC-specific case.

## 2. `describe_by_name( )` raises a **classic** exception — `TRY ... CATCH cx_root` will not save you

This one costs people an afternoon. `TYPE_NOT_FOUND` is a classic (non
class-based) exception. It is not a `CX_` class, you cannot reference it, and a
`TRY` block does not intercept it. This dumps:

```abap
TRY.
    descr ?= cl_abap_typedescr=>describe_by_name( 'NO_SUCH_TYPE' ).
  CATCH cx_root.       " <- never reached. Short dump anyway.
ENDTRY.
```

The only handling is the classic form with `EXCEPTIONS` and a `sy-subrc` check,
which in turn means you cannot use the functional/expression call style:

```abap
DATA lo_type TYPE REF TO cl_abap_typedescr.

CALL METHOD cl_abap_typedescr=>describe_by_name
  EXPORTING  p_name         = lv_name
  RECEIVING  p_descr_ref    = lo_type
  EXCEPTIONS type_not_found = 4.

IF sy-subrc <> 0.
  " unknown type - handle it
ENDIF.
```

This is exactly the case that matters, because `describe_by_name( )` is the one
entry point that is normally fed a *runtime* string — a table name off a
selection screen, a type name out of customizing. `describe_by_data( )` takes a
real data object and cannot fail this way.

The same applies to `get_component_type( )` (`component_not_found`,
`unsupported_input_type`) and `get_ddic_field_list( )` (`not_found`,
`no_ddic_type`) — all classic exceptions.

## 3. `GET` vs `CREATE`: same result, different object

`CL_ABAP_STRUCTDESCR`, `CL_ABAP_TABLEDESCR` and `CL_ABAP_REFDESCR` all offer
both a `get( )` and a `create( )` factory method with near-identical parameters.
The difference is not cosmetic:

> `CREATE` ... These return the type description object that was specified by the
> input parameters. **A new type description object is always created.**
>
> It is recommended that the `GET` methods are used instead of `CREATE` to avoid
> creating multiple type description objects for a single type.

`get( )` reuses an existing type description object for an identical type;
`create( )` allocates a fresh one every call. Inside a loop over a thousand
lines, `create( )` gives you a thousand objects describing the same type. Use
`get( )` unless you have a specific reason not to.

## 4. `CREATE DATA ... TYPE HANDLE` needs `CL_ABAP_DATADESCR`, and generic types resolve silently

Two things bite here.

**The cast.** `describe_by_data( )` has the static return type
`CL_ABAP_TYPEDESCR`, which `TYPE HANDLE` does not accept — it wants
`CL_ABAP_DATADESCR` or a subclass. So the cast is not decoration:

```abap
DATA(lo_descr) = CAST cl_abap_datadescr(
                   cl_abap_typedescr=>describe_by_name( 'SCARR' ) ).
CREATE DATA dref TYPE HANDLE lo_descr.
```

**The generic default.** The handle must describe a non-generic type, with a
documented exception that does *not* raise an error:

> Only type description objects for the generic ABAP types `c`, `n`, `p`, and `x`
> create and use a new bound data type with the standard values. Similarly, a
> type description object for a standard table with a generic table type creates
> and uses a new bound table type with a standard key.

So handing `TYPE HANDLE` a generic `c` silently gives you `c LENGTH 1`, and a
generic standard table type silently gives you a **standard key** — which, per
the notes in [Internal Table Keys](../Internal%20Table%20Keys#readme), keys on
every character-like component. No syntax error, no exception, wrong behaviour
later.

Building the type properly, with keys, is worth the extra parameters:

```abap
DATA(lo_tab) = cl_abap_tabledescr=>get(
    p_line_type  = lo_line_type
    p_table_kind = cl_abap_tabledescr=>tablekind_sorted
    p_key        = VALUE #( ( name = 'CARRID' ) )
    p_unique     = abap_true
    p_key_kind   = cl_abap_tabledescr=>keydefkind_user ).
```

For secondary keys use `get_with_keys( )` instead — note that in its `p_keys`
table the primary key entry carries `is_primary = abap_true` and an empty `name`
unless the table declares a primary key alias.

To verify the result, `applies_to_data( )` compares a type description object
against an actual data object and is the cheapest possible regression test:

```abap
ASSERT CAST cl_abap_tabledescr(
         cl_abap_typedescr=>describe_by_data( dref->* ) )->applies_to_data( itab_expected ) = abap_true.
```

## 5. `absolute_name` does not always round-trip

`CREATE DATA dref TYPE (name)` accepts either a relative name (`'LAND1'`) or an
absolute name (`'\TYPE=STRING'`). But a **bound** data type — the anonymous type
of e.g. `DATA lv TYPE p LENGTH 8 DECIMALS 2` — has an absolute name of the form
`\TYPE=%_...` and **no relative name at all**. In ABAP for Cloud Development,
feeding that internal name back into `CREATE DATA` raises
`CX_SY_CREATE_DATA_ERROR`:

```abap
DATA packed TYPE p LENGTH 8 DECIMALS 2.
DATA(abs) = cl_abap_typedescr=>describe_by_data( packed )->absolute_name.

TRY.
    CREATE DATA dref TYPE (abs).      " %_ name -> not usable in ABAP Cloud
  CATCH cx_sy_create_data_error.
ENDTRY.
```

If you need a data object of that shape, pass the type description object
through `TYPE HANDLE` instead of round-tripping a name string. Use
`is_ddic_type( )` and `get_relative_name( )` to find out which kind of name you
are actually holding — a bound type returns an empty relative name.

## 6. Dynamic type names from external input are an injection surface

RTTI is frequently the layer where a user-supplied string first turns into
executable behaviour (a table name, a type name, a `WHERE` clause built
alongside it). The keyword documentation is explicit that this needs checking:
use `CL_ABAP_DYN_PRG` to validate against an allowlist, and the built-in
`escape( )` function where escaping is required. Never concatenate unchecked
input into a dynamic clause.

Worked, runnable examples: [ydj_rtts_demo.abap](ydj_rtts_demo.abap)

---

**References**

- [ABAP keyword docs — Runtime Type Services (RTTS)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/index.htm?file=abenrtti.htm)
- [ABAP keyword docs — CREATE DATA, HANDLE](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCREATE_DATA_HANDLE.html)
- [ABAP keyword docs — INCLUDE, TYPE, STRUCTURE (the `GET_COMPONENTS` / `AS_INCLUDE` note)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINCLUDE_TYPE.html)
- [ABAP keyword docs — Dynamic Programming: security](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/abendynamic_programming_scrty.html)
- [SAP-samples/abap-cheat-sheets — 06_Dynamic_Programming.md](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/06_Dynamic_Programming.md)
- [Stack Overflow — Can't catch TYPE_NOT_FOUND exception](https://stackoverflow.com/questions/30597747/cant-catch-type-not-found-exception)
- [Stack Overflow — get_components on a DDIC structure with includes](https://stackoverflow.com/questions/58410709/get-components-of-ddic-structure-with-includes)
