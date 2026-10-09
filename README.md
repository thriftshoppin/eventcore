# EventCore

EventCore is intended to remain open source and free for anyone to use and modify. It is under development; publication terms and license will be stated with the public release.

EventCore is the server-side runtime and service hub for Open77 roleplay resources. Its intended relationship with RPCore is straightforward: EventCore provides versioned services, trusted player/session context, events, scoped observer information, and durable server storage; RPCore consumes those contracts and turns approved information into an immersive HUD and player-facing tools.

EventCore also owns the framework's administrator entry point. `/eventcore.admin`
opens its administrator console; `/eventcore.admins`, `/eventcore.roles`,
`/eventcore.services`, `/eventcore.events`, and `/eventcore.help` provide text access to Warden role,
service, and event-handler diagnostics. The panel includes a player roster,
authorized quick actions, a Warden-checked `admin.*` command console with
structured tool output, the service directory, and registered event handlers.
Every EventCore entry checks Warden for the reserved `admin` or `owner` role.
Quick actions are limited to commands explicitly granted by Warden, and Open77's
restricted command dispatcher checks that command grant again before execution.
Warden remains the only authority that assigns global roles.

The admin surface is being migrated into EventCore in increments. The current
panel fronts the existing Open77 restricted command handlers; gameplay rules and
the command implementations remain in their owning resources until migrated.
See [`docs/admin-console.md`](docs/admin-console.md) for commands, panel actions,
and the authorization flow.

Gameplay resources remain authoritative for their own domains. Inventory decides what a player owns, clothing decides which outfits are valid, and mission resources decide objective results. Related foundational RP services such as outfits/clothing bundles and owned vehicles can live behind shared EventCore contracts, while add-on resources publish versioned services and work directly with those owners when appropriate. EventCore is the compatibility and persistence fallback when no domain service fits. Its storage API gives each explicitly trusted resource a separate SQL-backed namespace; a mod cannot supply SQL, choose another resource's namespace, or directly access the database. This keeps mod-owned records separate instead of combining every mod's inventory or data into one list.

## 0.5.0

Adds a structured persistence gateway for trusted resources, with resource-private
and per-player storage, bounded atomic batches, and server-derived ownership.
Consumers use EventCore exports instead of database credentials or raw SQL.
See [`docs/persistence.md`](docs/persistence.md) for trust configuration and
the storage contract.

## 0.4.0

Adds EventCore's administrator console, text commands for Warden role and
runtime diagnostics, a read-only EventCore service/event-handler view, and a
Warden-authorized bridge to existing Open77 admin commands. No role assignment
or command authorization is moved out of Warden/Open77.

## 0.3.1

Adds read-only access queries backed by Open77's effective ACL. Trusted server
tools can ask whether a connected player holds the reserved `admin` or `owner`
role, read that player's role labels, or list connected global admins. Warden
remains the authority for role assignment; EventCore never grants admin rights.
EventCore declares the `acl.read` capability in its resource manifest. Allowlist each server tool in `server/access.lua` before it can use these exports.

## 0.3.0-beta.2

Adds EventCore's versioned client-state feed. Trusted server resources publish
client-safe snapshots (or clear a channel) through EventCore; clients receive
ordered `state:update` packets. EventCore transports these views but does not
become the authoritative owner of character, health, needs, mission, or other
gameplay state.

See [`docs/rpcore-integration.md`](docs/rpcore-integration.md) for the feed
contract and server/client integration example.

## 0.3.0-beta.1

This release prepares that architecture with:

- A server-side versioned service directory. Providers register serializable descriptors; consumers discover the provider resource and advertised methods/events.
- Trusted player-context reads using Open77's verified identity and latest server position snapshot.
- Native observer-scope reads so RPCore can target presentation updates to nearby/current viewers instead of broadcasting another player's outfit across town.
- Existing event dispatch, explicit client-event allowlisting, selected server event notifications, and server-only SQL persistence.
- Open77-correct asynchronous cross-resource examples. Function callbacks are not passed between isolated resource VMs.

This is an experimental foundation. EventCore transports versioned client-safe snapshots published by trusted resources, but does not implement inventory/clothing/mission providers, replace Open77's scheduler/resource lifecycle, or automatically capture state owned by another resource. The implementation status and staged roadmap are in [`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md) and [`docs/RPCORE_PREPARATION_PLAN.md`](docs/RPCORE_PREPARATION_PLAN.md).

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

## Warden roles for tools

EventCore exposes read-only `IsAdmin`, `GetPlayerRoles`, and `GetOnlineAdmins`
exports for trusted server tools. They read Open77's effective ACL and recognize
only the reserved `admin` and `owner` roles as global administrators. Scoped
roles such as `helper`, `moderator`, and `operator` remain distinguishable.
Warden assigns roles; EventCore never promotes players. EventCore declares `acl.read` in its resource manifest. Add each tool resource that needs these queries to `trustedAccessReaders` in `server/access.lua`.

## Compatibility and release

The `0.3.1` archive includes read-only ACL role queries and remains separate from the earlier `0.2.0-beta.1` release. The service directory requires an Open77 server build with server-to-server exports and resource-generation APIs. Verify compatibility on the actual server before enabling it for players.

For legacy adapters, see [`docs/legacy-compatibility.md`](docs/legacy-compatibility.md). EventCore does not patch RED4ext, Open77 binaries, or third-party native plugins. The planned custom-clothing boundary and stable outfit-code rules are in [`docs/server-managed-clothing.md`](docs/server-managed-clothing.md).

EventCore is released as All Rights Reserved. Permission is granted to download, install, and run this release on OPEN//77 servers through the OPEN//77 Workshop. Modification, redistribution, and derivative works are not permitted.