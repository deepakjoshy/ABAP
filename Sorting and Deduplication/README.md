# Sorting & Deduplication — Unstable SORT, the `sy-subrc = 4` That Means Nothing, and Why `ADJACENT` Is Load-Bearing

`SORT itab.` and `DELETE ADJACENT DUPLICATES FROM itab.` are the two statements
every ABAP developer writes in their first week and then stops thinking about.
Both are documented to behave in ways the surrounding code almost never accounts
for, and every one of the failures below is silent — no syntax error, no warning,
no dump, just a wrong result set.

This note is about the *statements*. The key definitions they depend on
(`DEFAULT KEY`, `EMPTY KEY`, secondary keys) are covered separately in
[Internal Table Keys](../Internal%20Table%20Keys#readme).

## Trap 1: `SORT` is unstable by default, and unstable means non-deterministic

> "Sorting is unstable by default, which means that the relative order of lines
> that do not differ in sort keys is not preserved when they are sorted. The order
> can be different depending on the platform or when sorted multiple times."
> — [ABAP keyword documentation, SORT itab](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapsort_itab.htm)

Read the second sentence again: **multiple sorting of a table using the same sort
key can produce a different order each time.** This is not merely "the order is
undefined but consistent". Sorting the same table twice by the same key is allowed
to give two different answers, and the same code is allowed to give different
answers on a different application server.

Where this actually bites is the two-stage sort, which looks completely reasonable:

```abap
SORT lt_items BY posnr.          " first, order within the document
SORT lt_items BY vbeln.          " then, group by document
```

The intent is "ordered by document, and by item within document". The second
`SORT` is entitled to discard the ordering the first one established, because rows
that tie on `vbeln` have no defined relative order. The fix is one statement, not
two:

```abap
SORT lt_items BY vbeln posnr.    " state the full key
```

and where the secondary criterion genuinely cannot be expressed as a key (it came
from the database's `ORDER BY`, or from the sequence rows were appended in), the
addition exists for exactly that:

```abap
SORT lt_items STABLE BY vbeln.   " ties keep their current relative order
```

`STABLE` costs more than an unstable sort. Pay it when you are relying on the
previous order, and only then.

## Trap 2: the `sy-subrc` of `DELETE ADJACENT DUPLICATES` is not a success check

`DELETE` sets `sy-subrc = 4` when "no duplicate adjacent lines were found"
([DELETE itab](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapdelete_itab.htm)).

A clean table with no duplicates is the *expected* case, and it returns 4. So
this — a real pattern, written by people being diligent — is wrong:

```abap
DELETE ADJACENT DUPLICATES FROM lt_keys.
IF sy-subrc <> 0.
  MESSAGE e001(zz) WITH 'Deduplication failed'.   " fires on clean data
ENDIF.
```

There is no error condition to check for here. `4` means "nothing needed deleting",
which is good news. Note also that `sy-tabix` is **not set** by `DELETE`, so
reading it afterwards gives you the value from some earlier statement — the same
stale-system-field shape as the `sy-subrc` trap in
[Update Task](../Update%20Task#readme).

## Trap 3: `ADJACENT` is the whole contract

The statement removes duplicates **from groups of consecutive lines**. It has no
concept of a duplicate that is three rows away. An unsorted table is deduplicated
only by coincidence:

| `carrid` | after `DELETE ADJACENT DUPLICATES ... COMPARING carrid` |
|---|---|
| `LH` | kept (first of its run) |
| `UA` | kept |
| `LH` | **kept** — not adjacent to the first `LH` |

The docs state the prerequisite as a hint rather than a rule — "the use of
`ADJACENT DUPLICATES` usually requires a suitable sorting by the components
compared in the statement" — and nothing enforces it. The sort key must cover the
`COMPARING` components, or the result is a partially-deduplicated table that will
pass a small test and fail on production volumes.

This is also why refactoring is dangerous: deleting or reordering a `SORT` several
hundred lines earlier silently changes what a `DELETE ADJACENT DUPLICATES` does.
Keep them together, or comment the dependency.

## Trap 4: no `COMPARING` means the primary key — which may be everything, or nothing

Without `COMPARING`, groups are formed from the key fields of the table key used,
defaulting to the primary table key. Two documented consequences, both from the
standard key:

- **For a structured line type the standard key is every character-like and
  byte-like component.** So `DELETE ADJACENT DUPLICATES FROM lt_flights.` on a
  `DEFAULT KEY` table compares far more columns than intended and deletes almost
  nothing. Adding a character field to the structure changes the result.
- **The standard key of a standard table can be empty**, and then: "If the primary
  table key is used to access a standard table and the key is empty, no lines are
  deleted." A `WITH EMPTY KEY` table — which is what every `SELECT ... INTO TABLE
  @DATA(lt_x)` produces — deduplicates to **nothing at all**.

The same rule governs `SORT` without `BY`: an empty primary key means no sort
takes place. In both cases the syntax check issues a warning *only* if the
emptiness is known statically.

Always name what you mean:

```abap
SORT lt_flights BY carrid connid.
DELETE ADJACENT DUPLICATES FROM lt_flights COMPARING carrid connid.
```

`COMPARING ALL FIELDS` is the explicit "whole row" form (and `COMPARING
table_line` is documented as having the same effect).

## Trap 5: `SORT` on a sorted table is either ignored or an uncatchable dump

Applying `SORT` to a `SORTED TABLE` is forbidden by the syntax check. When the
table category is only known at runtime — a generic `TYPE ANY TABLE` parameter, a
field symbol — the statement instead raises an **uncatchable** exception, but only
in the cases that would modify the existing order:

- `BY` specifies a key that is not an initial part of the table key
  (`SORT_SORT_ILL_KEY_ORDER`)
- `DESCENDING`, or `AS TEXT`, is used (`SORT_SORT_ILLEGAL`)
- a component specified after `BY` is an attribute of an object

Otherwise `SORT` is silently **ignored** for sorted tables. So the same generic
utility method either works, does nothing, or dumps uncatchably, depending on what
the caller passed in. Uncatchable means no `TRY`/`CATCH` will save you — see
[Exception Flow](../Exception%20Flow#readme).

## Trap 6: `AS TEXT` — the sort order depends on the operating system

Without `AS TEXT`, character-like components sort by their **binary representation
in the current code page**. The docs are explicit that this "depends on the
operating system of the host computer of the current AS instance", and that "the
order of uppercase and lowercase letters is specific to the operating system".

The classic symptom is a report whose alphabetical list is right in development
and subtly wrong in production, or a list where `Möller` sorts after `Muller`. The
documentation's own example:

- `SORT text_tab.` → `Miller, Moller, Muller, Möller`
- `SORT text_tab AS TEXT.` → `Miller, Moller, Möller, Muller`

`AS TEXT` sorts according to the locale of the current text environment, which is
what a human expects. It is also considerably slower, so it is worth skipping only
when the data is known to be ASCII and single-case. It can be set per component
after `BY`, and specifying it for a non-text-like component specified dynamically
is an uncatchable `SORT_AS_TEXT_BAD_DYN_TYPE`.

## Trap 7: dynamic sorting — the initial table that sorts nothing

Two silent no-ops in the dynamic forms:

- `SORT itab BY (otab).` — "If the table `otab` is initial, the table is not
  sorted." No exception, no `sy-subrc`. Same failure shape as the empty-range and
  empty-driver-table traps in [Selection Tables](../Selection%20Tables#readme)
  and [For All Entries](../For%20All%20Entries#readme).
- `SORT itab BY (name1) (name2).` — if all the name variables contain only
  blanks, no sort takes place.

`BY (otab)` expects `ABAP_SORTORDER_TAB`, whose rows carry `NAME`, `DESCENDING`
and `ASTEXT`. Invalid content — a component that does not exist, a bad
offset/length, or a `DESCENDING`/`ASTEXT` value that is neither `X` nor initial —
raises `CX_SY_DYN_TABLE_ILL_COMP_VAL`, which *is* catchable. That is the reason to
prefer the table form over individually-parenthesised component names: the docs
note the advantage plainly, "using a table like this has the advantage that any
exceptions are catchable", and the number of key components becomes dynamic too.

Note that `BY (otab)` cannot be combined with `BY comp1 comp2`, and that a global
`DESCENDING` or `AS TEXT` cannot be used alongside it — the direction lives in the
table rows instead.

## Smaller things worth knowing

- **Secondary keys cannot be used as sort keys.** `SORT` also does not affect the
  assignment of lines to a secondary table index. But `DELETE ADJACENT DUPLICATES
  ... USING KEY` *does* accept a secondary key, and then the grouping order comes
  from that key's index rather than from the primary index — a `SORT` you did
  beforehand becomes irrelevant. The docs call this out for secondary hash keys
  specifically: "a preceding sort using the statement `SORT` does not affect the
  processing order".
- **Hashed tables can be sorted.** `SORT` modifies their internal order and
  therefore the order a subsequent `LOOP` without `USING KEY` runs in.
- **`DELETE` does not release memory.** "Deleting lines of internal tables using
  `DELETE` does not usually release any memory"; the table is `IS INITIAL` after
  everything is deleted but still occupies its allocation. Use `FREE itab` when
  the point was to reclaim memory.
- **Sorting by a reference column** is legal but questionable, and a non-initial
  *invalid* reference involved in a sort is a runtime error.
- **`SORT` inside a `LOOP` over the same table** is a common cause of skipped or
  repeated rows, since the index positions the loop is walking change underneath
  it. `AT NEW` forbids modification outright — see
  [Control Level Processing](../Control%20Level%20Processing#readme).

## The safe pattern

```abap
" Sort key covers the COMPARING components, both stated explicitly,
" and the two statements sit next to each other so the dependency is visible.
SORT lt_items BY vbeln posnr.
DELETE ADJACENT DUPLICATES FROM lt_items COMPARING vbeln posnr.
```

Since 7.40 the deduplicating job can often be done in the expression that builds
the table instead, via `CORRESPONDING ... DISCARDING DUPLICATES` — see
[CORRESPONDING Operator](../Corresponding%20Operator#readme) — or avoided entirely
by selecting into a table with a `UNIQUE` key.

Worked, runnable examples: [ydj_sort_dedup_demo.abap](ydj_sort_dedup_demo.abap)

---

**References**

- [ABAP keyword docs — SORT itab](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapsort_itab.htm)
- [ABAP keyword docs — DELETE itab, duplicates](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapdelete_duplicates.htm)
- [ABAP keyword docs — DELETE itab (sy-subrc table)](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abapdelete_itab.htm)
