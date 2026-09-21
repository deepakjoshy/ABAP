# Constructors — No Virtual Dispatch, the `super->` Split, and the Static Constructor That Does Not Run

Every ABAP developer writes `constructor` in their first month and carries over
intuitions from Java or C#. Four of those intuitions are wrong in ABAP, and the
ABAP keyword documentation states each one explicitly. None of them produce a
syntax error — they produce an object that is quietly half-initialised.

Related notes: [Exception Flow](../Exception%20Flow#readme) for `CLEANUP`/`RETRY`,
and [Runtime Type Services](../Runtime%20Type%20Services#readme) for the
`CREATE DATA`/`create( )` side of instantiation.

Runnable demo: [ydj_constructor_demo.abap](ydj_constructor_demo.abap) — local
classes and literals only, no DDIC objects and no database access.

## Trap 1: a method called from a constructor ignores subclass redefinitions

This is the one that reverses a rule most developers think is universal.

> "The methods of subclasses are not visible in constructors. If an instance
> constructor calls an instance method of the same class using the implicit self
> reference `me`, the method is called as implemented in the class of the
> instance constructor, and not in any redefined form that may occur in the
> subclass being instantiated. **This is an exception to the rule** that states
> that, when instance methods are called, the implementation is called in the
> class to whose instance the reference points."
> — [ABAP keyword documentation, Inheritance and Constructors](https://help.sap.com/doc/abapdocu_750_index_htm/7.50/en-US/abeninheritance_constructors.htm)

```abap
CLASS lcl_base IMPLEMENTATION.
  METHOD constructor.
    mv_built_as = describe( ).   " runs lcl_base~describe, ALWAYS
  ENDMETHOD.
ENDCLASS.
```

Instantiate `lcl_derived`, which redefines `describe( )`, and `mv_built_as`
still holds the **base** answer. Call `describe( )` on the very same object one
line later and you get the derived answer. Same object, same method, two results.

In Java and C# the subclass override *does* run from the base constructor (which
is its own famous hazard, since it runs before the subclass fields are
initialised). ABAP made the opposite choice. A template-method pattern where the
constructor calls an abstract-ish hook and expects the subclass to supply the
value therefore silently gets the base implementation — and if the base method is
empty, the attribute stays initial.

Fix: do not call redefinable instance methods from a constructor. Pass the value
in as a constructor parameter, or move the work to a factory method that runs
after construction.

## Trap 2: `super->constructor( )` cuts the constructor in half

> "The instance constructor of a subclass is divided into two parts by the call
> `super->constructor( ... )` (demanded by the syntax). In the statements before
> the call, the constructor behaves like a **static method**, which means that
> the self reference `me->` cannot be used and the constructor does not have
> access to the instance components of its class."
> — [Inheritance and Constructors](https://help.sap.com/doc/abapdocu_750_index_htm/7.50/en-US/abeninheritance_constructors.htm)

```abap
METHOD constructor.
  " mv_raw = iv_raw.          <- SYNTAX ERROR here, not a runtime surprise
  DATA(lv_key) = to_upper( iv_raw ).
  super->constructor( iv_key = lv_key ).
  mv_raw = iv_raw.            " legal from here on
ENDMETHOD.
```

This one at least fails loudly, at compile time. What is less obvious is *why*
the first half exists: its only job is to compute the actual parameters for the
superclass constructor, so only local data, importing parameters and static
attributes are available to it.

Two related rules worth knowing before you refactor an inheritance tree:

- The `super->constructor( )` call is **required** in every subclass constructor,
  even when the superclass has no explicitly declared constructor. The only
  exception is a direct subclass of the root class `object`.
- The parameters you must fill are **not** necessarily the direct superclass
  ones. The documentation says the first *explicitly defined* instance
  constructor along the path up the inheritance tree is the one whose interface
  is filled — so inserting a new intermediate class that declares a constructor
  changes the required parameters at call sites further down.

## Trap 3: reading a constant does not run the static constructor

`class_constructor` runs **once per class per internal session**, before the
class is first accessed. The definition of "accessed" is narrower than it looks:

> "The class is accessed when an instance of the class is created or a static
> component is addressed using the class component selector. **The exception here
> is addressing a type or a constant of the class.**"
> — [ABAP keyword documentation, CLASS-METHODS class_constructor](https://help.sap.com/doc/abapdocu_751_index_htm/7.51/en-US/abapclass-methods_constructor.htm)

So this is not an access:

```abap
DATA(lv_name) = lcl_cfg=>c_name.      " CONSTANT -> class_constructor does NOT run
```

and this is:

```abap
DATA(lv_loaded) = lcl_cfg=>gv_loaded. " CLASS-DATA -> class_constructor runs first
```

The failure mode is a configuration or registry class whose `class_constructor`
fills a static table, consumed through a constant-only façade or a `TYPES`
reference. The lazy initialisation never fires and the table is empty, with no
error anywhere.

Two more rules from the same page that catch people out:

- A static constructor **cannot explicitly address its own class**. Inside
  `lcl_cfg=>class_constructor` you write `gv_loaded`, never `lcl_cfg=>gv_loaded`.
- A **failed dynamic access** to a component that does not exist does not count
  as an access either, so the static constructor is not executed in that case.

## Trap 4: a subclass name in front of an inherited static runs the *superclass* constructor

> "If a static component of a superclass is addressed using the name of a
> subclass, the superclass is addressed and its static constructor is executed,
> **but not the static constructor of the subclass**."
> — [CLASS-METHODS class_constructor](https://help.sap.com/doc/abapdocu_751_index_htm/7.51/en-US/abapclass-methods_constructor.htm)

```abap
DATA(lv) = lcl_sub_s=>gv_counter.   " gv_counter is INHERITED from lcl_sup
```

You wrote the subclass name, so you reasonably expect the subclass to be
initialised. It is not. Only `lcl_sup=>class_constructor` runs. If the subclass
static constructor is what registers it in a handler table or sets its own
static defaults, that registration silently does not happen.

The converse direction is the well-behaved one: addressing a subclass properly
*does* walk up the tree first. The runtime finds the next-highest superclass
whose static constructor has not yet run, executes that, then all classes down to
the one addressed — and "the static constructor must be fully executed, otherwise
a runtime error occurs."

## Trap 5: a static constructor cannot report failure

> "In static constructors, class-based exceptions cannot be declared using
> `RAISING`, since it is generally not specified whether the consumer of a class
> is the first consumer and whether or not this consumer must handle exceptions
> propagated by the static constructor."
> — [CLASS-METHODS class_constructor](https://help.sap.com/doc/abapdocu_751_index_htm/7.51/en-US/abapclass-methods_constructor.htm)

The reasoning is worth internalising: *which* caller happens to touch the class
first is a property of the program flow, not of the code you are writing. So
there is no sensible caller to hand an exception to.

The practical consequences:

- No interface parameters and no `RAISING`. Anything that can fail — a database
  read, a config lookup, an RFC — has no way to signal that it did.
- An unhandled exception inside a static constructor becomes a **short dump in
  whichever unlucky statement touched the class first**, which is frequently
  nowhere near the code that owns the problem.
- The documentation is explicit that the **execution order is program-flow
  dependent** and "static constructors must be implemented so that they can be
  executed in any order." Two static constructors that read each other's static
  attributes will work or not depending on which class is touched first.
- "The point at which the static constructor is called has not yet been
  finalized", and "static methods may be executed before the static constructor
  was ended" — so a static method must not assume its own class constructor has
  completed.

Keep static constructors to assignments that cannot fail. Lazy-load the
expensive, fallible work behind a `get_instance( )` that can raise properly.

## Trap 6: a failed `CREATE OBJECT` clears your reference variable

> "If a catchable exception is raised when the object is created in the instance
> constructor of the class, the created object is deleted and the object
> reference variable `oref` **is initialized**."
> — [ABAP keyword documentation, CREATE OBJECT](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapcreate_object.htm)

The trap is re-using a reference variable:

```abap
TRY.
    CREATE OBJECT lo_ref EXPORTING iv_ok = abap_false.
  CATCH lcx_bad.
    " lo_ref is now INITIAL - the perfectly good object it held is gone
ENDTRY.
```

A retry loop that keeps a last-known-good instance in the same variable loses it
on the first failure, and the `CATCH` block's fallback path then dereferences an
unbound reference and dumps with a different error than the one that actually
occurred. Create into a temporary reference and assign on success.

Related: the documentation notes that if the target reference variable is *also*
passed to the constructor, it already points to the new object during execution —
so pass a different variable when you mean "the previous object".

## Quick reference

| Behaviour | Rule |
|---|---|
| Method call from a constructor | Runs the constructor's class implementation, never a subclass redefinition |
| Before `super->constructor( )` | Acts as a static method: no `me->`, no instance attributes |
| `super->constructor( )` | Required in every subclass except direct subclasses of `object` |
| Which parameters to pass | Those of the first *explicitly defined* constructor up the tree |
| `lcl=>some_constant` | Not an access — `class_constructor` does **not** run |
| `lcl=>some_static_attribute` | Is an access — `class_constructor` runs first |
| `lcl_sub=>inherited_static` | Runs the **superclass** static constructor only |
| Static constructor interface | No parameters, no `RAISING`, order not guaranteed |
| Exception in instance constructor | Object deleted **and** `oref` initialized |

## References

- [ABAP Objects — Constructors of Classes](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abenconstructor.htm)
- [Inheritance and Constructors](https://help.sap.com/doc/abapdocu_750_index_htm/7.50/en-US/abeninheritance_constructors.htm)
- [CLASS-METHODS — class_constructor](https://help.sap.com/doc/abapdocu_751_index_htm/7.51/en-US/abapclass-methods_constructor.htm)
- [CREATE OBJECT](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapcreate_object.htm)
