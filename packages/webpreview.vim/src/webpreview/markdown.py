"""A live Markdown buffer using the same private session and editor pipe as PDF."""
import json
import mimetypes
from pathlib import Path
import sys
import threading
import zipfile
from urllib.parse import unquote
from .session import Session, emit, serve_session


class Markdown(Session):
    page = 'markdown'

    def __init__(self, source):
        super().__init__()
        self.source = Path(source).expanduser().resolve()
        self.text = ''
        self.revision = 0
        self.cursor = {'line': 1, 'column': 1}

    def update(self, request):
        with self.lock:
            if request['event'] == 'source':
                self.text = request['text']
                self.source = Path(request['file']).resolve()
                self.revision += 1
            elif request['event'] == 'cursor':
                self.cursor = {'line': request['line'], 'column': request.get('column', 1)}

    def state(self, known_revision=None):
        state = {'name': self.source.name, 'revision': self.revision, 'cursor': self.cursor}
        if str(self.revision) != known_revision:
            state['text'] = self.text
        return state

    def inverse(self, request):
        with self.lock:
            if request['revision'] != self.revision:
                raise ValueError('Draft changed; wait for the current preview before locating.')
            if 'path' in request:
                path = (self.source.parent / unquote(request['path'])).resolve()
                path.relative_to(self.source.parent)
                if path.suffix.lower() not in ('.md', '.markdown') or not path.is_file():
                    raise ValueError('Linked Markdown file is not available in this folder.')
                emit({'event': 'file', 'file': str(path)})
                return
            line = int(request['line'])
            end = int(request.get('end_line', line))
            if not 1 <= line <= end <= max(1, len(self.text.splitlines())):
                raise ValueError('Invalid source passage')
            event = {'event': 'source', 'file': str(self.source), 'line': line, 'column': 1}
            if request.get('text'):
                event.update(text=request['text'], end_line=end)
        emit(event)

    def resource(self, route):
        if not route.startswith('media/'):
            raise FileNotFoundError(route)
        path = (self.source.parent / unquote(route[len('media/'):])).resolve()
        path.relative_to(self.source.parent)
        if path.suffix.lower() not in ('.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg') or path.stat().st_size > 8 * 1024 * 1024:
            raise FileNotFoundError(route)
        return path.read_bytes(), mimetypes.guess_type(path.name)[0]

    def tick(self):
        pass

    def close(self):
        pass


def editor_channel(document, stopped):
    try:
        for line in sys.stdin:
            try:
                request = json.loads(line)
                if request.get('event') == 'open':
                    document.open_if_unused()
                else:
                    document.update(request)
            except (ValueError, TypeError, KeyError) as error:
                emit({'event': 'error', 'message': str(error)})
    finally:
        stopped.set()


def main(args, parser):
    if args.host:
        parser.error('--markdown runs beside the editor; omit --host')
    if args.markdown_assets:
        args.markdown_assets = Path(args.markdown_assets).expanduser().resolve()
        try:
            with zipfile.ZipFile(args.markdown_assets) as assets:
                for name in ('vendor.mjs', 'vendor.css', 'katex.min.css'):
                    assets.getinfo(name)
        except (OSError, KeyError, zipfile.BadZipFile) as error:
            parser.error('Cannot load Markdown assets: ' + str(error))
    document = Markdown(args.markdown)
    return serve_session(document, args, threading.Event(), editor_channel)
