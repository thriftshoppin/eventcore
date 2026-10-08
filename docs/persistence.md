# EventCore persistence

EventCore 0.3.0-beta.1 includes the server-only persistence adapter introduced in 0.2.0-beta.1 and adds a versioned service directory and trusted player-context APIs. It uses Open77's built-in MySQL/MariaDB bridge; it does not connect directly to SQL from client scripts and never puts database credentials in the resource.

## Server setup

1. Install MySQL or MariaDB and create a dedicated account for the server. Grant that account only the database permissions Open77 documents for the database EventCore will use.
2. In the `server.jsonc` used to launch the server, enable `database.enabled` and configure `connectionStringEnvironmentVariable` (default: `OP77_DATABASE_CONNECTION`). Keep `connectionString` empty.
3. Set `OP77_DATABASE_CONNECTION` in the dedicated server process environment to a MySqlConnector connection string. Do not put the password in this repository, in `open77.lua`, or in client files.
4. Restart the dedicated server, then approve EventCore's `database.access` permission in Warden. On startup, EventCore creates the two tables shown in [`schema.sql`](schema.sql).
5. Add each trusted server resource that will call EventCore persistence exports to the `trustedResources` table near the top of `server/persistence.lua` (the initial entry is `rpcore`). Restart EventCore after changing this list.

Open77's database bridge is disabled by default, supports MySQL/MariaDB, and exposes parameterized asynchronous queries to server scripts with `database.access`. Its `.await` methods must run from a host-managed coroutine. See [Open77 SQL setup](https://open2077.net/docs/database).

## What is persisted

Every `EventCore.DispatchLocal` completed on the server is added to a bounded asynchronous write queue with its name, JSON payload, session source when present, cancellation result, and database timestamp. Event dispatch still returns its in-memory context immediately. Queue overflow, invalid JSON payloads, and SQL failures are reported; queued event history is not a write-ahead log, so a process crash before insertion can lose the not-yet-written queue.

Player state is stored separately by stable identity and logical address (`namespace` + `stateKey`). EventCore prefers Open77's account-level `license`, which persists across linked devices; on older compatible runtimes it falls back to `userId`, which is installation-scoped. Temporary numeric player IDs are only used to resolve identity for the current call and are never used as the durable key.

EventCore can store inventory snapshots, outfit codes, character preferences, mission state, and other JSON-compatible server-owned values. It cannot automatically observe an inventory or outfit change owned by another resource, nor can a database row apply a wardrobe code to a player. The resource that authoritatively changes that state must call `SavePlayerState` after the change and call `LoadPlayerState` when restoring it. Do not accept a client-provided inventory snapshot as authoritative. Open77's loot docs likewise identify `onLootPickup` as the point where a server resource writes persistent inventory.

## Server API

All persistence exports below may wait on SQL. Call them from a server-managed coroutine using `Open77.exports.call` and `promise:await()`. Handle both dispatch failures and the method's `nil, reason` / `false, reason` result. Only trusted resources listed in `trustedResources` can call persistence exports. Open77 does not pass Lua callbacks or functions between resources; use the serializable APIs shown here.

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

## Tables

- `eventcore_events` is append-only event history. `source_id` is a session number for audit context (`0` indicates a server-originated event), not a durable player key. `occurred_ms` is the process-monotonic event timestamp (`0` if unavailable); `created_at` is the SQL server's timestamp.
- `eventcore_player_state` holds one latest JSON value for each `(identity_type, identity_id, namespace, state_key)` and increments `revision` on replacement. It supports snapshots such as inventory arrays and outfit-code strings. It is not an item transaction ledger.

The database account should be restricted to EventCore's database. Preserve regular SQL backups; copying the resource folder does not back up this state.

## Integration points

1. The manifest loads `server/persistence.lua` after the shared event bus and grants `database.access`; the module does not load on clients.
2. The adapter wraps `EventCore.DispatchLocal` server-side and queues the resulting context after existing in-memory listeners finish.
3. Its `MySQL.ready` callback creates both tables, then starts the background queue writer.
4. Other server resources use the guarded EventCore exports to save/load player snapshots. The resource that owns each gameplay state must invoke the API at its authoritative mutation and restoration points.

## Implemented vs. needs runtime verification

Implemented in this repository: SQL schema creation, event-history queue, durable player-state snapshot API, stable identity resolution, server-only credentials/permission path, trusted-resource export gate, bounded reads/writes, and this integration guide.

Needs in-game/server verification: Warden permission approval, the actual server's MariaDB/MySQL compatibility and grants, persistence across a server restart, and end-to-end inventory/outfit save/restore after the owning gameplay resources integrate these calls. EventCore does not claim to hook every third-party inventory or wardrobe system automatically.
