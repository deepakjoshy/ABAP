# CDS Access Control (DCL) | The Protection That Stops One Layer Up, the Rules That Can Only Widen & the User With `*`

ABAP CDS has its own data control language. A **CDS role**, written in DCL
source code in ADT, attaches **access rules** to a CDS entity, and from then
on every ABAP SQL read of that entity gets the rule's condition ANDed onto
whatever the program asked for. No statement in the calling program changes,
and nothing in the ABAP source hints that it happened.

That invisibility is the whole subject of this note. Every item below is a
documented behaviour where the result is *fewer or more rows than you think*,
and there is no exception, no `sy-subrc`, and usually no syntax error either.

## The shape of it

```
// the entity, in DDL
@AccessControl.authorizationCheck: #MANDATORY
define view entity YDJ_CARR_VE
  as select from scarr
  { key carrid, carrname, currcode }

// the role, a separate DCL object
@MappingRole: true
define role YDJ_CARR_VE_ROLE {
  grant select on YDJ_CARR_VE
    where (carrid) = aspect pfcg_auth(S_CARRID, CARRID, ACTVT = '03')
        and currcode = 'USD';
}
```

Three things are already worth noting. `@MappingRole: true` is **mandatory**,
and it assigns the role to *every* user in *every* client -- a CDS role is
not something you grant to anybody. It is always on, and the user-specific
part happens inside the conditions. The role is a **separate repository
object** from the entity it protects, so the two travel in different
transports. And `#MANDATORY` is a deliberate choice, not the default.

## 1. The default annotation means "no protection, and no warning"

`@AccessControl.authorizationCheck` has five values, and only one of them
notices that the protection is missing:

| Value | No access control exists | An access control exists |
|---|---|---|
| `#NOT_REQUIRED` (**default**) | every user has full access | it is evaluated |
| `#CHECK` | every user has full access, **plus a syntax warning** | it is evaluated |
| `#MANDATORY` | **runtime error** when the entity is accessed | it is evaluated |
| `#NOT_ALLOWED` | full access | **ignored at runtime**, warning only |
| `#PRIVILEGED_ONLY` | same as `#CHECK` for ABAP SQL | same as `#CHECK` for ABAP SQL |

The value almost everybody writes is `#CHECK`, and the docs are explicit that
its runtime behaviour is **identical** to `#NOT_REQUIRED`: the only difference
is a syntax check warning in the entity. So if the DCL object is never
written, or is deleted, or fails to arrive in a transport, the entity serves
every row to every user and the only trace is a warning in a *different*
object that nobody re-activates.

`#MANDATORY` is the only value that turns a missing access control into a
failure -- the docs recommend it precisely so that "accidental removal of the
access control must not remain unnoticed".

`#PRIVILEGED_ONLY` is a trap of its own: it is only honoured by dedicated
frameworks such as SADL, and for plain ABAP SQL it behaves like `#CHECK`. The
docs say customers should not use it unless told to.

## 2. Protection does not reach the next layer up

This is the one to remember:

> When a CDS entity is used as a data source in another CDS entity, its access
> controls are not considered when the wrapping entity is accessed. CDS access
> control only applies to the entry level entities accessed by ABAP SQL.

So a thin view on top of a protected view is an unprotected copy of it:

```
@AccessControl.authorizationCheck: #NOT_REQUIRED
define view entity YDJ_CARR_WRAP
  as select from YDJ_CARR_VE      // protected -- but not here
  { key carrid, carrname, currcode }
```

Nothing warns about this. The wrapper is a perfectly ordinary view, and the
author may not even know the source entity has a role. There is **no
automatic inheritance** of access control to higher layers of a data model,
which means every entity a program selects from directly needs its own role.

The explicit opt-in is an inheritance condition:

```
@MappingRole: true
define role YDJ_CARR_WRAP_ROLE {
  grant select on YDJ_CARR_WRAP
    where inheriting conditions from entity YDJ_CARR_VE;
}
```

`INHERITING CONDITIONS FROM ENTITY` pulls in the source entity's conditions;
`INHERITING CONDITIONS FROM SUPER` is how a customer rule keeps the
SAP-delivered conditions while adding its own. The older `INHERIT role FOR
GRANT SELECT ON entity` rule still exists but the docs say inheritance
*conditions* should be used instead of inheritance *rules*.

Inheritance has its own sharp edge: if the source conditions later use an
element the target does not have, the target becomes invalid. `WITH OPTIONAL
ELEMENTS ( element DEFAULT FALSE )` downgrades that to a warning. Pick the
default carefully -- `DEFAULT FALSE` is the secure one, `DEFAULT TRUE`
declares that it is temporarily acceptable for access control to ignore that
element, and optional elements are forbidden inside `NOT` so a secure
`DEFAULT FALSE` cannot be flipped to true by negation.

## 3. Access rules are OR-ed, so adding a role can only widen

Multiple access rules for one entity -- whether they sit in the same role or
in different roles in different packages -- are combined with a logical **or**
by default. `COMBINATION MODE OR` is the default and need not be written.

This inverts the instinct from classic authorizations. Writing a second role
to tighten a restriction *loosens* it instead, and the diff of your own object
shows a condition that looks restrictive.

`COMBINATION MODE AND` is the only way to tighten. The documented combination
is:

```
( cond_or_1 OR cond_or_2 OR ... ) AND cond_and_1 AND cond_and_2 AND ...
```

Two practical consequences. First, in a switchable role `COMBINATION MODE` is
**mandatory**, including for `OR` -- a reasonable habit to adopt everywhere,
since it makes the intent explicit at the point of reading. Second, the docs
advise using **only one access rule per CDS role**, which is really advice
about ownership: one rule per role keeps "who restricts this entity" a
question with one answer.

The customer-side override is `REDEFINITION`, which declares that this rule is
the only rule for the entity and all others are ignored. It is customer- and
partner-only (SAP never delivers it), allowed at most **once** per entity
(otherwise activation or import fails), it also disables existing full access
rules, and it is forbidden in switchable roles.

## 4. One full access rule beats every other rule, AND rules included

A **full access rule** is the same statement with no `WHERE`:

```
@MappingRole: true
define role YDJ_CARR_VE_FULL {
  grant select on YDJ_CARR_VE;   // that is the whole rule
}
```

The docs are blunt about what it does to the combination in section 3:

> A full access rule overrides the construction above, however, and produces a
> full access rule as the end result, even if there are rules with the mode
> `COMBINATION MODE AND`.

And its effect is documented as identical to there being no role at all, to
`#NOT_ALLOWED`, and to `WITH PRIVILEGED ACCESS` at the call site.

So one line, in one role, in any package, anywhere in the system, switches an
entity's protection off for everybody -- and it is a *documented, legitimate*
technique for customers to neutralise an SAP-delivered role without a
modification. Which means reviewing the role you wrote is not enough. The
question is whether **any** role in the system grants full access to that
entity. `REDEFINITION` is the counter-move, since it disables full access
rules too.

## 5. The user with `*` sees rows nobody else can see

A PFCG condition maps entity elements to authorization fields:

```
where (carrid) = aspect pfcg_auth(S_CARRID, CARRID, ACTVT = '03')
```

At runtime this becomes a condition built from the current user's
authorizations: several authorizations are OR-ed, the fields within one
authorization are AND-ed, and several values for one field are OR-ed. Fine so
far. Then:

> If a full authorization exists within a PFCG condition for an authorization
> field, no condition is created for the CDS element specified on the left
> side. This makes the PFCG condition accept all values, including the null
> value.

A full authorization does not produce a wide condition, it produces **no
condition**. And an absent condition lets through rows a wide condition never
would, because a comparison with a null is unknown rather than true (see
[Null Values](../Null%20Values#readme)). Elements reached through a path
expression or an outer join inside the entity are exactly the nullable ones.

The fix is to say it out loud:

```
where (carrid) = aspect pfcg_auth(S_CARRID, CARRID, ACTVT = '03')
    and carrid is not null
```

The operational point is bigger than the syntax: a developer or support user
with `*` on the authorization object is **not testing the access control at
all**. They are testing the no-condition path, which is the one path the
business user never takes. `ydj_cds_dcl_demo.abap` in this folder prints those
two row counts side by side.

## 6. `?=` and `BYPASS WHEN` look alike and differ on the unauthorized user

Both exist to let incomplete records -- an element that is still null or
initial -- past a PFCG condition. They disagree about the user who has no
authorization for the object at all.

`?=` instead of `=`:

> The condition is also met ... if all CDS elements in the left parentheses
> have the null value or their type-dependent initial value. This applies even
> if the user does not have an authorization for the specified authorization
> object.

`BYPASS WHEN` on an individual element:

> If the logged on user does not have the specified authorization, the PFCG
> condition is false, even if all CDS elements on the left side have the bypass
> value.

So `?=` is evaluated independently of the user's authorizations and will hand
incomplete rows to someone with nothing granted at all, while `BYPASS WHEN`
keeps the authorization object as a gate and only relaxes the *value* filter.
For anything resembling a security boundary, `BYPASS WHEN` is the one you
want; the docs also note `?=` applies to **all** elements in the parentheses
and cannot be narrowed to one, and recommend `BYPASS WHEN` as the better
alternative for that reason too.

The bypass conditions are `IS NULL`, `IS INITIAL` and `IS INITIAL OR NULL`,
and null and initial are **distinguished** -- a row with one of each, under a
rule that bypasses only `IS NULL`, is blocked.

## 7. Inside update task, every PFCG condition is full authorization

> During update task processing, the predefined aspect `pfcg_auth` behaves as
> if the user has full authorization. This replicates the behavior of the
> classic `AUTHORITY-CHECK` statement, which in this situation always returns
> `sy-subrc = 0`.

Same hole as the classic statement, same reason, and now also in the layer that
was supposed to be declarative. Anything selected from inside a `CALL FUNCTION
... IN UPDATE TASK` module -- a V1 that re-selects the document it is posting,
a V2 that aggregates -- gets the unfiltered row set, and by section 5 that
also means null values come along.

The existing notes on both halves of this:
[Authorization Checks](../Authorization%20Checks#readme) (trap 2) and
[Update Task](../Update%20Task#readme).

## 8. A switchable role in a switched-off package is an empty role

With `DEFINE ROLE name SWITCHABLE`, the role follows the Switch Framework
state of its own package. If the switch is anything other than On:

> the role is generated with empty content, in particular, all rules in the
> role are no longer present at runtime.

Not "the role is inactive" -- the role exists, activates, transports, and
contains nothing. If it is the only access control for the entity, the entity
then behaves as if it were never protected. The one case where this is loud
rather than silent is `#MANDATORY`, which the docs confirm turns the same
situation into a runtime error instead.

Two more consequences worth knowing: when a switchable role is not generated,
the syntax check **does not detect all errors in its rule content**, so a role
can be delivered from a system where it is dormant and cause import errors in
the system where it is live. And `SWITCHABLE` forbids `REDEFINITION` and all
inheritance statements, so it cannot be retrofitted onto an inheriting role.

## 9. The failures that are not errors

**Denied and absent are the same thing to the caller.**

> When CDS entities are accessed using ABAP SQL, ABAP programs cannot
> distinguish whether data is not read because it does not exist or because
> they are not allowed by CDS access control.

`sy-subrc = 4` means both. Do not raise "not authorized" from an empty result,
and do not raise "does not exist" either -- neither is knowable there.

**A type change can silently turn a condition into "no rows".** Authorization
field values are converted to the DDIC type of the element. Values that do not
fit become a false predicate; if every value of a field is incompatible, the
whole field is false and **the authorization is ignored**; if all
authorizations are ignored, the PFCG condition is false. Widening or retyping
an element in the DDIC can therefore empty out a report with no activation
error anywhere. Elements with a CDS enumerated type are the extreme case: used
in a PFCG condition outside a PFCG mapping, nothing except the full
authorization value is compatible and the condition is always false (with a
syntax warning).

**An optional element that is missing beats everything.** When a left-side
element declared `DEFAULT FALSE` is missing at runtime, the entire PFCG
condition is false -- and that is decided *before* the authorization object is
evaluated, so neither full authorization nor globally disabled authorization
checks can rescue it.

**Role data volume is a runtime limit, not a design detail.** The size of the
generated database statement depends on how much role data the current user
has. Tools that maintain roles automatically can produce authorizations with
thousands of single values (the docs' example: every cost centre in a company),
and those values land in the statement, which "may exceed the limit for the
statement size or lead to increased statement processing time". The developer
with three values passes; the production user with all of them fails.

**Emergency mode disables all of it.** For user `SAP*`, CDS access control is
off -- and not only the PFCG conditions, but the literal conditions and
user-defined aspects too.

**`NOT` is not available where you would want it.** A PFCG condition with
elements on the left side cannot be negated, because that would invert an
authorization check. Same for user-defined aspects and inheritance conditions.

**Key elements matter more than usual.** The entity's key elements take part in
internal selection statements, and the docs warn that they should either
identify a unique row or not be defined at all -- otherwise "unexpected
results can arise".

## 10. Where access control simply does not apply

- **Client-independent access.** `USING` and the obsolete `CLIENT SPECIFIED`
  can only be used on entities where access control is *disabled*. The two
  features are mutually exclusive by design -- see
  [CDS View Entities](../CDS%20Client%20Handling#readme).
- **Shared memory creation with a system user.** Access-controlled entities
  cannot be used in that code at all; it is a runtime error unless access
  control is disabled -- see [Shared Objects](../Shared%20Objects#readme).
- **The obsolete CDS-managed DDIC view.** Accessing it performs no implicit
  authorization check; rows are removed afterwards with `AUTHORITY-CHECK`
  instead.
- **Abstract and custom entities.** They cannot be named in an access rule.
- **Anything but direct ABAP SQL access.** Roles can be defined for CDS views,
  hierarchies, transactional queries and table functions, and implicit control
  applies only when such an entity is accessed *directly* by ABAP SQL.
- **Deliberately, at the call site.** `WITH PRIVILEGED ACCESS` in the `FROM`
  clause switches it off for one entity; `PRIVILEGED ACCESS` as the last
  position of the statement covers the whole statement including entities
  reached through path expressions.

And the division of labour the docs recommend: keep **classic** authorization
checks for start authorizations -- whether this user may run the application at
all -- and use CDS access control for filtering data *within* it. DCL is not a
replacement for `AUTHORITY-CHECK`, it is the layer underneath it.

## Cheat sheet

- `#NOT_REQUIRED` is the default and means **unprotected when no role exists**.
  `#CHECK` changes nothing at runtime. Use `#MANDATORY` when it matters.
- A wrapper view loses the protection. Every entity accessed directly by ABAP
  SQL needs its own role, or `INHERITING CONDITIONS FROM ENTITY`.
- Rules and roles are **OR-ed**. Adding a role cannot narrow anything; only
  `COMBINATION MODE AND` tightens.
- `GRANT SELECT ON entity;` with no `WHERE` disables protection entirely, and
  beats `COMBINATION MODE AND` rules.
- A user with `*` gets **no condition**, so nulls pass. Add `IS NOT NULL`, and
  never test access control with a `*` user.
- `?=` ignores the authorization object for empty values; `BYPASS WHEN` does
  not. Prefer `BYPASS WHEN`.
- In update task, PFCG conditions behave as full authorization.
- `SWITCHABLE` + switch off = a role with no rules at runtime.
- Empty result never means "not authorized". There is no indicator for that.
- `@MappingRole: true` is mandatory and means every user, in every client.

## Sources

ABAP keyword documentation, pages `ABENCDS_ACCESS_CONTROL`,
`ABENCDS_F1_DCL_SYNTAX`, `ABENCDS_F1_DEFINE_ROLE`, `ABENCDS_DCL_ROLE_RULES`,
`ABENCDS_DCL_ROLE_COND_RULE`, `ABENCDS_DCL_ROLE_GRANT_RULE`,
`ABENCDS_DCL_ROLE_CONDITIONS`, `ABENCDS_DCL_ROLE_COND_EXPR`,
`ABENCDS_F1_COND_PFCG`, `ABENCDS_F1_COND_INHERIT`:

<https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCDS_ACCESS_CONTROL.html>

Related notes in this repo:
[Authorization Checks](../Authorization%20Checks#readme),
[CDS View Entities | Client Handling](../CDS%20Client%20Handling#readme),
[CDS Associations](../CDS%20Associations#readme),
[Null Values](../Null%20Values#readme),
[Update Task](../Update%20Task#readme),
[Shared Objects](../Shared%20Objects#readme).
