# ABAP Language Versions — the property you never wrote, the whitelist that is not "modern ABAP", and the release contract that is not enough

Every repository object in an AS ABAP carries a property called **ABAP language
version**. It is not a pragma, not a comment, not something you type in your
source. It is metadata on the object, usually *derived* from its package or
software component, and it decides two things before your first line is parsed:

- **which ABAP language elements** you are allowed to write, and
- **which other repository objects** you are allowed to address.

> "For an ABAP program, its language version defines the syntax rules and set of
> repository objects that can be addressed as APIs."

The practical consequence, and the reason this note exists: **the same source
code is valid or invalid depending on where it lives.** Copying a working method
body into a class in a different package can turn it into a syntax error, and
nothing in the code you pasted changed.

---

## 1. There are three versions, and the ID lives in a table column

| Language Version | Kind | Version ID (`TRDIR-UCCHECK`) |
|---|---|---|
| **Standard ABAP** | unrestricted | `X` |
| **ABAP for Cloud Development** | restricted | `5` |
| **ABAP for Key Users** | restricted | `2` |

The ID is "generally transparent for developers" — but it is stored, literally,
in the `UCCHECK` column of table `TRDIR`. That column name is a fossil: it used
to mean "Unicode check", and Standard ABAP still reuses `X` because for Standard
ABAP the syntax check *is* the Unicode check. So the field that now selects your
entire language scope is named after a check that stopped being optional years
ago.

Two things follow that are worth knowing:

- **An unknown ID is not a fallback to Standard ABAP.** The doc is explicit: if
  a program has a version ID not in the table above, "it is handled in the same
  way as a version that does not support any language elements." Not permissive
  — maximally restrictive.
- `INSERT REPORT` and `SYNTAX-CHECK` take `VERSION` / `DIRECTORY ENTRY`
  additions, so generated code can be given a version explicitly. Both of those
  statements are themselves banned in ABAP for Cloud Development.

**You can test this without migrating anything.** The SAP-delivered program
`DEMO_ABAP_VERSIONS` "makes it possible to check ABAP source code using the
syntax rules of the different ABAP language versions" — paste a snippet, pick a
version, get the errors. This is the cheapest possible pre-migration check and
almost nobody knows it exists.

---

## 2. The restriction is a whitelist, and it is not "modern vs obsolete"

The doc page *Language Elements in ABAP Versions* is a machine-readable table of
every language element against every version. Counted from the current version
of that page:

| | Elements allowed |
|---|---|
| Standard ABAP | **3767** (all of them) |
| ABAP for Cloud Development | **2400** — 63.7% |
| ABAP for Key Users | **877** — 23.3% |

So **1367 language elements that compile today do not compile in ABAP for Cloud
Development.** And ABAP for Key Users is not "a bit tighter than Cloud" — it is
roughly a third of it.

Here is the part that catches people. The natural mental model is *"ABAP Cloud
bans the old stuff"*. That model is wrong in both directions.

**Obsolete elements are mostly banned — 168 elements are flagged obsolete, and
only 8 of them survive into ABAP for Cloud Development.** But look at *which* 8:

```
ADD          SUBTRACT      MULTIPLY      DIVIDE
FORM         ENDFORM       CALL METHOD (obsolete variant)      REPLACE (obsolete)
```

`FORM` / `ENDFORM` — subroutines, the thing every clean-ABAP guide tells you to
delete — **are legal in ABAP for Cloud Development.** `PERFORM` is legal too.
Meanwhile:

```
REPORT                 not allowed
START-OF-SELECTION     not allowed
WRITE                  not allowed
```

**Every runnable demo in this repository is invalid in ABAP for Cloud
Development**, including the one in this folder. Not because the *logic* is
outdated, but because the classical report skeleton — `REPORT`,
`START-OF-SELECTION`, `WRITE` — is gone. That is why the doc says "most
developments can be implemented **in methods only**, where the stricter syntax
rules of classes automatically apply."

The axis is **not** old-vs-new. It is **stateless, client-safe, UI-free,
upgrade-stable** vs everything else. A subroutine is ugly but harmless. `WRITE`
paints a list on a SAP GUI screen that ABAP Cloud does not have.

---

## 3. The migration pairs that actually bite

These are the ones that appear in ordinary, non-legacy, recently-written code:

| Banned in ABAP for Cloud Development | Cloud-safe replacement |
|---|---|
| `DESCRIBE TABLE itab LINES n` | `n = lines( itab )` |
| `GET TIME` / `GET RUN TIME` | `cl_abap_tstmp` / `utclong_current( )` |
| `DESCRIBE FIELD` | RTTI (`cl_abap_typedescr` and friends) |
| `SET PARAMETER` / `GET PARAMETER` (SPA/GPA) | explicit parameters — no hidden user memory |
| `SUBMIT`, `CALL TRANSACTION` | call the class/API directly |
| `OPEN`/`READ`/`TRANSFER`/`CLOSE`/`DELETE DATASET` | no application-server file system |
| `EXEC SQL` … `ENDEXEC` (Native SQL) | ABAP SQL, or AMDP |
| `PARAMETERS`, `SELECT-OPTIONS`, `SELECTION-SCREEN` | RAP / a real UI layer |
| `BREAK-POINT`, `LOG-POINT` | `ASSERT` (still allowed) |
| `DESCRIBE`, `SUM`, `ULINE`, `SKIP`, `FORMAT`, `HIDE` | — list processing is gone entirely |

Note the asymmetry in the last-but-one row: **`ASSERT` is allowed, `LOG-POINT`
and `BREAK-POINT` are not.** And note `DESCRIBE TABLE ... LINES` being banned
while the built-in function `lines( )` is allowed — the *capability* is fine,
only the statement form is refused. Most of this table is like that: a
functional one-for-one swap, not a redesign.

Two that surprise people the other way:

- **`CALL FUNCTION` is allowed** in ABAP for Cloud Development — including
  `CALL FUNCTION ... DESTINATION` for RFC. Function modules are not banned as a
  concept. (`CALL FUNCTION ... IN UPDATE TASK` and `STARTING NEW TASK` are.)
- **`AUTHORITY-CHECK` is allowed** in Cloud but **not** in ABAP for Key Users —
  a key-user enhancement cannot perform its own authority check.

---

## 4. `sy-` fields: the split is obsolete-vs-current, and it is enforced

System fields are whitelisted individually. Everything you actually use survives
— `sy-subrc`, `sy-tabix`, `sy-dbcnt`, `sy-datum`, `sy-uzeit`, `sy-uname`,
`sy-langu`, `sy-mandt`, `sy-batch`, `sy-repid`, `sy-cprog` are all allowed in
both restricted versions.

What is gone is the archaeology: `sy-appli`, `sy-cdate`, `sy-ctabl`, `sy-dcsys`,
`sy-batzd`/`batzm`/`batzo`/`batzs`/`batzw`, plus every field the doc marks
*Internal* (`sy-debug`, `sy-cfwae`, `sy-chwae`, `sy-dsnam`). If a `sy-` field is
in your code and you cannot remember what it does, that is the set to check.

---

## 5. A release contract is **necessary but not sufficient**

This is the single most misread rule in ABAP Cloud, and the doc states it
plainly:

> "Any repository object that can be used in a restricted ABAP language versions
> must be classified with an appropriate release contract (C1 contract in
> general). **But not all repository objects with a release contract can be used
> in a restricted language version.**"

A **released API** is therefore based on **two independent classifications**:

1. a **release contract** — the stability promise, and
2. **visibility for a restricted ABAP language version** — whether *you* may see it.

Finding a C1 contract on an object and concluding "I can call this from ABAP
Cloud" skips step 2. The contracts:

| Contract | Meaning |
|---|---|
| **C0** | release for adding enhancement fields at specified extension options |
| **C1** | **use system-internally** — stable interface for use within the AS ABAP |
| **C2** | use as remote API — stable interface for use *outside* the AS ABAP too |
| **C3** | manage configuration content — stable *persistence* for config content |
| **C4** | use in AMDP — stable interface of AMDP methods for other AMDP methods |

Classification happens in ADT or via transaction `SCFD_REGISTRY`.

Three further details that change decisions:

- **Released is not the same as recommended.** The release state is `Released`
  **or `Deprecated`**, and deprecated entries carry a **`Successor`** column. A
  deprecated-but-released API compiles cleanly in ABAP Cloud today. Check the
  state, not just the presence.
- **The same software component is a free pass.** Cloud-version objects may
  access "objects which are released APIs for ABAP for Cloud Development **or
  are in the same software component**." So intra-component calls need no
  release at all — which is why a migration looks easy inside one component and
  falls apart at the first component boundary.
- **Get the list programmatically.** Class **`CL_ABAP_DOCU_RELEASED_APIS`**
  produces the released-API list and, unlike the doc page, "the result can be
  restricted to certain release contracts or language versions and also
  non-transportable objects can be selected." For the wider picture there is the
  SAP Business Accelerator Hub and the ATC check for released objects.

---

## 6. Client isolation is enforced structurally, not by convention

In ABAP Cloud a user reaches data of the current client only. That is guaranteed
by three mechanisms, not by developer discipline:

1. **Implicit client handling in ABAP SQL** — there is no `CLIENT SPECIFIED`
   escape. (See [CDS Client Handling](../CDS%20Client%20Handling#readme).)
2. **AMDP methods may access client-safe repository objects only.**
3. **CDS entities that are released APIs must be client-safe.**

**Client-safe** is a precise term: an object accessing client-dependent SQL data
sources is client-safe "if it can access data of **one client only**". An object
touching only client-independent sources is *implicitly* client-safe.

The rule that catches AMDP authors: an AMDP method must be client-safe **if it
has the Cloud language version *or* is a released API with a C1 or C4 contract**
— and it must access only client-safe objects itself. Releasing an existing
AMDP method with a C1 contract therefore imposes client-safety on it
retroactively, in Standard ABAP, with no language-version change at all. For CDS
entities the annotation `ClientHandling.clientSafe` requests the checks
explicitly; for released APIs "the checks are done implicitly."

See also [AMDP](../AMDP#readme).

---

## 7. ABAP SQL is checked in the strictest mode that exists

> "For ABAP SQL, the most strict syntax check mode currently available is
> applied."

ABAP SQL has release-dependent **strict modes** (7.40 SP05 onward, one per
release). They are normally opt-in by accident: "they are applied only if a
feature is used that was not present in previous releases", and each mode
"contains the rules from all preceding releases". Adding one new feature to an
old statement retroactively subjects the whole statement to that release's
rules.

In ABAP for Cloud Development you do not get that gradient — the newest mode is
always on. Concretely that means comma-separated field lists, `@` host
variables, and `INTO` at the end are not style choices. It also means **fixed
point arithmetic must be active**: every strict mode from 7.40 SP05 "demand[s]
… programs in which the program property fixed point arithmetic is activated".
A legacy program relying on fixed-point-off arithmetic does not just need new
syntax, it needs its arithmetic re-verified. (See
[Numeric Arithmetic](../Numeric%20Arithmetic#readme).)

---

## 8. ABAP for Key Users is not documented

Worth knowing before you promise an estimate: ABAP for Key Users "is not
supported by the ABAP keyword documentation. Only ABAP syntax diagrams with a
short explanation are shown." With 877 allowed elements and no prose
documentation, the whitelist table and `DEMO_ABAP_VERSIONS` are effectively the
whole reference.

---

## Rules of thumb

1. **Check the version before you estimate.** `TRDIR-UCCHECK`, or the object
   properties in ADT. The code tells you nothing.
2. **Run `DEMO_ABAP_VERSIONS`** on a representative snippet before planning a
   migration.
3. **Grep for the cheap swaps first** — `DESCRIBE TABLE`, `GET TIME`,
   `GET/SET PARAMETER`, `BREAK-POINT`. They are one-line changes and they are
   safe to make in Standard ABAP *today*.
4. **Do not assume "obsolete" means "banned"**, or that "modern" means
   "allowed". `FORM` is legal in Cloud; `WRITE` is not.
5. **For any API, check contract *and* visibility *and* state.** C1 alone is not
   permission, and `Released` is not `Recommended`.
6. **Treat the software-component boundary as the real migration boundary**, not
   the package.

---

## Sources

- [ABAP Language Versions and APIs](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_LANGUAGE_VERSIONS.html) — the two main versions, access rules, client isolation, key-user version
- [ABAP Language Versions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_VERSIONS.html) — version ID table, `TRDIR-UCCHECK`, unknown-ID rule, `DEMO_ABAP_VERSIONS`, methods-only and strictest-SQL-mode wording
- [Language Elements in ABAP Versions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENRESTRICTED_ABAP_ELEMENTS.html) — the full per-element whitelist (source of every count and every allowed/banned claim here)
- [Released APIs of the Current System](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENRELEASED_APIS.html) — contract-necessary-but-not-sufficient wording, State/Successor columns, `CL_ABAP_DOCU_RELEASED_APIS`
- [Released API (glossary)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENRELEASED_API_GLOSRY.html) — the two classifications
- [Release Contract (glossary)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENRELEASE_CONTRACT_GLOSRY.html) — C0–C4 definitions, `SCFD_REGISTRY`
- [ABAP Cloud (glossary)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_CLOUD_GLOSRY.html) — the three restrictions, products where it applies
- [Restricted ABAP Language Version (glossary)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENRESTRICTED_VERSION_GLOSRY.html)
- [Client-Safe (glossary)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCLIENT_SAFE_GLOSRY.html) — the C1/C4 retroactive rule, `ClientHandling.clientSafe`
- [Client Isolation (glossary)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCLIENT_ISOLATION_GLOSRY.html)
- [ABAP SQL - Strict Modes](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_STRICT_MODES.html) — downward compatibility, cumulative rules, fixed point arithmetic requirement
