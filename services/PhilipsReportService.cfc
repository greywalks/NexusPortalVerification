component output=false {
    function init(required any excelService, required any configService, required string outputPath) {
        variables.excel = arguments.excelService;
        variables.config = arguments.configService;
        variables.outputPath = arguments.outputPath;
        return this;
    }

    struct function buildFromRaw(required string rawPath, required any periodStart, required any periodEnd, string reportName="") {
        var startDate = asDate(arguments.periodStart);
        var endDate = asDate(arguments.periodEnd);
        if (endDate < startDate) { var swap = startDate; startDate = endDate; endDate = swap; }

        var rawInv = variables.excel.readSheet(arguments.rawPath, "Inventory");
        var rawRecv = variables.excel.readSheet(arguments.rawPath, "Received");
        var rawRep = variables.excel.readSheet(arguments.rawPath, "Repairs");
        var rawShip = variables.excel.readSheet(arguments.rawPath, "Shipments");
        var dims = variables.config.getPhilipsDimensions();

        var inventory = [];
        var shipping = [];
        var received = [];
        var repairs = [];
        var flagged = [];
        var pending = [];
        var missing = {};

        // Raw Inventory is the current snapshot. Keep the first row per serial.
        var seenSerials = {};
        var inventoryLookup = {};
        for (var r in rawInv) {
            var serial = trim(value(r, "Serial") & "");
            if (!len(serial) || structKeyExists(seenSerials, serial)) continue;
            seenSerials[serial] = true;
            inventoryLookup[serial] = r;
            var model = trim(value(r, "Model") & "");
            var sqft = lookupDimension(model, dims);
            if (isNull(sqft) && len(model)) missing[uCase(model)] = true;
            var lastReceived = javacast("null", "");
            for (var rr in rawRecv) {
                if (trim(value(rr, "Serial") & "") != serial) continue;
                var rd = asDateSafe(value(rr, "Date"));
                if (isNull(rd)) continue;
                if (isNull(lastReceived) || rd > lastReceived) lastReceived = rd;
            }
            arrayAppend(inventory, {
                "Type": value(r, "Type"),
                "Grade": value(r, "Grade"),
                "RMA": value(r, "RMA"),
                "Model": model,
                "Size": isNull(sqft) ? "" : sqft,
                "Serial": serial,
                "Rcv Date": isNull(lastReceived) ? "" : lastReceived
            });
        }

        // Shipments in the requested billing period.
        for (var r in rawShip) {
            var d = asDateSafe(value(r, "Date"));
            if (isNull(d) || d < startDate || d > endDate) continue;
            arrayAppend(shipping, {
                "Date": d,
                "Stock Level (Primary)": value(r, "Stock Level (Primary)"),
                "Arrival RMA": value(r, "Arrival RMA"),
                "Departure RMA": value(r, "Departure RMA"),
                "Departure Tracking": value(r, "Departure Tracking"),
                "Ship to Name": value(r, "Ship to Name"),
                "Carrier": value(r, "Carrier"),
                "Column11": "Track",
                "Model": value(r, "Model"),
                "Serial": value(r, "Serial")
            });
        }

        // Received rows stay billable by default; suspicious rows are copied to review.
        for (var r in rawRecv) {
            var d = asDateSafe(value(r, "Date"));
            if (isNull(d) || d < startDate || d > endDate) continue;
            var serial = trim(value(r, "Serial") & "");
            var inv = structKeyExists(inventoryLookup, serial) ? inventoryLookup[serial] : {};
            var origin = value(r, "Origin Company") & "";
            var rma = value(r, "Arrival RMA") & "";
            var tracking = value(r, "Tracking ##") & "";
            var nonconforming = findNoCase("nonconform", origin) > 0 || findNoCase("nonconform", rma) > 0;
            var noTracking = !len(trim(tracking));
            arrayAppend(received, {
                "Model": value(r, "Model"),
                "Serial": serial,
                "Grade": value(inv, "Grade"),
                "Warehouse": value(inv, "Type"),
                "RMA": rma,
                "Date": d,
                "Origin Company": origin,
                "Tracking": tracking
            });
            if (nonconforming || noTracking) {
                var reasons = [];
                if (nonconforming) arrayAppend(reasons, "NonConforming origin/RMA");
                if (noTracking) arrayAppend(reasons, "No tracking number");
                arrayAppend(flagged, {
                    "Model": value(r, "Model"),
                    "Serial": serial,
                    "RMA": rma,
                    "Date": d,
                    "Origin Company": origin,
                    "Tracking": tracking,
                    "Reason": arrayToList(reasons, " + ")
                });
            }
        }

        // Only Repaired/Harvested repairs are billable. Everything else is visible on Pending.
        for (var r in rawRep) {
            var repairDate = asDateSafe(value(r, "Date"));
            if (isNull(repairDate) || repairDate < startDate || repairDate > endDate) continue;
            var status = trim(value(r, "Repaired/ Harvested") & "");
            var serial = trim(value(r, "Serial") & "");
            if (status != "Repaired" && status != "Harvested") {
                arrayAppend(pending, {
                    "Repair Date": repairDate,
                    "Model": value(r, "Model"),
                    "Serial": serial,
                    "Status": status,
                    "Diagnostics": value(r, "Diagnostics"),
                    "Parts Used": value(r, "Parts Used")
                });
                continue;
            }

            var bestPrior = javacast("null", "");
            var earliestAny = javacast("null", "");
            var bestPriorRow = {};
            var earliestRow = {};
            for (var rr in rawRecv) {
                if (trim(value(rr, "Serial") & "") != serial) continue;
                var rd = asDateSafe(value(rr, "Date"));
                if (isNull(rd)) continue;
                if (isNull(earliestAny) || rd < earliestAny) { earliestAny = rd; earliestRow = rr; }
                if (rd <= repairDate && (isNull(bestPrior) || rd > bestPrior)) { bestPrior = rd; bestPriorRow = rr; }
            }
            var recvRow = structCount(bestPriorRow) ? bestPriorRow : earliestRow;
            var receivedDate = structCount(bestPriorRow) ? bestPrior : (isNull(earliestAny)?"":earliestAny);
            arrayAppend(repairs, {
                "Repair Date": repairDate,
                "Received Date": isNull(receivedDate) ? "" : receivedDate,
                "Model": value(r, "Model"),
                "Serial": serial,
                "RMA": structCount(recvRow) ? value(recvRow, "Arrival RMA") : "",
                "Status": status,
                "Diagnostics": value(r, "Diagnostics"),
                "Parts Used": value(r, "Parts Used"),
                "Repaired Y/N": status == "Repaired" ? "Yes" : "No"
            });
        }

        var base = trim(arguments.reportName);
        if (!len(base)) base = "TPV_Philips_MonthEndReport_" & dateFormat(now(), "yyyymmdd") & "_" & timeFormat(now(), "HHmmss");
        base = reReplace(base, "(?i)\.xlsx$", "");
        base = reReplace(base, "[^A-Za-z0-9._ -]", "_", "all");
        var filename = base & ".xlsx";

        variables.excel.writeWorkbook(variables.outputPath & filename, [
            {name:"Inventory", headers:["Type","Grade","RMA","Model","Size","Serial","Rcv Date"], rows:inventory},
            {name:"Shipping", headers:["Date","Stock Level (Primary)","Arrival RMA","Departure RMA","Departure Tracking","Ship to Name","Carrier","Column11","Model","Serial"], rows:shipping},
            {name:"Recieved", headers:["Model","Serial","Grade","Warehouse","RMA","Date","Origin Company","Tracking"], rows:received},
            {name:"Repairs", headers:["Repair Date","Received Date","Model","Serial","RMA","Status","Diagnostics","Parts Used","Repaired Y/N"], rows:repairs},
            {name:"Flagged for Review", headers:["Model","Serial","RMA","Date","Origin Company","Tracking","Reason"], rows:flagged},
            {name:"Pending Repairs (Not Billed)", headers:["Repair Date","Model","Serial","Status","Diagnostics","Parts Used"], rows:pending}
        ]);

        return {
            filename: filename,
            path: variables.outputPath & filename,
            inventory: inventory,
            shipping: shipping,
            received: received,
            repairs: repairs,
            flagged: flagged,
            pending: pending,
            missing_inventory_dims: sortedKeys(missing),
            flagged_received_count: arrayLen(flagged),
            pending_repairs_count: arrayLen(pending),
            period_start: dateFormat(startDate, "yyyy-mm-dd"),
            period_end: dateFormat(endDate, "yyyy-mm-dd")
        };
    }

    private any function value(required struct row, required string key, any fallback="") {
        return structKeyExists(arguments.row, arguments.key) ? arguments.row[arguments.key] : arguments.fallback;
    }

    private any function asDateSafe(any raw="") {
        if (isDate(arguments.raw)) return parseDateTime(arguments.raw);
        var s = trim(arguments.raw & "");
        if (!len(s)) return javacast("null", "");
        try { return parseDateTime(s); } catch (any ignored) { return javacast("null", ""); }
    }

    private any function asDate(required any raw) {
        var d = asDateSafe(arguments.raw);
        if (isNull(d)) throw(type="Logicore.Validation", message="A valid period date is required.");
        return d;
    }

    private any function lookupDimension(any model="", required struct dims) {
        var m = uCase(trim(arguments.model & ""));
        if (!len(m)) return javacast("null", "");
        if (structKeyExists(arguments.dims, m)) return val(arguments.dims[m]);
        for (var pattern in ["-B$", "/[0-9]+$", "-[0-9]+$"]) {
            var stripped = reReplace(m, pattern, "");
            if (stripped != m && structKeyExists(arguments.dims, stripped)) return val(arguments.dims[stripped]);
        }
        var base = listFirst(m, "/");
        if (structKeyExists(arguments.dims, base)) return val(arguments.dims[base]);
        return javacast("null", "");
    }

    private array function sortedKeys(required struct source) {
        var keys = structKeyArray(arguments.source);
        arraySort(keys, "textnocase");
        return keys;
    }
}
