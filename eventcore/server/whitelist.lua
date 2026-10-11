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

-- RPCore HUD controller (server/hud.lua). EventCore is the resource RPCore allows to write HUD
-- state, so providers call EventCore's Hud* exports instead of calling RPCore themselves.
EventCore.HudConfig = {
    -- Give every joining player a baseline so the hunger / thirst / cyberpsychosis bars appear.
    -- RPCore invents no numbers on its own; a real provider's HudSetVital overrides these.
    -- Set false once a needs resource supplies real values.
    seedDefaults = true,
    defaults = { hunger = 100, thirst = 100, psychosis = 0 },
    -- RPCore element overrides applied to every joining player, e.g. to hide the web fallback
    -- gauges once the native hunger / thirst / cyberpsychosis bars are confirmed on screen:
    --   defaultElements = { ["vital.food"] = { visible = false }, ["vital.water"] = { visible = false },
    --                       ["vital.sanity"] = { visible = false } },
    defaultElements = {},
    defaultOverrideSeconds = 60,  -- lifetime used by tier / hide overrides that name none
    syncIntervalMs = 2000,        -- join detection and RPCore-restart detection
}

-- Extra server resources allowed to call the Hud* exports (rpcore is always allowed).
EventCore.HudCallers = {
    -- ["resource_folder_name"] = true,
}
