# Client inkWidget pipeline

EventCore ships **only** the native inkWidget host as a required client mod. No web vitals UI.

## Package

| Path | Role |
|------|------|
| `dist/eventcore-hud.zip` | Launcher-delivered required mod |
| `dist/eventcore-hud.zip.sha256` | Warden review hash |
| `client-mod/r6/scripts/EventCoreHud/*.reds` | Source |

## Pipeline

1. Lua / server / RTTI calls `EventCoreHudDefineBar` / `EventCoreHudSetBar` / `EventCoreHudRemoveBar` / `EventCoreHudClear` (store only).
2. `EventCoreHudSystem` holds bar state + revisions.
3. `healthbarWidgetGameController` pump applies state on the UI frame via `EventCoreBarHost`.
4. Spawn ladder: SpawnFromLocal → SpawnFromExternal → procedural ink canvas.

## Not included

- RPCore web vitals HTML/JS
- Automatic hunger/thirst/psychosis seeding (`seedDefaults = false`)
- Hard dependency on the `rpcore` server resource

## Warden

Enable required mods; review the SHA-256 (or `requiredMods.unsecured` for private LAN tests only).
