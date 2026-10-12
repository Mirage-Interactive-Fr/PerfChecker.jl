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

async function inspectNormalizedRecordedPlot(page,panel,record,label){
 const iframe=panel.locator('iframe');
 const href=await panel.getByRole('link',{name:'Open the same interactive export'}).getAttribute('href');
 const expectedURL=new URL(href,page.url()).href;
 const frame=await (await iframe.elementHandle()).contentFrame();
 assert(frame,`${label}: the selected native export has a frame`);
 const data=JSON.stringify(record.plot.data),options=JSON.stringify(record.plot.options);
 await frame.waitForFunction(({url,data,options})=>location.href===url&&
  typeof plot!=='undefined'&&JSON.stringify(plot.data)===data&&JSON.stringify(plot.options)===options,
  {url:expectedURL,data,options},{timeout:10000});
 const points=frame.locator('svg circle');
 await points.first().waitFor();
 assert.equal(await points.count(),record.plot.data.filter(row=>row.ratio!==null).length,label);
 const pointLabel=row=>row.version+' · '+row.metric+': '+row.value+' '+row.unit+
  ' · ratio '+(row.ratio??'unavailable')+' · '+row.normalization_status;
 const last=points.last(),hoverLabel=await last.getAttribute('aria-label');
 const hoverRow=record.plot.data.find(row=>row.ratio!==null&&pointLabel(row)===hoverLabel);
 assert(hoverRow,`${label}: the hovered point belongs to the selected saved model`);
 await last.hover();
 assert.equal(await frame.locator('#readout').innerText(),pointLabel(hoverRow),`${label}: pointer inspection`);
 // Focus can scroll an iframe beneath the pointer left by an operation-tab click.
 // Keep pointer inspection and keyboard inspection separate so a legitimate
 // mouseenter cannot replace the value whose keyboard focus we are asserting.
 await page.mouse.move(0,0);
 await points.first().focus();
 const row=record.plot.data.find(row=>row.ratio!==null),expected=pointLabel(row);
 const actual=await frame.locator('#readout').innerText();
 const context=await frame.evaluate(()=>({url:location.href,model:plot.id,title:plot.title,
  focused:document.activeElement?.getAttribute('aria-label'),
  hovered:document.querySelector('circle:hover')?.getAttribute('aria-label'),
  readout:document.querySelector('#readout')?.innerText}));
 assert.equal(actual,expected,`${label}: keyboard inspection ${JSON.stringify({expectedURL,
  expectedModel:record.plot.id,expected,...context})}`);
}

export async function checkRecordedGalleryInteractions(page,base){
 const checks=[];
 const gallery=page.locator('section[aria-label="DataStructures container catalogue recorded plots"]');
 const catalogSource=await (await page.request.get(base+'examples/real-packages/containers/catalog.json')).body();
 const catalog=JSON.parse(catalogSource.toString('utf8'));
 const selection=gallery.getByRole('combobox',{name:/^Explore the recorded measurements/});
 const family=gallery.getByRole('combobox',{name:/^Plot family/});
 const sources=new Map();
 async function readView(view){
  const response=await page.request.get(base+'examples/real-packages/containers/'+view.json);
  assert.equal(response.status(),200,`${view.id}: serialized source is available`);
  const source=await response.body();sources.set(view.id,source);
  return JSON.parse(source.toString('utf8'));
 }
 async function selectView(view){
  await selection.selectOption(view.id);
  const graph=gallery.locator('.recorded-export');
  const iframe=graph.locator('iframe');
  await iframe.scrollIntoViewIfNeeded();
  const frame=await (await iframe.elementHandle()).contentFrame();
  await frame.waitForURL(base+'examples/real-packages/containers/'+view.html);
  await frame.locator('canvas').waitFor();
  assert.equal(await graph.locator('img').count(),0);
  return {graph,frame};
 }
 async function inspectView(view){
  const record=await readView(view),{frame}=await selectView(view);
  assert.equal(record.plot.kind,view.kind);
  const fields=view.kind==='version_delta'?['relative_delta']:
   view.kind==='time_allocation_tradeoff'?['bytes','time']:['value'];
  const rows=record.plot.data.filter(row=>fields.every(field=>Number.isFinite(row[field])));
  assert(rows.length>0,`${view.id}: inspection uses actual finite saved rows`);
  const input=frame.getByRole('spinbutton',{name:'Recorded point index',exact:true});
  assert.equal(Number(await input.getAttribute('max')),rows.length);
  await frame.locator('#point-index[data-applied-index="1"]').waitFor();
  await frame.locator('#point-readout[aria-busy="false"]').waitFor();
  await input.fill(String(rows.length));
  await frame.locator(`#point-index[data-applied-index="${rows.length}"]`).waitFor();
  const readout=frame.locator('#point-readout[aria-busy="false"]');
  await readout.waitFor();
  assert.equal(await readout.getAttribute('data-error'),null,`${view.id}: native point inspection succeeds`);
  assert.equal(await input.getAttribute('data-applied-index'),String(rows.length),`${view.id}: native highlight follows the selected row`);
  const text=await readout.innerText(),row=rows.at(-1),prefix=`Point ${rows.length}: `;
  if(view.kind==='version_delta'){
   const start=prefix+`${row.baseline_version} → ${row.candidate_version} · change: `;
   const end=`% · ${row.status??'unknown'}`;
   assert(text.startsWith(start)&&text.endsWith(end),`${view.id}: exact comparison and status`);
   assert.equal(Number(text.slice(start.length,-end.length)),100*row.relative_delta);
  }else if(view.kind==='time_allocation_tradeoff'){
   const response=await page.request.get(base+'examples/real-packages/containers/'+view.html);
   assert.equal(response.status(),200);
   const model=/const model = (\{[^\n]+\});/.exec(await response.text());
   assert(model,`${view.id}: the native export retains its serialized model`);
   const exported=JSON.parse(model[1]),units=exported.options;
   assert.equal(exported.id,record.plot.id);assert.equal(exported.kind,record.plot.kind);
   assert.deepEqual(exported.data,record.plot.data,`${view.id}: native time/allocation values are unchanged`);
   if(units.time_unit!==record.plot.options.time_unit||units.allocation_unit!==record.plot.options.allocation_unit){
    const provenance=units.unit_provenance;
    assert.equal(provenance?.saved_model_sha256,
     createHash('sha256').update(sources.get(view.id)).digest('hex'),
     `${view.id}: explicit native units retain provenance to the exact saved source`);
    assert.equal(provenance.catalog_sha256,createHash('sha256').update(catalogSource).digest('hex'));
    assert.equal(provenance.sources.length,2);
    for(const [metric,field,unit]of [['julia.wall.time','time',units.time_unit],['julia.alloc.bytes','bytes',units.allocation_unit]]){
     const source=provenance.sources.find(item=>item.metric===metric);
     assert(source,`${view.id}: ${metric} has a published source`);
     const response=await page.request.get(base+'examples/real-packages/containers/'+source.json);
     assert.equal(response.status(),200);const bytes=await response.body();
     assert.equal(createHash('sha256').update(bytes).digest('hex'),source.sha256);
     const published=JSON.parse(bytes.toString('utf8')).plot;
     assert.equal(published.options.metric,metric);assert.equal(published.options.unit,unit);
     assert.equal(source.unit,unit);assert.equal(published.options.series_id,source.series_id);
     for(const row of exported.data){
      const matches=published.data.filter(item=>item.version===row.version&&item.target_kind===row.target_kind);
      assert.equal(matches.length,1);assert.equal(matches[0].value,row[field]);
     }
    }
   }
   const start=prefix+row.version+' · ',middle=` ${units.allocation_unit??'unit unspecified'} · `;
   const end=` ${units.time_unit??'unit unspecified'}`;
   assert(text.startsWith(start)&&text.endsWith(end),`${view.id}: exact version and units`);
   const values=text.slice(start.length,-end.length).split(middle);
   assert.equal(values.length,2);assert.equal(Number(values[0]),row.bytes);assert.equal(Number(values[1]),row.time);
  }else{
   const start=prefix+row.version+' · ',end=' '+record.plot.options.unit;
   assert(text.startsWith(start)&&text.endsWith(end),`${view.id}: exact version and unit`);
   assert.equal(Number(text.slice(start.length,-end.length)),row.value);
  }
 }
 const unavailable=catalog.views.find(view=>view.kind==='version_delta'&&view.html);
 const emptyRecord=await readView(unavailable);
 assert.equal(emptyRecord.plot.data.length,6,'The recorded zero-baseline comparison remains covered');
 assert(emptyRecord.plot.data.every(row=>row.relative_delta===null&&row.baseline_value===0&&
  row.candidate_value===0&&row.absolute_delta===0));
 const {graph,frame}=await selectView(unavailable);
 const notice=graph.locator('.unavailable-delta');
 await notice.waitFor();
 assert((await notice.innerText()).includes('Relative change unavailable for 6 recorded comparisons.'));
 assert((await notice.innerText()).includes('Every baseline is zero, so a percentage would divide by zero.'));
 const tableRows=notice.locator('tbody tr');
 assert.equal(await tableRows.count(),emptyRecord.plot.data.length);
 for(const [index,row]of emptyRecord.plot.data.entries()){
  assert.deepEqual(await tableRows.nth(index).locator('td').allTextContents(),[
   `${row.baseline_version} → ${row.candidate_version}`,`${row.baseline_value} ${row.unit}`,
   `${row.candidate_value} ${row.unit}`,`${row.absolute_delta} ${row.unit}`]);
 }
 assert.equal(await frame.getByRole('spinbutton',{name:'Recorded point index',exact:true}).count(),0,
  'A delta with no finite ratios does not invent inspectable points');
 for(const kind of ['version_series','distribution','version_delta','time_allocation_tradeoff']){
  let view=catalog.views.find(v=>v.kind===kind&&v.html);
  if(kind==='version_delta'){
   await family.selectOption('version_delta');
   await page.waitForFunction(({select,family,ids})=>!family.disabled&&ids.includes(select.value),
    {select:await selection.elementHandle(),family:await family.elementHandle(),
     ids:catalog.views.filter(v=>v.kind===kind&&v.metric==='julia.wall.time').map(v=>v.id)});
   const selected=await selection.inputValue();
   view=catalog.views.find(v=>v.id===selected);
   assert(view&&view.id!==unavailable.id&&view.kind===kind&&view.metric==='julia.wall.time',
    'The delta shortcut selects a recorded time comparison with a finite relative change');
  }
  await inspectView(view);
  const other=catalog.views.find(v=>v.kind===kind&&v.id!==view.id&&v.html&&v.id!==unavailable.id);
  assert(other,'Non-default catalogue entries are interactive too');
  await inspectView(other);
 }
 checks.push('series, samples, deltas and trade-offs inspect exact saved rows, including non-default entries; zero-baseline deltas preserve six absolute comparisons and finite delta selection');
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
 await inspectNormalizedRecordedPlot(page,chair,chairData,'Chairmarks heap_2048');
 checks.push('Chairmarks retains four interactive measurements including GC share and correct seconds-to-microseconds captions');
 return checks;
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
   await inspectNormalizedRecordedPlot(page,plot,record,
    `${await group.locator('h4').innerText()} / ${await tab.innerText()}`);
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

 checks.push(...await checkRecordedGalleryInteractions(page,base));

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
