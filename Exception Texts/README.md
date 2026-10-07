# Exception Texts & Messages — the `MESSAGE` that sends nothing, the attribute name that becomes the text, and the `TEXTID` you are not allowed to combine

Every `CATCH ... INTO DATA(lo_err)` in this repo ends the same way: `lo_err->get_text( )`.
That call is doing more than it looks like. This note is about where that string
actually comes from, and the handful of places where it silently turns into something
you did not intend.

> `"Each exception is assigned a text that can be parameterized by attributes and that describes the exception situation."`

Two things read that text. If nobody handles the exception, `"This text is displayed in the short dump of the runtime error if the exception is not handled."` If somebody does, `"the text can be read using the method GET_TEXT of the interface IF_MESSAGE, which is implemented by every exception class. Any long text can be read using the method GET_LONGTEXT."`

There are two ways an exception class can carry that text, and three ways to select
one at the moment you raise it:

| Mechanism | Text lives in | Selected by |
|---|---|---|
| `IF_T100_MESSAGE` | a message in `T100` | `EXPORTING textid = cls=>const` |
| `IF_T100_DYN_MSG` | *any* message in `T100`, decided at the raise | `MESSAGE e123(zz) WITH ...` |
| neither interface | OTR (Online Text Repository) | `EXPORTING textid = <SOTR_CONC>` — **system classes only** |

The three are not variations on a theme. They are mutually exclusive at the call
site, and mixing them up fails quietly rather than loudly.

```abap
" Both of these raise "the same" exception. They do not produce the same text,
" and only one of them can carry a message chosen at runtime.
RAISE EXCEPTION TYPE zcx_order EXPORTING textid = zcx_order=>not_released.
RAISE EXCEPTION TYPE zcx_order MESSAGE e005(zorder) WITH ls_order-id 'not released'.
```

## 1. `MESSAGE` after `RAISE EXCEPTION` does not send a message

The word is borrowed and it is misleading. The addition `MESSAGE`

> `"passes the specification of a message to the exception object"`

and that is all it does. No status line, no dialog, no `sy-subrc`, no flow change
beyond the exception itself. The message is *stored* so that something later —
`get_text( )`, a short dump, or `MESSAGE oref` — can render it. Everything the
[`MESSAGE` statement](../Messages#readme) does to program flow is absent here.

What it stores is not just the key. It overwrites:

> `"The addition MESSAGE fills the attributes of these interfaces with values. This assignment takes place after the instance constructor is executed. This overwrites any values that were assigned to these attributes when the exception object was constructed."`

So a constructor that carefully fills `t100key` — or `msgv1`, or any other interface
attribute — is not an input to the decision. It runs first and is then partly
discarded, with the raise site winning. This is the trap in a class whose
constructor sets a sensible default message: the default works everywhere except
exactly where somebody wrote `MESSAGE`, which is where they were most deliberate.

And the two selection mechanisms cannot be combined at all:

> `"If the addition MESSAGE is used, the input parameter TEXTID of the constructor of the exception class must not be filled. This parameter is only intended for specifying a predefined exception text."`

> `"In particular, the addition MESSAGE cannot be combined with the input parameter TEXTID."`

One more restriction worth knowing before you refactor: `"The addition MESSAGE cannot be specified after the variant RAISE EXCEPTION oref."` Pre-building an exception
object with `NEW` and raising it later is a legitimate pattern — but it is the one
form that cannot take a message. You get a syntax error, which is the good case.

### Which interface you implement decides which syntax compiles

| | `IF_T100_MESSAGE` | `IF_T100_DYN_MSG` |
|---|---|---|
| `T100KEY` attribute | yes | yes (included interface) |
| message type attribute | **no** | `MSGTY` |
| placeholder attributes | you declare them yourself | `MSGV1` to `MSGV4` |
| `EXPORTING textid = ...` | the intended use | available |
| `MESSAGE e123(zz) WITH ...` | `"with restrictions"` | the intended use |
| instance constructor | you implement it | not needed |

`IF_T100_DYN_MSG` adds exactly two things to its parent: `"The attribute MSGTY for the message type"` and `"The attributes MSGV1 to MSGV4 for the placeholders of the message"`. That is what makes the `MESSAGE` addition work without you writing
anything — `"no separate attributes for the placeholders of the message and no implementation of the instance constructor are required"`.

Using `MESSAGE` with an `IF_T100_MESSAGE`-only class is legal but deliberately
second-class: `"Exception objects of exception classes that include only the system interface IF_T100_MESSAGE can also be linked with messages using the addition MESSAGE with restrictions. The latter option is intended only for exception classes that previously had no specific exception texts for generic use before IF_T100_DYN_MSG was introduced."` Note also that `"The interface IF_T100_MESSAGE does not have any attributes for the message type."` — there is nowhere for the `e` in `MESSAGE e005(zz)`
to be stored on such a class. The documentation does not spell out what becomes of
it, so treat the type as unreliable there rather than assuming it survives.

For converting classic exceptions there is a short form that reads the `sy-msg*`
fields instead of naming a message: the addition `"has a short form USING MESSAGE"`,
which `"enables determining the message from the current content of the system fields"`.
It needs `IF_T100_DYN_MSG`.

```abap
" The classic-to-class-based bridge: the FM's message is already in sy-msg*.
CALL FUNCTION 'Z_SOMETHING'
  EXCEPTIONS error_message = 1.
IF sy-subrc <> 0.
  RAISE EXCEPTION TYPE zcx_wrapper USING MESSAGE.
ENDIF.
```

## 2. The placeholder that is an attribute *name*, not a value

This is the mechanism most people never look at, and it is the one that produces
output nobody can explain:

> `"It should be noted that with interface IF_T100_MESSAGE there is a double indirection for the possible placeholders of a message. The text for a placeholder is taken from an attribute of the implementing class whose name is itself contained in a component of structure T100KEY."`

`T100KEY-ATTR1` to `ATTR4` do not hold text. They hold *names*:
`"The content of components ATTR1 to ATTR4 is the names of attributes of the implementing class whose content is used as placeholder texts for the possible placeholders in the texts of the message."`

Which means a typo in a name is not a compile error and not an exception:

> `"If an attribute specified in the components ATTR1 to ATTR4 does not exist or if the content of an attribute cannot be converted to a placeholder text, the character & is added to the start and the end of the attribute name and the resulting string is used as the placeholder text."`

Your error message prints `&CUSTMER_NAME&` to a user, in production, and the only
clue is the ampersands. The same shrug applies to an empty one:
`"If one of the components ATTR1 to ATTR4 is initial, the corresponding placeholder text is initialized."`

With `IF_T100_DYN_MSG` the indirection still exists, but the framework fills it:
the `MESSAGE` addition assigns `msgid`/`msgno` from the message key, and
`attr1`-`attr4` get the *names* `MSGV1` to `MSGV4`, whose contents come from `WITH`.
That is the real reason the modern interface is less error-prone — not that it has
fewer moving parts, but that you are not the one spelling the attribute names.

### A missing message is not an error either

> `"In database table T100, a message is searched for whose message class and message number correspond to the components MSGID and MSGNO of the structure T100KEY. If a message is found, its texts are used. If not, a short text is generated that lists the message class and message number as well as the placeholder texts from the class attributes that are specified in the structure."`

A deleted message, an unactivated message class, a transport that moved the class
but not the message class: `get_text( )` returns a synthesized string and the
program carries on. There is also a language fallback before that point —
`"If the specified message is not found for the logon language of the current user, a search is made in the secondary language in AS ABAP and then in English."`

Placeholder syntax differs between the two texts of one message, which is easy to
get wrong when maintaining the long text: `&1` to `&4` and `&` in the short text,
but `&V1&` to `&V4&` in the long text. And the short text is small — four
placeholders, and `"These placeholders can be replaced by strings with a maximum of 50 characters using the addition WITH."` (the 50-character truncation itself is
covered in [Messages](../Messages#readme)).

## 3. `MESSAGE oref` — and the generic parameter that silently changes the statement

An exception object can be handed straight to the `MESSAGE` statement, because
`msg` accepts `"an object reference variable oref is specified whose dynamic type implements the interface IF_T100_MESSAGE"`. Two additions you may be reaching for
are gone:

> `"If oref is specified, the addition WITH and the variant with INTO are not allowed."`

No `WITH`, because the placeholder values are already inside the object. And no
`INTO` — so the usual trick of capturing a formatted message into a string does not
work on an exception object. Use `get_text( )`, which is what it is for.

The message type is your problem, because `IF_T100_MESSAGE` has no `MSGTY`. With
`IF_T100_DYN_MSG` it is implicit: `"If the TYPE addition is omitted for an object with the system interface IF_T100_DYN_MSG, the addition TYPE oref->if_t100_dyn_msg~msgty is added implicitly."` **This is sharper than it looks.** An exception raised with
`MESSAGE e005(zz)` carries type `E`, so a bare `MESSAGE lo_err.` in a report is an
error message — which, per [Messages](../Messages#readme), terminates list
processing with an empty screen. The statement that looks like "display the error"
is the statement that ends the program. Pass `TYPE 'S'` explicitly when you only
want to show it.

Now the quiet one. Pass that same reference through a generically typed parameter
and you are no longer executing the same statement:

> `"If field symbols or formal parameters of the generic type any or data are specified for oref, the variant MESSAGE text is used, which has identical syntax."`

`MESSAGE text` renders a character string as a free-text message. Identical source
line, different statement, different output, and the language-independent identity
is lost — a generic `display_error( iv_err )` helper is exactly the shape that
triggers this. Keep the formal parameter typed `REF TO cx_root` or
`REF TO if_t100_message`.

There is a compatibility path for classes with only `IF_MESSAGE`, and it has its own
cost: `"For compatibility reasons, this variant can still be used for classes that only implement the interface IF_MESSAGE."` but `"In this case, the system fields sy-msgid and sy-msgno are not filled specifically."` Any caller that inspects `sy-msgid`
afterwards — a BAPI return-table builder, an application log writer — gets nothing.
This is the case for every exception class that skipped `IF_T100_MESSAGE`:
`"In exception classes that do not implement the interface IF_T100_MESSAGE, the interface methods GET_TEXT and GET_LONGTEXT get the exception texts of exception objects stored in OTR"`.

## 4. `TEXTID` accepts far more than it should, and the where-used list hides it

`TEXTID` is typed, not constrained. For a T100-based class it is
`SCX_T100KEY`, so any message at all fits:

> `"From a technical perspective, any structure of type SCX_T100KEY whose components specify any message of table T100 can be passed to the input parameter TEXTID of the instance constructor. This is strongly discouraged, however, because an exception should only be raised with specific texts when using the parameter TEXTID."`

The programming guideline is blunter — `"This approach is, however, absolutely not advisable. If the parameter TEXTID is used, an exception can only be raised with the texts specific to it."` Only the generated constants belong there, and the reason
is maintainability rather than taste:

> `"A where-used list for a message contains its usage as an exception text in an exception class. But it does not contain the positions, where the specification of the message is passed in a structure of type SCX_T100KEY to the instance constructor of an exception class."`

So a message consumed via a hand-built `VALUE scx_t100key( ... )` looks **unused**.
Someone cleaning up a message class deletes it, and per section 2 nothing breaks
loudly — the text just becomes a generated placeholder line. The same blind spot
applies to OTR texts: `"Passing the specification of a text as an actual parameter to the parameter TEXTID is not contained in the where-used list of that text."`

Use the constant, which the tooling generates for you —
`"each exception text is defined by an identically named static constant in the public visibility section of the exception class that defines its properties"` — and remember
the fallback when you pass nothing at all:
`"If the parameter is not passed, the predefined exception text with the same name as the exception class is used."`

## 5. OTR texts: not for your code

If a class does not implement `IF_T100_MESSAGE`, its texts come from the OTR, and
that page opens with a warning rather than a description:

> `"This function is for internal use only."` `"Do not use it in application programs."`

The guideline agrees: `"Messages should be used as exception texts for exception classes in applications. OTR texts should be restricted to system classes."` and
`"OTR texts should only occur in predefined exception classes for system exceptions and should not be used in user-defined exception classes."`

This is not arbitrary. OTR is technically the nicer store —
`"OTR offers various benefits when compared with messages, such as no restriction to 73 characters and unlimited placeholders, but lacks full tool support."` — but the
tooling gap is decisive: `"do not support any exception texts from OTR. No exception texts can be defined for the OTR and no UUIDs are created."` in ADT. An OTR-texted
class is only fully maintainable in the Workbench, so it is a dead end for anything
new.

The practical upshot is that modern exception classes get the right interface for
free: `"An exception class is defined by inheriting from one of the superclasses CX_STATIC_CHECK, CX_DYNAMIC_CHECK, or CX_NO_CHECK. Such classes implement the interface IF_T100_MESSAGE by default and the constructor is generated accordingly."`

One Workbench-specific trap if you add the interface after creating the class: the
constructor generated for the OTR case is wrong for the T100 case and does not fix
itself — `"Otherwise, the constructor for internal exception texts is generated and must be regenerated by choosing Utilities -> Clean Up -> Constructor after a subsequent inclusion of the interface."`

## 6. Re-raising destroys the position; `PREVIOUS` is what preserves it

`RAISE EXCEPTION lo_err` on a caught object is tempting and lossy:

> `"In the existing exception object, the internal attributes that describe the position of the exception and that can be read using the method GET_SOURCE_POSITION are converted to the position of the statement RAISE."`

The object does not get a second position; it gets a *replacement* one. The original
line number — the thing you actually wanted from the dump — is gone.

> `"If a caught exception is raised again, note that the exception object does not remain unchanged because the information about the position of the exception is changed. If the original information is to be propagated to an external handler, a new exception of the same class can be raised, passing the original exception object to the PREVIOUS parameter of its constructor."`

Wrapping via `previous` keeps both. The cost is that the outermost exception is now
the least informative one, so a handler reading `get_text( )` on what it caught may
be reading the wrapper's generic text while the real message sits two links down.
There is a shipped helper for exactly that walk:

> `"The method GET_LATEST_T100_EXCEPTION in the class CL_MESSAGE_HELPER returns the last object in a chain of exception objects, which was created using PREVIOUS, that has an exception text defined by a message."`

`CL_MESSAGE_HELPER` also has `SET_MSG_VARS_FOR_IF_T100_MSG( )`, which takes an
exception object and fills `sy-msgid`/`sy-msgno`/`sy-msgv1`-`4` from it — the bridge
back to any legacy code that reads system fields instead of objects.

## Rules of thumb

1. New exception class → inherit from a `CX_*_CHECK` class, take the generated
   `IF_T100_MESSAGE`, and add `IF_T100_DYN_MSG` if the class will ever carry a
   message decided by the caller.
2. Pass **only** the generated constants to `textid`. Never a hand-built
   `scx_t100key` — the where-used list cannot see it.
3. Never try to combine `MESSAGE` and `textid`; pick one per class and stay with it.
4. `get_text( )` to read, `MESSAGE oref TYPE 'S'` to show. Never a bare
   `MESSAGE lo_err.` in list processing.
5. Type the formal parameter `REF TO cx_root`, never `any`/`data`, anywhere an
   exception object is passed to a helper that messages it.
6. Wrap with `previous`, never re-raise the same object, and walk the chain when
   you need the real text.
7. OTR texts are for SAP's own system classes. In application code, messages.

## Sources

- [Exception Texts](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENEXCEPTION_TEXTS.html) — `GET_TEXT`/`GET_LONGTEXT`, the `TEXTID` constant, the same-name default
- [Messages as Exception Texts](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENEXCEPTION_TEXTS_T100.html) — `SCX_T100KEY`, the where-used gap, constructor regeneration
- [`IF_T100_MESSAGE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENIF_T100_MESSAGE.html) — the double indirection, missing attribute and missing message behaviour
- [`IF_T100_DYN_MSG`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENIF_T100_DYN_MSG.html) — `MSGTY`, `MSGV1`-`MSGV4`, `USING MESSAGE`
- [Exception Classes for Messages](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENMESSAGE_EXCEPTIONS.html) — why the two interfaces are separated, `MESSAGE` vs `TEXTID`
- [`RAISE EXCEPTION`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPRAISE_EXCEPTION_CLASS.html) — `oref` and the overwritten source position, `PREVIOUS`
- [`RAISE EXCEPTION`, `MESSAGE`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPRAISE_EXCEPTION_MESSAGE.html) — the post-constructor overwrite, the `TEXTID` exclusion
- [`MESSAGE`, `msg`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPMESSAGE_MSG.html) — `MESSAGE oref`, no `WITH`/`INTO`, the generic-type switch to `MESSAGE text`
- [Exception Texts — programming guideline](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENEXCEPTION_TEXTS_GUIDL.html) — messages vs OTR, 73 characters
- [Exception Texts for System Classes](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENEXCEPTION_TEXTS_INTERNAL.html) — OTR, `SOTR_CONC`, no ADT support
- [`IF_T100_MESSAGE` in a Local Exception Class](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENMESSAGE_INTERFACE_ABEXA.html) and [`IF_T100_DYN_MSG` in a Local Exception Class](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENRAISE_MESSAGE_ABEXA.html) — the local-class patterns the demo follows
- [SAP-samples/abap-cheat-sheets — 27_Exceptions.md](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/27_Exceptions.md) — the full list of `RAISE EXCEPTION`/`THROW` syntax variants and `CL_MESSAGE_HELPER`

Related notes in this repo: [Messages](../Messages#readme) for what the `MESSAGE`
statement does to program flow and the 50-character placeholder truncation,
[Exception Flow](../Exception%20Flow#readme) for `CLEANUP`/`RETRY`/`RESUME`,
[RFC Calls](../RFC%20Calls#readme) for `error_message` and exceptions that do not
survive a remote call, [Reference Casting](../Reference%20Casting#readme) for the
downcast the demo uses to test an object for `IF_T100_MESSAGE`,
[Text Elements](../Text%20Elements#readme) for the other text store that silently
yields blanks, and [ABAP Language Versions](../ABAP%20Language%20Versions#readme) for
which of these additions ABAP Cloud allows.

Worked, runnable examples: [ydj_exception_text_demo.abap](ydj_exception_text_demo.abap)
