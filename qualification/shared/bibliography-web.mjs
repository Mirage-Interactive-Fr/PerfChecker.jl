// Opt-in live example: this launches one real Bibliography benchmark worker.
// Start examples/bibliography/web.jl first. Nothing is uploaded or published.
import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import path from 'node:path';

const base=process.argv[2] ?? 'http://127.0.0.1:8871/perfchecker/v1/';
const output=path.resolve(process.argv[3] ?? '.qualification/bibliography-web');
await mkdir(output,{recursive:true});
const browser=await chromium.launch({headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1080},
  recordVideo:{dir:output,size:{width:1440,height:1080}}});
const page=await context.newPage();
const errors=[];const actions=[];const started=Date.now();
page.on('pageerror',error=>errors.push(error.message));
async function point(selector){
  const locator=page.locator(selector);await locator.scrollIntoViewIfNeeded();
  const box=await locator.boundingBox();
  await page.mouse.move(box.x+box.width/2,box.y+box.height/2,{steps:20});
  return locator;
}
async function click(selector){await point(selector);await page.locator(selector).click();await pause(selector);}
async function select(selector,value){await point(selector);await page.selectOption(selector,value);await pause(`${selector}: ${value}`);}
async function pause(action){actions.push({seconds:(Date.now()-started)/1000,action});await page.waitForTimeout(900);}
async function screenshot(name){await page.screenshot({path:path.join(output,name+'.png'),fullPage:true});}
try{
  await page.goto(base,{waitUntil:'networkidle'});
  await page.waitForFunction(()=>document.querySelector('#plan-summary').textContent.includes('35/35'));
  // The pointer ring helps follow real recorded actions; application content is unchanged.
  await page.evaluate(()=>{
    const sheet=new CSSStyleSheet();sheet.replaceSync('.recording-pointer{position:fixed;left:0;top:0;width:18px;height:18px;border:3px solid #e05727;border-radius:50%;background:#fff7;pointer-events:none;z-index:99999;transform:translate(-50%,-50%)}');
    document.adoptedStyleSheets=[...document.adoptedStyleSheets,sheet];
    const pointer=document.createElement('div');pointer.className='recording-pointer';pointer.setAttribute('aria-hidden','true');document.body.append(pointer);
    document.addEventListener('pointermove',event=>{sheet.cssRules[0].style.left=event.clientX+'px';sheet.cssRules[0].style.top=event.clientY+'px';});
  });
  assert.equal(await page.locator('#feature-filter option').count(),8);
  await click('#clear-selection');await select('#package-filter','Bibliography');await select('#feature-filter','export_bibtex');
  assert.equal(await page.locator('#available-runs .run-card').count(),5);
  await screenshot('collectors');
  await select('#backend-filter','benchmark');await click('#add-visible');
  assert.equal(await page.locator('#selected-runs .run-card').count(),1);
  assert((await page.locator('#plan-summary').innerText()).startsWith('1/35 selected'));
  await page.locator('#samples').fill('50');await page.locator('#seconds').fill('0.5');
  assert.equal(await page.locator('#threads').inputValue(),'1');await screenshot('selection');
  const launched=page.waitForResponse(response=>response.url().endsWith('/jobs')&&response.request().method()==='POST');
  await click('#launch-job');const response=await launched;assert.equal(response.status(),202);
  const queued=await response.json();
  await page.waitForFunction(id=>[...document.querySelectorAll('.job-card')].some(card=>card.innerText.includes(id)&&card.innerText.includes('1 runs')&&card.querySelector('.status')?.textContent==='complete'),queued.job_id.slice(0,8),{timeout:240000});
  const apiBase=await page.locator('body').getAttribute('data-api-base');
  const jobs=await (await page.request.get(new URL(apiBase+'/jobs',base).href)).json();
  const completed=jobs.find(job=>job.job_id===queued.job_id);
  assert.equal(completed.state,'complete');await pause('measurement complete');await screenshot('complete');
  await click('[data-view-target="results"]');await page.locator('#results button').first().waitFor();
  await click('#results button:first-child');await page.locator('#result-summary.result-summary').waitFor();
  await select('#plot-metric-filter','julia.wall.time');await select('#plot-kind-filter','distribution');
  const frame=page.frameLocator('#makie-frame');
  await page.waitForFunction(()=>{const frame=document.querySelector('#makie-frame');return !frame.hidden&&frame.src.includes('distribution')&&!document.querySelector('#plot-loading')},{},{timeout:120000});
  const slider=frame.getByRole('slider',{name:'Inspect measured point'});await slider.waitFor();
  await slider.focus();await page.keyboard.press('End');await pause('inspect last measured sample');
  assert((await frame.locator('#point-readout').innerText()).startsWith('Point 50:'));
  await screenshot('results');await pause('saved result inspected');assert.deepEqual(errors,[]);
  await context.close();
  const video=page.video();await video.saveAs(path.join(output,'bibliography-web.webm'));
  await writeFile(path.join(output,'capture.json'),JSON.stringify({status:'passed',browser:browser.version(),
    job_id:queued.job_id,job_status:completed.state,actions,errors,
    checks:['35 leaves','7 workload filters','5 collectors for export','one selected leaf','one worker thread','real job completed','saved distribution reopened','offline measured point selected'],
    recording:'Uncut browser recording with a pointer ring; no synthetic measurements'},null,2));
  console.log('Bibliography: execution, saved distribution and recording passed');
}finally{await context.close();await browser.close();}
