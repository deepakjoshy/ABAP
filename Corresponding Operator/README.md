# CORRESPONDING vs MOVE-CORRESPONDING — what the new syntax quietly changes

`CORRESPONDING #( )` reads like a modern spelling of `MOVE-CORRESPONDING`. It is not.
The old statement *modifies* the target in place; the constructor expression *builds a
new value* and assigns it. Every difference below follows from that one sentence, and
all of them lose data silently — no syntax error, no dump, just fields that are
suddenly initial or rows that are suddenly gone.

## 1. Unmatched target components are wiped

```abap
" ls_tgt has STATUS. ls_src does not.
MOVE-CORRESPONDING ls_src TO ls_tgt.      " STATUS keeps its value
ls_tgt = CORRESPONDING #( ls_src ).       " STATUS is now INITIAL
```

> "In `MOVE-CORRESPONDING`, all not identically named components in `struct2` keep
> their value. When the result of the constructor expression is assigned, however,
> they are assigned the value from there, which is initial for ignored components."
> — [ABAP keyword docs, CORRESPONDING basic form](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCORRESPONDING_CONSTR_ARG_TYPE.html)

`BASE ( )` seeds the result with the current target and restores the old semantics:

```abap
ls_tgt = CORRESPONDING #( BASE ( ls_tgt ) ls_src ).
```

This is the one to reach for when you are refactoring an existing
`MOVE-CORRESPONDING` into expression form. Dropping the `BASE ( )` is the single most
common way this refactor introduces a bug.

## 2. For internal tables the default is the other way round

The asymmetry catches people who learned rule 1 and assumed it generalises:

| | Target table |
|---|---|
| `MOVE-CORRESPONDING itab1 TO itab2.` | **deleted first**, then refilled |
| `... KEEPING TARGET LINES.` | appended |
| `itab2 = CORRESPONDING #( itab1 ).` | replaced (new table) |
| `itab2 = CORRESPONDING #( BASE ( itab2 ) itab1 ).` | **appended** |

So `MOVE-CORRESPONDING` for tables is destructive by default, and the `BASE ( )` form
is *defined* as `MOVE-CORRESPONDING ... KEEPING TARGET LINES` — it appends, it does not
merge or overwrite by key. Calling it twice gives you every row twice.

## 3. Nested tables are replaced unless you say `DEEP`

Without `DEEP`, a tabular component is treated as one value and assigned whole, so a
nested target table is overwritten by the source's nested table:

```abap
ls_tgt = CORRESPONDING #( BASE ( ls_tgt ) ls_src ).              " nested ITEMS replaced
ls_tgt = CORRESPONDING #( DEEP APPENDING ( ls_tgt ) ls_src ).    " nested ITEMS merged
```

`DEEP` is the expression equivalent of `EXPANDING NESTED TABLES`. Two details worth
knowing:

- **A mapping rule sets `DEEP` implicitly** — with `MAPPING ...` you cannot write
  `DEEP` explicitly, and you get deep behaviour whether you wanted it or not.
- **`KEEPING TARGET LINES` never reaches nested tables.** Per the docs it "is only
  effective on the lines of `itab2` … because nested tables are always resolved in new
  initial lines." For nested merging you need `DEEP APPENDING ( )`.

## 4. A unique target key turns duplicates into a dump

Assigning into a table with a unique primary or secondary key raises
`CX_SY_ITAB_DUPLICATE_KEY` on the first collision. `DISCARDING DUPLICATES` suppresses
it:

```abap
lt_unique = CORRESPONDING #( lt_src DISCARDING DUPLICATES ).
```

Understand what you bought: the **first** line per key wins and the rest are dropped
without a trace. That is correct when the duplicates are genuinely redundant, and a
data-loss bug when they should have been summed. It also applies to the lines already
present via `BASE ( )`.

## The `FROM ... USING` lookup variant

The part of `CORRESPONDING` that has no `MOVE-CORRESPONDING` equivalent at all, and
the reason to learn the operator rather than avoid it. It replaces the standard
"enrich a table from a second table" loop:

```abap
" Before
LOOP AT lt_items ASSIGNING FIELD-SYMBOL(<item>).
  READ TABLE lt_prices INTO DATA(ls_price)
       WITH TABLE KEY material = <item>-material.
  IF sy-subrc = 0.
    <item>-price = ls_price-price.
  ENDIF.
ENDLOOP.

" After
lt_items = CORRESPONDING #( lt_items FROM lt_prices USING material = material ).
```

Rules that are easy to get wrong:

- **Left of the `=` is a column of `itab`, right of it a column of `lookup_tab`.**
  The reverse of what the `MAPPING` addition does, in the same operator.
- **The lookup table must be sorted or hashed**, or you must name a secondary key with
  `USING KEY`. The comparison fields have to cover that key completely. There is no
  linear-scan fallback — it is a syntax error, not a slow path.
- **Non-matching rows survive unchanged.** This is a left outer join: rows of `itab`
  with no partner in `lookup_tab` stay in the result with their existing values, they
  are not dropped.
- **The search fields are excluded from the assignment by default**, so the key column
  is not copied back over itself. List it explicitly in `MAPPING` if you do want it.
- **Assign the result back to the same table you passed in.** The docs say that case is
  optimised to work directly on `itab`; any other target forces a full temporary copy
  and a syntax warning. Passing the same table as both `itab` and `lookup_tab` when
  that is only known at runtime gives the runtime error `CORRESPONDING_SELF`.
- `DEEP` always applies here and `BASE` is not allowed.

## Quick decision table

| You want | Write |
|---|---|
| Keep unmatched target fields (structure) | `CORRESPONDING #( BASE ( tgt ) src )` |
| Replace target entirely | `CORRESPONDING #( src )` |
| Append rows to an existing table | `CORRESPONDING #( BASE ( tgt ) src )` |
| Merge nested tables instead of replacing | `CORRESPONDING #( DEEP APPENDING ( tgt ) src )` |
| Rename fields between the two | `CORRESPONDING #( src MAPPING t1 = s1 )` |
| Fall back to a value when the source is initial | `MAPPING t1 = s1 DEFAULT expr` |
| Blank a field that would otherwise be copied | `... EXCEPT t1` (or `EXCEPT *`) |
| Enrich from a second table | `CORRESPONDING #( itab FROM lookup USING k = k )` |
| Build the mapping rule at runtime | `CL_ABAP_CORRESPONDING` |

Worked, runnable examples: [ydj_corresponding_demo.abap](ydj_corresponding_demo.abap)

---

**References**

- [ABAP keyword docs — `MOVE-CORRESPONDING`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMOVE-CORRESPONDING.html)
- [ABAP keyword docs — `CORRESPONDING`, component operator](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONSTRUCTOR_EXPR_CORRESPONDING.html)
- [ABAP keyword docs — basic form (`EXACT`, `DEEP`, `BASE`, `APPENDING`)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCORRESPONDING_CONSTR_ARG_TYPE.html)
- [ABAP keyword docs — mapping rule (`MAPPING`, `DEFAULT`, `EXCEPT`)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCORRESPONDING_CONSTR_MAPPING.html)
- [ABAP keyword docs — lookup table variant (`FROM ... USING`)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCORRESPONDING_CONSTR_USING.html)
- [ABAP keyword docs — `DISCARDING DUPLICATES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCORRESPONDING_CONSTR_DUPL.html)
- [SAP-samples/abap-cheat-sheets — 05_Constructor_Expressions.md](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/05_Constructor_Expressions.md)
