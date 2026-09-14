# AUTHORITY-CHECK — the failure modes that return `sy-subrc = 0`

ABAP SQL triggers **no** authorization check in the database. `SELECT * FROM ekko`
reads every purchasing document in the system regardless of who is logged on. The
only thing standing between a user and that data is an `AUTHORITY-CHECK` the
developer remembered to write, and analysed correctly.

The statement itself is trivial. What is not trivial is that **most ways of getting
it wrong return `sy-subrc = 0`** — the same value as a successful check. There is no
dump, no syntax warning, and the code passes every test on a developer's own
SAP_ALL user. This note is about those cases.

Companion note on the write side: [`Enqueue Locks`](../Enqueue%20Locks#readme) and
[`Commit Work Events`](../Commit%20Work%20Events#readme).

## The shape of the statement

```abap
AUTHORITY-CHECK OBJECT 'S_CARRID'
  ID 'CARRID' FIELD lv_carrid
  ID 'ACTVT'  FIELD '03'.        " 03 = display, per table TACT
IF sy-subrc <> 0.
  " deny - see below for why <> 0 and not = 4
ENDIF.
```

- One to ten `ID` fields, each either `FIELD <value>` or `DUMMY`.
- Object and field names are **uppercase character-like**. In ABAP for Cloud
  Development the object name must be a literal; only Standard ABAP allows a
  variable there.
- The value after `FIELD` is evaluated to **40 characters maximum**. Longer fields
  produce an extended-program-check (SLIN) warning, not a syntax error.

`sy-subrc` values:

| `sy-subrc` | Meaning |
|---|---|
| `0` | Check passed — **or no check was performed at all** |
| `4` | Authorizations exist for the object, but not for these values — *or* the field names were wrong / too many fields were given |
| `12` | No authorization for this object in the user master record |
| `40` | Invalid user name in `FOR USER` |
| `24` | Documented as *no longer set*. Old code testing for it is dead code. |

## Trap 1: `sy-subrc = 0` does not mean "the user is authorized"

Two separate cases collapse into `0`:

1. The user genuinely has the authorization.
2. The **check indicator** for that object in the current context (usually the
   calling transaction, maintained via `SU24`/`SU25`) is set to *no check*. The
   `AUTHORITY-CHECK` statement is then skipped entirely and `sy-subrc` is set to `0`
   exactly as if it had succeeded.

So the behaviour of identical code differs depending on **which transaction the
program was started from**. The keyword documentation's own guidance is that a check
indicator should always be set to *check*. Objects in the `BC` (Basis) and `HR`
areas cannot be switched off this way; everything else, including every custom
`Z`-object, can.

The practical consequence: "it returned 0, so authorization is fine" is not a
conclusion you can draw from ABAP alone. Confirm with `SU53` (result of the last
authorization check for the user) or an `ST01`/`STAUTHTRACE` trace.

## Trap 2: during update processing, the check is *always* `0`

> During an update, the statement `AUTHORITY-CHECK` always sets the value `sy-subrc`
> to 0 and does not perform an authorization check.

Inside an update function module (`CALL FUNCTION ... IN UPDATE TASK`, executed after
`COMMIT WORK`) there is no user dialog context to check against. Every
`AUTHORITY-CHECK` there is a no-op that reports success.

This matters because "check it right before the database write" feels like the
safest possible placement, and it is the one placement where the check does nothing
at all. **Authorization must be checked in the dialog part of the SAP LUW, before
the update module is registered.**

The CDS side of the same restriction is stricter: access control is *not allowed*
during an update. A `SELECT` on a CDS entity whose access control is still active
raises the runtime error `SYSTEM_UPDATE_TASK_ILL_STMT`. Disable it deliberately with
`@AccessControl.authorizationCheck: #NOT_ALLOWED` on the entity, or
`... FROM entity WITH PRIVILEGED ACCESS` in the statement.

## Trap 3: an empty value is a real value, not a wildcard

`FIELD lv_value` with `lv_value` initial checks for the authorization value *space*
— it does not mean "any value". If the user's role grants `CARRID = LH` but the
program passes a blank carrier because the selection screen was left empty, the
check fails with `sy-subrc = 4` and the developer concludes the role is broken.

"Do not check this field" is spelled `DUMMY`:

```abap
AUTHORITY-CHECK OBJECT 'S_DEVELOP'
  ID 'DEVCLASS' FIELD '$TMP'
  ID 'OBJTYPE'  FIELD 'PROG'
  ID 'OBJNAME'  DUMMY          " not checked
  ID 'P_GROUP'  DUMMY
  ID 'ACTVT'    FIELD '02'.
```

The degenerate case is worth knowing: if **every** field is `DUMMY`, the statement
can only return `0` (at least one authorization for the object exists, whatever its
values) or `12` (none at all). It is an existence check, not a value check — useful
for a cheap early exit, useless as the only check.

## Trap 4: wrong field names return `4`, indistinguishable from "denied"

`sy-subrc = 4` covers both *"the values are not permitted"* and *"you named a field
that does not exist in this authorization object, or listed more than ten"*. A typo
in `ID 'ACTVIT'` produces a check that can never succeed for anyone, including
SAP_ALL users, and looks exactly like a missing role. If a check fails for a user
who demonstrably has the object, verify the field names in `SU21` before touching
the role.

The related subtlety: a field specified **twice** is treated as two different
fields, so *all* its values must be covered by one single authorization. That is
usually not what the author intended.

## Trap 5: `IF sy-subrc = 4` instead of `IF sy-subrc <> 0`

Failure is `4`, `12` **or** `40`. Code written as:

```abap
IF sy-subrc = 4.       " WRONG - 12 falls through as if authorized
  MESSAGE e001(zauth).
ENDIF.
```

lets every user who has *no* authorization object at all (`12`) straight through —
which is precisely the unprivileged user the check existed to stop. Always test
`<> 0`, and never `sy-subrc > 0` habits aside, never continue processing on any
non-zero value.

Related: `sy-subrc` is overwritten by the next statement that sets it. Evaluate it
on the line immediately after `AUTHORITY-CHECK`, before any `MESSAGE`, `SELECT` or
method call.

## Trap 6: `FOR USER` is a security hole, not a convenience

```abap
AUTHORITY-CHECK OBJECT 'S_CARRID'
  ID 'CARRID' FIELD lv_carrid
  ID 'ACTVT'  FIELD '03'
  FOR USER lv_user.        " checks someone ELSE's authorizations
```

The documentation is blunt about this: the addition can be misused to bypass a check
by naming a user with extensive authorizations, and user names arriving from outside
the program must never be passed here. It replaces the older function module
`AUTHORITY_CHECK`.

Two further points:

- **Never write `FOR USER sy-uname`.** It is redundant — the check without the
  addition uses the *actual* user name and does not read `sy-uname` at all — and
  `sy-uname` is a writable system field that can be overwritten, including in the
  debugger. `FOR USER sy-uname` is therefore strictly weaker than omitting it.
- An unknown user name gives `sy-subrc = 40`, which a `= 4` test misses (Trap 5).

## Where checks happen implicitly, and where they do not

| Implicit check | No implicit check |
|---|---|
| `CALL TRANSACTION ... WITH AUTHORITY-CHECK` | `CALL TRANSACTION` **without** that addition (unless `TCDCOUPLES` has an entry) |
| `LEAVE TO TRANSACTION` | `SUBMIT` of a program with no authorization group |
| `SUBMIT` of a program that *has* an authorization group | Any ABAP SQL read on a database table |
| ABAP file interface | |

Every path a user can reach where no implicit check applies has to be secured
explicitly.

## The modern alternatives

- **CDS access control (DCL).** `@AccessControl.authorizationCheck: #CHECK` on a
  view entity plus a `DEFINE ROLE ... GRANT SELECT ON ... WHERE (field) = ASPECT
  PFCG_AUTH(zauth_obj, zauth_field, ACTVT = '03')` filters rows implicitly on every
  read. The four annotation values are `#NOT_REQUIRED` (full access),
  `#CHECK` (warning if no access control exists), `#MANDATORY` (one must exist) and
  `#NOT_ALLOWED` (any existing one is ignored).
- **`CL_AUTH_OBJECTS_TO_SQL`** generates a dynamic `WHERE` condition from an
  authorization object, so a `SELECT` returns only rows the user may see. This
  replaces the classic "select everything, then `AUTHORITY-CHECK` inside the loop"
  antipattern — which is both slow and easy to get wrong.
- **RAP** moves the check into `GET GLOBAL AUTHORIZATIONS` /
  `GET INSTANCE AUTHORIZATIONS` handler methods that map `sy-subrc` onto
  `if_abap_behv=>auth-allowed` / `auth-unauthorized`. Checks can be suppressed
  deliberately with an authorization context
  (`AUTHORITY-CHECK DISABLE BEGIN CONTEXT ... AUTHORITY-CHECK DISABLE END.`, only
  inside behaviour pools) or with EML `PRIVILEGED` mode.

## Quick checklist

- Check **before** the work, in the dialog LUW — never inside an update module.
- Test `sy-subrc <> 0`, on the very next line.
- `DUMMY` for "not checked"; an initial variable is not a wildcard.
- Deny by default: the `ELSE` branch of a failed check must stop processing, not log
  and continue.
- Do not use `FOR USER`, and never `FOR USER sy-uname`.
- Verify with `SU53` / `STAUTHTRACE` — `sy-subrc = 0` on your own SAP_ALL user
  proves nothing.

## Sources

- [`AUTHORITY-CHECK OBJECT`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/index.htm?file=abapauthority-check.htm) — `sy-subrc` table, check indicator behaviour, `DUMMY` semantics, `FOR USER` risk
- [Authorization Checks During an Update](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/index.htm?file=abenauthority_during_update.htm) — the always-0 rule and `SYSTEM_UPDATE_TASK_ILL_STMT`
- [Insufficient Authorization Checks](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/index.htm?file=abenauthority_scrty.htm) — implicit vs explicit check table
- [`AUTHORITY-CHECK DISABLE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/index.htm?file=abapauthority-check_disable.htm) — RAP authorization contexts
- [SAP-samples/abap-cheat-sheets — 25_Authorization_Checks.md](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/25_Authorization_Checks.md) — CDS access control and RAP handler examples
