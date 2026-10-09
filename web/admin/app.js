(function () {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const body = document.body;
  let sequence = 0;
  let availableCommands = new Set();

  function requestRefresh() {
    sequence += 1;
    if (window.Open77 && typeof Open77.emit === "function") {
      Open77.emit("admin:refresh", { requestId: String(sequence) });
    }
  }

  function setText(id, value) { $(id).textContent = String(value); }

  function runCommand(command, args, confirmText) {
    if (!availableCommands.has(command)) return;
    if (confirmText && !window.confirm(confirmText)) return;
    if (window.Open77 && typeof Open77.emit === "function") {
      Open77.emit("admin:command", { command, args: (args || []).map(String) });
      setText("tool-result", "Sent " + command + " through Warden command authorization.");
    }
  }

  function makeButton(label, command, args, danger, confirmText) {
    const button = document.createElement("button");
    button.type = "button"; button.textContent = label;
    if (danger) button.className = "danger";
    button.disabled = !availableCommands.has(command);
    button.addEventListener("click", () => runCommand(command, args, confirmText));
    return button;
  }

  function makeBanButton(playerId) {
    const button = document.createElement("button");
    button.type = "button"; button.textContent = "Ban"; button.className = "danger";
    button.disabled = !availableCommands.has("admin.moderate.ban");
    button.addEventListener("click", () => {
      const duration = window.prompt("Ban duration (30m, 12h, 7d, 3600s, or perm):", "30m");
      if (!duration) return;
      if (!/^(perm|permanent|[1-9]\d*[smhd])$/i.test(duration.trim())) {
        setText("tool-result", "Use a duration such as 30m, 12h, 7d, 3600s, or perm."); return;
      }
      const reason = window.prompt("Reason for banning player " + playerId + ":");
      if (!reason || !reason.trim()) return;
      if (!window.confirm("Ban player " + playerId + " for " + duration + "?")) return;
      runCommand("admin.moderate.ban", [String(playerId), duration.trim(), reason.trim()]);
    });
    return button;
  }

  function renderQuickTools() {
    const root = $("quick-tools");
    while (root.firstChild) root.removeChild(root.firstChild);
    const options = [
      ["Heal self", "admin.self.heal", []],
      ["Revive self", "admin.self.revive", []],
      ["Toggle noclip", "admin.self.noclip", []],
      ["Toggle fly", "admin.self.fly", []],
      ["Read audit", "admin.read.audit", []],
      ["Detailed player readout", "admin.read.players", []],
      ["Server status", "admin.server.status", []],
      ["Clean spawned vehicles", "admin.world.cleanup", [], true, "Remove empty vehicles spawned by the admin tools?"],
    ];
    options.forEach(([label, command, args, danger, confirmText]) => {
      if (availableCommands.has(command)) root.appendChild(makeButton(label, command, args, danger, confirmText));
    });
    if (availableCommands.has("admin.world.announce")) {
      const input = document.createElement("input");
      input.type = "text"; input.maxLength = 150; input.placeholder = "Server announcement";
      input.setAttribute("aria-label", "Server announcement");
      const button = document.createElement("button"); button.type = "button"; button.textContent = "Announce";
      button.addEventListener("click", () => {
        const text = input.value.trim();
        if (text) runCommand("admin.world.announce", [text]);
      });
      root.append(input, button);
    }
    if (root.childNodes.length === 0) {
      const note = document.createElement("span"); note.textContent = "No admin commands are assigned to your Warden role."; root.appendChild(note);
    }
  }

  function renderPlayers(rows) {
    const table = $("players");
    while (table.firstChild) table.removeChild(table.firstChild);
    if (!Array.isArray(rows) || rows.length === 0) {
      const row = document.createElement("tr");
      const cell = document.createElement("td");
      cell.colSpan = 5; cell.className = "empty"; cell.textContent = "No players are online.";
      row.appendChild(cell); table.appendChild(row); return;
    }
    rows.forEach((player) => {
      const row = document.createElement("tr");
      if (player.isAdmin === true) row.className = "admin";
      const values = [player.playerId, player.name, Array.isArray(player.roles) && player.roles.length ? player.roles.join(", ") : "—", player.isAdmin === true ? "GLOBAL ADMIN" : "PLAYER"];
      values.forEach((value) => { const cell = document.createElement("td"); cell.textContent = String(value); row.appendChild(cell); });
      const actions = document.createElement("td"); actions.className = "tools";
      const id = String(player.playerId);
      [
        ["Heal", "admin.player.heal", [id]],
        ["Revive", "admin.player.revive", [id]],
        ["Goto", "admin.player.goto", [id]],
        ["Bring", "admin.player.bring", [id]],
        ["Kill", "admin.player.kill", [id], true, "Kill player " + id + "?"],
        ["Kick", "admin.moderate.kick", [id], true, "Kick player " + id + "?"],
      ].forEach(([label, command, args, danger, confirmText]) => {
        if (availableCommands.has(command)) actions.appendChild(makeButton(label, command, args, danger, confirmText));
      });
      if (availableCommands.has("admin.moderate.ban")) actions.appendChild(makeBanButton(id));
      if (actions.childNodes.length === 0) actions.textContent = "No assigned tools";
      row.appendChild(actions);
      table.appendChild(row);
    });
  }

  function renderRuntime(id, rows, kind) {
    const root = $(id);
    while (root.firstChild) root.removeChild(root.firstChild);
    if (!Array.isArray(rows) || rows.length === 0) {
      const empty = document.createElement("div"); empty.className = "empty";
      empty.textContent = "No " + kind + " registered."; root.appendChild(empty); return;
    }
    rows.forEach((entry) => {
      const row = document.createElement("div"); row.className = "runtime-row";
      const title = document.createElement("strong");
      const detail = document.createElement("span");
      if (kind === "services") {
        title.textContent = String(entry.id || "unknown service");
        detail.textContent = "v" + String(entry.version || "?") + " · " + String(entry.resource || "unknown");
      } else {
        title.textContent = String(entry.event || "unknown event");
        detail.textContent = String(entry.count || 0) + " listener(s)";
      }
      row.append(title, detail); root.appendChild(row);
    });
  }

  function parseCommandArgs(raw) {
    const args = []; let token = ""; let quote = null; let escaped = false; let started = false;
    for (const char of String(raw || "")) {
      if (escaped) { token += char; escaped = false; started = true; continue; }
      if (quote && char === "\\") { escaped = true; continue; }
      if (quote) {
        if (char === quote) quote = null;
        else token += char;
        started = true; continue;
      }
      if (char === "\"" || char === "'") { quote = char; started = true; continue; }
      if (/\s/.test(char)) {
        if (started) { args.push(token); token = ""; started = false; }
        continue;
      }
      token += char; started = true;
    }
    if (escaped || quote) return null;
    if (started) args.push(token);
    return args;
  }

  if (window.Open77 && typeof Open77.on === "function") {
    Open77.on("admin:open", (payload) => body.classList.toggle("closed", !(payload && payload.open === true)));
    Open77.on("admin:loading", (payload) => { if (payload && payload.loading) setText("status", "Reading server roles…"); });
    Open77.on("admin:data", (payload) => {
      if (!payload || typeof payload !== "object") return;
      const admins = Array.isArray(payload.admins) ? payload.admins : [];
      const players = Array.isArray(payload.players) ? payload.players : [];
      availableCommands = new Set(Array.isArray(payload.availableCommands) ? payload.availableCommands : []);
      setText("status", "Access verified by EventCore against Warden ACL.");
      setText("online-count", players.length);
      setText("admin-count", admins.length);
      setText("version", payload.version || "—");
      setText("service-count", payload.serviceCount ?? "—");
      setText("updated", new Date().toLocaleTimeString());
      renderPlayers(players);
      renderQuickTools();
      renderRuntime("services", payload.services, "services");
      renderRuntime("event-handlers", payload.eventHandlers, "events");
    });
    Open77.on("admin:commandResult", (payload) => {
      if (payload && typeof payload.message === "string") setText("tool-result", payload.message);
    });
    Open77.on("admin:toolData", (message) => {
      if (!message || typeof message.channel !== "string" || !message.payload) return;
      setText("tool-output-title", "Command output");
      setText("tool-output-channel", message.channel);
      $("tool-output").textContent = JSON.stringify(message.payload, null, 2);
    });
    Open77.emit("admin:ready", {});
  }

  $("refresh").addEventListener("click", requestRefresh);
  $("command-form").addEventListener("submit", (event) => {
    event.preventDefault();
    const command = $("command-name").value.trim();
    if (!/^admin\.[a-z0-9_.-]+$/.test(command)) {
      setText("tool-result", "Enter a registered admin command such as admin.read.vehicles."); return;
    }
    const args = parseCommandArgs($("command-args").value);
    if (!args || args.length > 12 || args.some((arg) => arg.length > 160)) {
      setText("tool-result", "Arguments need balanced quotes, at most 12 values, and at most 160 characters each."); return;
    }
    if (window.Open77 && typeof Open77.emit === "function") {
      Open77.emit("admin:command", { command, args });
      setText("tool-result", "Sent " + command + " through Warden command authorization.");
    }
  });
  $("close").addEventListener("click", () => Open77.emit("admin:close", {}));
  window.addEventListener("keydown", (event) => { if (event.key === "Escape") Open77.emit("admin:close", {}); });
})();
