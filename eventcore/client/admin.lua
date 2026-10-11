-- Client presentation for EventCore's admin menu. The client only renders
-- server-authorized snapshots; every request is checked again on the server.
local page
local ready = false
local opened = false
local waitingForReady = false
local requestSequence = 0

local function post(channel, payload)
    if page then page:send(channel, payload or {}) end
end

local function closePanel()
    opened = false
    if page then
        post("admin:open", { open = false })
        if type(page.setFocus) == "function" then page:setFocus(false, false) end
    end
end

local function requestSnapshot()
    if not opened or not TriggerServerEvent then return end
    requestSequence = requestSequence + 1
    TriggerServerEvent("eventcore:admin:request", tostring(requestSequence))
end

local function createPage()
    if page then return true end
    local surface, reason = Open77.webui.create({
        entry = "web/admin/index.html",
        layer = "menu",
        zIndex = 760,
        transparent = true,
        visible = true,
    })
    if not surface then
        print("[EventCore] admin menu surface failed: " .. tostring(reason))
        return false
    end
    page = surface
    page:on("admin:ready", function()
        ready = true
        post("admin:open", { open = false })
        if waitingForReady then
            waitingForReady = false
            post("admin:open", { open = true })
            post("admin:loading", { loading = true })
            requestSnapshot()
        end
    end)
    page:on("admin:refresh", requestSnapshot)
    page:on("admin:close", closePanel)
    page:on("admin:command", function(payload)
        if type(payload) ~= "table" or type(payload.command) ~= "string"
            or type(payload.args) ~= "table" or not TriggerServerEvent then return end
        TriggerServerEvent("eventcore:admin:command", payload.command, payload.args)
    end)
    return true
end

EventCore.On("admin:open", function()
    if not createPage() then return end
    opened = true
    if type(page.setFocus) == "function" then page:setFocus(true, true) end
    if ready then
        post("admin:open", { open = true })
        post("admin:loading", { loading = true })
        requestSnapshot()
    else
        waitingForReady = true
    end
end)

EventCore.On("admin:data", function(payload)
    if not opened or type(payload) ~= "table" then return end
    post("admin:data", payload)
    post("admin:loading", { loading = false })
end)

EventCore.On("admin:denied", function()
    closePanel()
    if Open77 and Open77.hud then Open77.hud.notify("EventCore admin access was revoked.") end
end)

EventCore.On("admin:executeCommand", function(payload)
    if type(payload) ~= "table" or type(payload.command) ~= "string"
        or type(payload.args) ~= "table" or not TriggerServerEvent then return end
    -- The platform's restricted command transport rechecks Warden's
    -- command.<name> permission when this command reaches its handler.
    local args = { payload.command }
    for _, value in ipairs(payload.args) do args[#args + 1] = tostring(value) end
    TriggerServerEvent("open77:command:execute", table.unpack(args))
end)

EventCore.On("admin:commandResult", function(payload)
    if type(payload) == "table" and type(payload.message) == "string" then
        post("admin:commandResult", payload)
    end
end)

RegisterNetEvent("open77:command:result", function(raw, accepted, message)
    if not opened or type(message) ~= "string" then return end
    post("admin:commandResult", { ok = accepted == true, command = tostring(raw or ""), message = message })
end)

RegisterNetEvent("open77_admin:data", function(channel, payload)
    if not opened or type(channel) ~= "string" or type(payload) ~= "table" then return end
    post("admin:toolData", { channel = channel, payload = payload })
end)


AddEventHandler("onClientResourceStart", function(name)
    if name == GetCurrentResourceName() then createPage() end
end)

AddEventHandler("open77:menuStateChanged", function(isOpen)
    local open = isOpen == true or tostring(isOpen) == "1" or tostring(isOpen) == "true"
    if open and opened then closePanel() end
end)
