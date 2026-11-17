import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, realpathSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createInterface } from 'node:readline';
const { chromium, webkit } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const packageRoot = resolve(fileURLToPath(new URL('..', import.meta.url)));
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(check, message) {
  const deadline = Date.now() + 20000;
  while (!await check()) { assert.ok(Date.now() < deadline, message); await pause(40); }
}
for (const [name, engine] of Object.entries({ chromium, webkit })) {
  const work = realpathSync(mkdtempSync(join(tmpdir(), 'webpreview-markdown-')));
  const file = join(work, 'draft.md');
  writeFileSync(file, 'The saved version stays intact.');
  writeFileSync(join(work, 'child.md'), 'A child draft.');
  writeFileSync(join(work, 'diagram.png'), Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII=', 'base64'));
  const text = '# A scientific draft\n\nA live paragraph for selection.\n\n'
    + 'Math $x_{a_b}^2$ and \\(E=mc^2\\).\n\n$$\nx^2+y^2=z^2\n$$\n\n'
    + '| Name | Value |\n| --- | --- |\n| Sample | 42 |\n\n- [x] Tested\n- [ ] To review\n\n'
    + 'Footnote[^one].\n\n[^one]: A measured observation.\n\n'
    + '[Heading](#a-scientific-draft) · [Child](child.md) · [External](https://example.com)\n\n'
    + '![Diagram](diagram.png)\n\n```tex\n$x^2$ <script>window.bad=1</script>\n```\n\n'
    + '<script>window.bad=2</script>\n\n[Unsafe](javascript:alert(1))\n\n'
    + '😀 前文 [漢字]^^(かんじ) 後文。\n\n[（半）形式的產物]^^((semi-)formal artefact)\n\n'
    + '[雙槽]^^(over)^_(under)\n\n'
    + Array.from({ length: 35 }, (_, i) => `## Passage ${i}\n\nReading paragraph ${i} with a stable source anchor.\n\n`).join('');
  const events = [], errors = [], diagnostics = [];
  const assets = process.env.MARKDOWN_ASSETS ? ['--markdown-assets', process.env.MARKDOWN_ASSETS] : [];
  const reader = spawn(process.env.PYTHON || 'python3', ['-m', 'webpreview', '--markdown', file, '--serve', ...assets],
    { env: { ...process.env, PYTHONPATH: join(packageRoot, 'src') } });
  const closed = new Promise(resolve => reader.once('close', resolve));
  createInterface({ input: reader.stdout }).on('line', line => events.push(JSON.parse(line)));
  reader.stderr.on('data', data => diagnostics.push(data.toString()));
  const send = message => reader.stdin.write(JSON.stringify(message) + '\n');
  const browser = await engine.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  try {
    await until(() => events.some(event => event.event === 'ready'), 'Markdown reader ready');
    const url = events.find(event => event.event === 'ready').url;
    const origin = new URL(url).origin;
    const unexpected = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/*', route => {
      if (new URL(route.request().url()).origin !== origin) {
        unexpected.push(route.request().url()); route.abort();
      } else route.continue();
    });
    send({ event: 'source', file, text });
    await page.goto(url);
    await page.locator('h1').filter({ hasText: 'A scientific draft' }).waitFor();
    assert.equal(await page.title(), 'draft.md · WebPreview');
    assert.equal(await page.locator('#state').textContent(), 'Live draft');
    assert.equal(await page.locator('#session').getAttribute('data-state'), 'connected');
    await page.locator('#options > summary').focus();
    await page.keyboard.press('Enter');
    await page.locator('#follow').focus();
    await page.keyboard.press('Escape');
    assert.equal(await page.locator('#options').getAttribute('open'), null);
    assert.ok(await page.locator('#options > summary').evaluate(node => node === document.activeElement), 'options return focus');
    await page.locator('#source').click();
    assert.equal(await page.locator('#source').textContent(), 'Cancel locate');
    await page.keyboard.press('Escape');
    assert.equal(await page.locator('#source').getAttribute('aria-pressed'), 'false');
    assert.ok(await page.locator('#source').evaluate(node => node === document.activeElement), 'cancel locate returns focus');
    assert.equal(await page.evaluate(() => {
      const event = new KeyboardEvent('keydown', { key: 'f', ctrlKey: true, bubbles: true, cancelable: true });
      document.dispatchEvent(event);
      return event.defaultPrevented;
    }), false, 'Markdown leaves native browser find available');
    assert.equal(await page.locator('table td').last().textContent(), '42');
    assert.equal(await page.locator('.katex').count(), 3);
    assert.equal(await page.locator('li input[checked]').count(), 1);
    assert.equal(await page.locator('.footnotes').count(), 1);
    assert.equal(await page.locator('pre code').textContent(), '$x^2$ <script>window.bad=1</script>\n');
    assert.equal(await page.evaluate(() => window.bad), undefined);
    assert.equal(await page.locator('a[href^="javascript:"]').count(), 0);
    await until(() => page.locator('img').evaluate(node => node.complete && node.naturalWidth === 1), 'local image loads');
    assert.deepEqual(unexpected, [], 'all renderer resources are local');
    assert.equal(await page.locator('a:has-text("External")').getAttribute('rel'), 'noopener noreferrer');
    assert.equal(await page.locator('a:has-text("Heading")').getAttribute('href'), '#a-scientific-draft');

    const annotation = page.locator('p').filter({ hasText: '😀 前文' });
    assert.equal(await annotation.locator('rt').textContent(), 'かんじ');
    assert.equal(await annotation.locator('ruby').evaluate(node => getComputedStyle(node).rubyPosition), 'over');
    assert.equal(await page.locator('.ia-ruby-double').count(), 1);
    await annotation.evaluate(node => {
      const range = document.createRange(); range.selectNodeContents(node);
      getSelection().removeAllRanges(); getSelection().addRange(range);
    });
    await page.locator('#source').click();
    await until(() => events.some(e => e.event === 'source'), 'annotation selection returned to Vim');
    assert.equal(events.find(e => e.event === 'source').text, '😀 前文 [漢字]^^(かんじ) 後文。');
    assert.equal(events.find(e => e.event === 'source').line, Number(await annotation.getAttribute('data-line')));
    await annotation.evaluate(node => {
      const base = node.querySelector('ruby').firstChild;
      const range = document.createRange(); range.setStart(base, 0); range.setEnd(base, 1);
      getSelection().removeAllRanges(); getSelection().addRange(range);
    });
    await page.locator('#source').click();
    await until(() => events.filter(e => e.event === 'source').length === 2, 'partial annotation selection');
    assert.equal(events.filter(e => e.event === 'source')[1].text, '漢', 'partial selection does not expand to the whole annotation');
    await annotation.locator('[data-source]').evaluate(node => {
      const range = document.createRange(); range.selectNodeContents(node);
      getSelection().removeAllRanges(); getSelection().addRange(range);
    });
    await page.locator('#source').click();
    await until(() => events.filter(e => e.event === 'source').length === 3, 'annotation-only selection');
    assert.equal(events.filter(e => e.event === 'source')[2].text, '[漢字]^^(かんじ)');
    await page.evaluate(() => getSelection().removeAllRanges());
    events.splice(0, events.length, ...events.filter(e => e.event !== 'source'));

    await page.evaluate(() => {
      const node = document.querySelector('p[data-line="3"]');
      const range = document.createRange(); range.selectNodeContents(node);
      getSelection().removeAllRanges(); getSelection().addRange(range);
    });
    await page.locator('#source').filter({ hasText: 'Select in source' }).waitFor();
    await page.locator('#source').click();
    await until(() => events.some(e => e.event === 'source'), 'selection returned to Vim');
    assert.equal(events.find(e => e.event === 'source').text, 'A live paragraph for selection.');
    assert.equal(events.find(e => e.event === 'source').line, 3);
    const changed = text.replace('A live paragraph for selection.', 'An updated paragraph.');
    send({ event: 'source', file, text: changed });
    await pause(700);
    assert.match(await page.locator('p[data-line="3"]').textContent(), /live paragraph/, 'selection defers refresh');
    assert.match(await page.locator('#state').textContent(), /Update pending/);
    await page.evaluate(() => getSelection().removeAllRanges());
    await page.locator('p[data-line="3"]').filter({ hasText: 'An updated paragraph.' }).waitFor();
    assert.equal(await page.locator('#state').textContent(), 'Live draft');

    await page.locator('#source').click();
    await page.locator('p[data-line="3"]').click();
    await until(() => events.filter(e => e.event === 'source').length === 2, 'point returned to Vim');
    const target = page.locator('h2[data-line]').filter({ hasText: /^Passage 15$/ });
    await target.scrollIntoViewIfNeeded();
    const before = await target.evaluate(node => node.getBoundingClientRect().top);
    send({ event: 'source', file, text: changed.replace('A scientific draft', 'A revised scientific draft') });
    await page.locator('h1').filter({ hasText: 'A revised scientific draft' }).waitFor({ state: 'attached' });
    const after = await target.evaluate(node => node.getBoundingClientRect().top);
    assert.ok(Math.abs(before - after) < 5, 'refresh keeps reading position');
    const point = await page.locator('h2[data-line]').last().getAttribute('data-line');
    await page.locator('#options').click(); await page.locator('#follow').check();
    await page.locator('#options').click();
    send({ event: 'cursor', line: Number(point), column: 1 });
    await until(() => page.locator('h2[data-line]').last().evaluate(node => node.hasAttribute('data-current') && node.getBoundingClientRect().top < innerHeight), 'follow cursor');

    await page.locator('a:has-text("Child")').click();
    await until(() => events.some(e => e.event === 'file'), 'linked document opens in editor');
    assert.equal(events.find(e => e.event === 'file').file, join(work, 'child.md'));
    send({ event: 'source', file: join(work, 'child.md'), text: '# A linked draft\n\nUnsaved content from Vim.' });
    await page.locator('h1').filter({ hasText: 'A linked draft' }).waitFor();
    assert.equal(page.url(), url, 'changing documents keeps the session URL');
    assert.equal(await page.title(), 'child.md · WebPreview');
    await page.reload();
    await page.locator('h1').filter({ hasText: 'A linked draft' }).waitFor();
    await page.route('**/state?*', route => route.abort());
    await page.locator('#state').filter({ hasText: 'Offline · retrying' }).waitFor();
    assert.equal(await page.locator('#session').getAttribute('data-state'), 'disconnected');
    assert.ok(await page.locator('#source').isDisabled());
    assert.ok(await page.locator('h1').isVisible(), 'offline draft stays readable');
    await page.unroute('**/state?*');
    await page.locator('#state').filter({ hasText: 'Live draft' }).waitFor();
    for (const width of [320, 390, 768]) {
      await page.setViewportSize({ width, height: 844 });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    }
    const mobile = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
    const touch = await mobile.newPage();
    await touch.goto(url);
    send({ event: 'source', file, text });
    await touch.locator('h1').filter({ hasText: 'A scientific draft' }).waitFor();
    assert.ok(await touch.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    for (const selector of ['#session', '#source', '#options > summary']) {
      const bounds = await touch.locator(selector).boundingBox();
      assert.ok(bounds.height >= 44 && bounds.width >= 44, selector + ' has a touch target');
    }
    assert.ok(await touch.locator('#state').isVisible(), 'draft state remains visible on phones');
    assert.equal(await touch.locator('ruby.ia-ruby-over').first().evaluate(node => getComputedStyle(node).rubyPosition), 'over');
    const sourceCount = events.filter(e => e.event === 'source').length;
    await touch.locator('#source').tap();
    await touch.locator('p[data-line="3"]').tap();
    await until(() => events.filter(e => e.event === 'source').length > sourceCount, 'touch locate in source');
    if (process.env.SCREENSHOT_DIR) await touch.screenshot({ path: join(process.env.SCREENSHOT_DIR, name + '-markdown-touch.png') });
    await mobile.close();
    if (process.env.SCREENSHOT_DIR) {
      await page.setViewportSize({ width: 1280, height: 900 });
      await page.evaluate(() => scrollTo(0, 0));
      await page.screenshot({ path: join(process.env.SCREENSHOT_DIR, name + '-markdown.png') });
      await page.emulateMedia({ colorScheme: 'dark' });
      await page.locator('#options > summary').click();
      await page.screenshot({ path: join(process.env.SCREENSHOT_DIR, name + '-markdown-dark.png') });
    }
    assert.deepEqual(errors, []);
    console.log(name + ': Markdown PASS');
  } finally {
    await browser.close(); reader.stdin.end();
    assert.equal(await closed, 0, diagnostics.join(''));
    rmSync(work, { recursive: true });
  }
}
