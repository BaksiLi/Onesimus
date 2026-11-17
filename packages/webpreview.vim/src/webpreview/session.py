"""Private HTTP transport and lifetime shared by the document readers."""
import hashlib
import json
import mimetypes
from pathlib import Path
import secrets
import signal
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit
import webbrowser
import zipfile

ASSETS = Path(__file__).resolve().parent / 'assets'
CLIENT_TTL = 90


def emit(event):
    print(json.dumps(event), flush=True)


class Session:
    def __init__(self):
        self.lock = threading.Lock()
        self.clients = {}

    def open_if_unused(self):
        with self.lock:
            now = time.monotonic()
            self.clients = {client: seen for client, seen in self.clients.items()
                            if now - seen < CLIENT_TTL}
            present = bool(self.clients)
        if not present:
            emit({'event': 'open'})


def handler_for(document, token, url_host='127.0.0.1', markdown_assets=None):
    hosts = {'127.0.0.1', 'localhost', url_host.lower()}
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def handle(self):
            try:
                super().handle()
            except (BrokenPipeError, ConnectionResetError):
                pass

        def route(self):
            path = urlsplit(self.path).path
            host = self.headers.get('Host', '').split(':')[0].lower()
            if host not in hosts:
                self.send_error(403)
                return None
            prefix = '/' + token + '/'
            if not path.startswith(prefix):
                self.send_error(404)
                return None
            return path[len(prefix):]

        def do_GET(self):
            route = self.route()
            if route is None:
                return
            with document.lock:
                if route == '':
                    data = (ASSETS / (document.page + '.html')).read_bytes()
                    content_type = 'text/html; charset=utf-8'
                elif route == 'viewer.mjs':
                    data, content_type = (ASSETS / (document.page + '.mjs')).read_bytes(), 'text/javascript'
                elif route.startswith(('pdfjs/', 'markdown/')):
                    prefix, archive = ('pdfjs/', 'pdfjs-5.4.624.zip') if route.startswith('pdfjs/') else ('markdown/', 'markdown-libraries.zip')
                    path = markdown_assets if prefix == 'markdown/' and markdown_assets else ASSETS / archive
                    with zipfile.ZipFile(path) as assets:
                        try:
                            data = assets.read(route.removeprefix(prefix))
                        except KeyError:
                            self.send_error(404)
                            return
                    content_type = 'text/javascript' if route.endswith('.mjs') else mimetypes.guess_type(route)[0] or 'application/octet-stream'
                elif route == 'state':
                    query = parse_qs(urlsplit(self.path).query)
                    client = query.get('client', [''])[0]
                    if client:
                        document.clients[client] = time.monotonic()
                    data = json.dumps(document.state(query.get('revision', [''])[0])).encode()
                    content_type = 'application/json'
                else:
                    try:
                        data, content_type = document.resource(route)
                    except (OSError, ValueError):
                        self.send_error(404)
                        return
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Referrer-Policy', 'no-referrer')
            if route.startswith('media/'):
                self.send_header('Content-Security-Policy', "sandbox; default-src 'none'; style-src 'unsafe-inline'")
            elif document.page == 'markdown' and route == '':
                self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'")
            if route in ('download', 'diff-download'):
                filename = 'paper-changes.pdf' if route == 'diff-download' else 'paper.pdf'
                self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
            if route in ('pdf', 'download', 'diff', 'diff-download'):
                self.send_header('X-PDF-Revision', hashlib.sha256(data).hexdigest())
            self.end_headers()
            self.wfile.write(data)

        def do_POST(self):
            route = self.route()
            if route is None:
                return
            if route not in ('inverse', 'leave'):
                self.send_error(404)
                return
            try:
                size = int(self.headers.get('Content-Length', 0))
                if not 0 < size <= 65536:
                    raise ValueError('Invalid position request')
                request = json.loads(self.rfile.read(size))
                if route == 'leave':
                    with document.lock:
                        document.clients.pop(request['client'], None)
                else:
                    document.inverse(request)
            except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as error:
                data = str(error).encode()
                self.send_response(409)
            else:
                data = b'Sent to source editor' if route == 'inverse' else b''
                self.send_response(200)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(data)
    return Handler


def serve_session(document, args, stopped, channel):
    token = secrets.token_urlsafe(24)
    try:
        server = ThreadingHTTPServer(('127.0.0.1', args.port),
                                     handler_for(document, token, args.url_host, args.markdown_assets))
    except OSError:
        stopped.set()
        document.close()
        raise
    url = f'http://127.0.0.1:{server.server_port}/{token}/'
    threading.Thread(target=server.serve_forever, daemon=True).start()
    if channel:
        threading.Thread(target=channel, args=(document, stopped), daemon=True).start()
    interrupted = False
    def stop(*_):
        nonlocal interrupted
        interrupted = True
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    if channel:
        emit({'event': 'ready', 'url': url, 'protocol': 1})
    else:
        print(f'Browser: {url}', flush=True)
    if not args.serve:
        webbrowser.open(url)
    try:
        while not interrupted and not stopped.wait(0.25):
            document.tick()
    finally:
        stopped.set()
        document.close()
        server.shutdown()
        server.server_close()
    return 0
