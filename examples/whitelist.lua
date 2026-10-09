-- Example only: copy approved entries into EventCore's server/whitelist.lua.
-- This file is not loaded by the EventCore manifest and grants no access itself.
--
-- For each entry, install and review the named resource folder and have that
-- resource declare `dependency "eventcore >=0.5.0"` in its open77.lua.
-- Do not grant these consumers `database.access`; this whitelist grants only
-- their own EventCore storage partition through structured exports.

EventCore = EventCore or {}
EventCore.Whitelist = {
    rpcore = true,
    -- clothing_mod = true,
    -- vehicle_garage = true,
}
