# Pragmas & Pseudo Comments | The Suppression That Silently Does Nothing, the Pragma Before the Colon That Covers the Whole Chain & the Mix That Creates a Warning You Cannot Switch Off

Every ABAP codebase of any age is sprinkled with `##NEEDED`, `##NO_TEXT` and
`"#EC CI_...`, and almost nobody reads the rules for them. They get copied out of
a message long text, pasted at the end of a line, and the warning goes away — or
appears to.

That is the problem. A suppression marker is the one construct in ABAP whose
*failure mode is silence*. If a pragma does not work, nothing is highlighted, no
syntax error appears, and the only symptom is a warning that is still in the
check result — in a list of hundreds, in a tool most developers run rarely. So a
pragma that does nothing looks exactly like a pragma that works, until somebody
turns the ABAP Test Cockpit on in the transport gate.

There are four families here, and two of them are obsolete. They differ from each
other in exactly the places where you would assume they agree: one is
case-insensitive and one is case-sensitive, one may be stacked on a line and one
may not, and the two of them together can produce a warning that cannot be
switched off at all.

> "Pragmas are program directives that can be used to hide warnings from various
> check tools."
> -- [Pragmas](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA.html)

> "A pseudo comment begins with the expression `#EC` or `#AU`"
> -- [pseudo comment](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_GLOSRY.html)

---

## 0. Who reads what

| Form | Example | Read by | Status |
|---|---|---|---|
| Pragma `##CODE` | `##NEEDED` | ABAP Compiler syntax check **and** extended program check | current |
| Pseudo comment `"#EC CI_...` | `"#EC CI_BUFFJOIN` | Code Inspector | **current** |
| Pseudo comment `"#EC ID` | `"#EC NEEDED` | extended program check | obsolete |
| Pseudo comment `"#AU ...` | `"#AU Risk_Level Harmless` | ABAP Unit | obsolete |

Two things in that table surprise people.

First, a pragma is read by **two different tools**, not one. The documented list
is "Warnings from the ABAP Compiler `syntax check`" and "Warnings from the
`extended program check`" — so the same `##` construct suppresses both the yellow
squiggle in the editor and a finding in `SLIN`, and the rules below differ
depending on which of the two raised the warning.

Second, the *only* pseudo comment family that is not obsolete is the Code
Inspector one:

> "Until now, only the pseudo comments for the Code Inspector have not been
> replaced by other language elements."
> -- [Pseudo Comments for Code Inspector](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_CI.html)

> "Pseudo comments are only still required for suppressing Code Inspector
> messages and are otherwise obsolete."
> -- [pseudo comment](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_GLOSRY.html)

Which means the rule *always use pragmas, never pseudo comments* that gets quoted
in code reviews is *almost* right, and the exception is not a legacy corner — it
is the Code Inspector, i.e. the check set most teams actually gate transports on.
You cannot replace `"#EC CI_NOORDER` with a pragma, because no pragma was ever
created for it.

---

## 1. The three ways a pragma fails — and only one of them is loud

This is the headline. The documentation puts the two sentences next to each
other, and they describe opposite experiences:

> "Unknown, formally incorrect, or incorrectly parameterized pragmas produce a
> syntax warning. Incorrectly positioned pragmas for warnings in the syntax check
> have no effect."
> -- [Pragmas](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA.html)

So:

| What you got wrong | What happens |
|---|---|
| The pragma name (typo, invented code) | syntax **warning** — loud, you will see it |
| The parameter (wrong value in `[...]`) | syntax warning *if formally wrong*, otherwise simply does not match (section 3) |
| The **position** | for a syntax-check warning: **no effect**, no diagnostic |

The last row is the one that bites. You misplace the pragma, the construct is
still a valid pragma, so nothing complains about the pragma itself — and the
original warning stays. Developers read that as "the pragma does not work for
this warning" and go looking for a different pragma code, when the code was right
all along.

Note the careful scoping in SAP's sentence: *for warnings in the syntax check*.
It does not promise the same forgiveness in the extended program check. Treat
position as load-bearing in both.

---

## 2. The position rules, and why they exist

> "Pragmas must only be used at specific positions in the source code for reasons
> of readability, namely:"
>
> - "At the start of a line, after any number of blanks"
> - "At the end of a line, only followed by `.`, `,`, or `:`."
> - "*Not* *after* `.`, `,`, or `:`."
> - "Multiple pragmas may be positioned one after another, separated by blanks,
>   at allowed positions."
>
> -- [Pragmas](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA.html)

Read that third bullet again. A pragma may sit *immediately before* the period
and may **not** sit after it. This is the single most common mistake, because a
pseudo comment is the other way round — it is a line-end comment, so it goes
*after* the period:

```abap
" pragma: before the period
DATA text TYPE string ##NEEDED.

" pseudo comment: after the period
DATA text TYPE string.   "#EC NEEDED
```

Those two lines look like stylistic variants of one idea. They are not: swap the
positions and both stop working. The pragma after the period is in the position
the documentation explicitly forbids, and the pseudo comment before the period is
not a comment at all — everything from `"` to end of line is comment text, so it
would swallow the period and break the statement.

The "reasons of readability" in SAP's own wording is worth taking at face value:
the restriction is not technical. A pragma is not a comment and is not ignored by
the compiler, so it *could* have been allowed anywhere. The grammar was narrowed
on purpose so that a reader scanning the left and right edges of a line sees
every directive.

Also from the quote: pragmas **stack**, separated by blanks. Pseudo comments do
not — see section 6.

---

## 3. A parameter narrows the suppression, and an empty one does not

> "A warning is affected by a pragma if all the parameters *specified* match the
> *concrete* parameters."
> -- [Pragmas](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA.html)

The documentation's own worked example is `##SHADOW`, which suppresses the
warning raised when a method name hides a built-in function. For a warning about
`SUBSTRING`, all three of these work:

```abap
##SHADOW            " no parameter   -> matches any shadowed function
##SHADOW[SUBSTRING] " exact match    -> matches this one
##SHADOW[]          " empty brackets -> parameter omitted, matches any
```

and one does not:

> "but not using `SHADOW[FIND]`"
> -- [Pragmas](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA.html)

So a parameter is a **filter**, not documentation. Writing `##SHADOW[FIND]` on a
method that shadows `substring` is a pragma that is spelled correctly, is
positioned correctly, is a real pragma with a real parameter — and suppresses
nothing. This is the failure mode that survives a code review, because the line
*looks* more precise than the bare `##SHADOW` next to it.

Two details that follow from the same quote:

- Omitting a parameter is **wider**, not narrower. `##SHADOW` and `##SHADOW[]`
  both match every shadowed function in that statement. If you want the pragma to
  stop applying when somebody adds a second shadowing method later, you must name
  the parameter — and accept that it then breaks silently if the name changes.
- Some parameters are not optional at all:

> "Compulsory parameters are underlined in the long text and must not be
> omitted."
> -- [Pragmas](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA.html)

*Underlined in the long text* is a formatting convention in a popup, which is an
unusual place to put a syntax requirement. Which brings us to the only reliable
way to find the right pragma:

> "For a system check warning, the existence of a pragma and its rules can be
> checked using the *long text of the message*, which in this case always exists."
> -- [Pragmas](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA.html)

Do not guess pragma codes and do not copy them from a different warning. Open the
long text of *the message you are suppressing*. For the extended program check,
the message description names the pragma too.

---

## 4. Scope: the comma, the colon, and the macro

> "A pragma applies to the current statement, that is to the statement that ends
> at the next `.` or `,` . Pragmas in front of the `:` of a chained statement
> apply to the entire chained statement. Pragmas that are used when calling a
> macro apply to all statements of the macro."
> -- [Pragmas](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA.html)

Three different scopes in one sentence, and the syntax that selects between them
is a single character of punctuation.

**Per part of a chain.** The pragma binds to the part ending at the next comma.
This is SAP's own replacement example for the obsolete pseudo comment, and it
suppresses the warning for `a` only:

```abap
DATA: a TYPE string ##NEEDED,
      b TYPE string.
```

**The whole chain.** Because `:` is one of the three characters a pragma may
precede, a pragma can also be written before the colon — and it then covers
*every* part of the chain:

```abap
DATA ##NEEDED:        " covers a AND b AND anything added below
  a TYPE string,
  b TYPE string.
```

That form is derived from the position rules above rather than copied from a
documented example, so verify it in your own system before adopting it — but the
scope rule it relies on is quoted verbatim.

The scope rule is what makes this dangerous rather than merely subtle. A chained
declaration grows over the years. The pragma was added when the chain had two
variables and one of them was genuinely a dummy; five years later the chain has
fourteen, and the *unused variable* check has been switched off for all fourteen
by a marker sitting on a line nobody has looked at. The chain-wide form is an
*opt-out of a check for an open-ended list*, and the list is editable by anyone.

The macro case is the same shape, one level worse: the pragma is written at the
call site and takes effect inside a body defined somewhere else entirely. If you
still have `DEFINE` macros, a pragma on the macro call suppresses that warning in
every statement the macro expands to.

**Practical rule:** put the pragma on the narrowest thing that will take it. Per
statement where you can; per chain part if it is a chain; before the colon only
when you actually mean *all of these, including the ones not written yet*.

---

## 5. The pragma on `TYPES` that stops being inherited

This one is pure *you would never guess, and it is written down*:

> "A pragma in a type definition made using `TYPES` ,for example, to hide the
> warning for redundant secondary keys of table types, can also be applied to data
> declarations using `DATA` in the case of non-generic types and related statements
> that reference the data type using `TYPE` . If a reference is made to a generic
> data type defined using `TYPES` , that is, a table type for which no primary
> table key is defined, a pragma specified there is not applied to the data
> declaration, since it uses a full table type implicitly and the pragma must
> potentially be specified again."
> -- [Pragmas](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA.html)

(The comma placement in `TYPES ,for example,` is SAP's, not a transcription slip.)

Unpacked: a pragma on a `TYPES` statement is normally *inherited* by every `DATA`
declaration that references the type. You suppress the warning once at the type
and you are done. Except when the type is **generic** — specifically a table type
declared without a primary table key — in which case the declaration implicitly
completes the type to a full one, and the inherited pragma does not come along.

The pragma SAP has in mind here is `##TABKEY`, and its own example places it at
the end of a table declaration:

> "hides the syntax warning that different table keys in an internal table
> cannot contain the same components using the pragma `##TABKEY`"
> -- [Internal Tables, Key Accesses](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENREAD_ITAB_USING_KEY_ABEXA.html)

```abap
" Primary key defined -> non-generic -> a DATA declaration referring to
" this type inherits the pragma, and stays quiet.
TYPES ty_tab TYPE SORTED TABLE OF ty_row
             WITH NON-UNIQUE KEY carrid
             WITH NON-UNIQUE SORTED KEY k2 COMPONENTS carrid ##TABKEY[K2].

DATA tab TYPE ty_tab.          " inherited, nothing to repeat
```

Take the primary key specification away and the type becomes generic. The `DATA`
declaration then completes it implicitly, the inheritance stops, and the warning
is back at every use site --- which is the trap, because dropping the primary key
from a table type is something people do deliberately, to let each declaration
choose its own. The fix is in SAP's own sentence: "the pragma must potentially be
specified again" --- at each `DATA`.

Do not copy `##TABKEY[K2]` as a recipe: the parameter is a key name, and section 3
is about what happens when a parameter does not match. Read the long text of your
own warning. Note also that `##TABKEY` is a *declaration* pragma; the similarly
named `##PRIMKEY` is the *statement* pragma for key accesses, and the two are not
interchangeable.

See [Internal Table Keys](../Internal%20Table%20Keys#readme) for what a primary table
key is and why a table type without one is generic.

---

## 6. One pseudo comment per line — the exact opposite of pragmas

> "Only one pseudo comment can be specified per program line. To specify multiple
> pseudo comments for a statement, they must be split into multiple lines."
> -- [Pseudo Comments](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT.html)

> "To hide multiple warnings from a statement with pseudo comments, the statement
> must be split into multiple lines."
> -- [Pseudo Comments for Code Inspector](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_CI.html)

Compare with the pragma rule from section 2: "Multiple pragmas may be positioned
one after another, separated by blanks, at allowed positions."

Same job, same syntactic slot, opposite rule. And because the pseudo-comment
limit is **per line** rather than per statement, the workaround is not "write
them both at the end" but *reformat the statement* so that each marker gets its
own line. That is why real-world Code Inspector suppression looks like SAP's own
example: a `SELECT` broken across thirteen lines with the pseudo comment parked
on the first line and ordinary comments explaining the rest.

The second thing to copy from that example is the explanation:

> "An additional regular comment illustrates to the user why the pseudo comment is
> being used."
> -- [Pseudo Comments for Code Inspector](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_CI.html)

SAP's example suppresses a buffer-bypass warning on a join and comments that the
application does its own buffering with Shared Objects. That is the standard this
should be held to: a suppression without a reason is an assertion that the check
is wrong, made anonymously. See [Table Buffering](../Table%20Buffering#readme)
for what that particular warning is actually telling you.

---

## 7. Mixing the generations creates a warning you cannot switch off

> "In a program that uses pragmas to deactivate warnings, the statement
> `SET EXTENDED CHECK` and the pseudo comment `#EC *` can no longer be used and
> produce an extended program check warning that cannot be deactivated."
> -- [Pragmas](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA.html)

> "The pseudo comment `#EC *` must no longer be used in programs that use pragmas
> to deactivate warnings."
> -- [Pseudo Comments for the Extended Program Check](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_SLIN.html)

`#EC *` is the blanket form — suppress everything — and `SET EXTENDED CHECK` is
the obsolete statement that switched the extended check off from inside the
source. Either one, in a program that *also* uses a single pragma, produces a
finding with no suppression route. Not *a warning you should not suppress*: one
that **cannot** be deactivated.

This matters during modernisation, which is exactly when both generations are
present. A developer tidying an old report adds one `##NEEDED`, and the ancient
`#EC *` at the top of the program — which has been quietly working for fifteen
years — turns into a permanent finding. The fix is to remove the blanket
suppression and the obsolete statement, not to remove the pragma.

---

## 8. `"#AU` is case-sensitive; pragmas are not

> "A pragma is not case-sensitive and does not contain blanks."
> -- [Pragmas](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA.html)

> "Pseudo comments are case-sensitive. Any deviations from the syntax produce a
> warning when tests are performed."
> -- [Pseudo Comments for Test Classes](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_TEST_CLASS.html)

`##needed` and `##NEEDED` are the same pragma. `"#AU Risk_Level Harmless` and
`"#AU RISK_LEVEL HARMLESS` are not interchangeable — and the diagnosis arrives
"when tests are performed", i.e. in the ABAP Unit result, not in the syntax
check.

For test classes the whole mechanism has been replaced by real syntax:

> "Real additions are now available for the statement `CLASS ... FOR TESTING` for
> defining test properties. These additions should be used instead of the pseudo
> comments. This makes pseudo comments for test classes obsolete. Existing pseudo
> comments are not ignored, but should no longer be used."
> -- [Pseudo Comments for Test Classes](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_TEST_CLASS.html)

The phrase "not ignored" is the operative one: an old
`"#AU Risk_Level Critical` in a test class is still in force. If you add a
`RISK LEVEL` addition and leave the pseudo comment in place, you have two
declarations of the same property in one class. See
[AUnits](../AUnits#readme) for what `RISK LEVEL` and `DURATION` actually do,
including the default that stops tests from running at all.

---

## 9. Finding the replacement for an obsolete pseudo comment

> "Pragmas replace the previously used pseudo comments to hide warnings from the
> extended program check. These pseudo comments are therefore obsolete and should
> no longer be used. The program `ABAP_SLIN_PRAGMAS` shows which pragmas are to be
> used instead of the obsolete pseudo comments."
> -- [Pragmas](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA.html)

SAP's style guide names a second route and the same program:

> "Prefer pragmas to pseudo comments to suppress irrelevant warnings and errors
> identified by the ATC."
>
> "Use program `ABAP_SLIN_PRAGMAS` or table `SLIN_DESC` to find the mapping
> between obsolete pseudo comments and the pragmas that have replaced them."
> -- [Clean ABAP: Prefer pragmas to pseudo comments](https://github.com/SAP/styleguides/blob/main/clean-abap/CleanABAP.md#prefer-pragmas-to-pseudo-comments)

So the migration is mechanical: run `ABAP_SLIN_PRAGMAS` (or read `SLIN_DESC`),
look up the `"#EC ID`, write the `##CODE` instead, and move it from after the
period to before it. Do not translate `"#EC CI_...` entries — those have no
pragma, by design.

One scoping note on this section: ATC *exemptions* are a separate, approval-based
mechanism maintained outside the source code, and this note does not cover them.
Clean ABAP's sentence above is about which in-source marker to write when an
in-source marker is the right answer.

---

## Quick reference

| Question | Answer |
|---|---|
| Where does a pragma go? | Start of a line, or end of a line immediately before `.`, `,` or `:` — never after them |
| Where does a pseudo comment go? | After the statement, as a line-end comment |
| Several markers on one statement? | Pragmas: stack them, separated by blanks. Pseudo comments: one per *line*, split the statement |
| Case? | Pragmas no; `"#EC`/`"#AU` yes |
| Wrong pragma name | Syntax warning (loud) |
| Wrong pragma position | Silently no effect for syntax-check warnings |
| Wrong pragma parameter | Silently does not match (`SHADOW[FIND]` vs `SHADOW[SUBSTRING]`) |
| Widest form of a parameterised pragma | Omit the parameter, or `[]` — both match any value |
| Scope of `##X` before a comma | That chain part only |
| Scope of `##X` before the colon | The entire chained statement, including parts added later |
| Scope of `##X` on a macro call | Every statement the macro expands to |
| Pragma on `TYPES`, used via `DATA` | Inherited — unless the type is a generic table type (no primary key), then repeat it |
| Which pseudo comments are still required? | Only `"#EC CI_...` for the Code Inspector |
| `#EC *` or `SET EXTENDED CHECK` + any pragma | Extended check warning that cannot be deactivated |
| Where do I find the right pragma? | The long text of the message being suppressed; `ABAP_SLIN_PRAGMAS` / `SLIN_DESC` for obsolete mappings |

---

## Sources

- [Pragmas](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA.html) --- position rules, scope, parameter matching, the `TYPES` inheritance gap, the `#EC *` collision
- [pragma](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPRAGMA_GLOSRY.html) --- the two tools a pragma speaks to
- [Internal Tables, Key Accesses](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENREAD_ITAB_USING_KEY_ABEXA.html) --- SAP's own `##TABKEY` example, on a table declaration
- [Pseudo Comments](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT.html) --- the one-per-line rule
- [pseudo comment](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_GLOSRY.html) --- `#EC` / `#AU`, and what is still required
- [Pseudo Comments for Code Inspector](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_CI.html) --- the family that has no pragma, and the comment-your-reason example
- [Pseudo Comments for the Extended Program Check](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_SLIN.html) --- the obsolete family and the `"#EC NEEDED` to `##NEEDED` migration
- [Pseudo Comments for Test Classes](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENPSEUDO_COMMENT_TEST_CLASS.html) --- `"#AU`, case sensitivity, "not ignored"
- [CLASS, FOR TESTING](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPCLASS_FOR_TESTING.html) --- the `RISK LEVEL` / `DURATION` additions that replaced them
- [extended program check](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENEXTENDED_PROGRAM_CHECK_GLOSRY.html) --- `SLIN`, `SLIN_ADMIN`, and the ATC as a front end
- [Code Inspector](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCODE_INSPECTOR_GLOSRY.html) --- `SCI`
- [Clean ABAP: Prefer pragmas to pseudo comments](https://github.com/SAP/styleguides/blob/main/clean-abap/CleanABAP.md#prefer-pragmas-to-pseudo-comments) --- SAP's own rule, and `SLIN_DESC`

---

See also: [AUnits](../AUnits#readme) for the `RISK LEVEL` and `DURATION`
additions that replaced `"#AU`,
[Internal Table Keys](../Internal%20Table%20Keys#readme) for the generic table
type behind the `TYPES` inheritance gap,
[Table Buffering](../Table%20Buffering#readme) for the buffer-bypass warning in
SAP's own Code Inspector example,
[Text Elements](../Text%20Elements#readme) for what `##NO_TEXT` is asserting
about a literal, and why the assertion is sometimes wrong,
[Checkpoints](../Checkpoints#readme) for `ASSERT`, the other construct whose
behaviour is decided by a setting outside the program,
[ABAP Language Versions](../ABAP%20Language%20Versions#readme) for the program
property that decides which checks apply in the first place, and
[Common Table Expressions](../Common%20Table%20Expressions#readme) for a case
where the pragma hides a *syntax* warning and the statement still fails at
runtime --- the clearest example in this repo that suppressing the message does
not address what it was reporting.
