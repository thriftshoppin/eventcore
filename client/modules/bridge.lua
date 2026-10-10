-- Small client-side library for EventCore's namespaced typed request bridge.
-- Import with: require('@eventcore/client.modules.bridge')

local Bridge = { PROTOCOL_VERSION = 2 }
local MAX_ACTION_ID = 96
local MAX_PAYLOAD_BYTES = 16 * 1024
local requestSequence = 0

local function nextRequestId()
    requestSequence = requestSequence + 1
    local wall = type(os) == "table" and type(os.time) == "function" and os.time() or 0
    local timer = type(GetGameTimer) == "function" and GetGameTimer() or 0
    return string.format("c-%d-%s-%d", wall, tostring(timer), requestSequence)
end

local function validActionId(value)
    return type(value) == "string" and #value > 0 and #value <= MAX_ACTION_ID
        and value:match("^[a-z][a-z0-9_.-]*$") ~= nil
        and not value:find("..", 1, true)
end

local function encodeBounded(payload)
    if not (Open77 and Open77.json and type(Open77.json.encode) == "function") then
        return false, "json_codec_unavailable"
    end
    local ok, encoded = pcall(Open77.json.encode, payload)
    if not ok or type(encoded) ~= "string" then return false, "invalid_payload" end
    if #encoded > MAX_PAYLOAD_BYTES then return false, "payload_too_large" end
    return true
end

--- Queue a request to a registered EventCore server action.
--- Returns an Open77.Promise; await it from a managed CreateThread.
function Bridge.request(actionId, payload, timeoutMs, requestId)
    if not validActionId(actionId) then return nil, "invalid_action_id" end
    if type(payload) ~= "table" then return nil, "invalid_payload" end
    local valid, reason = encodeBounded(payload)
    if not valid then return nil, reason end
    if not (Open77 and Open77.net and type(Open77.net.call) == "function") then
        return nil, "network_callbacks_unavailable"
    end
    requestId = requestId or nextRequestId()
    if type(requestId) ~= "string" or #requestId < 1 or #requestId > 96
        or not requestId:match("^[%w][%w_.:-]*$") then
        return nil, "invalid_request_id"
    end

    local options = {
        resource = "eventcore",
        name = "bridge.request",
    }
    if timeoutMs ~= nil then options.timeout = timeoutMs end
    return Open77.net.call(options, {
        protocolVersion = Bridge.PROTOCOL_VERSION,
        requestId = requestId,
        action = actionId,
        payload = payload,
    })
end

--- Convenience form for use only inside a managed scheduler coroutine.
function Bridge.requestAwait(actionId, payload, timeoutMs, requestId)
    local pending, reason = Bridge.request(actionId, payload, timeoutMs, requestId)
    if not pending then return nil, reason end
    return pending:await()
end

--- Create an ID for callers that may retry the same logical request. Reuse it
--- only with the same action and payload; the server rejects mismatched reuse.
Bridge.newRequestId = nextRequestId

--- Register a named client adapter export for server-directed typed actions.
--- Registration has no authority by itself; the matching server provider must
--- register the action with clientHandler = true and invoke it explicitly.
function Bridge.registerClientAction(actionId, handlerName, description)
    if not validActionId(actionId) then return nil, "invalid_action_id" end
    if type(handlerName) ~= "string" or #handlerName > 64
        or not handlerName:match("^[A-Za-z][A-Za-z0-9_]*$") then
        return nil, "invalid_handler"
    end
    if not (Open77 and Open77.exports and type(Open77.exports.call) == "function") then
        return nil, "exports_unavailable"
    end
    return Open77.exports.call("eventcore", "RegisterBridgeClientAction", actionId, handlerName, description)
end

function Bridge.unregisterClientAction(actionId)
    if not validActionId(actionId) then return nil, "invalid_action_id" end
    if not (Open77 and Open77.exports and type(Open77.exports.call) == "function") then
        return nil, "exports_unavailable"
    end
    return Open77.exports.call("eventcore", "UnregisterBridgeClientAction", actionId)
end

return Bridge
