# EventCore chat

EventCore supplies a replaceable chat UI while Open77 remains responsible for command registration and authorization.

## Install

1. Install EventCore 0.6.6 or newer as a resource and keep it in the server's `resources.load` list.
2. Keep `open77_chat` loaded. EventCore disables only its built-in presentation and T binding through the supported `setEnabled` export; the resource remains active as Open77's command/message transport. EventCore restores the built-in UI if it is stopped.
3. Keep other resources and their command registrations enabled. EventCore sends slash commands through Open77's authenticated command dispatcher, which still enforces each `command.<name>` ACL.
4. Restart the server and check the EventCore startup logs. In game, press **T** to open chat. A normal message is sent as chat; `/command arguments` runs a registered local or server command.

The open chat prompt is `eventcore:`. It is green; typed text and message output are white. Messages have exactly one source label: player names for player chat, **Server** for server output, **EventCore** for EventCore system replies, and an optional resource-provided label for messages sent through the approved `SendChat` export. Open77's `chat:ready` and `chat:addSuggestions` events feed the slash-command suggestions; use **Tab** to complete a match and **Up/Down** to select one. Four recent messages fit beneath the input, and command errors remain visible after the chat closes. Press **Escape** or controller **B** to close chat without sending.

EventCore replaces the built-in input and presentation while preserving the Open77 chat service that delivers command help, invalid-command feedback, server announcements, and suggestions. It does not unregister commands from other resources or take ownership of their permissions. Typed-command history is not persisted between sessions.

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
