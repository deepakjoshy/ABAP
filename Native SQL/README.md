# Native SQL & Database Connections (ADBC) — the LUW that is not yours, the client column nobody adds, and the truncation that happens on the wrong end

Native SQL is `"all platform-dependent statements and calls that can be passed to the Native SQL interface of the database interface"` — SQL that the database interface forwards instead of translating. You reach for it for the things ABAP SQL will not do: a HANA-only function, a stored procedure, DDL, or a table in a schema that is not the ABAP schema.

There are two ways in. The modern one is **ADBC**, a set of `CL_SQL_*` classes. The old one is static embedding between `EXEC SQL` and `ENDEXEC`, which `"is still supported but should no longer be used in new programs"`.

The trap is that Native SQL looks like ABAP SQL with a different spelling. It is not. Three guarantees that ABAP SQL gives you for free are gone, and none of them fail loudly:

- **the ABAP LUW is no longer the unit of work** — every connection carries its own database LUW, so `COMMIT WORK` and your `CL_SQL_CONNECTION` are two different switches;
- **there is no implicit client handling** — a `WHERE` clause without a client reads every client on the system;
- **types are bound, not converted** — and when the length does not fit, Native SQL truncates the *opposite end* from ABAP SQL, with no exception and no `sy-subrc`.

```abap
" Everything the database interface no longer does for you is in this one
" statement: the client predicate is explicit, the value is a ? placeholder
" rather than a concatenated literal, and the target type matches the column.
DATA(lo_stmt) = NEW cl_sql_statement( ).
lo_stmt->set_param( REF #( sy-mandt ) ).
lo_stmt->set_param( REF #( lv_carrid ) ).

DATA(lo_result) = lo_stmt->execute_query(
  `SELECT carrid, carrname FROM scarr WHERE mandt = ? AND carrid = ?` ).

lo_result->set_param_struct( struct_ref = REF #( ls_carrier ) ).
lo_result->next( ).
lo_result->close( ).          " a result set is an open database cursor
```

## 1. Every connection is its own LUW

This is the behaviour everything else in this note hangs off:

> `"Every active database connection creates a separate transaction context or is linked with its own database LUW. This means that database changes on one connection can be committed or rolled back independently of changes on other database connections."`

Used deliberately, that is a feature the ABAP LUW cannot otherwise offer: `"log data can be stored in and committed on a secondary or service connection without modifying the database LUW of the standard connection"`. An audit record written on a service connection survives a `ROLLBACK WORK` on the standard one — which is exactly what you want from an audit record.

Used accidentally, it is a program that hangs forever:

> `"a program changes a database row on the first connection and tries to change the same row on a second connection. This results in the program waiting for the lock of the first database LUW, without this first LUW ever being able to continue. This situation can only be resolved by ending the work process."`

One work process, one program, deadlocked against itself — no second user involved, so it will not reproduce under a single-user test unless you happen to hit the same row. The recovery is the part that matters operationally: it `"is done automatically for dialog processes, but it must be done manually for background jobs"`. In dialog the user sees a hang and eventually a dump; in batch the job sits in *running* until somebody notices and kills the work process. The documentation's own conclusion is blunt: `"It is therefore not advisable to change the same table within the a single program using multiple database connections."`

### The lowercase letter that splits one connection into two

You can hit that deadlock while believing you are using *one* connection, because ABAP SQL and Native SQL disagree about case:

> `"The name of a secondary connection or service connection specified after CONNECTION is transformed into uppercase letters internally. This must be respected when Native SQL accesses the connection explicitly. Conversely, an ABAP SQL statement can reuse database connections active in Native SQL or AMDP only if their names do not contain any lowercase letters."`

So `` `R/3*demo` `` in an ADBC call and `CONNECTION 'R/3*DEMO'` in an ABAP SQL statement are two connections, two LUWs, and — if they touch the same row — the self-deadlock above. The doc states the consequence for its own example: `"If the name of the service connection were to contain lowercase letters, separate connections with two different database LUWs would be produced. Accessing the same database table would then usually cause a lock situation."` Secondary connections from `DBCON` are safe by convention because they are already uppercase there; **service connections and `CONNECT TO ... AS` names are where this bites**.

### Which statement ends which LUW

| Statement | Acts on |
|---|---|
| `COMMIT WORK` / `ROLLBACK WORK` | **all active connections** |
| `COMMIT CONNECTION` / `ROLLBACK CONNECTION` | one named connection |
| `CL_SQL_CONNECTION->COMMIT` / `->ROLLBACK` | the connection of that object |
| `CLOSE` / `CLOSE_NO_DISCONNECT` | that connection — **as a rollback** |
| Implicit commit at work-process switch | all open connections, default connection last |

Two of those rows are easy to misread.

`COMMIT WORK` is not scoped to the standard connection — it and the implicit database commits `"act on all active connections"`. The separation is real, but only until something triggers a global commit. And the implicit commit at a work-process switch is executed `"on all open connections. The database commit on the default connection is the last one."`

Closing is the one that silently destroys data. Each close method `"ends the current database LUW with a database rollback"`, and for both, `"all database changes not yet committed using a database commit are discarded"`. A tidy `con->close_no_disconnect( )` at the end of a method throws away every insert you made on that connection unless you committed first. Worse, the same line behaves differently depending on which connection the object represents — `"The methods are ignored in instances that represent the standard connection."` Identical cleanup code, data loss on one connection and a no-op on the other.

Prefer `CLOSE_NO_DISCONNECT`: `"To restore a connection that was closed completely with CLOSE requires a significant amount of resources. CLOSE should only be used in exceptional cases"`.

### Never commit through `CL_SQL_STATEMENT`

It is syntactically possible to pass `COMMIT` to `EXECUTE_DDL`. Do not:

> `"The methods in the class CL_SQL_STATEMENT should not be used to execute transaction control statements (COMMIT, ROLLBACK) because they are not detected by the database interface, which then might not execute the actions required at the end of a transaction."`

The commit happens — the database interface just does not know it did, so the housekeeping it owes the ABAP LUW never runs. Transaction control `"is possible only using the methods COMMIT and ROLLBACK of the class CL_SQL_CONNECTION"`. To get a connection object for the standard connection, `"an instance of class CL_SQL_CONNECTION must be created for this connection using CREATE OBJECT"` (or `NEW`) rather than asking `GET_ABAP_CONNECTION` for *DEFAULT*.

One more scoping rule that catches people building a "connection manager": `"Secondary connections and service connections in an internal session cannot be used in called programs, which means that a called program always activates its own connection and hence its own database LUW, even if the same connection name is used."`

## 2. There is no implicit client handling

> `"Native SQL does not support implicit client handling. When accessing client-dependent database tables or views, the required client ID must be selected explicitly. In application programs, only the current client should be used to do this."`

ABAP SQL adds the client predicate for you. ADBC does not, and the result is a query that *works* — returns rows, fills your structure, raises nothing — while reading other people's clients. On a system with a single productive client the bug is invisible; it appears after a client copy.

Two details that make this worse than it first looks:

- The client column is an ordinary column to Native SQL, so it must be in your select list too if you are binding positionally with `SET_PARAM_STRUCT` against a full-table structure.
- For CDS entities there is a second mechanism: `"When the database object of a client-dependent CDS entity is accessed using Native SQL and the client handling algorithm of the entity is governed by the HANA session variable CDS_CLIENT, this variable must have an appropriate value."` Adding a `mandt = ?` predicate is not sufficient in that case.

Note also what is *not* restored by going through the Native SQL interface: `"Table buffering is bypassed when using Native SQL"`, and the DCL access control that a CDS view would apply does not exist at this level either.

## 3. The truncation happens on the wrong end

In ABAP SQL, a length mismatch is resolved by ABAP's conversion rules. In Native SQL, `"ABAP data objects should usually only be bound to suitable database fields"` — and if they are not, the conversion is done by the platform-dependent client library instead, where `"the following problems can occur"`: `"Unexpected conversion results"`, namely `"Cutting off or padding of values for character-like and byte-like types"` and `"Conversion rules different to those in ABAP"`.

The documentation's own example reads a `NUMC` column into a numeric text field that is too short. On an SAP HANA database:

| | Result |
|---|---|
| ABAP SQL | `00123` |
| Native SQL | `00000` |

Same column, same target, same row. ABAP SQL `"passes the data right-aligned and truncated on the left"`; Native SQL truncates on the right, so for a left-padded `NUMC` value you get the padding and lose the number. No exception, no `sy-subrc`, just zeros. Section 6 of the demo reproduces this read-only against `SPFLI-CONNID`.

The write direction is asymmetric rather than symmetric, which is why testing one direction proves nothing about the other: a host variable that is too *long* raises `CX_SY_NATIVE_SQL_ERROR` (`"inserted value too large for column"`) in Native SQL, where ABAP SQL would have silently left-truncated it.

`"This is particularly relevant for the ABAP types n, d, and t and decimal floating point numbers"` — precisely the types that look character-like in ABAP and are not stored that way.

### Trailing blanks make rows invisible to ABAP SQL

The same mismatch runs the other way when you *write* through Native SQL:

> `"In ABAP SQL, the trailing blanks of a text field literal are not stored in the database. An ABAP SQL WHERE condition comparing with the same text does find the data."`
>
> `"In Native SQL, the trailing blanks of a text field literal are stored in the database. An ABAP SQL WHERE condition comparing with the same text does not find the data."`

A row inserted by ADBC can therefore be unfindable by the ABAP SQL `SELECT` sitting next to it — `"It can be found with a LIKE condition or using the LEFT function"`. The same split applies to `c` written into a DDIC `STRING` column: ABAP SQL truncates trailing blanks `"according to the ABAP rules"`, Native SQL keeps them per the `NCLOB` rules.

### Column order is yours to get right

> `"When using Native SQL, the order of the columns in database tables defined in the ABAP Dictionary in the database system does not have to match the order of the structure definition in the ABAP Dictionary."`

ABAP SQL reconciles the two for you; Native SQL does not, so `"the order of the columns in the database system must be respected explicitly"`. That is the argument against `SELECT *` plus a positional `SET_PARAM_STRUCT`: it is correct until the physical column order diverges, which an append structure or a DDIC change can cause without anybody touching your program. Name the columns, or pass `CORRESPONDING_FIELDS`.

## 4. Binding and result sets

The binding rules are strict and positional:

- `SET_PARAM` `"must be called exactly once for each placeholder ?"`, and `"The order of the calls determines the assignment of the elementary data objects to the placeholders from left to right"`.
- `SET_PARAM_STRUCT` and `SET_PARAM_TABLE` are called *once*, and their components bind left to right.
- `"After each SQL statement is executed, the binding is removed."` Reusing the statement object means re-binding every parameter.
- One statement per call: `"Exactly one SQL statement can be passed to each method of the class CL_SQL_STATEMENT to be executed. Passing multiple SQL statements separated by delimiters such as ; is not possible."` This differs from `EXEC SQL`, where a semicolon-separated list is allowed — so a block migrated from `EXEC SQL` has to be split.
- For repeated execution with different values, use `CL_SQL_PREPARED_STATEMENT`; `CL_SQL_STATEMENT` `"allows the statement passed to be executed once"`.

On the read side, `NEXT_PACKAGE` has the same shape as the `APPENDING ... PACKAGE SIZE` trap in ABAP SQL:

> `"In each call of NEXT_PACKAGE, the rows read are appended to the internal table without deleting the previous content"`

so the target grows across packages and is a memory guard only if you clear it yourself.

And a result set is a cursor: `"An open result set is connected to an open database cursor. Therefore, a result set should be always closed explicitly with the method CLOSE after its usage to avoid inadvertently keeping too many database cursors open."` Open-cursor ceilings and the commit that closes cursors are covered in [Mass Data Processing](../Mass%20Data%20Processing#readme). If you need the result to outlive the LUW, `HOLD_CURSOR` `"can be filled with X"`.

For nulls, `SET_PARAM` takes an `IND_REF` indicator of DDIC type `INT2` in which `"the value -1 indicates whether a null value existed on the database"` — the manual equivalent of the `INDICATORS` addition in [Null Values](../Null%20Values#readme).

## 5. Injection is your problem now

Because the statement is a string, ADBC is an injection surface in a way ABAP SQL is not:

> `"To avoid SQL injections in ADBC reliably, no parts of an SQL statement that is not an operand position can come from outside of the program."`

The order of preference is fixed: use `?` placeholders with `SET_PARAM`; and only if a value genuinely cannot be a placeholder, escape it with `cl_abap_dyn_prg=>quote( )`, `"which also adds quotation marks at the start and at the end"`. Anything structural — a table name, a column list, an operator — must come from the program, not from input.

## 6. `EXEC SQL` and what is actually obsolete

`EXEC SQL` is still alive and still in a lot of legacy code. Two reasons not to add more of it:

- `"The area between EXEC and ENDEXEC is not checked completely by the syntax check"` — the statement is a string to the compiler, so typos reach runtime.
- `"New developments and improvements, such as support for new SQL statements or optimized performance using bulk access across internal tables, are now made only for ADBC."`

Worth knowing when reading the documentation itself: the ADBC overview page is now titled *Obsolete ABAP Database Connectivity (ADBC)* while its body still says, of static embedding, `"The recommendation, however, is to use ADBC."` The two statements are about different comparisons — ADBC is the better of the two Native SQL routes, and Native SQL as a whole is the thing being retired in favour of ABAP SQL, CDS and AMDP. For ABAP Cloud the relevant list is in [ABAP Language Versions](../ABAP%20Language%20Versions#readme), which already records `EXEC SQL` as not available there.

One last footgun if you do read legacy code: `SET TRANSACTION`. The behaviour it sets `"is preserved across the entire current database LUW, which can cause unexpected or critical situations when the database connection is reused"`, and on HANA you should call the `CL_SQL_CONNECTION` methods instead, because `"the default transaction behavior is restored automatically at the end of the database LUW"` there. Also note that the static `SET CONNECTION` statement `"is ignored by the database LUWs of the connections involved"`.

## Quick reference

| Goal | Reach for |
|---|---|
| Any ordinary table access | ABAP SQL — not this note |
| HANA-only SQL, DDL, stored procedure | `CL_SQL_STATEMENT` + `EXECUTE_QUERY` / `EXECUTE_DDL` / `EXECUTE_UPDATE` |
| Same statement, many values | `CL_SQL_PREPARED_STATEMENT` |
| A value from outside the program | `?` placeholder + `SET_PARAM` |
| A name from outside the program | `cl_abap_dyn_prg=>quote( )` — or refuse |
| Commit on one connection only | `COMMIT CONNECTION`, or `CL_SQL_CONNECTION->COMMIT` |
| Commit everywhere | `COMMIT WORK` |
| Log that survives a rollback | Service connection, committed separately |
| Release the connection, keep it warm | `CLOSE_NO_DISCONNECT` — **after** committing |
| Restrict to the current client | Your own `mandt = ?` predicate |
| Read in chunks | `SET_PARAM_TABLE` + `NEXT_PACKAGE` — and clear the table yourself |

## References

- [Native SQL — overview, client handling, buffering, platform differences](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENNATIVE_SQL.html)
- [ADBC — overview, client handling and security hints](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENADBC.html)
- [`CL_SQL_STATEMENT` — one statement per call, no transaction control](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCL_SQL_STATEMENT.html)
- [`CL_SQL_CONNECTION` — `GET_ABAP_CONNECTION`, `CLOSE` vs `CLOSE_NO_DISCONNECT`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCL_SQL_CONNECTION.html)
- [ADBC — Database LUWs](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENADBC_TRANSACTION.html)
- [ADBC — DQL statements, result sets and `NEXT_PACKAGE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENADBC_QUERY.html)
- [ADBC — DDL and DML statements, parameter binding](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENADBC_DDL_DML.html)
- [Native SQL — mapping of ABAP types, with the `NUMC` truncation example](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENNATIVE_SQL_TYPE_MAPPING.html)
- [Database connections and transactions — the self-deadlock](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDB_CONNECTIONS_TRANS.html)
- [Database access using database connections — the case-sensitivity split](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDB_CONNECTIONS_USING.html)
- [SQL injections using ADBC](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_INJ_ADBC_SCRTY.html)
- [`EXEC SQL` / `ENDEXEC`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPEXEC.html)

Related notes in this repo: [AMDP](../AMDP#readme) for the other way into database-native
code, [Dynamic SQL](../Dynamic%20SQL#readme) for the ABAP SQL equivalent of a statement
built at runtime, [Mass Data Processing](../Mass%20Data%20Processing#readme) for cursors
and the commit that closes them, [Table Buffering](../Table%20Buffering#readme) for the
bypass, [Null Values](../Null%20Values#readme) for indicators,
[CDS View Entities](../CDS%20Client%20Handling#readme) and
[CDS Access Control](../CDS%20Access%20Control#readme) for the client handling and the DCL
this level does not apply, [Update Task](../Update%20Task#readme) and
[Commit Work Events](../Commit%20Work%20Events#readme) for the ABAP LUW this one runs
beside, and [ABAP Language Versions](../ABAP%20Language%20Versions#readme) for what ABAP
Cloud allows.

Worked, runnable examples: [ydj_adbc_demo.abap](ydj_adbc_demo.abap)
