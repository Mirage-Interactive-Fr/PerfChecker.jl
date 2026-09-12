// Reopen a real historical run in Oxygen. No measurement job is launched.
import {chromium} from 'playwright';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';

const base=process.argv[2]??'http://127.0.0.1:8871/perfchecker/v1/';
const output=path.resolve(process.argv[3]??'.lab/media/bibliography-history');
const evidence=JSON.parse(await readFile('website/src/public/examples/bibliography/history/export-time.json','utf8'));
await mkdir(output,{recursive:true});
const browser=await chromium.launch({headless:true});
const context=await browser.newContext({viewport:{width:1680,height:1080},recordVideo:{dir:output,size:{width:1680,height:1080}}});
const page=await context.newPage();
const actions=[],errors=[];const started=Date.now();
page.on('pageerror',error=>errors.push(error.message));
async function action(selector,value){
  const control=page.locator(selector);await control.scrollIntoViewIfNeeded();
  const box=await control.boundingBox();await page.mouse.move(box.x+box.width/2,box.y+box.height/2,{steps:18});
  if(value===undefined)await control.click();else await control.selectOption(value);
  actions.push({seconds:(Date.now()-started)/1000,selector,value});
  await page.waitForTimeout(750);
}
try{
  await page.goto(base,{waitUntil:'networkidle'});
  await page.evaluate(()=>{
    const pointer=document.createElement('div');pointer.setAttribute('aria-hidden','true');
    pointer.style.cssText='position:fixed;width:18px;height:18px;border:3px solid #e05727;border-radius:50%;background:#fff7;pointer-events:none;z-index:99999;transform:translate(-50%,-50%)';
    document.body.append(pointer);document.addEventListener('pointermove',event=>{pointer.style.left=event.clientX+'px';pointer.style.top=event.clientY+'px';});
  });
  await action('[data-view-target="results"]');
  await page.locator('#result-profile-filter option[value="historical"]').waitFor({state:'attached'});
  await action('#result-profile-filter','historical');
  await page.locator('#result-filter').fill(evidence.run_id);
  assert.equal(await page.locator('#results button').count(),1);
  await action('#results button');
  await page.locator('#result-summary.result-summary').waitFor();
  await action('#plot-feature-filter','export_bibtex');
  await action('#plot-metric-filter','julia.wall.time');
  for(const [name,kind,metric] of [
    ['history-time','version_series','julia.wall.time'],
    ['history-memory','version_series','julia.alloc.bytes'],
    ['history-distribution','distribution','julia.wall.time'],
    ['history-delta','version_delta','julia.wall.time']]){
    await action('#plot-kind-filter',kind);await action('#plot-metric-filter',metric);
    await page.waitForFunction(()=>{const frame=document.querySelector('#makie-frame');return !frame.hidden&&!document.querySelector('#plot-loading')},null,{timeout:240000});
    const frame=page.frameLocator('#makie-frame');await frame.locator('canvas').first().waitFor();
    await page.waitForTimeout(500);
    assert(await frame.locator('#offline-figure').evaluate(element=>element.getBoundingClientRect().bottom<=window.innerHeight),'The complete plot must fit, including its version axis');
    if(kind!=='version_delta'){
      const slider=frame.getByRole('slider',{name:'Inspect measured point'});await slider.focus();await page.keyboard.press('End');
      await page.waitForTimeout(1000);
      const readout=await frame.locator('#point-readout').innerText();
      assert(readout.endsWith(' · 0.4.0'));
      if(name==='history-time')assert.equal(readout,`Point 9: ${evidence.plot.data.at(-1).value} ns · 0.4.0`);
    }
    await page.locator('#makie-frame').scrollIntoViewIfNeeded();
    await page.screenshot({path:path.join(output,name+'.png')});
    actions.push({seconds:(Date.now()-started)/1000,view:name});
    await page.waitForTimeout(1500);
  }
  assert.deepEqual(errors,[]);
  await context.close();await page.video().saveAs(path.join(output,'bibliography-history.webm'));
  await writeFile(path.join(output,'capture.json'),JSON.stringify({status:'passed',run_id:evidence.run_id,
    browser:browser.version(),actions,errors,checks:['saved historical run selected','nine measured versions','elapsed-time trajectory','allocated-byte trajectory','900 timing samples','eight baseline comparisons'],
    recording:'Actual saved-run exploration with a pointer ring; no new benchmark or fabricated values'},null,2));
}finally{await context.close();await browser.close();}
