# Open77 resource pack: EventCore + RP-ready Freeroam

| Folder | Resource | Version | What it is |
| --- | --- | --- | --- |
| [`eventcore/`](eventcore/) | `eventcore` | **0.8.0** | Runtime hub, MIT-licensed code, native **inkWidget** client pipeline, **EventView**, admin/chat. |
| [`freeroam/`](freeroam/) | `freeroam` | 0.7.4 | Freeroam with local RP changes (own HUD off, kill feed off). |

RPCore is a **separate** repository and is **optional** for EventCore 0.8.0.

<u>**You must own a valid copy of Cyberpunk 2077 and Phantom Liberty to run or use this software with the game.**</u>

EventCore's own code is **MIT** (see [`LICENSE`](LICENSE) / [`eventcore/LICENSE`](eventcore/LICENSE)). This repo does not ship CD PROJEKT RED game assets. CDPR terms, REDmod EULA, and Fan Content Guidelines still apply to the game.

## EventCore 0.8.0 highlights

- **Native inkWidget pipeline** — `preload_mod "dist/eventcore-hud.zip"`; sources under `eventcore/client-mod/r6/scripts/EventCoreHud/`. No web vitals UI package.
- **EventView** — LTEs and per-player missions; targets `player` / `nearest` / `group` / `all`.
- **RPCore optional** — missing RPCore is quiet by default; `seedDefaults = false`.

Full details: [`eventcore/README.md`](eventcore/README.md), [`eventcore/CHANGELOG.md`](eventcore/CHANGELOG.md).

## Install

1. Copy `eventcore/` → `resources/eventcore/`.
2. Place `freeroam/` as your server expects (often `resources/gamemodes/freeroam/`).
3. Load order: `eventcore` before optional consumers; keep `open77_chat` if you use EventCore chat.
4. Warden: approve EventCore permissions; enable required mods and review `eventcore-hud.zip` hash (or unsecured for private LAN only).
5. Restart; join via the official launcher.

Do not nest `rpcore/` inside `eventcore/`.

## License

MIT for EventCore project code. **Cyberpunk 2077 + Phantom Liberty ownership required** to run with the game.
