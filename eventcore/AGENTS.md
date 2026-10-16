# EventCore contributor handoff

Last verified: 2026-10-11, after an in-game test by the operator. Treat this file and `CHANGELOG.md` as current. Older handoff text (test-bench paths, "uncommitted"/"not deployed" notes, the 0.6.5/0.3.3 diagnosis) was removed because it described earlier installs.

## Current state

- EventCore 0.8.0 includes a paired typed bridge (`server/bridge.lua`, `client/bridge_runtime.lua`) backed by Open77's namespaced authenticated callbacks. Providers must be EventCore dependencies and explicitly listed in `EventCore.BridgeWhitelist`; EventCore derives provider identity/generation from export context, caps JSON payloads/results, rate-limits per player/action, and dispatches only named provider exports. Provider handlers still own gameplay authorization and validation.
- Client resources can import `@eventcore/client.modules.bridge` for client requests and local handler registration. HUDitor CET/REDscript-to-Open77 IPC is unproven and not implemented. Read `docs/client-bridge.md` and `docs/STACK_ARCHITECTURE.md` for the contract.
- `server/hud.lua` is EventCore's controller for the RPCore HUD. RPCore only accepts HUD writes from EventCore. See `CHANGELOG.md` for the exports and the `/eventcore.hud.*` test commands.
- 0.8.0 adds, alongside `server/hud.lua` (RPCore driver, unchanged): `client/native_hud.lua` (callers for every ink layer/widget/controller), `server/hud_bench.lua` (test bench, schedules, event log), `server/widgets.lua` + `client/widgets.lua` (custom ink-widget bridge) and the generated `shared/native_registry.lua`. This is work in progress and is kept deliberately in case Open77 or the game changes; see `docs/native-hud.md`.
- Chat: EventCore replaces only Open77's chat presentation and T binding through the `open77_chat` `setEnabled` export. `open77_chat` stays active as the command/message transport. Chat lines keep one source label (player name, `Server`, `EventCore`, or an approved resource label). The green `eventcore:` text is the input prompt, not a message prefix. Escape arrives as `open77:pauseKey` (declared through `local.events`); controller B also closes chat.

## Server requirements (confirmed against a real `server.jsonc`)

- `open77_chat` MUST be in `resources.load`. The EventCore manifest does not enforce it. Without it, chat suggestions, `chat:addMessage` delivery and command feedback are missing, and the client log shows `[EventCore][chat] could not replace Open77 chat UI`.
- Load `eventcore` before `rpcore`. Load `rpcore` exactly once.
- Do NOT place an `rpcore/` folder inside this repository or inside `resources/eventcore/`. A nested copy can register a second `rpcore`. It must never be committed here.
- Respawn is not part of EventCore. Among the stock resources, only the Freeroam gamemode respawns dead players (`open77_death` is a read-only facade). An RP server that drops Freeroam needs its own respawn resource.

## Where command output appears

- Server command replies (`open77:command:result`) and `chat:addMessage` lines show in the EventCore chat. They fade after about 8 seconds unless chat is open.
- Client `print()` output goes to the client log only, never to chat. Server `print()` goes to the server console and Warden.
- Do not "fix" missing debug output by changing HUD or chat code before checking the two points above.

## Known issues (operator-reported, in-game tested 2026-10-11)

- Vanilla health and "lifelihood" bars do not display properly.
- Wider screen aspect ratios display incorrectly.
- These are known issues. They are not caused by `server.jsonc`, the load list, or EventCore configuration. Do not change resource configuration or add hide/show workarounds to chase them without the operator asking. No other issues were reported in that test.

## Handoff and release

- Repository: `thriftshoppin/eventcore`; this resource lives in the `eventcore/` sibling folder.
- The operator makes the git commits. Do not commit, push, or deploy.
- **Licensing:** `LICENSE` is MIT for EventCore's own code. End users must own Cyberpunk 2077 and Phantom Liberty to run the mod with the game. Do not add CDPR game assets or proprietary scripts to this repository.
