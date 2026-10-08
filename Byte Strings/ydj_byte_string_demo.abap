*&---------------------------------------------------------------------*
*& Report  ydj_byte_string_demo
*&---------------------------------------------------------------------*
*& The string <-> xstring boundary: why the assignment is a hexadecimal
*& parse and not a code page conversion, and the places that fails quietly.
*&
*& Six sections:
*&   1  CONV xstring( text ) parses hex digits - it does not encode text
*&   2  the hex round trip that makes the bug look like working code
*&   3  bytes back to character-like: hex digits, truncation, lost bytes
*&   4  IN BYTE MODE is never the default, and the boundary is a byte
*&   5  BYTE-CO / BYTE-CA and the sy-fdpos that means two things
*&   6  GET BIT: 1-based, MSB-first, past-the-end is sy-subrc = 4
*&
*& READ-ONLY: no SELECT, no database write, no COMMIT, no file access,
*& no RFC. Everything here is in-memory string and byte handling.
*&
*& Base64 is covered in the README but deliberately NOT called here:
*& CL_WEB_HTTP_UTILITY / CL_HTTP_UTILITY availability differs between
*& on-premise releases and ABAP Cloud, and this report is meant to run
*& anywhere without a syntax error.
*&
*& Functional calls are hoisted into variables before every WRITE, per
*& the repo's Regular Expressions and String Processing notes.
*&
*& Refs: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCONVERSION_TYPE_C.html
*&       https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENCL_ABAP_CONV_CODEPAGE.html
*&---------------------------------------------------------------------*
REPORT ydj_byte_string_demo.

CLASS lcl_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS hex_parse_not_encoding.
    CLASS-METHODS round_trip_illusion.
    CLASS-METHODS bytes_back_to_chars.
    CLASS-METHODS byte_mode_is_not_default.
    CLASS-METHODS byte_comparisons.
    CLASS-METHODS bit_access.

  PRIVATE SECTION.

    " Rendering helper: an xstring written directly by WRITE would itself
    " be converted, so the hex text is built explicitly instead.
    CLASS-METHODS as_hex
      IMPORTING
        iv_bytes      TYPE xstring
      RETURNING
        VALUE(rv_text) TYPE string.

ENDCLASS.


CLASS lcl_demo IMPLEMENTATION.

  METHOD as_hex.

    " x / xstring to string yields the hexadecimal CHARACTERS of each
    " half-byte - which is exactly what we want for display here, and
    " exactly what surprises people in section 3.
    rv_text = CONV string( iv_bytes ).

  ENDMETHOD.


  METHOD hex_parse_not_encoding.

    WRITE: / '--- 1. CONV xstring( ) parses hex, it does not encode ---'.

    " Built at runtime on purpose. As a literal, the syntax check would
    " warn about the invalid characters; from a file or a screen field
    " there is no warning at all.
    DATA(lv_text) = `Hello`.

    DATA(lv_parsed) = CONV xstring( lv_text ).
    DATA(lv_parsed_len) = xstrlen( lv_parsed ).

    " 'H' is not one of 0-9 / A-F, so the conversion terminates at the
    " first character and no half-byte is ever passed.
    WRITE: / '  text                :', lv_text,
           / '  CONV xstring( text ) length:', lv_parsed_len.

    " The conversion that actually respects a code page.
    DATA(lv_encoded) = cl_abap_conv_codepage=>create_out(
                         codepage = `UTF-8` )->convert( source = lv_text ).
    DATA(lv_encoded_len) = xstrlen( lv_encoded ).
    DATA(lv_encoded_hex) = as_hex( lv_encoded ).

    WRITE: / '  create_out( )->convert( ) length:', lv_encoded_len,
           / '  bytes               :', lv_encoded_hex.

    " And back again. The documentation asserts this round trip.
    DATA(lv_decoded) = cl_abap_conv_codepage=>create_in(
                         codepage = `UTF-8` )->convert( source = lv_encoded ).

    IF lv_decoded = lv_text.
      WRITE: / '  round trip via code page: identical'.
    ELSE.
      WRITE: / '  round trip via code page: DIFFERENT'.
    ENDIF.

    " Neither branch above raised anything. The empty xstring from the
    " hex parse is the same empty xstring you would get from empty input.
    IF lv_parsed IS INITIAL.
      WRITE: / '  the hex parse produced an empty xstring, no exception'.
    ENDIF.

  ENDMETHOD.


  METHOD round_trip_illusion.

    WRITE: / '--- 2. Why hex-shaped test data hides the bug ---'.

    " Test data that happens to be hex digits round-trips perfectly,
    " which is the whole reason this reaches production.
    DATA(lv_hexish) = `DEADBEEF`.
    DATA(lv_bytes)  = CONV xstring( lv_hexish ).
    DATA(lv_there_and_back) = CONV string( lv_bytes ).
    DATA(lv_bytes_len) = xstrlen( lv_bytes ).

    WRITE: / '  input   :', lv_hexish,
           / '  bytes   :', lv_bytes_len,
           / '  back    :', lv_there_and_back.

    IF lv_there_and_back = lv_hexish.
      WRITE: / '  looks like a clean encode/decode. It is not one.'.
    ENDIF.

    " Odd number of valid characters: the last half-byte is padded.
    DATA(lv_odd) = `ABC`.
    DATA(lv_odd_bytes) = CONV xstring( lv_odd ).
    DATA(lv_odd_len) = xstrlen( lv_odd_bytes ).
    DATA(lv_odd_hex) = as_hex( lv_odd_bytes ).

    WRITE: / '  3 nibbles in :', lv_odd,
           / '  out          :', lv_odd_hex,
           / '  bytes        :', lv_odd_len.

    " Trailing rubbish is dropped silently from the first bad character.
    DATA(lv_mixed) = `DEADBEEFXYZ`.
    DATA(lv_mixed_bytes) = CONV xstring( lv_mixed ).
    DATA(lv_mixed_hex) = as_hex( lv_mixed_bytes ).

    WRITE: / '  mixed input  :', lv_mixed,
           / '  out          :', lv_mixed_hex,
           / '  the XYZ vanished without an exception'.

  ENDMETHOD.


  METHOD bytes_back_to_chars.

    WRITE: / '--- 3. Bytes to character-like and numeric targets ---'.

    " Real UTF-8 bytes for a non-ASCII string, produced properly.
    DATA(lv_src) = `Muenchen`.
    DATA(lv_utf8) = cl_abap_conv_codepage=>create_out( )->convert( source = lv_src ).

    " Assigning those bytes to a string gives the HEX DIGITS as text,
    " twice as long as the byte string - not the original text.
    DATA(lv_as_string) = CONV string( lv_utf8 ).
    DATA(lv_byte_len)  = xstrlen( lv_utf8 ).
    DATA(lv_char_len)  = strlen( lv_as_string ).

    WRITE: / '  bytes          :', lv_byte_len,
           / '  CONV string( ) :', lv_as_string,
           / '  its strlen     :', lv_char_len,
           / '  (2 characters per byte - hex digits, not the text)'.

    " A fixed-length c target truncates on the right, silently.
    TYPES ty_c4 TYPE c LENGTH 4.
    DATA(lv_short) = CONV ty_c4( lv_utf8 ).

    WRITE: / '  into c LENGTH 4:', lv_short,
           / '  the rest was cut off on the right, sy-subrc untouched'.

    " Numeric target: only the last 4 bytes survive. No overflow is
    " raised, because the leading bytes are discarded before the number
    " exists.
    DATA lv_wide TYPE xstring.
    lv_wide = CONV xstring( `FFFFFF075BCD15` ).
    DATA(lv_as_int) = CONV i( lv_wide ).
    DATA(lv_wide_len) = xstrlen( lv_wide ).

    WRITE: / '  7-byte xstring :', lv_wide_len,
           / '  CONV i( )      :', lv_as_int,
           / '  the leading FFFFFF was ignored, not an overflow'.

  ENDMETHOD.


  METHOD byte_mode_is_not_default.

    WRITE: / '--- 4. IN BYTE MODE is never the default ---'.

    " The documentation's own example: split UTF-8 bytes at hexadecimal
    " 20, which is a blank in UTF-8 and cannot occur inside a multi-byte
    " UTF-8 sequence. That last property is what makes it safe.
    DATA(lv_xstr) = cl_abap_conv_codepage=>create_out(
                      )->convert( source = `Like a Hurricane` ).

    DATA(lv_sep) = CONV xstring( `20` ).

    " In byte mode the inline declaration is a table of xstring; in
    " character mode the same statement would declare string.
    SPLIT lv_xstr AT lv_sep INTO TABLE DATA(lt_xtab) IN BYTE MODE.

    DATA(lv_count) = lines( lt_xtab ).
    WRITE: / '  segments:', lv_count.

    LOOP AT lt_xtab INTO DATA(lv_segment).
      " Each segment is still bytes - convert it back to see it.
      DATA(lv_word) = cl_abap_conv_codepage=>create_in(
                        )->convert( source = lv_segment ).
      DATA(lv_seg_len) = xstrlen( lv_segment ).
      WRITE: / '   ', lv_word, '(', lv_seg_len, 'bytes )'.
    ENDLOOP.

    " The segments were assigned "while ignoring the conversion rules",
    " so a byte-mode split does NOT hex-parse anything. That is why this
    " works where the assignment in section 1 did not.
    WRITE: / '  byte-mode SPLIT does not apply the hex rules'.

    " Separator not found: one segment with everything in it.
    DATA(lv_missing) = CONV xstring( `FF` ).
    SPLIT lv_xstr AT lv_missing INTO TABLE DATA(lt_one) IN BYTE MODE.
    DATA(lv_one_count) = lines( lt_one ).

    WRITE: / '  separator absent -> segments:', lv_one_count.

  ENDMETHOD.


  METHOD byte_comparisons.

    WRITE: / '--- 5. BYTE-CO / BYTE-CA and sy-fdpos ---'.

    DATA lv_data TYPE xstring.
    DATA lv_set  TYPE xstring.

    " The doc's own idiom: is the upper nibble of every byte empty?
    lv_data = CONV xstring( `010203` ).
    lv_set  = CONV xstring( `000102030405060708090A0B0C0D0E0F` ).

    CLEAR sy-fdpos.
    IF lv_data BYTE-CO lv_set.
      DATA(lv_fd_ok) = sy-fdpos.
      DATA(lv_len_ok) = xstrlen( lv_data ).
      WRITE: / '  BYTE-CO true  -> sy-fdpos:', lv_fd_ok,
             / '                   xstrlen :', lv_len_ok,
             / '  on SUCCESS sy-fdpos is the LENGTH, not an offset'.
    ENDIF.

    " Now a byte that is not in the set.
    lv_data = CONV xstring( `0102FF` ).

    CLEAR sy-fdpos.
    IF lv_data BYTE-CO lv_set.
      WRITE: / '  unexpected match'.
    ELSE.
      DATA(lv_fd_bad) = sy-fdpos.
      WRITE: / '  BYTE-CO false -> sy-fdpos:', lv_fd_bad,
             / '  on FAILURE it is the offset of the first bad byte'.
    ENDIF.

    " The initial-operand asymmetry. Both of these are guards that a
    " developer would expect to reject empty input.
    DATA lv_empty TYPE xstring.

    CLEAR sy-fdpos.
    IF lv_empty BYTE-CO lv_set.
      WRITE: / '  empty BYTE-CO set : TRUE  - the guard PASSES empty input'.
    ELSE.
      WRITE: / '  empty BYTE-CO set : false'.
    ENDIF.

    CLEAR sy-fdpos.
    IF lv_empty BYTE-CA lv_set.
      WRITE: / '  empty BYTE-CA set : true'.
    ELSE.
      WRITE: / '  empty BYTE-CA set : FALSE - always false if either is initial'.
    ENDIF.

  ENDMETHOD.


  METHOD bit_access.

    WRITE: / '--- 6. GET BIT: 1-based, MSB first ---'.

    DATA lv_hex TYPE xstring.
    lv_hex = CONV xstring( `1B` ).

    DATA(lv_bits) = xstrlen( lv_hex ) * 8.
    DATA lv_binary TYPE string.

    " Bit positions start at 1. Position 0 raises an UNCATCHABLE
    " exception (BIT_OFFSET_NOT_POSITIVE), so it is not demonstrated
    " here - a TRY block would not save the report.
    DATA lv_pos TYPE i VALUE 1.

    WHILE lv_pos <= lv_bits.
      GET BIT lv_pos OF lv_hex INTO DATA(lv_bit).
      lv_binary = lv_binary && lv_bit.
      lv_pos = lv_pos + 1.
    ENDWHILE.

    WRITE: / '  hex 1B  ->', lv_binary,
           / '  (MSB first: external interfaces often number from the LSB)'.

    " One past the end: sy-subrc = 4 and the target is NOT touched.
    DATA lv_last TYPE i VALUE 99.
    DATA(lv_past) = lv_bits + 1.
    GET BIT lv_past OF lv_hex INTO lv_last.
    DATA(lv_subrc) = sy-subrc.

    WRITE: / '  read past the end -> sy-subrc:', lv_subrc,
           / '                       target  :', lv_last,
           / '  no exception; an unchecked loop repeats the last value'.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_demo=>hex_parse_not_encoding( ).
  lcl_demo=>round_trip_illusion( ).
  lcl_demo=>bytes_back_to_chars( ).
  lcl_demo=>byte_mode_is_not_default( ).
  lcl_demo=>byte_comparisons( ).
  lcl_demo=>bit_access( ).
