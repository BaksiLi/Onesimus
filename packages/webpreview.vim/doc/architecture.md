# Product and architecture

WebPreview.vim is **a unified preview interface for Markdown and LaTeX in Vim**.
Its task is to read a draft, understand which revision is visible, locate or
select its source, and continue editing.

## Responsibilities

| Layer | Owns |
| --- | --- |
| Editor host | Buffers, saving, conflict review, manuscript builds and mappings |
| WebPreview | Preview commands, browser opening, reading controls, session lifetime and source-navigation handoff |
| Format adapter | Rendered content, revision identity and source coordinates |
| Language/typesetter | Markdown syntax, KaTeX formulas, TeX layout and Cogitatum semantics |

Markdown displays unsaved buffer snapshots. TeX displays the last complete
compiled PDF. They share reading actions, not freshness semantics.

PDF page layout belongs to TeX. Markdown prose width and CSS belong to its
renderer. Common controls can share labels, spacing and focus behavior without
changing manuscript typography. latexdiff builds a private comparison artifact;
it never replaces the manuscript build or overwrites its output.

## Code boundaries

| Location | Responsibility |
| --- | --- |
| `plugin/`, `autoload/` | Vim commands, process ownership, snapshots and source selection |
| `src/webpreview/session.py` | Loopback HTTP, token/Host boundary, page presence and pipe-owned lifetime |
| `src/webpreview/reader.py` | CLI, complete PDF publication, SyncTeX and revision comparisons |
| `src/webpreview/markdown.py` | Draft snapshots, source ranges and document-local resources |
| `src/webpreview/sourcemap.py` | Comparison lines mapped back to surviving source |
| `src/webpreview/assets/` | Browser readers and shipped libraries |
| `web/` | Build-time Markdown pipelines, native extensions and asset packaging |

The shared session does not import either format implementation. Readers supply
their state, resources, inverse navigation, refresh and shutdown behavior.
Markdown does not depend on the PDF implementation. The Python modules are
internal; the Vim commands/hooks and [editor protocol](editor-protocol.md) are
the integration surfaces.

Syntax extensions use the chosen Markdown engine's native API. A new document
format needs its own rendering and source-coordinate contract. There is no
generic plugin registry or second save/build system.

## Markdown and Cogitatum

Markdown provides document formatting. Cogitatum adds explicitly authored inquiry
structure. Ordinary headings, lists and paragraphs do not acquire argument roles
implicitly.

| Source | Current behavior |
| --- | --- |
| `.md` | Whole-document Markdown preview |
| `cog` fence in `.md` | Code in Markdown; `:WebPreviewInquiry` opens its semantic preview |
| `.cog.md` / `.cog` with the Cogitatum filetype | Dedicated inquiry, with Reading/Map supplied by vim-cogitatum |

Cogitatum shares the Vim entry, browser settings and literal source-selection
rules. Its browser UI and transport remain host-owned. Terminal Reading/Map stay
with vim-cogitatum. Shared prose rendering or inline semantic blocks are possible
presentation integrations, not completed features.

Reading must preserve complete source and source coordinates. An argument graph
alone cannot reconstruct the document. Cogitatum's compiler owns semantics;
WebPreview does not reinterpret ordinary Markdown as inquiry structure.

## Relationship to existing tools

In Onesimus, the Markdown reader replaces `markdown-preview.nvim` and the PDF
reader becomes the usual preview destination. An external PDF app stays
available. VimTeX, TeX, SyncTeX, PDF.js, KaTeX and Cogitatum remain collaborators.

The benefit is an integrated source-aware workflow: unsaved Markdown, compiled
and comparison PDFs, explicit source selection, local browser assets without a
Node runtime, and sessions owned by the editing Vim. This is not a claim to
outperform the underlying rendering engines.

Feature parity with `markdown-preview.nvim` is not the goal. Diagram integrations
and automatic table of contents are absent. Diagram fences remain code and
author HTML is literal. New features should solve a writing task and retain
source navigation; prefer content extensions to a larger common reader.
