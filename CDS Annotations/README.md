# CDS Annotations | The Typo That Activates Clean, the `Default` That Is Not a Default & the One Array Entry That Wipes the List

Annotations are the half of a CDS entity that the SQL does not describe: labels,
currency references, UI layout, OData exposure, authorization relevance. They
look like comments with an `@` in front, and they behave nothing like comments.

Three things make them a recurring source of silent defects:

1. in a data definition they are **not checked by the syntax check at all**,
2. the value you get when you omit an annotation is **not necessarily** the
   value the documentation prints in the `Default` row, and
3. an annotation you never wrote in this entity can still be active in it,
   because annotations are inherited bottom-up and overridden top-down by
   objects you may not know exist.

---

## 0. Two kinds, and only one of them is the ABAP runtime

- **ABAP annotations** are evaluated by the ABAP runtime framework, at
  activation or at runtime, and can change what ABAP SQL does -- the
  `@AbapCatalog`, `@AccessControl`, `@ClientHandling` and `@Metadata`
  families, plus `@EndUserText` and `@Environment.systemField`, which the
  keyword documentation names as ABAP annotations in its own example.
- **Framework-specific annotations** (`@UI.*`, `@OData.*`, `@Analytics.*`,
  `@ObjectModel.*`, `@Consumption.*`) are evaluated by other software
  components through an API. The keyword documentation is explicit about where
  responsibility lies: *"The evaluation of the annotations of CDS source code
  is currently the responsibility of the framework in which the CDS object is
  used."*

Everything else is inert: *"Annotations that are not evaluated by the ABAP
runtime framework or by frameworks of other software components are usually
ignored."* And you cannot invent your own to fill a gap --
*"Partners and customers cannot currently define their own annotations."*

Report `ABAP_DOCU_CDS_ANNOS_OVERVIEW` lists every SAP annotation with its
properties; `ABAP_DOCU_MDE_ANNOS` lists the subset usable in a metadata
extension. Those two reports settle most arguments faster than a blog post.

---

## 1. In a data definition, nobody checks your annotations

This is the single most expensive fact about CDS annotations, and it is stated
plainly in the annotation-syntax documentation. Annotation definitions exist as
repository objects, they drive syntax colouring and code completion in ADT, and
then:

> *"Currently, however, they are not covered by the syntax check."*

That sentence is about **DDL source code for data definitions** -- ordinary
`define view entity` sources. The same paragraph says the opposite about the
three other CDS source types (DCL for roles, DDLX for metadata extensions,
DDLA for annotation definitions), where *"the syntax check allows only those
annotations that follow the rules of an annotation definition"*.

So this view activates without a warning:

```
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.lable: 'Flight connections'              // lable, not label
@UI.headerInfo.typeNamee: 'Flight'                    // typeNamee
@Semantics.amount.currencyCde: 'Currency'             // currencyCde
define view entity ydj_flight_anno
  as select from spfli
{
  key carrid as Carrier,
  key connid as Connection
}
```

Activation is green. The metadata is stored faithfully -- the evaluation
documentation says the save happens *"for every annotation with correct syntax
regardless of name and value"* -- and then nothing reads it, because no
framework is listening for `lable`. The Fiori app shows the technical field
name, the label looks like it was simply never maintained, and the source code
looks right to the next reviewer because the typo is one character deep in a
word nobody re-reads.

Two practical consequences:

- A missing label or a missing UI facet is **never** diagnosed by activating
  the entity again. Check the spelling against
  `ABAP_DOCU_CDS_ANNOS_OVERVIEW`, or read back what was actually stored with
  `CL_DD_DDL_ANNOTATION_SERVICE` (see the demo report in this folder).
- Moving the identical annotation block into a **metadata extension** turns the
  same typo into a hard syntax error, because DDLX is checked:
  *"All other annotations produce syntax errors."* That is a real argument for
  keeping UI metadata in an MDE rather than in the view -- the checking is
  stricter there, not looser.

### Smaller syntax rules worth knowing

- A main annotation without subannotations *"can be specified exactly once in a
  scope"*, and *"An annotation name must be unique within a scope."*
- `@EndUserText: { label: 'x', quickInfo: 'y' }` and
  `@EndUserText.label: 'x'` are the same stored metadata:
  *"The way this metadata is saved internally is independent of the way it is
  specified"*, and the API *"always return subannotations as an individual
  annotation with a structured name."*
- The trailing form `@<Anno` *"can be used in the CDS DDL for CDS entities
  except for CDS view entities"*, and in an MDE *"@< cannot be used for
  introducing an annotation."* Migrating a DDIC-based view that used trailing
  annotations therefore means rewriting every one of them.
- In a single quoted value, escape a quote by doubling it or with a backslash:
  `@EndUserText.quickInfo: 'Customer''s first name'`.

---

## 2. A `Default: true` row does not mean true by default

Every SAP annotation has a properties table in the keyword documentation with a
`Default` row. Two of the `@Metadata` annotations print **`Default: true`** --
and both of them behave as `false` when you leave them out. That is not a
documentation bug; it is a column whose meaning almost nobody reads:

> *"Default value applied during the evaluation when the annotation is
> specified without a value. This value can differ from the value that is
> applied when the annotation is not specified at all."*

So there are **three** distinct states per Boolean annotation, not two:

| What you write | Which value applies |
|---|---|
| `@Metadata.allowExtensions: true` | `true` (explicit) |
| `@Metadata.allowExtensions` (no value) | the `Default` from the properties table -- `true` |
| nothing at all | the not-specified value from the KTD -- `false` |

The annotation documentation (KTD) is where the third column lives. For
`@Metadata.allowExtensions`:

> *"true: The current CDS object can be extended."*
> *"false: The current CDS object cannot be extended."*
> *"If the annotation is not specified, the value false is used."*

And for `@Metadata.ignorePropagatedAnnotations`, which has the same
`Default: true` row:

> *"true: Only direct and derived annotations of the definition are respected."*
> *"false: Inherited annotations of used definitions are also respected."*
> *"If the annotation is not specified, the value false is used."*

### The sentence that sends people the wrong way

The ABAP CDS metadata-extensions page describes the prerequisite like this:

> *"A prerequisite for extending a CDS entity with metadata extensions is that
> the annotation @Metadata.allowExtensions (with the default value true) is
> specified in the DDL source code of the CDS entity."*

Read quickly, the parenthesis sounds like *the default is true, so you need not
write it*. Read with the properties-table definition in hand, it means *write
it, and if you write it bare it means true*. The ABAP Data Models guide states
the operational version without ambiguity: the entity *"must contain the
annotation `@Metadata.allowExtensions` with the value `true` as a header
annotation."*

**Rule: always write the value.** `@Metadata.allowExtensions: true`. A bare
Boolean annotation leaves the outcome depending on which of the two
documented defaults applies, and there is a third reading that agrees with
neither -- the annotation API:

> *"In cases where an annotation has no value specified, the initial annotation
> value is returned rather than any default value defined in the annotation
> definition."*

For a Boolean, the initial value is `false`. So a bare
`@Metadata.ignorePropagatedAnnotations` can mean `true` to the activation
(definition default) and read back as `false` through
`CL_DD_DDL_ANNOTATION_SERVICE`. Reading this note's own warning once is cheaper
than debugging that.

### And one more silent no-op

`@Metadata.allowExtensions` is accepted everywhere and effective almost
nowhere:

> *"Metadata extensions are currently only supported in CDS views and CDS
> abstract entities. In all other CDS entities, there is no syntax error, but
> the annotation Metadata.allowExtensions has no effect."*

`ANNOTATE ENTITY` additionally *"Defines an MDE for any CDS entity except CDS
table functions."*

---

## 3. Annotations you did not write are active in your entity

Element and parameter annotations travel **upwards**, from the data source into
every consuming entity:

> *"a CDS entity selecting from a database table or from another CDS entity
> automatically inherits all annotations belonging to a specific element from
> the underlying data source."*

They arrive from four places: the source code of the entity below, a metadata
extension of the entity below, a CDS user-defined type used to type the
element, or a DDIC data element (whose field labels become `@EndUserText`
values). The last one is why most fields in a plain view entity already have
labels nobody typed.

Overriding goes the other way: *"Specifications in higher layers always
overwrite specifications from lower layers"*, plus one rule that outranks your
own source code -- *"the annotations of a metadata extension always have a
higher priority than the annotations specified in the source code of the CDS
entity itself."*

### The worked precedence order, and the surprise in it

For a stack of `CDS entity 2` -> `CDS entity 1`, each with two MDEs, the
documentation gives the active order from highest to lowest:

```
CUSTOMER extension 2      <- MDE on the consuming entity
PARTNER  extension 2
CDS entity 2              <- your own source code
CUSTOMER extension 1      <- MDE on the entity BELOW yours
CORE     extension 1
CDS entity 1
```

Your own source code sits in the **middle**. An MDE on the view you select
from loses to your code; an MDE on your own view beats it. So the fix for an
inherited label is either a direct annotation in your own entity or an MDE on
your own entity -- never an attempt to out-rank the layer below with a plain
annotation there.

Layer priority, lowest to highest: `#CORE`, `#LOCALIZATION`, `#INDUSTRY`,
`#PARTNER`, `#CUSTOMER`. The keyword documentation words it as a reading
direction, which is worth remembering because the syntax line lists them in
that order: *"The enumeration symbols are listed with the lowest priority ones
on the left and the highest priority on the right. #CORE therefore has the
lowest, and #CUSTOMER the highest priority."*

Within one layer, there is no determinism to rely on: *"If there are several
metadata extensions in a layer, the annotations of the first metadata extension
to be found are used. The metadata extensions are evaluated according to an
undefined but stable order."* Duplicates are at least flagged --
*"A syntax check warning is issued for annotations specified more than once,
and the system uses the annotation of the first metadata extension found."*

---

## 4. A `CAST` silently deletes the metadata of that field

> *"Calculations and expressions cut off annotation inheritance. If a field is
> used in a calculation, this field does not inherit any element annotations
> from the underlying data source. For example, if a field or a parameter is
> used as an operand in a `CAST` expression, it does not inherit any
> annotations from an underlying data source."*

This is the one that gets found in a demo to the business. Yesterday the column
had a label and a currency reference. Today someone wrapped it to fix a type
mismatch, and the label is gone -- no syntax error, no warning, nothing in the
transport log that mentions metadata.

There is a replacement, but only if the cast target carries annotations of its
own: *"Instead, if the `CAST` target is a DDIC data element or a user-defined
type, the annotations from the cast target are inherited."* Casting to a
data element or a CDS simple type therefore gives you that object's labels.
Casting to a built-in type such as `abap.char(10)` gives you nothing -- that
last part is an inference, since the sentence names only those two kinds of
cast target as sources of inherited annotations. The keyword
documentation's own example does exactly this on purpose:
`cast(char1 as demo_simple_type_inheritance) as Char1Field`.

### The same trap wearing an alias

Renaming is not a calculation, but for `@Semantics` it has the same effect:

> *"If a CDS view entity selecting from a database table uses an alias name for
> a currency key or unit key field, then the annotation cannot be evaluated by
> the API `CL_DD_DDL_ANNOTATION_SERVICE`."*

`@Semantics.amount.currencyCode` and `@Semantics.quantity.unitOfMeasure`
(the evaluation page spells the second one `unitofMeasure` with a lowercase
f-o; check the properties table before copying either) can
only be derived from the DDIC table *"if the name of the referred currency key
or unit key field isn't changed in a CDS view entity."* So renaming `waers` to
`Currency` for a tidier API -- exactly what every naming convention asks for --
drops the derivation, and amounts start rendering without currency formatting.
Specify `@Semantics.amount.currencyCode: 'Currency'` explicitly whenever you
rename the key field.

Related and useful: a field exposed through an association path *"inherits the
element annotations of preceding publications"*, so path expressions do carry
metadata across -- unlike expressions, which cut it.

---

## 5. One array entry overwrites the whole array

This is the `@UI` trap, and it is a single sentence in the propagation
documentation:

> *"Array-like annotations are always evaluated as a coherent, integral group.
> Even if only a single entry of such a group is annotated locally, this local
> definition overwrites all entries of the corresponding annotation of the
> underlying data source."*

So if the view below publishes

```
@UI.lineItem: [ { position: 10, label: 'Carrier' },
                { position: 20, label: 'Connection' },
                { position: 30, label: 'Departure' } ]
```

and your consuming view adds what looks like one extra entry

```
@UI.lineItem: [ { position: 40, label: 'Arrival' } ]
```

the result is a list with **one** column, not four. There is no merge. Repeat
the inherited entries you want to keep, or move the whole array into an MDE on
your own entity.

Internals worth knowing when you read the API output: array elements are stored
as individual annotations named after the array with an index in dollar signs --
`$1$`, `$2$`, ... -- so an inherited three-element array looks like three rows,
and your override looks like one row that replaced all three.

The annotation syntax in a data definition is also laxer than any annotation
definition can be, which is another way to write something no framework will
accept: *"Array elements do not always have to have the same type in the
annotation syntax"*, *"Arrays can be nested directly in the annotation syntax"*,
and *"Directly nested arrays are not saved but they are counted when the
elements are indexed."* In an MDE this is tightened up again: an array must be
written with square brackets and may contain only elements matching its
definition -- *"The format `@annot: value` is not possible. `@annot: [value]`
must be used instead."*

---

## 6. `null` is the delete key, and it propagates

An inherited annotation cannot be unset by omitting it -- omitting it is what
made it inherited. The documented eraser is the literal `null`:

```
@EndUserText.label: null
```

> *"Propagation of annotation values can be stopped via the value `null` [...]
> In this case, the annotation value of the underlying data source is
> overwritten by `null` and this value is also passed to higher-level consumer
> views using the element in question."*

Note the second half: you have not only hidden the label in your view, you have
hidden it in every view that selects from yours. A null is inherited like any
other value, and can itself be overwritten further up.

Rules that matter in practice:

- `null` is only legal as an element annotation value -- *"The value null leads
  to a syntax error at other positions."*
- It is a display filter, not a stored absence: *"An annotation with the value
  null by default is not returned by the methods of the class
  CL_DD_DDL_ANNOTATION_SERVICE. The default setting can be changed with the
  method input parameter NULL_VALUES."*
- Its scope is the exact identifier: `@annotation.annotation1: null`
  *"only affects the identifier `@annotation.annotation1` but does not affect,
  for example, `@annotation.annotation1.annotation2`."*
- On an array it is total: *"If the null value is specified for an annotation
  array, this value affects the entire array."*
- Intended use is narrow: *"Null values are only intended to hide unwanted,
  derived and inherited annotations in the evaluation of the annotations of a
  CDS entity."*

The blunter instrument is the header annotation
`@Metadata.ignorePropagatedAnnotations: true`, which switches inheritance off
for the entire entity. SAP's own demo pair `DEMO_CDS_ANNO_INHERITANCE_1` and
`DEMO_CDS_ANNO_INHERITANCE_1A` differ in exactly that one line, and the second
one loses the `@EndUserText.label` it was inheriting from
`DEMO_CDS_ANNO_INHERITANCE_2`. Use it when you want a clean metadata surface;
do not use it to suppress one unwanted label.

---

## 7. Metadata extensions: what they can and cannot carry

An MDE is a separate repository object (`DDLX` source code, editable only in
ADT) that annotates an existing entity:

```
@Metadata.layer: #CUSTOMER
@EndUserText.label: 'Flight connections'
annotate entity ydj_flight_anno with
{
  @EndUserText.label: 'Airline'
  Carrier;
  @EndUserText.label: 'Flight number'
  Connection;
}
```

`@Metadata.layer` is mandatory and must sit in front of the statement. The
target entity must exist and must itself allow extension. Two further gates
decide whether a given annotation is even eligible:

- the annotation definition must permit it --
  `@MetadataExtension.usageAllowed: true` (the `MDE` column in the properties
  table), and
- it must be irrelevant to activation:

> *"The DDL source code and the activation of a CDS entity are completely
> independent of any metadata extensions for this entity. For this reason, a
> metadata extension can only add annotations that are not already evaluated
> during the activation of the CDS entity."*

That rules out the tempting cleanup of moving the activation-relevant
annotations out of the view -- `@AccessControl.authorizationCheck` and the
`@AbapCatalog` block being the obvious candidates. The rule is the
documentation's; classifying those particular annotations as
activation-relevant is an inference, and the authoritative answer per
annotation is the `MDE` row of its properties table (or
`ABAP_DOCU_MDE_ANNOS`). What belongs in an MDE is UI and
consumption metadata, which is also the part that changes most often. The
payoff is real: *"When activating a CDS view entity, the metadata extensions
are ignored, which results in improved performance"*, and metadata can then be
transported and activated without a mass activation of everything downstream.

The flip side is the part that surprises people debugging a RAP/Fiori app:

> *"The annotations (of a CDS entity) specified in metadata extensions does not
> have any effect on the activation or the behavior at runtime. They are only
> respected by the class `CL_DD_DDL_ANNOTATION_SERVICE`."*

So an annotation in an MDE is invisible to anything that reads the DDL source
instead of the annotation API. The documented example of such a tool is in the
same family of classes:

> *"The method `GET_ANNOTATIONS` of the class `CL_DD_DDL_ANALYZE` also returns
> the annotations of CDS entities. However, it only analyzes the associated DDL
> source code. It ignores annotations from metadata extensions, derived and
> inherited annotations, and the translations of annotations for translatable
> texts."*

If a custom report, a test, or a code-inspector check reads annotations that
way, it will not see half of the active metadata. `CL_DD_DDL_ANNOTATION_SERVICE`
is the one that merges everything; its `GET_DIRECT_ANNOS_*` methods are the
deliberate exception that reads only what is written in the entity itself.

---

## 8. Translatable texts

`@EndUserText.*` values are not plain strings. Annotations marked
`@LanguageDependency` in their definition are stored in language-keyed,
translatable tables. Two consequences:

- The literal you type is the **original language of the CDS source**, not your
  logon language, and is then translated. The API reads the text for a language
  you pass in, defaulting to the text environment language, and
  *"If no text is found for the language, the secondary language in AS ABAP is
  used."*
- `@EndUserText.heading` is a special case worth not fighting:
  *"`@EndUserText.Heading` is only currently possible as an implicit annotation
  for this purpose. If specified directly in the DDL source code of a data
  definition, an annotation is not recognized as a language-dependent text.
  `@EndUserText.Heading` is also not allowed in the DDLX source code of a
  metadata extension."*

`ABAP_DOCU_TRANSLATABLE_ANNOS` lists every annotation that behaves this way.

---

## Checklist

- Never trust activation to validate an annotation name. Check against
  `ABAP_DOCU_CDS_ANNOS_OVERVIEW`, or read the stored metadata back.
- Always write the value of a Boolean annotation. `@Metadata.allowExtensions:
  true`, not `@Metadata.allowExtensions`.
- Omitted is not the documented `Default`. Omitted means the KTD
  not-specified value, which for both `@Metadata` Booleans here is `false`.
- When a label or currency reference disappears, look for a new `CAST`, a new
  expression, or a renamed currency/unit key field before looking anywhere else.
- When overriding an array annotation, restate every entry you want to keep.
- To remove an inherited annotation use `null`, and remember it travels further
  up the stack.
- Put UI metadata in an MDE: stricter syntax check, independent activation,
  layered overrides without modification. Keep activation-relevant annotations
  in the data definition, because an MDE cannot hold them.
- Your own entity source code outranks MDEs below it and loses to MDEs on
  itself. Fix metadata at the layer that actually wins.

Runnable companion: [`ydj_cds_annotation_demo.abap`](ydj_cds_annotation_demo.abap)
-- read-only, reads annotations of the SAP-delivered demo CDS entities with
`CL_DD_DDL_ANNOTATION_SERVICE`; no DDIC object has to be created.

## Verification notes

- Every double-quoted passage above is verbatim from an SAP page listed under
  Sources. Paraphrases are in italics or plain text, never in double quotes.
  53 quoted spans were extracted mechanically from this file (code fences
  excluded) and matched against the saved pages: 51 matched an on-disk copy.
  The remaining 2 come from the `@Metadata.ignorePropagatedAnnotations`
  properties page, which is short enough that it is always returned in full
  and so was never written to disk; those two rest on two independent
  fetches returning identical text instead.
- The `@Metadata.ignorePropagatedAnnotations` and `@Metadata.allowExtensions`
  properties tables (`Default: true`) and their KTD texts (not specified ->
  `false`) are on the same page in each case. The reconciliation offered here
  -- that `Default` applies only to a value-less specification -- is SAP's own,
  from the annotation-properties page.
- The inheritance example in the keyword documentation refers to
  *the second view entity* when the suppressing annotation is in the second
  code listing (`..._1A`). The listings themselves are unambiguous, and this
  note follows the listings.
- No local ABAP or CDS compiler was available: the DDL fragments are
  illustrative and were checked by eye against the syntax pages, and the demo
  report was checked structurally plus read manually.

## Sources

- [ABAP CDS - Annotations](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCDS_ANNOTATIONS.html)
- [CDS DDL - Annotation Syntax](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/cds-ddl-annotation-syntax)
- [CDS DDL - Annotation Syntax, value](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/cds-ddl-annotation-syntax-value)
- [ABAP CDS - Scopes for Annotations](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/abap-cds-scopes-for-annotations)
- [ABAP CDS - Annotation Properties](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/abap-cds-annotation-properties)
- [ABAP CDS - Evaluation of Annotations](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/abap-cds-evaluation-of-annotations)
- [ABAP CDS - Metadata Extensions](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/abap-cds-metadata-extensions)
- [ABAP CDS - Evaluation of Metadata Extensions](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/abap-cds-evaluation-of-metadata-extensions)
- [CDS DDL - ANNOTATE ENTITY, VIEW](https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/cds-ddl-annotate-entity-view)
- [Metadata.allowExtensions (annotation properties + KTD)](https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCDS_1985816297-_ANNO.html)
- [Metadata.ignorePropagatedAnnotations (annotation properties + KTD)](https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENCDS_1433174898-_ANNO.html)
- [Propagation of Annotations (ABAP Data Models guide)](https://help.sap.com/docs/abap-cloud/abap-data-models/propagation-of-annotations)
- [Metadata Extensions (ABAP Data Models guide)](https://help.sap.com/docs/abap-cloud/abap-data-models/metadata-extensions)
- [Annotations (ABAP Data Models guide)](https://help.sap.com/docs/ABAP_Cloud/aaae421481034feab3e71dd9e0f643bf/b22c173af13f426689e977ecff7ccf2b)

Related notes in this repo:
[CDS View Entities | Client Handling](../CDS%20Client%20Handling#readme) |
[CDS Associations](../CDS%20Associations#readme) |
[CDS Access Control](../CDS%20Access%20Control#readme) |
[Currency Amounts](../Currency%20Amounts#readme) |
[Text Elements](../Text%20Elements#readme) |
[ABAP Language Versions](../ABAP%20Language%20Versions#readme)
