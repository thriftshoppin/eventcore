# EventCore administrator console

EventCore owns the administrator entry point and runtime view. Warden remains
the authority for global roles and per-command grants.

## Text commands

- `/eventcore.admin` opens the console. Only a connected player with Warden's
  reserved `admin` or `owner` role can open it.
- `/eventcore.admins` lists connected global admins.
- `/eventcore.roles <playerId>` shows the connected player's effective Warden
  roles.
- `/eventcore.services` prints the current EventCore service directory.
- `/eventcore.events` prints registered EventCore event names and listener
  counts.
- `/eventcore.bridge` reports callback readiness, registered bridge actions,
  and whether success logging is enabled.
- `/eventcore.help` lists the EventCore administrator commands.

All commands are registered as restricted Open77 commands and also check
the caller's effective Warden roles inside EventCore.

For a test bench, set `EventCore.BridgeDebug = true` in
`server/whitelist.lua` to log successful action registration and outcomes in
the server console. Logs include only the event, resource, action ID, and
session player ID; they never print client payloads. Keep this off on a busy
server. Warnings for callback/provider failures remain available regardless.

## Panel actions

The console reads the player roster, roles, service descriptors, and EventCore
handler counts from server-owned data. It renders structured results pushed by
the existing admin resource after authorized read commands. Quick actions are an explicit allowlist
in `server/admin.lua`; each is shown only when Warden grants `command.<name>`.
The command field accepts `admin.*` names so the panel can reach the existing
admin tool set without duplicating its handlers. EventCore checks global admin
and the exact command permission, then Open77's restricted command dispatcher
checks that permission again when the command runs. UI visibility is not an
authorization boundary.

Current actions include player heal/revive/kill/teleport/bring/kick, self
heal/revive/noclip/fly, audit/status reads, spawned-vehicle cleanup, and a
server announcement. Ban prompts for duration and reason. The command field
can reach the broader admin tool set, including vehicles, props, weapons,
travel, and world tools, according to the caller's Warden grants. Global roles
cannot be assigned from the panel; use Warden.

The current console fronts existing Open77 command implementations during the
migration. It does not duplicate or bypass their action validation. Domain
systems continue to own their authoritative state until a specific API is
migrated into EventCore.
