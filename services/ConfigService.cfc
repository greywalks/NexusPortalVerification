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
        // Write to a temporary file first so an interrupted write cannot leave a
        // truncated JSON document behind for the next request to fail on.
        lock name="logicore-config-#hash(arguments.path)#" type="exclusive" timeout="10" {
            var tmp = arguments.path & "." & left(replace(createUUID(), "-", "", "all"), 8) & ".tmp";
            fileWrite(tmp, serializeJson(arguments.data), "utf-8");
            try { fileMove(tmp, arguments.path); }
            catch (any e) { try { fileDelete(tmp); } catch (any ignored) {} rethrow; }
        }
    }

    // ---- validation helpers -------------------------------------------------
    // Reference data drives invoice totals, so reject anything that is not the
    // expected shape instead of persisting it and billing from it later.
    private void function fail(required string message) { throw(type="Logicore.Validation", message=arguments.message); }
    private numeric function requireMoney(required any value, required string label) {
        if (!isSimpleValue(arguments.value) || !isNumeric(arguments.value) || val(arguments.value) < 0) fail(arguments.label & " must be a number of 0 or more.");
        return val(arguments.value);
    }
    private struct function validatePriceMap(required any input, required struct allowed, required string label) {
        if (!isStruct(arguments.input)) fail(arguments.label & " must be an object of prices.");
        var out = {};
        for (var key in arguments.input) {
            if (!structKeyExists(arguments.allowed, key)) fail(arguments.label & ": unknown price key '" & key & "'.");
            out[key] = requireMoney(arguments.input[key], arguments.label & " " & key);
        }
        return out;
    }

    struct function getSerialRules() { return readJson(variables.configPath & "serial_rules.json",{}); }
    void function saveSerialRules(required struct rules) {
        var list = arguments.rules.rules ?: "";
        if (!isArray(list)) fail("Serial rules must be an array.");
        var clean = []; var seen = {};
        for (var r in list) {
            if (!isStruct(r)) fail("Each serial rule must be an object.");
            var prefix = uCase(trim(r.prefix ?: "")); var base = trim(r.model_base ?: "");
            if (!len(prefix) || !len(base)) fail("Each serial rule needs a prefix and a model base.");
            if (len(prefix) > 20 || len(base) > 60) fail("Serial rule '" & prefix & "' has an over-long prefix or model base.");
            if (structKeyExists(seen, prefix)) fail("Serial rule prefix '" & prefix & "' is listed more than once.");
            seen[prefix] = true;
            var size = trim(r.size ?: "") & "";
            if (!listFind("55,65,70,75,86", size)) fail("Serial rule '" & prefix & "': size must be one of 55, 65, 70, 75, 86.");
            var o2 = lCase(trim(r.o2_rule ?: "never"));
            if (!listFind("year_pos5,year_pos6,always,never", o2)) fail("Serial rule '" & prefix & "': unknown -02 rule '" & o2 & "'.");
            var yearPos = r.year_pos ?: 5;
            if (!isNumeric(yearPos) || val(yearPos) < 0 || val(yearPos) != int(val(yearPos)) || val(yearPos) > 40) fail("Serial rule '" & prefix & "': year position must be a whole number between 0 and 40.");
            arrayAppend(clean, {prefix:prefix, year_pos:int(val(yearPos)), model_base:base, size:size, o2_rule:o2});
        }
        writeJson(variables.configPath & "serial_rules.json", {rules:clean});
    }

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
    void function saveStoragePrices(required struct prices) {
        // Keys already present (defaults plus any previously saved part type) are accepted;
        // anything else is rejected so a typo cannot introduce a price nothing bills against.
        var known = getStoragePrices();
        var clean = {};
        if (structKeyExists(arguments.prices, "part_type_prices")) clean.part_type_prices = validatePriceMap(arguments.prices.part_type_prices, known.part_type_prices, "Part type price");
        if (structKeyExists(arguments.prices, "line_prices")) clean.line_prices = validatePriceMap(arguments.prices.line_prices, known.line_prices, "Line price");
        for (var key in arguments.prices) if (!listFindNoCase("part_type_prices,line_prices", key)) fail("Unknown storage pricing section '" & key & "'.");
        if (!structCount(clean)) fail("No storage prices were supplied.");
        // Sections not supplied keep their current values; the frontend always sends both.
        var current = readJson(variables.configPath & "storage_prices.json", {});
        structAppend(current, clean, true);
        writeJson(variables.configPath & "storage_prices.json", current);
    }
    void function resetStoragePrices(){ if(fileExists(variables.configPath&"storage_prices.json")) fileDelete(variables.configPath&"storage_prices.json"); }

    struct function getFedexDefaults(){ return readJson(variables.configPath&"fedex_shipment_defaults.json",{}); }
    void function saveFedexDefaults(required struct data){
        var allowed = "margin_divisor,event1_code,site_name,org_id,customer_id,address,address2,city,state,zip_code,main_contact,bill_customer_id,call_type,call_rcvd_time,status,queue_id,due,tech";
        var clean = {};
        for (var key in arguments.data) {
            if (!listFindNoCase(allowed, key)) fail("Unknown FedEx default '" & key & "'.");
            var v = arguments.data[key];
            if (!isSimpleValue(v)) fail("FedEx default '" & key & "' must be a simple value.");
            if (key == "margin_divisor") { if (!isNumeric(v) || val(v) <= 0 || val(v) > 1) fail("margin_divisor must be a number greater than 0 and at most 1."); clean[key] = val(v); }
            else if (key == "call_rcvd_time") { if (!reFind("^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$", trim(v))) fail("call_rcvd_time must be HH:MM or HH:MM:SS."); clean[key] = trim(v); }
            else { if (len(v) > 200) fail("FedEx default '" & key & "' is too long."); clean[key] = trim(v & ""); }
        }
        if (!structCount(clean)) fail("No FedEx defaults were supplied.");
        var current = getFedexDefaults(); structAppend(current, clean, true);
        writeJson(variables.configPath&"fedex_shipment_defaults.json", current);
    }

    private struct function philipsReference(){
        var live=variables.configPath&"philips_reference.json";
        if(!fileExists(live)) fileCopy(variables.configPath&"philips_reference_default.json",live);
        return readJson(live,{dimensions:{},repair_cost:[]});
    }
    private void function savePhilipsReference(required struct ref){ writeJson(variables.configPath&"philips_reference.json",arguments.ref); }
    struct function getPhilipsDimensions(){ return philipsReference().dimensions ?: {}; }
    array function getPhilipsRepairCost(){ return philipsReference().repair_cost ?: []; }
    void function savePhilipsDimensions(required struct dims){ var r=philipsReference();r.dimensions=arguments.dims;savePhilipsReference(r); }
    void function addPhilipsDimension(required string model, required numeric sqft){if(!len(trim(arguments.model)))fail("Model is required.");if(arguments.sqft<0)fail("Square footage for "&arguments.model&" must be 0 or more.");var r=philipsReference();r.dimensions[uCase(trim(arguments.model))]=arguments.sqft;savePhilipsReference(r);}
    void function savePhilipsRepairCost(required array tiers){
        var clean = []; var seen = {};
        for (var t in arguments.tiers) {
            if (!isStruct(t)) fail("Each repair cost tier must be an object.");
            var size = trim(t.size ?: "") & "";
            if (!reFind("^[0-9]{1,3}(-[0-9]{1,3})?$", size)) fail("Repair cost tier size must be a number or a range such as 20-24 (got '" & size & "').");
            if (find("-", size) && val(listFirst(size, "-")) > val(listLast(size, "-"))) fail("Repair cost tier '" & size & "' has its range reversed.");
            if (structKeyExists(seen, size)) fail("Repair cost tier '" & size & "' is listed more than once.");
            seen[size] = true;
            arrayAppend(clean, {size:size, rb_price:requireMoney(t.rb_price ?: "", "Refurbish price for size " & size), harvest_price:requireMoney(t.harvest_price ?: "", "Harvest price for size " & size), box_build:requireMoney(t.box_build ?: 0, "Box build price for size " & size)});
        }
        if (!arrayLen(clean)) fail("At least one repair cost tier is required; Philips repairs would otherwise bill at $0.");
        var r=philipsReference();r.repair_cost=clean;savePhilipsReference(r);
    }

    struct function getAmcDimensions(){
        var live=variables.configPath&"amc_dimensions.json";
        if(!fileExists(live)) fileCopy(variables.configPath&"amc_dimensions_default.json",live);
        var d=readJson(live,{}); var out={}; for(var k in d) out[uCase(trim(k))]=d[k]; return out;
    }
    void function saveAmcDimensions(required struct dims){ writeJson(variables.configPath&"amc_dimensions.json",arguments.dims); }
    void function addAmcDimension(required string model, required numeric sqft){if(!len(trim(arguments.model)))fail("Model is required.");if(arguments.sqft<0)fail("Square footage for "&arguments.model&" must be 0 or more.");var d=getAmcDimensions();d[uCase(trim(arguments.model))]=arguments.sqft;saveAmcDimensions(d);}

    struct function amcDefaults(){return {unit_receipt:8.00,storage_base:1910.00,base_sqft:500,storage_addl:3.50,order_fee:10.00,order_out_fee:8.00};}
    struct function getAmcPrices(){var d=amcDefaults();var live=readJson(variables.configPath&"amc_prices.json",{});structAppend(d,live,true);return d;}
    void function saveAmcPrices(required struct prices){var clean=validatePriceMap(arguments.prices,getAmcPrices(),"AMC price");if(!structCount(clean))fail("No AMC prices were supplied.");var current=getAmcPrices();structAppend(current,clean,true);writeJson(variables.configPath&"amc_prices.json",current);}
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
