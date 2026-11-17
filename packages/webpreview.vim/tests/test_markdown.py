"""Built-in Markdown: private transport, assets, editor ownership and draft safety."""
import base64
import http.client
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import zipfile
from unittest.mock import patch
from urllib.parse import urlsplit

package = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(package / 'src'))
os.environ['PYTHONPATH'] = str(package / 'src') + os.pathsep + os.environ.get('PYTHONPATH', '')
from webpreview import session
from webpreview.markdown import Markdown


class MarkdownTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='webpreview markdown ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source = self.root / 'draft.md'
        self.source.write_text('# Saved title\n\nSaved paragraph.\n')
        self.document = Markdown(self.source)
        self.document.update({'event': 'source', 'file': str(self.source), 'text': '# Unsaved title\n\nLive paragraph.\n'})

    def test_draft_versions_selection_and_navigation_do_not_write_files(self):
        self.assertEqual(self.document.state()['text'], '# Unsaved title\n\nLive paragraph.\n')
        self.assertNotIn('text', self.document.state('1'), 'unchanged drafts are not retransmitted')
        self.document.update({'event': 'cursor', 'line': 3, 'column': 2})
        self.assertEqual(self.document.state('1')['cursor'], {'line': 3, 'column': 2})
        with patch.object(sys.modules['webpreview.markdown'], 'emit') as emit:
            self.document.inverse({'revision': 1, 'line': 3, 'end_line': 3, 'text': 'Live paragraph.'})
            self.assertEqual(emit.call_args.args[0], {'event': 'source', 'file': str(self.source),
                'line': 3, 'column': 1, 'end_line': 3, 'text': 'Live paragraph.'})
            emit.reset_mock()
            self.document.update({'event': 'source', 'file': str(self.source), 'text': 'A new revision.'})
            with self.assertRaisesRegex(ValueError, 'Draft changed'):
                self.document.inverse({'revision': 1, 'line': 1})
            emit.assert_not_called()
        self.assertEqual(self.source.read_text(), '# Saved title\n\nSaved paragraph.\n')

    def test_media_and_document_links_stay_in_the_open_documents_folder(self):
        image = self.root / 'diagram.png'
        image.write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII='))
        child = self.root / 'child note.md'
        child.write_text('A linked note.')
        self.assertEqual(self.document.resource('media/diagram.png'), (image.read_bytes(), 'image/png'))
        for route in ['media/../outside.png', 'media/%2E%2E/outside.png', 'media/draft.md', 'elsewhere']:
            with self.assertRaises((OSError, ValueError)):
                self.document.resource(route)
        outside = self.root.parent / 'private-outside.md'
        with patch.object(sys.modules['webpreview.markdown'], 'emit') as emit:
            self.document.inverse({'revision': 1, 'path': 'child%20note.md'})
            self.assertEqual(emit.call_args.args[0], {'event': 'file', 'file': str(child)})
            emit.reset_mock()
            for path in [str(outside), '../private-outside.md', 'diagram.png']:
                with self.assertRaises((OSError, ValueError)):
                    self.document.inverse({'revision': 1, 'path': path})
            emit.assert_not_called()

    def test_http_assets_exact_host_and_token_rules(self):
        server = session.ThreadingHTTPServer(('127.0.0.1', 0), session.handler_for(self.document, 'test-only', 'preview.example'))
        worker = threading.Thread(target=server.serve_forever)
        worker.start()
        connection = http.client.HTTPConnection(*server.server_address, timeout=5)
        try:
            for path, host, expected in [('/test-only/', 'preview.example', 200),
                    ('/test-only/markdown/vendor.mjs', 'preview.example', 200),
                    ('/test-only/markdown/versions.json', 'preview.example', 200),
                    ('/test-only/viewer.mjs', 'preview.example', 200),
                    ('/test-only/state', 'preview.example.attacker.test', 403),
                    ('/test-only/state', 'another.example', 403), ('/wrong/state', 'preview.example', 404),
                    ('/test-only/markdown/../../draft.md', 'preview.example', 404)]:
                connection.request('GET', path, headers={'Host': host})
                response = connection.getresponse()
                data = response.read()
                self.assertEqual(response.status, expected, (path, host))
                if path == '/test-only/' and expected == 200:
                    self.assertIn(b'Markdown document', data)
                    self.assertIn("script-src 'self'", response.headers['Content-Security-Policy'])
                if path.endswith('vendor.mjs'):
                    self.assertEqual(response.headers['Content-Type'], 'text/javascript')
            connection.request('GET', '/test-only/state?revision=1')
            state = json.loads(connection.getresponse().read())
            self.assertNotIn('text', state)
            self.assertNotIn(str(self.root), json.dumps(state), 'state metadata exposes no local path')
        finally:
            connection.close()
            server.shutdown()
            server.server_close()
            worker.join()

    def test_cli_owns_session_through_editor_pipe(self):
        process = subprocess.Popen([sys.executable, '-m', 'webpreview', '--markdown', str(self.source), '--serve'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            ready = json.loads(process.stdout.readline())
            self.assertEqual(ready['event'], 'ready')
            url = urlsplit(ready['url'])
            process.stdin.write(json.dumps({'event': 'source', 'file': str(self.source), 'text': 'Unsaved draft.'}) + '\n')
            process.stdin.flush()
            connection = http.client.HTTPConnection(url.hostname, url.port, timeout=5)
            for _ in range(100):
                connection.request('GET', url.path + 'state')
                state = json.loads(connection.getresponse().read())
                if state['revision']:
                    break
                time.sleep(0.02)
            self.assertEqual(state['text'], 'Unsaved draft.')
            connection.close()
            process.stdin.close()
            self.assertEqual(process.wait(timeout=5), 0)
            self.assertEqual(self.source.read_text(), '# Saved title\n\nSaved paragraph.\n')
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()
            process.stdout.close()
            process.stderr.close()

    def test_custom_assets_are_session_scoped_and_invalid_bundles_fail_at_startup(self):
        archive = self.root / 'custom Markdown.zip'
        with zipfile.ZipFile(archive, 'w') as assets:
            assets.writestr('vendor.mjs', 'export const custom = true;')
            assets.writestr('vendor.css', '.custom { color: teal; }')
            assets.writestr('katex.min.css', '/* custom math styles */')
        process = subprocess.Popen([sys.executable, '-m', 'webpreview', '--markdown', str(self.source),
            '--markdown-assets', str(archive), '--serve'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            ready = json.loads(process.stdout.readline())
            url = urlsplit(ready['url'])
            connection = http.client.HTTPConnection(url.hostname, url.port, timeout=5)
            for name, expected in [('vendor.mjs', b'export const custom = true;'),
                    ('vendor.css', b'.custom { color: teal; }')]:
                connection.request('GET', url.path + 'markdown/' + name)
                response = connection.getresponse()
                self.assertEqual(response.status, 200)
                self.assertEqual(response.read(), expected)
            connection.close()
            process.stdin.close()
            self.assertEqual(process.wait(timeout=5), 0)
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()
            process.stdout.close()
            process.stderr.close()
        archive.write_text('Not a ZIP archive')
        invalid = subprocess.run([sys.executable, '-m', 'webpreview', '--markdown', str(self.source),
            '--markdown-assets', str(archive), '--serve'], input='', capture_output=True, text=True, timeout=5)
        self.assertNotEqual(invalid.returncode, 0)
        self.assertEqual(invalid.stdout, '', 'no session starts with an invalid bundle')
        self.assertIn('Cannot load Markdown assets', invalid.stderr)

    def test_real_vim_defers_source_jumps_and_selects_without_saving(self):
        with zipfile.ZipFile(package / 'src/webpreview/assets/markdown-libraries.zip') as original:
            with zipfile.ZipFile(self.root / 'custom assets.zip', 'w') as custom:
                for name in original.namelist():
                    custom.writestr(name, b'/* Vim custom assets */' if name == 'vendor.css' else original.read(name))
        script = self.root / 'live.vim'
        script.write_text(r'''
set nocompatible
execute 'set runtimepath^='.fnameescape($WEBPREVIEW_PACKAGE)
runtime plugin/webpreview.vim
function! TestShow(url) abort
  call writefile([a:url], $WEBPREVIEW_TEST.'/url')
  return 1
endfunction
let g:webpreview_browserfunc = 'TestShow'
let g:webpreview_markdown_assets = $WEBPREVIEW_TEST.'/custom assets.zip'
execute 'edit '.fnameescape($WEBPREVIEW_TEST.'/draft.md')
setlocal filetype=markdown foldmethod=manual
call setline(3, 'A live paragraph.')
2,3fold
normal! zM
call cursor(1, 1)
WebPreview
function! HoldInsert() abort
  call writefile(['insert'], $WEBPREVIEW_TEST.'/inserting')
  for attempt in range(500)
    sleep 20m
    if filereadable($WEBPREVIEW_TEST.'/resume') | break | endif
  endfor
  sleep 100m
  call writefile([json_encode({'line': line('.'), 'mode': mode(1)})], $WEBPREVIEW_TEST.'/deferred')
  return ''
endfunction
call feedkeys("i\<C-r>=HoldInsert()\<CR>\<Esc>", 'xt')
for attempt in range(1000)
  sleep 20m
  doautocmd SafeState
  if mode(1) ==# 'v'
    normal! y
    call writefile([json_encode({'text': getreg('"'), 'modified': &modified, 'line': line('.'), 'fold': foldclosed(3), 'errors': v:errors})], $WEBPREVIEW_TEST.'/selected.tmp')
    call rename($WEBPREVIEW_TEST.'/selected.tmp', $WEBPREVIEW_TEST.'/selected')
  endif
  if filereadable($WEBPREVIEW_TEST.'/stop') | break | endif
endfor
qall!
''')
        log = self.root / 'vim.log'
        def wait(name):
            path = self.root / name
            for _ in range(200):
                if path.exists() and path.stat().st_size:
                    return path.read_text()
                if process.poll() is not None:
                    break
                time.sleep(0.025)
            self.fail(name + ': ' + log.read_text()[-3000:])
        with log.open('w') as output:
            process = subprocess.Popen([os.environ.get('WEBPREVIEW_TEST_VIM', 'vim'), '-Nu', 'NONE',
                '-i', 'NONE', '-n', '-T', 'xterm', '-S', str(script)], stdout=output, stderr=output,
                env={**os.environ, 'WEBPREVIEW_PACKAGE': str(package), 'WEBPREVIEW_TEST': str(self.root)})
        try:
            wait('inserting')
            url = urlsplit(wait('url').strip())
            connection = http.client.HTTPConnection(url.hostname, url.port, timeout=5)
            connection.request('GET', url.path + 'markdown/vendor.css')
            self.assertEqual(connection.getresponse().read(), b'/* Vim custom assets */')
            for _ in range(100):
                connection.request('GET', url.path + 'state')
                state = json.loads(connection.getresponse().read())
                if 'A live paragraph.' in state.get('text', ''):
                    break
                time.sleep(0.025)
            self.assertIn('A live paragraph.', state['text'])
            connection.request('POST', url.path + 'inverse', json.dumps({'revision': state['revision'],
                'line': 3, 'end_line': 3, 'text': 'live paragraph'}), {'Content-Type': 'application/json'})
            response = connection.getresponse()
            self.assertEqual(response.status, 200, response.read())
            response.read()
            (self.root / 'resume').touch()
            deferred = json.loads(wait('deferred'))
            self.assertEqual(deferred['line'], 1)
            self.assertTrue(deferred['mode'].startswith('i'))
            selected = json.loads(wait('selected'))
            self.assertEqual(selected, {'text': 'live paragraph', 'modified': 1, 'line': 3, 'fold': -1, 'errors': []})
            self.assertEqual(self.source.read_text(), '# Saved title\n\nSaved paragraph.\n')
            (self.root / 'stop').touch()
            self.assertEqual(process.wait(timeout=8), 0)
            connection.close()
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()


if __name__ == '__main__':
    unittest.main()
