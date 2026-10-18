# Internal Table Grouping — the work area that is empty, the `GROUP SIZE` you cannot have, and the member loop whose `sy-subrc` is always 0

`LOOP AT itab ... GROUP BY` (7.40 SP08) is the modern replacement for
[`AT NEW` / `AT END OF`](../Control%20Level%20Processing#readme): it needs no
pre-sorting and does not depend on the order of the components in the line type.
What it does have is a **two-phase execution model** and **two mutually exclusive
output bindings**, and almost every surprise below comes from code that was written
for one binding and is reading the other.

The statement runs in two phases, and the distinction matters for everything else:

> "If the addition GROUP BY is specified, the LOOP is processed in two phases:"
>
> - **Grouping** — "In the first phase, all lines determined by the conditions `cond`
>   are read in the processing order described in a loop across lines. **The statements
>   in the statement block between `LOOP` and `ENDLOOP` are not executed during this
>   process.**"
> - **Group Loop** — "In the second phase, a loop is executed across all groups."

So the loop body runs **once per group**, not once per line. The group key expression
is the only thing evaluated per line.

```abap
" Phase 1 evaluates wa-carrid for every line. Phase 2 runs the body once per carrier.
LOOP AT flights INTO DATA(wa) GROUP BY wa-carrid.
  WRITE: / wa-carrid.
ENDLOOP.
```

## Trap 1: the default binding hands you a whole row, and the other one hands you nothing

There are two bindings, chosen by whether you write a target **after** the
`GROUP BY` clause:

| | Written as | What the loop body sees |
|---|---|---|
| **Representative binding** | no `INTO`/`ASSIGNING`/`REFERENCE INTO` after `GROUP BY` | the **first line of the group**, in the `result` target (`wa`/`<fs>`/`dref`) |
| **Group key binding** | `... GROUP BY key INTO group` (or `ASSIGNING`/`REFERENCE INTO`) | the **group key**, in that second target |

Representative binding is the default, and it is a full table row:

> "In each loop pass, the first line of the current group is assigned as a
> representative of its group to the data object or field symbol defined there."

Only the key columns of that row are meaningful for the group. Every other column
holds whatever the first member happened to contain — `wa-fldate` in a loop grouped
by `carrid` is one arbitrary member's date, and nothing says so. Which line that is
depends on insertion order:

> "If the assignment of the lines to their group is defined, the order of the lines
> of a group is based on the time they are assigned to the group. This defines, in
> particular, the first line of each group that is used as a representative in the
> representative binding."

The mirror image is worse. Add a group key binding and the `result` work area stops
being filled:

> "The data object or field symbol of the output behavior defined in `result` for the
> table lines can still be addressed in the group loop but it is either initial after
> the LOOP statement or does not point to a line."

So this compiles and silently reads an initial value, with no warning (and for a
`d` or `n` column the initial value does not even look empty):

```abap
LOOP AT flights INTO DATA(wa) GROUP BY wa-carrid INTO DATA(key).
  WRITE: / key,            " correct: the group key
           wa-fldate.      " ALWAYS INITIAL - wa is not filled in a group key binding
ENDLOOP.
```

*Reading note:* SAP's phrase "initial after the LOOP statement" is read here as
*inside the group loop* — i.e. after the `LOOP` statement has executed, which is the
loop body. The corresponding sentence on the `FOR GROUPS` page states it without the
ambiguity: **"In the group key binding, `wa` or `<fs>` are initial after the `FOR`
expression."** The `group_key` page confirms the opposite case for representative
binding: "This is a representative binding in which the work area `wa` is reused in
the group loop to access the group key."

And you cannot have both. With a representative bound:

> "If a representative is bound to the current group, the associated group key cannot
> be addressed in the group loop."

The practical rule: **group by a derived value → you need the group key binding**
(there is nowhere else the computed key exists). **Group by plain columns → the
representative already carries them.**

## Trap 2: `GROUP SIZE` is rejected in exactly the form people try first

`GROUP SIZE` and `GROUP INDEX` are extra components you declare *inside* a structured
group key:

```abap
LOOP AT flights INTO DATA(wa)
     GROUP BY ( carrier = wa-carrid
                indx    = GROUP INDEX
                size    = GROUP SIZE )
     INTO DATA(key).
  " key-carrier, key-indx, key-size
ENDLOOP.
```

Two preconditions, and the obvious first attempt violates both:

- the group key must be the **structured** form `( k1 = ... k2 = ... )`, not a single
  `GROUP BY wa-carrid`;
- a group key binding must exist — "Before the additional components can be declared,
  a group key binding must be defined in the output behavior `group_result`."

Under representative binding it is not a matter of style, it is impossible:

> "no additional components for `GROUP SIZE` and `GROUP INDEX` can be created for a
> structured group key, since it is impossible to access these components in this
> case."

Also worth knowing: `size`/`indx` are **not part of the key** —
"These components are not part of the group key and are used to store group-specific
information instead". They do not split groups, and `ASCENDING` does not sort by them.

## Trap 3: `GROUP INDEX` is not a display counter

`GROUP INDEX` is the order in which the group keys were **first constructed**, which
is the default group order:

> "The default order of the groups depends on the time their group key is first
> created, which itself can be overridden by an explicit sorting using the additions
> `ASCENDING` or `DESCENDING`."

Add `ASCENDING` and the two part company:

> "If the groups are not sorted using `ASCENDING` or `DESCENDING`, the groups in the
> group loop are processed in the order of the group index. If the groups are sorted
> differently, **the original position is noted in the group index**."

So on a sorted group loop, `key-indx` jumps around — it is a stable identity for the
group, not "group 1, 2, 3 of the output". Print `sy-tabix` or your own counter for
that. The sort itself is a plain `SORT` on the key: "The groups are sorted in exactly
the same way as when the statement `SORT` is used on an internal table whose primary
table key is the group key", with `AS TEXT` behaving as it does there.

## Trap 4: `sy-tabix` means two different things, and neither is "row within the group"

| Where | `sy-tabix` |
|---|---|
| Group loop, **representative** binding | "the value that would be set for the line representing the group in the `LOOP` without grouping" — i.e. the **table index of the first member** |
| Group loop, **group key** binding | "the groups are counted in `sy-tabix`. The first loop pass sets `sy-tabix` to 1 and each subsequent loop pass raises it by 1." |
| Member loop `LOOP AT GROUP` | "the value that would be set for the current line in the `LOOP` without grouping" — the **index in `itab`**, not a position inside the group |

Adding `INTO DATA(key)` to an existing loop therefore silently changes the meaning of
every `sy-tabix` read in its body, from a row number to a group counter. For a
position *within* a group, count it yourself (or use `INDEX INTO` on the `FOR` form,
which has the same split semantics).

`sy-tabix` is restored on exit — "After leaving the loop using ENDLOOP, sy-tabix is
set to the value that it had before entering the loop."

## Trap 5: the member loop sets `sy-subrc = 0` even when it never ran

> "A member loop always sets the system field sy-subrc to 0."

With the reason spelled out:

> "A group loop does not create any empty groups, which means that a member loop is
> always passed as a rule. Only `WHERE` conditions can be used to prevent members of a
> group from being processed. Internally, however, this is not detected until the
> start of the first loop pass, which means that `sy-subrc` is set to 0 in this case
> as well."

So the habitual `IF sy-subrc = 0` after `LOOP AT GROUP ... WHERE ...` is dead code —
it is true whether or not a single member passed the condition. Use a counter, a flag
set inside the loop, or `lines( FILTER #( ... ) )`.

Other member-loop restrictions, all documented: `USING KEY`, `FROM`, `TO` and a
**dynamic** `WHERE` are not allowed after `LOOP AT GROUP`.

## Trap 6: the member loop is impossible if the table was not a data object

This is the one that turns a working loop into a syntax error during a refactor:

> "A member loop `LOOP AT GROUP` is only possible in `LOOP` statements for which the
> internal table `itab` is specified **directly as a data object and not as the result
> of a call or expression**. If the table is specified as the result of a call or
> expression, only the group keys exist in the group loop and no longer the groups
> themselves."

```abap
LOOP AT get_flights( ) INTO DATA(wa) GROUP BY wa-carrid INTO DATA(key).
  LOOP AT GROUP key INTO DATA(m).   " not possible - the groups do not exist here
  ENDLOOP.
ENDLOOP.
```

Replacing the variable `lt_flights` with the call `get_flights( )` — or wrapping it
in a `FILTER`/`VALUE` expression — removes the members. Assign to a variable first,
then group over the variable.

Two more scope rules in the same family:

- the group name is **lexically** scoped to that loop: "`LOOP AT GROUP` is in
  particular not possible in procedures called from a group loop, even if the data
  object or field symbol defined by the output behavior can be accessed here."
- the name must be written exactly as bound: "a field symbol with angle brackets
  specified after `ASSIGNING` and a data reference variable **without** dereferencing
  operator `->` specified after `REFERENCE INTO`" — so it is `LOOP AT GROUP dref`,
  never `LOOP AT GROUP dref->*`, even though the group key expression itself uses
  `GROUP BY dref->*`.

At the end of the loop the binding is gone: "At the end of the group loop, the
grouping is canceled and a specified data object is initialized or a field symbol no
longer has a group key assigned to it."

## Trap 7: the table is frozen for the whole group loop — unless you give up the members

> "The internal table itab cannot be modified in the group loop unless the addition
> WITHOUT MEMBERS is specified."

`WITHOUT MEMBERS` is the performance variant ("used to improve performance in all
cases where the content of the groups is not required"), and it is a package deal:

- "The output behavior cannot be defined for a line of the group as a representative
  and a group key binding must be defined."
- "The group loop cannot contain a nested member loop `LOOP AT GROUP`."
- "The internal table `itab` can be modified in the group loop."

`GROUP SIZE`/`GROUP INDEX` survive it — "The additional components can still be
evaluated even if the addition `WITHOUT MEMBERS` is used and the group members cannot
be accessed" — which makes `WITHOUT MEMBERS` + `GROUP SIZE` the cheap way to get a
pure count per key. (Note that the `result` work area is still required, because the
group key expression refers to it.)

## There is no `HAVING`, and `GROUP SIZE` is the only implicit aggregate

Unlike SQL's `GROUP BY`, nothing is totalled for you:

> "Implicitly, no further values are created that match the results of aggregate
> expressions when `GROUP BY` is used in the ABAP SQL statement `SELECT`, except in
> the component `gs` with the right side `GROUP SIZE`."

The documented substitutes are constructor expressions over the members —
`REDUCE` with `FOR ... IN GROUP` for aggregation, and `FILTER` where SQL would use
`HAVING`:

```abap
LOOP AT flights INTO DATA(wa) GROUP BY wa-carrid ASCENDING
     ASSIGNING FIELD-SYMBOL(<carrier>).
  DATA(seats) = REDUCE i( INIT s = 0
                          FOR f IN GROUP <carrier>
                          NEXT s = s + f-seatsocc ).
ENDLOOP.
```

Also absent, all by design: `SUM` and `AT` group level processing
("No group level processing with the statement `AT` is possible in a `LOOP` with the
addition `GROUP BY`", and the same for `LOOP AT GROUP`), `TRANSPORTING NO FIELDS`
(explicitly excluded when `GROUP BY` is used), and mesh paths. The group key type is
also static — "The data types of key or key1, key2, ... must be known
completely and statically" — so there is no dynamic `GROUP BY` for internal tables.

## The expression form, and where it differs

`FOR GROUPS ... OF` is the same machinery inside a constructor expression, with three
differences that bite:

- **Binding is chosen by presence of a name**, not by a keyword: "Specifying `group`
  or `<group>` (optional) results in the group key binding […] If `group` or
  `<group>` is not specified, the representative binding applies."
- **No inline declaration for the group key**: "If a constructor expression contains a
  `FOR` expression with group key binding and the group key is to be used as the
  result of the constructor expression, a suitable data type or a data object with
  this type must exist for this expression explicitly. It is not possible to derive
  this type here using an inline declaration as in `LOOP AT`." So the convenient
  `INTO DATA(key)` has no equivalent — declare the type.
- **`WHERE` needs parentheses.** The member iteration is
  `FOR wa IN GROUP group [WHERE ( log_exp )]`, while the statement form is
  `LOOP AT GROUP group ... [WHERE log_exp]`. Copying a condition between the two forms
  is a syntax error in one direction.

`INDEX INTO idx` mirrors `sy-tabix`: the representative's table index under
representative binding, "the groups are counted from the value 1" under group key
binding — and `idx` "cannot be addressed in `group_key`".

## When to use which

- Table already sorted by the key, and you want `SUM`'s automatic totals or you are
  editing classic report code → [`AT NEW`/`AT END OF`](../Control%20Level%20Processing#readme).
- Anything new, any derived key, any unsorted table → `GROUP BY`. "Unlike in group
  level processing, a grouping with `GROUP BY` does not depend on the structure of the
  lines and the processing order of the loop."
- Counts per key only, or you need to modify the table in the loop → add
  `WITHOUT MEMBERS`.
- Result is a table or a single aggregate → `FOR GROUPS ... OF` inside
  `VALUE`/`REDUCE` instead of a statement loop.

Worked, runnable examples: [ydj_group_by_demo.abap](ydj_group_by_demo.abap)

Related: [Control Level Processing](../Control%20Level%20Processing#readme) (the
predecessor), [Loop Modification](../Loop%20Modification#readme) (why the table is
frozen), [Internal Table Keys](../Internal%20Table%20Keys#readme),
[Sorting & Deduplication](../Sorting%20and%20Deduplication#readme),
[Field Symbols](../Field%20Symbols#readme).

**Transcription note.** Quotes are verbatim from the ABAP keyword documentation, with
four deliberate deviations: SAP's inline hyperlink markup inside quoted sentences is
dropped (it links to the keyword docs' own pages); **bold emphasis inside quotes is
added here**, SAP's own prose uses bold only for the `Grouping`/`Group Loop` labels;
the sentence on `GROUP SIZE`/`GROUP INDEX` not being part of the key ends in a colon
in the original, where it introduces two bullets, and is quoted here without it; and
the two-phase description is quoted as SAP's lead-in plus its two bullets rather than
flattened into one sentence. SAP's `data(key)` lowercase declaration operator in the
`GROUP SIZE` example is written `DATA(key)` in the snippets here.

---

**References**

- [ABAP keyword docs — LOOP AT itab, GROUP BY](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPLOOP_AT_ITAB_GROUP_BY.html)
- [ABAP keyword docs — LOOP AT itab, group_result](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPLOOP_AT_ITAB_GROUP_BY_BINDING.html)
- [ABAP keyword docs — LOOP AT itab, group_key (GROUP SIZE / GROUP INDEX)](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/loop-at-itab-group-key)
- [ABAP keyword docs — LOOP AT GROUP](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPLOOP_AT_GROUP.html)
- [ABAP keyword docs — LOOP AT itab, result](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPLOOP_AT_ITAB_RESULT.html)
- [ABAP keyword docs — FOR GROUPS ... OF](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENFOR_GROUPS_OF.html)
- [ABAP keyword docs — FOR ... IN GROUP](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENFOR_IN_GROUP.html)
- [ABAP keyword docs — Internal Tables in ABAP Release 7.40, SP08](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENNEWS-740_SP08-ITAB.html)
