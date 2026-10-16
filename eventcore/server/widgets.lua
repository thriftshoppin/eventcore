-- EventCore custom ink-widget bridge (server side).
--
-- Server resources (RPCore, needs, jobs, ...) set typed values for widgets defined in
-- EventCore.WidgetCatalog (shared/widgets.lua). EventCore validates against the catalog, remembers
-- the latest values per player, sends them to that player's client, and replays them when the client
-- reports ready. Presentation only: the client draws, the server stays the authority.

EventCore = EventCore or {}
EventCore.Widgets = EventCore.Widgets or {}
local Widgets = EventCore.Widgets

local MAX_STRING = 256
local state = {}   -- [player] = { [widgetId] = { field = value } }

local function playerId(value)
    value = tonumber(value)
    if not value or value < 1 or value % 1 ~= 0 then return nil end
    return value
end

local function checkField(def, value)
    if def.type == "boolean" then
        if type(value) ~= "boolean" then return nil, "expected_boolean" end
        return value
    elseif def.type == "number" then
        value = tonumber(value)
        if not value or value ~= value or value == math.huge or value == -math.huge then return nil, "expected_number" end
        if def.min and value < def.min then value = def.min end
        if def.max and value > def.max then value = def.max end
        return value
    elseif def.type == "string" then
        if type(value) ~= "string" then return nil, "expected_string" end
        local limit = math.min(tonumber(def.maxLen) or 64, MAX_STRING)
        if #value > limit then value = value:sub(1, limit) end
        return (value:gsub("[%c]", " "))
    elseif def.type == "enum" then
        for _, allowed in ipairs(def.values or {}) do if value == allowed then return value end end
        return nil, "not_in_enum"
    end
    return nil, "unknown_field_type"
end

--- Validate and apply `values` to widget `id` for `player`. Returns true or nil, reason.
function Widgets.Set(rawPlayer, id, values)
    local player = playerId(rawPlayer)
    if not player then return nil, "invalid_player_id" end
    local def = type(id) == "string" and EventCore.WidgetCatalog[id] or nil
    if not def then return nil, "unknown_widget" end
    if type(values) ~= "table" then return nil, "invalid_values" end
    local clean = {}
    for name, value in pairs(values) do
        local field = type(name) == "string" and def.fields and def.fields[name] or nil
        if not field then return nil, "unknown_field:" .. tostring(name) end
        local checked, reason = checkField(field, value)
        if checked == nil then return nil, name .. ":" .. tostring(reason) end
        clean[name] = checked
    end
    local mine = state[player] or {}
    state[player] = mine
    local merged = mine[id] or {}
    for name, value in pairs(clean) do merged[name] = value end
    mine[id] = merged
    EventCore.EmitClient("widget:apply", player, { id = id, values = clean })
    return true
end

--- Reset one widget (or all when id is nil) to catalog defaults on the client.
function Widgets.Reset(rawPlayer, id)
    local player = playerId(rawPlayer)
    if not player then return nil, "invalid_player_id" end
    if id ~= nil and not (type(id) == "string" and EventCore.WidgetCatalog[id]) then return nil, "unknown_widget" end
    if state[player] then
        if id then state[player][id] = nil else state[player] = nil end
    end
    EventCore.EmitClient("widget:reset", player, { id = id })
    return true
end

function Widgets.Catalog()
    local out = {}
    for id, def in pairs(EventCore.WidgetCatalog) do
        out[#out + 1] = { id = id, mount = def.mount, parent = def.parent, inkType = def.inkType }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- A client that (re)starts asks for what it should be showing.
RegisterNetEvent("eventcore:widgets:ready", function()
    local player = playerId(source)
    if not player then return end
    EventCore.EmitClient("widget:snapshot", player, { widgets = state[player] or {} })
end)

AddEventHandler("playerDropped", function()
    local id = tonumber(source)
    if id then state[id] = nil end
end)

-- /eventcore.widget <player> <widget> [field=value ...]   or   ... reset
RegisterCommand("eventcore.widget", function(src, args, raw)
    src = tonumber(src) or 0
    local function reply(ok, message)
        if src <= 0 then print("[EventCore][widget] " .. message) else
            TriggerClientEvent("open77:command:result", src, raw or "", ok, message) end
    end
    if src > 0 and not (EventCore.Access and EventCore.Access.IsLocalAdmin(src) == true) then
        return reply(false, "EventCore admin access denied.")
    end
    local player, id = args and args[1], args and args[2]
    if args and args[3] == "reset" then
        local ok, reason = Widgets.Reset(player, id)
        return reply(ok == true, ok and "Widget reset." or ("Reset failed: " .. tostring(reason)))
    end
    local values = {}
    for index = 3, #(args or {}) do
        local name, value = tostring(args[index]):match("^([%w_]+)=(.*)$")
        if not name then return reply(false, "Usage: /eventcore.widget <player> <widget> field=value ... | reset") end
        local def = EventCore.WidgetCatalog[id or ""]
        local field = def and def.fields[name]
        if field and field.type == "boolean" then value = (value == "true" or value == "1")
        elseif field and field.type == "number" then value = tonumber(value) end
        values[name] = value
    end
    local ok, reason = Widgets.Set(player, id, values)
    reply(ok == true, ok and "Widget updated." or ("Widget update failed: " .. tostring(reason)))
end, true)

-- Exports for other server resources: rpcore, trusted persistence callers, EventCore.HudCallers.
local function allowedCaller()
    local caller = GetInvokingResource and GetInvokingResource() or nil
    if type(caller) ~= "string" then return nil, "widget_caller_unknown" end
    local persistence = EventCore.Persistence
    if caller == "rpcore" or (persistence and persistence.IsTrustedCaller(caller))
        or (type(EventCore.HudCallers) == "table" and EventCore.HudCallers[caller] == true) then
        return caller
    end
    return nil, "widget_caller_not_trusted:" .. caller
end

local function guarded(fn)
    return function(...)
        local caller, why = allowedCaller()
        if not caller then return nil, why end
        return fn(...)
    end
end

exports("WidgetSet", guarded(Widgets.Set))
exports("WidgetReset", guarded(Widgets.Reset))
exports("WidgetCatalog", Widgets.Catalog)
