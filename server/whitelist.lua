-- Approved resources for EventCore's scoped storage and chat-send exports.
-- Install the resource folder and declare `dependency "eventcore >=0.5.0"`
-- in its open77.lua, then add one line below using this exact syntax:
--     ["resource_folder_name"] = true,
-- This grants that resource its own storage partition and permission to publish
-- messages through the EventCore chat surface.
EventCore = EventCore or {}
EventCore.Whitelist = {
    ["rpcore"] = true,
    -- ["resource_folder_name"] = true,
}

-- Server resources allowed to register typed bridge actions in either
-- direction. This is separate from storage access. Each action's provider
-- still authorizes the player and validates domain-specific rules.
EventCore.BridgeWhitelist = {
    ["rpcore"] = true,
    -- ["resource_folder_name"] = true,
}

-- Set true on a test bench to log successful bridge registrations and actions.
-- Payload contents are never printed. Keep false on a busy/production server.
EventCore.BridgeDebug = false
