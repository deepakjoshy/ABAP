*&---------------------------------------------------------------------*
*& ydj_rap_det_val_patterns.abap
*& Companion to README.md in this folder.
*&
*& THIS FILE IS NOT A RUNNABLE REPORT.
*& A determination or validation cannot exist outside a business object:
*& it is declared in a behavior definition (BDEF, a CDS object) and
*& implemented in a local class of an ABAP behavior pool (ABP). There is
*& no START-OF-SELECTION to put it in.
*&
*& What this file is: the two halves, side by side, as a copy-paste
*& skeleton.
*&   Part 1 - the BDEF, in a comment block (it is not ABAP source).
*&   Part 2 - the handler class, as it appears in the CCIMP include of
*&            the behavior pool.
*&
*& To use it, substitute your own names:
*&   ydj_c_salesorder  -> your BDEF / CDS root view entity
*&   SalesOrder        -> your root entity alias
*&   ZDJ_SALES         -> your message class
*& The nested components of failed / reported / mapped are named after
*& the entity (failed-salesorder below) - lower case, one per entity in
*& the BO. Check the derived type of your own BDEF with F2 in ADT rather
*& than copying the name from here.
*&
*& Deliberately absent, because the documentation forbids them in a
*& behavior pool (README section 5): COMMIT / ROLLBACK of any kind,
*& MESSAGE without INTO, WRITE, RAISE EXCEPTION, SUBMIT, AUTHORITY-CHECK
*& in an on-save object, and any EML MODIFY inside the validation.
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& PART 1 - the behavior definition
*&---------------------------------------------------------------------*
* managed implementation in class ydj_bp_salesorder unique;
* strict ( 2 );
*
* define behavior for YDJ_C_SALESORDER alias SalesOrder
* persistent table ydj_sales_order
* lock master
* authorization master ( global )
* {
*   create;
*   update;
*   delete;
*
*   field ( readonly, numbering : managed ) SoKey;
*   field ( readonly )                      DueDate;
*
*   " Administrative fields written by the framework itself: fencing them
*   " off stops anyone triggering logic from its own side effects.
*   field ( notrigger : warn ) LastChangedAt, CreatedAt;
*
*   " on modify: runs right after the buffer changes, so the result is
*   " visible during the transaction. Triggered by the fields it READS -
*   " both of them belong to THIS entity, which is a hard requirement.
*   determination calcDueDate on modify { field OrderDate, PaymentTerms; }
*
*   " on save: runs inside finalize - the last point data may change.
*   determination setID on save { create; }
*
*   " create AND update. 'update' on its own is not dependable:
*   " "Update works only in combination with the trigger operation create."
*   validation validateBuyer on save { create; update; }
* }
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& PART 2 - the handler class (CCIMP include of the behavior pool)
*&---------------------------------------------------------------------*
CLASS lhc_salesorder DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS calc_due_date FOR DETERMINE ON MODIFY
      IMPORTING keys FOR SalesOrder~calcDueDate.

    METHODS set_id FOR DETERMINE ON SAVE
      IMPORTING keys FOR SalesOrder~setID.

    METHODS validate_buyer FOR VALIDATE ON SAVE
      IMPORTING keys FOR SalesOrder~validateBuyer.

    " A determination has no 'failed' parameter, so it cannot reject
    " anything. The documented workaround is to record the negative
    " result and let a validation turn it into a failed entry. Note the
    " second half of the rule: a later run of the same determination may
    " find the data correct, and must then REMOVE its own marker, or the
    " validation rejects an instance that is no longer wrong.
    TYPES: BEGIN OF ty_problem,
             sokey  TYPE ydj_sales_order-sokey,
             reason TYPE string,
           END OF ty_problem.

    CLASS-DATA gt_problems TYPE HASHED TABLE OF ty_problem
                           WITH UNIQUE KEY sokey.

ENDCLASS.

CLASS lhc_salesorder IMPLEMENTATION.

  METHOD calc_due_date.
*   on modify. An EML MODIFY is allowed here (and in an on save
*   determination); it is NOT allowed in a validation.

*   IN LOCAL MODE switches off feature and authorization control, which
*   is what you want for a read the BO is performing on itself.
    READ ENTITIES OF ydj_c_salesorder IN LOCAL MODE
      ENTITY SalesOrder
        FIELDS ( OrderDate PaymentTerms DueDate )
        WITH CORRESPONDING #( keys )
        RESULT DATA(lt_orders)
        FAILED DATA(ls_read_failed).

*   An instance created and deleted in the same request may already be
*   gone: "it can happen that an EML read operation in a determination
*   defined as on modify fails as instances with the given key cannot be
*   found." So a read failure is expected input here, not an anomaly -
*   and there is nowhere to forward it to, because a determination has no
*   failed parameter. Skipping is the only option.
*   Note that FAILED is a STRUCTURE with one table per entity, not a
*   table - hence the component.
    IF lines( ls_read_failed-salesorder ) = lines( keys ).
      RETURN.
    ENDIF.

*   The alias is usable here because this is a handler method: "An alias,
*   however, only works within handler methods of a RAP BO provider."
*   Outside an implementation class, spell out ydj_c_salesorder.
    DATA lt_update TYPE TABLE FOR UPDATE SalesOrder.

    LOOP AT lt_orders INTO DATA(ls_order).
      IF ls_order-OrderDate IS INITIAL.
*       Nothing to compute from. A determination cannot reject, so the
*       problem is parked for the validation to pick up (see above).
        INSERT VALUE #( sokey  = ls_order-SoKey
                        reason = `Order date missing` ) INTO TABLE gt_problems.
        CONTINUE.
      ENDIF.

*     The marker from an earlier run has to go when the input is fixed.
      DELETE gt_problems WHERE sokey = ls_order-SoKey.

      DATA(lv_due) = CONV d( ls_order-OrderDate + ls_order-PaymentTerms ).

*     Idempotence: "The determination result must not change if the
*     determination is executed several times under the same conditions."
*     Writing only on an actual change keeps repeated runs free of
*     side effects - and avoids re-triggering anything downstream.
      IF ls_order-DueDate = lv_due.
        CONTINUE.
      ENDIF.

      APPEND VALUE #( %tky    = ls_order-%tky
                      DueDate = lv_due ) TO lt_update.
    ENDLOOP.

    IF lt_update IS INITIAL.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ydj_c_salesorder IN LOCAL MODE
      ENTITY SalesOrder
        UPDATE FIELDS ( DueDate )
        WITH lt_update
      REPORTED DATA(ls_reported).

    reported = CORRESPONDING #( DEEP ls_reported ).
  ENDMETHOD.

  METHOD set_id.
*   on save: this body runs inside the finalize saver method, which the
*   development guide calls "the last option to change data on the
*   transactional buffer". After it, an EML modify request is a runtime
*   error - so nothing from check_before_save onwards can patch data.
*
*   Do NOT notify anything from here: at this point the save has not been
*   decided. A validation may still reject the whole buffer.

    READ ENTITIES OF ydj_c_salesorder IN LOCAL MODE
      ENTITY SalesOrder
        FIELDS ( SalesOrderId )
        WITH CORRESPONDING #( keys )
        RESULT DATA(lt_orders).

    DATA lt_stamp TYPE TABLE FOR UPDATE SalesOrder.

    LOOP AT lt_orders INTO DATA(ls_order).
*     Skipping the already-filled case rather than overwriting it is
*     what makes a second execution a no-op.
      IF ls_order-SalesOrderId IS NOT INITIAL.
        CONTINUE.
      ENDIF.

*     A real semantic ID comes from a number range object, not from the
*     technical key - see ../Number Ranges for the buffering and gap
*     behaviour that choice brings with it.
      APPEND VALUE #( %tky         = ls_order-%tky
                      SalesOrderId = |{ ls_order-SoKey }| )
             TO lt_stamp.
    ENDLOOP.

    IF lt_stamp IS INITIAL.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF ydj_c_salesorder IN LOCAL MODE
      ENTITY SalesOrder
        UPDATE FIELDS ( SalesOrderId )
        WITH lt_stamp
      REPORTED DATA(ls_reported).

    reported = CORRESPONDING #( DEEP ls_reported ).
  ENDMETHOD.

  METHOD validate_buyer.
*   on save: this body runs inside check_before_save. Read only.
*   No EML MODIFY, no AUTHORITY-CHECK, no MESSAGE, no RAISE EXCEPTION.
*   The entire output channel is failed + reported.

    READ ENTITIES OF ydj_c_salesorder IN LOCAL MODE
      ENTITY SalesOrder
        FIELDS ( BuyerId )
        WITH CORRESPONDING #( keys )
        RESULT DATA(lt_orders)
        FAILED DATA(ls_read_failed).

    failed = CORRESPONDING #( DEEP ls_read_failed ).

    IF lt_orders IS INITIAL.
      RETURN.
    ENDIF.

*   FOR ALL ENTRIES with an empty driver table reads the WHOLE table -
*   see ../For All Entries. The guard above is that check, not tidiness.
    SELECT FROM ydj_buyer
      FIELDS id
      FOR ALL ENTRIES IN @lt_orders
      WHERE id = @lt_orders-BuyerId
      INTO TABLE @DATA(lt_known).

    LOOP AT lt_orders INTO DATA(ls_order).

      DATA(lv_reason) = ``.

      IF ls_order-BuyerId IS INITIAL.
        lv_reason = `Buyer is mandatory`.
      ELSEIF NOT line_exists( lt_known[ id = ls_order-BuyerId ] ).
        lv_reason = `Buyer does not exist`.
      ELSEIF line_exists( gt_problems[ sokey = ls_order-SoKey ] ).
*       Picking up what the determination could not reject by itself.
        lv_reason = gt_problems[ sokey = ls_order-SoKey ]-reason.
      ENDIF.

      IF lv_reason IS INITIAL.
        CONTINUE.
      ENDIF.

*     The key of the offending instance. One entry here rejects the
*     ENTIRE transactional buffer, not just this instance - and the
*     buffer is not emptied afterwards, so the consumer must correct it
*     or issue ROLLBACK ENTITIES before the next change.
      APPEND VALUE #( %tky = ls_order-%tky ) TO failed-salesorder.

*     new_message( ) is inherited from cl_abap_behavior_handler. This is
*     the only legal way to say something from in here.
      APPEND VALUE #(
        %tky             = ls_order-%tky
        %state_area      = 'VALIDATE_BUYER'
        %msg             = new_message(
                             id       = 'ZDJ_SALES'
                             number   = '001'
                             severity = if_abap_behv_message=>severity-error
                             v1       = ls_order-BuyerId
                             v2       = lv_reason )
        %element-BuyerId = if_abap_behv=>mk-on
      ) TO reported-salesorder.

    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
