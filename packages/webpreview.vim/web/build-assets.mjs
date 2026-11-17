// Build once for distribution; end users need Python, not Node or npm.
import { build } from 'esbuild';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, existsSync, readdirSync, copyFileSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const { values } = parseArgs({ options: {
  engine: { type: 'string', default: 'remark' }, extensions: { type: 'string' }, output: { type: 'string' }
} });
const entries = { remark: ['remark.mjs', 'remark-extensions.mjs'], 'markdown-it': ['markdown-it.mjs', 'markdown-extensions.mjs'] };
const entry = entries[values.engine];
if (!entry) throw Error('Choose --engine remark or --engine markdown-it');
const extensions = values.extensions ? resolve(values.extensions) : join(root, 'web', entry[1]);
const output = values.output ? resolve(values.output) : join(root, 'src/webpreview/assets/markdown-libraries.zip');
const work = mkdtempSync(join(tmpdir(), 'webpreview-markdown-build-'));
try {
  const result = await build({ entryPoints: [join(root, 'web', entry[0])], outfile: join(work, 'vendor.mjs'),
    alias: { 'webpreview:extensions': extensions,
      // Keep the AST API usable outside a DOM as well as in the browser.
      'decode-named-character-reference': createRequire(import.meta.url).resolve('decode-named-character-reference') },
    loader: { '.woff2': 'file', '.woff': 'file', '.ttf': 'file', '.svg': 'file', '.png': 'file' },
    bundle: true, minify: true, format: 'esm', platform: 'browser', metafile: true, legalComments: 'external' });
  const packages = {};
  for (const input of Object.keys(result.metafile.inputs)) {
    let folder = dirname(resolve(input));
    let manifest;
    while (folder !== dirname(folder)) {
      if (readdirSync(folder).includes('package.json')) {
        manifest = JSON.parse(readFileSync(join(folder, 'package.json')));
        if (manifest.name) break;
      }
      folder = dirname(folder);
    }
    if (!manifest?.name || manifest.private) continue;
    const versions = packages[manifest.name] ||= [];
    if (versions.includes(manifest.version)) continue;
    versions.push(manifest.version);
    for (const name of readdirSync(folder).filter(name => /^licen[cs]e(?:\.|$)/i.test(name))) {
      copyFileSync(join(folder, name), join(work, manifest.name.replaceAll('/', '_') + '-' + manifest.version + '-' + name));
    }
  }
  if (!existsSync(join(work, 'vendor.css'))) writeFileSync(join(work, 'vendor.css'), '');
  const katex = join(root, 'node_modules/katex/dist');
  copyFileSync(join(katex, 'katex.min.css'), join(work, 'katex.min.css'));
  mkdirSync(join(work, 'fonts'));
  for (const name of readdirSync(join(katex, 'fonts')).filter(name => name.endsWith('.woff2'))) {
    copyFileSync(join(katex, 'fonts', name), join(work, 'fonts', name));
  }
  // remark-math's npm tarball omits the repository-level license.
  if (packages['remark-math']) {
    copyFileSync(join(root, 'web/licenses/remark-math-6.0.0-license'), join(work, 'remark-math-6.0.0-license'));
  }
  const versions = { engine: values.engine, packages: Object.fromEntries(
    Object.entries(packages).sort(([left], [right]) => left.localeCompare(right))
      .map(([name, versions]) => [name, versions.sort()])) };
  writeFileSync(join(work, 'versions.json'), JSON.stringify(versions, null, 2));
  const zipped = spawnSync(process.env.PYTHON || 'python3', [join(root, 'web/archive.py'), work, output], { stdio: 'inherit' });
  if (zipped.status) throw Error('Cannot package browser libraries');
} finally { rmSync(work, { recursive: true, force: true }); }
