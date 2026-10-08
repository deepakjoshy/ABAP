# Byte Strings & Code Page Conversion — the assignment that looks like an encoding and is really a hex parse

This repo already leans on the `string` / `xstring` boundary in four different
notes. [JSON Serialization](../JSON%20Serialization#readme) has to undo it, because
`get_output( )` always hands back an `xstring`; the
[File Interface](../File%20Interface#readme) note hits it at `OPEN DATASET ... IN
BINARY MODE`, [Regular Expressions](../Regular%20Expressions#readme) uses
`CONV xstring( 'F09F91BD' )` to build a surrogate pair, and
[AMDP](../AMDP#readme) lists `xstring` among the types that cannot have a default.
In all four it appears as a utility line nobody explains.

It deserves explaining, because **the assignment between a character field and a
byte field is not a code page conversion.** It is a hexadecimal parse, it fails
quietly, and the failure is shaped so that the most obvious test data hides it.

```abap
" What people think this does: encode the text as bytes.
" What it actually does: read the text as hex digits. Result: 0 bytes.
DATA(lv_text) = `Hello`.
DATA(lv_wrong) = CONV xstring( lv_text ).            " xstrlen( ) = 0

" The actual encoding, and the only thing that respects a code page:
DATA(lv_right) = cl_abap_conv_codepage=>create_out( )->convert( lv_text ).
```

Nothing above raises an exception. Nothing sets `sy-subrc`.

## 1. Character to byte-like is a half-byte parse, and it stops at the first bad character

The conversion rules for a source field of type `c` or `string` with a byte-like
target are explicit about it:

> `"The characters in the source field are interpreted as the representation of the value of a half-byte in hexadecimal representation."`

> `"If the valid characters 0 to 9 and A to F appear, the corresponding half-byte value is passed left-aligned to the memory of the target field."`

So two characters make one byte, and anything that is not a hex digit is not an
error — it is a full stop:

> `"The first invalid character terminates the conversion from the position of this character and the half-bytes not filled up to that point are padded with hexadecimal 0."`

The documentation's own example is the whole trap in one line. Converting
`'0123456789ABCDEFXXXXXXX'` yields:

> `"The byte chain resulting from the conversion is 0123456789ABCDEF. If the literal were specified directly as the argument of the conversion, the syntax check would produce a warning."`

Seven characters disappeared. The only warning you get is a *syntax* warning, and
only when the value is a literal the syntax check can see. Build the same string at
runtime — from a file, an RFC parameter, a screen field — and there is no warning at
all, because there is nothing left to check at compile time.

Three consequences worth internalising:

- **`CONV xstring( 'Hello' )` is an empty byte string.** `H` is invalid, so the
  conversion terminates at the first character and no half-bytes are ever passed.
  An empty `xstring` is also what you would get from an empty input, so the
  "no data" and "wrong data" cases are indistinguishable downstream.
- **An odd number of valid characters silently gains a nibble.** For an `xstring`
  target: `"Half-bytes are passed to the target field whereby the length of the target field is determined by the number of valid characters in the source field. If number of valid characters in the source field is odd, the last remaining half-byte in the target field is padded with hexadecimal 0."`
  `'ABC'` becomes `ABC0` — three nibbles in, two bytes out.
- **A fixed-length `x` target pads or truncates instead.** converting the four
  valid characters of `FFFF` into an `x LENGTH 4` target gives `"FFFF0000"`, and a zero-length source means
  `"the target field is padded with hexadecimal 0"`. A short target is
  `"truncated on the right"`.

### Why this survives testing

Because hex-shaped test data round-trips perfectly. `'DEADBEEF'` parses to four
bytes and converts back to `DEADBEEF`, so a developer who tests with a hash, a GUID,
or a hand-written hex literal sees a clean round trip and concludes the code
encodes text. The first real customer name is where it returns nothing.

> **Not claimed here:** the conversion table names `0` to `9` and `A` to `F` as the
> valid characters and says nothing about lowercase `a` to `f`. Do not rely on
> either outcome for lowercase input — normalise with `to_upper( )` first.

## 2. Byte to character-like hands you the hex digits as text

The reverse direction is just as literal, and just as much not a decoding:

> `"The values of each half-byte in the source field are converted to the hexadecimal characters 0 to 9 and A to F and passed to the target field. The resulting length of the target field is determined by the number of characters passed."`

An `xstring` holding UTF-8 bytes assigned to a `string` therefore produces a string
of hex digits, twice as long as the byte string — not the text. The doc's example:
`xstring` `'FFFFFF075BCD15'` to `string` gives `"FFFFFF075BCD15"`, because
`"All bytes of the source field are included in the conversion."`

With a **fixed-length `c` target it gets worse**, because the overflow is silent in
the usual direction:

> `"If the target field is longer than the number of characters passed, it is padded on the right with blank characters. If it is too short, it is truncated on the right."`

The doc's own case: a 2-byte `x` field `'2710'` into `c LENGTH 2` gives
`"The string resulting from the conversion is 27. Two characters 10 are cut off on the right."`

And the numeric targets are the quietest of all. `x`/`xstring` to `i`:

> `"Only the last 4 bytes of the source field are converted."`

> `"The first three bytes FFFFFF of the source field are ignored."`

So a 7-byte identifier assigned to an `i` keeps the last four bytes and discards the
rest — no `CX_SY_CONVERSION_OVERFLOW`, because nothing overflowed; the bytes were
simply dropped before the number existed. (`b` and `s` *can* raise overflow, and
`utclong` is `"Not supported. Produces a syntax error or raises the exception CX_SY_CONVERSION_NOT_SUPPORTED."`)

Worth knowing for the other direction too: `string` to `string` is free.
`"No conversion takes place. After the assignment, the internal reference of the target field points to the same string as the source field."` — the copy-on-write
behaviour the [Internal Table Memory](../Table%20Memory#readme) note describes for
tables applies to strings as well.

## 3. The conversion that actually respects a code page

Text becomes bytes through a conversion class, never through an assignment:

> `"The methods CONVERT of the interfaces IF_ABAP_CONV_OUT and IF_ABAP_CONV_IN of objects created with the class CL_ABAP_CONV_CODEPAGE make it possible to convert strings to the binary representation of various code pages and vice versa."`

```abap
DATA(lv_xstr) = cl_abap_conv_codepage=>create_out( codepage = `UTF-8`
                                                 )->convert( source = lv_text ).
DATA(lv_back) = cl_abap_conv_codepage=>create_in(  codepage = `UTF-8`
                                                 )->convert( source = lv_xstr ).
ASSERT lv_back = lv_text.
```

`UTF-8` can be omitted — `"The value UTF-8 is the default value for the parameter CODEPAGE and can also be omitted."` Being explicit is still the better habit: the
default is a property of the class, not of your interface contract, and the receiver
of the bytes has its own opinion.

The framing on the older class page is the clearest statement of *why* any of this
exists:

> `"Data that is not in ABAP format, that is, text data that is not in the system code page format, or numeric data that is not in the byte order used on the current host computer, can be stored in binary form in an x field or in an xstring."`

An `xstring` is where data lives when it is *not* in ABAP format. That is the whole
point, and it is why no assignment rule can encode for you — ABAP does not know
which foreign format you meant.

### Three generations, all still in the documentation

| Class | Documented role |
|---|---|
| `CL_ABAP_CONV_IN_CE` | `"Importing non-ABAP formats into ABAP data objects (reads a binary input stream)."` |
| `CL_ABAP_CONV_OUT_CE` | `"Exporting ABAP data objects to a non-ABAP format (writes to a binary output stream)."` |
| `CL_ABAP_CONV_X2X_CE` | `"Importing data of any format and exporting data to any other format (reads from a binary input stream and writes to a binary output stream)."` |
| `CL_ABAP_CONV_CODEPAGE` | wraps the three above: `"The interfaces IF_ABAP_CONV_IN and IF_ABAP_CONV_OUT of objects that were created using the class CL_ABAP_CONV_CODEPAGE wrap the classes above for easier handling of code pages in character and byte string processing."` |

`CL_ABAP_CODEPAGE` (with the static `convert_to( )` / `convert_from( )` methods)
is a fourth spelling of the same idea, and it is the one the keyword documentation
itself uses in the `strlen` example this repo's
[String Processing](../String%20Processing#readme) note cites. Both spellings appear
in current documentation and neither is marked obsolete on the pages above, so pick
one per codebase and stay consistent rather than treating either as deprecated. On
releases that predate the wrappers, `CL_ABAP_CONV_IN_CE` / `OUT_CE` is the fallback —
which is exactly the caveat already noted in
[JSON Serialization](../JSON%20Serialization#readme). Which of them ABAP Cloud
permits is a question for [ABAP Language Versions](../ABAP%20Language%20Versions#readme),
not for this note.

## 4. Byte mode is never the default

Five statements do both kinds of processing, and the default is the one you probably
did not want:

> `"There is a strict split between character string processing and byte string processing."`

> `"If this addition is not specified, character string processing is performed in these statements."`

| Statement | Character | Byte |
|---|---|---|
| `CONCATENATE`, `FIND`, `REPLACE`, `SHIFT`, `SPLIT` | yes | yes, via `IN BYTE MODE` |
| `CONDENSE`, `CONVERT TEXT`, `OVERLAY`, `TRANSLATE`, `WRITE TO` | yes | **no byte-mode form at all** |
| `SET BIT`, `GET BIT` | no | byte only |

The second row is the one that shapes designs: there is no byte-mode `CONDENSE` or
`TRANSLATE`, so "clean up this binary payload the way I clean up strings" has no
direct translation. Convert, process as text, convert back — and accept that this is
only safe if the bytes really are text in a known code page.

`SPLIT ... IN BYTE MODE` is worth knowing in detail, because the inline declaration
changes type with the mode:

> `"If IN CHARACTER MODE is used, the declared variables are of the type string; if IN BYTE MODE is used, they are of the type xstring."`

and because the segment handling is byte-aware in a way the conversion rules are not:

> `"The segments are assigned directly while ignoring the conversion rules."`

That sentence is the good news in this note — a byte-mode split does *not* hex-parse
anything. The rest of the statement's behaviour matches the character-mode rules the
[String Processing](../String%20Processing#readme) note covers: a fixed-length target
too short means `"the segment is truncated on the right and sy-subrc is set to 4"`,
too long means it `"is padded with blanks or hexadecimal 0 on the right"`, a
separator that is absent or empty yields
`"a single segment that contains the entire content of dobj"`, and too few targets
means the last one keeps the unsplit remainder:
`"The remaining content of dobj is then assigned to the final operand, without being split."`

### The boundary you choose is a byte boundary, not a character boundary

The documentation's byte-mode example splits at hexadecimal `20`,
`"which stands for a blank in code page UTF-8"` — and that works precisely because
`20` cannot occur inside a multi-byte UTF-8 sequence. Generalising from it is where
chunking code breaks: cutting an arbitrary UTF-8 byte string at an arbitrary offset
(a 1024-byte block, a `PACKAGE SIZE` boundary, an HTTP chunk) can land in the middle
of a character, and converting that chunk back with `create_in( )` has half a
character to work with. Split on structure you control, or convert first and chunk
the characters.

The character-side analogue is documented, and the fix is named:

> `"If characters are truncated on the right when character strings containing non-Unicode double-byte characters are assigned, then such a character can be divided in the middle, which generally produces an invalid character at the right margin. To prevent this, the method CL_SCP_LINEBREAK_UTIL=>STRING_SPLIT_AT_POSITION can be used."`

## 5. `BYTE-CO` and friends: the same `sy-fdpos` trap, one type down

The byte-like comparison operators mirror `CO`/`CN`/`CA`/`NA`/`CS`/`NS` from the
[Character Comparisons](../Character%20Comparisons#readme) note, and they inherit its
worst feature — `sy-fdpos` is filled on success *and* on failure, with different
meanings:

> `"Contains Only: True, if operand1 only contains bytes from operand2. If operand2 is of type xstring and initial, the comparison expression is false, unless operand1 is also of type xstring and initial, in which case the comparison expression is always true. If the comparison is false, sy-fdpos contains the offset of the first byte in operand1, which is not contained in operand2. If the comparison is true, sy-fdpos contains the length of operand1."`

So `sy-fdpos = xstrlen( operand1 )` means "matched" for `BYTE-CO` and "did not match"
for `BYTE-CS`. Read the operator before you read the offset.

The initial-operand asymmetry is the other half, and it is inverted between the two
families you would expect to behave alike:

- `BYTE-CO` with an initial `operand2` is **false**, unless `operand1` is also an
  initial `xstring`, in which case it is `"always true"`.
- `BYTE-CA`: `"If operand1 or operand2 are of the type xstring and initial, the comparison expression is always false."`

A validation guard written with `BYTE-CO` therefore *passes* empty input and one
written with `BYTE-CA` *rejects* everything — the identical trap the character-side
note documents for `CO` and `CA`.

> **Doc-state note:** the `BYTE-CS` row in the current table reads "If `operand1` is
> of type `xs` and initial", which is evidently a truncation of `xstring`. Quoted
> here as paraphrase rather than verbatim for that reason.

A genuinely useful idiom from the doc's own example — testing that every byte has an
empty upper nibble: `"The logical expression in the IF statement is true, if the second half-byte is not filled for any of the bytes in hex1."`

## 6. Bits are 1-based, MSB-first, and off-the-end is not an error

> `"The bit positions in byte_string are counted from left to right, starting with the most significant bit (MSB) of the data object."`

Three things to get right:

- **Position 0 dumps.** `"The value of bitpos must be greater than 0, otherwise uncatchable exceptions are raised."` The runtime error is
  `BIT_OFFSET_NOT_POSITIVE`, and per the repo's
  [Checkpoints](../Checkpoints#readme) note an uncatchable exception is not something
  `TRY` saves you from. Loops over bits start at 1.
- **Past the end is `sy-subrc = 4`, not an exception.** `"If the value of bitpos is greater than the number of bits in byte_string, no bit is read and sy-subrc is set to 4."`
  The target variable keeps its previous value, so an unchecked read in a loop
  repeats the last bit instead of stopping.
- **MSB-first is a convention mismatch waiting to happen.** `"Counting the bits from the most significant bit (MSB) can have unexpected results when working with components that count from the least significant bit (LSB)."`
  Flag registers in external interfaces are frequently LSB-numbered.

Lengths come from `xstrlen( )`, not `strlen( )` — the bit count of a byte string is
`xstrlen( hex ) * 8`. One more detail for DDIC-typed binaries: `dbmaxlen` returns
`abap_max_db_rawstring_ln` for the built-in type, since
`"The latter is also returned for the built-in ABAP types string and xstring."`

## 7. Base64: there are two pairs of methods, and picking the wrong one destroys binaries

`CL_WEB_HTTP_UTILITY` (and the classic `CL_HTTP_UTILITY` on-premise) exposes four
methods whose names differ by three characters and whose types differ completely:

| Method | Importing | Returning |
|---|---|---|
| `encode_base64` | `unencoded TYPE STRING` | `encoded TYPE STRING` |
| `encode_x_base64` | `unencoded TYPE XSTRING` | `encoded TYPE STRING` |
| `decode_base64` | `encoded TYPE STRING` | `decoded TYPE STRING` |
| `decode_x_base64` | `encoded TYPE STRING` | `decoded TYPE XSTRING` |

For a PDF, an XLSX, or any other binary attachment, **only the `_x_` pair is
correct.** `decode_base64` hands back a `string`, and a PDF is not characters in the
system code page — so the bytes are run through a code page conversion that was never
meant for them. The file arrives corrupt, usually with a plausible size, which is why
this gets reported as "the attachment is damaged" rather than as an encoding bug.
Symmetrically, `encode_base64` takes a `string`, so reaching for it with binary
content means converting the binary to a string first — and per section 1, that is
either a hex parse or a code page conversion, neither of which you wanted.

Method signatures above are from the released `CL_WEB_HTTP_UTILITY` interface rather
than from the keyword documentation, which does not cover these classes. `CL_HTTP_UTILITY`
is the long-standing on-premise spelling and is reported as not permitted in ABAP
Cloud, where `CL_WEB_HTTP_UTILITY` carries released status — but treat the Cloud
availability question as belonging to
[ABAP Language Versions](../ABAP%20Language%20Versions#readme) and verify against your
own release.

## The short version

1. `xstr = str` and `CONV xstring( str )` **parse hex digits**; they stop at the
   first non-hex character and tell you nothing.
2. `str = xstr` hands back **hex digits as text**, twice as long, silently truncated
   into a fixed-length `c`.
3. Text to bytes is `CL_ABAP_CONV_CODEPAGE` (or `CL_ABAP_CODEPAGE`), always, with the
   code page named explicitly.
4. `IN BYTE MODE` is never the default, and `CONDENSE`/`TRANSLATE`/`OVERLAY`/
   `CONVERT TEXT`/`WRITE TO` have no byte-mode form.
5. Never cut a UTF-8 byte string at an offset you did not derive from its structure.
6. `BYTE-CO` passes empty input; `BYTE-CA` fails everything; `sy-fdpos` means
   opposite things per operator.
7. Bits are 1-based and MSB-first; position 0 is an uncatchable dump, past-the-end is
   `sy-subrc = 4`.
8. Base64 for binaries is `encode_x_base64` / `decode_x_base64` — the other pair
   quietly ruins the file.

## Sources

- [Source Field Type `c`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_C.html) — the half-byte parse, the first-invalid-character rule, the odd-nibble pad
- [Source Field Type `string`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_STRING.html) — zero-length behaviour, string-to-string reference sharing, the double-byte split hint
- [Source Field Type `x`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_X.html) — hex digits as characters, the `c`-target truncation, last-4-bytes for `i`
- [Source Field Type `xstring`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_XSTRING.html) — ignored leading bytes, zero-length targets
- [Methods for Handling Code Pages](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCL_ABAP_CONV_CODEPAGE.html) — `CL_ABAP_CONV_CODEPAGE`, the UTF-8 default, the round-trip `ASSERT`
- [System Classes for Converting Character Sets](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCL_ABAP_CONV.html) — why `xstring` exists, the three `_CE` classes, the wrapper hint
- [Statements for Character String and Byte String Processing](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSTRING_PROCESSING_STATEMENTS.html) — the strict split and the full statement table
- [`SPLIT`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPSPLIT.html) — `IN BYTE MODE`, inline types, the hex-20 example
- [Comparison Operators for Byte-Like Data Types](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLOGEXP_BYTES.html) — `BYTE-CO`/`CA`/`CS` and `sy-fdpos`
- [`GET BIT`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPGET_BIT.html) — MSB ordering, `sy-subrc = 4`, `BIT_OFFSET_NOT_POSITIVE`
- [Byte Chain Functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENBINARY_FUNCTIONS.html) and [length functions](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENLENGTH_FUNCTIONS.html) — `xstrlen`, `bit-set`, `dbmaxlen`
- [`CL_WEB_HTTP_UTILITY` interface](https://abapedia.org/steampunk-2111-api/cl_web_http_utility.clas.html) — the four base64 signatures and released status

Related notes in this repo: [String Processing](../String%20Processing#readme) for the
character-side trailing-blank and offset rules,
[Character Comparisons](../Character%20Comparisons#readme) for the `sy-fdpos` family
this one mirrors, [File Interface](../File%20Interface#readme) for binary vs text
`OPEN DATASET` and the BOM, [JSON Serialization](../JSON%20Serialization#readme) for
the `xstring` that `CALL TRANSFORMATION` hands back,
[Regular Expressions](../Regular%20Expressions#readme) for UCS-2 versus UTF-16
counting, and [Numeric Arithmetic](../Numeric%20Arithmetic#readme) for the
calculation type the `x`-to-`i` rules feed into.

Worked, runnable examples: [ydj_byte_string_demo.abap](ydj_byte_string_demo.abap)
