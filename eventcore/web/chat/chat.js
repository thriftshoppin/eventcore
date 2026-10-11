(() => {
  'use strict';
  const body = document.body;
  const messages = document.getElementById('messages');
  const input = document.getElementById('message');
  const suggestionPanel = document.getElementById('suggestions');
  const suggestionList = document.getElementById('suggestion-list');
  const lines = [];
  const suggestions = new Map();
  let visibleSuggestions = [];
  let selectedSuggestion = 0;
  let hideTimer = 0;
  let open = false;

  const bounded = (value, max = 240) => String(value || '').slice(0, max);
  const normalizeCommand = value => {
    const command = bounded(value, 80).trim();
    return command.startsWith('/') ? command : `/${command}`;
  };

  function renderMessages() {
    messages.replaceChildren();
    lines.slice(-4).forEach(line => {
      const row = document.createElement('div');
      row.className = `line ${line.type}`;
      if (line.author) {
        const author = document.createElement('span');
        author.className = 'author';
        if (line.author.toLowerCase() === 'eventcore') author.classList.add('eventcore');
        author.textContent = `${line.author}:`;
        row.appendChild(author);
      }
      row.appendChild(document.createTextNode(line.text));
      messages.appendChild(row);
    });
  }

  function setHistory(history) {
    lines.length = 0;
    if (Array.isArray(history)) {
      history.slice(-60).forEach(line => {
        if (!line || typeof line.text !== 'string') return;
        lines.push({
          type: line.type === 'error' ? 'error' : line.type === 'system' ? 'system' : 'player',
          author: bounded(line.author, 48),
          text: bounded(line.text, 512),
        });
      });
    }
    renderMessages();
  }

  function add(line) {
    if (!line || typeof line.text !== 'string') return;
    lines.push({
      type: line.type === 'error' ? 'error' : line.type === 'system' ? 'system' : 'player',
      author: bounded(line.author, 48),
      text: bounded(line.text, 512),
    });
    while (lines.length > 60) lines.shift();
    renderMessages();
    body.classList.add('has-lines');
    window.clearTimeout(hideTimer);
    if (!open) hideTimer = window.setTimeout(() => body.classList.remove('has-lines'), 8000);
  }

  function renderSuggestions() {
    suggestionList.replaceChildren();
    const query = input.value.trim().toLowerCase();
    if (!open || !query.startsWith('/')) {
      visibleSuggestions = [];
      selectedSuggestion = 0;
      suggestionPanel.hidden = true;
      return;
    }
    const commandQuery = query.split(/\s+/)[0];
    visibleSuggestions = [...suggestions.values()]
      .filter(item => item.command.toLowerCase().startsWith(commandQuery))
      .sort((a, b) => a.command.length - b.command.length || a.command.localeCompare(b.command))
      .slice(0, 4);
    selectedSuggestion = Math.max(0, Math.min(selectedSuggestion, visibleSuggestions.length - 1));
    if (!visibleSuggestions.length) {
      const empty = document.createElement('div');
      empty.className = 'suggestion';
      empty.textContent = 'No matching command';
      suggestionList.appendChild(empty);
      suggestionPanel.hidden = false;
      return;
    }
    visibleSuggestions.forEach((item, index) => {
      const row = document.createElement('div');
      row.className = `suggestion${index === selectedSuggestion ? ' selected' : ''}`;
      row.setAttribute('role', 'option');
      row.setAttribute('aria-selected', String(index === selectedSuggestion));
      const syntax = document.createElement('span');
      const command = document.createElement('strong');
      command.className = 'command';
      command.textContent = item.command;
      syntax.appendChild(command);
      (Array.isArray(item.parameters) ? item.parameters : []).slice(0, 5).forEach(parameter => {
        const name = bounded(parameter && parameter.name || parameter, 36);
        const node = document.createElement('span');
        node.className = 'params';
        node.textContent = parameter && parameter.optional ? `[${name}]` : `<${name}>`;
        if (parameter && parameter.help) node.title = bounded(parameter.help);
        syntax.appendChild(node);
      });
      row.appendChild(syntax);
      const help = document.createElement('span');
      help.className = 'help';
      help.textContent = bounded(item.help, 180);
      row.appendChild(help);
      row.addEventListener('pointerdown', event => {
        event.preventDefault();
        selectedSuggestion = index;
        completeSuggestion();
      });
      suggestionList.appendChild(row);
    });
    suggestionPanel.hidden = false;
  }

  function completeSuggestion() {
    const item = visibleSuggestions[selectedSuggestion];
    if (!item) return false;
    const suffix = input.value.trim().match(/^\/\S*(.*)$/s)?.[1]?.trim() || '';
    input.value = `${item.command}${suffix ? ` ${suffix}` : ' '}`;
    input.setSelectionRange(input.value.length, input.value.length);
    renderSuggestions();
    input.focus();
    return true;
  }

  function focusInput() {
    if (!open) return;
    input.focus({ preventScroll: true });
    input.setSelectionRange(input.value.length, input.value.length);
  }

  function close() {
    if (window.Open77) Open77.emit('eventcore:chat:close', {});
  }

  document.getElementById('composer').addEventListener('submit', event => {
    event.preventDefault();
    const text = input.value;
    input.value = '';
    renderSuggestions();
    if (text.trim() && window.Open77) Open77.emit('eventcore:chat:submit', { text });
  });

  input.addEventListener('input', () => {
    selectedSuggestion = 0;
    renderSuggestions();
    if (open && input.value.trim().startsWith('/') && window.Open77) {
      Open77.emit('eventcore:chat:requestSuggestions', {});
    }
  });
  input.addEventListener('keydown', event => {
    if (event.isComposing) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      close();
    } else if (event.key === 'Tab' && visibleSuggestions.length) {
      event.preventDefault();
      completeSuggestion();
    } else if (event.key === 'ArrowUp' && visibleSuggestions.length) {
      event.preventDefault();
      selectedSuggestion = (selectedSuggestion - 1 + visibleSuggestions.length) % visibleSuggestions.length;
      renderSuggestions();
    } else if (event.key === 'ArrowDown' && visibleSuggestions.length) {
      event.preventDefault();
      selectedSuggestion = (selectedSuggestion + 1) % visibleSuggestions.length;
      renderSuggestions();
    }
  });

  if (window.Open77 && typeof Open77.on === 'function') {
    Open77.on('eventcore:chat:line', add);
    Open77.on('eventcore:chat:history', data => setHistory(data && data.lines));
    Open77.on('eventcore:chat:suggestions', data => {
      const list = Array.isArray(data) ? data : data && Array.isArray(data.suggestions) ? data.suggestions : [];
      list.forEach(item => {
        if (!item || typeof item.command !== 'string') return;
        const command = normalizeCommand(item.command);
        suggestions.set(command.toLowerCase(), {
          command,
          help: bounded(item.help),
          parameters: Array.isArray(item.parameters) ? item.parameters : [],
        });
      });
      renderSuggestions();
    });
    Open77.on('eventcore:chat:suggestion', item => {
      if (!item || typeof item.command !== 'string') return;
      const command = normalizeCommand(item.command);
      suggestions.set(command.toLowerCase(), { command, help: bounded(item.help), parameters: item.parameters || [] });
      renderSuggestions();
    });
    Open77.on('eventcore:chat:removeSuggestion', data => {
      suggestions.delete(normalizeCommand(data && data.command).toLowerCase());
      renderSuggestions();
    });
    Open77.on('eventcore:chat:clearSuggestions', () => { suggestions.clear(); renderSuggestions(); });
    Open77.on('eventcore:chat:focus', focusInput);
    Open77.on('eventcore:chat:open', data => {
      open = !!(data && data.open);
      body.classList.toggle('closed', !open);
      if (Array.isArray(data && data.history)) setHistory(data.history);
      if (open) {
        input.value = '';
        focusInput();
      }
      renderSuggestions();
    });
    Open77.emit('eventcore:chat:ready', {});
  }
})();
