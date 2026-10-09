(() => {
  'use strict';
  const body = document.body, messages = document.getElementById('messages'), input = document.getElementById('message');
  const lines = [];
  function add(line) {
    if (!line || typeof line.text !== 'string') return;
    lines.push({ type: line.type === 'system' ? 'system' : 'player', author: typeof line.author === 'string' ? line.author : '', text: line.text });
    while (lines.length > 60) lines.shift();
    render();
  }
  function render() {
    messages.textContent = '';
    lines.forEach(line => {
      const row = document.createElement('div'); row.className = `line ${line.type}`;
      if (line.author) { const author = document.createElement('span'); author.className = 'author'; author.textContent = line.author; row.appendChild(author); }
      row.appendChild(document.createTextNode(line.text)); messages.appendChild(row);
    });
    messages.scrollTop = messages.scrollHeight;
  }
  function close() { if (window.Open77) Open77.emit('eventcore:chat:close', {}); }
  document.getElementById('composer').addEventListener('submit', event => {
    event.preventDefault(); const text = input.value; input.value = '';
    if (text.trim() && window.Open77) Open77.emit('eventcore:chat:submit', { text });
  });
  input.addEventListener('keydown', event => { if (event.key === 'Escape') { event.preventDefault(); close(); } });
  if (window.Open77 && typeof Open77.on === 'function') {
    Open77.on('eventcore:chat:line', add);
    Open77.on('eventcore:chat:history', data => { lines.length = 0; (data && Array.isArray(data.lines) ? data.lines : []).forEach(add); render(); });
    Open77.on('eventcore:chat:open', data => {
      const open = !!(data && data.open); body.classList.toggle('closed', !open);
      if (open) { (data.history || []).forEach(add); input.value = ''; input.focus(); }
    });
    Open77.emit('eventcore:chat:ready', {});
  }
})();
