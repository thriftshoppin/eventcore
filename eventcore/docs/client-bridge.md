# EventCore client bridge

EventCore 0.7.0 adds a paired typed bridge: clients can request registered server actions, and a registered server provider can ask its matching client adapter to apply a named action and return a result. It builds on Open77's resource-namespaced network callbacks and cross-resource exports; it does not create another socket, intercept private mod consoles, or execute arbitrary client text. The authenticated player ID is supplied by Open77 to server handlers. A callback is still only a request, so the owning domain must authorize and validate it. See the [Open77 callback contract](https://open2077.net/docs/callbacks).

## Approval gates

A server provider is accepted only when all of these are true:

1. It declares `dependency "eventcore >=0.7.0"` in its manifest.
2. Its exact resource folder name is enabled in `EventCore.BridgeWhitelist` in `server/whitelist.lua`.
3. It registers a named action from a server export invocation; EventCore derives provider name and resource generation from that invocation.
4. The request names an action that provider registered. Clients cannot choose the provider resource or export name.
5. The handler validates Warden/Open77 ACL, gameplay preconditions, and every field before changing state.

Bridge registration does not grant SQL, ACL, or gameplay permissions. `BridgeWhitelist` is intentionally separate from `EventCore.Whitelist` for scoped storage. A storage approval is not automatically a network-action approval, and vice versa.

## Register a server action

The action's resource owns the implementation and authorization. EventCore invokes the fixed export name recorded at registration, passing the authenticated player ID, action ID, and data table.

```lua
-- domain/server/main.lua
local function registerAction(actionId, definition)
    local pending, reason = Open77.exports.call("eventcore", "RegisterBridgeAction", actionId, definition)
    if not pending then return false, reason end
    return pending:await()
end

exports("HandleBridgeAction", function(playerId, actionId, payload)
    -- Cross-resource calls arrive from EventCore. Never trust payload.playerId.
    if GetInvokingResource() ~= "eventcore" then
        return { ok = false, error = "invalid_caller" }
    end
    if actionId == "map.pin.create" then
        if not Open77.acl.isAllowed(playerId, "map.pin.manage") then
            return { ok = false, error = "permission_denied" }
        end
        -- Validate title, sprite, position, visibility and bounds here.
        -- Persist through EventCore only after the domain accepts the change.
        return { ok = true, result = { accepted = true } }
    end
    return { ok = false, error = "unknown_action" }
end)

CreateThread(function()
    local ok, reason = registerAction("map.pin.create", {
        handler = "HandleBridgeAction",
        description = "Request creation of a shared map pin",
        maxPayloadBytes = 4096,
        maxCalls = 4,
        windowMs = 10000,
    })
    if not ok then Open77.log.error("map bridge registration failed: " .. tostring(reason)) end
end)
```

Each resource may register multiple action IDs, but all should route through a small number of explicit handler exports. Registering an action does not imply that the player is authorized to use it. Re-check permissions and world conditions inside the handler at mutation time.

## Call from a client resource

EventCore publishes the helper as a client module. The consumer must list EventCore as a dependency and have `network.events` in its own manifest. The helper returns an Open77 promise; await it inside a managed coroutine.

```lua
-- domain/open77.lua
dependency "eventcore >=0.7.0"
permissions { "network.events" }

-- domain/client/main.lua
local Bridge = assert(require("@eventcore/client.modules.bridge"))

CreateThread(function()
    local response, reason = Bridge.requestAwait("map.pin.create", {
        title = "Ripperdoc",
        position = { x = -1442.2, y = 127.4, z = 18.0 },
        sprite = "service",
    }, 5000)
    if not response then
        Open77.log.warn("map pin request failed: " .. tostring(reason))
        return
    end
    if not response.ok then
        Open77.log.warn("map pin refused: " .. tostring(response.error))
    end
end)
```

The client helper assigns each request a unique ID and sends protocol version 2. Callers that implement a retry can pass a fourth `requestId` argument to `Bridge.request` / `Bridge.requestAwait`, or create one with `Bridge.newRequestId()` and reuse it only for the same logical action and payload. EventCore scopes replay protection to the authenticated player, action, ID, and exact JSON payload; completed results and ambiguous provider failures are cached for two minutes in a bounded 64-entry per-player cache. A repeated in-flight ID is refused, and reusing an ID for different content returns `request_id_reused`. If a caller needs retries to remain safe across server restarts or beyond the in-memory cache window, its provider must also persist the request ID as part of its own idempotent domain transaction. The client helper caps requests at 16 KiB before transport. EventCore re-encodes the payload on the server, enforces the provider's lower-or-equal byte cap, applies a per-player sliding-window rate limit, and routes only to the registered owner. Open77 callbacks also enforce their transport limits and timeouts. No client-supplied identity is used.

## Server-to-client actions and updates

For a client adapter that needs to perform a local operation, the provider registers the same action with `clientHandler = true`. The client resource registers a named local export for that action. EventCore only routes the call to that registered resource and returns its structured result.

```lua
-- Server provider registration
registerAction("hud.layout.apply", {
    handler = "HandleBridgeAction",
    clientHandler = true,
    description = "Apply a server-approved HUD layout",
})

-- Server provider, in a managed coroutine after server-side policy checks
local pending, dispatchError = Open77.exports.call("eventcore", "CallBridgeClientAction",
    playerId, "hud.layout.apply", { layout = safeLayout }, 5000)
if pending then
    local result, reason = pending:await()
end
```

```lua
-- Client adapter, same Open77 resource name as the server provider
local Bridge = assert(require("@eventcore/client.modules.bridge"))

exports("ApplyHudLayout", function(actionId, payload)
    if actionId ~= "hud.layout.apply" then return { ok = false, error = "unknown_action" } end
    -- Apply only known HUDitor widget fields and return a local result.
    return { ok = true, result = { applied = true } }
end)

CreateThread(function()
    local pending, reason = Bridge.registerClientAction("hud.layout.apply", "ApplyHudLayout")
    if pending then pending:await() end
end)
```

Use `PublishClientState` / `ClearClientState` for server-owned presentation snapshots and deltas. The provider validates and authorizes domain changes first, then publishes the filtered client-safe result. Clients apply only known schema data. A client action result is an execution report, not proof that server gameplay state changed.

This split supports the future domains without a new protocol per feature:

- map pin requests, snapshots, and deltas;
- job offer/accept/result messages;
- fixer mission state and objective updates;
- live-event join/state/result messages;
- NPC interaction requests and server-authorized presentation.

Each domain owns its data schema, authorization, persistent records, and state transitions. EventCore owns only the safe transport and shared storage boundaries.

## HUDitor and Nexus dependencies

HUDitor remains a local game UI mod; its APIs do not run in the Open77 server VM. The RPCore client package pins HUDitor 1.1.0 and documents its required client dependencies: Codeware, Cyber Engine Tweaks, Input Loader, Mod Settings, RED4ext, and redscript 0.5.31 or newer. These are client-side mod frameworks, not EventCore server resources, and must not be added to `server/whitelist.lua` or granted SQL access. See the [HUDitor Nexus page](https://www.nexusmods.com/cyberpunk2077/mods/3315); RPCore's `client-mod/README.md` contains the install inventory.

No additional Nexus gameplay or HUD package is part of this integration set yet. The stack needs one owner for each visible widget; layering unrelated HUD replacers could duplicate or overwrite widgets and does not create a server adapter. Add another Nexus package only when a concrete feature needs it, its requirements and redistribution terms are reviewed, and its local/client-to-Open77 adapter path is defined. HUDitor's six required frameworks are the only external client dependencies currently selected.

EventCore's bridge can receive events from an Open77 client resource. It cannot automatically intercept CET, REDscript, or another private Nexus-mod API merely because those dependencies are installed. HUDitor still needs a supported local adapter path into the Open77 client resource before layout events can reach this bridge. Do not use the privileged debug runtime for production integration. Until that adapter is verified, HUDitor layout persistence remains local.

## Failure and compatibility behavior

- Unsupported protocol, malformed action, unregistered action, invalid payload, payload too large, rate limit, stopped provider, handler failure, and callback timeout all fail closed.
- The client displays a bounded error; server logs retain the internal provider failure context.
- Provider registrations are tied to resource generation; reloads invalidate stale actions.
- A missing HUDitor adapter disables only HUDitor sync. Server-owned gameplay domains continue operating.
- Client dependency/version reports are advisory. Never use them as Warden identity or authorization evidence.

## Current implementation boundary

Implemented in source: registered, allowlisted client-to-server requests; opt-in server-to-client calls to matching client adapters; source identity supplied by Open77's callback transport; manifest dependency and provider allowlist gates; caller/generation ownership; bounded JSON payload/result; per-player/action rate limits; request IDs with bounded in-memory replay protection; structured responses; and a published client helper.

Not implemented by this bridge: client mod filesystem scanning, automatic Nexus dependency installation, and HUDitor CET/REDscript-to-Open77 IPC. Server-to-client snapshots/deltas use the existing versioned EventCore state feed. Test both callback directions and provider lifecycle on the target server/client build before enabling gameplay actions.
