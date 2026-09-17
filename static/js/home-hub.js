// Home hub: links marked "new window" open a separate browser window rather
// than a tab. Everything else is plain markup.
(function () {
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a[data-open="window"]');
    if (!a) return;
    e.preventDefault();
    var w = window.open(a.href, '_blank', 'popup=yes,noopener=yes,noreferrer=yes,width=1200,height=800');
    if (!w) window.open(a.href, '_blank', 'noopener');
  });
})();
