# ServerManagedClothing direction

This document records the intended boundary for a future `ServerManagedClothing` Open77 resource that depends on EventCore. It is an integration contract, not a clothing resource implementation.

## Assets and authority are different

The server does not own the player's clothing mesh files. Custom assets must be present in the client's Open77 world profile before Cyberpunk starts. OPEN//77's required-mod system handles that distribution; the resource server declares the required set, while the launcher downloads and installs it when the player connects, before launching the game. That lets the server make its required clothing packages available to players who did not already have them installed, subject to the launcher consent flow and the package's trust/redistribution rules. It is not a download triggered after the player is already in the game, and the set applies to the world rather than being fetched separately for each outfit.

See [Mods your server requires](https://open2077.net/docs/server-mods) for the package and trust rules. Lua resource dependencies and manifest loading are documented in [The Lua resource runtime](https://open2077.net/docs/resource-runtime).

This is separate from deciding whose appearance data a client receives. Required packages may be installed for the world, but live outfit state must follow player proximity: do not broadcast or load every player's outfit for every client. Keep canonical selections and inventory server-side. When a player becomes visible to nearby players, send only the approved appearance snapshot needed by those current observers; the host's normal scope lifecycle governs which player entities are present. When they are out of scope, other clients have no reason to receive their outfit state.

Open77 exposes `Open77.players.observers(subjectId)` and `Open77.players.isInScope(viewerId, subjectId)` for native observer scope checks. ServerManagedClothing should use the same scope-aware delivery pattern as the supplied `open77_appearance` resource, rather than implementing a global broadcast. Send only the minimum approved outfit IDs/component data needed for presentation; never send another player's full inventory or persistent record as appearance data. See the [Open77 Lua API reference](https://open2077.net/docs/api).

ServerManagedClothing should therefore keep a server-side catalog of allowed outfit IDs and the asset packages those outfits depend on. The world must require every package needed by the catalog. Players may request an outfit ID; the server checks the ID against that catalog, role/job permissions, character rules, and any cooldowns before it changes the canonical selection. It should not treat a client-supplied mesh path, item record, or arbitrary outfit code as permission to equip it.

## Stable outfit-code compatibility

Generated outfit codes must describe stable clothing identities, not positions in the current clothing pool. Adding a new gang pack or clothing item must not change the meaning of any saved or shared code.

The future format should carry a code-format version and stable, namespaced outfit/item IDs. For example, an outfit may refer to `maelstrom.street_uniform` and items such as `addon.maelstrom.coat_01`; the catalog maps those IDs to the actual game records and the required asset package. The code should not depend on an array index, display name, local file path, or current catalog ordering.

Compatibility rules:

- Adding clothes appends new stable IDs; it never renumbers existing IDs or reuses retired IDs.
- Renaming an ID adds a permanent alias or migration from the old ID to the new one.
- When an item is retired, keep its decoder/migration and choose an explicit replacement or safe fallback. Do not silently reinterpret an old ID as a different garment.
- Keep the format version separate from the catalog version. A catalog can grow while the code format remains readable.
- Preserve the player's original code if an item cannot currently be applied. Report the missing package/item and use a visible fallback rather than deleting or rewriting the saved outfit.

EventCore's `SaveOutfitCode(playerId, outfitKey, code)` can persist the generated code as a string. `outfitKey` should itself be a stable named key, not a pool index. ServerManagedClothing will still need to validate and decode the code against its server-owned catalog before applying it.

## EventCore's role

EventCore supplies the durable event history and player-state storage. A future ServerManagedClothing resource should declare EventCore as a required resource dependency and use its server exports to:

```lua
dependency "eventcore >=0.3.0-beta.1"
```

- record accepted/rejected clothing selections as server events;
- store the selected outfit ID/code and any saved outfit slots under a character-aware state key;
- restore the saved selection on join/character selection;
- publish only approved, client-safe presentation data to the player and scoped observers.

Use EventCore's `ExposeEvent` for a clothing event only when other trusted server resources need to observe it. A normal clothing request does not need to expose its full payload host-wide. Do not persist a temporary player source as identity; EventCore resolves stable Open77 identity for player-state writes.

## Integration with current appearance handling

The supplied Open77 runtime already includes `open77_appearance` for server-persisted equipment and wardrobe selections, with validation and client presentation. ServerManagedClothing should reuse that as its presentation mechanism for compatible native `Items.*` clothing records instead of creating a second competing wardrobe database. If custom addon outfit codes need their own durable catalog, EventCore's `SaveOutfitCode` can store those codes, but a dedicated adapter must map an approved code to validated presentation records and ask the appearance owner to apply them.

No public server export for that appearance mutation is present in the supplied files. Before implementing this resource, inspect or obtain the appearance resource's supported integration API; if none exists, add a deliberate public server API there instead of writing directly into its SQL tables or relying on its private network event names.

## Join, proximity, and missing-asset behavior

The selected outfit is logical server state; its visuals depend on the client's installed, compatible files. A future implementation needs a known safe fallback when an outfit or required package is absent, and should not block a player's join on an unverified client claim that an asset rendered. Open77's required-mod set is prepared before game boot, so the server's mod package declaration—not a client-supplied readiness flag—is the baseline availability contract. The required-mod system requires player consent and applies package trust and redistribution rules; a mod whose author disallows rehosting uses the platform's player-fetch flow instead of the server redistributing it.

The practical split is: install the world's required asset packages at connection time, then stream or apply a player's appearance only to clients currently in that player's native scope. Proximity can limit live appearance traffic and presentation; it does not make required mod archives download only when someone walks nearby. The required-mod set belongs to the world and is installed before the game launches. This preserves the intended outcome: clients can render nearby players' custom clothes without loading the clothes or outfit data of someone across town.

## Current stage

Implemented now: EventCore can persist player state and specific outfit codes, keep client requests behind server validation, and emit explicitly exposed events to other server resources.

Not implemented yet: the `ServerManagedClothing` resource, job/role catalog, uniform selection UI, client asset application, outfit package manifest, or adapter to `open77_appearance`. Those need the clothing resource and its desired data/API contract.
