-- Reviewed consumers allowed to use EventCore's structured storage exports.
-- To approve a mod, install its resource folder, declare `dependency "eventcore"`
-- in that folder's open77.lua, and add its exact resource name here.
-- This grants only its EventCore storage partition, never database.access/SQL.
EventCore = EventCore or {}
EventCore.Whitelist = {
    rpcore = true,
}
