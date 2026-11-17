import { renderMarkdown } from './markdown/vendor.mjs';
const $ = selector => document.querySelector(selector);
const body = $('#document'), source = $('#source'), notice = $('#notice');
let revision = 0, filename = '', armed = false, live = false, cursor = 1, polling = false, paused = false, timer;
let pending = false;
const client = Math.random().toString(36).slice(2);
function element(node) { return node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement; }
function block(node) { return element(node)?.closest('[data-line]'); }
function sourceText(range) {
  const fragment = range.cloneContents();
  const enclosing = element(range.commonAncestorContainer)?.closest('[data-source]');
  if (enclosing && enclosing.textContent === fragment.textContent) return enclosing.dataset.source;
  let mapped = false;
  for (const node of fragment.querySelectorAll('[data-source]')) {
    const original = [...body.querySelectorAll('[data-source]')].find(original =>
      original.dataset.source === node.dataset.source && original.textContent === node.textContent);
    if (original) { node.replaceWith(node.dataset.source); mapped = true; }
  }
  if (!mapped) return range.toString().trim();
  for (const node of fragment.querySelectorAll('[data-line], br')) node.append('\n');
  return fragment.textContent.trim();
}
function selected() {
  const selection = getSelection();
  if (!selection?.rangeCount || selection.isCollapsed) return null;
  const range = selection.getRangeAt(0), first = block(range.startContainer), last = block(range.endContainer);
  if (!first || !last || !body.contains(first) || !body.contains(last)) return null;
  return { line: Number(first.dataset.line), end_line: Number(last.dataset.endLine), text: sourceText(range) };
}
function controls() {
  source.textContent = selected()?.text ? 'Select in source' : armed ? 'Cancel locate' : 'Locate in source';
  source.disabled = !live || !revision;
  source.title = !live ? 'Source navigation resumes when the preview reconnects'
    : !revision ? 'Waiting for a draft from the editor'
    : 'Select text to select it in the editor, or locate a passage in the draft';
  const state = !live ? 'Offline · retrying' : pending ? 'Update pending · clear selection to load' : 'Live draft';
  if ($('#state').textContent !== state) $('#state').textContent = state;
}
function arm(value) {
  armed = value;
  source.setAttribute('aria-pressed', String(value));
  body.classList.toggle('locating', value);
  controls();
}
function session(value) {
  live = value;
  const message = live ? 'Connected to Vim · live draft' : 'Disconnected · keeping the last draft, retrying';
  $('#session').dataset.state = value ? 'connected' : 'disconnected';
  $('#session').title = message;
  $('#session').setAttribute('aria-label', `Preview session: ${value ? 'connected' : 'disconnected'}`);
  controls();
}
function anchor() {
  const top = $('header').getBoundingClientRect().bottom;
  const nodes = [...body.querySelectorAll('[data-line]')];
  const node = nodes.find(node => node.getBoundingClientRect().bottom > top);
  return node && { line: Number(node.dataset.line), offset: node.getBoundingClientRect().top };
}
function near(line) {
  return [...body.querySelectorAll('[data-line]')].filter(node => Number(node.dataset.line) <= line
    && Number(node.dataset.endLine) >= line).at(-1);
}
function showCursor() {
  body.querySelector('[data-current]')?.removeAttribute('data-current');
  const node = near(cursor);
  if (!node) return;
  node.setAttribute('data-current', '');
  const bounds = node.getBoundingClientRect();
  if ($('#follow').checked && (bounds.top < $('header').offsetHeight || bounds.bottom > innerHeight)) {
    node.scrollIntoView({ block: 'center' });
  }
}
async function inverse(position) {
  try {
    const response = await fetch('./inverse', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...position, revision }), signal: AbortSignal.timeout(5000) });
    notice.textContent = await response.text();
  } catch { notice.textContent = 'Connection lost · this page will retry'; }
}
source.onpointerdown = event => { if (selected()) event.preventDefault(); };
source.onclick = () => {
  const passage = selected();
  if (passage?.text) {
    arm(false); inverse(passage);
  } else {
    arm(!armed);
    notice.textContent = armed ? 'Tap a passage to locate it in Vim · Esc cancels' : '';
  }
};
body.addEventListener('click', event => {
  const node = block(event.target);
  if (armed && live && node) {
    event.preventDefault(); event.stopPropagation(); arm(false);
    inverse({ line: Number(node.dataset.line) });
  } else {
    const link = event.target.closest('a[data-file]');
    if (link) {
      event.preventDefault(); inverse({ path: link.dataset.file });
    }
  }
}, true);
$('#follow').onchange = showCursor;
$('#session').onclick = () => { notice.textContent = $('#session').title + '. Quitting Vim ends this session.'; };
document.addEventListener('selectionchange', controls);
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') {
    if ($('#options').open) {
      $('#options').open = false;
      $('#options > summary').focus();
    } else if (armed) {
      arm(false);
      source.focus({ preventScroll: true });
      notice.textContent = '';
    } else notice.textContent = '';
  }
});
document.addEventListener('pointerdown', event => { if (!event.target.closest('#options')) $('#options').open = false; });

async function poll() {
  if (polling || paused) return;
  clearTimeout(timer); polling = true;
  try {
    const response = await fetch(`./state?client=${client}&revision=${revision}`, { cache: 'no-store', signal: AbortSignal.timeout(5000) });
    if (!response.ok) throw Error('Session ended');
    const state = await response.json();
    pending = state.revision !== revision && Boolean(selected());
    session(true);
    if (state.revision !== revision && !selected()) {
      const position = filename === state.name ? anchor() : null;
      body.innerHTML = renderMarkdown(state.text);
      revision = state.revision;
      pending = false;
      $('#name').textContent = state.name;
      $('#name').title = state.name;
      filename = state.name;
      document.title = state.name + ' · WebPreview';
      if (position) {
        const node = near(position.line);
        if (node) window.scrollBy(0, node.getBoundingClientRect().top - position.offset);
      } else window.scrollTo(0, 0);
    }
    if (!selected() && (cursor !== state.cursor.line || state.revision === revision)) {
      cursor = state.cursor.line; showCursor();
    }
    controls();
  } catch { session(false); arm(false); }
  finally {
    polling = false;
    if (!paused) timer = setTimeout(poll, 400);
  }
}
window.addEventListener('pagehide', () => {
  paused = true; clearTimeout(timer);
  navigator.sendBeacon('./leave', JSON.stringify({ client }));
});
window.addEventListener('pageshow', () => { paused = false; poll(); });
document.addEventListener('visibilitychange', () => { if (!document.hidden) poll(); });
poll();
