component output=false {
    variables.rootPath = getDirectoryFromPath(getCurrentTemplatePath());
    variables.system = createObject("java", "java.lang.System");
    variables.environmentName = lCase(trim(variables.system.getenv("USSI_NEXUS_ENV") ?: "development"));
    variables.runtimePath = trim(variables.system.getenv("USSI_NEXUS_RUNTIME_ROOT") ?: "");
    if (!len(variables.runtimePath)) variables.runtimePath = variables.rootPath;
    if (right(variables.runtimePath, 1) != "/" && right(variables.runtimePath, 1) != "\\") variables.runtimePath &= "/";
    variables.cookieSecure = variables.environmentName == "production";
    variables.cookieSecureSetting = lCase(trim(variables.system.getenv("USSI_NEXUS_COOKIE_SECURE") ?: ""));
    if (len(variables.cookieSecureSetting)) variables.cookieSecure = listFindNoCase("1,true,yes,on", variables.cookieSecureSetting) > 0;

    this.name = "USSINexusLucee";
    this.applicationTimeout = createTimeSpan(1, 0, 0, 0);
    this.sessionManagement = true;
    this.sessionTimeout = createTimeSpan(0, 8, 0, 0);
    this.setClientCookies = true;
    this.sessionCookie = {httpOnly:true, secure:variables.cookieSecure, sameSite:"Lax"};
    this.scriptProtect = "all";
    this.datasource = "logicore";
    this.javaSettings = {loadPaths:[variables.rootPath & "lib"],loadColdFusionClassPath:true,reloadOnChange:false};
    this.datasources["logicore"] = {
        class: "org.h2.Driver",
        connectionString: "jdbc:h2:file:" & replace(variables.runtimePath, "\\", "/", "all") & "data/logicore;MODE=LEGACY;DATABASE_TO_UPPER=FALSE;AUTO_SERVER=TRUE",
        username: "sa",
        password: ""
    };

    boolean function onApplicationStart() {
        application.rootPath = variables.rootPath;
        application.runtimePath = variables.runtimePath;
        application.environmentName = variables.environmentName;
        application.uploadPath = application.runtimePath & "uploads/";
        application.outputPath = application.runtimePath & "outputs/";
        application.dataPath = application.runtimePath & "data/";
        application.configPath = application.rootPath & "config/";
        application.signoffPath = application.dataPath & "training_signoffs/";

        for (var dirPath in [application.uploadPath, application.outputPath, application.dataPath, application.configPath, application.signoffPath]) {
            if (!directoryExists(dirPath)) directoryCreate(dirPath, true);
        }
        if (!directoryExists(application.outputPath & ".access/")) directoryCreate(application.outputPath & ".access/", true);

        application.excel = new services.ExcelService();
        application.audit = new services.AuditService(datasource="logicore");
        application.apiKeys = new services.ApiKeyService(datasource="logicore");
        application.sso = new services.SsoService();
        application.home = new services.HomeService(datasource="logicore");
        application.auth = new services.LuceeAuthService(datasource="logicore");
        application.configService = new services.ConfigService(rootPath=application.rootPath);
        application.outputs = new services.OutputService(outputPath=application.outputPath);
        application.nonconforming = new services.LuceeNonConformingService(datasource="logicore", outputPath=application.outputPath, excelService=application.excel);
        application.invoice = new services.InvoiceService(
            rootPath=application.rootPath,
            uploadPath=application.uploadPath,
            outputPath=application.outputPath,
            configService=application.configService,
            outputService=application.outputs,
            excelService=application.excel
        );
        application.philipsReport = new services.PhilipsReportService(excelService=application.excel, configService=application.configService, outputPath=application.outputPath);
        application.trainingPdf = new services.TrainingPdfService();
        // These two services derive their data/ and outputs/ locations from the
        // path they are given, so they must receive the runtime root (which may be
        // USSI_NEXUS_RUNTIME_ROOT), not the code checkout. Otherwise generated
        // reports are written under the code tree while routes read them from the
        // runtime root and downloads fail.
        application.training = new services.LuceeTrainingService(datasource="logicore", rootPath=application.runtimePath, excelService=application.excel);
        application.trainingImport = new services.TrainingImportService(datasource="logicore", excelService=application.excel);
        application.inventory = new services.InventoryService(datasource="logicore", rootPath=application.runtimePath, excelService=application.excel);
        application.inventory.bootstrap();
        application.loginThrottle = {};

        application.outputs.cleanOld(72);
        cleanUploads(72);
        return true;
    }

    // Uploaded workbooks are only needed while an analysis is active in a
    // session; remove anything older than the session lifetime so disk use is
    // bounded. Training sign-off scans live elsewhere and are not touched.
    private void function cleanUploads(numeric hours=72) {
        try {
            var cutoff = dateAdd("h", -arguments.hours, now());
            var q = directoryList(application.uploadPath, false, "query");
            for (var row in q) {
                if (row.type == "File" && row.dateLastModified < cutoff) {
                    try { fileDelete(application.uploadPath & row.name); } catch (any ignored) {}
                }
            }
        } catch (any e) {
            writeLog(type="warning", file="ussi_nexus", text="Upload cleanup failed: " & (e.message ?: ""));
        }
    }

    // Cross-site request forgery defense. Session cookies are SameSite=Lax, so
    // browsers already withhold them on cross-site POSTs; this check makes the
    // policy explicit and covers older browsers. Browsers send an Origin header
    // on every cross-origin state-changing request, so a present-but-foreign
    // Origin (or Referer) is rejected. Requests with neither header are not
    // browser-initiated cross-site requests (curl, the CI suite) and pass.
    private boolean function requestOriginAllowed() {
        var method = uCase(cgi.request_method ?: "GET");
        if (!listFindNoCase("POST,PUT,PATCH,DELETE", method)) return true;
        var expectedHost = lCase(trim(cgi.http_host ?: ""));
        var forwardedHost = lCase(trim(listFirst(cgi.http_x_forwarded_host ?: "", ",")));
        var origin = trim(cgi.http_origin ?: "");
        var referer = trim(cgi.http_referer ?: "");
        var source = len(origin) && origin != "null" ? origin : referer;
        if (!len(source)) return true;
        var sourceHost = lCase(reReplace(source, "^[a-zA-Z][a-zA-Z0-9+.-]*://([^/?##]+).*$", "\1"));
        if (sourceHost == source) return false;
        return len(sourceHost) && (sourceHost == expectedHost || (len(forwardedHost) && sourceHost == forwardedHost));
    }

    boolean function onRequestStart(string targetPage) {
        var requestPath=listFirst(cgi.request_uri?:"/","?");
        var isCI=createObject("java","java.lang.System").getenv("CI")=="true";
        cfheader(name="X-Content-Type-Options",value="nosniff");
        cfheader(name="X-Frame-Options",value="DENY");
        cfheader(name="Referrer-Policy",value="same-origin");
        cfheader(name="Permissions-Policy",value="camera=(), microphone=(), geolocation=()");
        var forwardedProto = lCase(listFirst(cgi.http_x_forwarded_proto ?: "", ","));
        var requestIsSecure = (cgi.https ?: "") == "on" || forwardedProto == "https";
        if (variables.environmentName == "production" && requestIsSecure) cfheader(name="Strict-Transport-Security",value="max-age=31536000; includeSubDomains");
        var internal=reFindNoCase("^/(WEB-INF|data|uploads|outputs|services|routes|config|migration|template|scripts|lib|deploy)/",requestPath)||reFindNoCase("^/(Application\.cfc|server\.json|\.CFConfig\.json|[^/]+\.md)$",requestPath);
        var ciFixture=isCI&&requestPath=="/tests/billing_parity.cfm";
        if((internal||left(requestPath,7)=="/tests/")&&!ciFixture){
            var response=getPageContext().getResponse();response.setStatus(404);response.setContentType("text/plain; charset=utf-8");writeOutput("Not Found");return false;
        }
        if (isCI && structKeyExists(url, "reload") && url.reload == "1") onApplicationStart();
        request.correlationId = lCase(left(replace(createUUID(), "-", "", "all"), 12));
        if (!requestOriginAllowed()) {
            var blocked = getPageContext().getResponse(); blocked.setStatus(403); blocked.setContentType("application/json; charset=utf-8");
            writeOutput(serializeJson({ok:false, error:"Cross-site request rejected."})); return false;
        }
        if (!structKeyExists(session, "sid")) session.sid = replace(createUUID(), "-", "", "all");
        return true;
    }

    void function onError(any exception, string eventName) {
        var correlationId = request.correlationId ?: "startup";
        var detail = (exception.message ?: "") & " | " & (exception.detail ?: "");
        var where = "";
        try { if (isArray(exception.tagContext ?: "") && arrayLen(exception.tagContext)) where = " @ " & (exception.tagContext[1].template ?: "") & ":" & (exception.tagContext[1].line ?: ""); } catch (any ignored) {}
        writeLog(type="error", file="ussi_nexus", text="[" & correlationId & "] " & (arguments.eventName ?: "") & " " & (exception.type ?: "") & ": " & detail & where);
        if (!isDefined("request.responseCommitted") || !request.responseCommitted) {
            cfheader(statusCode=500, statusText="Internal Server Error");
            var isCI = createObject("java","java.lang.System").getenv("CI") == "true";
            writeOutput(isCI ? "USSI Nexus CI error: " & detail : "USSI Nexus encountered an unexpected error. Reference: " & correlationId);
        }
    }
}
