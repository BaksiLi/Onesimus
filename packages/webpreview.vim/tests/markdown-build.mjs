// Exercise a user's extension outside the checkout, including its own CSS.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const root = fileURLToPath(new URL('..', import.meta.url));
const work = mkdtempSync(join(tmpdir(), 'webpreview-user-extension-'));
const archive = join(root, 'src/webpreview/assets/markdown-libraries.zip');
const original = readFileSync(archive);
try {
  writeFileSync(join(work, 'extension.mjs'), `
    import './note.css';
    export default function extend(md) {
      const fence = md.renderer.rules.fence;
      md.renderer.rules.fence = (tokens, i, ...args) => tokens[i].info === 'note'
        ? '<aside class="note">' + md.utils.escapeHtml(tokens[i].content) + '</aside>'
        : fence(tokens, i, ...args);
    }
  `);
  writeFileSync(join(work, 'note.css'), '.note { border-left: 3px solid teal; }');
  const output = join(work, 'custom.zip');
  execFileSync(process.execPath, [join(root, 'web/build-assets.mjs'),
    '--engine', 'markdown-it', '--extensions', join(work, 'extension.mjs'), '--output', output], { cwd: work });
  execFileSync(process.env.PYTHON || 'python3', ['-c',
    'import sys,zipfile\nwith zipfile.ZipFile(sys.argv[1]) as z: z.extractall(sys.argv[2])', output, join(work, 'assets')]);
  const { renderMarkdown } = await import(pathToFileURL(join(work, 'assets/vendor.mjs')));
  assert.equal(renderMarkdown('```note\n<special>\n```'),
    '<aside data-line="1" data-end-line="3" class="note">&lt;special&gt;\n</aside>');
  assert.doesNotMatch(renderMarkdown('[word]^^(note)'), /<ruby/, 'custom entry replaces the bundled extension');
  assert.match(renderMarkdown('$x^2$'), /class="katex"/, 'standard math is retained');
  assert.match(readFileSync(join(work, 'assets/vendor.css'), 'utf8'), /border-left/);
  writeFileSync(join(work, 'remark.mjs'), `
    import './note.css';
    export default function extend({ remark, rehype }) {
      remark.use(() => tree => {
        for (const node of tree.children) if (node.type === 'blockquote')
          node.data = { hProperties: { className: ['note'] } };
      });
      rehype.use(() => tree => { tree.children[0].properties['data-custom'] = 'yes'; });
    }
  `);
  const astOutput = join(work, 'remark.zip');
  execFileSync(process.execPath, [join(root, 'web/build-assets.mjs'),
    '--extensions', join(work, 'remark.mjs'), '--output', astOutput], { cwd: work });
  execFileSync(process.env.PYTHON || 'python3', ['-c',
    'import sys,zipfile\nwith zipfile.ZipFile(sys.argv[1]) as z: z.extractall(sys.argv[2])', astOutput, join(work, 'remark')]);
  const astEngine = await import(pathToFileURL(join(work, 'remark/vendor.mjs')));
  assert.match(astEngine.renderMarkdown('> A source-backed note.'), /class="note" data-line="1" data-end-line="1" data-custom="yes"/);
  assert.equal(astEngine.parseMarkdown('> A note.').children[0].type, 'blockquote');
  assert.doesNotMatch(astEngine.renderMarkdown('[word]^^(note)'), /<ruby/, 'custom remark entry replaces the annotation preset');
  writeFileSync(join(work, 'plain.mjs'), 'export default function extend(md) {}');
  const plain = join(work, 'plain.zip');
  execFileSync(process.execPath, [join(root, 'web/build-assets.mjs'),
    '--extensions', join(work, 'plain.mjs'), '--output', plain], { cwd: work });
  const css = execFileSync(process.env.PYTHON || 'python3', ['-c',
    'import sys,zipfile\nwith zipfile.ZipFile(sys.argv[1]) as z: sys.stdout.buffer.write(z.read("vendor.css"))', plain]);
  assert.equal(css.length, 0, 'an extension without styles still produces a complete archive');
  const repeated = join(work, 'repeated.zip');
  execFileSync(process.execPath, [join(root, 'web/build-assets.mjs'),
    '--extensions', join(work, 'plain.mjs'), '--output', repeated], { cwd: work });
  assert.deepEqual(readFileSync(repeated), readFileSync(plain), 'asset builds have stable bytes');
  const versions = JSON.parse(readFileSync(join(work, 'remark/versions.json'), 'utf8'));
  assert.equal(versions.engine, 'remark');
  assert.ok(versions.packages.katex.includes('0.19.1'), 'the direct formula renderer appears in the inventory');
  const entries = execFileSync(process.env.PYTHON || 'python3', ['-c',
    'import sys,zipfile\nwith zipfile.ZipFile(sys.argv[1]) as z: print("\\n".join(z.namelist()))', astOutput], { encoding: 'utf8' }).split('\n');
  for (const [name, releases] of Object.entries(versions.packages)) {
    for (const release of releases) {
      assert.ok(entries.some(entry => entry.startsWith(name.replaceAll('/', '_') + '-' + release + '-')),
        `bundled ${name}@${release} retains its license`);
    }
  }
  assert.deepEqual(readFileSync(archive), original, 'custom builds leave shipped assets intact');
  console.log('Custom Markdown build: PASS');
} finally { rmSync(work, { recursive: true, force: true }); }
