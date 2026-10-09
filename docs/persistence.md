# EventCore persistence

EventCore 0.5.0 includes the server-only SQL bridge and a structured storage gateway. A consumer gets only its own resource namespace and per-player records; it never sends SQL, table names, or an owner name. EventCore owns the database connection and keeps `database.access`; consumers call validated EventCore exports. The older compatibility persistence APIs remain available to the existing trusted RPCore integration and should not be used as a shared mod-storage interface.

## Server setup

1. Install MySQL or MariaDB and create a dedicated account for the server. Grant that account only the database permissions Open77 documents for the database EventCore will use.
2. In the `server.jsonc` used to launch the server, enable `database.enabled` and configure `connectionStringEnvironmentVariable` (default: `OP77_DATABASE_CONNECTION`). Keep `connectionString` empty.
3. Set `OP77_DATABASE_CONNECTION` in the dedicated server process environment to a MySqlConnector connection string. Do not put the password in this repository, in `open77.lua`, or in client files.
4. Restart the dedicated server, then approve EventCore's `database.access` permission in Warden. On startup, EventCore creates the persistence tables shown in [`schema.sql`](schema.sql).
5. Keep `database.access` on EventCore only. To approve a structured-storage consumer, install its resource folder, have its `open77.lua` declare `dependency "eventcore >=0.5.0"`, and add its exact folder/resource name to `EventCore.Whitelist` in `server/whitelist.lua`. The manifest dependency is visible and ensures load order; this reviewed Lua list is the authorization gate. Restart EventCore after changing the list.

Open77's database bridge is disabled by default, supports MySQL/MariaDB, and exposes parameterized asynchronous queries to server scripts with `database.access`. Its `.await` methods must run from a host-managed coroutine. See [Open77 SQL setup](https://open2077.net/docs/database).

## Add an approved resource

Install the mod's resource folder under the server's resources root and make sure it is selected by `resources.load`. In that resource's `open77.lua`, declare:

```lua
dependency "eventcore >=0.5.0"
```

Then add one line to the `EventCore.Whitelist` table in EventCore's `server/whitelist.lua`, replacing the placeholder with the exact resource/folder name:

```lua
["resource_folder_name"] = true,
```

Keep the comma. Lua table entries use `=`, not `:`. The resource name must also be an installed, selected resource. This entry enables only that resource's isolated EventCore storage; do not grant it `database.access`.

## What is persisted

Every `EventCore.DispatchLocal` completed on the server is added to a bounded asynchronous write queue with its name, JSON payload, session source when present, cancellation result, and database timestamp. Event dispatch still returns its in-memory context immediately. Queue overflow, invalid JSON payloads, and SQL failures are reported; queued event history is not a write-ahead log, so a process crash before insertion can lose the not-yet-written queue.

Player state is stored separately by stable identity and logical address (`namespace` + `stateKey`). EventCore prefers Open77's account-level `license`, which persists across linked devices; on older compatible runtimes it falls back to `userId`, which is installation-scoped. Temporary numeric player IDs are only used to resolve identity for the current call and are never used as the durable key.

EventCore can store inventory snapshots, outfit codes, character preferences, mission state, and other JSON-compatible server-owned values. It cannot automatically observe an inventory or outfit change owned by another resource, nor can a database row apply a wardrobe code to a player. The resource that authoritatively changes that state must call `SavePlayerState` after the change and call `LoadPlayerState` when restoring it. Do not accept a client-provided inventory snapshot as authoritative. Open77's loot docs likewise identify `onLootPickup` as the point where a server resource writes persistent inventory.

## Server API

All persistence exports below may wait on SQL. Call them from a server-managed coroutine using `Open77.exports.call` and `promise:await()`. Handle both dispatch failures and the method's `nil, reason` / `false, reason` result. Legacy compatibility exports use `trustedResources`; the isolated structured storage API has its separate `EventCore.Whitelist` allowlist plus the manifest-dependency check. Open77 supplies the real caller resource from the export context, so consumers cannot pass a different resource name. Open77 does not pass Lua callbacks or functions between resources; use the serializable APIs shown here.

## Isolated storage API (v1)

This is the default persistence path for new mods when no domain service owns the data. If a clothing, vehicle, inventory, or other authoritative resource already owns a domain, call that resource's validated API directly. EventCore is the cross-mod framework and compatibility fallback; it does not merge separate mod inventories. Shared basics such as outfit bundles and owned-vehicle records can become EventCore-owned services with defined contracts, while each add-on keeps its own records separate.

The `EventCore.Whitelist` allowlist is per server resource, not per player or client. Every row includes the resource identity captured by `GetInvokingResource()`. A mod cannot specify another owner, read across resource namespaces, or choose a database/table/query. EventCore's SQL statements are fixed in code and values are bound parameters. `StoragePutPlayer` resolves a current player ID to a stable account identity, and the SQL key also includes the calling resource and collection.

Example consumer manifest:

```lua
resource "my_clothing_mod"
version "1.0.0"
dependency "eventcore >=0.5.0"
server_script "server/main.lua"
```

Add `["my_clothing_mod"] = true,` to `EventCore.Whitelist` in `server/whitelist.lua` only after installing and reviewing the resource folder. Do not grant it `database.access`. A manifest dependency alone is not authorization, and an allowlist entry without the dependency is denied.

```lua
local function eventCoreCall(method, ...)
    local pending, dispatchError = Open77.exports.call("eventcore", method, ...)
    if not pending then return nil, dispatchError end
    return pending:await()
end

CreateThread(function()
    local ok, reason = eventCoreCall("StoragePutPlayer", playerId,
        "outfits", "streetwear-01", { code = "...", version = 1 })
    if not ok then print("outfit save failed: " .. tostring(reason)) end

    local outfit, loadReason = eventCoreCall("StorageGetPlayer", playerId,
        "outfits", "streetwear-01")
    if not outfit and loadReason ~= "not_found" then
        print("outfit load failed: " .. tostring(loadReason))
    end
end)
```

Exports are `StorageApiVersion`, `StoragePut/Get/Delete/List`, their `Storage*Player` variants, and `StorageTransaction`. Lists use a stable key cursor and accept limits from 1 to 100. Each JSON value and the aggregate transaction payload are capped at 48 KiB; a transaction accepts at most 32 operations. Transactions support only `put` and `delete` against the calling resource's own namespace. Successful changes emit `eventcore.storage.write` audit events without recording keys or values. `PersistenceStatus` reports readiness and configured storage-consumer count.

The current per-player key is account identity (`license`, or the compatible runtime's `userId` fallback), not a character ID. When EventCore gains a character service, character-scoped records should use that service's stable character key through a typed domain API.

```lua
-- From an authorized server resource, inside CreateThread or another managed coroutine.
local function eventCoreCall(method, ...)
    local pending, dispatchError = Open77.exports.call("eventcore", method, ...)
    if not pending then return nil, dispatchError end
    return pending:await()
end

local ok, reason = eventCoreCall("SavePlayerState", playerId, "inventory", "items", {
    { item = "Items.money", quantity = 250 }
})
if not ok then print("inventory save failed: " .. tostring(reason)) end

local savedItems, loadReason = eventCoreCall("LoadPlayerState", playerId, "inventory", "items")
if loadReason == "not_found" then
    savedItems = {} -- apply the resource's own default state
elseif not savedItems then
    print("inventory load failed: " .. tostring(loadReason))
end

-- Multiple outfit codes can use different keys under the same namespace:
eventCoreCall("SavePlayerState", playerId, "outfits", "streetwear-01", "<outfit-code>")
```

Player state exports:

- `SavePlayerState(playerId, namespace, stateKey, value)` — insert or replace JSON-compatible state; increments its revision.
- `LoadPlayerState(playerId, namespace, stateKey)` — returns `value, nil, metadata` or `nil, reason` (`metadata` contains `revision` and `updatedAt`).
- `DeletePlayerState(playerId, namespace, stateKey)` — deletes one saved value.
- `SaveInventoryState(playerId, snapshot)` / `LoadInventoryState(playerId)` — convenience access to the `inventory/snapshot` record.
- `SaveOutfitCode(playerId, outfitKey, code)` / `LoadOutfitCode(playerId, outfitKey)` — convenience access for multiple add-on outfit codes. Use stable named keys and versioned codes; never use a clothing-pool array index as an identity. See [`server-managed-clothing.md`](server-managed-clothing.md).

Event history exports:

- `PersistEvent(eventName, data, source?, options?)` — explicitly persist one event and wait for insertion; returns `eventId` or `nil, reason`.
- `GetPersistedEvent(eventId)` — read one event.
- `FindPersistedEvents(eventName?, limit?, beforeId?)` — newest-first, maximum 100 rows, with `beforeId` pagination.
- `PersistenceStatus()` — reports readiness and queue counts.

All payload values must encode as JSON and fit within 48 KiB. Query values are parameterized. The only player inventory/outfit rows EventCore can guarantee are those written through these server APIs; each consuming resource owns load timing, validation, and application to its game system.

## Native game map data

EventCore persists map definitions only: a trusted consumer such as RPCore stores validated pin IDs, labels, native sprite identifiers, and world coordinates in its own whitelisted storage partition. RPCore then asks Open77 to create resource-owned native blips, which Cyberpunk renders on its built-in City Map and minimap. EventCore does not store map tiles, draw a replacement map, or control minimap placement. Each map consumer must declare an EventCore dependency and be listed in `server/whitelist.lua`; the consumer remains responsible for validating admin actions and pin data before writes.

## Tables

- `eventcore_events` is append-only event history. `source_id` is a session number for audit context (`0` indicates a server-originated event), not a durable player key. `occurred_ms` is the process-monotonic event timestamp (`0` if unavailable); `created_at` is the SQL server's timestamp.
- `eventcore_player_state` is the legacy compatibility table keyed by `(identity_type, identity_id, namespace, state_key)`. It does not have a resource-owner column; new resources must use the isolated storage API instead.
- `eventcore_resource_state` holds shared resource-owned records keyed by `(resource_name, collection, state_key)`.
- `eventcore_resource_player_state` holds per-player records keyed by resource, stable player identity, collection, and state key.

The database account should be restricted to EventCore's database. Preserve regular SQL backups; copying the resource folder does not back up this state.

## Integration points

1. The manifest loads `server/whitelist.lua` before `server/persistence.lua`; EventCore alone requests `database.access`, and neither module loads on clients.
2. The adapter wraps `EventCore.DispatchLocal` server-side and queues the resulting context after existing in-memory listeners finish.
3. Its `MySQL.ready` callback creates the four tables, then starts the background queue writer.
4. Other server resources use the guarded EventCore exports to save/load player snapshots. The resource that owns each gameplay state must invoke the API at its authoritative mutation and restoration points.

## Implemented vs. needs runtime verification

Implemented in this repository: SQL schema creation, event-history queue, durable player-state snapshot API, stable identity resolution, server-only credentials/permission path, trusted-resource export gate, caller-isolated structured storage with bounded atomic batches, and this integration guide.

Needs in-game/server verification: Warden permission approval, the actual server's MariaDB/MySQL compatibility and grants, persistence across a server restart, and end-to-end inventory/outfit save/restore after the owning gameplay resources integrate these calls. EventCore does not claim to hook every third-party inventory or wardrobe system automatically.
