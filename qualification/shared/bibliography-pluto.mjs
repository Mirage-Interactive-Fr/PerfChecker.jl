// Opt-in real notebook execution. Supply the local URL printed by Pluto in
// PERFCHECKER_PLUTO_URL; the authentication URL is never included in evidence.
import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';

if(!process.env.PERFCHECKER_PLUTO_URL)throw new Error('Set PERFCHECKER_PLUTO_URL to the local notebook URL');
const output=path.resolve(process.argv[2] ?? '.qualification/bibliography-pluto');
await mkdir(output,{recursive:true});
const browser=await chromium.launch({headless:true});
const page=await browser.newPage({viewport:{width:1440,height:1080},locale:'en-US'});
const errors=[];page.on('pageerror',error=>errors.push(error.message));
async function jobState(){
  return page.locator('[data-suite-state]').getAttribute('data-suite-state');
}
try{
  await page.goto(process.env.PERFCHECKER_PLUTO_URL,{waitUntil:'domcontentloaded'});
  const refresh=page.getByRole('button',{name:'Refresh status',exact:true});
  const save=page.getByRole('button',{name:'Save completed reports',exact:true});
  await save.waitFor({timeout:120000});
  const selects=page.locator('pluto-output select');
  assert.equal(await selects.count(),4);
  const history=page.locator('pluto-output input[type="checkbox"]');
  let historyChecked=false;
  if(await history.count()){
    await history.check();
    await page.waitForFunction(()=>[...document.querySelectorAll('pluto-output select')].at(-1)?.options.length===10);
    const targets=await selects.nth(3).locator('option').allTextContents();
    assert(targets.includes('0.1.0')&&targets.includes('0.4.0'));
    await refresh.click();assert.equal(await jobState(),'idle');
    await history.uncheck();
    await page.waitForFunction(()=>[...document.querySelectorAll('pluto-output select')].at(-1)?.options.length<10);
    historyChecked=true;
  }
  await selects.nth(0).selectOption({label:'Bibliography'});
  await selects.nth(1).selectOption({label:'export_bibtex'});
  await selects.nth(2).selectOption({label:'benchmark'});
  await page.waitForFunction(()=>[...document.querySelectorAll('pluto-output pre')].some(e=>e.textContent.includes('1 runs')));
  await refresh.click();await page.waitForTimeout(1000);
  assert.equal(await jobState(),'idle','Filtering must not launch a job');
  assert.equal(await page.locator('pluto-output input[type="number"]').nth(2).inputValue(),'1');
  await page.screenshot({path:path.join(output,'selection.png'),fullPage:true});
  await page.getByRole('button',{name:'Launch selected checks',exact:true}).click();
  const deadline=Date.now()+240000;
  let complete=false;
  while(Date.now()<deadline){
    await refresh.click();await page.waitForTimeout(3000);
    assert.deepEqual(await page.locator('pluto-cell.errored pluto-output').allTextContents(),[]);
    complete=await jobState()==='complete';
    if(complete)break;
  }
  assert(complete,'Notebook job did not complete before the deadline');
  await save.click();
  await page.waitForFunction(()=>[...document.querySelectorAll('pluto-output')].some(e=>e.textContent.includes('Last saved reports:')));
  const saved=(await page.locator('pluto-output').allTextContents()).find(text=>text.includes('Last saved reports:'));
  // Changing a selector after completion must not launch or save another job.
  await selects.nth(1).selectOption({label:'import_bibtex'});await refresh.click();await page.waitForTimeout(1500);
  assert((await page.locator('pluto-output').allTextContents()).includes(saved));
  assert.equal(await jobState(),'complete');
  await selects.nth(1).selectOption({label:'export_bibtex'});await page.waitForTimeout(1000);
  assert.deepEqual(await page.locator('pluto-cell.errored pluto-output').allTextContents(),[]);
  await page.reload({waitUntil:'networkidle'});await save.waitFor();
  await refresh.click();await page.waitForTimeout(1000);
  assert.equal(await jobState(),'complete','Reloading must not start another job');
  await save.click();
  await page.waitForFunction(previous=>[...document.querySelectorAll('pluto-output')].some(element=>element.textContent.startsWith('saved_reports')&&element.textContent.includes('Last saved reports:')&&element.textContent!==previous),saved);
  const savedAgain=(await page.locator('pluto-output').allTextContents()).find(text=>text.includes('Last saved reports:'));
  assert.deepEqual(errors,[]);
  await page.screenshot({path:path.join(output,'completed.png'),fullPage:true});
  await writeFile(path.join(output,'capture.json'),JSON.stringify({status:'passed',browser:browser.version(),
    saved_reports:saved,saved_again:savedAgain,errors,history_checked:historyChecked,checks:['real Pluto notebook loaded','one export benchmark selected',
      'filters leave notebook idle','one worker thread','explicit launch completed','explicit report save',
      'later selector changes do not relaunch or resave','reload does not launch; one click saves again']},null,2));
  console.log('Pluto: selection, explicit execution and saved reports passed');
}finally{await browser.close();}
