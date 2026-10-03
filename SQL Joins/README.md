# ABAP SQL Joins — the `WHERE` that cancels your outer join, the parentheses you do not get to choose, and the cardinality that changes the result

A join is the one piece of ABAP SQL that most developers arrive already knowing, from
any other SQL dialect. That is exactly why the ABAP-specific parts are so easy to miss:
the syntax is familiar, and the two worst traps below change the **result set** with no
error, no warning and no visible symptom — the answer is just quietly wrong.

- a `WHERE` condition on a column of the right-hand table **silently converts a**
  **`LEFT OUTER JOIN` into an inner join** — the rows you wrote the outer join for are
  the first thing it deletes;
- **you do not choose the parentheses.** They are implied by where the `ON` conditions
  sit, and any brackets you add by hand must agree with that;
- the `cardinality` addition is a **promise to the optimizer, not a constraint** — get it
  wrong and the documented outcome is that the row count depends on your `SELECT` list;
- a join **turns the table buffer off** for the whole statement.

```abap
SELECT FROM scarr AS c
       INNER JOIN spfli AS p ON p~carrid = c~carrid
  FIELDS c~carrname, p~connid, p~cityfrom
  INTO TABLE @DATA(lt_flights).
```

Three join types exist: `[INNER] JOIN`, `LEFT|RIGHT [OUTER] JOIN` and `CROSS JOIN`.
Inner and outer joins **must** have an `ON` condition; a cross join **must not** have
one.

## Trap 1: a `WHERE` on the right-hand table cancels the outer join

This is the headline, because it is a *correctness* bug that produces a perfectly
plausible, slightly-too-small result set.

A left outer join is defined as the inner join plus one row per unmatched left row:
for each selected row on the left side `"at least one row is created in the result set,`
`even if no rows on the other side meet the condition sql_cond"`, and the right-hand
columns of those rows are `"filled with null values"`.

Now add a `WHERE`. A null compares as **unknown** to everything except `IS NULL`, so
any ordinary predicate on a right-hand column evaluates to unknown on exactly those
padded rows — and they are dropped. What is left is the inner join.

```abap
" Intent: every airline, plus its Frankfurt departures if it has any.
" Actual: only airlines that depart from Frankfurt. The outer join is dead code.
SELECT FROM scarr AS s
       LEFT OUTER JOIN spfli AS p ON s~carrid = p~carrid
  FIELDS s~carrid, p~connid
  WHERE p~cityfrom = 'FRANKFURT'          "<== kills the unmatched rows
  INTO TABLE @DATA(lt_wrong).

" Correct: the restriction belongs in the join condition, not in WHERE.
SELECT FROM scarr AS s
       LEFT OUTER JOIN spfli AS p ON s~carrid  = p~carrid
                                 AND p~cityfrom = 'FRANKFURT'
  FIELDS s~carrid, p~connid
  INTO TABLE @DATA(lt_right).
```

Why the habit forms: for an **inner** join, `ON` and `WHERE` are interchangeable — the
row either satisfies both or survives neither. The equivalence simply does not carry
over to outer joins, and nothing warns you when the join type changes later.

The documentation does flag the construct, in an easily missed way: specifying
`"Fields from the right side specified in LEFT OUTER JOIN or from the left side in`
`RIGHT OUTER JOIN in the WHERE condition"` is one of the triggers that switches the
statement into **strict mode for ABAP release 7.40, SP05**. That is a stricter syntax
check on the rest of the statement, not a prohibition — the construct stays legal.

### The one deliberate use: `IS NULL` as an anti-join

`IS NULL` is the single predicate that is *true* on those padded rows, which makes the
same construct the canonical way to ask for rows that have **no** match. The
documentation uses exactly this shape, and describes it as outputting
`"all airlines that do not fly from"` the given city:

```abap
" Airlines with NO Frankfurt departure at all.
SELECT FROM scarr AS s
       LEFT OUTER JOIN spfli AS p ON s~carrid  = p~carrid
                                 AND p~cityfrom = @lv_city
  FIELDS s~carrid, s~carrname
  WHERE p~connid IS NULL
  INTO TABLE @DATA(lt_anti).
```

Note where the filter sits: `p~cityfrom` is in the `ON` (it defines what counts as a
match), `IS NULL` is in the `WHERE` (it keeps only the non-matches). Move either one
and the query answers a different question. See
[Null Values](../Null%20Values#readme) for why every other comparison is unknown here.

## Trap 2: the parentheses are implied by the `ON` positions

In a chain of joins you might expect brackets to be yours to place, the way they are
in a `UNION` chain. They are not. The rule is positional:

> From left to right, each `ON` condition is assigned to the **directly preceding**
> `JOIN` and creates a join expression. [...] Explicitly specified parentheses
> **must match the parentheses** specified implicitly by the `ON` conditions.

So the grouping is already fixed by the time you start typing brackets, and brackets
that disagree are a syntax error rather than a re-grouping. The practical consequences:

- You cannot force a different evaluation order for inner/outer joins by adding
  parentheses. To change the order you have to **move the `ON` conditions**, which
  means re-writing the chain.
- The left-nested shape (`(( a JOIN b ON ... ) JOIN c ON ... )`) is the one that
  matches the natural `ON` placement. Putting a join expression on the **right** side
  of a join — `a JOIN ( b JOIN c ON ... ) ON ...` — is legal but is another
  7.40 SP05 strict-mode trigger: `"Multiple consecutive joins where a join expression`
  `and not a database table or view is on the right side of a join expression."`
- `RIGHT OUTER JOIN` is a strict-mode trigger all by itself. Since `a RIGHT OUTER`
  `JOIN b` is just `b LEFT OUTER JOIN a` with the sides swapped, the lower-friction
  choice is to swap the sides and keep every outer join in the codebase left-handed.

`CROSS JOIN` plays by different rules — it has no `ON` condition, so it is evaluated
left to right and parentheses **do** matter. Combining cross joins only is safe
(`"the order of the evaluation is irrelevant"`), but mixing them with inner/outer joins
is not: `"If cross joins are combined with inner and outer joins, the result can`
`depend on the order of evaluation or the parentheses."`

## Trap 3: fan-out — the join multiplies rows, and your aggregates with them

The result set `"contains all combinations of rows for whose columns the join condition`
`sql_cond is jointly true"`. One left row with five matches becomes five rows. Nothing
about that is surprising on its own; what surprises people is what it does to an
aggregate over a **left-hand** column, which is now counted once per match:

```abap
" Total distance of all flight connections.
SELECT FROM spfli AS p
  FIELDS SUM( p~distance )
  INTO @DATA(lv_true_total).

" Same aggregate, same column, after joining the flights of each connection.
" Every connection is now counted once PER FLIGHT. The number is meaningless,
" and it is larger - which reads like more complete data, not like a bug.
SELECT FROM spfli AS p
       INNER JOIN sflight AS f ON f~carrid = p~carrid
                              AND f~connid = p~connid
  FIELDS SUM( p~distance )
  INTO @DATA(lv_inflated).
```

Fixes, in order of preference:

- aggregate the right-hand table **before** joining, in a CTE or a subquery, so the
  join is `1:1` by construction;
- `COUNT( DISTINCT col )` if a count is all you need **and** a single column
  identifies the row — `COUNT( DISTINCT connid )` over `SPFLI` under-counts, because a
  connection is identified by `carrid` *and* `connid`;
- a scalar subquery in the `SELECT` list instead of a join.

`DISTINCT` is available on every aggregate function, not just `COUNT` —
`SUM( DISTINCT col )` parses fine. It is not a fix for fan-out, though:
`"The addition DISTINCT excludes duplicate values from the calculation"`, so two rows
that legitimately hold the same amount collapse into one. It de-duplicates **values**,
where the problem is duplicated **rows**.

## Trap 4: `cardinality` is a promise to the optimizer, not a constraint

An inner or outer join accepts a cardinality between the `JOIN` keyword and the table:

```abap
SELECT FROM scarr AS c
       LEFT OUTER MANY TO ONE JOIN spfli AS p ON c~carrid = p~carrid
  FIELDS c~carrid, c~carrname, p~connid
  INTO TABLE @DATA(lt_hinted).
```

The spellings are `ONE`/`EXACT ONE`/`MANY` on each side, nine combinations in all, and
if you write nothing the `"implicit default cardinality is"` *many-to-many*. It is easy
to read this as a declaration that is either true or checked. It is neither:

> The cardinality is **mainly descriptive, not prescriptive**. It does not force a
> matching result set.

What it actually does is license the optimizer to skip work — on SAP HANA it is used
`"for performance optimizations by suppressing surplus joins"`. If the data does not
match the promise, you get no error, no warning, and this:

> It is important that the cardinality specification matches the data in question.
> **Otherwise, the result is undefined and can depend on the entries in the**
> **`SELECT` list.**

Read that last clause twice. The documentation illustrates it with a deliberately
wrong `MANY TO ONE` between `SCARR` and `SPFLI`: with columns from both sides in the
`SELECT` list no optimization happens and you get the real row count, but with no
right-hand column and `COUNT(*)` the surplus join is optimized away and the count
changes. **Adding or removing a column from the `SELECT` list therefore changes the
number of rows.**

That makes it the most dangerous addition in the clause, because of who adds it and
when: it is normally pasted in during performance tuning, by someone reading a HANA
optimization note, long after the query was written and tested. The cardinality of
real data also drifts — `MANY TO EXACT ONE` is a true statement about a table until the
first customizing row without a text entry arrives.

Rules of thumb: leave it off unless you have measured a gain; if you do use it, make
sure it is enforced by a real key or a foreign key rather than by the current contents
of the table; and never use it to express intent. Specifying it puts the statement into
strict mode as of release 7.91.

## Trap 5: `CROSS JOIN` reads everything before it filters

A cross join has no `ON` condition, so the filtering has to happen in `WHERE`. The
result is the same as an inner join with that condition, but the execution is not:

> A cross join with a `WHERE` condition has the same result as an inner join with an
> identical `ON` condition. Unlike the inner join, **in a cross join all data is read
> first before the condition is evaluated**. In an inner join only data that meets the
> `ON` condition is read.

Hence the unusually blunt advice in the documentation: a cross join
`"should only be used with extreme caution"`, since without an `ON` condition
`"all data of all involved data sources is read"` and the row count is always the
product of both sides. Two tables of 100,000 rows is 10 billion rows.

One ABAP-specific quirk makes the cross product smaller than you would predict: a
cross join of two client-dependent sources is `"converted internally to an inner join"`
on the client columns, so you get the product *within* the current client. But
`"If one side is not client-dependent, the cross join is executed completely"` — so
joining a client-dependent table to a client-independent one is the expensive case.

`CROSS JOIN` also switches the statement into strict mode for release 7.65.

## Trap 6: what the `ON` condition will not accept

The `ON` condition looks like a `WHERE` condition and is not one. The documented
restrictions, and why each one shows up in real code:

| Restriction | What it breaks |
|---|---|
| `"After ON, at least one comparison must be specified."` | No `ON 1 = 1` placeholder; use `CROSS JOIN` and accept Trap 5 |
| The expression `[NOT] IN range_tab` **cannot be used** | A `SELECT-OPTIONS` / `RANGE OF` table cannot be applied in `ON`. It has to go in `WHERE` — which for an outer join lands you in Trap 1 |
| `"Subqueries cannot be used."` | No correlated lookup inside the join condition |
| `"Path expressions cannot be used."` | CDS associations cannot be dereferenced in `ON` |
| A dynamic `(cond_syntax)` works **only** if the `FROM` clause is static | A generator that builds both parts dynamically fails; see [Dynamic SQL](../Dynamic%20SQL#readme) |
| The client column `"cannot be used as an operand in the"` `ON` condition | The equality on the client column is added for you implicitly; writing it yourself is the error |

The range-table row is the one that bites hardest, because the fix for Trap 1 (move the
condition into `ON`) is unavailable precisely when the condition comes from a selection
screen. The way out is to filter the right-hand table in a CTE or subquery first, then
outer-join the filtered result. See [Selection Tables](../Selection%20Tables#readme).

Two more things are legal but switch on strict mode for 7.40 SP08:
`"Use of the additions LIKE, IN, and NOT and the operators OR or NOT in an ON`
`condition"`, and `"Outer join without a comparison between columns on the left and`
`right sides"` — i.e. an outer join whose `ON` only compares a column against a literal
or host variable, which is almost always a mistake.

Finally, a typing rule that is easy to violate with generated code: comparisons run on
the database, so join conditions should be formulated `"only between operands of the`
`same type and the same length"` to avoid platform-dependent conversions. And one
oddity worth knowing — `col LIKE '%'` is `"always true, even if the column"` holds a
null value, unlike every other `LIKE` pattern.

## Trap 7: the 50-source ceiling fails at two different times

The number of data sources in one join expression is capped — the maximum
`"is set to allow the SELECT statement to be executed on all supported database`
`systems and is currently 50"`. The failure mode depends on whether the compiler can
see it:

> More than 49 joins, if known statically, **produce a syntax error. If they are not
> known statically**, they produce a runtime error.

So a hand-written monster query is caught at activation, while a dynamic `FROM` clause
assembled from configuration is caught the first time a customer has enough rows in
the configuration table. Note also that the same data source may appear repeatedly —
`"A data source can exist more than once within a join expression"` — but then it
`"must then be given different names"` with `AS`, and each repetition spends one of the
50.

## Trap 8: a join turns the table buffer off

This one is a performance cliff rather than a wrong answer, and it is invisible in a
test system with cold buffers:

> If a database table is joined, the ABAP SQL statement **bypasses the table buffer**
> [...] Join expressions should not be applied to buffered tables. Instead the addition
> `FOR ALL ENTRIES` should be used, which can be processed by the ABAP SQL in-memory
> engine.

Joining a small, fully-buffered customizing table to a large one therefore converts
every buffered read into a database round trip. The in-memory engine only handles join
expressions that `"access only internal tables but no database tables"`, and when a
database table is involved any `FROM @itab` operand has to be shipped to the database —
`"only possible for one internal table per ABAP SQL statement"`, so two internal tables
cannot be joined against a database table at all. See
[Table Buffering](../Table%20Buffering#readme) and
[For All Entries](../For%20All%20Entries#readme).

## Smaller gotchas

- **Ambiguous column names need `~` everywhere, not just in the join.** If the same
  column name exists in several sources of the join, those sources
  `"must be identified in all other additions of the SELECT statement"` with the column
  selector — so adding a second table can force `~` prefixes into the `WHERE`,
  `GROUP BY` and `ORDER BY` clauses you did not touch.
- **`ORDER BY` over outer-joined columns is not portable.** With null values present,
  `"the sort order can depend on the database system"`. If the order matters, sort on
  columns of the preserved side, or wrap the nullable column in `coalesce`.
- **`coalesce` is the documented way to flatten outer-join nulls** into a default
  value, which also side-steps the null-handling rules on the ABAP side.
- **`ORDER BY PRIMARY KEY` is refused** for a join — see
  [Row Limiting & Ordering](../Row%20Limiting%20and%20Ordering#readme).
- **Inner and cross joins between two single sources are commutative**; outer joins
  obviously are not, and mixing cross with outer makes the order significant (Trap 2).
- **DDIC tables in a join must be transparent** — pooled and cluster tables cannot be
  joined at all.

## Quick reference

| Goal | Write this |
|---|---|
| Keep all left rows, restrict the right | Condition in `ON`, never in `WHERE` |
| Rows with no match (anti-join) | `LEFT OUTER JOIN` + `WHERE right~key IS NULL` |
| Filter the right side by a selection range | Pre-filter in a CTE, then outer-join it |
| Aggregate without fan-out | Aggregate in a CTE/subquery first (`COUNT( DISTINCT )` only if one column is the key) |
| Avoid `RIGHT OUTER JOIN` | Swap the two sides and use `LEFT OUTER JOIN` |
| Join a buffered table | Do not — use `FOR ALL ENTRIES` |
| Speed up a confirmed `n:1` join | `cardinality`, only if a key enforces it |

## References

- [`SELECT, FROM JOIN` — join types, nesting priority, `ON` restrictions and `cardinality`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_JOIN.html)
- [`join` — glossary definition](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENJOIN_GLOSRY.html)
- [`left outer join` — the unmatched-row rule](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLEFT_OUTER_JOIN_GLOSRY.html)
- [`cardinality` — glossary definition](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCARDINALITY_GLOSRY.html)
- [Strict mode 7.40 SP05 — the four join triggers](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_STRICTMODE_740_SP05.html)
- [Strict mode 7.40 SP08 — `LIKE`/`IN`/`NOT`/`OR` in `ON`, outer join without a column comparison](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_STRICTMODE_740_SP08.html)
- [Strict mode 7.65 — cross join in the `SELECT` statement](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_STRICTMODE_765.html)
- [Aggregate expressions — the `DISTINCT` addition](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_AGG_FUNC.html)
- [Inner, outer and cross joins — executable examples](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENJOINS_ABEXA.html)

Related notes in this repo: [CDS Associations](../CDS%20Associations#readme) for the
same joins expressed declaratively, [Set Operators](../Set%20Operators#readme) for
combining result sets instead of columns, and
[Null Values](../Null%20Values#readme) for what the padded rows actually contain.

Worked, runnable examples: [ydj_sql_join_demo.abap](ydj_sql_join_demo.abap)

