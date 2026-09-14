# Internal Table Keys — DEFAULT KEY, EMPTY KEY and secondary keys

Every internal table has a primary key whether or not you wrote one. The default
you get by omitting it is almost never the one you want, and three of its
consequences are silent: a `SORT` that does nothing useful, a `READ ... WITH KEY`
that matches on fields you never intended, and key fields that are suddenly
read-only.

## The three ways a primary key gets decided

| Declaration | Primary key |
|---|---|
| `DATA it TYPE TABLE OF ty.` | **Standard key** — implicitly *all* character-like and byte-like components |
| `... WITH DEFAULT KEY.` | Standard key, stated explicitly. Same thing, just visible |
| `... WITH EMPTY KEY.` | No key fields at all (standard tables only) |
| `... WITH NON-UNIQUE KEY carrid connid.` | Exactly those two components |

The standard key is the trap. For a structure with `carrid`, `connid`, `cityfrom`,
`cityto`, `airpfrom`, `airpto`, the standard key is **all six** of those
character-like fields — numeric components (`i`, `p`, `decfloat`, `f`) are excluded,
which is why the rule surprises people in both directions.

Two consequences worth internalising:

- **`SORT itab.` without `BY` sorts by the primary key.** With the standard key that
  means sorting by six fields in structure order, which is rarely the sort you
  wanted and is measurably slower than `SORT itab BY carrid connid.`
- **Key fields of the primary key are read-only in sorted and hashed tables.**
  Take the standard key by accident on a `SORTED TABLE` and half your structure
  becomes unassignable — the error shows up at the `MODIFY`, not at the declaration.

> "Specifying keys explicitly has the advantage of making the code more readable and
> preventing the standard key from being set by mistake."
> — [SAP-samples/abap-cheat-sheets, Internal Tables](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/01_Internal_Tables.md)

## When the standard key is silently empty

`WITH DEFAULT KEY` on a line type with **no** character-like or byte-like components
produces an *empty* key — there is nothing for the standard key to pick up. A table
of pure numerics keyed "by default" has no key at all, and then:

- `SORT itab.` does **nothing**. The table comes back in the original order.
- `READ TABLE itab FROM wa.` returns the **first line**, whatever `wa` contains,
  because there are no key components to compare.

Neither raises an error. Both are legal, documented behaviour on an empty key.

The same empty key arrives by another route people forget: an inline-declared
`SELECT` target.

```abap
SELECT * FROM spfli INTO TABLE @DATA(lt_flights).
" lt_flights is a STANDARD table WITH EMPTY KEY.
" A later READ TABLE lt_flights WITH TABLE KEY ... will not compile.
```

Use `EMPTY KEY` deliberately when the table is a sequential list you only ever
`LOOP` over or index — it documents the intent and costs nothing to maintain.
Use an explicit `NON-UNIQUE KEY` when you actually read by key.

## Secondary keys — optimized access on a standard table

A standard table's primary key access is a **linear scan**, even if you declared a
sensible primary key. Sorted and hashed keys are what make key access fast, and a
secondary key adds one to any table category without changing the table's category
or breaking existing statements.

```abap
DATA it_flights TYPE STANDARD TABLE OF spfli
  WITH NON-UNIQUE KEY carrid connid                          "primary
  WITH NON-UNIQUE SORTED KEY cities COMPONENTS cityfrom cityto  "secondary 1
  WITH UNIQUE HASHED KEY airports COMPONENTS airpfrom airpto.   "secondary 2
```

Up to 15 secondary keys per table. Sorted keys give binary search **and** a secondary
table index (so `sy-tabix` is set, and hashed tables become index-accessible through
one). Hashed keys give constant-time access but no index.

### They are never chosen for you

This is the single most common reason a secondary key appears to do nothing:

> "Secondary table keys are not selected and used automatically. If a secondary table
> key is not specified in a processing statement, the system always uses the primary
> table key or primary table index."

You must name it — `USING KEY cities`, or `WITH TABLE KEY cities COMPONENTS ...`, or
`itab[ KEY cities cityfrom = ... ]`. A `READ TABLE it_flights WITH KEY cityfrom = 'X'`
next to that declaration is still a linear scan on a free key.

### Lazy update: non-unique secondary keys are not maintained continuously

- **Unique** secondary keys are updated **immediately** on every change — uniqueness
  has to be checked at insert time. Consistent cost per write, consistently fast reads.
- **Non-unique** secondary keys are updated **lazily** — the secondary index is only
  (re)built on the next access *through that key*.

The practical effect: filling a table with a non-unique sorted secondary key is fast
(no duplicate checking), but the **first** read through that key pays for building the
whole index. If you interleave writes and single keyed reads in a loop, you rebuild
the index over and over and the "optimization" is slower than the linear scan it
replaced. Secondary keys are for tables **filled once and read many times**.

### Two gotchas that bite during modification

1. **You cannot change a field that belongs to a key you are looping through.**
   `LOOP AT itab ASSIGNING <fs> USING KEY cities` write-protects `cityfrom`/`cityto`
   inside that loop — assigning to them dumps. Note the protection applies *only*
   inside `LOOP`/`MODIFY` statements that use the key; elsewhere the fields are
   writable, so this is not something the compiler catches globally.

2. **Read with one key, modify with the same key.** `DELETE TABLE itab FROM wa`
   deletes the line matching the **primary** key, regardless of which key the
   surrounding `LOOP` used. If `wa` came from a secondary-key loop, that is a
   different line, and you delete the wrong row with no error. Add `USING KEY` to
   the `DELETE` too.

```abap
" Collect first - deleting from a table inside a loop driven by the same
" key is asking for trouble; take the rows out, then modify.
DATA lt_doomed LIKE it_flights.
LOOP AT it_flights INTO DATA(ls) USING KEY cities WHERE cityfrom = 'FRANKFURT'.
  APPEND ls TO lt_doomed.
ENDLOOP.

LOOP AT lt_doomed INTO ls.
  DELETE TABLE it_flights FROM ls USING KEY cities.   "<- the USING KEY matters
ENDLOOP.
```

Both were documented the hard way in Matt Sale's write-up below, and the second one
is still the classic "my data went missing" bug with secondary keys.

## Cost, and when not to bother

Secondary keys cost memory and write-time maintenance. Hashed keys add hash
administration; each sorted key adds a full secondary index. They are not free
annotations — skip them on small tables and on tables you modify constantly. The
break-even is roughly "large, filled once, read by that key often".

Worked, runnable examples: [ydj_itab_keys_demo.abap](ydj_itab_keys_demo.abap)

---

**References**

- [SAP Help — Internal Tables: table keys](https://help.sap.com/docs/abap-cloud/abap-keyword/table-key)
- [SAP Help — Secondary table key](https://help.sap.com/docs/abap-cloud/abap-keyword/secondary-table-key)
- [ABAP keyword docs — Secondary Key Guideline](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/abensecondary_key_guidl.html)
- [SAP-samples/abap-cheat-sheets — 01_Internal_Tables.md](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/01_Internal_Tables.md)
- [SAP Community — First real use of secondary indexes on an internal table](https://community.sap.com/t5/application-development-and-automation-blog-posts/first-real-use-of-secondary-indexes-on-an-internal-table/ba-p/13080365)
