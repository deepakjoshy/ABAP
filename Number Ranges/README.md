# Number Ranges — Buffering, Gaps, and NUMBER_GET_NEXT

Number range objects (transaction `SNRO`) are the standard way to hand out unique
document numbers. The part that bites people in production is **buffering**: a
correctly coded `NUMBER_GET_NEXT` call can still produce numbers that are
non-ascending and full of gaps, and that is *working as designed*, not a bug.

## Which buffering is my object using?

`SNRO` -> object -> attributes/customizing tab shows the buffering type and buffer
size. In a dump or the debugger the same information is in `TNRO-BUFFER`:

| `TNRO-BUFFER` | Meaning |
|---|---|
| `SPACE` | no buffering |
| `X` | main memory buffering |
| `L` | local buffering (obsolete) |
| `P` | extended local buffering |
| `S` | parallel buffering |

**A buffer size of 0 means "not buffered", whatever the type field says.**

Many objects are reached through an application-specific transaction rather than
`SNRO`, so the object name is not on screen. Two ways to find it:

- Start the number range transaction (e.g. `FBN1`), type `/h`, and read `TNRO-OBJECT`
  in the debugger — for `FBN1` that is `RF_BELEG`.
- Or `SE16` on table `TNRO` with `CODE = <transaction>`.

## Why buffered ranges produce gaps

With main memory buffering, the kernel pre-fetches a block of numbers (size = *No.
of Numbers in Buffer* in `SNRO`) from table `NRIV` into shared memory on **each
application server**. Consequences a developer has to plan for:

- **Gaps on rollback.** A number taken from the buffer is *not* returned to it on
  `ROLLBACK WORK`. It is simply lost.
- **Gaps on restart.** The pre-fetched block is committed to `NRIV` immediately,
  before the numbers are handed out. If the instance shuts down, the whole
  remaining block is gone — a gap the size of the buffer, per active server.
- **Non-ascending numbers.** Two app servers hold two different blocks, so the
  order in which documents are created has nothing to do with the order of the
  numbers.
- `SM56` is the admin transaction for the buffer (statistics, entries, reset).
  The buffer is reset automatically when an interval is changed in `SNRO`/`SNR0`.

If the numbering must be gapless (legal requirement in several countries for FI/SD
documents), the object has to be **unbuffered** — SAP ships `RF_BELEG` and
`RV_BELEG` that way. The reverse — de-buffering an object SAP delivers as buffered
— counts as a customer modification and can wreck performance in that application
area (SAP Note 678501).

## Calling it from ABAP

`NUMBER_GET_NEXT` is the classic API. The two parameters worth remembering:

- `quantity` — reserves a *block* of numbers. The `number` returned is the **last**
  number of the reserved block, so the block is `number - quantity + 1 .. number`.
  Getting this backwards is a common source of duplicate keys.
- `ignore_buffer = 'X'` — bypasses the buffer for this one call and reads `NRIV`
  directly. Useful when a single object is normally buffered but one caller needs
  strict sequencing. It costs a database access with a lock, so do not use it in a
  loop.

`returncode` is an **exporting** parameter, not an exception, and it is easy to
ignore by accident. A value of `'1'` means the number was taken from the *critical
area* — the interval is near exhaustion (the warning threshold is a percentage set
in `SNRO`, 10% by default). That is the hook for "number range almost full" alerts;
check the F1 documentation in your release for the remaining values.

See [`ydj_number_range_demo.abap`](ydj_number_range_demo.abap) for a runnable
wrapper with the block arithmetic and the critical-area check in place.

## Rules of thumb

- Never derive business meaning from the number itself (no "higher number = created
  later", no "gap = missing document").
- Never reuse a number that came back from a rolled-back LUW.
- Draw numbers **as late as possible** in the LUW, right before the `INSERT`, to
  minimise how many are lost to rollbacks.
- Do not implement your own `SELECT MAX( ) + 1` to avoid gaps. It serialises the
  whole table, deadlocks under load, and still gaps on rollback.

## Sources

- [How the Number Range Buffer Works](https://help.sap.com/saphelp_ewm900/helpdata/en/47/d5659d167e3c84e10000000a42189c/content.htm) — SAP Help Portal
- [Administration of the Number Range Buffer (SM56)](https://help.sap.com/saphelp_ewm900/helpdata/en/47/d565a3167e3c84e10000000a42189c/content.htm) — SAP Help Portal
- [Buffering Number Ranges and Legal Framework](https://community.sap.com/t5/technology-blog-posts-by-sap/buffering-number-ranges-and-legal-framework/ba-p/12953573) — SAP Community
- SAP KBA 1843002 — Gaps and jumps in number range assignment
