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
