# EventCore 0.3.0-beta.2 checkpoint

## Implemented in this repository

- Server-only Open77 MySQL/MariaDB persistence for event history and explicit JSON player-state records.
- Bounded, parameterized reads/writes; trusted-resource guards; explicit inventory/outfit convenience APIs.
- In-memory priority event dispatcher and controlled client-to-server relay for explicitly allowed event names.
- Opt-in server event notifications for safe, JSON-compatible records.
- Versioned server service directory: provider/resource identity and VM generation come from Open77's export invocation context; descriptors are serializable; stale provider generations are pruned.
- Trusted read-only `GetPlayerContext` and `GetPlayerObservers` APIs for RPCore. Context returns the stable account/install identity, display name, current session ID, latest position snapshot, and routing bucket. Observer results are the current native replication-scope viewers.
- Trusted EventCore client-state feed: `PublishClientState` and `ClearClientState` validate the caller, target, and bounded serializable payload; EventCore assigns channel sequence numbers and clients reject stale packets.
- `state:update` client dispatch with protocol version, channel, schema version, visibility, sequence, and snapshot.
- Cross-resource event `On`/`Off` callback exports removed because Open77 does not transfer Lua functions across resource VMs. `EventCore.On` / `Off` remain internal to the EventCore VM; exported `Emit` results are value-only.
- `0.3.0-beta.1` resource/version API identifiers, updated README, RPCore integration guide, architecture plan, persistence guide, and updated clothing dependency contract.

## Needs live-server verification

- Verify the installed server runtime provides server-to-server `Open77.exports.call`, `GetInvokingResourceGeneration`, and `Open77.resource.generation`. Open77 documents that server exports require an updated server binary.
- Verify RPCore's resource name remains `rpcore` or update the trusted-resource allowlist in `server/persistence.lua` and the context authorization before integration.
- Call `GetRuntimeInfo`, register/list/unregister a test provider, and confirm descriptors are removed after provider reload/stop.
- Query player context during a live session, confirm the Open77 `license`/`userId` fields and position bucket, and check `GetPlayerObservers` against actual native scope.
- Test SQL permissions, schema creation, save/load across a server restart, and queue/drop behavior during an SQL outage.
- Verify client relay permissions and end-to-end event dispatch on the target Open77 build.

## Still planned for RPCore readiness

- RPCore WebUI integration, cached snapshot replay/subscription lifecycle, and HUD visibility/update rules using the EventCore state feed.
- Domain provider integrations for character, inventory, clothing/appearance, missions/objectives, health/needs, economy, and vehicles. Each provider owns validation and authoritative state.
- Event-driven or scheduled state updates with defined cadence and backpressure. EventCore transports published snapshots but does not observe authoritative domains or schedule their updates.
- A concrete RPCore resource built against this contract.

## Boundaries

- The service catalog advertises provider exports; it does not expose provider internals or grant callers authority. Providers must validate methods and arguments themselves.
- Player position is an Open77 replicated snapshot, not a centimetre-accurate live read. Revalidate any gameplay decision at action time.
- Use `GetPlayerObservers` for nearby presentation. Do not broadcast full inventory, character, or outfit state to unrelated clients.
- Automatic event-history writes use a bounded in-memory queue, not a write-ahead log; termination before SQL insertion can lose queued rows.
- Client requests are untrusted. Domain resources validate/commit gameplay results before persistence.
- EventCore does not modify RED4ext/Open77 binaries or read arbitrary native game memory.

## Release preservation

The `0.2.0-beta.1` archive remains a separate, unchanged artifact. This repository and the new archive target `0.3.0-beta.2`.
