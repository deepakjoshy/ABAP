*&---------------------------------------------------------------------*
*& Report YDJ_SQL_HIERARCHY_DEMO
*&---------------------------------------------------------------------*
*& ABAP SQL hierarchies - the FROM clause that understands a tree.
*&
*&   1. GENERATOR + COLUMNS  -> HIERARCHY( ... ) inline, and why every
*&                              hierarchy column must be named in FIELDS.
*&   2. SELECT *             -> returns the SOURCE columns only. The same
*&                              hierarchy columns still work in WHERE.
*&   3. DIRTY DATA           -> MULTIPLE PARENTS / CYCLES raise; ORPHANS
*&                              defaults to IGNORE and drops rows quietly.
*&   4. ROOT TEST            -> hierarchy_parent_rank = 0, because
*&                              hierarchy_level starts at 1, never 0.
*&   5. NAVIGATORS           -> DESCENDANTS is positive distance,
*&                              ANCESTORS is negative. FROM 1 vs TO -1.
*&   6. DEPTH                -> 0 = roots only; negative = no rows and
*&                              sy-subrc 4, which is NOT an error.
*&   7. AGGREGATE NAVIGATOR  -> MEASURES rolls up the whole subtree; the
*&                              WHERE selects ROWS, not what is summed.
*&   8. CTE HIERARCHY        -> WITH ... WITH HIERARCHY, then navigate it.
*&
*& ---------------------------------------------------------------------
*& NOT RUNNABLE AS PASTED. A hierarchy cannot be built from a bare
*& database table: the generator needs a hierarchy SOURCE that exposes a
*& SELF-ASSOCIATION. There is no SAP-delivered flight-data equivalent, so
*& the two DDL artifacts below must exist first. Create them in ADT, then
*& this report compiles as written.
*&
*& (a) table YDJ_COST_CENTRE - key COST_CENTRE (char10), PARENT_CC
*&     (char10, blank for a root), CC_NAME (char40), PLAN_AMOUNT (curr).
*&
*& (b) view entity YDJ_I_COST_CENTRE_SRC:
*&
*&     @AccessControl.authorizationCheck: #NOT_REQUIRED
*&     define view entity YDJ_I_COST_CENTRE_SRC
*&       as select from ydj_cost_centre
*&       association to exact one YDJ_I_COST_CENTRE_SRC as _parent
*&         on $projection.parent_cc = _parent.cost_centre
*&     {
*&           _parent,
*&       key cost_centre,
*&           parent_cc,
*&           cc_name,
*&           plan_amount
*&     }
*&
*& The ON condition may use = and AND only - no ranges, no OR - or it is
*& not a hierarchy association.
*&
*& Requires an SAP HANA database: the docs state the result sets are
*& produced "using the SAP HANA hierarchy generator function HIERARCHY
*& and similar". Behaviour on other platforms was not verified here.
*&
*& Read-only: SELECTs only, no writes, no COMMIT.
*&
*& Docs: https://help.sap.com/docs/abap-cloud/abap-keywords-standard-abap/
*&       pages: select-from-hierarchy,
*&              select-from-hierarchy-child-to-parent-association,
*&              hierarchy-columns,
*&              select-from-hierarchy-node-navigator,
*&              select-from-hierarchy-descendants-aggregate,
*&              cds-ddl-define-hierarchy
*&---------------------------------------------------------------------*
REPORT ydj_sql_hierarchy_demo.


CLASS lcl_hierarchy_demo DEFINITION.

  PUBLIC SECTION.

    CLASS-METHODS run.

  PRIVATE SECTION.

    " A root is a row whose parent field is empty. Typed from the
    " column itself rather than using the char1 constant SPACE, so the
    " comparison cannot be a length/type mismatch in strict mode.
    CONSTANTS gc_no_parent TYPE ydj_cost_centre-parent_cc
                           VALUE IS INITIAL.

    TYPES:
      BEGIN OF ty_actual,
        cost_centre TYPE ydj_cost_centre-cost_centre,
        amount      TYPE ydj_cost_centre-plan_amount,
      END OF ty_actual,
      ty_actual_tab TYPE STANDARD TABLE OF ty_actual WITH EMPTY KEY.

    CLASS-METHODS:
      demo_columns_vs_star,
      demo_root_test,
      demo_navigators,
      demo_depth,
      demo_aggregate,
      demo_cte_hierarchy.

ENDCLASS.


CLASS lcl_hierarchy_demo IMPLEMENTATION.

  METHOD run.

    demo_columns_vs_star( ).
    demo_root_test( ).
    demo_navigators( ).
    demo_depth( ).
    demo_aggregate( ).
    demo_cte_hierarchy( ).

  ENDMETHOD.


  METHOD demo_columns_vs_star.

    " ---------------------------------------------------------------
    " 1 + 2. The hierarchy columns are opt-in.
    " ---------------------------------------------------------------
    " Named explicitly in FIELDS: all of them come back. SIBLINGS
    " ORDER BY is not cosmetic - without it "the order of the sibling
    " nodes is undefined", and the query ORDER BY then restores
    " pre-order traversal on the ABAP side.

    SELECT FROM HIERARCHY( SOURCE ydj_i_cost_centre_src
                           CHILD TO PARENT ASSOCIATION _parent
                           START WHERE parent_cc = @gc_no_parent
                           SIBLINGS ORDER BY cost_centre )
           FIELDS cost_centre,
                  parent_cc,
                  cc_name,
                  hierarchy_rank,
                  hierarchy_level,
                  hierarchy_parent_rank,
                  hierarchy_tree_size,
                  hierarchy_is_cycle,
                  hierarchy_is_orphan
           ORDER BY hierarchy_rank
           INTO TABLE @DATA(lt_full).

    DATA(lv_full_rows) = lines( lt_full ).
    WRITE: / 'Named columns   - rows:', lv_full_rows.

    " The same statement with *. It compiles, it runs, and the
    " hierarchy columns are NOT in the result set - "Only the
    " components of the source of the SQL hierarchy are respected."
    " The WHERE below proves they are still evaluated: the filter
    " works on a column the inline-declared table cannot hold.

    SELECT * FROM HIERARCHY( SOURCE ydj_i_cost_centre_src
                             CHILD TO PARENT ASSOCIATION _parent
                             START WHERE parent_cc = @gc_no_parent
                             SIBLINGS ORDER BY cost_centre )
           WHERE hierarchy_level <= 2
           ORDER BY hierarchy_rank
           INTO TABLE @DATA(lt_star).

    " lt_star has cost_centre / parent_cc / cc_name / plan_amount and
    " no hierarchy_level - yet only levels 1 and 2 are in it.
    DATA(lv_star_rows) = lines( lt_star ).
    WRITE: / 'SELECT * filtered to level <= 2 - rows:', lv_star_rows.
    WRITE: / '  ... and carries no hierarchy_level column at all.'.

  ENDMETHOD.


  METHOD demo_root_test.

    " ---------------------------------------------------------------
    " 3 + 4. Dirty data, and how to recognise a root.
    " ---------------------------------------------------------------
    " The defaults are MULTIPLE PARENTS NOT ALLOWED and CYCLES ERROR
    " (both raise) plus ORPHANS IGNORE (drops rows silently). This
    " variant survives all three and makes the damage visible instead:
    " CYCLES BREAKUP needs MULTIPLE PARENTS ALLOWED, and ORPHANS ROOT
    " re-roots the unreachable nodes with a flag set.
    "
    " Cost of ALLOWED: the tree columns stop being trustworthy, since
    " a node reachable by two paths is generated twice.

    SELECT FROM HIERARCHY( SOURCE ydj_i_cost_centre_src
                           CHILD TO PARENT ASSOCIATION _parent
                           START WHERE parent_cc = @gc_no_parent
                           SIBLINGS ORDER BY cost_centre
                           MULTIPLE PARENTS ALLOWED
                           ORPHANS ROOT
                           CYCLES BREAKUP )
           FIELDS cost_centre,
                  parent_cc,
                  hierarchy_level,
                  hierarchy_parent_rank,
                  hierarchy_is_cycle,
                  hierarchy_is_orphan
           INTO TABLE @DATA(lt_tolerant).

    DATA lv_roots    TYPE i.
    DATA lv_orphans  TYPE i.
    DATA lv_cycles   TYPE i.
    DATA lv_at_zero  TYPE i.

    LOOP AT lt_tolerant ASSIGNING FIELD-SYMBOL(<ls_node>).

      " The root test. hierarchy_parent_rank is "0 for root nodes";
      " hierarchy_level is "Always 1 for root nodes", so a test for
      " level 0 can never be true.
      IF <ls_node>-hierarchy_parent_rank = 0.
        lv_roots = lv_roots + 1.
      ENDIF.

      IF <ls_node>-hierarchy_level = 0.
        lv_at_zero = lv_at_zero + 1.     " stays 0 forever
      ENDIF.

      IF <ls_node>-hierarchy_is_orphan = 1.
        lv_orphans = lv_orphans + 1.
      ENDIF.

      IF <ls_node>-hierarchy_is_cycle = 1.
        lv_cycles = lv_cycles + 1.
      ENDIF.

    ENDLOOP.

    DATA(lv_tol_rows) = lines( lt_tolerant ).
    WRITE: / 'Tolerant read   - rows:', lv_tol_rows.
    WRITE: / '  roots (parent_rank = 0):', lv_roots.
    WRITE: / '  nodes at level 0       :', lv_at_zero, '<- always 0'.
    WRITE: / '  orphan-flagged         :', lv_orphans.
    WRITE: / '  cycle-flagged          :', lv_cycles.
    WRITE: / '  (with ORPHANS IGNORE the orphans would be missing,'.
    WRITE: / '   with sy-subrc still 0.)'.

  ENDMETHOD.


  METHOD demo_navigators.

    " ---------------------------------------------------------------
    " 5. Navigators, and the sign of HIERARCHY_DISTANCE.
    " ---------------------------------------------------------------
    " Generate once, navigate many times: "finding the descendant
    " nodes of a node with ... HIERARCHY_DESCENDANTS is more efficient
    " than generating a new SQL hierarchy with this node as a root
    " node", because the generated hierarchy is buffered on the DB.

    SELECT SINGLE FROM ydj_i_cost_centre_src
           FIELDS cost_centre
           WHERE parent_cc <> @gc_no_parent
           INTO @DATA(lv_node).

    IF sy-subrc <> 0.
      WRITE: / 'No non-root cost centre found - skipping navigators.'.
      RETURN.
    ENDIF.

    " DESCENDANTS: distance is the POSITIVE level difference, so
    " DISTANCE FROM 1 is the documented way to drop the start node.
    SELECT FROM HIERARCHY_DESCENDANTS(
                  SOURCE HIERARCHY( SOURCE ydj_i_cost_centre_src
                                    CHILD TO PARENT ASSOCIATION _parent
                                    START WHERE parent_cc = @gc_no_parent
                                    SIBLINGS ORDER BY cost_centre )
                  START WHERE cost_centre = @lv_node
                  DISTANCE FROM 1 )
           FIELDS cost_centre,
                  parent_id,
                  hierarchy_distance,
                  start_rank
           INTO TABLE @DATA(lt_below).

    " ANCESTORS: distance is the NEGATIVE difference, so the mirror
    " idiom is TO -1. Reusing FROM 1 here returns nothing at all.
    SELECT FROM HIERARCHY_ANCESTORS(
                  SOURCE HIERARCHY( SOURCE ydj_i_cost_centre_src
                                    CHILD TO PARENT ASSOCIATION _parent
                                    START WHERE parent_cc = @gc_no_parent
                                    SIBLINGS ORDER BY cost_centre )
                  START WHERE cost_centre = @lv_node
                  DISTANCE TO -1 )
           FIELDS cost_centre,
                  parent_id,
                  hierarchy_distance
           INTO TABLE @DATA(lt_above).

    " The wrong sign is not an error, just an empty table.
    SELECT FROM HIERARCHY_DESCENDANTS(
                  SOURCE HIERARCHY( SOURCE ydj_i_cost_centre_src
                                    CHILD TO PARENT ASSOCIATION _parent
                                    START WHERE parent_cc = @gc_no_parent
                                    SIBLINGS ORDER BY cost_centre )
                  START WHERE cost_centre = @lv_node
                  DISTANCE FROM -3 TO -2 )
           FIELDS cost_centre
           INTO TABLE @DATA(lt_wrong_sign).

    DATA(lv_below_rows) = lines( lt_below ).
    DATA(lv_above_rows) = lines( lt_above ).
    DATA(lv_wrong_rows) = lines( lt_wrong_sign ).

    WRITE: / 'Navigators from node:', lv_node.
    WRITE: / '  descendants (FROM  1):', lv_below_rows.
    WRITE: / '  ancestors   (TO   -1):', lv_above_rows.
    WRITE: / '  descendants (FROM -3 TO -2):', lv_wrong_rows,
             '<- wrong sign, empty, no error'.

  ENDMETHOD.


  METHOD demo_depth.

    " ---------------------------------------------------------------
    " 6. DEPTH 0 is roots only; DEPTH < 0 is sy-subrc 4.
    " ---------------------------------------------------------------
    " "If the value of depth is 0, only the root nodes are inserted";
    " "If depth is less than 0, no hierarchy nodes are created and
    " sy-subrc is set to 4." A computed depth that goes negative is
    " therefore indistinguishable from an empty subtree.

    DATA lv_depth TYPE i.

    lv_depth = 0.
    SELECT FROM HIERARCHY( SOURCE ydj_i_cost_centre_src
                           CHILD TO PARENT ASSOCIATION _parent
                           START WHERE parent_cc = @gc_no_parent
                           SIBLINGS ORDER BY cost_centre
                           DEPTH @lv_depth )
           FIELDS cost_centre, hierarchy_level
           INTO TABLE @DATA(lt_depth_0).
    DATA(lv_subrc_0) = sy-subrc.

    lv_depth = -1.
    SELECT FROM HIERARCHY( SOURCE ydj_i_cost_centre_src
                           CHILD TO PARENT ASSOCIATION _parent
                           START WHERE parent_cc = @gc_no_parent
                           SIBLINGS ORDER BY cost_centre
                           DEPTH @lv_depth )
           FIELDS cost_centre, hierarchy_level
           INTO TABLE @DATA(lt_depth_neg).
    DATA(lv_subrc_neg) = sy-subrc.

    DATA(lv_rows_0)   = lines( lt_depth_0 ).
    DATA(lv_rows_neg) = lines( lt_depth_neg ).

    WRITE: / 'DEPTH  0 - rows:', lv_rows_0,
             'sy-subrc:', lv_subrc_0, '(roots only)'.
    WRITE: / 'DEPTH -1 - rows:', lv_rows_neg,
             'sy-subrc:', lv_subrc_neg, '(not an exception)'.

    " DEPTH cannot be combined with ORPHANS ERROR or ORPHANS ROOT -
    " "only if the addition ORPHANS is not specified or is specified
    " as ORPHANS IGNORE". That combination is a syntax error, which is
    " why it is described here rather than demonstrated.

  ENDMETHOD.


  METHOD demo_aggregate.

    " ---------------------------------------------------------------
    " 7. The roll-up, and the WHERE that does not limit the sum.
    " ---------------------------------------------------------------
    " MEASURES applies the aggregate to "the node and all its
    " descendant nodes" - a running subtree total with no loop.
    "
    " The WHERE is the trap: "The WHERE condition does not restrict
    " the descendant nodes of the selected nodes. It is used only to
    " select those nodes for which the aggregate function is
    " calculated." So level <= 2 chooses which ROWS come back; every
    " one of them still totals its ENTIRE subtree.

    DATA lt_actuals TYPE ty_actual_tab.

    SELECT FROM ydj_i_cost_centre_src
           FIELDS cost_centre, plan_amount AS amount
           INTO TABLE @lt_actuals.

    DATA(lv_level) = 2.

    " Only ONE internal table may be transported per statement -
    " hierarchy functions bypass the buffer and the in-memory engine.
    SELECT FROM HIERARCHY_DESCENDANTS_AGGREGATE(
                  SOURCE HIERARCHY( SOURCE ydj_i_cost_centre_src
                                    CHILD TO PARENT ASSOCIATION _parent
                                    START WHERE parent_cc = @gc_no_parent
                                    SIBLINGS ORDER BY cost_centre ) AS h
                  JOIN @lt_actuals AS a
                    ON a~cost_centre = h~cost_centre
                  MEASURES SUM( a~amount )  AS actual_sum,
                           COUNT( DISTINCT h~cost_centre ) AS node_count
                  WHERE hierarchy_level <= @lv_level
                  WITH SUBTOTAL
                  WITH BALANCE )
           FIELDS cost_centre,
                  actual_sum,
                  node_count,
                  hierarchy_level,
                  hierarchy_aggregate_type
           INTO TABLE @DATA(lt_rollup).

    " Note what is NOT selectable above: a~amount. A joined data
    " source contributes to MEASURES only - its columns "are not part
    " of the tabular result" and cannot appear after WHERE either.
    " Adding JOIN also withdraws AVG and COUNT( * ) from MEASURES.

    DATA lv_nodes     TYPE i.
    DATA lv_subtotal  TYPE i.
    DATA lv_balance   TYPE i.

    LOOP AT lt_rollup ASSIGNING FIELD-SYMBOL(<ls_agg>).

      " hierarchy_aggregate_type: 0 = real node, 1 = SUBTOTAL,
      " 2 = BALANCE, 3 = NOT MATCHED, 4 = TOTAL. The WITH rows are
      " rows of NULLS apart from the measures and this flag, so they
      " arrive with a BLANK key and a real amount. Without this
      " branch they get reported, or summed, as if they were nodes.
      CASE <ls_agg>-hierarchy_aggregate_type.
        WHEN 0.
          lv_nodes = lv_nodes + 1.
        WHEN 1.
          lv_subtotal = lv_subtotal + 1.
        WHEN 2.
          lv_balance = lv_balance + 1.
        WHEN OTHERS.
          " 3 and 4 are not requested by this statement.
      ENDCASE.

    ENDLOOP.

    DATA(lv_rollup_rows) = lines( lt_rollup ).
    WRITE: / 'Roll-up rows total        :', lv_rollup_rows.
    WRITE: / '  real nodes (type 0)     :', lv_nodes.
    WRITE: / '  SUBTOTAL rows (type 1)  :', lv_subtotal.
    WRITE: / '  BALANCE  rows (type 2)  :', lv_balance.
    WRITE: / '  Each node total covers its WHOLE subtree, not only'.
    WRITE: / '  the levels the WHERE let through.'.

  ENDMETHOD.


  METHOD demo_cte_hierarchy.

    " ---------------------------------------------------------------
    " 8. A CTE exposed as a hierarchy, then navigated.
    " ---------------------------------------------------------------
    " WITH HIERARCHY promotes a CTE to a real SQL hierarchy. Two
    " constraints worth remembering: the subquery may read exactly one
    " data source and it must be an SQL hierarchy, and its SELECT list
    " "must not contain any columns with the same name or alias name
    " as a hierarchy column".
    "
    " Navigators consume hierarchies but never produce them - a
    " navigator cannot be a navigator's source, and cannot be exposed
    " as a CTE hierarchy.

    WITH
      +tree AS ( SELECT FROM HIERARCHY(
                                SOURCE ydj_i_cost_centre_src
                                CHILD TO PARENT ASSOCIATION _parent
                                START WHERE parent_cc = @gc_no_parent
                                SIBLINGS ORDER BY cost_centre )
                                  AS gen_hierarchy
                        FIELDS cost_centre,
                               parent_cc,
                               cc_name )
                 WITH HIERARCHY gen_hierarchy
      SELECT FROM HIERARCHY_DESCENDANTS(
                    SOURCE +tree
                    START WHERE hierarchy_parent_rank = 0
                    DISTANCE FROM 1 )
             FIELDS cost_centre,
                    cc_name,
                    hierarchy_distance,
                    hierarchy_level
             ORDER BY hierarchy_rank
             INTO TABLE @DATA(lt_cte).

    " START WHERE hierarchy_parent_rank = 0 selects every root as a
    " start node - the alias after HIERARCHY( ... ) is mandatory here,
    " because WITH HIERARCHY must name it.

    DATA(lv_cte_rows) = lines( lt_cte ).
    WRITE: / 'CTE hierarchy, below all roots - rows:', lv_cte_rows.

  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  lcl_hierarchy_demo=>run( ).
