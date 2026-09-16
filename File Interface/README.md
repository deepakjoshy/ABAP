# ABAP File Interface — `OPEN DATASET` sy-subrc traps, text-mode data loss and the BOM

Every SAP system moves files across the application server: bank statement in,
IDoc payload out, nightly extract for the warehouse. The statements are only five
(`OPEN` / `READ` / `TRANSFER` / `CLOSE` / `DELETE DATASET`) and they look trivial,
which is exactly why the failure modes below keep shipping to production.

Four of them are silent — no dump, no syntax error, and in two cases `sy-subrc`
actively lies to you.

---

## 1. `OPEN DATASET` does **not** raise when the file is missing — it sets `sy-subrc = 8`

This is the single most common bug in file-handling ABAP: the developer assumes an
exception, writes no check, and the program continues against a file that was never
opened. The next `READ DATASET` then raises `CX_SY_FILE_OPEN_MODE`
(`DATASET_NOT_OPEN`) — a dump in a completely different place from the real cause.

| `sy-subrc` | Meaning |
|---|---|
| `0` | The file was opened. |
| `8` | The operating system could not open the file. |

— [`OPEN DATASET`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPOPEN_DATASET.html)

And `8` tells you nothing about *why*: missing file, wrong directory, OS permissions,
full filesystem — all the same code. The doc is unusually direct about the fix:

> In order to find the reason, why the operating system could not open a file, the
> addition `MESSAGE` should **always** be used for the statement `OPEN DATASET`.

```abap
DATA lv_msg TYPE string.

OPEN DATASET lv_file FOR INPUT IN TEXT MODE ENCODING UTF-8
     SKIPPING BYTE-ORDER MARK
     MESSAGE lv_msg.

IF sy-subrc <> 0.
  " lv_msg now holds the OS message, e.g. "No such file or directory"
  MESSAGE lv_msg TYPE 'E'.
ENDIF.
```

Without `MESSAGE`, the reason only reaches the developer trace — and only if the
trace level is at least 2, which it is not on a normal production box.

### The access types are not symmetric about missing files

| Addition | File missing | File exists |
|---|---|---|
| `FOR INPUT` | `sy-subrc = 8`, nothing opened | opened, pointer at start |
| `FOR OUTPUT` | **created** | **content is deleted** |
| `FOR APPENDING` | **created** | opened, pointer at end |
| `FOR UPDATE` | `sy-subrc = 8`, **no file created** | opened, pointer at start |

Two things to take from that table. `FOR OUTPUT` silently truncates an existing
file, so an `OPEN ... FOR OUTPUT` that has drifted inside a package loop writes the
last package and destroys the rest. And `FOR UPDATE` — despite being a write mode —
behaves like `FOR INPUT` when the file is absent; it does not create anything.

— [`OPEN DATASET, access`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPOPEN_DATASET_ACCESS.html)

---

## 2. In binary mode, `sy-subrc = 4` does **not** mean "nothing was read"

The canonical read loop is `DO. READ DATASET ... IF sy-subrc <> 0. EXIT. ENDIF. ... ENDDO.`
That loop is correct for text files and **loses the last record** for binary files.

Text files:

| `sy-subrc` | Meaning |
|---|---|
| `0` | Data read up to an end-of-line marker (explicit, or implicit at end of file). |
| `4` | An attempt was made to read data **after** the end of the file. |

Binary files:

| `sy-subrc` | Meaning |
|---|---|
| `0` | Data was read without reaching the end of the file, or the end was reached exactly. |
| `4` | Data was read up to the end of the file **and the target field was longer than necessary**, *or* an attempt was made to read after the end of the file. |

— [`READ DATASET`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPREAD_DATASET.html)

So a binary `sy-subrc = 4` conflates "past EOF, got nothing" with "got a short final
chunk". The trailing partial record is real data, and the naive loop throws it away.
This survives testing because it only appears when the file length is *not* an exact
multiple of the record length — and test files usually are.

The guard is `ACTUAL LENGTH`, which is filled regardless of `sy-subrc`:

```abap
DO.
  READ DATASET lv_file INTO lv_chunk
       MAXIMUM LENGTH lv_reclen
       ACTUAL  LENGTH DATA(lv_read).

  IF lv_read > 0.
    " process the chunk - even on sy-subrc = 4
  ENDIF.

  IF sy-subrc <> 0.
    EXIT.
  ENDIF.
ENDDO.
```

> Regardless of the length of the target field, the number of characters or bytes
> actually read from the file is always returned.

Two further notes on that statement. `ACTUAL` is optional but the doc says to always
write it, because bare `LENGTH` reads like `MAXIMUM LENGTH` at a glance and means the
opposite. And `MAXIMUM LENGTH` counts **characters** for text files but **bytes** for
binary and legacy files — a distinction that only bites on multi-byte data.

---

## 3. `TRANSFER` always sets `sy-subrc = 0` — checking it is theatre

> The statement `TRANSFER` always sets `sy-subrc` to the value `0` or raises an exception.

— [`TRANSFER`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPTRANSFER.html)

So `IF sy-subrc <> 0` after a `TRANSFER` is dead code, and the error handling that
matters is `TRY ... CATCH cx_sy_file_io` / `cx_sy_conversion_codepage`. The commonly
seen pattern — no `TRY`, but a diligent `sy-subrc` check after every write — has the
error handling exactly inverted.

### Text mode deletes your trailing blanks

> If the file was opened as a text file or a legacy text file, the **trailing blank
> characters are deleted for all data objects, except for those of data type `string`**.

That is the fixed-width-export bug: writing a `c LENGTH 40` name field to a text file
produces a line whose columns no longer align, because the padding was stripped on the
way out. The receiving system's positional parser then reads garbage from record two
onwards. Fixed-width output needs either `LENGTH len` on the `TRANSFER` (which pads
back up with blanks if `len` exceeds the object) or a binary file.

Related, from the same page: `NO END OF LINE` suppresses the line marker, and with a
plain `TRANSFER` per record the end-of-line marker of the *server's* platform is used
— so the same program produces `LF` on Linux and `CRLF` on Windows unless
`WITH [UNIX|WINDOWS|NATIVE] LINEFEED` is specified at open time.

This repo's [String Processing](../String%20Processing#readme) note covers why
trailing blanks disappear in ABAP generally; the file interface is where it turns into
a data-format defect rather than a cosmetic one.

---

## 4. The byte order mark is file content until you say otherwise

`ENCODING DEFAULT` is `ENCODING UTF-8`. Reading a UTF-8 file produced by Excel, .NET
or most Windows tooling means the first three bytes are `EF BB BF`, and:

> If there is a BOM at the start of the file, this is ignored, and the file pointer is
> set after it. **Without the addition, the BOM is handled as regular file content.**

— [`OPEN DATASET, encoding`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPOPEN_DATASET_ENCODING.html)

The symptom is famous and rarely diagnosed correctly: every field on the first record
is fine except the first one, which fails a `CO '0123456789'` check or an
`IS INITIAL` comparison because it carries three invisible leading bytes. Records 2..n
are clean. Always open UTF-8 files for reading with `SKIPPING BYTE-ORDER MARK`.

For writing, the programming guideline is explicit:

> Write text files in UTF-8 and with a byte order mark.

so `... FOR OUTPUT IN TEXT MODE ENCODING UTF-8 WITH BYTE-ORDER MARK`. Note that
`BYTE-ORDER MARK` cannot be combined with `AT POSITION`. And a **UTF-16 file can only
be opened as a binary file** — there is no `ENCODING UTF-16`; you read bytes and
convert with `CL_ABAP_CONV_CODEPAGE`.

### Code page conversion failures are also silent by request

`IGNORING CONVERSION ERRORS` suppresses `CX_SY_CONVERSION_CODEPAGE`, and every
unconvertible character is replaced by `#` (or by `REPLACEMENT CHARACTER rc`). This is
often pasted in to "fix" a dump — it does not fix anything, it converts a loud failure
into corrupted data. Both settings can be changed on an open file with `SET DATASET`.

---

## 5. Everything else that bites

**The file is on *this* application server.** `OPEN DATASET` opens the file on the
host of the *current AS instance*. A background job that writes a file and a follow-up
job that reads it can land on different app servers in the same system, and the read
gets `sy-subrc = 8`. Interface directories need to be on shared/NFS storage, and this
is why the problem never reproduces on a single-instance sandbox.

**Reopening an open file dumps.** A file already open in the current program cannot be
opened again: `CX_SY_FILE_OPEN` / `DATASET_REOPEN`. Error paths that jump out before
`CLOSE DATASET` and are then retried hit this. There is also a ceiling of **100 open
files per internal session** (`CX_SY_TOO_MANY_FILES`), lower on some platforms.

**`CLOSE DATASET` proves nothing.** If the file is already closed or does not exist,
the statement is *ignored* and `sy-subrc` is set to `0`. What it does do is matter for
durability: if the OS still has buffered data, that data is written before closing. A
file is not fully on disk until it is closed — an unclosed file read back by another
process can be short. Files are auto-closed when the program ends, but relying on that
means you never see `CX_SY_FILE_CLOSE` (raised e.g. when the filesystem is full).

**Don't write mixed structures directly.** Only character-like objects may go to text
files; only byte-like objects *should* go to binary files. For a structure with both
numeric and character components, the documented approach is a typed field symbol:

```abap
FIELD-SYMBOLS <hex> TYPE x.
ASSIGN wa TO <hex> CASTING.
TRANSFER <hex> TO lv_file.
```

with the caveat the doc attaches: byte-like content depends on byte order and code
page, so this is for short-term storage **within the same system** only. For exchange
between systems, convert to character and write a text file.

---

## 6. Authorization: two independent gates, and neither is `AUTHORITY-CHECK`

`OPEN DATASET` and `DELETE DATASET` trigger automatic checks. Failing them raises
`CX_SY_FILE_AUTHORITY` — an **exception**, not `sy-subrc = 8`, so the "missing file"
handler from §1 never sees it.

- **`S_DATASET`** — fields `PROGRAM`, `FILENAME`, `ACTVT`. Program-dependent.
- **`SPTH` + `S_PATH`** — table-driven and program-*independent*. `FS_NOREAD` /
  `FS_NOWRITE` override `S_DATASET` entirely; `FS_BRGRU` names an authorization group
  checked against `S_PATH`. SAP recommends the `FS_BRGRU` route over the No-Read/No-Write
  columns, because the latter are exclude lists with no audit log.

The `S_DATASET` gotcha worth remembering:

> The physical file name used in the statements above and the values of the
> authorization field `FILENAME` are compared **literally**. Any relative paths
> specified are not transformed to absolute paths.

So `./in/file.txt` and `/usr/sap/trans/in/file.txt` are different strings to the check
even when they resolve to the same file. **Always use absolute physical file names.**
`AUTHORITY_CHECK_DATASET` lets you test the authorization before the statement instead
of catching the exception.

### Directory traversal

A file name that arrives from a selection screen, an RFC parameter or an OData payload
and goes straight into `OPEN DATASET` is a directory traversal vulnerability — `../`
segments walk out of the interface directory. `SPTH` *does* normalise `../` before its
own check, but that protects the system's rules, not your intent.

The fix is not hand-rolled string checks:

- Use **logical file names** (transaction `FILE`) resolved through `FILE_GET_NAME`.
  The doc states that if a program uses logical names exclusively, validation is not
  usually necessary — and you get platform-independent paths for free.
- If a physical name must be accepted, validate it with `FILE_VALIDATE_NAME` against a
  logical file name or path.

— [Directory Traversal](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYN_FILE_SCRTY.html),
[Automatic Authorization Checks](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENFILE_INTERFACE_AUTHORITY.html)

---

## Checklist

| Situation | Do this |
|---|---|
| Any `OPEN DATASET` | add `MESSAGE lv_msg` and check `sy-subrc = 8` |
| Reading a UTF-8 file | `ENCODING UTF-8 SKIPPING BYTE-ORDER MARK` |
| Writing a text file | `ENCODING UTF-8 WITH BYTE-ORDER MARK` |
| Binary read loop | use `ACTUAL LENGTH`, do not exit on `sy-subrc = 4` alone |
| Writing fixed-width records | `TRANSFER ... LENGTH len`, or binary mode |
| Deterministic line endings | `WITH UNIX LINEFEED` (or `WINDOWS`) |
| After `TRANSFER` | `TRY ... CATCH cx_sy_file_io` — the `sy-subrc` check is useless |
| Any file name from outside | `FILE_GET_NAME` / `FILE_VALIDATE_NAME`, absolute paths only |
| Every open file | explicit `CLOSE DATASET`, including on the error path |

## Sources

- [`OPEN DATASET`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPOPEN_DATASET.html)
- [`OPEN DATASET, access`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPOPEN_DATASET_ACCESS.html)
- [`OPEN DATASET, mode`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPOPEN_DATASET_MODE.html)
- [`OPEN DATASET, encoding`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPOPEN_DATASET_ENCODING.html)
- [`OPEN DATASET, error_handling`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPOPEN_DATASET_ERROR_HANDLING.html)
- [`READ DATASET`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPREAD_DATASET.html)
- [`TRANSFER`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPTRANSFER.html)
- [`CLOSE DATASET`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCLOSE_DATASET.html)
- [`DELETE DATASET`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPDELETE_DATASET.html)
- [Automatic Authorization Checks (`S_DATASET`, `SPTH`, `S_PATH`)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENFILE_INTERFACE_AUTHORITY.html)
- [Directory Traversal](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENDYN_FILE_SCRTY.html)

Runnable demo: [`ydj_dataset_traps_demo.abap`](ydj_dataset_traps_demo.abap)
