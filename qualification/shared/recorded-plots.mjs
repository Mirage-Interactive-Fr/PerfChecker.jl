import assert from 'node:assert/strict';
import path from 'node:path';

export async function checkRecordedInteractions(page,base,output){
 const checks=[];
 async function checkFrameHeight(container,label){
  const iframe=container.locator('iframe');
  await iframe.scrollIntoViewIfNeeded();
  await page.waitForFunction(frame=>{
   const body=frame.contentDocument?.body;
   const readout=frame.contentDocument?.querySelector('#readout');
   return body&&readout&&body.scrollHeight<=frame.clientHeight+2&&
    readout.getBoundingClientRect().bottom<=frame.clientHeight+2;
  },await iframe.elementHandle(),{timeout:10000});
  const fits=await iframe.evaluate(frame=>frame.contentDocument.body.scrollHeight<=frame.clientHeight+2);
  assert(fits,`${label}: the native export fits without a second vertical scrollbar`);
 }
 await page.goto(base+'real-packages/datastructures.html',{waitUntil:'networkidle'});
 const atlas=page.locator('.workload-atlas').first();
 await atlas.locator('#case-Accumulator .normalized-measurements img').evaluate(image=>image.decode());
 assert.equal(await atlas.locator('.workload-group').count(),35);
 const groups=atlas.locator('.workload-group');
 for(const group of await groups.all()){
  assert.equal(await group.getByRole('tab').count(),2);
  for(const tab of await group.getByRole('tab').all()){
   await tab.click();
   const plot=group.locator('.normalized-measurements');
   const href=await plot.getByRole('link',{name:'Download the serialized plot'}).getAttribute('href');
   const record=await (await page.request.get(new URL(href,base).href)).json();
   if(await plot.locator('iframe').count()){
    const frame=plot.frameLocator('iframe');
    await frame.locator('svg circle').first().waitFor();
    assert.equal(await frame.locator('circle').count(),record.plot.data.filter(r=>r.ratio!==null).length);
    await frame.locator('circle').first().focus();
    const text=await frame.locator('#readout').innerText(),row=record.plot.data.find(r=>r.ratio!==null);
    assert(text.includes(String(row.value))&&text.includes(row.unit)&&text.includes(row.version));
   }else{
    const image=plot.locator('img');await image.evaluate(image=>image.decode());
    assert.equal(new URL(await image.getAttribute('src'),base).pathname,
     new URL(href,base).pathname.replace(/\.json$/,'.svg'),'The fallback is the actual matching public SVG');
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
 checks.push('all 70 container operations retain their matching public SVG/data; guided SortedSet points and curve toggles work; operation tabs support the keyboard');

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
  const fallback=catalog.views.find(v=>v.kind===kind&&!v.html);
  await gallery.locator('select').first().selectOption(fallback.id);
  const image=graph.locator('img');await image.evaluate(element=>element.decode());
  assert.equal(new URL(await image.getAttribute('src'),base).href,
   new URL('examples/real-packages/containers/'+fallback.svg,base).href);
  assert.equal(await graph.locator('iframe').count(),0);
 }
 checks.push('guided series, samples, deltas and trade-offs load their real native WGL exports and inspect saved rows; other catalogue entries retain exact SVG fallbacks');
 const chair=page.locator('#case-heap_2048');
 await chair.getByRole('tab',{name:'Chairmarks',exact:true}).click();
 await chair.locator('img').evaluate(image=>image.decode());
 const href=await chair.getByRole('link',{name:'Download the serialized plot'}).getAttribute('href');
 const chairData=await (await page.request.get(new URL(href,base).href)).json();
 assert.equal(new Set(chairData.plot.data.map(row=>row.metric)).size,4);
 assert(chairData.plot.data.some(row=>row.metric==='julia.gc.fraction'));
 const timeRows=chairData.plot.data.filter(r=>r.metric==='julia.wall.time');
 assert(timeRows.every(r=>r.unit==='s'));
 const minimum=Math.min(...timeRows.map(r=>r.value))*1e6;
 assert((await chair.locator('.observation').innerText()).includes(minimum.toFixed(2)+' µs'));
 checks.push('Chairmarks retains four measurements including GC share, its genuine SVG, and correct seconds-to-microseconds captions');

 await page.goto(base+'real-packages/oxygen.html',{waitUntil:'networkidle'});
 const binary=page.locator('.workload-atlas').first().locator('#case-binary');
 await binary.getByRole('tab',{name:'1.10 patches',exact:true}).click();
 await binary.locator('img').evaluate(image=>image.decode());
 const binaryHref=await binary.getByRole('link',{name:'Download the serialized plot'}).getAttribute('href');
 const binaryData=await (await page.request.get(new URL(binaryHref,base).href)).json();
 assert.equal(binaryData.plot.data.filter(row=>row.ratio!==null).length,12);
 assert((await binary.getByRole('tabpanel').innerText()).includes('reference minimum from the complete history'));
 assert(binaryData.plot.data.some(row=>row.version==='1.10.0'));
 await binary.screenshot({path:path.join(output,'oxygen-patch-static.png')});
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
  }else if(await graph.locator('iframe').count()){
   await graph.locator('iframe').scrollIntoViewIfNeeded();
   const frame=graph.frameLocator('iframe');await frame.locator('canvas').waitFor();
   const input=frame.getByRole('spinbutton',{name:'Recorded point index',exact:true});
   await input.fill(await input.getAttribute('max'));
   await frame.locator('#point-readout[aria-busy="false"]').waitFor();
   assert((await frame.locator('#point-readout').innerText()).startsWith('Point '+await input.inputValue()+':'));
  }else{
   await graph.locator('img').evaluate(element=>element.decode());
   assert.equal(await graph.locator('iframe').count(),0);
  }
  if(label==='Allocation share'){
   await graph.screenshot({path:path.join(output,'oxygen-allocation-interactive.png')});
  }
 }
 checks.push('Oxygen patch SVG/data preserve full-history normalization; seven native profile families load and inspect recorded observations; isolated profile totals retain their static exports');
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
