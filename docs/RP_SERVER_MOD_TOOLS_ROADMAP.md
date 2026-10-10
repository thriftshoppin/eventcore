# Open77 RP Server Tools Roadmap

## Mission

Build a complete, modular roleplay server stack for Open77: persistent characters, custom clothing, inventory and economy, vehicles, apartments, jobs, gangs/factions, police, map markers, live events, NPC interactions, and the operator tools needed to run those systems. The stack must let separately installed mods work with each other through documented APIs while keeping each domain's rules and records under one clear owner.

This is a build checklist, not a claim that the listed systems already exist. A checked source item means code or a package exists locally; it is not complete until its acceptance checks pass on the target Open77 client and server.

## Product and security model

| Layer | Responsibility | Authority boundary |
|---|---|---|
| Open77 and Warden | Resource lifecycle, signed resource delivery, network sessions, native game APIs, operator ACL and global admin assignment | Warden is the only authority for global roles. Do not impersonate its ACL or use the privileged debug runtime as a production API. |
| EventCore | Stable cross-resource APIs, authenticated message routing, service discovery, scoped persistence fallback, common policy hooks, diagnostics and migration/version contracts | EventCore does not accept arbitrary SQL, Lua, console strings, resource paths or executable code from a client. It does not own every gameplay domain. |
| Domain resources | Characters, inventory, clothing, vehicles, property, jobs, factions, police, map data, NPCs and events | A domain is authoritative for its records and decisions. Other resources call its API rather than writing its tables. |
| RPCore | Player-facing HUD, chat, map controls, settings and admin interface | RPCore displays and submits typed requests. It is not a second source of truth. |
| Client companion mods | HUDitor/native widget adapters and other approved game-side integrations | Client reports are hints or execution results, never proof of identity, permissions, money, inventory or completed gameplay. |

The server controls shared state. A client can request an action or apply presentation data, but the owning server resource validates the player, authorization, world conditions, and resulting state before saving or broadcasting anything.

## Status key and current baseline

- **Source exists**: present in the local checkout; not necessarily target-build verified.
- **Needs verification**: source exists but must pass the stated live acceptance checks.
- **Not built**: implementation is still required.
- **Blocked**: depends on an external supported API, SDK, permission, or decision.

| Area | Current local position |
|---|---|
| EventCore base | **Source exists / needs verification.** Service catalog, ACL reads, scoped persistence, event/state feed, chat/admin surfaces, and a typed bridge are in the EventCore checkout. The bridge has not been verified against the current live client/server. |
| RPCore | **Source exists / needs verification.** HUD, chat/map UI, and the Open77 resource are in the RPCore checkout. Map, HUD, chat, controller, and server-storage behavior still require integrated playtests. |
| Test-bench resource alignment | **Known blocker.** The installed `2.31.21+op77.132` folder contains EventCore `0.6.5` and RPCore `0.3.3`; local checkouts declare `0.7.0` and `0.3.4`. The installed EventCore has no bridge files. A bridge test against that server would test the wrong source revision. |
| HUDitor companion | **Source exists / needs verification.** A local HUDitor-derived package is version-pinned and contains responsive defaults, vitals ownership protection, local save/restore, and a CET layout-save hook. Its layout hook does not currently deliver data to EventCore. |
| RP gameplay domains | **Mostly not built.** The roadmap below treats persistent characters, inventory, custom clothes, owned vehicles, apartments, jobs/fixers, factions/police, and gameplay loops as separate deliverables. |
| Live server console success logs | **Not complete.** Bridge failure warnings exist in EventCore source; successful HUDitor layout updates do not reach the live server console. |
| Git/deployment | Local changes are not a release. Test the test bench first. Do not commit, push, or deploy a pending build until the user explicitly says “okay.” |

## Dependency order at a glance

```text
Open77/Warden compatibility and delivery
  -> EventCore API, transport, persistence, observability
    -> account identity and character lifecycle
      -> inventory + economy primitives
        -> clothing/appearance, vehicles, apartments
          -> inventory-backed job loops, fixers, factions/gangs/PD, map visibility
            -> NPC coordination, PvE events, hacking/netrunning, businesses
              -> complete player/admin UI, operations and release
```

RPCore presentation and the HUDitor integration proceed alongside these stages, but a pretty UI must not be used to conceal missing domain logic.

# Milestones

## M0 — Freeze scope, ownership, and release rules

**Goal:** know exactly what belongs in the core and what each add-on owns before several mods write the same state.

- [ ] Maintain one feature register with: feature ID, owning resource, public API, persistent records, permissions, client components, UI surface, dependencies, test status, and release status.
- [ ] Define stable resource IDs and dependency direction. Domain resources may depend on EventCore; they should call one another directly when a domain API exists. EventCore is the compatibility/persistence fallback, not a mandatory hop for unrelated domain calls.
- [ ] For each piece of state, name one writer and any read-only consumers. Reject designs where RPCore and a gameplay resource both save the same value.
- [ ] Preserve the user's release policy: no public license until requested; no commit, push or server deploy before explicit approval; test the bench before publication.
- [ ] Record upstream attribution, exact versions, permissions, source archive hashes and license terms for every bundled Nexus/client dependency.

**Exit gate:** every first-release feature has an owner, dependencies, API sketch, data owner, permission rule, and test case.

## M1 — Establish the supported Open77 client/mod boundary

**Goal:** make approved native client mods communicate through the normal authenticated Open77 resource transport without a hidden endpoint or privileged debug escape hatch.

- [ ] Identify a supported production API from CET/REDscript/native client mod code into an Open77 client resource. Open77 resource Lua VMs are isolated; an ordinary local event in one resource is not a bridge to CET.
- [ ] If there is no supported API, choose and implement a reviewed platform extension: either an Open77-supported adapter interface or a native companion built against RED4ext that hands bounded data to the Open77 client runtime. Do not silently substitute `open77_debug`, arbitrary Lua evaluation, direct SQL, or an unauthenticated public/local HTTP listener.
- [ ] Define the local envelope: protocol/schema version, component ID, action ID, client-local revision, payload size limit, allowed widget/domain fields, and explicit result/error shape.
- [ ] Bind the handoff to the current game session/resource generation. EventCore must still derive player identity from Open77's authenticated callback source, not from adapter payload.
- [ ] Implement backpressure and coalescing: layout drags may change every frame, so transmit the final save (and optionally a throttled preview) instead of flooding the server.
- [ ] Fail closed when the bridge or dependency is missing. Local HUDitor/RPCore behavior must continue, and the UI must report `local-only` rather than imply synchronization.
- [ ] Add compatibility/version reporting for client components. Treat installed-mod lists and versions as self-reported compatibility hints, never as trust or permission grants.

**Exit gate:** one non-privileged HUDitor layout save reaches an Open77 client resource through the supported handoff, then EventCore, and results in a server-console success line tied to the authenticated session. A malformed or oversized report is rejected.

## M2 — Complete and verify EventCore's shared framework

**Goal:** provide one reusable contract every RP resource can consume safely.

### API and transport

- [x] Local source has a versioned service directory and a first typed bridge for client requests plus opt-in server-directed named client actions.
- [x] The typed client request path has request IDs and bounded in-memory replay protection; durable idempotency remains part of each provider's domain transaction.
- [x] Service registration requires an EventCore dependency and a caller-owned service ID namespace; a provider cannot advertise another resource's API name.
- [ ] Verify callbacks in both directions on the exact server/client build; verify export identity and resource generation behavior through start, stop, restart, and failure.
- [ ] Finalize a stable envelope: protocol version, domain, action, schema version, request ID, server revision, payload, and structured error. Keep request/result, snapshot/delta, and ephemeral event semantics separate.
- [ ] Add explicit per-action schema validators. A registered handler name and JSON size cap alone do not define valid domain data.
- [ ] Verify request-ID replay behavior under duplicate, concurrent, expired, and server-restart cases; add timeout/cancellation behavior, bounded retries where safe, and snapshot resync when a client detects a revision gap.
- [ ] Set per-action payload, result, rate, concurrency, and recipient limits. Coalesce high-frequency transient updates and monitor queue/backpressure.
- [ ] Keep the server callback source as the sole player identity; never accept a caller-selected player ID from a client payload.

### Access, storage, and audit

- [x] Local source has a separate storage whitelist, bridge whitelist, and Warden-backed read-only admin queries.
- [ ] Verify storage namespace isolation, trusted-caller checks, transaction rollback, SQL outage behavior, and persistence after server restart.
- [ ] Keep `EventCore.Whitelist` (scoped storage) separate from `EventCore.BridgeWhitelist` (typed network actions). Document what each grant allows and the exact manifest dependency needed.
- [ ] Add domain storage migrations with schema versions, backups/rollback plan, and bounded migration logs before changing production data.
- [ ] Add a sanitized server audit line for accepted/rejected action metadata: timestamp, player/session, domain/action, provider, request/revision, result and reason. Do not log secrets, full private payloads, access tokens, or unnecessary personal data.
- [ ] Add an admin diagnostics view for provider status, bridge action catalog, recent sanitized errors, queue health, database status and compatibility reports.
- [ ] Ensure logs distinguish `registered`, `request_received`, `accepted`, `rejected`, `client_applied`, `timed_out`, and `provider_unavailable`; never print “applied” when only a client acknowledgement was received.

### Services and lifecycle

- [x] Local source has service discovery, runtime/build metadata, state feeds, role queries and an EventCore admin entry point.
- [ ] Verify start ordering, declared dependencies, stale registration cleanup and provider reload lifecycle.
- [ ] Add explicit API deprecation policy and compatibility tests so mods can target supported EventCore API versions.
- [ ] Document direct domain-to-domain integration and when a consumer should fall back to EventCore storage/events.

**Exit gate:** a sample provider can register, validate, authorize, persist, publish a snapshot/delta, survive restart, and unregister on reload; invalid calls fail closed with useful sanitized diagnostics.

## M3 — Player accounts, characters, and lifecycle

**Goal:** support persistent roleplay identities and safe join/spawn flow before adding properties or jobs.

- [ ] Define stable account identity and separate it from temporary session/player IDs. Define character ID, ownership, display name, state and active-character selection.
- [ ] Build character create/list/select/update/archive flows with name uniqueness, field bounds, server validation, and per-account limits.
- [ ] Define character creation defaults, appearance references, starting inventory/cash, spawn selection, death/respawn and disconnect/reconnect lifecycle.
- [ ] Add server-owned character data schema and migrations; keep sensitive account identity off client UI payloads.
- [ ] Publish `character.ready`, `character.changed`, `character.selected`, `player.spawned`, and `player.left` typed lifecycle events with documented ordering.
- [ ] Ensure dependent resources wait for character readiness and clean up transient session state on drop.
- [ ] RPCore: build character selection/create UI and reconnect loading state only after server APIs are stable.

**Exit gate:** two characters on one account retain separate state; reconnect restores the selected character, and malformed/unauthorized character changes cannot affect another account.

## M4 — Inventory, items, and economy

**Goal:** establish shared transactional primitives required by clothes, vehicles, housing, jobs and shops.

- [ ] Define canonical item catalog IDs, stack rules, metadata schema, weight/slot limits, durability/unique items, and migration rules.
- [ ] Create inventory provider with server-only grant/remove/transfer/split/merge/equip APIs and atomic multi-item operations.
- [ ] Define cash/account/wallet model, ledger entries, currency rules, fees, escrow/hold, deposit/withdraw/transfer, and transaction idempotency.
- [ ] Require an owning resource permission for every mutation; client UI can request a transaction but cannot send an authoritative balance or inventory snapshot.
- [ ] Define cross-resource purchase contract: seller quotes price/stock, buyer confirms, inventory and wallet commit atomically or both roll back.
- [ ] Add audit history for high-value transfers and admin review tools; log metadata, not secrets.
- [ ] Add RPCore inventory/wallet UI only after provider contracts and pagination/weight responses are fixed.

**Exit gate:** duplicate/replayed purchase requests cannot duplicate money/items; reconnect and restart preserve balances and inventories; rejected transactions leave both sides unchanged.

## M5 — Clothing, appearance, and custom assets

**Goal:** make custom outfits persistent and compatible with inventory/character selection.

- [ ] Inventory each approved clothing/appearance asset package: source, version/hash, slot coverage, required loaders, installation paths, permissions/license, conflicts, and client size.
- [ ] Define server-side outfit records as references to approved asset/item IDs, not arbitrary client file paths or arbitrary mesh names.
- [ ] Build wardrobe, equip/unequip, outfit save/rename, shop purchase and allowed-slot validation APIs. Decide which clothing is owned, job/faction restricted, uniform-issued, or purely cosmetic.
- [ ] Connect equip operations atomically to inventory; prevent equipping an item the character does not own or is not permitted to use.
- [ ] Add client capability check for required clothing assets; fail clearly if a required package is absent or incompatible.
- [ ] Add admin tools to issue/revoke approved uniforms with actor, target, reason and audit record.
- [ ] Test clothing persistence through character switch, reconnect, death/respawn, vehicle entry, resource restart and missing asset.

**Exit gate:** a purchased custom clothing item is validated, equipped, saved to the correct character, restored on reconnect, and rejected for a character without ownership/permission.

## M6 — Vehicles, garages, keys, and ownership

**Goal:** create persistent player-owned vehicles with server-controlled access and compatible world presentation.

- [ ] Define vehicle catalog IDs, approved model list, ownership, registration, condition, fuel, storage, key/authorized-driver records, and impound state.
- [ ] Build purchase/transfer/sell/garage/store/retrieve/repair/impound APIs. Couple purchase to the economy transaction contract.
- [ ] Validate spawn model, position, routing bucket, distance, garage capacity, player state, cooldown and ownership on the server.
- [ ] Define vehicle entity persistence and crash/restart recovery; do not treat a client entity handle as durable identity.
- [ ] Implement keys/access rules for owners, passengers, shared keys, rentals, factions and job fleets.
- [ ] Add fuel stations, fuel type/capacity/consumption rules, refueling transactions, fuel price ownership, and recovery after disconnect; use one shared vehicle condition/fuel contract for player and job fleets.
- [ ] Add mechanic workflow: inspection, diagnosis, repair quote, parts/material consumption, work order, payment/approval, and vehicle condition updates. Validate mechanic role/duty, proximity, vehicle identity and payment server-side.
- [ ] Define towing/impound and roadside assistance handoffs so police, mechanics and vehicle storage do not implement conflicting ownership rules.
- [ ] Add RPCore garage/vehicle UI and ownership blips only from server-authorized results.
- [ ] Test duplicate spawn prevention, concurrent garage requests, disconnect during purchase, entity despawn, and resource restart.

**Exit gate:** one owned vehicle has a stable record, cannot be duplicated by replay, obeys key/access rules, and is recoverable after disconnect/restart.

## M7 — Apartments, property, and storage

**Goal:** support player housing as a durable gameplay system rather than a UI-only location list.

- [ ] Decide supported property types: apartment, room/rental, business, faction property, interior instance, and public/private shared property.
- [ ] Define property catalog, coordinates/interior entry, capacity, owner/tenant/co-owner, rent/deposit, access roles, furniture/decoration limits, storage and state version.
- [ ] Confirm Open77 APIs for interior/instance/routing-bucket behavior before designing around them; mark unsupported native behavior as a dependency, not a fake feature.
- [ ] Build server APIs for list/view/lease/buy/renew/evict/transfer/access/lock/unlock/enter/leave and admin recovery.
- [ ] Keep property authorization server-side; check proximity, character, payment, occupancy, lock state, and routing context on every entry or mutation.
- [ ] Give property storage its own inventory containers with access checks and transaction rules; do not create a second inventory implementation.
- [ ] Add rent billing, missed payment grace, eviction, offline owner handling and audit trails.
- [ ] Add RPCore map location, property search, lease panel and key/guest UI.
- [ ] Test capacity races, concurrent leases, reconnect inside an interior, instance cleanup, rent failure, and admin restoration.

**Exit gate:** a player can obtain and access a property under policy, store/retrieve items via inventory, persist ownership/lease state, and safely leave/rejoin without instance leaks.

## M8 — Jobs, fixers, missions, and progression

**Goal:** define repeatable server-authoritative work loops.

- [ ] Define job roles, requirements, duty state, uniform/loadout, pay rules, cooldowns, shift lifecycle and supervisor permissions.
- [ ] Build job offer/accept/start/objective/complete/cancel/fail APIs with an explicit server-owned state machine and versioned objective schemas.
- [ ] Define fixer contact/mission templates, prerequisites, active mission slots, stages, deadlines, location targets, rewards and cancellation/recovery.
- [ ] Implement an extensible job catalog and reusable shift/objective/reward engine before adding job-specific scripts. Every job declares its resource/API version, role requirements, allowed actions, objective types, payout policy, cooldowns, and failure/recovery behavior.
- [ ] Add first job families as separate tested modules: fixer gigs/contracts; police patrol/dispatch; MaxTac escalation/response; mechanic work orders; refueling/fuel delivery; garbage collection/routes and disposal. Keep MaxTac as a distinct high-severity duty/callout policy layered on police/dispatch, not an admin permission.
- [ ] For garbage collection, model assigned route stops, pickup capacity, accepted waste types, vehicle requirement, disposal point, route expiry, and per-stop idempotency; do not pay for client-reported stops without server-verifiable evidence.
- [ ] For refueling jobs, model company/job-owned tanker or service vehicle, stock, delivery target, quantity, price/contract and reconciliation against fuel consumed; protect against duplicated deliveries and self-issued payouts.
- [ ] For mechanic jobs, connect duty, work orders, approved parts, quotes, customer authorization, payment and persistent vehicle condition through the vehicle/economy providers.
- [ ] For police and MaxTac, add duty, dispatch priority, incident lifecycle, response assignment, evidence/action audit, custody/release flow, and escalation/de-escalation rules. Scope sensitive player-location feeds to authorized on-duty units.
- [ ] Build a netrunning/hacking minigame as a versioned challenge service: server issues a bounded challenge seed/rules/deadline, and RPCore opens an immersive full-screen “in their head” interface while the player is hacking. The client returns an attempt; server validates timing/attempt limits and computes outcome. Define target/access rules, trace/alarm consequences, cooldowns, rewards, abort/reconnect handling and audit. Never let client-supplied success directly grant access, money or items.
- [ ] Keep fixer missions and PvE event objectives on the same objective contract where possible, while preserving each domain's ownership and authorization.
- [ ] Validate each objective on the server using authoritative state or supported Open77 data. Client events may report attempts, not completion truth.
- [ ] Use idempotent payout and inventory awards tied to mission/job instance IDs; prevent replayed completion rewards.
- [ ] Support mission state recovery after disconnect/reconnect and resource restart.
- [ ] Add RPCore job board, job status, objective, fixer contact and result screens; use map markers only for authorized active content.
- [ ] Add admin create/inspect/cancel/compensate tools with reason logging.

**Exit gate:** a full job or fixer mission can be accepted, progressed, completed once, paid once, and recovered/failed correctly under disconnects and invalid client events.

## M9 — Gangs, factions, police, reputation, and team visibility

**Goal:** support organizations and role-gated shared play without leaking player locations or staff privileges.

- [ ] Define organization IDs/types, membership, ranks, invitations, roster visibility, territory/standing, alliances, rivalries and join/leave/transfer rules.
- [ ] Keep global Warden `admin`/`owner` separate from RP ranks such as police, gang leader, faction officer or dispatcher.
- [ ] Define scoped permissions for each action: roster view, team map markers, uniform access, vehicle access, property access, dispatch, arrest/search, organization management.
- [ ] Add faction/gang membership APIs and cache invalidation on join/leave/rank change.
- [ ] Create police-specific duty, dispatch, incident, arrest, evidence and release contracts only when the game APIs and legal rules are decided; every action must be logged and attributable.
- [ ] Define police-to-MaxTac escalation handoff (severity criteria, dispatch notification, assigned response, incident ownership, de-escalation and audit) without conflating either role with Warden admin.
- [ ] Derive team map markers from server-known player locations and membership, filtered per recipient. Never show every player by default; use scope, duty state, privacy, routing bucket and opt-in rules.
- [ ] Define reputation/standing as a domain-owned score with limits, decay, provenance and anti-farm rules; no client may write its own score.
- [ ] Add RPCore roster, duty, faction/gang panels and map visibility indicators.

**Exit gate:** only eligible team members receive team-only markers/rosters; rank changes apply promptly; no player can self-assign ranks or global admin.

## M10 — Native map, blips, locations, and live world events

**Goal:** use the game's map renderer and add persistent, authorized server-owned content.

- [ ] Keep the native minimap/City Map as the renderer. Do not substitute a blank fake map panel or redraw world tiles as a WebUI.
- [ ] Confirm the Open77 native blip API signatures, lifecycle and per-client ownership on the current build.
- [ ] Define blip schema: stable ID, map coordinates, native sprite/icon ID, label, color/scale, category, expiry, creator, visibility rule, resource owner and schema version.
- [ ] Build create/update/delete/list APIs with admin/staff checks, world-coordinate bounds, rate limits, deduplication and persistence.
- [ ] Apply filtered snapshots on ready and ordered deltas on mutation; recover from gaps with snapshot fetch; clear resource-owned blips on provider stop.
- [ ] Implement categories: public POI, personal waypoint, faction/gang team marker, police/dispatch, job/fixer objective, temporary event, property/business.
- [ ] Make player arrows opt-in and policy-filtered. Prevent location leakage to unrelated players and respect team/duty/routing scope.
- [ ] Add admin marker editor/list, player map locations tab, accessible icon names and invalid-icon feedback.
- [ ] Build live-event schedule/instance/start/join/leave/state/result flow; broadcast only to participants/eligible observers and persist durable outcomes.
- [ ] Support authored custom server events with templates, prerequisites, time windows, participant caps, routing/instance rules, join/leave, objectives, rewards, cancellation, cooldowns and operator controls. Distinguish ambient/world events from opt-in instanced PvE so one cannot unexpectedly force players into the other.
- [ ] Add event director/coordinator APIs that compose NPC encounters, map objectives, faction/police dispatch, inventory/economy rewards and cleanup through typed provider calls. The coordinator owns orchestration state only; each domain still validates its own actions.
- [ ] Define event phases (scheduled, announced, staging, active, resolving, completed/failed, cleanup), durable event IDs, idempotent participant rewards, reconnect policy, max concurrency, global/per-area budgets and rate limits.
- [ ] Test map opening/closing (M/Escape; B remains close/back only), minimap visibility, native map rendering, icon choice, team filtering, respawn, resource reload and no duplicate pins.

**Exit gate:** a persisted pin appears on the real game map for its intended audience, survives reconnect/restart, disappears when removed/expired, and never leaks private/team data.

## M11 — NPCs, shops, businesses, and world interactions

**Goal:** build supported world interactions that feed the same economy, inventory, job and property services.

- [ ] Inventory supported Open77 NPC/entity/interactions APIs and approved game models/actions; do not claim arbitrary AI or unrestricted native game control.
- [ ] Define NPC/business identity, location, schedule, interaction radius, service catalog, stock, prices, owner, duty state and persistence.
- [ ] Build interaction request/response APIs with server-side distance, line-of-sight where available, cooldown, state and permission checks.
- [ ] Connect shops to inventory/economy atomic transactions; connect businesses to ownership/property, staffing, stock and ledger services.
- [ ] Define NPC spawn/despawn/recovery, population limits, routing buckets and cleanup when a resource stops.
- [ ] Add NPC coordination contracts for encounter groups: spawn budget, role/archetype, patrol/guard/hostile behavior supported by Open77, target/aggro policy, leash/timeout, persistence class, event owner, routing bucket and deterministic cleanup. Avoid promising autonomous behavior the runtime cannot expose.
- [ ] Implement PvE encounter primitives (waves, objectives, extraction/defense, boss/elite flags, fail conditions, scaling bands and rewards) as event-owned state machines driven by server-validated NPC/entity events.
- [ ] Connect fixer jobs, custom events and police/MaxTac response to the NPC/event coordinator through typed, versioned requests; guard against duplicate spawns and cross-instance target leakage.
- [ ] Add RPCore interaction prompts, shop/ATM/garage/job interfaces with keyboard/controller accessibility.
- [ ] Test unsupported models, out-of-range calls, concurrent purchases, NPC despawn and duplicate entity prevention.

**Exit gate:** supported NPC/business interactions call domain APIs, validate proximity/state server-side, and never create a client-only purchase or reward.

## M12 — RPCore player experience and EventCore admin operations

**Goal:** expose the actual systems without making a separate unmaintainable UI for every resource.

- [ ] Finalize one style/token system and resolution-aware layout for standard, ultrawide, windowed, and changed monitor configurations.
- [ ] Keep chat top-left, show native command output/errors/help/suggestions, one source label per message, and preserve existing Open77 command registration and ACL behavior.
- [ ] Keep HUD panels movable/resizable with saved local defaults; ensure native widgets have a single owner and no duplicate health/stamina bars.
- [ ] Integrate HUDitor for native widgets; use RPCore's responsive layout for RPCore WebUI panels. Keep local layout functional when EventCore is offline.
- [ ] Build player-facing character, inventory, clothing, wallet, garage/fuel/mechanic, apartment, job/fixer, faction, map, dispatch and PvE event panels as their APIs become ready; make netrunning a dedicated immersive full-screen surface with clear exit/cancel behavior.
- [ ] Build one EventCore admin entry point for diagnostics and reviewed domain tools, with Warden checks on every command/action. Warden remains the only global role assignment path.
- [ ] Show errors and server status clearly. Do not show success until the authoritative server result is returned.
- [ ] Persist preferences with schema version and user/character ownership; provide reset and migration behavior.

**Exit gate:** UI is a view over server/domain APIs, works without trusting hidden client state, passes display/input tests, and clearly reports offline/unsupported features.

## M13 — Nexus/client-mod inventory and packaging

**Goal:** integrate third-party client mods deliberately, without treating Nexus downloads as a common plugin API.

### Current selection

| Component | Role | Status |
|---|---|---|
| HUDitor 1.1.0 by Pacings | Move/resize native HUD widgets; local saved layout | Bundled/adapted in RPCore's local client package; layout hook and CET diagnostics are present, but server sync is not. Recheck current Nexus permissions before publishing the derivative. |
| Codeware | HUDitor required framework | Client dependency; do not add as an EventCore resource. |
| Cyber Engine Tweaks | HUDitor required CET runtime and local Lua adapter host | Client dependency; currently used for HUDitor local hooks. It has no verified Open77 transport handoff in this stack. |
| Input Loader | HUDitor required input binding support | Client dependency. |
| Mod Settings | HUDitor configuration UI | Client dependency. |
| RED4ext | Native plugin loader/framework | Client dependency and potential base for a reviewed native bridge if Open77 exposes a supported integration point. |
| redscript 0.5.31+ | HUDitor scripts | Client dependency. |

No other Nexus gameplay/HUD mod is currently selected. Add a package only after completing every item below:

- [ ] Name the server feature it enables and identify a concrete API/hook to observe/control it.
- [ ] Read its source and dependency tree; pin exact file/version/hash and supported game build.
- [ ] Check permissions/license, attribution and redistribution rights before bundling or patching it.
- [ ] Check for overlapping UI/gameplay ownership and known conflicts with the already selected stack.
- [ ] Write a narrow adapter for its documented hooks; do not infer behavior from console output or private internals without a compatibility test.
- [ ] Route data through Open77/EventCore with bounded schemas and server authorization. Never give the Nexus mod database credentials or global admin rights.
- [ ] Package it through the supported Open77 required-mod/launcher flow, pass Warden review for executable DLL/REDscript/CET content, and verify client installation/compatibility reporting.
- [ ] Document disable/removal behavior and prove the core server still starts if the optional integration is absent.

**Important:** installing the six HUDitor dependencies does not make arbitrary Nexus mods compatible with EventCore. Each distinct mod runtime needs an adapter. Do not promise automatic dependency-tree discovery/installation until the client exposes trusted package metadata and the launcher supports a reviewed requirement declaration.

## M14 — Test, operate, and release

**Goal:** make a stable, recoverable test build before committing/publishing it.

### Automated/static checks

- [ ] Manifest validation: resource IDs, versions, files, dependency order, permissions, auto-start, resource load list.
- [ ] Lua syntax/static checks on all changed resources; schema validation for config/default JSON; package file/hash inventory.
- [ ] API contract checks for missing methods, wrong resource name, schema mismatch, unknown actions, invalid IDs, non-finite numbers and oversized payloads.
- [ ] Security cases: forged identity, unlisted resource, missing dependency, unauthorized admin, replay, burst rate, wrong recipient, team data leakage and stale generation.
- [ ] Persistence cases: concurrent write, transaction rollback, SQL outage/recovery, migration, reconnect, resource restart and server restart.

### Live test bench

- [ ] Deploy only to the designated local test bench after creating a restorable copy of current resources/configuration.
- [ ] Restart using the agreed visible `start.cmd` flow and wait for the console and local panel to become reachable before connecting.
- [ ] Connect at least two clients when testing identity, faction visibility, map sharing, inventory transfers and apartment/job concurrency.
- [ ] Verify server console shows action lifecycle with sanitized logs; CET console diagnostics are not a substitute for server logs.
- [ ] Test 16:9 and ultrawide/windowed resolutions, keyboard/controller inputs, player join/leave, respawn, reconnect, resource reload and missing optional mod.
- [ ] Verify Warden roles, command ACLs, admin audit trail, no player self-promotion, no public/private marker leak, no duplicate rewards/vehicles, and no client-authored durable truth.
- [ ] Record build ID, resource versions, test date, test steps/results, known defects, and rollback trigger in the release checklist.

### Release/deploy sequence

- [ ] Update README, changelog, install guide, dependency list, compatibility matrix, and `open77.lua` versions in each changed repository.
- [ ] Review diffs and ensure generated package matches the tracked source; verify bundle file list and third-party credits/rights.
- [ ] Make local commits only after user approval; keep EventCore and RPCore commits in their respective repositories.
- [ ] Deploy the approved commits to the test server, verify the exact build, and record rollback instructions.
- [ ] Push to the user's GitHub repositories only when explicitly asked; do not publish a public license or release prematurely.
- [ ] Promote a tested build only after the user accepts the test result.

**Exit gate:** install from the documented package on a clean client/server, complete the acceptance suite, recover from rollback, and match repository commits to the tested deployed files.

# First playable release definition

Do not call the stack a functioning RP server until all of these work together end-to-end:

- [ ] A player connects, creates/selects a character, spawns, disconnects, and returns to the same character state.
- [ ] Character inventory, wallet and appearance persist and cannot be forged by the client.
- [ ] Custom clothing assets install through the approved client path, validate against ownership/permissions, and equip/persist correctly.
- [ ] A player earns/spends money through at least one complete job/shop loop with no duplication on retry/reconnect.
- [ ] At least one end-to-end sample from each intended loop is proven before calling the toolset complete: fixer contract, police/MaxTac dispatch handoff, mechanic work order, fuel/refueling, garbage route, netrunning challenge, coordinated NPC PvE event and custom scheduled event.
- [ ] A player can own/access an apartment, use shared inventory storage, and recover access after reconnect.
- [ ] A player can own/store/retrieve a vehicle with keys and no duplicate spawn exploit.
- [ ] Faction/gang/police visibility, roles and team map markers obey server policy; global administration remains Warden-owned.
- [ ] The game's native map/minimap displays server-owned persistent pins and only authorized team/player markers.
- [ ] Chat, help, command errors, map, HUD and admin tools are coherent and usable across target display/input configurations.
- [ ] Every optional client mod has a declared version/dependency and fails safely when missing; every accepted shared action is validated, authorized, persisted if durable, and logged.
- [ ] The full stack passes live test-bench acceptance and has a documented rollback.

## Immediate next sequence

1. Freeze this resource ownership/API plan and reconcile it with the current EventCore/RPCore manifests and local changes.
2. Resolve the production CET/REDscript-to-Open77 client handoff; without it, HUDitor reports remain local and the rest of the RP domains should not depend on it.
3. Add successful EventCore action logs and verify the typed bridge on the current server/client build.
4. Complete the character identity and lifecycle contract, then implement the first authoritative domain: inventory/economy.
5. Use those foundations for clothing and apartments, then vehicles/fuel/mechanics, the reusable job engine and named job tracks, factions/police/MaxTac, map visibility, and coordinated PvE/custom events/NPCs/netrunning.
6. Integrate each domain into RPCore only after its API and persistence acceptance checks pass.
7. Test the complete first playable loop on the bench, update docs, and wait for explicit approval before commit/push/deploy.

## Reference material

- [Open77 resource runtime and isolated client/server resources](https://open2077.net/docs/resource-runtime)
- [Open77 authenticated, resource-namespaced callbacks](https://open2077.net/docs/callbacks)
- [Open77 server resource packaging and required-mod review](https://open2077.net/docs/server-resources)
- [Open77 privileged debug runtime boundary](https://open2077.net/docs/debug-runtime)
- [HUDitor source page, requirements, and current permissions](https://www.nexusmods.com/cyberpunk2077/mods/3315)
- [RPCore companion README and HUD migration checklist](../../rpcore/client-mod/README.md) (when both repositories are checked out side by side)
