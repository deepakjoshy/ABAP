# Internal Table Memory | Table Sharing, Copy-on-Write & Why CLEAR Frees Nothing

Every ABAP developer knows that passing a large internal table around is
"expensive" and that `CLEAR` "empties" it. Both of those beliefs are wrong in
the direction that matters, and the documentation says so explicitly.

The one-sentence version: **assigning one internal table to another does not
copy the rows** — the copy happens later, at the moment somebody writes, and
your memory measurement is taken before or after that moment depending on luck.
And **`CLEAR` on an internal table does not give the memory back**; `FREE`
does, and `DELETE` gives back almost nothing at all.

This note covers the four things that decide the real memory footprint of an
internal table: sharing (copy-on-write), the header/body split, the
`CLEAR`/`FREE`/`DELETE` asymmetry, and boxed components (`BOXED`), which is the
one optimisation SAP actually asks you to reach for by hand.

Related notes:
[Parameter Passing](../Parameter%20Passing#readme) — sharing is exactly why
"pass by value is slow" is not the rule people think it is;
[Mass Data Processing](../Mass%20Data%20Processing#readme) — `PACKAGE SIZE` is
the documentation's own answer to the memory limits described below;
[Internal Table Keys](../Internal%20Table%20Keys#readme) — hashed tables carry
the one-piece allocation constraint in section 5;
[Field Symbols](../Field%20Symbols#readme) — `ASSIGN` is one of the four
documented actions that silently revokes initial value sharing.

Runnable demo: [ydj_table_memory_demo.abap](ydj_table_memory_demo.abap).

## The shape, in one block

```abap
DATA lt_big  TYPE STANDARD TABLE OF sflight WITH EMPTY KEY.
DATA lt_copy TYPE STANDARD TABLE OF sflight WITH EMPTY KEY.

SELECT * FROM sflight INTO TABLE @lt_big UP TO 5000 ROWS.

lt_copy = lt_big.       " <- NO rows copied here. Both point at ONE table body.
                        "    Cost is a new table header, ~100 bytes.

APPEND INITIAL LINE TO lt_copy.   " <- THE COPY HAPPENS HERE. All 5000 rows are
                                  "    duplicated, right now, at this statement.
```

The assignment looks like the expensive line and is cheap. The `APPEND` looks
like the cheap line and is where 5000 rows get duplicated. Any memory or
runtime measurement that brackets only the assignment is measuring nothing.

## Trap 1: assignment shares the table body — the copy is deferred, not avoided

The keyword documentation states the mechanism directly:

> Sharing takes place internally when assignments are made between similar
> strings and similar internal tables that have row types that do not contain
> table types. This means that the actual data values are not copied for the
> time being. Only the necessary administration entries are copied, so that the
> target object points the same data as the source object.
>
> — *Sharing Between Dynamic Data Objects* (ABENMEMORY_CONSUMPTION_3)

And the end of it:

> Active sharing between existing dynamic data objects is canceled at the
> precise moment when either the source object or target object is accessed in
> change mode (**copy-on-write semantics**). The data values are then copied
> and the references and headers modified accordingly.

Three consequences that bite in practice:

**(a) The cost moves to an unrelated line.** The performance trace blames the
`APPEND`, `MODIFY`, `SORT` or `LOOP ... ASSIGNING` that triggered the copy, not
the assignment that set it up. A `SORT` on a "cheap local copy" can be the
single most expensive statement in a program for reasons that are nowhere in
that statement.

**(b) Either side triggers it.** The doc says *source object or target object*.
Modifying the **original** after handing a copy to someone else pays the full
duplication cost too. There is no "owner" that gets to modify for free.

**(c) Writes include field-symbol writes.** `LOOP AT lt_copy ASSIGNING
FIELD-SYMBOL(<ls>)` is change-mode access. `LOOP AT lt_copy INTO ls` is not.
The same loop written two ways has completely different memory behaviour.

## Trap 2: "similar" is deliberately undefined, so you cannot program against it

This is the part that makes sharing an optimisation and not a feature. The same
page:

> Table sharing is principally used only for tables whose row types do not
> themselves contain table types. Otherwise, the prerequisite for "similar
> tables" is kept deliberately vague. Tables are considered to be similar if
> they at least have the same table type, that is the same row type, table
> category, and keys. Additional table combinations are also considered to be
> similar and may be shared. However, this is an internal optimization measure
> that may change between releases. **This means programming must never be
> based on when table sharing occurs and when it is canceled again.**

Read that last sentence as a hard rule. Two practical readings:

- **Do not design for it.** "It's fine, ABAP shares it" is not a memory plan. A
  row type that gains a nested table component in a future release — someone
  appending a table-typed field to a DDIC structure — silently turns every
  assignment in your program from a pointer copy into a full duplication, with
  no code change on your side.
- **Do not design against it either.** Writing `LOOP AT src INTO ls. APPEND ls
  TO tgt. ENDLOOP.` to "force a real copy" is slower and achieves nothing
  a plain assignment does not, because the copy you were worried about happens
  anyway the first time either table is written.

Two further documented cases worth knowing:

- **Sharing also occurs in pass by value to procedures.** So `VALUE(it_data)`
  on a large table is *not* automatically a full copy at call time — it is a
  shared body that duplicates only if the procedure writes to it. The usual
  "always pass by reference for big tables" advice is therefore about
  guaranteeing the semantics you want, not about a copy cost you always pay.
  See [Parameter Passing](../Parameter%20Passing#readme).
- **Reference variables are different.** "Sharing is not canceled when objects
  are modified for reference variables that point to the same data object or
  the same instance of a class." Copy-on-write applies to table bodies and
  strings, never to `REF TO` — two object references always see each other's
  changes, forever.

The profile parameter `abap/table_sharing` exists and controls the mechanism
system-wide. Do not touch it to work around application behaviour; if your
program's correctness depends on its value, the program is wrong.

## Trap 3: the header/body split — an "empty" table is not free

A deep data object is a reference, a header, and the data. The sizes are
documented (*Memory Requirement for Deep Data Objects*,
ABENMEMORY_CONSUMPTION_1):

| Part | Approximate size |
|---|---|
| The reference itself (before any dynamic memory is requested) | exactly 8 bytes |
| Table header, once dynamic memory has been requested | ~100 bytes, **regardless of row count** |
| Pointers, for filled tables | ~50 (32-bit) or ~100 (64-bit) bytes more |
| String header, short string (< ~30 chars) | ~10–40 bytes |
| String header, any longer string | ~50 bytes, regardless of length |
| Box header | ~20–30 bytes |
| Object header | ~30 bytes |

The ~100-byte table header is the number that matters. A structure with 40
table-typed components, used as the row type of a 10,000-row internal table,
carries **40 × 100 bytes × 10,000 = ~40 MB of headers** before a single row of
payload exists. This is the usual explanation for a nested structure that costs
vastly more than the sum of its visible data.

Two related notes from the same page:

- Row-related administration costs live **parallel to the table body**, not in
  the header — "when rows are deleted, the corresponding administration data is
  also deleted."
- An unfilled table costs 8 bytes only. The ~100-byte header is allocated on
  first use and, crucially, **survives initialisation** — see the next trap.

## Trap 4: `CLEAR` does not release memory, `DELETE` releases almost none, `FREE` does

Three statements, three different outcomes, and the everyday one is the weakest.

**`DELETE` — the trap.** The documentation is blunt:

> Deleting rows in internal tables using `DELETE` does **not usually free any
> memory** in the internal table. Statements such as `CLEAR` or `FREE` must be
> used to free memory in internal tables.

So the standard "filter it down in place" pattern — `DELETE lt_data WHERE ...`
removing 95% of rows — leaves the memory footprint essentially unchanged. The
table reports a small `lines( )` and still occupies the old space. This is the
one that produces "but I deleted them" bug reports.

**`CLEAR` — keeps the initial size.** From `CLEAR`:

> All rows in an internal table are deleted. This frees up the memory space
> required for the table, **except for the initial memory requirement** (see
> `INITIAL SIZE`).

and, as an explicit upside:

> In the case of `CLEAR`, the initial memory requirements of an internal table
> are not released, which can have a positive effect on performance when
> inserting new rows in the internal table.

That is the right trade for a table you are about to refill — a work table
inside a loop. It is the wrong trade for a 10,000-row table declared with
`INITIAL SIZE 10000` that you are finished with, because the initial block stays
reserved.

**`FREE` — actually gives it back.**

> The statement `FREE` deletes all rows from an internal table and **releases
> the memory area that the rows occupied**. [...] Unlike `CLEAR`, the initial
> memory area (see `INITIAL SIZE`) remains unoccupied when `FREE` is used. This
> can become necessary when there is a lack of memory.

With the documented caveat on when to use which:

> In general, `FREE` should be used only if the entire memory is to be released
> in full and the internal table is no longer needed (or at the least not filled
> again right away).

Two more details:

- Even `FREE` does not always drop the header: "Only when using the statement
  `FREE` on internal tables are table headers sometimes deleted if they would
  take up too much memory." So the ~100 bytes may persist regardless.
- **For static components, initialization does not currently lead to memory
  being released** — a `CLASS-DATA` table is not freed by clearing it.
- On a table **with a header line**, `FREE` applies to the table body and not
  the header line; and with `CLEAR` you must write `itab[]` or you clear only
  the header line. (Obsolete, but still present in old reports.)

Rule of thumb: **`FREE` when done, `CLEAR` when refilling, never rely on
`DELETE` for memory.**

## Trap 5: hashed tables and strings need their memory in one piece

Two different limits, and only one of them is about total memory
(*Maximum Size of Dynamic Data Objects*, and the *Memory Consumption of Dynamic
Memory Objects* guideline):

- **The row/character ceiling is 2,147,483,647** for both — internal addressing
  uses 4-byte integers.
- **The one-piece rule:** "The size of strings and hash tables is limited by the
  biggest memory block that can be requested in one chunk." That is governed by
  the profile parameter `ztta/max_memreq_MB`.

For a **hashed table** the limit is on the hash administration, not the data,
so it does **not depend on row width**:

> The current limitation is the highest power of two, which is less than or
> equal to an eighth of the value specified by the profile parameter. For
> example, if the profile parameter specifies 250MB, a hashed table can contain
> approximately 16 million rows.

The consequence: a hashed table can fail on a system with plenty of free memory
because no single contiguous block that large is available — and the failing
threshold is a **basis profile parameter**, so the same code can work in
development and terminate in production. "Any attempt to exceed these limits
produces a runtime error and the termination of the program."

The documentation's own preference follows:

> If there is only little memory space available, it may be better to use an
> internal table, because its memory space is **requested in blocks**, while the
> entire memory space required for a string must always be free as a whole.

So under memory pressure a table of lines beats one giant string — which is the
opposite of the usual instinct. (See also
[String Processing](../String%20Processing#readme) for the runtime side of
building large strings.)

## Trap 6: `BOXED` — the one memory optimisation you apply by hand

The problem, from the guideline page:

> Note that statically managed data objects can also involve unnecessary memory
> consumption. For example, large flat structures with unused or initial
> components, whose initial values require a lot of memory space. Here, strings
> that only contain blanks occupy **2 bytes for each blank**. The situation can
> become particularly critical if these structures are combined with dynamic
> techniques (if they are used as internal table rows, for example).

A substructure declared `BOXED` is a **static box**: it stores a reference to a
single system-wide initial value instead of its own copy.

```abap
TYPES:
  BEGIN OF ty_row,
    comp  TYPE c LENGTH 10,
    scarr TYPE scarr BOXED,     " initial value stored ONCE per AS instance
  END OF ty_row.
```

> As long as none of the actions named in the following point were executed,
> initial value sharing applies to a static box. The internal reference points
> to a type-dependent initial value for the structure, which is saved exactly
> once in each AS Instance in the PXA.

So 100,000 rows whose `scarr` substructure is initial cost one copy of it, not
100,000. The documented payoff: "If static boxes are used, initial substructures
do not require multiple memories as long as **only reads are performed**", plus
a runtime benefit because assignments copy only the reference.

**The four documented actions that revoke initial value sharing** — this is the
list to memorise, because three of them do not look like writes:

1. Writes to the static box or one of its components
2. **Assigning the static box or one of its components to a field symbol using
   `ASSIGN`**
3. **Addressing the static box or one of its components using a data reference**
4. **Using a static box or one of its components as an actual parameter for
   procedure calls**

A read-only `LOOP ... ASSIGNING` over the boxed component, or passing it to a
logging routine, silently materialises the structure for that row and the
optimisation is gone. Field symbols and `REF TO` are the two everyday tools that
defeat it — see [Field Symbols](../Field%20Symbols#readme).

And the asymmetry nobody expects:

> The statements `CLEAR` and `FREE` **do not operate as write statements** on a
> static box that has the initial value sharing state, and the state is
> persisted. On the other hand, once the initial value sharing state is revoked,
> these statements **do not currently free up any memory** and provide the local
> instance of the static box with type-dependent initial values instead.

So `CLEAR` on a boxed component is free before it is touched, and useless after.
You cannot clear your way back into initial value sharing.

Two limits: `BOXED` works on substructures (`TYPES`) and on structured
attributes (`[CLASS-]DATA`), and **DDIC database tables cannot contain boxed
components since their structures have to be flat** (DDIC *structures* can).

In RTTI, a boxed component appears as `CL_ABAP_REFDESCR` — like a reference
variable, not like a structure — with `TYPEKIND_BREF` in the component table,
and such a type description object **cannot be used in `CREATE DATA` or `ASSIGN
CASTING`**. Generic code that walks `get_components( )` and assumes structures
look like structures will mis-handle it. See
[Runtime Type Services](../Runtime%20Type%20Services#readme).

## Trap 7: measuring it — and why the number moves

`CL_ABAP_MEMORY_UTILITIES` is the programmatic route:

| Method | Use |
|---|---|
| `GET_TOTAL_USED_SIZE` | exporting `SIZE` (`ABAP_MSIZE`) — total memory of the internal session |
| `GET_MEMORY_SIZE_OF_OBJECT` | importing `OBJECT` (`ANY`); exports `BOUND_SIZE_USED` / `BOUND_SIZE_ALLOC`, `REFERENCED_SIZE_USED` / `REFERENCED_SIZE_ALLOC` |
| `DO_GARBAGE_COLLECTION` | no parameters |

The parameters that make this note's point are on `GET_MEMORY_SIZE_OF_OBJECT`:
**`IGNORE_TABLE_SHARING`** and **`IGNORE_STRING_SHARING`**. Their existence is
the admission that "how big is this table" has two different correct answers —
the memory it would cost on its own, and the memory it actually adds given what
it currently shares with. A benchmark that does not state which one it measured
is not reproducible.

Also exported: `LOW_MEM` (a flag that, due to lack of memory, only the
`BOUND_SIZE_*` values were filled — so the `REFERENCED_*` figures are silently
meaningless when set) and `IS_IN_SHARED_MEMORY`.

The *bound* vs *referenced* distinction matters: bound memory is what belongs to
this object, referenced memory includes what it points at. For a table sharing
its body with another table, these diverge — which is the whole trap in one
measurement.

For interactive work the documentation points at **ABAP Debugger memory
analysis** and **Memory Inspector** (memory snapshots, `S_MEMORY_INSPECTOR`),
which is the better tool for finding the leak rather than confirming a number
you already suspect.

## Rules of thumb

1. **Assignment is cheap; the next write is not.** Look for the write, not the
   assignment, when memory or runtime spikes.
2. **Never program against sharing.** The doc says it may change between
   releases. Nested table types in the row type disable it entirely.
3. **`FREE` when finished, `CLEAR` when refilling.** `DELETE WHERE` frees
   essentially nothing.
4. **A ~100-byte header per table, per row.** Nested table components in a row
   type are the usual cause of a structure costing far more than its data.
5. **Under memory pressure prefer a table to one huge string**, and be aware a
   hashed table's ceiling comes from `ztta/max_memreq_MB`, not from free memory.
6. **`BOXED` pays only while nobody touches it** — and `ASSIGN`, data references
   and parameter passing all count as touching.
7. **State whether you ignored sharing** when you quote a memory figure.

## Sources

- ABAP Keyword Documentation — *Sharing Between Dynamic Data Objects*
  (`ABENMEMORY_CONSUMPTION_3`): the copy-on-write rule, the "deliberately vague"
  similarity definition, pass-by-value sharing, reference-variable exception
- ABAP Keyword Documentation — *Memory Requirement for Deep Data Objects*
  (`ABENMEMORY_CONSUMPTION_1`): header sizes, the `DELETE`-frees-nothing note,
  static components not being released
- ABAP Keyword Documentation — *Maximum Size of Dynamic Data Objects*
  (`ABENMEMORY_CONSUMPTION_2`): the 2³¹-1 ceiling, `ztta/max_memreq_MB`,
  blocks-vs-one-piece
- ABAP Programming Guidelines — *Memory Consumption of Dynamic Memory Objects*
  (`ABENMEM_CONS_DYN_MEM_OBJ_GUIDL`): the hashed-table calculation, the
  `PACKAGE SIZE` recommendation, the boxed-components rationale
- ABAP Keyword Documentation — [`CLEAR`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/abapclear.htm)
  and [`FREE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/abapfree_dataobject.htm)
- ABAP Keyword Documentation — *Boxed Components* / *Static Boxes*
  (`ABENBOXED_COMPONENTS`, `ABENSTATIC_BOXES`): the four revoking actions, the
  `CLEAR`/`FREE` asymmetry, the RTTI representation
- `CL_ABAP_MEMORY_UTILITIES` method signatures
