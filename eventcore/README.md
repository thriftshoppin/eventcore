# EventCore

<u>**You must own a valid copy of Cyberpunk 2077 and Phantom Liberty to run or use this software with the game.**</u> EventCore's own code is released under the **MIT License** (see [`LICENSE`](LICENSE)). This repository does not ship CD PROJEKT RED game assets or proprietary scripts. CD PROJEKT RED's terms, REDmod EULA, and Fan Content Guidelines still apply to any use involving the game.

**Version 0.8.0** — client HUD is the **sibling** package `eventcore-hud/` (zip for Warden), not nested under this resource.

**Version 0.8.0** — server runtime + **native inkWidget client pipeline** + **EventView**. No web vitals UI is shipped as the required client mod.

EventCore is the server-side runtime and service hub for Open77 roleplay resources. It provides versioned services, trusted player/session context, events, scoped observer information, durable server storage, administrator tools, chat, a native inkWidget HUD host, and EventView (LTE schedules and per-player missions).

The optional **RPCore** server resource may still consume EventCore contracts for a fuller RP presentation layer. It is **not required** to run EventCore. Missing RPCore produces a single quiet log line; set `EventCore.HudConfig.warnIfRpcoreMissing = true` only if you want repeated warnings.

---

## What 0.8.0 adds

### Native inkWidget client pipeline

EventCore ships a **required client mod** that hosts generic bars on the game's own HUD (`inkHUDLayer` / `healthbarWidgetGameController`). There is no packaged web vitals HTML/JS.

| Path | Role |
|------|------|
| `eventcore-hud/` (sibling; zip for Warden) | Launcher-delivered required mod |
| `eventcore-hud/ (sibling directory, zip for Warden).sha256` | Warden review hash |
| `client-mod/r6/scripts/EventCoreHud/*.reds` | Source (config, events, system, widgets, controller) |

**Pipeline**

1. Server / Lua / RTTI writes bar state only (`EventCoreHudDefineBar`, `EventCoreHudSetBar`, `EventCoreHudRemoveBar`, `EventCoreHudClear`).
2. `EventCoreHudSystem` stores definitions and values with revision counters.
3. A pump on `healthbarWidgetGameController` applies state on the **UI frame**.
4. Spawn ladder: `SpawnFromLocal` → `SpawnFromExternal` → procedural ink canvas.

See [`docs/client-inkwidget-pipeline.md`](docs/client-inkwidget-pipeline.md).

`open77.lua` declares:

```text
Warden required mod: sibling package `eventcore-hud/` (zip for Warden)
```

Enable required mods in Warden and review the SHA-256 (or use `requiredMods.unsecured` only for private LAN tests).

Vitals seeding is **off** by default (`EventCore.HudConfig.seedDefaults = false`). EventCore does not auto-push hunger / thirst / psychosis into a web UI.

### EventView

Operational panel and commands for **limited-time events** and **per-player missions**.

**Target tokens**

| Token | Meaning |
|-------|---------|
| `12` or `player:12` | One player |
| `nearest` | Nearest to the operator |
| `all` | Every online player |
| `group:<role>` | Online players with that Warden role |

**Commands**

```text
/eventcore.eventview.schedule <target> <loops> [label] ...
/eventcore.eventview.cancel [scheduleId]
/eventcore.eventview.targets <target>
/eventcore.eventview.mission <target> set|clear|list [missionId] ...
/eventcore.eventview.log [n]
```

Trusted mods write missions via exports:

```lua
exports.eventcore:EventViewMissionSet(playerId, "quest.intro", { title = "...", status = "active" })
exports.eventcore:EventViewMissionClear(playerId, "quest.intro")
```

Admin panel: `/eventcore.admin` → **EventView** section.  
Access: global `admin` / `owner`, or optional role `eventview` (`EventCore.EventViewConfig.operatorRole`).

See [`docs/eventview.md`](docs/eventview.md).

### HUD test bench (native discovery)

Global-admin tools to probe layers, controllers, and widgets through the host API, including schedules and a live result viewer. See [`docs/native-hud.md`](docs/native-hud.md).

---

## Administrator console

`/eventcore.admin` opens the administrator console. Text commands:

- `/eventcore.admins`
- `/eventcore.roles`
- `/eventcore.services`
- `/eventcore.events`
- `/eventcore.bridge`
- `/eventcore.help`

The panel includes a player roster, authorized quick actions, a Warden-checked `admin.*` command console, the service directory, registered event handlers, the HUD test bench, and EventView.

Every EventCore admin entry checks Warden for the reserved `admin` or `owner` role. Quick actions are limited to commands Warden grants; Open77 rechecks the command grant at execution. **Warden remains the only authority that assigns global roles.**

See [`docs/admin-console.md`](docs/admin-console.md).

## Chat

EventCore owns a skinnable in-game chat surface (**T** to open). Slash commands route through Open77's command registry and ACL. Keep `open77_chat` loaded so EventCore can disable the bundled UI while preserving transport. See [`docs/chat.md`](docs/chat.md).

## Domain boundaries

Gameplay resources remain authoritative for their own domains (inventory, clothing, missions, economy, vehicles). EventCore is the compatibility and persistence fallback when no domain service fits. Storage gives each trusted resource a separate SQL-backed namespace; mods cannot supply SQL or access another resource's namespace.

See [`docs/rpcore-integration.md`](docs/rpcore-integration.md) and [`docs/persistence.md`](docs/persistence.md).

## Install (server)

1. Place this resource at `resources/eventcore/` (contents of the `eventcore/` folder in the release archive).
2. Load **eventcore** before optional consumers (e.g. rpcore, freeroam).
3. Ensure MariaDB / `OP77_DATABASE_CONNECTION` is configured if you use persistence.
4. In Warden: grant EventCore permissions from `open77.lua`, enable required mods, review `eventcore-hud/` (sibling; zip for Warden) hash.
5. Restart the server.

Client packages are installed by the official OPEN//77 launcher from the server's required-mod list. Do not nest a second `rpcore/` folder inside EventCore.

## Persistence and credentials

EventCore uses Open77's MySQL/MariaDB bridge from server scripts only. Credentials come from `OP77_DATABASE_CONNECTION`; they never belong in this resource or client scripts. Open77 must grant `database.access` in Warden.

## Warden roles for tools

Trusted server tools may use read-only `IsAdmin`, `GetPlayerRoles`, and `GetOnlineAdmins`. Only reserved `admin` and `owner` count as global administrators. EventCore declares `acl.read` and never promotes players.

## Compatibility and license

EventCore source and documentation in this repository are licensed under the **MIT License** — see [`LICENSE`](LICENSE).

**You must own a valid copy of Cyberpunk 2077 and Phantom Liberty** to run or use this software with the game. This project does not include or grant rights to CD PROJEKT RED's game content, graphics, or scripts.


---

## Docs index

| Doc | Topic |
|-----|--------|
| [`docs/client-inkwidget-pipeline.md`](docs/client-inkwidget-pipeline.md) | Required client mod + RTTI surface |
| [`docs/eventview.md`](docs/eventview.md) | LTEs, missions, targeting |
| [`docs/native-hud.md`](docs/native-hud.md) | Native HUD bench and registry |
| [`docs/admin-console.md`](docs/admin-console.md) | Admin panel and commands |
| [`docs/chat.md`](docs/chat.md) | In-game chat |
| [`docs/rpcore-integration.md`](docs/rpcore-integration.md) | Optional RPCore consumer contract |
| [`docs/persistence.md`](docs/persistence.md) | SQL persistence |
| [`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md) | Checkpoint status |
| [`CHANGELOG.md`](CHANGELOG.md) | Version history |
| [`PREVIEW.md`](PREVIEW.md) | Snapshot review notes (pre-push) |
