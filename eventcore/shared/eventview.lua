-- EventView shared definitions (server + client).
--
-- EventView is the operational surface for:
--   * Server LTEs (limited-time events) that drive widgets / HUD over time
--   * Per-player mission / quest entries that other trusted mods can write
--   * Admin (or a specific EventCore admin role) scheduling and observation
--
-- Targeting modes used by commands and the admin panel:
--   player:<id>   one player
--   nearest       nearest player to the admin (fallback: admin themselves)
--   group:<role>  every online player that has the Warden role label
--   all           every online player
--
-- Other mods write per-player mission/quest state through the server exports
-- EventViewMissionSet / EventViewMissionClear (trusted callers only).

EventCore = EventCore or {}

EventCore.EventViewConfig = {
    -- Max active LTE schedules server-wide.
    maxSchedules = 16,
    -- Max steps per LTE schedule.
    maxSteps = 48,
    -- Max loops per LTE schedule.
    maxLoops = 20,
    -- Max pending mission entries remembered per player.
    maxMissionsPerPlayer = 32,
    -- In-memory event log size (not persisted).
    logSize = 400,
    -- Role label that may use EventView (in addition to global admin/owner).
    -- Set to nil to require global admin only.
    operatorRole = "eventview",
}

-- Optional named groups for convenience (role labels still work via group:<role>).
EventCore.EventViewGroups = {
    -- Example: ["staff"] = { "admin", "moderator" },
}
