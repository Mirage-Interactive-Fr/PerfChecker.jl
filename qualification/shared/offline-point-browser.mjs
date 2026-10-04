// Validate an exported point plot with no Julia or Bonito server running.
import {chromium} from 'playwright';
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';

assert.equal(process.argv.length,5,'Expected HTML EVIDENCE OUTPUT arguments');
const [htmlFile,evidenceFile,output]=process.argv.slice(2).map(value=>path.resolve(value));
const html=await readFile(htmlFile);
const evidence=JSON.parse(await readFile(evidenceFile,'utf8'));
await mkdir(output,{recursive:true});
const server=createServer((request,response)=>{
  if(request.url!=='/'){response.writeHead(404);response.end();return;}
  response.writeHead(200,{'content-type':'text/html; charset=utf-8'});response.end(html);
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let browser;
try{
  browser=await chromium.launch({headless:true});
  const page=await browser.newPage({viewport:{width:1200,height:740}});
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.goto(`http://127.0.0.1:${server.address().port}/`,{waitUntil:'networkidle'});
  const canvas=page.locator('canvas').first();await canvas.waitFor();
  await page.waitForTimeout(1000);
  const before=await canvas.screenshot();
  await page.getByRole('slider',{name:'Inspect measured point'}).focus();
  await page.keyboard.press('End');await page.waitForTimeout(1000);
  const last=evidence.plot.data.at(-1);
  const expected=`Point ${evidence.plot.data.length}: ${last.value} ${evidence.plot.options.unit} · ${last.version}`;
  assert.equal(await page.locator('#point-readout').innerText(),expected);
  assert(!before.equals(await canvas.screenshot()),'The highlighted point must move on the canvas');
  for(const [width,height] of [[1200,740],[640,480],[390,420]]){
    await page.setViewportSize({width,height});
    await page.waitForFunction(()=>{
      const bounds=document.querySelector('#offline-figure').getBoundingClientRect();
      return bounds.left>=0&&bounds.right<=window.innerWidth+1&&bounds.bottom<=window.innerHeight;
    });
    assert.equal(await page.locator('#point-readout').innerText(),expected);
  }
  assert.deepEqual(errors,[]);
  await page.screenshot({path:path.join(output,'selected-point.png')});
  await writeFile(path.join(output,'result.json'),JSON.stringify({status:'passed',browser:browser.version(),readout:expected,responsiveWidths:[1200,640,390],errors},null,2));
  console.log('Offline plot: keyboard selection, numeric evidence and canvas update passed');
}finally{await browser?.close();server.close();}
