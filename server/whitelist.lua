-- Approved resources for EventCore's structured storage exports.
-- Install the resource folder and declare `dependency "eventcore >=0.5.0"`
-- in its open77.lua, then add one line below using this exact syntax:
--     ["resource_folder_name"] = true,
-- This grants that resource only its own EventCore storage partition.
EventCore = EventCore or {}
EventCore.Whitelist = {
    ["rpcore"] = true,
    -- ["resource_folder_name"] = true,
}
