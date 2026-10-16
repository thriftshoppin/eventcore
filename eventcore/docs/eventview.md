# EventView

Operational panel for limited-time events (LTEs) and per-player missions/quests.

## Who can use it

- Global Warden `admin` / `owner`, **or**
- Players with the optional role label in `EventCore.EventViewConfig.operatorRole` (default `"eventview"`).

Set `operatorRole = nil` in `shared/eventview.lua` to require global admin only.

## Targeting

Every schedule and mission command takes a **target token**:

| Token | Meaning |
|-------|---------|
| `12` or `player:12` | One player by id |
| `nearest` | Nearest player to the operator (falls back to the operator) |
| `all` | Every online player |
| `group:admin` | Every online player with that Warden role |
| `group:moderator` | Same, any role label |

Named convenience groups can be added under `EventCore.EventViewGroups`.

## Admin panel

Open `/eventcore.admin` → **EventView** section.

- Pick target (all / nearest / player id / group)
- Paste LTE steps (hud / widget / mission)
- **Schedule LTE** or set/clear a mission on the resolved targets
- Live log of starts, steps, mission writes, cancels

## Commands

```
/eventcore.eventview.schedule <target> <loops> [label] [at,action,name ...]
/eventcore.eventview.cancel [scheduleId]
/eventcore.eventview.targets <target>
/eventcore.eventview.mission <target> set|clear|list [missionId] [title=.. status=..]
/eventcore.eventview.log [n]
```

Examples:

```
/eventcore.eventview.schedule all 1 server_lte
/eventcore.eventview.schedule nearest 2 blink 0,hide,inkHUDLayer 1500,show,inkHUDLayer
/eventcore.eventview.schedule group:admin 1 staff_only
/eventcore.eventview.mission all set welcome title=Welcome status=active
/eventcore.eventview.mission 12 clear welcome
/eventcore.eventview.targets group:moderator
```

## Other mods writing missions

Trusted callers (`rpcore`, persistence-trusted resources, `EventCore.HudCallers`, or `EventCore.EventViewCallers`) can:

```lua
exports.eventcore:EventViewMissionSet(playerId, "quest.intro", {
    title = "Find the fixer",
    body = "Meet them in Watson.",
    status = "active",
    progress = 0,
    widget = "example.meter",
    values = { visible = true, value = 10, label = "Quest" },
})

exports.eventcore:EventViewMissionClear(playerId, "quest.intro")
exports.eventcore:EventViewMissionList(playerId)
```

Missions are remembered per player until clear or disconnect, and replayed when the client signals widget-ready.

## LTE step kinds

- `hud` — `{ at, kind="hud", action="show|hide|status", target="inkHUDLayer"|controller }`
- `widget` — `{ at, kind="widget", id="example.meter", values={...} }`
- `mission` — `{ at, kind="mission", missionId="...", entry={...} }`
- `mission_clear` — `{ at, kind="mission_clear", missionId="..."? }`

Schedules run on the server so widget and mission writes stay authoritative. HUD steps reuse the existing HUD bench runner when present.
