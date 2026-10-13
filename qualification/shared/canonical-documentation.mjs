// Check the same plain-file routes used by the canonical SFTP host.
import assert from 'node:assert/strict';
import { readdir, readFile, access, mkdir, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { resolve, join, relative, posix } from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { inflateSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { readExport } from '../../website/deploy-sftp.mjs';
import { checkRecordedInteractions, checkInteractiveCatalog, checkRecordedPlotEmbeds, checkNormalizedTimingModel, checkNormalizedObservationSource } from './recorded-plots.mjs';
const root = resolve(process.argv[2] ?? 'website/build/sftp');
const localChecks = process.argv.includes('--local');
const canonicalOrigin = 'https://perfchecker.mirageinteractive.fr';
const localArtifacts = localChecks ? await mkdtemp(join(tmpdir(),'perfchecker-local-doc-check-')) : undefined;
const browserChecks = process.argv.includes('--browser');
const optionalOwners = [['linuxperf', 'PerfCheckerLinuxPerf'], ['likwid', 'PerfCheckerLIKWID'],
  ['makie', 'PerfCheckerMakie'], ['web', 'PerfCheckerWeb'], ['pluto', 'PerfCheckerPluto'],
  ['tachikoma', 'PerfCheckerTachikoma']];
const illustratedGuides = new Set(['interfaces/vscode.html', 'interfaces/vscode-configuration.html',
  'interfaces/vscode-workflows.html', 'interfaces/vscode-videos.html', 'mcp-advisor.html']);
const savedDiagnostics = ['latency', 'memory'].flatMap(kind => ['1.10.2', '1.11.0'].map(version => ({
  tab: `${kind === 'latency' ? 'Latency' : 'Memory'} · Oxygen ${version}`,
  image: `assets/screenshots/vscode/v101/${kind}-oxygen-${version}-fac983.png`,
  report: `examples/real-packages/oxygen-saved-diagnostics/${kind}-${version}.json`,
})));
const savedDiagnosticAssets = savedDiagnostics.flatMap(entry => [entry.image, entry.report]);
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
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
async function enumerate(directory, extension='.html') {
  const paths = [];
  for (const item of await readdir(directory, { withFileTypes: true })) {
    if (item.isDirectory()) paths.push(...await enumerate(join(directory, item.name),extension));
    else if (extension===null || item.name.endsWith(extension)) paths.push(join(directory, item.name));
  }
  return paths;
}
function assertCompleteCapability(source, exported, label) {
  assert.equal(source.length, exported.length, label);
  const present = source.some(Boolean) || exported.some(Boolean);
  if (present) assert.ok(source.every(Boolean) && exported.every(Boolean), `${label}: partial source/export capability`);
  return present;
}
function declaredScreenshots(source) {
  const result = [], tabs = [], lines = [], containers = [];
  let fence, offset = 0;
  for (const line of source.split('\n')) {
    const boundary = /^\s*(`{3,}|~{3,})(.*)$/.exec(line);
    if (boundary) {
      if (fence && boundary[1][0] === fence.marker) fence = undefined;
      else if (!fence) fence = { marker: boundary[1][0], html: /^@raw\s+html\s*$/.test(boundary[2].trim()) };
    } else if (!fence) {
      const open = /^\s*(:{3,})\s+(\S+)/.exec(line);
      const close = /^\s*:{3,}\s*$/.test(line);
      const label = /^\s*==\s+(.+?)\s*$/.exec(line);
      if (open) containers.push({ kind: open[2], label: undefined });
      else if (close) containers.pop();
      else if (label) {
        const tab = containers.findLast(container => container.kind === 'tabs');
        assert.ok(tab, 'A historical Markdown tab must belong to a tabs container');
        tab.label = label[1];
      }
    }
    lines.push({ offset, rendered: !boundary && (!fence || fence.html),
      tabs: containers.filter(container => container.kind === 'tabs').map(container => container.label).filter(Boolean) });
    offset += line.length + 1;
  }
  const attributes = tag => Object.fromEntries([...tag.matchAll(/([:\w-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g)]
    .map(match => [match[1], match[2] ?? match[3] ?? match[4] ?? '']));
  let line = 0;
  for (const token of source.matchAll(/<\/?PluginTabsTab\b[^>]*>|<DocMedia\b[^>]*>/g)) {
    while (line + 1 < lines.length && lines[line + 1].offset <= token.index) line++;
    if (!lines[line].rendered) continue;
    const tag = token[0];
    if (tag.startsWith('</PluginTabsTab')) { tabs.pop(); continue; }
    const attrs = attributes(tag);
    if (tag.startsWith('<PluginTabsTab')) { assert.ok(attrs.label); tabs.push(attrs.label); continue; }
    if (Object.hasOwn(attrs, 'video')) continue;
    assert.ok(attrs.src?.startsWith('/'), 'A historical screenshot must declare its local original');
    result.push({ asset: attrs.src.slice(1), tabs: [...lines[line].tabs, ...tabs] });
  }
  return result;
}
function assertDocumentationLayout(version, sourcePages, exportedPages, sections, examples, hasCompanionAPIs) {
  // Core 1.1.0 was published with the historical layout too. Version and shared
  // screenshots cannot identify this reorganization; canonical routes must agree
  // with their source tree. Partial modern exports must never fall back to legacy.
  const modern = sourcePages.some(Boolean) || exportedPages.some(Boolean);
  if (modern) {
    assert.ok(sourcePages.every(Boolean) && exportedPages.every(Boolean),
      'Incomplete modern documentation: all five canonical tool routes and sources are required');
    assert.deepEqual(sections, ['Manual', 'Examples', 'Interfaces', 'Tools', 'Agentic workflows', 'API']);
    assert.deepEqual(examples, ['Bibliography', 'DataStructures', 'Oxygen']);
  } else {
    assert.ok(['1.0.0', '1.0.1', '1.1.0'].includes(version), 'Unknown historical documentation layout');
    const legacy = ['Manual', 'Examples', 'Interfaces', 'Further topics', 'Reference', 'Contributing'];
    if (hasCompanionAPIs) legacy.push('Companion APIs');
    assert.deepEqual(sections.filter(section => section !== 'Home'), legacy,
      'An archive without canonical tool routes must retain its complete historical navigation');
    assert.deepEqual(examples, ['Choose an example', 'Bibliography', 'DataStructures', 'Oxygen']);
  }
  return modern;
}
async function checkLegacyInterfaces(page, local, site, savedDiagnosticBytes, hasSavedDiagnostics, channel) {
  const routes = ['interfaces/vscode.html', 'interfaces/vscode-workflows.html', 'mcp-advisor.html'];
  const sources = new Map(await Promise.all(routes.map(async route =>
    [route, await readFile(join('website/src', route.replace(/\.html$/, '.md')), 'utf8')])));
  const workflow = 'interfaces/vscode-workflows.html';
  const exported = await readFile(join(site, workflow), 'utf8');
  const profiles = [
    ['CPU samples', 'datastructures-profiles/cpu-flamegraph-054b5e59c351c558', 'cpu_flamegraph'],
    ['Wall-time samples', 'datastructures-profiles/wall-flamegraph-1a28318cdf1f7700', 'wall_flamegraph'],
    ['Allocated bytes', 'datastructures-profiles/allocation-flamegraph-6d6354c132248fdf', 'allocation_flamegraph'],
  ];
  const nativeProfiles = assertCompleteCapability(
    profiles.map(([, asset]) => sources.get(workflow).includes(`${asset}.html`)),
    profiles.map(([, asset]) => exported.includes(`${asset}.html`)), 'Historical native profile embeds');
  const diagnosticAssets = savedDiagnostics.flatMap(entry => [entry.image, entry.report]);
  const gallery = assertCompleteCapability(
    diagnosticAssets.map(asset => sources.get(workflow).includes(asset)),
    diagnosticAssets.map(asset => exported.includes(asset)), 'Historical diagnostic gallery');
  if (gallery) assert.ok(hasSavedDiagnostics, 'The historical gallery requires every original capture and report');
  async function originalBytes(asset, response) {
    assert.equal(response.status(), 200);
    const bytes = await response.body();
    const original = savedDiagnosticBytes.get(asset) ?? await readFile(join('website/src/public', asset));
    assert.deepEqual(await readFile(join(site, asset)), original, `${asset}: historical exported bytes`);
    assert.deepEqual(bytes, original, `${asset}: historical downloaded bytes`);
    assert.equal(sha256(bytes), sha256(original));
    return bytes;
  }
  for (const width of [1440, 390, 360]) {
    await page.setViewportSize({ width, height: 900 });
    for (const route of routes) {
      const screenshots = declaredScreenshots(sources.get(route));
      await page.goto(new URL(route, local).href, { waitUntil: 'networkidle' });
      await page.locator('.vp-doc h1').waitFor({ state: 'visible' });
      for (const screenshot of screenshots) {
        await page.goto(new URL(route, local).href, { waitUntil: 'networkidle' });
        for (const label of screenshot.tabs) {
          const tab = page.getByRole('tab', { name: label, exact: true });
          await tab.click(); assert.equal(await tab.getAttribute('aria-selected'), 'true');
        }
        const image = page.locator(`.vp-doc img[src$="/${screenshot.asset}"]`);
        for (const details of await image.locator('xpath=ancestor::details').all()) {
          if (!await details.evaluate(node => node.open)) await details.locator(':scope > summary').click();
        }
        await image.scrollIntoViewIfNeeded();
        await image.evaluate(image => image.decode());
        assert.ok(await image.isVisible(), `${route}/${screenshot.asset}: visible at ${width}px`);
        const dimensions = await image.evaluate(image => [image.naturalWidth, image.naturalHeight]);
        assert.ok(dimensions.every(value => value > 0));
        if (['vscode-studio.png', 'vscode-results.png', 'vscode-mcp-settings.png',
          'vscode-advice-chat.png', 'vscode-implementation.png', 'native-items.png']
          .includes(screenshot.asset.split('/').at(-1))) {
          assert.ok(dimensions[0] >= 1200 && dimensions[1] > 500, `${screenshot.asset}: full historical capture`);
        }
        if (screenshot.asset.endsWith('/vscode-suite-designer.png')) assert.deepEqual(dimensions, [1440, 2609]);
        if (screenshot.asset.endsWith('/suite-designer-linux-4fab779.png')) assert.deepEqual(dimensions, [1083, 502]);
        if (savedDiagnostics.some(entry => entry.image === screenshot.asset)) assert.deepEqual(dimensions, [1800, 1400]);
        assert.ok((await image.getAttribute('alt'))?.length > 40);
        const url = new URL(screenshot.asset, local).href, link = image.locator('..');
        assert.equal(new URL(await link.getAttribute('href'), local).href, url);
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), route);
        if (width === 1440) {
          const [response] = await Promise.all([page.waitForResponse(response => response.url() === url), link.click()]);
          await page.waitForURL(url); await originalBytes(screenshot.asset, response);
        } else await originalBytes(screenshot.asset, await page.request.get(url));
      }
      await page.goto(new URL(route, local).href, { waitUntil: 'networkidle' });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), route);
    }
    if (nativeProfiles) {
      await page.goto(new URL(workflow, local).href, { waitUntil: 'networkidle' });
      for (const [tabName, asset, kind] of profiles) {
        await page.getByRole('tab', { name: tabName, exact: true }).click();
        const iframe = page.locator(`.vp-doc iframe[src$="/${asset}.html"]`);
        await iframe.scrollIntoViewIfNeeded();
        const link = iframe.locator('..').getByRole('link', { name: 'Download the serialized plot', exact: true });
        const source = new URL(await link.getAttribute('href'), local);
        assert.equal(source.href, new URL(`examples/real-packages/${asset}.json`, local).href);
        const record = JSON.parse((await originalBytes(`examples/real-packages/${asset}.json`, await page.request.get(source.href))).toString());
        assert.equal(record.plot.kind, kind);
        const frame = iframe.contentFrame(), mark = frame.locator('.flame-frame').first();
        await mark.focus(); await frame.getByRole('tooltip').waitFor({ state: 'visible' });
        assert.ok((await frame.getByRole('tooltip').innerText()).includes(record.plot.data[0].label));
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
      }
    }
    if (gallery) for (const entry of savedDiagnostics) {
      await page.goto(new URL(workflow, local).href, { waitUntil: 'networkidle' });
      const link = page.locator(`.vp-doc a[href$="/${entry.report}"]`);
      assert.equal(await link.innerText(), 'Original JSON');
      const url = new URL(entry.report, local).href;
      assert.equal(new URL(await link.getAttribute('href'), local).href, url);
      const [response] = await Promise.all([page.waitForResponse(response => response.url() === url), link.click()]);
      await page.waitForURL(url); await originalBytes(entry.report, response);
    }
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto(new URL('reference/extensions.html', local).href, { waitUntil: 'networkidle' });
  const text = await page.locator('.vp-doc').innerText();
  assert.match(text, /64-bit/); assert.match(text, /PropCheck/); assert.match(text, /corpus/);
  console.log(`${channel}: source-declared historical media, complete native/profile capabilities, original JSON and mobile layouts passed`);
}
async function checkCanonicalInterfaces(page, local, site, savedDiagnosticBytes, savedDiagnostics) {
  const screenshots = [
    ['interfaces/vscode.html', 'assets/screenshots/vscode/v101/suite-designer-linux-4fab779.png', [1083, 502]],
    ['interfaces/vscode.html', 'examples/bibliography/vscode/native-items.png', [1442, 901]],
    ['interfaces/pluto.html', 'examples/bibliography/pluto/completed.png', [1440, 2386]],
    ['interfaces/web-studio.html', 'examples/real-packages/oxygen-web-studio.png', [1248, 1075]],
  ];
  const profiles = [
    ['tools/cpu-profile.html', 'cpu', 'cpu_flamegraph'],
    ['tools/wall-profile.html', 'wall', 'wall_flamegraph'],
    ['tools/allocation-profile.html', 'allocations', 'allocation_flamegraph'],
  ];
  async function fits(label) {
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), label);
  }
  async function originalBytes(asset, response) {
    assert.equal(response.status(), 200, asset);
    const bytes = await response.body();
    const original = savedDiagnosticBytes.get(asset) ?? await readFile(join('website/src/public', asset));
    assert.deepEqual(await readFile(join(site, asset)), original, `${asset}: exported original bytes`);
    assert.deepEqual(bytes, original, `${asset}: downloaded original bytes`);
    assert.equal(sha256(bytes), sha256(original), `${asset}: original SHA-256`);
    return bytes;
  }
  for (const width of [1440, 390, 360]) {
    await page.setViewportSize({ width, height: 900 });
    for (const [route, asset, dimensions] of screenshots) {
      await page.goto(new URL(route, local).href, { waitUntil: 'networkidle' });
      const image = page.locator(`.vp-doc img[src$="/${asset}"]`);
      await image.scrollIntoViewIfNeeded();
      await image.evaluate(image => image.decode());
      assert.ok(await image.isVisible(), `${route}/${asset}: visible at ${width}px`);
      assert.deepEqual(await image.evaluate(image => [image.naturalWidth, image.naturalHeight]), dimensions);
      assert.ok((await image.getAttribute('alt'))?.length > 40, `${asset}: descriptive alternative text`);
      const imageUrl = new URL(asset, local).href;
      const fullSize = image.locator('..');
      assert.equal(new URL(await image.getAttribute('src'), local).href, imageUrl);
      assert.equal(new URL(await fullSize.getAttribute('href'), local).href, imageUrl);
      await fits(`${route}: screenshot page overflows at ${width}px`);
      if (width === 1440) {
        const [response] = await Promise.all([
          page.waitForResponse(response => response.url() === imageUrl), fullSize.click(),
        ]);
        await page.waitForURL(imageUrl);
        await originalBytes(asset, response);
        const original = page.locator('body > img');
        await original.evaluate(image => image.decode());
        assert.deepEqual(await original.evaluate(image => [image.naturalWidth, image.naturalHeight]), dimensions);
      } else {
        await originalBytes(asset, await page.request.get(imageUrl));
      }
    }
    for (const [route, name, kind] of profiles) {
      await page.goto(new URL(route, local).href, { waitUntil: 'networkidle' });
      const asset = `examples/bibliography/profiles/${name}`;
      const iframe = page.locator(`.vp-doc iframe[src$="/${asset}.html"]`);
      await iframe.scrollIntoViewIfNeeded();
      const link = iframe.locator('..').getByRole('link', { name: 'Download the serialized plot', exact: true });
      const source = new URL(await link.getAttribute('href'), local);
      assert.equal(source.href, new URL(`${asset}.json`, local).href);
      const record = JSON.parse((await originalBytes(`${asset}.json`, await page.request.get(source.href))).toString());
      assert.equal(record.plot.kind, kind);
      const frame = iframe.contentFrame();
      const mark = frame.locator('.flame-frame').first();
      await mark.focus();
      const tooltip = frame.getByRole('tooltip');
      await tooltip.waitFor({ state: 'visible' });
      assert.ok((await tooltip.innerText()).includes(record.plot.data[0].label));
      await frame.getByRole('button', { name: 'Zoom in', exact: true }).click();
      assert.notEqual(await frame.locator('#flame-zoom-level').innerText(), 'Fit');
      await frame.getByRole('button', { name: 'Fit graph', exact: true }).click();
      assert.equal(await frame.locator('#flame-zoom-level').innerText(), 'Fit');
      await fits(`${route}: native profile overflows at ${width}px`);
    }
    for (const kind of ['latency', 'memory']) {
      const route = `tools/${kind}.html`, asset = `examples/real-packages/datastructures-diagnostics/${kind}`;
      await page.goto(new URL(route, local).href, { waitUntil: 'networkidle' });
      const iframe = page.locator(`.vp-doc iframe[src$="/${asset}.html"]`);
      await iframe.scrollIntoViewIfNeeded();
      const link = iframe.locator('..').getByRole('link', { name: 'Download the serialized plot', exact: true });
      const source = new URL(await link.getAttribute('href'), local);
      assert.equal(source.href, new URL(`${asset}.plot.json`, local).href);
      const record = JSON.parse((await originalBytes(`${asset}.plot.json`, await page.request.get(source.href))).toString());
      assert.equal(record.plot.kind, 'observation_series');
      const frame = iframe.contentFrame(), mark = frame.locator('.point').first();
      await mark.focus();
      const label = await mark.getAttribute('aria-label');
      assert.ok(label.includes(String(record.plot.data[0].value)), `${kind}: original recorded value`);
      assert.equal(await frame.locator('#readout').innerText(), `Point 1: ${label}`);
      await frame.getByRole('button', { name: 'Zoom in', exact: true }).click();
      assert.notEqual(await frame.locator('#zoom').innerText(), '100%');
      await frame.getByRole('button', { name: 'Fit', exact: true }).click();
      assert.equal(await frame.locator('#zoom').innerText(), '100%');
      await fits(`${route}: native diagnostic overflows at ${width}px`);
    }
    const workflow = new URL('interfaces/vscode.html', local).href;
    for (const entry of savedDiagnostics) {
      await page.goto(workflow, { waitUntil: 'networkidle' });
      const details = page.locator('.vp-doc details').filter({ hasText: 'Import a saved diagnostic report' });
      await details.locator('summary').click();
      assert.ok(await details.evaluate(node => node.open));
      const link = details.locator(`a[href$="/${entry.report}"]`);
      assert.ok(await link.isVisible(), `${entry.tab}: visible original JSON at ${width}px`);
      const url = new URL(entry.report, local).href;
      assert.equal(new URL(await link.getAttribute('href'), workflow).href, url);
      await fits(`${entry.tab}: diagnostic download page overflows at ${width}px`);
      const [response] = await Promise.all([
        page.waitForResponse(response => response.url() === url), link.click(),
      ]);
      await page.waitForURL(url);
      await originalBytes(entry.report, response);
    }
    const redirected = 'interfaces/vscode-workflows.html#Open-a-saved-diagnostic-report';
    await page.goto(new URL(redirected, local).href, { waitUntil: 'networkidle' });
    await page.waitForURL(new URL('interfaces/vscode.html#Open-a-saved-diagnostic-report', local).href);
    assert.ok(await page.locator('.vp-doc #Open-a-saved-diagnostic-report').count());
    for (const [alias, destination] of [
      ['mcp-advisor.html#MCP-advice-and-implementation', 'agentic/mcp.html'],
      ['reference/extensions.html#Extensions-and-providers', 'tools/supposition.html'],
    ]) {
      await page.goto(new URL(alias, local).href, { waitUntil: 'networkidle' });
      assert.equal(await page.locator('.vp-doc img, .vp-doc iframe').count(), 0, `${alias}: compatibility forwarder`);
      await page.locator(`.vp-doc a[href$="/${destination}"]`).first().click();
      await page.waitForURL(new URL(destination, local).href);
      await page.locator('.vp-doc h1').waitFor({ state: 'visible' });
      await fits(`${alias}: canonical destination overflows at ${width}px`);
    }
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  for (const tool of ['propcheck', 'supposition']) {
    await page.goto(new URL(`tools/${tool}.html`, local).href, { waitUntil: 'networkidle' });
    assert.match(await page.locator('.vp-doc').innerText(), /corpus/);
    const asset = `examples/tool-recipes/${tool}-corpus.json`;
    const link = page.locator(`.vp-doc a[href$="/${asset}"]`);
    const url = new URL(await link.getAttribute('href'), local).href;
    assert.equal(url, new URL(asset, local).href);
    await originalBytes(asset, await page.request.get(url));
    if (tool === 'supposition') {
      const text = await page.locator('.vp-doc').innerText();
      assert.match(text, /64-bit/); assert.match(text, /PropCheck/);
    }
  }
  console.log('Canonical interface media, three native profiles, two native diagnostics, four original JSON downloads, compatibility forwarding and property corpora passed at desktop/390px/360px');
}
const channels = localChecks ? [JSON.parse(await readFile(join(root,'build-info.json'),'utf8')).channel] : await readdir(root);
const interactionChannel = channels.includes('dev') ? 'dev' : channels.includes('stable') ? 'stable' : channels[0];
try {
for (const channel of channels) {
  const site = localChecks ? root : join(root, channel, 'site');
  const info = JSON.parse(await readFile(join(site, 'build-info.json'), 'utf8'));
  if(localChecks){
    assert.equal(info.source_state,'local-working-tree');
    assert(['127.0.0.1','localhost'].includes(new URL(info.url).hostname),'Local checks require a loopback preview');
  }
  const origin = localChecks ? new URL(info.url).origin : canonicalOrigin;
  const hasCompanionAPIs = /^1\./.test(info.version) && info.version !== '1.0.0';
  assert.equal(info.channel, channel); assert.equal(info.url, origin + info.base);
  const exportArtifact = localChecks ? {files:(await enumerate(site,null)).map(absolute=>({absolute,path:relative(site,absolute).replaceAll('\\','/')}))} : await readExport(site, info.channel, info.revision);
  console.log(`${channel}: ${localChecks?'completed local artifact inventory':'SFTP export preflight'} passed (${exportArtifact.files.length} files)`);
  // The original 1.0.1 archive predates this gallery, as does 1.0.0. Detect its
  // actual assets; a partial gallery must fail instead of silently skipping.
  const hasSavedDiagnostics = exportArtifact.files.some(file => savedDiagnosticAssets.includes(file.path));
  const savedDiagnosticBytes = new Map();
  if (hasSavedDiagnostics) {
    for (const asset of savedDiagnosticAssets) {
      const source = await readFile(join('website/src/public', asset));
      const built = await readFile(join(site, asset));
      assert.deepEqual(built, source, `${channel}/${asset}: exact original bytes`);
      assert.equal(sha256(built), sha256(source), `${channel}/${asset}: original SHA-256`);
      savedDiagnosticBytes.set(asset, source);
    }
  }
  const pages = await enumerate(site);
  const pageIds = new Map();
  for (const file of pages) pageIds.set(file, htmlIds(await readFile(file, 'utf8')));
  if (hasCompanionAPIs) {
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
    assert.ok(!/<(?:interactiverecordedplot|normalizedmeasurements)(?:\s|>)/i.test(html),
      `${route}: recorded plots must render their native output, not an unresolved custom element`);
    if (!html.includes('rel="canonical"')) {
      // Exported plots are public HTML assets, not VitePress documentation pages.
      await access(join('website/src/public', route)); continue;
    }
    assert.ok(html.includes(`rel="canonical" href="${url.href}"`), `Incorrect canonical URL in ${route}`);
    if (illustratedGuides.has(route)) await checkGuideRendering(route, html);
    const markdown = join('website/src', route.replace(/\.html$/, '.md'));
    const source = await readFile(markdown,'utf8').catch(error=>{
      if(error.code==='ENOENT')return undefined;throw error;
    });
    if (source !== undefined) {
      await checkRecordedPlotEmbeds(source,site);
    }
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
  const tooling=process.env.PERFCHECKER_PLOT_BROWSER_TOOLING;
  const { chromium } = createRequire(tooling?resolve(tooling,'package.json'):import.meta.url)('playwright');
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
    const examplesMenu=page.locator('.VPNavBar .VPFlyout').filter({has:page.getByRole('button',{name:'Examples',exact:true})});
    await examplesMenu.getByRole('button',{name:'Examples',exact:true}).click();
    await examplesMenu.getByRole('link',{name:'Bibliography',exact:true}).waitFor({state:'visible'});
    const sidebarGroups=page.locator('.VPSidebarItem.level-0');
    const canonicalTools=['cpu-profile','wall-profile','allocation-profile','latency','memory'];
    const exists=async path=>access(path).then(()=>true).catch(error=>{
      if(error.code==='ENOENT')return false;throw error;
    });
    const modernDocumentation=assertDocumentationLayout(info.version,
      await Promise.all(canonicalTools.map(tool=>exists(join('website/src/tools',tool+'.md')))),
      await Promise.all(canonicalTools.map(tool=>exists(join(site,'tools',tool+'.html')))),
      (await sidebarGroups.locator(':scope > .item').allTextContents()).map(text=>text.trim()),
      (await examplesMenu.getByRole('link').allTextContents()).map(text=>text.trim()),hasCompanionAPIs);
    if(modernDocumentation){
      const manual=sidebarGroups.first().locator(':scope > .items > .VPSidebarItem.level-1');
      assert.deepEqual((await manual.locator(':scope > .item').allTextContents()).map(text=>text.trim()),
        ['1. Your first comparison','2. Investigate a change','3. Suites and CI','Architecture','Contributing']);
    }
    await examplesMenu.getByRole('button',{name:'Examples',exact:true}).click();
    await page.locator('.VPNavBar').getByRole('button', { name: /Search/ }).click();
    await page.locator('.VPLocalSearchBox input').fill('implementation');
    const result = page.locator('.VPLocalSearchBox .result').first(); await result.waitFor();
    const href = await result.getAttribute('href');
    assert.ok(new URL(href, local).pathname.startsWith(info.base) && new URL(href, local).pathname.endsWith('.html'));
    await result.click();
    const searchTarget=new URL(href,local);
    await page.waitForURL(searchTarget.href,{waitUntil:'domcontentloaded'});
    await page.locator('.vp-doc h1').waitFor({state:'visible'});
    if(searchTarget.hash)assert(await page.evaluate(id=>!!document.getElementById(id),
      decodeURIComponent(searchTarget.hash.slice(1))),'Search navigates to its actual visible document and existing fragment');
    if (hasCompanionAPIs) {
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
    if(modernDocumentation){
      await checkCanonicalInterfaces(page, local, site, savedDiagnosticBytes, savedDiagnostics);
    }else{
      await checkLegacyInterfaces(page, local, site, savedDiagnosticBytes, hasSavedDiagnostics, channel);
    }
    const label = channel === 'dev' ? 'dev' : `v${info.version}`;
    const picker = page.locator('.VPNavBar .VPVersionPicker');
    await picker.getByRole('button', { name: label, exact: true }).click();
    await picker.getByRole('link', { name: label, exact: true }).waitFor({ state: 'visible' });
    if (channel === interactionChannel) {
      const catalog = JSON.parse(await readFile(join(site, 'examples/real-packages/containers/catalog.json'), 'utf8'));
      const marker = catalog.interactive_export;
      if (hasCompanionAPIs) assert.ok(marker, 'Core 1.0.1 and later require the published native interactive exports');
      if (marker) {
        assert.equal(marker.renderer, 'PerfChecker.performance_plot_html');
        assert.equal(marker.input_kind, 'published_serialized_plot');
        const digest = bytes => createHash('sha256').update(bytes).digest('hex');
        const documentationReplay = catalog.documentation_interactive_export;
        const exhaustive = marker.selection === 'all_saved_views', kinds = new Set();
        assert.ok(documentationReplay || exhaustive,
          'Every navigable timing view, patch window and profile must have a native export');
        // Core and its companions have independent package versions.
        const companionProject = await readFile('packages/PerfCheckerMakie/Project.toml', 'utf8');
        const companionVersion = /^version\s*=\s*"([^"]+)"/m.exec(companionProject)?.[1];
        assert.ok(companionVersion, 'The real Makie companion declares its own version');
        const expectedCompanionVersion = hasCompanionAPIs ? companionVersion : info.version;
        let nativeExports = 0;
        for (const packageName of ['datastructures', 'containers', 'oxygen', 'oxygen-features',
          'datastructures-profiles', 'oxygen-profiles']) {
          const directory = join(site, 'examples/real-packages', packageName);
          const recorded = JSON.parse(await readFile(join(directory, 'catalog.json'), 'utf8'));
          assert.equal(recorded.interactive_export?.renderer, marker.renderer);
          const timing = !packageName.endsWith('-profiles');
          const replay = recorded.documentation_interactive_export;
          const selectedViews = documentationReplay && timing
            ? recorded.views.filter(view => view.kind === 'normalized_metrics') : recorded.views;
          if (documentationReplay) {
            assert.equal(replay?.renderer, marker.renderer);
            assert.equal(replay.companion_version, expectedCompanionVersion,
              `${packageName}: replay renderer matches its actual package version`);
            assert.equal(replay.selection, timing ? 'all_normalized_views_and_patch_windows' : 'all_profile_views');
            assert.equal(replay.selected_views, selectedViews.reduce((sum, view) => sum + 1 + (view.patch_windows?.length ?? 0), 0));
            assert(Object.keys(replay.working_tree_source_sha256).length >= 6);
            for (const [file, hash] of Object.entries(replay.working_tree_source_sha256)) {
              assert.equal(digest(await readFile(file)), hash, `${packageName}: actual replay source ${file}`);
            }
          } else {
            assert.equal(recorded.interactive_export?.companion_version, expectedCompanionVersion,
              `${packageName}: public renderer must match the documented companion version`);
          }
          let selected = 0;
          const expected = await checkInteractiveCatalog({...recorded, views: selectedViews}, directory);
          for (const view of selectedViews) {
            for (const entry of [view, ...(view.patch_windows ?? [])]) {
              if (!entry.html) continue;
              assert.equal(digest(await readFile(join(directory, entry.json))), entry.html_input_sha256);
              const html = await readFile(join(directory, entry.html));
              assert.equal(digest(html), digest(await readFile(join('website/src/public/examples/real-packages', packageName, entry.html))),
                `${packageName}/${entry.html}: the build must preserve the exact native export`);
              assert.equal(entry.html_sha256, undefined, 'HTML hashes must not make catalogue provenance circular');
              kinds.add(view.kind); selected++;
              nativeExports++;
            }
          }
          assert.equal(selected, expected, `${packageName}: all saved views and patch windows are interactive`);
          if (['datastructures', 'oxygen'].includes(packageName)) {
            const sourceHash = digest(await readFile(join(directory, 'normalized.json')));
            const entry = recorded.views.find(view => view.html_input_sha256 === sourceHash);
            assert.ok(entry, `${packageName}: normalized alias must retain its source values`);
            assert.equal(digest(await readFile(join(directory, 'normalized.html'))),
              digest(await readFile(join(directory, entry.html))));
          }
        }
        assert(nativeExports > 0);
        const collectorDirectory = join(site, 'examples/real-packages/containers-collectors');
        const bibliographyRoot=join(site,'examples/bibliography');
        const quick=JSON.parse(await readFile(join(bibliographyRoot,'export-normalized.json'),'utf8'));
        const quickBytes=await readFile(join(bibliographyRoot,'timing-evidence.json'));
        assert.equal(quick.source_projection_sha256,digest(quickBytes));
        const quickRaw=JSON.parse(quickBytes.toString('utf8')).series.filter(series=>
          series.package===quick.plot.options.package&&series.feature===quick.plot.options.feature&&
          series.measurement_definition.endsWith('/'+quick.plot.options.collector));
        checkNormalizedTimingModel(quick.plot,{sourceRows:quickRaw.flatMap(series=>series.points.map(point=>
          ({metric:series.metric,unit:series.unit,version:point.version,value:point.statistics.minimum})))});
        for(const campaign of ['chairmarks-history','chairmarks-quick']){
          const directory=join(bibliographyRoot,campaign);
          await checkNormalizedObservationSource(JSON.parse(await readFile(join(directory,'normalized.json'),'utf8')),directory);
        }
        const entryDirectory=join(bibliographyRoot,'first-comparison');
        const entryBytes=await readFile(join(entryDirectory,'source.json'));
        const entry=JSON.parse(entryBytes.toString('utf8'));
        assert.equal(entry.schema_version,'perfchecker-legacy-first-comparison/1');
        assert.deepEqual(entry.units,{times:'ns',gctimes:'ns',memory:'By',allocs:'1'});
        const entryModel=JSON.parse(await readFile(join(entryDirectory,'normalized.json'),'utf8')).plot;
        assert.equal(entryModel.options.metadata.source_sha256['source.json'],digest(entryBytes));
        const entryOriginals=[];
        for(const capture of entry.measurements){
          assert.equal(capture.samples.length,50);
          for(const [field,metric,unit]of [['times','julia.wall.time','ns'],['gctimes','julia.gc.time','ns'],['memory','julia.alloc.bytes','By'],['allocs','julia.alloc.count','1']]){
            entryOriginals.push({metric,unit,version:capture.version,value:Math.min(...capture.samples.map(sample=>sample[field]))});
          }
        }
        checkNormalizedTimingModel(entryModel,{sourceRows:entryOriginals});
        const allocation=JSON.parse(await readFile(join(bibliographyRoot,'profiles/allocation-pie.json'),'utf8'));
        assert.equal(allocation.plot.kind,'allocation_pie');
        assert.equal(allocation.allocation_profile.weight_semantics,'independent whole-operation totals apportioned over retained stacks; estimates, not exact target totals');
        assert(Math.abs(allocation.plot.data.reduce((sum,row)=>sum+row.bytes,0)-allocation.allocation_profile.total_bytes)<1e-8);
        assert(Math.abs(allocation.plot.data.reduce((sum,row)=>sum+row.percentage,0)-100)<1e-8);
        const jetDirectory=join(site,'examples/jet-dispatch');
        const jetSource=await readFile(join(jetDirectory,'normalized-source.json'));
        const jetRaw=JSON.parse(jetSource.toString('utf8'));
        assert.equal(jetRaw.original_summary_sha256,digest(await readFile(join(jetDirectory,'summary.json'))));
        const jet=JSON.parse(await readFile(join(jetDirectory,'measurements.json'),'utf8')).plot;
        assert.equal(jet.options.reference_version,'dynamic');
        assert.equal(jet.options.metadata.source_sha256['normalized-source.json'],digest(jetSource));
        const jetOriginals=[];
        for(const capture of jetRaw.measurements){
          assert.equal(capture.samples.length,20);
          for(const [index,sample]of capture.samples.entries()){
            assert.equal(sample.time,capture.raw_trial.times_ns[index]/1e9);
            assert.equal(sample.gctime,capture.raw_trial.gctimes_ns[index]/1e9);
            assert.equal(sample.bytes,capture.raw_trial.memory_bytes);
            assert.equal(sample.allocs,capture.raw_trial.allocations);
          }
          for(const [field,metric,unit]of [['time','julia.wall.time','s'],['gctime','julia.gc.time','s'],
            ['bytes','julia.alloc.bytes','By'],['allocs','julia.alloc.count','1']]){
            jetOriginals.push({metric,unit,version:capture.implementation,value:Math.min(...capture.samples.map(sample=>sample[field]))});
          }
        }
        checkNormalizedTimingModel(jet,{sourceRows:jetOriginals,xlabel:'Implementation'});
        const collectorCatalog = JSON.parse(await readFile(join(collectorDirectory, 'catalog.json'), 'utf8'));
        const collectorCount = await checkInteractiveCatalog(collectorCatalog, collectorDirectory);
        assert.equal(collectorCount, 140, 'All 70 operations retain separate normalized exports for both collectors');
        for (const view of collectorCatalog.views) {
          const raw=JSON.parse(await readFile(join(collectorDirectory,view.json),'utf8'));
          assert.equal(view.normalized_views.length,new Set(raw.records.map(row=>row.workload)).size*2);
          for(const child of view.normalized_views){
            const model = JSON.parse(await readFile(join(collectorDirectory, child.plot), 'utf8')).plot;
            const originals=raw.records.filter(row=>row.workload===child.operation&&row.collector===child.collector);
            checkNormalizedTimingModel(model,{sourceRows:originals,collector:child.collector});
            assert.equal(model.options.versions.length,1,'This collector campaign measured one actual version');
            assert.equal(model.options.metadata.source_sha256[view.json], digest(await readFile(join(collectorDirectory, view.json))));
            for (const file of [child.html, child.plot, view.json]) {
              assert.equal(digest(await readFile(join(collectorDirectory, file))),
                digest(await readFile(join('website/src/public/examples/real-packages/containers-collectors', file))),
                `Collectors/${file}: the build preserves the measured source and native export`);
            }
          }
        }
        const normalized = catalog.views.filter(view => view.kind === 'normalized_metrics');
        assert.equal(normalized.length, 70);
        for (const view of normalized) {
          await access(join(site, 'examples/real-packages/containers', view.svg));
          await access(join(site, 'examples/real-packages/containers', view.json));
          if (view.html) await access(join(site, 'examples/real-packages/containers', view.html));
          else assert.fail(`Missing native HTML for ${view.id}`);
        }
        if (exhaustive || documentationReplay) {
          assert.equal(kinds.size, documentationReplay ? 9 : 12,
            'All normalized timing and eight native profile families remain available');
          const bibliography = join(site, 'examples/bibliography/history');
          const history = JSON.parse(await readFile(join(bibliography, 'catalog.json'), 'utf8'));
          assert.equal(history.views.length, 6, 'The six measured Bibliography views remain available');
          const historyViews = documentationReplay ? history.views.filter(view => view.kind === 'normalized_metrics') : history.views;
          assert(historyViews.length > 0, 'The Bibliography history retains its normalized graph');
          for (const view of historyViews) for (const file of [view.html, view.evidence])
            assert.equal(digest(await readFile(join(bibliography, file))),
              digest(await readFile(join('website/src/public/examples/bibliography/history', file))),
              `Bibliography/${file}: the build preserves the measured source and native export`);
          const assets = exportArtifact.files.filter(file => file.path.startsWith('examples/plot-assets/'));
          assert(assets.some(file => file.path.endsWith('.js')) && assets.some(file => file.path.endsWith('.bin')),
            'Shared WGL assets include the JavaScript modules and saved sessions');
          for (const file of assets) assert.equal(digest(await readFile(file.absolute)),
            digest(await readFile(join('website/src/public', file.path))), `Shared asset changed: ${file.path}`);
        }
        const output = localArtifacts ?? join(root, channel, 'browser-recorded');
        await mkdir(output, { recursive: true });
        await page.setViewportSize({ width: 1440, height: 1000 });
        const checks = await checkRecordedInteractions(page, local, output);
        await writeFile(join(output, 'recorded-plots-result.json'),
          JSON.stringify({ passed: true, channel, revision: info.revision, renderer: marker.renderer, checks }, null, 2) + '\n');
        console.log(`${channel}: ${nativeExports} selected real-package native HTML/source hashes, Bibliography normalized history and shared assets, and two aliases passed; public-renderer checks executed: ${checks.join('; ')}`);
      } else {
        console.log(`${channel}: legacy ${info.version} export has no native-gallery marker; native interaction checks were not executed`);
      }
    }
    assert.deepEqual(errors, []);
    console.log(`${channel}: mobile navigation, search, version picker, original VS Code interface captures and Supposition guide passed in Chromium`);
  } catch (error) {
    if (page) {
      try {
        const diagnostics = localArtifacts ?? resolve(root, '..', 'browser-diagnostics', channel);
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
} finally {
  if(localArtifacts)await rm(localArtifacts,{recursive:true,force:true});
}
