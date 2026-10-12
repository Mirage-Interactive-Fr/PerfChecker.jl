import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {checkInteractiveCatalog,checkRecordedPlotEmbeds} from './recorded-plots.mjs';
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
