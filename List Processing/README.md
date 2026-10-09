# Classic Lists & `WRITE` — the output length that comes from the type, the minus sign on the right and the list level you are allowed to overwrite

Every runnable demo in this repo ends in a `WRITE` statement. Eighty-odd notes use
it as the way to show a result, and not one of them explains what it does — which
is a gap worth closing, because `WRITE` is the one ABAP statement that **formats
on your behalf using information you did not supply**: the output length comes
from the *type*, the separators come from the *user's* country setting, and the
rightmost column is reserved for a sign you never asked for.

The result is a family of defects with the same signature: no syntax error, no
exception, no `sy-subrc`, and output that looks almost right.

```abap
DATA lv_amount TYPE p LENGTH 8 DECIMALS 2 VALUE '-1234.56'.
DATA lv_date   TYPE d.

lv_date = sy-datum.

WRITE: / lv_amount,      " prints the minus sign on the RIGHT:  1,234.56-
       / lv_date.        " output length for d is 8 - no room for separators
WRITE: / (10) lv_date.   " 10 columns, so the separators appear
```

And the part that decides whether the topic is worth learning at all, from SAP's
own overview page:

> `"Classic lists are no longer intended to be used directly in production programs. The use of other suitable output media is recommended instead."`

So this note is not an argument for writing new list reports. It is for the two
situations every ABAP developer actually meets: reading the thousands of existing
ones, and understanding why a `WRITE`-based demo (including the ones in this repo)
prints what it prints.

Related notes:
[Numeric Arithmetic](../Numeric%20Arithmetic#readme) — the conversion rules that
decide the digits before `WRITE` lays them out;
[String Templates](../String%20Templates#readme) — the modern replacement, and the
one whose `WIDTH` cannot shorten a value where an output length can;
[Currency Amounts](../Currency%20Amounts#readme) — the TCURX shift that happens
before any of this;
[Conversion Routines](../Conversion%20Routines#readme) — the Dictionary conversion
exit `WRITE` runs for you;
[Screen Modification](../Screen%20Modification#readme) — the other half of the
classic SAP GUI dialog;
[Messages](../Messages#readme) — why a type `E` message in `START-OF-SELECTION`
leaves you with an empty list;
[Checkpoints](../Checkpoints#readme) — the uncatchable-exception family `HIDE`
belongs to.

Runnable demo: [ydj_list_output_demo.abap](ydj_list_output_demo.abap) — a classic
report, no database access, no file access.

---

## 1. The output length comes from the type, and three built-in types cannot show their own content

An output length is attached to every single output:

> `"Each time a data object is output by a WRITE, an output length is defined, either implicitly in accordance with the tables below, or explicitly if len is specified after the addition AT."`

The predefined lengths are the whole story, and several rows of the table are
traps rather than conveniences:

| Type | Predefined output length | Consequence |
|---|---|---|
| `i` | 11 | fine — fits every value plus the sign |
| `s` | 5 | **not enough** for a 5-digit value *and* its sign |
| `p` | 2 x length of `dobj` (+1 if there is a decimal separator) | fine until the decimals outgrow the digits |
| `c`, `n` | length of `dobj`, max 255 | silently capped at 255 |
| `d` | 8 | **no room for the date separators** |
| `t` | 6 | **no room for the time separators** |
| `string` | number of columns required | always complete |
| enumerated type | 30 | name of the enumerated value |

The documentation is explicit about the two that bite:

> `"The predefined output lengths given in the table above for the types d and t are not sufficient to display the corresponding separator."`

> `"The predefined output length specified in the table above for the type s is not sufficient to display the sign for a 5-digit number."`

and repeats the `s` warning from the formatting side, generalised to `b`:

> `"For the data types b and s, it should be noted that the predefined output lengths for lists ignore the place that is reserved for the plus/minus sign, which can lead to unexpected results."`

This is why the documentation's own `READ LINE` example writes a date as
`(10) date` rather than `date`, and says so plainly:

> `"A target field wa with length 10 is used for the date, since this is the length of the output area and contains separators."`

So `WRITE sy-datum` is *not* the same thing as `WRITE (10) sy-datum`, and the
difference is not cosmetic — it changes what a downstream parser of the spool
list receives. `p` has a subtler version of the same problem:

> `"If, in the case of type p, the number of decimal places is greater than the number of digits calculated from 2 x the length of dobj - 1, the predefined length is not enough. This is because the decimal separator is outside the string of digits and must be padded with zeros."`

### What happens when the length is too short

Not an exception. A character:

> `"If there is not enough space available to display a number using these rules, an exception is raised for decimal floating point numbers only. Other numeric types are truncated and flagged with *."`

So a too-narrow numeric output arrives as `*`-marked garbage, while a decimal
floating point number raises `CX_SY_CONVERSION_OVERFLOW` instead — the same
value, two completely different failure modes depending on the declared type.
The asterisk convention extends to the `decfloat` exceptions as well:

> `"If one of the following catchable exceptions is raised in the output of a decimal floating point number, the target field or output of the statement WRITE is filled using asterisks (*)."`

### The fixes, in order of preference

- `WRITE AT (len) dobj` — an explicit absolute length.
- `WRITE (*) dobj` / `WRITE (**) dobj` — let the runtime size it:
  > `"With *, the minimum possible length is used, and with **, the maximum possible length is used."`
- **Not** `WRITE dobj(len)` (substring access), which the documentation
  specifically argues against:
  > `"Specifying the output length len after AT should always be preferred over specifying a length for the data object dobj (substring access)."`

  with a reason that matters for interactive lists:
  > `"Furthermore, the assignment of the list output to the data object is lost during substring access, which means that it can no longer be addressed in the list."`

  i.e. a substring-written field can no longer be reached by `READ LINE ... FIELD
  VALUE`, `MODIFY LINE ... FIELD` or `WRITE ... UNDER` — the field loses its
  identity in the list buffer. This is the single most common reason a
  `FIELD VALUE` read "mysteriously" returns nothing.

One last source of surprise: a Dictionary type overrides the table above
entirely.

> `"For data objects whose data types are defined in reference to the ABAP Dictionary, a different output length can be specified in the corresponding domains or using the built-in type. The output length specified here is used instead of the implicit output length from the table above."`

So retyping a field from `c LENGTH 10` to a Dictionary data element can change
your column layout without a single line of your code changing.

---

## 2. The rightmost column is the sign, so negative numbers print their minus on the right

This is the behaviour that produces the classic `1,234.56-` in SAP spool output,
and it is not a quirk of a particular report — it is the predefined format:

> `"In the numeric data types (b, s), i, int8, and p, the last place on the right is reserved for the sign (this also applies to b, even though these numbers are always positive). Here, negative values are given a minus - in the result and positive values a blank."`

Two things follow that cost real time:

1. **Every positive number also pays for the sign.** A blank is still a column.
   This is why `WRITE` output never quite lines up with the width you expected,
   and why right-aligning a numeric column by hand always looks one off.
2. **The output is not a number any more.** Not because of the sign, but
   because of the separators:
   > `"The thousands separators defined in the user master record are inserted if the available length is sufficient."`

   and the documentation draws the conclusion itself:
   > `"The statement WRITE TO is mainly suited for formatting data for output purposes but not for further internal processing. For example, a field can no longer be handled as a numeric data object if the decimal separator is represented as a comma."`

The separators come from the *user*, not from the program:

> `"Apart from one exception, numbers, date formats, and time formats are determined by the current formatting setting of the language environment, which can be set using SET COUNTRY."`

Which is the real headline: **the same report produces different text for
different users.** A German user's `1.000,00` and a US user's `1,000.00` are the
same `WRITE` statement. If anything downstream parses that text — an interface
file, a `%PC` download, a screen-scraped spool — the defect is user-dependent
and will not reproduce on the developer's own logon. Date formatting has the
same property, plus one extra hazard:

> `"A date field is formatted regardless of its content."`

No validation. A `d` field holding `'00000000'` or junk is laid out as a date
anyway. (The same sentence appears for type `t`.)

Alignment is predefined per type and also worth knowing before building columns:
numeric types are **right-aligned**, character-like, byte-like, date and time
types are **left-aligned**. And for fixed-length character types:

> `"In the case of character-like data types with a fixed length (c, n), trailing blanks are cut off."`

which is the `WRITE` side of the trailing-blank rules already documented in
[String Processing](../String%20Processing#readme).

---

## 3. Positioning fails silently in three different ways

`WRITE [AT] [/][pos][(len)] dobj` looks like an instruction. It is closer to a
request.

**The `/` that is ignored.** A newline is dropped whenever the cursor was not
placed by a previous output statement:

> `"If specified immediately after the position of the list cursor in a list line that is not the result of a previous output statement, / is ignored. This is the case during initial writing to a list page, and after explicit positioning with the statements SKIP, NEW-LINE, NEW-PAGE and BACK."`

So `SKIP. WRITE / 'Total'.` does **not** produce a blank line followed by
`Total`; the `/` is discarded and `Total` lands in the line `SKIP` moved to.

**The `pos` that is ignored, and the one that produces nothing at all:**

> `"If the value in pos is less than 1, it is ignored. If it is greater than the current list width, there is no output."`

A computed column that comes out as `0` writes at the cursor instead; one that
comes out wider than `sy-linsz` writes **nowhere**, with no exception and no
`sy-subrc`. A column loop that drifts past the line width simply stops producing
output, and the list looks like the data ran out.

**The `UNDER` that is ignored.** Column alignment by reference is string-matched
against the earlier statement:

> `"The data object other_dobj must be written exactly as in the corresponding WRITE statement, including all possible specified offset/lengths and so on. If the data object other_dobj was not specified before, the addition is ignored."`

Editing the header `WRITE` — adding a length, renaming a literal — silently
unhooks every `UNDER` that referred to it. The columns go back to the natural
cursor position and nothing reports it.

Also worth having in mind while reading old code: after a normal output

> `"After the output is displayed, the list cursor is positioned by default in the second place after the output"`

— two places, not one, which is what `NO-GAP` suppresses, and overwriting an
existing output behaves differently again:

> `"The output position of existing outputs in the list buffer is overwritten with the output length of the new output."`

---

## 4. The line that contains nothing is not written at all

This default is responsible for a whole class of "my line numbers are off" bugs:

> `"If the addition OFF is specified (default), all subsequent lines that contain only blanks after a line break are not written to the list."`

and it is not fooled by list elements:

> `"Blank lines are suppressed regardless of the formatting of the output. Lines that contain only empty checkboxes or input fields are also suppressed."`

So a selection list built as `WRITE / lv_flag AS CHECKBOX, lv_text.` loses
**every row where both are initial** — the rows are not blanked, they are absent.
Everything keyed on line numbers afterwards (`HIDE`, `READ LINE idx`,
`sy-lilli` arithmetic) is then shifted by an amount that depends on the data.
`SET BLANK LINES ON.` is the switch, and `SKIP` is explicitly not affected:

> `"Blank lines created using SKIP are independent of the statement SET BLANK LINES. They do not contain any output."`

Two more content-level surprises in the same family:

> `"If the start of a character string, which is output with WRITE, contains an internal ID (key or internal name) for an icon at the beginning between two characters @, this is displayed in the list as an icon, even without the addition AS ICON. This can cause unintentional output of icons and unexpected effects on the output length since the latter is determined by the length of the character string by default."`

User-supplied text that happens to start `@...@` becomes a picture and changes
its own width. And:

> `"Control characters for line feeds or tabs are ignored in strings that are displayed using WRITE. These characters are displayed as #, like all other non-displayable characters."`

(The sentence says both *ignored* and *displayed as `#`* — the observable
behaviour in a list is the `#`. Quoted as written rather than resolved here.)

---

## 5. 21 lists, and `sy-lsind` is the system field you are *supposed* to overwrite

The list buffer is a fixed-depth stack:

> `"A single list buffer can contain up to 21 lists, a basic list and 20 details lists."`

> `"The current list after the call of a dynpro sequence is the basic list. If the basic list is not displayed, no other list levels can be created."`

That second sentence is the reason a report that writes nothing in
`START-OF-SELECTION` can never reach `AT LINE-SELECTION`: with no basic list
displayed, there is no event to raise. Once displayed, the list is frozen:

> `"Displaying this list closes it in the list buffer. It can no longer be written to, but it can be read or modified."`

A detail list only comes into existence if you wrote the handler:

> `"Every user action on a displayed list that raises a list event for which an event block is defined in the ABAP program, creates a new details list."`

And during event processing there are *two* current list levels, which is why
`sy-lsind` and `sy-listi` are both needed:

> `"The list with the highest list index (sy-lsind) is always the current list of the ABAP program, while the list with the list index one below the highest (sy-listi) is displayed on the screen."`

Now the part that is genuinely unusual in ABAP. `sy-lsind` is writable, and
writing it **deletes lists**:

> `"Within an event block for a list event, a value is assigned to the system field sy-lsind. If the value of sy-lsind after the event block is closed is less than the list index of the current list and greater than or equal to 0, the current list replaces the list of this list level and all lists whose list index is greater than the value of sy-lsind are deleted from the list buffer. Other values of sy-lsind are reset to the index of the current list after the event block is closed."`

Read that against the usual expectations and three results fall out:

- `sy-lsind = 0` is the documented way to replace the basic list with the list
  you just built — and it **discards the entire stack above it**.
- An out-of-range or larger value is not an error and not a jump: it is
  *silently reset*. `sy-lsind = 99` does nothing at all.
- The assignment takes effect **after the event block is closed**, not where it
  is written. So a later statement in the same block can overwrite it, and the
  navigation you think you performed in the middle of a handler has not happened
  yet.

Two more sizes worth knowing, both documented rather than folklore:

> `"A list is made up of list lines with a fixed width of up to 1023 characters."`

> `"A page can contain a maximum of 60000 lines."`

and one system-field inconsistency that has cost people an afternoon:
`sy-colno` (column of the list cursor) counts from **1**, while `sy-cucol`
(column of the GUI cursor on the displayed list) counts from **2** — stated
per-row in the system-field table as *"Counting begins at 1."* and *"Counting
begins at 2."* respectively. A handler that compares the two directly is off by
one.

---

## 6. `HIDE` is per-line storage, not a variable capture — and it refuses to work in modern code

`HIDE` is how a classic interactive list remembers which business key a line
belonged to. The mechanism is not a closure over your variable; it is a
side-table keyed by line number:

> `"This statement stores the content of a variable dobj together with the current list line whose line number is contained in sy-linno in the hide area of the current list level."`

The values come back by **assignment**, at two documented moments:

> `"Any user action on a displayed screen list that causes a list event assigns all values saved using HIDE to the relevant variables."`

> `"If a list line of a list level is read or modified using the statements READ LINE or MODIFY LINE, all values of this line stored using HIDE are assigned to the relevant variables."`

Which produces the trap the documentation does *not* spell out, so it is flagged
here as an inference rather than a quotation: the docs say only that *saved*
values are assigned. For a line where nothing was saved — a header line, a
`ULINE`, a line written in a different loop — **nothing is assigned and the
variable keeps whatever it last held.** The handler then processes the previously
clicked row with `sy-subrc = 0` and no indication at all. This is exactly the
stale-read shape documented for `READ TABLE ... ASSIGNING` in
[Field Symbols](../Field%20Symbols#readme), and the fix is the same: initialise
to a sentinel before the read and check it after, rather than trusting the value.

The restrictions are where `HIDE` collides with everything written since 1999:

> `"The data type of the variable dobj must be flat and no field symbols or components of boxed components can be specified that point to lines of internal tables, and no class attributes can be specified."`

**No class attributes.** `HIDE` cannot store `me->mv_key` or a static attribute
at all — which, together with the overview page's warning that list statements
*"are based on global data and events of the runtime framework and are no longer
completely supported in ABAP Objects"*, is the concrete reason classic
interactive lists and ABAP Objects do not mix. And the companion rule:

> `"Cause: HIDE in a local field is not possible."` — runtime error `HIDE_NO_LOCAL`

So moving a `WRITE`/`HIDE` loop out of `START-OF-SELECTION` into a subroutine or
method with local variables turns a working report into a dump. The field has to
be global — which is why the demo beside this note is written procedurally with
global declarations, against the repo's usual local-class habit. The full
uncatchable set is worth recognising in a short dump: `HIDE_NO_LOCAL`,
`HIDE_NOT_GLOBAL`, `HIDE_FIELD_TOO_LARGE`, `HIDE_ILLEGAL_ITAB_SYMBOL`,
`HIDE_ON_EMPTY_PAGE` (*"HIDE is not possible on an empty page."*) and
`HIDE_TOO_MANY_HIDES` (*"Permitted number of HIDE statements per list line
exceeded"*). None are catchable, so a `TRY` block is no defence — see
[Checkpoints](../Checkpoints#readme).

Two placement rules complete the picture:

> `"The HIDE statement should be executed directly in the statement that has set the list cursor in the line."`

> `"The HIDE statement works independently of how the list cursor was set. In particular, variables can also be stored for empty list lines, that is, lines in which the list cursor was positioned using statements like SKIP."`

and a design hint from SAP's own example, which is good advice generally:

> `"In the real world, one would more likely save only the number and execute the calculation, when required, in the event block for AT LINE-SELECTION."`

Store the key. Re-derive everything else.

---

## 7. `READ LINE` reads the list buffer — formatted text, not your data

> `"This statement assigns the content of a line stored in the list buffer to the system field sy-lisel, and allows other target fields to be specified in result. In addition, all values for this line stored using HIDE are assigned to the respective variables."`

`sy-lisel` is the **rendered** line: output lengths applied, separators inserted,
sign on the right, everything from sections 1 and 2 already baked in. Parsing it
by offset is parsing your own formatting decisions, which is why
`READ LINE ... FIELD VALUE` exists — and why the documentation's example needs a
wider target than the source field:

> `"If an assignment was made to the output field date, the area length would be reduced."`

Reading a 10-column formatted date back into the `d` field it came from would
shrink the field's output area in the list. The target has to be a `c LENGTH 10`.

Three defaults decide which line you actually get:

> `"If the addition INDEX is not specified, the list level 0 (the basic list itself) is selected when the basic list is created and the list level at which the event was raised (sy-listi) is selected when a list event is processed."`

— so inside a handler, bare `READ LINE n` reads the **displayed** list, not the
detail list you are currently writing. Also:

> `"CURRENT PAGE indicates the topmost displayed page of the list, on which the last list event has taken place. No line is selected while creating the basic list."`

> `"For the addition CURRENT LINE, the line on which the screen cursor was positioned during a preceding list event (sy-lilli), or the last line read with a preceding READ LINE statement, is selected."`

`CURRENT LINE` moves as you read — a loop of `READ CURRENT LINE` walks forward
rather than re-reading the same line. `sy-subrc` is the only termination signal
(*"Not 0 | The specified line does not exist."*), and there is no count to check
first.

`MODIFY LINE` is the write-back twin, with two restrictions that look like bugs
when met in the wild:

> `"The first output of a data object in the list buffer with the statement WRITE defines the output length, which cannot be changed by the MODIFY statement."`

> `"The statement MODIFY ignores any specified alignments that are specified for the output with WRITE and CENTERED, RIGHT-JUSTIFIED."`

So you cannot widen a column on update, and a centred or right-justified field
comes back left-aligned. SAP's own recommendation is to not touch `sy-lisel` at
all:

> `"It is recommended that the system field sy-lisel is filled with the content of the list line to be changed before the statement MODIFY LINE is executed, and that the line is modified exclusively using the information in source, not by changing sy-lisel."`

---

## 8. The event is bound to a function code, not to a mouse

`AT LINE-SELECTION` is not "the double-click handler". It is the handler for one
function code:

> `"This statement defines an event block whose event is raised by the ABAP runtime framework when a screen list is displayed if the screen cursor is on a list line and a function is selected using the function code PICK."`

The double-click only reaches it because defining the block rewires the standard
GUI status for you:

> `"By defining this event block, the standard list status is enhanced automatically in such a way that the function code F2 and, with it, the double-click mouse functionality is linked with the function code PICK."`

> `"If the function key F2 is linked with a function code other than PICK, each double click raises its event, usually AT USER-COMMAND, and not AT LINE-SELECTION."`

Which is the whole trap in one line: **the moment you add `SET PF-STATUS` with
your own GUI status, double-click can stop reaching your handler** — silently,
because `AT USER-COMMAND` happily receives it instead. Nothing is broken, nothing
dumps, the detail list just never appears.

In the other direction, `AT USER-COMMAND` does not receive everything either:

> `"The function codes PICK and PFnn (nn stands for 01 to 24) do not raise the event AT USER-COMMAND, and instead raise the events AT LINE-SELECTION and AT PFnn."`

> `"All function codes that start with the character % are interpreted as system functions and do not raise the event AT USER-COMMAND."`

and a third, longer list is swallowed by the list processor itself — `BACK`,
`RW`, `PRI`, `PRINT`, `PNOP`, `PFILE`, and the whole scrolling family (`P+`,
`P-`, `PP+n`, `PL+n`, `PS+n`, `PPn`, `PSn`, `PZn`). So a custom toolbar button
given the function code `BACK` or `PRI` will never reach your `CASE sy-ucomm`.
Pick names that are not in these three sets; `sy-ucomm` is filled before the
block starts (*"The function code is available in the system field sy-ucomm when
processing starts."*).

### Page headers are per-event-block too

> `"If no addition is specified, an event block is raised for the event TOP-OF-PAGE when a basic list is created. If the addition DURING LINE-SELECTION is specified, an event block is raised for the corresponding events when details lists are created. System fields like sy-lsind must be used to distinguish between the individual details lists."`

A plain `TOP-OF-PAGE` runs for the basic list **only** — which is why detail
lists famously appear with no header until someone adds
`TOP-OF-PAGE DURING LINE-SELECTION`. Inside either block:

> `"The statement NEW-PAGE is ignored within this event block."`

`NEW-PAGE` itself has two documented non-behaviours:

> `"The statement NEW-PAGE cannot be used to create empty pages."`

> `"The statement NEW-PAGE does not raise the list event END-OF-PAGE. This list event is raised only if the page footer or page end is reached when the list is being written."`

So page-break logic that assumes `NEW-PAGE` triggers the footer never fires it,
and a footer can only be filled in `END-OF-PAGE` at all. Two doc-state notes
while in this area, recorded rather than silently repaired: the `TOP-OF-PAGE`
page says the placeholders `&1` – `&9` are replaced from `sy-tvar0` – `sy-tvar9`
(nine placeholders against ten fields as written), and it contains the garbled
sentence *"It is not possible to output lines than are available on the page
within the event block."* — the intent is evidently that the block cannot output
more lines than the page has room for.

### Lists from a dynpro

> `"After the current dynpro is processed, this statement interrupts the current dynpro sequence, starts the list processor, and displays the basic list. The basic list consists of any list output of all PBO and PAI modules of the dynpro sequence executed to this point."`

Two consequences: `LEAVE TO LIST-PROCESSING` collects output that was already
written earlier in the dialog (so a stray `WRITE` in a PBO module turns up in
your list), and

> `"The statement is ignored in the event blocks for reporting events and list events."`

— calling it from `START-OF-SELECTION` or `AT LINE-SELECTION` does nothing at
all. Also worth knowing before using the addition:

> `"If the value 0 is specified in dynnr, the current dynpro sequence is closed after the list processor is exited."`

---

## 9. What to use instead

The overview page names the replacements directly:

> `"For tabular list output, the classes of SAP List Viewer (ALV) are used, for example CL_SALV_TABLE."`

> `"The methods of the class CL_DEMO_OUTPUT demonstrate how simple WRITE output can be replaced by using a suitable output stream."`

For column alignment in a list that must stay a list — East Asian characters
occupy more columns than list-buffer positions, which is the cause of the `<`
and `>` markers:

> `"If characters are removed when passed from the list buffer to the list, this is indicated on the left by the character < and on the right by the character >."`

> `"The methods of the system class CL_ABAP_LIST_UTILITIES can be used to calculate output lengths in the list buffer and in list display."`

And the honest summary for this repo: the demos here use `WRITE` because a
`REPORT` with `START-OF-SELECTION` is the shortest runnable thing an ABAP
developer can paste into a system. That is a *demo* medium. For production
output, the sections above are the list of reasons not to use it — each one a
place where the statement formats, positions or remembers something on your
behalf, using settings that belong to the user rather than to the program.

---

## Sources

- [Lists - Overview](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLIST_OVERVIEW.html) — the 21-list buffer, the `sy-lsind` assignment rule, 1023-character lines, the deprecation statement
- [Lists - System Fields](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLIST_SYSTEMFIELDS.html) — `sy-lsind`/`sy-listi`/`sy-lisel`/`sy-lilli`, and the `sy-colno` vs `sy-cucol` counting split
- [`WRITE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWRITE-.html) — the ignored `/`, the ignored `pos`, `UNDER`, `NO-GAP`, the icon and control-character hints
- [`WRITE`, Output Length](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENWRITE_OUTPUT_LENGTH.html) — the predefined-length tables, the `d`/`t`/`s` shortfalls, `CL_ABAP_LIST_UTILITIES`
- [`WRITE`, Predefined Formats](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENWRITE_FORMATS.html) — the sign on the right, alignment per type, `SET COUNTRY`, the asterisk flag
- [`WRITE`, `TO`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPWRITE_TO.html) — formatting is for output not processing, the asterisk fill, the numeric-literal restriction
- [`HIDE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPHIDE.html) — line-keyed storage, no class attributes, `HIDE_NO_LOCAL` and the rest of the uncatchable set
- [`READ LINE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPREAD_LINE.html) — `sy-lisel`, the default list level, `CURRENT LINE`, the wider-target example
- [`MODIFY LINE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMODIFY_LINE.html) — the output length that cannot change and the ignored alignments
- [`AT LINE-SELECTION`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPAT_LINE-SELECTION.html) — the `PICK` function code and the F2 rewiring
- [`AT USER-COMMAND`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPAT_USER-COMMAND.html) — the reserved `%` functions and the list-processor function codes
- [`TOP-OF-PAGE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPTOP-OF-PAGE.html) — `DURING LINE-SELECTION`, the ignored `NEW-PAGE`
- [`NEW-PAGE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPNEW-PAGE.html) — no empty pages, no `END-OF-PAGE`
- [`SET BLANK LINES`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSET_BLANK_LINES.html) — the suppressed line and the suppressed empty checkbox
- [`LEAVE TO LIST-PROCESSING`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPLEAVE_TO_LIST-PROCESSING.html) — PBO/PAI output collection, ignored in list events, `dynnr = 0`

Worked, runnable example: [ydj_list_output_demo.abap](ydj_list_output_demo.abap)
