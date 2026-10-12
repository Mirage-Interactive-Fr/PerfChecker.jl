import assert from 'node:assert/strict';
import path from 'node:path';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';

export async function checkInteractiveCatalog(catalog,directory){
 const entries=catalog.views.flatMap(view=>[view,...(view.patch_windows??[])]);
 for(const entry of entries){
  assert(entry.html,`${entry.id??entry.label}: every recorded view needs a native HTML export`);
  const html=await readFile(path.join(directory,entry.html));
  assert(html.length>0,`${entry.html}: empty native export`);
  const source=await readFile(path.join(directory,entry.json));
  if(entry.html_input_sha256)assert.equal(createHash('sha256').update(source).digest('hex'),entry.html_input_sha256);
 }
 return entries.length;
}

export async function checkRecordedPlotEmbeds(source,publicDirectory){
 const embeds=[...source.matchAll(/<InteractiveRecordedPlot\b[^>]*\/?\s*>/g)];
 for(const [tag]of embeds){
  const html=/\bhtml="([^"]+)"/.exec(tag)?.[1];
  const model=/\bsource="([^"]+)"/.exec(tag)?.[1];
  assert(html&&model,'Every documented recorded plot needs its native HTML and serialized model');
  for(const asset of [html,model]){
   const target=path.resolve(publicDirectory,'.'+asset);
   assert(target.startsWith(path.resolve(publicDirectory)+path.sep),'Recorded plot assets remain in the public documentation directory');
   assert((await readFile(target)).length>0,`${asset}: missing or empty recorded plot asset`);
  }
 }
 return embeds.length;
}

export async function checkRecordedInteractions(page,base,output){
 const checks=[];
 async function checkFrameHeight(container,label){
  const iframe=container.locator('iframe');
  await iframe.scrollIntoViewIfNeeded();
  await page.waitForFunction(frame=>{
   const body=frame.contentDocument?.body;
   const readout=frame.contentDocument?.querySelector('#readout,#point-readout');
   return body&&readout&&body.scrollHeight<=frame.clientHeight+2&&
    readout.getBoundingClientRect().bottom<=frame.clientHeight+2;
  },await iframe.elementHandle(),{timeout:10000});
  const fits=await iframe.evaluate(frame=>frame.contentDocument.body.scrollHeight<=frame.clientHeight+2);
  assert(fits,`${label}: the native export fits without a second vertical scrollbar`);
  const stableHeight=async()=>{
   await page.waitForTimeout(150);
   const first=await iframe.evaluate(frame=>frame.clientHeight);
   await page.waitForTimeout(250);
   const second=await iframe.evaluate(frame=>frame.clientHeight);
   assert(Math.abs(second-first)<=2,`${label}: iframe height stabilizes after layout and filtering`);
  };
  await stableHeight();
  const body=iframe.contentFrame().locator('body');
  const previous=await body.evaluate(node=>node.style.minHeight);
  try{
   await body.evaluate(node=>{node.style.minHeight='100vh'});
   await stableHeight();
  }finally{await body.evaluate((node,value)=>{node.style.minHeight=value},previous)}
 }
 await page.goto(base+'real-packages/datastructures.html',{waitUntil:'networkidle'});
 const atlas=page.locator('.workload-atlas').first();
 await atlas.locator('#case-Accumulator .normalized-measurements iframe').scrollIntoViewIfNeeded();
 assert.equal(await atlas.locator('.workload-group').count(),35);
 const groups=atlas.locator('.workload-group');
 for(const group of await groups.all()){
  assert.equal(await group.getByRole('tab').count(),2);
  for(const tab of await group.getByRole('tab').all()){
   await tab.click();
   const plot=group.locator('.normalized-measurements');
   const href=await plot.getByRole('link',{name:'Download the serialized plot'}).getAttribute('href');
   const record=await (await page.request.get(new URL(href,base).href)).json();
   assert.equal(await plot.locator('iframe').count(),1,'Every operation has its native interactive export');
   {
    const frame=plot.frameLocator('iframe');
    await frame.locator('svg circle').first().waitFor();
    assert.equal(await frame.locator('circle').count(),record.plot.data.filter(r=>r.ratio!==null).length);
    await frame.locator('circle').first().focus();
    const text=await frame.locator('#readout').innerText(),row=record.plot.data.find(r=>r.ratio!==null);
    assert(text.includes(String(row.value))&&text.includes(row.unit)&&text.includes(row.version));
   }
  }
 }
 const accumulator=atlas.locator('#case-Accumulator');
 await accumulator.getByRole('tab',{name:'Construction',exact:true}).click();
 await page.keyboard.press('ArrowRight');
 assert.equal(await accumulator.getByRole('tab',{name:'Traversal',exact:true}).getAttribute('aria-selected'),'true');
 assert((await accumulator.getByRole('tabpanel').innerText()).includes('Construction is excluded'));
 const selectedContainer=atlas.locator('#case-SortedSet');
 await selectedContainer.getByRole('tab',{name:'Lookup',exact:true}).click();
 const containerFrame=selectedContainer.frameLocator('iframe');
 await containerFrame.locator('circle').first().waitFor();
 const toggle=containerFrame.getByRole('checkbox',{name:'wall.time',exact:true});
 const visiblePoints=await containerFrame.locator('circle').count();
 await toggle.uncheck();assert(!(await toggle.isChecked()));
 assert((await containerFrame.locator('circle').count())<visiblePoints);
 await toggle.check();assert(await toggle.isChecked());
 assert.equal(await containerFrame.locator('circle').count(),visiblePoints);
 await checkFrameHeight(selectedContainer,'SortedSet desktop');
 await selectedContainer.screenshot({path:path.join(output,'sortedset-interactive.png')});
 checks.push('all 70 container operations use their native interactive export; exact SortedSet points and curve toggles work; operation tabs support the keyboard');

 const gallery=page.locator('section[aria-label="DataStructures container catalogue recorded plots"]');
 const catalog=await (await page.request.get(base+'examples/real-packages/containers/catalog.json')).json();
 for(const kind of ['version_series','distribution','version_delta','time_allocation_tradeoff']){
  const view=catalog.views.find(v=>v.kind===kind&&v.html);
  await gallery.locator('select').first().selectOption(view.id);
  const graph=gallery.locator('.recorded-export');
  await graph.locator('iframe').scrollIntoViewIfNeeded();
  const frame=graph.frameLocator('iframe');
  await frame.locator('canvas').waitFor();
  const record=await (await page.request.get(base+'examples/real-packages/containers/'+view.json)).json();
  assert.equal(record.plot.kind,kind);
  const input=frame.getByRole('spinbutton',{name:'Recorded point index',exact:true});
  await input.fill(await input.getAttribute('max'));
  await frame.locator('#point-readout[aria-busy="false"]').waitFor();
  assert((await frame.locator('#point-readout').innerText()).startsWith('Point '+await input.inputValue()+':'));
  const other=catalog.views.find(v=>v.kind===kind&&v.id!==view.id);
  assert(other?.html,'Non-default catalogue entries are interactive too');
  await gallery.locator('select').first().selectOption(other.id);
  await graph.frameLocator('iframe').locator('canvas').waitFor();
  assert.equal(await graph.locator('img').count(),0);
 }
 checks.push('series, samples, deltas and trade-offs load real native WGL exports and inspect saved rows, including non-default catalogue entries');
 const chair=page.locator('#case-heap_2048');
 await chair.getByRole('tab',{name:'Chairmarks',exact:true}).click();
 await chair.frameLocator('iframe').locator('circle').first().waitFor();
 const href=await chair.getByRole('link',{name:'Download the serialized plot'}).getAttribute('href');
 const chairData=await (await page.request.get(new URL(href,base).href)).json();
 assert.equal(new Set(chairData.plot.data.map(row=>row.metric)).size,4);
 assert(chairData.plot.data.some(row=>row.metric==='julia.gc.fraction'));
 const timeRows=chairData.plot.data.filter(r=>r.metric==='julia.wall.time');
 assert(timeRows.every(r=>r.unit==='s'));
 const minimum=Math.min(...timeRows.map(r=>r.value))*1e6;
 assert((await chair.locator('.observation').innerText()).includes(minimum.toFixed(2)+' µs'));
 checks.push('Chairmarks retains four interactive measurements including GC share and correct seconds-to-microseconds captions');

 await page.goto(base+'real-packages/oxygen.html',{waitUntil:'networkidle'});
 const binary=page.locator('.workload-atlas').first().locator('#case-binary');
 await binary.getByRole('tab',{name:'1.10 patches',exact:true}).click();
 await binary.frameLocator('iframe').locator('circle').first().waitFor();
 const binaryHref=await binary.getByRole('link',{name:'Download the serialized plot'}).getAttribute('href');
 const binaryData=await (await page.request.get(new URL(binaryHref,base).href)).json();
 assert.equal(binaryData.plot.data.filter(row=>row.ratio!==null).length,12);
 assert((await binary.getByRole('tabpanel').innerText()).includes('reference minimum from the complete history'));
 assert(binaryData.plot.data.some(row=>row.version==='1.10.0'));
 await binary.screenshot({path:path.join(output,'oxygen-patch-interactive.png')});
 const profiles=page.locator('.recorded-figures').first();
 for(const label of ['Allocation share','By file','By line','Heatmap','Allocation stacks','CPU stacks','Wall-time stacks','Totals']){
  await profiles.getByRole('tab',{name:label,exact:true}).click();
  const graph=profiles.locator('.recorded-export:visible').first();
  if(label.endsWith('stacks')){
   const frame=graph.frameLocator('iframe');
   const rectangles=frame.locator('.flame-frame');
   await rectangles.first().waitFor();
   const source=await graph.getByRole('link',{name:'Download the serialized plot'}).getAttribute('href');
   const record=await (await page.request.get(new URL(source,base).href)).json();
   assert.equal(await rectangles.count(),record.plot.data.length);
   await rectangles.first().focus();
   const tooltip=frame.getByRole('tooltip');
   await tooltip.waitFor({state:'visible'});
   assert((await tooltip.innerText()).includes(record.plot.data[0].label));
   const fitted=await frame.locator('#flame').boundingBox();
   await frame.getByRole('button',{name:'Zoom in',exact:true}).click();
   assert((await frame.locator('#flame').boundingBox()).width>fitted.width*1.4);
   await frame.getByRole('button',{name:'Fit graph',exact:true}).click();
   assert(Math.abs((await frame.locator('#flame').boundingBox()).width-fitted.width)<2);
  }else{
   assert.equal(await graph.locator('iframe').count(),1,'Profile totals also have a native interactive export');
   await graph.locator('iframe').scrollIntoViewIfNeeded();
   const frame=graph.frameLocator('iframe');await frame.locator('canvas').waitFor();
   const input=frame.getByRole('spinbutton',{name:'Recorded point index',exact:true});
   await input.fill(await input.getAttribute('max'));
   await frame.locator('#point-readout[aria-busy="false"]').waitFor();
   assert((await frame.locator('#point-readout').innerText()).startsWith('Point '+await input.inputValue()+':'));
  }
  if(label==='Allocation share'){
   await graph.screenshot({path:path.join(output,'oxygen-allocation-interactive.png')});
  }
 }
 checks.push('Oxygen patch plots preserve full-history normalization; all profile families and totals inspect their original recorded observations interactively');

 for(const [route,name]of [['real-packages/oxygen.html','Oxygen network'],['interfaces/vscode-workflows.html','saved diagnostics']]){
  await page.goto(base+route,{waitUntil:'networkidle'});
  const frames=page.locator('iframe[src*="oxygen-network/"],iframe[src*="oxygen-saved-diagnostics/"]');
  assert(await frames.count()>0,`${name}: native observation exports are embedded`);
  const element=frames.first();await element.scrollIntoViewIfNeeded();
  const frame=page.frameLocator('iframe[src="'+await element.getAttribute('src')+'"]');
  await frame.locator('.point').first().waitFor();const before=await frame.locator('.point').count();
  await frame.locator('.point').first().focus();
  const label=await frame.locator('.point').first().getAttribute('aria-label');
  assert((await frame.locator('#readout').innerText()).endsWith(label));
  const toggle=frame.getByRole('checkbox').first();await toggle.uncheck();
  assert((await frame.locator('.point').count())<before,'Series filters change the actual marks');
  await toggle.check();assert.equal(await frame.locator('.point').count(),before);
  await checkFrameHeight(element.locator('..'),name);
 }
 checks.push('network and saved diagnostic exports inspect exact units/values and hide/show actual native series');
 await page.setViewportSize({width:390,height:844});
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 checks.push('interactive figures stay within the mobile page width');
 await page.goto(base+'real-packages/datastructures.html',{waitUntil:'networkidle'});
 const mobileContainer=page.locator('#case-SortedSet');
 await mobileContainer.getByRole('tab',{name:'Lookup',exact:true}).click();
 await mobileContainer.locator('iframe').scrollIntoViewIfNeeded();
 await mobileContainer.frameLocator('iframe').locator('svg circle').first().waitFor();
 await checkFrameHeight(mobileContainer,'SortedSet mobile');
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 await mobileContainer.screenshot({path:path.join(output,'sortedset-mobile.png')});
 checks.push('SortedSet native plot axis and point readout fit at desktop and 390px widths without a second vertical scrollbar');
 return checks;
}
