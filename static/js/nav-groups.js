// Collapsible sidebar groups shared by the portal page and the workspace shell.
// A group opens when it contains the active link, or when the user opened it
// last time (remembered per browser). Groups whose every item is hidden by the
// permission filter disappear entirely.
(function () {
  var KEY = 'nexus.nav.open';
  function load() { try { return JSON.parse(localStorage.getItem(KEY) || '{}'); } catch (e) { return {}; } }
  function save(state) { try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) {} }

  function visible(el) { return !el.classList.contains('hidden') && el.offsetParent !== null; }

  function init() {
    var state = load();
    document.querySelectorAll('.nav-group').forEach(function (group) {
      var key = group.dataset.group;
      var items = group.querySelector('.nav-group-items');
      var toggle = group.querySelector('.nav-group-toggle');
      if (!items || !toggle) return;
      var anyVisible = Array.prototype.some.call(items.children, function (c) { return !c.classList.contains('hidden'); });
      group.classList.toggle('hidden', !anyVisible);
      if (!anyVisible) return;
      var hasActive = !!items.querySelector('.active');
      var open = hasActive || state[key] === true || (state[key] === undefined && group.dataset.defaultOpen === 'true');
      set(group, toggle, open);
      if (group.dataset.navInit === '1') return; // re-run only refreshes visibility
      group.dataset.navInit = '1';
      toggle.addEventListener('click', function () {
        var next = !group.classList.contains('open');
        set(group, toggle, next);
        state[key] = next; save(state);
      });
    });
  }
  function set(group, toggle, open) {
    group.classList.toggle('open', open);
    toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
  // The permission filter (lucee-auth.js) may hide items after we first ran; re-check once everything has loaded.
  window.addEventListener('load', init);
  window.ussiNavGroupsInit = init;
})();
