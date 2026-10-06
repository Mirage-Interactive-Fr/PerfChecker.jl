import {chromium} from 'playwright';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const output=path.resolve(process.argv[2] ?? path.join(root,'.qualification/static-website-browser'));
await mkdir(output,{recursive:true});
const canonical='https://perfchecker.mirageinteractive.fr/';
const server=spawn(process.execPath,[path.join(root,'website/preview.mjs')],{
  env:{...process.env,PORT:'0',PERFCHECKER_DOCS_BASE:'/',PERFCHECKER_PREVIEW_CLEAN_URLS:'false'},
  windowsHide:true,stdio:['ignore','pipe','pipe'],
});
let browser;
try{
  const base=await new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(new Error('Static documentation server did not start')),20000);
    server.once('error',error=>{clearTimeout(timer);reject(error)});
    server.once('exit',code=>{clearTimeout(timer);reject(new Error(`Static server exited ${code}`))});
    server.stdout.on('data',data=>{
      const url=data.toString().match(/http:\/\/127\.0\.0\.1:\d+\//)?.[0];
      if(url){clearTimeout(timer);resolve(url)}
    });
  });
  browser=await chromium.launch({headless:true});
  const page=await browser.newPage();
  const errors=[];const checks=[];
  page.on('pageerror',error=>errors.push(error.message));
  page.on('response',response=>{
    const url=new URL(response.url());
    if(url.origin===new URL(base).origin&&response.status()>=400)
      errors.push(`${response.status()}: ${url.pathname}`);
  });
  const site=path.join(root,'website/build/site');
  const version=JSON.parse((await readFile(path.join(site,'siteinfo.js'),'utf8'))
    .match(/DOCUMENTER_CURRENT_VERSION\s*=\s*("[^"]+")/)[1]);
  for(const width of [390,1440]){
    await page.setViewportSize({width,height:1000});
    await page.goto(base,{waitUntil:'networkidle'});
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
    if(width<1280) await page.getByRole('button',{name:'mobile navigation',exact:true}).click();
    const picker=page.locator(width<1280?'.VPNavScreen .VPVersionPicker':'.VPNavBar .VPVersionPicker');
    await picker.getByRole('button',{name:version,exact:true}).click();
    const current=picker.getByRole('link',{name:version,exact:true});
    await current.waitFor({state:'visible'});
    assert.equal(new URL(await current.getAttribute('href'),base).href,base);
    assert.equal(await picker.getByRole('link',{name:'dev',exact:true}).getAttribute('href'),
      new URL('dev/',base).href);
    assert.equal(await picker.getByRole('link').count(),2);
    if(width<1280){
      await page.getByRole('button',{name:'mobile navigation',exact:true}).click();
      await page.locator('.VPNavScreen').waitFor({state:'hidden'});
    }else{
      await page.mouse.move(20,150);
      await page.getByRole('heading',{level:1}).click();
    }
    await page.screenshot({path:path.join(output,`static-home-${width}.png`),fullPage:true});
    if(width===390){
      const chart=page.locator('.normalized-measurements');
      await chart.locator('svg').waitFor();
      const bounds=await chart.locator('svg').evaluate(svg=>{
        const view=svg.viewBox.baseVal;
        return [...svg.querySelectorAll('text')].map(text=>{
          const box=text.getBBox();
          return {text:text.textContent,inside:box.x>=view.x&&box.x+box.width<=view.x+view.width&&
            box.y>=view.y&&box.y+box.height<=view.y+view.height};
        });
      });
      // Version labels are rotated. The unrotated axis legend must fit its SVG;
      // the narrow viewport intentionally offers horizontal chart scrolling.
      assert(bounds.find(box=>box.text==='Bibliography version')?.inside);
      const scroller=chart.locator('.normalized-scroll');
      const sizing=await scroller.evaluate(element=>({client:element.clientWidth,scroll:element.scrollWidth}));
      assert(sizing.scroll>sizing.client);
      await scroller.evaluate(element=>{element.scrollLeft=(element.scrollWidth-element.clientWidth)/2});
      await chart.screenshot({path:path.join(output,'static-chart-390.png')});
      const lastPoint=chart.locator('svg circle').last();
      await lastPoint.focus();
      assert((await scroller.evaluate(element=>element.scrollLeft))>0);
      const viewport=await scroller.boundingBox(), point=await lastPoint.boundingBox();
      assert(point.x>=viewport.x&&point.x+point.width<=viewport.x+viewport.width,
        'Keyboard focus must reveal the final point inside the narrow chart');
    }
  }
  checks.push('root version catalogue advertises this installed version and the canonical dev channel');
  await page.setViewportSize({width:1440,height:1000});
  await page.goto(base,{waitUntil:'networkidle'});
  await page.getByRole('link',{name:'Explore the interactive plots',exact:false}).click();
  await page.waitForURL('**/interfaces/visualization.html');
  await page.reload({waitUntil:'networkidle'});
  assert(await page.locator('h1').isVisible());
  checks.push('the homepage interactive-plots action reloads on static hosting');
  for(const route of ['interfaces/vscode','interfaces/vscode-configuration','mcp-advisor','guide/installation']){
    await page.goto(base+route+'.html',{waitUntil:'networkidle'});
    assert(await page.locator('h1').isVisible());
    const expected=new URL(route+'.html',canonical).href;
    assert.equal(await page.locator('link[rel="canonical"]').getAttribute('href'),expected);
    assert.equal(await page.locator('meta[property="og:url"]').getAttribute('content'),expected);
    const icon=await page.locator('link[rel="icon"]').getAttribute('href');
    assert.equal((await page.request.get(new URL(icon,base).href)).status(),200);
    await page.reload({waitUntil:'networkidle'});
    assert(await page.locator('h1').isVisible());
    assert(!/release candidate|PerfChecker\s+1\.0\.0[- ]rc/i.test(await page.locator('.vp-doc').innerText()));
    if(route==='mcp-advisor')
      await page.screenshot({path:path.join(output,'static-mcp-guide.png'),fullPage:true});
  }
  checks.push('portable deep links reload without rewrite rules, with matching canonical URLs and favicon');
  await page.locator('.VPNavBar').getByRole('button',{name:'Interfaces',exact:true}).hover();
  await page.locator('.VPNavBar').getByRole('link',{name:'VS Code',exact:true}).click();
  await page.waitForURL('**/interfaces/vscode.html');
  await page.locator('.vp-doc').getByRole('link',{name:'VS Code configuration',exact:true}).click();
  await page.waitForURL('**/interfaces/vscode-configuration.html');
  await page.reload({waitUntil:'networkidle'});
  checks.push('navigation and guide links use actual .html files on the static server');
  await page.locator('.VPNavBar').getByRole('button',{name:/Search/}).click();
  const search=page.locator('.VPLocalSearchBox input');
  await search.fill('implementation');
  await page.locator('.VPLocalSearchBox .result').first().waitFor();
  const href=await page.locator('.VPLocalSearchBox .result').first().getAttribute('href');
  assert(href&&new URL(href,base).pathname.endsWith('.html'));
  assert.equal((await page.request.get(new URL(href,base).href)).status(),200);
  await page.keyboard.press('Escape');
  checks.push('local search loads its index and links to reachable static pages');

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
    assert.equal(response.status(),200,`Missing static page: ${key.href}`);
    const parsed=await page.evaluate(html=>{
      const document=new DOMParser().parseFromString(html,'text/html');
      return {ids:[...document.querySelectorAll('[id]')].map(node=>node.id),
        links:[...document.querySelectorAll('a[href]')].map(node=>node.getAttribute('href')),
        assets:[...document.querySelectorAll('script[src],link[rel="stylesheet"],link[rel="modulepreload"]')]
          .map(node=>node.getAttribute('src')??node.getAttribute('href'))};
    },await response.text());
    documents.set(key.href,parsed);return parsed;
  }
  const pages=await markdownPages(path.join(root,'website/src'));
  const assets=new Set();
  for(const file of pages){
    const route=path.relative(path.join(root,'website/src'),file).replaceAll(path.sep,'/').replace(/\.md$/,'.html');
    const url=new URL(route==='index.html'?'':route,base);
    const document=await readDocument(url);
    for(const asset of document.assets) assets.add(new URL(asset,url).href);
    for(const href of document.links){
      const target=new URL(href,url);
      if(target.origin!==url.origin) continue;
      const extension=path.posix.extname(target.pathname);
      if(extension&&extension!=='.html') continue;
      const destination=await readDocument(target);
      if(target.hash) assert(destination.ids.includes(decodeURIComponent(target.hash.slice(1))),
        `Missing static section ${href} from ${route}`);
    }
  }
  for(const url of assets){
    assert.equal(new URL(url).origin,new URL(base).origin,'Runtime assets must ship in the static export');
    assert.equal((await page.request.head(url)).status(),200,`Missing static asset: ${url}`);
  }
  const sitemap=await page.request.get(base+'sitemap.xml');
  assert.equal(sitemap.status(),200);
  const locations=[...((await sitemap.text()).matchAll(/<loc>([^<]+)<\/loc>/g))].map(match=>match[1]);
  assert(locations.length>=pages.length);
  for(const location of locations){
    assert(location.startsWith(canonical));
    const url=new URL(location);
    assert.equal((await page.request.head(new URL(url.pathname,base).href)).status(),200,`Missing sitemap page: ${location}`);
  }
  assert.equal((await page.request.get(base+'interfaces/vscode')).status(),404,
    'This test server must not silently rewrite extensionless deep links');
  assert.equal((await page.request.get(base+'missing-static-page.html')).status(),404);
  checks.push(`${pages.length} pages, internal anchors, ${assets.size} runtime assets and sitemap targets resolve on static hosting`);
  assert.deepEqual(errors,[]);
  await writeFile(path.join(output,'static-website-browser-result.json'),
    JSON.stringify({passed:true,base:'/',canonical,version,checks},null,2)+'\n');
  console.log(checks.join('\n'));
}finally{
  await browser?.close();
  const stopped=once(server,'exit');server.kill();await stopped;
}
