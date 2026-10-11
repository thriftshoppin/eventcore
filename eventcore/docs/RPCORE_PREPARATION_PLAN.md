# EventCore preparation plan for RPCore

Target release: `0.3.0-beta.2` (EventCore feed transport; RPCore migration remains follow-on work)

## Preserve the existing release

Keep the already-produced `0.2.0-beta.1` archive unchanged. Develop each follow-on as a new release version in the working repository and preserve previous archives.

## Intended responsibility split

- **EventCore** is the shared server runtime and service hub. It exposes versioned, serializable contracts; provides trusted player/session context; brokers service discovery; dispatches permitted events; and owns generic server-only persistence.
- **RPCore** is a consumer and presentation extension. It asks EventCore and gameplay providers for approved state, then turns that state into an immersive HUD and player-facing tools. It does not query EventCore's SQL tables directly or treat client proposals as authoritative state.
- **Domain providers** remain responsible for their own rules and canonical state. Inventory decides inventory; appearance/clothing decides approved outfits; mission resources decide objectives and outcomes. Providers publish a versioned service descriptor and their own supported exports.
- **Open77** remains the authority for connection identity, position, native observer scope, resource lifecycle, and client presentation/network transport. EventCore should wrap documented capabilities only where RPCore needs a stable cross-resource contract.

## Added in `0.3.0-beta.1`

1. Publish EventCore's release and service API version from the runtime.
2. Add a server service directory. Providers register a serializable descriptor; EventCore derives provider name and generation from Open77's export invocation context, lists available services, and removes stale registrations when providers stop/reload. Descriptors advertise methods/events; they do not transfer functions or grant authority.
3. Add a trusted, read-only player context query for RPCore with authenticated account/install identity, verified display name, session ID, and the latest server position/routing bucket. Add an observer-scope query so presentation code can target current viewers instead of broadcasting appearance state globally.
4. Keep provider business logic and persistence ownership outside EventCore. EventCore's persistence remains an explicit service called by the resource that owns a state change.
5. Remove cross-resource callback-based `On`/`Off` examples/exports from the new contract. Keep the in-resource dispatcher, use Open77 host-wide events for serializable event notifications, and use Open77 server exports for request/response calls.
6. Document a minimal RPCore server-side integration example, API compatibility, trust boundaries, and remaining live-server verification.

## Defer until the next stages

- RPCore WebUI integration, cached snapshot replay/subscription lifecycle, and update cadence over EventCore's new client state feed.
- Event-driven position updates, task supervision, and feature/resource lifecycle management beyond Open77's own runtime.
- Inventory, clothing, mission, health, needs, vehicle, and economy provider implementations or schema migrations.
- Any change to RED4ext/Open77 binaries or unsupported native hooks.

These are separate because their authoritative source and update cadence must be identified per provider. `0.3.0-beta.2` implements transport only; it does not claim the complete RPCore HUD integration is implemented.

## Follow-on delivery order

1. **Runtime manager:** build a plugin/module registry over the service directory, with declared dependencies, health/readiness, task ownership, cancellation on provider-generation changes, and resource diagnostics. Open77 continues to start and stop actual resources; EventCore coordinates its own framework plugins and jobs rather than taking over platform resource control.
2. **Player and world services:** add stable session lifecycle events and validated context/state contracts for identity, position, routing bucket, life, vehicles, and native scope. Keep position freshness and scope semantics explicit.
3. **Authoritative domain providers:** integrate character, inventory, appearance/clothing, missions/objectives, economy, and other server-owned systems one provider at a time. Each provider validates changes and owns its persistence mutations.
4. **HUD feed integration:** EventCore 0.3.0-beta.2 defines a versioned client-safe snapshot transport; integrate provider updates, replay/subscription lifecycle, cadence/backpressure, and native-scope routing. RPCore renders the feed; it must not query SQL or trust client state as fact.
5. **RPCore integration:** attach the immersive HUD to the EventCore feed, then verify join, gameplay changes, scope transitions, reconnect, resource restart, and persistence on a live server.

The API contracts and source of truth for each domain should be agreed before implementing its provider. Avoid a single catch-all JSON blob that makes unrelated modules share undocumented fields.

## Acceptance boundary

Each archive must carry its version string and documentation that labels implemented versus planned behavior. The prior `0.2.0-beta.1` zip must retain its existing contents.

Open77 integration references: [Lua resource runtime](https://open2077.net/docs/resource-runtime), [cross-resource server exports](https://open2077.net/docs/server-exports), [player identity](https://open2077.net/docs/identity), and [Lua API reference](https://open2077.net/docs/api).
