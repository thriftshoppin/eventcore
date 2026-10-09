# EventCore chat

EventCore supplies a replaceable chat UI while Open77 remains responsible for command registration and authorization.

## Install

1. Install EventCore 0.6.5 or newer as a resource and keep it in the server's `resources.load` list.
2. Remove `open77_chat` from `resources.load` after EventCore is installed. This stops the bundled chat UI and releases its T key binding. EventCore registers its own T binding.
3. Keep other resources and their command registrations enabled. EventCore sends slash commands through Open77's authenticated command dispatcher, which still enforces each `command.<name>` ACL.
4. Restart the server and check the EventCore startup logs. In game, press **T** to open chat. A normal message is sent as chat; `/command arguments` runs a registered local or server command.

The open chat prompt is `eventcore:`. It is green; typed text and message output are white. Messages have exactly one source label: player names for player chat, **Server** for server output, **EventCore** for EventCore system replies, and an optional resource-provided label for messages sent through the approved `SendChat` export. Press **Escape** or controller **B** to close chat without sending.

Removing `open77_chat` replaces its input and presentation resource. It does not unregister commands from other resources. It also means features implemented only by that chat UI, such as its autocomplete/history presentation, are not available until an EventCore equivalent is added.

## Send messages from another resource

Add the calling resource to EventCore's `server/whitelist.lua`, then call the `SendChat` server export. The fourth argument is the single visible source label; omit it for **Server** output. The export only accepts approved callers and broadcasts through EventCore's chat feed:

```lua
local pending, reason = Open77.exports.call("eventcore", "SendChat", -1, "The clinic is open.", "system", "DISPATCH")
if not pending then
    print("EventCore chat unavailable: " .. tostring(reason))
    return
end
local accepted, sendError = pending:await()
if not accepted then print("EventCore chat refused: " .. tostring(sendError)) end
```

Pass a positive player ID instead of `-1` to send to one player. `kind` is `system` or `player`; plain text is clamped and control characters are removed. Do not use this export for slash commands.

## Boundaries

- EventCore chat does not grant command permissions. Open77's command ACL is still checked when the command reaches the server.
- Commands stay with their owning resources. EventCore does not forward arbitrary commands by running them as the server console.
- Messages sent by a resource through EventCore are server-originated; client-supplied messages cannot set their own author or type.
- EventCore keeps a short client-side display history for the current session only. Durable chat archives are not part of this feature.
