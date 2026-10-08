-- EventCore client runtime: local events plus explicitly named server messages.

EventCore = EventCore or {}
local NET_PREFIX = "eventcore:net:"
local networkListeners = {}
local registerLocalListener = EventCore.On

function EventCore.On(eventName, callback, priority)
    local id = registerLocalListener(eventName, callback, priority)
    if id and type(eventName) == "string" and not networkListeners[eventName] and RegisterNetEvent then
        networkListeners[eventName] = true
        RegisterNetEvent(NET_PREFIX .. eventName, function(payload)
            EventCore.DispatchLocal(eventName, payload, -1)
        end)
    end
    return id
end

function EventCore.EmitClient(eventName, payload)
    return EventCore.DispatchLocal(eventName, payload, -1)
end

function EventCore.EmitServer(eventName, payload)
    local relayEvent = NET_PREFIX .. "relay"
    if TriggerServerEvent then
        TriggerServerEvent(relayEvent, eventName, payload or {})
        return true
    elseif Open77 and Open77.net and Open77.net.send then
        return Open77.net.send(relayEvent, eventName, payload or {})
    end
    print(string.format("[EventCore][WARN] No server transport available for EmitServer '%s'", tostring(eventName)))
    return false
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

if exports then
    exports("Emit", function(eventName, payload)
        return exportContext(EventCore.EmitClient(eventName, payload))
    end)
    exports("EmitServer", function(eventName, payload)
        return EventCore.EmitServer(eventName, payload)
    end)
end

print("[EventCore] Client event subsystem initialized.")
