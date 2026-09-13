(() => {
  const base = document.body.dataset.api;
  const token = document.body.dataset.token;
  const $ = id => document.getElementById(id);
  let catalogue; let active; let polling; let busy = false;
  const status = message => {$('status').textContent = message;};
  async function request(route, payload, text = false) {
    const response = await fetch(base + route, payload === undefined ? {} : {method: 'POST', headers: {'Content-Type': 'application/json', 'X-PerfChecker-CSRF': token}, body: JSON.stringify(payload)});
    if (!response.ok) {const error = await response.json(); throw new Error(error.error || response.statusText);}
    return text ? response.text() : response.json();
  }
  function checked(container) {return [...container.querySelectorAll('input:checked')].map(input => input.value);}
  function controls(running) {busy = running; for (const id of ['discover', 'measure', 'diagnose', 'compare', 'investigate', 'sync', 'inventory', 'narrate']) $(id).disabled = running || (id === 'narrate' && catalogue.advisor === 'disabled'); $('cancel').disabled = !running;}
  async function refreshHistory() {
    const records = await request('/jobs');
    for (const id of ['history', 'baseline', 'candidate']) {
      const previous = $(id).value; $(id).replaceChildren();
      for (const record of records.filter(r => id === 'history' || r.action === 'run')) {
        const option = document.createElement('option'); option.value = record.id; option.textContent = `${record.action} · ${record.status} · ${record.id.slice(0, 8)}`; $(id).append(option);
      }
      if ([...$(id).options].some(option => option.value === previous)) $(id).value = previous;
    }
  }
  async function openEvidence(advice = false) {
    const id = $('history').value; if (!id) throw new Error('Choose a saved investigation.');
    $('evidence').innerHTML = await request(`/evidence?id=${encodeURIComponent(id)}&advice=${advice}`, undefined, true);
  }
  async function poll() {
    if (!active) return;
    const snapshot = await request(`/job?id=${encodeURIComponent(active)}`);
    status(`${snapshot.action} · ${snapshot.status} · ${Math.round(snapshot.elapsed_seconds)} seconds`);
    if (snapshot.status === 'running') {polling = setTimeout(() => poll().catch(failed), 800); return;}
    controls(false); await refreshHistory(); $('history').value = active;
    if (snapshot.error) status(snapshot.error);
    if (snapshot.result) await openEvidence();
    active = undefined;
  }
  async function launch(action) {
    if (busy) return;
    const selected = checked($('scenarios')).map(index => catalogue.scenarios[Number(index)]).map(({id, implementation}) => ({id, implementation}));
    const job = await request('/launch', {action, selection: selected, tools: checked($('tools')),
      samples: Number($('samples').value), timeout: Number($('timeout').value), threads: Number($('threads').value),
      evidence_id: $('history').value, max_experiments: Number($('max_experiments').value), budget_seconds: Number($('budget_seconds').value)});
    active = job.id; controls(true); status(`${action} started`); await poll();
  }
  function failed(error) {controls(false); status(String(error)); if (polling) clearTimeout(polling);}
  function bind(id, callback) {$(id).addEventListener('click', () => Promise.resolve().then(callback).catch(failed));}
  bind('discover', () => launch('discover')); bind('measure', () => launch('run')); bind('diagnose', () => launch('diagnose'));
  bind('investigate', () => launch('investigate')); bind('sync', () => launch('sync')); bind('inventory', () => launch('tools')); bind('narrate', () => launch('narrate'));
  bind('cancel', async () => {if (active) await request('/cancel', {id: active}); status('Cancellation requested; waiting for isolated worker shutdown.');});
  bind('open', () => openEvidence());
  bind('advise', async () => {await request('/advise', {id: $('history').value}); await openEvidence(true);});
  bind('compare', async () => {$('evidence').innerHTML = await request('/compare', {baseline: $('baseline').value, candidate: $('candidate').value}, true);});
  bind('json', () => {if ($('history').value) window.open(`${base}/evidence?id=${encodeURIComponent($('history').value)}&format=json`, '_blank', 'noopener');});
  bind('markdown', () => {if ($('history').value) window.open(`${base}/evidence?id=${encodeURIComponent($('history').value)}&format=markdown`, '_blank', 'noopener');});
  async function initialize() {
    catalogue = await request('/catalog');
    $('advisor-status').textContent = `Optional advisor: ${catalogue.advisor}. Configure it in Advisor and models. Verify its explanations against the evidence.`;
    if (catalogue.advisor_limits) {
      $('max_experiments').value = catalogue.advisor_limits.max_experiments;
      $('budget_seconds').value = catalogue.advisor_limits.budget_seconds;
    }
    controls(false);
    catalogue.scenarios.forEach((scenario, index) => {
      const label = document.createElement('label'); const checkbox = document.createElement('input'); checkbox.type = 'checkbox'; checkbox.value = String(index); checkbox.checked = true;
      const text = document.createElement('span'); text.textContent = `${scenario.id} / ${scenario.implementation} · ${scenario.collectors.join(', ')}`;
      label.append(checkbox, text); $('scenarios').append(label);
    });
    for (const tool of catalogue.analyzers) {
      const label = document.createElement('label'); const checkbox = document.createElement('input'); checkbox.type = 'checkbox'; checkbox.value = tool.tool; checkbox.checked = ['jet', 'latency'].includes(tool.tool);
      const text = document.createElement('span'); text.textContent = `${tool.tool}: ${tool.scope} (controller: ${tool.installation}; worker checked on launch)`; label.append(checkbox, text); $('tools').append(label);
    }
    await refreshHistory();
  }
  window.addEventListener('pagehide', () => {if (polling) clearTimeout(polling);});
  initialize().catch(failed);
})();
