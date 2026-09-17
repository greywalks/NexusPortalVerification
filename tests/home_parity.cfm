<cfscript>
// CI-only diagnostic for the home hub sanitizer and link validation. Application.cfc
// admits /tests/ only when CI=true; this template additionally refuses otherwise.
if (createObject("java","java.lang.System").getenv("CI") != "true") { cfheader(statusCode=404); writeOutput("Not Found"); abort; }
h = application.home;
dirty = '<p onclick="steal()">Hello <strong>team</strong></p><script>alert(1)</script><a href="javascript:alert(2)">bad</a> <a href="https://ok.example/x?a=1&b=2" target="_blank">good</a><img src=x onerror=alert(3)><mark>note</mark>';
seedish = '<p>Team <a href="https://datamg.ussi.global/quarantine" target="_blank">x</a>.</p><p><mark>hi</mark></p>';
parts = listToArray(h.htmlEscape(seedish), "&lt;", true, true);
out = {
    ok:true,
    escape_seedish:h.htmlEscape(seedish),
    parts_count:arrayLen(parts),
    parts:parts,
    sanitized_dirty:h.sanitizeHtml(dirty),
    sanitized_seedish:h.sanitizeHtml(seedish),
    safe_tab:h.safeUrl("https://example.com/tab"),
    safe_rel:h.safeUrl("/training-tracker/"),
    safe_js:h.safeUrl("javascript:alert(1)"),
    stored_links:queryExecute("SELECT id,label,url,target,style FROM home_links WHERE label LIKE 'Parity%' OR label='Remote NGERP access'", {}, {datasource:"logicore"}),
    stored_bulletin:queryExecute("SELECT id,title,body_html FROM home_sections WHERE kind='bulletin'", {}, {datasource:"logicore"})
};
cfcontent(type="application/json; charset=utf-8", reset=true);
writeOutput(serializeJson(out));
</cfscript>
