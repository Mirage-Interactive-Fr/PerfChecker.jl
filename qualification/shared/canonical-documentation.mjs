// Check the same plain-file routes used by the canonical SFTP host.
import assert from 'node:assert/strict';
import { readdir, readFile, access } from 'node:fs/promises';
import { resolve, join, relative, posix } from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { inflateSync } from 'node:zlib';
import { readExport } from '../../website/deploy-sftp.mjs';
const root = resolve(process.argv[2] ?? 'website/build/sftp');
const origin = 'https://perfchecker.mirageinteractive.fr';
const browserChecks = process.argv.includes('--browser');
const optionalOwners = [['linuxperf', 'PerfCheckerLinuxPerf'], ['likwid', 'PerfCheckerLIKWID'],
  ['makie', 'PerfCheckerMakie'], ['web', 'PerfCheckerWeb'], ['pluto', 'PerfCheckerPluto'],
  ['tachikoma', 'PerfCheckerTachikoma']];
const illustratedGuides = new Set(['interfaces/vscode.html', 'interfaces/vscode-configuration.html',
  'interfaces/vscode-workflows.html', 'interfaces/vscode-videos.html', 'mcp-advisor.html']);
function htmlIds(html) {
  return new Set([...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1].replaceAll('&amp;', '&')));
}
async function checkGuideRendering(route, html) {
  const source = await readFile(join('website/src', route.replace(/\.html$/, '.md')), 'utf8');
  const ids = htmlIds(html);
  let fence;
  for (const line of source.split('\n')) {
    const boundary = /^\s*(`{3,}|~{3,})/.exec(line);
    if (boundary) { fence = fence ? undefined : boundary[1][0]; continue; }
    if (fence) continue;
    const heading = /^#{1,6}\s+(.+?)\s*$/.exec(line);
    if (!heading) continue;
    // These guides deliberately use plain headings; Documenter preserves their case.
    const id = heading[1].replace(/\s+/g, '-');
    assert.ok(ids.has(id), `Guide heading did not render in ${route}: ${id}`);
  }
  const recordings = [...source.matchAll(/<DocMedia\b[^>]*\bvideo\b[^>]*\/?>/g)];
  assert.equal([...html.matchAll(/<video\b/g)].length, recordings.length,
    `Guide recording did not render as a video in ${route}`);
  for (const recording of recordings) {
    const track = /\bsubtitles="([^"]+)"/.exec(recording[0]);
    assert.ok(track && html.includes(track[1].slice(1)), `Missing caption track in ${route}`);
  }
}
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
  const pageIds = new Map();
  for (const file of pages) pageIds.set(file, htmlIds(await readFile(file, 'utf8')));
  if (info.version === '1.0.1') {
    for (const [slug, owner] of optionalOwners) {
      const provenance = await readFile(join(site, 'optional-api', `${slug}.toml`), 'utf8');
      assert.ok(provenance.includes(`source_revision = "${info.revision}"`), `${owner}: source revision`);
      assert.ok(provenance.includes(`owner = "${owner}"`), `${owner}: owner provenance`);
      const bindings = [...provenance.matchAll(/^\[\[bindings\]\]$/gm)].length;
      assert.ok(bindings > 0, `${owner}: real Docs records`);
      for (const page of ['public-api', 'full-api']) {
        const html = await readFile(join(site, 'optional-api', slug, `${page}.html`), 'utf8');
        assert.equal([...html.matchAll(/class="jldocstring custom-block"/g)].length, bindings,
          `${owner}/${page}: visible Julia docstring bodies`);
        assert.equal([...html.matchAll(new RegExp(`/blob/${info.revision}/packages/${owner}/`, 'g'))].length,
          bindings, `${owner}/${page}: exact source links`);
        assert.ok(!/```@(docs|autodocs|index)|\]\(@ref/.test(html), `${owner}: raw Julia directive`);
      }
      const inventory = await readFile(join(site, 'optional-api', `${slug}.inv`));
      let start = 0;
      for (let line = 0; line < 4; line++) start = inventory.indexOf(10, start) + 1;
      assert.ok(start > 0 && inventory.subarray(0, start).toString().startsWith('# Sphinx inventory version 2'));
      const rows = inflateSync(inventory.subarray(start)).toString().trim().split('\n');
      assert.ok(rows.some(row => /\sjl:\S+\s/.test(row)), `${owner}: Julia inventory entries`);
      for (const row of rows) {
        const match = /^(.*?)\s+(\S+:\S+)\s+(-?\d+)\s+(\S+)\s+(.*)$/.exec(row);
        assert.ok(match, `${owner}: inventory row`);
        const uri = match[4].endsWith('$') ? match[4].slice(0, -1) + match[1] : match[4];
        const target = new URL(uri, new URL('optional-api/', info.url));
        assert.ok(target.href.startsWith(new URL(`optional-api/${slug}/`, info.url).href));
        const file = join(site, decodeURIComponent(target.pathname.slice(info.base.length)));
        assert.ok(pageIds.has(file), `${owner}: inventory page ${uri}`);
        if (target.hash) assert.ok(pageIds.get(file).has(decodeURIComponent(target.hash.slice(1))),
          `${owner}: inventory fragment ${uri}`);
      }
    }
    console.log(`${channel}: six companion Public/Full APIs, Docs/source ownership and namespaced inventories passed`);
  }
  for (const file of pages) {
    const route = relative(site, file).replaceAll('\\', '/');
    const url = new URL(route === 'index.html' ? '' : route, info.url);
    const html = await readFile(file, 'utf8');
    if (!html.includes('rel="canonical"')) {
      // Exported plots are public HTML assets, not VitePress documentation pages.
      await access(join('website/src/public', route)); continue;
    }
    assert.ok(html.includes(`rel="canonical" href="${url.href}"`), `Incorrect canonical URL in ${route}`);
    if (illustratedGuides.has(route)) await checkGuideRendering(route, html);
    for (const match of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
      const target = new URL(match[1].replaceAll('&amp;', '&'), url);
      if (target.origin !== origin) continue;
      if (target.pathname === '/versions.js') continue; // Generated from remote inventory at publication.
      if (match[1].startsWith(origin) && target.pathname === '/' && info.base !== '/') continue; // Explicit link to the stable channel.
      // Explicit archived-version links intentionally leave the exported channel.
      if (match[1].startsWith(origin) && /^\/v\d+\.\d+\.\d+\//.test(target.pathname) &&
          (info.channel !== 'version' || !target.pathname.startsWith(info.base))) continue;
      assert.ok(target.pathname.startsWith(info.base), `Route escapes ${info.base}: ${target.pathname}`);
      const path = decodeURIComponent(target.pathname.slice(info.base.length));
      const extension = posix.extname(path);
      assert.ok(!path || path.endsWith('/') || extension, `Route requires rewrite rules: ${path}`);
      if (path === 'siteinfo.js') continue;
      const destination = join(site, !path || path.endsWith('/') ? path + 'index.html' : path);
      await access(destination);
      if (target.hash && pageIds.has(destination)) {
        const fragment = decodeURIComponent(target.hash.slice(1));
        assert.ok(pageIds.get(destination).has(fragment), `Missing fragment ${target.hash} from ${route} to ${target.pathname}`);
      }
    }
  }
  const sitemap = await readFile(join(site, 'sitemap.xml'), 'utf8');
  for (const match of sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)) assert.ok(match[1].startsWith(info.url));
  assert.ok((await readdir(join(site, 'assets/chunks'))).some(name => /hashmap|search|localSearch/i.test(name)), 'Missing local search index');
  console.log(`${channel}: ${pages.length} pages, canonical .html routes, internal fragments, guide headings, recordings, assets and sitemap passed`);
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
    if (info.version === '1.0.1') {
      for (const [slug, owner] of optionalOwners) {
        for (const api of ['public-api', 'full-api']) {
          await page.goto(new URL('reference/optional-api.html', local).href,
            { waitUntil: 'networkidle' });
          await page.locator('.vp-doc tbody tr').filter({ hasText: owner })
            .getByRole('link', { name: api === 'public-api' ? 'Public' : 'Full', exact: true }).click();
          await page.waitForURL(new URL(`optional-api/${slug}/${api}.html`, local).href);
          for (const width of [1440, 390]) {
            await page.setViewportSize({ width, height: 900 });
            assert.ok(await page.locator('.vp-doc .jldocstring').first().isVisible());
            assert.ok((await page.locator('.vp-doc .jldocstring').first().innerText()).length > 80);
            assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
          }
        }
      }
      await page.setViewportSize({ width: 1440, height: 900 });
      await page.locator('.VPNavBar').getByRole('button', { name: /Search/ }).click();
      await page.locator('.VPLocalSearchBox input').fill('CounterResult');
      await page.locator('.VPLocalSearchBox .result[href*="optional-api/"]').first().waitFor();
      await page.keyboard.press('Escape');
    }
    const illustrated = [
      ['interfaces/vscode.html', ['vscode-studio.png', 'vscode-suite-designer.png']],
      ['interfaces/vscode-workflows.html', ['vscode-results.png']],
      ['mcp-advisor.html', ['vscode-mcp-settings.png', 'vscode-advice-chat.png', 'vscode-implementation.png']],
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
    console.log(`${channel}: mobile navigation, search, version picker, six full-size VS Code screenshots and Supposition guide passed in Chromium`);
  } finally {
    await browser?.close(); const closed = once(server, 'exit'); server.kill('SIGTERM'); await closed;
  }
}
