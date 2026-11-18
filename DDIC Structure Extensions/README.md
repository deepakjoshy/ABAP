# DDIC Structure Extensions | The Category That Punishes You For Being Generous, the Level Numbers That Are Off By One & the Field Order That Is Not the Database Order

Adding one `ZZ` field to a standard SAP table is the most routine job in
ABAP, and it is a *two-object* change: the table stays untouched and a
second Dictionary object (an **append structure**, or a **customizing
include** that SAP reserved for you) carries your field. The mechanism is
simple. What catches people is the *classification* bolted on top of it,
because it works backwards from intuition:

- The **most permissive** enhancement category is the one that makes your
  own programs throw warnings and, after someone actually uses it, syntax
  errors. Being generous to a future customer is what breaks you.
- The level numbers in the documentation (**1-5**) are **not** the values
  stored in the Dictionary (**0-4**), so a report that filters on the
  documented number reads the wrong category.
- The field order in SE11 is **not** the column order on the database, and
  SAP documents this twice as the normal consequence of appending.

None of this shows up when you add the field. It shows up in a program
somebody else wrote, after an upgrade, or in a copy of the table.

Related notes:
[Runtime Type Services](../Runtime%20Type%20Services#readme) - how an
include looks from RTTI, and the `get_components( )` vs `components`
split the demo here relies on;
[String Processing](../String%20Processing#readme) - offset/length access,
which is the construct the enhancement category exists to police;
[Corresponding Operator](../Corresponding%20Operator#readme) - the
component-name-based alternative to positional assignment;
[Enhancement Framework](../Enhancement%20Framework#readme) - the *code*
side of the same modification-free idea;
[CDS Annotations](../CDS%20Annotations#readme) - the annotation syntax the
modern extensibility control is written in;
[Native SQL](../Native%20SQL#readme) - the one place where DDIC field
order really does stop protecting you.

---

## 0. The two mechanisms, and who owns which

| | Append structure | Customizing include |
|---|---|---|
| Who creates it | You, in your system | SAP reserves the name; you fill it |
| Name | Customer namespace (`Z*` / `Y*`) | `CI_*` customers, `SI_*` partners |
| Reach | One target only | Every table that includes it |
| Position | End of the structure | Wherever SAP put the slot |
| Needs SAP to plan ahead | No | Yes |

On appends, the keyword documentation is exact about the cardinality:

> An append structure is assigned to exactly one table or structure. There
> can, however, be more than one append structure for a table or structure.

So *many appends to one table* is fine; *one append on many tables* is not.
The documented workaround is indirection, and it is worth knowing because
it is how you keep ten tables consistent:

> The same structure can be appended to multiple DDIC database tables or
> structures by including it in the individual append structures as an
> include structure.

A customizing include is the opposite shape by design:

> A customizing include can be included in multiple DDIC database tables or
> DDIC structures. Its extension is then applied to all DDIC database
> tables or DDIC structures in which it is included.

And it survives upgrades differently - *better*, in the one way that
matters, because SAP re-inserts your fields for you:

> If a customizing include is used to add fields to a standard DDIC
> database table or DDIC structure, these fields are inserted automatically
> into DDIC structures or DDIC database tables delivered by SAP in an
> upgrade.

The reason the `CI_` structures in a fresh system look broken (they exist,
they are empty, nothing includes them visibly) is documented too:

> These customizing includes in SAP-delivered objects are usually empty.
> They are not linked with existing structures, they are only intended to
> reserve names.

---

## 1. The headline: the generous category is the one that breaks your code

The enhancement category is a *promise to the compiler* about what an
extension is allowed to contain. The syntax check then reads that promise
and warns about every line in every program that would stop working if the
promise were cashed in:

> This classification is used in the syntax check for ABAP programs to
> create a warning at all positions where a program works with structures,
> and where later structure extensions could cause syntax errors or changed
> program behavior.

The five categories, verbatim (the *Level* column is the documentation's
own numbering - see section 2 before you use it in code):

| Level | Category | Meaning (verbatim) |
|---|---|---|
| 1 | Not classified | "The structure does not have an enhancement category." |
| 2 | Cannot be enhanced | "The structure must not be extended." |
| 3 | Can be enhanced (character-like) | "All structure components and their extensions must be character-like and flat." |
| 4 | Can be enhanced (character-like or numeric) | "All structure components and their extensions must be flat." |
| 5 | Can be enhanced (deep) | "All structure components and their extensions can have any data type." |

Note what level 4 actually says: not *character-like or numeric*, but
**flat**. The category name is about the fields you may add; the rule is
about depth. The older SAP Library page spells out the type sets:

> Character-type includes elementary types C, D, N, and T; numeric includes
> the elementary types F, I, P, and X. The deep types STRING and XSTRING
> are not supported.

Now the part that inverts intuition. The warnings are graded, and grade **A**
is not a warning at all in waiting - it is a syntax error waiting:

| Grade | Check | Meaning (verbatim) |
|---|---|---|
| A | Syntax check | "An extension that completely exhausts the enhancement category of the affected structure produces a syntax error." |
| B | Extended check | "Permitted extensions can produce syntax errors, but not always." |
| C | Extended check | "Permitted extensions cannot produce syntax errors, although changes to program behavior do cause semantic problems." |

So the chain is: *you* classify your flat structure as **Can be enhanced
(deep)** because it feels generous and future-proof -> every program doing
`struc+off(len)` on it is now flagged -> the first customer who appends a
`STRING` makes those programs **not compile**. The keyword documentation
walks exactly this path with its own example:

```abap
DATA: my_struc TYPE ddic_struc,
      str TYPE string,
      off TYPE i,
      len TYPE i.
...
str = my_struc+off(len).
```

> If the structure were to be extended by a deep component after the
> program was delivered, the program would have incorrect syntax and would
> no longer be executable. In this case, therefore either the structure
> `ddic_struc` must be classified in the ABAP Dictionary as *Can be
> enhanced (character-like)* or else the offset/length cannot be specified
> in the program.

Read that resolution again: the documented fix for a *program* problem is
to make the *structure* **less** extensible. The category is not a courtesy
to customers, it is a contract with your own code.

The mechanism underneath is the fragment view - the grouping of adjacent
components of like type that ABAP uses to decide whether two structures may
be assigned or compared:

> These types of changes cause problems if the extensions change the
> structure fragment view.

That is why a *purely additive* change at the end of a structure can break
an assignment between two structures that you never touched:

> if a purely character-type structure is enhanced by inserting numeric or
> deep components, it can lose its character-type nature

Two more things the old page states that are easy to miss:

- **Containment rule.** "For structures and tables with includes or
  substructures, the enhancement categories of these includes and
  substructures cannot be lower than those of the initial structure." You
  cannot wrap a permissive include in a restrictive structure and call it
  contained.
- **No runtime safety net.** "All structure enhancement checks are only
  effective in programs with an active Unicode check. Only static checks
  are carried out and no checks at runtime." Nothing re-checks this when
  the program runs.

---

## 2. The level numbers in the doc are not the values in the Dictionary

The documentation numbers the categories **1 to 5**. The value actually
stored on the object is `DD02L-EXCLASS`, whose data element is `DDRANKING`
("DD: Ranking for include and subtype extension"), and that domain's fixed
values are **0 to 4**:

| `DD02L-EXCLASS` | Domain text | Documentation calls this |
|---|---|---|
| `0` | Not classified | Level 1 |
| `1` | Cannot Be Enhanced | Level 2 |
| `2` | Can be enhanced (character-type) | Level 3 |
| `3` | Can be enhanced (character-type or numeric) | Level 4 |
| `4` | Can Be Enhanced (Deep) | Level 5 |

So a clean-up report written from the documentation -
`WHERE exclass = @lc_not_classified` with `lc_not_classified = '1'` - does
not list unclassified tables. It lists the tables somebody carefully set to
**Cannot be enhanced**, which is the opposite population. The off-by-one is
silent in both directions and the result set looks plausible either way.

*Honesty flag:* the 1-5 levels above are verbatim from SAP Help; the 0-4
fixed values come from the published metadata of domain `DDRANKING`, not
from a Help page. Part 1 of the demo prints the raw `EXCLASS` next to both
readings so you can confirm it against your own `SE11` in thirty seconds
rather than taking this note's word for it.

Two neighbouring fields are worth knowing while you are in `DD02L`:

- `DD02L-WRONGCL` - "Enhancement category is incorrect". The *declared*
  category and the category *implied by the content* can drift apart, which
  is exactly what an upgrade or a transport of a reclassified include does
  to you. This flag is how the system remembers.
- `DD02L-SQLTAB` - "Name of an SQL table or an appended table". On a row
  with `TABCLASS = 'APPEND'` (domain `TABCLASS`, fixed value *Append
  structure*) this is the table being appended to - which makes
  *what is appended to this table, and by whom?* a one-line `SELECT`
  instead of a trip through `SE11`. Part 2 of the demo does it.

---

## 3. Content sets the ceiling, so the category is not freely chosen

You cannot declare a structure more restrictive than what it already
contains. The implicit category is derived, and the derivation is
documented in the data element documentation of DE_IMPLICIT_EXCLASS
(Implicit Enhancement Category):

> If the object contains at least one numeric type or a substructure or a
> component (field has structure/table/view as type) that can be enhanced
> numerically, the object itself can no longer be enhanced character-type,
> but can, at most, be enhanced character-type or numerically.

> If the object contains a deep component (string, reference, or table
> type) or a substructure or component that is marked as can be enhanced in
> any way, the object itself is also marked can be enhanced in any way.

> If the object does not contain any substructure or component that is
> marked can be enhanced, you can choose cannot be enhanced.

Consequences that bite in that order:

1. **One `STRING` column promotes the whole structure to the most
   permissive category** - and section 1 says that is the category that
   flags your offset/length code. The deep field you added for convenience
   changed the compile-time contract of every consumer.
2. **The drift is asymmetric.** The implicit category can only become
   *more* general as content is added, while the declared one sits still -
   so inconsistencies always appear as *declared is stricter than reality*,
   never the reverse.
3. **An upgrade can create the inconsistency without anyone editing
   anything**, because the content that moved is inside an SAP include you
   merely reference.

Part 4 of the demo computes the implied ceiling from live RTTI component
data and prints it next to the declared value, which is the check this
section is really about.

---

## 4. Classic says prefix, modern says suffix - and the defaults disagree

The classic rule for append fields is a **prefix**:

> The fields of an append structure must lie in the customer namespace,
> that is, the field names must begin with ZZ or YY.

The modern rule, enforced by the owner of the extended object, is a
3-character **suffix**:

```abap
@EndUserText.label : 'Used for demo of C0 Released API'
@AbapCatalog.enhancement.category    : #EXTENSIBLE_ANY
@AbapCatalog.enhancement.fieldSuffix : 'EMO'
@AbapCatalog.enhancement.quotaMaximumFields : 250
@AbapCatalog.enhancement.quotaMaximumBytes  : 2500
@AbapCatalog.enhancement.quotaShareCustomer : 50
@AbapCatalog.enhancement.quotaSharePartner  : 50
define structure demo_released_api { ... }
```

...and the extension then has to satisfy **both** conventions at once, which
is why real extension fields end up looking like `zz_quantity_emo`: `ZZ` at
the front for the classic namespace rule, the owner's suffix at the back
for the annotation. SAP's own released-API example does exactly that.

The quota annotations are the other half of the contract - the owner
*reserves* capacity rather than leaving it to first-come-first-served:
`quotaMaximumFields` (documented range 100-1000), `quotaMaximumBytes`
(1000-3500), and `quotaShareCustomer` / `quotaSharePartner`, currently only
valid as `50` each. Exceeding a quota is a *definition-time* failure for
the extender, which is the point: the limit is discovered when the append
is written, not when the table gets wide.

**The default flips between tools.** In `SE11` the system proposes the most
permissive category for a new object ("the system proposes the category can
be enhanced in any way as standard value" - SAP Community); in ADT the
Dictionary DDL template ships `#NOT_EXTENSIBLE` and SAP's own training
material instructs you to *replace the default value* `#NOT_EXTENSIBLE`.
Same concept, opposite starting point - so *I left the default* means
*maximum exposure* in one tool and *no extensibility at all* in the other.

One more asymmetry: an append can **add** a value help or a foreign key
where none exists, but it can never **change** one:

> A binding of a check table or search help that already exists for a field
> of the DDIC database table cannot be modified by an append structure.

ADT states the same rule as a positive: you may only add a value help "if
no value help exists for the original component".

---

## 5. The restrictions you discover at activation time

- **Transparent tables only.** "Append structures can only be appended to
  transparent tables." Pooled and cluster tables are out.
- **Long fields block appending entirely**, for a structural reason:
  "No append structures can be appended to DDIC database tables with fields
  of the type `LCHR` or `LRAW`, since these fields must always be the last
  field of the table." Appending puts your field last; the long field
  already is. The `SE11` procedure page widens the list to `VARC` as well.
- **The append itself must be flat**: "each field of the append structure
  must either refer to a data element or be directly assigned a data type,
  length, decimal places and short text".
- **Indexes work one way only.** "Any fields appended to a DDIC database
  table using an append structure can be added to its secondary indexes. No
  secondary index can be defined for the append structure itself." The
  index lives on the table; your `ZZ` field may join it.
- **Activating the append activates the table**: "The system activates the
  table when you activate the append structure." That is also the moment a
  database adjustment can be triggered on a table you did not open.
- **No new key fields.** Appended components land at the end of the
  structure, and key fields must be a leading block - so an append cannot
  extend the primary key. *Sourcing note:* this follows from the documented
  position rule and is stated flatly in SAP Community answers, but I did not
  find it as a sentence in the keyword documentation, so treat it as
  well-established practice rather than a quoted rule.

---

## 6. The Dictionary field order is not the database column order

This is documented three times in three places, which is a good sign it
surprises people. On appending:

> Any existing tables are not adjusted, which can put the fields in the
> dictionary in a different order from the order on the database.

On customizing includes:

> If a customizing include is extended in a transparent DDIC database
> table, no adjustment takes place. As a result, the order of fields in
> ABAP Dictionary and on the database might differ.

And as a general property, with the reason it is tolerated:

> The order of table fields in transparent tables in the ABAP Dictionary
> may be different from the order of the columns of the physical database
> table on the database. This means that modifying the order of table fields
> does not necessarily require an adjustment.

`DD03L` carries both numbers side by side - `POSITION` and `DBPOSITION`,
both labelled "Position of the field in the table" - and part 3 of the demo
prints the rows where they disagree. ABAP SQL is unaffected, because it
addresses columns by name. What is affected is everything that addresses
them positionally: Native SQL / ADBC written as `INSERT INTO t VALUES`
without a column list, external tooling and DB-level exports, and anything
reading a dumped row by offset. See the
[Native SQL](../Native%20SQL#readme) note for the LUW side of that door.

---

## 7. Copying the table dissolves the append

> When a DDIC structure or DDIC database table with an append structure is
> copied, the appended fields, foreign keys, and search helps become real
> elements of the target of the copy.

*Copy `MARA` to `ZMARA` so we can experiment* therefore produces an object
where your appended fields are ordinary fields - no longer an enhancement
of anything. Two consequences follow immediately: the append is no longer
the single place to change those fields, and the copy is frozen in time -
future appends to the original, including SAP's own upgrade changes, do not
reach it. The copy looks identical on the day it is made, which is the
whole problem.

The upgrade behaviour of a real append is the opposite, and is the reason
the mechanism exists:

> After an upgrade, the append structures are again appended to tables
> modified by SAP.

---

## 8. What activation actually does to existing rows

Adding a field to a populated table is usually harmless, but the
neighbouring operations in the same dialog are not. The documented
adjustment cases, with the two that lose data:

- A client column is inserted - "the data of the table is copied to all
  clients listed in the client table `T000`".
- Fields are deleted - "When key fields are deleted, rows can be lost."
- Fields are renamed - and this one is the trap, because *rename* sounds
  like metadata: "The field with the old name is deleted and a field with
  the new name is appended. This leads to the loss of the data in column
  with the old field name." There is no rename at the database level.
- Technical properties of table fields are changed.

And the one that quietly contradicts a DDIC setting you may have relied on:

> In adjustments, initial fields are filled with their type-dependent
> initial value, regardless of the flag for initial values.

---
## 9. In ADT, the append has no source code to version

The source-code form is `EXTEND TYPE`:

```abap
@EndUserText.label : 'Demo append structure'
@AbapCatalog.enhancement.category : #EXTENSIBLE_CHARACTER_NUMERIC
extend type demo_structure with demo_append_structure {
  comp3 : dats;
  comp4 : tims; }
```

...but the file you are editing is a view, not an artifact:

> The source code of an append structure is not saved and transported.
> Instead, the source code of an existing append structure is generated
> from the metadata of the associated system tables.

So a DDL text you diff, review or paste into a ticket is a *rendering* of
the `DD02L` / `DD03L` rows, re-derived each time. Formatting and comments in
it are not durable, and the authority is the metadata. SAP adds that this is
a genuine choice of tool, not a migration: "Each property of an append
structure can be defined using either `EXTEND TYPE` or in the transaction
`SE11`."

---

## Quick checklist

- Classify a new structure as **restrictively** as its content allows, not
  as generously as you can. Generosity is paid for in grade-A warnings in
  other people's programs.
- Never filter `DD02L-EXCLASS` on the documented level number. The stored
  values are `0`-`4`; the documentation's levels are `1`-`5`.
- Check `DD02L-WRONGCL` after an upgrade before trusting any declared
  category.
- One deep component (`STRING`, reference, table type) forces the most
  permissive category on the whole structure. Decide whether you want that
  before adding it.
- Append field names: `ZZ`/`YY` prefix *and* the owner's `fieldSuffix` if
  one is declared.
- Expect `SE11` order and database column order to differ after any
  append. Address columns by name; audit anything positional.
- Do not copy a table to *preserve* an enhancement - copying turns the
  append into plain fields and cuts it off from future changes.
- An append cannot add a key field, cannot change an existing search
  help or check table binding, and cannot be added to a table holding
  `LCHR` / `LRAW` / `VARC` at all.

---

## Sources

- [DDIC - Enhancement Category of Structures](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/ABENDDIC_STRUCTURES_ENH_CAT.html) - the 1-5 level table, the A/B/C warning grades and the offset/length example.
- [DDIC - Append Structures](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/ABENDDIC_APPEND_STRUCTURES.html) - cardinality, transparent-table and `LCHR`/`LRAW` restrictions, secondary indexes, the copy rule, the field-order consequence, upgrade behaviour.
- [DDIC - Customizing Includes](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/ddic-customizing-includes) - `CI_`/`SI_` naming, multi-table reach, automatic re-insertion at upgrade.
- [Structure Fragment View](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/structure-fragment-view) - what a fragment is, and the worked byte layout.
- [Structure Enhancements (SAP Library)](https://help.sap.com/doc/saphelp_nw73ehp1/7.31.19/en-US/6e/e3806dd38911d5994400508b6b8b11/content.htm) - the C/D/N/T vs F/I/P/X type sets, the containment rule, Unicode-check-only scope.
- [Adding an Append Structure (SAP Library)](https://help.sap.com/saphelp_snc700_ehp04/helpdata/en/cf/21ebc9446011d189700000e8322d00/content.htm) - `ZZ`/`YY` field prefix, flatness requirement, `VARC`/`LCHR`/`LRAW` prerequisite, activation side effect.
- [DDIC - Adjusting Database Tables](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/ddic-adjusting-database-tables) - the four adjustment cases, the rename-loses-data rule, initial values vs the initial-value flag.
- [DDIC - Dictionary DDL for Structure Extensions](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/ddic-dictionary-ddl-for-structure-extensions) and [DDIC DDL - EXTEND TYPE](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/ddic-ddl-extend-type) - `EXTEND TYPE` syntax and the not-transported source.
- [Append Structures (ADT user guide)](https://help.sap.com/docs/abap-cloud/abap-development-tools-user-guide/append-structures) - the value-help / foreign-key add-only rule.
- [C0 Developer Extensibility for ABAP Dictionary Objects](https://community.sap.com/t5/technology-blog-posts-by-sap/c0-developer-extensibility-for-abap-dictionary-objects/ba-p/13529950) (SAP blog) - the six extensibility annotations with their value ranges.
- [Extending Dictionary Objects](https://learning.sap.com/courses/building-data-models-with-the-abap-dictionary-and-abap-core-data-services/extending-dictionary-objects_b0c9bfa6-d415-408c-baed-2f15fb3a977f) (SAP Learning) - annotation semantics, extension includes, and the ADT `#NOT_EXTENSIBLE` starting point.
- [Enhancement Category (SAP Community)](https://community.sap.com/t5/application-development-and-automation-discussions/enhancement-category/m-p/2413434) - the implicit-category derivation rules and the `SE11` default proposal.
- Data element `DE_IMPLICIT_EXCLASS` (Implicit Enhancement Category) - the three implicit-derivation rules quoted in section 3.
- Domain `DDRANKING` and table `DD02L` / `DD03L` field lists (se80.co.uk) - the stored `0`-`4` values, `WRONGCL`, `SQLTAB`, `POSITION` vs `DBPOSITION`.
