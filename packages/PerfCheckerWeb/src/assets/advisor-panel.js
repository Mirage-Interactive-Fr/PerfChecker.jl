/* Shared by Oxygen and the VS Code extension. No provider requests in the browser. */
(function (global) {
  'use strict';
  global.mountAdvisorPanel = function (root, send, initial = {}) {
    let config = {...initial.config}, busy = false, pending;
    const node = (tag, text) => {const e = document.createElement(tag); if (text !== undefined) e.textContent = text; return e;};
    const title = node('h1', 'Advisor and models');
    const intro = node('p', 'Rule-based advice is always available. Connecting a model is optional; opening this panel does not download one.');
    const form = node('form'); form.className = 'advisor-form'; form.addEventListener('submit', e => e.preventDefault());
    const status = node('p', 'Ready.'); status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite');
    const fields = {}, buttons = [];
    function field(key, label, type = 'text', options) {
      const wrap = node('label'), caption = node('span', label);
      const input = node(options ? 'select' : type === 'textarea' ? 'textarea' : 'input');
      input.id = 'advisor-' + key;
      if (options) for (const [value, text] of options) {const o = node('option', text); o.value = value; input.append(o);}
      else if (type !== 'textarea') input.type = type;
      input.value = config[key] ?? '';
      if (type === 'checkbox') input.checked = Boolean(config[key]);
      wrap.append(caption, input); form.append(wrap); fields[key] = input;
      return wrap;
    }
    field('protocol', 'Mode', 'text', [['none', 'Rule-based advice only'], ['ollama', 'Local model · Ollama'], ['chat_completions', 'Local or remote model · Chat Completions'], ['chat_completions_schema', 'Chat Completions · schema-constrained response'], ['mcp_http', 'Advisor provided by an MCP HTTP tool']]);
    fields.protocol.value = initial.enabled === false ? 'none' : config.protocol || 'none';
    if (initial.enabled !== false && config.protocol && !fields.protocol.value) {
      const option = node('option', 'Custom Julia provider · ' + config.protocol);
      option.value = config.protocol; fields.protocol.append(option); fields.protocol.value = config.protocol;
    }
    if (initial.config_location) intro.append(node('span', ' Configuration: ' + initial.config_location + '.'));
    const endpointWrap = field('endpoint', 'Server address');
    const modelWrap = field('model', 'Model name (or MCP report label)');
    const remoteWrap = field('allow_remote', 'Allow a remote HTTPS connection', 'checkbox');
    const authWrap = field('api_key_env', 'Token environment variable name (not the token itself)');
    const promptWrap = field('instructions', 'Custom instructions', 'textarea'); fields.instructions.maxLength = 5000;
    fields.instructions.placeholder = 'For example: reduce allocations without changing the public API.';
    const defaults = node('p', 'By default, ask for concrete ways to improve the Julia code, distinguish observations from hypotheses, and explain how to verify changes. Only a bounded summary of the evidence is sent.');
    const timeoutWrap = field('timeout', 'Connection / download timeout (seconds)', 'number');
    fields.timeout.min = '1'; fields.timeout.max = '3600'; fields.timeout.value = config.timeout || 120;
    const versionWrap = field('mcp_version', 'MCP version', 'text', [['2026-07-28', '2026-07-28'], ['2025-11-25', '2025-11-25']]);
    fields.mcp_version.value = config.mcp_version || '2026-07-28';
    const toolWrap = field('mcp_tool', 'Selected MCP tool');
    const argumentWrap = field('mcp_prompt_argument', 'Prompt argument'); fields.mcp_prompt_argument.value = config.mcp_prompt_argument || 'prompt';
    const argsWrap = field('mcp_arguments', 'Other tool arguments (JSON)', 'textarea'); fields.mcp_arguments.value = JSON.stringify(config.mcp_arguments || {}, null, 2);
    const responseWrap = field('mcp_response', 'MCP response', 'text', [['text', 'Free-text advice · no actions executed'], ['structured', 'Structured response · verified references']]);
    fields.mcp_response.value = config.mcp_response || 'text';
    config.investigates = initial.investigates || false;
    const investigateWrap = field('investigates', 'Allow selection of declared, bounded experiments', 'checkbox'); fields.investigates.checked = initial.investigates || false;
    const maxWrap = field('max_experiments', 'Maximum experiments', 'number'); fields.max_experiments.value = initial.max_experiments || 4; fields.max_experiments.min = '1'; fields.max_experiments.max = '100';
    const budgetWrap = field('budget_seconds', 'Total investigation budget (seconds)', 'number'); fields.budget_seconds.value = initial.budget_seconds || 300; fields.budget_seconds.min = '1'; fields.budget_seconds.max = '86400';
    const toolbar = node('div'); toolbar.className = 'toolbar';
    function button(label, action, parent = toolbar) {const b = node('button', label); b.type = 'button'; b.addEventListener('click', action); parent.append(b); buttons.push(b); return b;}
    function draft() {
      const value = {...config}; delete value.investigates; delete value.max_experiments; delete value.budget_seconds;
      for (const key of ['protocol', 'endpoint', 'model', 'api_key_env', 'instructions', 'mcp_version', 'mcp_tool', 'mcp_prompt_argument', 'mcp_response']) value[key] = fields[key].value;
      value.allow_remote = fields.allow_remote.checked; value.timeout = Number(fields.timeout.value);
      value.mcp_arguments = JSON.parse(fields.mcp_arguments.value || '{}');
      return value;
    }
    function state(value) {
      busy = value;
      for (const input of Object.values(fields)) input.disabled = busy;
      for (const b of buttons) b.disabled = busy;
      cancel.disabled = !busy; root.setAttribute('aria-busy', String(busy));
      if (!busy) visibility();
    }
    function request(action, model = '', confirmed = false) {
      try {
        if (!form.reportValidity()) return;
        const value = draft(), enabled = value.protocol !== 'none';
        if (!enabled && action !== 'save') throw new Error('Select a provider before testing a connection.');
        if (fields.investigates.checked && value.protocol === 'mcp_http' && value.mcp_response === 'text') throw new Error('Selecting MCP experiments requires a structured response.');
        state(true); status.textContent = action === 'pull' ? 'Downloading… The server manages the files; you can cancel the wait.' : 'Working…';
        send({type: 'advisorAction', action, config: enabled ? value : null, model, confirmed,
          investigates: fields.investigates.checked, max_experiments: Number(fields.max_experiments.value), budget_seconds: Number(fields.budget_seconds.value)});
      } catch (e) {state(false); status.textContent = String(e.message || e);}
    }
    button('Save configuration', () => request('save'));
    const probe = button('Test connection / discover', () => request('probe'));
    const cancel = button('Cancel operation', () => send({type: 'advisorCancel'})); cancel.disabled = true;
    const inventory = node('section'); inventory.setAttribute('aria-label', 'Available models and tools');
    const install = node('section'); install.className = 'card';
    install.append(node('h2', 'Optional local models'), node('p', 'Ollama shares model files across projects. Reported sizes include shared layers, so their sum may exceed actual disk usage.'));
    const nameLabel = node('label', 'Model to download'), name = node('input'); name.id = 'advisor-download-model'; name.placeholder = 'For example: qwen3:0.6b'; nameLabel.append(name); install.append(nameLabel);
    const download = button('Download this model…', () => confirm('pull', name.value.trim()), install);
    button('Refresh models', () => request('models'), install);
    const help = button('Install / start Ollama: official guide', () => send({type: 'advisorHelp'}), install);
    const confirmation = node('section'); confirmation.className = 'card'; confirmation.hidden = true;
    const confirmText = node('p'); confirmation.append(confirmText);
    const commit = button('Confirm', () => {const p = pending; pending = undefined; confirmation.hidden = true; if (p) request(p.action, p.model, true);}, confirmation);
    button('Back', () => {pending = undefined; confirmation.hidden = true;}, confirmation);
    function confirm(action, model) {
      if (!model) {status.textContent = 'Enter the exact model name.'; return;}
      pending = {action, model}; confirmation.hidden = false;
      confirmText.textContent = action === 'pull' ? `Download ${model} from the Ollama registry? The exact size is unknown until download and depends on the version. Check the model description and available disk space. Partial files may remain if interrupted.` :
        action === 'delete' ? `Delete ${model} from the shared Ollama server? Other projects using it will need to download it again. Layers still in use will be retained.` : `Unload ${model} from memory? Its files will remain on disk.`;
      commit.focus();
    }
    function visibility() {
      const mode = fields.protocol.value, enabled = mode !== 'none', mcp = mode === 'mcp_http';
      for (const wrap of [endpointWrap, modelWrap, remoteWrap, authWrap, promptWrap, timeoutWrap, investigateWrap]) wrap.hidden = !enabled;
      for (const wrap of [versionWrap, toolWrap, argumentWrap, argsWrap, responseWrap]) wrap.hidden = !mcp;
      maxWrap.hidden = budgetWrap.hidden = !enabled || !fields.investigates.checked;
      defaults.hidden = !enabled; install.hidden = mode !== 'ollama'; probe.disabled = !enabled;
      const local = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(?::\d+)?\//.test(fields.endpoint.value);
      download.disabled = busy || !local;
    }
    fields.protocol.addEventListener('change', () => {
      const mode = fields.protocol.value;
      if (mode === 'ollama') {fields.endpoint.value = 'http://127.0.0.1:11434/api/chat'; fields.model.value = 'qwen3:0.6b';}
      if (mode === 'mcp_http') {fields.endpoint.value = 'http://127.0.0.1:8083/mcp'; fields.model.value = 'MCP advisor';}
      if (mode.startsWith('chat_completions')) {fields.endpoint.value = 'http://127.0.0.1:8081/v1/chat/completions'; fields.model.value = 'local';}
      inventory.replaceChildren(); confirmation.hidden = true; pending = undefined; visibility();
    });
    form.addEventListener('input', () => {pending = undefined; confirmation.hidden = true;});
    for (const key of ['endpoint', 'api_key_env', 'mcp_version']) fields[key].addEventListener('input', () => inventory.replaceChildren());
    fields.investigates.addEventListener('change', visibility); fields.endpoint.addEventListener('input', visibility);
    root.replaceChildren(title, intro, form, defaults, toolbar, status, confirmation, inventory, install);
    visibility();
    return {
      receive(message) {
        if (message.type !== 'advisorResult') return;
        state(false);
        const result = message.result || {};
        status.textContent = result.message || result.error || result.status || 'Operation complete.';
        if (result.selected_available === false) status.textContent += ' The configured model / tool is missing: select an entry below.';
        if (result.tools || result.models) {
          inventory.replaceChildren(node('h2', result.tools ? 'Choose an MCP tool' : 'Available models'));
          if (!(result.tools || result.models).length) inventory.append(node('p', 'No entries available.'));
          for (const item of result.tools || result.models || []) {
            const row = node('article'); row.className = 'card';
            row.append(node('h3', item.name), node('p', item.description || (Number.isFinite(item.size_bytes) ? `${(item.size_bytes / 1e9).toFixed(3)} GB reported by the server` : 'Size unavailable')));
            button('Use', () => {
              if (result.tools) {
                fields.mcp_tool.value = item.name;
                const properties = item.inputSchema?.properties || {};
                const candidates = Object.keys(properties).filter(k => properties[k]?.type === 'string');
                const guess = candidates.find(k => ['prompt', 'question', 'message'].includes(k)) || (candidates.length === 1 ? candidates[0] : '');
                if (guess) fields.mcp_prompt_argument.value = guess;
                status.textContent = 'Tool selected. Check the prompt argument and required arguments, then save.';
              } else {fields.model.value = item.name; status.textContent = 'Model selected. Save to use it.';}
            }, row);
            if (result.tools) {
              const details = node('details'); details.append(node('summary', 'Required arguments and tool schema'), node('pre', JSON.stringify(item.inputSchema || {}, null, 2))); row.append(details);
            } else if (fields.protocol.value === 'ollama' && /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(?::\d+)?\//.test(fields.endpoint.value)) {
              button('Unload from memory…', () => confirm('unload', item.name), row);
              button('Delete from disk…', () => confirm('delete', item.name), row);
            }
            inventory.append(row);
          }
        }
      }
    };
  };
})(globalThis);
