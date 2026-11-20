import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {checkInteractiveCatalog,checkRecordedPlotEmbeds,checkNormalizedTimingModel} from './recorded-plots.mjs';
import {isVersionComparison,isLatestDiagnostic,recordedVersions} from '../../website/src/.vitepress/theme/recorded-view-policy.mjs';
test('Normalized timing qualification checks original minima, not only consistent ratios',()=>{
 const originals=[['julia.wall.time','s',2],['julia.gc.fraction','1',0],
  ['julia.alloc.bytes','By',128],['julia.alloc.count','1',3]].map(([metric,unit,value])=>
  ({metric,unit,value,version:'1.0.0'}));
 const model={kind:'normalized_metrics',options:{collector:'Chairmarks',versions:['1.0.0']},
  data:originals.map(row=>({...row,reference_value:row.value,ratio:1,
   normalization_status:row.value===0?'both_zero':'ratio'}))};
 assert.equal(checkNormalizedTimingModel(model,{sourceRows:originals,collector:'Chairmarks'}),4);
 const wrong=structuredClone(model);wrong.data[0].value=20;wrong.data[0].reference_value=20;
 assert.throws(()=>checkNormalizedTimingModel(wrong,{sourceRows:originals}),/source measurement/);
 const absent=structuredClone(model);absent.data.splice(1,1);
 assert.throws(()=>checkNormalizedTimingModel(absent),/Four recorded metrics/);
 const falseGC=structuredClone(model);falseGC.data[1].metric='julia.gc.time';
 assert.throws(()=>checkNormalizedTimingModel(falseGC),/Chairmarks measures GC fraction/);
 const baseline={kind:'normalized_metrics',options:{collector:'BenchmarkTools',
  versions:['dynamic','typed'],reference_version:'dynamic',xlabel:'Implementation'},
  data:originals.flatMap(row=>['dynamic','typed'].map(version=>{
   const value=version==='typed'&&row.metric!=='julia.gc.fraction'?0:row.value;
   return {...row,version,value,reference_value:row.value,ratio:row.value===0?1:value/row.value,
    normalization_status:row.value===0?'both_zero':'ratio'};
  }))};
 assert.equal(checkNormalizedTimingModel(baseline,{xlabel:'Implementation'}),8);
 assert(baseline.data.filter(row=>row.version==='typed').some(row=>row.ratio===0));
});
test('Inventory includes non-default views and every patch window',async t=>{
 const directory=await mkdtemp(path.join(tmpdir(),'perfchecker-plot-inventory-'));
 t.after(()=>rm(directory,{recursive:true,force:true}));
 const entry=id=>({id,html:id+'.html',json:id+'.json'});
 const first=entry('default'),other=entry('non-default'),patch=entry('patch-window');
 first.patch_windows=[patch];const catalog={views:[first,other]};
 for(const item of [first,other,patch]){
  await writeFile(path.join(directory,item.html),'<html>native fixture</html>');
  await writeFile(path.join(directory,item.json),'{}');
 }
 assert.equal(await checkInteractiveCatalog(catalog,directory),3);
 await rm(path.join(directory,other.html));
 await assert.rejects(checkInteractiveCatalog(catalog,directory),{code:'ENOENT'});
 await writeFile(path.join(directory,other.html),'<html>native fixture</html>');
 await rm(path.join(directory,patch.html));
 await assert.rejects(checkInteractiveCatalog(catalog,directory),{code:'ENOENT'});
 await writeFile(path.join(directory,patch.html),'<html>native fixture</html>');
 delete patch.html;
 await assert.rejects(checkInteractiveCatalog(catalog,directory),/every recorded view/);
});
test('Documented recorded plots require real HTML and model assets',async t=>{
 const directory=await mkdtemp(path.join(tmpdir(),'perfchecker-plot-embeds-'));
 t.after(()=>rm(directory,{recursive:true,force:true}));
 await writeFile(path.join(directory,'native.html'),'<html>native fixture</html>');
 await writeFile(path.join(directory,'native.plot.json'),'{}');
 const tag='<InteractiveRecordedPlot html="/native.html" source="/native.plot.json" title="Recorded evidence" />';
 assert.equal(await checkRecordedPlotEmbeds(tag,directory),1);
 await assert.rejects(checkRecordedPlotEmbeds(tag.replace(' html="/native.html"',''),directory),/native HTML/);
 await rm(path.join(directory,'native.html'));
 await assert.rejects(checkRecordedPlotEmbeds(tag,directory),{code:'ENOENT'});
});
test('Normalized embeds display the exact source values and reference options',async t=>{
 const directory=await mkdtemp(path.join(tmpdir(),'perfchecker-normalized-embed-'));
 t.after(()=>rm(directory,{recursive:true,force:true}));
 const model={kind:'normalized_metrics',options:{collector:'BenchmarkTools',versions:['1.0.0','1.0.1']},
  data:[['julia.wall.time','s',2],['julia.gc.time','s',0],
   ['julia.alloc.bytes','By',128],['julia.alloc.count','1',3]].flatMap(([metric,unit,value])=>
   ['1.0.0','1.0.1'].map(version=>({metric,unit,value,version,reference_value:value,ratio:1,
    normalization_status:value===0?'both_zero':'ratio'})))};
 await writeFile(path.join(directory,'native.json'),JSON.stringify({plot:model}));
 const html=plot=>'<script>const plot='+JSON.stringify(plot)+';\n</script>';
 await writeFile(path.join(directory,'native.html'),html(model));
 const tag='<NormalizedMeasurements source="/native.json" html="/native.html" />';
 assert.equal(await checkRecordedPlotEmbeds(tag,directory),1);
 const changed=structuredClone(model);changed.options.reference_version='invented';
 await writeFile(path.join(directory,'native.html'),html(changed));
 await assert.rejects(checkRecordedPlotEmbeds(tag,directory),/ratios match the source model/);
 changed.options=model.options;changed.data[0].value=200;
 await writeFile(path.join(directory,'native.html'),html(changed));
 await assert.rejects(checkRecordedPlotEmbeds(tag,directory),/displayed values match the source model/);
});
test('Release comparisons use observed targets and single-release diagnostics keep their proper families',()=>{
 const single={kind:'version_series',options:{versions:['0.19.0','0.19.6']},data:[{version:'0.19.6',value:4}]};
 assert.deepEqual(recordedVersions(single),['0.19.6']);
 assert.equal(isVersionComparison(single),false,'An advertised range does not fabricate observations');
 assert.equal(isLatestDiagnostic(single),false,'A one-point trajectory is not a diagnostic');
 for(const kind of ['allocation_files','allocation_heatmap','version_series'])
  assert.equal(isLatestDiagnostic({...single,kind}),false);
 for(const kind of ['allocation_pie','allocation_lines'])
  assert.equal(isLatestDiagnostic({...single,kind}),true);
 for(const kind of ['cpu_flamegraph','wall_flamegraph','allocation_flamegraph'])
  assert.equal(isLatestDiagnostic({kind,options:{selected_version:'1.11.0'},data:[{value:2}]}),true);
 assert.equal(isVersionComparison({...single,data:[{version:'0.19.0',value:2},...single.data]}),true);
});
