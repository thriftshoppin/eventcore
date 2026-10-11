-- EventCore's paired typed client/server action bridge.
-- Client requests are never grants; the owning domain resource remains
-- responsible for gameplay validation and authorization.

EventCore = EventCore or {}
EventCore.Bridge = EventCore.Bridge or {}

local actions = {}
local rateWindows = {}
local requestResults = {}
local MAX_ACTIONS = 256
local MAX_ACTION_ID = 96
local MAX_PAYLOAD_BYTES = 16 * 1024
local MAX_RESULT_BYTES = 16 * 1024
local DEFAULT_RATE_COUNT = 12
local DEFAULT_RATE_WINDOW_MS = 10000
local MAX_REQUEST_ID = 96
local MAX_CACHED_REQUESTS_PER_PLAYER = 64
local REQUEST_RESULT_TTL_MS = 120000
local consumeRate
local callbackState = "initializing"

local function debugLog(eventName, resourceName, actionId, playerId)
    if EventCore.BridgeDebug ~= true then return end
    local details = { "event=" .. tostring(eventName) }
    if resourceName then details[#details + 1] = "resource=" .. tostring(resourceName) end
    if actionId then details[#details + 1] = "action=" .. tostring(actionId) end
    if playerId then details[#details + 1] = "player=" .. tostring(playerId) end
    print("[EventCore][bridge] " .. table.concat(details, " "))
end

local function validText(value, maxLength)
    return type(value) == "string" and #value > 0 and #value <= maxLength
end

local function validActionId(value)
    return validText(value, MAX_ACTION_ID)
        and value:match("^[a-z][a-z0-9_.-]*$") ~= nil
        and not value:find("..", 1, true)
end

local function validRequestId(value)
    return validText(value, MAX_REQUEST_ID)
        and value:match("^[%w][%w_.:-]*$") ~= nil
end

local function validExportName(value)
    return validText(value, 64) and value:match("^[A-Za-z][A-Za-z0-9_]*$") ~= nil
end

local function currentCaller()
    local name = GetInvokingResource and GetInvokingResource() or nil
    local generation = GetInvokingResourceGeneration and GetInvokingResourceGeneration() or nil
    if not validText(name, 64) or type(generation) ~= "number" or generation < 1 then
        return nil, nil
    end
    return name, generation
end

local function declaresEventCoreDependency(resourceName)
    if not (Open77 and Open77.resource and type(Open77.resource.metadata) == "function") then
        return false
    end
    local ok, dependencies = pcall(Open77.resource.metadata, resourceName, "dependencies")
    if not ok or type(dependencies) ~= "table" then return false end
    for _, dependency in pairs(dependencies) do
        if type(dependency) == "string" then
            local dependencyName = dependency:match("^%s*([^%s]+)")
            if dependencyName == "eventcore" then return true end
        elseif type(dependency) == "table" and dependency.name == "eventcore" then
            return true
        end
    end
    return false
end

local function encodeBounded(value, limit)
    if not (Open77 and Open77.json and type(Open77.json.encode) == "function") then
        return nil, "json_codec_unavailable"
    end
    local ok, encoded, reason = pcall(Open77.json.encode, value)
    if not ok or type(encoded) ~= "string" then return nil, reason or "invalid_payload" end
    if #encoded > limit then return nil, "payload_too_large" end
    return encoded
end

local function pruneActions()
    if not (Open77 and Open77.resource and type(Open77.resource.generation) == "function") then return end
    for actionId, entry in pairs(actions) do
        local ok, generation = pcall(Open77.resource.generation, entry.resource)
        if not ok or type(generation) ~= "number" or generation == 0 or generation ~= entry.generation then
            actions[actionId] = nil
        end
    end
end

local function actionCount()
    local count = 0
    for _ in pairs(actions) do count = count + 1 end
    return count
end

--- Register a named client-originated action for a reviewed server resource.
--- The action handler export must return { ok = boolean, ... } and independently
--- enforce its domain permissions and business rules.
function EventCore.Bridge.RegisterAction(actionId, definition)
    local resource, generation = currentCaller()
    if not resource then return false, "missing_export_caller" end
    if not (EventCore.BridgeWhitelist and EventCore.BridgeWhitelist[resource] == true) then
        return false, "bridge_resource_not_whitelisted"
    end
    if not declaresEventCoreDependency(resource) then return false, "eventcore_dependency_required" end
    if not validActionId(actionId) then return false, "invalid_action_id" end
    if type(definition) ~= "table" or not validExportName(definition.handler) then
        return false, "invalid_action_definition"
    end

    local maxPayloadBytes = tonumber(definition.maxPayloadBytes) or MAX_PAYLOAD_BYTES
    local maxCalls = tonumber(definition.maxCalls) or DEFAULT_RATE_COUNT
    local windowMs = tonumber(definition.windowMs) or DEFAULT_RATE_WINDOW_MS
    if maxPayloadBytes < 1 or maxPayloadBytes > MAX_PAYLOAD_BYTES or maxPayloadBytes % 1 ~= 0 then
        return false, "invalid_payload_limit"
    end
    if maxCalls < 1 or maxCalls > 120 or maxCalls % 1 ~= 0 then return false, "invalid_rate_limit" end
    if windowMs < 1000 or windowMs > 60000 or windowMs % 1 ~= 0 then return false, "invalid_rate_window" end

    pruneActions()
    local existing = actions[actionId]
    if existing and existing.resource ~= resource then return false, "action_already_registered" end
    if not existing and actionCount() >= MAX_ACTIONS then return false, "bridge_catalog_full" end

    actions[actionId] = {
        id = actionId,
        resource = resource,
        generation = generation,
        handler = definition.handler,
        clientHandler = definition.clientHandler == true,
        maxPayloadBytes = maxPayloadBytes,
        maxCalls = maxCalls,
        windowMs = windowMs,
        description = validText(definition.description, 160) and definition.description or "",
    }
    rateWindows[actionId] = nil
    debugLog("action_registered", resource, actionId)
    return true
end

--- Ask the same registered domain provider's client half to apply a typed
--- client-only action. The provider must have opted in at registration.
function EventCore.Bridge.CallClientAction(playerId, actionId, payload, timeoutMs)
    local caller = GetInvokingResource and GetInvokingResource() or nil
    local callerGeneration = GetInvokingResourceGeneration and GetInvokingResourceGeneration() or nil
    playerId = tonumber(playerId)
    if not playerId or playerId < 1 or playerId % 1 ~= 0 then return nil, "invalid_player_id" end
    if not validActionId(actionId) then return nil, "invalid_action_id" end
    if type(payload) ~= "table" then return nil, "invalid_payload" end

    pruneActions()
    local entry = actions[actionId]
    if not entry then return nil, "action_unavailable" end
    if caller ~= entry.resource or callerGeneration ~= entry.generation then
        return nil, "bridge_owner_mismatch"
    end
    if not entry.clientHandler then return nil, "client_action_not_registered" end
    local encoded, encodeReason = encodeBounded(payload, entry.maxPayloadBytes)
    if not encoded then return nil, encodeReason end
    if not consumeRate(playerId, entry) then return nil, "rate_limited" end

    if type(timeoutMs) ~= "number" then timeoutMs = 5000 end
    if timeoutMs < 100 or timeoutMs > 30000 or timeoutMs % 1 ~= 0 then
        return nil, "invalid_timeout"
    end
    if not (Open77 and Open77.net and type(Open77.net.callClientAwait) == "function") then
        return nil, "client_callbacks_unavailable"
    end

    local ok, response, reason = pcall(Open77.net.callClientAwait, playerId, {
        resource = "eventcore",
        name = "bridge.execute",
        timeout = timeoutMs,
    }, actionId, entry.resource, payload)
    if not ok then
        print(string.format("[EventCore][WARN] Client bridge action %s failed for player %d: %s",
            actionId, playerId, tostring(response)))
        return nil, "client_action_failed"
    end
    if type(response) ~= "table" or type(response.ok) ~= "boolean" then
        return nil, reason or "invalid_client_response"
    end
    local resultEncoded = encodeBounded(response, MAX_RESULT_BYTES)
    if not resultEncoded then return nil, "invalid_client_response" end
    debugLog(response.ok and "client_action_ok" or "client_action_refused", entry.resource, actionId, playerId)
    return response
end

function EventCore.Bridge.UnregisterAction(actionId)
    local resource = GetInvokingResource and GetInvokingResource() or nil
    local entry = actions[actionId]
    if not entry then return true end
    if not resource or entry.resource ~= resource then return false, "bridge_owner_mismatch" end
    actions[actionId] = nil
    rateWindows[actionId] = nil
    debugLog("action_unregistered", resource, actionId)
    return true
end

function EventCore.Bridge.ListActions()
    pruneActions()
    local result = {}
    for _, entry in pairs(actions) do
        result[#result + 1] = {
            id = entry.id,
            resource = entry.resource,
            description = entry.description,
            maxPayloadBytes = entry.maxPayloadBytes,
            maxCalls = entry.maxCalls,
            windowMs = entry.windowMs,
            clientHandler = entry.clientHandler,
        }
    end
    table.sort(result, function(left, right) return left.id < right.id end)
    return result
end

function EventCore.Bridge.GetStatus()
    local listed = EventCore.Bridge.ListActions()
    return {
        networkCallback = callbackState,
        debugLogging = EventCore.BridgeDebug == true,
        actionCount = #listed,
        actions = listed,
    }
end

local function nowMs()
    if type(GetGameTimer) == "function" then
        local value = GetGameTimer()
        if type(value) == "number" then return value end
    end
    return math.floor(os.clock() * 1000)
end

consumeRate = function(source, entry)
    local byPlayer = rateWindows[entry.id]
    if not byPlayer then
        byPlayer = {}
        rateWindows[entry.id] = byPlayer
    end
    local playerId = tostring(source)
    local now = nowMs()
    local timestamps = byPlayer[playerId] or {}
    local first = 1
    while first <= #timestamps and now - timestamps[first] >= entry.windowMs do
        first = first + 1
    end
    if first > 1 then
        local compacted = {}
        for index = first, #timestamps do compacted[#compacted + 1] = timestamps[index] end
        timestamps = compacted
    end
    if #timestamps >= entry.maxCalls then
        byPlayer[playerId] = timestamps
        return false
    end
    timestamps[#timestamps + 1] = now
    byPlayer[playerId] = timestamps
    return true
end

local function handleRequest(source, request)
    if type(source) ~= "number" or source < 1 or source % 1 ~= 0 then return nil, "invalid_player" end
    if type(request) ~= "table" or request.protocolVersion ~= 2
        or not validRequestId(request.requestId)
        or not validActionId(request.action) or type(request.payload) ~= "table" then
        return nil, "invalid_request"
    end

    pruneActions()
    local entry = actions[request.action]
    if not entry then return nil, "action_unavailable" end
    local encoded, encodeReason = encodeBounded(request.payload, entry.maxPayloadBytes)
    if not encoded then return nil, encodeReason end

    -- Idempotency is scoped to the authenticated player and request ID. A
    -- retry with the same body returns the original result; reusing the ID for
    -- different content is rejected. Entries are bounded and short-lived.
    local playerKey = tostring(source)
    local playerRequests = requestResults[playerKey]
    if not playerRequests then
        playerRequests = { entries = {}, order = {} }
        requestResults[playerKey] = playerRequests
    end
    local now = nowMs()
    local retained = {}
    for _, requestId in ipairs(playerRequests.order) do
        local cached = playerRequests.entries[requestId]
        if cached and (cached.state == "running" or now - cached.createdAt < REQUEST_RESULT_TTL_MS) then
            retained[#retained + 1] = requestId
        else
            playerRequests.entries[requestId] = nil
        end
    end
    playerRequests.order = retained

    local prior = playerRequests.entries[request.requestId]
    if prior then
        if prior.action ~= request.action or prior.payload ~= encoded then
            return nil, "request_id_reused"
        end
        if prior.state == "failed" then return nil, prior.failureReason end
        if prior.state == "complete" then
            local decoded, response = pcall(Open77.json.decode, prior.response)
            if decoded and type(response) == "table" then
                debugLog("request_replayed", entry.resource, entry.id, source)
                return response
            end
            playerRequests.entries[request.requestId] = nil
            return nil, "cached_response_unavailable"
        end
        return nil, "request_in_progress"
    end
    if not consumeRate(source, entry) then return nil, "rate_limited" end
    if #playerRequests.order >= MAX_CACHED_REQUESTS_PER_PLAYER then
        return nil, "request_cache_full"
    end
    local requestRecord = {
        action = request.action,
        payload = encoded,
        state = "running",
        createdAt = now,
    }
    playerRequests.entries[request.requestId] = requestRecord
    playerRequests.order[#playerRequests.order + 1] = request.requestId

    local pending, dispatchReason = Open77.exports.call(entry.resource, entry.handler,
        source, entry.id, request.payload)
    if not pending then
        print(string.format("[EventCore][WARN] Bridge provider %s unavailable for %s: %s",
            entry.resource, entry.id, tostring(dispatchReason)))
        playerRequests.entries[request.requestId] = nil
        return nil, "provider_unavailable"
    end

    local awaitOk, response, responseReason = pcall(function() return pending:await() end)
    if not awaitOk then
        print(string.format("[EventCore][WARN] Bridge provider %s failed for %s: %s",
            entry.resource, entry.id, tostring(response)))
        requestRecord.state = "failed"
        requestRecord.failureReason = "provider_failed"
        return nil, "provider_failed"
    end
    if type(response) ~= "table" or type(response.ok) ~= "boolean" then
        print(string.format("[EventCore][WARN] Bridge provider %s returned invalid response for %s",
            entry.resource, entry.id))
        requestRecord.state = "failed"
        requestRecord.failureReason = "invalid_provider_response"
        return nil, "invalid_provider_response"
    end
    local resultEncoded = encodeBounded(response, MAX_RESULT_BYTES)
    if not resultEncoded then
        requestRecord.state = "failed"
        requestRecord.failureReason = "invalid_provider_response"
        return nil, "invalid_provider_response"
    end
    requestRecord.state = "complete"
    requestRecord.response = resultEncoded
    debugLog(response.ok and "request_ok" or "request_refused", entry.resource, entry.id, source)
    return response
end

if AddEventHandler then
    AddEventHandler("playerDropped", function()
        local playerId = tonumber(source)
        if not playerId then return end
        local key = tostring(playerId)
        for _, byPlayer in pairs(rateWindows) do byPlayer[key] = nil end
        requestResults[key] = nil
    end)
end

if Open77 and Open77.net and type(Open77.net.register) == "function" then
    local ok, reason = Open77.net.register("bridge.request", handleRequest)
    if not ok then
        callbackState = "failed: " .. tostring(reason)
        print("[EventCore][WARN] Client bridge callback registration failed: " .. tostring(reason))
    else
        callbackState = "ready"
        debugLog("network_callback_ready")
    end
else
    callbackState = "unavailable"
    print("[EventCore][WARN] Open77 network callbacks unavailable; client bridge is disabled.")
end

exports("RegisterBridgeAction", EventCore.Bridge.RegisterAction)
exports("UnregisterBridgeAction", EventCore.Bridge.UnregisterAction)
exports("ListBridgeActions", EventCore.Bridge.ListActions)
exports("GetBridgeStatus", EventCore.Bridge.GetStatus)
exports("CallBridgeClientAction", EventCore.Bridge.CallClientAction)
