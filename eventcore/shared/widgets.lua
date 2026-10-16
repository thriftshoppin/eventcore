-- Custom ink widget catalog and native HUD settings (server + client).
--
-- Each entry describes ONE custom widget the way the game's own HUD is built: it is mounted into a
-- layer (the HUD lives in `inkHUDLayer`), optionally under an existing game controller, uses an ink
-- widget type, and exposes typed fields the server may set. The server validates every value
-- against these fields before anything reaches a client. Adding a widget = adding an entry here;
-- the bench, the exports and the client adapters pick it up with no other change.
--
--   mount      layer name from EventCore.NativeRegistry.layers (normally "inkHUDLayer")
--   parent     optional controller name from EventCore.NativeRegistry.controllers to attach under
--   inkType    optional ink widget type from EventCore.NativeRegistry.widgets (informational)
--   fields     [name] = { type = "number"|"boolean"|"string"|"enum", ... , default = ... }
--       number:  min, max (values are clamped)      string: maxLen (default 64)
--       enum:    values = { "a", "b" }
EventCore = EventCore or {}

EventCore.NativeHudConfig = {
    -- Show health/stamina/weapon/speedometer again when EventCore starts. Off by default because
    -- RPCore may be hiding them on purpose.
    restoreOnStart = false,
}

EventCore.WidgetCatalog = {
    -- Example only. Replace or extend with the widgets you are designing.
    ["example.meter"] = {
        mount = "inkHUDLayer",
        inkType = "inkRectangleWidget",
        fields = {
            visible = { type = "boolean", default = true },
            value = { type = "number", min = 0, max = 100, default = 0 },
            label = { type = "string", maxLen = 32, default = "" },
            tone = { type = "enum", values = { "normal", "warn", "critical" }, default = "normal" },
        },
    },
}
