// Exercise the public flame renderer against the saved model without changing its data.
// Usage: node flame_browser.mjs EXPORT.html SOURCE.json [SCREENSHOT.png]
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
assert(process.argv.length>=4&&process.argv.length<=5);
const saved=JSON.parse(fs.readFileSync(process.argv[3],'utf8')),model=saved.plot??saved;
const tooling=process.env.PERFCHECKER_PLOT_BROWSER_TOOLING;
const {chromium}=createRequire(tooling?path.join(path.resolve(tooling),'package.json'):import.meta.url)('playwright');
const browser=await chromium.launch({headless:true,executablePath:process.env.PERFCHECKER_CHROMIUM_EXECUTABLE||undefined,args:['--disable-gpu','--renderer-process-limit=1']});
try{
 const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
 page.on('pageerror',error=>errors.push(error.message));page.on('requestfailed',request=>errors.push(request.url()));
 page.on('response',response=>{if(response.status()>=400)errors.push(response.url())});
 await page.goto(pathToFileURL(path.resolve(process.argv[2])).href);
 assert(await page.evaluate(()=>window.top===window&&!Object.hasOwn(window,'PAYLOAD')&&!Object.hasOwn(window,'MODEL')&&!Object.hasOwn(window,'DATA')),'Standalone globals remain intact');
 const frames=page.locator('.flame-frame'),input=page.getByRole('spinbutton',{name:'Recorded frame index',exact:true});
 assert.equal(await frames.count(),model.data.length);assert.equal(Number(await input.getAttribute('max')),model.data.length);
 assert.equal(await page.locator('#title').innerText(),model.title);
 assert((await page.locator('#metadata').innerText()).includes(model.options.selected_version));
 const geometry=await frames.evaluateAll(nodes=>nodes.map(node=>({index:Number(node.dataset.index),x:Number(node.getAttribute('x')),width:Number(node.getAttribute('width')),text:node.getAttribute('aria-label')})));
 const baseline=82,plotWidth=1294;
 for(const [index,row]of model.data.entries()){
  assert.equal(geometry[index].index,index);assert(Math.abs(geometry[index].x-(baseline+plotWidth*row.x0))<1e-9);
  assert(Math.abs(geometry[index].width-plotWidth*(row.x1-row.x0))<1e-9,'Every visible frame preserves its recorded share, including subpixel frames');
  assert(geometry[index].text.includes(String(row.value))&&geometry[index].text.includes(row.label));
 }
 const readableLabels=await page.locator('.frame-label').evaluateAll(nodes=>nodes.map(node=>{const rect=node.previousElementSibling,bounds=node.getBBox();return {text:node.textContent,fill:getComputedStyle(node).fill,bar:getComputedStyle(rect).fill,left:bounds.x,right:bounds.x+bounds.width,top:bounds.y,bottom:bounds.y+bounds.height,x:Number(rect.getAttribute('x')),y:Number(rect.getAttribute('y')),width:Number(rect.getAttribute('width')),height:Number(rect.getAttribute('height'))}}));
 assert(readableLabels.length>0);for(const label of readableLabels){assert(label.left>=label.x&&label.right<=label.x+label.width&&label.top>=label.y&&label.bottom<=label.y+label.height,'Every visible label fits both native SVG dimensions');const luminance=rgb=>{const values=rgb.match(/[0-9.]+/g).slice(0,3).map(x=>Number(x)/255).map(x=>x<=.04045?x/12.92:((x+.055)/1.055)**2.4);return values[0]*.2126+values[1]*.7152+values[2]*.0722};const text=luminance(label.fill),bar=luminance(label.bar);assert((Math.max(text,bar)+.05)/(Math.min(text,bar)+.05)>=4.5,'Rendered label contrast remains readable on its real fill')}
 const fit=async()=>{await page.getByRole('button',{name:'Fit graph',exact:true}).click();const frame=await page.locator('.flame-scroll').boundingBox(),figure=await page.locator('#flame').boundingBox();assert(figure.width>0&&figure.height>0);assert(figure.x>=frame.x&&figure.y>=frame.y&&figure.x+figure.width<=frame.x+frame.width+1&&figure.y+figure.height<=frame.y+frame.height+1);return figure};
 const popup=async()=>{await page.getByRole('tooltip').waitFor({state:'visible'});const box=await page.getByRole('tooltip').boundingBox(),vp=page.viewportSize();assert(box.x>=0&&box.y>=0&&box.x+box.width<=vp.width+1&&box.y+box.height<=vp.height+1)};
 const inspect=async index=>{await input.fill(String(index+1));const text=await page.locator('#readout').innerText(),row=model.data[index];assert(text.includes(row.label)&&text.includes(String(row.value))&&text.includes((row.path||[]).join(' → ')));assert.equal(await frames.nth(index).getAttribute('class'),'flame-frame selected')};
 const thin=geometry.reduce((best,row,index)=>row.width<geometry[best].width?index:best,0),wide=geometry.reduce((best,row,index)=>row.width>geometry[best].width?index:best,0);
 await fit();const stableViewport=await page.locator('.flame-scroll').boundingBox();for(const index of [0,model.data.length-1]){await inspect(index);const current=await page.locator('.flame-scroll').boundingBox();assert.equal(current.y,stableViewport.y,'Changing short/long frame inspection keeps the click target stationary');assert.equal(current.height,stableViewport.height)}await inspect(thin);await input.fill('0');assert.equal(await input.getAttribute('aria-invalid'),'true');await inspect(model.data.length-1);
 await frames.nth(wide).click();await popup();assert((await page.getByRole('tooltip').innerText()).includes(model.data[wide].label));
 await page.locator('.flame-scroll').focus();await page.keyboard.press('+');const zoomed=await page.locator('#flame').boundingBox();await page.keyboard.press('+');assert((await page.locator('#flame').boundingBox()).width>zoomed.width*1.4);
 await frames.nth(wide).click();await popup();await page.locator('.flame-scroll').focus();await page.keyboard.press('ArrowRight');await page.waitForFunction(()=>document.querySelector('.flame-scroll').scrollLeft>0);assert.equal(await page.getByRole('tooltip').isVisible(),false);
 const viewport=page.locator('.flame-scroll'),box=await viewport.boundingBox();const before=await viewport.evaluate(node=>node.scrollLeft);await page.mouse.move(box.x+box.width*.7,box.y+box.height-5);await page.mouse.down();await page.mouse.move(box.x+box.width*.4,box.y+box.height-5);await page.mouse.up();assert((await viewport.evaluate(node=>node.scrollLeft))>before,'Background dragging pans the zoomed graph');
 await viewport.focus();await page.keyboard.press('0');await fit();
 await viewport.evaluate(node=>node.style.display='none');await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(resolve)));await viewport.evaluate(node=>node.style.removeProperty('display'));await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));await fit();
 for(const [name,type]of [['Download plot model JSON','json'],['Export SVG','svg']]){const pending=page.waitForEvent('download');await page.getByRole('button',{name,exact:true}).click();const download=await pending;assert.equal(await download.failure(),null);let content='';for await(const chunk of await download.createReadStream())content+=chunk.toString();if(type==='json')assert.deepEqual(JSON.parse(content),model);else{assert(content.includes('<svg'));assert(content.includes(model.title.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')));if(process.argv[4])fs.writeFileSync(path.resolve(process.argv[4]).replace(/\.png$/,'-export.svg'),content);const exported=await page.evaluate(text=>{const doc=new DOMParser().parseFromString(text,'image/svg+xml');if(doc.querySelector('parsererror'))throw Error('Invalid exported SVG');return {labels:Array.from(doc.querySelectorAll('text'),node=>node.textContent),frames:Array.from(doc.querySelectorAll('.flame-frame'),node=>({index:Number(node.dataset.index),x:Number(node.getAttribute('x')),width:Number(node.getAttribute('width')),transform:node.parentElement.getAttribute('transform')}))}},content);
 assert(exported.labels.some(label=>label.includes('not performance gains')));const legendLabels=model.kind==='allocation_flamegraph'?['sampled allocation frame']:['sampled Julia frame','runtime dispatch','non-concrete inferred return','garbage collection'];for(const label of legendLabels)assert(exported.labels.includes(label),'The downloadable image includes its diagnostic key: '+label);
 assert.equal(exported.frames.length,model.data.length);for(const [index,row]of exported.frames.entries()){assert.equal(row.index,index);assert.equal(row.x,geometry[index].x,'Export preserves every recorded frame origin');assert.equal(row.width,geometry[index].width,'Export preserves every recorded frame width');assert.match(row.transform,/^translate\(0 [0-9.]+\)$/,'Only the common header translation changes graph placement')}}}
 if(process.argv[4]){const svgPath=path.resolve(process.argv[4]).replace(/\.png$/,'-export.svg'),bytes=fs.readFileSync(svgPath),dataURL='data:image/svg+xml;base64,'+bytes.toString('base64');assert(Buffer.from(dataURL.split(',')[1],'base64').equals(bytes));const exportedPage=await browser.newPage({viewport:{width:1440,height:1000}});await exportedPage.setContent('<!doctype html><html><body style="margin:0"><img alt="Downloaded public flame SVG"></body></html>');await exportedPage.locator('img').evaluate(async(node,src)=>{node.src=src;await node.decode();if(!(node.naturalWidth>0&&node.naturalHeight>0))throw Error('Downloaded SVG failed to decode')},dataURL);await exportedPage.locator('img').screenshot({path:path.resolve(process.argv[4]).replace(/\.png$/,'-export.png')});assert(fs.readFileSync(svgPath).equals(bytes));await exportedPage.close()}
 if(process.argv[4])await page.screenshot({path:path.resolve(process.argv[4]),fullPage:true});
 await page.setViewportSize({width:390,height:844});await fit();assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 if(process.argv[4])await page.screenshot({path:path.resolve(process.argv[4]).replace(/\.png$/,'-mobile-fit.png'),fullPage:true});
 await inspect(thin);await frames.nth(wide).focus();await popup();await page.getByRole('button',{name:'Zoom in',exact:true}).click();await frames.nth(wide).click();await popup();
 if(process.argv[4])await page.screenshot({path:path.resolve(process.argv[4]).replace(/\.png$/,'-mobile-inspection.png'),fullPage:true});
 assert.deepEqual(errors,[]);console.log(JSON.stringify({status:'passed',kind:model.kind,frames:model.data.length,thinIndex:thin+1,minimumWidth:geometry[thin].width,errors}));
}finally{await browser.close()}
