// Frontend regression tests for the USSI Nexus portal shell.
//
// Loads views/portal.html with the real static/js files inlined in their
// production order, mocks every server response, and exercises the browser
// contracts that the Lucee routes depend on. No network, no server, no data.
//
// Usage:  npm install jsdom@24 && TZ=America/New_York node tests/frontend/portal_regression.test.js [repoRoot]
'use strict';
const fs = require('fs');
const path = require('path');
const { JSDOM, VirtualConsole } = require('jsdom');

const ROOT = path.resolve(process.argv[2] || path.join(__dirname, '..', '..'));
function pick(...candidates) {
  for (const c of candidates) { const p = path.join(ROOT, c); if (fs.existsSync(p)) return p; }
  throw new Error('Missing file: ' + candidates.join(' | '));
}
const FILES = {
  portal: pick('views/portal.html', 'portal.html'),
  themeInit: pick('static/js/theme-init.js', 'theme-init.js'),
  luceeAuth: pick('static/js/lucee-auth.js', 'lucee-auth.js'),
  app: pick('static/js/app.js', 'app.js'),
  nc: pick('static/js/nonconforming.js', 'nonconforming.js'),
};
const read = f => fs.readFileSync(f, 'utf8');

function json(body, status = 200) {
  return { ok: status >= 200 && status < 300, status, headers: { get: () => 'application/json' },
           json: async () => body, text: async () => JSON.stringify(body) };
}
function html(body, status = 200) {
  return { ok: status >= 200 && status < 300, status, headers: { get: () => 'text/html' },
           json: async () => { throw new SyntaxError('Unexpected token < in JSON'); }, text: async () => body };
}
const tick = (ms = 0) => new Promise(r => setTimeout(r, ms));

async function loadPortal({ routes = {}, auth, mutate, fixedNow } = {}) {
  let src = read(FILES.portal);
  const inline = (file) => `<script>${read(file).replace(/<\/script/gi, '<\\/script')}</script>`;
  const authJson = JSON.stringify(auth || { sections: ['invoice-generator', 'sms-nonconforming', 'training-tracker', 'tbd2'],
    invoiceChildren: ['promethean', 'amc', 'tcl', 'philips', 'config'], isSuperadmin: true });
  src = src.replace(/<script src="\/static\/js\/theme-init\.js"><\/script>/, () => inline(FILES.themeInit));
  src = src.replace(/<script src="\/static\/js\/lucee-auth\.js[^"]*" defer><\/script>/,
    () => `<script>window.LOGICORE_AUTH=${authJson};</script>` + inline(FILES.luceeAuth));
  src = src.replace(/<script src="\/static\/js\/app\.js[^"]*" defer><\/script>/, () => inline(FILES.app));
  src = src.replace(/<script src="\/static\/js\/nonconforming\.js[^"]*" defer><\/script>/, () => inline(FILES.nc));
  if (mutate) src = mutate(src);

  const errors = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', e => { if (!/navigation/i.test(e.message)) errors.push(e); });
  const calls = [], streams = [], alerts = [];
  const dom = new JSDOM(src, {
    url: 'https://nexus.test/index.cfm/', runScripts: 'dangerously', pretendToBeVisual: true, virtualConsole: vc,
    beforeParse(window) {
      if (fixedNow) {
        const RealDate = window.Date;
        const fixed = new RealDate(fixedNow).getTime();
        window.Date = class extends RealDate {
          constructor(...a) { if (a.length) super(...a); else super(fixed); }
          static now() { return fixed; }
        };
      }
      window.matchMedia = () => ({ matches: false, addEventListener() {} });
      window.alert = m => alerts.push(String(m));
      window.confirm = () => true;
      window.HTMLElement.prototype.scrollIntoView = function () {};
      window.EventSource = class { constructor(url) { this.url = url; streams.push(this); } close() { this.closed = true; } };
      window.fetch = async (url, init = {}) => {
        const u = String(url);
        calls.push({ url: u, method: (init.method || 'GET').toUpperCase(), body: init.body });
        const key = Object.keys(routes).find(k => {
          const [m, p] = k.includes(' ') ? k.split(' ') : ['*', k];
          return (m === '*' || m === (init.method || 'GET').toUpperCase()) && u.replace(/^\/index\.cfm/, '').split('?')[0] === p;
        });
        if (key) { const r = routes[key]; return typeof r === 'function' ? r(u, init) : r; }
        if (u.startsWith('http://localhost:9100')) throw new Error('no printer');
        return json({ ok: true, items: [], total: 0, statuses: [] });
      };
    },
  });
  await tick(5);
  return { dom, w: dom.window, d: dom.window.document, calls, streams, alerts, errors };
}

const results = [];
const unhandled = [];
process.on('unhandledRejection', e => unhandled.push(e));
async function test(name, fn) {
  try { await fn(); results.push([true, name]); }
  catch (e) { results.push([false, name, e && e.message ? e.message : String(e)]); }
}
function assert(cond, msg) { if (!cond) throw new Error(msg); }

const XSS = '<img src=x onerror="window.__pwned=1">';

(async () => {
  await test('page loads without script errors', async () => {
    const { errors } = await loadPortal();
    assert(errors.length === 0, 'script errors: ' + errors.map(e => e.message).join('; '));
  });

  await test('F-01 EventSource progress streams use the /index.cfm route prefix', async () => {
    const { w, streams } = await loadPortal({ routes: { 'POST /confirm_amc': json({ ok: true }) } });
    await w.aConfirmAndGenerate();
    assert(streams.length === 1, 'no stream opened');
    assert(streams[0].url === '/index.cfm/stream_amc', 'stream URL was ' + streams[0].url);
  });

  await test('F-01 JS navigations do not bypass the /index.cfm route prefix', async () => {
    const offenders = [];
    for (const f of [FILES.app, FILES.nc]) {
      read(f).split('\n').forEach((line, i) => {
        if (/location\.href\s*=\s*[`'"]\/(?!index\.cfm)/.test(line)) offenders.push(path.basename(f) + ':' + (i + 1));
      });
    }
    assert(offenders.length === 0, 'raw navigations: ' + offenders.join(', '));
    const { w } = await loadPortal();
    assert(w.ussiRouteUrl('/nonconforming/api/export?q=a') === '/index.cfm/nonconforming/api/export?q=a', 'route helper');
  });

  await test('F-02 AMC missing-dimension model names are rendered as text', async () => {
    const { w, d } = await loadPortal({ routes: { 'POST /analyze_amc': json({ ok: true, missing_dimension_models: [XSS] }) } });
    d.getElementById('amc-form').dispatchEvent(new w.Event('submit', { cancelable: true }));
    await tick(5);
    const list = d.getElementById('a-missing-dims-list');
    assert(!list.querySelector('img'), 'markup injected: ' + list.innerHTML.slice(0, 120));
    assert(list.textContent.includes(XSS), 'model name not shown');
    assert(list.querySelector('input').dataset.model === XSS, 'data-model not preserved');
  });

  await test('F-02 Philips, TCL, FedEx and Workshop review data are rendered as text', async () => {
    const { w, d } = await loadPortal({ routes: {
      'POST /analyze_philips': json({ ok: true, missing_dimension_models: [XSS] }),
      'POST /analyze_tcl': json({ ok: true, unit_count: 1, part_count: 1,
        unit_groups: [{ key: 'u"1', received_date: XSS, quantity: 1 }],
        part_groups: [{ key: 'p1', model: XSS, received_date: '2026-08-01', quantity: 1 }] }),
      'POST /analyze_fedex_shipment': json({ ok: true, row_count: 1, defaulted_rows: [{ tracking: XSS, po: XSS }],
        skipped_rows: [{ row: 2, tracking: XSS, reason: XSS }] }),
      'POST /sanitize': json({ ok: true, total_records: 1, issue_count: 1, auto_count: 1,
        issues: [{ row_index: 0, field: 'Actual Model', 'Actual Model': XSS, description: XSS, current_value: XSS, suggested_values: ['"><img src=x onerror=1>'] }],
        auto_corrections: [{ Date: XSS, 'Actual Serial': XSS, model_changed: 'True', old_model: XSS, new_model: XSS, size_changed: 'True', old_size: XSS, new_size: XSS, Result: XSS }] }),
    } });
    for (const id of ['philips-form', 'tcl-form', 'fedex-shipment-form', 'sanitize-form']) {
      d.getElementById(id).dispatchEvent(new w.Event('submit', { cancelable: true }));
    }
    await tick(10);
    for (const id of ['p-missing-dims-list', 't-pallet-groups', 't-box-groups', 'fx-defaulted-list', 'fx-skipped-list', 'issues-tbody', 'auto-tbody']) {
      const el = d.getElementById(id);
      assert(el.innerHTML.length > 0, id + ' was not rendered');
      assert(!el.querySelector('img'), 'markup injected into #' + id);
    }
    assert(d.querySelector('#issues-tbody option[value]:not([value=""])').value === '"><img src=x onerror=1>', 'option value altered');
    assert(w.__pwned === undefined, 'payload executed');
    const unitInput = d.querySelector('.t-unit-input');
    w.tValidateGroup(unitInput); // key contains a quote; selector must not throw
    assert(unitInput.classList.contains('border-ok'), 'group check did not run');
  });

  await test('F-03 saving Philips repair-cost tiers preserves box_build', async () => {
    const tiers = [{ size: '46', rb_price: 45, harvest_price: 20, box_build: 25 }, { size: '75', rb_price: 135, harvest_price: 75, box_build: 35 }];
    const { w, calls } = await loadPortal({ routes: {
      'GET /get_philips_repair_cost': json({ ok: true, tiers }),
      'POST /set_philips_repair_cost': json({ ok: true, count: 2 }),
    } });
    await w.rcLoad();
    await w.rcSave();
    const post = calls.find(c => c.url.endsWith('/set_philips_repair_cost'));
    const sent = JSON.parse(post.body).tiers;
    assert(sent.map(t => t.box_build).join(',') === '25,35', 'box_build sent as ' + sent.map(t => t.box_build).join(','));
    w.rcAddTier();
    await w.rcSave();
    const sent2 = JSON.parse(calls.filter(c => c.url.endsWith('/set_philips_repair_cost')).pop().body).tiers;
    assert(sent2.length === 2 && sent2[1].box_build === 35, 'box_build lost after add/re-render');
  });

  await test('F-04 blank, invalid or negative prices are not silently saved', async () => {
    const { w, d, calls } = await loadPortal({ routes: {
      'GET /get_storage_prices': json({ ok: true, defaults: { part_type_prices: { PSU: 5 }, line_prices: { unit_storage: 2 } },
        part_type_prices: { PSU: 5 }, line_prices: { unit_storage: 2 } }),
      'GET /get_amc_prices': json({ ok: true, defaults: { unit_receipt: 3 }, prices: { unit_receipt: 3 } }),
      'GET /config/serial_rules': json({ ok: true, rules: [] }),
      'GET /get_philips_repair_cost': json({ ok: true, tiers: [{ size: '50', rb_price: 90, harvest_price: 40, box_build: 25 }] }),
    } });
    w.showPage('config');
    await tick(10);
    d.querySelector('[data-type="line"]').value = '';
    await w.savePricing();
    assert(!calls.some(c => c.url.endsWith('/set_storage_prices')), 'blank storage price was saved');
    assert(/price/i.test(d.getElementById('pricing-status').textContent), 'no validation message');
    d.querySelector('.amc-price-input').value = '-1';
    await w.amcSavePricing();
    assert(!calls.some(c => c.url.endsWith('/set_amc_prices')), 'negative AMC price was saved');
    d.querySelector('.rc-rb').value = '';
    await w.rcSave();
    assert(!calls.some(c => c.url.endsWith('/set_philips_repair_cost')), 'blank repair price was saved');
  });

  await test('F-04 negative missing-dimension values block generation', async () => {
    const { w, d, calls } = await loadPortal({ routes: { 'POST /analyze_amc': json({ ok: true, missing_dimension_models: ['X1'] }) } });
    d.getElementById('amc-form').dispatchEvent(new w.Event('submit', { cancelable: true }));
    await tick(5);
    d.querySelector('.a-missing-dim-input').value = '-5';
    await w.aConfirmAndGenerate();
    assert(!calls.some(c => c.url.endsWith('/confirm_amc')), 'negative dimension was submitted');
    assert(!d.getElementById('a-confirm-btn').disabled, 'button left disabled');
  });

  await test('F-05 "Generate Another" does not resubmit the legacy invoice form', async () => {
    const { w, d, calls } = await loadPortal();
    const btn = [...d.querySelectorAll('#legacy-form button')].find(b => /Generate Another/.test(b.textContent));
    assert(btn.getAttribute('type') === 'button', 'button type is ' + btn.getAttribute('type'));
    btn.click();
    await tick(5);
    assert(!calls.some(c => c.url.endsWith('/generate')), 'form was submitted');
  });

  await test('F-06 default dates use the local calendar day (late evening, US Eastern)', async () => {
    // 23:30 EDT on 16 Sep 2026 is 03:30 UTC on 17 Sep.
    const { d } = await loadPortal({ fixedNow: '2026-09-17T03:30:00Z' });
    const localToday = new Date('2026-09-17T03:30:00Z').toLocaleDateString('en-CA');
    assert(d.getElementById('date-to2').value === localToday, `date-to2=${d.getElementById('date-to2').value} expected ${localToday}`);
    assert(d.getElementById('date-from2').value === localToday.slice(0, 8) + '01', 'date-from2=' + d.getElementById('date-from2').value);
  });

  await test('F-07 non-JSON responses (expired session) re-enable controls and report the failure', async () => {
    const { w, d, alerts } = await loadPortal({ routes: {
      'POST /sanitize': html('<html>Sign in</html>'),
      'POST /confirm_storage': html('<html>Sign in</html>'),
      'POST /confirm_tcl': html('Server error', 500),
      'POST /build_fedex_shipment': html('<html>Sign in</html>'),
    } });
    d.getElementById('sanitize-form').dispatchEvent(new w.Event('submit', { cancelable: true }));
    await tick(10);
    assert(!d.getElementById('sanitize-btn').disabled, 'sanitize button stuck');
    assert(alerts.length === 1, 'no error surfaced');
    await w.sConfirmAndGenerate();
    assert(!d.getElementById('s-confirm-btn').disabled, 'storage button stuck');
    await w.fxConfirmAndBuild();
    assert(!d.getElementById('fx-confirm-btn').disabled, 'fedex button stuck');
    await w.tConfirmAndGenerate();
    assert(!d.getElementById('t-confirm-btn').disabled, 'tcl button stuck');
    assert(/500|sign in|session/i.test(d.getElementById('t-log-box').textContent), 'tcl error not shown');
  });

  await test('F-07 serial-rule config load failure is reported, not thrown', async () => {
    const { w, d } = await loadPortal({ routes: { 'GET /config/serial_rules': json({ ok: false, error: 'Forbidden' }, 403) } });
    const before = unhandled.length;
    await w.loadCfg();
    await tick(5);
    assert(unhandled.length === before, 'unhandled rejection: ' + (unhandled[unhandled.length - 1] || {}).message);
    assert(/Forbidden/.test(d.getElementById('cfg-status').textContent), 'no message shown');
  });

  await test('F-07 legacy generation recovers when the progress stream drops', async () => {
    const { w, d, streams } = await loadPortal({ routes: { 'POST /generate': json({ ok: true, output: 'outputs/X.xlsx' }) } });
    d.getElementById('legacy-form').dispatchEvent(new w.Event('submit', { cancelable: true }));
    await tick(5);
    assert(streams.length === 1, 'no stream');
    assert(typeof streams[0].onerror === 'function', 'no onerror handler');
    streams[0].onerror();
    assert(!d.getElementById('legacy-btn').disabled, 'legacy button stuck');
  });

  await test('F-08 navigation works when the server omits the Config section', async () => {
    const { w, d, errors } = await loadPortal({
      auth: { sections: ['invoice-generator'], invoiceChildren: ['amc', 'tcl'], isSuperadmin: false },
      mutate: s => s.replace(/<div id="page-config"[\s\S]*?<!--\s*\/page-config\s*-->/, '')
                    .replace(/<a class="side-link nav-btn text-steel" data-page="config"[\s\S]*?<\/a>/, ''),
    });
    assert(!d.getElementById('page-config') && !d.getElementById('nav-config'), 'fixture did not remove config');
    w.showPage('tcl');
    assert(errors.length === 0, errors.map(e => e.message).join('; '));
    assert(d.getElementById('crumb-root').textContent === 'TCL', 'breadcrumb not updated');
    assert(!d.getElementById('page-tcl').classList.contains('hidden'), 'tcl page hidden');
  });

  await test('F-08 invoice portal never reveals a client page the user was not granted', async () => {
    const { w, d } = await loadPortal({ auth: { sections: ['invoice-generator', 'sms-nonconforming'], invoiceChildren: ['amc'], isSuperadmin: false } });
    w.showPortalPage('sms-nonconforming');
    w.showPortalPage('invoice-generator');
    assert(d.getElementById('page-promethean').classList.contains('hidden'), 'Promethean page revealed');
    assert(!d.getElementById('page-amc').classList.contains('hidden'), 'AMC page not shown');
  });

  await test('F-09 scripts still initialise when the Promethean section is omitted', async () => {
    const { w, errors } = await loadPortal({
      mutate: s => s.replace(/<form id="sanitize-form"/, '<div id="removed-a"').replace(/<form id="legacy-form"/, '<div id="removed-b"'),
    });
    assert(errors.length === 0, errors.map(e => e.message).join('; '));
    assert(typeof w.aConfirmAndGenerate === 'function' && typeof w.tConfirmAndGenerate === 'function', 'later modules not initialised');
  });

  await test('F-10 failed NonConforming delete keeps the record open and reports the error', async () => {
    const { w, d } = await loadPortal({ routes: {
      'GET /nonconforming/api/items/7': json({ ok: true, item: { id: 7, number: 'NC-7', model: 'M', serial: 'S', carrier: 'C' } }),
      'DELETE /nonconforming/api/items/7': json({ ok: false, error: 'Forbidden' }, 403),
    } });
    d.getElementById('nc-table-body').innerHTML = '<tr><td><button data-action="edit" data-id="7">Edit</button></td></tr>';
    d.querySelector('[data-action="edit"]').click();
    await tick(5);
    d.getElementById('nc-edit-delete').click();
    await tick(5);
    assert(!d.getElementById('nc-edit-modal').classList.contains('hidden'), 'modal closed after failed delete');
    assert(/Forbidden/.test(d.getElementById('nc-edit-error').textContent), 'error not shown');
  });

  await test('F-10 out-of-order NonConforming search responses cannot overwrite newer results', async () => {
    let release;
    const slow = new Promise(r => { release = r; });
    const { w, d } = await loadPortal({ routes: {
      'GET /nonconforming/api/items': async (u) => {
        if (u.includes('q=old')) { await slow; return json({ ok: true, total: 1, statuses: [], items: [{ id: 1, number: 'OLD' }] }); }
        return json({ ok: true, total: 1, statuses: [], items: [{ id: 2, number: u.includes('q=new') ? 'NEW' : 'INIT' }] });
      },
    } });
    const search = d.getElementById('nc-search');
    search.value = 'old'; search.dispatchEvent(new w.Event('input'));
    await tick(300);
    search.value = 'new'; search.dispatchEvent(new w.Event('input'));
    await tick(300);
    release(); await tick(5);
    assert(d.getElementById('nc-table-body').textContent.includes('NEW'), 'table shows: ' + d.getElementById('nc-table-body').textContent.trim());
  });

  await test('F-14 legacy tab styling toggles correctly', async () => {
    const { w, d } = await loadPortal();
    w.switchTab('legacy');
    assert(!d.getElementById('tab-legacy').classList.contains('text-steel'), 'active legacy tab is muted');
    assert(d.getElementById('tab-raw').classList.contains('text-steel'), 'inactive raw tab not muted');
  });

  await test('F-15 serial rule year position 0 is preserved', async () => {
    const { w, d, calls } = await loadPortal({ routes: {
      'GET /config/serial_rules': json({ rules: [{ prefix: 'ABC', year_pos: 0, model_base: 'M', size: '75', o2_rule: 'never' }] }),
      'POST /config/serial_rules': json({ ok: true }),
    } });
    await w.loadCfg();
    assert(d.querySelector('[data-field="year_pos"]').value === '0', 'year_pos rendered as ' + d.querySelector('[data-field="year_pos"]').value);
    await w.saveCfg();
    const body = JSON.parse(calls.find(c => c.method === 'POST' && c.url.endsWith('/config/serial_rules')).body);
    assert(body.rules[0].year_pos === 0, 'year_pos saved as ' + body.rules[0].year_pos);
  });

  await test('F-16 generated-file download links are URL-encoded', async () => {
    const { w, d, streams } = await loadPortal({ routes: { 'POST /confirm_amc': json({ ok: true }) } });
    await w.aConfirmAndGenerate();
    streams[0].onmessage({ data: JSON.stringify({ type: 'done', success: true, filename: 'AMC Aug #1?.xlsx', subtotal: 1 }) });
    const href = d.getElementById('a-download-btn').getAttribute('href');
    assert(href.endsWith('/download/AMC%20Aug%20%231%3F.xlsx'), 'href was ' + href);
  });

  // ── Happy paths: the fixes must not change successful behaviour ──────────
  await test('OK AMC analyze → confirm → stream → result, with valid and skipped dimensions', async () => {
    const { w, d, calls, streams } = await loadPortal({ routes: {
      'POST /analyze_amc': json({ ok: true, receipt_count: 1, ship_count: 1, additional_sqft: 0, missing_dimension_models: ['M1', 'M2', 'M3'] }),
      'POST /confirm_amc': json({ ok: true }),
    } });
    d.getElementById('amc-form').dispatchEvent(new w.Event('submit', { cancelable: true }));
    await tick(5);
    const inputs = d.querySelectorAll('.a-missing-dim-input');
    inputs[0].value = '12.5'; inputs[1].value = '0'; inputs[2].value = '';
    await w.aConfirmAndGenerate();
    const body = JSON.parse(calls.find(c => c.url.endsWith('/confirm_amc')).body);
    assert(JSON.stringify(body) === JSON.stringify({ dimensions: { M1: 12.5, M2: 0 } }), 'sent ' + JSON.stringify(body));
    assert(d.getElementById('a-confirm-btn').disabled, 'button should be disabled while generating');
    streams[0].onmessage({ data: JSON.stringify({ type: 'log', msg: 'working' }) });
    streams[0].onmessage({ data: JSON.stringify({ type: 'done', success: true, filename: 'AMC_AUG.xlsx', subtotal: 3686, tax: 0, total: 3686, excluded_count: 0 }) });
    assert(d.getElementById('a-total').textContent === '$3,686.00', 'total ' + d.getElementById('a-total').textContent);
    assert(d.getElementById('a-download-btn').getAttribute('href') === '/download/AMC_AUG.xlsx', 'href');
    assert(!d.getElementById('a-confirm-btn').disabled, 'button not re-enabled');
    assert(streams[0].closed, 'stream not closed');
  });

  await test('OK Workshop sanitize → review → generate → result links', async () => {
    const { w, d, streams, calls } = await loadPortal({ routes: {
      'POST /sanitize': json({ ok: true, total_records: 3, issue_count: 1, auto_count: 0, auto_corrections: [],
        issues: [{ row_index: 4, field: 'Actual Model', 'Actual Model': 'AP9', description: 'Unknown model', current_value: 'AP9', suggested_values: ['AP9-A75-NA-R'] }] }),
      'POST /generate': json({ ok: true, output: 'C:\\\\out\\\\Promethean_Invoice_Sep_2026.xlsx' }),
    } });
    d.getElementById('sanitize-form').dispatchEvent(new w.Event('submit', { cancelable: true }));
    await tick(5);
    assert(d.getElementById('review-summary').textContent.startsWith('3 records'), 'summary');
    const sel = d.querySelector('#issues-tbody select');
    sel.value = 'AP9-A75-NA-R'; sel.dispatchEvent(new w.Event('change'));
    await w.generateFromRaw();
    const fd = calls.find(c => c.url.endsWith('/generate')).body;
    assert(JSON.parse(fd.get('corrections'))['4'].value === 'AP9-A75-NA-R', 'correction not sent');
    streams[0].onmessage({ data: JSON.stringify({ type: 'done', success: true, depot_count: 2, triage_count: 1, subtotal: 245, total: 245,
      corrected_filename: 'corr.xlsx', master_filename: 'master.xlsx' }) });
    assert(d.getElementById('dl-invoice').getAttribute('href') === '/download/Promethean_Invoice_Sep_2026.xlsx', 'invoice href ' + d.getElementById('dl-invoice').getAttribute('href'));
    assert(d.getElementById('dl-master').getAttribute('href') === '/download/master.xlsx', 'master href');
    assert(d.getElementById('r-subtotal').textContent === '$245.00', 'subtotal');
  });

  await test('OK valid storage, AMC and repair-cost prices (including 0) are saved as numbers', async () => {
    const { w, d, calls } = await loadPortal({ routes: {
      'GET /get_storage_prices': json({ ok: true, defaults: { part_type_prices: { PSU: 5 }, line_prices: { unit_storage: 2 } },
        part_type_prices: { PSU: 5 }, line_prices: { unit_storage: 2 } }),
      'POST /set_storage_prices': json({ ok: true }),
      'GET /get_amc_prices': json({ ok: true, defaults: { unit_receipt: 3 }, prices: { unit_receipt: 3, storage_base: 500 } }),
      'POST /set_amc_prices': json({ ok: true }),
      'GET /get_philips_repair_cost': json({ ok: true, tiers: [{ size: '50', rb_price: 90, harvest_price: 40, box_build: 25 }] }),
      'POST /set_philips_repair_cost': json({ ok: true, count: 1 }),
      'GET /config/serial_rules': json({ rules: [] }),
    } });
    w.showPage('config');
    await tick(10);
    d.querySelector('[data-type="part"]').value = '0';
    await w.savePricing();
    const sp = JSON.parse(calls.find(c => c.url.endsWith('/set_storage_prices')).body);
    assert(sp.part_type_prices.PSU === 0 && sp.line_prices.unit_storage === 2, JSON.stringify(sp));
    assert(/saved/.test(d.getElementById('pricing-status').textContent), 'no confirmation');
    await w.amcSavePricing();
    const ap = JSON.parse(calls.find(c => c.url.endsWith('/set_amc_prices')).body);
    assert(ap.prices.unit_receipt === 3 && ap.prices.storage_base === 500, JSON.stringify(ap));
    d.querySelector('.rc-rb').value = '95';
    await w.rcSave();
    const rc = JSON.parse(calls.find(c => c.url.endsWith('/set_philips_repair_cost')).body);
    assert(JSON.stringify(rc.tiers) === JSON.stringify([{ size: '50', rb_price: 95, harvest_price: 40, box_build: 25 }]), JSON.stringify(rc));
    assert(/Saved 1 tier/.test(d.getElementById('rc-status').textContent), 'rc status');
  });

  await test('OK repair-cost add/remove keeps typed values', async () => {
    const { w, d } = await loadPortal({ routes: {
      'GET /get_philips_repair_cost': json({ ok: true, tiers: [{ size: '50', rb_price: 90, harvest_price: 40, box_build: 25 }] }) } });
    await w.rcLoad();
    w.rcAddTier();
    const rows = d.querySelectorAll('#rc-tiers-form [data-idx]');
    rows[1].querySelector('.rc-size').value = '60';
    rows[1].querySelector('.rc-rb').value = '100';
    w.rcRemoveTier(0);
    const left = d.querySelectorAll('#rc-tiers-form [data-idx]');
    assert(left.length === 1 && left[0].querySelector('.rc-size').value === '60' && left[0].querySelector('.rc-rb').value === '100', 'values lost');
  });

  await test('OK TCL valid breakdown confirms and shows totals', async () => {
    const { w, d, calls, streams } = await loadPortal({ routes: {
      'POST /analyze_tcl': json({ ok: true, unit_count: 5, part_count: 45,
        unit_groups: [{ key: 'u1', received_date: '2026-08-01', quantity: 5 }],
        part_groups: [{ key: 'p1', model: 'PART', received_date: '2026-08-02', quantity: 45 }] }),
      'POST /confirm_tcl': json({ ok: true }),
    } });
    d.getElementById('tcl-form').dispatchEvent(new w.Event('submit', { cancelable: true }));
    await tick(5);
    assert(d.querySelector('.t-box-input').value === '20,20,5', 'default box split ' + d.querySelector('.t-box-input').value);
    d.querySelector('.t-unit-input').value = '3,2';
    await w.tConfirmAndGenerate();
    const body = JSON.parse(calls.find(c => c.url.endsWith('/confirm_tcl')).body);
    assert(body.unit_breakdowns.u1 === '3,2' && body.box_breakdowns.p1 === '20,20,5', JSON.stringify(body));
    streams[0].onmessage({ data: JSON.stringify({ type: 'done', success: true, filename: 'TCL.xlsx', subtotal: 78.85, tax: 0, total: 78.85, total_pallets: 2, pallet_rate: 10, box_count: 3, line_count: 4 }) });
    assert(d.getElementById('t-subtotal').textContent === '$78.85', 'subtotal');
  });

  await test('OK NonConforming delete with an empty 200 body closes the record', async () => {
    const { w, d } = await loadPortal({ routes: {
      'GET /nonconforming/api/items/9': json({ ok: true, item: { id: 9, number: 'NC-9', model: 'M', serial: 'S', carrier: 'C' } }),
      'DELETE /nonconforming/api/items/9': { ok: true, status: 200, redirected: false, headers: { get: () => '' },
        json: async () => { throw new SyntaxError('Unexpected end of JSON input'); }, text: async () => '' },
    } });
    d.getElementById('nc-table-body').innerHTML = '<tr><td><button data-action="edit" data-id="9">Edit</button></td></tr>';
    d.querySelector('[data-action="edit"]').click();
    await tick(5);
    assert(!d.getElementById('nc-edit-modal').classList.contains('hidden'), 'modal did not open');
    assert(d.getElementById('nc-edit-model').value === 'M', 'field not populated');
    d.getElementById('nc-edit-delete').click();
    await tick(5);
    assert(d.getElementById('nc-edit-modal').classList.contains('hidden'), 'modal still open after successful delete');
  });

  await test('OK storage prices blank field still shows other values after reset to defaults', async () => {
    const { w, d } = await loadPortal({ routes: {
      'GET /get_storage_prices': json({ ok: true, defaults: { part_type_prices: { PSU: 5 }, line_prices: { unit_storage: 2 } },
        part_type_prices: { PSU: 7 }, line_prices: { unit_storage: 3 } }),
      'GET /config/serial_rules': json({ rules: [] }),
    } });
    w.showPage('config');
    await tick(10);
    w.resetPricing();
    assert(d.querySelector('[data-type="part"]').value === '5', 'defaults not rendered');
    assert(/click Save/.test(d.getElementById('pricing-status').textContent), 'reset not explained');
  });

  await tick(20);
  results.push([unhandled.length === 0, 'no unhandled promise rejections during the run',
    unhandled.length ? unhandled.map(e => e && e.message).join('; ') : undefined]);
  const failed = results.filter(r => !r[0]);
  for (const r of results) console.log((r[0] ? 'PASS ' : 'FAIL ') + r[1] + (r[2] ? '\n     -> ' + r[2] : ''));
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  process.exit(failed.length ? 1 : 0);
})();
