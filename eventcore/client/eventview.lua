-- EventCore EventView (client).
-- Receives mission updates and log pushes from the server EventView module.

EventCore = EventCore or {}
EventCore.EventView = EventCore.EventView or {}
local EV = EventCore.EventView

local missions = {} -- [id] = entry

local function emit(name, payload)
    if EventCore.EmitLocal then
        EventCore.EmitLocal(name, payload)
    end
end

RegisterNetEvent("eventcore:net:eventview:mission", function(payload)
    if type(payload) ~= "table" then return end
    if payload.action == "set" and type(payload.mission) == "table" and payload.mission.id then
        missions[payload.mission.id] = payload.mission
        emit("eventview:mission", { action = "set", mission = payload.mission })
    elseif payload.action == "clear" and payload.id then
        missions[payload.id] = nil
        emit("eventview:mission", { action = "clear", id = payload.id })
    elseif payload.action == "clear_all" then
        missions = {}
        emit("eventview:mission", { action = "clear_all" })
    end
end)

RegisterNetEvent("eventcore:net:eventview:log", function(payload)
    emit("eventview:log", payload)
end)

RegisterNetEvent("eventcore:net:eventview:result", function(payload)
    emit("eventview:result", payload)
end)

RegisterNetEvent("eventcore:net:eventview:missions", function(payload)
    emit("eventview:missions", payload)
end)

function EV.GetMissions()
    local out = {}
    for _, m in pairs(missions) do out[#out + 1] = m end
    return out
end

function EV.GetMission(id)
    return missions[id]
end
