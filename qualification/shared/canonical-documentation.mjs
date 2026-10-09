// Check the same plain-file routes used by the canonical SFTP host.
import assert from 'node:assert/strict';
import { readdir, readFile, access, mkdir, writeFile } from 'node:fs/promises';
import { resolve, join, relative, posix } from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { inflateSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { readExport } from '../../website/deploy-sftp.mjs';
import { checkRecordedInteractions } from './recorded-plots.mjs';
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
const channels = await readdir(root);
const interactionChannel = channels.includes('dev') ? 'dev' : channels.includes('stable') ? 'stable' : channels[0];
for (const channel of channels) {
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
      const bindings = provenance.split(/^\[\[bindings\]\]\r?\n/m).slice(1)
        .map(block => block.split(/^\[/m)[0]);
      assert.ok(bindings.length > 0, `${owner}: real Docs records`);
      assert.ok(bindings.every(block => /^public_api = (?:true|false)$/m.test(block)),
        `${owner}: every Docs record declares its API page`);
      for (const page of ['public-api', 'full-api']) {
        const html = await readFile(join(site, 'optional-api', slug, `${page}.html`), 'utf8');
        const expected = page === 'full-api' ? bindings.length :
          bindings.filter(block => /^public_api = true$/m.test(block)).length;
        assert.equal([...html.matchAll(/class="jldocstring custom-block"/g)].length, expected,
          `${owner}/${page}: visible Julia docstring bodies`);
        assert.equal([...html.matchAll(new RegExp(`/blob/${info.revision}/packages/${owner}/`, 'g'))].length,
          expected, `${owner}/${page}: exact source links`);
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
  let browser, page;
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
    page = await browser.newPage({ viewport: { width: 390, height: 900 } });
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
          const docstring = page.locator('.vp-doc .jldocstring').first();
          try {
            await docstring.waitFor({ state: 'visible' });
          } catch (cause) {
            throw new Error(`${channel}: ${owner}/${api} did not display its docstrings after navigation to ${page.url()}`, { cause });
          }
          for (const width of [1440, 390]) {
            await page.setViewportSize({ width, height: 900 });
            assert.ok(await docstring.isVisible(), `${channel}: ${owner}/${api} docstrings hidden at ${width}px`);
            assert.ok((await docstring.innerText()).length > 80, `${channel}: ${owner}/${api} docstring body missing at ${width}px`);
            assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1),
              `${channel}: ${owner}/${api} overflows at ${width}px`);
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
    if (channel === interactionChannel) {
      const catalog = JSON.parse(await readFile(join(site, 'examples/real-packages/containers/catalog.json'), 'utf8'));
      const marker = catalog.interactive_export;
      if (info.version === '1.0.1') assert.ok(marker, 'Core 1.0.1 requires the published native interactive exports');
      if (marker) {
        assert.equal(marker.renderer, 'PerfChecker.performance_plot_html');
        assert.equal(marker.input_kind, 'published_serialized_plot');
        const digest = bytes => createHash('sha256').update(bytes).digest('hex');
        const guided = marker.selection === 'guided_examples', kinds = new Set();
        if (info.version === '1.0.1') assert.ok(guided, 'Guided native examples must be selected deliberately');
        let nativeExports = 0;
        for (const packageName of ['datastructures', 'containers', 'oxygen', 'oxygen-features',
          'datastructures-profiles', 'oxygen-profiles']) {
          const directory = join(site, 'examples/real-packages', packageName);
          const recorded = JSON.parse(await readFile(join(directory, 'catalog.json'), 'utf8'));
          assert.equal(recorded.interactive_export?.renderer, marker.renderer);
          assert.equal(recorded.interactive_export?.companion_version, info.version,
            `${packageName}: public renderer must match the documented package version`);
          let selected = 0;
          for (const view of recorded.views) {
            for (const entry of [view, ...(view.patch_windows ?? [])]) {
              if (!entry.html) continue;
              assert.equal(digest(await readFile(join(directory, entry.json))), entry.html_input_sha256);
              const html = await readFile(join(directory, entry.html));
              assert.equal(digest(html), digest(await readFile(join('website/src/public/examples/real-packages', packageName, entry.html))),
                `${packageName}/${entry.html}: the build must preserve the exact native export`);
              if (!guided) assert.equal(digest(html), entry.html_sha256);
              else assert.equal(entry.html_sha256, undefined, 'HTML hashes must not make catalogue provenance circular');
              kinds.add(view.kind); selected++;
              nativeExports++;
            }
          }
          if (guided) assert.equal(selected, packageName.endsWith('-profiles') ? 7 : 5,
            `${packageName}: selected examples cover its useful plot families`);
          if (['datastructures', 'oxygen'].includes(packageName)) {
            const sourceHash = digest(await readFile(join(directory, 'normalized.json')));
            const entry = recorded.views.find(view => view.html_input_sha256 === sourceHash);
            assert.ok(entry, `${packageName}: normalized alias must retain its source values`);
            assert.equal(digest(await readFile(join(directory, 'normalized.html'))),
              digest(await readFile(join(directory, entry.html))));
          }
        }
        assert.equal(nativeExports, guided ? 34 : 103);
        const normalized = catalog.views.filter(view => view.kind === 'normalized_metrics');
        assert.equal(normalized.length, 70);
        for (const view of normalized) {
          await access(join(site, 'examples/real-packages/containers', view.svg));
          await access(join(site, 'examples/real-packages/containers', view.json));
          if (view.html) await access(join(site, 'examples/real-packages/containers', view.html));
          else if (!guided) assert.fail(`Missing native HTML for ${view.id}`);
        }
        if (guided) {
          assert.equal(kinds.size, 12, 'The guided exports cover all twelve native plot families');
          const bibliography = join(site, 'examples/bibliography/history');
          const history = JSON.parse(await readFile(join(bibliography, 'catalog.json'), 'utf8'));
          assert.equal(history.views.length, 6, 'The six measured Bibliography views remain available');
          for (const view of history.views) for (const file of [view.html, view.evidence])
            assert.equal(digest(await readFile(join(bibliography, file))),
              digest(await readFile(join('website/src/public/examples/bibliography/history', file))),
              `Bibliography/${file}: the build preserves the measured source and native export`);
          const assets = exportArtifact.files.filter(file => file.path.startsWith('examples/plot-assets/'));
          assert(assets.some(file => file.path.endsWith('.js')) && assets.some(file => file.path.endsWith('.bin')),
            'Shared WGL assets include the JavaScript modules and saved sessions');
          for (const file of assets) assert.equal(digest(await readFile(file.absolute)),
            digest(await readFile(join('website/src/public', file.path))), `Shared asset changed: ${file.path}`);
        }
        const output = join(root, channel, 'browser-recorded');
        await mkdir(output, { recursive: true });
        await page.setViewportSize({ width: 1440, height: 1000 });
        const checks = await checkRecordedInteractions(page, local, output);
        await writeFile(join(output, 'recorded-plots-result.json'),
          JSON.stringify({ passed: true, channel, revision: info.revision, renderer: marker.renderer, checks }, null, 2) + '\n');
        console.log(`${channel}: ${nativeExports} real-package native HTML/source hashes${guided ? ', six Bibliography exports and shared assets' : ''}, and two aliases passed; public-renderer checks executed: ${checks.join('; ')}`);
      } else {
        console.log(`${channel}: legacy ${info.version} export has no native-gallery marker; native interaction checks were not executed`);
      }
    }
    assert.deepEqual(errors, []);
    console.log(`${channel}: mobile navigation, search, version picker, six full-size VS Code screenshots and Supposition guide passed in Chromium`);
  } catch (error) {
    if (page) {
      try {
        const diagnostics = resolve(root, '..', 'browser-diagnostics', channel);
        await mkdir(diagnostics, { recursive: true });
        await writeFile(join(diagnostics, 'url.txt'), page.url() + '\n');
        await writeFile(join(diagnostics, 'page.html'), await page.content());
        await page.screenshot({ path: join(diagnostics, 'page.png'), fullPage: true });
      } catch (diagnosticError) {
        console.error(`${channel}: browser diagnostic capture failed`, diagnosticError);
      }
    }
    throw error;
  } finally {
    await browser?.close(); const closed = once(server, 'exit'); server.kill('SIGTERM'); await closed;
  }
}
