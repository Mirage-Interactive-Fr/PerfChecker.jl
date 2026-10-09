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
  args: ['--disable-gpu', '--renderer-process-limit=1'],
  executablePath: process.env.PERFCHECKER_CHROMIUM_EXECUTABLE || undefined,
});
try {
  const page = await browser.newPage({viewport: {width: 1100, height: 800}});
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(pathToFileURL(path.resolve(process.argv[2])).href);
  const initialSvg=await page.locator('svg').boundingBox(),initialViewport=await page.locator('.plot-scroll').boundingBox();
  assert(initialSvg.y+initialSvg.height<=initialViewport.y+initialViewport.height+1,'Initial fit includes the entire vertical axis and version labels');
  const toggles = page.locator('#controls input');
  assert.equal(await toggles.count(), 2, 'The regression fixture needs exactly two metrics');
  const points = page.locator('circle');
  const originalCount = await points.count();
  const longOption=(await page.locator('#version-to option').allTextContents()).find(label=>label.length>=40);
  assert(longOption,'The fixture includes a complete commit label');
  const longTick=page.locator('svg text[aria-label]').filter({has:page.locator('title',{hasText:longOption})});
  assert.equal(await longTick.getAttribute('aria-label'),longOption);
  assert.equal(await longTick.locator('title').textContent(),longOption);
  assert(await longTick.evaluate(node=>node.firstChild.textContent.length<=16));
  assert(await page.locator('svg text[aria-label]').evaluateAll(nodes=>nodes.every(node=>{const box=node.getBoundingClientRect(),svg=node.ownerSVGElement.getBoundingClientRect();return box.bottom<=svg.bottom&&box.right<=svg.right})), 'All version ticks fit the SVG');
  const selected = await points.first().getAttribute('aria-label');
  await points.first().focus();
  assert.equal(await page.locator('#readout').innerText(), selected);
  await toggles.first().uncheck();
  assert(await points.count() > 0 && await points.count() < originalCount);
  assert.equal(await page.locator('#readout').innerText(),
    'Hover or focus a visible point to read its value.');
  // The viewport itself is keyboard accessible before its visible points.
  await toggles.last().focus();
  await page.keyboard.press('Tab');
  assert.equal(await page.evaluate(() => document.activeElement.getAttribute('role') ?? document.activeElement.className), 'scroll plot-scroll');
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
  await toggles.last().check();
  const originalLabels = await points.evaluateAll(nodes=>nodes.map(node=>node.getAttribute('aria-label')));
  await page.getByRole('combobox',{name:'First recorded version',exact:true}).selectOption('1');
  assert((await points.count())<originalCount);
  assert((await points.evaluateAll(nodes=>nodes.map(node=>node.getAttribute('aria-label'))))
    .every(label=>originalLabels.includes(label)), 'Selecting versions must not recompute ratios');
  await page.getByRole('combobox',{name:'Last recorded version',exact:true}).selectOption('1');
  const positions=await points.evaluateAll(nodes=>nodes.map(node=>Number(node.getAttribute('cx'))));
  assert(positions.every(x=>x===465), 'A single recorded version is centered');
  const fitted = await page.locator('svg').boundingBox();
  await page.getByRole('button',{name:'Zoom in',exact:true}).click();
  assert((await page.locator('svg').boundingBox()).width>fitted.width*1.4);
  const viewport=page.locator('.plot-scroll');
  await viewport.focus();await page.keyboard.press('+');
  assert((await page.locator('svg').boundingBox()).width>fitted.width*2.2);
  await page.keyboard.press('-');
  assert((await page.locator('svg').boundingBox()).width<fitted.width*1.6);
  await viewport.evaluate(node=>node.scrollTo(100,0));
  const beforePan=await viewport.evaluate(node=>node.scrollLeft),box=await viewport.boundingBox();
  await page.mouse.move(box.x+box.width/2,box.y+box.height-25);await page.mouse.down();
  await page.mouse.move(box.x+box.width/2-80,box.y+box.height-25,{steps:5});await page.mouse.up();
  assert((await viewport.evaluate(node=>node.scrollLeft))>beforePan+60,'Mouse drag pans the real viewport');
  await viewport.focus();await page.keyboard.press('0');
  assert(Math.abs((await page.locator('svg').boundingBox()).width-fitted.width)<2);
  assert.equal(await page.getByRole('combobox',{name:'First recorded version',exact:true}).inputValue(),'1','Zero resets zoom, preserving the selected versions');
  await page.getByRole('button',{name:'Reset view',exact:true}).click();
  assert.equal(await points.count(),originalCount);
  assert(Math.abs((await page.locator('svg').boundingBox()).width-fitted.width)<2);
  const originalTitle=await page.locator('#title').innerText();
  const longTitle=originalTitle+' · comparison against commit 6d742e35a516c7324af4ad14f58ce1780aa28728 across all saved measurements and reproducible versions';
  await page.locator('#title').evaluate((node,title)=>node.textContent=title,longTitle);
  for(const name of ['Export SVG','Data CSV']){
    const downloaded=page.waitForEvent('download');
    await page.getByRole('button',{name,exact:true}).click();
    const download=await downloaded;assert.equal(await download.failure(),null);
    if(name==='Export SVG'){
      let content='';for await(const chunk of await download.createReadStream())content+=chunk.toString();
      const exported=await browser.newPage({viewport:{width:1000,height:800}});
      await exported.setContent(content);
      assert.equal(await exported.locator('svg > title').textContent(),longTitle);
      assert(await exported.locator('svg > text').count()>1,'Long export titles wrap');
      assert(await exported.locator('svg > text').evaluateAll(nodes=>nodes.every(node=>node.getBBox().x+node.getBBox().width<=870)), 'Export title stays inside the SVG');
      assert.equal(await exported.locator('circle').count(),originalCount);
      if(process.argv[3])await download.saveAs(path.join(path.dirname(path.resolve(process.argv[3])),path.parse(process.argv[3]).name+'-export.svg'));
      await exported.close();
    }
  }
  await page.locator('#title').evaluate((node,title)=>node.textContent=title,originalTitle);
  if(process.argv[3])await page.screenshot({path:path.join(path.dirname(path.resolve(process.argv[3])),path.parse(process.argv[3]).name+'-desktop.png')});
  await page.setViewportSize({width:390,height:844});
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
  await points.last().focus();
  assert.equal(await page.locator('#readout').innerText(),await points.last().getAttribute('aria-label'));
  assert.deepEqual(errors, []);
  if (process.argv[3]) await page.screenshot({path: path.resolve(process.argv[3])});
  console.log(JSON.stringify({status: 'passed', browser: browser.version(),
    originalCount, selected, keyboardVisiblePoint: visible, errors}));
} finally {
  await browser.close();
}
