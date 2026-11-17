# Test scope and upstream fixtures

WebPreview owns the integration between editing and reading. Its tests should
exercise that boundary as well as the bundled output of upstream engines.
An upstream parser passing its own suite does not test our AST transforms,
source attributes, resource policy or packaged browser code.

| Contract | Checks |
| --- | --- |
| Markdown syntax survives bundling and source decoration | `tests/commonmark.mjs`, `tests/markdown-engine.mjs` |
| Extensions retain native AST/tokens and source ownership | `tests/remark-annotation.mjs`, `tests/markdown-build.mjs` |
| Browser controls, refresh, selection, reading position and touch layout | `tests/browser.mjs`, `tests/markdown.browser.mjs` |
| Complete PDF publication, revision comparison, SyncTeX, private transport and shutdown | `tests/test_reader.py` |
| Unsaved drafts, media, linked notes and deferred source jumps | `tests/test_markdown.py` |
| Standalone Vim commands and selection | `tests/vim.vim` |
| Save/build/conflict policy | Onesimus's integration suite outside this package |

Run from the package directory:

```sh
python3 -m unittest discover -s tests
vim -Nu NONE -i NONE -n -es -S tests/vim.vim
node tests/markdown-engine.mjs
node tests/commonmark.mjs
node tests/browser.mjs
node tests/markdown.browser.mjs
```

Browser tests need Playwright and installed browsers. Set `PLAYWRIGHT_MODULE`
to its module entry when it lives outside the package. Tests create independent
editor/reader processes and temporary documents; they must not attach to a
person's running editor.

## What is inherited

`tests/fixtures/commonmark/spec-0.31.2.json` is the unmodified CommonMark 0.31.2
example corpus, retrieved from <https://spec.commonmark.org/0.31.2/spec.json>.
Its SHA-256 is
`d431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20`.
Examples retain upstream numbers and sections.

The fixture is derived from the CommonMark specification by John MacFarlane,
licensed CC BY-SA 4.0. The upstream license is retained beside it. This data's
license is separate from WebPreview's MIT code; no upstream test runner is copied.
The canonical license is <https://creativecommons.org/licenses/by-sa/4.0/>.

The regression runner selects 99 examples across complete sections for backslash
escapes, character references, ATX headings, fenced code and code spans. It compares DOM structure,
text and semantic attributes after removing our navigation metadata and link
window attributes, and checks native parser source coordinates. This targets
places where our math/annotation transforms and source decoration could disturb
ordinary Markdown. In the default remark profile, 95 use upstream expectations;
four explicitly assert the product's dialect. Example 12's empty `\(\)` and
backslash-only `\[...\]` become formulas in remark, whereas markdown-it retains
the CommonMark punctuation. Examples 21, 31 and 344 never produce author HTML
elements. remark retains their source text; markdown-it still applies inline
Markdown escapes, entities and code spans. Each profile has explicit expected
text for those cases. All 99 run in both profiles; these differences are visible,
not skipped or claimed as engine equivalence.
It is a scoped integration regression, not a claim of full
CommonMark conformance or complete equivalence between parser profiles.

The same runner accepts an optional asset archive path. Check an optional
markdown-it build without replacing the shipped remark bundle:

```sh
npm ci
node web/build-assets.mjs --engine markdown-it --output /tmp/markdown-it.zip
node tests/markdown-engine.mjs /tmp/markdown-it.zip
node tests/commonmark.mjs /tmp/markdown-it.zip
MARKDOWN_ASSETS=/tmp/markdown-it.zip node tests/markdown.browser.mjs
node tests/markdown-build.mjs
node tests/remark-annotation.mjs
```

The retired `markdown-preview.nvim` checkout at commit
`02cc3874738bc0f86e4b91f09b8a0ac88aef8e96` has `test/init.vim` and a manual
`test/test.md` demonstration. It is a useful feature checklist, not a portable
automated acceptance suite. We do not copy its Node/Vim harness or treat its
diagram demonstrations as passing features here.

PDF.js, KaTeX, VimTeX and the Markdown engines retain their own upstream suites.
Port a relevant regression with its version, source and license when it crosses
our integration boundary; do not vendor their entire application test systems.
Behavior we add, such as preserving a dirty buffer or deferring a source jump,
needs our own editor/browser assertion.

## Release evidence

Record actual engine, browser and platform coverage. Chromium and WebKit checks
on a desktop, including narrow viewports, do not establish physical iOS/Termius
or native Windows/Linux support. Keep unsupported features visible rather than
silently relaxing assertions or counting skipped cases as passes.
