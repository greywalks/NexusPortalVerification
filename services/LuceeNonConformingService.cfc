component extends="services.NonConformingService" output=false {
    function init(required string datasource, required string outputPath, required any excelService) {
        variables.datasource = arguments.datasource;
        variables.outputPath = arguments.outputPath;
        variables.excel = arguments.excelService;
        variables.editableFields = ["ticket_no","model","serial","ra_no","tracking","carrier","address","status","ussi_resolution","addtl_info","origin_company","store_no","rack","bin"];
        variables.requiredFields = ["model","serial","carrier"];
        super.init();
        return this;
    }

    string function buildExport(required array rows) {
        var filename="SMS_NonConforming_"&dateFormat(now(),"yyyymmdd")&"_"&timeFormat(now(),"HHmmss")&"_"&left(replace(createUUID(),"-","","all"),6)&".xlsx";
        var data=[];
        for(var item in arguments.rows){
            arrayAppend(data,{
                "Date Added":item.date_added?:"",
                "Number":item.number?:"",
                "Ticket No.":item.ticket_no?:"",
                "Model No.":item.model?:"",
                "Serial No.":item.serial?:"",
                "RA No.":item.ra_no?:"",
                "Tracking":item.tracking?:"",
                "Carrier":item.carrier?:"",
                "Address":item.address?:"",
                "Status":item.status?:"",
                "USSI Resolution Confirmation":item.ussi_resolution?:"",
                "Addtl Info":item.addtl_info?:"",
                "Origin Company":item.origin_company?:"",
                "Store No.":item.store_no?:"",
                "Rack":item.rack?:"",
                "Bin":item.bin?:"",
                "Filed By":item.filed_by_username?:""
            });
        }
        variables.excel.writeWorkbook(variables.outputPath&filename,[{
            name:"NonConforming",
            headers:["Date Added","Number","Ticket No.","Model No.","Serial No.","RA No.","Tracking","Carrier","Address","Status","USSI Resolution Confirmation","Addtl Info","Origin Company","Store No.","Rack","Bin","Filed By"],
            rows:data
        }]);
        return filename;
    }
}
