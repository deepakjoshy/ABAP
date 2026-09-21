# AMDP | The Method That Is Not ABAP, the Buffer It Bypasses & the Exception You Cannot Catch

`AMDP` (ABAP Managed Database Procedures) lets you write **SQLScript** inside what
looks like an ordinary ABAP method and have it execute on the HANA database instead
of on the application server.

The problem is exactly that "looks like": the declaration part of an AMDP method is
indistinguishable from any other method. Nothing in the signature says *this body is
a different language, runs on a different machine, ignores the table buffer, cannot
COMMIT, and throws exceptions you did not declare and therefore cannot catch*.

Everything below is from the ABAP keyword documentation, linked in
[Sources](#sources).

---

## 0. First: SAP's own guideline is "probably not"

Before any of the traps, the doc is blunt about when to use this at all:

> *"The use of AMDP is not recommended if the same task can be achieved using ABAP SQL
> (or ABAP CDS)."*

The keyword documentation ships an executable example (*AMDP, Comparison with ABAP
SQL*) whose entire point is that a badly written ABAP SQL access is usually fixed by
writing **better ABAP SQL**, not by moving it to the database. The doc's two
legitimate reasons to reach for AMDP:

1. A database-specific function exists that **ABAP SQL does not offer at all**.
2. A large process flow / analysis whose ABAP version would repeatedly **transport
   large amounts of data** between the database and the AS instance.

"It felt slow" is not on that list. Check the
[Table Buffering](../Table%20Buffering#readme) and
[For All Entries](../For%20All%20Entries#readme) notes first — those are the usual
real culprits.

---

## 1. Nothing in the declaration says "AMDP"

An AMDP procedure is declared like any other method:

```abap
PUBLIC SECTION.
  INTERFACES if_amdp_marker_hdb.          " <- the ONLY class-level marker

  TYPES ty_carriers TYPE STANDARD TABLE OF scarr WITH EMPTY KEY.

  CLASS-METHODS select_carriers
    IMPORTING VALUE(iv_client)   TYPE mandt
    EXPORTING VALUE(et_carriers) TYPE ty_carriers.
```

The doc states it outright:

> *"An AMDP procedure implementation cannot be identified as an AMDP method in the
> declaration part of the class."*

Only the **implementation** reveals it:

```abap
METHOD select_carriers
  BY DATABASE PROCEDURE
  FOR HDB
  LANGUAGE SQLSCRIPT
  OPTIONS READ-ONLY
  USING scarr.

  et_carriers = SELECT * FROM "SCARR"
                  WHERE mandt = :iv_client
                  ORDER BY carrid;

ENDMETHOD.
```

Practical consequences:

- A code review that reads the class definition sees a normal method.
- The class must carry the tag interface `IF_AMDP_MARKER_HDB` — the suffix names the
  database system, and it is currently the only one that exists.
- **AMDP classes can only be edited in ADT (Eclipse).** SE24/SE80 can display them,
  not change them.
- **Constructors cannot be AMDP methods.** The doc says so flatly.
- An AMDP class may freely mix AMDP and regular methods — which is the documented way
  to stay portable: a regular wrapper method that calls the AMDP method on HANA and
  falls back to ABAP SQL elsewhere.

---

## 2. `FOR HDB` is a runtime dependency, and the syntax check is not portable

`FOR HDB` does not mean *prefer HANA*. From the doc:

> *"The AMDP method can only be called in an AS ABAP whose standard database is managed
> by the specified database system; otherwise a runtime error is produced."*

Worse, the syntax check has the same restriction in the other direction:

> *"The check is performed with respect to the currently installed version of the
> database. **No checks take place on an AS ABAP with a different database system.**"*

So on a non-HANA system your SQLScript is **not syntax-checked at all** — it activates
clean and fails at runtime. And even on HANA, the check works by creating a temporary
database procedure, so it depends on the AS ABAP's database user holding `EXECUTE` on
`SYS.GET_PROCEDURE_OBJECTS` and `SYS.TRUNCATE_PROCEDURE_OBJECTS`. Missing those
produces **syntax errors in the AMDP method itself** — diagnosable via transaction
`SICK`, which is not where anyone looks when a method will not activate.

Guard the call rather than assuming:

```abap
IF cl_abap_dbfeatures=>use_features(
     requested_features = VALUE #( ( cl_abap_dbfeatures=>call_amdp_method ) ) ) = abap_false.
  " fall back to ABAP SQL
ENDIF.
```

---

## 3. The exception you did not declare is the one that kills you

Every AMDP exception class is under `CX_AMDP_ERROR`, and all of them are
`CX_DYNAMIC_CHECK` — the category that does **not** force you to declare it:

```
CX_ROOT
 |--CX_DYNAMIC_CHECK
     |--CX_AMDP_ERROR
         |--CX_AMDP_VERSION_ERROR      |--CX_AMDP_VERSION_MISMATCH
         |--CX_AMDP_CREATION_ERROR     |--CX_AMDP_DBPROC_GENERATE_FAILED
         |                             |--CX_AMDP_DBPROC_CREATE_FAILED
         |                             |--CX_AMDP_NATIVE_DBCALL_FAILED
         |                             |--CX_AMDP_WRONG_DBSYS
         |--CX_AMDP_EXECUTION_ERROR    |--CX_AMDP_EXECUTION_FAILED
         |                             |--CX_AMDP_IMPORT_TABLE_ERROR
         |                             |--CX_AMDP_RESULT_TABLE_ERROR
         |--CX_AMDP_CONNECTION_ERROR   |--CX_AMDP_NO_CONNECTION
                                       |--CX_AMDP_NO_CONNECTION_FOR_CALL
                                       |--CX_AMDP_WRONG_CONNECTION
```

The trap, verbatim:

> *"The exceptions ... **must be declared explicitly using `RAISING`** in the definition
> of an AMDP procedure implementation to be handleable when this method is called."*

So a `TRY ... CATCH cx_amdp_error` around a method whose signature has no `RAISING`
does **not** catch it. The database error becomes a short dump, and because
`CX_DYNAMIC_CHECK` needs no declaration, the compiler never warns you. The catch block
reads as defensive and is dead code.

> *"Other exceptions cannot be handled."* — anything outside the `CX_AMDP_*` tree is
> not catchable here at all.

And for functions:

> *"**No exceptions can be declared for AMDP function implementations.**"*

An AMDP table function behind a CDS table function therefore has **no** error path you
can declare. A failure surfaces in the `SELECT` that reads the CDS entity. See
[Exception Flow](../Exception%20Flow#readme) for the general `CX_DYNAMIC_CHECK` rules.

---

## 4. The table buffer is bypassed — and writes are forbidden because of it

Short and absolute:

> *"Table buffering is bypassed when using AMDP."*

So an AMDP method reading a fully-buffered customizing table hits the database every
time — the opposite of the performance win you moved it there for. Worse, in the write
direction the doc bans it outright:

> *"Writes cannot be performed on database tables where table buffering is switched on,
> since SQLScript accesses are ignored by buffer synchronizations."*

A write would leave every application server's buffer holding stale data with no
`DDLOG` entry to invalidate it — a permanent inconsistency, not a temporary one. This
is the same failure documented from the other side in
[Table Buffering §5](../Table%20Buffering#readme).

---

## 5. No COMMIT, no ROLLBACK — the LUW stays in ABAP

> *"Executing transactional statements is not permitted. In particular, no database
> commits and rollbacks with COMMIT and ROLLBACK statements are allowed. This also
> applies to called procedures. **LUWs should always be handled in the ABAP program**,
> to ensure data consistency between procedures."*

Note *"also applies to called procedures"* — calling a pre-existing native SQLScript
procedure that commits internally breaks the rule from inside an AMDP method that looks
compliant. Also banned in the implementation:

- **DDL** (creating/changing/deleting database objects).
- Statements only possible on tables and not views — `TRUNCATE TABLE`, `LOCK TABLE`.
- Access to **local temporary database objects**.
- An **empty** method body.
- **Recursion**: *"an SQLScript procedure or function cannot use itself"*, and it may
  not call anything that in turn uses it.
- AMDP methods have **no implicit enhancement options** — a detail that matters if you
  expected to extend one later. Compare [BAdIs](../BAdIs#readme).

For how the ABAP-side LUW actually behaves, see [Update Task](../Update%20Task#readme).

---

## 6. `USING` is a closed list, in both directions

Every ABAP-managed database object touched by the method must be listed after `USING`:
all DDIC tables and views, and all AMDP-managed procedures and functions (written
`class=>meth`). The rule is symmetric:

> *"**Each database object specified after USING must also be used** in the procedure
> or function."*

So `USING` rots in both directions — an object you stopped using is as much an
activation problem as one you forgot to add. Two non-obvious side effects:

- **A static constructor fires that you did not call.** *"When an AMDP method
  `class=>meth` is specified after USING, the ABAP runtime environment identifies this
  as a use of the class ... and its static constructor is executed before the first call
  of the AMDP method."* See [Constructors](../Constructors#readme).
- **ABAP visibility is projected onto the database.** A private AMDP method of another
  class cannot be called from the database side either, *"unless a friendship exists
  between the classes"*.

AMDP methods in the **same** class must also be listed. Objects in *other* schemas use
`USING SCHEMA schema OBJECTS ...` with a logical schema mapped in `DB_SCHEMA_MAP`, which
is what keeps the method transportable between systems whose schemas differ.

---

## 7. Dynamic access silently reorders your columns

This is the quietest data-corruption trap in AMDP. For statically known accesses:

> *"the AMDP framework makes sure that the order of the fields defined in the dictionary
> is respected (**this may be different from the order on the database**)."*

For dynamic ones, that guarantee is withdrawn:

> *"When database tables in ABAP Dictionary are accessed dynamically, the AMDP framework
> cannot respect the order of the fields defined here and the order of fields on the
> database (which might be different) is used instead. **This can produce the wrong
> values when making assignments to ABAP data objects** declared with respect to ABAP
> Dictionary."*

No exception, no `sy-subrc` — values land in the wrong fields because the positional
mapping shifted. The doc also warns dynamic access cannot prevent writes to buffered
tables (§4) and *"can be the cause of SQL injections related to input from outside"*,
and closes with:

> *"The use of dynamic programming techniques is **strongly discouraged**, even if
> supposedly permitted by the programming language of the database system."*

— naming `EXEC`, `EXECUTE IMMEDIATE` and `APPLY FILTER`. Same lesson as
[Dynamic SQL](../Dynamic%20SQL#readme), with a worse failure mode.

---

## 8. Signature restrictions that bite at activation

AMDP parameter interfaces are far narrower than normal methods:

| Rule | Consequence |
|---|---|
| `VALUE( )` mandatory; pass by reference **not permitted** | The default you normally omit is illegal here — see [Parameter Passing](../Parameter%20Passing#readme) |
| **No `RETURNING`** for procedures | Cannot be called functionally; procedures use `EXPORTING` |
| No generic types; only elementary types and tables with a **structured** row type whose components are **elementary** | No deep/nested tables, no object references |
| No enumerated types, no `DF16_SCL`/`DF34_SCL` | Activation error |
| Only **input** parameters may be optional | An optional `EXPORTING` is rejected |
| Each optional elementary input needs `DEFAULT` with a **literal or constant** | And, unlike regular methods, *"a literal specified as a replacement parameter must be convertible to the data type of the input parameter. If not, a syntax error occurs."* |
| `string`, `xstring`, `decfloat16`, `decfloat34` (and `f`) **cannot** have a default | Therefore cannot be optional at all |
| Optional **tabular** input uses `OPTIONAL`, never `DEFAULT` | |
| `CHANGING` cannot be `string`/`xstring` (except DDIC `SSTRING`) | |
| `c`/`n` limited to **5000 characters** | |
| Names: no `%_` prefix, `endmethod` forbidden, `client` reserved, `connection` only for a `DBCON_NAME` input | A perfectly reasonable parameter name is rejected |

Plus the one that only appears when you look at the generated object: a **tabular
`CHANGING` parameter is split** into an `IN` and an `OUT` parameter, because SQLScript
has no tabular `INOUT`. The `IN` half is named after your parameter with the postfix
`__IN__`. Invisible from ABAP — visible the moment another database procedure calls
yours.

---

## 9. Two conversions that look like data problems

- **Nulls become initial values.** *"When passed to an actual parameter, a null value is
  passed to its type-dependent initial value."* Outer joins and empty aggregates inside
  your SQLScript arrive in ABAP as `0` / blank, indistinguishable from real zeros. The
  full treatment is in [Null Values](../Null%20Values#readme).
- **There is no implicit client handling.** The doc's own example writes
  `WHERE mandt = clnt` by hand, passing `sy-mandt` in. Forget it and you read **every
  client**. `SESSION_CONTEXT` gives read access to HANA session variables (and
  `CDS_CLIENT` for CDS table functions), but *"write access to session variables with
  SQLScript statement `SET` is not permitted"*. Modern client-safety additions —
  `AMDP OPTIONS CDS SESSION CLIENT DEPENDENT` / `CLIENT INDEPENDENT` — are covered in
  [CDS Client Handling](../CDS%20Client%20Handling#readme).

---

## 10. Small things that waste an afternoon

- **`*` in column 1 is a comment**, ABAP-style, and is converted to SQLScript `--` when
  the procedure is stored. A convenience the doc says not to rely on when writing new
  AMDP methods.
- **Input parameters often need a leading colon** (`:iv_client`) in SQLScript operand
  positions. Not ABAP syntax; not flagged by an ABAP-trained eye.
- The procedure is stored under the name **`CLASS=>METH`**, and *"these names are
  case-sensitive when used in the database system"* — which is how you find it when
  calling from another procedure: `CALL "CLASS=>METH"( f1 => a1 );`
- **It is visible and editable in HANA tooling — do not.** *"changes like this are
  ignored by the implementation in the AMDP method and can be overwritten by the ABAP
  runtime environment at any time."*
- **`OPTIONS READ-ONLY` is contagious**: a read-only method *"can call other AMDP methods
  only if [they are] also flagged as READ-ONLY"*. It is mandatory at least once for AMDP
  functions, and can be given in the declaration (`AMDP OPTIONS READ-ONLY`), the
  implementation, or both.
- **`DETERMINISTIC`** (scalar functions only) buffers the result for the duration of a
  query when called repeatedly with the same inputs — correct only if the function truly
  is deterministic.
- Use **7-bit ASCII only** in AMDP implementations — *"strongly recommended"*.
- Interface methods and **redefined** methods can be AMDP methods; a tag interface is
  inherited by subclasses and by classes implementing a tagged interface.

---

## Rules of thumb

1. Try ABAP SQL / CDS first. SAP's guideline, not a preference.
2. Declare `RAISING cx_amdp_error` (§3), or your `CATCH` is decoration.
3. Never write to a buffered table from AMDP (§4), and expect no buffer reads either.
4. Keep the LUW in ABAP. No `COMMIT`/`ROLLBACK` below (§5).
5. Keep `USING` exact — unused entries fail just like missing ones (§6).
6. No dynamic table access. Column order is not guaranteed (§7).
7. Pass the client explicitly, or read every client (§9).
8. Wrap AMDP behind a regular method with an ABAP SQL fallback if the code must run on
   more than HANA (§2).

---

## Sources

- [AMDP — ABAP Managed Database Procedures](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-US/abenamdp.htm) — buffer bypass, `CALL_AMDP_METHOD`, ADT-only editing, the ABAP SQL guideline
- [AMDP — Classes](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-US/abenamdp_classes.htm) — `IF_AMDP_MARKER_HDB`, the `SCARR` example
- [AMDP — Methods](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-US/abenamdp_methods.htm) — flagging rules, no AMDP constructors
- [AMDP — Procedure Implementations](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-US/abenamdp_procedure_methods.htm) — the full signature restriction list, implementation bans, dynamic-access and null notes
- [METHOD — BY DATABASE PROCEDURE, FUNCTION](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-US/abapmethod_by_db_proc.htm) — `FOR`/`LANGUAGE`/`OPTIONS`/`USING`/`USING SCHEMA`, the no-check-on-other-DB rule, `SICK`
- [AMDP — SQL Script for the SAP HANA Database](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-US/abenamdp_hdb_sqlscript.htm) — `CLASS=>METH` naming, the `CHANGING` `__IN__` split, `*` comments, `SESSION_CONTEXT`, parameter limits
- [AMDP — Exception Classes](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-US/abenamdp_exceptions.htm) — the hierarchy and the mandatory `RAISING`
- [AMDP — Inheritance](https://help.sap.com/doc/abapdocu_753_index_htm/7.53/en-US/abenamdp_inheritance.htm)
- [SAP-samples/abap-cheat-sheets — 12_AMDP.md](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/12_AMDP.md) — `FOR TABLE FUNCTION`, client-safety additions, the `use_features` guard
