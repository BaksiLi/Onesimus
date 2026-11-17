# Markdown engines and extensions

The shipped engine is **remark-parse 11.0.0**, with GFM/math and **KaTeX 0.19.1**.
Its pipeline is source → MDAST → HAST → HTML. **markdown-it 15.0.3** is an optional
build profile. Each archive contains one parser; readers do not load both or
translate plugins between them.

The generated module exports `parseMarkdown(text)` and `renderMarkdown(text)`.
`parseMarkdown` returns the transformed MDAST in remark, or native tokens in
markdown-it. Source positions stay available before HTML rendering. Extensions
are synchronous build-time JavaScript, chosen locally; documents cannot load
plugins.

## remark

An extension exports `extend({ remark, rehype })`, receiving native unified
processors. Use `.use()` for MDAST or HAST plugins. CSS imports are bundled too.
Standard GFM/math support remains installed. A custom entry replaces the
annotation preset; copy [the supplied entry](../web/remark-extensions.mjs) to
retain it.

For example, install `remark-directive` and `unist-util-visit` in your extension
directory, then render `:::note` containers:

```js
import directive from 'remark-directive';
import { visit } from 'unist-util-visit';
import './preview.css';

export default function extend({ remark }) {
  remark.use(directive).use(function notes() {
    return tree => visit(tree, 'containerDirective', node => {
      if (node.name === 'note') node.data = {
        ...node.data, hName: 'aside', hProperties: { className: ['note'] }
      };
    });
  });
}
```

After `npm ci` in the package, build an archive:

```sh
node web/build-assets.mjs --extensions ~/my-preview/extensions.mjs --output ~/my-preview/markdown.zip
```

Configure Vim before opening the session:

```vim
let g:webpreview_markdown_assets = expand('~/my-preview/markdown.zip')
```

The CLI accepts `--markdown-assets /path/custom.zip`. Stop and reopen the
Markdown preview after changing this setting. Node/npm are only build tools;
session ownership, unsaved drafts and source navigation do not depend on them.

## markdown-it

Use a module exporting `extend(md)` with markdown-it's native plugin API:

```js
import container from 'markdown-it-container';
import './preview.css';
export default function extend(md) { md.use(container, 'note'); }
```

Choose the engine explicitly:

```sh
node web/build-assets.mjs --engine markdown-it --extensions ~/my-preview/extensions.mjs --output ~/my-preview/markdown.zip
```

Omit `--extensions` for [the supplied annotation preset](../web/markdown-extensions.mjs).
The two engines have intentional dialect differences; they do not promise
identical syntax or ASTs. See [test scope](testing.md).

## Annotation and source ownership

Inline Annotation is the default extension and a working integration example.
`[漢字]^^(かんじ)` adds ruby. Two-slot annotations and balanced parentheses are
supported. Code, formulas and link labels retain their own syntax.

Keep MDAST `position` on transformed nodes or `token.map` on markdown-it blocks.
Rendered block elements inherit source-line navigation. A `data-source` wrapper
can retain original syntax for transformed inline content. Selecting a complete
fragment recovers that syntax before Vim's unique literal-match check. Partial
or ambiguous selections remain literal. This is an atomic source fragment, not
a character source map. Never preprocess a draft and reuse its old positions.

The remark adapter retains an `inlineAnnotation` node with its core model and
exact UTF-16 ranges. Shared fixtures cover escapes and astral characters.
Selecting an entire annotation recovers its original Markdown; partial selection
does not expand to the whole annotation.

Keep raw HTML literal, escape generated text/attributes, and bundle local assets.
The reader's resource policy remains in force. Interactive DOM widgets require
their own integration; a parser extension alone does not manage widget lifetime.
