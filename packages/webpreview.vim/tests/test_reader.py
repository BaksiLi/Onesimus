"""Protocol, publication and lifecycle tests for the local/SSH PDF reader."""
import hashlib
import http.client
import io
import json
import os
from pathlib import Path
import shlex
import shutil
import socket
import struct
import subprocess
import tempfile
import threading
import time
import unittest
import sys
from unittest.mock import patch
from urllib.parse import urlsplit

package = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(package / 'src'))
os.environ['PYTHONPATH'] = str(package / 'src') + os.pathsep + os.environ.get('PYTHONPATH', '')
from webpreview import reader as pdf
from webpreview import session
from webpreview.sourcemap import SourceMap, surviving
CLI = [sys.executable, '-m', 'webpreview']


def sample(label=b'one'):
    return b'%PDF-1.4\n' + label + b'\n%%EOF\n'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def frame(data):
    return json.dumps({'length': len(data), 'sha256': digest(data)}).encode() + b'\n' + data


class ReaderTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='webpreview pdf $; ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.document = pdf.Document()

    def test_transport_rejects_partial_corrupt_and_oversized_revisions(self):
        data = sample()
        self.assertEqual(pdf.read_revision(io.BytesIO(frame(data))), (data, digest(data)))
        for broken in [frame(data)[:-3], frame(data).replace(b'%PDF', b'%BAD'), b'{"length": 999999999}\n', b'garbled\n']:
            with self.subTest(broken=broken[:60]):
                with self.assertRaises((ValueError, EOFError)):
                    pdf.read_revision(io.BytesIO(broken))

    def test_updates_are_published_and_errors_keep_the_last_pdf(self):
        for data in [sample(), sample(b'two')]:
            self.document.update(data, digest(data))
            self.assertEqual(self.document.data, data)
            self.assertEqual(self.document.digest, digest(data))
        self.document.fail('connection lost')
        self.assertEqual(self.document.data, sample(b'two'))

    def test_ssh_command_preserves_paths_without_shell_interpolation(self):
        path = "/paper name/$(touch nope); quote' main.pdf"
        args = pdf.reader_command(path, 'paper-host')
        self.assertEqual(args[-2], 'paper-host')
        remote = shlex.split(args[-1])
        self.assertEqual(remote, ['python3', '-u', '-c', pdf.REMOTE_READER, path])
        for host in ['-oProxyCommand=bad', 'host --option']:
            with self.assertRaises(ValueError):
                pdf.reader_command(path, host)

    def test_real_reader_waits_for_complete_pdf_and_exits_on_disconnect(self):
        source = self.root / "a ' $; paper.pdf"
        source.write_bytes(b'%PDF-1.4\nincomplete')
        process = subprocess.Popen(pdf.reader_command(str(source)), stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        try:
            with self.assertRaises(OSError):
                pdf.read_revision(process.stdout)
            source.write_bytes(sample())
            self.assertEqual(pdf.read_revision(process.stdout)[0], sample())
            source.write_bytes(sample(b'two'))
            self.assertEqual(pdf.read_revision(process.stdout)[0], sample(b'two'))
            process.stdin.close()
            self.assertEqual(process.wait(timeout=4), 0)
        finally:
            process.kill() if process.poll() is None else None
            process.wait()
            process.stdout.close()
            process.stdin.close()

    def test_idle_worker_shutdown_owns_and_reaps_reader(self):
        source = self.root / 'source.pdf'
        source.write_bytes(sample())
        stopped = threading.Event()
        worker = threading.Thread(target=pdf.follow, args=(self.document, pdf.reader_command(str(source)), stopped))
        worker.start()
        try:
            self.assertTrue(self.document.ready.wait(5))
            with self.document.lock:
                process = self.document.process
            stopped.set()
            self.document.stop_reader()
            worker.join(timeout=5)
            self.assertFalse(worker.is_alive())
            self.assertIsNotNone(process.poll())
        finally:
            stopped.set()
            self.document.stop_reader()
            worker.join(timeout=5)

    def test_http_only_serves_one_pdf_with_correct_token_and_host(self):
        self.document.update(sample(), digest(sample()))
        server = session.ThreadingHTTPServer(('127.0.0.1', 0), session.handler_for(self.document, 'secret', 'preview.example'))
        worker = threading.Thread(target=server.serve_forever)
        worker.start()
        try:
            for path, host, status in [
                ('/secret/', None, 200), ('/secret/pdf', None, 200),
                ('/secret/pdf', '127.0.0.1:8765', 200),
                ('/secret/pdf', 'preview.example:8765', 200),
                ('/secret/pdf', 'preview.example.evil.test', 403),
                ('/secret/viewer.mjs', None, 200),
                ('/secret/pdfjs/build/pdf.worker.min.mjs', None, 200),
                ('/secret/pdfjs/../../bin/webpreview', None, 404),
                ('/secret/state', None, 200), ('/wrong/pdf', None, 404),
                ('/secret/../../etc/passwd', None, 404),
                ('/secret/pdf', 'untrusted.test', 403),
            ]:
                connection = http.client.HTTPConnection('127.0.0.1', server.server_port)
                connection.request('GET', path, headers={'Host': host} if host else {})
                response = connection.getresponse()
                self.assertEqual(response.status, status, path)
                data = response.read()
                if path == '/secret/pdf' and status == 200:
                    self.assertEqual(data, sample())
                    self.assertEqual(response.getheader('X-PDF-Revision'), digest(data))
                connection.close()
        finally:
            server.shutdown()
            server.server_close()
            worker.join()

    def test_peer_reset_before_request_does_not_report_a_server_error(self):
        started, handled = threading.Event(), threading.Event()
        handler = session.handler_for(self.document, 'secret')

        class ObservedHandler(handler):
            def handle(self):
                started.set()
                try:
                    super().handle()
                finally:
                    handled.set()

        server = session.ThreadingHTTPServer(('127.0.0.1', 0), ObservedHandler)
        worker = threading.Thread(target=server.serve_forever)
        worker.start()
        try:
            with patch.object(server, 'handle_error') as error:
                with socket.create_connection(server.server_address, timeout=5) as peer:
                    self.assertTrue(started.wait(5))
                    peer.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
                self.assertTrue(handled.wait(5))
                error.assert_not_called()
                connection = http.client.HTTPConnection(*server.server_address, timeout=5)
                connection.request('GET', '/secret/state')
                response = connection.getresponse()
                self.assertEqual(response.status, 200)
                response.read()
                connection.close()
            # Unexpected application errors still surface.
            with patch.object(session.BaseHTTPRequestHandler, 'handle', side_effect=RuntimeError('bug')):
                with self.assertRaisesRegex(RuntimeError, 'bug'):
                    object.__new__(handler).handle()
        finally:
            server.shutdown()
            server.server_close()
            worker.join()

    def test_browser_presence_tracks_pages_not_the_reader_or_health_checks(self):
        server = session.ThreadingHTTPServer(('127.0.0.1', 0), session.handler_for(self.document, 'secret'))
        worker = threading.Thread(target=server.serve_forever)
        worker.start()
        connection = http.client.HTTPConnection(*server.server_address, timeout=5)
        try:
            def request(path, body=None):
                connection.request('POST' if body else 'GET', path, body)
                response = connection.getresponse()
                response.read()
                return response.status

            with patch.object(session.time, 'monotonic', return_value=100), patch.object(session, 'emit') as emit:
                self.assertEqual(request('/secret/state'), 200)
                self.document.open_if_unused()
                self.assertEqual(emit.call_args.args[0], {'event': 'open'})
                emit.reset_mock()
                for client in ('desktop', 'mobile'):
                    self.assertEqual(request('/secret/state?client=' + client), 200)
                self.document.open_if_unused()
                emit.assert_not_called()
                self.assertEqual(request('/wrong/leave', '{"client":"mobile"}'), 404)
                self.assertEqual(request('/secret/leave', '{"client":"desktop"}'), 200)
                self.document.open_if_unused()
                emit.assert_not_called()  # The other page is still reading.
                self.assertEqual(request('/secret/leave', '{"client":"mobile"}'), 200)
                self.document.open_if_unused()
                emit.assert_called_once_with({'event': 'open'})
                request('/secret/state?client=lost-without-leaving')
                emit.reset_mock()
                with patch.object(session.time, 'monotonic', return_value=100 + session.CLIENT_TTL):
                    self.document.open_if_unused()
                emit.assert_called_once_with({'event': 'open'})
                self.assertEqual(self.document.clients, {})
        finally:
            connection.close()
            server.shutdown()
            server.server_close()
            worker.join()

    def test_vim_requests_browser_presence_without_needing_synctex(self):
        with patch.object(pdf.sys, 'stdin', io.StringIO('{"event":"open"}\n')), \
                patch.object(session, 'emit') as emit:
            pdf.editor_channel(self.document, threading.Event())
        emit.assert_called_once_with({'event': 'open'})

    def test_headless_cli_serves_without_creating_cache_and_shuts_down(self):
        source = self.root / 'source.pdf'
        source.write_bytes(sample())
        cache = self.root / 'unused-cache'
        process = subprocess.Popen(
            [*CLI, '--pdf', str(source), '--serve'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            env={**os.environ, 'XDG_CACHE_HOME': str(cache)})
        try:
            url = urlsplit(process.stdout.readline().removeprefix('Browser: ').strip())
            self.assertEqual(url.hostname, '127.0.0.1')
            connection = http.client.HTTPConnection(url.hostname, url.port, timeout=5)
            for attempt in range(50):
                connection.request('GET', url.path + 'pdf')
                response = connection.getresponse()
                data = response.read()
                if response.status == 200:
                    break
                time.sleep(0.1)
            self.assertEqual(response.status, 200)
            self.assertEqual(data, sample())
            connection.close()
            self.assertFalse(cache.exists())
            process.terminate()
            self.assertEqual(process.wait(timeout=5), 0)
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)

    def test_following_misses_stay_quiet_while_explicit_locates_report(self):
        class Sync:
            def __init__(self):
                self.requests = []

            def forward(self, request):
                self.requests.append(request)
                raise ValueError('No SyncTeX position; build with -synctex=1 first')
        self.document.sync = Sync()
        lines = [json.dumps({'file': 'main.tex', 'line': 3, 'column': 1, 'follow': True}),
                 json.dumps({'file': 'main.tex', 'line': 4, 'column': 1}), 'not json']
        stopped = threading.Event()
        with patch.object(pdf.sys, 'stdin', io.StringIO('\n'.join(lines) + '\n')), \
                patch.object(pdf, 'emit') as emit:
            pdf.editor_channel(self.document, stopped)
        self.assertTrue(stopped.is_set())
        self.assertEqual([request['line'] for request in self.document.sync.requests], [3, 4])
        self.assertEqual([call.args[0]['event'] for call in emit.call_args_list], ['error', 'error'])

    def test_vim_channel_eof_ends_the_reader(self):
        source = self.root / 'source.pdf'
        source.write_bytes(sample())
        process = subprocess.Popen(
            [*CLI, '--pdf', str(source),
             '--serve', '--editor', str(self.root / 'main.tex')],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            event = json.loads(process.stdout.readline())
            self.assertEqual(event['event'], 'ready')
            self.assertTrue(event['url'].startswith('http://127.0.0.1:'))
            process.stdin.close()
            self.assertEqual(process.wait(timeout=5), 0)
        finally:
            if process.poll() is None:
                process.kill()
            process.stdout.close()
            process.stderr.close()
            process.wait()

    def test_diff_request_arrives_through_the_owning_vim_pipe(self):
        self.document.revision = pdf.Revision(
            self.document, self.root / 'main.tex', self.root / 'main.pdf', threading.Event())
        request = {'event': 'diff', 'base': '/snapshot with spaces/main.tex', 'engine': '-lualatex'}
        with patch.object(pdf.sys, 'stdin', io.StringIO(json.dumps(request) + '\n')), \
                patch.object(pdf, 'emit') as emit:
            pdf.editor_channel(self.document, threading.Event())
        self.assertEqual(self.document.revision.options['base'], request['base'])
        self.assertEqual(self.document.revision.options['engine'], '-lualatex')
        emit.assert_not_called()

    @unittest.skipIf(os.name == 'nt', 'POSIX process group fixture')
    def test_vim_pipe_close_cancels_the_comparison_and_its_child_process(self):
        tools = self.root / 'tools'
        tools.mkdir()
        tool = tools / 'latexdiff'
        tool.write_text('''#!/usr/bin/env python3
import json, os, subprocess, sys, time
from pathlib import Path
child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
Path(os.environ['WEBPREVIEW_TEST_CHILDREN']).write_text(json.dumps([os.getpid(), child.pid]))
time.sleep(60)
''')
        tool.chmod(0o755)
        main = self.root / 'main.tex'
        main.write_text('saved source')
        source = self.root / 'main.pdf'
        source.write_bytes(sample())
        children = self.root / 'children'
        process = subprocess.Popen(
            [*CLI, '--pdf', str(source), '--serve', '--editor', str(main)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            env={**os.environ, 'PATH': str(tools) + os.pathsep + os.environ['PATH'],
                 'WEBPREVIEW_TEST_CHILDREN': str(children)})
        try:
            self.assertEqual(json.loads(process.stdout.readline())['event'], 'ready')
            process.stdin.write(json.dumps({'event': 'diff', 'base': str(main)}) + '\n')
            process.stdin.flush()
            for _ in range(100):
                if children.exists():
                    break
                time.sleep(0.05)
            self.assertTrue(children.exists(), 'the comparison never started')
            pids = json.loads(children.read_text())
            process.stdin.close()
            self.assertEqual(process.wait(timeout=6), 0)
            for pid in pids:
                for _ in range(100):
                    state = subprocess.run(['ps', '-p', str(pid), '-o', 'stat='], capture_output=True, text=True).stdout.strip()
                    if not state or state.startswith('Z'):
                        break
                    time.sleep(0.02)
                else:
                    self.fail('comparison child survived Vim: ' + str(pid))
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()
            process.stdout.close()
            process.stderr.close()

    def test_stop_signal_during_event_wait_cannot_deadlock(self):
        source = self.root / 'source.pdf'
        source.write_bytes(sample())
        # Deliver SIGTERM while the main loop owns Event's non-reentrant lock.
        script = '''
import runpy, signal, sys, threading
reader = runpy.run_module('webpreview.reader')
source = sys.argv[1]
class InterruptedWait(threading.Event):
    def wait(self, timeout=None):
        if timeout == 0.25 and threading.current_thread() is threading.main_thread():
            with self._cond:
                signal.raise_signal(signal.SIGTERM)
            return False
        return super().wait(timeout)
threading.Event = InterruptedWait
sys.argv = ['webpreview', '--pdf', source, '--serve']
raise SystemExit(reader['main']())
'''
        result = subprocess.run(
            [pdf.sys.executable, '-c', script, str(source)],
            capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Browser: http://127.0.0.1:', result.stdout)


@unittest.skipUnless(shutil.which('pdflatex') and shutil.which('synctex'), 'TeX tools unavailable')
class PositionFixture(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='webpreview positions $; ')
        cls.root = Path(cls.temporary.name).resolve()
        cls.source = cls.root / 'main.tex'
        cls.source.write_text(
            '\\documentclass{article}\n\\begin{document}\nFirst paragraph.\n\n'
            'Second paragraph with $x^2+y^2=z^2$.\n\\newpage\nPage two.\n\\end{document}\n')
        subprocess.run(['pdflatex', '-synctex=1', '-recorder', '-interaction=batchmode', '-halt-on-error', 'main.tex'],
                       cwd=cls.root, check=True, stdout=subprocess.DEVNULL)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def setUp(self):
        self.path = self.root / 'main.pdf'
        self.document = pdf.Document()
        data = self.path.read_bytes()
        self.document.update(data, digest(data))
        self.sync = pdf.SyncTeX(self.document, self.path, self.source)
        self.document.sync = self.sync



class PositionTests(PositionFixture):
    @unittest.skipUnless(shutil.which('latexmk') and shutil.which('latexdiff'), 'Comparison tools unavailable')
    def test_standalone_vim_package_owns_the_real_reader_without_onesimus(self):
        script = self.root / 'standalone.vim'
        baseline = self.root / 'main.base.tex'
        baseline.write_text(self.source.read_text().replace('First paragraph.', 'Historical paragraph.'))
        self.addCleanup(baseline.unlink)
        compare = self.root / 'standalone-compare'
        compare.unlink(missing_ok=True)
        opened, stop, located = (self.root / name for name in ('standalone-url', 'standalone-stop', 'standalone-located'))
        for path in (opened, stop, located):
            path.unlink(missing_ok=True)
        script.write_text(r'''
set nocompatible
execute 'set runtimepath^='.fnameescape($WEBPREVIEW_PACKAGE)
runtime plugin/webpreview.vim
function! TestBrowser(url) abort
  call writefile([a:url], $WEBPREVIEW_TEST.'/standalone-url')
  return 1
endfunction
let g:webpreview_browserfunc = 'TestBrowser'
execute 'edit '.fnameescape($WEBPREVIEW_TEST.'/main.tex')
setlocal filetype=tex foldmethod=manual
call setline(3, 'An independent unsaved draft.')
3,5fold
normal! zM
call cursor(1, 1)
WebPreview
for attempt in range(1000)
  sleep 20m
  doautocmd SafeState
  if filereadable($WEBPREVIEW_TEST.'/standalone-compare')
    call delete($WEBPREVIEW_TEST.'/standalone-compare')
    WebPreviewChanges
  endif
  if line('.') == 5 && !filereadable($WEBPREVIEW_TEST.'/standalone-located')
    call writefile([json_encode({'modified': &modified, 'draft': getline(3),
          \ 'fold': foldclosed(5), 'onesimus': exists('*OnesimusWritingPreview')})],
          \ $WEBPREVIEW_TEST.'/standalone-located.tmp')
    call rename($WEBPREVIEW_TEST.'/standalone-located.tmp', $WEBPREVIEW_TEST.'/standalone-located')
  endif
  if filereadable($WEBPREVIEW_TEST.'/standalone-stop') | break | endif
endfor
qall!
'''.replace(r'\\ ', r'\ '))
        with (self.root / 'standalone.log').open('w') as log:
            process = subprocess.Popen([os.environ.get('WEBPREVIEW_TEST_VIM', 'vim'), '-Nu', 'NONE',
                '-i', 'NONE', '-n', '-T', 'xterm', '-S', str(script)], stdout=log, stderr=log,
                env={**os.environ, 'WEBPREVIEW_PACKAGE': str(package), 'WEBPREVIEW_TEST': str(self.root)})
        try:
            for _ in range(100):
                if opened.exists() and opened.stat().st_size:
                    break
                time.sleep(0.05)
            self.assertTrue(opened.exists(), (self.root / 'standalone.log').read_text())
            url = urlsplit(opened.read_text().strip())
            self.assertIsNotNone(url.hostname, repr(opened.read_text()) + '\n' + (self.root / 'standalone.log').read_text())
            connection = http.client.HTTPConnection(url.hostname, url.port, timeout=5)
            for _ in range(100):
                connection.request('GET', url.path + 'state')
                state = json.loads(connection.getresponse().read())
                if state['sha256'] == self.document.digest and state['diff']['status'] in ('ready', 'error'):
                    break
                time.sleep(0.05)
            self.assertEqual(state['sha256'], self.document.digest)
            self.assertEqual(state['diff']['status'], 'ready', state['diff'])
            self.assertEqual(state['diff']['base'], str(baseline))
            self.assertEqual(state['diff']['request'], 0, 'discovery must not select Changes')
            compare.touch()
            for _ in range(100):
                connection.request('GET', url.path + 'state')
                state = json.loads(connection.getresponse().read())
                if state['diff']['request'] == 1 and state['diff']['status'] in ('ready', 'error'):
                    break
                time.sleep(0.05)
            self.assertEqual(state['diff']['request'], 1, ':WebPreviewChanges requests the detected baseline')
            self.assertEqual(state['diff']['status'], 'ready', state['diff'])
            self.sync.forward({'file': str(self.source), 'line': 5, 'column': 1})
            connection.request('POST', url.path + 'inverse', json.dumps(self.document.position),
                               {'Content-Type': 'application/json'})
            response = connection.getresponse()
            self.assertEqual(response.status, 200, response.read())
            response.read()
            connection.close()
            for _ in range(100):
                if located.exists():
                    break
                time.sleep(0.05)
            self.assertTrue(located.exists(), (self.root / 'standalone.log').read_text())
            self.assertEqual(json.loads(located.read_text()), {'modified': 1,
                'draft': 'An independent unsaved draft.', 'fold': -1, 'onesimus': 0})
            stop.touch()
            self.assertEqual(process.wait(timeout=8), 0)
            for _ in range(100):
                connection = http.client.HTTPConnection(url.hostname, url.port, timeout=1)
                try:
                    connection.request('GET', url.path + 'state')
                    connection.getresponse().read()
                except OSError:
                    break
                finally:
                    connection.close()
                time.sleep(0.05)
            else:
                self.fail('The reader survived its standalone Vim session')
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()

    def test_real_forward_inverse_positions_and_editor_environment(self):
        self.sync.forward({'file': str(self.source), 'line': 5, 'column': 1})
        self.assertEqual(self.document.position['page'], 1)
        with patch.object(pdf, 'emit') as emit, patch.dict(os.environ, {'SYNCTEX_EDITOR': 'exit 99'}):
            self.sync.inverse(self.document.position)
            self.assertEqual(emit.call_args.args[0], {
                'event': 'source', 'file': str(self.source), 'line': 5, 'column': 1})
        self.sync.forward({'file': str(self.source), 'line': 7, 'column': 1})
        self.assertEqual(self.document.position['page'], 2)
        self.assertFalse(self.document.position['follow'])
        # A followed cursor marks its position so the page moves the marker, not the view.
        self.sync.forward({'file': str(self.source), 'line': 5, 'column': 1, 'follow': True})
        self.assertEqual((self.document.position['page'], self.document.position['follow']), (1, True))

    def test_selected_text_includes_both_synctex_endpoints(self):
        self.sync.forward({'file': str(self.source), 'line': 3, 'column': 1})
        start = dict(self.document.position)
        self.sync.forward({'file': str(self.source), 'line': 5, 'column': 1})
        with patch.object(pdf, 'emit') as emit:
            self.sync.inverse({**start, 'text': 'First paragraph. Second paragraph',
                               'end': self.document.position})
            event = emit.call_args.args[0]
            self.assertEqual((event['line'], event['end_line']), (3, 5))
            self.assertEqual(event['text'], 'First paragraph. Second paragraph')
        with patch.object(self.sync, 'source_position', side_effect=[
                {'file': 'one.tex', 'line': 3}, {'file': 'two.tex', 'line': 5}]), patch.object(pdf, 'emit') as emit:
            with self.assertRaisesRegex(ValueError, 'crosses source files'):
                self.sync.inverse({**start, 'text': 'selection', 'end': start})
            emit.assert_not_called()

    def test_stale_and_invalid_positions_do_not_move_the_editor(self):
        with patch.object(pdf, 'emit') as emit:
            for request in [
                {'page': 1, 'x': 1, 'y': 1, 'revision': 'old'},
                {'page': 1, 'x': float('nan'), 'y': 1, 'revision': self.document.digest},
            ]:
                with self.assertRaises(ValueError):
                    self.sync.inverse(request)
            emit.assert_not_called()




@unittest.skipUnless(all(shutil.which(tool) for tool in ('latexdiff', 'latexmk', 'pdflatex'))
                     and (shutil.which('pdftotext') or shutil.which('gs')),
                     'latexdiff/TeX/PDF text extractor unavailable')
class RevisionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="webpreview revision $; ' ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source = self.root / 'paper.tex'
        self.source.write_text('\\documentclass{article}\n\\begin{document}\n'
                               'A new sentence.\n\nThe formula is $x^3$.\n\\end{document}\n')
        self.compile()
        self.document = pdf.Document()
        self.publish()
        self.stopped = threading.Event()
        self.revision = pdf.Revision(self.document, self.source, self.path, self.stopped)
        self.addCleanup(self.revision.close)

    def compile(self):
        subprocess.run(['pdflatex', '-interaction=batchmode', '-halt-on-error', self.source.name],
                       cwd=self.source.parent, check=True, stdout=subprocess.DEVNULL)
        self.path = self.source.with_suffix('.pdf')

    def publish(self):
        data = self.path.read_bytes()
        self.document.update(data, digest(data))

    def finish(self, base=None, **options):
        if base is not None:
            self.revision.configure({'base': base, **options})
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            self.revision.refresh()
            if self.document.diff_state['status'] in ('ready', 'error', 'needs-build') \
                    and not (self.revision.worker and self.revision.worker.is_alive()):
                return self.document.diff_state
            time.sleep(0.05)
        self.fail('Comparison timed out: ' + self.document.diff_log.decode(errors='replace')[-4000:])

    def text(self):
        artifact = self.root / 'comparison.pdf'
        artifact.write_bytes(self.document.diff_data)
        command = ['pdftotext', str(artifact), '-'] if shutil.which('pdftotext') else [
            'gs', '-q', '-dBATCH', '-dNOPAUSE', '-sDEVICE=txtwrite', '-sOutputFile=-', str(artifact)]
        return subprocess.run(command, capture_output=True, text=True, check=True).stdout

    def test_ordinary_preview_does_not_build_without_a_baseline(self):
        self.revision.refresh()
        self.assertIsNone(self.revision.worker)
        self.assertEqual(self.document.diff_state['status'], 'idle')
        self.assertEqual(self.document.diff_state['base'], '')
        self.assertEqual(self.document.diff_state['request'], 0)

    def test_snapshot_typesets_additions_deletions_and_math_without_touching_the_paper(self):
        base = self.root / 'old paper.tex'
        base.write_text(self.source.read_text().replace('A new sentence.', 'An old sentence.\nDeleted passage.')
                        .replace('x^3', 'x^2'))
        before = {path.name: path.read_bytes() for path in self.root.iterdir() if path.is_file()}
        state = self.finish(str(base))
        self.assertEqual(state['status'], 'ready', self.document.diff_log.decode(errors='replace'))
        self.assertEqual(state['source_revision'], self.document.digest)
        self.assertNotEqual(state['sha256'], self.document.digest)
        text = self.text()
        self.assertIn('Deleted passage', text)
        self.assertIn('new sentence', text)
        self.assertNotIn('::::', text, 'underline decoration must not enter the PDF text layer')
        self.assertEqual({name: (self.root / name).read_bytes() for name in before}, before)

    def comparison_point(self, line):
        sync = self.document.diff_sync
        result = sync.query('view', f'{line}:1:{sync.generated}', self.document.diff_state['sha256'])
        return {'page': int(result['Page']), 'x': float(result['x']), 'y': float(result['y']),
                'revision': self.document.diff_state['sha256'], 'version': 'changes'}

    def test_comparison_navigation_maps_added_text_to_the_manuscript_and_releases_files(self):
        base = self.root / 'base.tex'
        base.write_text(self.source.read_text().replace('A new sentence.', 'An old sentence.\nDeleted passage.'))
        self.assertEqual(self.finish(str(base))['status'], 'ready')
        sync = self.document.diff_sync
        lines = sync.generated.read_text().splitlines()
        line = next(i for i, text in enumerate(lines, 1) if 'new sentence' in text)
        point = self.comparison_point(line)
        with patch.object(pdf, 'emit') as emit:
            sync.inverse({**point, 'text': 'new sentence', 'end': point})
        event = emit.call_args.args[0]
        self.assertEqual((event['file'], event['line'], event['text']), (str(self.source), 3, 'new sentence'))
        temporary = Path(sync.temporary.name)
        self.assertTrue(temporary.exists())
        self.revision.close()
        self.assertTrue(temporary.exists(), 'an in-flight inverse request keeps its comparison alive')
        del sync
        self.assertFalse(temporary.exists())

    def test_multifile_comparison_maps_back_to_the_included_chapter(self):
        chapter = self.root / 'chapter.tex'
        chapter.write_text('The revised chapter has a unique sentence.\n')
        self.source.write_text(self.source.read_text().replace('A new sentence.', '\\input{chapter}'))
        self.compile()
        self.publish()
        base = self.root / 'base.tex'
        base.write_text(self.source.read_text().replace('\\input{chapter}', 'The historical chapter.'))
        self.assertEqual(self.finish(str(base), files=[str(self.source), str(chapter)])['status'], 'ready')
        sync = self.document.diff_sync
        line = next(i for i, text in enumerate(sync.generated.read_text().splitlines(), 1) if 'revised chapter' in text)
        with patch.object(pdf, 'emit') as emit:
            sync.inverse(self.comparison_point(line))
        event = emit.call_args.args[0]
        self.assertEqual((event['file'], event['line']), (str(chapter), 1))

    def test_http_comparison_inverse_rejects_an_outdated_original(self):
        self.document.sync = pdf.SyncTeX(self.document, self.path, self.source)
        base = self.root / 'base.tex'
        base.write_text(self.source.read_text().replace('new', 'old'))
        self.assertEqual(self.finish(str(base))['status'], 'ready')
        sync = self.document.diff_sync
        line = next(i for i, text in enumerate(sync.generated.read_text().splitlines(), 1) if r'\DIFadd{new' in text)
        point = self.comparison_point(line)
        server = session.ThreadingHTTPServer(('127.0.0.1', 0), session.handler_for(self.document, 'test'))
        worker = threading.Thread(target=server.serve_forever)
        worker.start()
        connection = http.client.HTTPConnection(*server.server_address, timeout=5)
        try:
            with patch.object(pdf, 'emit') as emit:
                connection.request('POST', '/test/inverse', json.dumps(point), {'Content-Type': 'application/json'})
                response = connection.getresponse()
                self.assertEqual(response.status, 200, response.read())
                response.read()
                self.assertEqual(emit.call_args.args[0]['file'], str(self.source))
                emit.reset_mock()
                locate = sync.source_position
                def changed_during_locate(*args):
                    result = locate(*args)
                    self.document.update(sample(b'another original'), 'other')
                    return result
                with patch.object(sync, 'source_position', side_effect=changed_during_locate):
                    with self.assertRaisesRegex(ValueError, 'PDF changed'):
                        sync.inverse(point)
                emit.assert_not_called()
                self.document.update(sample(b'another original'), 'other')
                connection.request('POST', '/test/inverse', json.dumps(point), {'Content-Type': 'application/json'})
                response = connection.getresponse()
                self.assertEqual(response.status, 409)
                self.assertIn(b'outdated', response.read())
                emit.assert_not_called()
        finally:
            connection.close()
            server.shutdown()
            server.server_close()
            worker.join()


    def test_git_baseline_includes_historical_chapters(self):
        chapter = self.root / 'chapter.tex'
        self.source.write_text(self.source.read_text().replace('A new sentence.', '\\input{chapter}'))
        chapter.write_text('The historical chapter.\n')
        for args in [['init', '-q'], ['add', 'paper.tex', 'chapter.tex'],
                     ['-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'base']]:
            subprocess.run(['git', *args], cwd=self.root, check=True, capture_output=True)
        chapter.write_text('The revised chapter.\n')
        self.compile()
        self.publish()
        state = self.finish('', files=[str(self.source), str(chapter)])
        self.assertEqual(state['status'], 'ready', self.document.diff_log.decode(errors='replace'))
        self.assertEqual(state['base'], 'HEAD')
        self.assertIn('historical', self.text())
        self.assertIn('revised', self.text())

    def test_saved_input_requires_a_build_and_retries_even_if_pdf_bytes_are_identical(self):
        base = self.root / 'base.tex'
        base.write_text(self.source.read_text().replace('new', 'old'))
        self.source.write_text(self.source.read_text() + '% Source-only change.\n')
        stamp = self.path.stat().st_mtime_ns + 1_000_000_000
        os.utime(self.source, ns=(stamp, stamp))
        state = self.finish(str(base))
        self.assertEqual(state['status'], 'needs-build')
        self.assertIn('Build the paper', state['error'])
        self.assertEqual(self.document.diff_data, b'')
        os.utime(self.path, ns=(stamp + 1, stamp + 1))
        state = self.finish()
        self.assertEqual(state['status'], 'ready', self.document.diff_log.decode(errors='replace'))

    def test_failed_comparison_preserves_the_original_and_last_complete_revision(self):
        base = self.root / 'base.tex'
        base.write_text(self.source.read_text().replace('new', 'old'))
        ready = dict(self.finish(str(base)))
        self.assertEqual(ready['status'], 'ready')
        clean, previous = self.document.data, self.document.diff_data
        state = self.finish(str(base), engine='-not-an-engine')
        self.assertEqual(state['status'], 'error')
        self.assertIn('latexmk failed', state['error'])
        self.assertIn(b'not-an-engine', self.document.diff_log)
        self.assertEqual(self.document.diff_data, previous)
        self.assertEqual((state['built_base'], state['sha256']), (ready['built_base'], ready['sha256']))
        self.assertEqual(self.document.data, clean)

    def test_restructured_headings_stay_whole(self):
        # latexdiff once aligned a new heading with a deleted paragraph, so the
        # heading argument crossed a blank line and \@sect / REVTeX \@sect@ltx failed.
        classes = ['article'] + (['[aps,reprint]{revtex4-2}'] if shutil.which('kpsewhich') and subprocess.run(
            ['kpsewhich', 'revtex4-2.cls'], capture_output=True).returncode == 0 else [])
        for documentclass in classes:
            with self.subTest(documentclass):
                head = '\\documentclass' + (documentclass if '{' in documentclass else '{' + documentclass + '}')
                self.source.write_text(head + '\n\\begin{document}\n\\section{Methods}\n'
                    '\\subsection{Comparison models, refinement, and timing}\nThe baselines share the data.\n\\end{document}\n')
                self.compile()
                self.publish()
                base = self.root / 'base.tex'
                base.write_text(head + '\n\\begin{document}\n\\section{Methods}\n'
                    'Grid checks keep every decision, with errors $0.0049$, $0.0050$, and $0.0051$ on 800, 8000, and 16000 frequencies.\n\n'
                    '\\subsection{Comparisons with other methods}\nThe baselines share the data.\n\\end{document}\n')
                state = self.finish(str(base))
                self.assertEqual(state['status'], 'ready', self.document.diff_log.decode(errors='replace')[-3000:])
                self.assertIn('Grid checks', self.text())
                self.assertIn('refinement', self.text())

    def test_comparison_waits_until_the_reader_publishes_the_new_original(self):
        base = self.root / 'base.tex'
        base.write_text(self.source.read_text().replace('new', 'old'))
        self.path.write_bytes(self.path.read_bytes() + b'\n% new PDF revision\n')
        self.revision.configure({'base': str(base)})
        self.revision.refresh()
        self.revision.worker.join(timeout=5)
        self.assertEqual(self.document.diff_data, b'')
        self.publish()
        self.assertEqual(self.finish()['status'], 'ready')

    def test_project_sidecar_and_changed_snapshot_rebuild_the_revision(self):
        base = self.root / 'base.tex'
        base.write_text(self.source.read_text().replace('new', 'old'))
        self.revision.sidecar.write_text(base.name)
        self.assertEqual(self.finish()['status'], 'ready')
        self.assertIn('old', self.text())
        base.write_text(self.source.read_text().replace('new', 'earlier'))
        self.assertEqual(self.finish()['status'], 'ready')
        self.assertIn('earlier', self.text())

    def test_source_baseline_is_found_when_pdf_is_in_a_build_directory(self):
        output = self.root / 'build'
        output.mkdir()
        self.path.rename(output / self.path.name)
        self.path = output / self.path.name
        self.revision.close()
        self.revision = pdf.Revision(self.document, self.source, self.path, self.stopped)
        self.addCleanup(self.revision.close)
        base = self.root / 'paper.base.tex'
        base.write_text(self.source.read_text().replace('new', 'baseline'))
        self.assertEqual(self.finish()['status'], 'ready', self.document.diff_log.decode(errors='replace'))
        self.assertIn('baseline', self.text())
        self.assertEqual(self.revision.sidecar, self.root / 'paper.review-base')
        other = self.root / 'explicit.tex'
        other.write_text(self.source.read_text().replace('new', 'chosen'))
        self.revision.sidecar.write_text(other.name)
        self.assertEqual(self.finish()['status'], 'ready')
        self.assertIn('chosen', self.text())
        self.assertEqual(self.finish(str(base))['status'], 'ready')
        self.assertIn('baseline', self.text())

    def test_sidecar_can_point_to_a_multifile_snapshot(self):
        baseline = self.root / 'baseline'
        baseline.mkdir()
        (baseline / 'paper.tex').write_text(self.source.read_text().replace('A new sentence.', '\\input{chapter}'))
        (baseline / 'chapter.tex').write_text('A historical chapter.')
        self.revision.sidecar.write_text('baseline/paper.tex\n')
        self.assertEqual(self.finish()['status'], 'ready', self.document.diff_log.decode(errors='replace'))
        self.assertIn('historical chapter', self.text())
        self.assertIn('new sentence', self.text())

    def test_bibliography_is_built_in_the_private_output_directory(self):
        self.source.write_text(self.source.read_text().replace('A new sentence.',
            'A new sentence cites Knuth~\\cite{knuth}.\n\\bibliographystyle{plain}\n\\bibliography{refs}'))
        refs = self.root / 'refs.bib'
        refs.write_text('@book{knuth, author={Donald Knuth}, title={The TeXbook}, year={1984}, publisher={Addison-Wesley}}\n')
        self.compile()
        self.publish()
        base = self.root / 'base.tex'
        base.write_text(self.source.read_text().replace('new sentence', 'previous sentence'))
        state = self.finish(str(base), files=[str(self.source), str(refs)])
        self.assertEqual(state['status'], 'ready', self.document.diff_log.decode(errors='replace'))
        self.assertIn('TeXbook', self.text())

    @unittest.skipUnless(shutil.which('lualatex'), 'LuaLaTeX unavailable')
    def test_comparison_uses_the_projects_lualatex_engine(self):
        self.source.write_text(self.source.read_text().replace('A new sentence.',
            '\\ifdefined\\directlua A new sentence.\\else\\undefinedengine\\fi'))
        subprocess.run(['lualatex', '-interaction=batchmode', '-halt-on-error', self.source.name],
                       cwd=self.root, check=True, stdout=subprocess.DEVNULL)
        self.publish()
        base = self.root / 'base.tex'
        base.write_text(self.source.read_text().replace('new sentence', 'old sentence'))
        state = self.finish(str(base), engine='-lualatex')
        self.assertEqual(state['status'], 'ready', self.document.diff_log.decode(errors='replace'))


class SourceMapTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def mapping(self, source, generated):
        current = self.root / 'paper.tex'
        current.write_text(source)
        diff = self.root / 'diff.tex'
        diff.write_text(generated)
        return SourceMap(diff, [current])

    def test_nested_math_wrappers_and_comments_keep_line_numbers(self):
        source = 'An equation follows.\nThe value $x^{2}+y$ is measured. % Note\n'
        generated = '\\DIFdel{Old words.}\nAn equation follows.\nThe \\DIFdel{old} \\DIFadd{value $x^{2}+y$} is measured. %DIF >\n'
        mapping = self.mapping(source, generated)
        self.assertEqual(mapping.locate(3), {'file': str(self.root / 'paper.tex'), 'line': 2, 'column': 1})
        self.assertEqual(surviving('first\n\\DIFdel{deleted {nested}}\nlast').count('\n'), 2)

    def test_deleted_only_lines_locate_nearby_without_claiming_an_exact_selection(self):
        mapping = self.mapping('The current first paragraph.\nThe current next paragraph.\n',
            'The current first paragraph.\n\\DIFdelbegin \\DIFdel{A removed passage.}\n\\DIFdelend\nThe current next paragraph.\n')
        point = mapping.locate(2)
        self.assertTrue(point['approximate'])
        self.assertIn(point['line'], (1, 2))

    def test_repeated_unanchored_text_is_not_a_source_position(self):
        mapping = self.mapping('The repeated passage.\nThe repeated passage.\n', 'The repeated passage.\n')
        with self.assertRaisesRegex(ValueError, 'unambiguous'):
            mapping.locate(1)



if __name__ == '__main__':
    unittest.main()
