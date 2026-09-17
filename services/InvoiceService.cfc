component output=false {
    function init(required string rootPath,required string uploadPath,required string outputPath,required any configService,required any outputService,required any excelService){
        variables.rootPath=arguments.rootPath;variables.uploadPath=arguments.uploadPath;variables.outputPath=arguments.outputPath;variables.config=arguments.configService;variables.outputs=arguments.outputService;variables.excel=arguments.excelService;
        variables.taxRate=0.07;
        variables.workbooks=new services.InvoiceWorkbookService(arguments.rootPath,arguments.excelService,arguments.configService);
        return this;
    }

    // ---------------------------------------------------------------------
    // AMC
    // ---------------------------------------------------------------------
    struct function analyzeAMC(required string receivingPath,required string shippingPath,required string inventoryPath,required any dateFrom,required any dateTo){
        var start=asDate(arguments.dateFrom);var finish=asDate(arguments.dateTo);var dims=variables.config.getAmcDimensions();var prices=variables.config.getAmcPrices();
        var recv=variables.excel.readSheet(arguments.receivingPath,"Receiving Export");var ship=variables.excel.readSheet(arguments.shippingPath,"Shipping Export");var inv=variables.excel.readSheet(arguments.inventoryPath,"Inventory Export");
        var recvPeriod=[];for(var r in recv){var d=asDateSafe(value(r,"Received Date"));if(!isNull(d)&&d>=start&&d<=finish)arrayAppend(recvPeriod,r);}
        var shipPeriod=[];for(var r in ship){var d=asDateSafe(value(r,"Shipped Date"));if(!isNull(d)&&d>=start&&d<=finish)arrayAppend(shipPeriod,r);}
        var seen={};var invDedup=[];var excluded=[];var missing={};var totalSqft=0;
        for(var r in inv){var serial=trim(value(r,"Serial Number")&"");if(len(serial)&&structKeyExists(seen,serial))continue;if(len(serial))seen[serial]=true;arrayAppend(invDedup,r);var model=uCase(trim(value(r,"Model")&""));if(len(model)&&structKeyExists(dims,model)){totalSqft+=val(dims[model]);}else{if(len(model))missing[model]=true;arrayAppend(excluded,{"Source Tab":"Inventory","Reason":"No Dimensions match","Model":model,"Serial":serial,"Rack":value(r,"Rack"),"Bin":value(r,"Bin")});}}
        var additional=nearest50(max(totalSqft-val(prices.base_sqft),0));
        return {receiving:recvPeriod,shipping:shipPeriod,inventory:invDedup,receipt_count:arrayLen(recvPeriod),ship_count:arrayLen(shipPeriod),total_sqft:totalSqft,base_sqft:val(prices.base_sqft),additional_sqft:additional,missing_dimension_models:sortedKeys(missing),excluded:excluded,period_start:dateFormat(start,"yyyy-mm-dd"),period_end:dateFormat(finish,"yyyy-mm-dd")};
    }

    struct function buildAMC(required struct a,string invoiceTitle="AMC Warehouse Invoice",string filename=""){
        var p=variables.config.getAmcPrices();var subtotal=a.receipt_count*p.unit_receipt+p.storage_base+a.additional_sqft*p.storage_addl+a.ship_count*p.order_fee+a.ship_count*p.order_out_fee;var tax=roundMoney(subtotal*variables.taxRate);var total=roundMoney(subtotal+tax);
        var lines=[
            {description:"Unit Receipt & Processing",uom:"Each",unit_price:p.unit_receipt,quantity:a.receipt_count},
            {description:"Storage First 500sq Ft.",uom:"Each",unit_price:p.storage_base,quantity:1},
            {description:"Storage Addition Sq Ft (50ft Increments)",uom:"Each",unit_price:p.storage_addl,quantity:a.additional_sqft},
            {description:"Order Fee",uom:"Each",unit_price:p.order_fee,quantity:a.ship_count},
            {description:"Order Out Fee",uom:"Each",unit_price:p.order_out_fee,quantity:a.ship_count}
        ];
        var name=safeFilename(arguments.filename,"AMC_Warehouse_Invoice")&".xlsx";var path=variables.outputPath&name;
        variables.workbooks.amc(path,a,arguments.invoiceTitle,{subtotal:subtotal,tax:tax,total:total});variables.outputs.register(name,"amc");
        return {filename:name,receipt_count:a.receipt_count,ship_count:a.ship_count,total_sqft:roundMoney(a.total_sqft),additional_sqft:a.additional_sqft,subtotal:roundMoney(subtotal),tax:tax,total:total};
    }

    // ---------------------------------------------------------------------
    // Philips
    // ---------------------------------------------------------------------
    struct function analyzePhilips(required string reportPath,numeric partsSqft=0){
        var dims=variables.config.getPhilipsDimensions();var tiers=compileRepairTiers(variables.config.getPhilipsRepairCost());
        var inv=variables.excel.readSheet(arguments.reportPath,"Inventory");var ship=variables.excel.readSheet(arguments.reportPath,"Shipping");var recv=variables.excel.readSheet(arguments.reportPath,"Recieved");var repairs=variables.excel.readSheet(arguments.reportPath,"Repairs");
        var invSums={Demo:0,Service:0};var shipSums={Demo:0,Service:0};var excluded=[];var missing={};
        for(var r in inv){var typ=trim(value(r,"Type")&"");if(!len(typ))continue;var sqft="";if(structKeyExists(r,"Size")&&isNumeric(r.Size))sqft=val(r.Size);if(!isNumeric(sqft))sqft=lookupDimension(value(r,"Model"),dims,true);if(!isNull(sqft)&&isNumeric(sqft)){if(structKeyExists(invSums,typ))invSums[typ]+=sqft;}else{var m=trim(value(r,"Model")&"");if(len(m))missing[m]=true;arrayAppend(excluded,{"Source Tab":"Inventory","Reason":"No Size / no Dimensions match","Model":m,"Serial":value(r,"Serial"),"Type":typ,"Detail":""});}}
        var cleanShip=[];for(var r in ship){var typ=trim(value(r,"Stock Level (Primary)")&"");if(!len(typ))continue;arrayAppend(cleanShip,r);var sqft=lookupDimension(value(r,"Model"),dims,true);if(!isNull(sqft)&&isNumeric(sqft)){if(structKeyExists(shipSums,typ))shipSums[typ]+=sqft;}else{var m=trim(value(r,"Model")&"");if(len(m))missing[m]=true;arrayAppend(excluded,{"Source Tab":"Shipping","Reason":"No Dimensions match","Model":m,"Serial":value(r,"Serial"),"Type":typ,"Detail":""});}}
        var demoTotal=invSums.Demo+shipSums.Demo;var serviceTotal=invSums.Service+shipSums.Service;var credits=splitPhilipsCredit(demoTotal,serviceTotal);
        var inbound=0;for(var r in recv)if(len(trim(value(r,"Model")&"")))inbound++;
        var outbound=0;for(var r in cleanShip)if(len(trim(value(r,"Model")&"")))outbound++;
        var repaired=0;var harvested=0;var repairTotal=0;var harvestTotal=0;var cleanRep=[];var missingRepair={};
        for(var r in repairs){var status=trim(value(r,"Status")&"");var price=repairPrice(value(r,"Model"),status,tiers);if(isNull(price)){price=0;var m=trim(value(r,"Model")&"");if(len(m))missingRepair[m]=true;arrayAppend(excluded,{"Source Tab":"Repairs","Reason":"No display size parsed from model","Model":m,"Serial":value(r,"Serial"),"Type":status,"Detail":""});}r["Price"]=price;arrayAppend(cleanRep,r);if(status=="Repaired"){repaired++;repairTotal+=price;}else if(status=="Harvested"){harvested++;harvestTotal+=price;}}
        return {inventory:inv,shipping:cleanShip,received:recv,repairs:cleanRep,demo_total_sqft:demoTotal,demo_additional_sqft:max(demoTotal-credits.demo,0),service_total_sqft:serviceTotal,service_additional_sqft:max(serviceTotal-credits.service,0),parts_sqft_manual:arguments.partsSqft,inbound_count:inbound,outbound_count:outbound,repair_count:repaired,repair_total:repairTotal,harvest_count:harvested,harvest_total:harvestTotal,report_path:arguments.reportPath,missing_dimension_models:sortedKeys(missing),missing_repair_models:sortedKeys(missingRepair),excluded:excluded};
    }

    struct function buildPhilips(required struct a,string invoiceTitle="TPV Philips Warehouse Invoice",string filename=""){
        var p=variables.config.getPhilipsPrices();var demo=nearest50(a.demo_additional_sqft);var service=nearest50(a.service_additional_sqft);var parts=nearest50(a.parts_sqft_manual);var subtotal=p.warehouse_base+demo*p.demo_addl_sqft+service*p.service_addl_sqft+a.inbound_count*p.inbound_handling+a.outbound_count*p.outbound_handling+parts*p.parts_addl_sqft+a.repair_total+a.harvest_total;var tax=roundMoney(subtotal*variables.taxRate);var total=roundMoney(subtotal+tax);
        var lines=[{description:"Warehouse Cost, First 500 sq. ft.",uom:"Each",unit_price:p.warehouse_base,quantity:1},{description:"Demo Additional Square Footage, in 50 sq ft. increments",uom:"Each",unit_price:p.demo_addl_sqft,quantity:demo},{description:"Service Additional Square Footage, in 50 sq ft. increments",uom:"Each",unit_price:p.service_addl_sqft,quantity:service},{description:"Inbound Handling",uom:"Each",unit_price:p.inbound_handling,quantity:a.inbound_count},{description:"Outbound Handling",uom:"Each",unit_price:p.outbound_handling,quantity:a.outbound_count},{description:"Parts Additional Square Footage",uom:"Each",unit_price:p.parts_addl_sqft,quantity:parts},{description:"Repair",uom:"Unit Size/Each",unit_price:1,quantity:a.repair_total,total:a.repair_total},{description:"Harvest",uom:"Each",unit_price:1,quantity:a.harvest_total,total:a.harvest_total}];
        var name=safeFilename(arguments.filename,"TPV_Philips_Warehouse_Invoice")&".xlsx";var path=variables.outputPath&name;variables.workbooks.philips(path,a,arguments.invoiceTitle,{subtotal:subtotal,tax:tax,total:total},p);variables.outputs.register(name,"philips");
        return {filename:name,demo_total_sqft:roundMoney(a.demo_total_sqft),service_total_sqft:roundMoney(a.service_total_sqft),demo_additional_sqft:demo,service_additional_sqft:service,inbound_count:a.inbound_count,outbound_count:a.outbound_count,repair_count:a.repair_count,harvest_count:a.harvest_count,subtotal:roundMoney(subtotal),tax:tax,total:total};
    }

    // ---------------------------------------------------------------------
    // TCL
    // ---------------------------------------------------------------------
    struct function analyzeTCL(required string inventoryPath,required any dateFrom,required any dateTo){
        var rows=variables.excel.readFirstSheet(arguments.inventoryPath);var start=asDate(arguments.dateFrom);var finish=asDate(arguments.dateTo);var unitMap={};var partMap={};var unitCount=0;var partCount=0;
        for(var r in rows){for(var req in ["Model","Serial Number","Grade","Rack","Bin","Received Date"])if(!structKeyExists(r,req))throw(type="Logicore.Validation",message="Inventory file is missing expected column '#req#'.");var d=asDateSafe(value(r,"Received Date"));var isUnit=uCase(trim(value(r,"Rack")&""))=="MAIN"||uCase(trim(value(r,"Bin")&""))=="RCV";if(isUnit){unitCount++;if(isNull(d))continue;var key="unit::"&(isNull(d)?"unknown":dateFormat(d,"yyyy-mm-dd"));if(!structKeyExists(unitMap,key))unitMap[key]={key:key,received_date:isNull(d)?"":dateFormat(d,"yyyy-mm-dd"),quantity:0,rows:[]};unitMap[key].quantity++;arrayAppend(unitMap[key].rows,r);}else if(!isNull(d)&&d>=start&&d<=finish){partCount++;var model=value(r,"Model")&"";var grade=value(r,"Grade")&"";if(!len(model)||!len(grade))continue;var key="part::"&model&"::"&grade&"::"&dateFormat(d,"yyyy-mm-dd");if(!structKeyExists(partMap,key))partMap[key]={key:key,model:model,grade:grade,received_date:dateFormat(d,"yyyy-mm-dd"),quantity:0,rows:[]};partMap[key].quantity++;arrayAppend(partMap[key].rows,r);}}
        return {unit_groups=structValuesSorted(unitMap,"received_date"),part_groups=structValuesSorted(partMap,"received_date"),period_start=dateFormat(start,"yyyy-mm-dd"),period_end=dateFormat(finish,"yyyy-mm-dd"),unit_count=unitCount,part_count=partCount};
    }

    struct function validateTCL(required struct a,required struct unitBreakdowns,required struct boxBreakdowns){var errors=[];var pu={};var pb={};for(var g in a.unit_groups){try{var nums=parseBreakdown(unitBreakdowns[g.key]?:"");if(arraySum(nums)!=g.quantity)arrayAppend(errors,"Unit batch #g.received_date#: pallet breakdown sums to #arraySum(nums)#, expected #g.quantity#");else pu[g.key]=nums;}catch(any e){arrayAppend(errors,"Unit batch #g.received_date# (#g.quantity# units): #e.message#");}}for(var g in a.part_groups){try{var nums=parseBreakdown(boxBreakdowns[g.key]?:"");if(arraySum(nums)!=g.quantity)arrayAppend(errors,"Part group #g.model# / #g.received_date#: box breakdown sums to #arraySum(nums)#, expected #g.quantity#");else{var bad=[];for(var n in nums)if(n<1||n>20)arrayAppend(bad,n);if(arrayLen(bad))arrayAppend(errors,"Part group #g.model#: box sizes must be 1-20");else pb[g.key]=nums;}}catch(any e){arrayAppend(errors,"Part group #g.model#: #e.message#");}}return {errors:errors,unit:pu,box:pb};}

    struct function buildTCL(required struct a,required struct unitBreakdowns,required struct boxBreakdowns,string filename=""){
        var valid=validateTCL(a,unitBreakdowns,boxBreakdowns);if(arrayLen(valid.errors))throw(type="Logicore.Validation",message=arrayToList(valid.errors," | "));
        var tp=variables.config.getTclPrices();var pallets=0;for(var k in valid.unit)pallets+=arrayLen(valid.unit[k]);var palletRate=pallets<=tp.pallet_threshold?tp.pallet_rate_small:tp.pallet_rate_large;var tierCounts={"Serialized In Fee (1 part)":0,"2-5 Parts in Box":0,"6-10 Parts in Box":0,"11-15 Parts in Box":0,"16-20 Parts in Box":0};var tierRates={"Serialized In Fee (1 part)":tp.box_1,"2-5 Parts in Box":tp.box_2_5,"6-10 Parts in Box":tp.box_6_10,"11-15 Parts in Box":tp.box_11_15,"16-20 Parts in Box":tp.box_16_20};var boxCount=0;
        for(var k in valid.box)for(var n in valid.box[k]){boxCount++;var label=n==1?"Serialized In Fee (1 part)":n<=5?"2-5 Parts in Box":n<=10?"6-10 Parts in Box":n<=15?"11-15 Parts in Box":"16-20 Parts in Box";tierCounts[label]++;}
        var lines=[];if(pallets)arrayAppend(lines,{description:"FGI TV Inventory (in pallet)",uom:"Each",unit_price:palletRate,quantity:pallets});for(var label in tierCounts)if(tierCounts[label])arrayAppend(lines,{description:(left(label,10)=="Serialized"?"TV Part A-Grade Serialized Inventory (Single Part)":"TV Part A-Grade Inventory (#label#)"),uom:"Each",unit_price:tierRates[label],quantity:tierCounts[label]});var subtotal=0;for(var l in lines)subtotal+=l.unit_price*l.quantity;var tax=roundMoney(subtotal*variables.taxRate);var total=roundMoney(subtotal+tax);var name=safeFilename(arguments.filename,"TCL_Warehouse_Invoice")&".xlsx";variables.workbooks.tcl(variables.outputPath&name,a,valid,lines,palletRate,{subtotal:subtotal,tax:tax,total:total},tierRates);variables.outputs.register(name,"tcl");return {filename:name,total_pallets:pallets,pallet_rate:palletRate,box_count:boxCount,line_count:arrayLen(lines),subtotal:roundMoney(subtotal),tax:tax,total:total};
    }

    // ---------------------------------------------------------------------
    // Promethean FedEx shipment upload
    // ---------------------------------------------------------------------
    struct function analyzeFedexShipment(required string rawPath,required string periodLabel,required any callDate){
        var cfg=fedexDefaults();var headers=variables.excel.headers(arguments.rawPath);for(var h in ["Express or Ground Tracking ID","Net Charge Amount","Payor","Recipient Company","Recipient Name","Recipient Address Line 1","Recipient Address Line 2","Recipient City","Recipient State","Recipient Zip Code","Original Customer Reference","Original Ref##3/PO Number"])if(!arrayFind(headers,h))throw(type="Logicore.Validation",message="Raw FedEx file is missing expected column: "&h);var rows=variables.excel.readFirstSheet(arguments.rawPath);var out=[];var defaultsUsed=[];var skipped=[];var seen={};var total=0;var rowNum=1;
        for(var r in rows){rowNum++;var tid=trim(value(r,"Express or Ground Tracking ID")&"");var netRaw=trim(value(r,"Net Charge Amount")&"");if(!len(tid)){arrayAppend(skipped,{row:rowNum,reason:"No tracking ID"});continue;}if(!isNumeric(netRaw)||val(netRaw)==0){arrayAppend(skipped,{row:rowNum,tracking:tid,reason:"No Net Charge Amount"});continue;}if(structKeyExists(seen,tid)){arrayAppend(skipped,{row:rowNum,tracking:tid,reason:"Duplicate tracking ID — already billed once this run"});continue;}seen[tid]=true;var company=trim(value(r,"Recipient Company")&"");var person=trim(value(r,"Recipient Name")&"");var used=!len(company)&&!len(person);var po=trim(value(r,"Original Customer Reference")&"");if(!len(po))po=trim(value(r,"Original Ref##3/PO Number")&"");var price=floor((val(netRaw)/val(cfg.margin_divisor))*100)/100;var built={SiteID:"",SiteName:used?cfg.site_name:canonical(value(r,"Recipient Company"),cfg.site_name),OrgID:cfg.org_id,CustomerID:cfg.customer_id,Address:used?cfg.address:fallbackCanonical(value(r,"Recipient Address Line 1"),cfg.address),Address2:used?cfg.address2:canonical(value(r,"Recipient Address Line 2"),cfg.address2),City:used?cfg.city:fallbackCanonical(value(r,"Recipient City"),cfg.city),State:used?cfg.state:fallbackCanonical(value(r,"Recipient State"),cfg.state),ZipCode:used?cfg.zip_code:cleanZip(value(r,"Recipient Zip Code"),cfg.zip_code),MainContact:used?cfg.main_contact:canonical(value(r,"Recipient Name"),cfg.main_contact),BillCustomerID:cfg.bill_customer_id,CustomerPO:po,CallType:cfg.call_type,CallRcvd:asDate(arguments.callDate),CallRcvdTime:(hour(parseDateTime(cfg.call_rcvd_time))*3600+minute(parseDateTime(cfg.call_rcvd_time))*60+second(parseDateTime(cfg.call_rcvd_time)))/86400,Status:cfg.status,QueueID:cfg.queue_id,DUE:cfg.due,"Due By Date":asDate(arguments.callDate),Summary:arguments.periodLabel&" FedEx Invoices - "&tid,Tech:cfg.tech,Event1:cfg.event1_code,Event1Price:price};arrayAppend(out,built);total+=price;if(used)arrayAppend(defaultsUsed,{tracking:tid,po:po});}
        return {rows:out,defaulted_rows:defaultsUsed,skipped_rows:skipped,total_price:roundMoney(total),period_label:arguments.periodLabel,call_date:dateFormat(asDate(arguments.callDate),"yyyy-mm-dd")};
    }

    struct function buildFedexShipment(required struct a,string filename=""){
        var headers=["SiteID","SiteName","OrgID","CustomerID","Address","Address2","City","State","ZipCode","MainContact","BillCustomerID","CustomerPO","CallType","CallRcvd","CallRcvdTime","Status","QueueID","DUE","Due By Date","Summary","Tech","Event1","Event1Price"];var name=safeFilename(arguments.filename,"FedEx_Shipment_Upload")&".xlsx";variables.excel.fillTemplate(variables.rootPath&"template/FedEx_Shipment_Upload_Template.xlsx",variables.outputPath&name,{},[{name:"_uploadsheet",headers:variables.excel.headers(variables.rootPath&"template/FedEx_Shipment_Upload_Template.xlsx"),rows:a.rows,formats:{CallRcvdTime:"hh:mm:ss",CallRcvd:"mm-dd-yy","Due By Date":"mm-dd-yy"}}]);variables.outputs.register(name,"promethean");return {filename:name,row_count:arrayLen(a.rows),total_price:a.total_price,defaulted_count:arrayLen(a.defaulted_rows),skipped_count:arrayLen(a.skipped_rows)};
    }

    // ---------------------------------------------------------------------
    // Promethean Storage & Small Parts
    // ---------------------------------------------------------------------
    struct function analyzeStorage(required string inventoryCsv,required string shippingCsv,required string receiptCsv,required string fedexPath,required numeric palletCount,required any dateFrom,required any dateTo,string whitelistPath=""){
        var prices=variables.config.getStoragePrices();var wl=loadWhitelist(arguments.whitelistPath);var start=createDate(year(asDate(arguments.dateFrom)),month(asDate(arguments.dateFrom)),1);var finish=asDate(arguments.dateTo);var inv=readCsv(arguments.inventoryCsv);var ship=readCsv(arguments.shippingCsv);var receipt=readCsv(arguments.receiptCsv);var invSerials={};var unitStorage=[];
        for(var r in inv)if(lCase(trim(value(r,"Item Type")&""))=="unit"){var serial=cleanCsv(value(r,"Serial Number"));if(!len(serial)||structKeyExists(invSerials,serial))continue;invSerials[serial]=true;arrayAppend(unitStorage,{ActualModel:cleanCsv(value(r,"Model")),"Actual Serial":serial,Storage:prices.line_prices.unit_storage});}
        var shipPeriod=[];var shipSeen={};for(var r in ship){var d=asDateSafe(cleanCsv(value(r,"Pickup Date")));var serial=cleanCsv(value(r,"Serial Number"));if(isNull(d)||d<start||d>finish||!len(serial)||structKeyExists(shipSeen,serial))continue;shipSeen[serial]=true;arrayAppend(shipPeriod,r);if(!structKeyExists(invSerials,serial))arrayAppend(unitStorage,{ActualModel:cleanCsv(value(r,"Model")),"Actual Serial":serial,Storage:prices.line_prices.unit_storage});}
        var unitsReceived=[];var autoSpc=[];var unmatched=[];for(var r in receipt){var d=asDateSafe(cleanCsv(value(r,"Received Date")));if(isNull(d)||d<start||d>finish)continue;var type=lCase(trim(cleanCsv(value(r,"Item Type"))));var model=uCase(trim(cleanCsv(value(r,"Model"))));var serial=trim(cleanCsv(value(r,"Serial Number")));if(type=="unit"){arrayAppend(unitsReceived,r);if(!structKeyExists(wl.units,model))arrayAppend(unmatched,tagRow(r,"Non-Whitelist Unit"));}else if(!len(type)){var onWL=structKeyExists(wl.parts,model);var validRma=reFindNoCase("^M[0-9]{8}$",serial)>0;if(onWL&&validRma)arrayAppend(autoSpc,{"Checkin Date":d,ID:serial,"Part ##":model,Price:prices.line_prices.small_part_checkin});else arrayAppend(unmatched,tagRow(r,onWL?"WL Part – No Valid RMA":"Non-Whitelist Part"));}}
        var fed=analyzeStorageFedex(arguments.fedexPath,start,finish,prices.part_type_prices,prices.line_prices.small_part_pick);
        return {unit_storage:unitStorage,units_received:unitsReceived,programming:fed.programming,part_type_totals:fed.part_type_totals,ship_month:shipPeriod,period_start:dateFormat(start,"yyyy-mm-dd"),period_end:dateFormat(finish,"yyyy-mm-dd"),unit_picks_count:arrayLen(shipPeriod),small_part_picks:fed.small_part_picks,pallet_count:arguments.palletCount,auto_spc_rows:autoSpc,unmatched:unmatched};
    }

    struct function buildStorage(required struct a,string filename="",array includeUnmatched=[]){
        var prices=variables.config.getStoragePrices();var spc=duplicate(a.auto_spc_rows);
        // Manually included unmatched rows are identified by their position (1-based)
        // in the analysis' unmatched list or by their serial/ID; the row content and
        // the price always come from the server-side analysis and configuration, never
        // from the request.
        var unmatched=a.unmatched?:[];
        for(var pick in arguments.includeUnmatched){var src={};if(isNumeric(pick)&&val(pick)>=1&&val(pick)<=arrayLen(unmatched))src=unmatched[int(val(pick))];else{var wanted=isStruct(pick)?trim((pick.ID?:pick.id?:pick.serial?:pick["Serial Number"]?:"")&""):trim(pick&"");if(len(wanted))for(var u in unmatched){if(compareNoCase(trim(cleanCsv(value(u,"Serial Number"))),wanted)==0){src=u;break;}}}if(!structCount(src))throw(type="Logicore.Validation",message="Unmatched row '"&(isSimpleValue(pick)?pick:"")&"' is not part of the current Storage analysis.");var serial=trim(cleanCsv(value(src,"Serial Number")));var model=uCase(trim(cleanCsv(value(src,"Model"))));var d=asDateSafe(cleanCsv(value(src,"Received Date")));arrayAppend(spc,{"Checkin Date":isNull(d)?"":d,ID:serial,"Part ##":model,Price:prices.line_prices.small_part_checkin});}
        var smallTotal=0;for(var sp in spc)smallTotal+=val(sp.Price?:0);var subtotal=arrayLen(a.unit_storage)*prices.line_prices.unit_storage+a.pallet_count*prices.line_prices.pallet_storage+arrayLen(a.units_received)*prices.line_prices.unit_receipt+a.unit_picks_count*prices.line_prices.unit_pick+a.small_part_picks*prices.line_prices.small_part_pick+smallTotal;var tax=roundMoney(subtotal*.07);var total=roundMoney(subtotal+tax);var lines=[{description:"Unit Storage",uom:"Each",unit_price:prices.line_prices.unit_storage,quantity:arrayLen(a.unit_storage)},{description:"Pallet Storage",uom:"Each",unit_price:prices.line_prices.pallet_storage,quantity:a.pallet_count},{description:"Unit Receipt",uom:"Each",unit_price:prices.line_prices.unit_receipt,quantity:arrayLen(a.units_received)},{description:"Small Part Check In",uom:"Each",unit_price:prices.line_prices.small_part_checkin,quantity:arrayLen(spc)},{description:"Unit Pick",uom:"Each",unit_price:prices.line_prices.unit_pick,quantity:a.unit_picks_count},{description:"Small Part Pick",uom:"Each",unit_price:prices.line_prices.small_part_pick,quantity:a.small_part_picks}];var name=safeFilename(arguments.filename,"Promethean_Storage_Invoice")&".xlsx";var workbookAnalysis=duplicate(a);workbookAnalysis.auto_spc_rows=spc;variables.workbooks.storage(variables.outputPath&name,workbookAnalysis,{subtotal:subtotal,tax:tax,total:total});variables.outputs.register(name,"promethean");return {filename:name,unit_storage_count:arrayLen(a.unit_storage),pallet_count:a.pallet_count,units_received_count:arrayLen(a.units_received),small_parts_count:arrayLen(spc),unit_picks_count:a.unit_picks_count,small_part_picks:a.small_part_picks,subtotal:roundMoney(subtotal),tax:tax,total:total};
    }

    // ---------------------------------------------------------------------
    // Promethean Workshop sanitizer + billing
    // ---------------------------------------------------------------------
    struct function analyzeWorkshop(required string rawPath,required any dateFrom,required any dateTo){
        var rows=variables.excel.readSheet(arguments.rawPath,"Repair Data");var start=asDate(arguments.dateFrom);var finish=asDate(arguments.dateTo);var rules=variables.config.getSerialRules().rules ?: [];var clean=[];var all=[];var issues=[];var autos=[];var idx=0;
        for(var r in rows){var d=asDateSafe(value(r,"Date Integer"));if(isNull(d)||d<start||d>finish)continue;var item=duplicate(r);item.row_index=idx;var derived=serialModelSize(value(r,"Actual Serial"),rules);item._derived_model=derived.model;item._derived_size=derived.size;item._clean_model=len(derived.model)?derived.model:cleanModel(value(r,"Actual Model"));var rawSize=lCase(trim(value(r,"Derive Size")&""));var size=normalizePanelSize(rawSize);if(len(derived.size))size=derived.size;if(!len(size))size=sizeFromModel(item._clean_model);item._size=size;item.Size=size=="86"?"Large":listFindNoCase("55,65,70,75",size)?"Small":"";item._Type=deriveWorkshopType(value(r,"Category"));item._Type2=workshopType2(value(r,"Result"),value(r,"Category"));item.Type=item._Type;item.Type2=item._Type2;item["Actual Model"]=item._clean_model;var hasIssue=false;
            if(!len(size)){arrayAppend(issues,issue(item,"unresolved_size","Cannot determine panel size from serial '#value(r,"Actual Serial")#' or model '#value(r,"Actual Model")#'","Derive Size",value(r,"Derive Size"),["65","70","75","86","EXCLUDE"]));hasIssue=true;}
            else if(reFind("^[0-9]{1,5}$",trim(value(r,"Actual Serial")&""))){arrayAppend(issues,issue(item,"suspect_serial","Serial '#value(r,"Actual Serial")#' looks invalid","Actual Serial",value(r,"Actual Serial"),[]));hasIssue=true;}
            else if(!len(item._Type)){arrayAppend(issues,issue(item,"unknown_category","Unknown category '#value(r,"Category")#'","Category",value(r,"Category"),["Refurbished","Pending Parts","Scrap","EXCLUDE"]));hasIssue=true;}
            if(len(derived.model)&&derived.model!=(value(r,"Actual Model")&"") || (len(size)&&!listFindNoCase("55,65,70,75,86",rawSize))){arrayAppend(autos,{row_index:idx,"Actual Model":value(r,"Actual Model"),"Actual Serial":value(r,"Actual Serial"),Date:dateFormat(d,"yyyy-mm-dd"),Result:value(r,"Result"),Category:value(r,"Category"),old_model:value(r,"Actual Model"),new_model:len(derived.model)?derived.model:value(r,"Actual Model"),old_size:rawSize,new_size:size,model_changed:(len(derived.model)&&derived.model!=(value(r,"Actual Model")&"")),size_changed:(len(size)&&!listFindNoCase("55,65,70,75,86",rawSize))});}
            arrayAppend(all,item);if(!hasIssue&&listFindNoCase("55,65,70,75,86",size)&&len(item._Type))arrayAppend(clean,item);idx++;}
        return {rows:all,clean:clean,issues:issues,auto_corrections:autos,total_records:arrayLen(all),issue_count:arrayLen(issues),auto_count:arrayLen(autos),raw_path:arguments.rawPath};
    }

    struct function analyzeWorkshopLegacy(required string repairPath,required string masterPath,required string shippingPath,required any dateFrom,required any dateTo,struct meta={}){
        var start=asDate(dateFrom);var finish=asDate(dateTo);var rows=[];var idx=0;
        for(var source in variables.excel.readFirstSheet(repairPath)){
            var d=asDateSafe(value(source,"Date Integer"));if(isNull(d)||d<start||d>finish)continue;
            for(var requiredColumn in ["Type","Type2","Derive Size"]){if(!structKeyExists(source,requiredColumn))throw(type="Logicore.Validation",message="Pre-sanitized Repair Data is missing expected column '#requiredColumn#'.");}
            var r=duplicate(source);r.row_index=idx++;r._Type=value(r,"Type");r._Type2=value(r,"Type2");r._size=trim(value(r,"Derive Size")&"");r.Size=r._size=="86"?"Large":"Small";r._exclude=false;
            if(!len(trim(value(r,"Actual Model")&""))||!len(trim(value(r,"Actual Serial")&"")))throw(type="Logicore.Validation",message="Pre-sanitized Repair Data requires Actual Model and Actual Serial values.");
            arrayAppend(rows,r);
        }
        return {rows:rows,clean:rows,issues:[],auto_corrections:[],total_records:arrayLen(rows),issue_count:0,auto_count:0,master_path:masterPath,shipping_path:shippingPath,date_from:dateFormat(start,"yyyy-mm-dd"),date_to:dateFormat(finish,"yyyy-mm-dd"),raw_path:"",fedex_path:"",_meta:meta,skip_companions:true};
    }

    struct function buildWorkshop(required struct a,struct corrections={},string filename=""){
        var rows=[];var corrected=duplicate(a.rows);var unresolved={};var issueText={};for(var iss in a.issues){unresolved[iss.row_index&""]=true;issueText[iss.row_index&""]=iss.description?:iss.issue_type;}
        // Corrections are checked up front. A value that cannot be applied used to
        // drop the row from the invoice without any trace; now the request is
        // rejected and the user is told which rows to fix.
        var problems=[];
        for(var key in arguments.corrections){var corr=arguments.corrections[key];var field=isStruct(corr)?trim(corr.field?:""):"";var valx=trim((isStruct(corr)?corr.value?:"":corr)&"");if(!len(valx))continue;if(valx=="EXCLUDE")continue;if(field=="Derive Size"&&!listFind("55,65,70,75,86",valx))arrayAppend(problems,"Row "&key&": panel size must be 55, 65, 70, 75, 86 or EXCLUDE (got '"&valx&"').");else if(field=="Category"&&!len(deriveWorkshopType(valx)))arrayAppend(problems,"Row "&key&": category '"&valx&"' is not Refurbished, Pending Parts or Scrap.");else if(field=="Actual Serial"&&reFind("^[0-9]{1,5}$",valx))arrayAppend(problems,"Row "&key&": serial '"&valx&"' still looks invalid.");else if(!listFindNoCase("Derive Size,Category,Actual Serial",field))arrayAppend(problems,"Row "&key&": corrections for '"&field&"' are not supported.");}
        if(arrayLen(problems))throw(type="Logicore.Validation",message="Some corrections could not be applied: "&arrayToList(problems," "));
        var dropped=[];
        for(var i=1;i<=arrayLen(corrected);i++){var r=corrected[i];var key=r.row_index&"";if(structKeyExists(arguments.corrections,key)){var corr=arguments.corrections[key];var field=isStruct(corr)?corr.field?:"":"";var valx=trim((isStruct(corr)?corr.value?:"":corr)&"");if(valx=="EXCLUDE"){r._exclude=true;structDelete(unresolved,key);}else if(!len(valx)){/* blank correction: issue stays unresolved */}else if(field=="Derive Size"){r["Derive Size"]=valx;r._size=valx;r.Size=valx=="86"?"Large":"Small";structDelete(unresolved,key);}else if(field=="Category"){r.Category=valx;r._Type=deriveWorkshopType(valx);r.Type=r._Type;r._Type2=workshopType2(value(r,"Result"),valx);r.Type2=r._Type2;structDelete(unresolved,key);}else if(field=="Actual Serial"){r["Actual Serial"]=valx;var dm=serialModelSize(valx,variables.config.getSerialRules().rules?:[]);if(len(dm.model)){r["Actual Model"]=dm.model;r._clean_model=dm.model;}if(len(dm.size)){r._size=dm.size;r.Size=dm.size=="86"?"Large":"Small";}structDelete(unresolved,key);}}
            corrected[i]=r;
            var reason="";
            if(r._exclude?:false)reason="Excluded by user during review.";
            else if(structKeyExists(unresolved,key))reason="Issue not resolved during review: "&(issueText[key]?:"");
            else if(!listFindNoCase("55,65,70,75,86",r._size?:""))reason="Panel size '"&(r._size?:"")&"' is not billable.";
            else if(!len(r._Type?:""))reason="Category '"&value(r,"Category")&"' does not map to a Workshop tab.";
            if(len(reason))arrayAppend(dropped,{"Model":value(r,"Actual Model"),"Serial":value(r,"Actual Serial"),"Source Tab":(r._Type?:"")=="Triage Tab"?"Triage Units":"Depot Repair","Category":value(r,"Category"),"Result":value(r,"Result"),"Original Date":value(r,"Date Integer"),"Reason":reason});
            else arrayAppend(rows,r);
        }
        var excluded=[];
        if(len(a.master_path?:"")){var dedup=deduplicateWorkshop(rows,a.master_path,a.shipping_path,a.date_from);rows=dedup.rows;excluded=dedup.excluded;}
        // Rows removed during review are reported alongside the dedup exclusions so nothing leaves the invoice silently.
        for(var d in dropped)arrayAppend(excluded,d);
        var counts={};var subtotal=0;
        for(var r in rows){var previous=r.was_prev_triaged?:false;var price=workshopPrice(r._Type,r._Type2,r.Size,previous);r["Unit Price"]=price;var ck=r._Type&"|"&r._Type2&"|"&r.Size&"|"&(previous?"1":"0");counts[ck]=(counts[ck]?:0)+1;subtotal+=price;}
        var lines=[];for(var key in counts){var bits=listToArray(key,"|");var price=workshopPrice(bits[1],bits[2],bits[3],bits[4]=="1");arrayAppend(lines,{description:bits[1]&" - "&bits[2]&" - "&bits[3]&(bits[4]=="1"?" - Previously Triaged":""),uom:"Each",unit_price:price,quantity:counts[key]});}
        var programming=[];
        if(len(a.fedex_path?:"")){var p=variables.config.getStoragePrices();var start=asDate(a.date_from);var fed=analyzeStorageFedex(a.fedex_path,createDate(year(start),month(start),1),asDate(a.date_to),p.part_type_prices,p.line_prices.small_part_pick);programming=fed.programming;for(var typ in fed.part_type_totals){var fee=p.part_type_prices[typ]?:0;subtotal+=fee*fed.part_type_totals[typ];arrayAppend(lines,{description:"Parts Testing & Configuration - "&typ,uom:"Each",unit_price:fee,quantity:fed.part_type_totals[typ]});}}
        var tax=roundMoney(subtotal*.07);var total=roundMoney(subtotal+tax);var base=safeFilename(arguments.filename,"Promethean_Workshop_Invoice");var name=base&".xlsx";
        var depot=[];var triage=[];
        for(var r in rows){if(r._Type=="Depot Repair Tab")arrayAppend(depot,{"Model":value(r,"Actual Model"),"Serial":value(r,"Actual Serial"),"Type":depotType(r),"Size":r.Size,"Repair Cost":r["Unit Price"],"Parts Summary":normalizeResult(value(r,"Result"))});else arrayAppend(triage,{"Model":value(r,"Actual Model"),"Serial":value(r,"Actual Serial"),"Triage":normalizeResult(value(r,"Result")),"Derived Type":r._Type2&r.Size&"-Triage","Size":r.Size,"Cost":r["Unit Price"]});}
        variables.workbooks.workshop(variables.outputPath&name,a,depot,triage,programming,excluded,{subtotal:subtotal,tax:tax,total:total});
        variables.outputs.register(name,"promethean");var result={filename:name,depot_count:arrayLen(depot),triage_count:arrayLen(triage),excluded_count:arrayLen(excluded),subtotal:roundMoney(subtotal),tax:tax,total:total};if(!(a.skip_companions?:false))structAppend(result,workshopCompanions(a,corrected,rows,base));return result;
    }

    // ---------------------------------------------------------------------
    // Use the complete historical master for discount eligibility; only earlier
    // periods participate in duplicate exclusion, matching Python apply_dedup.
    struct function deduplicateWorkshop(required array rows, required string masterPath, required string shippingPath, required any billingStart){
        var repair=variables.excel.readSheet(arguments.masterPath,"Repair Log");
        var triage=variables.excel.readSheet(arguments.masterPath,"Triage Log");
        var priorRepair={};var priorTriage={};var allTriage={};var shipped={};
        var cutoff=asDate(arguments.billingStart);
        for(var r in repair){var d=asDateSafe(value(r,"Month"));var sn=value(r,"Serial")&"";if(!isNull(d)&&d<cutoff&&(!structKeyExists(priorRepair,sn)||d>priorRepair[sn]))priorRepair[sn]=d;}
        for(var r in triage){var d=asDateSafe(value(r,"Date"));var sn=value(r,"Serial")&"";allTriage[sn]=true;if(!isNull(d)&&d<cutoff&&(!structKeyExists(priorTriage,sn)||d>priorTriage[sn]))priorTriage[sn]=d;}
        for(var r in readCsv(arguments.shippingPath)){var d=asDateSafe(value(r,"Shipped Date"));var sn=value(r,"Serial Number")&"";if(!isNull(d)&&(!structKeyExists(shipped,sn)||d>shipped[sn]))shipped[sn]=d;}
        var included=[];var excluded=[];
        for(var r in arguments.rows){
            var sn=value(r,"Actual Serial")&"";var prev="";
            if(structKeyExists(priorRepair,sn))prev=priorRepair[sn];
            if(structKeyExists(priorTriage,sn)&&(!isDate(prev)||priorTriage[sn]>prev))prev=priorTriage[sn];
            var triageOnly=structKeyExists(priorTriage,sn)&&!structKeyExists(priorRepair,sn)&&r._Type=="Depot Repair Tab";
            var isDuplicate=isDate(prev)&&!triageOnly&&(!structKeyExists(shipped,sn)||shipped[sn]<=prev);
            if(isDuplicate){
                var reason="Previously invoiced on "&dateFormat(prev,"yyyy-mm-dd")&"; ";
                reason&=structKeyExists(shipped,sn)?"last shipped on "&dateFormat(shipped[sn],"yyyy-mm-dd")&", which was not after the prior invoice.":"no later shipment was found, so the serial was not billed again.";
                arrayAppend(excluded,{"Model":value(r,"Actual Model"),"Serial":sn,"Source Tab":r._Type=="Depot Repair Tab"?"Depot Repair":"Triage Units","Category":value(r,"Category"),"Result":value(r,"Result"),"Original Date":value(r,"Date Integer"),"Reason":reason});
            }else{
                r.was_prev_triaged=r._Type=="Depot Repair Tab"&&structKeyExists(allTriage,sn);
                r["Unit Price"]=workshopPrice(r._Type,r._Type2,r.Size,r.was_prev_triaged);
                arrayAppend(included,r);
            }
        }
        return {rows:included,excluded:excluded,repair_history:repair,triage_history:triage};
    }

    private string function depotType(required struct r){
        if(r._Type2=="Salvage of Hardware and Scrap")return r._Type2;
        return (r.was_prev_triaged?:false)?r._Type2&r.Size&" - Previously Triaged":r._Type2;
    }

    private struct function workshopCompanions(required struct a,required array corrected,required array billed,required string base){
        var result={};
        if(len(a.raw_path?:"")){
            var name=arguments.base&"_Corrected_Production.xlsx";var rows=[];
            for(var r in corrected)arrayAppend(rows,{"Date":value(r,"Date Integer"),"Clean Model":value(r,"Actual Model"),"Serial":value(r,"Actual Serial"),"Type":r._Type?:"","Type2":r._Type2?:"","Result":value(r,"Result"),"Category":value(r,"Category"),"Size":r.Size?:"","Raw Size":value(r,"Derive Size"),"Notes":(r._exclude?:false)?"Excluded by user":(r._notes?:"")});
            variables.excel.replaceSheets(a.raw_path,variables.outputPath&name,[{name:"Sanitized Data",headers:["Date","Clean Model","Serial","Type","Type2","Result","Category","Size","Raw Size","Notes"],rows:rows}]);
            variables.outputs.register(name,"promethean");result.corrected_filename=name;
        }
        if(len(a.master_path?:"")){
            var repairs=variables.excel.readSheet(a.master_path,"Repair Log");var triage=variables.excel.readSheet(a.master_path,"Triage Log");var date=asDate(a.date_from);var month=createDate(year(date),month(date),1);
            for(var r in billed){if(r._Type=="Depot Repair Tab")arrayAppend(repairs,{Month:month,Model:value(r,"Actual Model"),Serial:value(r,"Actual Serial"),Type:depotType(r)});else arrayAppend(triage,{Date:month,Model:value(r,"Actual Model"),Serial:value(r,"Actual Serial"),Type:"Triage - "&r._Type2});}
            var name=arguments.base&"_Updated_Master.xlsx";
            variables.excel.replaceSheets(a.master_path,variables.outputPath&name,[{name:"Repair Log",headers:["Month","Model","Serial","Type"],rows:repairs},{name:"Triage Log",headers:["Date","Model","Serial","Type"],rows:triage}]);
            variables.outputs.register(name,"promethean");result.master_filename=name;
        }
        return result;
    }

    // Helper functions
    // ---------------------------------------------------------------------
    private struct function fedexDefaults(){var d={margin_divisor:.85,event1_code:"PMTH-SHIP",site_name:"UNITED SERVICE SOURCE",org_id:"Promethean",customer_id:"Promethean",address:"7195 WAELTI DR",address2:"STE 101",city:"MELBOURNE",state:"FL",zip_code:"32940",main_contact:"MATT SHAW",bill_customer_id:"Promethean",call_type:"DEPOT",call_rcvd_time:"17:00:00",status:"CMP",queue_id:"DIGIMED",due:"BY",tech:"E-ERWE"};structAppend(d,variables.config.getFedexDefaults(),true);return d;}
    private any function value(required struct r,required string key){return structKeyExists(arguments.r,arguments.key)?arguments.r[arguments.key]:"";}
    private date function asDate(required any v){
        // Lucee's date return annotation accepts date-shaped strings unchanged.
        // Always return a date object so comparisons cannot become lexical.
        if(isInstanceOf(arguments.v,"java.util.Date"))return arguments.v;
        var s=trim(arguments.v&"");
        if(reFind("^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}",s))return parseDateTime(s);
        if(reFind("^[0-9]{1,2}[-/][0-9]{1,2}[-/][0-9]{4}$",s)){
            var p=listToArray(replace(s,"/","-","all"),"-");return createDate(val(p[3]),val(p[1]),val(p[2]));
        }
        if(isDate(s))return parseDateTime(s);
        throw(type="Logicore.Validation",message="Unrecognized date: "&s);
    }
    private any function asDateSafe(any v=""){try{return asDate(arguments.v);}catch(any e){return javacast("null","");}}
    private numeric function nearest50(required numeric n){return createObject("java","java.lang.Math").rint(arguments.n/50.0)*50;}
    private numeric function roundMoney(required numeric n){return createObject("java","java.math.BigDecimal").init(javaCast("double",arguments.n)).setScale(javaCast("int",2),createObject("java","java.math.RoundingMode").HALF_EVEN).doubleValue();}
    private array function sortedKeys(required struct s){var a=structKeyArray(arguments.s);arraySort(a,"textnocase");return a;}
    private string function safeFilename(string requested="",string fallback="output"){var n=trim(arguments.requested);if(!len(n))n=arguments.fallback;n=reReplace(n,"\.xlsx$","","one");n=reReplace(n,"[^A-Za-z0-9._-]+","_","all");return left(n,120);}
    private numeric function arraySum(required array a){var x=0;for(var n in a)x+=n;return x;}
    private array function parseBreakdown(required string text){var a=[];for(var p in listToArray(arguments.text,",")){if(!isNumeric(trim(p))||val(p)<=0||val(p)!=int(val(p)))throw(type="Logicore.Validation",message="breakdown must contain positive whole numbers");arrayAppend(a,int(val(p)));}if(!arrayLen(a))throw(type="Logicore.Validation",message="empty breakdown");return a;}
    private array function structValuesSorted(required struct m,string field=""){var sortField=arguments.field;var a=[];for(var k in arguments.m)arrayAppend(a,arguments.m[k]);if(len(arguments.field))arraySort(a,function(x,y){return compareNoCase(x[sortField]&"",y[sortField]&"");});return a;}
    private array function flattenGroups(required array one,required array two){var a=[];for(var g in arguments.one)for(var r in g.rows)arrayAppend(a,r);for(var g in arguments.two)for(var r in g.rows)arrayAppend(a,r);return a;}
    private struct function compileRepairTiers(required array raw){var out=[];for(var r in arguments.raw){var s=trim(r.size&"");var lo=val(listFirst(s,"-"));var hi=find("-",s)?val(listLast(s,"-")):lo;arrayAppend(out,{lo:lo,hi:hi,rb:val(r.rb_price),harvest:val(r.harvest_price),box:val(r.box_build?:0)});}return {rows:out};}
    private any function repairPrice(any model="",string status="",required struct tiers){var m=reFind("^[[:space:]]*([0-9]+)",uCase(trim(arguments.model&"")),1,true);if(!m.len[1])return javacast("null","");var size=val(mid(arguments.model,m.pos[2],m.len[2]));var best={};var bestDist=999999;for(var t in arguments.tiers.rows){var dist=size>=t.lo&&size<=t.hi?0:min(abs(size-t.lo),abs(size-t.hi));if(dist<bestDist){best=t;bestDist=dist;}}if(!structCount(best))return javacast("null","");return arguments.status=="Repaired"?best.rb:best.harvest;}
    private numeric function lookupDimension(any model="",required struct dims,boolean loose=false){var m=uCase(trim(arguments.model&""));if(!len(m))return javacast("null","");if(structKeyExists(arguments.dims,m))return val(arguments.dims[m]);if(arguments.loose){for(var pat in ["-B$","/[0-9]+$","-[0-9]+$"]){var stripped=reReplace(m,pat,"");if(stripped!=m&&structKeyExists(arguments.dims,stripped))return val(arguments.dims[stripped]);}var base=listFirst(m,"/");if(structKeyExists(arguments.dims,base))return val(arguments.dims[base]);}return javacast("null","");}
    private struct function splitPhilipsCredit(required numeric demo,required numeric service){var half=250;var dc=half;var sc=half;if(arguments.demo<half){dc=arguments.demo;sc=min(500-arguments.demo,arguments.service);}else if(arguments.service<half){sc=arguments.service;dc=min(500-arguments.service,arguments.demo);}return {demo:dc,service:sc};}
    private string function canonical(any raw="",required string expected){var s=trim(arguments.raw&"");return compareNoCase(s,arguments.expected)==0?arguments.expected:s;}
    private string function fallbackCanonical(any raw="",required string expected){var s=canonical(arguments.raw,arguments.expected);return len(s)?s:arguments.expected;}
    private string function cleanZip(any raw="",required string fallback){var s=trim(arguments.raw&"");if(right(s,2)==".0")s=left(s,len(s)-2);var m=reFind("^[0-9]+",s,1,true);if(m.len[1]>=5)return left(s,5);return len(s)?s:arguments.fallback;}
    private string function cleanCsv(any v=""){var s=trim(arguments.v&"");if(left(s,2)=='="'&&right(s,1)=='"')s=mid(s,3,len(s)-3);return replace(s,'"','',"all");}
    private struct function loadWhitelist(string path=""){var parts={};var units={};if(len(arguments.path)&&fileExists(arguments.path)){for(var r in variables.excel.readSheet(arguments.path,"Parts")){var v=uCase(trim(value(r,"Parts List")&""));if(len(v))parts[v]=true;}for(var r in variables.excel.readSheet(arguments.path,"Units"))for(var k in r){var v=uCase(trim(r[k]&""));if(len(v))units[v]=true;}}else{var d=deserializeJson(fileRead(variables.rootPath&"config/whitelist_default.json","utf-8"));for(var v in d.parts)parts[uCase(trim(v))]=true;for(var v in d.unit_models)units[uCase(trim(v))]=true;}return {parts:parts,units:units};}
    private struct function tagRow(required struct r,required string source){var x=duplicate(arguments.r);x._Source=arguments.source;return x;}
    private struct function analyzeStorageFedex(required string path,required date start,required date finish,required struct partPrices,required numeric pickPrice){var rows=variables.excel.readFirstSheet(arguments.path);var programming=[];var totals={};var picks=0;var rowNum=1;for(var r in rows){rowNum++;var d=asDateSafe(value(r,"Request Date"));if(isNull(d)||d<arguments.start||d>arguments.finish)continue;var q=value(r,"Quantity");var qty=isNumeric(q)?val(q):1;if(qty<=0)qty=1;if(qty!=int(qty))throw(type="Logicore.Validation",message="FedEx Quantity must contain whole numbers; fractional value found on source row "&rowNum);qty=int(qty);picks+=qty;var code=value(r,"Part/Component Reported Product Code")&"";var typ=classifyPart(code);var fee=len(typ)&&structKeyExists(arguments.partPrices,typ)?arguments.partPrices[typ]:0;arrayAppend(programming,{MSO:value(r,"MSO"),"Request Date":d,"Outbound Tracking":value(r,"Outbound Tracking"),"Part ##":code,Type:typ,Serial:value(r,"Serial Number"),Quantity:qty,"Individual Part Fee":fee,"Total Programming Fee":fee*qty,"Part Pick Fee":arguments.pickPrice});if(len(typ))totals[typ]=(totals[typ]?:0)+qty;}return {programming:programming,part_type_totals:totals,small_part_picks:picks};}
    private string function classifyPart(required string code){var pc=uCase(arguments.code);var map=[{t:"PSU",k:["PSU"]},{t:"Mainboard Configure for Dispatch",k:["MAINBOARD","MAINBRD"]},{t:"AC-PCA",k:["AC-PCA"]},{t:"Keypad",k:["KEYPAD"]},{t:"Maintouch",k:["MAINTOUCHPCA","MAINTOUCH"]},{t:"EXT-INPUT",k:["EXT-INPUT"]},{t:"OPS-PCA",k:["OPS-PCA"]},{t:"USB",k:["OPS-","OPS4-","AP-WIFI","WIFI","BT","-NP","-7P","-5P","-CP","-C1-"]},{t:"SPEAKER",k:["SPEAKER"]},{t:"CONSOLE",k:["CONSOLE"]}];for(var m in map)for(var kw in m.k)if(find(kw,pc))return m.t;return "";}
    private array function readCsv(required string path){var text=fileRead(arguments.path,"utf-8");var records=parseCsvText(text);if(!arrayLen(records))return[];var headers=records[1];var out=[];for(var i=2;i<=arrayLen(records);i++){var rec=records[i];if(arrayLen(rec)==1&&!len(trim(rec[1])))continue;var row={};for(var c=1;c<=arrayLen(headers);c++)row[cleanCsv(headers[c])]=c<=arrayLen(rec)?cleanCsv(rec[c]):"";arrayAppend(out,row);}return out;}
    private array function parseCsvText(required string text){var rows=[];var row=[];var field="";var quoted=false;var i=1;while(i<=len(arguments.text)){var ch=mid(arguments.text,i,1);if(ch=='"'){if(quoted&&i<len(arguments.text)&&mid(arguments.text,i+1,1)=='"'){field&='"';i++;}else quoted=!quoted;}else if(ch==","&&!quoted){arrayAppend(row,field);field="";}else if((ch==chr(10)||ch==chr(13))&&!quoted){if(ch==chr(13)&&i<len(arguments.text)&&mid(arguments.text,i+1,1)==chr(10))i++;arrayAppend(row,field);arrayAppend(rows,row);row=[];field="";}else field&=ch;i++;}if(len(field)||arrayLen(row)){arrayAppend(row,field);arrayAppend(rows,row);}return rows;}
    private struct function issue(required struct r,required string kind,required string desc,required string field,any current="",required array suggestions){return {row_index:r.row_index,issue_type:arguments.kind,description:arguments.desc,field:arguments.field,current_value:arguments.current&"","Actual Model":value(r,"Actual Model")&"","Actual Serial":value(r,"Actual Serial")&"",Result:value(r,"Result")&"",Category:value(r,"Category")&"",Date:isDate(value(r,"Date Integer"))?dateFormat(value(r,"Date Integer"),"yyyy-mm-dd"):(value(r,"Date Integer")&""),suggested_values:arguments.suggestions};}
    private struct function serialModelSize(required any serial,required array rules){var s=trim(arguments.serial&"");var su=uCase(s);var sorted=duplicate(arguments.rules);arraySort(sorted,function(a,b){return len(b.prefix?:"")-len(a.prefix?:"");});for(var rule in sorted){var p=uCase(rule.prefix?:"");if(len(p)&&left(su,len(p))==p){var suffix="-NA-R";var o=rule.o2_rule?:"never";var pos=val(rule.year_pos?:5)+1;if(o=="always")suffix="-02-NA-R";else if(o!="never"&&len(s)>=pos&&mid(s,pos,1)>="L")suffix="-02-NA-R";return {model:(rule.model_base?:"")&suffix,size:(rule.size?:"")&""};}}var map={"686P":["AP6-86-4K-R","86"],"675F":["AP6-75-4K-R","75"],"9A65":["AP9-A65-NA-R","65"],"9A75":["AP9-A75-NA-R","75"],"9A76":["AP9-A75-NA-R","75"],"9A86":["AP9-A86-NA-R","86"],"9B65":["AP9-B65-NA-R","65"],"9B75":["AP9-B75-NA-R","75"],"9B86":["AP9-B86-NA-R","86"],"9G86":["AP9-B86-NA-R","86"],"AA65":["AP10-A65-NA-R","65"],"AA75":["AP10-A75-NA-R","75"],"AA86":["AP10-A86-NA-R","86"],"AB55":["AP10-B55-NA-R","55"],"AB65":["AP10-B65-NA-R","65"],"AB75":["AP10-B75-NA-R","75"],"AB86":["AP10-B86-NA-R","86"],"BE65":["APLE-65-NA-R","65"],"BE75":["APLE-75-NA-R","75"],"BE86":["APLE-86-NA-R","86"],"LX65":["APLX-65-NA-R","65"],"LX75":["APLX-75-NA-R","75"],"LX86":["APLX-86-NA-R","86"]};var p4=left(su,4);if(structKeyExists(map,p4))return {model:map[p4][1],size:map[p4][2]};if(left(su,3)=="V65")return {model:"VTP-65-NA-R",size:"65"};if(left(su,3)=="V75")return {model:"VTP-75-NA-R",size:"75"};return {model:"",size:""};}
    private string function cleanModel(any model=""){var m=trim(arguments.model&"");if(!len(m))return"";for(var bad in [" - Harvest","-NA-2","-NA—R","-R-EU","-2"]){while(right(m,len(bad))==bad)m=left(m,len(m)-len(bad));}if(right(m,5)=="-NA-R")return m;if(right(m,3)=="-NA")return m&"-R";if(right(m,2)=="-R"){if(findNoCase("-4K-R",m))return m;return left(m,len(m)-2)&"-NA-R";}return m&"-NA-R";}
    private string function normalizePanelSize(required string raw){var s=lCase(trim(arguments.raw));if(listFindNoCase("55,65,70,75,86",s))return s;var map={"5t":"75","6t":"86","0t":"70","7o":"70","b7":"75","77":"75","76":"75","5w":"75","66":"65","68":"86","57":"75","83":"86"};return structKeyExists(map,s)?map[s]:"";}
    private string function sizeFromModel(required string m){var hit=reFind("-([0-9]{2})-",arguments.m,1,true);if(hit.len[1]&&listFindNoCase("55,65,70,75,86",mid(arguments.m,hit.pos[2],hit.len[2])))return mid(arguments.m,hit.pos[2],hit.len[2]);return"";}
    private string function deriveWorkshopType(any category=""){var c=lCase(trim(arguments.category&""));if(find("refurbished",c)||find("scrap",c))return"Depot Repair Tab";if(find("pending parts",c))return"Triage Tab";return"";}
    private string function normalizeResult(any result=""){
        var text=trim(arguments.result&"");
        var rules=[
            ["harvest.*physical|physical.*harvest","Harvested: Physical Damage"],
            ["panel damaged.*harvest|harvest.*panel damage","Harvested: Panel Damage"],
            ["harvest.*lcd|lcd.*harvest","Harvested: LCD Damage"],
            ["harvest.*lines|lines.*harvest","Harvested: Lines in Screen"],
            ["harvest.*shipping|shipping.*harvest|destroyed in shipping","Harvested: Destroyed in Shipping"],
            ["harvest","Harvested: Physical Damage"],
            ["^scrap$|immediate scrap","Salvage of Hardware and Scrap"]
        ];for(var rule in rules)if(reFindNoCase(rule[1],text))return rule[2];return text;
    }
    private string function workshopType2(any result="",any category=""){var c=lCase(trim(arguments.category&""));if(find("scrap",c))return"Salvage of Hardware and Scrap";var res=lCase(arguments.result&"");for(var kw in ["lcd","lcm","pending lcd","pending lcm","retaped deflector","retape deflector","deflector sheet","backlight deflector","reflector sheet","overlay replaced","lcd and","lcm and","lcd, ","lcm, ","obf lcd","pending overlay"])if(find(kw,res))return"Heavy";return"Basic";}
    private numeric function workshopPrice(required string type,required string type2,required string size,boolean previous=false){if(type2=="Salvage of Hardware and Scrap")return 28;if(type=="Depot Repair Tab"){if(type2=="Basic")return previous?(size=="Large"?74:64):(size=="Large"?135:110);if(type2=="Heavy")return previous?(size=="Large"?127:108):(size=="Large"?268:220);}if(type=="Triage Tab"){if(type2=="Basic")return size=="Large"?101:86;if(type2=="Heavy")return size=="Large"?181:152;}return 0;}
    private numeric function countType(required array rows,required string type){var n=0;for(var r in arguments.rows)if((r._Type?:"")==arguments.type)n++;return n;}
    private array function unresolvedRows(required array rows,required struct unresolved){var a=[];for(var r in arguments.rows)if(structKeyExists(arguments.unresolved,r.row_index&""))arrayAppend(a,r);return a;}
}
