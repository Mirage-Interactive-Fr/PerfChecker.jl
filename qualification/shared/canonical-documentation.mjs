// Check the same plain-file routes used by the canonical SFTP host.
import assert from 'node:assert/strict';
import { readdir, readFile, access } from 'node:fs/promises';
import { resolve, join, relative, posix } from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { readExport } from '../../website/deploy-sftp.mjs';
const root = resolve(process.argv[2] ?? 'website/build/sftp');
const origin = 'https://perfchecker.mirageinteractive.fr';
const browserChecks = process.argv.includes('--browser');
async function enumerate(directory) {
  const paths = [];
  for (const item of await readdir(directory, { withFileTypes: true })) {
    if (item.isDirectory()) paths.push(...await enumerate(join(directory, item.name)));
    else if (item.name.endsWith('.html')) paths.push(join(directory, item.name));
  }
  return paths;
}
for (const channel of await readdir(root)) {
  const site = join(root, channel, 'site');
  const info = JSON.parse(await readFile(join(site, 'build-info.json'), 'utf8'));
  assert.equal(info.channel, channel); assert.equal(info.url, origin + info.base);
  const exportArtifact = await readExport(site, info.channel, info.revision);
  console.log(`${channel}: SFTP export preflight passed (${exportArtifact.files.length} files)`);
  const pages = await enumerate(site);
  for (const file of pages) {
    const route = relative(site, file).replaceAll('\\', '/');
    const url = new URL(route === 'index.html' ? '' : route, info.url);
    const html = await readFile(file, 'utf8');
    if (!html.includes('rel="canonical"')) {
      // Exported plots are public HTML assets, not VitePress documentation pages.
      await access(join('website/src/public', route)); continue;
    }
    assert.ok(html.includes(`rel="canonical" href="${url.href}"`), `Incorrect canonical URL in ${route}`);
    for (const match of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
      const target = new URL(match[1].replaceAll('&amp;', '&'), url);
      if (target.origin !== origin) continue;
      if (target.pathname === '/versions.js') continue; // Generated from remote inventory at publication.
      if (match[1].startsWith(origin) && target.pathname === '/' && info.base !== '/') continue; // Explicit link to the stable channel.
      assert.ok(target.pathname.startsWith(info.base), `Route escapes ${info.base}: ${target.pathname}`);
      const path = decodeURIComponent(target.pathname.slice(info.base.length));
      if (!path) continue;
      const extension = posix.extname(path);
      assert.ok(path.endsWith('/') || extension, `Route requires rewrite rules: ${path}`);
      if (path === 'siteinfo.js') continue;
      await access(join(site, path.endsWith('/') ? path + 'index.html' : path));
    }
  }
  const sitemap = await readFile(join(site, 'sitemap.xml'), 'utf8');
  for (const match of sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)) assert.ok(match[1].startsWith(info.url));
  assert.ok((await readdir(join(site, 'assets/chunks'))).some(name => /hashmap|search|localSearch/i.test(name)), 'Missing local search index');
  console.log(`${channel}: ${pages.length} pages, canonical .html routes, assets and sitemap passed`);
  if (!browserChecks) continue;
  const { chromium } = await import('playwright');
  const server = spawn(process.execPath, ['website/preview.mjs'], { env: { ...process.env, PORT: '0',
    PERFCHECKER_PREVIEW_SOURCE: site, PERFCHECKER_DOCS_BASE: info.base, PERFCHECKER_PREVIEW_CLEAN_URLS: 'false' },
    stdio: ['ignore', 'pipe', 'pipe'] });
  let browser;
  try {
    const local = await new Promise((ok, fail) => {
      const timer = setTimeout(() => fail(new Error('Preview did not start')), 20000);
      server.once('error', error => { clearTimeout(timer); fail(error); });
      server.once('exit', () => { clearTimeout(timer); fail(new Error('Preview exited before readiness')); });
      server.stdout.on('data', bytes => {
        const match = bytes.toString().match(/http:\/\/127\.0\.0\.1:\d+\/[^\s]*/);
        if (match) { clearTimeout(timer); ok(match[0]); }
      });
    });
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 390, height: 900 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('response', response => {
      if (response.url().startsWith(new URL(local).origin) && response.status() >= 400) errors.push(response.url());
    });
    await page.goto(local, { waitUntil: 'networkidle' });
    assert.ok(await page.locator('.VPNavBarTitle img').evaluate(image => image.complete && image.naturalWidth > 0));
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.locator('.VPNavBar').getByRole('link', { name: 'Manual', exact: true }).click();
    await page.waitForURL('**/guide/overview.html');
    await page.reload({ waitUntil: 'networkidle' });
    await page.locator('.VPNavBar').getByRole('button', { name: /Search/ }).click();
    await page.locator('.VPLocalSearchBox input').fill('implementation');
    const result = page.locator('.VPLocalSearchBox .result').first(); await result.waitFor();
    const href = await result.getAttribute('href');
    assert.ok(new URL(href, local).pathname.startsWith(info.base) && new URL(href, local).pathname.endsWith('.html'));
    await result.click(); await page.waitForLoadState('networkidle');
    const illustrated = [
      ['interfaces/vscode.html', ['vscode-studio.png', 'vscode-suite-designer.png']],
      ['interfaces/vscode-workflows.html', ['vscode-results.png']],
      ['mcp-advisor.html', ['vscode-mcp-settings.png', 'vscode-implementation.png']],
    ];
    for (const [route, screenshots] of illustrated) {
      await page.goto(new URL(route, local).href, { waitUntil: 'networkidle' });
      for (const screenshot of screenshots) {
        const image = page.locator(`.vp-doc img[src$="/${screenshot}"]`);
        await image.scrollIntoViewIfNeeded();
        await image.evaluate(image => image.decode());
        assert.ok(await image.evaluate(image => image.naturalWidth >= 1200 && image.naturalHeight > 500));
        assert.ok((await image.getAttribute('alt'))?.length > 40);
        const imageUrl = new URL(await image.getAttribute('src'), local);
        assert.ok(imageUrl.pathname.startsWith(info.base));
        const fullSize = await image.locator('..').getAttribute('href');
        assert.equal(new URL(fullSize, local).href, imageUrl.href, 'Screenshots must open their full-size source');
        assert.equal((await page.request.get(imageUrl.href)).status(), 200);
      }
      await page.setViewportSize({ width: 390, height: 900 });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), route);
      await page.reload({ waitUntil: 'networkidle' });
      assert.ok(await page.locator('h1').isVisible());
      await page.setViewportSize({ width: 1440, height: 900 });
    }
    await page.goto(new URL('reference/extensions.html', local).href, { waitUntil: 'networkidle' });
    const text = await page.locator('.vp-doc').innerText();
    assert.match(text, /64-bit/); assert.match(text, /PropCheck/); assert.match(text, /corpus/);
    const label = channel === 'dev' ? 'dev' : `v${info.version}`;
    const picker = page.locator('.VPNavBar .VPVersionPicker');
    await picker.getByRole('button', { name: label, exact: true }).click();
    await picker.getByRole('link', { name: label, exact: true }).waitFor({ state: 'visible' });
    assert.deepEqual(errors, []);
    console.log(`${channel}: mobile navigation, search, version picker, five full-size VS Code screenshots and Supposition guide passed in Chromium`);
  } finally {
    await browser?.close(); const closed = once(server, 'exit'); server.kill('SIGTERM'); await closed;
  }
}
