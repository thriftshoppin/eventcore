--[[
    EventCore - Server-only SQL persistence
    EventCore requests access to Open77's server-wide SQL bridge. No SQL API is loaded by clients.
]]

EventCore = EventCore or {}
EventCore.Persistence = EventCore.Persistence or {}

local TABLE_NAME = "eventcore_events"
local MAX_PAYLOAD_BYTES = 48 * 1024
local MAX_QUEUE_SIZE = 1000
local MAX_READ_LIMIT = 100
local MAX_STORAGE_BATCH = 32
local MAX_STORAGE_BATCH_BYTES = 48 * 1024
local STORAGE_API_VERSION = 1

-- Only these server resources may call the persistence exports. Add trusted
-- server-side consumers here when they are installed on the same server.
local trustedResources = {
    rpcore = true
}

-- Storage is opt-in by resource in server/whitelist.lua. The caller's
-- resource name comes from GetInvokingResource and becomes the ownership key.
local storageResources = EventCore.Whitelist or {}

local state = "waiting_for_database"
local writeQueue = {}
local droppedQueuedWrites = 0
local workerStarted = false
local exposedEventNames = {}

local CREATE_SCHEMA = [[
CREATE TABLE IF NOT EXISTS eventcore_events (
    event_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    event_name VARCHAR(128) NOT NULL,
    source_id INT NOT NULL DEFAULT 0,
    source_kind VARCHAR(16) NOT NULL,
    event_data LONGTEXT NOT NULL,
    cancelled TINYINT(1) NOT NULL DEFAULT 0,
    cancel_reason VARCHAR(255) NOT NULL DEFAULT '',
    occurred_ms BIGINT UNSIGNED NOT NULL DEFAULT 0,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (event_id),
    KEY idx_eventcore_name_id (event_name, event_id),
    KEY idx_eventcore_source_id (source_id, event_id),
    CONSTRAINT chk_eventcore_event_data_json CHECK (JSON_VALID(event_data))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local CREATE_PLAYER_STATE_SCHEMA = [[
CREATE TABLE IF NOT EXISTS eventcore_player_state (
    identity_type VARCHAR(16) NOT NULL,
    identity_id VARCHAR(64) NOT NULL,
    namespace VARCHAR(64) NOT NULL,
    state_key VARCHAR(128) NOT NULL,
    state_json LONGTEXT NOT NULL,
    revision BIGINT UNSIGNED NOT NULL DEFAULT 1,
    updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (identity_type, identity_id, namespace, state_key),
    KEY idx_eventcore_state_updated (updated_at),
    CONSTRAINT chk_eventcore_state_json CHECK (JSON_VALID(state_json))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local CREATE_RESOURCE_STATE_SCHEMA = [[
CREATE TABLE IF NOT EXISTS eventcore_resource_state (
    resource_name VARCHAR(64) NOT NULL,
    collection VARCHAR(64) NOT NULL,
    state_key VARCHAR(128) NOT NULL,
    state_json LONGTEXT NOT NULL,
    revision BIGINT UNSIGNED NOT NULL DEFAULT 1,
    updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (resource_name, collection, state_key),
    KEY idx_eventcore_resource_state_updated (resource_name, updated_at),
    CONSTRAINT chk_eventcore_resource_state_json CHECK (JSON_VALID(state_json))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local CREATE_RESOURCE_PLAYER_STATE_SCHEMA = [[
CREATE TABLE IF NOT EXISTS eventcore_resource_player_state (
    resource_name VARCHAR(64) NOT NULL,
    identity_type VARCHAR(16) NOT NULL,
    identity_id VARCHAR(64) NOT NULL,
    collection VARCHAR(64) NOT NULL,
    state_key VARCHAR(128) NOT NULL,
    state_json LONGTEXT NOT NULL,
    revision BIGINT UNSIGNED NOT NULL DEFAULT 1,
    updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (resource_name, identity_type, identity_id, collection, state_key),
    KEY idx_eventcore_resource_player_updated (resource_name, updated_at),
    CONSTRAINT chk_eventcore_resource_player_state_json CHECK (JSON_VALID(state_json))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local UPSERT_RESOURCE_STATE = [[
INSERT INTO eventcore_resource_state
    (resource_name, collection, state_key, state_json, revision)
VALUES (?, ?, ?, ?, 1)
ON DUPLICATE KEY UPDATE
    state_json = VALUES(state_json),
    revision = revision + 1,
    updated_at = CURRENT_TIMESTAMP(3)
]]

local DELETE_RESOURCE_STATE = [[
DELETE FROM eventcore_resource_state
WHERE resource_name = ? AND collection = ? AND state_key = ?
]]

local UPSERT_RESOURCE_PLAYER_STATE = [[
INSERT INTO eventcore_resource_player_state
    (resource_name, identity_type, identity_id, collection, state_key, state_json, revision)
VALUES (?, ?, ?, ?, ?, ?, 1)
ON DUPLICATE KEY UPDATE
    state_json = VALUES(state_json),
    revision = revision + 1,
    updated_at = CURRENT_TIMESTAMP(3)
]]

local DELETE_RESOURCE_PLAYER_STATE = [[
DELETE FROM eventcore_resource_player_state
WHERE resource_name = ? AND identity_type = ? AND identity_id = ? AND collection = ? AND state_key = ?
]]

local function encodeData(data)
    if not Open77 or not Open77.json or type(Open77.json.encode) ~= "function" then
        return nil, "json_codec_unavailable"
    end

    local ok, encoded, reason = pcall(Open77.json.encode, data == nil and {} or data)
    if not ok then
        return nil, tostring(encoded)
    end
    if type(encoded) ~= "string" then
        return nil, reason or "event_data_not_json_serializable"
    end
    if #encoded > MAX_PAYLOAD_BYTES then
        return nil, "event_data_too_large"
    end
    return encoded
end

local function normalizeSource(source)
    if type(source) == "number" and source > 0 and source % 1 == 0 then
        return source, "player"
    end
    -- Use 0 for server-originated records so positional SQL parameters never
    -- contain Lua nil holes (which can truncate a parameter array).
    return 0, "server"
end

local function insertEncoded(eventName, encodedData, sourceId, sourceKind, cancelled, cancelReason, occurredMs)
    return MySQL.insert.await([[
        INSERT INTO eventcore_events
            (event_name, source_id, source_kind, event_data, cancelled, cancel_reason, occurred_ms)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        eventName,
        sourceId,
        sourceKind,
        encodedData,
        cancelled and 1 or 0,
        cancelReason or "",
        occurredMs or 0
    })
end

local function writeWorker()
    while true do
        if state == "ready" and #writeQueue > 0 then
            local record = table.remove(writeQueue, 1)
            local ok, result = pcall(insertEncoded,
                record.name, record.data, record.sourceId, record.sourceKind,
                record.cancelled, record.cancelReason, record.occurredMs)

            if not ok then
                record.attempts = record.attempts + 1
                if record.attempts < 3 and #writeQueue < MAX_QUEUE_SIZE then
                    table.insert(writeQueue, 1, record)
                    Wait(1000)
                else
                    print(string.format("[EventCore][ERROR] Dropped persisted event '%s' after SQL failure: %s",
                        record.name, tostring(result)))
                end
            elseif type(result) ~= "number" then
                print(string.format("[EventCore][ERROR] SQL insert returned no event ID for '%s'", record.name))
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end

local function startWorker()
    if workerStarted or type(CreateThread) ~= "function" then return end
    workerStarted = true
    CreateThread(writeWorker)
end

function EventCore.Persistence.Status()
    return {
        state = state,
        queuedWrites = #writeQueue,
        droppedQueuedWrites = droppedQueuedWrites,
        table = TABLE_NAME,
        storageApiVersion = STORAGE_API_VERSION,
        storageConsumers = (function()
            local count = 0
            for _ in pairs(storageResources) do count = count + 1 end
            return count
        end)(),
    }
end

--- Persist one JSON-compatible event and wait for its SQL insert to complete.
--- Call from a server-managed coroutine (for example CreateThread or an event handler).
function EventCore.Persistence.Persist(eventName, data, source, options)
    if state ~= "ready" then return nil, "persistence_" .. state end
    if type(eventName) ~= "string" or eventName == "" or #eventName > 128 then
        return nil, "invalid_event_name"
    end

    local encoded, encodeError = encodeData(data)
    if not encoded then return nil, encodeError end

    options = type(options) == "table" and options or {}
    local sourceId, sourceKind = normalizeSource(source)
    local reason = options.cancelReason ~= nil and tostring(options.cancelReason):sub(1, 255) or ""
    local occurredMs = tonumber(options.occurredMs)
    if not occurredMs or occurredMs < 0 or occurredMs ~= occurredMs or occurredMs == math.huge then
        occurredMs = 0
    else
        occurredMs = math.floor(occurredMs)
    end
    local ok, eventId = pcall(insertEncoded, eventName, encoded, sourceId, sourceKind,
        options.cancelled == true, reason, occurredMs)
    if not ok then return nil, tostring(eventId) end
    return eventId
end

--- Retrieve a persisted event by its numeric database ID.
function EventCore.Persistence.Get(eventId)
    if state ~= "ready" then return nil, "persistence_" .. state end
    eventId = tonumber(eventId)
    if not eventId or eventId < 1 or eventId % 1 ~= 0 then return nil, "invalid_event_id" end

    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT event_id, event_name, source_id, source_kind, event_data,
                   cancelled, cancel_reason, occurred_ms, created_at
            FROM eventcore_events WHERE event_id = ? LIMIT 1
        ]], { eventId })
    end)
    if not ok then return nil, tostring(row) end
    if not row then return nil, "not_found" end

    local decodedOk, data, decodeError = pcall(Open77.json.decode, row.event_data)
    if not decodedOk or data == nil then return nil, tostring(decodeError or data) end
    row.event_data = data
    row.cancelled = row.cancelled == true or tonumber(row.cancelled) == 1
    return row
end

--- List newest records first. Limit is clamped and beforeId enables pagination.
function EventCore.Persistence.Find(eventName, limit, beforeId)
    if state ~= "ready" then return nil, "persistence_" .. state end
    if eventName ~= nil and (type(eventName) ~= "string" or eventName == "" or #eventName > 128) then
        return nil, "invalid_event_name"
    end

    limit = math.floor(tonumber(limit) or 50)
    limit = math.max(1, math.min(limit, MAX_READ_LIMIT))
    if beforeId ~= nil then
        beforeId = tonumber(beforeId)
        if not beforeId or beforeId < 1 or beforeId % 1 ~= 0 then return nil, "invalid_event_id" end
    end

    local conditions, params = {}, {}
    if eventName then
        conditions[#conditions + 1] = "event_name = ?"
        params[#params + 1] = eventName
    end
    if beforeId then
        conditions[#conditions + 1] = "event_id < ?"
        params[#params + 1] = beforeId
    end

    local whereClause = #conditions > 0 and (" WHERE " .. table.concat(conditions, " AND ")) or ""
    params[#params + 1] = limit
    local sql = [[
        SELECT event_id, event_name, source_id, source_kind, event_data,
               cancelled, cancel_reason, occurred_ms, created_at
        FROM eventcore_events]] .. whereClause .. " ORDER BY event_id DESC LIMIT ?"

    local ok, rows = pcall(function() return MySQL.query.await(sql, params) end)
    if not ok then return nil, tostring(rows) end

    for _, row in ipairs(rows or {}) do
        local decodedOk, data, decodeError = pcall(Open77.json.decode, row.event_data)
        if not decodedOk or data == nil then
            return nil, "invalid_stored_json: " .. tostring(decodeError or data)
        end
        row.event_data = data
        row.cancelled = row.cancelled == true or tonumber(row.cancelled) == 1
    end
    return rows or {}
end

local function resolvePlayerIdentity(playerId)
    playerId = tonumber(playerId)
    if not playerId or playerId < 1 or playerId % 1 ~= 0 then
        return nil, nil, "invalid_player_id"
    end
    if not Open77 or not Open77.players or type(Open77.players.identifiers) ~= "function" then
        return nil, nil, "player_identity_api_unavailable"
    end

    local ok, identifiers, reason = pcall(Open77.players.identifiers, playerId)
    if not ok then return nil, nil, tostring(identifiers) end
    if type(identifiers) ~= "table" then return nil, nil, reason or "player_not_found" end

    -- license is the account-level key and follows a player across linked devices.
    -- Older compatible builds may expose only the persistent installation userId.
    if type(identifiers.license) == "string" and identifiers.license ~= "" then
        return "license", identifiers.license
    end
    local userId = identifiers.userId or identifiers.open77
    if type(userId) == "string" and userId ~= "" then
        return "userId", userId
    end
    return nil, nil, "persistent_player_identity_unavailable"
end

local function validateStorageAddress(collection, stateKey)
    if type(collection) ~= "string" or #collection < 1 or #collection > 64
        or not collection:match("^[%w][%w_.%-]*$") then
        return false, "invalid_collection"
    end
    if type(stateKey) ~= "string" or #stateKey < 1 or #stateKey > 128 then
        return false, "invalid_state_key"
    end
    return true
end

local function decodeStorageRow(row)
    if type(row) ~= "table" or type(row.state_json) ~= "string" then
        return nil, "invalid_stored_state"
    end
    local ok, value, reason = pcall(Open77.json.decode, row.state_json)
    if not ok or value == nil then return nil, "invalid_stored_json: " .. tostring(reason or value) end
    return value, nil, { revision = tonumber(row.revision) or 1, updatedAt = row.updated_at }
end

local function decodeStorageRows(rows)
    local result = {}
    for _, row in ipairs(rows or {}) do
        local value, reason, metadata = decodeStorageRow(row)
        if reason then return nil, reason end
        result[#result + 1] = {
            key = row.state_key,
            value = value,
            revision = metadata.revision,
            updatedAt = metadata.updatedAt,
        }
    end
    return result
end

local function auditStorageWrite(resourceName, operation, scope, collection, count)
    if type(EventCore.DispatchLocal) ~= "function" then return end
    pcall(EventCore.DispatchLocal, "eventcore.storage.write", {
        resource = resourceName,
        operation = operation,
        scope = scope,
        collection = collection,
        count = count or 1,
    }, 0)
end

local function storageReady()
    return state == "ready", state == "ready" and nil or ("persistence_" .. state)
end

local function validateResourceName(resourceName)
    if type(resourceName) ~= "string" or #resourceName < 1 or #resourceName > 64 then
        return false
    end
    if storageResources[resourceName] ~= true then return false end

    -- Storage consumers must also declare EventCore as a manifest dependency.
    -- This makes the integration visible in open77.lua and ensures load order;
    -- the explicit allowlist above remains the actual authorization gate.
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

local function playerStorageAddress(resourceName, playerId, collection, stateKey)
    if not validateResourceName(resourceName) then return nil, nil, "storage_caller_not_trusted" end
    local addressOk, addressReason = validateStorageAddress(collection, stateKey)
    if not addressOk then return nil, nil, addressReason end
    local identityType, identityId, identityReason = resolvePlayerIdentity(playerId)
    if not identityType then return nil, nil, identityReason end
    return identityType, identityId
end

--- Store a JSON document in the calling resource's private namespace.
function EventCore.Persistence.StoragePut(resourceName, collection, stateKey, value)
    if not validateResourceName(resourceName) then return false, "storage_caller_not_trusted" end
    local ready, unavailable = storageReady()
    if not ready then return false, unavailable end
    local addressOk, addressReason = validateStorageAddress(collection, stateKey)
    if not addressOk then return false, addressReason end
    local encoded, encodeReason = encodeData(value)
    if not encoded then return false, encodeReason end

    local ok, result = pcall(function()
        return MySQL.update.await(UPSERT_RESOURCE_STATE,
            { resourceName, collection, stateKey, encoded })
    end)
    if not ok then return false, tostring(result) end
    auditStorageWrite(resourceName, "put", "resource", collection)
    return true
end

function EventCore.Persistence.StorageGet(resourceName, collection, stateKey)
    if not validateResourceName(resourceName) then return nil, "storage_caller_not_trusted" end
    local ready, unavailable = storageReady()
    if not ready then return nil, unavailable end
    local addressOk, addressReason = validateStorageAddress(collection, stateKey)
    if not addressOk then return nil, addressReason end

    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT state_json, revision, updated_at
            FROM eventcore_resource_state
            WHERE resource_name = ? AND collection = ? AND state_key = ?
            LIMIT 1
        ]], { resourceName, collection, stateKey })
    end)
    if not ok then return nil, tostring(row) end
    if not row then return nil, "not_found" end
    return decodeStorageRow(row)
end

function EventCore.Persistence.StorageDelete(resourceName, collection, stateKey)
    if not validateResourceName(resourceName) then return false, "storage_caller_not_trusted" end
    local ready, unavailable = storageReady()
    if not ready then return false, unavailable end
    local addressOk, addressReason = validateStorageAddress(collection, stateKey)
    if not addressOk then return false, addressReason end

    local ok, result = pcall(function()
        return MySQL.update.await(DELETE_RESOURCE_STATE,
            { resourceName, collection, stateKey })
    end)
    if not ok then return false, tostring(result) end
    local deleted = (tonumber(result) or 0) > 0
    if deleted then auditStorageWrite(resourceName, "delete", "resource", collection) end
    return deleted
end

function EventCore.Persistence.StorageList(resourceName, collection, afterKey, limit)
    if not validateResourceName(resourceName) then return nil, "storage_caller_not_trusted" end
    local ready, unavailable = storageReady()
    if not ready then return nil, unavailable end
    if type(collection) ~= "string" or #collection < 1 or #collection > 64
        or not collection:match("^[%w][%w_.%-]*$") then
        return nil, "invalid_collection"
    end
    if afterKey ~= nil and (type(afterKey) ~= "string" or #afterKey > 128) then
        return nil, "invalid_cursor"
    end
    limit = tonumber(limit) or 50
    if limit % 1 ~= 0 or limit < 1 or limit > MAX_READ_LIMIT then return nil, "invalid_limit" end

    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT state_key, state_json, revision, updated_at
            FROM eventcore_resource_state
            WHERE resource_name = ? AND collection = ? AND state_key > ?
            ORDER BY state_key ASC LIMIT ?
        ]], { resourceName, collection, afterKey or "", limit })
    end)
    if not ok then return nil, tostring(rows) end
    return decodeStorageRows(rows)
end

function EventCore.Persistence.StoragePutPlayer(resourceName, playerId, collection, stateKey, value)
    local identityType, identityId, addressReason = playerStorageAddress(resourceName, playerId, collection, stateKey)
    if not identityType then return false, addressReason end
    local ready, unavailable = storageReady()
    if not ready then return false, unavailable end
    local encoded, encodeReason = encodeData(value)
    if not encoded then return false, encodeReason end

    local ok, result = pcall(function()
        return MySQL.update.await(UPSERT_RESOURCE_PLAYER_STATE,
            { resourceName, identityType, identityId, collection, stateKey, encoded })
    end)
    if not ok then return false, tostring(result) end
    auditStorageWrite(resourceName, "put", "player", collection)
    return true
end

function EventCore.Persistence.StorageGetPlayer(resourceName, playerId, collection, stateKey)
    local identityType, identityId, addressReason = playerStorageAddress(resourceName, playerId, collection, stateKey)
    if not identityType then return nil, addressReason end
    local ready, unavailable = storageReady()
    if not ready then return nil, unavailable end

    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT state_json, revision, updated_at
            FROM eventcore_resource_player_state
            WHERE resource_name = ? AND identity_type = ? AND identity_id = ?
              AND collection = ? AND state_key = ?
            LIMIT 1
        ]], { resourceName, identityType, identityId, collection, stateKey })
    end)
    if not ok then return nil, tostring(row) end
    if not row then return nil, "not_found" end
    return decodeStorageRow(row)
end

function EventCore.Persistence.StorageDeletePlayer(resourceName, playerId, collection, stateKey)
    local identityType, identityId, addressReason = playerStorageAddress(resourceName, playerId, collection, stateKey)
    if not identityType then return false, addressReason end
    local ready, unavailable = storageReady()
    if not ready then return false, unavailable end

    local ok, result = pcall(function()
        return MySQL.update.await(DELETE_RESOURCE_PLAYER_STATE,
            { resourceName, identityType, identityId, collection, stateKey })
    end)
    if not ok then return false, tostring(result) end
    local deleted = (tonumber(result) or 0) > 0
    if deleted then auditStorageWrite(resourceName, "delete", "player", collection) end
    return deleted
end

function EventCore.Persistence.StorageListPlayer(resourceName, playerId, collection, afterKey, limit)
    if not validateResourceName(resourceName) then return nil, "storage_caller_not_trusted" end
    if type(collection) ~= "string" or #collection < 1 or #collection > 64
        or not collection:match("^[%w][%w_.%-]*$") then
        return nil, "invalid_collection"
    end
    if afterKey ~= nil and (type(afterKey) ~= "string" or #afterKey > 128) then
        return nil, "invalid_cursor"
    end
    limit = tonumber(limit) or 50
    if limit % 1 ~= 0 or limit < 1 or limit > MAX_READ_LIMIT then return nil, "invalid_limit" end
    local identityType, identityId, identityReason = resolvePlayerIdentity(playerId)
    if not identityType then return nil, identityReason end
    local ready, unavailable = storageReady()
    if not ready then return nil, unavailable end

    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT state_key, state_json, revision, updated_at
            FROM eventcore_resource_player_state
            WHERE resource_name = ? AND identity_type = ? AND identity_id = ?
              AND collection = ? AND state_key > ?
            ORDER BY state_key ASC LIMIT ?
        ]], { resourceName, identityType, identityId, collection, afterKey or "", limit })
    end)
    if not ok then return nil, tostring(rows) end
    return decodeStorageRows(rows)
end

--- Apply a bounded batch of storage mutations as one SQL transaction.
--- The caller's resource scope is attached to every statement by this module.
function EventCore.Persistence.StorageTransaction(resourceName, operations)
    if not validateResourceName(resourceName) then return false, "storage_caller_not_trusted" end
    local ready, unavailable = storageReady()
    if not ready then return false, unavailable end
    if type(operations) ~= "table" or #operations < 1 or #operations > MAX_STORAGE_BATCH then
        return false, "invalid_operation_count"
    end

    local statements, totalBytes, collectionForAudit = {}, 0, "multiple"
    for index, operation in ipairs(operations) do
        if type(operation) ~= "table" then return false, "invalid_operation_" .. index end
        local kind = operation.op
        local scope = operation.scope or "resource"
        local collection, stateKey = operation.collection, operation.key
        local addressOk, addressReason = validateStorageAddress(collection, stateKey)
        if not addressOk then return false, "operation_" .. index .. "_" .. addressReason end

        if kind == "put" then
            local encoded, encodeReason = encodeData(operation.value)
            if not encoded then return false, "operation_" .. index .. "_" .. encodeReason end
            totalBytes = totalBytes + #encoded
            if totalBytes > MAX_STORAGE_BATCH_BYTES then return false, "transaction_payload_too_large" end
            if scope == "resource" then
                statements[#statements + 1] = {
                    query = UPSERT_RESOURCE_STATE,
                    values = { resourceName, collection, stateKey, encoded },
                }
            elseif scope == "player" then
                local identityType, identityId, identityReason = resolvePlayerIdentity(operation.playerId)
                if not identityType then return false, "operation_" .. index .. "_" .. identityReason end
                statements[#statements + 1] = {
                    query = UPSERT_RESOURCE_PLAYER_STATE,
                    values = { resourceName, identityType, identityId, collection, stateKey, encoded },
                }
            else
                return false, "operation_" .. index .. "_invalid_scope"
            end
        elseif kind == "delete" then
            if scope == "resource" then
                statements[#statements + 1] = {
                    query = DELETE_RESOURCE_STATE,
                    values = { resourceName, collection, stateKey },
                }
            elseif scope == "player" then
                local identityType, identityId, identityReason = resolvePlayerIdentity(operation.playerId)
                if not identityType then return false, "operation_" .. index .. "_" .. identityReason end
                statements[#statements + 1] = {
                    query = DELETE_RESOURCE_PLAYER_STATE,
                    values = { resourceName, identityType, identityId, collection, stateKey },
                }
            else
                return false, "operation_" .. index .. "_invalid_scope"
            end
        else
            return false, "operation_" .. index .. "_invalid_op"
        end
        if index == 1 then collectionForAudit = collection end
    end

    local ok, committed, reason = pcall(function()
        return MySQL.transaction.await(statements)
    end)
    if not ok then return false, tostring(committed) end
    if committed ~= true then return false, tostring(reason or "transaction_failed") end
    auditStorageWrite(resourceName, "transaction", "mixed", collectionForAudit, #statements)
    return true
end

function EventCore.Persistence.IsStorageCaller(resourceName)
    return validateResourceName(resourceName)
end

function EventCore.Persistence.StorageApiVersion()
    return STORAGE_API_VERSION
end

local function validateStateAddress(namespace, stateKey)
    if type(namespace) ~= "string" or namespace == "" or #namespace > 64 then
        return false, "invalid_namespace"
    end
    if type(stateKey) ~= "string" or stateKey == "" or #stateKey > 128 then
        return false, "invalid_state_key"
    end
    return true
end

--- Store JSON-compatible authoritative state for an admitted player.
--- Use namespaces such as "inventory" and "outfits"; values are written by
--- the server only and keyed by a stable Open77 account/installation identity.
function EventCore.Persistence.SavePlayerState(playerId, namespace, stateKey, value)
    if state ~= "ready" then return false, "persistence_" .. state end
    local addressOk, addressError = validateStateAddress(namespace, stateKey)
    if not addressOk then return false, addressError end

    local identityType, identityId, identityError = resolvePlayerIdentity(playerId)
    if not identityType then return false, identityError end
    local encoded, encodeError = encodeData(value)
    if not encoded then return false, encodeError end

    local ok, result = pcall(function()
        return MySQL.update.await([[
            INSERT INTO eventcore_player_state
                (identity_type, identity_id, namespace, state_key, state_json, revision)
            VALUES (?, ?, ?, ?, ?, 1)
            ON DUPLICATE KEY UPDATE
                state_json = VALUES(state_json),
                revision = revision + 1,
                updated_at = CURRENT_TIMESTAMP(3)
        ]], { identityType, identityId, namespace, stateKey, encoded })
    end)
    if not ok then return false, tostring(result) end
    return true
end

--- Load a player's saved state by their current session ID and logical address.
function EventCore.Persistence.LoadPlayerState(playerId, namespace, stateKey)
    if state ~= "ready" then return nil, "persistence_" .. state end
    local addressOk, addressError = validateStateAddress(namespace, stateKey)
    if not addressOk then return nil, addressError end

    local identityType, identityId, identityError = resolvePlayerIdentity(playerId)
    if not identityType then return nil, identityError end
    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT state_json, revision, updated_at
            FROM eventcore_player_state
            WHERE identity_type = ? AND identity_id = ? AND namespace = ? AND state_key = ?
            LIMIT 1
        ]], { identityType, identityId, namespace, stateKey })
    end)
    if not ok then return nil, tostring(row) end
    if not row then return nil, "not_found" end

    local decodedOk, value, decodeError = pcall(Open77.json.decode, row.state_json)
    if not decodedOk or value == nil then return nil, tostring(decodeError or value) end
    return value, nil, { revision = tonumber(row.revision) or 1, updatedAt = row.updated_at }
end

function EventCore.Persistence.DeletePlayerState(playerId, namespace, stateKey)
    if state ~= "ready" then return false, "persistence_" .. state end
    local addressOk, addressError = validateStateAddress(namespace, stateKey)
    if not addressOk then return false, addressError end
    local identityType, identityId, identityError = resolvePlayerIdentity(playerId)
    if not identityType then return false, identityError end

    local ok, result = pcall(function()
        return MySQL.update.await([[
            DELETE FROM eventcore_player_state
            WHERE identity_type = ? AND identity_id = ? AND namespace = ? AND state_key = ?
        ]], { identityType, identityId, namespace, stateKey })
    end)
    if not ok then return false, tostring(result) end
    return (tonumber(result) or 0) > 0
end

function EventCore.Persistence.SaveInventoryState(playerId, snapshot)
    if type(snapshot) ~= "table" then return false, "invalid_inventory_snapshot" end
    return EventCore.Persistence.SavePlayerState(playerId, "inventory", "snapshot", snapshot)
end

function EventCore.Persistence.LoadInventoryState(playerId)
    return EventCore.Persistence.LoadPlayerState(playerId, "inventory", "snapshot")
end

function EventCore.Persistence.SaveOutfitCode(playerId, outfitKey, code)
    if type(code) ~= "string" or code == "" then return false, "invalid_outfit_code" end
    return EventCore.Persistence.SavePlayerState(playerId, "outfit_codes", outfitKey, code)
end

function EventCore.Persistence.LoadOutfitCode(playerId, outfitKey)
    return EventCore.Persistence.LoadPlayerState(playerId, "outfit_codes", outfitKey)
end

function EventCore.Persistence.IsTrustedCaller(resourceName)
    return type(resourceName) == "string" and trustedResources[resourceName] == true
end

function EventCore.Persistence.ExposeEvent(eventName, enabled)
    if type(eventName) ~= "string" or eventName == "" or #eventName > 128 then
        return false, "invalid_event_name"
    end
    exposedEventNames[eventName] = enabled ~= false
    return true
end

local function queueDispatch(context)
    if type(context.name) ~= "string" or context.name == "" or #context.name > 128 then
        print("[EventCore][WARN] Dispatched event has an invalid name and was not persisted.")
        return
    end
    local encoded, reason = encodeData(context.data)
    if not encoded then
        print(string.format("[EventCore][WARN] Event '%s' was not queued for persistence: %s",
            tostring(context.name), tostring(reason)))
        return
    end

    local sourceId, sourceKind = normalizeSource(context.source)
    local cancelReason = context.getCancelReason and context.getCancelReason() or nil
    local record = {
        name = context.name,
        data = encoded,
        sourceId = sourceId,
        sourceKind = sourceKind,
        cancelled = context.isCancelled and context.isCancelled() or false,
        cancelReason = cancelReason and tostring(cancelReason):sub(1, 255) or "",
        occurredMs = type(context.timestamp) == "number" and math.max(0, math.floor(context.timestamp * 1000)) or nil,
        attempts = 0
    }

    -- Only explicitly exposed names cross resource boundaries. This keeps
    -- private server event payloads local unless a trusted consumer opts in.
    -- Open77 copies the value; no callback or mutable reference is shared.
    if exposedEventNames[record.name] and type(TriggerEvent) == "function" then
        local published, publishError = TriggerEvent("eventcore:dispatched", {
            name = record.name,
            data = context.data,
            source = record.sourceId,
            sourceKind = record.sourceKind,
            cancelled = record.cancelled,
            cancelReason = record.cancelReason,
            occurredMs = record.occurredMs or 0
        })
        if published == false then
            print("[EventCore][WARN] Could not publish cross-resource event: " .. tostring(publishError))
        end
    end

    if #writeQueue >= MAX_QUEUE_SIZE then
        droppedQueuedWrites = droppedQueuedWrites + 1
        if droppedQueuedWrites == 1 or droppedQueuedWrites % 100 == 0 then
            print(string.format("[EventCore][ERROR] Persistence queue full; %d dispatched event(s) have not been queued",
                droppedQueuedWrites))
        end
        return
    end

    writeQueue[#writeQueue + 1] = record
end

-- Preserve the existing synchronous in-memory dispatch contract. Database writes
-- happen on a separate managed coroutine after listeners have completed.
if type(EventCore.DispatchLocal) == "function" then
    local dispatchInMemory = EventCore.DispatchLocal
    EventCore.DispatchLocal = function(eventName, payload, source)
        local context = dispatchInMemory(eventName, payload, source)
        if context then queueDispatch(context) end
        return context
    end
end

local function initializeDatabase()
    if type(MySQL) ~= "table" or type(MySQL.ready) ~= "function" then
        state = "unavailable"
        print("[EventCore][WARN] SQL bridge unavailable; enable the Open77 database and grant database.access.")
        return
    end

    state = "connecting"
    local queued, reason = MySQL.ready(function()
        state = "initializing"
        local ok, err = pcall(function()
            MySQL.update.await(CREATE_SCHEMA)
            MySQL.update.await(CREATE_PLAYER_STATE_SCHEMA)
            MySQL.update.await(CREATE_RESOURCE_STATE_SCHEMA)
            MySQL.update.await(CREATE_RESOURCE_PLAYER_STATE_SCHEMA)
        end)
        if not ok then
            state = "error"
            print("[EventCore][ERROR] SQL schema initialization failed: " .. tostring(err))
            return
        end
        state = "ready"
        startWorker()
        print("[EventCore] SQL persistence ready (event history, player state, and isolated resource storage); queued dispatches will be flushed.")
    end)

    if not queued then
        state = "unavailable"
        print("[EventCore][WARN] SQL readiness could not be queued: " .. tostring(reason))
    end
end

initializeDatabase()
