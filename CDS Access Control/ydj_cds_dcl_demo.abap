*&---------------------------------------------------------------------*
*& Report YDJ_CDS_DCL_DEMO
*&
*& CDS access control (DCL): the protection that stops at the entry
*& level, and the access rules that can only ever widen.
*&
*& A CDS role is DCL source code -- a separate repository object that
*& can only be written in ADT. It cannot be created from a report, so
*& the DCL and DDL below are commented reference blocks.
*&
*& What a report CAN do is execute the statements that DCL turns into,
*& because a CDS access condition is nothing more than a condition
*& that the database interface ANDs onto the query the application
*& wrote. That is what the runnable half does: it prints the row counts
*& for each shape, so the widening, the AND/OR combination rule and the
*& null leak are arithmetic rather than assertions.
*&
*& Nothing here creates, changes or deletes anything. No DDIC object
*& has to exist beyond SCARR and SPFLI.
*&
*& Notes: CDS Access Control (README.md in this folder)
*& Docs : ABENCDS_ACCESS_CONTROL, ABENCDS_F1_DEFINE_ROLE,
*&        ABENCDS_DCL_ROLE_RULES, ABENCDS_DCL_ROLE_COND_RULE,
*&        ABENCDS_DCL_ROLE_GRANT_RULE, ABENCDS_F1_COND_PFCG,
*&        ABENCDS_F1_COND_INHERIT
*&---------------------------------------------------------------------*
REPORT ydj_cds_dcl_demo.

*&---------------------------------------------------------------------*
*& The DDL and DCL this note is about (separate repository objects in
*& ADT - shown here as comments for readability only; // is the
*& comment character in DDL and DCL, not ").
*&---------------------------------------------------------------------*
*  --- the protected entity -----------------------------------------
*  @AccessControl.authorizationCheck: #MANDATORY   // <- not #CHECK
*  define view entity YDJ_CARR_VE
*    as select from scarr
*  {
*    key carrid,
*        carrname,
*        currcode
*  }
*
*  --- the role: ONE conditional rule -------------------------------
*  @MappingRole: true      // mandatory, and it means EVERY user
*  define role YDJ_CARR_VE_ROLE {
*    grant select on YDJ_CARR_VE
*      where (carrid) = aspect pfcg_auth(S_CARRID, CARRID, ACTVT = '03')
*          and currcode = 'USD';
*  }
*
*  --- a SECOND role for the SAME entity, added later by someone else
*  @MappingRole: true
*  define role YDJ_CARR_VE_ROLE2 {
*    grant select on YDJ_CARR_VE
*      combination mode or   // the DEFAULT, stated out loud
*      where currcode = 'EUR';  // this does NOT narrow anything
*  }
*
*  --- and the one line that switches protection off for everybody ---
*  @MappingRole: true
*  define role YDJ_CARR_VE_FULL {
*    grant select on YDJ_CARR_VE;  // no WHERE = full access, and it
*  }                               // beats the AND rules as well
*
*  --- the wrapper that loses the protection ------------------------
*  @AccessControl.authorizationCheck: #NOT_REQUIRED
*  define view entity YDJ_CARR_WRAP
*    as select from YDJ_CARR_VE  // <- a PROTECTED entity as a data
*  {                             //    source: its role is NOT
*    key carrid,                 //    evaluated when YDJ_CARR_WRAP
*        carrname,               //    is selected from in ABAP SQL
*        currcode
*  }
*
*  --- the opt-in that puts it back ---------------------------------
*  @MappingRole: true
*  define role YDJ_CARR_WRAP_ROLE {
*    grant select on YDJ_CARR_WRAP
*      where inheriting conditions from entity YDJ_CARR_VE;
*  }
*---------------------------------------------------------------------*

DATA lv_city TYPE spfli-cityto VALUE 'FRANKFURT'.
DATA lv_subrc TYPE sy-subrc.

START-OF-SELECTION.

*---------------------------------------------------------------------*
* 1) An access condition is just an extra AND on the statement the
*    application wrote. Nothing in the ABAP source shows it.
*---------------------------------------------------------------------*
  SELECT COUNT( * ) FROM scarr INTO @DATA(lv_unprotected).

  SELECT COUNT( * ) FROM scarr WHERE currcode = 'USD'
    INTO @DATA(lv_one_rule).

  WRITE: / '1) rows the SELECT asked for       :', lv_unprotected.
  WRITE: / '   rows after ONE access rule      :', lv_one_rule.
  WRITE: / '   -> the difference is invisible in the calling program;'.
  WRITE: / '      an empty result is not an error and not a message.'.
  SKIP.

*---------------------------------------------------------------------*
* 2) Two rules for the same entity are OR-ed, so a second role only
*    ever WIDENS. Adding a role cannot narrow anything.
*---------------------------------------------------------------------*
  SELECT COUNT( * ) FROM scarr WHERE currcode = 'USD' OR currcode = 'EUR'
    INTO @DATA(lv_two_rules).

  WRITE: / '2) rows, one rule (USD)            :', lv_one_rule.
  WRITE: / '   rows, two rules (USD or EUR)    :', lv_two_rules.
  WRITE: / '   rows, plus one full access rule :', lv_unprotected.
  WRITE: / '   -> a full access rule is GRANT SELECT with no WHERE.'.
  WRITE: / '      It wins over every other rule, AND rules included.'.
  SKIP.

*---------------------------------------------------------------------*
* 3) COMBINATION MODE AND is the only way to tighten. The documented
*    result is ( or_1 OR or_2 ... ) AND and_1 AND and_2 ...
*---------------------------------------------------------------------*
  SELECT COUNT( * ) FROM scarr
    WHERE ( currcode = 'USD' OR currcode = 'EUR' ) AND carrid = 'LH'
    INTO @DATA(lv_and_rule).

  WRITE: / '3) rows, ( USD or EUR ) AND LH     :', lv_and_rule.
  WRITE: / '   -> OR is the DEFAULT mode, so writing a rule and'.
  WRITE: / '      omitting COMBINATION MODE AND loosens instead.'.
  SKIP.

*---------------------------------------------------------------------*
* 4) The user with full authorization sees rows nobody else can see.
*    A full authorization for the field generates NO condition for the
*    element, so null values pass. A restricted user never gets them,
*    because any comparison with a null is unknown, not true.
*
*    The outer join below stands in for the path expression inside the
*    protected entity: it is what makes the element nullable. All
*    three counts are measured, not derived from each other.
*---------------------------------------------------------------------*
  SELECT COUNT( * )
    FROM scarr AS c
         LEFT OUTER JOIN spfli AS p
           ON  p~carrid = c~carrid
           AND p~cityto = @lv_city
    WHERE p~cityto = @lv_city
    INTO @DATA(lv_restricted).

  SELECT COUNT( * )
    FROM scarr AS c
         LEFT OUTER JOIN spfli AS p
           ON  p~carrid = c~carrid
           AND p~cityto = @lv_city
    WHERE p~connid IS NULL
    INTO @DATA(lv_nullrows).

  SELECT COUNT( * )
    FROM scarr AS c
         LEFT OUTER JOIN spfli AS p
           ON  p~carrid = c~carrid
           AND p~cityto = @lv_city
    INTO @DATA(lv_no_condition).

  WRITE: / '4) join rows, element = city       :', lv_restricted.
  WRITE: / '   join rows, element IS NULL      :', lv_nullrows.
  WRITE: / '   join rows, no condition at all  :', lv_no_condition.
  WRITE: / '   -> row 1 is what a restricted user sees, row 3 is'.
  WRITE: / '      what a user with * sees. Same role, same entity.'.
  WRITE: / '      Fix: AND the condition with element IS NOT NULL.'.
  SKIP.

*---------------------------------------------------------------------*
* 5) Denied and absent are the same thing to the caller. There is no
*    sy-subrc for "filtered by access control", and no exception.
*---------------------------------------------------------------------*
  SELECT SINGLE carrid FROM scarr WHERE currcode = 'ZZZ'
    INTO @DATA(lv_hit).
  lv_subrc = sy-subrc.

  WRITE: / '5) sy-subrc, condition matches none:', lv_subrc.
  WRITE: / '   -> an access condition that filters everything out'.
  WRITE: / '      produces exactly the same 4, so a program cannot'.
  WRITE: / '      tell "you may not" from "it is not there". Do not'.
  WRITE: / '      build an authorization message on sy-subrc.'.

  IF lv_hit IS NOT INITIAL.
    WRITE: / '   (not reached: SCARR has no ZZZ currency)'.
  ENDIF.
