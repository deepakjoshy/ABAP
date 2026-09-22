# Enhancement Framework — The Post-Exit That Does Not Run and the Section That Replaces Instead of Appends

[BAdIs](../BAdIs#readme) are the *object* half of the Enhancement Framework. This
note is the other half: **source code enhancements** (`ENHANCEMENT-POINT`,
`ENHANCEMENT-SECTION`, implicit enhancement options) and **class enhancements**
(pre-exit, post-exit, overwrite-exit on a method of a global class).

These are how you change SAP standard code without a modification and without a
repair, so almost every customer system is full of them. They are also the part
of the framework where the behaviour is decided by things that are not visible
in the code you are looking at: a switch state, an addition you did not write,
where an include happens to be used, and — in one documented case — nothing at
all.

The one-sentence version: **your enhancement compiling and being visible in the
editor does not mean it runs**, and for the two most common exits the reason it
did not run is written in the documentation rather than in your code.

Related notes: [BAdIs](../BAdIs#readme) for the object plug-in half of the same
framework, [Constructors](../Constructors#readme) for the `me->` /
`super->` rules that the `CORE_OBJECT` trap below plays against,
[Exception Flow](../Exception%20Flow#readme) for why "an exception was raised"
is the pivot of the post-exit rule, and [AMDP](../AMDP#readme) — which the
documentation singles out as having no implicit enhancement points at all.

Runnable demo: [ydj_enhancement_demo.abap](ydj_enhancement_demo.abap). It
*simulates* the generated exit structure with local classes, because the real
artefacts cannot live in a report — see the note in section 10.

## The shape, in one block

```abap
" Explicit option: PLUG-INS ARE ADDED here. Needs a real enhancement spot.
ENHANCEMENT-POINT ydj_enh_01 SPOTS ydj_spot.

" Same, but STATIC: intended for DECLARATIONS, and stand-by switches count too.
ENHANCEMENT-POINT ydj_enh_02 SPOTS ydj_spot STATIC.

" Explicit option: THE BLOCK IS REPLACED by exactly one plug-in.
ENHANCEMENT-SECTION ydj_enh_03 SPOTS ydj_spot.
  lv_discount = lv_amount * '0.10'.
END-ENHANCEMENT-SECTION.

" The plug-in itself. You never type this - the Workbench generates it.
ENHANCEMENT 4 ZDJ_ENH_IMPL.
  lv_discount = lv_amount * '0.15'.
ENDENHANCEMENT.
```

`ENHANCEMENT-POINT` **adds**. `ENHANCEMENT-SECTION` **replaces**. That single
difference is the source of half the surprises below, and neither keyword says
so.

## Trap 1: the exit is a *local class*, so `me->` is not the object you are enhancing

When you add a pre-, post- or overwrite-exit to a method of a global class, the
Workbench does not put code inside that method. It generates a **local class**
in the original class's implementation section:

> When `pre`/`post`/`overwrite` methods are created, a local class named
> `lcl_<enhancement_name>` is generated for the enhancement
> `<enhancement_name>`. This local class is attached to the end of the local
> class implementation section in the original class.
>
> You can access the components of the original class within
> `lcl_<enhancement_name>` by the object reference `CORE_OBJECT`.

— [Enhancing the Components of Global Classes or Interfaces](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/86/b83142680d5c33e10000000a155106/content.htm)

So inside your exit:

| You write | You get |
|---|---|
| `me->mv_total` | an attribute of the **generated local class**, not of the enhanced class |
| `core_object->mv_total` | the attribute of the **actual instance** being enhanced |

`me->mv_total` is usually a plain syntax error, which is the good case. The
quiet case is a *static* attribute or a constant of the same name reachable
through the enclosing scope — then it compiles, reads something, and that
something is not the running object's state.

The three generated interfaces are worth recognising in a dump or a where-used
list, because their names are all you get:

| Interface | Exit |
|---|---|
| `IPR_<enhancement_name>` | pre-exit |
| `IPO_<enhancement_name>` | post-exit |
| `IOW_<enhancement_name>` | overwrite-exit |

## Trap 2: the pre-exit cannot export anything, and the post-exit's `EXPORTING` silently became `CHANGING`

The exits do **not** have the signature of the method they enhance. The
documented transformation:

> - The `pre` method does not have `export` parameters.
> - The `post` method does not have `export` parameters; the `export`
>   parameters become `changing` parameters.
> - The `returning` parameter of a functional method becomes a `changing`
>   parameter
> - `overwrite` methods have the same signature as the original method.
> - The parameter definitions of `pre`/`post`/`overwrite` methods cannot be
>   changed.

— [Enhancing the Components of Global Classes or Interfaces](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/86/b83142680d5c33e10000000a155106/content.htm)

Two consequences that decide which exit you actually need:

**A pre-exit can never change the result.** It has no `EXPORTING` and no
`RETURNING`. It can only read the inputs, touch `CORE_OBJECT`, or raise. The
common mistake is picking a pre-exit for "adjust the returned price" — the
parameter you want is not in the signature, and you cannot add it, because the
parameter definitions cannot be changed.

**A post-exit is the only place the result is editable**, and it is editable
because the original's `EXPORTING` arrives as `CHANGING` — meaning it is
**already filled** with whatever the original produced. A post-exit that
assigns unconditionally overwrites the standard result; one that assigns only
in its own special case leaves the standard result intact. Both are one line
apart and neither looks unusual.

The `RETURNING` → `CHANGING` rule is the same story for a functional method:
`rv_result` is not returned from your exit, it is passed in and out.

## Trap 3: the post-exit runs only if the method reaches `ENDMETHOD`

This is the sharpest one, because the failure mode is "the enhancement does
nothing, intermittently".

> A `post-method` is called after the last statement of the existing method
> before ENDMETHOD (**only if the method is exited using ENDMETHOD**).

— [Enhancements to Classes and Interfaces](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/58/4fb541d3d52d31e10000000a155106/content.htm)

The documented interruptions of the `pre → xyz → post` chain:

| Event | `pre` | original `xyz` | `post` |
|---|---|---|---|
| normal run | runs | runs | runs |
| exception raised in `pre` | runs | **skipped** | **skipped** |
| exception raised in `xyz` | runs | runs (partly) | **skipped** |
| `CHECK` / `EXIT` / `RETURN` in `xyz` | runs | runs | **runs** |

The last row is the one people get wrong in both directions, because it changed:

> Starting with SAP NetWeaver 7.0 Enhancement Package 1 and SAP NetWeaver 7.1
> Enhancement Package 1, statements like `CHECK`, `EXIT` and `RETURN` used
> within the method `xyz` do not stop the post-method from being executed. For
> more information, see SAP Note 1083387.

— [Enhancements to Classes and Interfaces](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/58/4fb541d3d52d31e10000000a155106/content.htm)

So on any current release, an early `RETURN` in the standard method is **not**
what skipped your post-exit. An exception is. Which means:

- A post-exit is not a `CLEANUP` block and is not a `finally`. It is the
  success path only.
- Anything that must happen even when the standard method fails does not belong
  in a post-exit at all.
- If a post-exit "works in the test system and not in production", look for the
  exception the production data triggers inside the standard method — not for a
  switch, a transport, or an activation flag.

And because the pre-exit runs *before* the original, raising in the pre-exit is
the documented way to suppress the standard logic entirely — but it suppresses
the post-exit with it.

## Trap 4: an overwrite-exit is mutually exclusive with pre/post, and it silently discards future SAP fixes

> However, an `overwrite` method is executed **instead of** the original method.
> When an `overwrite` method is created, it is not allowed to have `pre` or
> `post` methods for the same original method.

— [Enhancements to Classes and Interfaces](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/58/4fb541d3d52d31e10000000a155106/content.htm)

Two separate costs, one of them deferred:

1. **Immediate:** you cannot layer. Adding an overwrite-exit means removing any
   pre/post exits on that method, including someone else's.
2. **At the next upgrade:** the original method body is dead code. Every note,
   every correction, every fix SAP ever ships for that method is loaded into the
   system, activated, and never executed. Nothing warns you — the code is there,
   it is current, and control never reaches it.

An overwrite-exit is a modification with better paperwork. It is the right tool
occasionally and the wrong default always; the ordering is pre-exit, post-exit,
then overwrite-exit only when the first two genuinely cannot express it.

## Trap 5: `ENHANCEMENT-POINT` without `STATIC` is *dynamic* — compiled in, not executed

Both states exist at once and they are not the same state:

> When the program is generated, the source code plug-ins ... that exist in the
> current system and that have a switch in the state **stand-by or on** are
> inserted at this position.
>
> If the addition `STATIC` is not specified, the source code enhancement is
> dynamic. This means that, when the program is executed, only those source code
> plug-ins are executed whose switch has the state **on**.

— [`ENHANCEMENT-POINT`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapenhancement-point.htm)

So a stand-by plug-in **is in the generated program** — it shows in the editor,
it is syntax-checked, it appears in a where-used — and it does nothing at
runtime. Debugging past it is the usual way people discover this, after
concluding the enhancement "was not transported".

The corollary, and the reason `STATIC` exists:

> The addition `STATIC` is intended for the enhancement of data declarations,
> while the statement `ENHANCEMENT-POINT` without the addition `STATIC` is
> intended for the enhancement of executable code.

— [`ENHANCEMENT-POINT`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapenhancement-point.htm)

A declaration cannot be conditionally present at runtime — either the field
exists or the program does not compile. That is the whole reason declarations
need `STATIC` and executable code does not.

One relieving default, worth knowing before hunting for a switch that does not
exist: *"If no switch is assigned to a source code plug-in, it is handled as if
the switch has the state on."* In a system with no Switch Framework in play,
everything runs.

## Trap 6: `ENHANCEMENT-SECTION` replaces your code — except the declarations, which it appends

`ENHANCEMENT-SECTION` is "replace this block". That is true for executable
statements. For declarations it inverts depending on `STATIC`:

> If the addition `STATIC` is not specified, the source code enhancement is
> dynamic. In a dynamic source code enhancement, **declarative statements are
> not replaced. Instead, the declarative statements of the source code plug-in
> are added** to the declarative statements in the program section.

— [`ENHANCEMENT-SECTION`](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapenhancement-section.htm)

So the same plug-in, on the same section, does two different things to two kinds
of statement: your `DATA` lines join the originals, your executable lines evict
them. A plug-in that re-declares a variable it also intends to replace ends up
with the original declaration still present.

`STATIC` makes it consistent — declarations are replaced too — and the
documentation immediately warns you off it:

> Unlike the statement `ENHANCEMENT-POINT`, the addition `STATIC` of the
> statement `ENHANCEMENT-SECTION` should only be used with maximum caution when
> changing data declarations. This is because a replacement is being done, not
> an enhancement. Application developers at SAP in particular should not use the
> addition `STATIC` at all with `ENHANCEMENT-SECTION` since the change will be
> active in the entire customer system.

— [`ENHANCEMENT-SECTION`](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapenhancement-section.htm)

The one genuinely forgiving rule in this whole area is also here: *"If no
suitable source code plug-in is found, the original section is executed."* An
un-enhanced section behaves exactly as written.

## Trap 7: two plug-ins on one section, and the documentation says the winner is undefined

`ENHANCEMENT-SECTION` takes **exactly one** plug-in — it is a replacement, so
there is no way to take two. If two are eligible, conflict resolution decides,
and when it cannot:

> If more than one conflict-resolving enhancement implementation takes
> precedence, or if there is no conflict-resolving enhancement implementation,
> the conflict cannot be resolved correctly. Instead, one of the primary
> conflict resolving enhancement implementations or one of the conflict
> resolving enhancement implementations is used. **Exactly which implementation
> is used is the same for each program execution, but it is otherwise
> undefined.**

— [`ENHANCEMENT-SECTION`](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapenhancement-section.htm)

"The same for each program execution, but otherwise undefined" is the worst
possible shape for a bug: completely stable in any one system, and free to
differ between development and production, or across an upgrade, with no code
change to point at. This is the same family as the BAdI ordering rule
([BAdIs, trap 5](../BAdIs#readme)) — repeatable but unspecified.

Note the asymmetry with `ENHANCEMENT-POINT`, which has no such problem:
*"Multiple source code plug-ins from multiple enhancement implementations can be
assigned to a single enhancement option"* — because adding several blocks is
well defined where replacing with several is not.

## Trap 8: implicit enhancement options are not always there

Implicit options need no spot and no explicit statement. The documented
positions:

- After the last line of the source code of executable programs, function
  groups, module pools, subroutine pools, and include programs
- Before the first and after the last line of the implementation of a procedure
- Before the first and after the last line of a source code plug-in
- At the end of a visibility area in the declaration section of a local class
- At the end of a list of formal parameters of the same name at the declaration
  of local methods
- In structure definitions using `BEGIN OF` / `END OF`, before the `END OF`

— [Implicit Enhancement Options](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-US/abenimplicit_enh_points.htm)

They are hidden in the editor by default — *Edit → Enhancement Operations → Show
Implicit Enhancement Points*.

The part that bites is that in an include program they can be **absent**:

> The enhancement implementations for implicit enhancement options can only ever
> be appended to a single framework program, which means that the implicit
> enhancement options are not available in include programs when the following
> applies:
>
> - The include program is not included in a framework program.
> - The include program is included more than once in a framework program.
> - The include program is included in multiple programs, and none of these
>   programs is selected as a relevant framework program in ABAP Workbench.
> - The include program is included in multiple programs and at least one of
>   these programs contains an include-bound explicit enhancement point (that
>   is, a point defined using the addition `INCLUDE BOUND`).

— [Implicit Enhancement Options](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-US/abenimplicit_enh_points.htm)

Read the last condition again: **somebody else adding an `INCLUDE BOUND`
enhancement point to an unrelated program can remove the implicit enhancement
options from an include you were relying on.** Nothing in your code changed.

## Trap 9: `INCLUDE BOUND` cannot be mixed, and some places allow no enhancement at all

`INCLUDE BOUND` binds the option to the include rather than to one compilation
unit, so every program including it gets the enhancement — without it, an
enhancement point in an include must be assigned to exactly one compilation
unit in the Enhancement Builder. The restrictions are absolute:

> In an include program, include-bound and non-include-bound source code
> enhancements cannot both be defined at the same time. This also applies if an
> include program includes other include programs.
>
> In an include program that is included in the same program more than once,
> only include-bound source code enhancements are allowed.

— [`ENHANCEMENT-POINT`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapenhancement-point.htm)

"Cannot both be defined at the same time" is a property of the *include*, not of
your statement — so the first enhancement point in a shared include fixes the
style for everyone who comes after.

Two places where there is nothing to enhance:

> No source code enhancements are allowed within interface sections and class
> sections. The only exception are implicit enhancement options at the end of
> types.

— [Enhancements to Classes and Interfaces](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/58/4fb541d3d52d31e10000000a155106/content.htm)

> AMDP methods do not have any implicit enhancement points.

— [Implicit Enhancement Options](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-US/abenimplicit_enh_points.htm)

The AMDP one follows from what an AMDP method body actually is — SQLScript
shipped to the database, not ABAP (see [AMDP](../AMDP#readme)). There is no ABAP
statement sequence to insert into.

## Trap 10: the code is not stored where you are reading it

> Although source code plug-ins are displayed in the same source code as the
> corresponding enhancement points `ENHANCEMENT-POINT` or
> `ENHANCEMENT-SECTION`, they are actually **stored in other include programs**
> that are managed by Enhancement Builder.

— [`ENHANCEMENT`](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapenhancement.htm)

Practical effects: the plug-in is a separate transportable object from the
program it appears in (so they can move independently and arrive out of order);
a text search over the program's source can miss it; and the `ENHANCEMENT` /
`ENDENHANCEMENT` statements cannot be typed:

> The statements `ENHANCEMENT` and `ENDENHANCEMENT` cannot be entered and edited
> directly. Instead, they are generated by ABAP Workbench ... The ID `id` is
> also assigned by the workbench.

— [`ENHANCEMENT`](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapenhancement.htm)

The same applies to deleting an enhancement point you added: once saved, *Edit →
Enhancement Operations → Delete Enhancement* is the only route — removing the
line by hand is not.

Finally, enhancements nest: a plug-in can itself contain `ENHANCEMENT-POINT` and
`ENHANCEMENT-SECTION`, and has implicit options at both ends. Deep enhancement
stacks in a long-lived system are not a misuse; they are the design.

## Choosing an exit

| You need to | Use |
|---|---|
| Validate inputs, or block the standard logic by raising | pre-exit |
| Read or adjust the result the standard method produced | post-exit |
| Run something even when the standard method fails | **neither** — no exit runs after an exception |
| Replace the logic completely, accepting every future SAP fix is dead | overwrite-exit |
| Add code at a point SAP marked | `ENHANCEMENT-POINT` |
| Swap out a block SAP marked | `ENHANCEMENT-SECTION` (exactly one plug-in wins) |
| Add code at the start/end of a procedure SAP did not mark | implicit enhancement option |
| Enhance a declaration | `ENHANCEMENT-POINT ... STATIC` |

## Quick reference

| Symptom | Cause |
|---|---|
| Post-exit does not run | The standard method raised an exception; `RETURN`/`CHECK`/`EXIT` is **not** the cause |
| Pre-exit cannot set the result | By design — pre-exits have no `EXPORTING` and no `RETURNING` |
| Post-exit wipes the standard result | Its `CHANGING` parameter arrives already filled; assign conditionally |
| `me->attr` wrong or not found in an exit | The exit is a generated local class — use `CORE_OBJECT->attr` |
| Enhancement visible in the editor, never executed | Dynamic `ENHANCEMENT-POINT` + switch in *stand-by* |
| Replaced block still declares the old variables | Dynamic `ENHANCEMENT-SECTION` appends declarations instead of replacing them |
| Wrong plug-in wins on a section | Unresolvable conflict — documented as undefined, stable per system |
| Implicit options missing in an include | Multiple/zero framework programs, or an `INCLUDE BOUND` point elsewhere |
| SAP note has no effect on a method | An overwrite-exit is bypassing the corrected code |

## Sources

- [`ENHANCEMENT-POINT`](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapenhancement-point.htm) — stand-by vs on, `STATIC` for declarations, `INCLUDE BOUND` uniqueness and mixing rules
- [`ENHANCEMENT-SECTION`](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapenhancement-section.htm) — replacement semantics, the declarative-statements exception, the undefined conflict outcome, the `STATIC` warning
- [`ENHANCEMENT`](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapenhancement.htm) — plug-ins stored in other includes, not directly editable, nesting
- [Implicit Enhancement Options](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-US/abenimplicit_enh_points.htm) — the position list, the four include cases, no implicit points in AMDP methods
- [Enhancements to Classes and Interfaces](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/58/4fb541d3d52d31e10000000a155106/content.htm) — the `pre → xyz → post` chain and its interruptions, `ENDMETHOD` rule, SAP Note 1083387, overwrite exclusivity
- [Enhancing the Components of Global Classes or Interfaces](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/86/b83142680d5c33e10000000a155106/content.htm) — `lcl_<enh>`, `CORE_OBJECT`, `IPR_`/`IPO_`/`IOW_`, the signature transformation rules
- [ABAP Source Code Enhancements](https://help.sap.com/doc/saphelp_nw75/7.5.5/en-US/a0/47e94086087e7fe10000000a1550b0/content.htm) — explicit vs implicit overview, plug-in storage diagram
