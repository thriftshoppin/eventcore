# Changelog

## 0.4.0

- Added an EventCore-owned administrator console and Warden-gated text commands for opening it, listing global admins, inspecting player roles, and viewing runtime services and event handlers.
- Added a player roster, quick-action bridge, and Warden-checked `admin.*` command console; Open77 rechecks each command at execution.
- Added read-only event-handler diagnostics and the service directory to the admin console.
- Kept Warden as the sole authority for assigning global roles.

## 0.3.1

- Added trusted, read-only ACL role queries for player tools: `IsAdmin`, `GetPlayerRoles`, and `GetOnlineAdmins`.
- Defined global admin as Open77's reserved `admin` or `owner` role; scoped staff roles do not count as global admin.
- Declared `acl.read` for EventCore. Role assignment remains owned by Warden and the Open77 ACL.

## 0.3.0-beta.2

- Added EventCore's versioned, trusted server-to-client state feed for presentation snapshots and explicit channel clears.
- Added detached, bounded payload validation, server-assigned per-player/channel ordering, and client-side stale-packet rejection.
- Added `PublishClientState` and `ClearClientState` to the runtime service catalog.
- Declared the Open77 player-read permission used by trusted state-feed target validation and existing runtime context reads.
- Documented RPCore integration; gameplay providers remain authoritative for their own state.

## 0.3.0-beta.1

Prepares EventCore for RPCore as a consumer-facing service hub.

- Added a versioned server service directory with generation-bound provider ownership.
- Added trusted player context and native observer-scope query APIs.
- Removed cross-resource callback-based `On`/`Off` exports; Open77 does not transfer functions between isolated resources.
- Made exported event-dispatch results serializable.
- Updated the RPCore integration, persistence, clothing, and legacy bridge documentation for Open77 server exports.
- Added the RPCore preparation plan and implementation checkpoint.

## 0.2.0-beta.1

- Added server-only SQL event history and explicit JSON player-state persistence.
- Added trusted persistence exports and selected server event notifications.
- Added inventory snapshot and outfit-code persistence helpers.

The `0.2.0-beta.1` archive is retained as a separate release artifact.
