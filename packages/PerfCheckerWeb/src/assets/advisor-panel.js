/* Shared by Oxygen and the VS Code extension. No provider requests in the browser. */
(function (global) {
  'use strict';
  global.mountAdvisorPanel = function (root, send, initial = {}) {
    let config = {...initial.config}, busy = false, pending;
    const node = (tag, text) => {const e = document.createElement(tag); if (text !== undefined) e.textContent = text; return e;};
    const title = node('h1', 'Conseiller et modèles');
    const intro = node('p', 'Les conseils déterministes sont toujours disponibles. Une connexion IA est facultative ; aucun modèle ne sera téléchargé à l’ouverture.');
    const form = node('form'); form.className = 'advisor-form'; form.addEventListener('submit', e => e.preventDefault());
    const status = node('p', 'Prêt.'); status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite');
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
    field('protocol', 'Mode', 'text', [['none', 'Conseils déterministes uniquement'], ['ollama', 'Modèle local · Ollama'], ['chat_completions', 'Modèle local ou distant · Chat Completions'], ['chat_completions_schema', 'Chat Completions · réponse structurée contrainte'], ['mcp_http', 'Assistant exposé par un outil MCP HTTP']]);
    fields.protocol.value = initial.enabled === false ? 'none' : config.protocol || 'none';
    if (initial.enabled !== false && config.protocol && !fields.protocol.value) {
      const option = node('option', 'Fournisseur Julia personnalisé · ' + config.protocol);
      option.value = config.protocol; fields.protocol.append(option); fields.protocol.value = config.protocol;
    }
    if (initial.config_location) intro.append(node('span', ' Configuration : ' + initial.config_location + '.'));
    const endpointWrap = field('endpoint', 'Adresse du serveur');
    const modelWrap = field('model', 'Nom du modèle (ou étiquette du rapport MCP)');
    const remoteWrap = field('allow_remote', 'Autoriser explicitement une connexion HTTPS distante', 'checkbox');
    const authWrap = field('api_key_env', 'Nom de la variable d’environnement du jeton (jamais le jeton)');
    const promptWrap = field('instructions', 'Consignes personnalisées', 'textarea'); fields.instructions.maxLength = 5000;
    fields.instructions.placeholder = 'Ex. : réduire les allocations sans changer l’API publique.';
    const defaults = node('p', 'Par défaut : demander des pistes concrètes pour améliorer le code Julia, séparer observations et hypothèses, et indiquer comment vérifier les corrections. Seul un résumé borné des preuves est envoyé.');
    const timeoutWrap = field('timeout', 'Délai maximal de connexion / téléchargement (secondes)', 'number');
    fields.timeout.min = '1'; fields.timeout.max = '3600'; fields.timeout.value = config.timeout || 120;
    const versionWrap = field('mcp_version', 'Version MCP', 'text', [['2026-07-28', '2026-07-28'], ['2025-11-25', '2025-11-25']]);
    fields.mcp_version.value = config.mcp_version || '2026-07-28';
    const toolWrap = field('mcp_tool', 'Outil MCP sélectionné');
    const argumentWrap = field('mcp_prompt_argument', 'Argument recevant le prompt'); fields.mcp_prompt_argument.value = config.mcp_prompt_argument || 'prompt';
    const argsWrap = field('mcp_arguments', 'Autres arguments de l’outil (JSON)', 'textarea'); fields.mcp_arguments.value = JSON.stringify(config.mcp_arguments || {}, null, 2);
    const responseWrap = field('mcp_response', 'Réponse MCP', 'text', [['text', 'Conseils libres · aucune action exécutée'], ['structured', 'Réponse structurée · références vérifiées']]);
    fields.mcp_response.value = config.mcp_response || 'text';
    config.investigates = initial.investigates || false;
    const investigateWrap = field('investigates', 'Permettre le choix d’expériences déclarées et bornées', 'checkbox'); fields.investigates.checked = initial.investigates || false;
    const maxWrap = field('max_experiments', 'Nombre maximal d’expériences', 'number'); fields.max_experiments.value = initial.max_experiments || 4; fields.max_experiments.min = '1'; fields.max_experiments.max = '100';
    const budgetWrap = field('budget_seconds', 'Budget total d’investigation (secondes)', 'number'); fields.budget_seconds.value = initial.budget_seconds || 300; fields.budget_seconds.min = '1'; fields.budget_seconds.max = '86400';
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
        if (!enabled && action !== 'save') throw new Error('Choisis un fournisseur pour tester une connexion.');
        if (fields.investigates.checked && value.protocol === 'mcp_http' && value.mcp_response === 'text') throw new Error('Le choix d’expériences MCP nécessite une réponse structurée.');
        state(true); status.textContent = action === 'pull' ? 'Téléchargement en cours… Le serveur gère les fichiers ; tu peux interrompre l’attente.' : 'Opération en cours…';
        send({type: 'advisorAction', action, config: enabled ? value : null, model, confirmed,
          investigates: fields.investigates.checked, max_experiments: Number(fields.max_experiments.value), budget_seconds: Number(fields.budget_seconds.value)});
      } catch (e) {state(false); status.textContent = String(e.message || e);}
    }
    button('Enregistrer la configuration', () => request('save'));
    const probe = button('Tester la connexion / découvrir', () => request('probe'));
    const cancel = button('Annuler l’opération', () => send({type: 'advisorCancel'})); cancel.disabled = true;
    const inventory = node('section'); inventory.setAttribute('aria-label', 'Modèles et outils disponibles');
    const install = node('section'); install.className = 'card';
    install.append(node('h2', 'Modèles locaux facultatifs'), node('p', 'Ollama stocke les modèles une seule fois pour tous tes projets. Les tailles incluent des couches partagées : leur somme ne représente pas forcément l’espace réel.'));
    const nameLabel = node('label', 'Modèle à télécharger'), name = node('input'); name.id = 'advisor-download-model'; name.placeholder = 'Ex. : qwen3:0.6b'; nameLabel.append(name); install.append(nameLabel);
    const download = button('Télécharger ce modèle…', () => confirm('pull', name.value.trim()), install);
    button('Actualiser les modèles', () => request('models'), install);
    const help = button('Installer / démarrer Ollama : guide officiel', () => send({type: 'advisorHelp'}), install);
    const confirmation = node('section'); confirmation.className = 'card'; confirmation.hidden = true;
    const confirmText = node('p'); confirmation.append(confirmText);
    const commit = button('Confirmer', () => {const p = pending; pending = undefined; confirmation.hidden = true; if (p) request(p.action, p.model, true);}, confirmation);
    button('Revenir', () => {pending = undefined; confirmation.hidden = true;}, confirmation);
    function confirm(action, model) {
      if (!model) {status.textContent = 'Indique le nom exact du modèle.'; return;}
      pending = {action, model}; confirmation.hidden = false;
      confirmText.textContent = action === 'pull' ? `Télécharger « ${model} » depuis le registre Ollama ? Taille exacte inconnue avant téléchargement ; elle dépend de sa version. Vérifie la fiche du modèle et l’espace disponible. Des fichiers partiels peuvent rester après interruption.` :
        action === 'delete' ? `Supprimer « ${model} » du serveur Ollama partagé ? Les autres projets utilisant ce modèle devront le télécharger à nouveau. Les couches encore utilisées seront conservées.` : `Décharger « ${model} » de la mémoire ? Les fichiers resteront sur le disque.`;
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
        status.textContent = result.message || result.error || result.status || 'Opération terminée.';
        if (result.selected_available === false) status.textContent += ' Le modèle / outil configuré est absent : sélectionne une entrée ci-dessous.';
        if (result.tools || result.models) {
          inventory.replaceChildren(node('h2', result.tools ? 'Choisir un outil MCP' : 'Modèles disponibles'));
          if (!(result.tools || result.models).length) inventory.append(node('p', 'Aucune entrée disponible.'));
          for (const item of result.tools || result.models || []) {
            const row = node('article'); row.className = 'card';
            row.append(node('h3', item.name), node('p', item.description || (Number.isFinite(item.size_bytes) ? `${(item.size_bytes / 1e9).toFixed(3)} Go déclarés par le serveur` : 'Taille non disponible')));
            button('Utiliser', () => {
              if (result.tools) {
                fields.mcp_tool.value = item.name;
                const properties = item.inputSchema?.properties || {};
                const candidates = Object.keys(properties).filter(k => properties[k]?.type === 'string');
                const guess = candidates.find(k => ['prompt', 'question', 'message'].includes(k)) || (candidates.length === 1 ? candidates[0] : '');
                if (guess) fields.mcp_prompt_argument.value = guess;
                status.textContent = 'Outil sélectionné. Vérifie l’argument du prompt et les arguments requis, puis enregistre.';
              } else {fields.model.value = item.name; status.textContent = 'Modèle sélectionné. Enregistre pour l’utiliser.';}
            }, row);
            if (result.tools) {
              const details = node('details'); details.append(node('summary', 'Arguments requis et contrat de l’outil'), node('pre', JSON.stringify(item.inputSchema || {}, null, 2))); row.append(details);
            } else if (fields.protocol.value === 'ollama' && /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(?::\d+)?\//.test(fields.endpoint.value)) {
              button('Décharger de la mémoire…', () => confirm('unload', item.name), row);
              button('Supprimer du disque…', () => confirm('delete', item.name), row);
            }
            inventory.append(row);
          }
        }
      }
    };
  };
})(globalThis);
