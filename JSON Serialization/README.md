# JSON & XML Serialization — `CALL TRANSFORMATION id`, the asJSON traps, and `/ui2/cl_json`

Every SAP integration eventually serializes ABAP data. There are two common
routes and they do **not** produce the same payload:

| Route | Available | Produces |
|---|---|---|
| `CALL TRANSFORMATION id` (identity transformation) | SAP_BASIS 7.40+, kernel-native | **asXML** or **asJSON** — the canonical, non-negotiable format |
| `/ui2/cl_json=>serialize( )` | UI2 add-on (SAP_BASIS 740–76X) | configurable format (camelCase, compression, ISO timestamps) |

The kernel route is the fast one. The class route is the one whose output looks
like JSON an external consumer would expect. Choosing the fast one because it is
fast, without knowing what asJSON actually emits, is where the time goes.

> asJSON is produced **only** by the identity transformation `ID`. For your own
> transformations, JSON is handled as [JSON-XML](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENJSON_XML_GLOSRY.html)
> instead, and asJSON does not apply.

---

## 1. asJSON has no booleans, and no lowercase

Two properties of asJSON surprise every consumer on the other end of the wire.

**The names are the SOURCE/RESULT parameter names, upper-cased** — not the names
of your ABAP variables, and never camelCase:

```abap
DATA(writer) = cl_sxml_string_writer=>create( type = if_sxml=>co_xt_json ).

CALL TRANSFORMATION id SOURCE itab = lt_flights   " <-- 'itab' is the contract
                       RESULT XML writer.
" {"ITAB":[{"COMP1":1,"COMP2":"abc","COMP3":"X"}]}
```

Rename that `itab =` to `flights =` for readability and you have made a
**breaking change to the payload**, with no syntax error and nothing in the diff
that looks like an interface change.

The upper-casing applies to the **static** form only. The documentation states
the rule precisely: names specified statically are upper-cased; names specified
dynamically use *the case used there*. So the dynamic bind table is the only way
to get a lowercase key out of the identity transformation:

```abap
DATA(lt_src) = VALUE abap_trans_srcbind_tab(
                 ( name = `order` value = REF #( ls_order ) ) ).

CALL TRANSFORMATION id SOURCE (lt_src) RESULT XML writer.
" {"order":{...}}  <-- lowercase, unreachable via SOURCE order = ls_order
```

Note the syntax: there is no `SOURCE (lv_name) = data`. The dynamic form takes a
**table** of name/reference pairs typed `abap_trans_srcbind_tab` (type group
`ABAP`); the `RESULT` side equivalent is `abap_trans_resbind_tab`.

**There are no JSON booleans.** The documentation is explicit: *"Representations
of Boolean values and zero are not used."* The mapping is purely type-driven:

| ABAP type | asJSON |
|---|---|
| `i`, `p`, `decfloat16`, `decfloat34`, `f` | JSON **number**, unquoted |
| `c`, `string`, `n`, `d`, `t`, `x`, `xstring` | quoted **string** |

So `abap_bool` is `char1` and serializes as `"X"` / `""` — not `true` / `false`.
A JavaScript consumer doing `if (obj.COMP3)` gets it right for `"X"` and right
for `""` by luck; one doing `if (obj.COMP3 === true)` never fires at all.

The same rule makes `n` (NUMC) a quoted string **with its leading zeros intact**
(`"0788"`), because `n` is character-like. This is the opposite of what
`/ui2/cl_json` does by default — see §6.

---

## 2. `clear` defaults to `none` — missing fields keep the old value

This is the trap with real data-corruption potential. On deserialization the
target fields specified after `RESULT` are **not initialized**:

| `clear` | Meaning |
|---|---|
| `all` | All `RESULT` target fields initialized before the transformation. **The documentation's recommended setting.** |
| `supplied` | Only fields with a root node assigned (ST) / present in the data (XSLT) are initialized. |
| `none` | **Default.** Target fields are not initialized — *except* internal tables. |

The doc's own warning: with nonexistent elements *all* data objects retain their
original values; with empty elements *structures* retain their values.

```abap
DATA ls_order TYPE ty_order.
ls_order-customer = 'ACME'.        " left over from the previous iteration

" Payload for the NEXT order legitimately has no customer node at all.
CALL TRANSFORMATION id SOURCE XML lv_json
                       RESULT order = ls_order.

" ls_order-customer is STILL 'ACME'. Order two is now billed to order one's
" customer, with sy-subrc = 0 and no exception.
```

The fix is one addition, and it belongs on **every** deserialization you write:

```abap
CALL TRANSFORMATION id SOURCE XML lv_json
                       RESULT order = ls_order
                       OPTIONS clear = 'all'.
```

Note the asymmetry that hides this in testing: internal tables *are* cleared by
default. A loop deserializing into a **table** behaves correctly, so the bug only
appears once someone deserializes into a flat structure — usually in a
single-record RFC or an OData create.

---

## 3. `initial_components = 'suppress'` is a loaded gun

`initial_components` controls whether initial structure components are written
out at all:

| Value | Meaning |
|---|---|
| `include` | All initial components are produced. |
| `suppress_boxed` | **Default.** Initial *boxed* components suppressed; all others produced. |
| `suppress` | No initial components produced. |

`suppress` is tempting — it can dramatically shrink a payload of mostly-empty
structures. The documentation attaches two warnings to it, and both matter:

1. It should only be used where you have **complete control over the
   deserialization**. If the receiving side does not use `clear = 'all'`, every
   suppressed component silently keeps whatever the target field held before —
   §2, now triggered deliberately by the sender. An external consumer expecting
   the field may simply fail.
2. It also suppresses components typed with the **XML schema domains**. A
   component typed `XSDBOOLEAN` holding `abap_false` is a legitimate, meaningful
   `false` — and it disappears from the payload entirely.

`suppress` plus `clear = 'none'` on the receiver is the pairing that produces
data that is wrong rather than merely absent.

---

## 4. `value_handling` — truncation happens in two directions

On deserialization, the default is strict: a `RESULT` field of type `c`, `n` or
`x` that is too short for the incoming value raises `CX_SY_CONVERSION_DATA_LOSS`,
and a type `p` field with too few decimals raises
`CX_SY_CONVERSION_LOST_DECIMALS`.

| Value | Direction | Meaning |
|---|---|---|
| `default` | both | Raises on invalid `n` (serialize) / too-short target or lost decimals (deserialize). |
| `move` | serialize only | Invalid values in an `n` field are copied out **unchanged**. |
| `accept_data_loss` | deserialize only | Too-short targets are truncated: `c` and `x` **on the right**, `n` **on the left**. |
| `accept_decimals_loss` | deserialize only | Type `p` targets are rounded to the available decimals. |
| `reject_illegal_characters` | deserialize only | Raises `CX_SY_CONVERSION_CODEPAGE` on characters invalid for the encoding/code page. |

The truncation asymmetry is the part worth remembering: `accept_data_loss` cuts
a character field at the **end** and a numeric-text field at the **start**,
because for `n` the rightmost digits are the significant ones. Apply it to a
too-short `matnr` and you keep the *last* digits of a different material number
— a plausible-looking value, not an obviously broken one.

**Catching these is not straightforward.** The conversion exceptions above cannot
be handled directly on `CALL TRANSFORMATION`; they arrive packed into
`CX_TRANSFORMATION_ERROR` or a subclass. Only `CX_SY_TRANS_OPTION_ERROR` — an
invalid option name or value — is raised directly and catchable as itself.

```abap
TRY.
    CALL TRANSFORMATION id SOURCE XML lv_json
                           RESULT data = ls_target
                           OPTIONS clear = 'all'.
  CATCH cx_transformation_error INTO DATA(lx).   " NOT cx_sy_conversion_data_loss
    " lx->get_text( )
ENDTRY.
```

Specifying a value in the wrong direction (e.g. `accept_data_loss` on a
serialization) raises `CX_SY_TRANS_OPTION_ERROR` rather than being ignored.

---

## 5. Writing JSON: the writer, the cast, and `xml_header`

The sXML writer is what turns the identity transformation into JSON. The type
constant is the only thing that decides XML vs JSON:

```abap
" if_sxml=>co_xt_xml10  -> XML 1.0      if_sxml=>co_xt_json -> JSON
DATA(writer) = cl_sxml_string_writer=>create( type = if_sxml=>co_xt_json ).

CALL TRANSFORMATION id SOURCE data = ls_struct
                       RESULT XML writer.        " 'XML' even for a JSON writer

DATA(lv_xstr) = writer->get_output( ).           " always xstring
DATA(lv_json) = cl_abap_conv_codepage=>create_in( )->convert( lv_xstr ).
```

Two details that cost a syntax error each:

- The result is **`xstring`**, never `string`. Convert it
  (`cl_abap_conv_codepage`, or `cl_abap_conv_in_ce` on older releases).
- To reach the formatting methods you must **cast to `if_sxml_writer`**, because
  `create( )` returns the narrower static type:

```abap
DATA(pretty) = CAST if_sxml_writer( cl_sxml_string_writer=>create( type = if_sxml=>co_xt_json ) ).
pretty->set_option( option = if_sxml_writer=>co_opt_linebreaks ).
pretty->set_option( option = if_sxml_writer=>co_opt_indent ).

CALL TRANSFORMATION id SOURCE data = ls_struct RESULT XML pretty.
DATA(lv_out) = CAST cl_sxml_string_writer( pretty )->get_output( ).
```

On newer releases the `SOURCE JSON` / `RESULT JSON` additions skip the writer
entirely:

```abap
CALL TRANSFORMATION id SOURCE var = num RESULT JSON DATA(json).   " -> xstring
CALL TRANSFORMATION id SOURCE JSON json RESULT var = int.
```

**`xml_header` is narrower than it looks.** The option (`full` / `no` /
`without_encoding`, default `full`) only applies when transforming to XML *and*
writing into a data object of type `c`, `string`, or an internal table. Writing
through a writer object is not affected by it.

Serializing **objects** (not just data) additionally requires the class to
implement `IF_SERIALIZABLE_OBJECT` — otherwise the identity transformation will
not serialize the instance.

---

## 6. `/ui2/cl_json` — different defaults, same class of trap

`/ui2/cl_json` exists precisely because asJSON "fits badly for properly handling
ABAP types and name pretty-printing" (SAP's own wording in the open-source
`abap-to-json` project). It is the right choice when an external contract
dictates the format; the kernel transformation is the right choice when you
control both ends and want speed.

```abap
DATA(lv_json) = /ui2/cl_json=>serialize(
                  data        = lt_flights
                  compress    = abap_true                          " skip IS INITIAL fields
                  pretty_name = /ui2/cl_json=>pretty_mode-camel_case ).

/ui2/cl_json=>deserialize( EXPORTING json        = lv_json
                                     pretty_name = /ui2/cl_json=>pretty_mode-camel_case
                           CHANGING  data        = lt_flights ).
```

Defaults worth knowing, all of them different from asJSON:

| Parameter | Default | Effect |
|---|---|---|
| `compress` | `abap_false` | `abap_true` skips all `IS INITIAL` fields — the analogue of `initial_components = 'suppress'`, with the same receiver risk. |
| `pretty_name` | none | `camel_case` / `pascal_case` / `extended`. **Must match on both sides** — serialize camelCase and deserialize without it and fields silently do not map. |
| `numc_as_string` | `abap_false` | NUMC is emitted as an **integer with leading zeros dropped** (`12345`). asJSON keeps `"000000000012345"`. |
| `ts_as_iso8601` | `abap_false` | Timestamps as the numeric string `20160708123456`; `abap_true` gives `"2016-07-08T12:34:56Z"`. Deserialization accepts both either way. |
| `conversion_exits` | `abap_false` | Applies DDIC conversion exits — documented as a performance loss. |
| `assoc_arrays` | `abap_false` | Sorted/hashed tables with a unique key become JSON objects keyed by the key fields (joined with `-` for composite keys). |
| `expand_includes` | `abap_true` | Named includes inlined into the parent object; `abap_false` nests them under the alias. |

And the familiar hazard, restated for this class: on deserialization, *"if the
ABAP structure contains more fields than in the JSON object, the content of
unmatched fields is preserved."* Same bleed as `clear = 'none'` in §2, and here
there is no `clear = 'all'` switch — clear the target yourself first.

Serializing a JSON structure **into an ABAP class instance is not supported**;
only data objects, structures and tables.

---

## Quick reference

```abap
" Safe deserialization - clear = 'all' should be reflexive
CALL TRANSFORMATION id SOURCE XML lv_json
                       RESULT data = ls_target
                       OPTIONS clear = 'all'.

" All options, for reference
... OPTIONS clear              = 'all' | 'supplied' | 'none'
            data_refs          = 'no' | 'heap' | 'heap-or-error' | 'heap-or-create' | 'embedded'
            initial_components = 'include' | 'suppress_boxed' | 'suppress'
            technical_types    = 'error' | 'ignore'
            value_handling     = 'default' | 'move' | 'accept_data_loss'
                               | 'accept_decimals_loss' | 'reject_illegal_characters'
            exceptions         = 'resumable'
            xml_header         = 'full' | 'no' | 'without_encoding'
```

Note that `data_refs` and `technical_types` are largely **XSLT-only**: `no` is
the ST default, while `heap`, `heap-or-error`, `heap-or-create` and `embedded`
(and both `technical_types` values) are documented as possible only in XSLT.
`exceptions = 'resumable'` applies only to deserializations with ST, and pairs
with `CATCH BEFORE UNWIND` + `RESUME` — see
[Exception Flow](../Exception%20Flow#readme) for how resumable exceptions work.

---

## Demo program

[`ydj_json_serial_demo.abap`](ydj_json_serial_demo.abap) — runnable, read-only,
no database access. Demonstrates the uppercase naming contract, the `"X"`/`""`
non-boolean mapping, the `clear = 'none'` value bleed, `initial_components`
suppression, and the two-direction `accept_data_loss` truncation.

---

## Sources

- [`CALL TRANSFORMATION`](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPCALL_TRANSFORMATION.html)
- [`CALL TRANSFORMATION - OPTIONS`](https://help.sap.com/doc/abapdocu_752_index_htm/7.52/en-US/abapcall_transformation_options.htm)
- [asJSON — Canonical JSON Representation](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_ASJSON.html)
- [asJSON — General Format](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_ASJSON_GENERAL.html)
- [asJSON — Mapping of Elementary ABAP Types](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENABAP_ASJSON_ABAP_TYPES_ELEM.html)
- [SAP-samples/abap-cheat-sheets — 21_XML_JSON.md](https://github.com/SAP-samples/abap-cheat-sheets/blob/main/21_XML_JSON.md)
- [SAP/abap-to-json — `/UI2/CL_JSON` documentation](https://github.com/SAP/abap-to-json/blob/main/docs/basic.md)
