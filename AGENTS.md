# EventCore contributor handoff

## Current local work

- EventCore 0.7.0 now includes a paired typed bridge (`server/bridge.lua`, `client/bridge_runtime.lua`) backed by Open77's namespaced authenticated callbacks. Providers must be EventCore dependencies and explicitly listed in `EventCore.BridgeWhitelist`; EventCore derives provider identity/generation from export context, caps JSON payloads/results, rate-limits per player/action, and dispatches only named provider exports. Provider handlers still own gameplay authorization and validation.
- Client resources can import `@eventcore/client.modules.bridge` for client requests and local handler registration. Server-to-client snapshots/deltas still use the revisioned state feed; opt-in direct client actions require the same registered provider resource. HUDitor CET/REDscript-to-Open77 IPC is still unproven and not implemented.
- Read `docs/client-bridge.md` and `docs/STACK_ARCHITECTURE.md` for the contract, provider example, dependency boundary, and remaining live verification.

- EventCore 0.6.6 keeps `open77_chat` active as the command/message transport while suppressing its UI through the supported `setEnabled` export. Native chat output, command errors/results, suggestions, and templates relay through EventCore's overlay; stopping EventCore restores the native chat.
- The T binding opens the focused composer; Open77 consumes Escape before WebUI receives it, so `client/chat.lua` listens to `open77:pauseKey` (declared through `local.events`). Controller B also closes chat while it is open.
- The current uncommitted chat work now relays Open77 `chat:addMessage` and command-suggestion events into EventCore, displays up to four compact recent lines below the input, and shows up to four matching slash-command hints with Tab/arrow-key selection.
- Chat messages retain one source label. Player chat uses the player name, server announcements use `Server`, EventCore replies use `EventCore`, and approved resource messages may provide one source label. The green `eventcore:` text is the input prompt, not a message prefix.
- See `CHANGELOG.md`, `docs/chat.md`, and `docs/IMPLEMENTATION_STATUS.md` for this revision's contract and verification state.

## Handoff and release

- Repository: `thriftshoppin/eventcore`; resource folder is this repository root.
- Test server currently runs from `C:\Users\Open77\Downloads\open77-server-2.31.21+op77.132-win-x64`; source changes are local and have not been deployed.
- The chat suggestion and compact-message updates have been published; in-game verification is still needed for T focus, first-character typing, Escape close, controller B close, and slash-command flow.
- Do not commit, push, or deploy until the user explicitly says “okay” for the pending changes. The user wants testing before GitHub publication and deploys only after local commits.
- Do not add a license before publication. The user reserves the right to choose release licensing later.
