*&---------------------------------------------------------------------*
*& Report YDJ_CDS_ASSOCIATION_DEMO
*&
*& CDS associations: the join you did not write.
*&
*& A CDS association is instantiated as a JOIN, and which join depends
*& on where the path expression is used -- not on the association
*& definition. This program proves the consequences with real row
*& counts, using the joins that the associations would be transformed
*& into, over the standard flight tables.
*&
*& WHAT THIS PROGRAM IS NOT
*&
*& It does not define CDS entities. An association needs a CDS view
*& entity (a separate repository object, written in the DDL editor in
*& ADT), and a path expression needs that entity to EXPOSE the
*& association. Neither can be created from a report.
*&
*& So the DDL and the path expressions appear here as commented
*& reference blocks against a hypothetical YDJ_CARR_VE, and the
*& runnable half executes the EQUIVALENT joins -- which is the whole
*& point of the note: the association is the join.
*&
*& Nothing here creates, changes or deletes anything. No DDIC object
*& has to exist beyond SCARR, SPFLI and SFLIGHT.
*&
*& Notes: CDS Associations (README.md in this folder)
*& Docs : ABENCDS_ASSOCIATION_V2, ABENCDS_ASSOC_JOIN_V2,
*&        ABENCDS_PATH_EXPRESSION_V2, ABENABAP_SQL_PATH,
*&        ABENABAP_SQL_PATH_FILTER, ABENABAP_SQL_PATH_RESTRICTIONS
*&---------------------------------------------------------------------*
REPORT ydj_cds_association_demo.

*&---------------------------------------------------------------------*
*& The CDS view entity this note is about (a separate repository
*& object in ADT - shown here as a comment for readability only).
*&
*&   @AccessControl.authorizationCheck: #NOT_REQUIRED
*&   define view entity YDJ_CARR_VE
*&     as select from scarr
*&     association of one to many spfli as _spfli     " <- to-MANY, said
*&       on scarr.carrid = _spfli.carrid              "    out loud
*&   {
*&     key scarr.carrid,                 " required: used in the ON
*&         scarr.carrname,               "    condition of an EXPOSED
*&         _spfli                        " <- EXPOSED: no join at all,
*&   }                                  "    and the only reason ABAP
*&                                      "    SQL can reach _spfli
*&
*& Three edits to that source, each changing the generated SQL:
*&
*&  (a) drop the cardinality  -> "association to spfli as _spfli"
*&      That is NOT "unspecified". The doc: "If the cardinality is not
*&      defined explicitly, the cardinality 'to 1' is used implicitly
*&      ([min..1])." On HANA the left outer join is then built with
*&      TO ONE and "the result can be undefined if the results set
*&      does not match the cardinality". Part 2 below measures exactly
*&      how false that promise is on real data.
*&
*&  (b) write "_spfli.connid" instead of bare "_spfli"
*&      -> the association becomes USED instead of EXPOSED: a LEFT
*&         OUTER JOIN is now generated, and because it is no longer
*&         exposed, no other CDS entity and no ABAP SQL statement can
*&         use it in a path expression.
*&
*&  (c) remove "scarr.carrid" from the element list
*&      -> syntax error while _spfli is exposed. The ON condition's
*&         source fields "must also be listed in the SELECT list" so
*&         that a consumer can build the join. Tidying the projection
*&         breaks an association nobody touched.
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& The ABAP SQL path expressions this note is about - each one legal
*& only against the view entity above, so they are comments too.
*&
*&   " Default in a column: LEFT OUTER JOIN
*&   SELECT carrid, carrname,
*&          \_spfli-connid AS connid
*&          FROM ydj_carr_ve
*&          INTO TABLE @DATA(lt_outer).
*&
*&   " Same association, INNER, with the caller's own cardinality --
*&   " which OVERWRITES the modeller's: "Specifying the cardinality
*&   " overwrites the original definition of the cardinality".
*&   SELECT carrid, carrname,
*&          \_spfli[ INNER MANY TO ONE ]-connid AS connid
*&          FROM ydj_carr_ve
*&          INTO TABLE @DATA(lt_inner).
*&
*&   " Default as a data source: INNER JOIN. Note the mandatory alias
*&   " (a FROM path expression is reachable only through "AS f ~ ...")
*&   " and that a to-MANY association in FROM also requires the
*&   " identical path expression in the SELECT list.
*&   SELECT f~carrid, f~connid
*&          FROM ydj_carr_ve\_spfli AS f
*&          INTO TABLE @DATA(lt_from).
*&
*&   " A filter is part of the JOIN, not a WHERE on the result:
*&   SELECT carrid,
*&          \_spfli[ WHERE cityfrom = 'FRANKFURT' ]-connid AS connid
*&          FROM ydj_carr_ve
*&          INTO TABLE @DATA(lt_filtered).
*&
*& Deliberately NOT shown as working code - each is a documented
*& restriction on path expressions in ABAP SQL:
*&
*&   ... FROM ydj_carr_ve FOR ALL ENTRIES IN @lt_keys ...
*&     -> path expressions cannot be combined with FOR ALL ENTRIES
*&
*&   ... FROM ydj_carr_ve WITH PRIVILEGED ACCESS ...
*&     -> nor with WITH PRIVILEGED ACCESS
*&
*&   ... INNER JOIN x ON y\_assoc-f = x~f ...
*&     -> path expressions cannot be used in the ON condition of a join
*&
*&   SELECT carrid, \_spfli-connid INTO TABLE @DATA(lt_any).
*&     -> with CORRESPONDING or an inline @DATA/@FINAL target, a
*&        path-expression column MUST carry an AS alias
*&---------------------------------------------------------------------*

CONSTANTS lc_city TYPE spfli-cityfrom VALUE 'FRANKFURT'.

DATA: lv_carriers     TYPE i,
      lv_inner        TYPE i,
      lv_outer        TYPE i,
      lv_dropped      TYPE i,
      lv_pairs        TYPE i,
      lv_with_flights TYPE i,
      lv_multiplied   TYPE i,
      lv_on_filter    TYPE i,
      lv_where_filter TYPE i,
      lv_lost         TYPE i,
      lv_max_conns    TYPE i.

DATA: BEGIN OF ls_per_carrier,
        carrid TYPE spfli-carrid,
        cnt    TYPE i,
      END OF ls_per_carrier.
DATA lt_per_carrier LIKE TABLE OF ls_per_carrier.

START-OF-SELECTION.

*&---------------------------------------------------------------------*
*& 0) The baseline: how many carriers exist at all.
*&---------------------------------------------------------------------*
  SELECT COUNT( * )
    FROM scarr
    INTO @lv_carriers.

  WRITE: / 'Carriers in SCARR                    :', lv_carriers.
  SKIP.

*&---------------------------------------------------------------------*
*& 1) The SAME association, two positions, two join types.
*&
*&    _spfli.connid in the element list -> LEFT OUTER JOIN
*&    FROM ydj_carr_ve\_spfli           -> INNER JOIN
*&
*&    Nothing in the association definition says "inner" or "outer".
*&    The doc: after FROM it is an inner join, "In all other locations,
*&    it is a left outer join".
*&---------------------------------------------------------------------*
  SELECT COUNT( DISTINCT c~carrid )
    FROM scarr AS c
         INNER JOIN spfli AS p ON c~carrid = p~carrid
    INTO @lv_inner.

  SELECT COUNT( DISTINCT c~carrid )
    FROM scarr AS c
         LEFT OUTER JOIN spfli AS p ON c~carrid = p~carrid
    INTO @lv_outer.

  lv_dropped = lv_outer - lv_inner.

  WRITE: / '1) carriers, element list (OUTER)    :', lv_outer.
  WRITE: / '   carriers, FROM clause  (INNER)    :', lv_inner.
  WRITE: / '   carriers lost by moving the path  :', lv_dropped.

  IF lv_dropped > 0.
    WRITE: / '   -> moving the path expression into FROM'.
    WRITE: / '      silently switched outer to inner.'.
  ELSE.
    WRITE: / '   -> equal here only because every carrier in this'.
    WRITE: / '      client happens to have flights. Part 3 forces'.
    WRITE: / '      the unmatched case with a filter.'.
  ENDIF.
  SKIP.

*&---------------------------------------------------------------------*
*& 2) The cardinality nobody enforces.
*&
*&    Omitting the cardinality asserts TO ONE. Here is what that
*&    assertion is worth against the actual data: the join produces
*&    MORE rows than there are carriers, so "to one" is simply false
*&    and the TO ONE optimization is running on a false premise --
*&    documented outcome: "the result can be undefined".
*&---------------------------------------------------------------------*
  SELECT COUNT( * )
    FROM scarr AS c
         INNER JOIN spfli AS p ON c~carrid = p~carrid
    INTO @lv_pairs.

  SELECT COUNT( DISTINCT carrid )
    FROM spfli
    INTO @lv_with_flights.

  lv_multiplied = lv_pairs - lv_with_flights.

* A subquery is NOT allowed as a data source in an ABAP SQL FROM
* clause, so the per-carrier maximum is aggregated into an internal
* table first and reduced in ABAP.
  SELECT carrid, COUNT( * ) AS cnt
    FROM spfli
    GROUP BY carrid
    INTO TABLE @lt_per_carrier.

  lv_max_conns = 0.
  LOOP AT lt_per_carrier INTO ls_per_carrier.
    IF ls_per_carrier-cnt > lv_max_conns.
      lv_max_conns = ls_per_carrier-cnt.
    ENDIF.
  ENDLOOP.

  WRITE: / '2) joined rows (carrier x connection):', lv_pairs.
  WRITE: / '   carriers that have flights        :', lv_with_flights.
  WRITE: / '   surplus rows over "one per carrier":', lv_multiplied.
  WRITE: / '   worst carrier has connections     :', lv_max_conns.

  IF lv_max_conns > 1.
    WRITE: / '   -> the relationship is to-MANY. Writing'.
    WRITE: / '      "association to spfli" (no cardinality) claims'.
    WRITE: / '      to-ONE, and nothing checks it: at most a syntax'.
    WRITE: / '      WARNING, and an undefined result set on HANA.'.
  ENDIF.
  SKIP.

*&---------------------------------------------------------------------*
*& 3) A filter belongs to the JOIN, not to the result.
*&
*&    _spfli[ WHERE cityfrom = 'FRANKFURT' ].connid becomes an
*&    EXTENDED CONDITION ON THE JOIN -- the filter moves into the ON
*&    clause of a LEFT OUTER JOIN. Carriers with no Frankfurt flight
*&    are therefore KEPT, with a null connid.
*&
*&    The same condition in a WHERE clause is applied AFTER the join
*&    and throws those carriers away. Same words, different result --
*&    and this is the standard outer-join-plus-WHERE trap wearing an
*&    association costume.
*&---------------------------------------------------------------------*
  SELECT COUNT( DISTINCT c~carrid )
    FROM scarr AS c
         LEFT OUTER JOIN spfli AS p
           ON c~carrid = p~carrid AND p~cityfrom = @lc_city
    INTO @lv_on_filter.

  SELECT COUNT( DISTINCT c~carrid )
    FROM scarr AS c
         LEFT OUTER JOIN spfli AS p ON c~carrid = p~carrid
    WHERE p~cityfrom = @lc_city
    INTO @lv_where_filter.

  lv_lost = lv_on_filter - lv_where_filter.

  WRITE: / '3) carriers, filter IN the join      :', lv_on_filter.
  WRITE: / '   carriers, filter in WHERE         :', lv_where_filter.
  WRITE: / '   carriers discarded by the WHERE   :', lv_lost.

  IF lv_lost > 0.
    WRITE: / '   -> the association filter keeps them (null connid),'.
    WRITE: / '      the WHERE clause deletes them. The filter is'.
    WRITE: / '      part of the join, so it cannot exclude the'.
    WRITE: / '      left-hand row.'.
  ENDIF.

  IF lv_on_filter = lv_carriers.
    WRITE: / '   -> and the filtered outer join returns EVERY'.
    WRITE: / '      carrier, which is the point: a filter on an'.
    WRITE: / '      outer path narrows the JOIN, never the result.'.
  ENDIF.
  SKIP.

*&---------------------------------------------------------------------*
*& 4) What none of this shows, and has to be read instead:
*&
*&    - EXPOSING an association ("_spfli" alone in the element list)
*&      generates NO join: "the association is not mentioned in the
*&      statement that is passed to the database". It is free, and it
*&      is the only thing that makes the association reusable.
*&
*&    - The join is generated in the view that USES the association,
*&      not the one that defines it, and "their left side is always
*&      the CDS entity that exposes the CDS association".
*&
*&    - $projection in an ON condition resolves against the ELEMENT
*&      LIST, alias names included -- so renaming an element with AS
*&      retargets the join condition.
*&
*&    - An association reached in WHERE must have max = 1. The "1:"
*&      attribute silences that check without guaranteeing anything:
*&      "It is not possible at runtime, however, to check whether the
*&      required uniqueness is achieved by the condition."
*&
*&    - An association whose target is a DDIC TABLE (as _spfli here)
*&      exposes nothing, so no further association can follow it in a
*&      path expression. Paths only continue through CDS entities.
*&
*&    - A SELF association cannot be instantiated as a join in the
*&      entity that defines it: expose it, do not use it there.
*&---------------------------------------------------------------------*
  WRITE: / '4) See README.md for exposure, $projection, the "1:"'.
  WRITE: / '   promise, DDIC dead ends and compositions.'.
