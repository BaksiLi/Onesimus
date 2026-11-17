"""Rebuild the pinned PDF.js archive from its verified upstream tarball."""
import base64
import hashlib
import io
from pathlib import Path
import tarfile
import tempfile
from urllib.request import urlopen
from archive import write_archive

VERSION = '5.4.624'
INTEGRITY = 'sm6TxKTtWv1Oh6n3C6J6a8odejb5uO4A4zo/2dgkHuC0iu8ZMAXOezEODkVaoVp8nX1Xzr+0WxFJJmUr45hQzg=='
URL = f'https://registry.npmjs.org/pdfjs-dist/-/pdfjs-dist-{VERSION}.tgz'
ASSETS = Path(__file__).resolve().parents[1] / 'src/webpreview/assets'

with urlopen(URL, timeout=60) as response:
    data = response.read()
if base64.b64encode(hashlib.sha512(data).digest()).decode() != INTEGRITY:
    raise ValueError('PDF.js tarball integrity mismatch')
with tempfile.TemporaryDirectory(prefix='webpreview-pdfjs-') as temporary:
    root = Path(temporary)
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as source:
        for entry in source:
            name = entry.name.removeprefix('package/')
            if entry.isfile() and (name in ('LICENSE', 'build/pdf.min.mjs', 'build/pdf.worker.min.mjs',
                    'web/pdf_viewer.mjs', 'web/pdf_viewer.css')
                    or name.startswith(('cmaps/', 'standard_fonts/', 'wasm/', 'web/images/'))):
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.extractfile(entry).read())
    write_archive(root, ASSETS / f'pdfjs-{VERSION}.zip')
