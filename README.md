# Open77 pack: EventCore + freeroam + eventcore-hud

Three **sibling** packages. Do not nest them.

| Directory | Role | Install |
|-----------|------|---------|
| **eventcore/** | Server resource | `resources/eventcore/` + `resources.load` |
| **freeroam/** | Gamemode | Server freeroam path + `resources.load` |
| **eventcore-hud/** | **Client** required mod | Zip → **Warden** (not inside eventcore) |

RPCore is a separate repo and optional.

**You must own Cyberpunk 2077 and Phantom Liberty** to run this with the game. EventCore code is MIT.

## eventcore-hud (Warden)

```bash
cd eventcore-hud && zip -r ../eventcore-hud.zip r6
```

Register that zip as a required mod in Warden. Pre-beta packages are unverified until the platform trusts them — expected.

## eventcore (server)

Copy `eventcore/` to the server resources folder. Do **not** embed the client HUD scripts here.

## freeroam

RP-oriented freeroam sibling (HUD/killfeed off by config). Keep only one freeroam on the server.
