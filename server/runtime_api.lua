-- Versioned server service directory and the shared player-context read API.
-- Resource identity and generation come from Open77's export invocation context;
-- callers cannot register a service under another resource's name.

EventCore = EventCore or {}
EventCore.Services = EventCore.Services or {}

local services = {}
local MAX_SERVICES = 64
local MAX_METHODS = 32
local MAX_EVENTS = 32
local CORE_SERVICE_ID = "eventcore.runtime"

local function validText(value, maxLength)
    return type(value) == "string" and #value > 0 and #value <= maxLength
end

local function validIdentifier(value)
    return validText(value, 64) and value:match("^[a-z][a-z0-9_.-]*$") ~= nil
end

local function validMethod(value)
    return validText(value, 64) and value:match("^[A-Za-z][A-Za-z0-9_]*$") ~= nil
end

local function validVersion(value)
    return validText(value, 32) and value:match("^%d+%.%d+%.%d+[%w%.%+%-]*$") ~= nil
end

local function copyNames(values, validator, maxCount)
    if type(values) ~= "table" then return nil, "expected_array" end
    local count = #values
    if count > maxCount then return nil, "too_many_entries" end
    local keyCount = 0
    for key in pairs(values) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > count then
            return nil, "expected_array"
        end
        keyCount = keyCount + 1
    end
    if keyCount ~= count then return nil, "expected_array" end

    local copied, seen = {}, {}
    for index = 1, count do
        local value = values[index]
        if not validator(value) then return nil, "invalid_entry" end
        if seen[value] then return nil, "duplicate_entry" end
        seen[value] = true
        copied[index] = value
    end
    return copied
end

local function currentCaller()
    local name = GetInvokingResource and GetInvokingResource() or nil
    local generation = GetInvokingResourceGeneration and GetInvokingResourceGeneration() or nil
    if not validText(name, 64) or type(generation) ~= "number" or generation < 1 then
        return nil, nil
    end
    return name, generation
end

local function pruneStale()
    if not (Open77 and Open77.resource and Open77.resource.generation) then return end
    for serviceId, entry in pairs(services) do
        local ok, generation = pcall(Open77.resource.generation, entry.resource)
        if not ok or type(generation) ~= "number" or generation == 0 or generation ~= entry.generation then
            services[serviceId] = nil
        end
    end
end

local function descriptorCopy(entry)
    local methods, events = {}, {}
    for index, name in ipairs(entry.methods) do methods[index] = name end
    for index, name in ipairs(entry.events) do events[index] = name end
    return {
        id = entry.id,
        version = entry.version,
        resource = entry.resource,
        apiVersion = entry.apiVersion,
        methods = methods,
        events = events,
        description = entry.description,
    }
end

--- Register a provider's serializable contract. The provider is inferred from
--- Open77's export context; it is never accepted as a caller-supplied argument.
function EventCore.Services.Register(definition)
    local resource, generation = currentCaller()
    if not resource then return false, "missing_export_caller" end
    if type(definition) ~= "table" then return false, "invalid_definition" end
    if not validIdentifier(definition.id) then return false, "invalid_service_id" end
    if definition.id == CORE_SERVICE_ID then return false, "reserved_service_id" end
    if not validVersion(definition.version) then return false, "invalid_service_version" end
    if type(definition.apiVersion) ~= "number" or definition.apiVersion < 1
        or definition.apiVersion % 1 ~= 0 then
        return false, "invalid_api_version"
    end

    local methods, methodError = copyNames(definition.methods, validMethod, MAX_METHODS)
    if not methods then return false, "invalid_methods:" .. methodError end
    local events, eventError = copyNames(definition.events or {}, function(value)
        return validText(value, 128) and value:match("^[a-zA-Z0-9:_%.%-]+$") ~= nil
    end, MAX_EVENTS)
    if not events then return false, "invalid_events:" .. eventError end

    pruneStale()
    local existing = services[definition.id]
    if existing and existing.resource ~= resource then
        return false, "service_already_registered"
    end
    if not existing and #EventCore.Services.List() >= MAX_SERVICES then
        return false, "service_catalog_full"
    end

    services[definition.id] = {
        id = definition.id,
        version = definition.version,
        resource = resource,
        generation = generation,
        apiVersion = definition.apiVersion,
        methods = methods,
        events = events,
        description = validText(definition.description, 160) and definition.description or "",
    }
    return true
end

--- Remove a provider contract only when called by its owning resource.
function EventCore.Services.Unregister(serviceId)
    local resource = currentCaller()
    local entry = services[serviceId]
    if not entry then return true end
    if not resource or entry.resource ~= resource then return false, "service_owner_mismatch" end
    services[serviceId] = nil
    return true
end

--- Return a detached, sorted, serializable view of the active service catalog.
function EventCore.Services.List()
    pruneStale()
    local result = {
        {
            id = CORE_SERVICE_ID,
            version = EventCore.VERSION,
            resource = "eventcore",
            apiVersion = EventCore.API_VERSION,
            methods = {
                "GetRuntimeInfo", "GetServiceCatalog", "GetPlayerContext", "GetPlayerObservers",
                "IsAdmin", "GetPlayerRoles", "GetOnlineAdmins",
                "RegisterService", "UnregisterService", "AllowClientEvent", "Emit", "EmitClient",
                "PublishClientState", "ClearClientState",
                "BroadcastClient", "PersistEvent", "GetPersistedEvent", "FindPersistedEvents",
                "PersistenceStatus", "ExposeEvent", "SavePlayerState", "LoadPlayerState",
                "DeletePlayerState", "SaveInventoryState", "LoadInventoryState", "SaveOutfitCode",
                "LoadOutfitCode",
            },
            events = {},
            description = "Runtime capabilities and trusted player/scope context.",
        },
    }
    for _, entry in pairs(services) do result[#result + 1] = descriptorCopy(entry) end
    table.sort(result, function(left, right) return left.id < right.id end)
    return result
end

local function trustedCaller()
    local resource = GetInvokingResource and GetInvokingResource() or nil
    return resource, EventCore.Persistence
        and EventCore.Persistence.IsTrustedCaller(resource) == true
end

--- Return public runtime/build information and the current provider catalog.
function EventCore.GetRuntimeInfo()
    return {
        version = EventCore.VERSION,
        apiVersion = EventCore.API_VERSION,
        capabilities = { "events", "service_catalog", "player_context", "player_scope", "persistence", "client_state_feed_v1", "acl_role_read" },
        services = EventCore.Services.List(),
    }
end

--- Read verified identity and the latest server position for the current session.
--- Restricted to trusted server resources; never includes secrets or native handles.
function EventCore.GetPlayerContext(playerId)
    local caller, trusted = trustedCaller()
    if not trusted then return nil, "resource_not_trusted:" .. tostring(caller or "unknown") end
    playerId = tonumber(playerId)
    if not playerId or playerId < 1 or playerId % 1 ~= 0 then return nil, "invalid_player_id" end
    if not (Open77 and Open77.players and Open77.players.identity and Open77.players.position) then
        return nil, "player_api_unavailable"
    end

    local identityOk, identity = pcall(Open77.players.identity, playerId)
    local positionOk, position = pcall(Open77.players.position, playerId)
    if not identityOk or type(identity) ~= "table" then return nil, "player_not_found" end
    if not positionOk or type(position) ~= "table" then return nil, "position_unavailable" end

    local identityType, identityId
    if type(identity.license) == "string" and identity.license ~= "" then
        identityType, identityId = "license", identity.license
    elseif type(identity.userId) == "string" and identity.userId ~= "" then
        identityType, identityId = "userId", identity.userId
    else
        return nil, "stable_identity_unavailable"
    end

    local x, y, z = tonumber(position.x), tonumber(position.y), tonumber(position.z)
    if not x or not y or not z or x ~= x or y ~= y or z ~= z
        or x == math.huge or y == math.huge or z == math.huge
        or x == -math.huge or y == -math.huge or z == -math.huge then
        return nil, "position_unavailable"
    end

    return {
        playerId = playerId,
        identityType = identityType,
        identityId = identityId,
        displayName = type(identity.name) == "string" and identity.name or "",
        position = { x = x, y = y, z = z },
        routingBucket = tonumber(position.bucket) or 0,
    }
end

--- Return the native-scope viewers for one player, for proximity-aware output.
function EventCore.GetPlayerObservers(playerId)
    local caller, trusted = trustedCaller()
    if not trusted then return nil, "resource_not_trusted:" .. tostring(caller or "unknown") end
    playerId = tonumber(playerId)
    if not playerId or playerId < 1 or playerId % 1 ~= 0 then return nil, "invalid_player_id" end
    if not (Open77 and Open77.players and Open77.players.observers) then
        return nil, "observer_api_unavailable"
    end
    local identityOk, identity = pcall(Open77.players.identity, playerId)
    if not identityOk or type(identity) ~= "table" then
        return nil, "player_not_found"
    end
    local queryOk, observers = pcall(Open77.players.observers, playerId)
    if not queryOk then return nil, "observer_query_failed" end
    if type(observers) ~= "table" then return nil, "observer_query_failed" end

    local result = {}
    for _, observerId in ipairs(observers) do
        observerId = tonumber(observerId)
        if observerId and observerId > 0 and observerId % 1 == 0 then result[#result + 1] = observerId end
    end
    table.sort(result)
    return result
end

exports("GetRuntimeInfo", EventCore.GetRuntimeInfo)
exports("RegisterService", EventCore.Services.Register)
exports("UnregisterService", EventCore.Services.Unregister)
exports("GetServiceCatalog", EventCore.Services.List)
exports("GetPlayerContext", EventCore.GetPlayerContext)
exports("GetPlayerObservers", EventCore.GetPlayerObservers)
