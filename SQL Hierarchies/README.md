# ABAP SQL Hierarchies — the `SELECT *` that returns no hierarchy, the three clauses CDS forbids and ABAP SQL demands, and the `WHERE` that does not limit the sum

Hierarchical data is a parent-child table: cost centres under cost centres, BOM
positions under assemblies, managers under managers. Classically you read it into an
internal table and walked it yourself. The documentation is blunt about that era:

> "In former times you had to load the data from the database into internal tables and
> program it all by yourself (if you did not find an appropriate API)."

ABAP SQL now has a `FROM` clause that understands trees. An **SQL hierarchy** is

> "A tabular SQL data source in ABAP SQL whose rows contain the content of the
> hierarchy nodes of a parent-child hierarchy."

and it comes in three flavours — a **CDS hierarchy** (`DEFINE HIERARCHY`, a reusable
CDS entity), the **hierarchy generator** (`HIERARCHY( ... )`, written inline in the
`FROM` clause), and a **CTE hierarchy** (`WITH ... WITH HIERARCHY`). The repo's
[Common Table Expressions](../Common%20Table%20Expressions#readme) note points here:
a CTE cannot recurse, and this is what ABAP SQL offers instead.

This note is about the parts that do not behave the way the surrounding SQL does.

- **`SELECT *` returns none of the hierarchy columns** — no rank, no level, no
  orphan flag — while those same columns still work in `WHERE` and `ORDER BY`, so the
  statement filters on data it refuses to show you;
- **the three defaults fail in two different directions**: multiple parents and cycles
  raise exceptions, orphans are *discarded silently*, and the obvious fix for the first
  two quietly invalidates the tree arithmetic;
- **`GENERATE SPANTREE` requires three clauses in ABAP SQL and forbids the same three
  in CDS** — the documented syntax of the two dialects is in direct opposition;
- **`START WHERE` is mandatory in ABAP SQL** but can be left out in CDS — and only
  when the parent column is numeric, never for a UUID key;
- **the aggregate navigator's `WHERE` does not restrict what is aggregated**, only
  which rows you get back;
- **sibling order is undefined** unless you ask for it, and so is
  `HIERARCHY_SIBLING_DISTANCE`;
- `DEPTH` with a negative value is **`sy-subrc = 4`**, not an error.

```abap
" The generator form: a tree, inline, with the two options you almost always want.
SELECT FROM HIERARCHY( SOURCE ydj_i_cost_centre_src
                       CHILD TO PARENT ASSOCIATION _parent
                       START WHERE parent_cc = ' '
                       SIBLINGS ORDER BY cost_centre )
       FIELDS cost_centre,
              parent_cc,
              hierarchy_level,          " 1 for roots, not 0
              hierarchy_parent_rank,    " 0 for roots
              hierarchy_tree_size       " this node + all descendants
       INTO TABLE @DATA(lt_tree).
```

## What you have to build first

A hierarchy cannot be generated from a bare database table. It needs a **hierarchy
source**: a data source that exposes a **self-association** describing the
parent-child relationship. For a CDS hierarchy the source

> "cannot be anything else but a CDS view that exposes a hierarchy association"

The association rules are narrow, and all of them are syntax errors rather than
surprises:

- "The association must be a self-association."
- "Only equality comparisons with the operator `=` and combined using `AND` can occur
  in the `ON` condition of the association."
- "In each comparison in the `ON` condition, one field of the association source must
  be compared with a field, which is prefixed with `_hierarchy_assoc`, of the
  association target."

So `ON ... parent >= _assoc.id` or an `OR` anywhere in the `ON` condition is not a
hierarchy association, no matter how sensible the relationship is.

```asddls
// The hierarchy source. The self-association IS the parent-child relation.
@AccessControl.authorizationCheck: #NOT_REQUIRED
define view entity YDJ_I_COST_CENTRE_SRC
  as select from ydj_cost_centre
  association to exact one YDJ_I_COST_CENTRE_SRC as _parent
    on $projection.parent_cc = _parent.cost_centre
{
      _parent,              -- must be exposed in the SELECT list
  key cost_centre,
      parent_cc,
      cc_name,
      plan_amount
}
```

```asddls
// Optional: the same thing as a reusable CDS entity instead of inline SQL.
define hierarchy YDJ_H_COST_CENTRE
  with parameters
    p_root : abap.char10
  as parent child hierarchy(
    source
      YDJ_I_COST_CENTRE_SRC
      child to parent association _parent
      start where
        cost_centre = :p_root
      siblings order by
        cost_centre ascending
    )
    {
      cost_centre,
      parent_cc,
      cc_name,
      plan_amount
    }
```

Both are then a data source: `SELECT FROM ydj_h_cost_centre( p_root = @lv_root )`.
The keyword documentation states they are interchangeable —

> "This variant of the hierarchy generator `HIERARCHY` in ABAP SQL works in the same
> way as the statement `DEFINE HIERARCHY` in ABAP CDS. Accessing the hierarchy
> generator `HIERARCHY` as the data source of a query is the same as accessing a CDS
> hierarchy defined accordingly."

Traps 3, 4 and 5 below are the places where that sentence stops being true.

## Trap 1: `SELECT *` returns no hierarchy columns at all

Every hierarchy adds columns that are not in the underlying table —
`HIERARCHY_RANK`, `HIERARCHY_LEVEL`, `HIERARCHY_PARENT_RANK`, `HIERARCHY_TREE_SIZE`,
`HIERARCHY_IS_CYCLE`, `HIERARCHY_IS_ORPHAN`, `NODE_ID`, `PARENT_ID`. They are the
entire reason to use a hierarchy. And the one spelling that reads everything reads
none of them:

> "If `*` or `...~*` is specified, hierarchy columns are not part of the result set of
> the query. Only the components of the source of the SQL hierarchy are respected. In
> this case, the hierarchy columns are also ignored by any structure or internal table
> created in the `INTO` clause by an inline declaration `@DATA|@FINAL(...)`."

> "The hierarchy columns must be specified explicitly in the `SELECT` list before they
> can be selected."

There is no warning. `SELECT * FROM HIERARCHY( ... ) INTO TABLE @DATA(lt)` compiles,
runs, and hands back exactly the rows of the source table — in hierarchy order, with
every structural fact stripped off, and an inline-declared table that has nowhere to
put them even if you wanted them.

The half that makes this hard to spot: the columns are perfectly usable *elsewhere* in
the same statement.

> "In other clauses, hierarchy columns can be specified regardless of the `SELECT`
> list and are evaluated accordingly."

```abap
" Compiles. Filters correctly on a column it will not return.
SELECT * FROM HIERARCHY( SOURCE ydj_i_cost_centre_src
                         CHILD TO PARENT ASSOCIATION _parent
                         START WHERE parent_cc = ' ' )
       WHERE hierarchy_level <= 2
       ORDER BY hierarchy_rank
       INTO TABLE @DATA(lt_two_levels).   " no hierarchy_level in here

" Works. Name every hierarchy column you intend to read.
SELECT FROM HIERARCHY( SOURCE ydj_i_cost_centre_src
                       CHILD TO PARENT ASSOCIATION _parent
                       START WHERE parent_cc = ' ' )
       FIELDS cost_centre, parent_cc, cc_name, hierarchy_level
       WHERE hierarchy_level <= 2
       ORDER BY hierarchy_rank
       INTO TABLE @DATA(lt_ok).
```

The exception, which cuts the other way, is the aggregate navigator's `MEASURES`
columns — see trap 8. Those are *not* hierarchy columns, so:

> "If `*` or `...~*` is specified in the `SELECT` list, they are read like a column of
> the SQL hierarchy specified as a source and are part of a structure or internal
> table created using an inline declaration `@DATA|@FINAL(...)`."

In one `SELECT agg~*`, therefore, your computed sums come back and `hierarchy_rank`
does not.

## Trap 2: two defaults raise exceptions, one deletes your data quietly

Three clauses govern what happens when the data is not a clean tree. Their defaults
are not consistent with each other.

| Clause | Default | Behaviour on bad data |
|---|---|---|
| `MULTIPLE PARENTS` | `NOT ALLOWED` | **exception** |
| `CYCLES` | `ERROR` | **exception** |
| `ORPHANS` | `IGNORE` | **silently dropped** |

For multiple parents the documentation says "This is the default setting. A child node
can have exactly on parent node only)." (SAP's typo, quoted as printed) — and SAP's
own demo spells out the consequence: "The first `SELECT` statement does not specify the
addition and `NOT ALLOWED` is applied implicitly. The hierarchy node with the ID `D`
has three parent nodes and hence an exception is raised."

For cycles: "`ERROR` — This is the default setting. An exception is raised when a node
cycle is detected."

For orphans: "`IGNORE` — This is the default setting. Any orphan nodes are not
inserted in the SQL hierarchy."

So the same category of dirty data gives you a short dump for two defects and a
quietly shorter result set for the third. And "orphan" is broader than it sounds —
three distinct things qualify:

> "Hierarchy nodes that could have parent nodes according to the parent-child
> relationship, but the parent nodes are not in the SQL hierarchy (true orphans)."

> "Hierarchy nodes that cannot be reached from the root node set using hierarchy edges."

> "Hierarchy nodes that are part of a node cycle and cannot be reached from the root
> node set using hierarchy nodes (island orphans)."

The second bullet is the one that bites: *anything* not reachable from your
`START WHERE` roots is an orphan and is dropped by default. A mistyped root, a root
whose own parent field is not blank, a subtree re-parented under a node outside the
start set — all produce a smaller tree and `sy-subrc = 0`.

`ORPHANS ROOT` is how you see them instead of losing them: true orphans
"are included in the root node set as root nodes and flagged as orphan nodes in the
hierarchy column `HIERARCHY_IS_ORPHAN`", their descendants are kept and flagged too,
and for island orphans a synthetic parent is generated in which
"all columns of the source `hierarchy_source` contain the null value" and
`PARENT_ID` "also contains the null value" — a row of nulls that becomes a row of
initial values on the way into your internal table (see
[Null Values](../Null%20Values#readme)).

### The fix for one half breaks the other half

The natural reaction to the exception is `MULTIPLE PARENTS ALLOWED`. That makes the
statement run — and silently removes the guarantee that the tree columns mean anything:

> "The values of some hierarchy columns are usable only if the hierarchy is a tree-like
> SQL hierarchy in which a hierarchy node does not have multiple parent nodes."

Once a node is reachable by two paths it is *generated twice*, which the generator
documentation states plainly:

> "Rows of the result set of the source specified after `SOURCE` can occur more than
> once in the result set of the hierarchy generator, if selected by appropriate
> parent-child relationships."

A `SUM( plan_amount )` over that result double-counts, and `HIERARCHY_TREE_SIZE` stops
being a subtree count. If what you need is "one path per node", that is what
`GENERATE SPANTREE` is for — which is trap 3.

## Trap 3: `GENERATE SPANTREE` demands three clauses in ABAP SQL and forbids the same three in CDS

`GENERATE SPANTREE` collapses a multi-parent graph into a tree by keeping one path per
node — "If the paths have different lengths, the shortest is selected. If the paths all
have the same length, the first path found is selected."

The two dialects then state opposite requirements for it.

ABAP SQL:

> "If the addition GENERATE SPANTREE is specified, the following additions must be
> specified at the same time:"
>
> - `MULTIPLE PARENTS ALLOWED`
> - `ORPHANS IGNORE` or `ORPHANS` not specified
> - `CYCLES BREAKUP`

ABAP CDS:

> "If the addition GENERATE SPANTREE is specified, the additions MULTIPLE PARENTS,
> ORPHANS, and CYCLES cannot be specified and other defaults apply in parts:"
>
> - `MULTIPLE PARENTS` is used implicitly with `ALLOWED`.
> - `CYCLES` is used implicitly with `BREAKUP`.

The three clauses that are mandatory in the `FROM` clause are prohibited in the DDL —
so a working `define hierarchy` cannot be pasted into an ABAP SQL generator, nor the
reverse, even though the documentation elsewhere says the two are equivalent. Each
direction is a syntax error, which is the good outcome; the bad outcome is concluding
the feature is broken.

```abap
" ABAP SQL: all three companions are REQUIRED.
SELECT FROM HIERARCHY( SOURCE ydj_i_bom_src
                       CHILD TO PARENT ASSOCIATION _parent
                       START WHERE parent_id = ' '
                       MULTIPLE PARENTS ALLOWED
                       CYCLES BREAKUP
                       GENERATE SPANTREE )
       FIELDS part_id, parent_id
       INTO TABLE @DATA(lt_spantree).
```

```asddls
// CDS: writing those same three lines here is an error. Omit them.
define hierarchy YDJ_H_BOM
  as parent child hierarchy(
    source YDJ_I_BOM_SRC
      child to parent association _parent
      start where parent_id = ''
      siblings order by part_id
      generate spantree
    )
    { part_id, parent_id }
```

`CYCLES BREAKUP` carries its own coupling in both dialects — "If the addition BREAKUP
is specified, MULTIPLE PARENTS ALLOWED must also be specified" — so you cannot tolerate
cycles while insisting on single parents.

**One documented contradiction, flagged rather than resolved.** The two pages disagree
on when the addition does nothing. ABAP SQL: "If the parent-child relationships for the
current data produce **only tree-like** SQL hierarchies, the addition `GENERATE
SPANTREE` is ignored." CDS: "If the parent-child relationships for the current data
**do not produce** tree hierarchies, the addition `GENERATE SPANTREE` is ignored."
Those cannot both be right. The ABAP SQL wording is the one that makes sense — there is
nothing to prune in a graph that is already a tree — but this is a reading, not a
sourced fact, so do not build logic on either sentence.

## Trap 4: `START WHERE` is mandatory in ABAP SQL, and optional in CDS only for numeric keys

In the ABAP SQL generator the clause is not bracketed in the syntax diagram, and the
text matches: "`START WHERE` must be followed by a start condition that defines root
nodes for the root node set of the SQL hierarchy."

In CDS it is bracketed, and there is an implicit fallback — with a condition on it:

> "In semantic key scenarios, i.e. when the column that contains the parent node has a
> numeric data type, the `START WHERE` condition can be left out. In this case, an
> implicit `START WHERE` condition is generated, so that the root node set consists of
> all rows where the column that contains the parent node (as defined by the hierarchy
> association) is initial."

> "In UUID scenarios, the condition where to start is not implicitly set and must be
> specified explicitly. Otherwise, a syntax check error occurs."

So "roots are the rows with an empty parent" is automatic for an `INT4` parent column,
and a syntax error for a `RAW16` one. Modern RAP-style models with UUID keys fall in
the second group — cross-reference
[RAP Determinations and Validations](../RAP%20Determinations%20and%20Validations#readme)
for where those keys come from.

The start condition is also the one place where the familiar "empty filter" hazard
appears, in the same shape as the repo's
[Selection Tables](../Selection%20Tables#readme) note:

> "The start condition should select a meaningful set of root nodes. If no rows in the
> result set of the source `hierarchy_source` meet the condition, the SQL hierarchy is
> empty. If all rows meet the condition, the descendant nodes of every row are selected
> and inserted."

A start condition built from a selection screen that comes out matching everything does
not read the table once — it generates a full subtree *per row*, every node appearing
once for every ancestor it has.

## Trap 5: the clause order is fixed, and the two dialects order them differently

> "The order of the additions is fixed. They must be specified as shown here."

ABAP SQL `HIERARCHY( ... )`:

```
SOURCE / CHILD TO PARENT ASSOCIATION / PERIOD / START WHERE /
SIBLINGS ORDER BY / DEPTH / MULTIPLE PARENTS / ORPHANS / CYCLES /
LOAD / GENERATE SPANTREE / CACHE
```

CDS `DEFINE HIERARCHY`:

```
SOURCE / CHILD TO PARENT ASSOCIATION / PERIOD / DIRECTORY / START WHERE /
SIBLINGS ORDER BY / DEPTH / NODETYPE / LOAD / MULTIPLE PARENTS /
ORPHANS / CYCLES / GENERATE SPANTREE / CACHE
```

`LOAD` sits *after* `CYCLES` in ABAP SQL and *before* `MULTIPLE PARENTS` in CDS, and
`DIRECTORY` and `NODETYPE` exist only in CDS. Since both orders are mandatory, a
definition that is correct in one is a syntax error in the other for no reason beyond
line order.

## Trap 6: without `SIBLINGS ORDER BY`, order is undefined — and so is one whole column

> "The addition `SIBLINGS ORDER BY` sorts sibling nodes in the SQL hierarchy generated
> by the hierarchy generator. If this addition is not used, the order of the sibling
> nodes is undefined."

Undefined, not insertion order and not key order. A hierarchy rendered into a tree
control or written to a report will come out stable on one system and shuffled on
another. Worse, the sibling navigator's distance column depends on it:

> "If the values in the additional column `HIERARCHY_SIBLING_DISTANCE` are accessed,
> the addition `SIBLINGS ORDER BY` should be used in the SQL hierarchy specified after
> `SOURCE`. Otherwise, the values remain undefined."

Three further restrictions, each a compile error:

- hierarchy columns are not allowed here — "The additional hierarchy columns cannot be
  specified after `SIBLINGS ORDER BY`. They can, however, be specified in the general
  `ORDER BY` clause of the current query." So sorting siblings by `hierarchy_rank` is
  not a thing;
- no positional form — "The fields of the source `hierarchy source` must be specified
  by their name. It is not possible to specify a position as in the `ORDER BY` clause";
- "The fields specified after `ORDER BY` cannot be of the type `LCHR`, `LRAW`,
  `STRING`, `RAWSTRING`, or `GEOM_EWKB`." A `STRING` description column cannot order
  siblings.

Note also that the query's own `ORDER BY` is not an alternative but a layer on top:
"If additionally a general `ORDER BY` clause is specified in current query, it affects
the SQL hierarchy that is sorted by `SIBLINGS ORDER BY`." `ORDER BY hierarchy_rank` is
the usual way to keep pre-order traversal after the rows reach ABAP.

## Trap 7: the off-by-one columns, and the sign of a distance

Root nodes do not sit at level 0.

| Column | Value at a root |
|---|---|
| `HIERARCHY_LEVEL` | "Always 1 for root nodes. For their descendant nodes, the distance from the root node plus one." |
| `HIERARCHY_PARENT_RANK` | "0 for root nodes, otherwise the `HIERARCHY_RANK` ID of the parent node." |

So `WHERE hierarchy_level = 0` matches nothing, ever, and the idiomatic test for "is a
root" is `hierarchy_parent_rank = 0` — which is exactly what SAP's own CTE example
writes (`START WHERE hierarchy_parent_rank = 0`).

The navigators add `HIERARCHY_DISTANCE`, and its sign flips by direction.
`HIERARCHY_DESCENDANTS` gives "the positive difference between the hierarchy levels
`HIERARCHY_LEVEL` of the individual child nodes and the respective start nodes";
`HIERARCHY_ANCESTORS` gives "the negative difference". Hence the documented idioms for
dropping the start node itself:

> "If `FROM 1` is specified without the addition `TO`, `HIERARCHY_DESCENDANTS` selects
> only descendant nodes"

> "If `TO -1` is specified without the addition `FROM`, `HIERARCHY_ANCESTORS` selects
> only the ancestor nodes"

Use the wrong sign and you get an empty table rather than a complaint — SAP's example
spells it out: with `n1 = -3` and `n2 = -2`, "the result set of `HIERARCHY_DESCENDANTS`
is empty", while the same pair returns grandparents and great-grandparents from
`HIERARCHY_ANCESTORS`. `DISTANCE` also has no inversion check of its own: "If the value
of `n1` is greater than `n2`, no hierarchy node is selected."

```abap
" Everything under a node, excluding the node. FROM 1, not a WHERE on level.
SELECT FROM HIERARCHY_DESCENDANTS(
              SOURCE ydj_h_cost_centre( p_root = @lv_root )
              START WHERE cost_centre = @lv_node
              DISTANCE FROM 1 )
       FIELDS cost_centre, parent_id, hierarchy_distance
       INTO TABLE @DATA(lt_below).

" The chain upwards, excluding the node. TO -1, because ancestors are negative.
SELECT FROM HIERARCHY_ANCESTORS(
              SOURCE ydj_h_cost_centre( p_root = @lv_root )
              START WHERE cost_centre = @lv_node
              DISTANCE TO -1 )
       FIELDS cost_centre, parent_id, hierarchy_distance
       INTO TABLE @DATA(lt_above).
```

`DEPTH` has its own quiet failure. "If the value of `depth` is 0, only the root nodes
are inserted into the SQL hierarchy" — and:

> "If `depth` is less than 0, no hierarchy nodes are created and `sy-subrc` is set to 4."

A depth computed as `lv_max - lv_current` that goes negative therefore produces an
empty result and `sy-subrc = 4`, indistinguishable from "this subtree is empty".
`DEPTH` is also mutually exclusive with orphan handling: "The addition `DEPTH` can be
used only if the addition `ORPHANS` is not specified or is specified as
`ORPHANS IGNORE`."

## Trap 8: the aggregate navigator's `WHERE` does not restrict what it aggregates

`HIERARCHY_DESCENDANTS_AGGREGATE` computes, for every node, an aggregate over that
node's whole subtree — a running roll-up without a loop. It takes a `WHERE`, and that
`WHERE` does not mean what it means anywhere else in SQL:

> "The `WHERE` condition does not restrict the descendant nodes of the selected nodes.
> It is used only to select those nodes for which the aggregate function is calculated."

SAP's own example description, on `WHERE hierarchy_level <= @level`:

> "only nodes with a maximum hierarchy level of 2 are added to the result set. The
> aggregate functions, however, respect all descendant nodes regardless of their
> hierarchy level."

So `WHERE hierarchy_level <= 2` does not give you "the total of the top two levels" —
it gives you the top two levels' rows, each carrying a total over its *entire* subtree.
There is no reading of the result that reveals the difference; the numbers are simply
larger than the rows you can see justify.

```abap
SELECT FROM HIERARCHY_DESCENDANTS_AGGREGATE(
              SOURCE ydj_h_cost_centre( p_root = @lv_root ) AS h
              JOIN @lt_actuals AS a ON a~cost_centre = h~cost_centre
              MEASURES SUM( a~amount ) AS actual_sum
              WHERE hierarchy_level <= 2
              WITH SUBTOTAL
              WITH BALANCE )
       FIELDS cost_centre,
              actual_sum,
              hierarchy_rank,
              hierarchy_aggregate_type   " 0 = real node, 1/2 = WITH row
       INTO TABLE @DATA(lt_rollup).
```

Four more sharp edges in that one statement:

- **`JOIN` is an outer join, and its columns vanish.** "The result set of the SQL
  hierarchy is joined with the result set of the data source `data_source` in
  accordance with `LEFT OUTER JOIN` rules" — and "they are not part of the tabular
  result of the hierarchy navigator as additional columns". You can sum
  `a~amount`; you cannot select it. Nor filter on it: "The columns of a data source
  joined using `JOIN` cannot be used after `WHERE`."
- **Adding `JOIN` removes two aggregate functions.** Without `JOIN` the allowed set is
  `AVG`, `MIN`, `MAX`, `SUM`, `COUNT( [DISTINCT] col )`, `COUNT( * )`. With `JOIN` it
  is only `MIN`, `MAX`, `SUM`, `COUNT( [DISTINCT] col )` — `AVG` and `COUNT( * )` are
  gone, and "The addition `DISTINCT` is only possible for `COUNT` and for columns of
  the SQL hierarchy."
- **The `WITH` rows are rows of nulls.** Each `WITH` addition "adds exactly one row",
  in which "all columns, including the hierarchy columns, contain the null value,
  except columns created using the addition `MEASURES` and the hierarchy column
  `HIERARCHY_AGGREGATE_TYPE`". Nulls become initial values in ABAP, so a `WITH TOTAL`
  row arrives as a node with a blank key and a real amount — it will happily be
  appended to a report or summed a second time unless you branch on
  `HIERARCHY_AGGREGATE_TYPE` (`SUBTOTAL` = 1, `BALANCE` = 2, `NOT MATCHED` = 3,
  `TOTAL` = 4, ordinary node = 0).
- **`SUBTOTAL` and `BALANCE` are complements of your `WHERE`,** not of the hierarchy:
  `SUBTOTAL` aggregates "all hierarchy nodes that meet the `WHERE` condition",
  `BALANCE` "all hierarchy nodes that do not meet the `WHERE` condition". Using any
  `WITH` addition also moves the statement's syntax check "in strict mode from ABAP
  release 7.77".

## Trap 9: navigate an existing hierarchy, do not regenerate it

Generating a hierarchy is the expensive part, and the result is cached:

> "Since hierarchies generated from the `START WHERE` condition are buffered on the
> database, it is advisable to use hierarchy navigators to evaluate a SQL hierarchy.
> For example, finding the descendant nodes of a node with the hierarchy node navigator
> `HIERARCHY_DESCENDANTS` is more efficient than generating a new SQL hierarchy with
> this node as a root node."

Which also means a parameterised root is the wrong shape for a large tree:

> "it is advisable to use fixed values for the root nodes of large hierarchies of data
> that do not change often ... The usage of arbitrary parameters for specifying the root
> nodes especially should be restricted to small hierarchies or for demonstration
> purposes only."

Drilling down by re-calling `HIERARCHY( ... START WHERE id = @clicked_node )` on every
click is therefore the slow path twice over: it misses the cache and it re-reads the
source. Generate once from a fixed root, then navigate.

Navigators are a dead end structurally, though — they consume hierarchies and do not
produce them:

> "Hierarchy navigators do not create any SQL hierarchies: They cannot be specified as
> a source in hierarchy navigators. They cannot be exposed as a CTE hierarchy."

Generators *can* nest (a `HIERARCHY` whose `SOURCE` is another `HIERARCHY`), with a
one-line warning attached — "SQL hierarchies should only be nested in exceptional
cases" — and on the CDS side not even that: "a CDS hierarchy cannot be the source of
another CDS hierarchy."

Two performance switches are worth knowing and not worth defaulting:
`LOAD INCREMENTAL` loads "Only the rows of the source table that can be reached from
the start nodes", but "If, on the other hand, the source table has only few rows and
they are all part of the hierarchy, `LOAD INCREMENTAL` might even take longer than
`LOAD BULK`", and it "should not be used with global temporary tables as data source".
`CACHE FORCE` caches "even if the source cannot be assessed to be reliably
deterministic" — i.e. you are asserting determinism the database could not verify.

## Trap 10: access control prunes the source, and the default then deletes the subtree

A CDS role on the hierarchy source is applied *before* the tree is built:

> "If a CDS role is assigned to a CDS view specified as a source, the source is
> implicitly subject to CDS access control and only nodes that meet the access
> conditions of the CDS role are transferred to the SQL hierarchy."

Compose that with trap 2. A user authorised for a child cost centre but not for its
parent loses the parent row from the source; the child is then a node "that could have
parent nodes according to the parent-child relationship, but the parent nodes are not
in the SQL hierarchy" — a true orphan — and the default `ORPHANS IGNORE` drops it,
together with everything beneath it. The user sees a smaller tree with no indication
that anything was withheld, and the totals under trap 8 are correspondingly short.

`ORPHANS ROOT` turns that into visible re-rooted subtrees; `SOURCE ... WITH PRIVILEGED
ACCESS` switches the filtering off entirely —
"the access control is deactivated, and the access conditions are not evaluated" —
which is the right tool for a reconciliation job and the wrong one for a user-facing
report. See [CDS Access Control](../CDS%20Access%20Control#readme).

## Small print

- **No buffer, no in-memory engine, one internal table.**
  "Hierarchy functions cannot be processed by the ABAP SQL in-memory engine. The ABAP
  SQL statement bypasses the table buffer and an internal table accessed by
  `FROM @itab` must be transported to the database. This is only possible for one
  internal table per ABAP SQL statement." A fully-buffered customising table read
  through a hierarchy goes to the database every time
  ([Table Buffering](../Table%20Buffering#readme)).
- **Column names collide with hierarchy column names.** "The association source of the
  association cannot contain any fields that have the same name as a hierarchy column.
  An alternative element name must be defined for these fields." A legacy table with a
  `NODE_ID` or `PARENT_ID` column must alias it in the source view. The same holds for
  `VALID_FROM`/`VALID_UNTIL` under `PERIOD`, and for CTE hierarchies: "The `SELECT` list
  of the subquery must not contain any columns with the same name or alias name as a
  hierarchy column."
- **CDS cannot read its own hierarchy columns.** "Unlike in ABAP SQL, however, ABAP CDS
  cannot access the additional hierarchy columns of a CDS hierarchy. Instead, the
  associated hierarchy attributes must be entered in the element list of the CDS
  hierarchy if required" — via `$node.hierarchy_rank as hiera_rank`. From ABAP SQL you
  then get both names for the same value, because "the hierarchy columns are read
  regardless of whether hierarchy attributes are listed in the element list".
- **`NODE_ID` is a concatenation, usually.** For a parent-child hierarchy it is
  `SSTRING` length 1333 holding "Internal character-like key of the hierarchy node that
  concatenates the values of all association target fields" — unless the `ON` condition
  has exactly one comparison, in which case "no concatenation is required, and the data
  type is the data type of the specified field". So its type depends on how many fields
  your association compares.
- **Temporal hierarchies narrow, never widen.** With `PERIOD`, "Validity intervals can
  only remain the same or become narrower from hierarchy level to hierarchy level, they
  never widen", and a child's own period is not enough: "Only the validity interval of
  the parent node is decisive. A path of a regular SQL hierarchy is truncated in a
  temporal SQL hierarchy at the position in which there is no intersection between the
  period and the preceding validity interval." Note also that the time filter can mask
  structural defects — "Nodes that would raise an exception in a regular SQL hierarchy
  can be hidden in a temporal SQL hierarchy" — so a hierarchy that works for this
  year's dates may dump for last year's. `PERIOD` and `GENERATE SPANTREE` are mutually
  exclusive.
- **`MULTIPLE PARENTS LEAVES ONLY`** is the middle setting: only leaf nodes may have
  several parents. SAP's demo shows it raising an exception as soon as one of those
  leaves gains a child of its own — a tolerance that expires when the data grows.
- **Navigators add `START_RANK` and `START_ID`** on top of the source's hierarchy
  columns, carrying "the values of the hierarchy columns `HIERARCHY_RANK` and `NODE_ID`
  of the associated start nodes" — which is how you tell apart rows belonging to
  different start nodes when `START WHERE` matched more than one.

## Quick reference

| Goal | Spelling |
|---|---|
| Whole tree from the real roots | `START WHERE parent_col = ' '` (explicit in ABAP SQL) |
| See rank/level/tree size | name them in `FIELDS` — `*` will not return them |
| Find the roots in a result | `hierarchy_parent_rank = 0` (never `hierarchy_level = 0`) |
| Everything under a node, excluding it | `HIERARCHY_DESCENDANTS( ... DISTANCE FROM 1 )` |
| The path up to the root, excluding the node | `HIERARCHY_ANCESTORS( ... DISTANCE TO -1 )` |
| Subtree roll-up without a loop | `HIERARCHY_DESCENDANTS_AGGREGATE( ... MEASURES SUM( ... ) )` |
| Stable, reproducible node order | `SIBLINGS ORDER BY` + query `ORDER BY hierarchy_rank` |
| Survive dirty data instead of dumping | `MULTIPLE PARENTS ALLOWED` + `CYCLES BREAKUP` + `ORPHANS ROOT` |
| One path per node in a graph | `GENERATE SPANTREE` (+3 clauses in ABAP SQL, none in CDS) |
| Reuse the definition across programs | `DEFINE HIERARCHY` in CDS, not the inline generator |
| Drill down after the first read | a navigator over the cached hierarchy, not a new generator |

## References

- [`SELECT, FROM hierarchy` — the three kinds, and the `*` rule](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/select-from-hierarchy)
- [`SELECT, FROM HIERARCHY` — the generator, both variants](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/select-from-hierarchy-abenselect_hierarchy_generator)
- [`SELECT, FROM HIERARCHY, CHILD TO PARENT ASSOCIATION` — every addition, fixed order, `ORPHANS`/`CYCLES`/`MULTIPLE PARENTS`/`DEPTH`/`LOAD`/`SPANTREE`/`CACHE`](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/select-from-hierarchy-child-to-parent-association)
- [Hierarchy Columns — names, types, and the tree-only caveat](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/hierarchy-columns)
- [`SELECT, FROM hierarchy_navigator` — navigators create nothing, and the caching advice](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/select-from-hierarchy-navigator)
- [`SELECT, FROM hierarchy_node_navigator` — `DESCENDANTS`/`ANCESTORS`/`SIBLINGS` and `DISTANCE`](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/select-from-hierarchy-node-navigator)
- [`SELECT, FROM hierarchy_descendants_aggregate` — `MEASURES`, the `WHERE` that does not limit, and the `WITH` rows](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/select-from-hierarchy-descendants-aggregate)
- [`CDS DDL - DEFINE HIERARCHY` — the CDS dialect, implicit `START WHERE`, `$node.`](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/cds-ddl-define-hierarchy)
- [`SELECT, FROM cds_hierarchy`](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/select-from-cds-hierarchy)
- [`WITH, HIERARCHY` — exposing a CTE as a hierarchy](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWITH_HIERARCHY.html)
- [ABAP SQL - Working with Hierarchies — SAP's own end-to-end walkthrough](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/abap-sql-working-with-hierarchies)

Related notes in this repo:
[Common Table Expressions](../Common%20Table%20Expressions#readme) for the recursion a
hierarchy replaces, [CDS Associations](../CDS%20Associations#readme) for the
self-association this is built on, [SQL Joins](../SQL%20Joins#readme) for the fan-out
that multiple parents reintroduce, [Null Values](../Null%20Values#readme) for the
`WITH`/orphan rows made of nulls, [CDS Access Control](../CDS%20Access%20Control#readme)
for the filter that creates orphans, [Table Buffering](../Table%20Buffering#readme) for
the bypass, [Window Expressions](../Window%20Expressions#readme) for the other
"compute it in the database" tool, and [AMDP](../AMDP#readme) for what you would
otherwise have written by hand.

Worked examples: [ydj_sql_hierarchy_demo.abap](ydj_sql_hierarchy_demo.abap)
