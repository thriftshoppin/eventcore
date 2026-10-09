# Changelog

## 0.6.5
- Routed Escape close through Open77's pause-key event because the host consumes Escape before WebUI receives it.
- Declared the local-event capability required to receive the host close event.
- Kept T chat focus active through the WebUI open/focus handshake so the first keystroke can go directly into the composer.
- Added controller B as a close action while chat is open.

## 0.6.4
- Replaced the boxed chat field with a transparent text overlay and green `eventcore:` prompt.
- Focused the input on open and kept recent messages visible briefly after closing.
- Used one source label per message, including `Server` for server output.

## 0.6.3
- Matched the chat input surface to Open77's stock chat styling with green accents.

## 0.6.2
- Reduced the chat panel width and tightened its input spacing and typography.

## 0.6.1
- Kept the focused chat open instead of closing it on the menu-focus event it triggers.
- Moved the chat panel to the top-left of the screen.

## 0.6.0

- Added an EventCore-owned, skinnable in-game chat surface and T key mapping.
- Added server-side chat validation, a bounded send rate, and client fan-out.
- Routed slash commands through Open77's existing authenticated command dispatcher; command ACLs and resource command registrations remain in force.
- Added the trusted `SendChat` export so approved resources can publish messages through the EventCore UI.
- Documented removing `open77_chat` from the server resource list to replace its UI and release its keybind.

## 0.5.0

- Added a server-only structured storage gateway so approved resources can persist their own data without direct SQL access.
- Isolated resource and per-player records by the actual calling resource; callers cannot select another resource's namespace or submit SQL.
- Added bounded key listing, payload limits, atomic batches, schema initialization, and write audit events.
- Documented the service ownership boundary: use a domain resource's API when one exists and EventCore storage as the fallback. Shared RP services can build on EventCore contracts without combining mod inventories.

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
