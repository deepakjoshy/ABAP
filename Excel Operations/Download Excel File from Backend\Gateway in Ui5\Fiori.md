### Extract and Download Excel File in Fiori/Ui5 from Backend/Gateway




- Create an entity in the backend odata project and mark media type checked


- Redefine the method '/IWBEP/IF_MGW_APPL_SRV_RUNTIME~GET_STREAM' in DPC_EXT Class
Sample Code
      METHOD /iwbep/if_mgw_appl_srv_runtime~get_stream.
    
        DATA : ls_stream     TYPE ty_s_media_resource,
               ls_upld       TYPE ydj_file_poc,
               lv_filename   TYPE char30,
               lt_table_data TYPE TABLE OF ydj_i_recon_hierarchy_poc.
    
        FIELD-SYMBOLS:<fs_key> TYPE /iwbep/s_mgw_name_value_pair,
                      <tab>    TYPE STANDARD TABLE.
    
        SELECT * FROM Ztable INTO TABLE @lt_table_data.
    
        DATA(lt_data) = REF #( lt_table_data ).
        ASSIGN lt_data->* TO <tab>.
    
        TRY.
            cl_salv_table=>factory(
            EXPORTING
              list_display = abap_false
            IMPORTING
              r_salv_table = DATA(salv_table)
            CHANGING
              t_table      = lt_table_data ).
    
            DATA(lt_fcat) = cl_salv_controller_metadata=>get_lvc_fieldcatalog(
                                     r_columns      = salv_table->get_columns( )
                                     r_aggregations = salv_table->get_aggregations( ) ).
          CATCH cx_salv_msg.
            RETURN.
        ENDTRY.
    
        cl_salv_bs_lex=>export_from_result_data_table(
            EXPORTING
              is_format            = if_salv_bs_lex_format=>mc_format_xlsx
              ir_result_data_table =  cl_salv_ex_util=>factory_result_data_table(
                                                      r_data                      = lt_data
                                                      t_fieldcatalog              = lt_fcat   )
            IMPORTING
              er_result_file       = DATA(r_xstring) ).
        
		
		    ls_stream-value = r_xstring.
 		    ls_stream-mime_type = 'application/msexcel'. 
        copy_data_to_ref( EXPORTING is_data = ls_stream   CHANGING  cr_data = er_stream ). 
    
        DATA : ls_lheader     TYPE ihttpnvp.
        ls_lheader-name = 'Content-Disposition'.
        ls_lheader-value = |inline; filename="Sample_Report.xlsx"|.
        set_header( is_header = ls_lheader ).
    
      ENDMETHOD.




###### Frontend Ui5/Fiori Code 

On click of download to excel button

```javascript
	onCustomButtonAction: function (oEvent) {
		var sUrl = "/sap/opu/odata/sap/ZSERVICE/FileSet(Filename='test')/$value";
		var encodeUrl = encodeURI(sUrl);
		sap.m.URLHelper.redirect(encodeUrl, true);
	}
```
