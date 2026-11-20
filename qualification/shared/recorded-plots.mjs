import assert from 'node:assert/strict';
import path from 'node:path';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {isVersionComparison,isLatestDiagnostic} from '../../website/src/.vitepress/theme/recorded-view-policy.mjs';

export async function checkInteractiveCatalog(catalog,directory){
 const entries=catalog.views.flatMap(view=>view.normalized_views?.length?
  view.normalized_views:[view,...(view.patch_windows??[])]);
 for(const entry of entries){
  assert(entry.html,`${entry.id??entry.label}: every recorded view needs a native HTML export`);
  const html=await readFile(path.join(directory,entry.html));
  assert(html.length>0,`${entry.html}: empty native export`);
  const source=await readFile(path.join(directory,entry.json));
  if(entry.html_input_sha256)assert.equal(createHash('sha256').update(source).digest('hex'),entry.html_input_sha256);
  if(entry.kind==='normalized_metrics'){
   const record=JSON.parse(await readFile(path.join(directory,entry.plot??entry.json),'utf8'));
   checkNormalizedTimingModel(record.plot);
  }
 }
 return entries.length;
}

export function checkNormalizedTimingModel(model,{sourceRows,collector,xlabel}={}){
 assert.equal(model.kind,'normalized_metrics','Timing collectors use the canonical normalized renderer');
 const metrics=[...new Set(model.data.map(row=>row.metric))];
 assert.equal(metrics.length,4,'Four recorded metrics share one normalized axis');
 for(const metric of ['julia.wall.time','julia.alloc.bytes','julia.alloc.count'])assert(metrics.includes(metric));
 const gc=metrics.filter(metric=>['julia.gc.time','julia.gc.fraction'].includes(metric));
 assert.equal(gc.length,1,'GC is measured, with its original time/fraction semantics');
 if(collector)assert.equal(model.options.collector,collector);
 if(xlabel)assert.equal(model.options.xlabel,xlabel);
 for(const metric of metrics){
  const rows=model.data.filter(row=>row.metric===metric);
  assert.equal(new Set(rows.map(row=>row.version)).size,model.options.versions.length);
  assert.equal(rows.length,model.options.versions.length);
  const reference=model.options.reference_version??'minimum';
  const minimum=reference==='minimum'?rows[0].reference_value:
   rows.find(row=>row.version===reference)?.value;
  assert(Number.isFinite(minimum),'The reference is an actual recorded minimum');
  if(reference==='minimum')assert(minimum<=Math.min(...rows.map(row=>row.value)),
   'A selected window retains its full-history minimum instead of renormalizing');
  for(const row of rows){
   assert(Number.isFinite(row.value)&&row.value>=0,'Every value comes from an available recorded metric');
   assert.equal(row.reference_value,minimum);
   const ratio=minimum===0?(row.value===0?1:null):row.value/minimum;
   assert.equal(row.ratio,ratio);
   assert.equal(row.normalization_status,minimum===0?(row.value===0?'both_zero':'zero_reference'):'ratio',
    'Zero-reference conventions remain explicit rather than inventing observations');
   if(sourceRows){
    const originals=sourceRows.filter(source=>source.metric===row.metric&&source.version===row.version);
    assert.equal(originals.length,1,'A normalized row identifies exactly one original recorded minimum');
    assert.equal(row.value,originals[0].value,'Rendering preserves the source measurement');
    assert.equal(row.unit,originals[0].unit,'Rendering preserves the source unit');
    if(reference==='minimum')assert.equal(minimum,Math.min(...sourceRows.filter(source=>source.metric===metric).map(source=>source.value)));
   }
  }
 }
 if(/chairmarks/i.test(model.options.collector)){
  assert.equal(gc[0],'julia.gc.fraction','Chairmarks measures GC fraction, not GC time');
  assert(model.data.filter(row=>row.metric===gc[0]).every(row=>['1','%'].includes(row.unit)));
 }
 return model.data.length;
}

export async function checkNormalizedObservationSource(record,directory){
 const declaration=record.sample_observations;
 assert(declaration?.file&&declaration.sha256,'Recorded numeric samples are published with their fingerprint');
 const bytes=await readFile(path.join(directory,declaration.file));
 assert.equal(createHash('sha256').update(bytes).digest('hex'),declaration.sha256);
 const observations=bytes.toString('utf8').trim().split('\n').map(line=>JSON.parse(line));
 assert.equal(observations.length,declaration.records);
 const originals=record.plot.data.map(row=>{
  const raw=observations.filter(sample=>sample.run_id===record.run_id&&sample.metric===row.metric&&
   sample.attributes?.version===row.version&&sample.attributes?.feature===record.plot.options.feature);
  assert.equal(raw.length,row.samples,'Every normalized minimum has its actual recorded sample population');
  assert(raw.every(sample=>sample.unit===row.unit&&sample.measurement_definition.endsWith('/'+record.plot.options.collector)),
   'The original metric, unit and collector identity agree');
  return {metric:row.metric,version:row.version,unit:row.unit,value:Math.min(...raw.map(sample=>sample.value))};
 });
 return checkNormalizedTimingModel(record.plot,{sourceRows:originals});
}

export async function checkRecordedPlotEmbeds(source,publicDirectory){
 const embeds=[...source.matchAll(/<(?:InteractiveRecordedPlot|NormalizedMeasurements)\b[^>]*\/?\s*>/g)];
 for(const [tag]of embeds){
  const html=/\bhtml="([^"]+)"/.exec(tag)?.[1];
  const model=/\bsource="([^"]+)"/.exec(tag)?.[1];
  assert(html&&model,'Every documented recorded plot needs its native HTML and serialized model');
  for(const asset of [html,model]){
   const target=path.resolve(publicDirectory,'.'+asset);
   assert(target.startsWith(path.resolve(publicDirectory)+path.sep),'Recorded plot assets remain in the public documentation directory');
   assert((await readFile(target)).length>0,`${asset}: missing or empty recorded plot asset`);
  }
  if(tag.startsWith('<NormalizedMeasurements')){
   const record=JSON.parse(await readFile(path.resolve(publicDirectory,'.'+model),'utf8'));
   checkNormalizedTimingModel(record.plot);
   assert(isVersionComparison(record.plot),`${model}: a displayed comparison needs at least two recorded targets`);
   const native=await readFile(path.resolve(publicDirectory,'.'+html),'utf8');
   const encoded=/const plot=(.*);\n/.exec(native);
   assert(encoded,`${html}: the normalized export contains its actual saved model`);
   const displayed=JSON.parse(encoded[1]);
   assert.deepEqual(displayed.data,record.plot.data,`${html}: displayed values match the source model`);
   assert.deepEqual(displayed.options,record.plot.options,`${html}: displayed units, targets and ratios match the source model`);
  }
 }
 return embeds.length;
}

async function inspectNormalizedRecordedPlot(page,panel,record,label){
 checkNormalizedTimingModel(record.plot);
 assert(isVersionComparison(record.plot),`${label}: History needs at least two actual recorded targets`);
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
 assert.equal(await frame.locator('#controls input').count(),4,`${label}: four superposed metrics`);
 assert.equal(await frame.locator('svg path').count(),4,`${label}: one shared plot contains all four curves`);
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

export async function inspectRecordedFlamePlot(page,graph,record,label){
 const iframe=graph.locator('iframe');
 const href=await graph.getByRole('link',{name:'Open the same interactive export'}).getAttribute('href');
 const expectedURL=new URL(href,page.url()).href;
 const frame=await (await iframe.elementHandle()).contentFrame();
 const rectangles=frame.locator('.flame-frame'),tooltip=frame.getByRole('tooltip');
 const inspection=row=>{
  const lines=['Frame: '+row.label,'Version: '+record.plot.options.selected_version,
   'Path: '+(row.path??[]).join(' → '),'Share: '+row.percentage+'%',
   'Weight: '+row.value+' '+record.plot.options.value_label];
  for(const [key,name]of [['runtime_dispatch','Runtime dispatch'],['gc_event','Garbage collection']])
   if(Number(row[key+'_value'])>0)lines.push(name+': '+row[key+'_percentage']+'% ('+row[key+'_value']+' '+record.plot.options.value_label+')');
  if(row.inference_status?.length)lines.push('Julia inference: '+row.inference_status.join(', '));
  if(row.inferred_return_type?.length)lines.push('Inferred return: '+row.inferred_return_type.join(' | '));
  if((row.inference_status??[]).some(value=>['any','union','abstract'].includes(value)))lines.push('Inspect with @code_warntype or Cthulhu');
  return lines.join('\n');
 };
 const context=()=>frame.evaluate(()=>({url:location.href,
  focused:document.activeElement?.getAttribute('data-index'),
  hovered:document.querySelector('.flame-frame:hover')?.getAttribute('data-index'),
  tooltip:getComputedStyle(document.querySelector('#tooltip')).display,
  readout:document.querySelector('#readout').textContent,viewport:[innerWidth,innerHeight]}));
 const layout=()=>frame.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
 const first=inspection(record.plot.data[0]);
 const hoverIndex=record.plot.data.slice(1).reduce((best,row,index)=>
  row.x1-row.x0>record.plot.data[best].x1-record.plot.data[best].x0?index+1:best,
  Math.min(1,record.plot.data.length-1));
 async function assertKeyboardInspection(stage){
  const diagnostic=`${label} / ${stage} ${JSON.stringify(await context())}`;
  assert.equal(await rectangles.first().evaluate(node=>node===document.activeElement),true,diagnostic);
  assert.equal(await tooltip.isVisible(),true,diagnostic);
  assert.equal(await tooltip.innerText(),first,diagnostic);
  assert.equal(await frame.locator('#readout').innerText(),`Frame 1 of ${record.plot.data.length}\n${first}`,diagnostic);
 }
 try{
  await frame.waitForURL(expectedURL);
  await rectangles.first().waitFor();
  assert.equal(await rectangles.count(),record.plot.data.length);
  assert.equal(await rectangles.first().getAttribute('aria-label'),first);
  await rectangles.first().focus();
  await tooltip.waitFor({state:'visible'});
  await layout();
  await assertKeyboardInspection('initial focus and iframe layout');
  await rectangles.first().hover();
  await page.mouse.move(0,0);
  await assertKeyboardInspection('pointer leaves the focused frame');
  const previousHeight=await iframe.evaluate(node=>node.style.height);
  try{
   const resized=frame.evaluate(()=>new Promise(resolve=>addEventListener('resize',()=>requestAnimationFrame(resolve),{once:true})));
   await iframe.evaluate(node=>{node.style.height=(node.clientHeight+10)+'px'});
   await resized;
   await assertKeyboardInspection('incidental iframe resize');
  }finally{await iframe.evaluate((node,height)=>{node.style.height=height},previousHeight)}
  await frame.getByRole('button',{name:'Zoom in',exact:true}).focus();
  assert.equal(await tooltip.isVisible(),false,`${label}: blur clears the keyboard tooltip`);
  await rectangles.nth(hoverIndex).hover();
  assert.equal(await tooltip.innerText(),inspection(record.plot.data[hoverIndex]),`${label}: pointer inspection is exact`);
  await page.mouse.move(0,0);
  assert.equal(await tooltip.isVisible(),false,`${label}: pointer-only inspection clears on leave`);
 }catch(error){
  error.message=`${label}: ${error.message}\nNative flame context: ${JSON.stringify({expectedURL,model:record.plot.id,...await context()})}`;
  throw error;
 }
}

export async function checkRecordedGalleryInteractions(page,base){
 const checks=[];
 // The container atlas was exercised above. Cover every remaining operation,
 // collector and patch window instead of resurrecting duplicate galleries.
 for(const [route,first]of [['datastructures',1],['oxygen',0]]){
  await page.goto(base+'real-packages/'+route+'.html',{waitUntil:'networkidle'});
  assert.equal(await page.locator('.package-gallery .normalized-measurements').count(),0);
  const atlases=page.locator('.workload-atlas');
  for(let index=first;index<await atlases.count();index++){
   for(const group of await atlases.nth(index).locator('.workload-group').all()){
    const tabs=group.locator('.operation-tabs').getByRole('tab');
    for(let choice=0;choice<Math.max(1,await tabs.count());choice++){
     if(await tabs.count())await tabs.nth(choice).click();
     await group.getByRole('tab',{name:'History',exact:true}).click();
     const graph=group.locator('.normalized-measurements');
     const href=await graph.getByRole('link',{name:'Download the serialized plot'}).getAttribute('href');
     const record=await(await page.request.get(new URL(href,base).href)).json();
     await inspectNormalizedRecordedPlot(page,graph,record,route+' / '+record.plot.id);
    }
   }
  }
 }
 await page.goto(base+'real-packages/datastructures.html',{waitUntil:'networkidle'});
 const atlas=page.locator('.workload-atlas').first();
 const catalog=await(await page.request.get(base+'examples/real-packages/containers-collectors/catalog.json')).json();
 let visited=0;
 for(const view of catalog.views){
  const group=atlas.locator('#case-'+view.title);
  for(const operation of new Set(view.normalized_views.map(child=>child.operation))){
   const label=operation.endsWith('_build')?'Construction':operation.endsWith('_lookup')?'Lookup':operation.endsWith('_drain')?'Drain':operation.endsWith('_traverse')?'Traversal':operation.endsWith('_connectivity')?'Connectivity':'Prefix sums';
   await group.locator('.operation-tabs').getByRole('tab',{name:label,exact:true}).click();
   await group.getByRole('tab',{name:'Latest version',exact:true}).click();
   const latest=group.locator('.latest-evidence');
   assert.equal(await latest.locator('.normalized-measurements,iframe').count(),0,
    'A single-release collector capture is a value table, not a version comparison');
   for(const child of view.normalized_views.filter(child=>child.operation===operation)){
    const record=await(await page.request.get(base+'examples/real-packages/containers-collectors/'+child.plot)).json();
    for(const row of record.plot.data){
     const tableRow=latest.locator('tbody tr').filter({has:page.locator('td').filter({hasText:child.collector})})
      .filter({hasText:row.metric==='julia.wall.time'?'Wall time':row.metric==='julia.gc.fraction'?'GC fraction':row.metric==='julia.alloc.bytes'?'Allocated bytes':'Allocations'});
     assert.equal(await tableRow.count(),1,child.id+' / '+row.metric);
     assert.equal(await tableRow.locator('td').nth(2).innerText(),row.value+' '+row.unit);
    }
    visited++;
   }
   await group.getByRole('tab',{name:'History',exact:true}).click();
  }
 }
 assert.equal(visited,140,'Every operation/collector selection is exercised');
 checks.push('All multi-release atlas selections expose four overlaid curves; all140 single-release collector records remain exact values beside the70 histories');
 return checks;
}

async function checkNativeProfileMenus(page,base){
 let inspected=0;
 async function inspect(graph,label){
  const href=await graph.getByRole('link',{name:'Download the serialized plot',exact:true}).getAttribute('href');
  const record=await(await page.request.get(new URL(href,base).href)).json();
  assert(isLatestDiagnostic(record.plot),`${label}: only actual single-release diagnostics appear`);
  await graph.locator('iframe').scrollIntoViewIfNeeded();
  if(record.plot.kind.endsWith('flamegraph')){
   await inspectRecordedFlamePlot(page,graph,record,label);
  }else{
   const frame=graph.frameLocator('iframe');
   await frame.locator('canvas').waitFor();
   const input=frame.getByRole('spinbutton',{name:'Recorded point index',exact:true});
   assert.equal(Number(await input.getAttribute('max')),record.plot.data.length,`${label}: every saved row remains inspectable`);
   await input.fill(String(record.plot.data.length));
   await frame.locator('#point-readout[aria-busy="false"]').waitFor();
   assert((await frame.locator('#point-readout').innerText()).startsWith(`Point ${record.plot.data.length}:`),label);
   const before=await frame.locator('#offline-figure').boundingBox();
   await frame.getByRole('button',{name:'Zoom in',exact:true}).click();
   assert((await frame.locator('#offline-figure').boundingBox()).width>before.width*1.4,`${label}: native viewport zoom`);
   await frame.getByRole('button',{name:'Fit plot',exact:true}).click();
  }
  inspected++;
 }
 for(const [route,workloads]of [['datastructures',['heap_2048','counter_2048']],['oxygen',['heap_request']]]){
  await page.goto(base+'real-packages/'+route+'.html',{waitUntil:'networkidle'});
  for(const workload of workloads){
   const group=page.locator('#case-'+workload);
   await group.getByRole('tab',{name:'Latest version',exact:true}).click();
   const profiles=group.locator('.recorded-figures');
   const tabs=profiles.getByRole('tab');
   await tabs.first().waitFor({state:'visible'});
   assert((await tabs.count())>=3,`${route}/${workload}: the profile tabs have actually loaded`);
   for(let index=0;index<await tabs.count();index++){
    await tabs.nth(index).click();
    for(const graph of await profiles.locator('.recorded-export:visible').all())
     await inspect(graph,route+' / '+workload+' / '+await tabs.nth(index).innerText());
   }
  }
 }
 for(const [name,destination]of [['BenchmarkTools','tools/benchmarktools.html'],['JET','tools/jet.html'],
  ['native profiles','tools/callgrind.html'],['saved results','tools/results.html'],
  ['interface pages','interfaces/visualization.html']]){
  await page.goto(base+'real-packages/extensions.html#Allocation,-CPU-and-wall-time-profiles',{waitUntil:'networkidle'});
  assert.equal(await page.locator('.vp-doc [id="Allocation,-CPU-and-wall-time-profiles"]').count(),1,
   'The compatibility page preserves the old profile fragment');
  assert.equal(await page.locator('.vp-doc iframe').count(),0,'Tool recipes is a compatibility link page');
  const link=page.locator('.vp-doc').getByRole('link',{name,exact:true});
  assert.equal(new URL(await link.getAttribute('href'),page.url()).href,new URL(destination,base).href);
  await link.click();
  await page.waitForURL(new URL(destination,base).href);
  await page.locator('.vp-doc h1').waitFor({state:'visible'});
 }
 for(const [route,kind]of [['allocation-profile','allocation_flamegraph'],['cpu-profile','cpu_flamegraph'],
  ['wall-profile','wall_flamegraph']]){
  await page.goto(base+'tools/'+route+'.html',{waitUntil:'networkidle'});
  const graph=page.locator('.vp-doc .recorded-export');
  const source=await graph.getByRole('link',{name:'Download the serialized plot',exact:true}).getAttribute('href');
  assert.equal((await(await page.request.get(new URL(source,base).href)).json()).plot.kind,kind,
   `${route}: the practical page opens its actual profile family`);
  await inspect(graph,'Tool / '+route);
  const frame=graph.frameLocator('iframe'),fitted=await frame.locator('#flame').boundingBox();
  await frame.getByRole('button',{name:'Zoom in',exact:true}).click();
  assert((await frame.locator('#flame').boundingBox()).width>fitted.width*1.4,`${route}: native viewport zoom`);
  await frame.getByRole('button',{name:'Fit graph',exact:true}).click();
  assert(Math.abs((await frame.locator('#flame').boundingBox()).width-fitted.width)<2,`${route}: fit restores the viewport`);
 }
 return `${inspected} native profile selections across both DataStructures workloads, Oxygen and three practical tool pages preserve their saved models and working controls; Tool recipe compatibility links resolve`;
}

async function checkFrameHeight(page,container,label){
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

export async function checkRecordedInteractions(page,base,output){
 const checks=[];
 await page.goto(base+'real-packages/datastructures.html',{waitUntil:'networkidle'});
 const atlas=page.locator('.workload-atlas').first();
 await atlas.locator('#case-Accumulator .normalized-measurements iframe').scrollIntoViewIfNeeded();
 assert.equal(await atlas.locator('.workload-group').count(),35);
 const groups=atlas.locator('.workload-group');
 for(const group of await groups.all()){
  assert.equal(await group.locator('.operation-tabs').getByRole('tab').count(),2);
  for(const tab of await group.locator('.operation-tabs').getByRole('tab').all()){
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
 const operationPanel=await accumulator.getByRole('tab',{name:'Traversal',exact:true}).getAttribute('aria-controls');
 assert((await accumulator.locator('[id="'+operationPanel+'"]').innerText()).includes('Construction is excluded'));
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
 await checkFrameHeight(page,selectedContainer,'SortedSet desktop');
 await selectedContainer.screenshot({path:path.join(output,'sortedset-interactive.png')});
 checks.push('all 70 container operations use their native interactive export; exact SortedSet points and curve toggles work; operation tabs support the keyboard');

 checks.push(...await checkRecordedGalleryInteractions(page,base));
 checks.push(...await checkRecordedDiagnosticInteractions(page,base,output));
 return checks;
}

export async function checkRecordedDiagnosticInteractions(page,base,output){
 const checks=[];
 checks.push(await checkNativeProfileMenus(page,base));

 await page.goto(base+'real-packages/oxygen.html',{waitUntil:'networkidle'});
 const binary=page.locator('.workload-atlas').first().locator('#case-binary');
 await binary.getByRole('tab',{name:'1.10 patches',exact:true}).click();
 await binary.frameLocator('iframe').locator('circle').first().waitFor();
 const binaryHref=await binary.getByRole('link',{name:'Download the serialized plot'}).getAttribute('href');
 const binaryData=await (await page.request.get(new URL(binaryHref,base).href)).json();
 assert.equal(binaryData.plot.data.filter(row=>row.ratio!==null).length,12);
 assert((await binary.locator('.history-evidence').innerText()).includes('reference minimum from the complete history'));
 assert(binaryData.plot.data.some(row=>row.version==='1.10.0'));
 await binary.screenshot({path:path.join(output,'oxygen-patch-interactive.png')});
 await page.locator('#case-heap_request').getByRole('tab',{name:'Latest version',exact:true}).click();
 const profiles=page.locator('#case-heap_request .recorded-figures');
 for(const label of ['Allocation share','By line','Allocation stacks','CPU stacks','Wall-time stacks']){
  await profiles.getByRole('tab',{name:label,exact:true}).click();
  const graph=profiles.locator('.recorded-export:visible').first();
  const profileSource=await graph.getByRole('link',{name:'Download the serialized plot'}).getAttribute('href');
  const profileRecord=await(await page.request.get(new URL(profileSource,base).href)).json();
  assert(isLatestDiagnostic(profileRecord.plot),`${label}: latest diagnostics use one actual release and no versioned plot family`);
  if(label.endsWith('stacks')){
   const frame=graph.frameLocator('iframe');
   const rectangles=frame.locator('.flame-frame');
   await rectangles.first().waitFor();
   const source=await graph.getByRole('link',{name:'Download the serialized plot'}).getAttribute('href');
   const record=await (await page.request.get(new URL(source,base).href)).json();
   assert.equal(await rectangles.count(),record.plot.data.length);
   await inspectRecordedFlamePlot(page,graph,record,label);
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
 assert.equal(await profiles.getByRole('tab',{name:/^(By file|Allocation history|Totals)$/}).count(),0);
 checks.push('Oxygen patch plots preserve full-history normalization; latest profiles contain only single-release stacks, allocation pie and by-line diagnostics');
 checks.push(...await checkRecordedObservationInteractions(page,base,output));
 return checks;
}

export async function checkRecordedObservationInteractions(page,base,output){
 const checks=[];
 for(const [route,name]of [['real-packages/oxygen.html','Oxygen network'],
  ['tools/latency.html','saved latency diagnostics'],['tools/memory.html','saved memory diagnostics']]){
  await page.goto(base+route,{waitUntil:'networkidle'});
  const frames=page.locator('iframe[src*="oxygen-network/"],iframe[src*="datastructures-diagnostics/"]');
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
  await checkFrameHeight(page,element.locator('..'),name);
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
 await checkFrameHeight(page,mobileContainer,'SortedSet mobile');
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 await mobileContainer.screenshot({path:path.join(output,'sortedset-mobile.png')});
 checks.push('SortedSet native plot axis and point readout fit at desktop and 390px widths without a second vertical scrollbar');
 return checks;
}
