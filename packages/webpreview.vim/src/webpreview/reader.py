#!/usr/bin/env python3
"""Serve editor-owned Markdown drafts and complete PDF revisions in the browser."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import tarfile
import tempfile
import time
import weakref
from .session import ASSETS, Session, emit, serve_session
from .sourcemap import SourceMap

MAX_PDF = 128 * 1024 * 1024

# One authenticated SSH connection carries complete PDF revisions. Length
# framing handles binary data, and checks before/after reading reject a file
# being rewritten by TeX. No SSH configuration or remote file is modified.
REMOTE_READER = r'''
import hashlib, json, os, sys, threading
path = sys.argv[1]
previous = None
stopped = threading.Event()
def watch_stdin():
    sys.stdin.buffer.read()
    stopped.set()
threading.Thread(target=watch_stdin, daemon=True).start()
while not stopped.is_set():
    try:
        before = os.stat(path)
        if before.st_size > 128 * 1024 * 1024:
            raise ValueError('PDF exceeds 128 MiB')
        with open(path, 'rb') as source:
            data = source.read(128 * 1024 * 1024 + 1)
        after = os.stat(path)
        if (before.st_mtime_ns, before.st_size, before.st_ino) != (after.st_mtime_ns, after.st_size, after.st_ino):
            stopped.wait(1)
            continue
        if not data.startswith(b'%PDF-') or b'%%EOF' not in data[-1024:]:
            raise ValueError('Waiting for a complete PDF')
        digest = hashlib.sha256(data).hexdigest()
        if digest != previous:
            header = json.dumps({'length': len(data), 'sha256': digest}).encode() + b'\n'
            sys.stdout.buffer.write(header)
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
            previous = digest
    except (OSError, ValueError) as error:
        sys.stdout.buffer.write(json.dumps({'error': str(error)}).encode() + b'\n')
        sys.stdout.buffer.flush()
    stopped.wait(2)
'''


def reader_command(pdf, host=None):
    if host:
        if host.startswith('-') or any(c.isspace() for c in host):
            raise ValueError('Use an SSH host alias or user@host, without options or whitespace')
        command = 'python3 -u -c {} {}'.format(shlex.quote(REMOTE_READER), shlex.quote(pdf))
        return ['ssh', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=3', '--', host, command]
    return [sys.executable, '-u', '-c', REMOTE_READER, str(Path(pdf).expanduser().resolve())]


def read_revision(stream):
    line = stream.readline(8193)
    if not line:
        raise EOFError('Connection closed; reconnecting')
    if len(line) > 8192 or not line.endswith(b'\n'):
        raise ValueError('Invalid PDF transport header')
    header = json.loads(line)
    if 'error' in header:
        raise OSError(header['error'])
    size = header.get('length', 0)
    if not isinstance(size, int) or not 0 < size <= MAX_PDF:
        raise ValueError('Invalid PDF length')
    pieces, remaining = [], size
    while remaining:
        piece = stream.read(remaining)
        if not piece:
            raise EOFError('PDF transfer interrupted')
        pieces.append(piece)
        remaining -= len(piece)
    data = b''.join(pieces)
    if hashlib.sha256(data).hexdigest() != header.get('sha256'):
        raise ValueError('PDF transfer checksum mismatch')
    if not data.startswith(b'%PDF-') or b'%%EOF' not in data[-1024:]:
        raise ValueError('Incomplete PDF')
    return data, header['sha256']


class Document(Session):
    page = 'pdf'

    def __init__(self):
        super().__init__()
        self.data = b''
        self.digest = ''
        self.error = 'Waiting for the first complete PDF…'
        self.ready = threading.Event()
        self.process = None
        self.sync = None
        self.position = None
        self.sequence = 0
        self.revision = None
        self.diff_state = {'base': '', 'built_base': '', 'status': 'idle', 'sha256': '', 'source_revision': '', 'error': '', 'request': 0}
        self.diff_data = b''
        self.diff_log = b''
        self.diff_sync = None

    def state(self, known_revision=None):
        return {'sha256': self.digest, 'error': self.error, 'sync': self.sync is not None,
                'position': self.position, 'diff': {**self.diff_state, 'sync': self.diff_sync is not None}}

    def resource(self, route):
        if route in ('pdf', 'download') and self.data:
            return self.data, 'application/pdf'
        if route in ('diff', 'diff-download') and self.diff_data:
            return self.diff_data, 'application/pdf'
        if route == 'diff-log':
            return self.diff_log, 'text/plain; charset=utf-8'
        raise FileNotFoundError(route)

    def inverse(self, request):
        with self.lock:
            changes = request.get('version') == 'changes'
            sync = self.diff_sync if changes else self.sync
            if changes and self.diff_state['source_revision'] != self.digest:
                raise ValueError('Comparison is outdated; rebuild before locating.')
        if sync is None:
            raise ValueError('Source navigation is not available for this PDF.')
        sync.inverse(request)

    def tick(self):
        if self.revision:
            self.revision.refresh()

    def close(self):
        self.stop_reader()
        if self.revision:
            self.revision.close()
        self.worker.join(timeout=5)

    def stop_reader(self):
        with self.lock:
            if self.process is not None:
                self.process.terminate()

    def update(self, data, digest):
        with self.lock:
            if digest != self.digest:
                self.position = None
            self.data, self.digest, self.error = data, digest, ''
            self.ready.set()

    def fail(self, error):
        with self.lock:
            message = str(error)
            if message != self.error:
                print(message, file=sys.stderr, flush=True)
            self.error = message


class SyncTeX:
    """Positions travel through the pipe owned by the source editor."""
    def __init__(self, document, pdf, source):
        self.document = document
        self.pdf = Path(pdf).resolve()
        self.directory = Path(source).resolve().parent

    def query(self, direction, value, revision):
        if not revision or hashlib.sha256(self.pdf.read_bytes()).hexdigest() != revision:
            raise ValueError('PDF changed; refresh before locating')
        result = subprocess.run(
            ['synctex', direction, '-i' if direction == 'view' else '-o', value,
             *(['-o', str(self.pdf)] if direction == 'view' else [])],
            cwd=self.directory, env={**os.environ, 'SYNCTEX_EDITOR': ''},
            capture_output=True, text=True, timeout=5, check=True)
        if hashlib.sha256(self.pdf.read_bytes()).hexdigest() != revision:
            raise ValueError('PDF changed; refresh before locating')
        records = []
        for line in result.stdout.splitlines():
            if line in ('SyncTeX result begin', 'SyncTeX result end'):
                continue
            key, separator, value = line.partition(':')
            if separator:
                if key == 'Output':
                    records.append({})
                if records:
                    records[-1][key] = value
        if not records:
            raise ValueError('No SyncTeX position; build with -synctex=1 first')
        return records[0]

    def forward(self, request):
        if not self.document.ready.wait(5):
            raise ValueError('Waiting for a complete PDF')
        with self.document.lock:
            revision = self.document.digest
        result = self.query('view', '{}:{}:{}'.format(
            int(request['line']), int(request['column']), request['file']), revision)
        position = {'page': int(result['Page']), 'x': float(result['x']),
                    'y': float(result['y']), 'revision': revision,
                    'follow': bool(request.get('follow'))}
        with self.document.lock:
            self.document.sequence += 1
            self.document.position = {**position, 'id': self.document.sequence}

    def source_position(self, point, revision):
        page, x, y = int(point['page']), float(point['x']), float(point['y'])
        if page < 1 or not math.isfinite(x) or not math.isfinite(y):
            raise ValueError('Invalid page position')
        result = self.query('edit', f'{page}:{x}:{y}:{self.pdf}', revision)
        source = Path(result['Input'])
        if not source.is_absolute():
            source = self.directory / source
        return {'file': str(source.resolve()), 'line': int(result['Line']),
                'column': max(1, int(result['Column']))}

    def current_revision(self):
        return self.document.digest

    def inverse(self, request):
        with self.document.lock:
            if request['revision'] != self.current_revision():
                raise ValueError('PDF changed; refresh before locating')
        position = self.source_position(request, request['revision'])
        if 'text' in request and not position.get('approximate'):
            if not isinstance(request['text'], str) or not request['text'].strip():
                raise ValueError('Invalid selected text')
            end = self.source_position(request['end'], request['revision'])
            if end['file'] != position['file']:
                raise ValueError('Selection crosses source files; select one passage')
            position.update(text=request['text'], end_line=end['line'])
        with self.document.lock:
            if request['revision'] != self.current_revision():
                raise ValueError('PDF changed; refresh before locating')
        emit({'event': 'source', **position})


class RevisionSync(SyncTeX):
    """Keep a completed comparison and its source map together while it is read."""
    def __init__(self, document, pdf, generated, files, temporary):
        super().__init__(document, pdf, generated)
        self.generated = generated
        self.mapping = SourceMap(generated, files)
        self.temporary = temporary
        weakref.finalize(self, temporary.cleanup)

    def current_revision(self):
        state = self.document.diff_state
        return state['sha256'] if state['source_revision'] == self.document.digest \
            and state['status'] != 'needs-build' else ''

    def source_position(self, point, revision):
        position = super().source_position(point, revision)
        if Path(position['file']) != self.generated.resolve():
            raise ValueError('This comparison element has no manuscript source position.')
        return self.mapping.locate(position['line'])


class Revision:
    """One cancellable latexdiff build, owned by the reader and its Vim pipe."""
    def __init__(self, document, source, pdf, stopped):
        self.document = document
        self.source = Path(source).resolve()
        self.pdf = Path(pdf).resolve()
        self.sidecar = self.source.with_suffix('.review-base')
        self.snapshot = self.source.with_name(self.source.stem + '.base' + self.source.suffix)
        self.options = {'files': [str(self.source)], 'engine': '-pdf'}
        self.request = 0
        self.previous = None
        self.stopped = stopped
        self.cancel = threading.Event()
        self.worker = None

    def configure(self, request):
        with self.document.lock:
            if request.get('base') == '' and self.options.get('base'):
                request = {**request, 'base': self.options['base']}
            self.options.update(request)
            if 'base' in request:
                self.request += 1

    def refresh(self):
        with self.document.lock:
            revision = self.document.digest
            options, request = dict(self.options), self.request
        if not revision:
            return
        base, error, needs_build = options.get('base'), '', False
        try:
            if not base:
                base = self.sidecar.read_text(encoding='utf-8').strip() if self.sidecar.exists() else ''
                if not base and self.snapshot.is_file():
                    base = str(self.snapshot)
                if not base and 'base' in options:
                    base = 'HEAD'
            path = Path(base).expanduser()
            if not path.is_absolute():
                path = self.source.parent / path
            files = sorted({self.source, *(Path(name).resolve() for name in options['files'])})
            stamps = tuple((str(file), file.stat().st_mtime_ns, file.stat().st_size) for file in files)
            base_stamp = (path.stat().st_mtime_ns, path.stat().st_size) if base and path.is_file() else None
            pdf_stamp = self.pdf.stat().st_mtime_ns
            key = (base, revision, request, stamps, base_stamp, options['engine'], pdf_stamp)
            needs_build = bool(base and any(stamp[1] > self.pdf.stat().st_mtime_ns for stamp in stamps))
            if needs_build:
                error = 'Saved inputs changed. Build the paper before comparing.'
        except OSError as failure:
            key, error = (base, revision, request, str(failure)), str(failure)
        if self.worker and self.worker.is_alive():
            if key != self.previous:
                self.cancel.set()
            return
        if key == self.previous and not self.cancel.is_set():
            return
        self.previous = key
        with self.document.lock:
            self.document.diff_state.update(base=base or '', request=request,
                status='needs-build' if needs_build else 'error' if error else 'building' if base else 'idle', error=error)
        if not base or error:
            return
        self.cancel = threading.Event()
        self.worker = threading.Thread(target=self.build,
            args=(base, path, files, revision, options['engine'], key), daemon=True)
        self.worker.start()

    def run(self, command, cwd, log, output=None):
        log.write(('\n$ ' + shlex.join(map(str, command)) + '\n').encode())
        log.flush()
        process = subprocess.Popen(command, cwd=cwd, stdout=output or log, stderr=log,
                                   start_new_session=os.name != 'nt')
        deadline = time.monotonic() + 180
        try:
            while process.poll() is None:
                if self.cancel.is_set() or self.stopped.is_set():
                    raise InterruptedError('Comparison cancelled')
                if time.monotonic() > deadline:
                    raise TimeoutError(command[0] + ' exceeded three minutes; see the comparison log.')
                time.sleep(0.05)
            if process.returncode:
                raise ValueError(command[0] + ' failed; see the comparison log.')
        finally:
            if process.poll() is None:
                if os.name == 'nt':
                    subprocess.run(['taskkill', '/T', '/F', '/PID', str(process.pid)],
                                   stdout=log, stderr=log)
                else:
                    os.killpg(process.pid, signal.SIGKILL)
                process.wait()

    def git_base(self, base, work, log):
        listing = work / 'git-root'
        with listing.open('wb') as output:
            self.run(['git', 'rev-parse', '--show-toplevel'], self.source.parent, log, output)
        root = Path(listing.read_text().strip())
        with listing.open('wb') as output:
            self.run(['git', 'rev-parse', '--verify', '--end-of-options', base + '^{commit}'], root, log, output)
        commit = listing.read_text().strip()
        with listing.open('wb') as output:
            self.run(['git', 'ls-tree', '-rz', '--name-only', commit], root, log, output)
        names = [name for name in listing.read_text().split('\0') if Path(name).suffix in ('.tex', '.ltx', '.sty', '.cls')]
        if not names:
            raise ValueError('The Git baseline contains no TeX sources for this paper.')
        archive = work / 'base.tar'
        with archive.open('wb') as output:
            self.run(['git', 'archive', '--format=tar', commit, '--', *names], root, log, output)
        with tarfile.open(archive) as snapshot:
            for member in snapshot:
                if member.isfile():
                    target = work / 'old' / member.name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(snapshot.extractfile(member).read())
        return work / 'old' / self.source.relative_to(root), base + ' @ ' + commit[:10]

    def build(self, base, path, files, revision, engine, key):
        temporary = tempfile.TemporaryDirectory(prefix='webpreview-diff-')
        try:
            work = Path(temporary.name)
            log_path = work / 'comparison.log'
            try:
                if hashlib.sha256(self.pdf.read_bytes()).hexdigest() != revision:
                    return  # The PDF watcher has not published this build yet.
                with log_path.open('wb') as log:
                    old, label = (path, str(path)) if path.is_file() else self.git_base(base, work, log)
                    # Flatten a copy without build products: old/new .bbl files must
                    # not silently turn bibliography generation into a one-sided diff.
                    root = Path(os.path.commonpath([str(file.parent) for file in files]))
                    for file in files:
                        copied = work / 'new' / file.relative_to(root)
                        copied.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copyfile(file, copied)
                    current = work / 'new' / self.source.relative_to(root)
                    generated = work / self.source.name
                    with generated.open('wb') as output:
                        # Sectioning arguments stay whole: markup inside a moved heading
                        # breaks class heading parsers such as REVTeX's \@sect@ltx.
                        self.run(['latexdiff', '--encoding=utf8', '--flatten',
                                  '--preamble=' + str(ASSETS / 'latexdiff.tex'), '--math-markup=whole',
                                  '--graphics-markup=none',
                                  '--exclude-textcmd=part,chapter,section,subsection,subsubsection,paragraph,subparagraph',
                                  str(old), str(current)], current.parent, log, output)
                    diagnostics = log_path.read_text(errors='replace')
                    if 'WARNING: Could not find included file ' in diagnostics or 'WARNING: Could not find subfile ' in diagnostics:
                        raise ValueError('latexdiff could not expand an included source. See the comparison log.')
                    output = work / 'output'
                    self.run(['latexmk', *shlex.split(engine), '-interaction=nonstopmode',
                              '-halt-on-error', '-synctex=1', '-cd-', '-outdir=' + str(output),
                              '-auxdir=' + str(output), str(generated)], current.parent, log)
                    data = (output / self.source.with_suffix('.pdf').name).read_bytes()
                    if not data.startswith(b'%PDF-') or b'%%EOF' not in data[-1024:]:
                        raise ValueError('The comparison build did not produce a complete PDF.')
                sync = RevisionSync(self.document, output / self.source.with_suffix('.pdf').name,
                                    generated, files, temporary)
                with self.document.lock:
                    stamps = tuple((str(file), file.stat().st_mtime_ns, file.stat().st_size) for file in files)
                    if not self.cancel.is_set() and not self.stopped.is_set() \
                            and self.document.digest == revision and self.request == key[2] and stamps == key[3] \
                            and self.pdf.stat().st_mtime_ns == key[-1] \
                            and (not path.is_file() or (path.stat().st_mtime_ns, path.stat().st_size) == key[4]):
                        self.document.diff_data = data
                        self.document.diff_sync = sync
                        temporary = None  # The published comparison now owns its temporary files.
                        self.document.diff_state.update(status='ready', error='', built_base=label,
                            sha256=hashlib.sha256(data).hexdigest(), source_revision=revision)
            except InterruptedError:
                return
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                with self.document.lock:
                    if not self.cancel.is_set() and not self.stopped.is_set():
                        self.document.diff_state.update(status='error', error=str(error))
            finally:
                if not self.cancel.is_set():
                    with self.document.lock:
                        self.document.diff_log = log_path.read_bytes() if log_path.exists() else b''
        finally:
            if temporary is not None:
                temporary.cleanup()

    def close(self):
        self.cancel.set()
        if self.worker:
            self.worker.join()
        self.document.diff_sync = None


def editor_channel(document, stopped):
    try:
        for line in sys.stdin:
            request = None
            try:
                request = json.loads(line)
                if request.get('event') == 'open':
                    document.open_if_unused()
                elif request.get('event') == 'diff':
                    document.revision.configure(request)
                else:
                    document.sync.forward(request)
            except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as error:
                # Following asks on every cursor rest; a line without a PDF position is not news.
                if not (isinstance(request, dict) and request.get('follow')):
                    emit({'event': 'error', 'message': str(error)})
    finally:
        stopped.set()


def follow(document, command, stopped):
    while not stopped.is_set():
        process = None
        try:
            with document.lock:
                if stopped.is_set():
                    return
                process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
                document.process = process
            while not stopped.is_set():
                try:
                    data, digest = read_revision(process.stdout)
                    document.update(data, digest)
                except OSError as error:
                    document.fail(error)
        except (OSError, ValueError, EOFError) as error:
            if not stopped.is_set():
                document.fail(error)
        finally:
            if process is not None:
                process.stdin.close()
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                process.stdout.close()
                with document.lock:
                    document.process = None
        stopped.wait(2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument('--pdf', help='PDF path on the source machine')
    inputs.add_argument('--markdown', metavar='SOURCE', help='Preview Markdown drafts through the editor JSON pipe')
    parser.add_argument('--markdown-assets', metavar='ZIP', help='Custom Markdown renderer and styles built with web/build-assets.mjs')
    parser.add_argument('--host', help='SSH alias or user@host; omit for a local PDF')
    parser.add_argument('--serve', action='store_true', help='Serve on loopback without opening a browser (for SSH forwarding)')
    parser.add_argument('--port', type=int, default=0, help='Loopback port; default chooses a free port')
    parser.add_argument('--url-host', default='127.0.0.1', help='Exact hostname allowed for a private relay; listener stays on loopback')
    parser.add_argument('--editor', metavar='MAIN_TEX', help='Own this reader through an editor JSON pipe; enable SyncTeX')
    args = parser.parse_args()
    if args.markdown:
        from .markdown import main as markdown_main
        return markdown_main(args, parser)
    if args.editor and args.host:
        parser.error('--editor runs beside the editor on the source machine; omit --host')
    try:
        command = reader_command(args.pdf, args.host)
    except ValueError as error:
        parser.error(str(error))
    document = Document()
    stopped = threading.Event()
    if args.editor:
        document.sync = SyncTeX(document, args.pdf, args.editor)
        document.revision = Revision(document, args.editor, args.pdf, stopped)
    document.worker = threading.Thread(target=follow, args=(document, command, stopped), daemon=True)
    document.worker.start()
    try:
        return serve_session(document, args, stopped, editor_channel if args.editor else None)
    except OSError as error:
        parser.exit(1, f'Cannot open preview port {args.port}: {error}\n')


if __name__ == '__main__':
    raise SystemExit(main())
