// Requires Playwright and its Chromium/WebKit browsers; no runtime JS dependencies.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, realpathSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createInterface } from 'node:readline';
const { chromium, webkit } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(check, message) {
  const end = Date.now() + 45000;
  while (!await check()) {
    assert.ok(Date.now() < end, message);
    await pause(50);
  }
}

for (const [name, engine] of Object.entries({ chromium, webkit })) {
  const work = realpathSync(mkdtempSync(join(tmpdir(), 'tex-preview-browser-')));
  const source = join(work, 'paper.tex'), base = join(work, 'base.tex');
  const text = '\\documentclass{article}\n\\begin{document}\n'
    + 'A revised sentence provides a clear navigation target.\n\n'
    + 'The unchanged paragraph provides a separate source anchor.\n\\newpage\n'
    + 'Second page for reading position.\n\\end{document}\n';
  writeFileSync(source, text);
  writeFileSync(base, text.replace('A revised sentence provides a clear navigation target.',
    'An earlier sentence.\nA deleted passage existed only in the baseline.'));
  function build() {
    const result = spawnSync('pdflatex', ['-synctex=1', '-interaction=batchmode', '-halt-on-error', 'paper.tex'], { cwd: work });
    assert.equal(result.status, 0, result.stdout.toString());
  }
  build();
  const events = [], errors = [], diagnostics = [];
  const reader = spawn(process.env.PYTHON || 'python3', ['-m', 'webpreview',
    '--pdf', join(work, 'paper.pdf'), '--editor', source, '--serve'], {
    env: { ...process.env, PYTHONPATH: join(root, 'src') },
  });
  const closed = new Promise(resolve => reader.once('close', resolve));
  createInterface({ input: reader.stdout }).on('line', line => events.push(JSON.parse(line)));
  reader.stderr.on('data', data => diagnostics.push(data.toString()));
  const send = event => reader.stdin.write(JSON.stringify(event) + '\n');
  const browser = await engine.launch();
  try {
    await until(() => events.some(e => e.event === 'ready'), 'reader ready');
    const { url, protocol } = events.find(e => e.event === 'ready');
    assert.equal(protocol, 1);
    const state = async () => (await fetch(url + 'state')).json();
    const page = await browser.newPage({ viewport: { width: 1420, height: 1000 } });
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(url);
    await page.locator('.textLayer span').first().waitFor();
    await page.locator('#refresh').filter({ hasText: 'Up to date' }).waitFor();
    console.log(name + ': reader loaded');
    assert.equal(await page.locator('#diff-state').count(), 0);
    const sourceBounds = await page.locator('#source').boundingBox(), findBounds = await page.locator('#find').boundingBox();
    assert.ok(findBounds.x > sourceBounds.x, 'Find is at the right');
    assert.equal(await page.locator('#source').textContent(), 'Locate in source');
    await page.locator('#session').click();
    assert.equal(await page.locator('#session').getAttribute('aria-expanded'), 'true');
    await page.locator('#change-close').click();
    assert.ok(await page.locator('#change-detail').isHidden(), 'details close button works');
    assert.equal(await page.locator('#session').getAttribute('aria-expanded'), 'false');
    assert.ok(await page.locator('#session').evaluate(node => node === document.activeElement), 'details return focus');
    await page.locator('#options > summary').focus();
    await page.keyboard.press('Enter');
    await page.locator('#auto').focus();
    await page.keyboard.press('Escape');
    assert.equal(await page.locator('#options').getAttribute('open'), null);
    assert.ok(await page.locator('#options > summary').evaluate(node => node === document.activeElement), 'options return focus');
    await page.locator('#source').click();
    assert.equal(await page.locator('#source').textContent(), 'Cancel locate');
    await page.keyboard.press('Escape');
    assert.equal(await page.locator('#source').getAttribute('aria-pressed'), 'false');
    await page.locator('#find').click();
    await page.keyboard.press('Escape');
    assert.ok(await page.locator('#find').evaluate(node => node === document.activeElement), 'find returns focus to its opener');
    await page.keyboard.press('Control+f');
    assert.ok(await page.locator('#query').evaluate(node => node === document.activeElement), 'Ctrl+F opens PDF search');
    await page.keyboard.press('Escape');

    const scale = () => page.locator('.page').first().evaluate(el => parseFloat(getComputedStyle(el).getPropertyValue('--scale-factor')));
    const widthScale = await scale();
    await page.setViewportSize({ width: 1100, height: 900 });
    await until(async () => await scale() < widthScale, 'Fit continuously responds to resize');
    assert.equal(await page.locator('#fit').getAttribute('aria-pressed'), 'true');
    await page.locator('#larger').click();
    assert.equal(await page.locator('#fit').getAttribute('aria-pressed'), 'false');
    const manual = await scale();
    await page.setViewportSize({ width: 1300, height: 900 });
    await pause(150);
    assert.equal(await scale(), manual, 'manual zoom stays fixed');
    await page.locator('#fit').click();
    assert.equal(await page.locator('#fit').getAttribute('aria-pressed'), 'true');
    await page.locator('#fit').click();
    assert.equal(await scale(), manual, 'Fit off restores manual zoom');
    console.log(name + ': zoom verified');

    send({ event: 'diff', base, files: [source], engine: '-pdf' });
    await until(async () => (await state()).diff.status === 'ready', 'latexdiff completed: ' + diagnostics.join(''));
    await page.locator('#changes[aria-pressed=true]').waitFor();
    await page.locator('#source:enabled').waitFor();
    console.log(name + ': changes loaded');
    assert.equal(await page.locator('#download').getAttribute('href'), './diff-download');
    await page.keyboard.press('Meta+f');
    await page.locator('#query').fill('revised sentence');
    await page.locator('#matches').filter({ hasText: /1 \/ 1/ }).waitFor();
    await page.keyboard.press('Escape');
    await page.evaluate(() => {
      const span = [...document.querySelectorAll('.textLayer span')].find(el => el.textContent.includes('revised'));
      const range = document.createRange();
      range.selectNodeContents(span);
      const selection = getSelection();
      selection.removeAllRanges(); selection.addRange(range);
    });
    await page.locator('#source').filter({ hasText: 'Select in source' }).waitFor();
    await page.locator('#source').click();
    await until(() => events.some(e => e.event === 'source'), 'Changes selection located');
    const selected = events.find(e => e.event === 'source');
    assert.equal(selected.file, source);
    assert.equal(selected.line, 3);
    assert.match(selected.text, /revised/);
    console.log(name + ': selection located');
    await page.evaluate(() => getSelection().removeAllRanges());

    await page.locator('#page').fill('2'); await page.locator('#page').press('Enter');
    await page.locator('#original').click();
    await page.locator('#original[aria-pressed=true]').waitFor();
    await page.locator('#changes').click();
    await page.locator('#changes[aria-pressed=true]').waitFor();
    assert.equal(await page.locator('#page').inputValue(), '2', 'versions retain their own view');
    await page.reload();
    await page.locator('#changes[aria-pressed=true]').waitFor();
    assert.equal(await page.locator('#page').inputValue(), '2');

    writeFileSync(source, text + '% A saved source-only change.\n');
    await page.locator('#refresh').filter({ hasText: 'Needs build' }).waitFor();
    assert.ok(!(await page.locator('header').innerText()).includes('Up to date'));
    await page.locator('#refresh').click();
    await page.locator('#change-text').filter({ hasText: /Build the paper/ }).waitFor();
    await page.keyboard.press('Escape');
    build();
    send({ event: 'diff', files: [source] });
    await page.locator('#refresh').filter({ hasText: 'Up to date' }).waitFor();
    assert.equal(await page.locator('#changes').getAttribute('aria-pressed'), 'true', 'build preserves reading choice');

    await page.route('**/state?*', route => route.abort());
    await page.locator('#refresh').filter({ hasText: 'Offline' }).waitFor();
    assert.equal(await page.locator('#session').getAttribute('data-state'), 'disconnected');
    assert.ok(await page.locator('#source').isDisabled());
    assert.ok(await page.locator('.page').first().isVisible(), 'offline PDF stays readable');
    await page.unroute('**/state?*');
    await page.locator('#refresh').filter({ hasText: 'Up to date' }).waitFor();
    assert.ok(!(await page.locator('#status').textContent()).includes('disconnected'), 'reconnecting clears the offline notice');

    for (const width of [320, 390, 768, 1360]) {
      await page.setViewportSize({ width, height: 900 });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'no toolbar overflow');
      await page.locator('#find').click();
      await page.locator('#query').fill('missing phrase');
      await page.locator('#matches').filter({ hasText: 'No matches' }).waitFor();
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'search fits narrow screens');
      await page.keyboard.press('Escape');
    }
    const mobile = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
    const touch = await mobile.newPage();
    await touch.goto(url);
    await touch.locator('.textLayer span').first().waitFor();
    const fit = await touch.locator('#fit').boundingBox();
    assert.ok(fit.height >= 44, 'touch targets remain thumb sized');
    for (const button of ['#session', '#original', '#changes', '#find', '#options > summary']) {
      const bounds = await touch.locator(button).boundingBox();
      assert.ok(bounds.width >= 44 && bounds.height >= 44, button + ' has a touch target');
    }
    await touch.locator('#fit').tap();
    assert.equal(await touch.locator('#fit').getAttribute('aria-pressed'), 'false');
    await touch.locator('#fit').tap();
    assert.equal(await touch.locator('#fit').getAttribute('aria-pressed'), 'true');
    await touch.locator('#options > summary').tap();
    assert.ok(await touch.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'options fit the viewport');
    const downloadBounds = await touch.locator('#download').boundingBox();
    assert.ok(downloadBounds.x >= 0 && downloadBounds.x + downloadBounds.width <= 390, 'download action fits the viewport');
    await touch.locator('#options > summary').tap();
    if (process.env.SCREENSHOT_DIR) {
      await touch.screenshot({ path: join(process.env.SCREENSHOT_DIR, name + '-mobile.png') });
      await page.screenshot({ path: join(process.env.SCREENSHOT_DIR, name + '-desktop.png') });
    }
    assert.ok((await touch.locator('header').boundingBox()).height < 120, 'phone toolbar uses two rows');
    if (process.env.SCREENSHOT_DIR) {
      await touch.locator('#find').tap();
      await touch.locator('#query').fill('revised');
      await touch.locator('#matches').filter({ hasText: /1 \/ 1/ }).waitFor();
      await touch.screenshot({ path: join(process.env.SCREENSHOT_DIR, name + '-mobile-find.png') });
      await page.emulateMedia({ colorScheme: 'dark' });
      await page.locator('#options > summary').click();
      await page.screenshot({ path: join(process.env.SCREENSHOT_DIR, name + '-dark.png') });
    }
    await mobile.close();
    assert.deepEqual(errors, []);
    console.log(name + ': PASS');
  } finally {
    await browser.close();
    reader.stdin.end();
    assert.equal(await closed, 0, diagnostics.join(''));
    rmSync(work, { recursive: true });
  }
}
