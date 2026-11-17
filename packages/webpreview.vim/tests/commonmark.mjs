import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = fileURLToPath(new URL('..', import.meta.url));
const work = mkdtempSync(join(tmpdir(), 'webpreview-commonmark-'));
const sections = new Set(['Backslash escapes', 'Entity and numeric character references',
  'ATX headings', 'Fenced code blocks', 'Code spans']);
const examples = JSON.parse(readFileSync(join(root, 'tests/fixtures/commonmark/spec-0.31.2.json'), 'utf8'))
  .filter(example => sections.has(example.section));
let browser;
try {
  execFileSync(process.env.PYTHON || 'python3', ['-c',
    'import sys,zipfile\nwith zipfile.ZipFile(sys.argv[1]) as archive: archive.extractall(sys.argv[2])',
    process.argv[2] || join(root, 'src/webpreview/assets/markdown-libraries.zip'), work]);
  const { renderMarkdown, parseMarkdown, engine } = await import(pathToFileURL(join(work, 'vendor.mjs')));
  const rendered = examples.map(example => ({ ...example, actual: renderMarkdown(example.markdown) }));
  browser = await chromium.launch();
  const page = await browser.newPage();
  const results = await page.evaluate(({ examples, engine }) => {
    function normalize(html) {
      const template = document.createElement('template');
      template.innerHTML = html;
      function tree(node, verbatim = false) {
        if (node.nodeType === Node.TEXT_NODE) {
          return verbatim || /^(p|h[1-6]|a|em|strong)$/.test(node.parentNode.localName)
            || node.textContent.trim() ? node.textContent : null;
        }
        const tag = node.localName || 'root';
        const attributes = [...(node.attributes || [])]
          .filter(attribute => !/^data-(line|end-line|file)$/.test(attribute.name)
            && !['target', 'rel'].includes(attribute.name)
            && !(attribute.name === 'id' && /^h[1-6]$/.test(tag)))
          .map(attribute => [attribute.name, attribute.value]).sort();
        return [tag, attributes, [...node.childNodes]
          .map(child => tree(child, verbatim || tag === 'pre' || tag === 'code'))
          .filter(child => child !== null)];
      }
      return tree(template.content);
    }
    return examples.map(example => {
      const document = new DOMParser().parseFromString(example.actual, 'text/html');
      if ([21, 31, 344].includes(example.example)) {
        const markdownItText = { 21: '<a href="/bar/)">', 31: '<a href="öö.html">', 344: '<a href="">' };
        return { example: example.example,
          actual: [document.body.textContent.trim(), document.querySelectorAll('a').length],
          expected: [engine === 'remark' ? example.markdown.trim() : markdownItText[example.example], 0] };
      }
      if (example.example === 12 && engine === 'remark') {
        const formulas = [...document.querySelectorAll('math annotation')].map(node => node.textContent);
        for (const formula of document.querySelectorAll('.katex-display, .katex')) formula.remove();
        return { example: example.example,
          actual: [formulas, document.body.textContent.trim()],
          expected: [['', '\\\\'], '!\"#$%&\'*+,-./:;<=>?@^_`{|}~'] };
      }
      return { example: example.example, actual: normalize(example.actual), expected: normalize(example.html) };
    });
  }, { examples: rendered, engine });
  const failures = [];
  for (const result of results) {
    try { assert.deepEqual(result.actual, result.expected); }
    catch (error) { failures.push(`Example ${result.example}: ${error.message}`); }
  }
  for (const example of examples) {
    const parsed = parseMarkdown(example.markdown);
    if (engine === 'remark') {
      const check = node => {
        if (node.position) {
          const { start, end } = node.position;
          assert.ok(start.offset >= 0 && end.offset <= example.markdown.length && start.offset <= end.offset,
            `Example ${example.example}: ${node.type} has invalid source offsets`);
          for (const point of [start, end]) {
            const prefix = example.markdown.slice(0, point.offset).split('\n');
            assert.equal(point.line, prefix.length);
            assert.equal(point.column, prefix.at(-1).length + 1);
          }
        }
        for (const child of node.children || []) check(child);
      };
      check(parsed);
    } else {
      for (const token of parsed) if (token.map) {
        assert.ok(token.map[0] >= 0 && token.map[0] < token.map[1]
          && token.map[1] <= example.markdown.split('\n').length,
        `Example ${example.example}: ${token.type} has invalid source lines`);
      }
    }
  }
  assert.equal(failures.length, 0, failures.join('\n'));
  const policies = engine === 'remark' ? 4 : 3;
  console.log(`${engine}: ${examples.length - policies} CommonMark expectations + ${policies} explicit product-policy cases; all source ranges passed`);
} finally {
  await browser?.close();
  rmSync(work, { recursive: true, force: true });
}
