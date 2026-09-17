component output=false {
    function init(required string rootPath) {
        variables.rootPath = arguments.rootPath;
        variables.configPath = arguments.rootPath & "config/";
        if (!directoryExists(variables.configPath)) directoryCreate(variables.configPath,true);
        return this;
    }

    private any function readJson(required string path, any fallback={}) {
        if (!fileExists(arguments.path)) return duplicate(arguments.fallback);
        try { return deserializeJson(fileRead(arguments.path,"utf-8")); }
        catch(any e) { throw(type="Logicore.Config",message="Could not parse " & getFileFromPath(arguments.path),detail=e.message); }
    }

    private void function writeJson(required string path, required any data) {
        lock name="logicore-config-#hash(arguments.path)#" type="exclusive" timeout="10" {
            fileWrite(arguments.path, serializeJson(arguments.data), "utf-8");
        }
    }

    struct function getSerialRules() { return readJson(variables.configPath & "serial_rules.json",{}); }
    void function saveSerialRules(required struct rules) { writeJson(variables.configPath & "serial_rules.json",arguments.rules); }

    struct function storageDefaults() {
        return {
            part_type_prices:{
                "PSU":7,"Mainboard Configure for Dispatch":52,"Mainboard":37,"AC-PCA":4,"Keypad":4,
                "Maintouch":37,"EXT-INPUT":7,"OPS-PCA":4,"USB":4,"SPEAKER":4,"CONSOLE":0
            },
            line_prices:{unit_storage:8.00,pallet_storage:23.50,unit_receipt:15.00,small_part_checkin:0.77,unit_pick:8.00,small_part_pick:8.00}
        };
    }

    struct function getStoragePrices() {
        var defaults=storageDefaults();
        var live=readJson(variables.configPath & "storage_prices.json",{});
        if(structKeyExists(live,"part_type_prices")) structAppend(defaults.part_type_prices,live.part_type_prices,true);
        if(structKeyExists(live,"line_prices")) structAppend(defaults.line_prices,live.line_prices,true);
        return defaults;
    }
    void function saveStoragePrices(required struct prices) { writeJson(variables.configPath & "storage_prices.json",arguments.prices); }
    void function resetStoragePrices(){ if(fileExists(variables.configPath&"storage_prices.json")) fileDelete(variables.configPath&"storage_prices.json"); }

    struct function getFedexDefaults(){ return readJson(variables.configPath&"fedex_shipment_defaults.json",{}); }
    void function saveFedexDefaults(required struct data){ writeJson(variables.configPath&"fedex_shipment_defaults.json",arguments.data); }

    private struct function philipsReference(){
        var live=variables.configPath&"philips_reference.json";
        if(!fileExists(live)) fileCopy(variables.configPath&"philips_reference_default.json",live);
        return readJson(live,{dimensions:{},repair_cost:[]});
    }
    private void function savePhilipsReference(required struct ref){ writeJson(variables.configPath&"philips_reference.json",arguments.ref); }
    struct function getPhilipsDimensions(){ return philipsReference().dimensions ?: {}; }
    array function getPhilipsRepairCost(){ return philipsReference().repair_cost ?: []; }
    void function savePhilipsDimensions(required struct dims){ var r=philipsReference();r.dimensions=arguments.dims;savePhilipsReference(r); }
    void function addPhilipsDimension(required string model, required numeric sqft){var r=philipsReference();r.dimensions[uCase(trim(arguments.model))]=arguments.sqft;savePhilipsReference(r);}
    void function savePhilipsRepairCost(required array tiers){var r=philipsReference();r.repair_cost=arguments.tiers;savePhilipsReference(r);}

    struct function getAmcDimensions(){
        var live=variables.configPath&"amc_dimensions.json";
        if(!fileExists(live)) fileCopy(variables.configPath&"amc_dimensions_default.json",live);
        var d=readJson(live,{}); var out={}; for(var k in d) out[uCase(trim(k))]=d[k]; return out;
    }
    void function saveAmcDimensions(required struct dims){ writeJson(variables.configPath&"amc_dimensions.json",arguments.dims); }
    void function addAmcDimension(required string model, required numeric sqft){var d=getAmcDimensions();d[uCase(trim(arguments.model))]=arguments.sqft;saveAmcDimensions(d);}

    struct function amcDefaults(){return {unit_receipt:8.00,storage_base:1910.00,base_sqft:500,storage_addl:3.50,order_fee:10.00,order_out_fee:8.00};}
    struct function getAmcPrices(){var d=amcDefaults();var live=readJson(variables.configPath&"amc_prices.json",{});structAppend(d,live,true);return d;}
    void function saveAmcPrices(required struct prices){writeJson(variables.configPath&"amc_prices.json",arguments.prices);}
    void function resetAmcPrices(){if(fileExists(variables.configPath&"amc_prices.json"))fileDelete(variables.configPath&"amc_prices.json");}

    struct function readDimensionsWorkbook(required string path){
        var rows=application.excel.readFirstSheet(arguments.path);
        var dims={};
        for(var row in rows){
            var model="";var sqft="";
            for(var key in row){
                var nk=lCase(key);
                if(find("model",nk))model=trim(row[key]&"");
                if(find("sq",nk)||find("footage",nk)||find("footprint",nk))sqft=row[key];
            }
            if(len(model)&&isNumeric(sqft)&&sqft>=0)dims[uCase(model)]=sqft;
        }
        if(!structCount(dims))throw(type="Logicore.Validation",message="No Model / Sq Footage rows were found in the uploaded workbook.");
        return dims;
    }

    string function writeDimensionsWorkbook(required string outputPath, required struct dims, string sheetName="Dimensions"){
        var rows=[];var keys=structKeyArray(arguments.dims);arraySort(keys,"textnocase");
        for(var model in keys)arrayAppend(rows,{"Model":model,"Sq Footage":arguments.dims[model]});
        application.excel.writeWorkbook(arguments.outputPath,[{name:arguments.sheetName,headers:["Model","Sq Footage"],rows:rows}]);
        return arguments.outputPath;
    }
}
