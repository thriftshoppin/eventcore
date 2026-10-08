--[[
    EventCore - Server Dispatcher & Open77 Network Bus
    Responsible for server events and client-server transmission
]]

EventCore = EventCore or {}

local NET_PREFIX = "eventcore:net:"
local allowedClientEvents = {}

--- Broadcast an event locally on the server
function EventCore.EmitServer(eventName, payload)
    return EventCore.DispatchLocal(eventName, payload, -1)
end

local function exportContext(context)
    return {
        name = context.name,
        data = context.data,
        source = context.source,
        timestamp = context.timestamp,
        cancelled = context.isCancelled(),
        cancelReason = context.getCancelReason(),
    }
end

--- Send an event to a specific client player
function EventCore.EmitClient(eventName, targetPlayer, payload)
    if not targetPlayer then
        print(string.format("[EventCore][ERROR] EmitClient requires targetPlayer. Event: %s", eventName))
        return false
    end

    local netEvent = NET_PREFIX .. eventName

    -- Support Open77 native networking with graceful fallback
    if TriggerClientEvent then
        TriggerClientEvent(netEvent, targetPlayer, payload or {})
    elseif Open77 and Open77.net and Open77.net.send then
        Open77.net.send(targetPlayer, netEvent, payload or {})
    else
        print(string.format("[EventCore][WARN] No client network transport found for EmitClient '%s'", eventName))
    end

    return true
end

--- Broadcast an event to all connected clients
function EventCore.BroadcastClient(eventName, payload)
    local netEvent = NET_PREFIX .. eventName

    if TriggerClientEvent then
        TriggerClientEvent(netEvent, -1, payload or {})
    elseif Open77 and Open77.net and Open77.net.broadcast then
        Open77.net.broadcast(netEvent, payload or {})
    end

    return true
end

--- Listen for client-to-server forwarded events
local function handleInboundClientEvent(eventName, playerSource, payload)
    if type(eventName) ~= "string" or not allowedClientEvents[eventName] then
        print(string.format("[EventCore][WARN] Rejected client event: %s", tostring(eventName)))
        return false
    end
    -- Fire on server event bus with player source
    local context = EventCore.DispatchLocal(eventName, payload, playerSource)
    return context
end

--- Explicitly allow a client event from trusted server-side resource code.
function EventCore.AllowClientEvent(eventName)
    if type(eventName) ~= "string" or eventName == "" or #eventName > 128 then
        return false, "invalid_event_name"
    end
    allowedClientEvents[eventName] = true
    return true
end

-- Hook into native network layer for incoming events
if RegisterNetEvent then
    -- FiveM / Open77 compatibility layer
    RegisterNetEvent(NET_PREFIX .. "relay", function(eventName, payload)
        local src = source
        handleInboundClientEvent(eventName, src, payload)
    end)
end

if Open77 and Open77.net and Open77.net.on then
    Open77.net.on(NET_PREFIX .. "relay", function(playerSource, eventName, payload)
        handleInboundClientEvent(eventName, playerSource, payload)
    end)
end

-- Export functions for other Open77 resources
if exports then
    exports("AllowClientEvent", function(eventName)
        local caller = GetInvokingResource and GetInvokingResource() or nil
        if not EventCore.Persistence or not EventCore.Persistence.IsTrustedCaller(caller) then
            return false, "client_event_caller_not_trusted"
        end
        return EventCore.AllowClientEvent(eventName)
    end)

    exports("Emit", function(eventName, payload)
        return exportContext(EventCore.EmitServer(eventName, payload))
    end)

    exports("EmitClient", function(eventName, target, payload)
        return EventCore.EmitClient(eventName, target, payload)
    end)

    exports("BroadcastClient", function(eventName, payload)
        return EventCore.BroadcastClient(eventName, payload)
    end)

    local function trustedPersistenceCall(method, ...)
        local caller = GetInvokingResource and GetInvokingResource() or nil
        if not EventCore.Persistence or not EventCore.Persistence.IsTrustedCaller(caller) then
            return nil, "persistence_caller_not_trusted"
        end
        return method(...)
    end

    exports("PersistEvent", function(...)
        return trustedPersistenceCall(EventCore.Persistence.Persist, ...)
    end)
    exports("GetPersistedEvent", function(...)
        return trustedPersistenceCall(EventCore.Persistence.Get, ...)
    end)
    exports("FindPersistedEvents", function(...)
        return trustedPersistenceCall(EventCore.Persistence.Find, ...)
    end)
    exports("PersistenceStatus", function()
        return EventCore.Persistence.Status()
    end)
    exports("ExposeEvent", function(...)
        return trustedPersistenceCall(EventCore.Persistence.ExposeEvent, ...)
    end)
    exports("SavePlayerState", function(...)
        return trustedPersistenceCall(EventCore.Persistence.SavePlayerState, ...)
    end)
    exports("LoadPlayerState", function(...)
        return trustedPersistenceCall(EventCore.Persistence.LoadPlayerState, ...)
    end)
    exports("DeletePlayerState", function(...)
        return trustedPersistenceCall(EventCore.Persistence.DeletePlayerState, ...)
    end)
    exports("SaveInventoryState", function(...)
        return trustedPersistenceCall(EventCore.Persistence.SaveInventoryState, ...)
    end)
    exports("LoadInventoryState", function(...)
        return trustedPersistenceCall(EventCore.Persistence.LoadInventoryState, ...)
    end)
    exports("SaveOutfitCode", function(...)
        return trustedPersistenceCall(EventCore.Persistence.SaveOutfitCode, ...)
    end)
    exports("LoadOutfitCode", function(...)
        return trustedPersistenceCall(EventCore.Persistence.LoadOutfitCode, ...)
    end)
end

print("[EventCore] Server subsystem initialized successfully on Open77 platform.")
