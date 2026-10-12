# Open77 resource pack: EventCore + RP-ready Freeroam

This repository packages two Open77 server resources that are meant to run together with [RPCore](https://github.com/thriftshoppin/rpcore) on a roleplay server:

| Folder | Resource | Version | What it is |
| --- | --- | --- | --- |
| [`eventcore/`](eventcore/) | `eventcore` | 0.7.0 | Event, service and persistence foundation for Open77 resources, plus the in-game chat overlay, admin console, HUD controller and typed client/server bridge. |
| [`freeroam/`](freeroam/) | `freeroam` | 0.7.4 | The Freeroam gamemode with two local RP changes: its own HUD is off and its kill feed is off. Everything else is unchanged. |

RPCore is a separate repository. It is not part of this pack.

> **Status: in development.** The operator tested this stack in game on 2026-10-11 and reported only the [known issues](#known-issues) below. Expect rough edges and breaking changes before the full release.

## What each resource does

### EventCore

- **Chat.** A focused text overlay opened with **T**. It replaces only Open77's chat presentation and keeps `open77_chat` running as the command and message transport. Slash commands still go through Open77's command dispatcher, so each command's ACL is still enforced.
- **Admin console.** `/eventcore.admin` and related commands, gated by Warden roles.
- **HUD controller.** `server/hud.lua` is the only writer RPCore accepts for HUD state. It provides the `Hud*` exports and the `/eventcore.hud.*` test commands.
- **Typed bridge.** A paired client/server bridge with explicit provider allowlists, payload caps and per-player rate limits (`@eventcore/client.modules.bridge` on the client).
- **Services and persistence.** A service directory, a revisioned state feed and scoped storage through Open77's database access.

Full details are in [`eventcore/README.md`](eventcore/README.md) and [`eventcore/docs/`](eventcore/docs/).

### Freeroam (RP build)

Everything in the stock gamemode still works: the `/freeroam` menu, scoreboard, race, PvP, spawns, automatic respawn, vehicles and teleports. Two things are different:

1. **HUD off.** `FreeroamConfig.hud.enabled = false`. Freeroam creates no HUD page, so it never hides the game's health, stamina, weapon or speedometer widgets. RPCore owns the player HUD. Set it to `true` to restore the stock HUD.
2. **Kill feed off.** `FreeroamConfig.combat.killfeed.enabled = false`. No kill-feed entries and no "X eliminated Y" chat line. Hitmarker and damage flash are unaffected.

The files that differ from stock are `freeroam/client/main.lua` and `freeroam/shared/config.lua`. See [`freeroam/RP-PATCH.md`](freeroam/RP-PATCH.md).

**Freeroam is the only stock resource that respawns dead players.** `open77_death` is a read-only facade. If you stop loading Freeroam, nobody respawns, so keep it loaded or supply your own respawn resource.

## Install

1. Copy `eventcore/` into the server's `resources/` folder as `resources/eventcore/`.
2. Put `freeroam/` where your server keeps Freeroam (stock servers keep it at `resources/gamemodes/freeroam/`) and replace the existing folder. Keep only one `freeroam` on the server.
3. Edit `resources.load` in `server.jsonc` as shown below.
4. In Warden, approve the permissions requested by `eventcore`, `rpcore` and `freeroam`. Re-approve them if they were reset by an update.
5. Restart the server, then join through the launcher.

Do not nest one resource inside another (for example an `rpcore/` folder inside `eventcore/`). A nested copy can register the same resource twice.

### `resources.load`

```jsonc
"resources": {
  "load": [
    // ...your other resources...
    "eventcore",      // before rpcore
    "open77_chat",    // REQUIRED by EventCore chat; the manifest does not enforce it
    "rpcore",         // load exactly once
    // Freeroam's dependencies:
    "open77_weapons",
    "open77_cyberware_lab",
    "open77_contextmenu",
    "open77_props",
    "open77_worldui",
    "open77_zones",
    "open77_notifications",
    "open77_animations",
    "open77_doors",
    "freeroam"        // after its dependencies
  ]
}
```

Do not also load a separate respawn resource; Freeroam already handles respawn and the join spawn. `open77_freeroam` is a persistence add-on and is not needed for this pack.

### EventCore whitelisting

EventCore has two layers of approval: Warden permissions in `eventcore/open77.lua`, and server-resource allowlists in `eventcore/server/whitelist.lua`. A resource that runs SQL through EventCore needs both the Warden `database.access` permission in its own manifest and an entry in `EventCore.Whitelist`.

#### Storage and SQL resources

Add the exact resource folder name to `EventCore.Whitelist`:

```lua
EventCore.Whitelist = {
    ["rpcore"] = true,
    ["your_sql_resource"] = true,
}
```

This grants that resource its own scoped storage partition and allows its approved EventCore storage/chat-send calls. In the calling resource, declare the dependency and permission as well:

```lua
dependency "eventcore >=0.5.0"
permissions { "database.access" }
```

Do not add a resource to this list just because it is loaded. Add only resources that are trusted to use EventCore's persistence or approved chat-send exports.

#### Typed bridge providers

`EventCore.BridgeWhitelist` is separate from storage approval. Add a provider here only when it registers typed client/server bridge actions:

```lua
EventCore.BridgeWhitelist = {
    ["rpcore"] = true,
    ["your_bridge_resource"] = true,
}
```

The provider still validates Warden/Open77 ACL, gameplay conditions and every request field. Bridge approval does not grant SQL access.

#### HUD callers

`rpcore` is always allowed to receive HUD writes. Add another resource to `EventCore.HudCallers` only when it intentionally calls the `Hud*` exports:

```lua
EventCore.HudCallers = {
    ["your_hud_resource"] = true,
}
```

#### Read-only Warden role queries

The read-only `IsAdmin`, `GetPlayerRoles` and `GetOnlineAdmins` exports are separately restricted in `eventcore/server/access.lua`. Add trusted server tools to `trustedAccessReaders` only when they need those queries. EventCore never assigns or promotes Warden roles.

The EventCore manifest requests `network.events`, `local.events`, `input.actions`, `database.access`, `players.read` and `acl.read`. Approve those permissions in Warden, then restart the server. Re-approve them if an Open77 update resets the grants.

## Verify it works

- Client log shows `[EventCore][chat] bound to T`. If it shows `could not replace Open77 chat UI`, `open77_chat` is not loaded.
- Pressing **T** opens chat, and slash commands show suggestions.
- The client log does **not** contain `[freeroam] design-system HUD active`. If it does, the old Freeroam files are still in place.
- `/freeroam.help` lists the Freeroam commands, and the `/freeroam` menu opens.
- After dying, you respawn after about four seconds.
- Warden shows one `eventcore`, one `rpcore` and one `freeroam`.

## Where output appears

- Server command replies and `chat:addMessage` lines appear in the EventCore chat and fade after about 8 seconds unless chat is open.
- Client `print()` output goes to the client log, not to chat.
- Server `print()` output goes to the server console and Warden.

## Known issues

Reported by the operator after in-game testing on 2026-10-11:

- Vanilla health and "lifelihood" bars do not display properly.
- Wider screen aspect ratios display incorrectly.

These are known issues, not configuration mistakes. Changing `server.jsonc` or adding hide/show workarounds will not fix them.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| No command output or suggestions in chat | `open77_chat` is missing from `resources.load`. |
| Chat lines vanish quickly | They fade after about 8 seconds. Press **T** to keep them visible. |
| Debug text is missing | Client `print()` goes to the client log only. |
| Nobody respawns | `freeroam` is not loaded. |
| A resource appears twice in Warden | A nested or duplicate folder exists. Remove the extra copy. |
| Custom Freeroam HUD still appears | Old Freeroam files are still installed. Replace the folder and restart. |

## Repository layout

```text
eventcore/   EventCore resource (repository-style: README, CHANGELOG, AGENTS, docs, source)
freeroam/    Freeroam resource with the RP changes applied
```

Each folder is a complete resource. Install them as separate resources, not nested.

## For contributors and agents

Current state, server requirements and known issues are kept in [`eventcore/AGENTS.md`](eventcore/AGENTS.md) and [`eventcore/CHANGELOG.md`](eventcore/CHANGELOG.md). Older notes, such as test-server paths or "uncommitted" markers, are out of date. The repository owner makes the commits; do not commit, push or deploy on their behalf.

## License

EventCore is all rights reserved while it is in development, and it is planned to move to the MIT License at its full release. See [`eventcore/LICENSE`](eventcore/LICENSE). This does not change the terms of any other resource in this repository.
