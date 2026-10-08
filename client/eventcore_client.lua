-- EventCore client runtime: local events plus explicitly named server messages.

EventCore = EventCore or {}
local NET_PREFIX = "eventcore:net:"
local networkListeners = {}
local stateSequences = {}
local registerLocalListener = EventCore.On

function EventCore.On(eventName, callback, priority)
    local id = registerLocalListener(eventName, callback, priority)
    if id and eventName == EventCore.STATE_FEED_EVENT and not networkListeners[eventName] and RegisterNetEvent then
        networkListeners[eventName] = true
        RegisterNetEvent(NET_PREFIX .. eventName, function(packet)
            if type(packet) ~= "table" or packet.protocolVersion ~= 1
                or type(packet.epoch) ~= "string" or #packet.epoch > 64
                or type(packet.publisher) ~= "string" or #packet.publisher < 1 or #packet.publisher > 64
                or not packet.publisher:match("^[a-z][a-z0-9_.-]*$")
                or type(packet.channel) ~= "string" or #packet.channel < 1 or #packet.channel > 64
                or not packet.channel:match("^[a-z][a-z0-9_.-]*$")
                or type(packet.schemaVersion) ~= "number" or packet.schemaVersion < 1
                or packet.schemaVersion % 1 ~= 0
                or type(packet.sequence) ~= "number" or packet.sequence < 1
                or packet.sequence % 1 ~= 0 or type(packet.visible) ~= "boolean"
                or type(packet.state) ~= "table" then
                return
            end
            local sequenceKey = packet.publisher .. "\0" .. packet.channel
            local current = stateSequences[sequenceKey]
            if current and (packet.schemaVersion < current.schemaVersion
                or (packet.epoch == current.epoch and packet.schemaVersion == current.schemaVersion
                    and packet.sequence <= current.sequence)) then
                return
            end
            stateSequences[sequenceKey] = {
                epoch = packet.epoch,
                schemaVersion = packet.schemaVersion,
                sequence = packet.sequence,
            }
            EventCore.DispatchLocal(eventName, packet, -1)
        end)
    elseif id and type(eventName) == "string" and not networkListeners[eventName] and RegisterNetEvent then
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
