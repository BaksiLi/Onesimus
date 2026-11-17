# Contributing

Keep the editing-to-reading boundary small. Describe the writing problem a
change solves and how source navigation survives it. Preserve Vim 8.2 and
Python 3.9 compatibility. Do not attach tests to a person's running editor.
The [architecture](doc/architecture.md) explains ownership.

## Development

The checkout works as a Vim package with Python 3.9+. Browsers use the committed
asset archives; no pip/npm installation is required for that path.

```sh
sh tests/run.sh
```

This runs standalone Vim, Python and shipped Markdown engine checks. Python
reports TeX-dependent skips when those tools are absent. Node 22+ is needed for
the JavaScript tests, not for ordinary preview use.

For the complete suite:

```sh
npm ci
npx playwright install chromium webkit
sh tests/run.sh --full
```

Full checks require Vim, Python, Node, `pdflatex`, `synctex`, `latexmk`,
`latexdiff`, `lualatex`, and `pdftotext` or `gs`. They exercise both Markdown
profiles, extension builds, upstream fixtures and both browser engines.
`WEBPREVIEW_TEST_VIM`, `PYTHON` and `PLAYWRIGHT_MODULE` select local test tools.
See [test scope](doc/testing.md) for coverage and inherited fixture licenses.

## Bundled libraries

```sh
npm ci
npm run build:assets
npm run build:pdfjs
```

Markdown versions are locked in `package-lock.json`. PDF.js comes from a fixed
upstream tarball checked against its SHA-512 digest. Both builders retain
upstream licenses and write ZIPs with sorted paths and fixed metadata. Rebuilds
with unchanged sources and tools produce identical archives. Keep the archives
committed so plugin installation remains independent of build tooling.

`markdown-libraries.zip/versions.json` records every bundled package version,
including multiple versions of the same dependency. [Third-party notices](THIRD_PARTY.md)
describe provenance. Asset changes need the shipped-output tests, not just tests
of unbundled source.

## First commit and early releases

The package directory is the intended repository root. Before its first commit:

- Copy only package files to an empty directory, excluding ignored artifacts.
  Run its tests there with no Onesimus runtime or neighboring repositories.
- Run the complete suite and inspect browser layouts. Record actual platforms;
  desktop WebKit at a narrow width is not a physical iOS test.
- Build and test the Python distributions:
  `python -m build && python tests/distribution.py dist`.
- Check `git diff --check`, bundled licenses, and the files to be committed for
  private hostnames, token URLs, user paths and manuscript/build artifacts.

The committed CI workflow is for that standalone repository. A successful local
run does not establish that the remote CI matrix has passed. Publish an early
0.x release with its tested support boundary; do not advertise native Windows,
Neovim or physical mobile support before testing those environments.

Onesimus can keep its bundled copy until a real release is available, then pin
that release. Repository extraction does not require an immediate installer
migration, registry publication, or a promise that every integration API is stable.
