# Editor protocol

A local reader for live Markdown and compiled PDF revisions. Python 3.9+,
no Python runtime dependencies; browser engines and fonts are bundled.
TeX/SyncTeX and comparison tools come from your TeX installation.

The Python package and command are `webpreview`. The Vim package owns the built-in
Markdown/PDF readers. Cogitatum uses its own host transport; it is not a consumer
of this protocol.

Install the package root with `pip install .`, then run:

```sh
webpreview --pdf /path/paper.pdf
# Or, without opening a browser on this machine:
webpreview --pdf /path/paper.pdf --serve
```

`python -m webpreview` offers the same CLI. The Vim plugin uses
`python3 bin/webpreview` directly, so it needs no separate pip installation.
`--host ssh-alias` follows a remote PDF using your SSH configuration. The
server listens on loopback; a private relay may use a locally configured hostname
with `--url-host`. No deployment hostname is shipped in the package.

## Editor integration (protocol 1)

Start with `--editor /path/main.tex --serve`. stdin/stdout carry one JSON object
per line; stderr is diagnostics. Closing stdin ends the reader and all comparison
jobs. The host editor owns opening the URL, changing buffers, unfolding, Visual
selection and its own save/build policy. The reader neither opens source files
in an editor nor saves them. No Vim server, daemon or global registry is required.

Host → reader:

```json
{"event":"open"}
{"file":"/path/main.tex","line":42,"column":1,"follow":false}
{"event":"diff","base":"HEAD","files":["/path/main.tex"],"engine":"-pdf"}
```

`open` requests a browser only when no page has reported presence in 90 seconds.
`follow` positions quietly; an explicit position returns to Original. `diff`
without `base` updates inputs without choosing a version. An empty base reuses
the chosen comparison, then the main source's `.review-base` sidecar or
`.base.tex` snapshot, then HEAD. The adjacent source conventions also enable
automatic comparison without selecting Changes. See [baseline conventions](changes.md).

Reader → host:

```json
{"event":"ready","url":"<private-session-url>","protocol":1}
{"event":"open"}
{"event":"source","file":"/path/main.tex","line":42,"column":1}
{"event":"source","file":"/path/main.tex","line":42,"column":1,"text":"Selected text","end_line":43}
{"event":"error","message":"Explanation"}
```

An approximate source event adds `"approximate":true`; the host should locate the
nearby surviving line and explain, without selecting text. This is used for
removed or unmatched comparison passages. Exact Visual selection remains the
editor's responsibility. Dirty buffers must remain intact.

The token-scoped HTTP API serves `state`, `pdf`, `diff`, `download`,
`diff-download`, `diff-log`, and bundled assets. `POST inverse` accepts
`page`, `x`, `y`, `revision`, and `version` (`original` or `changes`), plus optional
`text` and `end` coordinates. Coordinates use PDF points from the page's top.
Source files and build trees are never served. Changes navigation is enabled
only while its source revision matches Original. `diff.status` is `idle`,
`building`, `ready`, `needs-build` or `error`; hosts supply their own build command.
Lines without an exact mapping locate a nearby unambiguous anchor with
`approximate`; if none exists, navigation is rejected. Historical or generated
source files are never navigation targets.

## Live Markdown

`webpreview --markdown /path/note.md --serve` uses the same private HTTP session,
presence checks, JSON pipe and shutdown. It emits `ready` and `open` events just
like PDF. The editor sends unsaved buffer snapshots and cursor positions:

```json
{"event":"source","file":"/path/note.md","text":"# Draft\n\nUnsaved paragraph."}
{"event":"cursor","line":3,"column":1}
```

`state` returns `name` (basename only), `revision`, `cursor`, and `text` when
changed. `state?revision=N` omits the source text if that revision is still
current. Rendered blocks keep the parser's one-based source line ranges.
`POST inverse` accepts `revision`, `line`, optional `end_line`/`text`, or a
relative Markdown `path`. Stale revisions cannot move the editor. Selection
uses the same `source` event as PDF; following a note link emits
`{"event":"file","file":"/path/linked.md"}`. Vim opens it while preserving the
previous buffer, then supplies its live text to the existing session.

`media/` serves only image types below the open note's directory, including
symlink/path containment checks; it is not a general file server. Linked note
paths use the same directory boundary. Rendering libraries/fonts and their
licenses are in `markdown-libraries.zip`. HTML input is literal, and remote
resources do not load automatically.

`--markdown-assets /path/custom.zip` selects a locally built renderer archive for
this session. Build it with `web/build-assets.mjs --extensions entry.mjs --output
custom.zip`; Vim passes `g:webpreview_markdown_assets` through this option. It
changes the parser bundle/styles, not the editor protocol or session ownership.
The default archive uses remark/MDAST with Inline Annotation.
`--engine markdown-it` selects the alternative at build time; each archive
contains one engine, with the same reader protocol. Inline `data-source` wrappers
carry escaped original syntax for complete-fragment selections; the resulting
`text` still goes through the host's unique literal-match check.

## Development

```sh
python -m unittest discover -s tests
```

Integration tests use installed `pdflatex`, `synctex`, `latexmk`, `latexdiff`,
and a PDF text extractor. Onesimus runs these plus its Vim lifecycle tests.
`node tests/browser.mjs` checks Chromium and WebKit using Playwright; set
`PLAYWRIGHT_MODULE` to its module path when it is installed outside this package.
The Python provider is independently buildable; it is not published to a registry.
The bundled PDF.js archive includes its upstream license.
