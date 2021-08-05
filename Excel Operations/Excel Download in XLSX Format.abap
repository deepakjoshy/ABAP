    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = DATA(lo_table)
          CHANGING  t_table      = it_input_table ).
  
        DATA(lt_fcat) = cl_salv_controller_metadata=>get_lvc_fieldcatalog(
                        r_columns      = lo_table->get_columns( )
                        r_aggregations = lo_table->get_aggregations( ) ).

        DATA(lo_result) = cl_salv_ex_util=>factory_result_data_table( 
                          r_data         = ir_data_ref
                          t_fieldcatalog = lt_fcat ).

        cl_salv_bs_tt_util=>if_salv_bs_tt_util~transform(
                                                          EXPORTING
                                                            xml_type      = if_salv_bs_xml=>c_type_xlsx
                                                            xml_version   = cl_salv_bs_a_xml_base=>get_version( )
                                                            r_result_data = lo_result
                                                            xml_flavour   = if_salv_bs_c_tt=>c_tt_xml_flavour_export
                                                            gui_type      = if_salv_bs_xml=>c_gui_type_gui
                                                          IMPORTING
                                                            xml           = rv_xstring ).
      CATCH cx_root.
        CLEAR rv_xstring.
    ENDTRY.
