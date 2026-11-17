# Changes and baseline convention

WebPreview compares baseline **source** with the saved source behind a compiled
PDF. `latexdiff` creates a private TeX document and builds it for the browser's
Changes view. Do not put generated diff TeX next to the manuscript for discovery.
It is an output, not a baseline or the source being edited.

## One-file baseline

For `paper.tex`, keep a self-contained baseline at `paper.base.tex`:

```text
paper.tex
paper.base.tex
build/
    paper.pdf
    paper.synctex.gz
```

Opening the browser detects the baseline and prepares Changes. The browser
stays on Original until you choose Changes. For a `.ltx` main file, the matching
snapshot is `paper.base.ltx`. The convention follows the main source, even when
build output lives elsewhere.

## Multi-file snapshot or Git revision

Put one value in `paper.review-base`, beside `paper.tex`. It can contain a Git
commit/ref, or a source path relative to that directory:

```text
baseline/paper.tex
```

For a multi-file snapshot, keep its relative includes intact:

```text
paper.tex
chapters/
    methods.tex
paper.review-base
baseline/
    paper.tex
    chapters/
        methods.tex
```

`latexdiff --flatten` expands both source trees. Keep the baseline as a fixed
snapshot; changing a baseline's included files requires an explicit comparison
request. Current figures are reused; image pixels are not compared.

## Choose and refresh

`:WebPreviewChanges [source-path|git-ref]` requests Changes explicitly. A relative
argument is a source file when it exists in Vim's working directory; Git refs
are resolved beside the main source. The command does not save or build the
manuscript. It compares saved files, so unsaved edits are absent.

With VimTeX, the adapter uses its main source, engine, source list and recorder
file. Without it, the main source/PDF are inferred from the current TeX file;
local dependencies can be collected from the adjacent `.fls` recorder file.
Hosts with other layouts should supply their complete file list and engine
through `webpreview#tex#open()` and the [editor protocol](editor-protocol.md).

Baseline choice is, in order:

1. An explicitly chosen baseline, retained for this session.
2. `<main>.review-base` beside the main source.
3. `<main>.base.tex` (or `.base.ltx`).
4. Git `HEAD`, only after an explicit Changes request with no other baseline.

An ordinary preview with no baseline convention stays Original and does not
launch a comparison. There is no scan for arbitrary `old`, `diff` or timestamped
files. No baseline is created or rewritten automatically.

After a manuscript build, hosts send the updated input list without a new
baseline request. Changes rebuilds in the background and preserves the reading
choice. An explicit request selects Changes when ready. Failures keep Original
and the last complete comparison, with the retained baseline identified.

## Ownership

WebPreview owns private comparison builds, Original/Changes, SyncTeX mapping
and comparison downloads. The source editor owns manuscript builds, save/conflict
policy, and opening a final PDF in an external application. Onesimus exposes
`:OnesimusDiff` with its freshness checks; the standalone command is
`:WebPreviewChanges`. Both use the same baseline convention.

Comparison output stays in session-owned temporary directories. Download
exports a separate `paper-changes.pdf`; it does not alter project files.
Closing the reader cancels builds and removes temporary output.
