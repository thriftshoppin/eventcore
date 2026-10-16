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


  // ---- HUD test bench -------------------------------------------------------------------
  const NATIVE = window.EC_NATIVE || { layers: [], widgets: [], controllers: [], blackboards: [] };
  const KINDS = { controller: NATIVE.controllers, layer: NATIVE.layers, widget: NATIVE.widgets, blackboard: NATIVE.blackboards };
  const hudRows = []; const seenSeq = new Set();
  const emit = (name, payload) => { if (window.Open77 && typeof Open77.emit === "function") Open77.emit(name, payload); };

  function fillHudList() {
    const list = $("hud-list"); const needle = $("hud-search").value.trim().toLowerCase();
    const kind = $("hud-kind").value;
    while (list.firstChild) list.removeChild(list.firstChild);
    (KINDS[kind] || []).filter((e) => !needle || e.n.toLowerCase().includes(needle)).slice(0, 300).forEach((e) => {
      const option = document.createElement("option"); option.value = e.n; option.textContent = e.n; list.appendChild(option);
    });
    if (kind === "layer") list.value = "inkHUDLayer";
    else if (list.options.length) list.selectedIndex = 0;
    showHudDetail();
  }

  function showHudDetail() {
    const kind = $("hud-kind").value; const name = $("hud-list").value;
    const entry = (KINDS[kind] || []).find((e) => e.n === name);
    $("hud-detail").textContent = !entry ? "" : kind === "blackboard"
      ? name + ": " + entry.v.map((f) => f[0] + ":" + f[1]).join(", ")
      : name + (entry.p ? " extends " + entry.p : "");
  }

  function hudSpec(extra) {
    return Object.assign({ target: $("hud-list").value, action: $("hud-action").value }, extra || {});
  }

  function sendHud(spec, local) {
    const player = Number($("hud-player").value) || 0;
    if (!local && !player) return;
    emit(local ? "hud:local" : "hud:send", { player, spec });
  }

  function addHudRow(entry) {
    if (!entry || typeof entry !== "object") return;
    if (entry.seq) { if (seenSeq.has(entry.seq)) return; seenSeq.add(entry.seq); }
    const body = $("hud-log");
    if (hudRows.length === 0) while (body.firstChild) body.removeChild(body.firstChild);
    hudRows.push(entry);
    const row = document.createElement("tr"); row.className = entry.ok ? "ok" : "bad";
    const time = entry.at ? new Date(entry.at * 1000).toLocaleTimeString() : "";
    [entry.seq || "", time, entry.adminName || "", entry.playerName || "", (entry.action || "") + " " + (entry.target || ""),
      (entry.ok ? "OK " : "FAIL ") + (entry.detail || ""), entry.ms != null ? entry.ms : ""].forEach((value) => {
      const cell = document.createElement("td"); cell.textContent = String(value); row.appendChild(cell);
    });
    body.insertBefore(row, body.firstChild);
    while (body.childNodes.length > 150) body.removeChild(body.lastChild);
  }

  function fillHudPlayers(players) {
    const select = $("hud-player"); const keep = select.value;
    while (select.firstChild) select.removeChild(select.firstChild);
    (players || []).forEach((p) => {
      const option = document.createElement("option"); option.value = String(p.playerId);
      option.textContent = p.playerId + " " + p.name; select.appendChild(option);
    });
    if (keep) select.value = keep;
  }

  $("hud-kind").addEventListener("change", fillHudList);
  $("hud-search").addEventListener("input", fillHudList);
  $("hud-list").addEventListener("change", showHudDetail);
  $("hud-send").addEventListener("click", () => sendHud(hudSpec(), false));
  $("hud-local").addEventListener("click", () => sendHud(hudSpec(), true));
  $("hud-layer-hide").addEventListener("click", () => sendHud({ target: "inkHUDLayer", action: "hide" }, false));
  $("hud-layer-show").addEventListener("click", () => sendHud({ target: "inkHUDLayer", action: "show" }, false));
  $("hud-all-hide").addEventListener("click", () => sendHud({ group: "hud", action: "hide" }, false));
  $("hud-all-show").addEventListener("click", () => sendHud({ group: "hud", action: "show" }, false));
  $("hud-clear").addEventListener("click", () => {
    hudRows.length = 0; const body = $("hud-log");
    while (body.firstChild) body.removeChild(body.firstChild);
  });
  function parseSchedule() {
    const steps = [];
    for (const line of $("hud-sched").value.split(/\r?\n/)) {
      const text = line.trim(); if (!text || text[0] === "#") continue;
      const m = /^(\d+)\s+(show|hide|status)\s+([A-Za-z0-9_]+)$/.exec(text);
      if (!m) return { error: "Bad line: " + text };
      const step = { at: Number(m[1]), action: m[2] };
      if (m[3] === "hud" || m[3] === "verified") step.group = m[3]; else step.target = m[3];
      steps.push(step);
    }
    return steps.length ? { steps } : { error: "Add at least one step." };
  }
  $("hud-sched-send").addEventListener("click", () => {
    const parsed = parseSchedule();
    if (parsed.error) { setText("tool-result", parsed.error); return; }
    emit("hud:schedule", { player: Number($("hud-player").value) || 0, steps: parsed.steps, loops: Number($("hud-loops").value) || 1 });
  });
  $("hud-sched-stop").addEventListener("click", () => emit("hud:cancel", {}));
  fillHudList();

  // ── EventView ────────────────────────────────────────────────────────────
  const evRows = [];
  function evTargetToken() {
    const mode = $("ev-target").value;
    if (mode === "player") {
      const id = Number($("ev-player-id").value);
      return id > 0 ? String(id) : "";
    }
    return mode;
  }
  function addEvRow(entry) {
    if (!entry) return;
    evRows.push(entry);
    while (evRows.length > 200) evRows.shift();
    const body = $("ev-log");
    while (body.firstChild) body.removeChild(body.firstChild);
    if (!evRows.length) {
      const tr = document.createElement("tr");
      tr.innerHTML = '<td colspan="5" class="empty">No EventView activity yet.</td>';
      body.appendChild(tr);
      return;
    }
    evRows.slice().reverse().forEach((e, i) => {
      const tr = document.createElement("tr");
      const detail = e.label || e.missionId || e.schedule || e.stepKind || e.targetToken || "—";
      const player = e.playerName || e.player || "—";
      const result = e.ok === false ? ("FAIL " + (e.reason || "")) : (e.kind || "ok");
      tr.innerHTML = "<td>" + (evRows.length - i) + "</td><td>" + (e.kind || "—") + "</td><td>" +
        String(detail).replace(/</g, "&lt;") + "</td><td>" + String(player).replace(/</g, "&lt;") +
        "</td><td>" + String(result).replace(/</g, "&lt;") + "</td>";
      body.appendChild(tr);
    });
  }
  function parseEvSteps() {
    const steps = [];
    for (const line of $("ev-steps").value.split(/\r?\n/)) {
      const text = line.trim();
      if (!text || text[0] === "#") continue;
      // <ms> hud <action> <target>
      let m = /^(\d+)\s+hud\s+(show|hide|status)\s+([A-Za-z0-9_]+)$/.exec(text);
      if (m) {
        steps.push({ at: Number(m[1]), kind: "hud", action: m[2], target: m[3] });
        continue;
      }
      // <ms> widget <id> k=v k=v...
      m = /^(\d+)\s+widget\s+([A-Za-z0-9_.-]+)(.*)$/.exec(text);
      if (m) {
        const values = {};
        const rest = (m[3] || "").trim();
        if (rest) {
          for (const part of rest.split(/\s+/)) {
            const kv = /^([A-Za-z0-9_]+)=(.*)$/.exec(part);
            if (kv) {
              let v = kv[2];
              if (v === "true" || v === "false") v = v === "true";
              else if (!isNaN(Number(v)) && v !== "") v = Number(v);
              values[kv[1]] = v;
            }
          }
        }
        steps.push({ at: Number(m[1]), kind: "widget", id: m[2], values });
        continue;
      }
      // <ms> mission <id> title=.. status=..
      m = /^(\d+)\s+mission\s+([A-Za-z0-9_.-]+)(.*)$/.exec(text);
      if (m) {
        const entry = {};
        const rest = (m[3] || "").trim();
        if (rest) {
          for (const part of rest.split(/\s+/)) {
            const kv = /^([A-Za-z0-9_]+)=(.*)$/.exec(part);
            if (kv) entry[kv[1]] = kv[2];
          }
        }
        steps.push({ at: Number(m[1]), kind: "mission", missionId: m[2], entry });
        continue;
      }
      // <ms> mission_clear [id]
      m = /^(\d+)\s+mission_clear(?:\s+([A-Za-z0-9_.-]+))?$/.exec(text);
      if (m) {
        steps.push({ at: Number(m[1]), kind: "mission_clear", missionId: m[2] || null });
        continue;
      }
      return { error: "Bad EventView line: " + text };
    }
    return steps.length ? { steps } : { error: "Add at least one step." };
  }
  $("ev-sched-send").addEventListener("click", () => {
    const token = evTargetToken();
    if (!token) { setText("tool-result", "Pick a target (or enter a player id)."); return; }
    const parsed = parseEvSteps();
    if (parsed.error) { setText("tool-result", parsed.error); return; }
    emit("eventview:schedule", {
      target: token,
      steps: parsed.steps,
      loops: Number($("ev-loops").value) || 1,
      label: ($("ev-label").value || "").trim() || undefined,
    });
    setText("tool-result", "EventView schedule sent.");
  });
  $("ev-sched-stop").addEventListener("click", () => {
    emit("eventview:cancel", {});
    setText("tool-result", "EventView cancel sent.");
  });
  $("ev-targets").addEventListener("click", () => {
    const token = evTargetToken() || "all";
    // Use command path so result appears in tool-result via existing admin command channel if available;
    // also emit a soft request the server can answer via eventview:result in future.
    setText("tool-result", "Resolve targets: " + token + " (use /eventcore.eventview.targets " + token + ")");
  });
  $("ev-mission-list").addEventListener("click", () => {
    emit("eventview:mission_list", evTargetToken() || "all");
  });
  $("ev-watch").addEventListener("click", () => emit("eventview:watch", true));
  $("ev-clear").addEventListener("click", () => {
    evRows.length = 0;
    const body = $("ev-log");
    while (body.firstChild) body.removeChild(body.firstChild);
    const tr = document.createElement("tr");
    tr.innerHTML = '<td colspan="5" class="empty">No EventView activity yet.</td>';
    body.appendChild(tr);
  });
  $("ev-mission-set").addEventListener("click", () => {
    const token = evTargetToken();
    const mid = ($("ev-mission-id").value || "").trim();
    if (!token || !mid) { setText("tool-result", "Need target + mission id."); return; }
    // Drive through schedule with a single mission step so targeting stays consistent.
    emit("eventview:schedule", {
      target: token,
      loops: 1,
      label: "mission:" + mid,
      steps: [{
        at: 0,
        kind: "mission",
        missionId: mid,
        entry: {
          title: ($("ev-mission-title").value || mid).trim(),
          status: ($("ev-mission-status").value || "active").trim(),
        },
      }],
    });
    setText("tool-result", "Mission set scheduled for " + token);
  });
  $("ev-mission-clear").addEventListener("click", () => {
    const token = evTargetToken();
    const mid = ($("ev-mission-id").value || "").trim() || null;
    if (!token) { setText("tool-result", "Need target."); return; }
    emit("eventview:schedule", {
      target: token,
      loops: 1,
      label: "mission_clear",
      steps: [{ at: 0, kind: "mission_clear", missionId: mid }],
    });
    setText("tool-result", "Mission clear scheduled for " + token);
  });

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
      fillHudPlayers(players);
      emit("hud:watch", true);
      renderQuickTools();
      renderRuntime("services", payload.services, "services");
      renderRuntime("event-handlers", payload.eventHandlers, "events");
    });
    Open77.on("hud:log", (payload) => {
      if (!payload) return;
      if (Array.isArray(payload.entries)) payload.entries.forEach(addHudRow); else addHudRow(payload.entry);
    });
    Open77.on("eventview:log", (payload) => {
      if (!payload) return;
      if (Array.isArray(payload.entries)) payload.entries.forEach(addEvRow); else addEvRow(payload.entry);
    });
    Open77.on("eventview:result", (payload) => {
      if (payload) setText("tool-result", payload.ok ? ("Scheduled " + (payload.schedule || "")) : ("EventView failed: " + (payload.reason || "")));
    });
    Open77.on("eventview:missions", (payload) => {
      if (!payload || !payload.missions) return;
      $("tool-output").textContent = JSON.stringify(payload.missions, null, 2);
      setText("tool-output-title", "EventView missions");
      setText("tool-output-channel", "eventview");
    });
    emit("eventview:watch", true);
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
