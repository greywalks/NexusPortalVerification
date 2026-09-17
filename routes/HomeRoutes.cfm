<cfscript>
// Intranet home hub: /home (everyone signed in) and /home/edit (home editors).
function homeAttr(required string v){return application.home.escapeHubText(arguments.v);}
function homeCanEdit(required struct u){return val(arguments.u.is_superadmin?:0)==1||application.auth.hasAccess(arguments.u,"home","editor");}
function homeRequireEditor(){var u=requireLogin();if(!homeCanEdit(u))htmlOut(workspaceShellStart(u,"home","Home")&'<div class="card" role="alert"><h2>Editing not permitted</h2><p>Your account does not have the Home Page Editor permission. Ask an administrator to grant it under User Management.</p><p><a class="btn" href="/home">&larr; Back to Home</a></p></div>'&workspaceShellEnd(),403);return u;}
function homeLinkHtml(required struct l){var label=encodeForHtml(l.label);var cls="home-link home-link-"&encodeForHtmlAttribute(l.style?:"normal");var url=len(l.url?:"")?l.url:"";var out="";
    if(!len(url))out='<span class="'&cls&' home-link-unset" title="No address set">'&label&'</span>';
    else if((l.target?:"same")=="tab")out='<a class="'&cls&'" href="'&homeAttr(url)&'" target="_blank" rel="noopener noreferrer">'&label&'</a>';
    else if((l.target?:"same")=="window")out='<a class="'&cls&'" href="'&homeAttr(url)&'" target="_blank" rel="noopener noreferrer" data-open="window">'&label&'</a>';
    else out='<a class="'&cls&'" href="'&homeAttr(url)&'">'&label&'</a>';
    if(len(l.description?:""))out&='<span class="home-link-desc">'&encodeForHtml(l.description)&'</span>';return out;}
function homeSectionHtml(required struct s){var h='<section class="home-section" id="home-section-'&s.id&'"><h3 class="home-section-title">'&encodeForHtml(s.title)&'</h3>';
    if(len(s.subtitle?:""))h&='<p class="home-section-sub">'&encodeForHtml(s.subtitle)&'</p>';
    if(len(s.note_text?:""))h&='<p class="home-note home-note-'&encodeForHtmlAttribute(s.note_style?:"normal")&'">'&encodeForHtml(s.note_text)&'</p>';
    if(s.kind=="bulletin")h&='<div class="home-bulletin">'&(s.body_html?:"")&'</div>';
    else{h&='<ul class="home-links">';for(var l in s.links)h&='<li>'&homeLinkHtml(l)&'</li>';h&='</ul>';}
    return h&'</section>';}
function homeRedirect(){redirectTo("/home/edit"&(len(valUrl("focus",""))?"##home-section-"&valUrl("focus",""):""));}

hp=len(path)>5?mid(path,6,len(path)-5):"/";if(!len(hp))hp="/";

if(hp=="/"&&method=="GET"){u=requireLogin();cols=application.home.columns();h=workspaceShellStart(u,"home","Home");
    h&='<div class="home-hub"><div class="home-banner">'&encodeForHtml(application.home.banner())&'</div><div class="home-columns">';
    for(c=1;c<=3;c++){h&='<div class="home-column">';for(s in cols[c])h&=homeSectionHtml(s);h&='</div>';}
    h&='</div>'&(homeCanEdit(u)?'<p class="home-edit-bar"><a class="btn" href="/home/edit">&##9998; Edit home page</a></p>':'')&'</div><script src="/static/js/home-hub.js"></script>';
    htmlOut(h&workspaceShellEnd());}

if(hp=="/edit"&&method=="GET"){u=homeRequireEditor();cols=application.home.columns();h=workspaceShellStart(u,"home","Edit Home Page");
    if(len(valUrl("error","")))h&='<div class="card" role="alert" style="border-color:##ef4444;color:##f87171">'&encodeForHtml(valUrl("error",""))&'</div>';
    h&='<p class="muted">Changes are live as soon as they are saved. <a href="/home">View the home page</a>.</p>';
    h&='<div class="card"><form method="post" action="/home/banner" class="home-inline"><label>Banner text <input name="banner" value="'&encodeForHtmlAttribute(application.home.banner())&'" maxlength="120"></label> <button>Save banner</button></form></div>';
    h&='<div class="card"><h2>Add a section</h2><form method="post" action="/home/sections/new" class="home-inline"><input name="title" placeholder="Section title (e.g. Employees:)" required maxlength="200"> <select name="kind" aria-label="Section type"><option value="links">Link list</option><option value="bulletin">Bulletin (formatted text)</option></select> <select name="col" aria-label="Column"><option value="1">Left column</option><option value="2">Middle column</option><option value="3">Right column</option></select> <button>Add section</button></form></div>';
    h&='<div class="home-edit-columns">';
    for(c=1;c<=3;c++){h&='<div class="home-edit-column"><h2>'&["Left","Middle","Right"][c]&' column</h2>';
        for(s in cols[c]){sid=s.id;h&='<div class="card home-edit-section" id="home-section-'&sid&'"><div class="home-edit-head"><strong>'&encodeForHtml(s.title)&'</strong> <span class="muted">'&(s.kind=="bulletin"?"bulletin":"links")&'</span><span class="home-edit-move">';
            for(dir in ["up","down","left","right"])h&='<form method="post" action="/home/sections/'&sid&'/move" class="inline"><input type="hidden" name="direction" value="'&dir&'"><button type="submit" title="Move '&dir&'" aria-label="Move '&dir&'">'&{up:"&uarr;",down:"&darr;",left:"&larr;",right:"&rarr;"}[dir]&'</button></form>';
            h&='<form method="post" action="/home/sections/'&sid&'/delete" class="inline" onsubmit="return confirm(''Delete this section and everything in it?'')"><button type="submit" class="danger" title="Delete section">&times;</button></form></span></div>';
            h&='<form method="post" action="/home/sections/'&sid&'/update" class="home-edit-form"><label>Title <input name="title" value="'&encodeForHtmlAttribute(s.title)&'" required maxlength="200"></label><label>Subtitle <input name="subtitle" value="'&encodeForHtmlAttribute(s.subtitle?:"")&'" maxlength="500" placeholder="Optional line under the title"></label>';
            if(s.kind=="links"){h&='<label>Note <input name="note_text" value="'&encodeForHtmlAttribute(s.note_text?:"")&'" maxlength="500" placeholder="Optional callout above the links"></label><label>Note style <select name="note_style"><option value="normal"'&((s.note_style?:"normal")=="normal"?' selected':'')&'>Normal</option><option value="alert"'&((s.note_style?:"")=="alert"?' selected':'')&'>Alert (red)</option><option value="highlight"'&((s.note_style?:"")=="highlight"?' selected':'')&'>Highlight (yellow)</option></select></label>';}
            else{h&='<label>Bulletin</label><div class="home-toolbar" data-for="body-'&sid&'"><button type="button" data-cmd="bold" title="Bold"><b>B</b></button><button type="button" data-cmd="italic" title="Italic"><i>I</i></button><button type="button" data-cmd="underline" title="Underline"><u>U</u></button><button type="button" data-cmd="highlight" title="Highlight">&##9632;</button><button type="button" data-cmd="heading" title="Heading">H</button><button type="button" data-cmd="insertUnorderedList" title="Bullet list">&bull; List</button><button type="button" data-cmd="insertOrderedList" title="Numbered list">1. List</button><button type="button" data-cmd="link" title="Insert link">&##128279; Link</button><button type="button" data-cmd="unlink" title="Remove link">Unlink</button><button type="button" data-cmd="clear" title="Clear formatting">Clear</button></div><div class="home-editor" id="body-'&sid&'" contenteditable="true" aria-label="Bulletin text">'&(s.body_html?:"")&'</div><input type="hidden" name="body_html" id="body-'&sid&'-input"><p class="muted">Links inside the bulletin: select text, click Link, enter the address, and choose whether it opens in a new tab.</p>';}
            h&='<button type="submit">Save section</button></form>';
            if(s.kind=="links"){h&='<table class="home-edit-links"><thead><tr><th>Text</th><th>Address</th><th>Opens in</th><th>Style</th><th>Description</th><th></th></tr></thead><tbody>';
                forms='';
                for(l in s.links){fid="lf-"&l.id;forms&='<form method="post" action="/home/links/'&l.id&'/update" id="'&fid&'"></form><form method="post" action="/home/links/'&l.id&'/move" id="'&fid&'-up"><input type="hidden" name="direction" value="up"></form><form method="post" action="/home/links/'&l.id&'/move" id="'&fid&'-down"><input type="hidden" name="direction" value="down"></form><form method="post" action="/home/links/'&l.id&'/delete" id="'&fid&'-del" onsubmit="return confirm(''Remove this link?'')"></form>';
                    h&='<tr><td><input form="'&fid&'" name="label" value="'&encodeForHtmlAttribute(l.label)&'" required maxlength="200" aria-label="Link text"></td><td><input form="'&fid&'" name="url" value="'&homeAttr(l.url?:"")&'" placeholder="https://… or /training-tracker/" maxlength="2000" aria-label="Address"></td><td><select form="'&fid&'" name="target" aria-label="Opens in"><option value="same"'&((l.target?:"same")=="same"?' selected':'')&'>Same page</option><option value="tab"'&((l.target?:"")=="tab"?' selected':'')&'>New tab</option><option value="window"'&((l.target?:"")=="window"?' selected':'')&'>New window</option></select></td><td><select form="'&fid&'" name="style" aria-label="Style"><option value="normal"'&((l.style?:"normal")=="normal"?' selected':'')&'>Normal</option><option value="highlight"'&((l.style?:"")=="highlight"?' selected':'')&'>Highlight</option><option value="alert"'&((l.style?:"")=="alert"?' selected':'')&'>Alert</option></select></td><td><input form="'&fid&'" name="description" value="'&encodeForHtmlAttribute(l.description?:"")&'" maxlength="500" placeholder="Optional" aria-label="Description"></td><td class="home-edit-actions"><button form="'&fid&'" type="submit">Save</button><button form="'&fid&'-up" type="submit" title="Move up" aria-label="Move up">&uarr;</button><button form="'&fid&'-down" type="submit" title="Move down" aria-label="Move down">&darr;</button><button form="'&fid&'-del" type="submit" class="danger" title="Remove" aria-label="Remove link">&times;</button></td></tr>';}
                nfid="nl-"&sid;forms&='<form method="post" action="/home/sections/'&sid&'/links/new" id="'&nfid&'"></form>';
                h&='<tr><td><input form="'&nfid&'" name="label" placeholder="New link text" required maxlength="200" aria-label="New link text"></td><td><input form="'&nfid&'" name="url" placeholder="https://…" maxlength="2000" aria-label="New link address"></td><td><select form="'&nfid&'" name="target" aria-label="Opens in"><option value="same">Same page</option><option value="tab">New tab</option><option value="window">New window</option></select></td><td><select form="'&nfid&'" name="style" aria-label="Style"><option value="normal">Normal</option><option value="highlight">Highlight</option><option value="alert">Alert</option></select></td><td><input form="'&nfid&'" name="description" placeholder="Optional" maxlength="500" aria-label="Description"></td><td class="home-edit-actions"><button form="'&nfid&'" type="submit">Add</button></td></tr></tbody></table>'&forms;}
            h&='</div>';}
        h&='</div>';}
    h&='</div><script src="/static/js/home-editor.js"></script>';htmlOut(h&workspaceShellEnd());}

// ---- writes (POST, editor permission) --------------------------------------
if(method=="POST"){u=homeRequireEditor();actor=u.username;
    try{
        if(hp=="/banner"){application.home.setBanner(form.banner?:"");audit("home.banner","home_settings","banner",{banner:form.banner?:""});redirectTo("/home/edit");}
        if(hp=="/sections/new"){newId=application.home.createSection(form.kind?:"links",form.title?:"",form.subtitle?:"",val(form.col?:1),actor);audit("home.section_created","home_section",newId,{title:form.title?:"",kind:form.kind?:"",col:val(form.col?:1)});redirectTo("/home/edit##home-section-"&newId);}
        sm=reFind("^/sections/([0-9]+)/(update|delete|move|links/new)$",hp,1,true);
        if(sm.len[1]){sid=val(mid(hp,sm.pos[2],sm.len[2]));act=mid(hp,sm.pos[3],sm.len[3]);existing=application.home.section(sid);if(!structCount(existing))htmlOut(workspaceShellStart(u,"home","Home")&'<p>Section not found.</p>'&workspaceShellEnd(),404);
            if(act=="update"){application.home.updateSection(sid,form.title?:"",form.subtitle?:"",form.note_text?:"",form.note_style?:"normal",form.body_html?:"",actor);audit("home.section_updated","home_section",sid,{title:form.title?:"",kind:existing.kind,body_length:len(form.body_html?:"")});redirectTo("/home/edit##home-section-"&sid);}
            if(act=="delete"){application.home.deleteSection(sid);audit("home.section_deleted","home_section",sid,{title:existing.title,links:arrayLen(existing.links)});redirectTo("/home/edit");}
            if(act=="move"){application.home.moveSection(sid,lCase(form.direction?:""));audit("home.section_moved","home_section",sid,{direction:form.direction?:""});redirectTo("/home/edit##home-section-"&sid);}
            if(act=="links/new"){newLink=application.home.addLink(sid,form.label?:"",form["url"]?:"",form.target?:"same",form.style?:"normal",form.description?:"");audit("home.link_added","home_link",newLink,{section_id:sid,label:form.label?:"",url:form["url"]?:"",target:form.target?:"same"});redirectTo("/home/edit##home-section-"&sid);}
        }
        lm=reFind("^/links/([0-9]+)/(update|delete|move)$",hp,1,true);
        if(lm.len[1]){lid=val(mid(hp,lm.pos[2],lm.len[2]));act=mid(hp,lm.pos[3],lm.len[3]);existingLink=application.home.link(lid);if(!structCount(existingLink))htmlOut(workspaceShellStart(u,"home","Home")&'<p>Link not found.</p>'&workspaceShellEnd(),404);back="/home/edit##home-section-"&existingLink.section_id;
            if(act=="update"){application.home.updateLink(lid,form.label?:"",form["url"]?:"",form.target?:"same",form.style?:"normal",form.description?:"");audit("home.link_updated","home_link",lid,{label:form.label?:"",url:form["url"]?:"",target:form.target?:"same",style:form.style?:"normal"});redirectTo(back);}
            if(act=="delete"){application.home.deleteLink(lid);audit("home.link_deleted","home_link",lid,{label:existingLink.label,url:existingLink.url?:""});redirectTo(back);}
            if(act=="move"){application.home.moveLink(lid,lCase(form.direction?:""));audit("home.link_moved","home_link",lid,{direction:form.direction?:""});redirectTo(back);}
        }
    }catch(any e){if(e.type=="Logicore.Validation")redirectTo("/home/edit?error="&urlEncodedFormat(e.message));rethrow;}
}
htmlOut(workspaceShellStart(requireLogin(),"home","Home")&'<p>Page not found.</p>'&workspaceShellEnd(),404);
</cfscript>
