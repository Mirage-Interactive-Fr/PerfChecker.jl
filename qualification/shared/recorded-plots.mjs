import assert from 'node:assert/strict';
import path from 'node:path';

export async function checkRecordedInteractions(page,base,output){
 const checks=[];
 await page.goto(base+'real-packages/datastructures',{waitUntil:'networkidle'});
 const atlas=page.locator('.workload-atlas').first();
 await atlas.locator('#case-Accumulator .normalized-measurements svg').waitFor();
 assert.equal(await atlas.locator('.workload-group').count(),35);
 const groups=atlas.locator('.workload-group');
 for(const group of await groups.all()){
  assert.equal(await group.getByRole('tab').count(),2);
  for(const tab of await group.getByRole('tab').all()){
   await tab.click();
   const plot=group.locator('.normalized-measurements');
   await plot.locator('svg').waitFor();
   const href=await plot.getByRole('link',{name:'Download the plotted values'}).getAttribute('href');
   const record=await (await page.request.get(new URL(href,base).href)).json();
   assert.equal(await plot.locator('circle').count(),record.plot.data.filter(r=>r.ratio!==null).length);
   const first=plot.locator('circle').first();
   await first.focus();
   const text=await plot.locator('.point-reading').innerText();
   const row=record.plot.data.find(r=>r.ratio!==null);
   assert(text.includes(String(row.value))&&text.includes(row.unit)&&text.includes(row.version));
  }
 }
 const accumulator=atlas.locator('#case-Accumulator');
 await accumulator.getByRole('tab',{name:'Construction',exact:true}).click();
 await page.keyboard.press('ArrowRight');
 assert.equal(await accumulator.getByRole('tab',{name:'Traversal',exact:true}).getAttribute('aria-selected'),'true');
 assert((await accumulator.getByRole('tabpanel').innerText()).includes('Construction is excluded'));
 const toggle=accumulator.getByRole('button',{name:'Elapsed time'});
 await toggle.click();assert.equal(await toggle.getAttribute('aria-pressed'),'false');
 await toggle.click();assert.equal(await toggle.getAttribute('aria-pressed'),'true');
 await accumulator.screenshot({path:path.join(output,'accumulator-interactive.png')});
 checks.push('all 70 container operations: tabs, exact saved points and keyboard inspection; Accumulator curve toggles');

 const gallery=page.locator('section[aria-label="DataStructures container catalogue recorded plots"]');
 const catalog=await (await page.request.get(base+'examples/real-packages/containers/catalog.json')).json();
 for(const kind of ['version_series','distribution','version_delta','time_allocation_tradeoff']){
  const view=catalog.views.find(v=>v.kind===kind&&(kind!=='version_delta'||v.metric==='julia.wall.time'));
  await gallery.locator('select').first().selectOption(view.id);
  const graph=gallery.locator('.interactive-recorded');
  await graph.locator('.mark').first().waitFor();
  const record=await (await page.request.get(base+'examples/real-packages/containers/'+view.json)).json();
  const finite=kind==='version_delta'?record.plot.data.filter(r=>r.relative_delta!==null):record.plot.data;
  assert.equal(await graph.locator('.mark').count(),finite.length);
  await graph.locator('.mark').first().focus();assert(!(await graph.locator('.reading').innerText()).startsWith('Select a mark'));
  const width=(await graph.locator('svg').boundingBox()).width;
  await graph.getByRole('button',{name:'Zoom in',exact:true}).click();
  assert((await graph.locator('svg').boundingBox()).width>width*1.4);
  await graph.getByRole('button',{name:'Fit graph',exact:true}).click();
 }
 checks.push('gallery series, samples, deltas and trade-offs expose exact saved records and zoom');
 const chair=page.locator('#case-heap_2048');
 await chair.getByRole('tab',{name:'Chairmarks',exact:true}).click();
 await chair.getByRole('button',{name:'GC share',exact:true}).waitFor();
 assert.equal(await chair.locator('.metric-toggles button').count(),4);
 const href=await chair.getByRole('link',{name:'Download the plotted values'}).getAttribute('href');
 const chairData=await (await page.request.get(new URL(href,base).href)).json();
 const timeRows=chairData.plot.data.filter(r=>r.metric==='julia.wall.time');
 assert(timeRows.every(r=>r.unit==='s'));
 const minimum=Math.min(...timeRows.map(r=>r.value))*1e6;
 assert((await chair.locator('.observation').innerText()).includes(minimum.toFixed(2)+' µs'));
 checks.push('Chairmarks exposes four curves including GC share and converts seconds correctly in captions');

 await page.goto(base+'real-packages/oxygen',{waitUntil:'networkidle'});
 const binary=page.locator('.workload-atlas').first().locator('#case-binary');
 await binary.getByRole('tab',{name:'1.10 patches',exact:true}).click();
 await binary.locator('.normalized-measurements svg').waitFor();
 assert.equal(await binary.locator('.normalized-measurements circle').count(),12);
 assert((await binary.getByRole('tabpanel').innerText()).includes('reference minimum from the complete history'));
 await binary.locator('circle').first().focus();
 assert((await binary.locator('.point-reading').innerText()).includes('1.10.0'));
 await binary.screenshot({path:path.join(output,'oxygen-patch-interactive.png')});
 const profiles=page.locator('.recorded-figures').first();
 for(const label of ['Allocation share','By file','By line','Heatmap','Allocation stacks','CPU stacks','Wall-time stacks','Totals']){
  await profiles.getByRole('tab',{name:label,exact:true}).click();
  const graph=profiles.locator('.interactive-recorded:visible').first();
  await graph.locator('.mark').first().waitFor();
  await graph.locator('.mark').first().focus();
  assert(!(await graph.locator('.reading').innerText()).startsWith('Select a mark'));
  if(label==='Allocation share'){
   assert.equal(await graph.locator('.mark').count(),6);
   assert((await graph.innerText()).includes('Other'));
   await graph.screenshot({path:path.join(output,'oxygen-allocation-interactive.png')});
  }
 }
 checks.push('Oxygen patch tabs preserve full-history normalization; eight profile tabs support point inspection and grouped allocation pie');
 await page.setViewportSize({width:390,height:844});
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 checks.push('interactive figures stay within the mobile page width');
 return checks;
}
