"""Build from the sdist and exercise an installed wheel outside the checkout."""
import http.client
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import time
from urllib.parse import urlsplit
import venv
import zipfile


def run(*command, **options):
    return subprocess.run(command, check=True, **options)


def smoke(python, directory):
    environment = {key: value for key, value in os.environ.items() if key != 'PYTHONPATH'}
    environment['PATH'] = str(python.parent)
    for kind, content in [('markdown', b'# A draft.'), ('pdf', b'%PDF-1.4\ncomplete\n%%EOF\n')]:
        source = directory / ('draft.md' if kind == 'markdown' else 'paper.pdf')
        source.write_bytes(content)
        command = [str(python), '-I', '-m', 'webpreview', '--' + kind, str(source), '--serve']
        if kind == 'pdf':
            command += ['--editor', str(directory / 'paper.tex')]
        process = subprocess.Popen(command, cwd=directory, env=environment,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            ready = json.loads(process.stdout.readline())
            assert ready['event'] == 'ready', ready
            url = urlsplit(ready['url'])
            if kind == 'markdown':
                process.stdin.write(json.dumps({'event': 'source', 'file': str(source), 'text': '# Unsaved draft.'}) + '\n')
                process.stdin.flush()
            connection = http.client.HTTPConnection(url.hostname, url.port, timeout=5)
            try:
                for _ in range(100):
                    connection.request('GET', url.path + 'state')
                    state = json.loads(connection.getresponse().read())
                    if state.get('revision') or state.get('sha256'):
                        break
                    time.sleep(0.025)
                assert state.get('text') == '# Unsaved draft.' if kind == 'markdown' else state.get('sha256'), state
                for route in ['', 'viewer.mjs', 'markdown/vendor.mjs' if kind == 'markdown' else 'pdfjs/build/pdf.min.mjs']:
                    connection.request('GET', url.path + route)
                    response = connection.getresponse()
                    assert response.status == 200, route
                    assert response.read(), route
            finally:
                connection.close()
            process.stdin.close()
            assert process.wait(timeout=8) == 0, process.stderr.read()
        finally:
            if process.poll() is None:
                process.kill()
            process.wait()
            process.stdout.close()
            process.stderr.close()


def main():
    distributions = Path(sys.argv[1]).resolve()
    wheel, = distributions.glob('*.whl')
    sdist, = distributions.glob('*.tar.gz')
    with tempfile.TemporaryDirectory(prefix='webpreview-distribution-') as temporary:
        work = Path(temporary).resolve()
        with tarfile.open(sdist) as archive:
            names = {Path(name).relative_to(Path(name).parts[0]).as_posix() for name in archive.getnames()}
            for required in ['plugin/webpreview.vim', 'autoload/webpreview.vim', 'bin/webpreview',
                    'web/build-assets.mjs', 'web/build-pdfjs.py', 'web/archive.py',
                    'tests/run.sh', 'doc/webpreview.txt', 'THIRD_PARTY.md', 'package-lock.json']:
                assert required in names, 'Missing source: ' + required
            for entry in archive:
                if entry.isfile():
                    target = work / 'source' / entry.name
                    assert target.resolve().is_relative_to(work / 'source')
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.extractfile(entry).read())
        source, = (work / 'source').iterdir()
        run(sys.executable, '-m', 'build', '--wheel', '--outdir', str(work / 'rebuilt'), str(source))
        rebuilt, = (work / 'rebuilt').glob('*.whl')
        with zipfile.ZipFile(wheel) as original, zipfile.ZipFile(rebuilt) as rebuilt_archive:
            assets = {name for name in original.namelist() if name.startswith('webpreview/')}
            assert assets == {name for name in rebuilt_archive.namelist() if name.startswith('webpreview/')}
            for name in assets:
                assert original.read(name) == rebuilt_archive.read(name), name
        venv.EnvBuilder(with_pip=True, symlinks=os.name != 'nt').create(work / 'venv')
        python = work / 'venv' / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
        run(str(python), '-m', 'pip', 'install', '--no-index', '--no-deps', str(rebuilt))
        smoke(python, work)
        run('sh', 'tests/run.sh', cwd=source, env={**os.environ, 'PYTHON': sys.executable})
    print('Source distribution, rebuilt wheel, installed readers and standalone checkout: PASS')


if __name__ == '__main__':
    main()
