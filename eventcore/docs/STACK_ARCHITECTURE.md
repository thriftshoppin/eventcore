# EventCore stack architecture

## Purpose

Build one extensible Open77 roleplay stack in which the server coordinates and authorizes shared state while each game client runs the presentation and native game integrations that only exist locally. HUDitor is a first-party client layer in this stack, not an optional add-on. RPCore is the player-facing presentation layer. EventCore is the cross-resource API, network coordinator, policy boundary, and persistence service. Warden remains the server operator and ACL authority.

This document defines the target architecture and identifies which pieces exist versus which still need adapters or live verification.

## Stack responsibilities

| Component | Owns | Must not own |
|---|---|---|
| Warden / Open77 ACL | Server operators, permissions, resource lifecycle and server configuration | Client UI state or game-specific mod execution |
| EventCore server runtime | Authenticated client/server messaging, protocol negotiation, server policy checks, domain discovery, event routing, audit metadata, and approved persistence APIs | Every gameplay domain's rules or arbitrary client code execution |
| EventCore client runtime | Stack handshake, client adapter registry, typed requests, server-directed presentation updates, and acknowledgements | Server authority, ACL decisions, or durable gameplay truth |
| HUDitor client layer | Native UI widget integration, layout/editing, responsive placement, and player-local UI preferences | Jobs, faction authority, money, inventory, or other shared gameplay state |
| RPCore | RPCore HUD and player-facing interfaces, including adapters that expose EventCore state through HUDitor | Independent copies of state owned by EventCore or other domain providers |
| Domain resources | Their own authoritative rules and records: map pins, jobs, fixers, live events, NPC systems, inventory, clothing, vehicles, and so on | Direct database access or bypassing the owning domain's API |

The server is the **control plane**: it validates requests, decides what is allowed, owns shared state, and tells clients what to render or attempt. Clients are **execution and presentation planes**: they apply approved native game/UI changes and report success or failure. A client report is never proof of identity, permission, money, inventory, or completed gameplay.

## One shared protocol, many domains

All stack traffic uses versioned, typed envelopes rather than forwarded console strings or arbitrary Lua. The conceptual envelope is:

```lua
{
    protocol = 1,
    kind = "request", -- request, result, event, snapshot, delta
    id = "request-id",
    domain = "map", -- jobs, fixers, npc, hud, live_events, ...
    action = "pin.create",
    schema = 1,
    revision = 12,
    payload = {}
}
```

The transport supplies the real sender/session identity. A client cannot set a different player ID, resource owner, ACL role, or storage namespace in `payload`. Each domain declares its own action schemas, authorization rules, limits, and recipients. Unknown domains/actions, incompatible protocol versions, stale revisions, invalid payloads, and excessive rates are rejected with a structured result.

Use three traffic patterns:

1. **Request/result:** client asks for an action; server validates and the owning domain commits or rejects it; result is returned with the request ID.
2. **Snapshot/delta:** client receives a complete authorized view on join/reload, then ordered changes with revisions. A revision gap triggers a fresh snapshot.
3. **Ephemeral event:** short-lived UI/telemetry or nearby-world changes that do not need durable storage. Coalesce high-frequency updates and scope them to relevant observers/buckets.

Keep event names/domain IDs stable and version payload schemas independently. Do not create a new transport for each future feature.

## Domain ownership and persistence

EventCore provides the safe storage and transport mechanisms already present in the repository. Each gameplay domain remains the source of truth for its own rules and records:

- Map provider validates and owns shared pin definitions and visibility policy.
- Jobs/fixers provider owns job offers, assignments, stages, rewards, and completion.
- Live-event provider owns schedules, participation, and outcomes.
- NPC provider owns server-selected NPC state and replication intent; clients render only supported native models/actions.
- RPCore/HUDitor own local layout and appearance preferences, while server policy may provide a default profile.

Use EventCore's caller-scoped storage for a resource's isolated data, or a typed provider API when other resources need to consume that domain. Do not put all state in one global inventory or generic JSON blob. Persist only durable records; derive current player positions and transient UI state from Open77/runtime state where possible. Durable writes happen after the authoritative server-side mutation, never merely because a client proposed one.

## HUDitor as a first-party client layer

HUDitor is packaged, version-pinned, and maintained as part of the client stack. Its adapter contract should expose a small stable interface:

- `ready`: HUDitor and the supported native widget hooks are available.
- `layout.changed`: normalized widget ID, position/scale/visibility, and local revision.
- `layout.save`: explicit final save boundary.
- `layout.apply`: validated server-provided defaults or the player's saved layout.
- `widget.available`: capability/version information for optional native widgets such as the minimap.

RPCore consumes this interface for its UI, and EventCore may store player preferences through a typed API. HUDitor should not receive arbitrary server scripts. Server-to-client messages contain data and named actions only; the client validates them against its installed HUDitor version and widget schema.

The client stack reports exact component versions and capabilities during handshake. EventCore returns a compatibility decision and server-approved configuration. If a required component is absent or incompatible, disable only the dependent feature, show a clear diagnostic, and leave unrelated client/server resources running.

## Map flow as the first domain

The map demonstrates the general protocol without inventing a replacement for the game map:

1. The server-owned map provider loads validated persistent pins.
2. On client `ready`, EventCore sends a filtered marker snapshot with a revision.
3. RPCore's map adapter asks Open77 to create/update/remove native resource-owned blips; HUDitor handles local placement of the native minimap widget.
4. Admin pin edits are typed requests. Warden/Open77 ACL and the map provider authorize and persist them before broadcasting a delta.
5. Teammate markers are derived from server-held player positions and faction/gang membership, then filtered per recipient. The client does not authoritatively report its own location.
6. Local zoom, pan, open/close, and widget placement remain local unless a specific feature explicitly opts into synchronization.

The same request/result and snapshot/delta contracts can later carry jobs, fixers, live events, and NPC presentation without changing the transport or trust model.

## Extension and approval model

Use two explicit registries:

- **Server resource registry:** installed resource manifests declare dependencies/capabilities; EventCore discovers versioned domain services. Warden/operator review and the existing resource allowlists decide which server resources may use sensitive EventCore APIs.
- **Client integration registry:** a reviewed Lua config lists bundled client components/adapters and their supported versions, capabilities, event/action schemas, and rate limits. It does not authorize a client's claimed identity or grant gameplay rights.

The client can report installed component IDs and versions as compatibility hints. Treat those values as self-reported. Server permission checks always use Open77's authenticated session and Warden ACL. Third-party mods cannot register arbitrary server actions just by claiming to be installed.

## Guardrails that prevent unsafe coupling

- Never relay arbitrary console text, Lua, SQL, file paths, or executable code across the network.
- Never let client payloads choose their sender, domain owner, target namespace, privilege, or server resource identity.
- Keep permissions and authoritative state checks server-side and in the resource that owns the domain.
- Validate payload schema, bounds, version, rate, sequence/revision, and recipient scope before mutation or broadcast.
- Use per-domain persistence collections and stable player/character identity; don't persist transient numeric session IDs as identities.
- Make client operations idempotent where practical; use request IDs and revisions to prevent duplicate/stale writes.
- Scope private state to its owner and team/map data to allowed observers. Do not broadcast full state to every client by default.
- Keep integrations optional at the feature boundary, but make HUDitor a pinned first-party stack dependency. A missing HUDitor should fail clearly and safely, not silently re-enable conflicting stock widgets.
- Preserve upstream credits and licensing terms for bundled HUDitor code; track local patches so updates can be reviewed instead of overwritten.

## Build order

1. **Freeze the contract:** protocol envelope, error shape, domain/action naming, revision rules, and compatibility policy.
2. **Prove the HUDitor bridge:** verify a supported client path from HUDitor's layout event into the EventCore client resource. Do not depend on a privileged debug-only bridge.
3. **Harden the generic transport:** add explicit schemas/allowlists, request IDs, rate limits, structured results, and snapshot resync without changing domain ownership.
4. **Integrate HUDitor + RPCore:** handshake, responsive defaults, local layout editing, per-player persistence, and compatibility diagnostics.
5. **Finish the map provider:** native blip snapshots/deltas, Warden-checked authoring, and faction-filtered player markers.
6. **Add domains independently:** jobs/fixers, live events, NPCs, etc. Each has a provider API, storage namespace/schema, authorization policy, and client presentation adapter.
7. **Verify and release:** test each domain on the target Open77 client/server build, then update changelog/release metadata. No domain is called complete from static code review alone.

## Existing building blocks

The current EventCore source contains an in-memory server event bus, trusted versioned service catalog, explicit client event allowlisting, a sequenced server-to-client state feed, caller-scoped structured persistence, and a paired typed bridge for client requests and opt-in server-directed client actions. Service providers must declare EventCore as a manifest dependency and use IDs namespaced to their actual resource name; this prevents one add-on from squatting another's advertised API. Extend these mechanisms behind stable APIs rather than create parallel transport/storage systems. HUDitor-to-Open77 IPC and live verification remain outstanding. See [`client-bridge.md`](client-bridge.md) for the current API and exact implementation boundary.
