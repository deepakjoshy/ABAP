*&---------------------------------------------------------------------*
*& Report  ydj_exception_text_demo
*&---------------------------------------------------------------------*
*& Where the string returned by get_text( ) actually comes from, and the
*& four places it silently becomes something else.
*&
*& Six sections:
*&   1  RAISE ... MESSAGE stores a message - it does not send one
*&   2  T100KEY-ATTRn holds an attribute NAME, so a typo prints &NAME&
*&   3  a message that is not in T100 produces a generated text, not an error
*&   4  the MESSAGE addition runs AFTER the constructor and overwrites it
*&   5  MESSAGE oref - the implicit type, and why INTO/WITH are forbidden
*&   6  wrapping with PREVIOUS, and walking the chain for the real text
*&
*& READ-ONLY: no SELECT, no database write, no COMMIT, no file access.
*& Everything here is exception objects and text resolution.
*&
*& Two local exception classes are defined the way the ABAP Keyword
*& Documentation defines them for local classes: IF_T100_MESSAGE needs an
*& instance constructor that fills T100KEY by hand, IF_T100_DYN_MSG needs
*& neither that nor placeholder attributes.
*&
*& Uses the SAP-delivered message SABAPDEMOS 888, whose short text is four
*& placeholders separated by blanks - the same message the keyword
*& documentation itself uses for the MESSAGE addition.
*&
*& Functional calls are hoisted into variables before every WRITE, per the
*& repo's Regular Expressions and String Processing notes.
*&
*& Refs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENIF_T100_MESSAGE.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABAPRAISE_EXCEPTION_MESSAGE.html
*&---------------------------------------------------------------------*
REPORT ydj_exception_text_demo.

*&---------------------------------------------------------------------*
*& IF_T100_MESSAGE: the interface for STATIC exception texts.
*& T100KEY-ATTR1..ATTR4 hold the NAMES of attributes of this class. The
*& text1/text2 attributes below are what those names point at - that is
*& the "double indirection" the documentation warns about.
*&---------------------------------------------------------------------*
CLASS lcx_t100 DEFINITION INHERITING FROM cx_dynamic_check.

  PUBLIC SECTION.

    INTERFACES if_t100_message.

    METHODS constructor
      IMPORTING
        iv_msgid TYPE symsgid
        iv_msgno TYPE symsgno
        iv_attr2 TYPE csequence DEFAULT 'TEXT2'
        iv_text1 TYPE csequence OPTIONAL
        iv_text2 TYPE csequence OPTIONAL.

    " The placeholder carriers. With IF_T100_MESSAGE you declare these
    " yourself; with IF_T100_DYN_MSG you get MSGV1..MSGV4 for free.
    DATA text1 TYPE c LENGTH 50.
    DATA text2 TYPE c LENGTH 50.

ENDCLASS.

CLASS lcx_t100 IMPLEMENTATION.

  METHOD constructor.

    super->constructor( ).

    text1 = iv_text1.
    text2 = iv_text2.

    " In a LOCAL exception class the filling of T100KEY must be programmed
    " explicitly - for a GLOBAL class the Class Builder / ADT generates it.
    if_t100_message~t100key-msgid = iv_msgid.
    if_t100_message~t100key-msgno = iv_msgno.
    if_t100_message~t100key-attr1 = 'TEXT1'.

    " iv_attr2 is parameterised ONLY so section 2 can pass a wrong name.
    " Real code would hard-code 'TEXT2' here.
    if_t100_message~t100key-attr2 = iv_attr2.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& IF_T100_DYN_MSG: adds MSGTY and MSGV1..MSGV4 to IF_T100_MESSAGE.
*& No constructor, no placeholder attributes, no T100KEY assignments -
*& the MESSAGE addition of RAISE EXCEPTION fills all of it.
*&---------------------------------------------------------------------*
CLASS lcx_dyn DEFINITION INHERITING FROM cx_dynamic_check.

  PUBLIC SECTION.

    INTERFACES if_t100_dyn_msg.

    ALIASES msgty FOR if_t100_dyn_msg~msgty.

ENDCLASS.

CLASS lcx_dyn IMPLEMENTATION.
ENDCLASS.

*&---------------------------------------------------------------------*
*& Same interface, but with a constructor that presets the message type.
*& Section 4 raises this class twice to show that the preset survives a
*& plain RAISE and is discarded when MESSAGE is specified.
*&---------------------------------------------------------------------*
CLASS lcx_dyn_preset DEFINITION INHERITING FROM cx_dynamic_check.

  PUBLIC SECTION.

    INTERFACES if_t100_dyn_msg.

    ALIASES msgty FOR if_t100_dyn_msg~msgty.

    METHODS constructor.

ENDCLASS.

CLASS lcx_dyn_preset IMPLEMENTATION.

  METHOD constructor.

    super->constructor( ).

    " A deliberate, sensible default chosen by the class author.
    if_t100_message~t100key-msgid = 'SABAPDEMOS'.
    if_t100_message~t100key-msgno = '888'.
    if_t100_dyn_msg~msgty         = 'I'.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& No message interface at all. Used in section 6 as the wrapper whose
*& own text is not message-based - which is exactly why the PREVIOUS
*& chain has to be walked to find the text that matters.
*& The inherited CX_ROOT constructor already offers TEXTID and PREVIOUS.
*&---------------------------------------------------------------------*
CLASS lcx_plain DEFINITION INHERITING FROM cx_dynamic_check.
ENDCLASS.

CLASS lcx_plain IMPLEMENTATION.
ENDCLASS.


CLASS lcl_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS:
      message_sends_nothing,
      attr_name_not_value,
      missing_message_is_silent,
      message_overwrites_ctor,
      oref_type_and_restrictions,
      previous_chain.

ENDCLASS.


CLASS lcl_demo IMPLEMENTATION.

  METHOD message_sends_nothing.

    WRITE: / '1) RAISE ... MESSAGE stores a message, it does not send one'.

    TRY.
        " The addition "passes the specification of a message to the
        " exception object". Nothing is displayed, no system behaviour of
        " the MESSAGE STATEMENT applies, and sy-subrc is untouched.
        RAISE EXCEPTION TYPE lcx_dyn MESSAGE s888(sabapdemos)
              WITH 'nothing' 'was' 'sent' 'here'.

      CATCH lcx_dyn INTO DATA(lo_err).

        DATA(lv_text) = lo_err->get_text( ).

        WRITE: / '   text stored on the object   :', lv_text.
        WRITE: / '   msgty stored on the object  :', lo_err->msgty.
        WRITE: / '   sy-subrc                    :', sy-subrc,
                 '<- nothing to do with MESSAGE'.

    ENDTRY.

    WRITE: / '   report still running        : yes - no screen, no status line'.
    SKIP.

  ENDMETHOD.


  METHOD attr_name_not_value.

    WRITE: / '2) T100KEY-ATTRn holds an attribute NAME, not a value'.

    " Spelled correctly: ATTR2 names the attribute TEXT2, which exists,
    " so the placeholder is replaced by the content of TEXT2.
    DATA(lo_ok) = NEW lcx_t100( iv_msgid = 'SABAPDEMOS'
                                iv_msgno = '888'
                                iv_attr2 = 'TEXT2'
                                iv_text1 = 'value-of-TEXT1'
                                iv_text2 = 'value-of-TEXT2' ).

    DATA(lv_ok) = lo_ok->get_text( ).
    WRITE: / '   ATTR2 = ''TEXT2''    :', lv_ok.

    " One letter wrong. There is no attribute called TEXTTWO. This is not
    " a syntax error, raises nothing and sets no sy-subrc: the attribute
    " NAME, wrapped in & characters, becomes the placeholder text.
    DATA(lo_typo) = NEW lcx_t100( iv_msgid = 'SABAPDEMOS'
                                  iv_msgno = '888'
                                  iv_attr2 = 'TEXTTWO'
                                  iv_text1 = 'value-of-TEXT1'
                                  iv_text2 = 'value-of-TEXT2' ).

    DATA(lv_typo) = lo_typo->get_text( ).
    WRITE: / '   ATTR2 = ''TEXTTWO''  :', lv_typo.
    WRITE: / '   ^ expect &TEXTTWO& where the value should have been'.
    SKIP.

  ENDMETHOD.


  METHOD missing_message_is_silent.

    WRITE: / '3) A message that is not in T100 does not raise anything'.

    " Nonexistent message class. The documented behaviour is that "a short
    " text is generated that lists the message class and message number as
    " well as the placeholder texts" - so a deleted message, or a class
    " transported without its message class, degrades silently.
    DATA(lo_gone) = NEW lcx_t100( iv_msgid = 'YDJ_NO_SUCH_CLS'
                                  iv_msgno = '042'
                                  iv_text1 = 'alpha'
                                  iv_text2 = 'beta' ).

    DATA(lv_gone) = lo_gone->get_text( ).

    WRITE: / '   generated text :', lv_gone.
    WRITE: / '   exception      : none - get_text( ) returned normally'.
    SKIP.

  ENDMETHOD.


  METHOD message_overwrites_ctor.

    WRITE: / '4) MESSAGE is applied AFTER the constructor and overwrites it'.

    " (a) Plain raise: the constructor's preset is what the object carries.
    TRY.
        RAISE EXCEPTION TYPE lcx_dyn_preset.

      CATCH lcx_dyn_preset INTO DATA(lo_plain).

        DATA(lv_plain) = lo_plain->get_text( ).
        WRITE: / '   plain raise   - msgty:', lo_plain->msgty,
                 'text:', lv_plain.

    ENDTRY.

    " (b) Same class, same constructor, plus the MESSAGE addition. The
    " assignment "takes place after the instance constructor is executed"
    " and "overwrites any values that were assigned to these attributes
    " when the exception object was constructed" - so msgty is E, not the
    " I the constructor chose, and the WITH values are in the text.
    TRY.
        RAISE EXCEPTION TYPE lcx_dyn_preset MESSAGE e888(sabapdemos)
              WITH 'constructor' 'preset' 'was' 'overwritten'.

      CATCH lcx_dyn_preset INTO DATA(lo_msg).

        DATA(lv_msg) = lo_msg->get_text( ).
        WRITE: / '   with MESSAGE  - msgty:', lo_msg->msgty,
                 'text:', lv_msg.

    ENDTRY.

    WRITE: / '   ^ the raise site wins; the constructor ran first anyway'.

    " Not shown because it does not compile, which is the good case:
    "   RAISE EXCEPTION TYPE lcx_dyn_preset
    "         MESSAGE e888(sabapdemos) EXPORTING textid = ...
    " "the addition MESSAGE cannot be combined with the input parameter
    " TEXTID". Nor can MESSAGE follow RAISE EXCEPTION oref.
    SKIP.

  ENDMETHOD.


  METHOD oref_type_and_restrictions.

    WRITE: / '5) MESSAGE oref - the implicit type is the trap'.

    TRY.
        RAISE EXCEPTION TYPE lcx_dyn MESSAGE e888(sabapdemos)
              WITH 'this' 'object' 'carries' 'type-E'.

      CATCH lcx_dyn INTO DATA(lo_err).

        WRITE: / '   msgty on the object :', lo_err->msgty.

        " A BARE "MESSAGE lo_err." would get the message type added
        " implicitly from the object's own MSGTY attribute - type E - and in
        " list processing a type E terminates the report with an empty
        " screen. The statement that looks like "show the error" is the
        " statement that ends the program. Deliberately NOT executed:
        "
        "   MESSAGE lo_err.               " <- would end this report here
        "
        " The explicit type is safe:
        MESSAGE lo_err TYPE 'S'.

        WRITE: / '   MESSAGE lo_err TYPE ''S'' : sent, report still running'.

        " MESSAGE lo_err INTO lv_x  and  MESSAGE lo_err WITH ...  are both
        " forbidden: "the addition WITH and the variant with INTO are not
        " allowed". get_text( ) is the way to obtain the string.
        DATA(lv_text) = lo_err->get_text( ).
        WRITE: / '   get_text( ) not INTO :', lv_text.

        " Also note: passing lo_err on to a helper whose formal parameter is
        " typed generically as ANY or DATA silently switches the statement
        " to the MESSAGE text variant, "which has identical syntax".
        " Type such parameters REF TO cx_root or REF TO if_t100_message.

    ENDTRY.

    SKIP.

  ENDMETHOD.


  METHOD previous_chain.

    WRITE: / '6) Wrap with PREVIOUS, then walk the chain for the real text'.

    TRY.

        TRY.
            RAISE EXCEPTION TYPE lcx_dyn MESSAGE s888(sabapdemos)
                  WITH 'the' 'real' 'message' 'is-here'.

          CATCH lcx_dyn INTO DATA(lo_inner).

            " Re-raising this same object with RAISE EXCEPTION lo_inner
            " would move the recorded source position to THIS line, because
            " those internal attributes "are converted to the position of
            " the statement RAISE". Wrapping keeps the original.
            RAISE EXCEPTION TYPE lcx_plain EXPORTING previous = lo_inner.

        ENDTRY.

      CATCH lcx_plain INTO DATA(lo_outer).

        " The outermost exception is the least informative one: lcx_plain
        " implements no message interface. CL_MESSAGE_HELPER=>
        " GET_LATEST_T100_EXCEPTION( ) does this walk in real code; it is
        " done by hand here so the mechanism is visible.
        DATA(lo_link)  = CAST cx_root( lo_outer ).
        DATA(lv_depth) = 0.

        WHILE lo_link IS BOUND.

          lv_depth = lv_depth + 1.

          TRY.
              " Downcast to the interface: succeeds only for links whose
              " class implements IF_T100_MESSAGE (IF_T100_DYN_MSG includes
              " it, so lcx_dyn passes and lcx_plain does not).
              DATA(lo_t100) = CAST if_t100_message( lo_link ).
              DATA(lv_found) = lo_t100->if_message~get_text( ).

              WRITE: / '   link', lv_depth,
                       ': T100 text found :', lv_found.

            CATCH cx_sy_move_cast_error.

              WRITE: / '   link', lv_depth,
                       ': no IF_T100_MESSAGE - keep walking'.

          ENDTRY.

          lo_link = lo_link->previous.

          " Defensive stop; a PREVIOUS chain should never be this deep.
          IF lv_depth > 10.
            EXIT.
          ENDIF.

        ENDWHILE.

    ENDTRY.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_demo=>message_sends_nothing( ).
  lcl_demo=>attr_name_not_value( ).
  lcl_demo=>missing_message_is_silent( ).
  lcl_demo=>message_overwrites_ctor( ).
  lcl_demo=>oref_type_and_restrictions( ).
  lcl_demo=>previous_chain( ).
