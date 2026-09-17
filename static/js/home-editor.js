// Bulletin editor for the home page: a contenteditable area with a small
// toolbar. On submit the content is reduced to a fixed subset of markup
// (paragraphs, emphasis, lists, headings, marks, links); the server sanitizes
// it again, so this normaliser is for tidy output, not for security.
(function () {
  var KEEP = { P: 'p', BR: 'br', STRONG: 'strong', B: 'strong', EM: 'em', I: 'em', U: 'u', UL: 'ul', OL: 'ol', LI: 'li', H3: 'h3', H4: 'h3', H2: 'h3', BLOCKQUOTE: 'blockquote', MARK: 'mark', S: 's', STRIKE: 's', A: 'a' };
  var BLOCK = { DIV: 1, SECTION: 1, ARTICLE: 1 };

  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }

  function serialise(node) {
    var out = '';
    node.childNodes.forEach(function (n) {
      if (n.nodeType === 3) { out += esc(n.nodeValue); return; }
      if (n.nodeType !== 1) return;
      var tag = KEEP[n.tagName];
      if (n.tagName === 'SPAN' && /background/.test(n.getAttribute('style') || '')) tag = 'mark';
      if (BLOCK[n.tagName]) { out += '<p>' + serialise(n) + '</p>'; return; }
      if (!tag) { out += serialise(n); return; }
      if (tag === 'br') { out += '<br>'; return; }
      if (tag === 'a') {
        var href = n.getAttribute('href') || '';
        var target = n.getAttribute('target') === '_blank' ? ' target="_blank"' : '';
        out += '<a href="' + esc(href) + '"' + target + '>' + serialise(n) + '</a>';
        return;
      }
      out += '<' + tag + '>' + serialise(n) + '</' + tag + '>';
    });
    return out;
  }

  function insertLink(editor) {
    editor.focus();
    var sel = window.getSelection();
    if (!sel.rangeCount || sel.isCollapsed) { alert('Select the text you want to turn into a link first.'); return; }
    var url = prompt('Link address (https://… , mailto:… or /path):');
    if (!url) return;
    url = url.trim();
    if (!/^(https?:\/\/|mailto:|tel:|\/)/i.test(url)) { alert('The address must start with http://, https://, mailto:, tel: or /.'); return; }
    var newTab = confirm('Open this link in a new tab?\n\nOK = new tab, Cancel = same page');
    var range = sel.getRangeAt(0);
    var a = document.createElement('a');
    a.href = url;
    if (newTab) { a.target = '_blank'; a.rel = 'noopener noreferrer'; }
    try { range.surroundContents(a); } catch (e) { a.appendChild(range.extractContents()); range.insertNode(a); }
  }

  // Open the section named in the URL hash (after a save/redirect) and scroll to it;
  // otherwise open the first section so the page is not a wall of closed rows.
  (function () {
    var target = location.hash && document.querySelector(location.hash + '.home-edit-section');
    if (target) { target.open = true; target.scrollIntoView({ block: 'start' }); }
    else { var first = document.querySelector('.home-edit-section'); if (first) first.open = true; }
  })();

  document.querySelectorAll('.home-toolbar').forEach(function (bar) {
    var editor = document.getElementById(bar.dataset.for);
    if (!editor) return;
    bar.addEventListener('click', function (e) {
      var btn = e.target.closest('button[data-cmd]');
      if (!btn) return;
      e.preventDefault();
      var cmd = btn.dataset.cmd;
      editor.focus();
      if (cmd === 'link') insertLink(editor);
      else if (cmd === 'unlink') document.execCommand('unlink');
      else if (cmd === 'heading') document.execCommand('formatBlock', false, 'h3');
      else if (cmd === 'highlight') document.execCommand('hiliteColor', false, '#fff59d');
      else if (cmd === 'clear') { document.execCommand('removeFormat'); document.execCommand('formatBlock', false, 'p'); }
      else document.execCommand(cmd);
    });
    editor.addEventListener('paste', function (e) {
      // Paste as plain text so foreign markup never enters the bulletin.
      e.preventDefault();
      var text = (e.clipboardData || window.clipboardData).getData('text/plain');
      document.execCommand('insertText', false, text);
    });
    var form = editor.closest('form');
    var hidden = document.getElementById(editor.id + '-input');
    if (form && hidden) form.addEventListener('submit', function () { hidden.value = serialise(editor); });
  });
})();
