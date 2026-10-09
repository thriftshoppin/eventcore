# RPCore integration contract

This guide describes the EventCore `0.3.1` foundation for RPCore. EventCore is the server-side runtime/service hub and owns the client-state transport contract. RPCore consumes safe APIs and renders the player-facing HUD. Inventory, appearance, missions, and other domain resources remain authoritative for their own rules and data.

Open77 gives each resource an isolated Lua VM. Cross-resource requests therefore use serializable values and named exports; Lua callbacks and internal tables do not cross that boundary. Use Open77's `Open77.exports.call` and await its promise from a managed server coroutine. See [Open77 cross-resource server exports](https://open2077.net/docs/server-exports).

## EventCore services available now

| Service | Method | Purpose | Access |
| --- | --- | --- | --- |
| `eventcore.runtime` | `GetRuntimeInfo()` | EventCore version, API version, capabilities, and service catalog | Any server resource |
| `eventcore.runtime` | `GetServiceCatalog()` | Active provider descriptors, including the provider resource name | Any server resource |
| `eventcore.runtime` | `GetPlayerContext(playerId)` | Verified stable identity, display name, session ID, last known position, and routing bucket | Trusted server resources; initially `rpcore` |
| `eventcore.runtime` | `GetPlayerObservers(playerId)` | Current native replication-scope viewers for proximity-aware presentation | Trusted server resources; initially `rpcore` |
| `eventcore.runtime` | `IsAdmin(playerId)` | Whether a connected player holds Open77's reserved `admin` or `owner` role | Trusted access readers; initially `rpcore` |
| `eventcore.runtime` | `GetPlayerRoles(playerId)` | The connected player's effective Open77 ACL role labels | Trusted access readers; initially `rpcore` |
| `eventcore.runtime` | `GetOnlineAdmins()` | Connected players holding the reserved global admin or owner role | Trusted access readers; initially `rpcore` |
| `eventcore.runtime` | `PublishClientState(playerId, channel, schemaVersion, payload)` | Send a validated, client-safe snapshot through EventCore | Trusted server resources |
| `eventcore.runtime` | `ClearClientState(playerId, channel, schemaVersion)` | Clear a presentation channel | Trusted server resources |

## Client-state feed

Gameplay resources own and validate gameplay state. A trusted presentation
consumer such as RPCore converts it into a client-safe view, then publishes the
view through EventCore. EventCore checks the caller and target player, detaches
and bounds the payload, assigns an increasing per-player/channel sequence, and
sends the `eventcore:net:state:update` packet. The client rejects stale sequence
numbers and dispatches it on `EventCore.STATE_FEED_EVENT` (`state:update`).

Packets contain `protocolVersion`, `epoch`, `publisher`, `channel`,
`schemaVersion`, `sequence`, `visible`, and `state`. Epochs let the client
accept fresh sequences after EventCore restarts. Use a stable resource-namespaced channel such as
`rpcore.hud`; the publisher owns that channel's schema. Payloads are limited to
2,048 table entries, 12 nested levels, 4,096 characters per string, and 64 KiB
of combined string/key content.
Functions, userdata, cycles, non-finite numbers, and unsupported keys are
rejected. `visible=false` explicitly clears the channel with an empty state.

Server publisher (from a managed server coroutine):

```lua
local pending, reason = Open77.exports.call("eventcore", "PublishClientState",
    playerId, "rpcore.hud", 1, hudView)
if not pending then return false, reason end
return pending:await()
```

RPCore client listener:

```lua
EventCore.On(EventCore.STATE_FEED_EVENT, function(packet)
    if packet.channel ~= "rpcore.hud" or packet.schemaVersion ~= 1 then return end
    if packet.visible then
        -- Render packet.state; it is presentation data, not gameplay authority.
    else
        -- Clear this HUD view.
    end
end)
```

The feed is transport, not a provider or source of truth. Resource join/restart
replay, subscriptions, update cadence, and RPCore's current provider compatibility
reader still need integration and live-server verification.

The player-context identity prefers the Open77 account `license` and falls back to the persistent installation `userId` on runtimes without `license`. The session `playerId` is for live addressing only. Position is Open77's latest replicated server snapshot and can be unavailable or slightly stale; gameplay decisions must revalidate conditions at the moment of action.

Example RPCore server call:

```lua
local function eventCoreCall(method, ...)
    local pending, dispatchError = Open77.exports.call("eventcore", method, ...)
    if not pending then return nil, dispatchError end
    return pending:await()
end

CreateThread(function()
    local context, reason = eventCoreCall("GetPlayerContext", playerId)
    if not context then
        Open77.log.warn("No player context: " .. tostring(reason))
        return
    end

    -- Send only the presentation data this RPCore client needs.
    -- Re-check native scope before sending another player's appearance.
end)
```

`GetPlayerObservers(subjectId)` answers the observers currently in Open77's native replication scope. Use this before sending another player's presentation update. Do not globally broadcast a full inventory, character record, or outfit state. Scope is dynamic; query it when routing each update or snapshot.

The `eventcore.runtime` descriptor also lists EventCore's event and persistence exports. Methods that touch SQL, allow client proposals, or expose event payloads remain restricted by the trusted-resource checks described in [`persistence.md`](persistence.md) and [`legacy-compatibility.md`](legacy-compatibility.md); discovery does not grant permission.

## Reading global admin status

Global administration remains assigned by Warden through Open77's ACL. EventCore
does not grant or revoke ACL rights. It exposes a read-only query so trusted
server tools can make consistent decisions without inventing another role
system. EventCore declares `acl.read` in its resource manifest. Add each tool resource to `trustedAccessReaders` in
`server/access.lua` before it can use these exports.

```lua
local pending, reason = Open77.exports.call("eventcore", "IsAdmin", playerId)
if not pending then return nil, reason end
local isAdmin, callError = pending:await()
if isAdmin == nil then return nil, callError end
-- `isAdmin` is true only for the reserved Open77 `admin` or `owner` role.
```

Use `GetPlayerRoles(playerId)` when a tool needs to distinguish a scoped staff
role from global administration. `GetOnlineAdmins()` lists connected global
admins only; offline ACL management remains in Warden.

## Registering a domain provider

EventCore stores provider descriptors as plain data. A provider name and VM generation are taken from Open77's export invocation context, never from descriptor fields supplied by the caller. A descriptor does not grant access to the provider's methods: the provider still has to export each method and authorize callers inside that method.

```lua
-- inventory_mod/open77.lua
resource "inventory_mod"
version "1.0.0"
dependency "eventcore >=0.3.0-beta.1"
server_script "server/main.lua"
```

```lua
-- inventory_mod/server/main.lua
exports("GetSnapshot", function(playerId)
    if GetInvokingResource() ~= "rpcore" then return nil, "caller_denied" end
    -- Validate playerId and return only the safe fields RPCore is allowed to show.
    return { weight = 14.2, capacity = 40.0 }
end)

CreateThread(function()
    local pending, dispatchError = Open77.exports.call("eventcore", "RegisterService", {
        id = "inventory",
        version = "1.0.0",
        apiVersion = 1,
        methods = { "GetSnapshot" },
        events = { "inventory:changed" },
        description = "Authoritative inventory summary for presentation.",
    })
    if not pending then
        Open77.log.error("EventCore registration failed: " .. tostring(dispatchError))
        return
    end
    local accepted, reason = pending:await()
    if not accepted then Open77.log.error("Service rejected: " .. tostring(reason)) end
end)
```

RPCore reads `GetServiceCatalog()`, checks `id`, `version`, and `apiVersion`, then calls the advertised provider method by its resource name:

```lua
local pending, dispatchError = Open77.exports.call(provider.resource, "GetSnapshot", playerId)
if not pending then return nil, dispatchError end
local snapshot, callError = pending:await()
```

Provider services must validate every argument, use `GetInvokingResource()` for authorization, and never trust `source` to exist inside an export callback. EventCore automatically removes descriptors after a provider generation stops or reloads. A provider should re-register on its next start.

## What this release does not do yet

- It does not build HUD state from gameplay providers or replay cached state after a client/resource restart. RPCore must publish a validated view and manage its rendering lifecycle.
- It does not include inventory, clothing, mission, economy, health/needs, or vehicle providers. Their owning resources must implement and register those contracts.
- It does not provide a general task supervisor or replace Open77's resource lifecycle and scheduler.
- It does not query EventCore SQL tables from RPCore. Durable writes remain explicit calls from the server resource that owns the authoritative state.
- It does not broadcast every player's data. Use `GetPlayerObservers` to target currently scoped viewers for remote-player presentation.

## Compatibility and rollout

`0.3.0-beta.3` adds read-only ACL role queries; `API_VERSION` remains 1. Cross-resource `On`/`Off` exports remain unavailable because Open77's value codec does not transfer callbacks. The in-resource `EventCore.On` and `EventCore.Off` dispatcher remains available inside each EventCore VM; use named exports for server request/response calls and `state:update` for this validated client presentation feed. Rebuild consumers against this beta before using it.

The new cross-resource server API requires an Open77 server build that supports server exports, `GetInvokingResourceGeneration`, and `Open77.resource.generation`. The client runtime does not need an update for those server-side calls. Verify the actual server build before deployment.
