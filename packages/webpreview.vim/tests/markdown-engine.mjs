// Test the shipped bundle without npm dependencies or a browser.
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';

const root = fileURLToPath(new URL('..', import.meta.url));
const work = mkdtempSync(join(tmpdir(), 'webpreview-markdown-engine-'));
try {
  execFileSync(process.env.PYTHON || 'python3', ['-c',
    'import sys,zipfile\nwith zipfile.ZipFile(sys.argv[1]) as z: z.extractall(sys.argv[2])',
    process.argv[2] || join(root, 'src/webpreview/assets/markdown-libraries.zip'), work]);
  const { renderMarkdown, parseMarkdown, engine } = await import(pathToFileURL(join(work, 'vendor.mjs')));
  const render = text => renderMarkdown(text);
  const annotation = '[（半）形式的產物]^^((semi-)formal artefact)';
  assert.match(render(annotation), /data-source="\[（半）形式的產物\]/);
  assert.match(render(annotation), /<rt>\(semi-\)formal artefact<\/rt>/);
  assert.match(render('[漢字]^^(over)^_(under)'), /ia-ruby-double/);
  assert.match(readFileSync(join(work, 'vendor.css'), 'utf8'), /ruby-position/);
  for (const protectedText of ['`[word]^^(note)`', '```\n[word]^^(note)\n```',
    '$[word]^^(note)$', '$$\n[word]^^(note)\n$$', '\\([word]^^(note)\\)', '\\[word]^^(note)']) {
    assert.doesNotMatch(render(protectedText), /<ruby/);
  }
  const footnote = render('[Link](https://example.com) and note[^n].\n\n[^n]: [字]^^(zi)');
  assert.match(footnote, /class="footnote-ref"|data-footnote-ref/);
  assert.match(footnote, /data-line="3" data-end-line="3"/);
  assert.match(footnote, /<ruby/);
  const unsafe = render('[<script>]^^(<img src=x onerror=bad()>)');
  assert.doesNotMatch(unsafe.replace(/data-source="[^"]*"/g, ''), /<script|<img/);
  assert.match(unsafe, /&(?:lt;|#x3C;)script/);
  assert.match(render('- [x] [字]^^(zi)'), /class="task-list-item"/);
  assert.match(render('A paragraph.\n\n' + annotation), /data-line="3" data-end-line="3"/);
  if (engine === 'remark') {
    const source = '😀 &amp; 前文 [漢字]^^(かんじ) 後文。';
    const ast = parseMarkdown(source);
    assert.equal(ast.type, 'root');
    const node = ast.children[0].children.find(node => node.type === 'inlineAnnotation');
    assert.equal(node.model.source, '[漢字]^^(かんじ)');
    assert.equal(source.slice(node.position.start.offset, node.position.end.offset), node.model.source);
    assert.equal(source.slice(node.model.base.start, node.model.base.end), '漢字');
    assert.equal(ast.children[0].children[0].value, '😀 & 前文 ');
    assert.match(render('**[漢字]^^(かんじ)**'), /<strong><span data-source/);
    assert.match(render('[a *b*]^^(note)'), /data-source="\[a \*b\*\]/);
    assert.doesNotMatch(render('[link [字]^^(zi)](https://example.com)'), /<ruby/, 'link content remains host-owned');
  } else assert.ok(Array.isArray(parseMarkdown('# Heading')), 'markdown-it exposes its native token tree');
  console.log(engine + ' engine: PASS');
} finally { rmSync(work, { recursive: true, force: true }); }
