# CDS Associations | The Join Type Decided by Where You Use It, the Cardinality Nobody Enforces & Exposing vs Using

A CDS association looks like a named, reusable relationship. It is really a
*deferred join*, and almost everything about that join -- whether it is inner
or outer, whether the database is allowed to optimise it away, whether it is
generated at all, whether anyone outside the view can see it -- is decided
somewhere other than the `association` line you wrote.

The doc is blunt about the mechanism:

> *"As soon as an association is used in a path expression, for example, to
> specify a field from the association target in the element list of a view, it
> is internally transformed into a join. So technically, a CDS association is
> instantiated as join."*

Which means every join pitfall still applies -- you just no longer see the
`JOIN` keyword at the place where the row count changes.

---

## 1. The same association is an inner join here and an outer join there

There is no join type on an association definition. The type comes from
**where the path expression is used**:

| Where the path expression appears | Join generated |
|---|---|
| As the data source after `FROM` | `INNER JOIN` |
| As an element of the `SELECT` list | `LEFT OUTER JOIN` |
| In `WHERE` / `HAVING` / `WHEN` | `LEFT OUTER JOIN` |
| After `GROUP BY` | `LEFT OUTER JOIN` |
| As operand of an aggregate / built-in / `CASE` / `CAST` | `LEFT OUTER JOIN` |
| Bare `_assoc` in the element list (exposure only) | **none** |

So this refactoring -- pulling a repeated path expression up into the `FROM`
clause to "read better" -- is not behaviour-neutral:

```
// _spfli used in the element list -> LEFT OUTER JOIN
define view entity ydj_assoc_a
  as select from scarr
  association of one to many demo_cds_assoc_spfli as _spfli
    on scarr.carrid = _spfli.carrid
{
  key scarr.carrid,
      _spfli.connid          // <- left outer: carriers with no flights SURVIVE
}

// the same association as data source -> INNER JOIN
define view entity ydj_assoc_b
  as select from demo_cds_assoc_scarr._spfli
{
  key carrid,
      connid                 // <- inner: carriers with no flights are GONE
}
```

Carriers with no flights are in the first result and not in the second. No
warning, no annotation, nothing in the diff that says `INNER`.

Override it explicitly in the path expression attributes when it matters:

```
_spfli[inner].connid                 // CDS DDL
\_spfli[ INNER MANY TO ONE ]-connid  -- ABAP SQL
```

In ADT you can confirm what was actually generated: the DDL editor shows the
generated SQL DDL statement.

---

## 2. Cardinality is documentation the database is allowed to believe

`association [1..1]` / `association of many to one` is **not a constraint**.
Nothing checks it at runtime. What it does is hand the optimiser a promise:

> *"In these database systems, LEFT OUTER JOINs produced by a path expression
> are given the addition TO ONE if an explicit or implicit "to 1" cardinality
> is used and the addition TO MANY if any other cardinality is used. ... an
> optimization is attempted and **the result can be undefined if the results
> set does not match the cardinality**."*

Undefined results. Not an exception, not a dump -- the join is optimised on the
assumption you told the truth, and if you did not, the row count is whatever
falls out.

And the default is the dangerous one:

> *"If the cardinality is not defined explicitly, the cardinality "to 1" is
> used implicitly (`[min..1]`)."*

Omitting the cardinality on a genuinely to-many relationship therefore does not
mean "unspecified". It means **you asserted to-one**, and on HANA the
`LEFT OUTER JOIN ... TO ONE` optimisation is now live on a claim that is false.
This is the doc's own `DEMO_CDS_WRONG_CARDINALITY` example -- one carrier, many
flights, no explicit cardinality:

```
define view demo_cds_wrong_cardinality
  as select from scarr
     association to spfli as _spfli on _spfli.carrid = scarr.carrid
  { scarr.carrid, scarr.carrname, _spfli.connid }
```

> *"On optimizing database systems, such as the SAP HANA database, the two
> reads return a different number of rows, potentially an unexpected result."*

Two reads of the same view. Different row counts. The fix is one word of
honesty (`association [0..*]` / `association of one to many`), and the doc's
guidance is unambiguous: *"the cardinality should always be defined to match
the data in question."*

What you get for free is thin: *"A non-matching cardinality usually produces a
syntax check **warning**"* -- and only for paths, not for the definition.

---

## 3. The caller can overwrite the modeller's cardinality

This is the part that surprises people who assume the data model is the single
source of truth. In ABAP SQL:

> *"Specifying the cardinality overwrites the original definition of the
> cardinality ... of the current association with the new cardinality."*

```abap
SELECT scarr~carrname,
       \_spfli[ MANY TO ONE ]-connid AS connid   " <- caller's claim wins
       FROM demo_cds_assoc_scarr AS scarr
       INTO TABLE @FINAL(result).
```

A consumer who adds `MANY TO ONE` to silence a cardinality warning has not
fixed anything -- they have re-asserted the wrong promise at the call site,
where the modeller will never see it. Same trap through the numeric form:

> *"If the cardinality is specified as `(1)`, a LEFT OUTER JOIN is defined
> implicitly using the addition MANY TO ONE on database systems that support
> this."*

Two syntax orders, and they are not interchangeable:

```abap
\_assoc[ INNER MANY TO ONE ]-field AS alias   " worded: join type FIRST
\_assoc[ (1) INNER ]-field AS alias           " numeric: join type AFTER
```

Both forms tighten the syntax check: specifying a cardinality puts the
statement in **strict mode from release 7.58**, and specifying a join type or a
filter does so **from 7.52**. So adding an attribute to an old statement can
surface errors in code that has compiled for years.

---

## 4. Using an association and exposing it are different things

They look almost identical in the element list, and they do opposite things:

```
{
  key so_item_key,
      parent_key,
      material,
      _SalesOrder,                 // EXPOSED: no join, reusable outside
      _ScheduleLine,               // EXPOSED: no join, reusable outside
      _Material.material as mat    // USED:    join generated, NOT reusable
}
```

- **Bare `_assoc`** -- exposed. *"no join is generated and ... the association
  is not mentioned in the statement that is passed to the database."* It costs
  nothing at runtime and it is the only thing that makes the association
  reachable from another CDS entity or from ABAP SQL.
- **`_assoc.field`** -- used. A join *is* generated, and because the
  association was not exposed, *"it cannot be used in other CDS view entities
  or in ABAP SQL."*

Two consequences worth internalising:

1. An association that is not exposed is **invisible to ABAP SQL entirely**. A
   path expression in a `SELECT` needs a root that the entity actually exposes.
2. Exposure imposes a rule on your `ON` condition: the association source
   fields used in it *"must also be listed in the SELECT list"*, so the join
   can be built by whoever consumes it. Removing a field from the element list
   for tidiness can break an association you never touched.

And the join lands where the association was *used*, not where it was defined:

> *"Note that this happens in the view that uses the association, and not in
> the view that defines the association."*

> *"their left side is always the CDS entity that exposes the CDS
> association."*

---

## 5. `$projection` is the element list, not the data source

In an `ON` condition you can prefix the source side with either the data source
name or `$projection`:

```
association of many to one YDJ_MAT as _Material
  on $projection.material_id = _Material.material   // element list, ALIAS names
```

`$projection` resolves against the **`SELECT` list**, which means *"an
alternative element name defined using `AS` can be specified instead of the
field name."* So renaming an element for readability silently retargets every
`$projection.` reference to it -- a rename in the projection is a change to the
join condition.

One restriction follows from the same mechanism: if the `ON` condition uses
`$projection` to reach a *path expression* in the `SELECT` list, then that
association *"cannot itself be used in the SELECT list, to avoid invalid join
expressions."*

---

## 6. `WHERE` needs a unique path, and `1:` only silences the check

Filtering through an association is the most restricted use:

> *"When a CDS association is used in a WHERE condition, `1` must be specified
> for max."*

For a non-aggregated element among aggregates, and in `WHERE` / `HAVING`, the
path must be unique -- every association to-one, or filters declared unique
with the `1:` attribute. That attribute is a *promise*, not a check:

> *"The addition `1:` prevents a syntax error, if a path specified with filter
> conditions or with a quantity value cardinality is used in a WHERE clause or
> HAVING clause. It is not possible at runtime, however, to check whether the
> required uniqueness is achieved by the condition."*

So `1:` on a filter that does not actually reduce the path to one row buys a
clean activation and a duplicated-row result set. Neither `1:` nor `*:` may be
the only thing in the brackets.

---

## 7. A filter is part of the join, so two filters are two joins

A filter condition *"is converted to an extended condition for the join"*.
Different filters on the same association therefore produce **different joins**:

```
_demo_join2[ inner where d = '1' ].d,
_demo_join2[ inner where d = '1' ].e,          // same filter -> same join
_demo_join2[ inner where d = '2' ].e           // different filter -> ANOTHER join
```

For **CDS view entities** the merge is automatic: *"CDS associations with
semantically identical filter conditions are automatically summarized into one
single join expression."* For the older **DDIC-based views** it is the
`@AbapCatalog.compiler.compareFilter` annotation that decides, and the doc warns
plainly: *"The results sets of the two configurations can, however, differ."* --
which is why a migrated view can change its numbers.

Two syntax rules that catch people:

- Columns in a filter *"always refer to the target"* of that association, and
  *"An explicit name must not and cannot be specified with the column selector
  `~`"*.
- `WHERE` inside the brackets is optional only when the filter is the sole
  attribute; with a join type or cardinality present it is mandatory.

`WITH DEFAULT FILTER` on the definition supplies the filter when the path does
not -- and a filter in the path **replaces** it rather than adding to it.

---

## 8. Two spellings of the same model: `.` in CDS, `\` and `-` in ABAP SQL

The same association graph is written differently depending on which language
you are in, which is a steady source of syntax errors:

| | CDS DDL | ABAP SQL |
|---|---|---|
| Separator between associations | `.` (period) | `\` (backslash) |
| Reaching a field of the target | `_a._b.field` | `\_a\_b-field` |
| Source prefix | `source._assoc` | `source~\_assoc` |
| Attributes | `[inner where d = '1']` | `[ INNER MANY TO ONE WHERE d = '1' ]` |

```abap
SELECT carrid, connid, fldate, price
       FROM demo_cds_assoc_scarr
            \_spfli[   airpfrom = 'FRA' ]
            \_sflight[ currency  = 'EUR' AND
                       price  BETWEEN 500 AND 1500 ]
            AS flights
       ORDER BY carrid, connid, fldate, price
       INTO TABLE @FINAL(result).
```

Line breaks are allowed only *"In front of a backslash (`\`), but not in the
SELECT list"*, in blanks inside parameter parentheses, and in blanks inside the
attribute brackets.

---

## 9. The ABAP SQL restrictions that only bite at the call site

A model that activates cleanly can still be unusable from ABAP. These are hard
restrictions on path expressions in ABAP SQL:

- **No `FOR ALL ENTRIES`**, and no `WITH PRIVILEGED ACCESS`.
- **Not in the `ON` condition of a join.**
- With `CORRESPONDING` or an inline `@DATA(...)` / `@FINAL(...)` in `INTO`, a
  path-expression column **must** have an `AS alias` -- there is no derivable
  name for it.
- A path expression as a `FROM` data source *"can be used in the SELECT
  statement only by using an alias name `tabalias` defined using `AS` in front
  of the column selector `~`"*.
- If an association in the `FROM` clause has a cardinality greater than to-one,
  *"the identical path expression must also be specified in the SELECT list."*
- No association whose `ON` condition touches the **client column** of source or
  target -- *"This cannot be bypassed using the obsolete addition CLIENT
  SPECIFIED either"*, and `USING CLIENT` is out too. (See
  [CDS View Entities | Client Handling](../CDS%20Client%20Handling#readme).)
- Association targets cannot be DDIC tables or views **with replacement
  objects**.
- Static `AS tabalias` with a dynamic `FROM` excludes path expressions.

The documented escape hatch is worth remembering, because it is a design move
rather than a workaround:

> *"If CDS association reads are required that are possible in ABAP CDS but not
> in ABAP SQL, they can be moved to a CDS view entity."*

---

## 10. Dead ends in a path: DDIC targets, self associations, non-SQL entities

- An association whose target is a **DDIC database table or view exposes
  nothing**, so *"no further CDS associations can be specified in a path
  expression"* after it. Paths only keep going through CDS entities that expose
  the next hop -- which is why a model that stops at a table forces the next
  view to define its own association instead of extending yours.
- A **self association** (target = source) *"cannot be created as a join in the
  CDS view entity where it is defined"*, so it may be exposed but not used in
  any position that generates a join. Exposed self associations are what CDS
  hierarchies and the ABAP SQL `HIERARCHY` generator consume.
- Targets that are **abstract or custom entities** cannot be used anywhere a
  join would be instantiated. A **CDS projection view** target is stricter
  still: not usable in path expressions at all, and you cannot pull a field
  from it into the element list.
- **Cyclical dependencies** should be avoided -- they cause trouble in mass
  activation, not at read time.

---

## 11. `composition` and `association to parent` are not just tidier names

A composition is the modelling of an **existential dependency** -- a sales
order item cannot exist without its header -- and it comes as a pair: a
to-child `composition of ...` on the parent and an `association to parent` on
the child.

```
define view entity DEMO_SALES_CDS_SO_I_VE
  as select from demo_sales_so_i
  association        to parent DEMO_SALES_CDS_SO_VE  as _SalesOrder
    on $projection.parent_key = _SalesOrder.so_key
  composition of exact one to many DEMO_SALES_CDS_SO_I_SL_VE as _ScheduleLine
  association of many to one DEMO_SALES_CDS_MATERIAL_VE as _Material
    on $projection.material = _Material.material
{ ... }
```

Structurally they behave like associations (they generate the same joins, and a
path *"may consist of a mixture of to-child associations, to-parent
associations, and regular CDS associations"*). The difference is semantic, and
RAP reads it: the composition tree is what defines a business object's lock
scope, authorisation inheritance and lifecycle. Using a plain `association`
where the relationship is genuinely existential does not break the `SELECT` --
it breaks the behaviour definition built on top of it later.

---

## Summary

| Question | Answer |
|---|---|
| What join type will my association become? | Depends on **where** the path is used. `FROM` -> inner, everything else -> left outer, bare exposure -> no join. |
| I omitted the cardinality. What did I get? | **To-one.** Implicitly `[min..1]`, and HANA may optimise on that promise. |
| Is cardinality enforced? | No. Wrong cardinality -> *undefined* result, at most a syntax **warning**. |
| Can a consumer change it? | Yes -- ABAP SQL attributes **overwrite** the definition. |
| Why can nobody use my association? | It is *used*, not *exposed*. Only bare `_assoc` in the element list exposes it. |
| Why did removing an element break an association? | Exposure requires the `ON` condition's source fields to be in the `SELECT` list. |
| `$projection.x` -- which `x`? | The element list's, alias names included. Renaming an element changes the `ON` condition. |
| Why won't my association work in `WHERE`? | `max` must be `1`; `1:` silences the check without guaranteeing anything. |
| Same association twice, two joins? | Different filters -> different joins. View entities merge identical ones automatically; DDIC-based views need `compareFilter`. |
| Works in CDS but not in ABAP SQL? | Expected. `FOR ALL ENTRIES`, `ON` conditions, client columns, missing aliases. Push the read into a view entity. |

Runnable companion: [`ydj_cds_association_demo.abap`](ydj_cds_association_demo.abap)
-- read-only, standard flight tables, no DDIC objects to create.

## Sources

- [CDS DDL - CDS View Entity, SELECT, Associations](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abencds_association_v2.htm)
- [CDS DDL - CDS View Entity, Associations and Joins](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abencds_assoc_join_v2.htm)
- [CDS DDL - CDS View Entity, ASSOCIATION](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abencds_simple_association_v2.htm)
- [CDS DDL - CDS View Entity, path_expr](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abencds_path_expression_v2.htm)
- [ABAP SQL - SQL Path Expressions sql_path](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abenabap_sql_path.htm)
- [ABAP SQL - Path Expressions, attributes](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abenabap_sql_path_filter.htm)
- [ABAP SQL - Restrictions for Path Expressions](https://help.sap.com/doc/abapdocu_758_index_htm/7.58/en-US/abenabap_sql_path_restrictions.htm)
- [ABAP CDS - SELECT, ASSOCIATION (cardinality, DEFAULT FILTER)](https://help.sap.com/doc/abapdocu_751_index_htm/7.51/en-US/abencds_f1_association.htm)
- [ABAP CDS - path_expr, attributes (`1:`, `compareFilter`)](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-US/abencds_path_expression_attr.htm)

Related notes in this repo:
[CDS View Entities | Client Handling](../CDS%20Client%20Handling#readme) |
[For All Entries](../For%20All%20Entries#readme) |
[Table Buffering](../Table%20Buffering#readme) |
[Null Values](../Null%20Values#readme) |
[Window Expressions](../Window%20Expressions#readme) |
[Dynamic SQL](../Dynamic%20SQL#readme)
