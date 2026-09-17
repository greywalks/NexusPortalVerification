// ── Defaults ─────────────────────────────────────────────────────────────────
const today = new Date();
const firstOfMonth = new Date(today.getFullYear(), today.getMonth(), 1);
// Format as the user's local calendar day. toISOString() converts to UTC, which
// shifts defaults to the next day in US evenings and the previous day east of UTC.
const fmt = d => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

// ── Shared safety helpers ────────────────────────────────────────────────────
// Values shown in review tables come from uploaded workbooks and must never be
// interpreted as markup.
function escHtml(value) {
  if (value === null || value === undefined) return '';
  return String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}
// Escape a value for use inside a double-quoted CSS attribute selector.
function cssAttr(value) {
  return (window.CSS && typeof window.CSS.escape === 'function')
    ? window.CSS.escape(String(value))
    : String(value).replace(/["\\\n\r]/g, c => '\\' + (c === '\n' ? 'a ' : c === '\r' ? 'd ' : c));
}
function downloadUrl(filename) {
  return '/download/' + encodeURIComponent(filename || '');
}
// Parse a JSON API response without throwing. An HTML body (for example the
// sign-in page after a session expires) or an HTTP error becomes {ok:false}.
async function readJson(res) {
  let data = null;
  try { data = await res.json(); } catch (e) { data = null; }
  if (data && typeof data === 'object') {
    if (!res.ok) {
      data = Object.assign({}, data, {ok: false});
      if (!data.error) data.error = `Request failed (HTTP ${res.status})`;
    }
    return data;
  }
  const hint = (res.ok || res.status === 401 || res.status === 403)
    ? ' Your session may have expired; reload the page and sign in again.' : '';
  return {ok: false, error: `Unexpected server response (HTTP ${res.status}).${hint}`};
}
async function requestJson(url, init) {
  let res;
  try { res = await fetch(url, init); }
  catch (err) { return {ok: false, error: 'Network error: ' + (err && err.message ? err.message : err)}; }
  return readJson(res);
}
// Returns a finite, non-negative number, or NaN for blank/invalid/negative input.
function nonNegativeValue(input) {
  const raw = String(input.value ?? '').trim();
  if (raw === '') return NaN;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : NaN;
}
['date-from','date-from2'].forEach(id=>{const el=document.getElementById(id);if(el)el.value=fmt(firstOfMonth);});
['date-to','date-to2','invoice-date','invoice-date2','completed-date','completed-date2'].forEach(id=>{const el=document.getElementById(id);if(el)el.value=fmt(today);});
['t-date-from'].forEach(id=>{const el=document.getElementById(id);if(el)el.value=fmt(firstOfMonth);});
['t-date-to','t-invoice-date'].forEach(id=>{const el=document.getElementById(id);if(el)el.value=fmt(today);});
['fx-call-date'].forEach(id=>{const el=document.getElementById(id);if(el)el.value=fmt(today);});

// ── Page / Tab nav ────────────────────────────────────────────────────────────
function showPage(page) {
  // All top-level sections (brand pages + config)
  const allPages = ['promethean','amc','tcl','philips','config'];
  allPages.forEach(p=>{
    // The server omits sections the user may not use, so any of these can be absent.
    document.getElementById('page-'+p)?.classList.toggle('hidden', p!==page);
    const nav=document.getElementById('nav-'+p);
    if(nav){nav.classList.toggle('active', p===page);nav.classList.toggle('text-steel', p!==page);}
  });
  if(page==='config' && document.getElementById('cfg-tbody')) loadCfg();
}

function showConfigPage() {
  if (typeof window.showPortalPage === 'function') window.showPortalPage('invoice-generator');
  showPage('config');
  const destination = new URL(window.location.href);
  destination.searchParams.set('portal', 'invoice-generator');
  destination.searchParams.set('client', 'config');
  window.history.replaceState({}, '', destination);
}

// ── Sub-page nav (within a brand section) ─────────────────────────────────
function showSubPage(subPage, brand) {
  const subMap = {
    'promethean': ['invoice','storage','fedex-shipment']
    // Add: 'amc': ['amc_workshop'], etc. as modules are built
  };
  const subs = subMap[brand] || [];
  subs.forEach(s => {
    const el = document.getElementById('page-' + s);
    const btn = document.getElementById('subnav-' + s);
    if (el) el.classList.toggle('hidden', s !== subPage);
    if (btn) { btn.classList.toggle('active', s === subPage); btn.classList.toggle('text-steel', s !== subPage); }
  });
}
function switchTab(tab) {
  document.getElementById('pane-raw').classList.toggle('hidden', tab!=='raw');
  document.getElementById('pane-legacy').classList.toggle('hidden', tab!=='legacy');
  document.getElementById('tab-raw').classList.toggle('active', tab==='raw');
  document.getElementById('tab-legacy').classList.toggle('active', tab==='legacy');
  document.getElementById('tab-raw').classList.toggle('text-steel', tab!=='raw');
  document.getElementById('tab-legacy').classList.toggle('text-steel', tab!=='legacy');
}

// ── Drop zones ────────────────────────────────────────────────────────────────
function setupZone(zoneId, inputId, iconId, labelId, defaultLabel) {
  const zone=document.getElementById(zoneId),input=document.getElementById(inputId),
        icon=document.getElementById(iconId),lbl=document.getElementById(labelId);
  if(!zone||!input) return;
  input.addEventListener('change',()=>{
    if(input.files[0]){zone.classList.add('filled');icon.textContent='✅';
      lbl.textContent=input.files[0].name;lbl.classList.add('text-ok');lbl.classList.remove('text-steel');}
  });
  zone.addEventListener('dragover',e=>{e.preventDefault();zone.classList.add('dragover');});
  zone.addEventListener('dragleave',()=>zone.classList.remove('dragover'));
  zone.addEventListener('drop',e=>{
    e.preventDefault();zone.classList.remove('dragover');
    const f=e.dataTransfer.files[0];
    if(f){const dt=new DataTransfer();dt.items.add(f);input.files=dt.files;input.dispatchEvent(new Event('change'));}
  });
}
setupZone('zone-raw','file-raw','icon-raw','label-raw','Full Promethean production workbook · .xlsx');
setupZone('zone-prev2','file-prev2','icon-prev2','label-prev2','Full billing history · .xlsx');
setupZone('zone-ship2','file-ship2','icon-ship2','label-ship2','All outbound shipments · .csv');
setupZone('zone-fedex2','file-fedex2','icon-fedex2','label-fedex2','Parts setup & programming · .xlsx');
setupZone('zone-repair','file-repair','icon-repair','label-repair','Pre-sanitized with Type and Type2 columns');
setupZone('zone-prev','file-prev','icon-prev','label-prev','Full billing history · .xlsx');
setupZone('zone-shipping','file-shipping','icon-shipping','label-shipping','All outbound shipments · .csv');
setupZone('tz-inv','t-inv','icon-t-inv','lbl-t-inv','Raw warehouse inventory snapshot · .xlsx');
setupZone('fx-zone-raw','fx-raw','fx-icon-raw','fx-lbl-raw','Monthly billing export straight from FedEx · .xlsx');

// ── Sanitize form ─────────────────────────────────────────────────────────────
let _issues=[], _outputFilename='', _corrections={};

document.getElementById('sanitize-form')?.addEventListener('submit', async e=>{
  e.preventDefault();
  const btn=document.getElementById('sanitize-btn');
  btn.disabled=true; btn.textContent='Validating…';
  const data=await requestJson('/sanitize',{method:'POST',body:new FormData(e.target)});
  btn.disabled=false; btn.innerHTML='<span>🔍</span> Validate & Review Data';
  if(!data.ok){alert('Error: '+(data.error||'Unknown'));return;}
  _issues=data.issues||[];
  showReview(data);
});

function showReview(data) {
  document.getElementById('step-upload').classList.add('hidden');
  document.getElementById('step-review').classList.remove('hidden');

  const autoCount  = data.auto_count  || 0;
  const issueCount = data.issue_count || 0;
  document.getElementById('review-summary').textContent =
    `${data.total_records} records in period · ${issueCount} need review · ${autoCount} auto-corrected`;

  // Issues section
  if(_issues.length === 0) {
    document.getElementById('no-issues').classList.remove('hidden');
    document.getElementById('issues-container').classList.add('hidden');
    document.getElementById('gen-raw-label').textContent = 'Generate Invoice';
    // Adjust message depending on whether auto-corrections exist
    if((data.auto_count || 0) === 0) {
      document.getElementById('no-issues-title').textContent = 'All records validated — nothing to review';
      document.getElementById('no-issues-sub').textContent   = 'No changes were needed. Ready to generate.';
    } else {
      document.getElementById('no-issues-title').textContent = 'No manual input needed';
      document.getElementById('no-issues-sub').textContent   = `${data.auto_count} correction${data.auto_count!==1?'s were':' was'} applied automatically — expand the table above to review them.`;
    }
  } else {
    document.getElementById('no-issues').classList.add('hidden');
    document.getElementById('issues-container').classList.remove('hidden');
    document.getElementById('issue-count-badge').textContent = `${issueCount} issue${issueCount!==1?'s':''}`;
    document.getElementById('gen-raw-label').textContent = 'Apply & Generate Invoice';
    renderIssues(_issues);
  }

  // Auto-corrections section
  const autos = data.auto_corrections || [];
  if(autos.length > 0) {
    document.getElementById('auto-corrections-section').classList.remove('hidden');
    document.getElementById('auto-count-badge').textContent = `${autos.length} correction${autos.length!==1?'s':''}`;
    renderAutoCorrections(autos);
  }

  // Auto-suggest filename
  const from = document.getElementById('date-from2').value;
  const to   = document.getElementById('date-to2').value;
  if(from && to) {
    const d = new Date(from+'T12:00:00');
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    document.getElementById('output-filename').value = `Promethean_Invoice_${months[d.getMonth()]}_${d.getFullYear()}`;
  }
}

function renderAutoCorrections(autos) {
  const tbody = document.getElementById('auto-tbody');
  tbody.innerHTML = '';
  autos.forEach(ac => {
    const tr = document.createElement('tr');
    tr.className = 'border-b border-steel/10 hover:bg-accent/5';
    const nowModel = ac.model_changed === 'True' ? `<span class="text-ok">${escHtml(ac.new_model)}</span>` : `<span class="text-slate-400">${escHtml(ac.new_model)}</span>`;
    const wasCol = ac.model_changed === 'True' ? `<span class="text-warn/70 font-mono text-xs">${escHtml(ac.old_model)}</span>` : `<span class="text-steel font-mono text-xs">${escHtml(ac.old_model)}</span>`;
    tr.innerHTML = `
      <td class="px-3 py-1.5 font-mono text-steel">${escHtml(ac.Date)}</td>
      <td class="px-3 py-1.5 font-mono text-slate-400">${escHtml(String(ac.Actual_Serial||ac['Actual Serial']||'').substring(0,22))}</td>
      <td class="px-3 py-1.5">${wasCol}${ac.size_changed==='True'?` <span class="text-warn/60 text-xs">sz:${escHtml(ac.old_size)}</span>`:''}</td>
      <td class="px-3 py-1.5">${nowModel}${ac.size_changed==='True'?` <span class="text-ok text-xs">${escHtml(ac.new_size)}"</span>`:''}</td>
      <td class="px-3 py-1.5 text-steel max-w-xs truncate" title="${escHtml(ac.Result)}">${escHtml(String(ac.Result||'').substring(0,30))}</td>`;
    tbody.appendChild(tr);
  });
}

function toggleAutoTable() {
  const wrap = document.getElementById('auto-table-wrap');
  const btn  = document.getElementById('auto-toggle-btn');
  const hidden = wrap.classList.toggle('hidden');
  btn.textContent = hidden ? 'show ▾' : 'hide ▴';
}

function renderIssues(issues) {
  const tbody=document.getElementById('issues-tbody');
  tbody.innerHTML='';
  issues.forEach(iss=>{
    const tr=document.createElement('tr');
    tr.className='border-b border-steel/10 hover:bg-accent/5';
    const opts=iss.suggested_values||[];
    const optsHtml=opts.length
      ?`<select data-idx="${escHtml(iss.row_index)}" data-field="${escHtml(iss.field)}" aria-label="Corrected value"
           class="issue-select bg-ink-100 border border-steel/40 rounded px-2 py-1.5 text-xs text-slate-200 w-full"
           onchange="markIssue(this)">
           <option value="">— choose —</option>
           ${opts.map(o=>`<option value="${escHtml(o)}">${escHtml(o)}</option>`).join('')}
         </select>`
      :`<input type="text" data-idx="${escHtml(iss.row_index)}" data-field="${escHtml(iss.field)}" aria-label="Corrected value"
           class="bg-ink-100 border border-steel/40 rounded px-2 py-1.5 text-xs text-slate-200 w-full"
           placeholder="Enter correct value…" onchange="markIssueInput(this)" />`;
    tr.innerHTML=`
      <td class="px-3 py-2.5 font-mono text-slate-400">${escHtml(iss.Date)}</td>
      <td class="px-3 py-2.5 text-slate-300">${escHtml(iss['Actual Model'])}</td>
      <td class="px-3 py-2.5 font-mono text-slate-400 text-xs">${escHtml(String(iss['Actual Serial']||'').substring(0,20))}</td>
      <td class="px-3 py-2.5 text-warn/80">${escHtml(iss.description||iss.issue_type)}</td>
      <td class="px-3 py-2.5 font-mono text-steel">${escHtml(iss.current_value)}</td>
      <td class="px-3 py-2.5 min-w-[160px]">${optsHtml}</td>`;
    tbody.appendChild(tr);
  });
}
function markIssue(sel){_corrections[sel.dataset.idx]={field:sel.dataset.field,value:sel.value};}
function markIssueInput(inp){_corrections[inp.dataset.idx]={field:inp.dataset.field,value:inp.value};}

// ── Generate from raw ─────────────────────────────────────────────────────────
async function generateFromRaw(){
  document.getElementById('step-review').classList.add('hidden');
  document.getElementById('step-result-raw').classList.remove('hidden');
  document.getElementById('progress-raw').classList.remove('hidden');
  const pbar=document.getElementById('pbar-raw');
  pbar.style.width='0%'; pbar.className='h-full rounded-full shimmer transition-all duration-500';
  setTimeout(()=>pbar.style.width='60%',100);
  document.getElementById('log-box').innerHTML='';

  const fd=new FormData();
  fd.append('mode','raw');
  fd.append('corrections',JSON.stringify(_corrections));
  fd.append('output_filename',document.getElementById('output-filename').value.trim());

  const data=await requestJson('/generate',{method:'POST',body:fd});
  if(!data.ok){showRawError(data.error||'Unknown error');return;}
  _outputFilename=String(data.output||'').split(/[\\/]/).pop();

  const es=new EventSource('/stream');
  const logBox=document.getElementById('log-box');
  es.onmessage=ev=>{
    const d=JSON.parse(ev.data);
    if(d.type==='ping')return;
    if(d.type==='log'){const l=document.createElement('div');l.className='log-line text-slate-400';l.textContent='› '+d.msg;logBox.appendChild(l);logBox.scrollTop=logBox.scrollHeight;}
    if(d.type==='done'){
      es.close();
      pbar.style.width='100%';pbar.classList.remove('shimmer');pbar.style.background=d.success?'#22c55e':'#ef4444';
      if(d.success)showRawResult(d); else showRawError(d.error||'Unknown error');
    }
  };
  es.onerror=()=>{es.close();showRawError('Connection lost.');};
}

function activateFileLink(id, filename){
  if(!filename) return;
  const el = document.getElementById(id);
  if(!el) return;
  el.href     = downloadUrl(filename);
  el.download = filename;
  el.classList.remove('opacity-50','pointer-events-none');
}

function showRawResult(d){
  document.getElementById('result-raw').classList.remove('hidden');
  document.getElementById('r-depot').textContent=d.depot_count??'—';
  document.getElementById('r-triage').textContent=d.triage_count??'—';
  document.getElementById('r-subtotal').textContent=d.subtotal!=null?'$'+d.subtotal.toLocaleString('en-US',{minimumFractionDigits:2}):'—';
  document.getElementById('r-total').textContent=d.total!=null?'$'+d.total.toLocaleString('en-US',{minimumFractionDigits:2}):'—';
  // Invoice — always ready
  document.getElementById('dl-invoice').href=downloadUrl(_outputFilename);
  document.getElementById('dl-invoice').download=_outputFilename;
  // Corrected file and master filenames come in the same done payload
  activateFileLink('dl-corrected', d.corrected_filename);
  activateFileLink('dl-master',    d.master_filename);
}
function showRawError(msg){document.getElementById('error-raw').classList.remove('hidden');document.getElementById('error-raw-msg').textContent=msg;}
function backToUpload(){document.getElementById('step-review').classList.add('hidden');document.getElementById('step-upload').classList.remove('hidden');}
function backToReview(){document.getElementById('step-result-raw').classList.add('hidden');document.getElementById('step-review').classList.remove('hidden');}
function resetAll(){location.reload();}

// ── Legacy form ───────────────────────────────────────────────────────────────
document.getElementById('legacy-form')?.addEventListener('submit',async e=>{
  e.preventDefault();
  const btn=document.getElementById('legacy-btn');
  btn.disabled=true;btn.innerHTML='<span>⟳</span> Generating…';
  document.getElementById('legacy-progress').classList.remove('hidden');
  document.getElementById('legacy-result').classList.add('hidden');
  const pbar=document.getElementById('pbar-legacy');
  pbar.style.width='0%';pbar.className='h-full rounded-full shimmer transition-all duration-500';
  setTimeout(()=>pbar.style.width='60%',100);

  const fd=new FormData(e.target);
  fd.append('mode','legacy');
  const resetButton=()=>{btn.disabled=false;btn.innerHTML='<span>⚡</span> Generate Invoice';};
  const data=await requestJson('/generate',{method:'POST',body:fd});
  if(!data.ok){resetButton();document.getElementById('legacy-progress').classList.add('hidden');alert('Error: '+(data.error||'Unknown'));return;}
  const filename=String(data.output||'').split(/[\\/]/).pop();

  const es=new EventSource('/stream');
  es.onerror=()=>{
    es.close();resetButton();
    pbar.style.width='100%';pbar.classList.remove('shimmer');pbar.style.background='#ef4444';
    alert('Error: Connection lost while generating. Check the output list before generating again.');
  };
  es.onmessage=ev=>{
    const d=JSON.parse(ev.data);
    if(d.type==='done'){
      es.close();pbar.style.width='100%';pbar.classList.remove('shimmer');pbar.style.background=d.success?'#22c55e':'#ef4444';
      btn.disabled=false;btn.innerHTML='<span>⚡</span> Generate Invoice';
      if(d.success){
        document.getElementById('l-depot').textContent=d.depot_count??'—';
        document.getElementById('l-triage').textContent=d.triage_count??'—';
        document.getElementById('l-subtotal').textContent=d.subtotal!=null?'$'+d.subtotal.toLocaleString('en-US',{minimumFractionDigits:2}):'—';
        document.getElementById('l-total').textContent=d.total!=null?'$'+d.total.toLocaleString('en-US',{minimumFractionDigits:2}):'—';
        const dlLink=document.getElementById('dl-legacy');
        dlLink.href=downloadUrl(filename);dlLink.download=filename;
        document.getElementById('legacy-result').classList.remove('hidden');
      } else {alert('Error: '+(d.error||'Unknown'));}
    }
  };
});
function resetLegacy(){document.getElementById('legacy-result').classList.add('hidden');document.getElementById('legacy-progress').classList.add('hidden');}

// ══════════════════════════════════════════════════════════
// SERIAL CONFIG PAGE
// ══════════════════════════════════════════════════════════

function showCfgStatus(ok, message){
  const status=document.getElementById('cfg-status');
  if(!status) return;
  status.className='mb-4 px-4 py-2 rounded-lg text-sm font-mono '+(ok
    ?'bg-ok/10 border border-ok/30 text-ok'
    :'bg-warn/10 border border-warn/30 text-warn');
  status.textContent=message;
  clearTimeout(showCfgStatus._t);
  showCfgStatus._t=setTimeout(()=>status.classList.add('hidden'),ok?4000:8000);
}

async function loadCfg(){
  const data=await requestJson('/config/serial_rules');
  if(data.ok===false || !Array.isArray(data.rules)){
    showCfgStatus(false,'✗ Could not load serial rules: '+(data.error||'unexpected response'));
    return;
  }
  renderCfgTable(data.rules);
}

function renderCfgTable(rules){
  const tbody=document.getElementById('cfg-tbody');
  tbody.innerHTML='';
  rules.forEach((r,i)=>tbody.appendChild(makeCfgRow(r,i)));
}

function makeCfgRow(r,i){
  const tr=document.createElement('tr');
  tr.className='cfg-row border-b border-steel/10';
  tr.dataset.idx=i;
  const o2opts=['year_pos5','year_pos6','always','never'];
  const o2labels=['Year char (pos 5)','Year char (pos 6)','Always -02','Never -02'];
  const o2html=o2opts.map((v,j)=>`<option value="${v}"${r.o2_rule===v?' selected':''}>${o2labels[j]}</option>`).join('');
  const yearPos=(r.year_pos===0||r.year_pos)?r.year_pos:'';
  tr.innerHTML=`
    <td class="px-2 py-1.5"><input class="cfg-input font-mono" value="${escHtml(r.prefix)}" placeholder="e.g. 775T" data-field="prefix" aria-label="Serial prefix" /></td>
    <td class="px-2 py-1.5"><input class="cfg-input font-mono w-12 text-center" value="${escHtml(yearPos)}" placeholder="5" data-field="year_pos" title="Position of year character in serial (0-indexed)" aria-label="Year position" /></td>
    <td class="px-2 py-1.5"><input class="cfg-input" value="${escHtml(r.model_base)}" placeholder="e.g. AP7-B75" data-field="model_base" aria-label="Model base" /></td>
    <td class="px-2 py-1.5"><select class="cfg-select" data-field="size" aria-label="Size">
      ${['55','65','70','75','86'].map(s=>`<option${r.size===s?' selected':''}>${s}"</option>`).join('')}
    </select></td>
    <td class="px-2 py-1.5"><select class="cfg-select" data-field="o2_rule" aria-label="-02 rule">${o2html}</select></td>
    <td class="px-2 py-1.5 text-center"><button type="button" aria-label="Delete rule" onclick="deleteCfgRow(this)" class="text-steel hover:text-warn transition-colors text-base" title="Delete row">✕</button></td>`;
  return tr;
}

function addCfgRow(){
  const tbody=document.getElementById('cfg-tbody');
  const i=tbody.children.length;
  tbody.appendChild(makeCfgRow({prefix:'',year_pos:'5',model_base:'',size:'75',o2_rule:'year_pos5'},i));
}

function deleteCfgRow(btn){
  btn.closest('tr').remove();
}

function collectCfgRules(){
  return Array.from(document.querySelectorAll('#cfg-tbody tr')).map(tr=>{
    const get=f=>tr.querySelector(`[data-field="${f}"]`)?.value?.trim()||'';
    const yearPos=parseInt(get('year_pos'),10);
    return {prefix:get('prefix'),year_pos:Number.isInteger(yearPos)&&yearPos>=0?yearPos:5,model_base:get('model_base'),size:get('size').replace('"',''),o2_rule:get('o2_rule')};
  }).filter(r=>r.prefix&&r.model_base);
}

async function saveCfg(){
  const rules=collectCfgRules();
  const data=await requestJson('/config/serial_rules',{
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({rules})
  });
  if(data.ok) showCfgStatus(true,`✓ Saved ${rules.length} rules successfully`);
  else showCfgStatus(false,'✗ Save failed: '+(data.error||'Unknown error'));
}

// ── Theme toggle ──────────────────────────────────────────────────────────────
function persistThemePreference(preference) {
  fetch('/account/theme', {
    method: 'POST',
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: new URLSearchParams({theme: preference}).toString()
  }).catch(() => {});
}

function toggleTheme() {
  const html = document.documentElement;
  const next = html.dataset.theme === 'light' ? 'dark' : 'light';
  if (window.ussiApplyThemePreference) window.ussiApplyThemePreference(next);
  else html.dataset.theme = next;
  const label = document.getElementById('toggle-label');
  if (label) label.textContent = next === 'light' ? '🌙' : '☀';
  persistThemePreference(next);
}

window.addEventListener('DOMContentLoaded', () => {
  const label = document.getElementById('toggle-label');
  if (label) label.textContent = document.documentElement.dataset.theme === 'light' ? '🌙' : '☀';
});

// ── About modal ───────────────────────────────────────────────────────────────
function showAbout() { document.getElementById('about-modal').classList.remove('hidden'); }
function hideAbout() { document.getElementById('about-modal').classList.add('hidden'); }
document.addEventListener('keydown', e => { if(e.key==='Escape') hideAbout(); });

// ── Storage Invoice Form ───────────────────────────────────────────────────────
(function() {
  // ── Storage file drop-zones ───────────────────────────────────────────────
  const sZones = [
    {zone:'sz-inv',   file:'s-inv',   icon:'icon-s-inv',   lbl:'lbl-s-inv'},
    {zone:'sz-ship',  file:'s-ship',  icon:'icon-s-ship',  lbl:'lbl-s-ship'},
    {zone:'sz-recv',  file:'s-recv',  icon:'icon-s-recv',  lbl:'lbl-s-recv'},
    {zone:'sz-fedex', file:'s-fedex', icon:'icon-s-fedex', lbl:'lbl-s-fedex'},
    {zone:'sz-wl',    file:'s-wl',    icon:'icon-s-wl',    lbl:'lbl-s-wl', optional:true},
  ];
  sZones.forEach(({zone,file,icon,lbl,optional})=>{
    const inp = document.getElementById(file);
    const zn  = document.getElementById(zone);
    if (!inp) return;
    inp.addEventListener('change',()=>{
      if(inp.files[0]){
        document.getElementById(lbl).textContent = inp.files[0].name + (optional?' (will override built-in)':'');
        zn.classList.add('filled');
        document.getElementById(icon).textContent = optional ? '🔄' : '✅';
      }
    });
    ['dragover','dragleave','drop'].forEach(ev=>zn.addEventListener(ev,e=>{
      e.preventDefault();
      if(ev==='dragover') zn.classList.add('dragover');
      else { zn.classList.remove('dragover'); if(ev==='drop'){ inp.files=e.dataTransfer.files; inp.dispatchEvent(new Event('change')); }}
    }));
  });

  // Pre-fill dates
  ['s-date-from'].forEach(id=>{const el=document.getElementById(id);if(el)el.value=fmt(firstOfMonth);});
  ['s-date-to','s-invoice-date','s-completed-date'].forEach(id=>{const el=document.getElementById(id);if(el)el.value=fmt(today);});

  // ── State ─────────────────────────────────────────────────────────────────
  let _sReviewData = {};   // analysis result from /analyze_storage

  // ── Step navigation ───────────────────────────────────────────────────────
  function sBackToUpload() {
    document.getElementById('s-step-upload').classList.remove('hidden');
    document.getElementById('s-step-review').classList.add('hidden');
    document.getElementById('s-result-card').classList.add('hidden');
    document.getElementById('s-log-wrap').classList.add('hidden');
  }

  // ── Analyze submit ────────────────────────────────────────────────────────
  const sForm = document.getElementById('storage-form');
  if (sForm) sForm.addEventListener('submit', async e => {
    e.preventDefault();
    const btn = document.getElementById('s-gen-btn');
    btn.disabled = true; btn.textContent = 'Analyzing…';

    const logWrap = document.getElementById('s-analyze-log-wrap');
    const logBox  = document.getElementById('s-analyze-log');
    logWrap.classList.remove('hidden');
    logBox.innerHTML = '';

    const fd = new FormData(sForm);
    let resp, data;
    try {
      resp = await fetch('/analyze_storage', {method:'POST', body:fd});
      data = await readJson(resp);
    } catch(err) {
      logBox.innerHTML = `<div class="text-warn">❌ Network error: ${escHtml(err)}</div>`;
      btn.disabled = false; btn.textContent = 'Analyze Files →';
      return;
    }

    (data.logs || []).forEach(m => {
      const d = document.createElement('div'); d.textContent = '› ' + m; logBox.appendChild(d);
    });

    if (!data.ok) {
      const d = document.createElement('div');
      d.className = 'text-warn'; d.textContent = '❌ ' + (data.error || 'Failed');
      logBox.appendChild(d);
      btn.disabled = false; btn.textContent = 'Analyze Files →';
      return;
    }

    _sReviewData = data;
    btn.disabled = false; btn.textContent = 'Analyze Files →';
    sShowReview(data);
  });

  // ── Populate review step ──────────────────────────────────────────────────
  function sShowReview(data) {
    document.getElementById('s-step-upload').classList.add('hidden');
    document.getElementById('s-step-review').classList.remove('hidden');

    document.getElementById('s-review-summary').innerHTML = [
      {label:'Unit Storage',     val: (data.unit_storage_count||0).toLocaleString() + ' units'},
      {label:'Small Parts',      val: (data.auto_spc_count||0).toLocaleString() + ' parts'},
      {label:'FedEx Part Rows',  val: (data.programming_rows||0).toLocaleString() + ' rows'},
      {label:'Unmatched Items',  val: (data.unmatched_count||0).toLocaleString() + ' → extra tab'},
    ].map(s=>`<div class="text-center"><div class="text-steel font-mono uppercase text-xs mb-1">${s.label}</div><div class="text-slate-100 font-semibold font-mono">${s.val}</div></div>`).join('');

    const uc = document.getElementById('s-unmatched-count');
    if (uc) uc.textContent = (data.unmatched_count||0).toLocaleString();
  }

  // ── Checkbox helpers ──────────────────────────────────────────────────────
  window.sSelectAll  = (tblId) => document.querySelectorAll(`#${tblId} input[type=checkbox]`).forEach(c=>c.checked=true);
  window.sSelectNone = (tblId) => document.querySelectorAll(`#${tblId} input[type=checkbox]`).forEach(c=>c.checked=false);
  window.sToggleAll  = (tblId, checked) => document.querySelectorAll(`#${tblId} input[type=checkbox]:not(#chk-no-rma-all):not(#chk-recv-all)`).forEach(c=>c.checked=checked);

  // ── Confirm + Generate ────────────────────────────────────────────────────
  window.sConfirmAndGenerate = async function() {
    const btn = document.getElementById('s-confirm-btn');
    btn.disabled = true; btn.textContent = 'Generating…';

    document.getElementById('s-log-wrap').classList.remove('hidden');
    document.getElementById('s-result-card').classList.add('hidden');
    document.getElementById('s-log-box').innerHTML = '';
    document.getElementById('s-progress-bar').classList.remove('hidden');

    const data = await requestJson('/confirm_storage', {
      method:'POST', headers:{'Content-Type':'application/json'}, body:'{}'
    });
    if (!data.ok) {
      sLog('❌ ' + (data.error||'Error starting generation'));
      document.getElementById('s-progress-bar').classList.add('hidden');
      btn.disabled=false; btn.textContent='Generate Invoice →';
      return;
    }

    const es = new EventSource('/stream_storage');
    es.onmessage = ev => {
      const msg = JSON.parse(ev.data);
      if (msg.type==='ping') return;
      if (msg.type==='log') { sLog(msg.msg); return; }
      if (msg.type==='done') {
        es.close();
        document.getElementById('s-progress-bar').classList.add('hidden');
        btn.disabled=false; btn.textContent='Generate Invoice →';
        if (msg.success) showStorageResult(msg);
        else sLog('❌ ' + (msg.error||'Failed'));
      }
    };
    es.onerror = () => { es.close(); document.getElementById('s-progress-bar').classList.add('hidden'); sLog('⚠ Connection lost'); btn.disabled=false; btn.textContent='Generate Invoice →'; };
  };

  function sLog(msg) {
    const box = document.getElementById('s-log-box');
    const line = document.createElement('div'); line.className='log-line'; line.textContent='› '+msg;
    box.appendChild(line); box.scrollTop = box.scrollHeight;
  }

  function showStorageResult(msg) {
    document.getElementById('s-result-card').classList.remove('hidden');
    document.getElementById('s-result-filename').textContent = msg.filename||'';
    document.getElementById('s-download-btn').href = downloadUrl(msg.filename);
    const fmt$ = n=>'$'+Number(n||0).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
    const fmtN = n=>Number(n||0).toLocaleString();
    const stats=[
      {label:'Unit Storage',   val:fmtN(msg.unit_storage_count)+' units'},
      {label:'Pallet Storage', val:fmtN(msg.pallet_count)+' pallets'},
      {label:'Units Received', val:fmtN(msg.units_received_count)},
      {label:'Parts Check-In', val:fmtN(msg.small_parts_count)},
      {label:'Unit Picks',     val:fmtN(msg.unit_picks_count)},
      {label:'Part Orders',    val:fmtN(msg.small_part_picks)},
    ];
    document.getElementById('s-result-stats').innerHTML =
      stats.map(s=>`<div class="bg-ink-100/50 rounded-lg p-3 border border-steel/20"><div class="text-xs text-steel font-mono uppercase mb-1">${s.label}</div><div class="text-slate-100 font-semibold font-mono">${s.val}</div></div>`).join('');
    document.getElementById('s-subtotal').textContent = fmt$(msg.subtotal);
    document.getElementById('s-tax').textContent      = fmt$(msg.tax);
    document.getElementById('s-total').textContent    = fmt$(msg.total);
  }

})();

// ── FedEx Shipment Upload Form ────────────────────────────────────────────────
(function() {
  function fxBackToUpload() {
    document.getElementById('fx-step-upload').classList.remove('hidden');
    document.getElementById('fx-step-review').classList.add('hidden');
    document.getElementById('fx-result-card').classList.add('hidden');
    document.getElementById('fx-log-wrap').classList.add('hidden');
  }
  window.fxBackToUpload = fxBackToUpload;

  const fxForm = document.getElementById('fedex-shipment-form');
  if (fxForm) fxForm.addEventListener('submit', async e => {
    e.preventDefault();
    const btn = document.getElementById('fx-gen-btn');
    btn.disabled = true; btn.textContent = 'Analyzing…';

    const logWrap = document.getElementById('fx-analyze-log-wrap');
    const logBox  = document.getElementById('fx-analyze-log');
    logWrap.classList.remove('hidden');
    logBox.innerHTML = '';

    const fd = new FormData(fxForm);
    let resp, data;
    try {
      resp = await fetch('/analyze_fedex_shipment', {method:'POST', body:fd});
      data = await readJson(resp);
    } catch(err) {
      logBox.innerHTML = `<div class="text-warn">❌ Network error: ${escHtml(err)}</div>`;
      btn.disabled = false; btn.textContent = 'Analyze File →';
      return;
    }

    (data.logs || []).forEach(m => {
      const d = document.createElement('div'); d.textContent = '› ' + m; logBox.appendChild(d);
    });

    if (!data.ok) {
      const d = document.createElement('div');
      d.className = 'text-warn'; d.textContent = '❌ ' + (data.error || 'Failed');
      logBox.appendChild(d);
      btn.disabled = false; btn.textContent = 'Analyze File →';
      return;
    }

    btn.disabled = false; btn.textContent = 'Analyze File →';
    fxShowReview(data);
  });

  function fxShowReview(data) {
    document.getElementById('fx-step-upload').classList.add('hidden');
    document.getElementById('fx-step-review').classList.remove('hidden');

    const fmt$ = n=>'$'+Number(n||0).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
    document.getElementById('fx-review-summary').innerHTML = [
      {label:'Call Rows',       val: (data.row_count||0).toLocaleString()},
      {label:'Total Billed',    val: fmt$(data.total_price)},
      {label:'Used Default Site', val: (data.defaulted_rows||[]).length.toLocaleString()},
    ].map(s=>`<div class="text-center"><div class="text-steel font-mono uppercase text-xs mb-1">${s.label}</div><div class="text-slate-100 font-semibold font-mono">${s.val}</div></div>`).join('');

    const defaulted = data.defaulted_rows || [];
    document.getElementById('fx-defaulted-count').textContent = defaulted.length.toLocaleString();
    document.getElementById('fx-defaulted-list').innerHTML = defaulted.slice(0, 25).map(r =>
      `<div class="font-mono">› ${escHtml(r.tracking)}${r.po ? ' · PO ' + escHtml(r.po) : ''}</div>`).join('') +
      (defaulted.length > 25 ? `<div class="font-mono">…and ${defaulted.length - 25} more</div>` : '');

    const skipped = data.skipped_rows || [];
    const skippedWrap = document.getElementById('fx-skipped-wrap');
    skippedWrap.classList.toggle('hidden', skipped.length === 0);
    document.getElementById('fx-skipped-count').textContent = skipped.length.toLocaleString();
    document.getElementById('fx-skipped-list').innerHTML = skipped.slice(0, 25).map(r =>
      `<div class="font-mono">› row ${escHtml(r.row)}${r.tracking ? ' · ' + escHtml(r.tracking) : ''} — ${escHtml(r.reason)}</div>`).join('') +
      (skipped.length > 25 ? `<div class="font-mono">…and ${skipped.length - 25} more</div>` : '');
  }

  window.fxConfirmAndBuild = async function() {
    const btn = document.getElementById('fx-confirm-btn');
    btn.disabled = true; btn.textContent = 'Building…';

    document.getElementById('fx-log-wrap').classList.remove('hidden');
    document.getElementById('fx-result-card').classList.add('hidden');
    document.getElementById('fx-log-box').innerHTML = '';
    document.getElementById('fx-progress-bar').classList.remove('hidden');

    const data = await requestJson('/build_fedex_shipment', {
      method:'POST', headers:{'Content-Type':'application/json'}, body:'{}'
    });
    if (!data.ok) {
      fxLog('❌ ' + (data.error||'Error starting build'));
      document.getElementById('fx-progress-bar').classList.add('hidden');
      btn.disabled=false; btn.textContent='Build Upload File →';
      return;
    }

    const es = new EventSource('/stream_fedex_shipment');
    es.onmessage = ev => {
      const msg = JSON.parse(ev.data);
      if (msg.type==='ping') return;
      if (msg.type==='log') { fxLog(msg.msg); return; }
      if (msg.type==='done') {
        es.close();
        document.getElementById('fx-progress-bar').classList.add('hidden');
        btn.disabled=false; btn.textContent='Build Upload File →';
        if (msg.success) showFxResult(msg);
        else fxLog('❌ ' + (msg.error||'Failed'));
      }
    };
    es.onerror = () => { es.close(); document.getElementById('fx-progress-bar').classList.add('hidden'); fxLog('⚠ Connection lost'); btn.disabled=false; btn.textContent='Build Upload File →'; };
  };

  function fxLog(msg) {
    const box = document.getElementById('fx-log-box');
    const line = document.createElement('div'); line.className='log-line'; line.textContent='› '+msg;
    box.appendChild(line); box.scrollTop = box.scrollHeight;
  }

  function showFxResult(msg) {
    document.getElementById('fx-result-card').classList.remove('hidden');
    document.getElementById('fx-result-filename').textContent = msg.filename||'';
    document.getElementById('fx-download-btn').href = downloadUrl(msg.filename);
    const fmt$ = n=>'$'+Number(n||0).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
    const fmtN = n=>Number(n||0).toLocaleString();
    const stats=[
      {label:'Call Rows',     val:fmtN(msg.row_count)},
      {label:'Total Billed',  val:fmt$(msg.total_price)},
      {label:'Used Default Site', val:fmtN(msg.defaulted_count)},
    ];
    document.getElementById('fx-result-stats').innerHTML =
      stats.map(s=>`<div class="bg-ink-100/50 rounded-lg p-3 border border-steel/20"><div class="text-xs text-steel font-mono uppercase mb-1">${s.label}</div><div class="text-slate-100 font-semibold font-mono">${s.val}</div></div>`).join('');
  }
})();

// ── Philips Invoice Form ─────────────────────────────────────────────────────
(function() {
  function setupDropZone(inputId, zoneId, iconId, lblId, icon) {
    const inp = document.getElementById(inputId);
    const zn  = document.getElementById(zoneId);
    if (!inp || !zn) return;
    inp.addEventListener('change', () => {
      if (inp.files[0]) {
        document.getElementById(lblId).textContent = inp.files[0].name;
        zn.classList.add('filled');
        document.getElementById(iconId).textContent = '✅';
      }
    });
    ['dragover','dragleave','drop'].forEach(ev=>zn.addEventListener(ev,e=>{
      e.preventDefault();
      if(ev==='dragover') zn.classList.add('dragover');
      else { zn.classList.remove('dragover'); if(ev==='drop'){ inp.files=e.dataTransfer.files; inp.dispatchEvent(new Event('change')); }}
    }));
  }
  setupDropZone('p-report', 'pz-report', 'icon-p-report', 'lbl-p-report');
  setupDropZone('p-raw',    'pz-raw',    'icon-p-raw',    'lbl-p-raw');

  // ── Tab switcher ──────────────────────────────────────────────────────────
  window.pSwitchTab = function(tab) {
    document.getElementById('p-pane-raw').classList.toggle('hidden', tab!=='raw');
    document.getElementById('p-pane-report').classList.toggle('hidden', tab!=='report');
    document.getElementById('p-tab-raw').classList.toggle('active', tab==='raw');
    document.getElementById('p-tab-report').classList.toggle('active', tab==='report');
    document.getElementById('p-tab-raw').classList.toggle('text-steel', tab!=='raw');
    document.getElementById('p-tab-report').classList.toggle('text-steel', tab!=='report');
  };

  // Default the raw-data period to last calendar month
  const lastMonthEnd   = new Date(today.getFullYear(), today.getMonth(), 0);
  const lastMonthStart = new Date(lastMonthEnd.getFullYear(), lastMonthEnd.getMonth(), 1);
  const ps = document.getElementById('p-period-start'); if (ps) ps.value = fmt(lastMonthStart);
  const pe = document.getElementById('p-period-end');   if (pe) pe.value = fmt(lastMonthEnd);

  function pBackToUpload() {
    document.getElementById('p-step-upload').classList.remove('hidden');
    document.getElementById('p-step-review').classList.add('hidden');
    document.getElementById('p-result-card').classList.add('hidden');
    document.getElementById('p-log-wrap').classList.add('hidden');
  }
  window.pBackToUpload = pBackToUpload;

  function pLog(msg) {
    const box = document.getElementById('p-log-box');
    const line = document.createElement('div'); line.className='log-line'; line.textContent='› '+msg;
    box.appendChild(line); box.scrollTop = box.scrollHeight;
  }

  async function pRunAnalyze(url, form, btn, defaultLabel) {
    btn.disabled = true; btn.textContent = 'Analyzing…';
    const logWrap = document.getElementById('p-analyze-log-wrap');
    const logBox  = document.getElementById('p-analyze-log');
    logWrap.classList.remove('hidden');
    logBox.innerHTML = '';

    const fd = new FormData(form);
    let resp, data;
    try {
      resp = await fetch(url, {method:'POST', body:fd});
      data = await readJson(resp);
    } catch(err) {
      logBox.innerHTML = `<div class="text-warn">❌ Network error: ${escHtml(err)}</div>`;
      btn.disabled = false; btn.textContent = defaultLabel;
      return;
    }
    (data.logs || []).forEach(m => {
      const d = document.createElement('div'); d.textContent = '› ' + m; logBox.appendChild(d);
    });
    if (!data.ok) {
      const d = document.createElement('div');
      d.className = 'text-warn'; d.textContent = '❌ ' + (data.error || 'Failed');
      logBox.appendChild(d);
      btn.disabled = false; btn.textContent = defaultLabel;
      return;
    }
    btn.disabled = false; btn.textContent = defaultLabel;
    pShowReview(data);
  }

  const pForm = document.getElementById('philips-form');
  if (pForm) pForm.addEventListener('submit', e => {
    e.preventDefault();
    pRunAnalyze('/analyze_philips', pForm, document.getElementById('p-gen-btn'), 'Analyze →');
  });

  const pRawForm = document.getElementById('philips-raw-form');
  if (pRawForm) pRawForm.addEventListener('submit', e => {
    e.preventDefault();
    pRunAnalyze('/generate_report_and_analyze', pRawForm, document.getElementById('p-raw-gen-btn'), 'Build Report & Analyze →');
  });

  function pShowReview(data) {
    document.getElementById('p-step-upload').classList.add('hidden');
    document.getElementById('p-step-review').classList.remove('hidden');
    document.getElementById('p-result-card').classList.add('hidden');
    document.getElementById('p-log-wrap').classList.add('hidden');

    document.getElementById('p-review-summary').innerHTML = [
      {label:'Inbound',           val: (data.inbound_count||0).toLocaleString() + ' units'},
      {label:'Outbound',          val: (data.outbound_count||0).toLocaleString() + ' units'},
      {label:'Repaired',          val: (data.repair_count||0).toLocaleString() + ' units'},
      {label:'Harvested',         val: (data.harvest_count||0).toLocaleString() + ' units'},
    ].map(s=>`<div class="text-center"><div class="text-steel font-mono uppercase text-xs mb-1">${s.label}</div><div class="text-slate-100 font-semibold font-mono">${s.val}</div></div>`).join('');

    // Report summary — only present when built from raw data this session
    const reportWrap = document.getElementById('p-report-summary');
    if (data.report_filename) {
      reportWrap.classList.remove('hidden');
      document.getElementById('p-report-download-btn').href = downloadUrl(data.report_filename);
      const flagged = data.flagged_received_count||0, pending = data.pending_repairs_count||0;
      document.getElementById('p-report-flagged-note').textContent =
        `${flagged.toLocaleString()} received row(s) flagged for review, ${pending.toLocaleString()} repair(s) still pending — both included as informational tabs.`;
    } else {
      reportWrap.classList.add('hidden');
    }

    const missing = data.missing_dimension_models || [];
    const wrap = document.getElementById('p-missing-dims-wrap');
    const none = document.getElementById('p-no-missing-dims');
    if (missing.length) {
      wrap.classList.remove('hidden'); none.classList.add('hidden');
      document.getElementById('p-missing-dims-list').innerHTML = missing.map(m => `
        <div class="flex items-center gap-3">
          <span class="text-slate-200 text-xs font-mono flex-1 truncate">${escHtml(m)}</span>
          <span class="text-steel text-xs">sq ft</span>
          <input type="number" step="0.01" min="0" placeholder="skip"
            class="p-missing-dim-input w-28 bg-ink-100 border border-steel/50 rounded-lg px-3 py-1.5 text-sm text-slate-200"
            aria-label="Square feet for ${escHtml(m)}" data-model="${escHtml(m)}" />
        </div>`).join('');
    } else {
      wrap.classList.add('hidden'); none.classList.remove('hidden');
    }
  }

  // ── Confirm + Generate ────────────────────────────────────────────────────
  window.pConfirmAndGenerate = async function() {
    const btn = document.getElementById('p-confirm-btn');
    // Blank means "skip"; anything else must be a non-negative number. Checked
    // before any request so a typo cannot silently change billed square footage.
    const dimensions = {};
    const badDims = [];
    document.querySelectorAll('.p-missing-dim-input').forEach(inp => {
      inp.classList.remove('border-warn');
      if (String(inp.value).trim() === '' && !(inp.validity && inp.validity.badInput)) return;
      const n = nonNegativeValue(inp);
      if (Number.isNaN(n)) { badDims.push(inp.dataset.model); inp.classList.add('border-warn'); }
      else dimensions[inp.dataset.model] = n;
    });
    document.getElementById('p-log-wrap').classList.remove('hidden');
    document.getElementById('p-result-card').classList.add('hidden');
    document.getElementById('p-log-box').innerHTML = '';
    if (badDims.length) {
      pLog('❌ Enter a square footage of 0 or more (or leave blank to skip) for: ' + badDims.join(', '));
      return;
    }
    btn.disabled = true; btn.textContent = 'Generating…';
    document.getElementById('p-progress-bar').classList.remove('hidden');

    let resp, data;
    try {
      resp = await fetch('/confirm_philips', {
        method:'POST', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({dimensions})
      });
      data = await readJson(resp);
    } catch(err) {
      pLog('❌ Network error: ' + err);
      btn.disabled=false; btn.textContent='Generate Invoice →';
      return;
    }
    if (!data.ok) {
      pLog('❌ ' + (data.error||'Error starting generation'));
      document.getElementById('p-progress-bar').classList.add('hidden');
      btn.disabled=false; btn.textContent='Generate Invoice →';
      return;
    }

    const es = new EventSource('/stream_philips');
    es.onmessage = ev => {
      const msg = JSON.parse(ev.data);
      if (msg.type==='ping') return;
      if (msg.type==='log') { pLog(msg.msg); return; }
      if (msg.type==='done') {
        es.close();
        document.getElementById('p-progress-bar').classList.add('hidden');
        btn.disabled=false; btn.textContent='Generate Invoice →';
        if (msg.success) pShowResult(msg);
        else pLog('❌ ' + (msg.error||'Failed'));
      }
    };
    es.onerror = () => { es.close(); document.getElementById('p-progress-bar').classList.add('hidden'); pLog('⚠ Connection lost'); btn.disabled=false; btn.textContent='Generate Invoice →'; };
  };

  function pShowResult(msg) {
    document.getElementById('p-result-card').classList.remove('hidden');
    document.getElementById('p-result-filename').textContent = msg.filename||'';
    document.getElementById('p-download-btn').href = downloadUrl(msg.filename);
    const reportBtn = document.getElementById('p-result-report-btn');
    if (msg.report_filename) {
      reportBtn.classList.remove('hidden');
      reportBtn.href = downloadUrl(msg.report_filename);
    } else {
      reportBtn.classList.add('hidden');
    }
    const fmt$ = n=>'$'+Number(n||0).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
    const fmtN = n=>Number(n||0).toLocaleString();
    const stats=[
      {label:'Inbound Handling',  val:fmtN(msg.inbound_count)+' units'},
      {label:'Outbound Handling', val:fmtN(msg.outbound_count)+' units'},
      {label:'Repaired',          val:fmtN(msg.repair_count)+' units'},
      {label:'Harvested',         val:fmtN(msg.harvest_count)+' units'},
    ];
    document.getElementById('p-result-stats').innerHTML =
      stats.map(s=>`<div class="bg-ink-100/50 rounded-lg p-3 border border-steel/20"><div class="text-xs text-steel font-mono uppercase mb-1">${s.label}</div><div class="text-slate-100 font-semibold font-mono">${s.val}</div></div>`).join('');
    const excluded = msg.excluded_count||0;
    const note = document.getElementById('p-excluded-note');
    note.innerHTML = excluded > 0
      ? `<span class="text-accent font-mono font-semibold">Excluded Items →</span> <span class="text-slate-300">${excluded}</span> row(s) still had no match and were left out of the totals — check the <strong class="text-slate-300">"Excluded Items"</strong> tab in the output file.`
      : `<span class="text-ok font-mono font-semibold">✓</span> <span class="text-slate-300">No excluded items — every row matched the Dimensions / Repair Cost reference.</span>`;
    document.getElementById('p-subtotal').textContent = fmt$(msg.subtotal);
    document.getElementById('p-tax').textContent      = fmt$(msg.tax);
    document.getElementById('p-total').textContent    = fmt$(msg.total);
  }
})();

// ── AMC Warehouse Invoice ─────────────────────────────────────────────────────
(function() {
  function setupDropZone(inputId, zoneId, iconId, lblId, icon) {
    const input = document.getElementById(inputId);
    if (!input) return;
    input.addEventListener('change', () => {
      const zone = document.getElementById(zoneId);
      const lbl  = document.getElementById(lblId);
      if (input.files[0]) {
        zone.classList.add('filled');
        lbl.textContent = input.files[0].name;
        document.getElementById(iconId).textContent = '✅';
      }
    });
  }
  setupDropZone('a-recv', 'az-recv', 'icon-a-recv', 'lbl-a-recv');
  setupDropZone('a-ship', 'az-ship', 'icon-a-ship', 'lbl-a-ship');
  setupDropZone('a-inv',  'az-inv',  'icon-a-inv',  'lbl-a-inv');

  window.aBackToUpload = function() {
    document.getElementById('a-step-upload').classList.remove('hidden');
    document.getElementById('a-step-review').classList.add('hidden');
    document.getElementById('a-result-card').classList.add('hidden');
    document.getElementById('a-log-wrap').classList.add('hidden');
  };

  const aForm = document.getElementById('amc-form');
  if (aForm) aForm.addEventListener('submit', async e => {
    e.preventDefault();
    const btn = document.getElementById('a-gen-btn');
    btn.disabled = true; btn.textContent = 'Analyzing…';

    const logWrap = document.getElementById('a-analyze-log-wrap');
    const logBox  = document.getElementById('a-analyze-log');
    logWrap.classList.remove('hidden');
    logBox.innerHTML = '';

    const fd = new FormData(aForm);
    let resp, data;
    try {
      resp = await fetch('/analyze_amc', {method:'POST', body:fd});
      data = await readJson(resp);
    } catch(err) {
      logBox.innerHTML = `<div class="text-warn">❌ Network error: ${escHtml(err)}</div>`;
      btn.disabled = false; btn.textContent = 'Analyze →';
      return;
    }

    (data.logs || []).forEach(m => {
      const d = document.createElement('div'); d.textContent = '› ' + m; logBox.appendChild(d);
    });

    if (!data.ok) {
      const d = document.createElement('div');
      d.className = 'text-warn'; d.textContent = '❌ ' + (data.error || 'Failed');
      logBox.appendChild(d);
      btn.disabled = false; btn.textContent = 'Analyze →';
      return;
    }
    btn.disabled = false; btn.textContent = 'Analyze →';
    aShowReview(data);
  });

  function aShowReview(data) {
    document.getElementById('a-step-upload').classList.add('hidden');
    document.getElementById('a-step-review').classList.remove('hidden');
    document.getElementById('a-result-card').classList.add('hidden');
    document.getElementById('a-log-wrap').classList.add('hidden');

    document.getElementById('a-review-summary').innerHTML = [
      {label:'Received',    val: (data.receipt_count||0).toLocaleString() + ' units'},
      {label:'Shipped',     val: (data.ship_count||0).toLocaleString() + ' units'},
      {label:'Billable Sq Ft', val: (data.additional_sqft||0).toLocaleString() + ' sq ft'},
    ].map(s=>`<div class="text-center"><div class="text-steel font-mono uppercase text-xs mb-1">${s.label}</div><div class="text-slate-100 font-semibold font-mono">${s.val}</div></div>`).join('');

    const missing = data.missing_dimension_models || [];
    const wrap = document.getElementById('a-missing-dims-wrap');
    const none = document.getElementById('a-no-missing-dims');
    if (missing.length) {
      wrap.classList.remove('hidden'); none.classList.add('hidden');
      document.getElementById('a-missing-dims-list').innerHTML = missing.map(m => `
        <div class="flex items-center gap-3">
          <span class="text-slate-200 text-xs font-mono flex-1 truncate">${escHtml(m)}</span>
          <span class="text-steel text-xs">sq ft</span>
          <input type="number" step="0.01" min="0" placeholder="skip"
            class="a-missing-dim-input w-28 bg-ink-100 border border-steel/50 rounded-lg px-3 py-1.5 text-sm text-slate-200"
            aria-label="Square feet for ${escHtml(m)}" data-model="${escHtml(m)}" />
        </div>`).join('');
    } else {
      wrap.classList.add('hidden'); none.classList.remove('hidden');
    }
  }

  // ── Confirm + Generate ────────────────────────────────────────────────────
  window.aConfirmAndGenerate = async function() {
    const btn = document.getElementById('a-confirm-btn');
    // Blank means "skip"; anything else must be a non-negative number. Checked
    // before any request so a typo cannot silently change billed square footage.
    const dimensions = {};
    const badDims = [];
    document.querySelectorAll('.a-missing-dim-input').forEach(inp => {
      inp.classList.remove('border-warn');
      if (String(inp.value).trim() === '' && !(inp.validity && inp.validity.badInput)) return;
      const n = nonNegativeValue(inp);
      if (Number.isNaN(n)) { badDims.push(inp.dataset.model); inp.classList.add('border-warn'); }
      else dimensions[inp.dataset.model] = n;
    });
    document.getElementById('a-log-wrap').classList.remove('hidden');
    document.getElementById('a-result-card').classList.add('hidden');
    document.getElementById('a-log-box').innerHTML = '';
    if (badDims.length) {
      aLog('❌ Enter a square footage of 0 or more (or leave blank to skip) for: ' + badDims.join(', '));
      return;
    }
    btn.disabled = true; btn.textContent = 'Generating…';
    document.getElementById('a-progress-bar').classList.remove('hidden');

    let resp, data;
    try {
      resp = await fetch('/confirm_amc', {
        method:'POST', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({dimensions})
      });
      data = await readJson(resp);
    } catch(err) {
      aLog('❌ Network error: ' + err);
      btn.disabled=false; btn.textContent='Generate Invoice →';
      return;
    }
    if (!data.ok) {
      aLog('❌ ' + (data.error||'Error starting generation'));
      document.getElementById('a-progress-bar').classList.add('hidden');
      btn.disabled=false; btn.textContent='Generate Invoice →';
      return;
    }

    const es = new EventSource('/stream_amc');
    es.onmessage = ev => {
      const msg = JSON.parse(ev.data);
      if (msg.type==='ping') return;
      if (msg.type==='log') { aLog(msg.msg); return; }
      if (msg.type==='done') {
        es.close();
        document.getElementById('a-progress-bar').classList.add('hidden');
        btn.disabled=false; btn.textContent='Generate Invoice →';
        if (msg.success) aShowResult(msg);
        else aLog('❌ ' + (msg.error||'Failed'));
      }
    };
    es.onerror = () => { es.close(); document.getElementById('a-progress-bar').classList.add('hidden'); aLog('⚠ Connection lost'); btn.disabled=false; btn.textContent='Generate Invoice →'; };
  };

  function aLog(msg) {
    const box = document.getElementById('a-log-box');
    const d = document.createElement('div'); d.textContent = '› ' + msg; box.appendChild(d);
    box.scrollTop = box.scrollHeight;
  }

  function aShowResult(msg) {
    document.getElementById('a-result-card').classList.remove('hidden');
    document.getElementById('a-result-filename').textContent = msg.filename||'';
    document.getElementById('a-download-btn').href = downloadUrl(msg.filename);
    const fmt$ = n=>'$'+Number(n||0).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
    const fmtN = n=>Number(n||0).toLocaleString();
    const stats=[
      {label:'Received',       val:fmtN(msg.receipt_count)+' units'},
      {label:'Shipped',        val:fmtN(msg.ship_count)+' units'},
      {label:'Billable Sq Ft', val:fmtN(msg.additional_sqft)+' sq ft'},
    ];
    document.getElementById('a-result-stats').innerHTML =
      stats.map(s=>`<div class="bg-ink-100/50 rounded-lg p-3 border border-steel/20"><div class="text-xs text-steel font-mono uppercase mb-1">${s.label}</div><div class="text-slate-100 font-semibold font-mono">${s.val}</div></div>`).join('');
    const excluded = msg.excluded_count||0;
    const note = document.getElementById('a-excluded-note');
    note.innerHTML = excluded > 0
      ? `<span class="text-accent font-mono font-semibold">Excluded Items →</span> <span class="text-slate-300">${excluded}</span> row(s) still had no Dimensions match and were left out of the sq ft total — check the <strong class="text-slate-300">"Excluded Items"</strong> tab in the output file.`
      : `<span class="text-ok font-mono font-semibold">✓</span> <span class="text-slate-300">No excluded items — every model matched the Dimensions reference.</span>`;
    document.getElementById('a-subtotal').textContent = fmt$(msg.subtotal);
    document.getElementById('a-tax').textContent      = fmt$(msg.tax);
    document.getElementById('a-total').textContent    = fmt$(msg.total);
  }
})();

(function() {
  // ══════════════════════════════════════════════════════════════════════
  // TCL Warehouse Invoice
  // ══════════════════════════════════════════════════════════════════════
  let _tAnalysis = null;   // {unit_groups, part_groups, ...} from /analyze_tcl

  window.tBackToUpload = function() {
    document.getElementById('t-step-upload').classList.remove('hidden');
    document.getElementById('t-step-review').classList.add('hidden');
    document.getElementById('t-result-card').classList.add('hidden');
    document.getElementById('t-log-wrap').classList.add('hidden');
  };

  const tForm = document.getElementById('tcl-form');
  if (tForm) tForm.addEventListener('submit', async e => {
    e.preventDefault();
    const btn = document.getElementById('t-gen-btn');
    btn.disabled = true; btn.textContent = 'Analyzing…';

    const logWrap = document.getElementById('t-analyze-log-wrap');
    const logBox  = document.getElementById('t-analyze-log');
    logWrap.classList.remove('hidden');
    logBox.innerHTML = '';

    const fd = new FormData(tForm);
    let resp, data;
    try {
      resp = await fetch('/analyze_tcl', {method:'POST', body:fd});
      data = await readJson(resp);
    } catch(err) {
      logBox.innerHTML = `<div class="text-warn">❌ Network error: ${escHtml(err)}</div>`;
      btn.disabled = false; btn.textContent = 'Analyze Inventory →';
      return;
    }

    (data.logs || []).forEach(m => {
      const d = document.createElement('div'); d.textContent = '› ' + m; logBox.appendChild(d);
    });

    if (!data.ok) {
      const d = document.createElement('div');
      d.className = 'text-warn'; d.textContent = '❌ ' + (data.error || 'Failed');
      logBox.appendChild(d);
      btn.disabled = false; btn.textContent = 'Analyze Inventory →';
      return;
    }

    _tAnalysis = data;
    btn.disabled = false; btn.textContent = 'Analyze Inventory →';
    tShowReview(data);
  });

  function tShowReview(data) {
    document.getElementById('t-step-upload').classList.add('hidden');
    document.getElementById('t-step-review').classList.remove('hidden');

    document.getElementById('t-review-summary').innerHTML = [
      {label:'Units (Pallet Storage)', val: (data.unit_count||0).toLocaleString() + ' units, ' + data.unit_groups.length + ' batch(es)'},
      {label:'Parts This Period',      val: (data.part_count||0).toLocaleString() + ' parts, ' + data.part_groups.length + ' group(s)'},
    ].map(s=>`<div class="text-center"><div class="text-steel font-mono uppercase text-xs mb-1">${s.label}</div><div class="text-slate-100 font-semibold font-mono">${s.val}</div></div>`).join('');

    // Pallet groups
    const pWrap = document.getElementById('t-pallet-groups');
    if (!data.unit_groups.length) {
      pWrap.innerHTML = '<p class="text-xs text-steel font-mono">No units in this inventory file.</p>';
    } else {
      pWrap.innerHTML = data.unit_groups.map(g => `
        <div class="flex items-center gap-3 bg-ink-50 border border-steel/30 rounded-lg p-3">
          <div class="flex-1 min-w-0">
            <div class="text-sm text-slate-200">Received <span class="font-mono">${escHtml(g.received_date)}</span></div>
            <div class="text-xs text-steel font-mono">${escHtml(g.quantity)} units</div>
          </div>
          <input type="text" data-unit-key="${escHtml(g.key)}" data-qty="${escHtml(g.quantity)}"
            value="${escHtml(g.quantity)}" aria-label="Pallet breakdown for units received ${escHtml(g.received_date)}"
            class="t-unit-input w-56 bg-ink-100 border border-steel/50 rounded-lg px-3 py-2 text-sm text-slate-200 font-mono"
            placeholder="e.g. 7,7,5,7,4" oninput="tValidateGroup(this)" />
          <span class="text-xs font-mono w-24 text-right" data-check-for="${escHtml(g.key)}" aria-live="polite"></span>
        </div>`).join('');
    }

    // Part groups
    const bWrap = document.getElementById('t-box-groups');
    if (!data.part_groups.length) {
      bWrap.innerHTML = '<p class="text-xs text-steel font-mono">No parts received in this billing period.</p>';
    } else {
      bWrap.innerHTML = data.part_groups.map(g => `
        <div class="flex items-center gap-3 bg-ink-50 border border-steel/30 rounded-lg p-2.5">
          <div class="flex-1 min-w-0">
            <div class="text-sm text-slate-200 font-mono truncate">${escHtml(g.model)}</div>
            <div class="text-xs text-steel font-mono">recv ${escHtml(g.received_date)} · ${escHtml(g.quantity)} pcs</div>
          </div>
          <input type="text" data-box-key="${escHtml(g.key)}" data-qty="${escHtml(g.quantity)}"
            value="${escHtml(tDefaultBoxBreakdown(g.quantity))}" aria-label="Box breakdown for ${escHtml(g.model)}"
            class="t-box-input w-40 bg-ink-100 border border-steel/50 rounded-lg px-2.5 py-1.5 text-xs text-slate-200 font-mono"
            placeholder="e.g. 20,20,10" oninput="tValidateGroup(this)" onblur="tAutoSplitBoxInput(this)" />
          <span class="text-xs font-mono w-20 text-right" data-check-for="${escHtml(g.key)}" aria-live="polite"></span>
        </div>`).join('');
    }

    document.getElementById('t-validation-errors').classList.add('hidden');
  }

  // TCL box tiers cap at 20 parts/box. Given a group quantity, greedily fill
  // boxes of 20 and put the remainder in a final box (e.g. 50 -> "20,20,10").
  const T_MAX_BOX_SIZE = 20;
  function tDefaultBoxBreakdown(qty) {
    qty = parseInt(qty, 10);
    if (!Number.isInteger(qty) || qty <= 0) return String(qty);
    if (qty <= T_MAX_BOX_SIZE) return String(qty);
    const boxes = [];
    let remaining = qty;
    while (remaining > T_MAX_BOX_SIZE) {
      boxes.push(T_MAX_BOX_SIZE);
      remaining -= T_MAX_BOX_SIZE;
    }
    boxes.push(remaining);
    return boxes.join(',');
  }

  // If the user types/pastes a single raw number over the 20/box max, auto-expand
  // it into valid 20-max boxes on blur instead of leaving an invalid entry.
  window.tAutoSplitBoxInput = function(input) {
    if (!input.classList.contains('t-box-input')) return;
    const raw = input.value.trim();
    if (!raw || raw.includes(',')) return; // only auto-fix bare single-number entries
    const n = Number(raw);
    if (Number.isInteger(n) && n > T_MAX_BOX_SIZE) {
      input.value = tDefaultBoxBreakdown(n);
      tValidateGroup(input);
    }
  };

  // Live sum-check on a single group's input (visual only — server re-validates)
  window.tValidateGroup = function(input) {
    const key = input.dataset.unitKey || input.dataset.boxKey;
    const expected = parseInt(input.dataset.qty, 10);
    const check = document.querySelector(`[data-check-for="${cssAttr(key)}"]`);
    const parts = input.value.split(',').map(s=>s.trim()).filter(Boolean).map(Number);
    const sum = parts.reduce((a,b)=>a+(isNaN(b)?0:b),0);
    const valid = parts.length>0 && parts.every(n=>Number.isInteger(n) && n>0) && sum===expected;
    if (check) {
      check.textContent = valid ? `✓ ${sum}` : `${sum} / ${expected}`;
      check.className = 'text-xs font-mono w-24 text-right ' + (valid ? 'text-ok' : 'text-warn');
    }
    input.classList.toggle('border-ok', valid);
    input.classList.toggle('border-warn', !valid);
  };

  window.tConfirmAndGenerate = async function() {
    // Client-side pre-check before hitting the server
    const badInputs = [...document.querySelectorAll('.t-unit-input, .t-box-input')].filter(inp => {
      const expected = parseInt(inp.dataset.qty, 10);
      const parts = inp.value.split(',').map(s=>s.trim()).filter(Boolean).map(Number);
      const sum = parts.reduce((a,b)=>a+(isNaN(b)?0:b),0);
      return !(parts.length>0 && parts.every(n=>Number.isInteger(n) && n>0) && sum===expected);
    });
    const errBox = document.getElementById('t-validation-errors');
    if (badInputs.length) {
      errBox.classList.remove('hidden');
      errBox.textContent = `❌ ${badInputs.length} group(s) don't sum to their total yet — check the highlighted fields above.`;
      badInputs[0].scrollIntoView({behavior:'smooth', block:'center'});
      return;
    }
    errBox.classList.add('hidden');

    const btn = document.getElementById('t-confirm-btn');
    btn.disabled = true; btn.textContent = 'Generating…';

    document.getElementById('t-log-wrap').classList.remove('hidden');
    document.getElementById('t-result-card').classList.add('hidden');
    document.getElementById('t-log-box').innerHTML = '';
    document.getElementById('t-progress-bar').classList.remove('hidden');

    const unit_breakdowns = {};
    document.querySelectorAll('.t-unit-input').forEach(inp => { unit_breakdowns[inp.dataset.unitKey] = inp.value; });
    const box_breakdowns = {};
    document.querySelectorAll('.t-box-input').forEach(inp => { box_breakdowns[inp.dataset.boxKey] = inp.value; });

    const data = await requestJson('/confirm_tcl', {
      method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({unit_breakdowns, box_breakdowns})
    });
    if (!data.ok) {
      tLog('❌ ' + (data.error||'Error starting generation'));
      if (Array.isArray(data.field_errors)) data.field_errors.forEach(m => tLog('  · ' + m));
      document.getElementById('t-progress-bar').classList.add('hidden');
      btn.disabled=false; btn.textContent='Generate Invoice →';
      return;
    }

    const es = new EventSource('/stream_tcl');
    es.onmessage = ev => {
      const msg = JSON.parse(ev.data);
      if (msg.type==='ping') return;
      if (msg.type==='log') { tLog(msg.msg); return; }
      if (msg.type==='done') {
        es.close();
        document.getElementById('t-progress-bar').classList.add('hidden');
        btn.disabled=false; btn.textContent='Generate Invoice →';
        if (msg.success) showTclResult(msg);
        else tLog('❌ ' + (msg.error||'Failed'));
      }
    };
    es.onerror = () => { es.close(); document.getElementById('t-progress-bar').classList.add('hidden'); tLog('⚠ Connection lost'); btn.disabled=false; btn.textContent='Generate Invoice →'; };
  };

  function tLog(msg) {
    const box = document.getElementById('t-log-box');
    const line = document.createElement('div'); line.className='log-line'; line.textContent='› '+msg;
    box.appendChild(line); box.scrollTop = box.scrollHeight;
  }

  function showTclResult(msg) {
    document.getElementById('t-result-card').classList.remove('hidden');
    document.getElementById('t-result-filename').textContent = msg.filename||'';
    document.getElementById('t-download-btn').href = downloadUrl(msg.filename);
    const fmt$ = n=>'$'+Number(n||0).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
    const fmtN = n=>Number(n||0).toLocaleString();
    const stats=[
      {label:'Total Pallets', val:fmtN(msg.total_pallets)+' @ '+fmt$(msg.pallet_rate)},
      {label:'Boxes Billed',  val:fmtN(msg.box_count)},
      {label:'Invoice Lines', val:fmtN(msg.line_count)},
    ];
    document.getElementById('t-result-stats').innerHTML =
      stats.map(s=>`<div class="bg-ink-100/50 rounded-lg p-3 border border-steel/20"><div class="text-xs text-steel font-mono uppercase mb-1">${s.label}</div><div class="text-slate-100 font-semibold font-mono">${s.val}</div></div>`).join('');
    document.getElementById('t-subtotal').textContent = fmt$(msg.subtotal);
    document.getElementById('t-tax').textContent      = fmt$(msg.tax);
    document.getElementById('t-total').textContent    = fmt$(msg.total);
  }
})();

function showSaveStatus(el, ok, message) {
  if (!el) return;
  el.className = 'mb-3 px-4 py-2 rounded-lg text-sm font-mono ' + (ok ? 'bg-ok/10 text-ok border border-ok/30' : 'bg-warn/10 text-warn border border-warn/30');
  el.textContent = message;
  clearTimeout(el._hideTimer);
  el._hideTimer = setTimeout(() => el.classList.add('hidden'), ok ? 3000 : 8000);
}

(function() {
  // ── Admin pricing panel ───────────────────────────────────────────────────
  let _pricingDefaults = {};
  let _pricingCurrent  = {};

  async function loadPricingAdmin() {
    try {
      const r = await fetch('/get_storage_prices');
      const d = await r.json();
      if (!d.ok) return;
      _pricingDefaults = d.defaults;
      _pricingCurrent  = {part_type_prices: {...d.part_type_prices}, line_prices: {...d.line_prices}};
      renderPricingForm();
    } catch(e) { console.warn('Pricing load failed', e); }
  }

  function renderPricingForm() {
    const LINE_LABELS = {
      unit_storage:'Unit Storage ($/unit)', pallet_storage:'Pallet Storage ($/pallet)',
      unit_receipt:'Unit Receipt & Processing ($/unit)', small_part_checkin:'Small Parts Check In ($/part)',
      unit_pick:'Unit Picks ($/unit)', small_part_pick:'Small Part Picks ($/order)',
    };
    const lf = document.getElementById('line-prices-form');
    if(lf) lf.innerHTML = Object.entries(_pricingCurrent.line_prices).map(([k,v])=>`
      <div class="flex items-center justify-between gap-3">
        <label class="text-steel text-xs flex-1" for="line-price-${escHtml(k)}">${escHtml(LINE_LABELS[k]||k)}</label>
        <div class="flex items-center gap-1">
          <span class="text-steel text-xs">$</span>
          <input type="number" step="0.01" min="0" value="${escHtml(v)}" data-key="${escHtml(k)}" data-type="line" id="line-price-${escHtml(k)}"
            class="w-20 bg-ink-100 border border-steel/30 rounded px-2 py-1 text-xs text-slate-200 text-right" />
        </div>
      </div>`).join('');

    const pf = document.getElementById('part-prices-form');
    if(pf) pf.innerHTML = Object.entries(_pricingCurrent.part_type_prices).map(([k,v])=>`
      <div class="flex items-center justify-between gap-3">
        <label class="text-steel text-xs flex-1">${escHtml(k)}</label>
        <div class="flex items-center gap-1">
          <span class="text-steel text-xs">$</span>
          <input type="number" step="0.01" min="0" value="${escHtml(v)}" data-key="${escHtml(k)}" data-type="part" aria-label="${escHtml(k)} price"
            class="w-20 bg-ink-100 border border-steel/30 rounded px-2 py-1 text-xs text-slate-200 text-right" />
        </div>
      </div>`).join('');
  }

  window.savePricing = async function() {
    const linePrices = {}, partPrices = {}, invalid = [];
    const collect = (selector, target) => document.querySelectorAll(selector).forEach(inp => {
      const n = nonNegativeValue(inp);
      inp.classList.toggle('border-warn', Number.isNaN(n));
      if (Number.isNaN(n)) invalid.push(inp.dataset.key); else target[inp.dataset.key] = n;
    });
    collect('[data-type="line"]', linePrices);
    collect('[data-type="part"]', partPrices);
    const st = document.getElementById('pricing-status');
    if (invalid.length) {
      // A blank or mistyped field used to be saved as $0.00 and billed that way.
      showSaveStatus(st, false, 'Nothing saved. Enter a price of 0 or more for: ' + invalid.join(', '));
      return;
    }
    const d = await requestJson('/set_storage_prices',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({part_type_prices:partPrices,line_prices:linePrices})});
    showSaveStatus(st, d.ok, d.ok ? '✓ Prices saved' : '❌ ' + (d.error||'Save failed'));
    if(d.ok){_pricingCurrent={part_type_prices:{...partPrices},line_prices:{...linePrices}};}
  };

  window.resetPricing = function() {
    if(!confirm('Reset all storage prices to defaults?')) return;
    _pricingCurrent = {part_type_prices:{..._pricingDefaults.part_type_prices}, line_prices:{..._pricingDefaults.line_prices}};
    renderPricingForm();
    showSaveStatus(document.getElementById('pricing-status'), true, 'Defaults loaded — click Save Pricing Changes to apply them.');
  };

  // Load pricing when config tab is shown (lazy)
  const origShowPage = window.showPage;
  if (origShowPage) {
    window.showPage = function(name) {
      origShowPage(name);
      if(name==='config' && Object.keys(_pricingCurrent).length===0) loadPricingAdmin();
      if(name==='config') { pdRefreshCount(); rcLoad(); }
    };
  } else {
    // fallback: load on DOMContentLoaded if showPage not yet defined
    document.addEventListener('DOMContentLoaded', () => {
      const cfgBtn = document.querySelector('[onclick*="showPage(\'config\')"]');
      if(cfgBtn) cfgBtn.addEventListener('click', ()=>{ if(!Object.keys(_pricingCurrent).length) loadPricingAdmin(); pdRefreshCount(); rcLoad(); });
    });
  }
})();

// ── Philips Reference Data Admin ─────────────────────────────────────────────
(function() {
  // ── Dimensions ────────────────────────────────────────────────────────────
  async function pdRefreshCount() {
    try {
      const r = await fetch('/get_philips_dimensions');
      const d = await r.json();
      const el = document.getElementById('pd-count');
      if (el && d.ok) el.textContent = d.count.toLocaleString() + ' models';
    } catch(e) {}
  }
  window.pdRefreshCount = pdRefreshCount;

  const pdInput = document.getElementById('pd-upload-input');
  if (pdInput) pdInput.addEventListener('change', async () => {
    if (!pdInput.files[0]) return;
    const status = document.getElementById('pd-status');
    status.classList.remove('hidden'); status.className = 'text-xs font-mono px-3 py-1.5 rounded bg-steel/10 text-steel';
    status.textContent = 'Uploading…';
    const fd = new FormData(); fd.append('dimensions', pdInput.files[0]);
    try {
      const r = await fetch('/upload_philips_dimensions', {method:'POST', body:fd});
      const d = await r.json();
      if (d.ok) {
        status.className = 'text-xs font-mono px-3 py-1.5 rounded bg-ok/10 text-ok border border-ok/30';
        status.textContent = `✓ Replaced — ${d.count} models now stored`;
        pdRefreshCount();
      } else {
        status.className = 'text-xs font-mono px-3 py-1.5 rounded bg-warn/10 text-warn border border-warn/30';
        status.textContent = '❌ ' + (d.error||'Upload failed');
      }
    } catch(e) {
      status.className = 'text-xs font-mono px-3 py-1.5 rounded bg-warn/10 text-warn border border-warn/30';
      status.textContent = '❌ Network error';
    }
    pdInput.value = '';
    setTimeout(()=>status.classList.add('hidden'), 4000);
  });

  // ── Repair Cost tiers ─────────────────────────────────────────────────────
  async function rcLoad() {
    try {
      const r = await fetch('/get_philips_repair_cost');
      const d = await r.json();
      if (d.ok) rcRender(d.tiers);
    } catch(e) { console.warn('Repair cost load failed', e); }
  }
  window.rcLoad = rcLoad;

  function rcRender(tiers) {
    const form = document.getElementById('rc-tiers-form');
    if (!form) return;
    // box_build is not edited here but is part of each stored tier; carry it
    // through unchanged so saving prices does not reset it to 0.
    form.innerHTML = tiers.map((t,i) => `
      <div class="grid grid-cols-4 gap-2 items-center" data-idx="${i}" data-box-build="${escHtml(t.box_build ?? 0)}">
        <input type="text" value="${escHtml(t.size)}" placeholder="50 or 20-24" aria-label="Screen size" class="rc-size bg-ink-100 border border-steel/30 rounded px-2 py-1 text-xs text-slate-200" />
        <input type="number" step="1" min="0" value="${escHtml(t.rb_price)}" aria-label="Refurbish price" class="rc-rb bg-ink-100 border border-steel/30 rounded px-2 py-1 text-xs text-slate-200" />
        <input type="number" step="1" min="0" value="${escHtml(t.harvest_price)}" aria-label="Harvest price" class="rc-harvest bg-ink-100 border border-steel/30 rounded px-2 py-1 text-xs text-slate-200" />
        <button type="button" onclick="rcRemoveTier(${i})" aria-label="Remove tier" class="text-warn text-xs font-mono hover:opacity-70 transition-all">✕</button>
      </div>`).join('');
  }

  window.rcAddTier = function() {
    const form = document.getElementById('rc-tiers-form');
    const rows = rcCollect();
    rows.push({size:'', rb_price:0, harvest_price:0, box_build:0});
    rcRender(rows);
  };

  window.rcRemoveTier = function(idx) {
    const rows = rcCollect();
    rows.splice(idx, 1);
    rcRender(rows);
  };

  // strict=false keeps raw values so add/remove re-renders never discard what
  // the user typed; strict=true returns NaN for blank/invalid/negative prices.
  function rcCollect(strict) {
    const rows = [];
    const price = inp => strict ? nonNegativeValue(inp) : (inp.value === '' ? '' : Number(inp.value));
    document.querySelectorAll('#rc-tiers-form [data-idx]').forEach(row => {
      const boxBuild = Number(row.dataset.boxBuild);
      rows.push({
        size: row.querySelector('.rc-size').value.trim(),
        rb_price: price(row.querySelector('.rc-rb')),
        harvest_price: price(row.querySelector('.rc-harvest')),
        box_build: Number.isFinite(boxBuild) ? boxBuild : 0,
      });
    });
    return rows;
  }

  window.rcSave = async function() {
    const st = document.getElementById('rc-status');
    const tiers = rcCollect(true).filter(t => t.size !== '');
    const invalid = tiers.filter(t => Number.isNaN(t.rb_price) || Number.isNaN(t.harvest_price)).map(t => t.size);
    if (invalid.length) {
      showSaveStatus(st, false, 'Nothing saved. Enter prices of 0 or more for size(s): ' + invalid.join(', '));
      return;
    }
    const d = await requestJson('/set_philips_repair_cost', {method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({tiers})});
    showSaveStatus(st, d.ok, d.ok ? `✓ Saved ${d.count ?? tiers.length} tier(s)` : '❌ ' + (d.error||'Save failed'));
    if (d.ok) rcRender(tiers);
  };
})();

// ── AMC Reference Data Admin ──────────────────────────────────────────────────
(function() {
  const AMC_PRICE_LABELS = {
    unit_receipt:  'Unit Receipt & Processing ($/each)',
    storage_base:  'Storage, First 500 sq ft (flat $)',
    base_sqft:     'Sq Ft included in flat Storage charge',
    storage_addl:  'Storage, Additional Sq Ft ($/sq ft, 50-ft increments)',
    order_fee:     'Order Fee ($/each shipped)',
    order_out_fee: 'Order Out Fee ($/each shipped)',
  };
  let _amcPricesDefaults = {};
  let _amcPricesCurrent  = {};

  // ── Dimensions ────────────────────────────────────────────────────────────
  async function adRefreshCount() {
    try {
      const r = await fetch('/get_amc_dimensions');
      const d = await r.json();
      const el = document.getElementById('ad-count');
      if (el && d.ok) el.textContent = d.count.toLocaleString() + ' models';
    } catch(e) {}
  }
  window.adRefreshCount = adRefreshCount;

  const adInput = document.getElementById('ad-upload-input');
  if (adInput) adInput.addEventListener('change', async () => {
    if (!adInput.files[0]) return;
    const status = document.getElementById('ad-status');
    status.classList.remove('hidden'); status.className = 'text-xs font-mono px-3 py-1.5 rounded bg-steel/10 text-steel';
    status.textContent = 'Uploading…';
    const fd = new FormData(); fd.append('dimensions', adInput.files[0]);
    try {
      const r = await fetch('/upload_amc_dimensions', {method:'POST', body:fd});
      const d = await r.json();
      if (d.ok) {
        status.className = 'text-xs font-mono px-3 py-1.5 rounded bg-ok/10 text-ok border border-ok/30';
        status.textContent = `✓ Replaced — ${d.count} models now stored`;
        adRefreshCount();
      } else {
        status.className = 'text-xs font-mono px-3 py-1.5 rounded bg-warn/10 text-warn border border-warn/30';
        status.textContent = '❌ ' + (d.error||'Upload failed');
      }
    } catch(e) {
      status.className = 'text-xs font-mono px-3 py-1.5 rounded bg-warn/10 text-warn border border-warn/30';
      status.textContent = '❌ Network error';
    }
    adInput.value = '';
    setTimeout(()=>status.classList.add('hidden'), 4000);
  });

  // ── Pricing ───────────────────────────────────────────────────────────────
  async function amcLoadPricing() {
    try {
      const r = await fetch('/get_amc_prices');
      const d = await r.json();
      if (!d.ok) return;
      _amcPricesDefaults = d.defaults;
      _amcPricesCurrent  = {...d.prices};
      amcRenderPricingForm();
    } catch(e) { console.warn('AMC pricing load failed', e); }
  }
  window.amcLoadPricing = amcLoadPricing;

  function amcRenderPricingForm() {
    const form = document.getElementById('amc-prices-form');
    if (!form) return;
    form.innerHTML = Object.entries(_amcPricesCurrent).map(([k,v])=>`
      <div class="flex items-center justify-between gap-3">
        <label class="text-steel text-xs flex-1" for="amc-price-${escHtml(k)}">${escHtml(AMC_PRICE_LABELS[k]||k)}</label>
        <div class="flex items-center gap-1">
          <span class="text-steel text-xs">$</span>
          <input type="number" step="0.01" min="0" value="${escHtml(v)}" data-key="${escHtml(k)}" id="amc-price-${escHtml(k)}"
            class="amc-price-input w-24 bg-ink-100 border border-steel/30 rounded px-2 py-1 text-xs text-slate-200 text-right" />
        </div>
      </div>`).join('');
  }

  window.amcSavePricing = async function() {
    const prices = {}, invalid = [];
    document.querySelectorAll('.amc-price-input').forEach(inp => {
      const n = nonNegativeValue(inp);
      inp.classList.toggle('border-warn', Number.isNaN(n));
      if (Number.isNaN(n)) invalid.push(AMC_PRICE_LABELS[inp.dataset.key] || inp.dataset.key); else prices[inp.dataset.key] = n;
    });
    const st = document.getElementById('amc-pricing-status');
    if (invalid.length) {
      showSaveStatus(st, false, 'Nothing saved. Enter a value of 0 or more for: ' + invalid.join(', '));
      return;
    }
    const d = await requestJson('/set_amc_prices', {method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({prices})});
    showSaveStatus(st, d.ok, d.ok ? '✓ Prices saved' : '❌ ' + (d.error||'Save failed'));
    if (d.ok) _amcPricesCurrent = {...prices};
  };

  window.amcResetPricing = function() {
    if(!confirm('Reset all AMC prices to defaults?')) return;
    _amcPricesCurrent = {..._amcPricesDefaults};
    amcRenderPricingForm();
    showSaveStatus(document.getElementById('amc-pricing-status'), true, 'Defaults loaded — click Save AMC Pricing to apply them.');
  };

  // Load AMC admin data when the config tab is shown (lazy, chained onto the existing hook)
  const prevShowPage = window.showPage;
  if (prevShowPage) {
    window.showPage = function(name) {
      prevShowPage(name);
      if (name==='config') {
        adRefreshCount();
        if (Object.keys(_amcPricesCurrent).length===0) amcLoadPricing();
      }
    };
  }
})();

// ── Sidebar / topbar enhancements (design overhaul, additive only) ───────────
(function() {
  const crumbMap = { promethean: 'Promethean', amc: 'AMC', tcl: 'TCL', philips: 'Philips', config: 'Config' };
  const subCrumbMap = { invoice: 'Workshop Invoice', storage: 'Storage Invoice' };

  function setCrumb(root, leaf) {
    const rootEl = document.getElementById('crumb-root');
    const leafEl = document.getElementById('crumb-leaf');
    const sepEl  = document.getElementById('crumb-sep');
    if (rootEl) rootEl.textContent = root || '';
    if (leaf) {
      if (leafEl) { leafEl.textContent = leaf; leafEl.classList.remove('hidden'); }
      if (sepEl) sepEl.classList.remove('hidden');
    } else {
      if (sepEl) sepEl.classList.add('hidden');
      if (leafEl) leafEl.classList.add('hidden');
    }
  }

  window.closeSidebarMobile = function() {
    document.getElementById('sidebar')?.classList.remove('open');
    document.getElementById('sidebar-scrim')?.classList.remove('open');
  };
  window.toggleSidebar = function() {
    document.getElementById('sidebar')?.classList.toggle('open');
    document.getElementById('sidebar-scrim')?.classList.toggle('open');
  };

  const prevShowPage2 = window.showPage;
  window.showPage = function(page) {
    prevShowPage2(page);
    setCrumb(crumbMap[page] || page, page === 'promethean' ? 'Workshop Invoice' : null);
    // .nav-btn scopes this to client-level sidebar links only — portal-level
    // tabs (.portal-nav-btn, e.g. "Invoice Generator") have their own active
    // state managed by showPortalPage() and must stay untouched here, or
    // switching clients within the Invoice Generator tab would deactivate it.
    document.querySelectorAll('.side-link.nav-btn').forEach(el => {
      el.classList.toggle('active', el.dataset.page === page);
    });
    document.getElementById('sidebar-sub-promethean')?.classList.toggle('hidden', page !== 'promethean');
    closeSidebarMobile();
  };

  const prevShowSubPage2 = window.showSubPage;
  window.showSubPage = function(sub, brand) {
    prevShowSubPage2(sub, brand);
    if (brand === 'promethean') setCrumb('Promethean', subCrumbMap[sub] || sub);
    document.querySelectorAll('.side-sublink').forEach(el => {
      el.classList.toggle('active', el.dataset.sub === sub);
    });
  };

  // Keep each module's child navigation directly below its parent. The legacy
  // generated template placed Invoice Generator's client tree after every
  // portal module, which made the hierarchy look unrelated.
  const invoicePortalNav = document.getElementById('portal-nav-invoice-generator');
  const invoicePortalBody = document.getElementById('portal-body-invoice-generator');
  if (invoicePortalNav && invoicePortalBody && invoicePortalNav.nextElementSibling !== invoicePortalBody) {
    invoicePortalNav.after(invoicePortalBody);
  }

  let activeNonConformingView = 'list';
  window.showNonConformingPage = function(view) {
    activeNonConformingView = view === 'add' ? 'add' : 'list';
    document.getElementById('nc-page-list')?.classList.toggle('hidden', activeNonConformingView !== 'list');
    document.getElementById('nc-page-add')?.classList.toggle('hidden', activeNonConformingView !== 'add');
    document.querySelectorAll('[data-nc-view]').forEach(el => {
      el.classList.toggle('active', el.dataset.ncView === activeNonConformingView);
    });
    setCrumb('SMS NonConforming', activeNonConformingView === 'add' ? 'Add Item' : 'Item List');
    closeSidebarMobile();
  };

  // ── Portal-level nav (Invoice Generator / SMS NonConforming / TBD 2) ──────
  // Training Tracker is NOT part of this toggle set — it's a real multi-page
  // Flask app of its own (own login, own sessions) mounted at
  // /training-tracker/, so its sidebar entry is a plain <a> that navigates
  // away rather than a JS-toggled panel. Keep it out of `allPortals`.
  const allPortals = ['invoice-generator', 'sms-nonconforming', 'tbd2'];
  const portalCrumbMap = { 'invoice-generator': 'Promethean', 'sms-nonconforming': 'SMS NonConforming', 'tbd2': 'TBD 2' };

  window.showPortalPage = function(portal) {
    // If the SPA content divs for this portal tab don't exist on the current
    // page (e.g. this was called from the Training Tracker's sidebar, which
    // shares this markup/JS but isn't part of index.html's hidden-div SPA),
    // do a real navigation back to the portal root instead of no-op'ing.
    if (!document.getElementById('portal-content-' + portal)) {
      window.location.href = '/index.cfm?portal=' + portal;
      return;
    }
    allPortals.forEach(p => {
      const navBtn  = document.getElementById('portal-nav-' + p);
      const body    = document.getElementById('portal-body-' + p);     // sidebar sub-nav (invoice-generator only)
      const content = document.getElementById('portal-content-' + p);  // main content
      if (navBtn) { navBtn.classList.toggle('active', p === portal); navBtn.classList.toggle('text-steel', p !== portal); }
      if (body) body.classList.toggle('hidden', p !== portal);
      if (content) content.classList.toggle('hidden', p !== portal);
    });
    if (portal === 'invoice-generator') {
      // Restore whichever client/page was last active. If Config was cleared
      // while another portal was open, return to the safe Promethean default.
      const permitted = [...document.querySelectorAll('.side-link.nav-btn[data-page]')]
        .filter(el => !el.classList.contains('hidden'));
      const activeNav = permitted.find(el => el.classList.contains('active'));
      const page = activeNav ? activeNav.dataset.page : (permitted[0] ? permitted[0].dataset.page : null);
      if (page) showPage(page);
    } else if (portal === 'sms-nonconforming') {
      const configNav = document.getElementById('nav-config');
      configNav?.classList.remove('active');
      configNav?.classList.add('text-steel');
      // The module always opens on the searchable records list. Add Item is a
      // deliberate secondary destination in the module's sidebar.
      showNonConformingPage('list');
    } else {
      const configNav = document.getElementById('nav-config');
      configNav?.classList.remove('active');
      configNav?.classList.add('text-steel');
      setCrumb(portalCrumbMap[portal] || portal, null);
    }
    const destination = new URL(window.location.href);
    destination.searchParams.set('portal', portal);
    if (portal !== 'invoice-generator') destination.searchParams.delete('client');
    window.history.replaceState({}, '', destination);
    closeSidebarMobile();
  };

  window.addEventListener('DOMContentLoaded', () => {
    // Arriving here via a sidebar link from Training Tracker (?portal=<n>)?
    // Restore that tab instead of the default Promethean/Workshop Invoice view.
    const requestedParams = new URLSearchParams(window.location.search);
    const requestedPortal = requestedParams.get('portal');
    const requestedClient = requestedParams.get('client');
    if (requestedPortal && document.getElementById('portal-content-' + requestedPortal)) {
      showPortalPage(requestedPortal);
      if (requestedPortal === 'invoice-generator' && requestedClient === 'config') {
        const configNav = document.getElementById('nav-config');
        if (configNav && !configNav.classList.contains('hidden')) showConfigPage();
      }
      if (requestedPortal === 'sms-nonconforming' && requestedParams.get('view') === 'add') {
        showNonConformingPage('add');
      }
    } else {
      // Root/leaf text is already server-rendered correctly for whichever
      // section the logged-in user actually has access to (see index() in
      // app.py) — just re-run it through setCrumb for sep/leaf visibility,
      // rather than hardcoding 'Promethean'/'Workshop Invoice'.
      const rootEl = document.getElementById('crumb-root');
      if (rootEl) setCrumb(rootEl.textContent.trim(), rootEl.dataset.defaultLeaf || null);
    }
  });
})();
