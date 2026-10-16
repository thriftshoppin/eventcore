-- EventCore custom ink-widget bridge (client side).
--
-- The server sends validated widget values (`widget:apply`, `widget:reset`, `widget:snapshot`).
-- This module keeps the current values and hands them to ADAPTERS, the pieces that actually draw
-- a widget: an RPCore web panel, a game-side companion that mounts an ink widget under
-- `inkHUDLayer`, or anything else. Adapters are registered by code on this client:
--
--   EventCore.Widgets.RegisterAdapter("example.meter", function(id, values, def, event) ... end)
--   EventCore.Widgets.RegisterAdapter("*", fn)      -- every widget
--
-- `event` is "apply" | "reset". `values` is the full current table (catalog defaults merged in).
-- With no adapter a widget is only tracked: nothing is drawn and nothing is claimed.

EventCore = EventCore or {}
local Widgets = {}
EventCore.Widgets = Widgets

local adapters = {}   -- [id or "*"] = { fn, ... }
local current = {}    -- [id] = values

local function defaultsFor(id)
    local def = EventCore.WidgetCatalog and EventCore.WidgetCatalog[id]
    local values = {}
    if def then for name, field in pairs(def.fields or {}) do values[name] = field.default end end
    return values, def
end

local function dispatch(id, event)
    local values, def = current[id], EventCore.WidgetCatalog[id]
    for _, key in ipairs({ id, "*" }) do
        for _, fn in ipairs(adapters[key] or {}) do
            local ok, err = pcall(fn, id, values, def, event)
            if not ok then print(("[EventCore][widgets] adapter for %s failed: %s"):format(id, tostring(err))) end
        end
    end
    -- Also a local event, so other client resources can listen without registering an adapter.
    EventCore.EmitClient("widget:changed", { id = id, event = event, values = values })
end

function Widgets.RegisterAdapter(id, fn)
    if type(id) ~= "string" or type(fn) ~= "function" then return false end
    adapters[id] = adapters[id] or {}
    adapters[id][#adapters[id] + 1] = fn
    -- Catch a late adapter up with anything already received.
    if id == "*" then for known in pairs(current) do pcall(fn, known, current[known], EventCore.WidgetCatalog[known], "apply") end
    elseif current[id] then pcall(fn, id, current[id], EventCore.WidgetCatalog[id], "apply") end
    return true
end

function Widgets.Get(id) return current[id] end

local function apply(id, values)
    if type(id) ~= "string" or not (EventCore.WidgetCatalog and EventCore.WidgetCatalog[id]) or type(values) ~= "table" then return end
    local merged = current[id] or defaultsFor(id)
    for name, value in pairs(values) do merged[name] = value end
    current[id] = merged
    dispatch(id, "apply")
end

local function reset(id)
    if id == nil then
        local ids = {}
        for known in pairs(current) do ids[#ids + 1] = known end
        for _, known in ipairs(ids) do current[known] = defaultsFor(known); dispatch(known, "reset") end
    elseif EventCore.WidgetCatalog[id] then
        current[id] = defaultsFor(id); dispatch(id, "reset")
    end
end

EventCore.On("widget:apply", function(p) if type(p) == "table" then apply(p.id, p.values) end end)
EventCore.On("widget:reset", function(p) if type(p) == "table" then reset(p.id) end end)
EventCore.On("widget:snapshot", function(p)
    if type(p) ~= "table" or type(p.widgets) ~= "table" then return end
    for id, values in pairs(p.widgets) do apply(id, values) end
end)

-- Ask the server for what this client should be showing (join and client restart).
AddEventHandler("onClientResourceStart", function(name)
    if name == GetCurrentResourceName() and TriggerServerEvent then TriggerServerEvent("eventcore:widgets:ready") end
end)

if exports then
    exports("WidgetGet", function(id) return current[id] end)
end
