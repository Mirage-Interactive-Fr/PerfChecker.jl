// Browser regression for a real standalone normalized-metrics export.
// Run with: node normalized_browser.mjs EXPORTED_HTML [SCREENSHOT_PNG]
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import path from 'node:path';

const tooling = process.env.PERFCHECKER_PLOT_BROWSER_TOOLING;
const resolveFrom = tooling ? path.join(path.resolve(tooling), 'package.json') : import.meta.url;
const {chromium} = createRequire(resolveFrom)('playwright');
assert(process.argv.length >= 3 && process.argv.length <= 4,
  'Expected exported HTML and an optional screenshot destination');
const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.PERFCHECKER_CHROMIUM_EXECUTABLE || undefined,
});
try {
  const page = await browser.newPage({viewport: {width: 1100, height: 800}});
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(pathToFileURL(path.resolve(process.argv[2])).href);
  const toggles = page.locator('#controls input');
  assert.equal(await toggles.count(), 2, 'The regression fixture needs exactly two metrics');
  const points = page.locator('circle');
  const originalCount = await points.count();
  const selected = await points.first().getAttribute('aria-label');
  await points.first().focus();
  assert.equal(await page.locator('#readout').innerText(), selected);
  await toggles.first().uncheck();
  assert(await points.count() > 0 && await points.count() < originalCount);
  assert.equal(await page.locator('#readout').innerText(),
    'Hover or focus a visible point to read its value.');
  // Tab from the last toggle to the first still-visible measured point.
  await toggles.last().focus();
  await page.keyboard.press('Tab');
  assert.equal(await page.evaluate(() => document.activeElement.tagName), 'circle');
  const visible = await page.evaluate(() => document.activeElement.getAttribute('aria-label'));
  assert.notEqual(visible, selected);
  assert.equal(await page.locator('#readout').innerText(), visible);
  await toggles.last().uncheck();
  assert.equal(await page.locator('#readout').innerText(),
    'Hover or focus a visible point to read its value.');
  await toggles.first().check();
  await points.first().focus();
  assert.equal(await page.locator('#readout').innerText(), selected);
  assert.deepEqual(errors, []);
  if (process.argv[3]) await page.screenshot({path: path.resolve(process.argv[3])});
  console.log(JSON.stringify({status: 'passed', browser: browser.version(),
    originalCount, selected, keyboardVisiblePoint: visible, errors}));
} finally {
  await browser.close();
}
