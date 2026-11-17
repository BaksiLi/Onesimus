import * as pdfjs from './pdfjs/build/pdf.min.mjs';
import { EventBus, FindState, PDFFindController, PDFLinkService, PDFViewer } from './pdfjs/web/pdf_viewer.mjs';

pdfjs.GlobalWorkerOptions.workerSrc = new URL('./pdfjs/build/pdf.worker.min.mjs', import.meta.url).href;
const $ = selector => document.querySelector(selector);
const container = $('#pages'), status = $('#status'), refreshButton = $('#refresh'), sourceButton = $('#source');
const findBar = $('#find-bar'), query = $('#query'), detail = $('#change-detail');
const bus = new EventBus();
const links = new PDFLinkService({ eventBus: bus, externalLinkTarget: 2, externalLinkRel: 'noopener noreferrer' });
const find = new PDFFindController({ eventBus: bus, linkService: links });
const viewer = new PDFViewer({
  container, eventBus: bus, linkService: links, findController: find, annotationEditorMode: pdfjs.AnnotationEditorType.DISABLE,
  imageResourcesPath: './pdfjs/web/images/',
});
links.setViewer(viewer);
let shown = '', latest = '', loading = false, position = null, located = 0, restore = null;
let armed = false, syncAvailable = false, connected = null;
let noticeUntil = 0;
let documentError = '', manualScale = 1;
let diff, diffRequest = 0, observedPosition = null, shownMode = 'original', wantedMode = 'original';
const views = {};
let detailKind = '', findOrigin = null;
const back = [];
// Presence belongs to this page, not to the lifetime of its reader process.
const client = Math.random().toString(36).slice(2);
let pollTimer, polling = false, paused = false;
let savedView = null;
try { savedView = JSON.parse(sessionStorage.getItem(location.pathname)); } catch { /* An old tab may have invalid saved state. */ }
if (savedView?.version === 'changes') wantedMode = 'changes';
diffRequest = savedView?.request || 0;
observedPosition = savedView?.position ?? null;
window.addEventListener('pagehide', () => {
  paused = true;
  clearTimeout(pollTimer);
  navigator.sendBeacon('./leave', JSON.stringify({ client }));
  sessionStorage.setItem(location.pathname, JSON.stringify({ ...currentView(), version: shownMode,
    request: diffRequest, position: observedPosition }));
});
window.addEventListener('pageshow', () => { paused = false; poll(); });
document.addEventListener('visibilitychange', () => { if (!document.hidden) poll(); });

function selection() {
  const selected = window.getSelection();
  if (!selected?.rangeCount || selected.isCollapsed) return null;
  const range = selected.getRangeAt(0);
  const element = node => node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
  if (!element(range.startContainer)?.closest('.textLayer') || !element(range.endContainer)?.closest('.textLayer')) return null;
  return { range, text: selected.toString().trim() };
}

function notice(message) {
  status.textContent = message;
  noticeUntil = Date.now() + 5000;
}

function updateControls() {
  const revision = shownMode === 'changes' ? diff?.sha256 : latest;
  const newer = revision && shown !== revision;
  const [label, explanation] = documentStatus();
  const canRefresh = connected && newer && !loading;
  refreshButton.disabled = loading;
  refreshButton.textContent = label;
  refreshButton.title = explanation;
  refreshButton.dataset.action = canRefresh ? 'refresh' : 'details';
  refreshButton.classList.toggle('loading', loading);
  sourceButton.textContent = selection()?.text ? 'Select in source' : armed ? 'Cancel locate' : 'Locate in source';
  const current = shownMode === 'original' ? shown === latest
    : diff?.sync && shown === diff.sha256 && diff.source_revision === latest && diff.status !== 'needs-build';
  sourceButton.disabled = !connected || !syncAvailable || !shown || !current || loading;
  sourceButton.title = !connected ? 'Source navigation resumes when the preview reconnects'
    : !syncAvailable ? 'Open this preview from an editor to navigate to source'
    : !current || loading ? 'Source navigation needs the latest completed build'
    : shownMode === 'changes' ? 'Locate surviving text in the manuscript; removed passages locate nearby source'
    : 'Select text to select it in the editor, or locate a place in the PDF';
  if (detailKind === 'build') showDetail('build', 'PDF status', explanation);
  diffControls();
}

function documentStatus() {
  if (loading) return ['Loading…', 'Loading a complete PDF.'];
  if (connected === false) return ['Offline', sessionText()];
  if (documentError) return [shown ? 'Build unavailable' : 'Waiting', documentError];
  if (diff?.status === 'needs-build') return ['Needs build', diff.error];
  if (shownMode === 'changes' || wantedMode === 'changes') {
    const [label, text] = diffStatus();
    if (label) return [label, text];
  }
  const revision = shownMode === 'changes' ? diff?.sha256 : latest;
  if (revision && revision !== shown) return ['New PDF', 'Load the newer completed build.'];
  return shown ? ['Up to date', shownMode === 'changes' ? diffStatus()[1]
    : 'Showing the latest completed PDF. Source edits need a build in the editor.']
    : ['Waiting', 'Waiting for a complete PDF.'];
}

function currentView() {
  if (!viewer.pagesCount) return { scale: 'page-width' };
  const page = viewer.currentPageNumber, view = viewer.getPageView(page - 1);
  const rect = view.div.getBoundingClientRect(), bounds = container.getBoundingClientRect();
  const [x, y] = view.viewport.convertToPdfPoint(Math.max(0, bounds.left - rect.left), bounds.top - rect.top);
  return { page, x, y, scale: viewer.currentScaleValue };
}

/** Whether a viewport point on this page is comfortably inside the visible reader. */
function inView(view, top) {
  const page = view.div.getBoundingClientRect(), bounds = container.getBoundingClientRect();
  const at = page.top + page.height * top / view.viewport.height, margin = bounds.height / 8;
  return at > bounds.top + margin && at < bounds.bottom - margin;
}

function locate() {
  if (shownMode !== 'original' || selection() || !position || position.revision !== shown || position.id === located || !viewer.pagesCount) return;
  const view = viewer.getPageView(position.page - 1);
  if (!view?.pdfPage) {
    viewer.currentPageNumber = position.page;
    return;
  }
  const y = view.pdfPage.view[3] - position.y;
  const [left, top] = view.viewport.convertToViewportPoint(position.x, y);
  if (!(position.follow && inView(view, top))) {
    viewer.scrollPageIntoView({
      pageNumber: position.page, destArray: [null, { name: 'XYZ' }, position.x, y, null],
      ignoreDestinationZoom: true,
    });
    container.scrollTop = Math.max(0, container.scrollTop - container.clientHeight / 4);
  }
  document.querySelector('.sync-target')?.remove();
  const marker = document.createElement('span');
  marker.className = position.follow ? 'sync-target is-follow' : 'sync-target';
  marker.style.left = `${100 * left / view.viewport.width}%`;
  marker.style.top = `${100 * top / view.viewport.height}%`;
  view.div.append(marker);
  located = position.id;
}

bus.on('pagesinit', () => {
  viewer.currentScaleValue = restore.scale;
  if (restore.page) {
    viewer.scrollPageIntoView({
      pageNumber: Math.min(restore.page, viewer.pagesCount),
      destArray: [null, { name: 'XYZ' }, restore.x, restore.y, null], ignoreDestinationZoom: true,
    });
  }
  $('#page').value = viewer.currentPageNumber;
  $('#count').textContent = `/ ${viewer.pagesCount}`;
  $('#page').max = viewer.pagesCount;
  if (!findBar.hidden && query.value) search();
  locate();
});
bus.on('pagerendered', locate);
bus.on('pagechanging', event => { $('#page').value = event.pageNumber; });
$('#page').onchange = event => {
  if (!viewer.pdfDocument) return;
  viewer.currentPageNumber = Math.min(viewer.pagesCount, Math.max(1, Math.trunc(Number(event.target.value) || 1)));
  event.target.value = viewer.currentPageNumber;
};
$('#smaller').onclick = () => viewer.pdfDocument && viewer.decreaseScale();
$('#larger').onclick = () => viewer.pdfDocument && viewer.increaseScale();
function fitState() {
  const fitting = viewer.currentScaleValue === 'page-width';
  $('#fit').setAttribute('aria-pressed', String(fitting));
  if (!fitting && Number(viewer.currentScaleValue) > 0) manualScale = Number(viewer.currentScaleValue);
}
bus.on('scalechanging', fitState);
$('#fit').onclick = () => {
  if (viewer.pdfDocument) viewer.currentScaleValue = viewer.currentScaleValue === 'page-width' ? manualScale : 'page-width';
};
new ResizeObserver(() => {
  if (viewer.pdfDocument && viewer.currentScaleValue === 'page-width') viewer.currentScaleValue = 'page-width';
}).observe(container);

async function refresh(mode = shownMode) {
  const expected = mode === 'changes' ? diff?.sha256 : latest;
  if (!expected || loading || shown === expected && shownMode === mode) return;
  loading = true;
  updateControls();
  try {
    const response = await fetch(mode === 'changes' ? './diff' : './pdf', { cache: 'no-store', signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw Error('PDF unavailable');
    const revision = response.headers.get('X-PDF-Revision');
    const data = new Uint8Array(await response.arrayBuffer());
    if (viewer.pagesCount) views[shownMode] = currentView();
    restore = views[mode] || (savedView && (savedView.version || 'original') === mode ? savedView : { scale: currentView().scale });
    if ((savedView?.version || 'original') === mode) savedView = null;
    const previous = viewer.pdfDocument;
    // PDF.js shares page bookkeeping between documents. Close the old one
    // before loading a revision, after its complete bytes have arrived.
    viewer.setDocument(null);
    links.setDocument(null);
    shown = '';
    back.length = 0;
    $('#back').hidden = true;
    if (previous) await previous.destroy();
    const next = await pdfjs.getDocument({
      data, isEvalSupported: false,
      cMapUrl: './pdfjs/cmaps/', cMapPacked: true,
      standardFontDataUrl: './pdfjs/standard_fonts/', wasmUrl: './pdfjs/wasm/',
    }).promise;
    shown = revision;
    shownMode = mode;
    arm(false);
    viewer.setDocument(next);
    links.setDocument(next);
  } catch (error) {
    notice(`Could not load PDF · ${error.message}`);
  } finally {
    loading = false;
    updateControls();
  }
}
refreshButton.onclick = () => {
  if (refreshButton.dataset.action === 'refresh') refresh();
  else if (detailKind === 'build') closeDetail();
  else showDetail('build', 'PDF status', documentStatus()[1]);
};
$('#auto').onchange = event => { if (event.target.checked) refresh(); };

function arm(value) {
  armed = value;
  sourceButton.setAttribute('aria-pressed', String(value));
  container.classList.toggle('locating', value);
  sourceButton.textContent = selection()?.text ? 'Select in source' : value ? 'Cancel locate' : 'Locate in source';
}
function point(page, clientX, clientY) {
  const view = viewer.getPageView(Number(page.dataset.pageNumber) - 1);
  const rect = page.getBoundingClientRect();
  const [x, y] = view.viewport.convertToPdfPoint(clientX - rect.left, clientY - rect.top);
  return { page: view.id, x, y: view.pdfPage.view[3] - y };
}
async function inverse(request) {
  try {
    const response = await fetch('./inverse', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      signal: AbortSignal.timeout(10000),
      body: JSON.stringify({ ...request, revision: shown, version: shownMode }),
    });
    notice(await response.text());
  } catch {
    notice('Connection lost · this tab will retry automatically');
  }
}
// Keep the native text selection when the author presses the toolbar action.
sourceButton.onpointerdown = event => { if (selection()) event.preventDefault(); };
sourceButton.onclick = () => {
  const selected = selection();
  if (selected?.text) {
    const { range, text } = selected;
    const rects = [...range.getClientRects()].filter(rect => rect.width && rect.height);
    if (!rects.length) return;
    const first = rects[0], last = rects.at(-1);
    const pageOf = node => (node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement).closest('.page');
    inverse({ ...point(pageOf(range.startContainer), first.left + 1, first.top + first.height / 2), text,
      end: point(pageOf(range.endContainer), last.right - 1, last.top + last.height / 2) });
    arm(false);
    return;
  }
  arm(!armed);
  if (armed) status.textContent = 'Tap a place in the PDF to locate it in the source editor · Esc cancels';
  else status.textContent = '';
};
document.addEventListener('selectionchange', updateControls);
document.addEventListener('keydown', event => {
  const command = (event.metaKey || event.ctrlKey) && !event.altKey ? event.key.toLowerCase() : '';
  if (command === 'f') {
    event.preventDefault();
    openFind();
  } else if (command === 'g' && query.value) {
    event.preventDefault();
    if (findBar.hidden) openFind(true, event.shiftKey); else search(true, event.shiftKey);
  } else if (event.key === 'Escape') {
    if ($('#options').open) {
      $('#options').open = false;
      $('#options > summary').focus();
    } else if (armed) {
      arm(false);
      status.textContent = '';
      sourceButton.focus({ preventScroll: true });
    } else if (findBar.contains(document.activeElement) || (detail.hidden && !findBar.hidden)) {
      closeFind();
    } else if (!detail.hidden) {
      closeDetail();
    }
  }
});
container.addEventListener('click', event => {
  if (!armed || sourceButton.disabled) return;
  const page = event.target.closest('.page');
  if (!page) return;
  event.preventDefault();
  event.stopPropagation();
  arm(false);
  inverse(point(page, event.clientX, event.clientY));
}, true);
// Citation links keep a small return stack without changing the session URL.
container.addEventListener('click', event => {
  if (event.target.closest('.linkAnnotation a[href^="#"]')) {
    back.push(currentView());
    $('#back').hidden = false;
  }
}, true);
$('#back').onclick = () => {
  const view = back.pop();
  viewer.scrollPageIntoView({ pageNumber: view.page,
    destArray: [null, { name: 'XYZ' }, view.x, view.y, null], ignoreDestinationZoom: true });
  if (!back.length) {
    $('#back').hidden = true;
    container.focus({ preventScroll: true });
  }
};
// The options disclosure closes like a menu: outside, or after downloading.
document.addEventListener('pointerdown', event => {
  if (!event.target.closest('#options')) $('#options').open = false;
});
$('#options').addEventListener('click', event => {
  if (event.target.closest('a')) $('#options').open = false;
});
function search(again = false, previous = false) {
  bus.dispatch('find', { type: again ? 'again' : '', query: query.value,
    highlightAll: true, findPrevious: previous });
}
function openFind(again = false, previous = false, origin = document.activeElement) {
  if (findBar.hidden) findOrigin = origin;
  findBar.hidden = false;
  $('#find').setAttribute('aria-expanded', 'true');
  query.focus();
  query.select();
  if (query.value) search(again, previous);
}
function closeFind() {
  if (findBar.hidden) return;
  findBar.hidden = true;
  $('#find').setAttribute('aria-expanded', 'false');
  $('#matches').textContent = '';
  bus.dispatch('findbarclose', { source: null });
  const origin = findOrigin?.isConnected && findOrigin !== document.body ? findOrigin : container;
  origin.focus({ preventScroll: true });
}
$('#find').onclick = () => (findBar.hidden ? openFind(false, false, $('#find')) : closeFind());
$('#find-close').onclick = closeFind;
query.oninput = () => search();
query.onkeydown = event => {
  // Enter also confirms CJK input-method candidates; leave those alone.
  if (event.key === 'Enter' && !event.isComposing) {
    event.preventDefault();
    search(true, event.shiftKey);
  }
  // Search fields clear themselves on Escape; keep the query for next time.
  if (event.key === 'Escape') event.preventDefault();
};
$('#previous').onclick = () => search(true, true);
$('#next').onclick = () => search(true);
function showMatches({ current, total }, notFound) {
  $('#matches').textContent = !query.value || findBar.hidden ? ''
    : notFound ? 'No matches' : total ? `${current} / ${total}` : $('#matches').textContent;
}
bus.on('updatefindmatchescount', ({ matchesCount }) => showMatches(matchesCount, false));
bus.on('updatefindcontrolstate', ({ state, matchesCount }) => {
  if (state === FindState.PENDING) {
    $('#matches').textContent = query.value && !findBar.hidden ? '…' : '';
  } else {
    showMatches(matchesCount, state === FindState.NOT_FOUND);
  }
});

function showDetail(kind, title, text) {
  detailKind = kind;
  $('#change-title').textContent = title;
  $('#change-text').textContent = text;
  detail.hidden = false;
  for (const [selector, name] of [['#session', 'session'], ['#refresh', 'build'], ['#changes', 'diff']]) {
    $(selector).setAttribute('aria-expanded', String(kind === name));
  }
}
function closeDetail(returnFocus = detail.contains(document.activeElement)) {
  const origin = detailKind === 'session' ? $('#session') : detailKind === 'build' ? refreshButton : $('#changes');
  detail.hidden = true;
  detailKind = '';
  for (const selector of ['#session', '#refresh', '#changes']) $(selector).setAttribute('aria-expanded', 'false');
  if (returnFocus) origin.focus({ preventScroll: true });
}
$('#change-close').onclick = () => closeDetail(true);

function session(value) {
  if (value === 'connected' && connected === false) {
    status.textContent = '';
    noticeUntil = 0;
  }
  connected = value === 'connected';
  const button = $('#session');
  button.dataset.state = value;
  button.setAttribute('aria-label', `Preview session: ${value}`);
  button.title = sessionText();
  if (detailKind === 'session') showDetail('session', 'Preview session', sessionText());
}
function sessionText() {
  return connected
    ? syncAvailable
      ? 'Connected. This reader belongs to the source editor: it follows completed builds, and Locate in source returns to the editor.'
      : 'Connected to the PDF reader. Completed builds refresh here; source navigation requires an editor session.'
    : connected === false
      ? 'Connection lost. The last PDF stays readable while this tab retries. Refresh and source navigation resume when the connection returns. If the editor has closed, open a new preview from the editor.'
      : 'Connecting to the reader…';
}
$('#session').onclick = () => (detailKind === 'session' ? closeDetail() : showDetail('session', 'Preview session', sessionText()));

function diffStatus() {
  const name = (path) => path.split(/[\\/]/).pop();
  const retained = diff?.sha256 ? `\nStill showing the previous comparison with ${name(diff.built_base)}.` : '';
  if (!connected) return ['Offline', 'The last loaded PDF stays readable. Comparison resumes when the reader reconnects.'];
  if (!syncAvailable) return ['Read only', 'Open this preview from a TeX editor to compare revisions.'];
  if (!diff) return ['New reader needed', 'Close and reopen preview from the source editor to use latexdiff.'];
  if (!diff.base) return ['', 'Choose a source snapshot or Git revision with :WebPreviewChanges [baseline].\n'
    + 'Or place paper.base.tex beside paper.tex; paper.review-base can name another source or Git ref. Unsaved edits are never included.'];
  if (diff.status === 'building') return [diff.sha256 ? 'Updating…' : 'Building…',
    `Building a typeset comparison with ${name(diff.base)}. The current PDF remains readable.${retained}`];
  if (diff.error) return [diff.status === 'needs-build' ? 'Needs build'
      : diff.sha256 ? 'Failed · showing older' : 'Build failed',
    `Comparison with ${name(diff.base)} failed: ${diff.error}${retained}`];
  if (diff.source_revision !== latest) return ['Outdated', `This comparison predates the latest original.\nBase: ${name(diff.base)}`];
  return ['', `Compared with ${name(diff.built_base)}. Additions are blue and underlined; deletions are red and struck through.\n`
    + 'Locate in source also works here. Removed passages locate the nearest surviving source line. Figures use the current files; their pixels are not compared.'];
}
function diffControls() {
  const [label, text] = diffStatus();
  $('#original').setAttribute('aria-pressed', String(shownMode === 'original'));
  $('#changes').setAttribute('aria-pressed', String(shownMode === 'changes'));
  $('#changes').setAttribute('aria-busy', String(diff?.status === 'building'));
  $('#changes').title = text;
  $('#diff-log').hidden = !diff?.base;
  $('#download').href = shownMode === 'changes' ? './diff-download' : './download';
  $('#download').textContent = shownMode === 'changes' ? 'Download changes PDF' : 'Download PDF';
  if (detailKind === 'diff') showDetail('diff', 'Revision comparison', text);
}
$('#original').onclick = () => {
  wantedMode = 'original';
  if (detailKind === 'diff') closeDetail();
  refresh('original');
};
$('#changes').onclick = () => {
  wantedMode = 'changes';
  if (diff?.sha256 && shownMode !== 'changes') {
    refresh('changes');
    if (diff.error) showDetail('diff', 'Revision comparison', diffStatus()[1]);
    else if (detailKind === 'diff') closeDetail();
  } else if (detailKind === 'diff') {
    closeDetail();
  } else {
    showDetail('diff', 'Revision comparison', diffStatus()[1]);
  }
};

async function poll() {
  if (polling || paused) return;
  clearTimeout(pollTimer);
  polling = true;
  try {
    const response = await fetch(`./state?client=${client}`, {
      cache: 'no-store', signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw Error('Session ended');
    const state = await response.json();
    latest = state.sha256;
    documentError = state.error;
    syncAvailable = state.sync;
    if (!connected) session('connected');
    position = state.position;
    diff = state.diff;
    if (diff?.request > diffRequest) {
      diffRequest = diff.request;
      wantedMode = 'changes';
    }
    // An explicit source locate returns to Original; following never interrupts a revision read.
    if (observedPosition !== null && position && position.id !== observedPosition && !position.follow) wantedMode = 'original';
    observedPosition = position?.id || 0;
    if (!armed && Date.now() > noticeUntil) status.textContent = '';
    const mode = wantedMode === 'changes' && diff?.sha256 ? 'changes' : 'original';
    const revision = mode === 'changes' ? diff?.sha256 : latest;
    if (revision && !selection() && (mode !== shownMode || (!shown || revision !== shown
        && ($('#auto').checked || mode === 'original' && position?.revision === latest)))) await refresh(mode);
    locate();
    updateControls();
  } catch {
    if (connected !== false) {
      session('disconnected');
      arm(false);
      notice('Preview disconnected · keeping the last PDF');
    } else if (!armed && Date.now() > noticeUntil) {
      status.textContent = '';
    }
    updateControls();
  } finally {
    polling = false;
    if (!paused) pollTimer = setTimeout(poll, 1000);
  }
}
poll();
