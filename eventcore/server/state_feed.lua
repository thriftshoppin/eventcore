-- EventCore-owned, server-to-client feed for versioned presentation state.
-- Gameplay/domain resources remain authoritative; trusted consumers publish
-- only the client-safe view they have already validated.

EventCore = EventCore or {}
EventCore.StateFeed = EventCore.StateFeed or {}

local sequences = {}
local MAX_DEPTH = 12
local MAX_NODES = 2048
local MAX_STRING = 4096
local MAX_BYTES = 64 * 1024
local function currentEpoch()
    if Open77 and Open77.resource and Open77.resource.generation then
        local ok, generation = pcall(Open77.resource.generation, "eventcore")
        if ok and type(generation) == "number" and generation > 0 then
            return tostring(generation)
        end
    end
    local now = os and os.time and os.time() or 0
    local timer = GetGameTimer and GetGameTimer() or 0
    return tostring(now) .. ":" .. tostring(timer) .. ":" .. tostring({})
end
local feedEpoch = currentEpoch()

local function validId(value)
    return type(value) == "string" and #value > 0 and #value <= 64
        and value:match("^[a-z][a-z0-9_.-]*$") ~= nil
end

local function copyValue(value, seen, budget, depth)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" then return value end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil, "invalid_number" end
        return value
    end
    if kind == "string" then
        if #value > MAX_STRING then return nil, "string_too_long" end
        budget.bytes = budget.bytes + #value
        if budget.bytes > MAX_BYTES then return nil, "payload_too_large" end
        return value
    end
    if kind ~= "table" then return nil, "unsupported_value" end
    if depth > MAX_DEPTH then return nil, "payload_too_deep" end
    if seen[value] then return nil, "cyclic_payload" end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        budget.count = budget.count + 1
        if budget.count > MAX_NODES then seen[value] = nil; return nil, "payload_too_large" end
        if not ((type(key) == "string" and #key <= 128)
            or (type(key) == "number" and key >= 1 and key % 1 == 0)) then
            seen[value] = nil
            return nil, "invalid_payload_key"
        end
        if type(key) == "string" then
            budget.bytes = budget.bytes + #key
            if budget.bytes > MAX_BYTES then seen[value] = nil; return nil, "payload_too_large" end
        end
        local copied, reason = copyValue(child, seen, budget, depth + 1)
        if reason then seen[value] = nil; return nil, reason end
        result[key] = copied
    end
    seen[value] = nil
    return result
end

local function callerTrusted()
    local caller = GetInvokingResource and GetInvokingResource() or nil
    local trusted = EventCore.Persistence
        and EventCore.Persistence.IsTrustedCaller(caller) == true
    return caller, trusted
end

local function publish(playerId, channel, schemaVersion, payload, visible)
    local caller, trusted = callerTrusted()
    if not trusted then return false, "resource_not_trusted:" .. tostring(caller or "unknown") end
    playerId = tonumber(playerId)
    if not playerId or playerId < 1 or playerId % 1 ~= 0 then return false, "invalid_player_id" end
    if not validId(channel) then return false, "invalid_channel" end
    if type(schemaVersion) ~= "number" or schemaVersion < 1 or schemaVersion % 1 ~= 0 then
        return false, "invalid_schema_version"
    end
    if type(visible) ~= "boolean" then return false, "invalid_visibility" end
    if visible and type(payload) ~= "table" then return false, "invalid_payload" end

    local detached = {}
    if visible then
        local reason
        detached, reason = copyValue(payload, {}, { count = 0, bytes = 0 }, 0)
        if reason then return false, reason end
    end
    if not (Open77 and Open77.players and Open77.players.identity) then
        return false, "player_api_unavailable"
    end
    local found, identity = pcall(Open77.players.identity, playerId)
    if not found or type(identity) ~= "table" then return false, "player_not_found" end

    local key = caller .. "\0" .. tostring(playerId) .. "\0" .. channel
    local sequence = (sequences[key] or 0) + 1
    sequences[key] = sequence
    return EventCore.EmitClient(EventCore.STATE_FEED_EVENT, playerId, {
        protocolVersion = 1,
        epoch = feedEpoch,
        publisher = caller,
        channel = channel,
        schemaVersion = schemaVersion,
        sequence = sequence,
        visible = visible,
        state = detached,
    })
end

function EventCore.StateFeed.Publish(playerId, channel, schemaVersion, payload)
    return publish(playerId, channel, schemaVersion, payload, true)
end

function EventCore.StateFeed.Clear(playerId, channel, schemaVersion)
    return publish(playerId, channel, schemaVersion, {}, false)
end

exports("PublishClientState", EventCore.StateFeed.Publish)
exports("ClearClientState", EventCore.StateFeed.Clear)
