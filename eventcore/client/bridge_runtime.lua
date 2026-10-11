-- EventCore's paired, server-directed client action registry.
-- Only actions registered by a resource matching the server-approved owner are
-- executable; this is data/API dispatch, not a general remote-code facility.

EventCore = EventCore or {}
EventCore.Bridge = EventCore.Bridge or {}

local actions = {}
local MAX_ACTION_ID = 96
local MAX_PAYLOAD_BYTES = 16 * 1024
local MAX_RESULT_BYTES = 16 * 1024

local function validText(value, maxLength)
    return type(value) == "string" and #value > 0 and #value <= maxLength
end

local function validActionId(value)
    return validText(value, MAX_ACTION_ID)
        and value:match("^[a-z][a-z0-9_.-]*$") ~= nil
        and not value:find("..", 1, true)
end

local function validExportName(value)
    return validText(value, 64) and value:match("^[A-Za-z][A-Za-z0-9_]*$") ~= nil
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

local function currentCaller()
    local name = GetInvokingResource and GetInvokingResource() or nil
    local generation = GetInvokingResourceGeneration and GetInvokingResourceGeneration() or nil
    if not validText(name, 64) or type(generation) ~= "number" or generation < 1 then
        return nil, nil
    end
    return name, generation
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

function EventCore.Bridge.RegisterClientAction(actionId, handler, description)
    local resource, generation = currentCaller()
    if not resource then return false, "missing_export_caller" end
    if not validActionId(actionId) then return false, "invalid_action_id" end
    if not validExportName(handler) then return false, "invalid_handler" end
    pruneActions()
    local existing = actions[actionId]
    if existing and existing.resource ~= resource then return false, "action_already_registered" end
    actions[actionId] = {
        id = actionId,
        resource = resource,
        generation = generation,
        handler = handler,
        description = validText(description, 160) and description or "",
    }
    return true
end

function EventCore.Bridge.UnregisterClientAction(actionId)
    local resource = GetInvokingResource and GetInvokingResource() or nil
    local entry = actions[actionId]
    if not entry then return true end
    if not resource or entry.resource ~= resource then return false, "bridge_owner_mismatch" end
    actions[actionId] = nil
    return true
end

local function executeClientAction(actionId, owner, payload)
    if not validActionId(actionId) or not validText(owner, 64) or type(payload) ~= "table" then
        return nil, "invalid_request"
    end
    pruneActions()
    local entry = actions[actionId]
    if not entry or entry.resource ~= owner then return nil, "client_action_unavailable" end
    local encoded, encodeReason = encodeBounded(payload, MAX_PAYLOAD_BYTES)
    if not encoded then return nil, encodeReason end

    local pending, dispatchReason = Open77.exports.call(entry.resource, entry.handler, actionId, payload)
    if not pending then return nil, "client_handler_unavailable" end
    local awaitOk, response = pcall(function() return pending:await() end)
    if not awaitOk then
        print(string.format("[EventCore][WARN] Client adapter %s failed for %s: %s",
            entry.resource, actionId, tostring(response)))
        return nil, "client_handler_failed"
    end
    if type(response) ~= "table" or type(response.ok) ~= "boolean" then
        return nil, "invalid_client_response"
    end
    local resultEncoded = encodeBounded(response, MAX_RESULT_BYTES)
    if not resultEncoded then return nil, "invalid_client_response" end
    return response
end

if Open77 and Open77.net and type(Open77.net.register) == "function" then
    local ok, reason = Open77.net.register("bridge.execute", executeClientAction)
    if not ok then
        print("[EventCore][WARN] Client action callback registration failed: " .. tostring(reason))
    end
else
    print("[EventCore][WARN] Open77 client callbacks unavailable; server-directed client actions are disabled.")
end

exports("RegisterBridgeClientAction", EventCore.Bridge.RegisterClientAction)
exports("UnregisterBridgeClientAction", EventCore.Bridge.UnregisterClientAction)
