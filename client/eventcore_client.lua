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

if exports then
    exports("On", function(eventName, callback, priority)
        return EventCore.On(eventName, callback, priority)
    end)
    exports("Off", function(eventName, id)
        return EventCore.Off(eventName, id)
    end)
    exports("Emit", function(eventName, payload)
        return EventCore.EmitClient(eventName, payload)
    end)
    exports("EmitServer", function(eventName, payload)
        return EventCore.EmitServer(eventName, payload)
    end)
end

print("[EventCore] Client event subsystem initialized.")
