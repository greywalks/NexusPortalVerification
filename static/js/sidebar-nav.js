// ── Shared sidebar nav (safe subset of app.js) ────────────────────────────────
// Used on pages that render the portal sidebar but aren't the main SPA page
// (currently: Training Tracker and Inventory Management). Keeps only what the sidebar
// needs — mobile open/close and portal-level tab navigation — without the
// rest of app.js, which assumes Invoice Generator form elements exist on the
// page and would throw on load here.
//
// On index.html itself, the full app.js defines these same functions with
// richer behavior (breadcrumbs, SPA tab toggling, etc.) — don't load both
// files on the same page, one will just overwrite the other's definitions.

(function () {
  window.closeSidebarMobile = function () {
    document.getElementById('sidebar')?.classList.remove('open');
    document.getElementById('sidebar-scrim')?.classList.remove('open');
  };

  window.toggleSidebar = function () {
    document.getElementById('sidebar')?.classList.toggle('open');
    document.getElementById('sidebar-scrim')?.classList.toggle('open');
  };

  // Portal-level tabs (Invoice Generator / SMS NonConforming / TBD 2) only
  // exist as SPA divs on index.html. From here, always do a real navigation
  // back to the portal root and let index.html's own app.js restore the tab.
  window.showPortalPage = function (portal) {
    window.location.href = '/index.cfm?portal=' + portal;
  };

  // ── Theme toggle ──────────────────────────────────────────────────────────
  window.toggleTheme = function () {
    const html = document.documentElement;
    const next = html.dataset.theme === 'light' ? 'dark' : 'light';
    if (window.ussiApplyThemePreference) window.ussiApplyThemePreference(next);
    else html.dataset.theme = next;
    const label = document.getElementById('toggle-label');
    if (label) label.textContent = next === 'light' ? '🌙' : '☀';
    fetch('/account/theme', {
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: new URLSearchParams({theme: next}).toString()
    }).catch(() => {});
  };

  (function () {
    const label = document.getElementById('toggle-label');
    if (label) label.textContent = document.documentElement.dataset.theme === 'light' ? '🌙' : '☀';
  })();
})();
