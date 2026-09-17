<cfscript>
// CI-only deterministic parity fixtures for the Lucee invoice builders.
// These expected values mirror the executable formulas in current Python main.
if (createObject("java", "java.lang.System").getenv("CI") != "true") {
    cfheader(statusCode=404, statusText="Not Found");
    writeOutput("Not Found");
    abort;
}

function assertEq(required any actual, required any expected, required string label) {
    if (isNumeric(arguments.actual) && isNumeric(arguments.expected)) {
        if (abs(val(arguments.actual) - val(arguments.expected)) > 0.001) {
            throw(type="Logicore.Parity", message=arguments.label & " expected " & arguments.expected & " but got " & arguments.actual);
        }
    } else if ((arguments.actual & "") != (arguments.expected & "")) {
        throw(type="Logicore.Parity", message=arguments.label & " expected " & arguments.expected & " but got " & arguments.actual);
    }
}

results = {};

// Promethean Storage: current Python-main test explicitly excludes Parts Testing
// charges from the invoice subtotal. One stored unit, one pallet, one receipt,
// one unit pick, three small-part picks and one check-in = 79.27.
storageAnalysis = {
    unit_storage:[{ActualModel:"MODEL", "Actual Serial":"INV-1", Storage:8.0}],
    units_received:[{Model:"MODEL", "Serial Number":"RECV-1"}],
    programming:[{MSO:"M1", Quantity:3}],
    part_type_totals:{PSU:3},
    ship_month:[{"Serial Number":"SHIP-1"}],
    unit_picks_count:1,
    small_part_picks:3,
    pallet_count:1,
    auto_spc_rows:[{"Part ##":"AP10A-65PSU", Price:0.77}],
    unmatched:[]
};
storage = application.invoice.buildStorage(storageAnalysis, "CI_Storage_Parity");
assertEq(storage.subtotal, 79.27, "Storage subtotal");
assertEq(storage.tax, 5.55, "Storage tax");
assertEq(storage.total, 84.82, "Storage total");
results.storage = storage;

// AMC defaults: 2 receipts, 3 shipments, and 150 additional sq ft.
amcAnalysis = {
    receipt_count:2,
    ship_count:3,
    total_sqft:650,
    additional_sqft:150,
    receiving:[], shipping:[], inventory:[], excluded:[]
};
amc = application.invoice.buildAMC(amcAnalysis, "AMC Warehouse Invoice", "CI_AMC_Parity");
assertEq(amc.subtotal, 2505.00, "AMC subtotal");
assertEq(amc.tax, 175.35, "AMC tax");
assertEq(amc.total, 2680.35, "AMC total");
results.amc = amc;

// Philips builder fixture uses already-analyzed additional square footage.
philipsAnalysis = {
    demo_total_sqft:500,
    service_total_sqft:2050,
    demo_additional_sqft:250,
    service_additional_sqft:1800,
    parts_sqft_manual:100,
    inbound_count:2,
    outbound_count:3,
    repair_count:2,
    repair_total:200,
    harvest_count:2,
    harvest_total:56,
    received:[], shipping:[], repairs:[], excluded:[]
};
philips = application.invoice.buildPhilips(philipsAnalysis, "TPV Philips Warehouse Invoice", "CI_Philips_Parity");
assertEq(philips.subtotal, 9721.00, "Philips subtotal");
assertEq(philips.tax, 680.47, "Philips tax");
assertEq(philips.total, 10401.47, "Philips total");
results.philips = philips;

// TCL: two pallets at $75, one serialized single-part box, one five-part box.
tclAnalysis = {
    unit_groups:[{key:"unit::2026-08-01", received_date:"2026-08-01", quantity:4, rows:[]}],
    part_groups:[{key:"part::MODEL::A::2026-08-01", model:"MODEL", grade:"A", received_date:"2026-08-01", quantity:6, rows:[]}]
};
tcl = application.invoice.buildTCL(
    tclAnalysis,
    {"unit::2026-08-01":"2,2"},
    {"part::MODEL::A::2026-08-01":"1,5"},
    "CI_TCL_Parity"
);
assertEq(tcl.total_pallets, 2, "TCL pallet count");
assertEq(tcl.subtotal, 157.70, "TCL subtotal");
assertEq(tcl.tax, 11.04, "TCL tax");
assertEq(tcl.total, 168.74, "TCL total");
results.tcl = tcl;

// Promethean Workshop current price table: Depot Basic Small 110,
// Depot Heavy Large 268, Triage Basic Small 86, Salvage 28.
workshopAnalysis = {
    issues:[],
    rows:[
        {row_index:0, _Type:"Depot Repair Tab", _Type2:"Basic", _size:"75", Size:"Small"},
        {row_index:1, _Type:"Depot Repair Tab", _Type2:"Heavy", _size:"86", Size:"Large"},
        {row_index:2, _Type:"Triage Tab", _Type2:"Basic", _size:"65", Size:"Small"},
        {row_index:3, _Type:"Depot Repair Tab", _Type2:"Salvage of Hardware and Scrap", _size:"75", Size:"Small"}
    ]
};
workshop = application.invoice.buildWorkshop(workshopAnalysis, {}, "CI_Workshop_Parity");
assertEq(workshop.depot_count, 3, "Workshop depot count");
assertEq(workshop.triage_count, 1, "Workshop triage count");
assertEq(workshop.subtotal, 492.00, "Workshop subtotal");
assertEq(workshop.tax, 34.44, "Workshop tax");
assertEq(workshop.total, 526.44, "Workshop total");
results.workshop = workshop;

// FedEx shipment builder: confirms the upload workbook path and passthrough totals.
fedexAnalysis = {
    rows:[{
        SiteID:"", SiteName:"UNITED SERVICE SOURCE", OrgID:"Promethean", CustomerID:"Promethean",
        Address:"7195 WAELTI DR", Address2:"STE 101", City:"MELBOURNE", State:"FL", ZipCode:"32940",
        MainContact:"MATT SHAW", BillCustomerID:"Promethean", CustomerPO:"PO-1", CallType:"DEPOT",
        CallRcvd:createDate(2026,8,31), CallRcvdTime:"17:00:00", Status:"CMP", QueueID:"DIGIMED",
        DUE:"BY", "Due By Date":createDate(2026,8,31), Summary:"082026 FedEx Invoices - TRACK-1",
        Tech:"E-ERWE", Event1:"PMTH-SHIP", Event1Price:123.45
    }],
    defaulted_rows:[], skipped_rows:[], total_price:123.45
};
fedex = application.invoice.buildFedexShipment(fedexAnalysis, "CI_FedEx_Parity");
assertEq(fedex.row_count, 1, "FedEx row count");
assertEq(fedex.total_price, 123.45, "FedEx total");
results.fedex = fedex;

cfcontent(type="application/json; charset=utf-8", reset=true);
writeOutput(serializeJson({ok:true, fixtures:results}));
</cfscript>
