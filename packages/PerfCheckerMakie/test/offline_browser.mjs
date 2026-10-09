// Exercise a genuine public WGL export against its saved source model.
// Usage: node offline_browser.mjs EXPORT.html|HTTP_URL SOURCE.json|- [SCREENSHOT.png]
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';

assert(process.argv.length >= 4 && process.argv.length <= 5);
const saved=JSON.parse(fs.readFileSync(process.argv[3]==='-'?0:process.argv[3],'utf8')),model=saved.plot??saved;
const target=/^https?:\/\//.test(process.argv[2])?new URL(process.argv[2]):pathToFileURL(path.resolve(process.argv[2]));
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
  page.on('request',request=>{const url=new URL(request.url());
    if(target.protocol!=='file:'&&['http:','https:'].includes(url.protocol)&&url.origin!==target.origin)
      errors.push('Export requires an external origin: '+url.href);});
  await page.goto(target.href);
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
  const fields=model.kind==='version_delta'?['relative_delta']:model.kind==='time_allocation_tradeoff'?['bytes','time']:['allocation_lines','allocation_files','allocation_heatmap','allocation_pie'].includes(model.kind)?['bytes']:['value'];
  const finite=model.data.filter(row=>fields.every(field=>typeof row[field]==='number'&&Number.isFinite(row[field]))&&(model.kind!=='allocation_pie'||row.bytes>=0));
  assert.equal(count,finite.length,'The picker follows the same finite records as the actual figure');
  if(model.kind==='allocation_pie'&&finite.every(row=>row.bytes===0)){
    assert.equal(await input.getAttribute('data-readout-only'),'true');
    assert.equal(await input.getAttribute('data-source-plot'),null,'An all-zero pie has no fabricated source mesh');
    for(let index=0;index<count;index++){
      await input.fill(String(index+1));
      const text=await page.locator('#point-readout').innerText();
      assert(text.includes(finite[index].version)&&text.includes(finite[index].label)&&text.includes('no visible sector'));
    }
    await input.fill('0');assert.equal(await input.getAttribute('aria-invalid'),'true');
    await input.fill('1');assert.equal(await input.getAttribute('aria-invalid'),'false');
    const downloaded=page.waitForEvent('download');
    await page.getByRole('button',{name:'Download plot model JSON',exact:true}).click();
    const download=await downloaded;assert.equal(await download.failure(),null);
    let json='';for await(const chunk of await download.createReadStream())json+=chunk.toString();
    assert.deepEqual(JSON.parse(json),model,'The download retains the complete saved model');
    assert.equal(await page.locator('.popup.show').count(),0);
    assert((await page.locator('.plot-help').innerText()).startsWith('No positive allocation weight.'));
    if(process.argv[4])await page.screenshot({path:path.resolve(process.argv[4]),fullPage:true});
    assert.deepEqual(errors,[]);
    console.log(JSON.stringify({status:'passed',kind:model.kind,zeroRows:count,errors}));
  } else {
  if(model.kind==='allocation_heatmap'){
    const cells=JSON.parse(await input.getAttribute('data-source-cells'));
    assert.deepEqual(cells.shape,[model.options.versions.length,model.options.labels.length]);
    assert.deepEqual(cells.indices,finite.map(row=>model.options.versions.indexOf(row.version)+model.options.labels.indexOf(row.label)*cells.shape[0]),
      'Native texture indices preserve the source version/site identity, including sparse grids');
  }
  const row=finite[count-1];
  await input.fill(String(count));
  await page.locator('#point-readout[aria-busy="false"]').waitFor();
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  assert.equal(await page.locator('#point-readout').getAttribute('data-error'),null);
  const inspectGeometry=(requestedIndex=null)=>page.evaluate(requestedIndex=>{
    const input=document.getElementById('point-index');
    const source=WGL.plot_cache[input.dataset.sourcePlot],highlight=WGL.plot_cache[input.dataset.highlightPlot];
    const keys=['wgl_positions','pos','offset','positions_transformed_f32c'];
    const sourceKey=keys.find(key=>source.geometry.attributes[key]),targetKey=keys.find(key=>highlight.geometry.attributes[key]);
    const index=(requestedIndex??Number(input.value))-1,a=source.geometry.attributes[sourceKey],b=highlight.geometry.attributes[targetKey];
    const ranges=JSON.parse(input.dataset.sourceVertices||'[]'),cells=JSON.parse(input.dataset.sourceCells||'null'),triangles=JSON.parse(input.dataset.sourceTriangles||'[]');
    const vertices=cells?Array.from({length:a.count},(_,i)=>i):ranges.length?ranges[index]:[index];
    const sourcePoint=Array.from({length:b.itemSize},(_,component)=>{
      if(triangles.length){const triangle=triangles[index];return triangle.length?Math.fround(triangle.reduce((sum,vertex)=>sum+(component<a.itemSize?a.array[vertex*a.itemSize+component]:0),0)/3):NaN;}
      const values=vertices.map(vertex=>component<a.itemSize?a.array[vertex*a.itemSize+component]:0);
      const lower=Math.min(...values),upper=Math.max(...values);
      if(cells){const cell=cells.indices[index],fraction=component===0?((cell%cells.shape[0])+.5)/cells.shape[0]:component===1?(Math.floor(cell/cells.shape[0])+.5)/cells.shape[1]:.5;
        return Math.fround(lower+(upper-lower)*fraction);}
      return Math.fround((lower+upper)/2);
    });
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
    const vertexPixels=vertices.map(vertex=>project(source,Array.from({length:a.itemSize},(_,component)=>a.array[vertex*a.itemSize+component])));
    const pixelHeight=(Math.max(...vertexPixels.map(pixel=>pixel[1]))-Math.min(...vertexPixels.map(pixel=>pixel[1])))/(cells?cells.shape[1]:1);
    const gridBounds=cells?{left:Math.min(...vertexPixels.map(pixel=>pixel[0])),right:Math.max(...vertexPixels.map(pixel=>pixel[0])),
      top:Math.min(...vertexPixels.map(pixel=>pixel[1])),bottom:Math.max(...vertexPixels.map(pixel=>pixel[1]))}:null;
    return {sourcePoint,selectedPoint,sourcePixel:project(source,sourcePoint),selectedPixel:project(highlight,selectedPoint),pixelHeight,gridBounds};
  },requestedIndex);
  const geometry=await inspectGeometry();
  assert.deepEqual(geometry.selectedPoint,geometry.sourcePoint,'The last selected buffer matches the correct source row');
  assert(geometry.sourcePixel.every((value,index)=>Math.abs(value-geometry.selectedPixel[index])<1),'Highlight occupies the actual source point');
  if(model.kind==='allocation_files'){
    const spans=await Promise.all(finite.map((_,index)=>inspectGeometry(index+1)));
    const largest=finite.reduce((best,row,index)=>row.bytes>finite[best].bytes?index:best,0);
    const pixelsPerByte=spans[largest].pixelHeight/finite[largest].bytes;
    assert(pixelsPerByte>0);
    finite.forEach((row,index)=>assert(Math.abs(spans[index].pixelHeight-row.bytes*pixelsPerByte)<0.002,
      'Every native stacked segment has the same displayed pixels per recorded byte'));
  }
  if(process.argv[4])await page.screenshot({path:path.resolve(process.argv[4]),fullPage:true});
  console.log(JSON.stringify({kind:model.kind,point:count,geometry}));
  await page.mouse.click(...geometry.sourcePixel);
  const popup=page.locator('.popup.show');await popup.waitFor({timeout:5000});
  const assertPopupBounds=async()=>{const box=await popup.boundingBox(),size=page.viewportSize();
    assert(box&&box.x>=0&&box.y>=0&&box.x+box.width<=size.width+1&&box.y+box.height<=size.height+1,
      'The visible native popup fits entirely within the window');};
  assert((await popup.innerText()).startsWith('Point '+count+':'),'Clicking the visible point identifies the selected record');
  await assertPopupBounds();
  let firstClickable=model.kind==='allocation_pie'?finite.findIndex(row=>row.bytes>0)+1:1;
  if(model.kind==='time_allocation_tradeoff'&&count>1){
    const candidates=await Promise.all(finite.map((_,index)=>inspectGeometry(index+1)));
    const separation=candidates.map((candidate,index)=>Math.min(...candidates
      .filter((_,other)=>other!==index)
      .map(other=>Math.hypot(...candidate.sourcePixel.map((value,axis)=>value-other.sourcePixel[axis])))));
    firstClickable=separation.slice(0,-1).reduce((best,value,index)=>value>separation[best]?index:best,0)+1;
    console.log(JSON.stringify({kind:model.kind,unselectedPoint:firstClickable,separationPixels:separation[firstClickable-1]}));
  }
  const firstSource=await inspectGeometry(firstClickable);
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
  if(['allocation_lines','allocation_files'].includes(model.kind)){
    assert(readout.includes(row.file+(model.kind==='allocation_lines'?':'+row.line:'')),'Allocation inspection identifies the actual source location');
    assert(readout.endsWith(' '+model.options.unit),'Allocation inspection retains the recorded byte unit');
  }
  if(model.kind==='allocation_pie'){
    assert(readout.includes(row.label)&&readout.includes(String(row.percentage)+'%'),'Pie inspection retains the recorded site and percentage');
    const native=await popup.innerText(),first=finite[firstClickable-1];
    assert(native.includes(first.version)&&native.includes(first.label),'The native sector click identifies its recorded source row');
    const triangles=JSON.parse(await input.getAttribute('data-source-triangles'));
    assert.equal(triangles.length,count);
    const zero=finite.findIndex(row=>row.bytes===0);
    if(zero>=0){
      assert.deepEqual(triangles[zero],[],'A zero-byte sector has no invented native triangle');
      await input.fill(String(zero+1));
      await page.locator('#point-readout[aria-busy="false"]').waitFor();
      const zeroText=await page.locator('#point-readout').innerText();
      assert(zeroText.includes(finite[zero].label)&&zeroText.includes('no visible sector'));
      assert((await inspectGeometry(zero+1)).selectedPoint.every(Number.isNaN),'A zero-byte record does not draw a fabricated highlight');
      await input.fill(String(count));
      await page.locator('#point-readout[aria-busy="false"]').waitFor();
    }
  }
  if(model.kind==='allocation_heatmap'){
    assert(readout.includes(row.label),'Heatmap inspection identifies the recorded site');
    assert(readout.endsWith(' '+model.options.unit),'Heatmap inspection retains its recorded byte unit');
    const assertCellText=(text,expected)=>{
      assert(text.includes(expected.version)&&text.includes(expected.label),'The native cell retains its exact recorded identity');
      const weight=text.slice(text.lastIndexOf(' · ')+3).split(' ');
      assert.equal(Number(weight[0]),expected.bytes,'The native cell retains its exact recorded weight');
      assert.equal(weight[1],model.options.unit);
    };
    assertCellText(await popup.innerText(),finite[0]);
    const missing=[];
    model.options.versions.forEach((version,x)=>model.options.labels.forEach((label,y)=>{
      if(!finite.some(row=>row.version===version&&row.label===label))missing.push({x,y});
    }));
    if(missing.length){
      const zero=finite.findIndex(row=>row.bytes===0);
      assert(zero>=0,'The sparse fixture includes a recorded zero distinct from an absent cell');
      await input.fill('0');
      const zeroGeometry=await inspectGeometry(zero+1);
      await page.mouse.click(...zeroGeometry.sourcePixel);
      await popup.waitFor();
      const zeroText=await popup.innerText();
      assert(zeroText.startsWith('Point '+(zero+1)+':'),'The native zero-valued cell is still an inspectable recorded observation');
      assertCellText(zeroText,finite[zero]);
      await input.fill(String(zero+1));
      await page.locator('#point-readout[aria-busy="false"]').waitFor();
      assertCellText(await page.locator('#point-readout').innerText(),finite[zero]);
      await input.fill('0');
      const beforeMissing=await page.locator('#point-readout').innerText();
      const bounds=zeroGeometry.gridBounds,{x,y}=missing[0];
      await page.mouse.click(bounds.left+(x+.5)*(bounds.right-bounds.left)/model.options.versions.length,
        bounds.bottom-(y+.5)*(bounds.bottom-bounds.top)/model.options.labels.length);
      await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
      assert.equal(await popup.count(),0,'An absent native cell does not invent a zero-valued popup');
      assert.equal(await page.locator('#point-readout').innerText(),beforeMissing,'An absent cell does not create a recorded observation');
      await input.fill(String(count));
      await page.locator('#point-readout[aria-busy="false"]').waitFor();
    }
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
  const popupPan=await viewport.evaluate(node=>{
    const before=[node.scrollLeft,node.scrollTop];
    node.scrollBy(node.scrollLeft>0?-20:20,node.scrollTop>0?-20:20);
    return {before,after:[node.scrollLeft,node.scrollTop]};
  });
  assert(popupPan.after.some((value,index)=>value!==popupPan.before[index]),
    'The popup dismissal test pans away from the current edge: '+JSON.stringify(popupPan));
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
  assert.deepEqual(exported,model,'The download retains the complete saved model');
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
  console.log(JSON.stringify({status:'passed',kind:model.kind,points:count,readout,popupPan,errors}));
  }
} finally {await browser.close();}
