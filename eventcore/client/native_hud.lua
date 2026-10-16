-- EventCore native HUD callers.
--
-- EventCore shows only the game's own HUD. The HUD lives in the `inkHUDLayer` ink layer; its
-- controllers (every `inkHUDGameController`) and widgets are listed in the generated
-- `EventCore.NativeRegistry` (shared/native_registry.lua, built from the game scripts).
--
-- This module gives every registry entry a caller: EventCore.NativeHud.Caller(name) returns a
-- function(visible) for ANY layer, controller or widget in the registry, and
-- EventCore.NativeHud.Call(name, action) runs one and returns a structured result.
--
-- What is known and what is not:
--   * Open77.hud.setVisible(component, visible) is the one host call this repo has seen work, for the
--     components "health", "stamina", "weapon" and "speedometer" (see ALIASES).
--   * Every other registry name is passed to the host unchanged. The host may accept or refuse it.
--     The result always says which, so nothing here claims a widget responded when it did not.
--   * No host call for reading or writing blackboards is documented. Blackboard entries are
--     browsable (registry) but "read"/"set" report `no_host_api` instead of guessing.

EventCore = EventCore or {}
local NativeHud = {}
EventCore.NativeHud = NativeHud

local ACTIONS = { show = true, hide = true, status = true, introspect = true, restore = true }
local GROUPS = { hud = true, verified = true }
local MAX_FAILURES = 40

-- Components Freeroam has been seen to drive through Open77.hud.setVisible. Controller names map
-- to them; everything else is called by its own registry name.
local VERIFIED_COMPONENTS = { "health", "stamina", "weapon", "speedometer" }
local ALIASES = {
    healthbarWidgetGameController = "health",
    StaminabarWidgetGameController = "stamina",
    weaponIndicatorController = "weapon",
    WeaponRosterGameController = "weapon",
    speedometerLogicController = "speedometer",
    analogSpeedometerLogicController = "speedometer",
}

local function now()
    if Open77 and Open77.time and type(Open77.time.monotonic) == "function" then
        local ok, value = pcall(Open77.time.monotonic)
        if ok and tonumber(value) then return tonumber(value) * 1000 end
    end
    return os.clock() * 1000
end

local function text(value, limit)
    value = tostring(value)
    if #value > limit then value = value:sub(1, limit) end
    return (value:gsub("[%c]", " "))
end

local function hostSetVisible()
    local hud = Open77 and Open77.hud
    if type(hud) ~= "table" or type(hud.setVisible) ~= "function" then return nil end
    return hud.setVisible
end

--- One host call. Returns { ok, accepted, detail } and never throws.
local function setVisible(component, visible)
    local fn = hostSetVisible()
    if not fn then return { ok = false, detail = "host_api_unavailable: Open77.hud.setVisible" } end
    local called, accepted, detail = pcall(fn, component, visible)
    if not called then return { ok = false, detail = "host_error: " .. text(accepted, 200) } end
    -- Freeroam treats a falsy second value as a refusal and reads `detail` for the reason.
    local ok = accepted ~= false and accepted ~= nil
    return { ok = ok, accepted = ok, detail = detail ~= nil and text(detail, 200) or (ok and "accepted" or "refused") }
end

local function find(name)
    local registry = EventCore.NativeRegistry
    if not (registry and registry.Find) then return nil end
    return registry.Find(name)
end

--- The name handed to the host for a registry entry.
function NativeHud.ComponentFor(name)
    return ALIASES[name] or name
end

local callers = {}
--- A caller for any registry name: function(visible) -> result. Cached.
function NativeHud.Caller(name)
    local entry, kind = find(name)
    if not entry then return nil, "unknown_target" end
    if kind == "blackboard" then return nil, "blackboards_have_no_visibility" end
    local caller = callers[name]
    if not caller then
        local component = NativeHud.ComponentFor(name)
        caller = function(visible) return setVisible(component, visible == true) end
        callers[name] = caller
    end
    return caller
end

--- Every registry entry that has a caller, for adapters that want to enumerate them.
function NativeHud.List(kind)
    local registry = EventCore.NativeRegistry or {}
    local source = kind == "layer" and registry.layers or kind == "widget" and registry.widgets
        or kind == "controller" and registry.controllers or {}
    local names = {}
    for _, entry in ipairs(source) do names[#names + 1] = entry.n end
    return names
end

local function introspect()
    local report = { hud = {}, other = {} }
    local hud = Open77 and Open77.hud
    if type(hud) == "table" then
        for key, value in pairs(hud) do report.hud[#report.hud + 1] = tostring(key) .. ":" .. type(value) end
    end
    -- Namespaces that might carry UI or blackboard access. Names only; nothing is called.
    for _, key in ipairs({ "ui", "blackboard", "blackboards", "ink", "widgets", "webui", "input" }) do
        if Open77 and type(Open77[key]) == "table" then report.other[#report.other + 1] = "Open77." .. key end
    end
    table.sort(report.hud)
    return {
        ok = type(hud) == "table",
        detail = ("Open77.hud: %s | other namespaces: %s"):format(
            #report.hud > 0 and table.concat(report.hud, ", ") or "missing",
            #report.other > 0 and table.concat(report.other, ", ") or "none"),
    }
end

local function sweep(group, visible)
    local registry = EventCore.NativeRegistry
    if not registry then return { ok = false, detail = "registry_unavailable" } end
    local names = {}
    if group == "verified" then
        for _, component in ipairs(VERIFIED_COMPONENTS) do names[#names + 1] = component end
    else
        names[1] = "inkHUDLayer"
        for _, entry in ipairs(registry.controllers) do
            if entry.hud then names[#names + 1] = entry.n end
        end
    end
    local accepted, refused, seen, failures = 0, 0, {}, {}
    for _, name in ipairs(names) do
        local component = NativeHud.ComponentFor(name)
        if not seen[component] then
            seen[component] = true
            local result = setVisible(component, visible)
            if result.ok then accepted = accepted + 1 else
                refused = refused + 1
                if #failures < MAX_FAILURES then failures[#failures + 1] = name end
            end
        end
    end
    return {
        ok = accepted > 0, accepted = accepted, refused = refused,
        detail = ("%s %s: %d accepted, %d refused%s"):format(group, visible and "show" or "hide", accepted, refused,
            #failures > 0 and (" (e.g. " .. table.concat(failures, ", ", 1, math.min(#failures, 5)) .. ")") or ""),
    }
end

--- Run one native HUD call. spec = { target?, group?, action }. Always returns a result table:
--- { ok, accepted?, detail, ms, target, action }.
function NativeHud.Call(spec)
    local started = now()
    local result
    local action = type(spec) == "table" and spec.action or nil
    local target = type(spec) == "table" and (spec.target or spec.group) or nil
    if not ACTIONS[action] then
        result = { ok = false, detail = "unknown_action" }
    elseif action == "introspect" then
        result = introspect()
    elseif action == "restore" then
        result = sweep("verified", true)
    elseif spec.group ~= nil then
        if not GROUPS[spec.group] then result = { ok = false, detail = "unknown_group" }
        elseif action == "status" then
            local fn = hostSetVisible()
            result = { ok = fn ~= nil, detail = fn and "Open77.hud.setVisible present" or "Open77.hud.setVisible missing" }
        else result = sweep(spec.group, action == "show") end
    else
        local entry, kind = find(spec.target)
        if not entry then
            result = { ok = false, detail = "unknown_target" }
        elseif kind == "blackboard" then
            result = { ok = false, detail = "no_host_api: no documented Open77 call reads or sets blackboards ("
                .. #entry.v .. " fields listed in the registry)" }
        elseif action == "status" then
            local fn = hostSetVisible()
            result = { ok = fn ~= nil, detail = ("%s %s -> host name '%s'; setVisible %s"):format(kind, spec.target,
                NativeHud.ComponentFor(spec.target), fn and "present" or "missing") }
        else
            local caller = NativeHud.Caller(spec.target)
            result = caller(action == "show")
        end
    end
    result.ms = math.floor((now() - started) * 10) / 10
    result.target = target and text(target, 96) or nil
    result.action = action
    return result
end

-- Server-driven test calls. Only the server can raise this event on a client; the server has
-- already checked that the sender is a global admin. The client still validates every field.
local function runFromServer(payload)
    local requestId, spec = type(payload) == "table" and payload.requestId, type(payload) == "table" and payload.spec
    if type(requestId) ~= "string" or #requestId > 48 or type(spec) ~= "table" then return end
    local result = NativeHud.Call({ target = type(spec.target) == "string" and spec.target or nil,
        group = type(spec.group) == "string" and spec.group or nil,
        action = type(spec.action) == "string" and spec.action or nil })
    if TriggerServerEvent then TriggerServerEvent("eventcore:hud:result", requestId, result) end
end
EventCore.On("hud:run", runFromServer)

-- Scheduled playback. The server sends the whole schedule once; this client runs it on its own
-- timers and reports every step as a normal result, so the viewer shows each one as it fires.
local playing = {}
local MAX_STEPS, MAX_LOOPS = 32, 10

local function sleepUntil(id, dueMs)
    while playing[id] do
        local remaining = dueMs - now()
        if remaining <= 0 then return true end
        Wait(math.max(1, math.min(250, math.floor(remaining))))
    end
    return false
end

local function playSchedule(payload)
    if type(payload) ~= "table" or type(payload.id) ~= "string" or #payload.id > 16
        or type(payload.steps) ~= "table" or #payload.steps < 1 or #payload.steps > MAX_STEPS then return end
    local id, loops = payload.id, math.floor(tonumber(payload.loops) or 1)
    local period = tonumber(payload.period) or 1000
    if loops < 1 or loops > MAX_LOOPS or period < 1 or period > 400000 then return end
    local steps = {}
    for index, step in ipairs(payload.steps) do
        if type(step) ~= "table" or not tonumber(step.at) then return end
        steps[index] = { at = tonumber(step.at), action = step.action,
            target = type(step.target) == "string" and step.target or nil,
            group = type(step.group) == "string" and step.group or nil }
    end
    playing[id] = true
    CreateThread(function()
        for loop = 1, loops do
            local started = now()
            for index, step in ipairs(steps) do
                if not sleepUntil(id, started + step.at) then return end
                local result = NativeHud.Call(step)
                if TriggerServerEvent then TriggerServerEvent("eventcore:hud:result", ("%s:%d:%d"):format(id, loop, index), result) end
            end
            if loop < loops and not sleepUntil(id, started + period) then return end
        end
        playing[id] = nil
    end)
end

EventCore.On("hud:schedule", playSchedule)
EventCore.On("hud:cancel", function(payload)
    if type(payload) == "table" and type(payload.id) == "string" then playing[payload.id] = nil end
end)

-- Optional (EventCore.NativeHudConfig.restoreOnStart, off by default because RPCore may hide these on
-- purpose): show the game's own readouts when EventCore starts. Retries briefly because the host may not be ready on the first tick.
local startConfig = EventCore.NativeHudConfig or {}
if startConfig.restoreOnStart == true and AddEventHandler and CreateThread then
    AddEventHandler("onClientResourceStart", function(name)
        if name ~= GetCurrentResourceName() then return end
        CreateThread(function()
            for _ = 1, 8 do
                if hostSetVisible() then
                    local result = sweep("verified", true)
                    if result.ok then
                        print("[EventCore][hud] native HUD shown: " .. result.detail)
                        return
                    end
                end
                Wait(1000)
            end
            print("[EventCore][hud] could not confirm native HUD visibility (Open77.hud.setVisible unavailable or refused)")
        end)
    end)
end

if exports then
    exports("NativeHudCall", function(spec) return NativeHud.Call(spec) end)
end
