-- EventCore -> RPCore HUD controller.
--
-- RPCore draws the HUD and simulates nothing: a bar has no value until something pushes one,
-- and RPCore only accepts HUD writes from the resources in its Config.exports.allowedCallers
-- (EventCore by default). This module is that caller. Other server resources (needs, jobs,
-- missions, admin tools) go through the EventCore Hud* exports below instead of calling RPCore
-- directly, so there is one place that holds the desired HUD state.
--
-- Design rules (same as the rest of EventCore):
--   * Exports never yield. They validate, record the desired state and queue the RPCore call;
--     one worker thread performs the awaited cross-resource calls.
--   * RPCore keeps vitals and element overrides in memory only. This module remembers the
--     last non-expiring values per player and replays them when a player joins and whenever
--     RPCore restarts, so a resource restart never leaves players with blank bars.
--   * Timed effects (ForceTier, hidden bars, level overrides) are NOT replayed: they expire.
--
-- Config: EventCore.HudConfig / EventCore.HudCallers in server/whitelist.lua.

EventCore = EventCore or {}
EventCore.Hud = EventCore.Hud or {}
local Hud = EventCore.Hud

local config = type(EventCore.HudConfig) == "table" and EventCore.HudConfig or {}
local RPCORE = "rpcore"
local SOURCE = "eventcore"
local QUEUE_MAX = 512
local SYNC_MS = math.max(500, tonumber(config.syncIntervalMs) or 2000)
local DEFAULT_TTL = math.max(1, tonumber(config.defaultOverrideSeconds) or 60)
local VITALS = { hunger = true, thirst = true, psychosis = true }
local ALIAS = { sanity = "psychosis" }

local players = {}   -- [id] = { seeded, vitals = { [name] = { value, max } }, elements = { [id] = patch } }
local queue = {}
local lastLog = {}
local link = { up = nil, generation = nil, lastError = nil }

local function log(key, message)
    if lastLog[key] == message then return end
    lastLog[key] = message
    print("[EventCore][hud] " .. message)
end

local function playerId(value)
    local id = tonumber(value)
    if not id or id < 1 or id % 1 ~= 0 then return nil end
    return id
end

local function finite(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function stateFor(id)
    local s = players[id]
    if not s then s = { seeded = false, vitals = {}, elements = {} }; players[id] = s end
    return s
end

local function enqueue(method, ...)
    if #queue >= QUEUE_MAX then
        table.remove(queue, 1)
        log("overflow", "RPCore call queue is full; dropping the oldest HUD update")
    end
    queue[#queue + 1] = { method = method, args = { ... }, n = select("#", ...) }
end

--- Awaited call into RPCore. Only from the worker thread (it yields).
local function callRpcore(method, ...)
    if not (Open77 and Open77.exports and type(Open77.exports.call) == "function") then
        return nil, "exports_api_unavailable"
    end
    local args, n = { ... }, select("#", ...)
    local dispatched, pending, dispatchError = pcall(function()
        return Open77.exports.call(RPCORE, method, table.unpack(args, 1, n))
    end)
    if not dispatched then return nil, tostring(pending) end
    if not pending then return nil, tostring(dispatchError or "rpcore_call_refused") end
    local awaited, first, second = pcall(function() return pending:await() end)
    if not awaited then return nil, tostring(first) end
    return first, second
end

-- ── desired-state API (never yields) ────────────────────────────────────────

--- Provider baseline for hunger / thirst / psychosis. Replayed after joins and RPCore restarts.
function Hud.SetVital(rawId, vital, value, max)
    local id = playerId(rawId)
    if not id then return nil, "invalid_player_id" end
    vital = ALIAS[vital] or vital
    if not VITALS[vital] then return nil, "unknown_vital" end
    local v = finite(value)
    if not v then return nil, "invalid_value" end
    local m = nil
    if max ~= nil then
        m = finite(max)
        if not m or m <= 0 then return nil, "invalid_max" end
    end
    stateFor(id).vitals[vital] = { value = v, max = m }
    if m then enqueue("SetVital", id, vital, v, m) else enqueue("SetVital", id, vital, v) end
    return true
end

--- opts == nil: same as SetVital(id, "psychosis", value). With opts ({ ttl, source, max } or a
--- ttl in seconds) it is a timed level override: forwarded, not remembered.
function Hud.SetPsychosis(rawId, value, opts)
    if opts == nil then return Hud.SetVital(rawId, "psychosis", value) end
    local id = playerId(rawId)
    if not id then return nil, "invalid_player_id" end
    local v = finite(value)
    if not v then return nil, "invalid_value" end
    if type(opts) ~= "number" and type(opts) ~= "table" then return nil, "invalid_options" end
    if type(opts) == "table" then
        local copy = {}
        for key, item in pairs(opts) do
            if type(key) ~= "string" or (type(item) ~= "number" and type(item) ~= "string" and type(item) ~= "boolean") then
                return nil, "invalid_options"
            end
            copy[key] = item
        end
        if copy.source == nil then copy.source = SOURCE end
        opts = copy
    end
    enqueue("SetPsychosis", id, v, opts)
    return true
end

--- Pin the cyberpsychosis tier for `ttl` seconds (stable|strained|fraying|breach|psychosis).
function Hud.ForceTier(rawId, tier, ttl, source)
    local id = playerId(rawId)
    if not id then return nil, "invalid_player_id" end
    if type(tier) ~= "string" or tier == "" then return nil, "unknown_tier" end
    local seconds = ttl ~= nil and finite(ttl) or DEFAULT_TTL
    if not seconds or seconds <= 0 then return nil, "invalid_ttl" end
    enqueue("ForceTier", id, tier, seconds, type(source) == "string" and source or SOURCE)
    return true
end

function Hud.ReleaseTier(rawId, which)
    local id = playerId(rawId)
    if not id then return nil, "invalid_player_id" end
    if which ~= nil and type(which) ~= "string" then return nil, "invalid_release" end
    enqueue("ReleaseTier", id, which or "all")
    return true
end

--- visible=false force-hides a bar for `ttl` seconds; visible=true releases the force-hide.
function Hud.SetBarVisible(rawId, bar, visible, ttl, source)
    local id = playerId(rawId)
    if not id then return nil, "invalid_player_id" end
    if type(bar) ~= "string" then return nil, "unknown_bar" end
    if type(visible) ~= "boolean" then return nil, "invalid_visible" end
    if visible then
        enqueue("SetBarVisible", id, bar, true)
    else
        local seconds = ttl ~= nil and finite(ttl) or DEFAULT_TTL
        if not seconds or seconds <= 0 then return nil, "invalid_ttl" end
        enqueue("SetBarVisible", id, bar, false, seconds, type(source) == "string" and source or SOURCE)
    end
    return true
end

--- Show/hide/fade/move an RPCore HUD element: patch = { visible, opacity, placement }.
--- Remembered and replayed (RPCore keeps overrides in memory only).
function Hud.SetElement(rawId, elementId, patch)
    local id = playerId(rawId)
    if not id then return nil, "invalid_player_id" end
    if type(elementId) ~= "string" or elementId == "" then return nil, "unknown_element" end
    if type(patch) ~= "table" then return nil, "invalid_patch" end
    local s = stateFor(id)
    local merged = s.elements[elementId] or {}
    for key, value in pairs(patch) do merged[key] = value end
    s.elements[elementId] = merged
    enqueue("SetHudElement", id, elementId, patch)
    return true
end

function Hud.ResetElement(rawId, elementId)
    local id = playerId(rawId)
    if not id then return nil, "invalid_player_id" end
    if type(elementId) ~= "string" then return nil, "unknown_element" end
    stateFor(id).elements[elementId] = nil
    enqueue("ResetHudElement", id, elementId)
    return true
end

function Hud.ResetElements(rawId)
    local id = playerId(rawId)
    if not id then return nil, "invalid_player_id" end
    stateFor(id).elements = {}
    enqueue("ResetHudElements", id)
    return true
end

--- Re-send everything remembered for one player (join, RPCore restart).
function Hud.Replay(rawId)
    local id = playerId(rawId)
    local s = id and players[id] or nil
    if not s then return false end
    for name, item in pairs(s.vitals) do
        if item.max then enqueue("SetVital", id, name, item.value, item.max)
        else enqueue("SetVital", id, name, item.value) end
    end
    for elementId, patch in pairs(s.elements) do enqueue("SetHudElement", id, elementId, patch) end
    return true
end

--- Plain-data diagnostics (also returned by the HudGetStatus export).
function Hud.Status()
    local tracked = 0
    for _ in pairs(players) do tracked = tracked + 1 end
    return {
        rpcoreUp = link.up == true, rpcoreGeneration = link.generation, lastError = link.lastError,
        queued = #queue, trackedPlayers = tracked,
        seedDefaults = config.seedDefaults ~= false,
    }
end

-- ── worker: queue, join seeding, RPCore restart detection ───────────────────

local function onlineIds()
    if type(GetPlayers) ~= "function" then return nil end
    local ok, list = pcall(GetPlayers)
    if not ok or type(list) ~= "table" then return nil end
    local ids = {}
    for _, value in ipairs(list) do
        local id = playerId(value)
        if id then ids[#ids + 1] = id end
    end
    return ids
end

local function rpcoreGeneration()
    if Open77 and Open77.resource and type(Open77.resource.generation) == "function" then
        local ok, generation = pcall(Open77.resource.generation, RPCORE)
        if ok and type(generation) == "number" then return generation end
    end
    return nil
end

local function seedDefaults(s)
    if s.seeded then return end
    s.seeded = true
    -- Element overrides every joining player starts with (EventCore.HudConfig.defaultElements).
    for elementId, patch in pairs(type(config.defaultElements) == "table" and config.defaultElements or {}) do
        if type(elementId) == "string" and type(patch) == "table" and s.elements[elementId] == nil then
            s.elements[elementId] = patch
        end
    end
    if config.seedDefaults == false then return end
    -- Baseline so the bars exist before a real provider reports. Any value a provider already
    -- set is kept. Turn off with EventCore.HudConfig.seedDefaults = false.
    for name, value in pairs(type(config.defaults) == "table" and config.defaults or {}) do
        local v = finite(value)
        if VITALS[name] and v and not s.vitals[name] then s.vitals[name] = { value = v } end
    end
end

local function syncTick()
    local pong, why = callRpcore("GetApiVersion")
    local up = pong ~= nil
    link.lastError = (not up) and tostring(why or "rpcore_unreachable") or nil
    local generation = rpcoreGeneration()
    local replayAll = up and (link.up ~= true or generation ~= link.generation)
    link.up, link.generation = up, generation
    if not up then log("down", "RPCore is not answering (" .. tostring(link.lastError) .. "); HUD updates will resume when it starts.")
    else lastLog.down = nil end

    local ids = onlineIds()
    if not ids then return end
    local online = {}
    for _, id in ipairs(ids) do
        online[id] = true
        local fresh = players[id] == nil or not players[id].seeded
        local s = stateFor(id)
        seedDefaults(s)
        if up and (fresh or replayAll) then Hud.Replay(id) end
    end
    for id in pairs(players) do
        if not online[id] then players[id] = nil end
    end
end

CreateThread(function()
    local nextSync = 0
    while true do
        local job = table.remove(queue, 1)
        if job then
            local ok, reason = callRpcore(job.method, table.unpack(job.args, 1, job.n))
            if ok ~= true then
                log("fail:" .. job.method, ("RPCore %s failed: %s"):format(job.method, tostring(reason or ok)))
            end
            Wait(10)
        else
            Wait(100)
        end
        local now = GetGameTimer and GetGameTimer() or 0
        if now >= nextSync then
            nextSync = now + SYNC_MS
            local ok, err = pcall(syncTick)
            if not ok then log("sync", "sync failed: " .. tostring(err)) end
        end
    end
end)

AddEventHandler("playerDropped", function()
    local id = playerId(source)
    if id then players[id] = nil end
end)

-- ── exports for other server resources ──────────────────────────────────────

local function allowedCaller()
    local caller = GetInvokingResource and GetInvokingResource() or nil
    if type(caller) ~= "string" then return nil, "hud_caller_unknown" end
    local persistence = EventCore.Persistence
    if (persistence and persistence.IsTrustedCaller(caller))
        or (type(EventCore.HudCallers) == "table" and EventCore.HudCallers[caller] == true) then
        return caller
    end
    return nil, "hud_caller_not_trusted:" .. caller
end

local function guarded(fn)
    return function(...)
        local caller, why = allowedCaller()
        if not caller then return nil, why end
        return fn(...)
    end
end

exports("HudSetVital", guarded(Hud.SetVital))
exports("HudSetPsychosis", guarded(Hud.SetPsychosis))
exports("HudForceTier", guarded(Hud.ForceTier))
exports("HudReleaseTier", guarded(Hud.ReleaseTier))
exports("HudSetBarVisible", guarded(Hud.SetBarVisible))
exports("HudSetElement", guarded(Hud.SetElement))
exports("HudResetElement", guarded(Hud.ResetElement))
exports("HudResetElements", guarded(Hud.ResetElements))
exports("HudGetStatus", Hud.Status)

-- ── admin test commands ─────────────────────────────────────────────────────
-- Global admin (Open77 admin/owner role) or the server console. Same gate as /eventcore.admin.

local function reply(source, raw, accepted, message)
    source = tonumber(source) or 0
    if source <= 0 then
        print("[EventCore][hud] " .. tostring(message))
        return
    end
    TriggerClientEvent("open77:command:result", source, raw or "", accepted == true, tostring(message))
end

local function adminOnly(handler)
    return function(source, args, raw)
        source = tonumber(source) or 0
        if source > 0 then
            local allowed, reason = EventCore.Access.IsLocalAdmin(source)
            if allowed ~= true then
                return reply(source, raw, false, "EventCore HUD access denied: " .. tostring(reason or "global_admin_required"))
            end
        end
        handler(source, type(args) == "table" and args or {}, raw)
    end
end

--- Target = explicit player id argument, else the caller. Console must name one.
local function target(source, arg)
    if arg ~= nil then
        local id = playerId(arg)
        if not id then return nil, "invalid player id" end
        if Open77 and Open77.players and type(Open77.players.name) == "function" then
            local ok, name = pcall(Open77.players.name, id)
            if not ok or name == nil then return nil, "player " .. id .. " is not online" end
        end
        return id
    end
    if source > 0 then return source end
    return nil, "name a player id when running from the console"
end

local function result(source, raw, ok, reason, okMessage)
    if ok then reply(source, raw, true, okMessage) else reply(source, raw, false, "Refused: " .. tostring(reason)) end
end

RegisterCommand("eventcore.hud.vital", adminOnly(function(source, args, raw)
    local id, why = target(source, args[3])
    if not id then return reply(source, raw, false, "Usage: /eventcore.hud.vital <hunger|thirst|psychosis> <value> [player] (" .. tostring(why) .. ")") end
    local ok, reason = Hud.SetVital(id, tostring(args[1] or ""):lower(), args[2])
    result(source, raw, ok, reason, ("Queued %s = %s for player %d."):format(tostring(args[1]), tostring(args[2]), id))
end), true)

RegisterCommand("eventcore.hud.bar", adminOnly(function(source, args, raw)
    local id, why = target(source, args[4])
    local state = tostring(args[2] or ""):lower()
    if not id or (state ~= "on" and state ~= "off") then
        return reply(source, raw, false, "Usage: /eventcore.hud.bar <hunger|thirst|psychosis> <on|off> [seconds] [player] " .. (why and ("(" .. why .. ")") or ""))
    end
    local ok, reason = Hud.SetBarVisible(id, tostring(args[1] or ""):lower(), state == "on", args[3])
    result(source, raw, ok, reason, ("Queued %s bar %s for player %d."):format(tostring(args[1]), state, id))
end), true)

RegisterCommand("eventcore.hud.tier", adminOnly(function(source, args, raw)
    local id, why = target(source, args[3])
    if not id or not args[1] then
        return reply(source, raw, false, "Usage: /eventcore.hud.tier <stable|strained|fraying|breach|psychosis|release> [seconds] [player] " .. (why and ("(" .. why .. ")") or ""))
    end
    local name = tostring(args[1]):lower()
    local ok, reason
    if name == "release" then ok, reason = Hud.ReleaseTier(id) else ok, reason = Hud.ForceTier(id, name, args[2]) end
    result(source, raw, ok, reason, ("Queued tier %s for player %d."):format(name, id))
end), true)

RegisterCommand("eventcore.hud.element", adminOnly(function(source, args, raw)
    local id, why = target(source, args[3])
    local state = tostring(args[2] or ""):lower()
    if not id or not args[1] or (state ~= "show" and state ~= "hide") then
        return reply(source, raw, false, "Usage: /eventcore.hud.element <element id, e.g. vanilla.minimap> <show|hide> [player] " .. (why and ("(" .. why .. ")") or ""))
    end
    local ok, reason = Hud.SetElement(id, tostring(args[1]), { visible = state == "show" })
    result(source, raw, ok, reason, ("Queued %s %s for player %d."):format(tostring(args[1]), state, id))
end), true)

RegisterCommand("eventcore.hud.reset", adminOnly(function(source, args, raw)
    local id, why = target(source, args[1])
    if not id then return reply(source, raw, false, "Usage: /eventcore.hud.reset [player] (" .. tostring(why) .. ")") end
    Hud.ResetElements(id)
    Hud.ReleaseTier(id)
    reply(source, raw, true, ("Queued HUD reset for player %d (element overrides and tier override)."):format(id))
end), true)

RegisterCommand("eventcore.hud.status", adminOnly(function(source, args, raw)
    local id, why = target(source, args[1])
    if not id then return reply(source, raw, false, "Usage: /eventcore.hud.status [player] (" .. tostring(why) .. ")") end
    CreateThread(function()
        local status = Hud.Status()
        reply(source, raw, true, ("EventCore HUD -> RPCore: %s%s | generation %s | %d queued | %d player(s) tracked | seed defaults %s")
            :format(status.rpcoreUp and "linked" or "NOT linked",
                status.lastError and (" (" .. status.lastError .. ")") or "", tostring(status.rpcoreGeneration),
                status.queued, status.trackedPlayers, status.seedDefaults and "on" or "off"))
        local s = players[id]
        if s then
            for name in pairs(VITALS) do
                local item = s.vitals[name]
                reply(source, raw, true, ("  remembered %s = %s"):format(name, item and tostring(item.value) or "none"))
            end
        end
        local vitals, reason = callRpcore("GetVitals", id)
        if type(vitals) ~= "table" then
            return reply(source, raw, false, "  RPCore GetVitals failed: " .. tostring(reason))
        end
        local h, t, p = vitals.hunger or {}, vitals.thirst or {}, vitals.psychosis or {}
        reply(source, raw, true, ("  RPCore sees hunger %s (data=%s), thirst %s (data=%s), psychosis %s tier %s (data=%s)")
            :format(tostring(h.value), tostring(h.hasData), tostring(t.value), tostring(t.hasData),
                tostring(p.value), tostring(p.tierId), tostring(p.hasData)))
    end)
end), true)
