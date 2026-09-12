'use strict';
const byId = id => document.getElementById(id);
const endpoint = name => new URL(name, location.href.endsWith('/') ? location.href : location.href + '/');
let timer;
async function api(name, body) {
  const response = await fetch(endpoint(name), body === undefined ? {} : {method:'POST',
    headers:{'Content-Type':'application/json','X-PerfChecker-CSRF':document.body.dataset.token},body:JSON.stringify(body)});
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || 'Request failed');
  return result;
}
function error(e) {byId('status').textContent = e.message;}
async function refresh() {
  const listing = await api('items');
  byId('items').replaceChildren(...listing.items.map(item=>{
    const row = document.createElement('label'), check = document.createElement('input');
    check.type='checkbox';check.value=item.id;check.checked=true;
    const title = document.createTextNode(item.name), detail=document.createElement('small');
    detail.textContent=`${item.file} · ${item.tags.join(', ') || 'shared'}`;
    row.append(check,title,detail);return row;
  }));
}
async function poll() {
  const state=await api('state'), running=state.status==='running';
  byId('run').disabled=running;byId('refresh').disabled=running;byId('cancel').disabled=!running;
  byId('status').textContent=state.message || state.status;
  if(running) {timer=setTimeout(()=>poll().catch(error),500);return;}
  if(state.result) byId('results').replaceChildren(...state.result.runs.map(run=>{
    const row=document.createElement('article'), title=document.createElement('strong'), detail=document.createElement('small');
    title.textContent=`${run.item.name}: ${run.status}`;
    detail.textContent=run.samples.map(s=>s.status==='complete' ? `${(s.seconds*1000).toFixed(2)} ms · ${s.bytes} Julia bytes · ${s.passes} passing assertions` : s.message || s.status).join('; ');
    const note=document.createElement('small');note.textContent='Includes setup, imports and assertions. Performance budget not compared.';
    row.append(title,detail,note);return row;
  }));
}
byId('refresh').onclick=()=>refresh().catch(error);
byId('run').onclick=async()=>{
  const ids=[...document.querySelectorAll('#items input:checked')].map(input=>input.value);
  if(!ids.length) {error(new Error('Select at least one item.'));return;}
  byId('run').disabled=true;
  try {await api('run',{ids});clearTimeout(timer);await poll();} catch(e) {byId('run').disabled=false;error(e);}
};
byId('cancel').onclick=()=>api('cancel',{}).catch(error);
refresh().then(poll).catch(error);
