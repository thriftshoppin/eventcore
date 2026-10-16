-- EventCore trusted callers and HUD config (seedDefaults off for pipeline-only).

EventCore = EventCore or {}

EventCore.TrustedPersistenceCallers = EventCore.TrustedPersistenceCallers or {
    ["rpcore"] = true,
}

EventCore.TrustedAccessReaders = EventCore.TrustedAccessReaders or {
    ["rpcore"] = true,
}

-- RPCore HUD controller (server/hud.lua). EventCore is the resource RPCore allows to write HUD
-- state, so providers call EventCore's Hud* exports instead of calling RPCore themselves.
EventCore.HudConfig = {
    -- Pipeline only: do not seed web/RPCore vitals on join.
    seedDefaults = false,
    -- defaults unused while seedDefaults = false
    -- defaults = { hunger = 100, thirst = 100, psychosis = 0 },
    -- RPCore invents no numbers on its own; a real provider's HudSetVital overrides these.
    -- RPCore element overrides applied to every joining player, e.g. to hide the web fallback
    -- gauges once the native hunger / thirst / cyberpsychosis bars are confirmed on screen:
    --   defaultElements = { ["vital.food"] = { visible = false }, ["vital.water"] = { visible = false },
    --                       ["vital.sanity"] = { visible = false } },
    syncIntervalMs = 2000,
    warnIfRpcoreMissing = false,
    defaultOverrideSeconds = 60,
}

-- Extra server resources allowed to call the Hud* exports (rpcore is always allowed).
EventCore.HudCallers = EventCore.HudCallers or {}
