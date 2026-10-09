# EventCore contributor handoff

## Current local work

- EventCore 0.6.5 updates the replacement chat input. The T binding opens the focused composer; Open77 consumes Escape before WebUI receives it, so `client/chat.lua` listens to `open77:pauseKey` (declared through `local.events`). Controller B also closes chat while it is open.
- Chat messages retain one source label. Player chat uses the player name, server announcements use `Server`, EventCore replies use `EventCore`, and approved resource messages may provide one source label. The green `eventcore:` text is the input prompt, not a message prefix.
- See `CHANGELOG.md`, `docs/chat.md`, and `docs/IMPLEMENTATION_STATUS.md` for this revision's contract and verification state.

## Handoff and release

- Repository: `thriftshoppin/eventcore`; resource folder is this repository root.
- Test server resources live under `C:\Users\Open77\Downloads\open77-server-2.31.21+op77.131-win-x64\resources\eventcore`.
- This work is prepared locally and needs in-game verification of T focus, first-character typing, Escape close, controller B close, and slash-command flow.
- Do not commit, push, or deploy until the user explicitly says “okay” for the pending changes. The user wants testing before GitHub publication and deploys only after local commits.
- Do not add a license before publication. The user reserves the right to choose release licensing later.
