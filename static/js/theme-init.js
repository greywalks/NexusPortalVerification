(function () {
  const routePrefix = '/index.cfm';

  function explicitRoute(value) {
    if (typeof value !== 'string' || !value.startsWith('/') || value.startsWith('//')) return value;
    if (value === routePrefix || value.startsWith(routePrefix + '/') || value.startsWith(routePrefix + '?') || value.startsWith('/static/')) return value;
    if (value === '/') return routePrefix;
    if (value.startsWith('/?')) return routePrefix + value.slice(1);
    return routePrefix + value;
  }

  window.ussiRouteUrl = explicitRoute;

  const nativeFetch = window.fetch.bind(window);
  window.fetch = function (input, init) {
    return nativeFetch(typeof input === 'string' ? explicitRoute(input) : input, init);
  };

  function rewriteAttribute(element, attribute) {
    const value = element.getAttribute(attribute);
    const explicit = explicitRoute(value);
    if (explicit !== value) element.setAttribute(attribute, explicit);
  }

  function rewriteDocumentRoutes(root) {
    (root || document).querySelectorAll('a[href]').forEach(function (link) {
      rewriteAttribute(link, 'href');
    });
    (root || document).querySelectorAll('form[action]').forEach(function (form) {
      rewriteAttribute(form, 'action');
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    rewriteDocumentRoutes(document);
  });
  document.addEventListener('click', function (event) {
    const link = event.target.closest?.('a[href]');
    if (link) rewriteAttribute(link, 'href');
  }, true);
  document.addEventListener('submit', function (event) {
    if (event.target.matches?.('form[action]')) rewriteAttribute(event.target, 'action');
  }, true);

  const html = document.documentElement;
  const allowed = ['system', 'light', 'dark'];
  const serverPreference = html.dataset.themePreference;
  let savedPreference = '';
  let legacyTheme = '';

  try {
    savedPreference = localStorage.getItem('themePreference') || '';
    legacyTheme = localStorage.getItem('theme') || '';
  } catch (error) {}

  const preference = allowed.includes(serverPreference)
    ? serverPreference
    : (allowed.includes(savedPreference) ? savedPreference : (allowed.includes(legacyTheme) ? legacyTheme : 'system'));
  const media = window.matchMedia('(prefers-color-scheme: light)');

  function apply(value) {
    const normalized = allowed.includes(value) ? value : 'system';
    html.dataset.themePreference = normalized;
    html.dataset.theme = normalized === 'system' ? (media.matches ? 'light' : 'dark') : normalized;
    try {
      localStorage.setItem('themePreference', normalized);
      localStorage.setItem('theme', html.dataset.theme);
    } catch (error) {}
  }

  window.ussiApplyThemePreference = apply;
  apply(preference);
  media.addEventListener?.('change', function () {
    if (html.dataset.themePreference === 'system') apply('system');
  });
})();
