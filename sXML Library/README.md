# sXML Library | The Reader That Cannot Be Rewound, the `VALUE` That Keeps the Previous Node's Text & the Duplicate Attribute That Two APIs Count Differently

This repo's [JSON Serialization](../JSON%20Serialization#readme) note uses
`cl_sxml_string_writer=>create( type = if_sxml=>co_xt_json )` as a *sink* --- a
thing you hand to `CALL TRANSFORMATION id` and then ask for its output. That is
one line of a library, and it is the half that has no traps in it.

The other half is the reader, and it is a different kind of object than it
looks. There is no document behind it:

> "In contrast to the iXML Library for ABAP Cloud and the iXML Library Classic,
> no document is created in DOM format and no DTDs (Document Type Definitions)
> are supported. Instead, the nodes of the tree structure represented by the XML
> data are processed serially and only the current node can be accessed."
> -- [`sXML Library`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB.html)

Every surprise below is a consequence of that one sentence. There is nothing to
go back to, so there is no rewind, no re-read and no second pass. What makes it
a trap rather than a documented limitation is that the API does not refuse the
things you cannot do --- it returns the *previous* answer, or silently does
nothing, and the parse loop finishes normally.

Use it when the payload is large or foreign and you do not need the whole tree:

> "If access to all nodes of an XML document in the memory is not required and
> no DTD is needed, the sXML Library is an alternative to the iXML Library with
> better performance. It also supports more XML formats and enables the handling
> of JSON in ABAP programs."
> -- [`sXML Library`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB.html)

---

## 0. The shape of the thing

Five reader classes, five writer classes, all reached through one interface
each. The source or target is the only difference:

| Reader | Writer | Data lives in |
|---|---|---|
| `CL_SXML_STRING_READER` | `CL_SXML_STRING_WRITER` | a byte string |
| `CL_SXML_TABLE_READER` | `CL_SXML_TABLE_WRITER` | an internal table with a flat byte-like line type |
| `CL_SXML_DATASET_READER` | `CL_SXML_DATASET_WRITER` | a file on the AS instance host |
| `CL_SXML_HTTP_READER` | `CL_SXML_HTTP_WRITER` | an ICF HTTP service / client |
| `CL_SXML_XOP_READER` | `CL_SXML_XOP_WRITER` | an `IF_SXML_XOP=>XOP_PACKAGE` |

Both families are abstract-superclass plus interface: `CL_SXML_READER`
implements the general methods, `IF_SXML_READER` declares what every reader has,
and *"If special components need to be accessed that are not declared in the
interface, a downcast must be used on the corresponding class."*

A reader takes a **byte string**, not a string, and the conversion is yours to
make --- which means the code page of the payload is decided at that line and
nowhere else:

```abap
DATA(lo_reader) = cl_sxml_string_reader=>create(
                    cl_abap_conv_codepage=>create_out( )->convert( lv_text ) ).
```

See [Byte Strings](../Byte%20Strings#readme) for what that conversion commits
you to. There are then two parsing APIs over the same reader, token-based and
object-oriented, and sections 6 to 8 are about the places they disagree.

---

## 1. The reader is a one-way cursor, and there is no reset

Not *rewinding is expensive*. There is no rewind:

> "A reader cannot be used more than once for the same XML data or for other XML
> data. The read position of a reader is controlled during parsing using its
> methods. The actions allowed by a reader depend on its current read position.
> For example, a reader located at the end of the parsed XML data can no longer
> be used as an XML source of the statement `CALL TRANSFORMATION`. No method
> exists that can restore the reader to its initial state. A new reader can be
> created instead."
> -- [`sXML - Parsing`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE.html)

The writer is the same: *"A writer cannot be used more than once for the same
XML data or for other data."*

The read position is not an implementation detail --- it is part of the contract
with `CALL TRANSFORMATION`:

> "The transformation moves the reader by one node and processes the entire
> matching subtree. If the transformation is successful, the reader is located
> at the end of the processed data."
> -- [`CALL TRANSFORMATION`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPCALL_TRANSFORMATION.html)

Three designs die on those two quotes, and none of them fails at activation:

- **Sniff, then deserialize.** *Parse the payload to find out which schema it
  is, then run `CALL TRANSFORMATION id` on the same reader* works --- but only
  if you stop the sniffing loop on exactly the element opening you want handed
  over. One `next_node( )` too many and the transformation is pointed at the
  wrong subtree, or at nothing.
- **Deserialize, then inspect the rest.** Impossible. A successful
  transformation leaves the reader at the end of what it consumed.
- **Catch and retry.** A `TRY` around a transformation that re-runs it on the
  same reader cannot work. There is nothing to retry with.

SAP's own example for the hand-over is worth reading closely, because it
contains the next section's trap as load-bearing code:

```abap
FINAL(reader) = CAST if_sxml_reader( cl_sxml_string_reader=>create( xml ) ).

WHILE reader->name <> 'body'.
  reader->next_node( ).
ENDWHILE.

DATA itab TYPE TABLE OF i.
CALL TRANSFORMATION id SOURCE XML reader
                       RESULT table = itab.
```

That loop terminates on the `<body>` element opening rather than running past
it only because of how `NAME` behaves --- see section 2. It also has no
`CO_NT_FINAL` guard, so a payload that never contains `<body>` does not stop on
the condition it tests. *That last observation is mine, not SAP's: the example
is written for a known payload, and copying it to an unknown one is the
mistake.*

---

## 2. `VALUE` is not cleared between nodes --- the quiet one

This is the section to read if you only read one. The reader's attributes are
*not* a snapshot of the current node:

> "When parsing, the attributes of a reader are only overwritten by non-initial
> content. If the parser is set to a literal element without a name, for
> example, the preceding content of the attribute `NAME` is kept. This applies
> particularly to the attribute `VALUE`, which is not initialized if a node has
> no value."
> -- [`sXML - Token-Based Parsing`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE_ITERATIVE.html)

So the obvious loop --- step, then read name and value --- is wrong for every
node that has no value of its own:

```abap
DO.
  reader->next_node( ).
  IF reader->node_type = if_sxml_node=>co_nt_final.
    EXIT.
  ENDIF.
  " WRONG for element openings, element closes and empty elements:
  " reader->value still holds whatever the last VALUE node held.
  APPEND VALUE #( name = reader->name value = reader->value ) TO result.
ENDDO.
```

Given `<city>Kochi</city><empty/>`, the `<empty/>` element opening reports
`Kochi`. Nothing is raised. `sy-subrc` is not involved --- these are attributes
of an object, not a statement result. The output is *plausible*: every empty
element inherits the text of the last non-empty one, which looks like a
mapping bug in the sender rather than a parser misuse in the receiver.

The rule is therefore: **read `VALUE` only when `NODE_TYPE` is
`CO_NT_VALUE`.** The tree shape the documentation draws is what makes that
correct --- the value is a *subnode* of the element opening, not a property of
it:

```
|--CO_NT_ELEMENT_OPEN
|  |
|  |--CO_NT_VALUE
|
|--CO_NT_ELEMENT_CLOSE
```

Attributes are the exception to that shape, and they are explicitly attached to
the opening: *"They are assigned as a list to the node with the type
`CO_NT_ELEMENT_OPEN` and can be accessed using special methods when the parser
is on the opening of the element."*

The same stickiness is what makes `reader->name` usable as a `WHILE` condition
in section 1's example, and it is why `reader->prefix` and `reader->nsuri` need
the identical discipline. The object-oriented API does not have this problem at
all --- *"Unlike in token-based parsing, only the relevant values are
available."*

---

## 3. `PUSH_BACK` is a branch, not an undo

It looks like the escape hatch from section 1. It is not:

> "Token-based parsing is designed mainly for forward iteration through the XML
> data. Free navigation, as possible in iXML Library in DOM, is not recommended
> here. The method `PUSH_BACK` makes it possible to move back a step but does
> not restore the reader to the state it had when it reached the node using
> `NEXT_NODE`. After a `PUSH_BACK`, the parsed node does not always produce the
> same result as the last time. In particular, subnodes already parsed could be
> skipped."
> -- [`sXML - Token-Based Parsing`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE_ITERATIVE.html)

*"the parsed node does not always produce the same result as the last time"* is
a remarkable thing for a parser to promise. Re-reading a node after a
`PUSH_BACK` can legitimately give you less than the first read did.

What it is actually for, and the two siblings it is grouped with:

| Method | Documented behaviour |
|---|---|
| `NEXT_NODE` | *"Moves the parser to the next node"* |
| `CURRENT_NODE` | *"Resets the parser to the node for the element opening of the current node, if available. This method is ignored by value nodes or closed elements."* |
| `PUSH_BACK` | *"Resets the parser to the node for the element opening of the direct parent node."* |
| `SKIP_NODE` | *"Parses all nodes from a node for an element opening to the associated end of element."* |

`CURRENT_NODE` has a stated purpose, and it is narrow: *"The method
`CURRENT_NODE` is most useful when reading an attribute list, to return to the
start."* Note its failure mode --- *"This method is ignored by value nodes or
closed elements"*. **Ignored**, not rejected. Call it from the wrong node type
and your code continues with the parser exactly where it was, which is the
hardest class of bug to see in a loop.

In the object-oriented API the pairing is explicit: *"If the current node is to
be accessed after `PUSH_BACK`, the node object can be obtained using
`READ_CURRENT_NODE`."*

---

## 4. `SKIP_NODE` buys no speed --- and that is what makes it useful

The name promises a shortcut. The documentation says the opposite, in the
overview page's list of library characteristics:

> "Serial processing of XML data in the sXML Library involves the parsing and
> rendering of each node from front to back without a preview. This is
> particularly clear in the parser method `SKIP_NODE`, which skips a node, but
> still has to parse it with all subnodes. This characteristic can be exploited
> to check whether data is well-formed and to test the copying of XML data to a
> writer."
> -- [`sXML Library`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB.html)

So *skipping* a 50 MB subtree costs the same as reading it. In exchange you get
two things that are hard to get any other way.

**A well-formedness check.** Create a reader, `skip_node( )` the root, and if no
`CX_SXML_PARSE_ERROR` arrives the document parsed. No target type, no schema, no
transformation.

**A format converter.** Pass a writer and the subtree is copied into it --- and
*"In particular, the format of the copied tree or subtree can be transformed
into a different format."* An XML-to-JSON converter with no ABAP data type
anywhere in it:

```abap
DATA(lo_reader) = cl_sxml_string_reader=>create( lv_xml ).
DATA(lo_writer) = CAST if_sxml_writer(
  cl_sxml_string_writer=>create( type = if_sxml=>co_xt_json ) ).

DO.
  lo_reader->next_node( ).
  IF lo_reader->node_type = if_sxml_node=>co_nt_final.
    EXIT.
  ENDIF.
  IF lo_reader->node_type = if_sxml_node=>co_nt_element_open
     AND lo_reader->name = 'items'.
    lo_reader->skip_node( lo_writer ).   " copies, and converts
    EXIT.
  ENDIF.
ENDDO.

DATA(lv_json) = CAST cl_sxml_string_writer( lo_writer )->get_output( ).
```

And the same silent-no-op warning as `CURRENT_NODE`: *"This method has no effect
for value nodes or closed elements."* A loop that calls `skip_node( )` on the
wrong node type does not skip, does not complain, and walks into the subtree it
was supposed to drop.

One hierarchy note from SAP's own example: because `skip_node( )` leaves the
parser on the *end* of the element, a loop that tracks nesting depth has to
decrement its own level counter after the call --- the matching
`CO_NT_ELEMENT_CLOSE` is consumed inside `skip_node( )` and never reaches the
loop body.

---

## 5. The copy in section 4 is lossy by construction

Three node kinds cannot survive a trip through an sXML writer, because the
writers cannot produce them:

> "The writers in the sXML Library do not currently support XML comments, CDATA
> sections, or processor instructions."
> -- [`sXML - Rendering`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_RENDER.html)

Which turns section 4's elegant validity check into something narrower than it
appears: *the document that was proved well-formed is not the document that
came out of the writer.* If comments or CDATA matter to the consumer --- and in
an interface where somebody put a licence header or an embedded HTML fragment in
a `CDATA` block, they do --- the copy is not a copy.

Entity handling, in contrast, is symmetric and automatic in both directions:

> "If the content of elements or attributes contain the notations `&lt;`,
> `&gt;`, `&amp;`, `&quot;`, or `&apos;`, they are transformed automatically to
> the corresponding characters when parsed."
> -- [`sXML - Parsing`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE.html)

> "If rendering produces content of elements or attributes, the characters `<`,
> `>`, `&`, `"`, and `'` are transformed automatically into the respective XML
> notation."
> -- [`sXML - Rendering`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_RENDER.html)

So you never escape by hand, and you never double-escape. Raw data is handled
for you as well, per format: byte-like values go to *"the format Base64 for XML
1.0 or to the binary part of the XOP package for XOP."*

---

## 6. Duplicate attribute names: the two APIs return different lists

Same payload, same reader class, two documented answers.

> "If an XML element has multiple identically named attributes, all of these
> attributes are respected in the order in which they appear (see example class
> `CL_DEMO_XML_ATTRIBUTES`)"
> -- [`sXML - Token-Based Parsing`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE_ITERATIVE.html)

> "If an XML element has multiple identically named attributes, only one of
> these attributes is used in object-oriented parsing (unlike in token-based
> parsing). This attribute has the value of the last identically named
> attribute (see example class `CL_DEMO_XML_ATTRIBUTES`)"
> -- [`sXML - Object-Oriented Parsing`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE_OO.html)

`NEXT_ATTRIBUTE` iterates *n* attributes; `GET_ATTRIBUTES` returns *one*. If a
sender duplicates an attribute name --- which is not well-formed XML, but is
exactly the kind of thing a hand-built payload does --- then a refactor from one
API to the other changes the data your program sees, and no diff in the
refactor shows it. Neither API reports anything.

The two APIs are not walled off from each other, which is how a refactor ends
up half-done: *"Token-based parsing and object-oriented parsing are not strictly
separated. Methods such as `NEXT_NODE` and `READ_NEXT_NODE` can be called
alternately in the same program."* The documentation discourages it *"for
reasons of readability"* --- the stronger reason is this section.

---

## 7. The two APIs also end differently

The end-of-data signal is not the same, and this is the detail that turns a
one-line API swap into an endless loop.

| | step method | end of data | node access |
|---|---|---|---|
| Token-based | `NEXT_NODE` | `NODE_TYPE` = `IF_SXML_NODE=>CO_NT_FINAL` | reader attributes, sticky (section 2) |
| Object-oriented | `READ_NEXT_NODE` | the returned reference `IS INITIAL` | node object, only relevant values |

> "The static type of the reference variable node is then `IF_SXML_NODE`, which
> points to a node object. The return value is initial at the end of the XML
> data."
> -- [`sXML - Object-Oriented Parsing`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE_OO.html)

A loop converted from `NEXT_NODE` to `READ_NEXT_NODE` that keeps testing
`CO_NT_FINAL` tests an attribute that the new call does not have to maintain,
against a node object that is already initial. *Whether that spins or dumps
depends on what the initial reference is dereferenced into next --- the point is
that the exit condition is no longer the one being tested.*

The object-oriented side costs something, and the documentation says so twice:
*"Object-oriented parsing is more convenient than token-based parsing, but the
many extra objects that are created can affect performance negatively."* and,
for the writer, *"Object-oriented rendering can demonstrate poorer performance
than token-based rendering due to the extra objects that are created."* On a
library whose entire reason for existing is being faster than DOM, that is
worth knowing before you pick the nicer API.

The node objects themselves follow a tidy pattern, verified against SAP's
`CL_DEMO_SXML_OO_READER`:

```abap
DATA(lo_node) = lo_reader->read_next_node( ).
IF lo_node IS INITIAL.
  EXIT.
ENDIF.

CASE lo_node->type.
  WHEN if_sxml_node=>co_nt_element_open.
    DATA(lo_open) = CAST if_sxml_open_element( lo_node ).
    DATA(lv_name) = lo_open->qname-name.        " not ->name
    DATA(lv_ns)   = lo_open->qname-namespace.   " reader calls this NSURI
    DATA(lt_att)  = lo_open->get_attributes( ).
  WHEN if_sxml_node=>co_nt_value.
    DATA(lo_val) = CAST if_sxml_value_node( lo_node ).
    IF lo_val->value_type = if_sxml_value=>co_vt_text.
      DATA(lv_text) = lo_val->get_value( ).
    ELSEIF lo_val->value_type = if_sxml_value=>co_vt_raw.
      DATA(lv_raw) = lo_val->get_value_raw( ).
    ENDIF.
ENDCASE.
```

Two naming traps in there: the node object exposes the name as `qname-name`
while the reader exposes it as `NAME`, and the namespace as `qname-namespace`
while the reader calls it `NSURI`. And `VALUE_TYPE` must be checked before
choosing an accessor --- `get_value( )` is not the right call for raw data.

---

## 8. Readers and writers disagree about which reference you should hold

This is why writer code is full of `CAST` in both directions while reader code
has none. It is deliberate, and both halves are documented in one sentence
each.

> "The static type of the reference variables is then the interface
> `IF_SXML_READER` and its methods and attributes can be addressed directly."
> -- [`sXML - Token-Based Parsing`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE_ITERATIVE.html)

> "Here, the static type of the reference variables is the type of the class
> itself, since more class-specific methods exist than in readers."
> -- [`sXML - Token-Based Rendering`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_RENDER_TOKEN.html)

So `cl_sxml_string_reader=>create( )` already gives you the interface, and
`cl_sxml_string_writer=>create( )` gives you the class. Which means the writer
needs an upcast to reach the interface methods, and a downcast to get its result
back out:

> "Since the method is a class-specific method, a downcast is required if an
> interface reference variable is used."
> -- [`sXML - Token-Based Rendering`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_RENDER_TOKEN.html)

```abap
" up, to write nodes and set options
DATA(lo_writer) = CAST if_sxml_writer( cl_sxml_string_writer=>create( ) ).
lo_writer->open_element( name = 'doc' ).
lo_writer->write_value( 'hello' ).
lo_writer->close_element( ).

" down, to read the result
DATA(lv_raw) = CAST cl_sxml_string_writer( lo_writer )->get_output( ).
```

`GET_OUTPUT` exists only where there is something to get: *"For writers that do
not write to external repositories, the written XML can be read using the
method `GET_OUTPUT`."* A dataset writer or HTTP writer has already sent its
bytes somewhere. See [Reference Casting](../Reference%20Casting#readme) for what
a failed `?=` leaves behind, which is the other half of this.

The writer also validates as it goes --- *"A writer of this type is validating,
which means that invalid actions, such as attempts to add an attribute to a
value node, raise an exception."* --- so token order is enforced, not merely
expected.

---

## 9. The XML declaration is off by default, and three things can override it

A standalone sXML writer emits no `<?xml ... ?>` line unless you ask:

> "The XML declaration can be set in the IF_SXML_WRITER interface using one of
> the following values for the option CO_OPT_XML_HEADER:"
>
> - "CO_OPT_VAL_NO (no XML header)"
> - "CO_OPT_VAL_WITHOUT_ENCODING (version)"
> - "CO_OPT_VAL_FULL (version and encoding)"
>
> "The default option is CO_OPT_VAL_NO. Using the option xml_header for CALL
> TRANSFORMATION overrides the option in IF_SXML_WRITER if it is initial. For
> JSON and Binary XML, the setting of the option is ignored."
> -- [`sXML - Rendering`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_RENDER.html)

Four separate facts in one quote, and each is a different support call:

- a consumer that requires a declaration rejects your output, and nothing in
  your code mentions a header at all;
- the **same writer object** produces different bytes depending on whether you
  wrote the nodes yourself or a `CALL TRANSFORMATION` wrote them, because the
  statement's own `xml_header` option wins *"if it is initial"*;
- for a JSON writer the option is simply ignored --- so testing your header
  logic against the JSON writer from the
  [JSON Serialization](../JSON%20Serialization#readme) note proves nothing;
- and the encoding is a *second*, independent source of a prefix:

> "An XML writer to which the character format UTF16BE or UTF16LE was passed to
> the parameter `ENCODING` uses the byte order mark (BOM) required by the XML
> standard as the prefix for the written XML data."
> -- [`sXML - Supported Formats`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_FORMATS.html)

A BOM is invisible in every editor and breaks string comparisons, which is the
same class of problem the [File Interface](../File%20Interface#readme) note
documents on the download side. Note also that *"Writers for Binary XML only
accept the default value"* for `ENCODING`.

Set the option **before the first node**, and read it back if you are branching
on it, which is what SAP's own `CL_DEMO_SXML_HEADER` does:

```abap
lo_writer->set_option( option = if_sxml_writer=>co_opt_xml_header
                       value  = if_sxml_writer=>co_opt_val_full ).
...
CASE lo_writer->get_option( option = if_sxml_writer=>co_opt_xml_header ).
```

---

## 10. The reader sniffs the format, so JSON parses silently --- under other names

Readers are not told what they are holding:

> "When an XML reader is created, it itself detects the format of the data
> passed to the parameter `INPUT` of the factory method `CREATE`. The same
> reader classes can be used for all formats except XOP."
> -- [`sXML - Supported Formats`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_FORMATS.html)

That is convenient right up to the moment somebody switches an interface from
XML to JSON, because JSON is not parsed as JSON:

> "JSON is not XML but JSON data can be represented using XML data. Once mapping
> of this type is the SAP-specific JSON-XML. The format JSON in sXML Library
> means that an XML writer of this format transforms valid JSON-XML data to JSON
> data and an XML reader detects JSON data and parses it as if it were JSON-XML
> data. All methods for handling JSON in ABAP are based on readers and writers
> like these."
> -- [`sXML - Supported Formats`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_FORMATS.html)

*(The second sentence of that quote is garbled in the source. "Once mapping of
this type is the SAP-specific JSON-XML" is presumably meant to read one mapping
of this type. Quoted as written.)*

The practical consequence: your `IF reader->name = 'city'` never matches. In
JSON-XML the element names are the *structural* names of the JSON type system,
and your original key arrives as an attribute called `name` on that element. So
the loop runs to `CO_NT_FINAL`, matches nothing, reports no error, and the
program concludes the payload was empty. Use `GET_ATTRIBUTE_VALUE` ---
*"Sets the attribute `VALUE` of the reader to the value of a specific
attribute"* --- rather than the element name:

```abap
lo_reader->get_attribute_value( 'name' ).   " positional, as in SAP's demo
DATA(lv_key) = lo_reader->value.
```

Two format notes that are easy to trip on:

- **XOP opts out of the sniffing.** *"Only the special class
  `CL_SXML_XOP_READER` can be used for the XOP format. The factory method
  `CREATE` of this class expects an actual parameter of the type
  `IF_SXML_XOP=>XOP_PACKAGE`."* Not a byte string --- a structure whose
  `PARTS` component is a hashed table of the raw parts, keyed by `CONTENT_ID`.
- **`TYPE` tells you what you actually got.** *"The attribute `TYPE` declared in
  the interface `IF_SXML` contains the type of every XML reader and XML writer
  or the format it is processing."* That is the only honest way to find out
  which format the sniffer decided on.

For what `id` produces on the way out --- `asXML` versus `asJSON`, and why
`abap_bool` never becomes `true` --- see
[JSON Serialization](../JSON%20Serialization#readme). This note is about the
layer underneath it.

---

## 11. sXML rejects XML that iXML accepted

Moving a parser from iXML to sXML for the performance is a payload decision,
not a refactor:

> "The parser of the sXML Library is a more strict validator than the parser of
> the iXML Library. A namespace prefix must be declared in the same element or
> in a superelement. Preceding declarations in a parallel element are
> interpreted as errors."
> -- [`sXML - Parsing`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE.html)

```xml
<root>
  <a xmlns:ns="urn:example">1</a>
  <ns:b>2</ns:b>          <!-- prefix declared in a PARALLEL element -->
</root>
```

The character set changes with the library too, which the `CALL TRANSFORMATION`
page states while comparing the two: *"The iXML Library supports UCS-2 and the
sXML Library supports UTF."* And the directions of travel differ: sXML
*"supports the UTF character representation of the Unicode character set and
hence also characters from the surrogate area"*, while the iXML libraries
*"create a DOM document and support DTDs"* --- which sXML does not.

Note what failing part-way through means for a streaming parser. A
`CX_SXML_PARSE_ERROR` can arrive after the reader has already produced valid
nodes, so anything you wrote to a target before the error is half-written. There
is no transaction around a parse, and per section 1 there is no reset to
restart from.

---

## 12. The exceptions, and the ones the compiler lets you forget

> "The exception classes in the sXML library usually start with the prefix
> `CX_SXML`. The exceptions of category `CX_DYNAMIC_CHECK` are propagated to the
> caller and must be handled by the user. The subclass `CX_SXML_INTERNAL_ERROR`
> of `CX_NO_CHECK` represents internal errors in the library and cannot usually
> be handled properly in an application program."
> -- [`sXML - Exception Classes`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_EXCEPTIONS.html)

```
CX_ROOT
 |
 |--CX_DYNAMIC_CHECK
 |   |--CX_ABAP_XML_NAME_ERROR
 |   |--CX_SXML_ERROR
 |   |--CX_SXML_ILLEGAL_ARGUMENT_ERROR
 |   |--CX_SXML_NAME_ERROR
 |   |--CX_SXML_PARSE_ERROR
 |   |--CX_SXML_STATE_ERROR
 |
 |--CX_NO_CHECK
     |--CX_SXML_INTERNAL_ERROR
```

`CX_DYNAMIC_CHECK` is the important word. A parse loop with no `TRY` **activates
cleanly** and dumps on the first malformed payload --- the same shape this repo
documents for [AMDP](../AMDP#readme), where `CX_AMDP_*` being
`CX_DYNAMIC_CHECK` makes a `CATCH` without a `RAISING` into dead code. Here it
runs the other way: the compiler does not insist you catch, and the first
payload from a new sender is where you find out.

`CX_SXML_STATE_ERROR` is the one named for sections 1 and 3 --- a method called
from a read or write position that does not permit it. And a documented
exception worth knowing by name: reading an attribute as raw with
`next_attribute_value( if_sxml_value=>co_vt_raw )` raises
`CX_SXML_PARSE_ERROR` when the value is not valid Base64, which is why SAP's own
example catches it and continues rather than treating it as fatal.

---

## Quick reference

| You want | Do this | Watch out for |
|---|---|---|
| Parse a string | convert to `xstring` first, then `cl_sxml_string_reader=>create( )` | `CREATE` takes byte-like data; the code page is decided at that line |
| Step through nodes | `next_node( )` until `node_type = if_sxml_node=>co_nt_final` | read `value` **only** on `co_nt_value` (section 2) |
| Read attributes | park on `co_nt_element_open`, then `next_attribute( )` until `node_type <> co_nt_attribute` | `current_node( )` to return to the start of the list |
| Read one named attribute | `get_attribute_value( 'attr' )`, then read `value` | positional parameter; `value` is sticky if it does not match |
| Object-oriented walk | `read_next_node( )` until the reference `IS INITIAL` | **not** `co_nt_final`; duplicate attributes collapse (sections 6, 7) |
| Validate a document | `skip_node( )` the root inside a `TRY` | parses the whole subtree anyway; a `TRY` is mandatory, not optional |
| Convert XML to JSON | `skip_node( lo_json_writer )` | comments, CDATA and PIs are dropped (section 5) |
| Write XML | `CAST if_sxml_writer( ...create( ) )`, then `open_element` / `write_attribute` / `write_value` / `close_element` | attribute-after-value raises; order is validated |
| Get the result | `CAST cl_sxml_string_writer( w )->get_output( )` | class-specific method, downcast required; absent on dataset/HTTP writers |
| Emit a declaration | `set_option( co_opt_xml_header, co_opt_val_full )` before the first node | default is `CO_OPT_VAL_NO`; ignored for JSON and Binary XML |
| Hand a reader to `CALL TRANSFORMATION` | stop on the element opening you want consumed | the reader ends up at the end of the consumed subtree, and cannot be reused |
| Reuse a reader | you cannot | create a new one; there is no reset (section 1) |

Formats, all constants of `IF_SXML`: `CO_XT_XML10` (default), `CO_XT_JSON`,
`CO_XT_BINARY`, `CO_XT_XOP`.

---

## 13. Defects in the sources, and what I did not verify

The repo's convention is that double quotes mean verbatim SAP text. These are
the places where the verbatim text is wrong or inconsistent, found while
checking the quotes above against SAP's own example code.

- **`CO_VT_TEXT` is listed twice.** The token-based parsing page's table of
  reader attributes gives `VALUE_TYPE` two entries: *"CO_VT_TEXT - Text data in
  the attribute VALUE"* and *"CO_VT_TEXT - Raw data in the attribute
  VALUE_RAW"*. The second is a copy-paste defect. The constant that exists is
  `CO_VT_RAW`, which SAP's own `CL_DEMO_SXML_OO_READER` and
  `CL_DEMO_SXML_TOKEN_RDR_MTHDS` both test against.
- **`IF_SXML_READER` where `IF_SXML_NODE` is meant.** The parsing overview says
  the node names in its tree diagram *"are the same as the constants of the
  interface IF_SXML_READER that describe the type of a node"*. Every code
  example on that page and in the library qualifies them as
  `IF_SXML_NODE=>CO_NT_...`, which is what compiles.
- **`IF_SXML_READER` where `IF_SXML_WRITER` is meant.** The object-oriented
  rendering page says a node object *"can be created using one of the dedicated
  methods of the interface IF_SXML_READER, such as NEW_OPEN_ELEMENT,
  NEW_CLOSE_ELEMENT, and NEW_VALUE"* --- and then its own example calls
  `writer->new_open_element( )`, and its own method table lists all five under
  `IF_SXML_WRITER`.
- **A missing word.** *"Once mapping of this type is the SAP-specific
  JSON-XML"* on the formats page is presumably *one mapping of this type*.

Not verified, and deliberately not asserted anywhere above:

- **Whether a duplicate-attribute payload is accepted at all.** Section 6
  quotes both documented outcomes, but duplicate attribute names are not
  well-formed XML and section 11's parser is the stricter of the two libraries.
  The demo attempts it and prints the real outcome rather than claiming one.
- **`CO_NT_COMMENT` and `CO_NT_PI`.** Both appear in SAP's own demo classes
  only as commented-out `WHEN` branches, which is consistent with section 5's
  statement that writers cannot produce them --- but I have no documented
  statement about whether a *reader* ever reports them, so the demo's `CASE`
  does not test for them and this note makes no claim.
- **Release availability.** Everything here is quoted from the 8.16 rendering
  of the keyword documentation. `CL_ABAP_CONV_CODEPAGE` is used because SAP's
  current examples use it; `CL_ABAP_CODEPAGE=>CONVERT_TO( )` is the older static
  equivalent, and which one your system has is a release question this note does
  not answer.

---

## Demo program

[`ydj_sxml_stream_demo.abap`](ydj_sxml_stream_demo.abap) --- eight runnable
traps, one per section.

The sXML Library is pure in-memory string processing, so this demo is genuinely
read-only rather than read-only by careful arrangement: it contains no `SELECT`,
no `CALL FUNCTION`, no `COMMIT WORK`, no file access and no RFC. Every payload is
a literal built in the program. It is safe to run in any client.

Each trap creates its own reader, which is itself the point of section 1 ---
there is no way to share one.

---

## Sources

ABAP keyword documentation, 8.16:

- [`sXML Library`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB.html) --- no DOM, no DTD, the `SKIP_NODE` characteristic, when to prefer sXML over iXML
- [`sXML - Parsing`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE.html) --- the node tree, the five reader classes, single use and no reset, the stricter validator, entity handling
- [`sXML - Token-Based Parsing`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE_ITERATIVE.html) --- the non-initial-overwrite rule, the four navigation methods, `PUSH_BACK` not restoring state, duplicate attributes kept
- [`sXML - Object-Oriented Parsing`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE_OO.html) --- `READ_NEXT_NODE` returning initial, duplicate attributes collapsed, the performance caveat
- [`sXML - Rendering`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_RENDER.html) --- validating writers, single use, `GET_OUTPUT`, the XML header option, no comments/CDATA/PIs
- [`sXML - Token-Based Rendering`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_RENDER_TOKEN.html) --- the static-type asymmetry, the downcast for `GET_OUTPUT`, the seven write methods
- [`sXML - Object-Oriented Rendering`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_RENDER_OO.html) --- `WRITE_NODE` and the `NEW_*` factories
- [`sXML - Supported Formats`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_FORMATS.html) --- the four formats, reader format detection, XOP packages, the UTF-16 BOM
- [`sXML - XML Reader`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_READER.html) / [`XML Writer`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_WRITER.html) --- the class hierarchies
- [`sXML - Exception Classes`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_EXCEPTIONS.html) --- the `CX_SXML_*` tree and its two categories
- [`CALL TRANSFORMATION`](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABAPCALL_TRANSFORMATION.html) --- a reader as `SOURCE XML` and a writer as `RESULT XML`, the position contract, UCS-2 versus UTF

SAP example classes referenced above (package `SXML_DEMO`):
`CL_DEMO_SXML_TOKEN_RDR_STEPS`, `CL_DEMO_SXML_TOKEN_RDR_MTHDS`,
`CL_DEMO_SXML_OO_READER`, `CL_DEMO_SXML_TRAFO_FROM_READER`,
`CL_DEMO_SXML_HEADER`, `CL_DEMO_XML_ATTRIBUTES`.

---

## Related notes in this repo

- [JSON Serialization](../JSON%20Serialization#readme) --- the layer above this one: `CALL TRANSFORMATION id`, `asJSON`, and the sXML writer used purely as a sink
- [Byte Strings](../Byte%20Strings#readme) --- the `string` / `xstring` boundary every `create( )` call crosses
- [String Templates](../String%20Templates#readme) --- `XSD = YES` and the other direction of asXML formatting
- [Reference Casting](../Reference%20Casting#readme) --- what the `CAST` calls in sections 7 and 8 do when they fail
- [Exception Flow](../Exception%20Flow#readme) --- `CX_DYNAMIC_CHECK` versus `CX_NO_CHECK`, and why section 12 compiles without a `TRY`
- [AMDP](../AMDP#readme) --- the other place in this repo where `CX_DYNAMIC_CHECK` makes the compiler stay quiet
- [HTTP Client](../HTTP%20Client#readme) --- where `CL_SXML_HTTP_READER` and `CL_SXML_HTTP_WRITER` get their streams
- [File Interface](../File%20Interface#readme) --- the BOM and code-page problems of section 9, on the file side
- [Dynamic Method Calls](../Dynamic%20Method%20Calls#readme) --- `CALL METHOD reader->(method)`, which is how SAP's own step-by-step example drives the parser
- [List Processing](../List%20Processing#readme) --- why the demo hoists every value out of its `WRITE` lists
