import {chromium} from 'playwright';
import {spawn} from 'node:child_process';
import {mkdir, writeFile, readFile, readdir} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
execFileSync(process.execPath,['--test',path.join(root,'qualification/shared/preview.test.mjs')],{stdio:'inherit',windowsHide:true});
const output=path.resolve(process.argv[2] ?? path.join(root,'.qualification/website-browser'));
await mkdir(output,{recursive:true});
const server=spawn(process.execPath,[path.join(root,'website/preview.mjs')],{
  env:{...process.env,PORT:'0'},windowsHide:true,stdio:['ignore','pipe','pipe'],
});
let browser;
try {
  const base=await new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(new Error('Documentation server did not start')),20000);
    server.on('error',error=>{clearTimeout(timer);reject(error);});
    server.on('exit',code=>{clearTimeout(timer);reject(new Error(`Documentation server exited ${code}`));});
    server.stdout.on('data',data=>{
      const url=data.toString().match(/http:\/\/127\.0\.0\.1:\d+\/[^\s]*/)?.[0];
      if(url){clearTimeout(timer);resolve(url);}
    });
  });
  browser=await chromium.launch({headless:true});
  const page=await browser.newPage();
  const errors=[];const checks=[];
  page.on('pageerror',error=>errors.push(error.message));
  for(const width of [390,768,1024,1279,1280,1440,1920]){
    await page.setViewportSize({width,height:950});
    for(const route of ['', 'tutorials/bibliography']){
      await page.goto(base+route,{waitUntil:'networkidle'});
      const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth);
      assert(overflow<=1,`Horizontal overflow at ${width}: ${route}`);
      const burger=page.getByRole('button',{name:'mobile navigation',exact:true});
      if(width<1280){
        assert(await burger.isVisible());await burger.focus();await page.keyboard.press('Enter');
        assert.equal(await burger.getAttribute('aria-expanded'),'true');
        const screen=page.locator('.VPNavScreen');
        await screen.getByRole('button',{name:'Use PerfChecker',exact:true}).click();
        await screen.getByRole('link',{name:'Web Studio',exact:true}).click();
        await page.waitForURL('**/interfaces/web-studio');
        assert.equal(await burger.getAttribute('aria-expanded'),'false');
      }else{
        assert(!(await burger.isVisible()));
        assert.equal(await page.locator('.VPNavBarMenu > .VPNavBarMenuGroup:not(.VPVersionPicker)').count(),4);
        await page.locator('.VPNavBarMenu').getByRole('button',{name:'Use PerfChecker',exact:true}).hover();
        await page.locator('.VPNavBarMenu').getByRole('link',{name:'Web Studio',exact:true}).waitFor();
      }
      checks.push(`navigation:${width}:${route||'home'}`);
    }
  }
  await page.setViewportSize({width:1440,height:1080});
  for(const width of [390,1280,1440,1920]){
    await page.setViewportSize({width,height:1080});
    await page.goto(base,{waitUntil:'networkidle'});
    const card=page.locator('.maintainer-link');
    assert.equal(await card.getAttribute('href'),'https://mirageinteractive.fr/');
    const position=await card.evaluate(el=>getComputedStyle(el).position);
    assert.equal(position,width>=1280?'fixed':'static');
    const overlay=page.locator('.normalized-measurements');
    await overlay.locator('svg').waitFor();
    assert.equal(await overlay.locator('svg path').count(),4);
    assert.equal(await overlay.locator('svg circle').count(),36);
    const timeToggle=overlay.getByRole('button',{name:'Elapsed time',exact:false});
    await timeToggle.click();
    assert.equal(await timeToggle.getAttribute('aria-pressed'),'false');
    await timeToggle.click();
    await page.locator('.absolute-measurements summary').click();
    const plots=page.locator('.measurement-grid img');
    assert.equal(await plots.count(),4);
    for(const img of await plots.all()) await img.evaluate(el=>el.decode());
    const boxes=await plots.evaluateAll(images=>images.map(el=>{
      const r=el.getBoundingClientRect();return {x:r.x,y:r.y,right:r.right};
    }));
    if(width>=1280){
      const bounds=await card.boundingBox();
      assert(boxes.every(b=>b.right<bounds.x),'Maintainer card covers plots');
      assert.equal(boxes[0].y,boxes[1].y);
    }else assert(boxes[1].y>boxes[0].y);
    await page.locator('.absolute-measurements summary').click();
    await page.screenshot({path:path.join(output,`home-measurements-${width}.png`),fullPage:true});
  }
  const overview=await (await page.request.get(base+'examples/bibliography/history/overview.json')).json();
  assert.equal(overview.versions.length,9);
  assert.equal(overview.metrics.length,4);
  assert(overview.metrics.every(m=>m.rows.length===9&&m.rows.every(r=>r.samples===100)));
  checks.push('home shows four measured histories and a discrete responsive maintainer link');
  await page.setViewportSize({width:1440,height:1080});
  await page.goto(base+'guide/overview',{waitUntil:'networkidle'});
  await page.getByRole('button',{name:'Hide sidebar',exact:true}).click();
  assert(!(await page.locator('.VPSidebar').isVisible()));
  await page.reload({waitUntil:'networkidle'});
  assert(await page.getByRole('button',{name:'Show sidebar',exact:true}).isVisible());
  await page.getByRole('button',{name:'Show sidebar',exact:true}).click();
  assert(await page.locator('.VPSidebar').isVisible());
  checks.push('desktop sidebar collapses, persists across reloads and expands again');
  for(const width of [390,1440]){
    await page.setViewportSize({width,height:1080});
    await page.goto(base,{waitUntil:'networkidle'});
    if(width<1280) await page.getByRole('button',{name:'mobile navigation',exact:true}).click();
    const picker=page.locator(width<1280?'.VPNavScreen .VPVersionPicker':'.VPNavBar .VPVersionPicker');
    const button=picker.getByRole('button',{name:'dev',exact:true});
    await button.click();
    const link=picker.getByRole('link',{name:'dev',exact:true});
    await link.waitFor({state:'visible'});
    assert.equal(new URL(await link.getAttribute('href'),base).pathname,new URL(base).pathname);
    assert.equal(await picker.getByRole('link').count(),1);
  }
  checks.push('version picker lists only the local development build on mobile and desktop');
  // Exercise Documenter's publication metadata on a simulated host. These
  // versions are test fixtures only and never become part of the public site.
  const published=await browser.newContext({viewport:{width:1440,height:1080}});
  await published.route('**/*',async route=>{
    const url=new URL(route.request().url());
    if(url.origin!=='http://docs.perfchecker.test') return route.abort();
    const response=await published.request.get(new URL(url.pathname+url.search,base).href);
    await route.fulfill({response});
  });
  await published.addInitScript(()=>{
    window.DOC_VERSIONS=['stable','v1.0','dev'];
    window.DOCUMENTER_CURRENT_VERSION='v1.0';
  });
  const publishedPage=await published.newPage();
  await publishedPage.goto('http://docs.perfchecker.test/',{waitUntil:'domcontentloaded'});
  const publishedPicker=publishedPage.locator('.VPNavBar .VPVersionPicker');
  await publishedPicker.getByRole('button',{name:'v1.0',exact:true}).click();
  await publishedPicker.getByRole('link',{name:'stable',exact:true}).waitFor({state:'visible'});
  assert.deepEqual((await publishedPicker.getByRole('link').allTextContents()).map(s=>s.trim()),['stable','v1.0','dev']);
  assert.equal(await publishedPicker.getByRole('link',{name:'stable',exact:true}).getAttribute('href'),
    'http://docs.perfchecker.test/stable/');
  await published.close();
  checks.push('published version picker reads Documenter metadata without a hard-coded release list');
  await page.setViewportSize({width:1440,height:1080});
  for(const route of ['','contributing/documentation','model-specialization']){
    await page.goto(base+route,{waitUntil:'networkidle'});
    const prose=await page.locator('.vp-doc').innerText();
    assert(!/same AI author|V1 candidate|Reusable Mirage layer/.test(prose));
    assert.equal((prose.match(/Mirage Interactive/g)||[]).length,route===''?1:0);
    if(route==='') assert.equal(await page.locator('.vp-doc a[href="https://mirageinteractive.fr/"]').count(),1);
    assert.equal(await page.locator('a[href*="v1-candidate"]').count(),0);
  }
  checks.push('community-facing content excludes internal release and training worklogs');
  await page.goto(base+'guide/overview',{waitUntil:'networkidle'});
  assert(!(await page.locator('.vp-doc').innerText()).includes('perfchecker-suite-plan/1'));
  const firstList=page.locator('.vp-doc ol').first();
  assert.equal(await firstList.locator(':scope > li').count(),4);
  assert.equal(await firstList.evaluate(list=>list.start),1);
  assert((await firstList.locator('li').first().innerText()).includes('What is being measured?'));
  await page.goto(base+'contributing/documentation',{waitUntil:'networkidle'});
  const screenshotPolicy=page.locator('.vp-doc ol').first();
  assert.equal(await screenshotPolicy.locator(':scope > li').count(),7);
  assert.equal(await screenshotPolicy.evaluate(list=>list.start),1);
  checks.push('ordered instructions retain every step and start at one');
  await page.goto(base+'reference/run-bundles',{waitUntil:'networkidle'});
  const formatGuide=await page.locator('.vp-doc').innerText();
  assert(formatGuide.includes('test plan, file format version 1'));
  assert(formatGuide.includes('/2')&&formatGuide.includes('/10'));
  assert(formatGuide.includes('You do not choose this integer'));
  checks.push('format versions are explained in reference rather than listed in the overview');
  await page.goto(base+'guide/installation',{waitUntil:'networkidle'});
  const installation=await page.locator('.vp-doc').innerText();
  assert(installation.includes('Pkg.add("PerfChecker")'));
  assert(!/Pkg.activate|Pkg.develop|Generate the suite skeleton|Local PerfChecker development/.test(installation));
  checks.push('installation contains package choices without development or suite scaffolding');
  await page.goto(base+'suites-and-comparisons',{waitUntil:'networkidle'});
  const suiteIntro=await page.locator('.vp-doc').innerText();
  assert(suiteIntro.includes('workload')&&suiteIntro.includes('plan')&&suiteIntro.includes('comparison'));
  const suiteGroup=page.locator('.VPSidebar .group').filter({has:page.getByText('Suites and comparisons',{exact:true})});
  assert.equal(await suiteGroup.count(),1);
  assert((await suiteGroup.locator('a').first().getAttribute('href')).endsWith('/suites-and-comparisons'));
  assert.equal(await suiteGroup.locator('a[href*="advisor"], a[href*="machine-transfer"]').count(),0);
  checks.push('suite navigation starts with an explanation and separates advanced advice');
  await page.goto(base+'guide/first-check',{waitUntil:'networkidle'});
  const itemDownload=page.locator('a[download="bibliography-testitems.jl"]');
  assert.equal(await itemDownload.count(),1);
  const itemResponse=await page.request.get(new URL(await itemDownload.getAttribute('href'),page.url()).href);
  assert.equal(itemResponse.status(),200);
  assert.equal(await itemResponse.text(),await readFile(path.join(root,'website/src/public/examples/bibliography/bibliography-testitems.jl'),'utf8'));
  assert((await page.locator('.vp-doc').innerText()).includes('Bibliography BibTeX round trip'));
  checks.push('first-result tutorial supplies the complete downloadable test item');
  for(const route of ['interfaces/packages','operations/overview','experiments','reference/index']){
    await page.goto(base+route,{waitUntil:'networkidle'});
    assert(await page.locator('.vp-doc table').count()>=1);
    assert(await page.locator('.vp-doc a[href]').count()>=3);
  }
  checks.push('section entry pages connect questions, prerequisites and next steps');
  // Follow the documentation's links, including raw-HTML links that the Markdown
  // builder cannot validate. Read detached DOMs without launching embedded media.
  const sourceRoot=path.join(root,'website/src');
  async function markdownPages(directory){
    const found=[];
    for(const entry of await readdir(directory,{withFileTypes:true})){
      if(entry.name==='public'||entry.name.startsWith('.')) continue;
      const file=path.join(directory,entry.name);
      if(entry.isDirectory()) found.push(...await markdownPages(file));
      else if(entry.name.endsWith('.md')) found.push(file);
    }
    return found;
  }
  const documents=new Map();
  async function readDocument(url){
    const key=new URL(url);key.hash='';
    if(documents.has(key.href)) return documents.get(key.href);
    const response=await page.request.get(key.href);
    assert.equal(response.status(),200,`Missing documentation page: ${key.href}`);
    const parsed=await page.evaluate(html=>{
      const document=new DOMParser().parseFromString(html,'text/html');
      return {ids:[...document.querySelectorAll('[id]')].map(node=>node.id),
        links:[...document.querySelectorAll('.vp-doc a[href]')].map(node=>node.getAttribute('href'))};
    },await response.text());
    documents.set(key.href,parsed);return parsed;
  }
  const markdown=await markdownPages(sourceRoot);
  for(const file of markdown){
    const route=path.relative(sourceRoot,file).replaceAll(path.sep,'/').replace(/\.md$/,'');
    const url=new URL(route==='index'?'':route,base);
    const document=await readDocument(url);
    for(const href of document.links){
      const target=new URL(href,url);
      if(target.origin!==url.origin) continue;
      const extension=path.posix.extname(target.pathname);
      if(extension&&extension!=='.html') continue;
      const destination=await readDocument(target);
      if(target.hash) assert(destination.ids.includes(decodeURIComponent(target.hash.slice(1))),
        `Missing section ${href} linked from ${route}`);
    }
  }
  checks.push(`all ${markdown.length} documentation pages have reachable internal page and section links`);
  for(const width of [390,1440]){
    await page.setViewportSize({width,height:1080});
    await page.goto(base+'tutorials/quick-tour',{waitUntil:'networkidle'});
    assert(await page.getByRole('heading',{name:/Bibliography in three small steps/}).isVisible());
    assert.equal(await page.locator('.doc-screenshot img').count(),2);
    for(const img of await page.locator('.doc-screenshot img').all()){
      await img.scrollIntoViewIfNeeded();await img.evaluate(image=>image.decode());
      assert(await img.evaluate(image=>image.naturalWidth>=700));
      assert((await img.getAttribute('alt')).length>30);
    }
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=document.documentElement.clientWidth+1));
    await page.screenshot({path:path.join(output,`quick-tour-${width}.png`),fullPage:true});
  }
  checks.push('short tutorial has readable measured plots on mobile and desktop');
  for(const route of ['tutorials/comparisons','reference/checks','process-memory']){
    await page.goto(base+route,{waitUntil:'networkidle'});
    const figures=page.locator('.doc-screenshot img');assert(await figures.count()>=1);
    for(const img of await figures.all()){
      await img.scrollIntoViewIfNeeded();await img.evaluate(image=>image.decode());
      assert(await img.evaluate(image=>image.naturalWidth>0));
    }
  }
  checks.push('comparison and measurement guides load their recorded figures');
  for(const route of ['interfaces/repl-pluto','tutorials/bibliography']){
    await page.goto(base+route,{waitUntil:'networkidle'});
    const download=page.locator('a[download="notebook.jl"]');
    assert.equal(await download.count(),1);
    const response=await page.request.get(new URL(await download.getAttribute('href'),page.url()).href);
    assert.equal(response.status(),200);
    const notebook=await response.text();
    assert.equal(notebook,await readFile(path.join(root,'examples/bibliography/notebook.jl'),'utf8'));
    assert(notebook.startsWith('### A Pluto.jl notebook ###'));
    assert(!/[A-Z]:\\|\/Users\/|\/home\//.test(notebook));
    assert(notebook.includes('historical')&&notebook.includes('history-suite.jl'));
  }
  checks.push('downloaded Pluto notebook matches the runnable portable example');
  await page.goto(base+'interfaces/visualization',{waitUntil:'networkidle'});
  const historyRoot=base+'examples/bibliography/history/';
  const history=await (await page.request.get(historyRoot+'catalog.json')).json();
  assert.equal(history.versions.length,9);
  assert.equal(history.views.length,6);
  const chooser=page.getByRole('combobox',{name:'Historical view'});
  for(const view of history.views){
    await chooser.selectOption(view.id);
    const iframe=page.locator(`iframe[src$="/${view.html}"]`);
    await iframe.waitFor();
    const frame=page.frameLocator(`iframe[src$="/${view.html}"]`);
    const data=await (await page.request.get(historyRoot+view.evidence)).json();
    assert((await page.locator('.history-reading-guide').innerText()).length>100);
    if(view.kind==='normalized_metrics'){
      assert.equal(data.plot.data.length,36);
      assert.equal(data.plot.options.reference_version,'minimum');
      assert.equal(data.plot.options.statistic,'minimum');
      await frame.locator('svg circle').last().waitFor();
      assert.equal(await frame.locator('svg path').count(),4);
      assert.equal(await frame.getByRole('checkbox').count(),4);
      for(const metric of new Set(data.plot.data.map(r=>r.metric))){
        const records=data.plot.data.filter(r=>r.metric===metric);
        const minimum=Math.min(...records.map(r=>r.value));
        assert(records.every(r=>r.reference_value===minimum));
        assert(records.every(r=>r.ratio===(minimum===0?(r.value===0?1:null):r.value/minimum)));
      }
      await frame.locator('svg circle').first().focus();
      assert((await frame.locator('#readout').innerText()).includes('ratio'));
      await frame.getByRole('checkbox').first().uncheck();
      assert.equal(await frame.locator('svg path').count(),3);
      await frame.getByRole('checkbox').first().check();
    }else if(view.kind!=='version_delta'){
      assert.equal(new Set(data.plot.data.map(row=>row.version)).size,9);
      const slider=frame.getByRole('slider',{name:'Inspect measured point'});
      await slider.waitFor();await frame.locator('canvas').first().waitFor();
      await page.waitForTimeout(700);
      const before=await frame.locator('canvas').first().screenshot();
      await slider.focus();await page.keyboard.press('End');await page.waitForTimeout(700);
      const last=data.plot.data.at(-1);
      assert.equal(await frame.locator('#point-readout').innerText(),`Point ${data.plot.data.length}: ${last.value} ${data.plot.options.unit} · ${last.version}`);
      const after=await frame.locator('canvas').first().screenshot();
      assert(!before.equals(after),'The plotted point must move, not just its text label');
      const fit=await frame.locator('#offline-figure').evaluate(element=>{
        const bounds=element.getBoundingClientRect();
        return {left:bounds.left,right:bounds.right,bottom:bounds.bottom,width:document.documentElement.clientWidth,height:window.innerHeight};
      });
      assert(fit.left>=0&&fit.right<=fit.width+1,'The complete historical figure must fit the iframe');
      assert(fit.bottom<=fit.height,'The horizontal axis must remain visible inside the iframe');
      await frame.locator('#offline-viewport').screenshot({path:path.join(output,`plot-${view.id}.png`)});
    }else{
      assert.equal(data.plot.data.length,8);
      assert(data.plot.data.every(row=>row.baseline_version==='0.1.0'));
      await frame.locator('canvas').first().waitFor();
    }
    const values=page.locator('.history-values');
    await values.locator('summary').click();
    await page.waitForFunction(()=>document.querySelectorAll('.history-values tbody tr').length>=8);
    assert.equal(await values.locator('tbody tr').count(),view.kind==='normalized_metrics'?36:view.kind==='version_delta'?8:9);
    await values.locator('summary').click();
    await page.screenshot({path:path.join(output,`bibliography-${view.id}.png`),fullPage:true});
    checks.push(`historical view, measured values and reading guide:${view.id}`);
  }
  const availability=page.locator('.history-availability');
  await availability.locator('summary').click();
  assert.equal(await availability.locator('.history-pass').count(),28);
  assert.equal(await availability.locator('.history-unavailable').count(),8);
  assert.equal(await availability.locator('.history-error,.history-missing').count(),0);
  checks.push('history availability keeps undefined workloads distinct from measured values');
  await page.goto(base+'guide/understanding-measurements',{waitUntil:'networkidle'});
  for(const heading of ['Wall time: how long the operation takes','Garbage collection: reclaiming unused objects','Flame graphs: where sampled work accumulates'])
    await page.getByRole('heading',{name:new RegExp('^'+heading)}).waitFor();
  assert((await page.locator('.vp-doc').innerText()).includes('GC fraction'));
  checks.push('measurement tutorial is built and exposes timing, GC and flame-graph explanations');
  for(const id of ['cpu','wall','allocations']){
    await page.getByRole('combobox',{name:'Choose profile weight'}).selectOption(id);
    const iframe=page.locator('.measured-profiles iframe');
    await iframe.scrollIntoViewIfNeeded();
    const frame=page.frameLocator('.measured-profiles iframe');
    const rectangles=frame.locator('.flame-frame');
    await rectangles.first().waitFor();
    const evidence=await (await page.request.get(base+`examples/bibliography/profiles/${id}.json`)).json();
    assert.equal(await rectangles.count(),evidence.plot.data.length);
    const graph=frame.locator('#flame');
    const fitted=await graph.boundingBox();
    assert(fitted);
    const frameBounds=await iframe.boundingBox();
    assert(fitted.width<frameBounds.width&&fitted.height<frameBounds.height,'The full flame graph must fit initially');
    await frame.getByRole('button',{name:'Zoom in',exact:true}).click();
    assert((await graph.boundingBox()).width>fitted.width*1.4,'Zoom must enlarge the graph');
    await frame.getByRole('button',{name:'Fit graph',exact:true}).click();
    assert(Math.abs((await graph.boundingBox()).width-fitted.width)<2);
    await rectangles.first().focus();
    const tooltip=frame.getByRole('tooltip');
    await tooltip.waitFor({state:'visible'});
    const text=await tooltip.innerText();
    assert(text.includes(evidence.plot.data[0].label));
    assert(text.includes(evidence.plot.options.value_label));
    assert(text.includes('Path:')&&text.includes('Weight:'));
    await iframe.screenshot({path:path.join(output,`bibliography-profile-${id}.png`)});
    checks.push(`recorded profile matches saved frames, fits, zooms and supports keyboard inspection:${id}`);
  }
  await page.goto(base+'tutorials/bibliography',{waitUntil:'networkidle'});
  const screenshots=page.locator('.doc-screenshot img');
  assert(await screenshots.count()>=4,'The walkthrough must show its actual interface captures');
  for(const screenshot of await screenshots.all()){
    await screenshot.scrollIntoViewIfNeeded();
    await screenshot.evaluate(image=>image.decode());
    assert(await screenshot.evaluate(image=>image.naturalWidth>=700));
    assert((await screenshot.getAttribute('alt'))?.trim());
  }
  checks.push('Bibliography interface screenshots load with descriptive alternatives');
  const recordings=JSON.parse(await readFile(path.join(root,'website/media.json'),'utf8'));
  for(const [recordingId,recordingSpec] of Object.entries(recordings)){
  const mediaState=recordingSpec.youtube_id ? 'youtube' : existsSync(path.join(root,'website/src/public',recordingSpec.file)) ? 'local' : 'pending';
  const mediaFigure=page.locator(`[data-recording="${recordingId}"]`);
  assert.equal(await mediaFigure.getAttribute('data-media-state'),mediaState);
  if(mediaState==='local'){
  const video=mediaFigure.locator('video');
  await video.scrollIntoViewIfNeeded();
  const recording=await page.request.get(base+recordingSpec.file);
  assert.equal(recording.headers()['content-type'],'video/webm');
  await video.evaluate(element=>{element.muted=true;return element.play();});
  await page.waitForFunction(id=>document.querySelector(`[data-recording="${id}"] video`).currentTime>0,recordingId);
  assert(await video.evaluate(element=>Number.isFinite(element.duration)&&element.duration>10));
  await video.evaluate(element=>{element.currentTime=element.duration-1;});
  await page.waitForFunction(id=>{const video=document.querySelector(`[data-recording="${id}"] video`);return video.currentTime>video.duration-2&&!video.seeking;},recordingId);
  const captions=await page.request.get(base+recordingSpec.captions);
  assert((await captions.text()).startsWith('WEBVTT'));
  assert.equal(await video.locator('track[kind="captions"]').count(),1);
  await page.waitForFunction(id=>{
    const track=document.querySelector(`[data-recording="${id}"] video`).textTracks[0];
    return track?.cues?.length>=4;
  },recordingId);
  await video.evaluate(element=>element.pause());
  checks.push(`recorded walkthrough playback, seeking and captions:${recordingId}`);
  }else if(mediaState==='youtube'){
    assert.equal(await mediaFigure.locator('iframe').count(),0,'YouTube must not load before the viewer clicks');
    await mediaFigure.getByRole('button',{name:/Watch the walkthrough on YouTube/}).waitFor();
    checks.push('YouTube opt-in control; external playback is not qualified by this check');
  }else{
    assert.equal(await mediaFigure.locator('video,iframe').count(),0);
    assert((await mediaFigure.innerText()).includes('Follow the written walkthrough'));
    checks.push('recording without an embedded player has an explicit written-walkthrough fallback');
  }
  if(recordingSpec.download_url){
    assert.equal(await mediaFigure.getByRole('link',{name:'Download the original recording',exact:true}).getAttribute('href'),recordingSpec.download_url);
    checks.push(`external recording download:${recordingId}`);
  }
  }
  await page.getByRole('button',{name:'Search',exact:true}).click();
  await page.locator('input[type="search"]').fill('run_testitems');
  await page.locator('.VPLocalSearchBox .result').first().waitFor();
  checks.push('local API search');
  assert.deepEqual(errors,[]);
  await writeFile(path.join(output,'website-browser.json'),JSON.stringify({status:'passed',browser:browser.version(),checks,errors},null,2));
  console.log(`Documentation: ${checks.length} browser checks passed`);
}finally{
  await browser?.close();server.kill();
}
