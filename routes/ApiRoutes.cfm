<cfscript>
// /api/v1 — token-authenticated JSON surface for system-to-system integration.
// Groundwork for linking Inventory Management and invoicing to external
// databases: read endpoints, one ingest endpoint, stable error shapes.
// Authentication: "Authorization: Bearer nxk_..." or "X-Api-Key: nxk_...".
// Sessions and cookies are never consulted here.
function apiOut(required any data,numeric status=200){cfheader(statusCode=arguments.status,statusText=arguments.status>=400?"Error":"OK");cfheader(name="Cache-Control",value="no-store");cfcontent(type="application/json; charset=utf-8",reset=true);writeOutput(serializeJson(arguments.data));request.responseCommitted=true;abort;}
function apiError(required string code,required string message,numeric status=400,any details=""){var body={ok:false,error:{code:arguments.code,message:arguments.message}};if(!isSimpleValue(arguments.details)||len(arguments.details))body.error.details=arguments.details;body.correlation_id=request.correlationId?:"";apiOut(body,arguments.status);}
function bearerToken(){var auth=trim(cgi.http_authorization?:"");if(reFindNoCase("^Bearer\s+",auth))return trim(reReplaceNoCase(auth,"^Bearer\s+",""));var headers=getHttpRequestData(false).headers;for(var h in headers)if(lCase(h)=="x-api-key")return trim(headers[h]);return "";}
function requireScope(required string scope){var token=bearerToken();if(!len(token))apiError("unauthenticated","Provide an API key as 'Authorization: Bearer <key>'.",401);var key=application.apiKeys.authenticate(token);if(!structCount(key)){application.audit.record("api.auth_failed",{},"api_key",left(token,12)&"…",{},"failure","api");apiError("unauthenticated","The API key is invalid or revoked.",401);}if(!application.apiKeys.hasScope(key,arguments.scope))apiError("forbidden","This key lacks the '"&arguments.scope&"' scope.",403);request.apiKey=key;return key;}
function apiActor(){var k=request.apiKey?:{};return {username:"api:"&(k.name?:"?")&" ("&(k.prefix?:"")&")"};}
function apiAudit(required string action,string targetType="",any targetId="",struct detail={},string outcome="success"){try{application.audit.record(arguments.action,apiActor(),arguments.targetType,arguments.targetId,arguments.detail,arguments.outcome,"api");}catch(any ignored){}}
function apiBody(){try{return bodyJson();}catch(any e){apiError("invalid_json",e.message,400);}}

ap=removeChars(path,1,len("/api/v1"));if(!len(ap))ap="/";

if(ap=="/"||ap=="/health"){apiOut({ok:true,service:"USSI Nexus",api:"v1",time:dateTimeFormat(now(),"yyyy-mm-dd'T'HH:nn:ss")});}

// ---- Inventory ---------------------------------------------------------------
if(ap=="/inventory/imports"&&method=="GET"){requireScope("inventory:read");apiOut({ok:true,imports:application.inventory.imports(min(max(val(valUrl("limit",100)),1),500))});}
sm=reFind("^/inventory/serials/(.+)$",ap,1,true);if(sm.len[1]&&method=="GET"){requireScope("inventory:read");serialValue=urlDecode(mid(ap,sm.pos[2],sm.len[2]));d=application.inventory.serialDetail(serialValue);if(!structCount(d))apiError("not_found","No lifecycle events for serial "&serialValue,404);apiOut({ok:true,serial:d});}
mm=reFind("^/inventory/mso/(.+)$",ap,1,true);if(mm.len[1]&&method=="GET"){requireScope("inventory:read");msoValue=urlDecode(mid(ap,mm.pos[2],mm.len[2]));d=application.inventory.msoDetail(msoValue);if(!structCount(d))apiError("not_found","No events for MSO "&msoValue,404);apiOut({ok:true,mso:d});}
md=reFind("^/inventory/models/(.+)$",ap,1,true);if(md.len[1]&&method=="GET"){requireScope("inventory:read");modelValue=urlDecode(mid(ap,md.pos[2],md.len[2]));apiOut({ok:true,model:application.inventory.modelDetail(modelValue)});}
if(ap=="/inventory/shipping"&&method=="GET"){requireScope("inventory:read");range=application.inventory.shippingRange(valUrl("preset","custom"),valUrl("start",""),valUrl("end",""));rep=application.inventory.shippingHistory(range,valUrl("model",""));apiOut({ok:true,range:range,summary:rep.summary,rows:rep.rows});}
if(ap=="/inventory/quality/audit"&&method=="GET"){requireScope("inventory:read");audit=application.inventory.qualityAudit();if(!structCount(audit))apiError("not_ready","No Promethean reference is installed, so no audit is available.",409);apiOut({ok:true,audit:audit});}
if(ap=="/inventory/events"&&method=="POST"){requireScope("inventory:write");b=apiBody();if(!isStruct(b))apiError("invalid_body","Send a JSON object with kind, source and rows.",400);try{r=application.inventory.ingestRows(b.kind?:"",isArray(b.rows?:"")?b.rows:[],b.source?:"");apiAudit("inventory.api_ingest","inventory_import",r.batch_id,{kind:b.kind?:"",source:b.source?:"",rows:r.rows,events:r.events,duplicate_payload:r.duplicate_payload});apiOut({ok:true,result:r},r.duplicate_payload?200:201);}catch(any e){if(e.type=="Logicore.Validation")apiError("invalid_body",e.message,400);writeLog(type="error",file="ussi_nexus",text="["&(request.correlationId?:"")&"] api ingest: "&(e.message?:"")&" | "&(e.detail?:""));apiError("server_error","The rows could not be imported. Reference: "&(request.correlationId?:""),500);}}

// ---- Invoicing ---------------------------------------------------------------
if(ap=="/invoices/prices"&&method=="GET"){requireScope("invoices:read");c=application.configService;apiOut({ok:true,prices:{amc:c.getAmcPrices(),philips:c.getPhilipsPrices(),tcl:c.getTclPrices(),storage:c.getStoragePrices(),philips_repair_cost:c.getPhilipsRepairCost(),fedex_defaults:c.getFedexDefaults()}});}
if(ap=="/invoices/dimensions"&&method=="GET"){requireScope("invoices:read");c=application.configService;apiOut({ok:true,amc:c.getAmcDimensions(),philips:c.getPhilipsDimensions()});}
if(ap=="/invoices/outputs"&&method=="GET"){requireScope("invoices:read");apiOut({ok:true,outputs:application.outputs.listAll()});}
om=reFind("^/invoices/outputs/(.+)$",ap,1,true);if(om.len[1]&&method=="GET"){requireScope("invoices:read");fn=urlDecode(mid(ap,om.pos[2],om.len[2]));real=application.outputs.resolve(fn);if(!len(real)||!len(application.outputs.subsection(fn)))apiError("not_found","No generated file named "&fn,404);apiAudit("file.download","output",fn,{via:"api"});cfheader(name="Content-Disposition",value='attachment; filename="'&getFileFromPath(real)&'"');cfcontent(file=real,type="application/octet-stream",reset=true);abort;}

// ---- Audit (read-only export for SIEM pulls) ------------------------------------
if(ap=="/audit/events"&&method=="GET"){requireScope("config:read");res=application.audit.search(actor=valUrl("actor",""),action=valUrl("action",""),targetType=valUrl("target_type",""),targetId=valUrl("target_id",""),outcome=valUrl("outcome",""),startDate=valUrl("start_date",""),endDate=valUrl("end_date",""),limit=min(max(val(valUrl("limit",100)),1),1000),offset=max(val(valUrl("offset",0)),0));for(ev in res.rows)structDelete(ev,"detail_json");apiOut({ok:true,total:res.total,limit:res.limit,offset:res.offset,events:res.rows});}

apiError("not_found","No API route matches "&method&" "&ap,404);
</cfscript>
