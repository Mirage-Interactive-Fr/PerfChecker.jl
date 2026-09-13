(async function () {
  'use strict';
  const base = document.body.dataset.api, token = document.body.dataset.token;
  async function api(route, body) {
    const response = await fetch(base + route, {method: body ? 'POST' : 'GET', headers: {'Content-Type': 'application/json', 'X-PerfChecker-CSRF': token}, body: body ? JSON.stringify(body) : undefined});
    const value = await response.json(); if (!response.ok) throw new Error(value.error || `HTTP ${response.status}`); return value;
  }
  let polling, panel;
  function result(value) {panel.receive({type: 'advisorResult', result: value});}
  async function poll() {
    try {
      const job = await api('/advisor-job');
      if (job.status === 'running') polling = setTimeout(poll, 700);
      else result(job.result || {status: job.status, message: job.error || job.status});
    } catch (e) {result({status: 'error', message: String(e)});}
  }
  try {
    panel = mountAdvisorPanel(document.getElementById('advisor-root'), async message => {
      try {
        if (message.type === 'advisorHelp') {window.open('https://docs.ollama.com/quickstart', '_blank', 'noopener'); return;}
        if (message.type === 'advisorCancel') {await api('/advisor-cancel', {}); return;}
        const response = await api('/advisor-action', message);
        if (response.status === 'running') await poll(); else result(response);
      } catch (e) {result({status: 'error', message: String(e)});}
    }, await api('/advisor-settings'));
    const running = await api('/advisor-job');
    if (running.status === 'running') await poll();
  } catch (e) {document.getElementById('advisor-root').textContent = String(e);}
  window.addEventListener('pagehide', () => clearTimeout(polling));
})();
