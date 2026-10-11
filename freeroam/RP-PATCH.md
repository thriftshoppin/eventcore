# Freeroam 0.7.4 - RP server build

This is the stock Freeroam resource with two local changes. Everything else is untouched, including the menu, scoreboard, race, PvP, spawns, respawn, vehicles and teleports.

1. **HUD off** (`shared/config.lua`: `hud = { enabled = false }`, `client/main.lua`). Freeroam no longer creates its HUD page, so it never hides the game's health, stamina, weapon and speedometer widgets. RPCore owns the player HUD. Set `enabled = true` to restore the stock HUD.
2. **Kill feed off** (`shared/config.lua`: `combat.killfeed.enabled = false`). No kill-feed entries and no "X eliminated Y" chat line. Hitmarker and damage flash are unaffected.

Install: replace `resources/gamemodes/freeroam/` with this folder and restart the server. Load `freeroam` after its dependencies (`open77_weapons`, `open77_cyberware_lab`, `open77_contextmenu`, `open77_props`, `open77_worldui`, `open77_zones`, `open77_notifications`, `open77_animations`, `open77_doors`). Do not also load a separate respawn resource; Freeroam handles respawn. These same edits ship as patches in `rpcore/install/`.

Known issues (operator-reported, in-game tested 2026-10-11): vanilla health and "lifelihood" bars do not display properly, and wider screen aspect ratios display incorrectly. They are not caused by this patch.
