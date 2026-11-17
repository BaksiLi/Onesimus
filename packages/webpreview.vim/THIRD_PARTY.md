# Third-party material

WebPreview's own code is MIT-licensed. The materials below keep their upstream
licenses; they are included rather than fetched from a CDN at runtime.

| Material | Source and version | Notices |
| --- | --- | --- |
| PDF.js | npm `pdfjs-dist` 5.4.624, Mozilla PDF.js | `src/webpreview/assets/pdfjs-5.4.624.zip`: `LICENSE` and licenses in `cmaps/`, `standard_fonts/`, `wasm/` |
| Markdown, math and annotation libraries | npm packages pinned in `package-lock.json` | `markdown-libraries.zip`: `versions.json`, versioned license files and `vendor.mjs.LEGAL.txt` |
| CommonMark examples | CommonMark specification 0.31.2, John MacFarlane | `tests/fixtures/commonmark/LICENSE`; specification data is CC BY-SA 4.0 |

The default Markdown archive contains remark, unified, GFM/math, KaTeX and
Inline Annotation, with their transitive runtime modules. The optional
markdown-it archive contains the selected engine and its plugins. The inventory
inside each archive describes that build, not every development dependency.

`web/build-pdfjs.py` records the upstream download URL and SHA-512 integrity.
`web/build-assets.mjs` collects module versions and license files from the
locked npm installation. Rebuild commands and verification are in
[CONTRIBUTING.md](CONTRIBUTING.md).

`remark-math@6.0.0` omits its repository-level MIT license from the npm tarball.
The unchanged notice is retained at `web/licenses/remark-math-6.0.0-license` and
included in the built archive. It comes from the package's upstream `gitHead`,
`d5d0660b150810a535bbb07eac6cc96a4510aa24`, at
<https://github.com/remarkjs/remark-math/blob/d5d0660b150810a535bbb07eac6cc96a4510aa24/license>.
