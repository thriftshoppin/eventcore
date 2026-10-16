# EventCore snapshot preview (NOT PUSHED)

Read this before any git push. Pipeline-only: native inkWidgets + EventView. No web vitals UI package.

## What this snapshot is

```
eventcore/eventcore/   ← server resource + required client mod
eventcore/freeroam/    ← unchanged sibling (still has its own web hud; not EventCore vitals)
```

## New / changed (EventCore)

### Client inkWidget pipeline (NEW — not a RPCore paste)

```
client-mod/r6/scripts/EventCoreHud/
  EventCoreHudConfig.reds      layout + spawn knobs
  EventCoreHudEvents.reds      define / value / remove / reset events
  EventCoreHudSystem.reds      store + RTTI: Ping, DefineBar, SetBar, RemoveBar, Clear, Status
  EventCoreHudWidgets.reds     spawn ladder + EventCoreBarHost (procedural ink bars)
  EventCoreHudController.reds  pump on healthbarWidgetGameController

dist/eventcore-hud.zip         launcher required-mod package
dist/eventcore-hud.zip.sha256  Warden hash
```

RTTI surface (game-side, called from client when rtti is available):

- `EventCoreHudPing() -> Bool`
- `EventCoreHudDefineBar(id, label, order, colorCsv, ticksCsv) -> Bool`
- `EventCoreHudSetBar(id, visible, value, maxValue) -> Bool`
- `EventCoreHudRemoveBar(id) -> Bool`
- `EventCoreHudClear() -> Bool`
- `EventCoreHudHeartbeat() -> Bool`
- `EventCoreHudStatus() -> String`

### EventView (already in checkpoint-4, kept)

```
shared/eventview.lua
server/eventview.lua
client/eventview.lua
docs/eventview.md
web/admin/*  (EventView section)
```

Targets: `player:<id>` | `nearest` | `group:<role>` | `all`

### Softened (no more RPCore spam / no seeded web vitals)

```
server/hud.lua       one-shot optional log if rpcore missing
server/whitelist.lua seedDefaults = false
                     warnIfRpcoreMissing = false
open77.lua           preload_mod "dist/eventcore-hud.zip"
```

### Docs

```
docs/client-inkwidget-pipeline.md
docs/eventview.md
CHANGELOG.md  (0.8.0 notes)
```

## Explicitly NOT in this package

- Full RPCore server resource
- RPCore web vitals HTML/JS as EventCore required mod
- Blind copy of `rpcore-hud` reds (names, psychosis tiers, test harness)
- Auto seed hunger/thirst/psychosis on join

## Freeroam note

`freeroam/web/hud.*` is the gamemode’s own WebUI. Untouched in this snapshot. Disable via freeroam config / RP patch when you want native-only.

## Suggested commit message (when you say push)

```
EventCore 0.8.0: inkWidget client pipeline + EventView

- Ship dist/eventcore-hud.zip (preload_mod) — generic bar host only
- EventView LTE/missions with player|nearest|group|all targeting
- RPCore server resource optional; seedDefaults off; quiet missing log
```

## Install path on server

```
resources/eventcore/   ← contents of eventcore/eventcore/
```

Load `eventcore` (and freeroam if used). Approve required-mod hash in Warden for `eventcore-hud.zip`.
