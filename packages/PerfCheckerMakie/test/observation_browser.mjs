import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
const tooling=process.env.PERFCHECKER_PLOT_BROWSER_TOOLING;
const {chromium}=createRequire(tooling?path.join(path.resolve(tooling),'package.json'):import.meta.url)('playwright');
const browser=await chromium.launch({headless:true,executablePath:process.env.PERFCHECKER_CHROMIUM_EXECUTABLE||undefined,
 args:['--disable-gpu','--renderer-process-limit=1']});
try{
 const page=await browser.newPage({viewport:{width:1100,height:800}}),errors=[];
 page.on('pageerror',error=>errors.push(error.message));
 await page.goto(pathToFileURL(path.resolve(process.argv[2])).href);
 assert.equal(await page.evaluate(()=>globalThis.injected),undefined);
 assert.equal(await page.locator('.panel').count(),3);
 const points=page.locator('.point'),count=await points.count();assert.equal(count,11);
 await points.first().hover();assert((await page.locator('#readout').innerText()).includes('0.25 s'));
 await page.locator('[data-panel="signed"] .point').last().focus();assert((await page.locator('#readout').innerText()).includes('0 By'));
 await page.getByRole('spinbutton',{name:'Recorded point index'}).fill('2');
 assert((await page.locator('#readout').innerText()).includes('unavailable'));
 const bars=await page.locator('[data-panel="signed"] rect').evaluateAll(nodes=>nodes.map(node=>({x:+node.getAttribute('x'),w:+node.getAttribute('width'),h:+node.getAttribute('height')})));
 assert.equal(bars.length,4);assert.equal(bars.filter(bar=>bar.h===0).length,2);
 assert(bars[0].x+bars[0].w<=bars[2].x,'Two versions are dodged rather than hidden behind each other');
 const irregular=await page.locator('[data-panel="irregular"] rect').evaluateAll(nodes=>nodes.map(node=>({x:+node.getAttribute('x'),w:+node.getAttribute('width')})));
 assert(irregular[0].x+irregular[0].w<irregular[1].x,'Irregular numeric x spacing determines the bar width');
 assert(await page.locator('[data-panel="signed"] [aria-label="Series and versions"]').innerText().then(text=>text.includes('1.0.0')&&text.includes('1.0.1')));
 await page.getByRole('checkbox',{name:'Recorded samples',exact:true}).uncheck();assert.equal(await points.count(),7);
 await page.getByRole('checkbox',{name:'Recorded samples',exact:true}).check();assert.equal(await points.count(),count);
 await page.getByRole('combobox',{name:'Measurement panel'}).selectOption('time');assert.equal(await page.locator('.panel').count(),1);
 await page.getByRole('combobox',{name:'Recorded package version'}).selectOption('1.0.1');assert.equal(await points.count(),2);
 await points.first().focus();assert((await page.locator('#readout').innerText()).includes('0.5 s'));
 await page.getByRole('button',{name:'Reset filters',exact:true}).click();assert.equal(await points.count(),count);
 const viewport=page.getByRole('group',{name:'Recorded observation plots'}),fitted=await page.locator('#plots').boundingBox();
 await viewport.focus();await page.keyboard.press('+');assert((await page.locator('#plots').boundingBox()).width>fitted.width*1.4);
 await page.keyboard.press('0');assert(Math.abs((await page.locator('#plots').boundingBox()).width-fitted.width)<2);
 for(const name of ['Model JSON','Visible data CSV']){
  const pending=page.waitForEvent('download');await page.getByRole('button',{name,exact:true}).click();
  const download=await pending;assert.equal(await download.failure(),null);let content='';for await(const chunk of await download.createReadStream())content+=chunk.toString();
  if(name==='Model JSON'){const model=JSON.parse(content);assert.equal(model.data.length,13);assert.equal(model.data[1].value,null);assert.equal(model.data[2].value,0);}
  else{assert(content.includes('"0.25"'));assert(content.includes('"","s"'),'Unavailable values remain blank in CSV');}
 }
 if(process.argv[3])await page.screenshot({path:path.resolve(process.argv[3]),fullPage:true});
 for(const width of [390,260]){
  await page.setViewportSize({width,height:844});await page.getByRole('button',{name:'Fit',exact:true}).click();
  await page.waitForFunction(width=>Array.from(document.querySelectorAll('svg')).every(svg=>Number(svg.getAttribute('viewBox').split(' ')[2])<width),width);
  const fontSizes=await page.locator('svg .tick,svg .axis-label').evaluateAll(nodes=>nodes.map(node=>{const matrix=node.getScreenCTM();return parseFloat(getComputedStyle(node).fontSize)*Math.hypot(matrix.a,matrix.b)}));
  assert(fontSizes.every(size=>size>=10.9),`Responsive axes keep effective fonts of at least 11px at ${width}px embed width`);
  assert(await page.evaluate(()=>document.body.scrollWidth<=innerWidth+1),'Fitted mobile export has no horizontal document overflow');
  if(process.argv[3])await page.screenshot({path:path.resolve(process.argv[3]).replace(/\.png$/,`-${width}.png`),fullPage:true});
 }
 assert.equal(await points.count(),count);assert.deepEqual(errors,[]);
 console.log('PASS: native observation hover/focus, exact/unavailable/zero values, dodged versions, filters, keyboard zoom, downloads and mobile fit');
}finally{await browser.close();}
