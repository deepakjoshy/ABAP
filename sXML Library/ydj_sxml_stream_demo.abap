*&---------------------------------------------------------------------*
*& Report YDJ_SXML_STREAM_DEMO
*&---------------------------------------------------------------------*
*& The sXML Library - streaming XML and JSON through a reader and a
*& writer, and the eight behaviours that make a correct-looking parse
*& loop return the wrong text with no exception and no sy-subrc.
*&
*& The sXML Library builds no document. "Instead, the nodes of the tree
*& structure represented by the XML data are processed serially and only
*& the current node can be accessed." Everything below follows from
*& that one sentence: there is no tree to go back to.
*&
*&   1. STICKY VALUE  -> "the attributes of a reader are only
*&                       overwritten by non-initial content" and VALUE
*&                       "is not initialized if a node has no value",
*&                       so an empty element reports the PREVIOUS
*&                       element's text. This is the quiet one.
*&   2. SINGLE USE    -> "A reader cannot be used more than once for the
*&                       same XML data or for other XML data" and "No
*&                       method exists that can restore the reader to
*&                       its initial state." Not a rewind cost - no
*&                       rewind exists.
*&   3. PUSH_BACK     -> moves back one step but "does not restore the
*&                       reader to the state it had when it reached the
*&                       node using NEXT_NODE". It is not an undo.
*&   4. SKIP_NODE     -> "skips a node, but still has to parse it with
*&                       all subnodes" - no speed win, but it is a
*&                       well-formedness check and a format converter,
*&                       and it is a silent no-op on a value node.
*&   5. DUP ATTRIBUTES-> token-based parsing keeps ALL identically named
*&                       attributes, object-oriented parsing keeps only
*&                       the LAST. Same XML, two answers, no error.
*&   6. XML HEADER    -> CO_OPT_XML_HEADER defaults to CO_OPT_VAL_NO, so
*&                       a writer emits no XML declaration unless asked,
*&                       and for JSON the option is ignored entirely.
*&   7. FORMAT SNIFF  -> a reader "detects the format of the data
*&                       passed" itself. Hand it JSON and it parses, but
*&                       the node names you iterate over are JSON-XML
*&                       names, not your field names.
*&   8. STRICTER      -> "The parser of the sXML Library is a more
*&                       strict validator than the parser of the iXML
*&                       Library" - namespace declarations in a parallel
*&                       element are errors here and were not there.
*&
*& WHAT THIS PROGRAM TOUCHES
*& -------------------------
*& Nothing. The sXML Library is pure in-memory string processing: this
*& report has no SELECT, no CALL FUNCTION, no COMMIT WORK, no file and
*& no RFC. Every payload below is a literal built in the program. It is
*& safe to run in any client.
*&
*& Docs: https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE_ITERATIVE.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_PARSE_OO.html
*&       https://help.sap.com/doc/abapdocu_816_index_htm/8.16/en-US/ABENABAP_SXML_LIB_RENDER.html
*&---------------------------------------------------------------------*
REPORT ydj_sxml_stream_demo.

CLASS lcl_sxml_demo DEFINITION FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS run.

  PRIVATE SECTION.
    " The payload every trap reuses. Note <empty/> directly after
    " <city>Kochi</city>: that pairing is what makes trap 1 visible.
    CLASS-METHODS payload
      RETURNING VALUE(rv_xml) TYPE xstring.

    CLASS-METHODS as_string
      IMPORTING iv_raw           TYPE xstring
      RETURNING VALUE(rv_string) TYPE string.

    " node_type is typed by the framework, not by i - taking it as i
    " would compile and would silently truncate on a release that
    " widens the type.
    CLASS-METHODS node_text
      IMPORTING iv_type        TYPE if_sxml_node=>node_type
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS trap_1_sticky_value.
    CLASS-METHODS trap_2_single_use.
    CLASS-METHODS trap_3_push_back.
    CLASS-METHODS trap_4_skip_node.
    CLASS-METHODS trap_5_duplicate_attributes.
    CLASS-METHODS trap_6_xml_header.
    CLASS-METHODS trap_7_format_sniffing.
    CLASS-METHODS trap_8_strict_parser.

ENDCLASS.


CLASS lcl_sxml_demo IMPLEMENTATION.

  METHOD payload.
    " An sXML reader consumes a BYTE string. The factory method is not
    " overloaded for type string, so the conversion is mandatory and is
    " where the code page of the payload is decided. See the repo's
    " Byte Strings note; cl_abap_codepage=>convert_to( ) is the older
    " static equivalent of the two-step form used here.
    DATA(lv_text) =
      `<order id="4711">`                 &&
      `<customer vip="X" tier="gold">Joshy</customer>` &&
      `<city>Kochi</city>`                &&
      `<empty/>`                          &&
      `<items>`                           &&
      `<item>pen</item>`                  &&
      `<item>book</item>`                 &&
      `</items>`                          &&
      `</order>`.

    rv_xml = cl_abap_conv_codepage=>create_out( )->convert( lv_text ).
  ENDMETHOD.

  METHOD as_string.
    rv_string = cl_abap_conv_codepage=>create_in( )->convert( iv_raw ).
  ENDMETHOD.

  METHOD node_text.
    " CO_NT_FINAL and friends are constants of IF_SXML_NODE. The parsing
    " overview page says they are constants "of the interface
    " IF_SXML_READER"; every code example on the same page and all of
    " SAP's own demo classes qualify them with IF_SXML_NODE, which is
    " what compiles.
    CASE iv_type.
      WHEN if_sxml_node=>co_nt_initial.
        rv_text = `CO_NT_INITIAL`.
      WHEN if_sxml_node=>co_nt_element_open.
        rv_text = `CO_NT_ELEMENT_OPEN`.
      WHEN if_sxml_node=>co_nt_element_close.
        rv_text = `CO_NT_ELEMENT_CLOSE`.
      WHEN if_sxml_node=>co_nt_value.
        rv_text = `CO_NT_VALUE`.
      WHEN if_sxml_node=>co_nt_attribute.
        rv_text = `CO_NT_ATTRIBUTE`.
      WHEN if_sxml_node=>co_nt_final.
        rv_text = `CO_NT_FINAL`.
      WHEN OTHERS.
        rv_text = `(other)`.
    ENDCASE.
  ENDMETHOD.

  METHOD trap_1_sticky_value.
    " ------------------------------------------------------------------
    " TRAP 1 - the reader's attributes are not cleared between nodes.
    "
    " Doc, verbatim: "When parsing, the attributes of a reader are only
    " overwritten by non-initial content. If the parser is set to a
    " literal element without a name, for example, the preceding content
    " of the attribute NAME is kept. This applies particularly to the
    " attribute VALUE, which is not initialized if a node has no value."
    "
    " So the obvious loop - next_node, then read name and value - is
    " wrong for every node that has no value of its own. <empty/> below
    " reports Kochi, because <city> was the last node that had a value.
    " Nothing raises, nothing sets sy-subrc, and the result is PLAUSIBLE
    " data, which is why this survives code review.
    " ------------------------------------------------------------------
    WRITE: / `TRAP 1 - VALUE survives into the next node`.
    WRITE: / `node type           name       reader->value`.
    ULINE.

    DATA(lo_reader) = cl_sxml_string_reader=>create( payload( ) ).

    TRY.
        DO.
          lo_reader->next_node( ).

          IF lo_reader->node_type = if_sxml_node=>co_nt_final.
            EXIT.
          ENDIF.

          " Hoisted, because this repo's List Processing note documents
          " that a functional method call is not allowed in a WRITE list.
          " Fixed-length char fields, NOT lv_type(20): offset/length
          " on a data object of type string demands that many
          " characters and raises CX_SY_RANGE_OUT_OF_BOUNDS when the
          " value is shorter. Assigning a string to a c field pads and
          " truncates instead, which is what a column wants.
          DATA lv_type TYPE c LENGTH 20.
          DATA lv_name TYPE c LENGTH 10.

          lv_type = node_text( lo_reader->node_type ).
          lv_name = lo_reader->name.
          DATA(lv_value) = lo_reader->value.

          WRITE: / lv_type, lv_name, lv_value.
        ENDDO.

      CATCH cx_sxml_parse_error INTO DATA(lo_parse_err).
        DATA(lv_err) = lo_parse_err->get_text( ).
        WRITE: / `parse error:`, lv_err.
    ENDTRY.

    WRITE: / `The <empty> element opening reports Kochi. It has no value`.
    WRITE: / `of its own, so VALUE was left alone. The fix is to read`.
    WRITE: / `VALUE only when node_type = CO_NT_VALUE, never after an`.
    WRITE: / `element opening.`.
    SKIP.
  ENDMETHOD.

  METHOD trap_2_single_use.
    " ------------------------------------------------------------------
    " TRAP 2 - a reader is a one-way cursor, and its POSITION is part of
    " the contract it has with CALL TRANSFORMATION.
    "
    " Doc, verbatim: "A reader cannot be used more than once for the
    " same XML data or for other XML data." / "No method exists that can
    " restore the reader to its initial state. A new reader can be
    " created instead." / "a reader located at the end of the parsed XML
    " data can no longer be used as an XML source of the statement CALL
    " TRANSFORMATION".
    "
    " CALL TRANSFORMATION's own page states the hand-over rule: "The
    " transformation moves the reader by one node and processes the
    " entire matching subtree. If the transformation is successful, the
    " reader is located at the end of the processed data."
    "
    " Two designs die here:
    "   - "parse it once to see which schema this is, then CALL
    "     TRANSFORMATION id on the same reader" works ONLY if you stop
    "     exactly on the element opening you want handed over.
    "   - "CALL TRANSFORMATION first, then walk the rest" cannot work,
    "     because a successful transformation leaves the reader at the
    "     end of what it consumed.
    " There is no reset, so a CATCH-and-retry around a transformation
    " cannot retry anything.
    " ------------------------------------------------------------------
    WRITE: / `TRAP 2 - partial consumption, then hand-over`.
    ULINE.

    DATA(lo_reader) = cl_sxml_string_reader=>create( payload( ) ).

    " Walk to the <items> opening and stop THERE. This is the only
    " position from which the subtree below <items> can be handed to a
    " transformation. SAP's own example (CL_DEMO_SXML_TRAFO_FROM_READER)
    " uses exactly this shape - and note that its loop condition reads
    " the sticky NAME attribute from trap 1, with no CO_NT_FINAL guard,
    " so a payload that never contains the element it wants would not
    " stop on its own. The guard below is deliberate.
    DATA lv_found TYPE abap_bool VALUE abap_false.

    TRY.
        DO.
          lo_reader->next_node( ).

          IF lo_reader->node_type = if_sxml_node=>co_nt_final.
            EXIT.
          ENDIF.

          IF lo_reader->node_type = if_sxml_node=>co_nt_element_open
             AND lo_reader->name = 'items'.
            lv_found = abap_true.
            EXIT.
          ENDIF.
        ENDDO.

      CATCH cx_sxml_parse_error INTO DATA(lo_parse_err).
        DATA(lv_err) = lo_parse_err->get_text( ).
        WRITE: / `parse error:`, lv_err.
    ENDTRY.

    IF lv_found = abap_false.
      WRITE: / `<items> not found - nothing to hand over.`.
      SKIP.
      RETURN.
    ENDIF.

    WRITE: / `Reader is parked on the <items> element opening.`.
    WRITE: / `A CALL TRANSFORMATION id SOURCE XML lo_reader here would`.
    WRITE: / `consume that subtree and leave the reader at its end. It`.
    WRITE: / `is not executed: the subtree is plain XML, not asXML, so`.
    WRITE: / `the identity transformation has no matching ABAP target`.
    WRITE: / `and would raise CX_TRANSFORMATION_ERROR. Only a payload`.
    WRITE: / `already in asXML or asJSON format deserializes with id.`.
    SKIP.
  ENDMETHOD.

  METHOD trap_3_push_back.
    " ------------------------------------------------------------------
    " TRAP 3 - PUSH_BACK is a branch, not an undo.
    "
    " Doc, verbatim: "The method PUSH_BACK makes it possible to move
    " back a step but does not restore the reader to the state it had
    " when it reached the node using NEXT_NODE. After a PUSH_BACK, the
    " parsed node does not always produce the same result as the last
    " time. In particular, subnodes already parsed could be skipped."
    "
    " And: "Token-based parsing is designed mainly for forward iteration
    " through the XML data. Free navigation, as possible in iXML Library
    " in DOM, is not recommended here."
    "
    " PUSH_BACK is documented as resetting "the parser to the node for
    " the element opening of the direct parent node". Applied from a
    " value node it lands on that value's own element opening, and a
    " second call goes up to the superelement - which is SAP's own
    " description of the steps in CL_DEMO_SXML_TOKEN_RDR_STEPS. What it
    " does NOT give you is a reader that behaves as if the forward walk
    " had not happened.
    " ------------------------------------------------------------------
    WRITE: / `TRAP 3 - PUSH_BACK twice from a value node`.
    ULINE.

    DATA(lo_reader) = cl_sxml_string_reader=>create( payload( ) ).

    TRY.
        " Walk forward to the first value node.
        DO.
          lo_reader->next_node( ).

          IF lo_reader->node_type = if_sxml_node=>co_nt_final
             OR lo_reader->node_type = if_sxml_node=>co_nt_value.
            EXIT.
          ENDIF.
        ENDDO.

        DATA lv_at TYPE c LENGTH 20.
        DATA lv_nm TYPE c LENGTH 20.

        lv_at = node_text( lo_reader->node_type ).
        lv_nm = lo_reader->name.
        WRITE: / `after forward walk  :`, lv_at, lv_nm.

        lo_reader->push_back( ).
        lv_at = node_text( lo_reader->node_type ).
        lv_nm = lo_reader->name.
        WRITE: / `after push_back #1  :`, lv_at, lv_nm.

        lo_reader->push_back( ).
        lv_at = node_text( lo_reader->node_type ).
        lv_nm = lo_reader->name.
        WRITE: / `after push_back #2  :`, lv_at, lv_nm.

      CATCH cx_sxml_error INTO DATA(lo_err).
        " CX_SXML_STATE_ERROR is the one to expect if a navigation
        " method is called from a position that does not allow it.
        DATA(lv_text) = lo_err->get_text( ).
        WRITE: / `sXML error:`, lv_text.
    ENDTRY.

    WRITE: / `Note the NAME column: trap 1 applies to these reads too.`.
    SKIP.
  ENDMETHOD.

  METHOD trap_4_skip_node.
    " ------------------------------------------------------------------
    " TRAP 4 - SKIP_NODE buys no speed, but it is a format converter.
    "
    " Doc, verbatim: "This is particularly clear in the parser method
    " SKIP_NODE, which skips a node, but still has to parse it with all
    " subnodes. This characteristic can be exploited to check whether
    " data is well-formed and to test the copying of XML data to a
    " writer."
    "
    " So SKIP_NODE is not an optimisation - the subtree is parsed either
    " way. What it IS: pass a writer and the subtree is copied, and
    " "the format of the copied tree or subtree can be transformed into
    " a different format". That is an XML-to-JSON converter in four
    " statements, with no transformation and no ABAP data type involved.
    "
    " Two sharp edges:
    "   - "This method has no effect for value nodes or closed
    "     elements." A silent no-op, not an exception - so a loop that
    "     calls skip_node on the wrong node type simply does not skip,
    "     and the reader keeps walking into the subtree you meant to
    "     drop.
    "   - the copy is LOSSY by construction: "The writers in the sXML
    "     Library do not currently support XML comments, CDATA sections,
    "     or processor instructions." Using a copy to prove a document
    "     is well-formed therefore proves it about a document that has
    "     quietly had its comments and CDATA removed.
    " ------------------------------------------------------------------
    WRITE: / `TRAP 4 - skip the <items> subtree INTO a JSON writer`.
    ULINE.

    DATA(lo_reader) = cl_sxml_string_reader=>create( payload( ) ).

    " The writer is created through the interface, because open_element
    " and close_element are IF_SXML_WRITER methods, and read back
    " through the class, because get_output is class-specific. That
    " asymmetry is trap 6's subject.
    DATA(lo_writer) = CAST if_sxml_writer(
      cl_sxml_string_writer=>create( type = if_sxml=>co_xt_json ) ).

    TRY.
        DO.
          lo_reader->next_node( ).

          IF lo_reader->node_type = if_sxml_node=>co_nt_final.
            EXIT.
          ENDIF.

          IF lo_reader->node_type = if_sxml_node=>co_nt_element_open
             AND lo_reader->name = 'items'.
            " Copies this element opening, every subnode and the
            " matching close into the writer, in JSON this time.
            lo_reader->skip_node( lo_writer ).
            EXIT.
          ENDIF.
        ENDDO.

        DATA(lv_raw)  = CAST cl_sxml_string_writer( lo_writer )->get_output( ).
        DATA(lv_json) = as_string( lv_raw ).
        WRITE: / `JSON produced from the XML subtree:`.
        WRITE: / lv_json.

      CATCH cx_sxml_error INTO DATA(lo_err).
        DATA(lv_text) = lo_err->get_text( ).
        WRITE: / `sXML error:`, lv_text.
    ENDTRY.

    WRITE: / `No CALL TRANSFORMATION, no ABAP structure, no asJSON -`.
    WRITE: / `just a reader piped into a writer of a different format.`.
    SKIP.
  ENDMETHOD.

  METHOD trap_5_duplicate_attributes.
    " ------------------------------------------------------------------
    " TRAP 5 - the two parsing APIs disagree about attributes.
    "
    " Token-based, verbatim: "If an XML element has multiple
    " identically named attributes, all of these attributes are
    " respected in the order in which they appear".
    "
    " Object-oriented, verbatim: "If an XML element has multiple
    " identically named attributes, only one of these attributes is used
    " in object-oriented parsing (unlike in token-based parsing). This
    " attribute has the value of the last identically named attribute".
    "
    " Both sentences are from SAP, and they are the same XML giving two
    " different answers depending on which of the two documented APIs
    " you reached for. Neither reports anything.
    "
    " The two APIs also END differently, which is the part that bites on
    " a refactor from one to the other:
    "   token-based : stop when NODE_TYPE = IF_SXML_NODE=>CO_NT_FINAL
    "   object-based: stop when the returned REFERENCE IS INITIAL
    "                 ("The return value is initial at the end of the
    "                  XML data.")
    " A loop converted from NEXT_NODE to READ_NEXT_NODE that keeps
    " testing CO_NT_FINAL is no longer testing its own exit condition.
    " Whether that spins or dumps depends on what the initial reference
    " meets next; either way the loop is not the loop you reviewed.
    "
    " Honest limit of this demo: a duplicate-attribute payload is not
    " well-formed XML, and the sXML parser is documented as the stricter
    " of the two libraries, so whether a given release lets it through
    " is not something this program asserts. It attempts it and prints
    " the actual outcome. The ATTRIBUTE ITERATION below runs on the
    " well-formed payload and is the part you can rely on.
    " ------------------------------------------------------------------
    WRITE: / `TRAP 5 - attributes, token-based then object-oriented`.
    ULINE.

    " --- token-based: NEXT_ATTRIBUTE walks the list of the element the
    " --- parser is currently parked on.
    DATA(lo_reader) = cl_sxml_string_reader=>create( payload( ) ).
    DATA lv_parked TYPE abap_bool VALUE abap_false.

    TRY.
        DO.
          lo_reader->next_node( ).

          IF lo_reader->node_type = if_sxml_node=>co_nt_final.
            EXIT.
          ENDIF.

          IF lo_reader->node_type = if_sxml_node=>co_nt_element_open
             AND lo_reader->name = 'customer'.
            lv_parked = abap_true.
            EXIT.
          ENDIF.
        ENDDO.

        " Only iterate an attribute list if the parser is actually
        " parked on an element opening. Falling into next_attribute( )
        " from CO_NT_FINAL asks the reader for something its read
        " position does not offer, which is CX_SXML_STATE_ERROR
        " territory rather than an empty list.
        WHILE lv_parked = abap_true.
          lo_reader->next_attribute( ).

          IF lo_reader->node_type <> if_sxml_node=>co_nt_attribute.
            EXIT.
          ENDIF.

          DATA lv_an TYPE c LENGTH 10.
          lv_an = lo_reader->name.
          DATA(lv_av) = lo_reader->value.
          WRITE: / `  token-based attribute:`, lv_an, lv_av.
        ENDWHILE.

      CATCH cx_sxml_error INTO DATA(lo_err1).
        DATA(lv_t1) = lo_err1->get_text( ).
        WRITE: / `sXML error (token):`, lv_t1.
    ENDTRY.

    " --- object-oriented: READ_NEXT_NODE returns node objects, and the
    " --- element-opening object carries GET_ATTRIBUTES.
    DATA(lo_reader2) = cl_sxml_string_reader=>create( payload( ) ).

    TRY.
        DO.
          DATA(lo_node) = lo_reader2->read_next_node( ).

          IF lo_node IS INITIAL.
            EXIT.
          ENDIF.

          IF lo_node->type = if_sxml_node=>co_nt_element_open.
            DATA(lo_open) = CAST if_sxml_open_element( lo_node ).
            DATA(lv_en)   = lo_open->qname-name.

            IF lv_en = 'customer'.
              DATA(lt_attr) = lo_open->get_attributes( ).

              LOOP AT lt_attr INTO DATA(lo_attr).
                DATA lv_on TYPE c LENGTH 10.
                lv_on = lo_attr->qname-name.
                DATA lv_ov TYPE string.
                CLEAR lv_ov.

                " VALUE_TYPE decides which accessor is the right one.
                " The constants are CO_VT_TEXT and CO_VT_RAW - note
                " that the token-based parsing page lists CO_VT_TEXT
                " TWICE in its attribute table, once for text in VALUE
                " and once for "Raw data in the attribute VALUE_RAW".
                " The second entry is a copy-paste defect: SAP's own
                " example CL_DEMO_SXML_OO_READER tests against
                " if_sxml_value=>co_vt_raw there, which is the
                " constant that exists.
                IF lo_attr->value_type = if_sxml_value=>co_vt_text.
                  lv_ov = lo_attr->get_value( ).
                ELSEIF lo_attr->value_type = if_sxml_value=>co_vt_raw.
                  lv_ov = `(raw - use get_value_raw)`.
                ENDIF.

                " The element/attribute OBJECT exposes the namespace as
                " qname-namespace; the READER exposes the same thing as
                " the attribute NSURI. Different names, same concept.
                WRITE: / `  OO attribute        :`, lv_on, lv_ov.
              ENDLOOP.

              EXIT.
            ENDIF.
          ENDIF.
        ENDDO.

      CATCH cx_sxml_error INTO DATA(lo_err2).
        DATA(lv_t2) = lo_err2->get_text( ).
        WRITE: / `sXML error (OO):`, lv_t2.
    ENDTRY.

    " --- and now the case the two quotes are actually ABOUT. A
    " --- duplicate attribute name is not well-formed XML, so this
    " --- block asserts nothing: it counts what the token-based API
    " --- returns and prints that number, whatever it is.
    DATA(lv_dup) =
      `<root>`                            &&
      `<customer vip="X" vip="Y"/>`       &&
      `</root>`.

    DATA(lo_reader3) = cl_sxml_string_reader=>create(
      cl_abap_conv_codepage=>create_out( )->convert( lv_dup ) ).

    DATA lv_count TYPE i VALUE 0.
    DATA lv_last  TYPE string.
    CLEAR lv_last.

    TRY.
        DO.
          lo_reader3->next_node( ).

          IF lo_reader3->node_type = if_sxml_node=>co_nt_final.
            EXIT.
          ENDIF.

          IF lo_reader3->node_type = if_sxml_node=>co_nt_element_open
             AND lo_reader3->name = 'customer'.

            DO.
              lo_reader3->next_attribute( ).

              IF lo_reader3->node_type <> if_sxml_node=>co_nt_attribute.
                EXIT.
              ENDIF.

              lv_count = lv_count + 1.
              lv_last  = lo_reader3->value.
            ENDDO.

            EXIT.
          ENDIF.
        ENDDO.

        WRITE: / `  duplicate-name attributes counted:`, lv_count.
        WRITE: / `  last value seen                  :`, lv_last.
        WRITE: / `  2 means all duplicates were kept (token-based rule);`.
        WRITE: / `  1 means this reader collapsed them.`.

      CATCH cx_sxml_error INTO DATA(lo_err3).
        DATA(lv_t3) = lo_err3->get_text( ).
        WRITE: / `  duplicate name REJECTED by the parser:`, lv_t3.
        WRITE: / `  which is section 11's strictness, not section 6.`.
    ENDTRY.

    WRITE: / `Same element, same payload, two APIs. With duplicate`.
    WRITE: / `attribute names the two lists differ in LENGTH - that is`.
    WRITE: / `what the count above measures on THIS release.`.
    SKIP.
  ENDMETHOD.

  METHOD trap_6_xml_header.
    " ------------------------------------------------------------------
    " TRAP 6 - the XML declaration is OFF by default, and the reader and
    " writer are not symmetric about which reference type you hold.
    "
    " Doc, verbatim: the XML declaration is set through the option
    " CO_OPT_XML_HEADER with CO_OPT_VAL_NO, CO_OPT_VAL_WITHOUT_ENCODING
    " or CO_OPT_VAL_FULL, and "The default option is CO_OPT_VAL_NO."
    " Two consequences:
    "   - a writer used standalone emits XML with NO <?xml ... ?> line
    "     unless you ask for one, which some consumers reject.
    "   - "Using the option xml_header for CALL TRANSFORMATION overrides
    "     the option in IF_SXML_WRITER if it is initial", so the same
    "     writer produces different output depending on whether YOU
    "     wrote the nodes or a transformation did.
    "   - "For JSON and Binary XML, the setting of the option is
    "     ignored" - so this whole trap silently does not apply to the
    "     JSON writer in trap 4.
    "
    " The reference-type asymmetry, verbatim:
    "   reader: "The static type of the reference variables is then the
    "            interface IF_SXML_READER"
    "   writer: "Here, the static type of the reference variables is the
    "            type of the class itself, since more class-specific
    "            methods exist than in readers."
    " and for reading the result back: "Since the method is a
    " class-specific method, a downcast is required if an interface
    " reference variable is used." That is why writer code is full of
    " CAST in both directions - see also this repo's JSON Serialization
    " note, which hits the same cast from the formatting side.
    " ------------------------------------------------------------------
    WRITE: / `TRAP 6 - no XML declaration unless you ask`.
    ULINE.

    TRY.
        " (a) default writer - no header
        DATA(lo_plain) = CAST if_sxml_writer(
          cl_sxml_string_writer=>create( ) ).

        lo_plain->open_element( name = 'doc' ).
        lo_plain->write_value( 'hello' ).
        lo_plain->close_element( ).

        DATA(lv_raw_a) = CAST cl_sxml_string_writer( lo_plain )->get_output( ).
        DATA(lv_a)     = as_string( lv_raw_a ).
        WRITE: / `default              :`, lv_a.

        " (b) same writer class, header requested BEFORE the first node
        DATA(lo_hdr) = CAST if_sxml_writer(
          cl_sxml_string_writer=>create( ) ).

        lo_hdr->set_option( option = if_sxml_writer=>co_opt_xml_header
                            value  = if_sxml_writer=>co_opt_val_full ).

        lo_hdr->open_element( name = 'doc' ).
        lo_hdr->write_value( 'hello' ).
        lo_hdr->close_element( ).

        DATA(lv_raw_b) = CAST cl_sxml_string_writer( lo_hdr )->get_output( ).
        DATA(lv_b)     = as_string( lv_raw_b ).
        WRITE: / `co_opt_val_full      :`, lv_b.

      CATCH cx_sxml_error INTO DATA(lo_err).
        DATA(lv_text) = lo_err->get_text( ).
        WRITE: / `sXML error:`, lv_text.
    ENDTRY.

    WRITE: / `A writer is also single-use: "A writer cannot be used more`.
    WRITE: / `than once for the same XML data or for other data."`.
    SKIP.
  ENDMETHOD.

  METHOD trap_7_format_sniffing.
    " ------------------------------------------------------------------
    " TRAP 7 - the reader sniffs the format, so JSON parses silently -
    " but under JSON-XML element names, not yours.
    "
    " Doc, verbatim: when a reader is created "it itself detects the
    " format of the data passed to the parameter INPUT of the factory
    " method CREATE". And for JSON specifically: "an XML reader detects
    " JSON data and parses it as if it were JSON-XML data."
    "
    " The consequence is the opposite of what the convenience suggests.
    " A parse loop written against XML element names keeps running when
    " somebody switches the interface to JSON - it just stops matching,
    " because the node names it now sees are the JSON-XML structural
    " names, with YOUR field names arriving as the name ATTRIBUTE of
    " those nodes. Same loop, no exception, zero hits.
    "
    " One reader class does NOT take part in the sniffing: "Only the
    " special class CL_SXML_XOP_READER can be used for the XOP format",
    " and its CREATE "expects an actual parameter of the type
    " IF_SXML_XOP=>XOP_PACKAGE" rather than a byte string.
    " ------------------------------------------------------------------
    WRITE: / `TRAP 7 - the same reader class, fed JSON`.
    ULINE.

    DATA(lv_json) = `{"id":4711,"city":"Kochi"}`.
    DATA(lo_reader) = cl_sxml_string_reader=>create(
      cl_abap_conv_codepage=>create_out( )->convert( lv_json ) ).

    TRY.
        DO.
          lo_reader->next_node( ).

          IF lo_reader->node_type = if_sxml_node=>co_nt_final.
            EXIT.
          ENDIF.

          IF lo_reader->node_type <> if_sxml_node=>co_nt_element_open.
            CONTINUE.
          ENDIF.

          DATA lv_nm TYPE c LENGTH 10.
          lv_nm = lo_reader->name.
          DATA lv_attr TYPE string.
          CLEAR lv_attr.

          " GET_ATTRIBUTE_VALUE "Sets the attribute VALUE of the reader
          " to the value of a specific attribute". The JSON-XML mapping
          " carries the original key in an attribute called name.
          TRY.
              lo_reader->get_attribute_value( 'name' ).
              lv_attr = lo_reader->value.
            CATCH cx_sxml_error.
              lv_attr = `(none)`.
          ENDTRY.

          WRITE: / `  element:`, lv_nm, `name attribute:`, lv_attr.
        ENDDO.

      CATCH cx_sxml_parse_error INTO DATA(lo_parse_err).
        DATA(lv_err) = lo_parse_err->get_text( ).
        WRITE: / `parse error:`, lv_err.
    ENDTRY.

    WRITE: / `No element is called id or city. A loop testing`.
    WRITE: / `reader->name = 'city' finds nothing and reports success.`.
    SKIP.
  ENDMETHOD.

  METHOD trap_8_strict_parser.
    " ------------------------------------------------------------------
    " TRAP 8 - sXML rejects XML that the iXML Library accepted, and the
    " exceptions that say so are CX_DYNAMIC_CHECK.
    "
    " Doc, verbatim: "The parser of the sXML Library is a more strict
    " validator than the parser of the iXML Library. A namespace prefix
    " must be declared in the same element or in a superelement.
    " Preceding declarations in a parallel element are interpreted as
    " errors."
    "
    " So "we moved from iXML to sXML for the performance" is a payload
    " compatibility decision, not just a refactor. The character set
    " changes too: "The iXML Library supports UCS-2 and the sXML Library
    " supports UTF."
    "
    " The exception hierarchy is the second half of this trap. Verbatim:
    " "The exceptions of category CX_DYNAMIC_CHECK are propagated to the
    " caller and must be handled by the user." CX_SXML_ERROR and its
    " siblings CX_SXML_PARSE_ERROR, CX_SXML_STATE_ERROR,
    " CX_SXML_NAME_ERROR and CX_SXML_ILLEGAL_ARGUMENT_ERROR all sit
    " under CX_DYNAMIC_CHECK, which means a parse loop with no TRY
    " ACTIVATES CLEANLY and dumps on the first malformed payload - the
    " same shape as the AMDP exception trap in this repo.
    " CX_SXML_INTERNAL_ERROR is the exception: it is CX_NO_CHECK and
    " "cannot usually be handled properly in an application program".
    " ------------------------------------------------------------------
    WRITE: / `TRAP 8 - a prefix declared in a PARALLEL element`.
    ULINE.

    " ns:b uses a prefix declared on <a>, which is a sibling of <b>,
    " not an ancestor of it. That is the documented error case.
    DATA(lv_bad) =
      `<root>`                                        &&
      `<a xmlns:ns="urn:example">1</a>`               &&
      `<ns:b>2</ns:b>`                                &&
      `</root>`.

    DATA(lo_reader) = cl_sxml_string_reader=>create(
      cl_abap_conv_codepage=>create_out( )->convert( lv_bad ) ).

    DATA lv_nodes TYPE i VALUE 0.

    TRY.
        DO.
          lo_reader->next_node( ).

          IF lo_reader->node_type = if_sxml_node=>co_nt_final.
            EXIT.
          ENDIF.

          lv_nodes = lv_nodes + 1.
        ENDDO.

        WRITE: / `parsed without error, nodes:`, lv_nodes.
        WRITE: / `(this release accepted the parallel declaration)`.

      CATCH cx_sxml_parse_error INTO DATA(lo_parse_err).
        DATA(lv_err) = lo_parse_err->get_text( ).
        WRITE: / `CX_SXML_PARSE_ERROR after`, lv_nodes, `nodes:`.
        WRITE: / lv_err.
        WRITE: / `Note the reader had already produced nodes before it`.
        WRITE: / `failed. A streaming parser fails PART WAY THROUGH, so`.
        WRITE: / `anything you already wrote to a target is half-done.`.
    ENDTRY.

    SKIP.
  ENDMETHOD.

  METHOD run.
    WRITE: / `YDJ_SXML_STREAM_DEMO - sXML Library traps`.
    WRITE: / `Read-only. No database, no RFC, no file, no COMMIT WORK.`.
    SKIP.

    trap_1_sticky_value( ).
    trap_2_single_use( ).
    trap_3_push_back( ).
    trap_4_skip_node( ).
    trap_5_duplicate_attributes( ).
    trap_6_xml_header( ).
    trap_7_format_sniffing( ).
    trap_8_strict_parser( ).

    WRITE: / `Done.`.
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  lcl_sxml_demo=>run( ).
