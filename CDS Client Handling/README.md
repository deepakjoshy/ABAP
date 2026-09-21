# CDS View Entities | Client Handling, the Column You Cannot Select & the Buffering That Moved

A `define view entity` looks like a tidier spelling of the old `define view`.
It is not. Client handling, the shape of the result set, the allowed `SELECT`
additions and the whole buffering mechanism are different, and every one of
those differences is silent at the ABAP call site until it is not.

CDS view entities arrived with ABAP release 7.55 as the successor to
CDS DDIC-based views, which the keyword documentation now labels
*(obsolete)* everywhere they appear.

---

## 1. You no longer decide whether the view is client-dependent

For a **DDIC-based view** you wrote it down:

```
@ClientHandling.type: #INHERITED | #CLIENT_DEPENDENT | #CLIENT_INDEPENDENT
@ClientHandling.algorithm: #AUTOMATED | #SESSION_VARIABLE | #NONE
```

For a **view entity** there is no such annotation. The doc is explicit:
*"The client dependency of CDS view entities is not defined by annotations."*
It is derived from the data sources, full stop:

- any client-dependent data source -> the view entity is client-dependent
- no client-dependent data source -> it is client-independent

So the migration of a view that carried `#CLIENT_DEPENDENT` or
`#SESSION_VARIABLE` does not carry an equivalent line forward. There is
nothing to review in the new source, which is exactly why nobody reviews it.

Client handling itself is always the session-variable algorithm: filtering on
the HANA session variable `CDS_CLIENT`, addressed in CDS as `$session.client`.

---

## 2. The client column is not in the result set. At all.

> *"Since client handling is performed completely implicitly in CDS view
> entities, a client field is not allowed in the `SELECT` list of a view
> entity. The result set of an ABAP SQL read on a CDS view entity can never
> contain a client column either."*

Two consequences that only show up after migration:

- a `key mandt` (or `key client`) element in the old view is a **syntax error**
  in the view entity, and
- ABAP code doing `SELECT * ... INTO TABLE @lt_result` where the target
  structure is typed from the *old* view, or code that reads `-mandt` off a
  result row, loses that field. With `INTO CORRESPONDING FIELDS` it just stays
  initial: no syntax error, no exception, an empty client in the output file.

If you genuinely need the client ID back for a client-dependent entity that
has no client column, the only documented route is the `SELECT` addition
`EXPOSE CLIENT AS clnt_col` (allowed with `USING ... CLIENTS ...`), which
prepends a column of client IDs to the result set.

---

## 3. Half the client additions of SELECT are rejected on a view entity

| Addition | DDIC-based view | View entity |
|---|---|---|
| `USING CLIENT clnt` | allowed | allowed, **but see below** |
| `USING ALL CLIENTS` | allowed | **not allowed** |
| `USING CLIENTS IN ...` | allowed | not allowed (same rule) |
| `CLIENT SPECIFIED` | allowed, obsolete | **not allowed** |

And `USING CLIENT` on a view entity has a second condition that has nothing to
do with clients: it only works where **CDS access control is off**.

- Statically recognizable `USING CLIENT` on an entity that is *not* annotated
  `@AccessControl.authorizationCheck: #NOT_ALLOWED`, without
  `WITH PRIVILEGED ACCESS` in the `FROM` clause -> **syntax check error**.
- Reaching an access-controlled entity that way at runtime -> **exception**.

The reason is stated plainly in the doc: *"CDS access control does not work for
client-independent access."* So the cross-client report that worked over the
old view fails to compile over the new one, and the fix is an authorization
decision (`WITH PRIVILEGED ACCESS`), not a syntax fix. Treat it as one.

One more detail that costs a syntax error: `clnt` expects a `c LENGTH 3` data
object -- a literal or a host variable -- and `sy-mandt` **cannot be specified
directly**. Copy it into a local first (see the demo).

---

## 4. The outer-join trap: `#AUTOMATED` and the view entity return different rows

This is the one that changes data rather than failing loudly.

Take a **left outer join with a client-independent left side and a
client-dependent right side**:

- **DDIC-based view with `@ClientHandling.algorithm: #AUTOMATED`** (the default
  for a client-dependent V1 view): *"The left side is replaced by a cross join
  of the client-independent data source with the DDIC database table `T000` and
  a comparison of the client columns in the `ON` condition."* The doc states the
  purpose outright -- this *"avoids null values"*.
- **View entity** (session-variable algorithm, and `#SESSION_VARIABLE` on a V1
  view): *"Compares the client column with the value of the session variable
  `$session.client` in the `ON` condition."*

Same join, same sources, different generated SQL. A view built on a customizing
table joined out to transaction data can lose or gain rows after migration,
depending on which clients exist in `T000`. Nothing in the DDL diff hints at it,
because the difference lives in the implicit expansion. Run an old-vs-new row
count on any view whose outer join mixes a client-independent source in, before
you retire the V1 object.

The right-outer-join row of the table is the mirror image of this.

---

## 5. Native SQL and AMDP do not get implicit client handling

Everything above applies to **ABAP SQL only**. Reaching the generated database
object directly -- Native SQL, or a `USING` list in an AMDP method -- gets you
the raw table:

- *"Native SQL and AMDP do not implement implicit client handling. The current
  client must always be specified explicitly here."*
- The session variable is *"guaranteed only on SAP HANA databases used as
  standard AS ABAP databases under the name `CDS_CLIENT`. On other platforms,
  the existence and content of the session variable are not guaranteed outside
  of an ABAP SQL access, and this can produce unexpected behavior or programs
  may crash."*
- In an **AMDP procedure implementation** that touches such a database object,
  `CDS_CLIENT` must be set with the declaration addition
  `AMDP OPTIONS CDS SESSION CLIENT` -- *"If not, a syntax error occurs."*
  In an **AMDP function implementation** used as a CDS table function, the
  variable is filled for you.
- Separately: CDS DDIC-based views *"are not client-safe and cannot be used in
  the `USING` list of an AMDP method"* -- which is a genuine reason to migrate,
  not just a style preference.

---

## 6. Buffering moved out of the view and got stricter

The buffering annotations you know do not exist here. `@AbapCatalog.buffering.status`,
`.type` and `.numberOfKeyFields` are *"not supported in CDS view entities"* --
they are V1-only. Buffering is declared in a **separate repository object**:

```
@AbapCatalog.entityBuffer.definitionAllowed: true   " in the view entity

DEFINE VIEW ENTITY BUFFER ON cds_view_entity ...    " separate tuning object
```

The behavioural difference is the important part:

> *"In contrast to table buffering of CDS DDIC-based views where ABAP SQL
> bypasses the table buffer if the prerequisites are not met, the restrictions
> are checked directly for the view in case of CDS view entities. For a view
> that does not meet the prerequisites, table buffering cannot be enabled."*

V1 degraded quietly to a database read. A view entity refuses to activate the
buffer. Better -- but it means a straight migration of a buffered view can fail
activation, on rules such as: only DDIC tables or other buffering-allowed view
entities as sources; at least one key element with combined key length <= 900
bytes and no LOB keys; no input parameters; no calculation that does not depend
on database content only (no current-timestamp functions); no session variable
other than `$session.client`; no data-aging tables; no customer extensions; no
`GEOM_EWKB` element.

Also worth knowing: a view entity buffer and a propagated buffer are mutually
exclusive, buffering on several layers of a CDS stack *"stores data redundantly"*
in separate buffers, and a **non-unique primary key** on a buffered entity
*"might lead to unexpected buffer behavior"* -- the `key` addition is load-bearing.

---

## Cheat sheet

| Question | View entity answer |
|---|---|
| How is client dependency set? | Derived from the data sources. No annotation. |
| Can I select the client column? | No. Never in the result set. |
| How do I get the client ID back? | `EXPOSE CLIENT AS clnt_col` with `USING ... CLIENTS ...` |
| Cross-client read? | `USING CLIENT @lv_clnt`, only with access control off / `WITH PRIVILEGED ACCESS`. `USING ALL CLIENTS` and `CLIENT SPECIFIED` are out. |
| Can I pass `sy-mandt`? | Not directly. Copy to a `c LENGTH 3` local. |
| Outer join over a client-independent source? | Compares against `$session.client` -- not the `T000` cross join that `#AUTOMATED` generated. Re-test row counts. |
| AMDP / Native SQL? | No implicit handling. `AMDP OPTIONS CDS SESSION CLIENT`, or a syntax error. |
| Buffering? | Separate `DEFINE VIEW ENTITY BUFFER` object; prerequisites are enforced at activation, not bypassed at runtime. |

Runnable companion: [`ydj_cds_client_demo.abap`](ydj_cds_client_demo.abap) --
read-only, standard flight tables, no DDIC objects to create.

## Sources

- [ABAP CDS - View Entities](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCDS_V2_VIEWS.html)
- [ABAP CDS - Definition of Client Handling for CDS View Entities](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCDS_VIEW_CLIENT_HDL_DEF.html)
- [ABAP CDS - Client Handling in CDS DDIC-Based Views](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCDS_VIEW_CLIENT_HANDLING_V1.html)
- [ABAP SQL - Client Handling](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_SQL_CLIENT_HANDLING.html)
- [SELECT, USING CLIENT, CLIENTS](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSELECT_CLIENT.html)
- [ABAP CDS - Table Buffering of CDS View Entities](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCDS_V2_VIEW_BUFFERING.html)
- [CDS DDL - CDS View Entity, session_variable](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCDS_SESSION_VARIABLE_V2.html)
- [A new generation of CDS views: CDS view entities](https://community.sap.com/t5/application-development-and-automation-blog-posts/a-new-generation-of-cds-views-cds-view-entities/ba-p/13488765) (SAP Community, release 7.55)

Related notes in this repo:
[Table Buffering](../Table%20Buffering#readme) |
[Null Values](../Null%20Values#readme) |
[Authorization Checks](../Authorization%20Checks#readme) |
[Dynamic SQL](../Dynamic%20SQL#readme)
