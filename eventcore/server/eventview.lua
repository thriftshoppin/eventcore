-- EventCore EventView (server).
--
-- Admin-gated operational panel for:
--   * LTE schedules that drive widgets / native HUD calls across targets
--   * Per-player mission / quest entries written by trusted mods
--
-- Targeting: player:<id> | nearest | group:<role> | all
-- Commands: /eventcore.eventview.*  (see bottom)
-- Exports: EventViewMissionSet, EventViewMissionClear, EventViewMissionList,
--          EventViewSchedule, EventViewCancel, EventViewTargets

EventCore = EventCore or {}
EventCore.EventView = EventCore.EventView or {}
local EV = EventCore.EventView
local Cfg = EventCore.EventViewConfig or {}

local MAX_SCHEDULES = Cfg.maxSchedules or 16
local MAX_STEPS = Cfg.maxSteps or 48
local MAX_LOOPS = Cfg.maxLoops or 20
local MAX_MISSIONS = Cfg.maxMissionsPerPlayer or 32
local LOG_SIZE = Cfg.logSize or 400
local OPERATOR_ROLE = Cfg.operatorRole -- e.g. "eventview"

local log = {}
local schedules = {}
local scheduleSeq = 0
local missions = {} -- [playerId] = { [missionId] = entry }
local watchers = {} -- [adminId] = true

local function nowMs()
    if Open77 and Open77.time and type(Open77.time.monotonic) == "function" then
        local ok, t = pcall(Open77.time.monotonic)
        if ok and type(t) == "number" then return math.floor(t * 1000) end
    end
    return math.floor((os.clock() or 0) * 1000)
end

local function playerId(value)
    local id = tonumber(value)
    if not id or id < 1 or id % 1 ~= 0 then return nil end
    return id
end

local function nameOf(id)
    if not id or id <= 0 then return "console" end
    local ok, name = pcall(function() return Open77.players.name(id) end)
    if ok and name then return tostring(name) end
    return ("Player %d"):format(id)
end

local function onlineIds()
    if type(GetPlayers) ~= "function" then return {} end
    local ok, list = pcall(GetPlayers)
    if not ok or type(list) ~= "table" then return {} end
    local out = {}
    for _, raw in ipairs(list) do
        local id = playerId(raw)
        if id and Open77 and Open77.players and Open77.players.name(id) ~= nil then
            out[#out + 1] = id
        end
    end
    return out
end

local function hasRole(id, role)
    if not (EventCore.Access and EventCore.Access.GetLocalPlayerRoles) then return false end
    local roles = EventCore.Access.GetLocalPlayerRoles(id)
    if type(roles) ~= "table" then return false end
    for _, r in ipairs(roles) do
        if r == role then return true end
    end
    return false
end

--- Global admin OR optional EventView operator role.
local function canOperate(id)
    if id == 0 then return true end -- console
    if EventCore.Access and EventCore.Access.IsLocalAdmin(id) == true then return true end
    if type(OPERATOR_ROLE) == "string" and OPERATOR_ROLE ~= "" and hasRole(id, OPERATOR_ROLE) then
        return true
    end
    return false
end

local function record(entry)
    entry.at = entry.at or nowMs()
    log[#log + 1] = entry
    while #log > LOG_SIZE do table.remove(log, 1) end
    for adminId in pairs(watchers) do
        if canOperate(adminId) then
            EventCore.EmitClient("eventview:log", adminId, { entry = entry })
        else
            watchers[adminId] = nil
        end
    end
end

-- ── targeting ──────────────────────────────────────────────────────────────

--- Resolve a target token into a list of player ids.
--- token: number|string  "12" | "player:12" | "nearest" | "all" | "group:admin" | "group:staff"
function EV.ResolveTargets(admin, token)
    if token == nil then return nil, "missing_target" end
    local t = tostring(token):lower()

    if t == "all" then
        local ids = onlineIds()
        if #ids == 0 then return nil, "no_players_online" end
        return ids
    end

    if t == "nearest" then
        local adminId = playerId(admin)
        if not adminId or adminId <= 0 then
            -- console has no position; fall back to first online
            local ids = onlineIds()
            if #ids == 0 then return nil, "no_players_online" end
            return { ids[1] }
        end
        -- Prefer Open77 nearest helper if present; otherwise return admin themselves.
        if Open77 and Open77.players and type(Open77.players.nearest) == "function" then
            local ok, nid = pcall(Open77.players.nearest, adminId)
            if ok and playerId(nid) then return { playerId(nid) } end
        end
        if Open77.players.name(adminId) ~= nil then return { adminId } end
        return nil, "nearest_unavailable"
    end

    local group = t:match("^group:(.+)$")
    if group then
        -- Named convenience group from EventCore.EventViewGroups, or a raw role label.
        local roles = (EventCore.EventViewGroups and EventCore.EventViewGroups[group]) or { group }
        local out = {}
        for _, id in ipairs(onlineIds()) do
            for _, role in ipairs(roles) do
                if hasRole(id, role) then
                    out[#out + 1] = id
                    break
                end
            end
        end
        if #out == 0 then return nil, "group_empty:" .. group end
        return out
    end

    local pid = t:match("^player:(%d+)$") or t:match("^(%d+)$")
    pid = playerId(pid)
    if not pid then return nil, "invalid_target" end
    if not (Open77 and Open77.players and Open77.players.name(pid) ~= nil) then
        return nil, "player_not_online"
    end
    return { pid }
end

-- ── missions (per-player, writable by trusted mods) ────────────────────────

local function trustedMissionCaller()
    local caller = GetInvokingResource and GetInvokingResource() or nil
    if type(caller) ~= "string" then return nil, "mission_caller_unknown" end
    if caller == "rpcore" then return caller end
    if EventCore.Persistence and EventCore.Persistence.IsTrustedCaller
        and EventCore.Persistence.IsTrustedCaller(caller) then return caller end
    if type(EventCore.HudCallers) == "table" and EventCore.HudCallers[caller] == true then return caller end
    if type(EventCore.EventViewCallers) == "table" and EventCore.EventViewCallers[caller] == true then
        return caller
    end
    return nil, "mission_caller_not_trusted:" .. caller
end

--- Set / update a mission entry for one player.
--- entry = { title?, body?, status?, progress?, meta?, widget?, values? }
function EV.MissionSet(rawPlayer, missionId, entry)
    local player = playerId(rawPlayer)
    if not player then return nil, "invalid_player_id" end
    if type(missionId) ~= "string" or missionId == "" or #missionId > 64 then
        return nil, "invalid_mission_id"
    end
    if type(entry) ~= "table" then return nil, "invalid_entry" end

    missions[player] = missions[player] or {}
    local bag = missions[player]
    local count = 0
    for _ in pairs(bag) do count = count + 1 end
    if not bag[missionId] and count >= MAX_MISSIONS then return nil, "too_many_missions" end

    local clean = {
        id = missionId,
        title = type(entry.title) == "string" and entry.title:sub(1, 80) or missionId,
        body = type(entry.body) == "string" and entry.body:sub(1, 400) or "",
        status = type(entry.status) == "string" and entry.status:sub(1, 32) or "active",
        progress = tonumber(entry.progress),
        meta = type(entry.meta) == "table" and entry.meta or nil,
        widget = type(entry.widget) == "string" and entry.widget or nil,
        values = type(entry.values) == "table" and entry.values or nil,
        updatedAt = nowMs(),
    }
    if clean.progress then
        clean.progress = math.max(0, math.min(100, clean.progress))
    end
    bag[missionId] = clean

    -- Push mission list + optional widget drive to the player.
    EventCore.EmitClient("eventview:mission", player, { action = "set", mission = clean })
    if clean.widget and clean.values and EventCore.Widgets and EventCore.Widgets.Set then
        EventCore.Widgets.Set(player, clean.widget, clean.values)
    end

    record({
        kind = "mission_set",
        player = player,
        playerName = nameOf(player),
        missionId = missionId,
        title = clean.title,
        status = clean.status,
    })
    return true
end

function EV.MissionClear(rawPlayer, missionId)
    local player = playerId(rawPlayer)
    if not player then return nil, "invalid_player_id" end
    if not missions[player] then return true end
    if missionId then
        missions[player][missionId] = nil
        EventCore.EmitClient("eventview:mission", player, { action = "clear", id = missionId })
    else
        missions[player] = nil
        EventCore.EmitClient("eventview:mission", player, { action = "clear_all" })
    end
    record({
        kind = "mission_clear",
        player = player,
        playerName = nameOf(player),
        missionId = missionId or "*",
    })
    return true
end

function EV.MissionList(rawPlayer)
    local player = playerId(rawPlayer)
    if not player then return nil, "invalid_player_id" end
    local bag = missions[player] or {}
    local out = {}
    for _, entry in pairs(bag) do out[#out + 1] = entry end
    table.sort(out, function(a, b) return (a.updatedAt or 0) > (b.updatedAt or 0) end)
    return out
end

-- ── LTE schedules ──────────────────────────────────────────────────────────
-- A step is either:
--   { at=ms, kind="hud", action="show|hide|status", target="inkHUDLayer"|... }
--   { at=ms, kind="widget", id="example.meter", values={...} }
--   { at=ms, kind="mission", missionId="...", entry={...} }  -- set
--   { at=ms, kind="mission_clear", missionId="..." }

local function cleanStep(step)
    if type(step) ~= "table" then return nil, "step_not_table" end
    local at = tonumber(step.at)
    if not at or at < 0 or at > 600000 then return nil, "at_0_to_600000" end
    local kind = tostring(step.kind or "hud")
    if kind == "hud" then
        local action = tostring(step.action or "")
        if action ~= "show" and action ~= "hide" and action ~= "status" then
            return nil, "hud_action"
        end
        local target = step.target or step.group
        if type(target) ~= "string" or target == "" then return nil, "hud_target" end
        return { at = math.floor(at), kind = "hud", action = action, target = target }
    elseif kind == "widget" then
        if type(step.id) ~= "string" or not (EventCore.WidgetCatalog and EventCore.WidgetCatalog[step.id]) then
            return nil, "unknown_widget"
        end
        return { at = math.floor(at), kind = "widget", id = step.id, values = type(step.values) == "table" and step.values or {} }
    elseif kind == "mission" then
        if type(step.missionId) ~= "string" or step.missionId == "" then return nil, "mission_id" end
        return { at = math.floor(at), kind = "mission", missionId = step.missionId, entry = type(step.entry) == "table" and step.entry or {} }
    elseif kind == "mission_clear" then
        return { at = math.floor(at), kind = "mission_clear", missionId = step.missionId }
    end
    return nil, "unknown_kind"
end

local function applyStep(player, step)
    if step.kind == "hud" and EventCore.HudBench and EventCore.HudBench.Run then
        -- origin "eventview" so the bench log stays distinct
        return EventCore.HudBench.Run(0, player, { action = step.action, target = step.target }, "eventview")
    elseif step.kind == "widget" and EventCore.Widgets and EventCore.Widgets.Set then
        return EventCore.Widgets.Set(player, step.id, step.values)
    elseif step.kind == "mission" then
        return EV.MissionSet(player, step.missionId, step.entry)
    elseif step.kind == "mission_clear" then
        return EV.MissionClear(player, step.missionId)
    end
    return nil, "unhandled_step"
end

--- Schedule an LTE against a target token (player/nearest/group/all).
function EV.Schedule(admin, targetToken, steps, loops, label)
    if not canOperate(admin) then return nil, "not_operator" end
    local targets, why = EV.ResolveTargets(admin, targetToken)
    if not targets then return nil, why end
    if type(steps) ~= "table" or #steps < 1 or #steps > MAX_STEPS then
        return nil, "steps_1_to_" .. MAX_STEPS
    end
    loops = math.floor(tonumber(loops) or 1)
    if loops < 1 or loops > MAX_LOOPS then return nil, "loops_1_to_" .. MAX_LOOPS end

    local clean, last = {}, 0
    for i, step in ipairs(steps) do
        local c, reason = cleanStep(step)
        if not c then return nil, ("step %d: %s"):format(i, reason) end
        if c.at < last then return nil, ("step %d: steps must be in time order"):format(i) end
        last = c.at
        clean[i] = c
    end

    local active = 0
    for _ in pairs(schedules) do active = active + 1 end
    if active >= MAX_SCHEDULES then return nil, "too_many_schedules" end

    scheduleSeq = scheduleSeq + 1
    local id = "ev" .. scheduleSeq
    local period = last + 250
    local started = nowMs()
    schedules[id] = {
        id = id,
        admin = admin,
        adminName = nameOf(admin),
        targetToken = tostring(targetToken),
        targets = targets,
        label = type(label) == "string" and label:sub(1, 64) or id,
        steps = clean,
        loops = loops,
        period = period,
        startedAt = started,
        endsAt = started + period * loops + 5000,
    }

    -- Fire steps on server timers so widget/mission writes stay authoritative.
    for loop = 1, loops do
        for index, step in ipairs(clean) do
            local delay = (loop - 1) * period + step.at
            local stepCopy, loopN, idx = step, loop, index
            SetTimeout(delay, function()
                if not schedules[id] then return end
                for _, pid in ipairs(targets) do
                    if Open77 and Open77.players and Open77.players.name(pid) ~= nil then
                        local ok, reason = applyStep(pid, stepCopy)
                        record({
                            kind = "lte_step",
                            schedule = id,
                            label = schedules[id] and schedules[id].label,
                            loop = loopN,
                            step = idx,
                            player = pid,
                            playerName = nameOf(pid),
                            stepKind = stepCopy.kind,
                            ok = ok == true,
                            reason = ok and nil or tostring(reason),
                        })
                    end
                end
                if loopN == loops and idx == #clean then
                    schedules[id] = nil
                    record({ kind = "lte_done", schedule = id })
                end
            end)
        end
    end

    record({
        kind = "lte_start",
        schedule = id,
        label = schedules[id].label,
        targetToken = tostring(targetToken),
        targetCount = #targets,
        steps = #clean,
        loops = loops,
        admin = admin,
        adminName = nameOf(admin),
    })
    return id
end

function EV.Cancel(admin, scheduleId)
    if not canOperate(admin) then return nil, "not_operator" end
    if scheduleId then
        if not schedules[scheduleId] then return nil, "unknown_schedule" end
        schedules[scheduleId] = nil
        record({ kind = "lte_cancel", schedule = scheduleId, admin = admin })
        return true
    end
    local n = 0
    for id in pairs(schedules) do
        schedules[id] = nil
        n = n + 1
    end
    record({ kind = "lte_cancel", schedule = "*", count = n, admin = admin })
    return n
end

function EV.ListSchedules()
    local out = {}
    for id, s in pairs(schedules) do
        out[#out + 1] = {
            id = id,
            label = s.label,
            targetToken = s.targetToken,
            targetCount = #(s.targets or {}),
            steps = #(s.steps or {}),
            loops = s.loops,
            adminName = s.adminName,
            endsAt = s.endsAt,
        }
    end
    return out
end

function EV.LogTail(n)
    n = math.min(tonumber(n) or 50, #log)
    local first = math.max(1, #log - n + 1)
    local out = {}
    for i = first, #log do out[#out + 1] = log[i] end
    return out
end

-- ── net + commands ─────────────────────────────────────────────────────────

RegisterNetEvent("eventcore:eventview:watch", function(on)
    local id = playerId(source)
    if not id or not canOperate(id) then return end
    watchers[id] = on ~= false and true or nil
    if watchers[id] then
        EventCore.EmitClient("eventview:log", id, { entries = EV.LogTail(100) })
    end
end)

RegisterNetEvent("eventcore:eventview:schedule", function(payload)
    local id = playerId(source)
    if not id or not canOperate(id) then return end
    if type(payload) ~= "table" then return end
    local sid, reason = EV.Schedule(id, payload.target, payload.steps, payload.loops, payload.label)
    EventCore.EmitClient("eventview:result", id, {
        ok = sid ~= nil,
        schedule = sid,
        reason = reason,
    })
end)

RegisterNetEvent("eventcore:eventview:cancel", function(scheduleId)
    local id = playerId(source)
    if not id or not canOperate(id) then return end
    EV.Cancel(id, scheduleId)
end)

RegisterNetEvent("eventcore:eventview:mission_list", function(target)
    local id = playerId(source)
    if not id or not canOperate(id) then return end
    local targets = EV.ResolveTargets(id, target or id)
    local out = {}
    if targets then
        for _, pid in ipairs(targets) do
            out[tostring(pid)] = EV.MissionList(pid)
        end
    end
    EventCore.EmitClient("eventview:missions", id, { missions = out })
end)

AddEventHandler("playerDropped", function()
    local id = tonumber(source)
    if id then
        watchers[id] = nil
        missions[id] = nil
    end
end)

-- Snapshot missions when widgets client signals ready (reuse widgets ready if present).
RegisterNetEvent("eventcore:widgets:ready", function()
    local player = playerId(source)
    if not player or not missions[player] then return end
    for _, entry in pairs(missions[player]) do
        EventCore.EmitClient("eventview:mission", player, { action = "set", mission = entry })
    end
end)

local function replyCmd(src, raw, ok, message)
    if src <= 0 then
        print("[EventCore][eventview] " .. message)
    else
        TriggerClientEvent("open77:command:result", src, raw or "", ok, message)
    end
end

-- /eventcore.eventview.schedule <target> <loops> <label?>
-- Target: <id> | player:<id> | nearest | all | group:<role>
-- Steps are expected via the admin panel; the command form supports a simple hud hide/show pair for smoke tests:
--   /eventcore.eventview.schedule all 1 smoke 0,hide,inkHUDLayer 2000,show,inkHUDLayer
RegisterCommand("eventcore.eventview.schedule", function(src, args, raw)
    src = tonumber(src) or 0
    if src > 0 and not canOperate(src) then return replyCmd(src, raw, false, "EventView access denied.") end
    local target = args and args[1]
    local loops = tonumber(args and args[2]) or 1
    local label = args and args[3]
    local steps = {}
    -- Optional inline steps: at,action,target
    for i = 4, #(args or {}) do
        local at, action, tgt = tostring(args[i]):match("^(%d+),([%w_]+),(.+)$")
        if at then
            steps[#steps + 1] = { at = tonumber(at), kind = "hud", action = action, target = tgt }
        end
    end
    if #steps == 0 then
        -- default smoke pair so the command is usable without the panel
        steps = {
            { at = 0, kind = "hud", action = "hide", target = "inkHUDLayer" },
            { at = 2000, kind = "hud", action = "show", target = "inkHUDLayer" },
        }
    end
    local id, reason = EV.Schedule(src, target, steps, loops, label)
    replyCmd(src, raw, id ~= nil, id and ("Scheduled " .. id) or ("Schedule failed: " .. tostring(reason)))
end, true)

RegisterCommand("eventcore.eventview.cancel", function(src, args, raw)
    src = tonumber(src) or 0
    if src > 0 and not canOperate(src) then return replyCmd(src, raw, false, "EventView access denied.") end
    local n, reason = EV.Cancel(src, args and args[1])
    replyCmd(src, raw, n ~= nil, n and ("Cancelled.") or ("Cancel failed: " .. tostring(reason)))
end, true)

RegisterCommand("eventcore.eventview.targets", function(src, args, raw)
    src = tonumber(src) or 0
    if src > 0 and not canOperate(src) then return replyCmd(src, raw, false, "EventView access denied.") end
    local ids, reason = EV.ResolveTargets(src, args and args[1] or "all")
    if not ids then return replyCmd(src, raw, false, "Resolve failed: " .. tostring(reason)) end
    local parts = {}
    for _, id in ipairs(ids) do parts[#parts + 1] = ("%d:%s"):format(id, nameOf(id)) end
    replyCmd(src, raw, true, ("Targets (%d): %s"):format(#ids, table.concat(parts, ", ")))
end, true)

RegisterCommand("eventcore.eventview.mission", function(src, args, raw)
    src = tonumber(src) or 0
    if src > 0 and not canOperate(src) then return replyCmd(src, raw, false, "EventView access denied.") end
    local target, action, missionId = args and args[1], args and args[2], args and args[3]
    if not target or not action then
        return replyCmd(src, raw, false, "Usage: /eventcore.eventview.mission <target> set|clear|list [missionId] [title=..]")
    end
    local targets, why = EV.ResolveTargets(src, target)
    if not targets then return replyCmd(src, raw, false, tostring(why)) end

    if action == "list" then
        local lines = {}
        for _, pid in ipairs(targets) do
            local list = EV.MissionList(pid) or {}
            lines[#lines + 1] = ("%d:%s (%d)"):format(pid, nameOf(pid), #list)
            for _, m in ipairs(list) do
                lines[#lines + 1] = ("  - %s [%s] %s"):format(m.id, m.status, m.title or "")
            end
        end
        return replyCmd(src, raw, true, table.concat(lines, "\n"))
    end

    if action == "clear" then
        for _, pid in ipairs(targets) do EV.MissionClear(pid, missionId) end
        return replyCmd(src, raw, true, "Cleared.")
    end

    if action == "set" then
        if not missionId then return replyCmd(src, raw, false, "missionId required") end
        local entry = { title = missionId, status = "active" }
        for i = 4, #(args or {}) do
            local k, v = tostring(args[i]):match("^([%w_]+)=(.*)$")
            if k then entry[k] = v end
        end
        for _, pid in ipairs(targets) do EV.MissionSet(pid, missionId, entry) end
        return replyCmd(src, raw, true, "Mission set on " .. #targets .. " player(s).")
    end

    replyCmd(src, raw, false, "Unknown action. Use set|clear|list")
end, true)

RegisterCommand("eventcore.eventview.log", function(src, args, raw)
    src = tonumber(src) or 0
    if src > 0 and not canOperate(src) then return replyCmd(src, raw, false, "EventView access denied.") end
    local entries = EV.LogTail(tonumber(args and args[1]) or 20)
    local lines = {}
    for _, e in ipairs(entries) do
        lines[#lines + 1] = string.format("[%s] %s p=%s %s",
            tostring(e.kind), tostring(e.schedule or e.missionId or "-"),
            tostring(e.playerName or e.player or "-"),
            e.ok == false and ("FAIL " .. tostring(e.reason)) or "ok")
    end
    replyCmd(src, raw, true, #lines > 0 and table.concat(lines, "\n") or "(empty)")
end, true)

-- Exports for other resources (missions) and for admin tooling.
local function guardMission(fn)
    return function(...)
        local caller, why = trustedMissionCaller()
        if not caller then return nil, why end
        return fn(...)
    end
end

exports("EventViewMissionSet", guardMission(EV.MissionSet))
exports("EventViewMissionClear", guardMission(EV.MissionClear))
exports("EventViewMissionList", function(player)
    return EV.MissionList(player)
end)
exports("EventViewSchedule", function(admin, target, steps, loops, label)
    return EV.Schedule(admin or 0, target, steps, loops, label)
end)
exports("EventViewCancel", function(admin, id)
    return EV.Cancel(admin or 0, id)
end)
exports("EventViewTargets", function(admin, token)
    return EV.ResolveTargets(admin or 0, token)
end)
exports("EventViewLog", function(n)
    return EV.LogTail(n)
end)
