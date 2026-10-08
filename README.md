# EventCore

EventCore is the server-side runtime and service hub for Open77 roleplay resources. Its intended relationship with RPCore is straightforward: EventCore provides versioned services, trusted player/session context, events, scoped observer information, and durable server storage; RPCore consumes those contracts and turns approved information into an immersive HUD and player-facing tools.

Gameplay resources remain authoritative for their own domains. Inventory decides what a player owns, clothing decides which outfits are valid, and mission resources decide objective results. They publish versioned service descriptors and validated exports for RPCore and other consumers. EventCore is the common hub and persistence layer, not a replacement for each domain's rules.

## 0.3.0-beta.1

This release prepares that architecture with:

- A server-side versioned service directory. Providers register serializable descriptors; consumers discover the provider resource and advertised methods/events.
- Trusted player-context reads using Open77's verified identity and latest server position snapshot.
- Native observer-scope reads so RPCore can target presentation updates to nearby/current viewers instead of broadcasting another player's outfit across town.
- Existing event dispatch, explicit client-event allowlisting, selected server event notifications, and server-only SQL persistence.
- Open77-correct asynchronous cross-resource examples. Function callbacks are not passed between isolated resource VMs.

This is an experimental foundation, not the completed RPCore data feed. EventCore does not yet push live HUD updates, implement inventory/clothing/mission providers, replace Open77's scheduler/resource lifecycle, or automatically capture state owned by another resource. The implementation status and staged roadmap are in [`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md) and [`docs/RPCORE_PREPARATION_PLAN.md`](docs/RPCORE_PREPARATION_PLAN.md).

Release-by-release changes are listed in [`CHANGELOG.md`](CHANGELOG.md).

## Integration

Server consumers call EventCore and provider exports through `Open77.exports.call` from a managed coroutine. The caller must validate the returned values, and a provider must authorize each caller with `GetInvokingResource()` and validate every argument. Open77 does not pass a network player's `source` into an export call; pass the player ID explicitly after resolving it from a trusted server event.

```lua
CreateThread(function()
    local pending, reason = Open77.exports.call("eventcore", "GetPlayerContext", playerId)
    if not pending then
        Open77.log.warn("EventCore unavailable: " .. tostring(reason))
        return
    end
    local context, callError = pending:await()
    if not context then
        Open77.log.warn("Player context unavailable: " .. tostring(callError))
        return
    end
    -- Build a client-safe view; never forward private identity fields to a HUD.
end)
```

See [`docs/rpcore-integration.md`](docs/rpcore-integration.md) for service registration, player context, scope-aware presentation, and the RPCore contract. See [`docs/persistence.md`](docs/persistence.md) for database setup and the trusted server state APIs.

## Persistence and credentials

EventCore uses Open77's built-in MySQL/MariaDB bridge from server scripts only. The server environment provides `OP77_DATABASE_CONNECTION`; database credentials never belong in this resource or its client scripts. Open77 must grant EventCore `database.access` in Warden. The schema is in [`docs/schema.sql`](docs/schema.sql).

Event history is a bounded asynchronous audit queue, not a write-ahead log. Authoritative gameplay resources must explicitly save their state after accepted changes and load it at the correct lifecycle point. Client proposals are untrusted.

## Compatibility and release

The `0.3.0-beta.1` archive is separate from the earlier `0.2.0-beta.1` release. The service directory requires an Open77 server build with server-to-server exports and resource-generation APIs. Verify compatibility on the actual server before enabling it for players.

For legacy adapters, see [`docs/legacy-compatibility.md`](docs/legacy-compatibility.md). EventCore does not patch RED4ext, Open77 binaries, or third-party native plugins. The planned custom-clothing boundary and stable outfit-code rules are in [`docs/server-managed-clothing.md`](docs/server-managed-clothing.md).

EventCore is released as All Rights Reserved. Permission is granted to download, install, and run this release on OPEN//77 servers through the OPEN//77 Workshop. Modification, redistribution, and derivative works are not permitted.
