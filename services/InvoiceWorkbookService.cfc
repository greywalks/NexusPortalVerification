component output=false {
    function init(required string rootPath,required any excel,required any config){variables.layouts=rootPath&"template/layouts/";variables.excel=excel;variables.config=config;return this;}

    void function amc(required string path,required struct a,required string title,required struct totals){
        var p=variables.config.getAmcPrices();var received=[];var shipped=[];
        for(var r in a.receiving)arrayAppend(received,{Model:v(r,"Model"),Serial:v(r,"Serial Number"),"Receive Date":dateValue(v(r,"Received Date")),Charge:p.unit_receipt});
        for(var r in a.shipping)arrayAppend(shipped,{"Shipped Date":dateValue(v(r,"Shipped Date")),"Ticket ##":v(r,"Ticket Number"),Model:v(r,"Model"),"Serial Number":v(r,"Serial Number"),"Tracking Number":v(r,"Tracking Number"),"Return Tracking":v(r,"Return Tracking"),"Order Fee":p.order_fee,"Out Fee":p.order_out_fee});
        var cells={A5:title,C8:p.unit_receipt,C9:p.storage_base,C10:p.storage_addl,C12:p.order_fee,C13:p.order_out_fee,D9:1,D10:a.additional_sqft};
        cells.D8=f("COUNTA(Received!C2:C1048576)",a.receipt_count);cells.D12=f("COUNTA(Shipped!A2:A1048576)",a.ship_count);cells.D13=duplicate(cells.D12);
        for(var row in [8,9,10,12,13])cells["E"&row]=f("C"&row&"*D"&row,(isStruct(cells["D"&row])?cells["D"&row].value:cells["D"&row])*cells["C"&row]);
        totalsCells(cells,15,totals,"SUM(E8:E14)");
        variables.excel.fillTemplate(variables.layouts&"AMC.xlsx",path,{Breakdown:cells},[
            {name:"Received",headers:["Model","Serial","Receive Date","Charge"],rows:received},
            {name:"Shipped",headers:["Shipped Date","Ticket ##","Model","Serial Number","Tracking Number","Return Tracking","Order Fee","Out Fee"],rows:shipped},
            excluded(a.excluded,["Source Tab","Reason","Model","Serial","Rack","Bin"])
        ]);
    }

    void function philips(required string path,required struct a,required string title,required struct totals){
        var received=mapRows(a.received,["Model","Serial","Column1","Warehouse","Date","RMA","Price"],["Model","Serial","Grade","Warehouse","Date","RMA",6]);
        var shipped=mapRows(a.shipping,["Date","Type","Departure RMA","Ship to Name","Tracking","Carrier","Model","Price"],["Date","Stock Level (Primary)","Departure RMA","Ship to Name","Departure Tracking","Carrier","Model",6]);
        var repairs=mapRows(a.repairs,["Repair Date","Receive Date","Model","Serial","RMA","Repaired/Harvested","Repaired Y/N","Diagnostics","Parts Used","Price"],["Repair Date","Received Date","Model","Serial","RMA","Status","","Diagnostics","Parts Used","Price"]);
        for(var r in repairs)r["Repaired Y/N"]=r["Repaired/Harvested"]=="Repaired"?"Yes":"No";
        var cells={A5:title,D8:1,D9:nearest50(a.demo_additional_sqft),D12:nearest50(a.service_additional_sqft),D19:nearest50(a.parts_sqft_manual)};
        cells.D15=f("COUNTA(Receieved!A2:A100000)",a.inbound_count);cells.D16=f("COUNTA(Shipping!G2:G100000)",a.outbound_count);
        cells.D22=f('COUNTIFS(Repairs!F:F,"Repaired")',a.repair_count);cells.E22=f('SUMIFS(Repairs!J:J,Repairs!F:F,"Repaired")',a.repair_total);
        cells.D23=f('COUNTIFS(Repairs!F:F,"Harvested")',a.harvest_count);cells.E23=f('SUMIFS(Repairs!J:J,Repairs!F:F,"Harvested")',a.harvest_total);
        totalsCells(cells,25,totals,"SUM(E8:E24)");
        variables.excel.fillTemplate(variables.layouts&"Philips.xlsx",path,{Breakdown:cells},[
            {name:"Receieved",headers:["Model","Serial","Column1","Warehouse","Date","RMA","Price"],rows:received},
            {name:"Shipping",headers:["Date","Type","Departure RMA","Ship to Name","Tracking","Carrier","Model","Price"],rows:shipped},
            {name:"Repairs",headers:["Repair Date","Receive Date","Model","Serial","RMA","Repaired/Harvested","Repaired Y/N","Diagnostics","Parts Used","Price"],rows:repairs},
            excluded(a.excluded,["Source Tab","Reason","Model","Serial","Type","Detail"])
        ]);
    }

    void function storage(required string path,required struct a,required struct totals){
        var p=variables.config.getStoragePrices().line_prices;var cells=metadata(a._meta?:{});
        cells.C10=p.unit_storage;cells.C11=p.pallet_storage;cells.C14=p.unit_receipt;cells.C16=p.unit_pick;cells.C17=p.small_part_pick;cells.D11=a.pallet_count;
        cells.D10=f("COUNTA('Unit Storage'!B:B)-1",arrayLen(a.unit_storage));cells.D14=f("COUNTA('Unit Receiving'!B:B)-1",arrayLen(a.units_received));cells.D15=f("COUNTA('Small Parts Check In'!B:B)-1",arrayLen(a.auto_spc_rows));
        var smallTotal=0;for(var r in a.auto_spc_rows)smallTotal+=r.Price?:0;
        cells.E15=f('SUMIF(''Small Parts Check In''!D:D,">0",''Small Parts Check In''!D:D)',smallTotal);
        cells.D16=f("COUNTA('Units Shipped'!B:B)-1",a.unit_picks_count);cells.D17=f("SUM('Part Testing & Programming'!G:G)",a.small_part_picks);totalsCells(cells,31,totals,"SUM(E8:E30)");
        var received=mapRows(a.units_received,["Actual Model","Actual Serial","Receipt Fee"],["Model","Serial Number",p.unit_receipt]);
        var shipped=mapRows(a.ship_month,["MSO","Pickup Date","Model","Serial","Tracking","Sales Order Number","Out Fee"],["Ticket Number","Pickup Date","Model","Serial Number","Tracking Number","Sales Order Number",p.unit_pick]);
        var unmatched={name:"Unmatched Parts & Units",rows:a.unmatched};
        if(!arrayLen(a.unmatched)){unmatched.headers=["No unmatched items this period."];}
        variables.excel.fillTemplate(variables.layouts&"Storage.xlsx",path,{Breakdown:cells},[
            {name:"Unit Storage",headers:["ActualModel","Actual Serial","Storage"],rows:a.unit_storage},
            {name:"Unit Receiving",headers:["Actual Model","Actual Serial","Receipt Fee"],rows:received},
            {name:"Units Shipped",headers:["MSO","Pickup Date","Model","Serial","Tracking","Sales Order Number","Out Fee"],rows:shipped},
            partSheet(a.programming),{name:"Small Parts Check In",headers:["Checkin Date","ID","Part ##","Price"],rows:a.auto_spc_rows},unmatched
        ]);
    }

    void function workshop(required string path,required struct a,required array depot,required array triage,required array programming,required array excludedRows,required struct totals){
        var cells=metadata(a._meta?:{});var prices=variables.config.getStoragePrices().part_type_prices;
        var types=["PSU","Mainboard Configure for Dispatch","Mainboard","AC-PCA","Keypad","Maintouch","EXT-INPUT","OPS-PCA","USB","SPEAKER"];
        for(var i=1;i<=arrayLen(types);i++)cells["C"&(33+i)]=prices[types[i]]?:0;
        totalsCells(cells,45,totals,"SUM(E11:E43)");
        arraySort(depot,function(x,y){return compareNoCase(x.Type&"|"&x.Size&"|"&x.Model,y.Type&"|"&y.Size&"|"&y.Model);});
        arraySort(triage,function(x,y){return compareNoCase(x["Derived Type"]&"|"&x.Model,y["Derived Type"]&"|"&y.Model);});
        variables.excel.fillTemplate(variables.layouts&"Workshop.xlsx",path,{Breakdown:cells},[
            {name:"Depot Repair",headers:["Model","Serial","Type","Size","Repair Cost","Parts Summary"],rows:depot},
            {name:"Triage Units",headers:["Model","Serial","Triage","Derived Type","Size","Cost"],rows:triage},partSheet(programming),
            {name:"Excluded Serials",headers:["Model","Serial","Source Tab","Category","Result","Original Date","Reason"],rows:excludedRows,emptyMessage:"No serials were excluded this run."}
        ]);
    }

    void function tcl(required string path,required struct a,required struct breakdowns,required array lines,required numeric palletRate,required struct totals){
        var meta=a._meta?:{};var count=arrayLen(lines);var cells={H3:meta.invoice_number?:"",G3:dateValue(meta.invoice_date?:dateFormat(now(),"yyyy-mm-dd")),C12:dateValue(meta.due_date?:""),A12:meta.po_number?:"Contract",B12:meta.terms?:"Net 30",A6:meta.bill_to?:"TTE Technology Inc"&chr(10)&"189 Technology Dr."&chr(10)&"Irvine, CA 92618"};
        cells.F6=meta.ship_to?:cells.A6;cells.A15=meta.period_label?:dateFormat(a.period_end?:now(),"mmm yyyy")&"***";
        for(var i=1;i<=count;i++){var row=15+i;cells["A"&row]=lines[i].description;cells["G"&row]=lines[i].quantity;cells["H"&row]=lines[i].unit_price;cells["I"&row]=f("H"&row&"*G"&row,lines[i].unit_price*lines[i].quantity);}
        var last=max(16,15+count);var tr=last+8;cells["I"&tr]=f("SUM(I16:I"&last&")",totals.subtotal);cells["I"&(tr+1)]=f("I"&tr&"*0.07",totals.tax);cells["I"&(tr+2)]=f("I"&tr&"+I"&(tr+1),totals.total);
        var rows=[];var pallet=0;
        for(var g in a.unit_groups){var idx=1;for(var n in breakdowns.unit[g.key]){pallet++;for(var j=1;j<=n;j++){if(idx>arrayLen(g.rows))break;var r=g.rows[idx++];arrayAppend(rows,{"Line Item":"FGI TV Inventory (in pallet)",Model:v(r,"Model"),Serial:v(r,"Serial Number"),"Quantity in Box":1,"Receive Date":dateValue(v(r,"Received Date")),"Pallet Number":pallet,Charge:j==n?palletRate:0});}}}
        for(var g in a.part_groups){var idx=1;for(var n in breakdowns.box[g.key]){var label=n==1?"Serialized In Fee (1 part)":n<=5?"2-5 Parts in Box":n<=10?"6-10 Parts in Box":n<=15?"11-15 Parts in Box":"16-20 Parts in Box";var price=n<=5?3.85:n<=10?7.7:n<=15?11.55:15;var date=idx<=arrayLen(g.rows)?dateValue(v(g.rows[idx],"Received Date")):"";idx+=n;arrayAppend(rows,{"Line Item":n==1?"TV Part A-Grade Serialized Inventory (Single Part)":"TV Part A-Grade Inventory ("&label&")",Model:g.model,Serial:"N/A","Quantity in Box":n,"Receive Date":date,"Pallet Number":"N/A",Charge:price});}}
        variables.excel.fillTemplate(variables.layouts&"TCL_"&count&".xlsx",path,{Invoice:cells},[{name:"Line Items",headers:["Line Item","Model","Serial","Quantity in Box","Receive Date","Pallet Number","Charge"],rows:rows}]);
    }

    private struct function partSheet(required array rows){return {name:"Part Testing & Programming",headers:["MSO","Request Date","Outbound Tracking","Part ##","Type","Serial","Quantity","Individual Part Fee","Total Programming Fee","Part Pick Fee"],rows:rows};}
    private struct function excluded(required array rows,required array headers){return {name:"Excluded Items",headers:headers,rows:rows,emptyMessage:"No excluded items this period."};}
    private struct function metadata(required struct meta){return {E1:meta.call_id?:"",E3:dateValue(meta.invoice_date?:""),E4:dateValue(meta.completed_date?:""),E5:meta.customer?:""};}
    private struct function f(required string formula,required numeric value){return {formula:formula,value:value};}
    private void function totalsCells(required struct cells,required numeric row,required struct totals,required string subtotalFormula){cells["E"&row]=f(subtotalFormula,totals.subtotal);cells["E"&(row+1)]=f("E"&row&"*7%",totals.tax);cells["E"&(row+2)]=f("SUM(E"&row&":E"&(row+1)&")",totals.total);}
    private any function v(required struct r,required string key){return structKeyExists(r,key)?r[key]:"";}
    private array function mapRows(required array rows,required array headers,required array sources){var out=[];for(var r in rows){var item={};for(var i=1;i<=arrayLen(headers);i++){var key=sources[i];item[headers[i]]=isNumeric(key)?key:v(r,key);}arrayAppend(out,item);}return out;}
    private any function dateValue(any value=""){if(isInstanceOf(value,"java.util.Date"))return value;if(isDate(value))return parseDateTime(value);return value;}
    private numeric function nearest50(required numeric n){return createObject("java","java.lang.Math").rint(n/50.0)*50;}
}
