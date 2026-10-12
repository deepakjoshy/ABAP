*&---------------------------------------------------------------------*
*& Report YDJ_SQL_STRING_FUNC_DEMO
*&---------------------------------------------------------------------*
*& String functions in ABAP SQL - what the database does to a character
*& column that ABAP would have left alone.
*&
*&   1. && and CONCAT disagree     -> a text field literal that consists
*&      about a separator             only of blanks is kept by the
*&                              operator && and ignored by the function
*&                              CONCAT, so the same separator survives
*&                              in one form and vanishes in the other.
*&   2. LENGTH ignores trailing    -> length( carrname ) is the length of
*&      blanks                        the content, not the CHAR(20) of
*&                              the column it came from.
*&   3. LPAD does not only pad     -> if the requested length is shorter
*&                              than the value, "it is truncated on the
*&                              right" - a right-aligning LPAD silently
*&                              cuts the end off and reports nothing.
*&   4. The search term of INSTR   -> it has to be a literal or a host
*&      cannot be computed           CONSTANT, and "sub respects all
*&                              blanks", so a CONSTANTS field declared
*&                              longer than its value never matches.
*&   5. Eight of these functions   -> every other one bypasses the table
*&      run in the table buffer      buffer. Adding RTRIM to a WHERE on
*&                              a fully buffered table sends every read
*&                              to the database from then on.
*&
*& Read-only. No INSERT/UPDATE/DELETE/MODIFY/COMMIT/ROLLBACK anywhere.
*& SCARR is used only to give the statements a FROM clause.
*&
*& Deliberately restricted to the functions that have been available the
*& longest: CONCAT, CONCAT_WITH_SPACE, LENGTH, LEFT, RIGHT, SUBSTRING,
*& LPAD, RPAD, LTRIM, REPLACE, INSTR, UPPER and LOWER. An unsupported SQL
*& function is a SYNTAX error, not a runtime one, so LOCATE, INITCAP and
*& the _REGEXPR family would stop this whole report from compiling on an
*& older system. They are written up in README.md instead.
*&
*& Doc: https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING_FUNC.html
*&      https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_STRING.html
*&      https://help.sap.com/doc/abapdocu_latest_index_htm/latest/en-US/ABENSQL_ENGINE_EXPR.html
*&---------------------------------------------------------------------*
REPORT ydj_sql_string_func_demo.

* Host constants, not host variables: the sub argument of INSTR accepts
* only a literal or a host constant. c_sub_padded holds the same value as
* c_sub_exact and six trailing blanks nobody typed.
CONSTANTS:
  c_carrid     TYPE scarr-carrid VALUE 'AA',
  c_sub_exact  TYPE c LENGTH 4   VALUE 'http',
  c_sub_padded TYPE c LENGTH 10  VALUE 'http'.

CLASS lcl_string_demo DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS:
      main,
      concat_vs_operator,
      length_and_slices,
      padding_truncates,
      search_term_blanks,
      replace_trim_and_case.
ENDCLASS.


CLASS lcl_string_demo IMPLEMENTATION.

  METHOD main.
    concat_vs_operator( ).
    length_and_slices( ).
    padding_truncates( ).
    search_term_blanks( ).
    replace_trim_and_case( ).
  ENDMETHOD.


  METHOD concat_vs_operator.

    WRITE: / '1. The separator that survives && and not CONCAT'.
    ULINE.

    SELECT SINGLE
           FROM scarr
           FIELDS carrid && ' ' && '(' && carrname && ')'   AS by_operator,
                  concat( carrid, carrname )                AS by_concat,
                  concat_with_space( carrid, carrname, 1 )  AS by_concat_sp
           WHERE carrid = @c_carrid
           INTO @DATA(ls_cat).

    IF sy-subrc <> 0.
      WRITE: / 'No row for carrier', c_carrid,
               '- fill the flight demo data (SAPBC_DATA_GENERATOR) first.'.
      RETURN.
    ENDIF.

    WRITE: / 'carrid && .. && carrname  ', ls_cat-by_operator.
    WRITE: / 'concat( carrid, carrname ) ', ls_cat-by_concat.
    WRITE: / 'concat_with_space( .., 1 ) ', ls_cat-by_concat_sp.
    SKIP.
    WRITE: / 'The operator && respects precisely one blank in a text field'.
    WRITE: / 'literal that consists only of blanks. CONCAT ignores trailing'.
    WRITE: / 'blanks in both arguments and in the result, so the second'.
    WRITE: / 'line has no separator at all - the concatenation is correct'.
    WRITE: / 'and unreadable. CONCAT_WITH_SPACE is the function form of a'.
    WRITE: / 'separator; the number of blanks has to be a literal or a'.
    WRITE: / 'host constant, never a column.'.
    SKIP 2.

  ENDMETHOD.


  METHOD length_and_slices.

    DATA lv_declared TYPE i.

    WRITE: / '2. LENGTH is the length of the content, not of the column'.
    ULINE.

    SELECT SINGLE
           FROM scarr
           FIELDS carrname,
                  length( carrname )           AS content_len,
                  left( carrname, 3 )          AS first_three,
                  right( carrname, 3 )         AS last_three,
                  substring( carrname, 1, 3 )  AS sub_three
           WHERE carrid = @c_carrid
           INTO @DATA(ls_len).

    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DESCRIBE FIELD ls_len-carrname LENGTH lv_declared IN CHARACTER MODE.

    WRITE: / 'carrname                   ', ls_len-carrname.
    WRITE: / 'DESCRIBE FIELD .. LENGTH   ', lv_declared.
    WRITE: / 'length( carrname )         ', ls_len-content_len.
    WRITE: / 'left( carrname, 3 )        ', ls_len-first_three.
    WRITE: / 'right( carrname, 3 )       ', ls_len-last_three.
    WRITE: / 'substring( carrname, 1, 3 )', ls_len-sub_three.
    SKIP.
    WRITE: / 'LENGTH counts the characters "ignoring trailing blanks", so'.
    WRITE: / 'it is the content length and not the declared CHAR length.'.
    WRITE: / 'RIGHT reads the last characters of the content as well, not'.
    WRITE: / 'the last characters of the column - the padding is gone'.
    WRITE: / 'before the function sees the value. LEFT and RIGHT also'.
    WRITE: / 'refuse a len greater than the length of the argument, and'.
    WRITE: / 'SUBSTRING needs pos and len to stay inside the argument.'.
    SKIP 2.

  ENDMETHOD.


  METHOD padding_truncates.

    WRITE: / '3. LPAD pads to a length - and truncates to it as well'.
    ULINE.

    SELECT SINGLE
           FROM scarr
           FIELDS lpad( carrname, 25, '.' ) AS wider,
                  lpad( carrname,  5, '.' ) AS narrower,
                  rpad( carrname, 25, '.' ) AS wider_right
           WHERE carrid = @c_carrid
           INTO @DATA(ls_pad).

    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    WRITE: / 'lpad( carrname, 25, ''.'' )  ', ls_pad-wider.
    WRITE: / 'lpad( carrname,  5, ''.'' )  ', ls_pad-narrower.
    WRITE: / 'rpad( carrname, 25, ''.'' )  ', ls_pad-wider_right.
    SKIP.
    WRITE: / 'The second line is the trap. The documentation says: "If len'.
    WRITE: / 'is less than the length of sql_exp, it is truncated on the'.
    WRITE: / 'right." So a function whose job is to add characters on the'.
    WRITE: / 'left removes characters on the right when the column turns'.
    WRITE: / 'out to be wider than the report column - no exception, no'.
    WRITE: / 'null value, just a shorter value that still looks like a'.
    WRITE: / 'name. The other documented surprise cannot be shown from'.
    WRITE: / 'a literal: if the pad argument src is EMPTY and len is'.
    WRITE: / 'greater than the length of the value, "sql_exp remains'.
    WRITE: / 'unchanged" - so an unfilled pad character pads nothing and'.
    WRITE: / 'the result keeps a variable length.'.
    SKIP 2.

  ENDMETHOD.


  METHOD search_term_blanks.

    WRITE: / '4. The search term of INSTR respects every blank it has'.
    ULINE.

    SELECT SINGLE
           FROM scarr
           FIELDS url,
                  instr( url, 'http' )         AS by_literal,
                  instr( url, @c_sub_exact )   AS by_exact_const,
                  instr( url, @c_sub_padded )  AS by_padded_const
           WHERE carrid = @c_carrid
           INTO @DATA(ls_instr).

    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    WRITE: / 'url                            ', ls_instr-url(40).
    WRITE: / 'instr( url, ''http'' )            ', ls_instr-by_literal.
    WRITE: / 'instr( url, @c_sub_exact )     ', ls_instr-by_exact_const.
    WRITE: / 'instr( url, @c_sub_padded )    ', ls_instr-by_padded_const.
    SKIP.
    WRITE: / 'c_sub_exact is c LENGTH 4 and c_sub_padded is c LENGTH 10,'.
    WRITE: / 'both with the value ''http''. For INSTR the documentation'.
    WRITE: / 'says the searched string "ignores trailing blanks" while'.
    WRITE: / 'the search term "respects all blanks" - so the six blanks'.
    WRITE: / 'that the CONSTANTS declaration padded it with are part'.
    WRITE: / 'of what is being searched for, and 0 means not found'.
    WRITE: / 'rather than a wrong offset. A constant has to be declared'.
    WRITE: / 'at exactly the length of its value.'.
    SKIP.
    WRITE: / 'The restriction above that comes first, though, is that'.
    WRITE: / 'the search term may only be a literal or a host CONSTANT.'.
    WRITE: / 'A host variable is rejected by the syntax check, so a'.
    WRITE: / 'search term that is read from a selection screen cannot'.
    WRITE: / 'be passed to INSTR at all. The next line does not compile:'.
    WRITE: / '  instr( url, @lv_term ) AS by_variable'.
    WRITE: / 'LIKE with a host variable, or LIKE_REGEXPR, is the way'.
    WRITE: / 'to search for something computed at runtime.'.
    SKIP 2.

  ENDMETHOD.


  METHOD replace_trim_and_case.

    WRITE: / '5. REPLACE, LTRIM, UPPER and the table buffer'.
    ULINE.

    SELECT SINGLE
           FROM scarr
           FIELDS replace( carrname, 'a', 'XY' )        AS doubled_a,
                  ltrim( concat( '000', carrid ), '0' ) AS unzeroed,
                  upper( carrname )                     AS upper_name,
                  lower( carrid )                       AS lower_id
           WHERE carrid = @c_carrid
           INTO @DATA(ls_mix).

    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    WRITE: / 'replace( carrname, ''a'', ''XY'' ) ', ls_mix-doubled_a.
    WRITE: / 'ltrim( concat( .. ), ''0'' ) ', ls_mix-unzeroed.
    WRITE: / 'upper( carrname )          ', ls_mix-upper_name.
    WRITE: / 'lower( carrid )            ', ls_mix-lower_id.
    SKIP.
    WRITE: / 'Three things worth remembering about this statement:'.
    WRITE: / '- REPLACE is case-sensitive: a lowercase a is doubled'.
    WRITE: / '  above and an uppercase A is not. It can also fail at'.
    WRITE: / '  COMPILE time on short data - the maximum possible'.
    WRITE: / '  length is len1 / len2 * len3, here 20 / 1 * 2 = 40,'.
    WRITE: / '  and anything above 1333 is a syntax error.'.
    WRITE: / '- LTRIM and RTRIM remove the trailing blanks of their'.
    WRITE: / '  first argument whichever end you asked about, and the'.
    WRITE: / '  blanks inside the character argument are significant.'.
    WRITE: / '- UPPER and LOWER do not accept NUMC, DATS or TIMS at'.
    WRITE: / '  all, which is a syntax error rather than a no-op.'.
    SKIP.
    WRITE: / 'Only CONCAT, CONCAT_WITH_SPACE, LEFT, RIGHT, LENGTH,'.
    WRITE: / 'SUBSTRING, UPPER and LOWER can be evaluated by the ABAP'.
    WRITE: / 'SQL in-memory engine. REPLACE, LTRIM, LPAD and the rest'.
    WRITE: / 'bypass table buffering - and so does the operator &&,'.
    WRITE: / 'while the function CONCAT does not. Two ways of writing'.
    WRITE: / 'the same concatenation, two different buffer behaviours.'.
    SKIP 2.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.
  lcl_string_demo=>main( ).

