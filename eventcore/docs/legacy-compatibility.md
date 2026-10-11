# Legacy add-on compatibility

EventCore is a server resource, not a replacement RED4ext loader. RED4ext loads native game plugins inside the player's game process; Open77's database runs on the dedicated server. A legacy plugin must never receive the SQL connection string or be treated as an authority for inventory, rewards, or a player's saved account state.

The installed game folder contains the RED4ext/Open77 binaries and Open77 runtime resources, not the RED4ext source/SDK project needed to change RED4ext itself. EventCore therefore provides an Open77 resource bridge that legacy-facing adapters can use without modifying the loader.

## Server resource event bridge

After EventCore finishes its existing in-memory listener dispatch, it can publish selected names as a value-copied `eventcore:dispatched` event over Open77's host-wide server bus. A trusted server resource opts a name in through Open77's server-export call. Only opted-in event names cross the resource boundary, so private server event payloads stay local by default. Any running server resource can then listen without passing a Lua callback through an export:

```lua
CreateThread(function()
    local pending, dispatchError = Open77.exports.call(
        "eventcore", "ExposeEvent", "mission:objective:updated")
    if not pending then
        Open77.log.error("EventCore call failed: " .. tostring(dispatchError))
        return
    end
    local ok, reason = pending:await()
    if not ok then Open77.log.error("Event exposure rejected: " .. tostring(reason)) end
end)

AddEventHandler("eventcore:dispatched", function(record)
    print(record.name, record.source, record.sourceKind, record.cancelled)
    -- record.data is the JSON-compatible event payload.
end)
```

The record contains `name`, `data`, `source`, `sourceKind`, `cancelled`, `cancelReason`, and `occurredMs`. `source` is a transient server session number (`0` for server-originated events). Expose only event names whose payloads are safe for other server resources to receive; listeners should still avoid logging secrets or unnecessary personal data.

## Legacy client request path

An Open77 client adapter can forward an explicit proposal through EventCore's registered network relay. A trusted server resource must first allow the exact event name:

```lua
-- Server, from RPCore or the authoritative resource:
CreateThread(function()
    local pending, dispatchError = Open77.exports.call(
        "eventcore", "AllowClientEvent", "legacy:outfit:select")
    if not pending then return end
    local ok, reason = pending:await()
    if not ok then Open77.log.error(tostring(reason)) end
end)

-- Client adapter. EventCore owns the receiver and gets the authenticated source.
TriggerServerEvent("eventcore:net:relay", "legacy:outfit:select", {
    outfit = "streetwear-01"
})
```

The server receives the authenticated session source, but the payload is still client-controlled. A server resource must validate the request and decide whether it can change canonical state. Only after that resource has committed the authoritative change should it save the resulting server-owned snapshot through EventCore's trusted persistence API.

For example, inventory owners should process authoritative changes (including Open77's `onLootPickup` hook), update their own inventory model, then save that resulting snapshot. They must not store the item list sent by a client as fact. The Open77 loot documentation explicitly leaves persistent inventory to the server resource that owns it.

## Outfit/appearance compatibility

The supplied Open77 runtime already includes `open77_appearance`, which persists player equipment and wardrobe/outfit selections on the server and restores/replicates them. Keep that resource authoritative for those native looks. EventCore's generic `SavePlayerState` can store a separate addon-defined outfit-code catalog or other application data when a trusted server resource actually owns it, but it does not replace or silently mirror `open77_appearance`'s private SQL schema.

The planned `ServerManagedClothing` dependency and client-asset boundary are described in [`server-managed-clothing.md`](server-managed-clothing.md).

Native RED4ext/CET/redscript plugins are not server resources and cannot subscribe directly to EventCore's Open77 Lua event bus. A bridge for a specific legacy plugin needs an Open77 client resource or a server resource that understands that plugin's documented data format. The adapter must convert only the specific fields the server can validate; arbitrary client memory, native handles, functions, and the whole game process are not serialized into SQL.

## Current boundary

- Implemented in 0.3.0-beta.1: service registration/discovery; trusted server player-context and observer-scope reads; host-wide server event notifications; client-to-server relay for explicitly allowed event names; guarded database exports for trusted server resources; generic player state persistence.
- Still needs a concrete legacy add-on to integrate: mapping its input/output and validating its schema. RED4ext loader source was not present in the supplied game install, so this change does not modify `RED4ext.dll`, Open77's `Open77.dll`, or any installed plugin binary.
