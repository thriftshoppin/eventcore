-- EventCore native HUD test bench (server side).
--
-- EventCore shows only the game's own HUD. This module lets a global admin, from the in-game
-- admin panel, send a native HUD call to any player (usually themselves), and watch the result
-- come back in a live event viewer. A server console or in-game command does the same thing, so
-- you can be the client and drive the server from one session.
--
--   admin panel (web)  ->  eventcore:hud:send   ->  server validates admin + registry name
--   server             ->  eventcore:hud:run    ->  target client calls the native HUD
--   target client      ->  eventcore:hud:result ->  server logs it and pushes it to watchers
--
-- Nothing here is gameplay authority: it changes only what the target client draws.

EventCore = EventCore or {}
EventCore.HudBench = EventCore.HudBench or {}
local Bench = EventCore.HudBench

local LOG_MAX = 300
local PENDING_MAX_PER_ADMIN = 16
local TIMEOUT_MS = 5000
local SEND_INTERVAL_MS = 120
local ACTIONS = { show = true, hide = true, status = true, introspect = true, restore = true }
local GROUPS = { hud = true, verified = true }

local log, seq = {}, 0
local pending = {}   -- [requestId] = { admin, player, entry, startedAt }
local pendingCount = {}
local watchers = {}  -- [adminId] = true
local lastSendAt = {}
local requestSeq = 0

local function playerId(value)
    value = tonumber(value)
    if not value or value < 1 or value % 1 ~= 0 then return nil end
    return value
end

local function clip(value, limit)
    value = tostring(value == nil and "" or value)
    if #value > limit then value = value:sub(1, limit) end
    return (value:gsub("[%c]", " "))
end

local function nowMs()
    return GetGameTimer and GetGameTimer() or 0
end

local function nameOf(id)
    if id == 0 then return "console" end
    local ok, name = pcall(Open77.players.name, id)
    return clip(ok and name or ("Player " .. tostring(id)), 48)
end

local function isAdmin(id)
    local allowed = EventCore.Access and EventCore.Access.IsLocalAdmin(id)
    return allowed == true
end

local function push(entry)
    for adminId in pairs(watchers) do
        if isAdmin(adminId) then EventCore.EmitClient("hud:log", adminId, { entry = entry }) else watchers[adminId] = nil end
    end
end

local function record(entry)
    seq = seq + 1
    entry.seq = seq
    entry.at = os.time()
    log[#log + 1] = entry
    if #log > LOG_MAX then table.remove(log, 1) end
    push(entry)
    return entry
end

--- Validate a spec from any source. Returns a clean copy or nil, reason.
local function cleanSpec(spec)
    if type(spec) ~= "table" then return nil, "invalid_spec" end
    local action = spec.action
    if type(action) ~= "string" or not ACTIONS[action] then return nil, "unknown_action" end
    local clean = { action = action }
    if spec.group ~= nil then
        if type(spec.group) ~= "string" or not GROUPS[spec.group] then return nil, "unknown_group" end
        clean.group = spec.group
    elseif action ~= "introspect" and action ~= "restore" then
        if type(spec.target) ~= "string" or #spec.target > 96 then return nil, "invalid_target" end
        if not (EventCore.NativeRegistry and EventCore.NativeRegistry.Find(spec.target)) then
            return nil, "unknown_target"
        end
        clean.target = spec.target
    end
    return clean
end

--- Send a validated native HUD call to `player`. `admin` is the requester (0 = console).
function Bench.Run(admin, player, spec, origin)
    player = playerId(player)
    if not player or Open77.players.name(player) == nil then return nil, "player_not_online" end
    local clean, reason = cleanSpec(spec)
    if not clean then return nil, reason end
    pendingCount[admin] = pendingCount[admin] or 0
    if pendingCount[admin] >= PENDING_MAX_PER_ADMIN then return nil, "too_many_pending" end
    requestSeq = requestSeq + 1
    local requestId = ("hud%d"):format(requestSeq)
    pending[requestId] = { admin = admin, player = player, startedAt = nowMs(), spec = clean, origin = origin }
    pendingCount[admin] = pendingCount[admin] + 1
    EventCore.EmitClient("hud:run", player, { requestId = requestId, spec = clean })
    return requestId
end


-- ── schedules ───────────────────────────────────────────────────────────────
-- A schedule is a short list of { at = ms, action, target|group } steps. The server validates it
-- and sends it to the client once; the client plays it on its own timers (no server thread, no
-- network jitter) and reports each step back as an ordinary result, so every step shows up in the
-- viewer. Steps are pre-registered as pending so a client that never answers shows as a timeout.
local MAX_STEPS, MAX_LOOPS, MAX_AT_MS, MAX_SCHEDULES = 32, 10, 300000, 2
local schedules, scheduleSeq = {}, 0

function Bench.Schedule(admin, player, steps, loops, origin)
    player = playerId(player)
    if not player or Open77.players.name(player) == nil then return nil, "player_not_online" end
    if type(steps) ~= "table" or #steps < 1 or #steps > MAX_STEPS then return nil, "steps_1_to_" .. MAX_STEPS end
    loops = math.floor(tonumber(loops) or 1)
    if loops < 1 or loops > MAX_LOOPS then return nil, "loops_1_to_" .. MAX_LOOPS end
    local clean, last = {}, 0
    for index, step in ipairs(steps) do
        local spec, reason = cleanSpec(type(step) == "table" and step or nil)
        local at = type(step) == "table" and tonumber(step.at)
        if not spec then return nil, ("step %d: %s"):format(index, reason) end
        if not at or at ~= at or at < 0 or at > MAX_AT_MS then return nil, ("step %d: at_0_to_%d"):format(index, MAX_AT_MS) end
        spec.at = math.floor(at)
        if spec.at < last then return nil, ("step %d: steps must be in time order"):format(index) end
        last = spec.at
        clean[index] = spec
    end
    local active = 0
    for _, item in pairs(schedules) do if item.admin == admin then active = active + 1 end end
    if active >= MAX_SCHEDULES then return nil, "too_many_schedules" end
    scheduleSeq = scheduleSeq + 1
    local id = "s" .. scheduleSeq
    local period = last + 250
    local now = nowMs()
    schedules[id] = { admin = admin, player = player, endsAt = now + period * loops + TIMEOUT_MS }
    for loop = 1, loops do
        for index, spec in ipairs(clean) do
            pending[("%s:%d:%d"):format(id, loop, index)] = { admin = admin, player = player, spec = spec,
                startedAt = now + (loop - 1) * period + spec.at, origin = origin or "schedule", schedule = id }
        end
    end
    EventCore.EmitClient("hud:schedule", player, { id = id, steps = clean, loops = loops, period = period })
    record({ admin = admin, adminName = nameOf(admin), player = player, playerName = nameOf(player),
        target = id, action = "schedule", ok = true, origin = origin or "schedule",
        detail = ("%d step(s) x %d loop(s), %d ms per loop"):format(#clean, loops, period) })
    return id
end

--- Stop one schedule or (id == nil) every schedule of this admin. Returns how many were stopped.
function Bench.Cancel(admin, id)
    local stopped = 0
    for sid, item in pairs(schedules) do
        if (id == nil or id == sid) and (item.admin == admin or admin == 0) then
            schedules[sid] = nil
            stopped = stopped + 1
            for requestId, entry in pairs(pending) do if entry.schedule == sid then pending[requestId] = nil end end
            EventCore.EmitClient("hud:cancel", item.player, { id = sid })
            record({ admin = admin, adminName = nameOf(admin), player = item.player, playerName = nameOf(item.player),
                target = sid, action = "cancel", ok = true, detail = "schedule stopped", origin = "schedule" })
        end
    end
    return stopped
end

-- Pending calls whose client never answered become "timeout" log entries. Checked lazily on the
-- next send/log request, so there is no polling thread.
local function expire()
    local now = nowMs()
    for sid, item in pairs(schedules) do if now > item.endsAt then schedules[sid] = nil end end
    for requestId, item in pairs(pending) do
        if now - item.startedAt > TIMEOUT_MS then
            pending[requestId] = nil
            if not item.schedule then pendingCount[item.admin] = math.max(0, (pendingCount[item.admin] or 1) - 1) end
            record({ admin = item.admin, adminName = nameOf(item.admin), player = item.player,
                playerName = nameOf(item.player), target = item.spec.target or item.spec.group or "-",
                action = item.spec.action, ok = false, detail = "timeout: client did not answer", origin = item.origin })
        end
    end
end

local function cleanResult(result)
    if type(result) ~= "table" then return nil end
    local out = { ok = result.ok == true, detail = clip(result.detail, 300) }
    local ms = tonumber(result.ms)
    if ms and ms == ms and ms >= 0 and ms < 1e6 then out.ms = ms end
    for _, key in ipairs({ "accepted", "refused" }) do
        local count = tonumber(result[key])
        if count and count >= 0 and count < 1e5 then out[key] = count end
    end
    return out
end

RegisterNetEvent("eventcore:hud:result", function(requestId, result)
    local id = playerId(source)
    local item = type(requestId) == "string" and pending[requestId]
    if not id or not item or item.player ~= id then return end
    local clean = cleanResult(result)
    if not clean then return end
    pending[requestId] = nil
    if not item.schedule then pendingCount[item.admin] = math.max(0, (pendingCount[item.admin] or 1) - 1) end
    record({ admin = item.admin, adminName = nameOf(item.admin), player = id, playerName = nameOf(id),
        target = item.spec.target or item.spec.group or "-", action = item.spec.action, ok = clean.ok,
        detail = clean.detail, ms = clean.ms, accepted = clean.accepted, refused = clean.refused,
        origin = item.origin })
end)

local function requireAdmin(id)
    if not isAdmin(id) then
        EventCore.EmitClient("admin:denied", id, { reason = "global_admin_required" })
        return false
    end
    return true
end

-- Web UI -> server. `player` defaults to the sender, so one admin can be both ends.
RegisterNetEvent("eventcore:hud:send", function(player, spec)
    local id = playerId(source)
    if not id or not requireAdmin(id) then return end
    local now = nowMs()
    if lastSendAt[id] and now - lastSendAt[id] < SEND_INTERVAL_MS then return end
    lastSendAt[id] = now
    expire()
    local requestId, reason = Bench.Run(id, playerId(player) or id, spec, "web")
    if not requestId then
        record({ admin = id, adminName = nameOf(id), player = playerId(player) or id, playerName = "-",
            target = type(spec) == "table" and clip(spec.target or spec.group or "-", 96) or "-",
            action = type(spec) == "table" and clip(spec.action, 16) or "-", ok = false,
            detail = "rejected: " .. tostring(reason), origin = "web" })
    end
end)

RegisterNetEvent("eventcore:hud:schedule", function(player, steps, loops)
    local id = playerId(source)
    if not id or not requireAdmin(id) then return end
    local now = nowMs()
    if lastSendAt[id] and now - lastSendAt[id] < SEND_INTERVAL_MS then return end
    lastSendAt[id] = now
    expire()
    local sid, reason = Bench.Schedule(id, playerId(player) or id, steps, loops, "web")
    if not sid then
        record({ admin = id, adminName = nameOf(id), player = playerId(player) or id, playerName = "-",
            target = "-", action = "schedule", ok = false, detail = "rejected: " .. tostring(reason), origin = "web" })
    end
end)

RegisterNetEvent("eventcore:hud:cancel", function()
    local id = playerId(source)
    if not id or not requireAdmin(id) then return end
    Bench.Cancel(id, nil)
end)

-- /eventcore.hud.schedule <player> <loops> <at,action,target> ...
--   e.g. /eventcore.hud.schedule 1 3 0,hide,inkHUDLayer 2000,show,inkHUDLayer
RegisterCommand("eventcore.hud.schedule", function(src, args, raw)
    src = tonumber(src) or 0
    local reply = function(ok, message)
        if src <= 0 then print("[EventCore][hud] " .. message) else
            TriggerClientEvent("open77:command:result", src, raw or "", ok, message) end
    end
    if src > 0 and not isAdmin(src) then return reply(false, "EventCore admin access denied.") end
    expire()
    local steps = {}
    for index = 3, #(args or {}) do
        local at, action, what = tostring(args[index]):match("^(%d+),(%a+),([%w_]+)$")
        if not at then return reply(false, "Step '" .. tostring(args[index]) .. "' must look like 2000,hide,inkHUDLayer") end
        local step = { at = tonumber(at), action = action }
        if GROUPS[what] then step.group = what else step.target = what end
        steps[#steps + 1] = step
    end
    local sid, reason = Bench.Schedule(src, args and args[1], steps, args and args[2], "command")
    if not sid then return reply(false, "Usage: /eventcore.hud.schedule <player> <loops> <at,action,target>... (" .. tostring(reason) .. ")") end
    reply(true, "Schedule " .. sid .. " sent; watch the admin HUD viewer.")
end, true)

RegisterCommand("eventcore.hud.cancel", function(src)
    src = tonumber(src) or 0
    if src > 0 and not isAdmin(src) then return end
    Bench.Cancel(src, nil)
end, true)

-- Web UI opens or closes the event viewer; opening replays the retained log.
RegisterNetEvent("eventcore:hud:watch", function(on)
    local id = playerId(source)
    if not id or not requireAdmin(id) then return end
    expire()
    if on == false then watchers[id] = nil return end
    if watchers[id] then return end
    watchers[id] = true
    local first = math.max(1, #log - 99)
    EventCore.EmitClient("hud:log", id, { entries = { table.unpack(log, first, #log) } })
end)

AddEventHandler("playerDropped", function()
    local id = tonumber(source)
    if id then watchers[id], lastSendAt[id] = nil, nil end
end)

-- /eventcore.hud.test <player> <target|group> <action>   e.g.  /eventcore.hud.test 1 inkHUDLayer hide
RegisterCommand("eventcore.hud.test", function(src, args, raw)
    src = tonumber(src) or 0
    local reply = function(ok, message)
        if src <= 0 then print("[EventCore][hud] " .. message) else
            TriggerClientEvent("open77:command:result", src, raw or "", ok, message) end
    end
    if src > 0 and not isAdmin(src) then return reply(false, "EventCore admin access denied.") end
    expire()
    local spec = { action = args and args[3] }
    local what = args and args[2]
    if GROUPS[what or ""] then spec.group = what else spec.target = what end
    local requestId, reason = Bench.Run(src, args and args[1], spec, "command")
    if not requestId then return reply(false, "Usage: /eventcore.hud.test <player> <target|hud|verified> <show|hide|status|introspect|restore> (" .. tostring(reason) .. ")") end
    reply(true, "HUD test sent as " .. requestId .. "; result appears in the admin HUD viewer.")
end, true)

RegisterCommand("eventcore.hud.log", function(src, args, raw)
    src = tonumber(src) or 0
    if src > 0 and not isAdmin(src) then return end
    expire()
    local count = math.min(tonumber(args and args[1]) or 10, 30)
    for index = math.max(1, #log - count + 1), #log do
        local e = log[index]
        local line = ("#%d %s -> %s %s %s: %s"):format(e.seq, e.adminName, e.playerName, e.action, e.target, e.detail)
        if src <= 0 then print("[EventCore][hud] " .. line) else
            TriggerClientEvent("open77:command:result", src, raw or "", e.ok, line) end
    end
end, true)

function Bench.GetLog() return log end
