# Interfaces — Flat Nesting, the Diamond That Is Not a Diamond & the Optional Method That Returns 0

`INTERFACES` already appears in six files in this repo — `DesignPatterns/Strategy.abap`,
`DesignPatterns/Adapter.abap`, `AMDP/ydj_amdp_demo.abap`, `AUnits/ZCL_TestSeams_Demo.abap`,
`ABAPConstructorExpressions.abap` and `NewABAPTableExpressions.abap` — and is nowhere explained. The
one-line version ("a contract with no implementation") is true and useless. The
parts that actually catch people are the composition rules, because ABAP's
answers are *not* the Java/C# answers:

> "Each interface and its components appear only once in a composite interface.
> Even an interface that is seemingly implemented more than once in an interface
> [...] really exists only once."
> — [`INTERFACES`, composition](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINTERFACES_IFAC.html)

That single sentence removes the diamond problem *and* removes your ability to
do anything about it. Everything below follows from it.

Related notes: [Reference Casting](../Reference%20Casting#readme) for what `?=`
does between interface references, [Constructors](../Constructors#readme) for
why `me->` is not what you think during construction,
[BAdIs](../BAdIs#readme) for `DEFAULT IGNORE` in its other home, and
[ABAP Unit](../AUnits#readme) for `PARTIALLY IMPLEMENTED`.

Runnable demo: [ydj_interfaces_demo.abap](ydj_interfaces_demo.abap) — local
interfaces, local classes and literals only. No DDIC objects, no database, no
`COMMIT`.

---

## The model in one table

| Thing | Where it lives | Addressed as |
|---|---|---|
| Interface method `meth` of `intf` | in the implementing class, as a public component | `cref->intf~meth( )` or `iref->meth( )` |
| Interface `CLASS-DATA attr` | **once per implementing class** | `class=>intf~attr` — *never* `intf=>attr` |
| Interface `CONSTANTS const` | in the interface | `intf=>const` — this one *does* work |
| Alias declared with `ALIASES` | a component of the class/interface, same namespace | the alias name |
| `intf` included in `intf2` | flat — **not** a level | still `intf~comp` |

The last row is the one that surprises everyone.

---

## Trap 1 — nesting is flat, and the name never chains

`INTERFACES intf.` inside an interface declaration makes `intf` a *component
interface*. It is tempting to read that as nesting, with a path. It is not:

```abap
INTERFACE lif_readable.
  METHODS read RETURNING VALUE(rv_text) TYPE string.
ENDINTERFACE.

INTERFACE lif_auditable.
  INTERFACES lif_readable.      " composite
  METHODS audit RETURNING VALUE(rv_text) TYPE string.
ENDINTERFACE.

CLASS lcl_document DEFINITION.
  PUBLIC SECTION.
    INTERFACES lif_auditable.   " the class never names lif_readable
ENDCLASS.
```

The class implements `read( )` under the name of the interface that **declared**
it, not the one it came in through:

```abap
METHOD lif_readable~read.       " correct
METHOD lif_auditable~lif_readable~read.   " not valid syntax
```

The docs are explicit:

> "A direct chaining of interface names `intf1~...~intfn~comp` is not possible."
> — [Interface Component Selector](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENINTERFACE_COMPONENT_SELECTOR.html)

> "All the interface components are at the same hierarchical level."

**Why this bites:** you implement `lif_auditable`, the syntax check demands
`lif_readable~read`, and there is no `lif_readable` anywhere in your class
definition. It looks like a mistake. It isn't — the component came in with the
composite and kept its original surname. Conversely, `DATA li TYPE REF TO
lif_readable` binds to your object fine even though you never named
`lif_readable` in `INTERFACES`.

---

## Trap 2 — the diamond is not a diamond, and you cannot make it one

Two composites, both containing `lif_readable`, both implemented by one class:

```abap
INTERFACE lif_auditable.
  INTERFACES lif_readable.
ENDINTERFACE.

INTERFACE lif_archivable.
  INTERFACES lif_readable.
ENDINTERFACE.

CLASS lcl_document DEFINITION.
  PUBLIC SECTION.
    INTERFACES: lif_auditable, lif_archivable.
ENDCLASS.
```

In a language with multiple inheritance this is the diamond, and you would be
asked which `read( )` wins. ABAP does not ask, because there is only one:

> "Even the components of an interface that is the interface component of one or
> more other interface, and appears to be implemented multiple times in a class,
> only exist once."
> — [`INTERFACES`, implementation](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINTERFACES_CLASS.html)

One `METHOD lif_readable~read.` implementation. Both paths reach it. Upcasting
the object to `lif_auditable` and to `lif_archivable`, then narrowing both to
`lif_readable`, gives two references that compare **equal**.

**The real consequence is the restriction, not the convenience.** If
`lif_auditable` and `lif_archivable` each want `read( )` to mean something
slightly different, there is no mechanism for that — no per-path override, no
explicit interface implementation like C#'s `IFoo.Read()`. Your only options are
to rename one of them in its own interface or to split the class. Discover this
*before* you design a class around two third-party interfaces that share an
ancestor.

A second, quieter consequence in the composition rules:

> "Since there are no separate namespaces for global and local interfaces, it
> must be ensured that combinations of local interfaces do not result in
> combinations of global and local interfaces with identical names."

A local `lif_x` and a global `LIF_X` arriving through different composites
cannot both exist once. That is a compile-time break caused by a name, in code
you did not touch.

---

## Trap 3 — an alias is a rename, not a component

`ALIASES short FOR intf~comp.` is frequently described as "exposing the
interface method under your own name". The docs are narrower:

> "An alias name is a component of the class and the interface. It is in the same
> namespace as the other components and is inherited by subclasses."
> — [`ALIASES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPALIASES.html)

Three things follow, all of which trip people:

1. **Same namespace.** You cannot have your own `read( )` *and* an alias `read`
   for `lif_readable~read`. It is one name, and it is taken.
2. **It is not storage.** Aliasing two different interfaces' attributes to the
   same name is not a merge, and aliasing one attribute twice does not give you
   two values. There is one component underneath.
3. **Mixing the two names in one place is a warning.**

   > "Within a context, such as a class declaration or method, only one name
   > should be used to access components. The syntax check issues a warning if
   > both the alias name and the full name `intf~meth` are used together."

Aliases *can* be declared in any visibility section of a class — but that does
not narrow anything useful: the interface component itself stays public, so a
`PRIVATE` alias hides the *short* name only, and `cref->intf~comp` still works
from outside. An alias is a convenience, never an access control.

Two places aliases genuinely earn their keep: making a deeply-composed
component readable (`m1` instead of `i1~meth` from three interfaces down), and
`METHODS <alias> REDEFINITION`, which the docs explicitly allow.

---

## Trap 4 — `DATA VALUES` sets start values, and refuses constants

`INTERFACES ... DATA VALUES attr = val` is the only place a class gets to adjust
an interface's attributes at declaration time:

```abap
CLASS lcl_demo DEFINITION.
  PUBLIC SECTION.
    INTERFACES lif_greet
      DATA VALUES text1 = 'Hello' text2 = 'World'.
ENDCLASS.
```

It "fulfills the same functions as the addition `VALUE` of the statement `DATA`"
— an *initial value*, per implementing class. It is not a configuration
mechanism shared with other implementers, and it does not run any code.

The restriction worth knowing:

> "Constants declared in the interface or in a component interface with the
> statement `CONSTANTS` cannot be specified after the addition `DATA VALUES`."

So the obvious "give this implementation a different constant" is unavailable by
design — which is correct, but the error message arrives later than you'd like.
Same additions also let a class make interface methods `ABSTRACT METHODS` /
`FINAL METHODS` / `ALL METHODS ABSTRACT`; note that making even one interface
method abstract forces **the whole class** to be abstract.

---

## Trap 5 — `DEFAULT IGNORE` returns a filled result

`METHODS meth DEFAULT IGNORE|FAIL` (interfaces only, never classes) makes an
implementation optional. The two kinds behave in opposite ways:

| Addition | Not implemented, then called | |
|---|---|---|
| `DEFAULT IGNORE` | runs "the same as when it is implemented with an empty body" | **silent** |
| `DEFAULT FAIL` | raises `CX_SY_DYN_CALL_ILLEGAL_METHOD`; unhandled → runtime error `CALL_METHOD_NOT_IMPLEMENTED` | loud |

`IGNORE` is the dangerous one, and the docs spell out exactly why:

> "In particular, all actual parameters are initialized that receive values from
> formal parameters using pass by value."
> — [`METHODS`, `DEFAULT`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMETHODS_DEFAULT.html)

So `DATA(lv_score) = li_thing->score( ).` returns **0**, not "nothing". No
exception, no log, no `sy-subrc`. Zero is a plausible score, an empty table is a
plausible result set, and `abap_false` is a plausible flag. The method that was
never written is indistinguishable from the method that ran and found nothing.

Two more rules on top:

- **Redefinition inherits the default.** A subclass redefining an optional
  method need not implement it, and the default behaviour then "is applied along
  a path of the inheritance tree until an explicit implementation occurs" —
  so a `REDEFINITION` with no body silently *reverts* to `IGNORE`, discarding a
  perfectly good superclass implementation. The docs call this out: "this is not
  recommended. The default behavior is often not as expected, particularly if an
  explicit implementation already exists in a preceding superclass."
- **`DEFAULT` is not allowed on constructors or test methods.**

Compare with [BAdIs](../BAdIs#readme): `DEFAULT IGNORE` *is* the built-in
behaviour of `CALL BADI`, whereas `DEFAULT FAIL` matches what a plain global
interface does for a missing non-optional method.

---

## Trap 6 — interface `CLASS-DATA` is per implementing class

An interface can declare `CLASS-DATA`. It looks like exactly the right place for
a registry, a cache or a call counter shared by every implementer. It is not:

> "When an interface is implemented in a class, the components of this interface
> are added to the other components of the public visibility section. A component
> `comp` of an implemented interface `intf` becomes a fully-fledged component of
> the class."
> — [ABAP Objects — Interfaces](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENINTERFAC.html)

A *fully-fledged component of the class* — so each implementing class gets its
own copy. Two classes implementing `lif_countable`, four `bump( )` calls
between them, and:

```abap
lcl_counter_a=>lif_countable~gv_calls   " 3
lcl_counter_b=>lif_countable~gv_calls   " 1
```

There is no fourth place holding 4. The counter is always plausible and always
partial, which is why this survives testing with one implementer and breaks the
day someone adds a second.

The inheritance case behaves the other way round and is worth keeping straight:
static attributes of a *superclass* really do exist once across the whole
subtree — "A change to a static attribute applies to all classes in which it
exists, independently of the addressing"
([`CLASS-DATA`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCLASS-DATA.html)).
Inheritance shares; interface implementation copies.

If you want one shared value across implementers, put it in a real class and let
the implementers use it.

---

## Trap 7 — `intf=>const` works, `intf=>attr` does not

The class component selector reaches *some* static components of an interface:

> "In the case of static components of interfaces, the name of the interface can
> only be used to access constants. [...] All other static components of an
> interface, apart from object references, can be accessed using classes that
> implement the interface."

| Written | Result |
|---|---|
| `intf=>const` | ✔ constants |
| `intf=>type` | ✔ data types (`TYPES`) |
| `intf=>attr` (`CLASS-DATA`) | ✘ syntax error |
| `class=>intf~attr` | ✔ |
| `class=>intf~meth( )` | ✔ static method |

This is the practical reason ABAP codebases put constants in interfaces —
`if_xyz=>co_status_open` needs no class and no instance. It is also why the
first attempt at a shared counter fails at the syntax check rather than at
runtime, which is the one mercy in this area.

---

## Trap 8 — the missing implementation is a *warning*, not an error

This one is release-engineering, not syntax:

> "If the implementation of a non-optional method of a global interface
> implemented using `INTERFACES` is missing in a class, a syntax **warning**
> occurs instead of a syntax error. This prevents classes from becoming unusable
> due to subsequent enhancements of global interfaces. Calling a missing
> implementation, however, always raises an exception of the class
> `CX_SY_DYN_CALL_ILLEGAL_METHOD`."

So SAP adding a method to a global interface you implement does **not** break
your class at activation — it breaks it at the moment someone calls the new
method, possibly months later, in whichever system got there first. Treat that
warning as an error in your own review.

The asymmetry to remember: **local** interfaces give a real syntax error for the
same omission. Global is forgiving, local is not. The same split applies to the
reverse mistake (implementing a method that the interface does not declare —
warning for global, error for local; the docs call such an implementation "dead
code that cannot be executed and should [be] removed").

And the sanctioned way to under-implement on purpose, for hand-written test
doubles:

```abap
CLASS mock_server DEFINITION FOR TESTING FINAL.
  PUBLIC SECTION.
    INTERFACES if_http_server PARTIALLY IMPLEMENTED.
ENDCLASS.
```

> "The addition `PARTIALLY IMPLEMENTED` [...] can only be used in test classes."
> Calling a non-implemented method during a test raises
> `CX_SY_DYN_CALL_ILLEGAL_METHOD`.
> — [`INTERFACES`, `PARTIALLY IMPLEMENTED`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINTERFACES_PARTIALLY.html)

Note it fails like `DEFAULT FAIL`, not like `DEFAULT IGNORE` — a test double
that gets called somewhere you didn't expect tells you so, loudly. That is the
right default, and it is the opposite of trap 5.

---

## Quick checklist

- Implementing a composite → the syntax check will ask for `<declaring_intf>~meth`,
  not `<composite>~meth`. Not a mistake.
- Never write `intf1~intf2~comp`. It is not valid syntax in any position.
- Two interfaces sharing an ancestor → **one** implementation, no override point.
  Check this before designing around it.
- Aliases: one name per component per context, no access control, not storage.
- Optional interface method → decide `IGNORE` vs `FAIL` deliberately. `IGNORE`
  returns a *filled* initial value and is invisible.
- Redefining an optional method → **always implement it explicitly**.
- Need shared state across implementers? Not interface `CLASS-DATA`. Use a class.
- Constants in interfaces are idiomatic (`intf=>const`); static attributes there
  are not reachable that way at all.
- A missing implementation of a *global* interface method is only a warning.
  Do not let it ship.
- Test doubles: `PARTIALLY IMPLEMENTED`, and only in test classes.

---

References:
[ABAP Objects — Interfaces](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENINTERFAC.html) ·
[`INTERFACES`, implementation](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINTERFACES_CLASS.html) ·
[`INTERFACES`, composition](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINTERFACES_IFAC.html) ·
[`INTERFACES`, `PARTIALLY IMPLEMENTED`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINTERFACES_PARTIALLY.html) ·
[`ALIASES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPALIASES.html) ·
[`METHODS`, `DEFAULT`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMETHODS_DEFAULT.html) ·
[`METHODS`, `REDEFINITION`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMETHODS_REDEFINITION.html) ·
[`CLASS-DATA`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCLASS-DATA.html) ·
[`CONSTANTS`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCONSTANTS.html) ·
[Interface Component Selector](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENINTERFACE_COMPONENT_SELECTOR.html) ·
[Class Component Selector](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCLASS_COMPONENT_SELECTOR.html)
