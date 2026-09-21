# Text Elements — The Text Symbol That Silently Becomes a Blank

Text symbols, selection texts and list headers are the **text elements** of an
ABAP program. They are not declared in the source: they live in a separate
repository object called the **text pool**, one per language, maintained in
`SE38 -> Goto -> Text Elements` (or the Text Elements tab in ADT).

That split is the whole topic. The source says `TEXT-001`; whether that
produces your text, a *different* language's text, or a single blank is decided
by a repository object you did not transport, in a language you did not test,
with **no syntax error and no runtime exception** in any of those cases.

The one sentence that matters, from the keyword documentation:

> "If the text symbol does not exist in the currently loaded text pool,
> `text-idf` is handled like an initial single-character text field."

An initial single-character text field is a blank. Not a dump, not an empty
string you could test for with a meaningful error — a blank. A report header
that reads `Posting run for company code` in dev prints a lone space in
production, and every `sy-subrc` on the way is 0.

Related notes: [String Processing](../String%20Processing#readme) for why a
type `c` text symbol loses its trailing blanks in `&&` and
[Selection Tables](../Selection%20Tables#readme) for the selection screen these
texts label.

Runnable demo: [ydj_text_symbol_demo.abap](ydj_text_symbol_demo.abap) — it
reads its own text pool, so it demonstrates the fallback live even before you
maintain a single text element.

## The two spellings are not equivalent

```abap
" Form 1: bare symbol. If the symbol is missing -> a BLANK.
WRITE: / TEXT-h01.

" Form 2: literal linked to a symbol. If the symbol is missing -> 'Posting run'.
WRITE: / 'Posting run'(h01).
```

Both compile. Both are the same data object when the text pool is complete.
They differ only on the day something is wrong — and form 2 is the one that
degrades into readable English instead of whitespace:

> "If the text symbol exists in the currently loaded text pool, it replaces the
> literal. If the text symbol does not exist, the literal is used."

This is the single highest-value habit in the topic. **Always write the
literal form.** It costs nothing, it documents the text at the point of use for
the next developer, and it removes the entire failure mode below.

## Trap 1: the text pool is chosen by logon language, and can be empty

When a program is loaded into an internal session, the runtime imports the text
pool of the **logon language**. The documented fallback chain:

1. text pool of the logon language, else
2. text pool of the **secondary language** of the AS ABAP
   (profile parameter `zcsa/second_language`), else
3. "an empty text pool without text elements is loaded".

Step 3 is not an error state. There is no message, no `sy-subrc`, no dump. If
the program was only ever translated into EN and a user logs on in DE on a
system with no secondary language configured, *every* bare `TEXT-xxx` in that
program is a blank for that user, and only for that user.

This is why the bug report is always "the report looks broken for the Germany
team" and never reproduces for the developer.

The same applies to background jobs: the job step runs under the language of
the job, not yours.

## Trap 2: a typo in the ID is not an error

`idf` is a three-character ID of alphanumeric characters and `_`. There is no
check that it exists. `TEXT-h01` where the maintained symbol is `h10` compiles
cleanly and prints a blank forever. The literal form turns that same typo into
a visible, correct-looking English text instead — wrong language, but not
missing.

There is no extended-check equivalent here that makes the bare form safe, so
the mitigation is the convention, not a tool.

## Trap 3: `text` is a reserved-looking name that will bite a structure

Straight from the documentation:

> "The identifier `text-idf` is reserved for text symbols. A structure called
> `text` cannot have any components with three-character names. It is best
> never to call a structure `text`."

`DATA text TYPE ty_something.` where the structure happens to have a component
named `key`, `id` or `lng` produces syntax errors whose message has nothing to
do with text symbols. Particularly nasty when `text` is typed with a *global*
DDIC structure, because the colliding component can be added later by someone
else and break your program at activation.

## Trap 4: a text symbol is type `c` of a fixed length, not a `string`

A text symbol "has the data type `c` and the length defined in the text
elements by `mlen`". Two consequences:

- The maximum length is maintained per symbol. A translation longer than
  `mlen` cannot be stored — the Workbench offers to shorten it. Leave headroom:
  the documentation's own example is that English *window* (6) needs
  *Fenster* (7) in German. A symbol sized to fit the English text exactly is a
  truncated text in half of Europe.
- It is a fixed-length field, so its trailing blanks follow the rules in
  [String Processing](../String%20Processing#readme): they vanish in `&&` and
  in most operand positions, but `strlen( )` over a `c` field ignores them
  while a `string` copy keeps them. Concatenating two text symbols without a
  separator gives you `PostingrunCompany code`, which is the usual cause of
  "the translation lost its space".

## Trap 5: `SET LANGUAGE` does not do what its name suggests

```abap
SET LANGUAGE lv_langu.        " loads a text pool
SET LOCALE LANGUAGE lv_langu. " sets the text environment - unrelated statement
```

`SET LANGUAGE` loads the **list headers and text symbols** of another language
for the *current program only* — not for programs it calls. Three documented
edges:

- It does **not** load selection texts. The selection screen keeps the old
  language. `READ TEXTPOOL` plus `SELECTION_TEXTS_MODIFY` is the documented
  route if you need those too.
- If the requested language has no pool, the secondary language is loaded
  instead; if there is no secondary language either, `sy-subrc = 4` and **the
  program carries on with the previous text pool**. Unchecked, you print the
  old language and believe you switched.
- Symbols that were present in the old pool and are missing in the new one are
  *initialized* — so a partial translation is worse than none: the untranslated
  symbols become blanks rather than staying English.

There is deliberately no `GET LANGUAGE` statement.

## Trap 6: `READ TEXTPOOL` has two formats you must know to parse it

`READ TEXTPOOL prog INTO itab LANGUAGE lang.` fills a table of DDIC structure
`TEXTPOOL`. Rows are identified by `ID` + `KEY`:

| `ID` | `KEY` | `ENTRY` |
|---|---|---|
| `H` | 001..004 | list header column headers |
| `I` | ID of a text symbol | text of the text symbol |
| `R` | - | program title |
| `S` | parameter / select-option name | selection text |
| `T` | - | list header title bar |

Two formatting rules that are not guessable:

- For selection texts **not** taken from the Dictionary, "the actual text in
  `ENTRY` is preceded by eight blanks". Read `ENTRY` raw and every selection
  text looks indented; `CONDENSE` or `ENTRY+8` is required.
- Selection texts taken from the ABAP Dictionary **are not stored in the text
  pool at all** and cannot be read this way. They are marked with a `D` in the
  first position of `ENTRY`. Function module `RS_TEXTPOOL_READ` reads those.

Other edges: `sy-subrc = 4` means the program, the language, or the pool does
not exist — and is *always* 4 for program types that have no text pool at all.
For **global classes and function pools you must pass the master program name**,
not the class or function group name, because the pool is attached to the
generated master program.

## Trap 7: `INSERT TEXTPOOL` overwrites the whole pool

> "If a text pool for the specified language already exists, all its text
> elements are overwritten." ... "If the internal table is empty, all text
> elements of an existing text pool are deleted."

So the read-modify-write pattern must be *read the whole pool*, change one row,
write it back. A well-meaning "insert just my new symbol" deletes every other
text element for that language, including the program title and every selection
text. It always sets `sy-subrc = 0`, so there is no failure signal, and invalid
`ID`/`KEY` values or duplicates produce "an inconsistent text pool" rather than
a rejection.

`LENGTH` is the translation headroom (`mlen`), and if it is shorter than the
text in `ENTRY` it is silently raised to the actual text length.

## Quick reference

| Situation | Result |
|---|---|
| `TEXT-abc`, symbol missing | one blank, no error |
| `'Text'(abc)`, symbol missing | `Text` |
| No pool in logon language, no secondary language | empty pool, all symbols blank |
| `SET LANGUAGE` with no pool and no secondary | `sy-subrc = 4`, old pool still active |
| `SET LANGUAGE`, symbol missing in new pool | symbol initialized to blank |
| `READ TEXTPOOL` for a global class | pass the **master program** name |
| Selection text from the Dictionary | not in the pool; `D` in `ENTRY(1)` |
| `INSERT TEXTPOOL` with empty table | deletes every text element |

## Rules of thumb

- Write `'Literal'(idf)` everywhere. Never a bare `TEXT-idf` in new code.
- Size `mlen` generously — assume translations are 30-50% longer.
- Never name a structure `text`.
- Always check `sy-subrc` after `SET LANGUAGE`; it fails silently by design.
- Never `INSERT TEXTPOOL` without having `READ TEXTPOOL` first.
- Hard-coded English in a `WRITE` is not a smaller sin than a missing text
  symbol — but a missing text symbol is the one that is invisible in code
  review, because the source reads perfectly.

## Sources

- [Text Symbols](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENTEXT_SYMBOLS.html) — type `c`/`mlen`, the missing-symbol blank rule, the literal-link fallback, the `text` structure warning, the *window*/*Fenster* length hint
- [Text Pools](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENTEXT_POOL.html) — logon language -> secondary language -> empty pool, supported program types, the master-program rule for classes and function pools
- [SET LANGUAGE](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSET_LANGUAGE.html) — current program only, no selection texts, `sy-subrc` table, missing symbols initialized, `SET LOCALE LANGUAGE` is a different statement
- [READ TEXTPOOL](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPREAD_TEXTPOOL.html) — the `ID`/`KEY` table, eight-blank prefix, the `D` marker for Dictionary selection texts, `sy-subrc` for programs without pools
- [INSERT TEXTPOOL](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPINSERT_TEXTPOOL.html) — full overwrite, empty-table deletion, always `sy-subrc = 0`, `LENGTH` auto-raise, the eight-blank/`D` rules for writing
