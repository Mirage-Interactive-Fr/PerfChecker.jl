// Exercise a genuine public WGL export against its saved source model.
// Usage: node offline_browser.mjs EXPORT.html SOURCE.json [SCREENSHOT.png]
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';

assert(process.argv.length >= 4 && process.argv.length <= 5);
const saved=JSON.parse(fs.readFileSync(process.argv[3],'utf8')),model=saved.plot??saved;
const tooling=process.env.PERFCHECKER_PLOT_BROWSER_TOOLING;
const {chromium}=createRequire(tooling?path.join(path.resolve(tooling),'package.json'):import.meta.url)('playwright');
const browser=await chromium.launch({headless:true,
  executablePath:process.env.PERFCHECKER_CHROMIUM_EXECUTABLE||undefined,
  args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--renderer-process-limit=1']});
try {
  const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  page.on('requestfailed',request=>errors.push(request.url()+': '+request.failure()?.errorText));
  page.on('response',response=>{if(response.status()>=400)errors.push(response.url()+': '+response.status())});
  await page.goto(pathToFileURL(path.resolve(process.argv[2])).href);
  await page.locator('canvas').waitFor();
  const input=page.getByRole('spinbutton',{name:'Recorded point index',exact:true});
  await input.waitFor();
  await page.getByRole('button',{name:'Fit plot',exact:true}).waitFor();
  await page.locator('#offline-viewport').evaluate(node=>{node.style.display='none'});
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  assert.equal(await page.locator('#offline-viewport').evaluate(node=>node.clientWidth),0);
  assert(await page.locator('#offline-figure').evaluate(node=>new DOMMatrix(getComputedStyle(node).transform).a>0),
    'A hidden plot keeps a positive scale while its width is zero');
  await page.locator('#offline-viewport').evaluate(node=>node.style.removeProperty('display'));
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  const shownFigure=await page.locator('#offline-figure').boundingBox(),shownFrame=await page.locator('#offline-viewport').boundingBox();
  assert(shownFigure.width>0&&shownFigure.height>0&&shownFigure.x>=shownFrame.x&&shownFigure.y>=shownFrame.y&&
    shownFigure.x+shownFigure.width<=shownFrame.x+shownFrame.width+1&&
    shownFigure.y+shownFigure.height<=shownFrame.y+shownFrame.height+1,
    'Showing a hidden plot restores a complete, positive-scale Fit');
  const count=Number(await input.getAttribute('max'));
  assert(count>0);
  const fields=model.kind==='version_delta'?['relative_delta']:model.kind==='time_allocation_tradeoff'?['bytes','time']:['value'];
  const finite=model.data.filter(row=>fields.every(field=>typeof row[field]==='number'&&Number.isFinite(row[field])));
  assert.equal(count,finite.length,'The picker follows the same finite records as the actual figure');
  const row=finite[count-1];
  await input.fill(String(count));
  await page.locator('#point-readout[aria-busy="false"]').waitFor();
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  assert.equal(await page.locator('#point-readout').getAttribute('data-error'),null);
  const inspectGeometry=(requestedIndex=null)=>page.evaluate(requestedIndex=>{
    const input=document.getElementById('point-index');
    const source=WGL.plot_cache[input.dataset.sourcePlot],highlight=WGL.plot_cache[input.dataset.highlightPlot];
    const key=['wgl_positions','pos','offset'].find(key=>source.geometry.attributes[key]&&highlight.geometry.attributes[key]);
    const index=(requestedIndex??Number(input.value))-1,a=source.geometry.attributes[key],b=highlight.geometry.attributes[key];
    const sourcePoint=Array.from(a.array.slice(index*a.itemSize,(index+1)*a.itemSize));
    const selectedPoint=Array.from(b.array.slice(0,b.itemSize));
    function project(mesh,values){
      const uniforms=mesh.material.uniforms;
      let point=[values[0],values[1],values[2]??0,1];
      const transform=key=>{const matrix=uniforms[key].value.elements??uniforms[key].value;
        if(matrix.length!==16)throw new Error('Expected a native 4x4 '+key+' transform');
        point=[0,1,2,3].map(row=>point.reduce((sum,value,column)=>sum+matrix[column*4+row]*value,0));};
      for(const key of ['model_f32c','preprojection'])if(uniforms[key])transform(key);
      point=point.map(value=>value/point[3]);
      for(const key of ['view','projection'])transform(key);
      const scene=mesh.parent,[x,y,width,height]=scene.viewport.value;
      const screen=scene.screen,canvas=screen.canvas.getBoundingClientRect();
      return [canvas.left+(x+(point[0]/point[3]+1)*width/2)/screen.renderer._width*canvas.width,
        canvas.bottom-(y+(point[1]/point[3]+1)*height/2)/screen.renderer._height*canvas.height];
    }
    return {sourcePoint,selectedPoint,sourcePixel:project(source,sourcePoint),selectedPixel:project(highlight,selectedPoint)};
  },requestedIndex);
  const geometry=await inspectGeometry();
  assert.deepEqual(geometry.selectedPoint,geometry.sourcePoint,'The last selected buffer matches the correct source row');
  assert(geometry.sourcePixel.every((value,index)=>Math.abs(value-geometry.selectedPixel[index])<1),'Highlight occupies the actual source point');
  if(process.argv[4])await page.screenshot({path:path.resolve(process.argv[4]),fullPage:true});
  console.log(JSON.stringify({kind:model.kind,point:count,geometry}));
  await page.mouse.click(...geometry.sourcePixel);
  const popup=page.locator('.popup.show');await popup.waitFor({timeout:5000});
  const assertPopupBounds=async()=>{const box=await popup.boundingBox(),size=page.viewportSize();
    assert(box&&box.x>=0&&box.y>=0&&box.x+box.width<=size.width+1&&box.y+box.height<=size.height+1,
      'The visible native popup fits entirely within the window');};
  assert((await popup.innerText()).startsWith('Point '+count+':'),'Clicking the visible point identifies the selected record');
  await assertPopupBounds();
  const firstSource=await inspectGeometry(1);
  await page.mouse.click(...firstSource.sourcePixel);
  const picked=Number((await popup.innerText()).match(/^Point (\d+):/)?.[1]);
  assert(picked>=1&&picked<=count,'An unselected source marker exposes a recorded point');
  assert.deepEqual((await inspectGeometry(picked)).sourcePoint,firstSource.sourcePoint,
    'The native picked record occupies the clicked position, including coincident samples');
  const readout=await page.locator('#point-readout').innerText();
  for(const field of ['version','baseline_version','candidate_version','value','bytes','time'])
    if(field in row)assert(readout.includes(String(row[field])),`Missing exact ${field} at point ${count}`);
  if(model.kind==='time_allocation_tradeoff'){
    const specified=typeof model.options.time_unit==='string'&&typeof model.options.allocation_unit==='string';
    assert(readout.endsWith(' '+(specified?model.options.time_unit:'unit unspecified')),
      'The native readout keeps the recorded time unit');
    assert(readout.includes(' '+(specified?model.options.allocation_unit:'unit unspecified')+' · '),
      'The native readout keeps the recorded allocation unit');
  }
  await input.fill('0');
  assert.equal(await input.getAttribute('aria-invalid'),'true');
  assert.equal(await popup.count(),0,'An invalid selection closes the previous point popup');
  await input.evaluate((node,count)=>{for(const value of [1,count,1,count]){node.value=String(value);node.dispatchEvent(new Event('input',{bubbles:true}));}},count);
  await page.locator('#point-readout[aria-busy="false"]').waitFor();
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  assert.equal(await input.getAttribute('aria-invalid'),'false');
  const latest=await inspectGeometry();
  assert.deepEqual(latest.selectedPoint,latest.sourcePoint,'Rapid selection leaves the newest source position selected');
  assert.equal(await page.locator('#point-readout').innerText(),readout);
  const viewport=page.locator('#offline-viewport'),figure=page.locator('#offline-figure');
  const fitted=await figure.boundingBox(),frame=await viewport.boundingBox();
  assert(fitted.y+fitted.height<=frame.y+frame.height+1,'Fit includes the complete exported figure');
  await viewport.focus();await page.keyboard.press('+');
  assert((await figure.boundingBox()).width>fitted.width*1.4);
  await page.keyboard.press('-');assert(Math.abs((await figure.boundingBox()).width-fitted.width)<2);
  await page.keyboard.press('+');
  await page.keyboard.press('+');
  await viewport.evaluate(node=>node.scrollTo(100,100));
  const before=await viewport.evaluate(node=>[node.scrollLeft,node.scrollTop]);
  const box=await viewport.boundingBox();
  await page.keyboard.down('Shift');
  await page.mouse.move(box.x+box.width/2,box.y+box.height/2);await page.mouse.down();
  await page.mouse.move(box.x+box.width/2-80,box.y+box.height/2-60,{steps:5});
  await page.mouse.up();await page.keyboard.up('Shift');
  const after=await viewport.evaluate(node=>[node.scrollLeft,node.scrollTop]);
  assert(after[0]>before[0]+60&&after[1]>before[1]+40,'Shift-drag pans the real figure');
  const enlarged=await inspectGeometry();
  await viewport.evaluate((node,pixel)=>{const box=node.getBoundingClientRect();node.scrollBy(pixel[0]-box.x-box.width/2,pixel[1]-box.y-box.height/2)},enlarged.sourcePixel);
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  await page.mouse.click(...(await inspectGeometry()).sourcePixel);
  assert((await popup.innerText()).startsWith('Point '+count+':'),'Native picking follows the visible zoomed point');
  await assertPopupBounds();
  await viewport.evaluate(node=>node.scrollBy(20,20));
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  assert.equal(await popup.count(),0,'Panning closes the popup at its previous point position');
  await viewport.focus();await page.keyboard.press('0');
  assert(Math.abs((await figure.boundingBox()).width-fitted.width)<2);
  const downloaded=page.waitForEvent('download');
  await page.getByRole('button',{name:'Download plot model JSON',exact:true}).click();
  const download=await downloaded;assert.equal(await download.failure(),null);
  let json='';for await(const chunk of await download.createReadStream())json+=chunk.toString();
  const exported=JSON.parse(json);
  assert.deepEqual(exported.data,model.data,'The exported model retains every saved value');
  assert.deepEqual(exported.options,model.options,'The exported model retains its units and provenance');
  assert.equal(exported.kind,model.kind);
  if(process.argv[4])await page.screenshot({path:path.resolve(process.argv[4]),fullPage:true,animations:'disabled'});
  await page.setViewportSize({width:390,height:844});
  await page.getByRole('button',{name:'Fit plot',exact:true}).click();
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  const mobileFit=await figure.boundingBox(),mobileFrame=await viewport.boundingBox();
  assert(mobileFrame.height-mobileFit.height<=4,'Mobile Fit uses the figure height without a large empty viewport');
  const stableFit=await viewport.evaluate(async node=>{
    const sizes=[];
    for(let frame=0;frame<6;frame++){
      await new Promise(resolve=>requestAnimationFrame(resolve));
      const box=node.getBoundingClientRect();sizes.push([box.width,box.height]);
    }
    return sizes;
  });
  assert(stableFit.every(size=>size[0]===stableFit[0][0]&&size[1]===stableFit[0][1]),
    'The fitted viewport settles without a resize feedback loop');
  assert(mobileFit.x>=mobileFrame.x&&mobileFit.y>=mobileFrame.y&&
    mobileFit.x+mobileFit.width<=mobileFrame.x+mobileFrame.width+1&&
    mobileFit.y+mobileFit.height<=mobileFrame.y+mobileFrame.height+1,
    'Initial mobile Fit shows the entire figure, including its title and axes');
  if(process.argv[4])await page.screenshot({path:path.resolve(process.argv[4]).replace(/\.png$/,'-mobile-fit.png'),fullPage:false,animations:'disabled'});
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Mobile overflow is internal');
  await page.getByRole('button',{name:'Zoom in',exact:true}).click();
  await page.getByRole('button',{name:'Zoom in',exact:true}).click();
  await input.fill('1');if(count>1)await input.press('ArrowUp');
  assert.equal(await input.inputValue(),String(Math.min(2,count)));
  await page.locator('#point-readout[aria-busy="false"]').waitFor();
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  assert((await page.locator('#point-readout').innerText()).startsWith('Point '+Math.min(2,count)+':'));
  const mobile=await inspectGeometry();
  assert.deepEqual(mobile.selectedPoint,mobile.sourcePoint);
  await viewport.evaluate((node,pixel)=>{const box=node.getBoundingClientRect();node.scrollBy(pixel[0]-box.x-box.width/2,pixel[1]-box.y-box.height/2)},mobile.sourcePixel);
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  await page.mouse.click(...(await inspectGeometry()).sourcePixel);
  assert((await popup.innerText()).startsWith('Point '+Math.min(2,count)+':'),'Native picking follows the visible mobile point');
  await assertPopupBounds();
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'The mobile popup stays within the page');
  if(process.argv[4])await page.screenshot({path:path.resolve(process.argv[4]).replace(/\.png$/,'-mobile-inspection.png'),fullPage:false,animations:'disabled'});
  assert.deepEqual(errors,[]);
  console.log(JSON.stringify({status:'passed',kind:model.kind,points:count,readout,errors}));
} finally {await browser.close();}
