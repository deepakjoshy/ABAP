# Common Table Expressions (`WITH`) — the CTE you defined and did not use, the client column that stops being one, and the `ORDER BY` that is not portable

A common table expression (CTE) is a named, temporary result set that exists only for
the duration of one ABAP SQL statement. The documentation calls them
`"temporary views, which only exist for the duration of the database access"`, and the
reason to reach for one is almost always the same: you need an intermediate result —
aggregate first, then join — and ABAP SQL otherwise gives you nowhere to put it.
A CTE is also the documented workaround for something ABAP SQL simply cannot do:
`"selecting directly from a subquery SELECT FROM subquery, which is not possible in ABAP SQL"`.

This note is about what changes once the intermediate result becomes a data source.
Two of the behaviours below are syntax errors that surface while you are *deleting*
code rather than adding it, one quietly takes client handling away from half of your
statement, and one only fails on a database you do not develop on.

- **every CTE you define must be used**, and the main query must read at least one of
  them — so commenting out one join can break the compile of a statement you did not
  otherwise touch;
- **the result set of a CTE has no client column**, even if you explicitly selected
  `mandt` into it — and `USING` is then *refused* on that data source;
- **`ORDER BY` inside a CTE is not supported by every database**, so a top-N-per-group
  CTE that works on your system can raise `CX_SY_SQL_UNSUPPORTED_FEATURE` on another;
- **`FOR ALL ENTRIES` is the one clause the main query may not have** — which is awkward,
  because "move it into a CTE" is the usual advice for `FOR ALL ENTRIES` problems;
- a `WITH` loop is closed by **`ENDWITH`**, not `ENDSELECT`.

```abap
" Aggregate first, then join: the fan-out fix, without a helper table.
WITH
  +seats AS ( SELECT FROM sflight
                FIELDS carrid, connid, SUM( seatsocc ) AS occupied
                GROUP BY carrid, connid )
  SELECT FROM spfli AS p
         INNER JOIN +seats AS s ON s~carrid = p~carrid
                               AND s~connid = p~connid
    FIELDS p~carrid, p~connid, p~cityfrom, p~cityto, s~occupied
    WHERE p~carrid = 'LH'
    INTO TABLE @DATA(lt_result).
```

The statement has exactly three parts: a comma-separated list of CTE definitions
(`"There must be at least one definition of a CTE"`), the CTE subqueries themselves, and
one closing main query that produces the result set handled by `INTO`.

## The `+` is part of the name

The name rules are small but strict, and all of them are syntax errors rather than
surprises:

- the name must be prefixed with `+`, and
  `"The initial + character is part of the name, but cannot stand alone and must not be followed by a number"`
  — so `+1st_pass` does not compile, `+pass1` does;
- `"The names cte can have a maximum of 30 characters, and can contain letters, numbers, and underscores"`,
  and must start with a letter or an underscore (after the `+`);
- the name is local to the statement: `"A common table expression is only known within the current WITH statement."`

The `+` is not decoration. It is the same idea as the `@` on host variables —
`"The character + in front of the name of a common table expression marks it as such, just like the character @ for host variables"`
— and it buys you one real guarantee: `"a common table expression cannot have the same name as a table from the ABAP Dictionary and hence cannot be hidden"`.
No CTE can ever shadow a DDIC table, so `FROM +carriers` is unambiguous forever.

One asymmetry worth knowing before you debug it: the `+` survives everywhere except in
an inline declaration. `"The character + is omitted from the name of the substructure"`
when a substructure is created for a CTE in an `INTO` clause with `@DATA(...)` — so the
component of your result structure is `carriers`, not `+carriers`.

## Trap 1: an unused CTE is a syntax error (and there is no recursion)

> `"Each common table expression defined in a WITH statement must be used at least once within the WITH statement, either in another common table expression or in the main query. This means that the main query must access at least one common table expression."`

This is stricter than most SQL dialects, where an unused CTE is dead weight the
optimizer discards. In ABAP it does not compile. The practical consequence is that the
error arrives during *subtraction*, not addition: you comment out the one join that read
`+prices` while narrowing down a bug, and the statement stops compiling for a reason
that has nothing to do with the line you edited.

The same rule has a second half, and this one is architectural:

> `"It cannot be used in its own subquery or in the subqueries of preceding definitions."`

So a CTE can only ever read CTEs defined **above** it. No self-reference means **ABAP
SQL CTEs are not recursive** — the `WITH RECURSIVE` pattern from other dialects has no
equivalent here, and transitive closure over a parent-child table is not expressible this
way. The documented route for that is a different feature: exposing the CTE as a
[CTE hierarchy](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWITH_HIERARCHY.html)
with the `hierarchy` addition, which is what ABAP SQL offers instead of recursion.

```abap
WITH
  +a AS ( SELECT FROM scarr FIELDS carrid ),
  +b AS ( SELECT FROM +a    FIELDS carrid )   " legal: +a is defined above
  SELECT FROM +b FIELDS carrid INTO TABLE @DATA(lt_x).

" +a AS ( SELECT FROM +b ... )   " illegal: forward reference
" +a AS ( SELECT FROM +a ... )   " illegal: self-reference, so no recursion
```

## Trap 2: the CTE result set has no client column

This is the headline, because it is the one behaviour that silently changes what client
handling applies to your statement.

> `"Generally, the result set of a common table expression has no client column. Even if the client column of a client-dependent data source is included explicitly in the subquery to its SELECT list, it does not behave as such in the result set."`

Read that twice. Selecting `mandt` into the CTE does not give the CTE a client column —
it gives it an ordinary `CHAR(3)` column that happens to be called `mandt`. Implicit
client handling still applies to the *database table* inside the subquery, so the rows in
the CTE are the current client's rows; but the CTE itself is a **client-independent**
data source from that point on, and it is listed as such in the documentation alongside
internal tables.

That has a visible consequence straight away. Because the data source has no client
column, there is nothing to switch:

> `"a query of the WITH statement that uses a common table expression as a data source cannot specify the addition USING or the obsolete addition CLIENT SPECIFIED"`

So the cross-client report that worked as a plain `SELECT ... USING ALL CLIENTS` does not
survive a refactor into `WITH`: the `USING` moves down into the CTE subquery, where it
still works, and the main query can no longer say anything about clients at all. If the
subquery reads all clients, the main query joins **all of them** against whatever else it
reads, with no implicit comparison on the CTE side to stop it.

The fix is explicit — `DECLARE CLIENT`:

```abap
WITH
  +rows AS ( SELECT FROM spfli FIELDS mandt, carrid, connid USING ALL CLIENTS )
  SELECT FROM +rows DECLARE CLIENT mandt
    FIELDS carrid, connid
    INTO TABLE @DATA(lt_rows).        " now client-dependent again
```

> `"The addition DECLARE CLIENT enables client handling for data sources that otherwise are never client-dependent (CTEs, internal tables)."`

It works on `"any column of type CHAR with length 3"`, the column
`"is not required to be in the first position"`, and once declared, implicit client
handling and the `USING` additions behave exactly as they do for a real client-dependent
table. The one thing it does not do is check that the column you nominated is meaningful
— the documentation only asks that it
`"should be specified in a way to produce meaningful results"`.

## Trap 3: `ORDER BY` in a CTE is database-dependent

Sorting inside a CTE is how you express "the top 3 flights per carrier", and the syntax
allows it with two ordering restrictions:

> `"The addition UP TO n ROWS can only be used after ORDER BY and the addition OFFSET can only be used after UP TO n ROWS."`

But the feature itself is not guaranteed:

> `"An ORDER BY clause in a subquery is not supported by all databases."`

What you get is a syntax *warning* from the extended program check, suppressed with the
pragma `##db_feature_mode[limit_in_subselect_or_cte]` — and that pragma is where the trap
lives, because suppressing the warning does not add the capability. On a database that
lacks it, `"a catchable exception of the class CX_SY_SQL_UNSUPPORTED_FEATURE is raised"`
at runtime. Develop on HANA, suppress the warning because it is noise, and the statement
fails on the system that is not HANA — a secondary connection to a legacy database counts.

The documented guard is a feature query, not a comment:

```abap
IF cl_abap_dbfeatures=>use_features(
     requested_features = VALUE #( ( cl_abap_dbfeatures=>limit_in_subselect_or_cte ) ) ).
  " the ORDER BY ... UP TO form is safe here
ENDIF.
```

> `"it is possible to use the method USE_FEATURES of the class CL_ABAP_DBFEATURES to check whether the current database system or a database system accessed using a secondary connection supports ORDER BY clauses in subqueries"`

## Trap 4: the column name list must be complete — and `*` makes it a time bomb

A CTE may rename its columns positionally, in a parenthesized list after the name. The
names `"work like the alias names defined in the SELECT list using AS and overwrite these names"`,
which makes the list the cleanest way to name the output of expressions and aggregates.
Two syntax details bite immediately: `"If a name list is specified, it must contain a name for each column of the common table expression"`
— all or nothing, no partial renaming — and the blanks are mandatory, exactly as in
every other parenthesized ABAP SQL construct:
`"At least one blank must be placed after the opening parenthesis and in front of the closing parenthesis."`

The trap is the combination with `*`. It is allowed, and the documentation flags the
consequence itself:

> `"It is possible to specify a name list if all columns with * are selected in the SELECT list of the subquery. This can lead to syntax errors if the data source of the subquery is subsequently extended."`

That is a program which compiles today, is never edited, and stops compiling because
somebody appended a field to a table — the count no longer matches. Name the columns in
the `SELECT` list instead of using `*` when a name list is in play.

One more naming rule, for the `UNION` case: with a set operator in the subquery,
`"the column names are determined by the SELECT list of the first SELECT statement"`.
The leftmost branch names the result, so reordering branches renames columns.

## Trap 5: `FOR ALL ENTRIES` is the one clause the main query cannot have

> `"All clauses are possible as in a standalone SELECT statement except for FOR ALL ENTRIES"`

This is worth a line of its own because the advice usually runs the other way: when
`FOR ALL ENTRIES` is slow, or when its implicit `DISTINCT` has eaten rows, the suggested
fix is to express the driver set in SQL. You can do that — put the driver set in a CTE
and join it — but you cannot keep `FOR ALL ENTRIES` *and* gain a CTE in the same
statement. It is a rewrite, not an addition.

Related: an internal table can still be a data source inside a CTE via `FROM @itab`, but
`"If an internal table @itab with elementary row type is accessed in the FROM clause of a common table expression, the SELECT list cannot be * or contain data_source~*"`
— a table of plain `carrid` values must list its column explicitly.

## Trap 6: `ENDWITH`, and do not nest it

The main query opens a `SELECT` loop under exactly the same conditions as a standalone
`SELECT` — a work area target rather than an internal table — and then:

> `"ENDWITH has exactly the same meaning for WITH ... SELECT as ENDSELECT for a standalone SELECT loop."`

So `INTO TABLE @lt_x` needs no terminator, `INTO @ls_x` must be closed with `ENDWITH`,
and the usual loop advice follows it: `"In particular, WITH loops should not be nested."`

The static form may also follow `OPEN CURSOR`, which gives you a cursor over a CTE-based
query; the dynamic form may not (see Trap 8).

## Trap 7: a `WITH` over a database table bypasses the table buffer

> `"Only WITH statements that access only internal tables but no database tables can be processed by the ABAP SQL in-memory engine. If a database table is accessed at any position of the statement, the ABAP SQL statement bypasses the table buffer and an internal table accessed by FROM @itab must be transported to the database."`

Two separate costs in one sentence. The buffer bypass is the same rule joins have, and it
applies to the **whole statement** — one CTE over a real table switches buffering off for
every source in it, including the buffered customizing table you joined in the main
query. And the transport has a hard ceiling: `"This is only possible for one internal table per ABAP SQL statement."`
Two internal tables in one `WITH` over a database table do not work, no matter which
CTE each one sits in.

## Trap 8: the dynamic form takes the main query only

`WITH (select_syntax)` exists, and it is not simply "the static form as a string":

> `"In contrast to the static form, the syntax in select_syntax must not contain the definition of CTEs. It may contain the main query only."`

So the dynamic form is best read as the fully dynamic `SELECT` that ABAP SQL otherwise
lacks — `"a fully dynamic SELECT statement that can be compared to an ADBC query that is also passed as a string"`
— and not as a way to build CTEs at runtime. Bad syntax is a runtime problem, not a
syntax-check one: `"Invalid syntax raises a catchable exception of class CX_SY_DYNAMIC_OSQL_ERROR"`.
It also `"cannot be used after the statement OPEN CURSOR"`, where the static form can.

If you need runtime variability *with* CTEs, the static form accepts dynamic tokens in
its clauses — with one consequence that is easy to trip over:

> `"If the clauses of the subquery contain dynamic tokens, the common table expression can only be used in other dynamic tokens of the WITH statement."`

Make one CTE subquery dynamic, and every reference to that CTE must become dynamic too.
The change propagates outward through the statement.

The usual rule applies to all of it —
`"If used incorrectly, dynamic programming techniques can present a serious security risk"`
— so anything from outside goes through `CL_ABAP_DYN_PRG` or `escape( )` first.

## Small print

- **Strict mode.** Using `WITH` means `"the syntax check is performed in the strict mode for ABAP release 7.65"`; the dynamic form is checked in the
  [strict mode for 7.96](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_STRICTMODE_796.html).
- **A second CTE-specific database feature exists.** `CL_ABAP_DBFEATURES` also carries
  the constant `CTE_IN_CORRELATED_SUBQUERIES`, for
  `"Access to common table expression in correlated subqueries in ABAP SQL"` — so reading a
  CTE from a *correlated* subquery is a separate capability from reading it in a `FROM`
  clause. And the class no longer covers everything: `"Most of these features are not governed by CL_ABAP_DBFEATURES any more. Note that there is no syntax warning any more if such HANA-only features are used."`
  The exception then surfaces only when the statement goes to a non-HANA database over a
  secondary connection.
- **Set operators are allowed on both levels** — in a CTE subquery and across main
  queries — with the `query_clauses` rules that apply to any union.
- **CDS access control still applies inside a CTE subquery.** If a CDS entity with a CDS
  role is read, only authorized data arrives, and
  `"ABAP programs cannot distinguish whether this is due to the conditions of the SELECT statement, the conditions of the CDS entity, or an associated CDS role"`
  — an empty CTE is not evidence of missing data.
- **`*` in the main query** does not transfer unconverted into a work area, the same rule
  as a standalone `SELECT`.
- **CTEs can replace global temporary tables:** `"If required, common table expressions can also perform the tasks of GTTs"` — no DDIC object, no cleanup, no cross-statement state.
- **Associations can be exposed too**, either the CDS associations of an accessed view
  entity or dedicated CTE associations, for use in path expressions later in the same
  statement.

## Quick reference

| Goal | Write this |
|---|---|
| Aggregate, then join without fan-out | `+agg AS ( ... GROUP BY ... )`, join `+agg` in the main query |
| Select from a subquery | Not possible directly — wrap the subquery in a CTE |
| Name the output of an expression | Name list `+cte( a, b )`, blanks inside the parentheses |
| Reuse one intermediate result twice | One CTE, referenced from two later queries |
| Keep client handling over a CTE | `FROM +cte DECLARE CLIENT mandt` |
| Top-N inside a CTE | `ORDER BY ... UP TO n ROWS` + `CL_ABAP_DBFEATURES` guard |
| Recursive parent-child walk | Not a CTE — use the `hierarchy` addition |
| Loop over the main query | `INTO @ls_wa ... ENDWITH.` |
| Fully dynamic query | `WITH (select_syntax)` — main query only, no CTEs |

## References

- [`WITH` — static and dynamic form, naming, client handling, buffer and strict mode](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWITH.html)
- [`WITH, subquery_clauses` — `ORDER BY`/`UP TO` restrictions and the DB-feature pragma](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWITH_SUBQUERY.html)
- [`WITH, mainquery_clauses` — the `FOR ALL ENTRIES` exclusion](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWITH_MAINQUERY.html)
- [`ENDWITH`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPENDWITH.html)
- [`SELECT, FROM data_source, declare_client` — `DECLARE CLIENT`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_DECLARE_CLIENT.html)
- [`WITH, hierarchy` — the CTE hierarchy, instead of recursion](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWITH_HIERARCHY.html)
- [`WITH, associations`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWITH_ASSOCIATIONS.html)
- [`CL_ABAP_DBFEATURES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCL_ABAP_DBFEATURES.html)
- [`WITH`, common table expressions — executable example](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENWITH_CTE_ABEXA.html)

Related notes in this repo: [SQL Joins](../SQL%20Joins#readme) for the fan-out a CTE
fixes, [Set Operators](../Set%20Operators#readme) for the union a CTE lets you filter
once, [Row Limiting & Ordering](../Row%20Limiting%20and%20Ordering#readme) for
`UP TO`/`OFFSET`/`ORDER BY` on their own,
[For All Entries](../For%20All%20Entries#readme) for the clause the main query cannot
have, [Table Buffering](../Table%20Buffering#readme) for what the bypass costs,
[CDS View Entities](../CDS%20Client%20Handling#readme) for client handling in general,
[CDS Access Control](../CDS%20Access%20Control#readme) for the silently filtered CTE, and
[Dynamic SQL](../Dynamic%20SQL#readme) for the dynamic-token rules.

Worked, runnable examples: [ydj_cte_demo.abap](ydj_cte_demo.abap)
