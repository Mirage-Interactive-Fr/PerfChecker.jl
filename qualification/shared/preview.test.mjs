import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

test('preview remains readable while its build source is replaced',async()=>{
  const source=await mkdtemp(join(tmpdir(),'perfchecker-preview-fixture-'));
  await writeFile(join(source,'index.html'),'<h1>Completed documentation</h1>');
  await writeFile(join(source,'404.html'),'<h1>Missing page</h1>');
  const server=spawn(process.execPath,[fileURLToPath(new URL('../../website/preview.mjs',import.meta.url))],{
    env:{...process.env,PORT:'0',PERFCHECKER_PREVIEW_SOURCE:source},
    windowsHide:true,stdio:['ignore','pipe','pipe'],
  });
  try{
    const base=await new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>reject(new Error('Preview startup timed out')),15000);
      server.once('error',error=>{clearTimeout(timeout);reject(error)});
      server.once('exit',code=>{clearTimeout(timeout);reject(new Error(`Preview exited: ${code}`))});
      server.stdout.on('data',data=>{
        const url=data.toString().match(/http:\/\/127\.0\.0\.1:\d+\//)?.[0];
        if(url){clearTimeout(timeout);resolve(url)}
      });
    });
    // This directory was created exclusively by this test, never a real build.
    await rm(join(source,'index.html'));
    assert.equal(await (await fetch(base)).text(),'<h1>Completed documentation</h1>');
    await writeFile(join(source,'index.html'),'<h1>Incomplete next build</h1>');
    assert.equal(await (await fetch(base)).text(),'<h1>Completed documentation</h1>');
    assert.equal((await fetch(base+'absent')).status,404);
  }finally{
    const stopped=once(server,'exit');server.kill();await stopped;
    await rm(source,{recursive:true,force:true});
  }
});
