-- EventCore owns the administrator entry point and its read-only operations.
-- Open77/Warden remains the only authority that changes global ACL roles.
EventCore = EventCore or {}
EventCore.Admin = EventCore.Admin or {}

local lastRequestAt = {}
local lastCommandAt = {}
local REQUEST_INTERVAL_MS = 500
local COMMAND_INTERVAL_MS = 250
local PANEL_CALLERS = { open77_admin = true }

-- These are the existing server tool commands exposed in the EventCore UI.
-- Open77 still enforces command.<name> when each command is executed.
local PANEL_COMMANDS = {
    ["admin.player.heal"] = true,
    ["admin.player.revive"] = true,
    ["admin.player.kill"] = true,
    ["admin.player.goto"] = true,
    ["admin.player.bring"] = true,
    ["admin.moderate.kick"] = true,
    ["admin.moderate.ban"] = true,
    ["admin.read.players"] = true,
    ["admin.read.audit"] = true,
    ["admin.server.status"] = true,
    ["admin.world.announce"] = true,
    ["admin.world.cleanup"] = true,
    ["admin.self.noclip"] = true,
    ["admin.self.fly"] = true,
    ["admin.self.heal"] = true,
    ["admin.self.revive"] = true,
    ["admin.self.god"] = true,
}

local function playerId(value)
    value = tonumber(value)
    if not value or value < 1 or value % 1 ~= 0 then return nil end
    return value
end

local function requireAdmin(source)
    local id = playerId(source)
    if not id then return false, "player_required" end
    local allowed, reason = EventCore.Access.IsLocalAdmin(id)
    if allowed ~= true then return false, reason or "global_admin_required" end
    return true, id
end

local function reply(source, raw, accepted, message)
    source = tonumber(source) or 0
    if source <= 0 then
        print("[EventCore][admin] " .. tostring(message))
        return
    end
    TriggerClientEvent("open77:command:result", source, raw or "", accepted == true, tostring(message))
end

local function openPanel(id)
    return EventCore.EmitClient("admin:open", id, { version = EventCore.VERSION })
end

local function commandAllowed(id, command)
    local panelAction = PANEL_COMMANDS[command] == true
    local adminTool = type(command) == "string" and #command <= 64
        and command:sub(1, 6) == "admin."
        and command:match("^[a-z0-9_.%-]+$") ~= nil
    if not (panelAction or adminTool) or not (Open77 and Open77.acl and Open77.acl.isAllowed) then
        return false
    end
    local ok, allowed = pcall(Open77.acl.isAllowed, id, "command." .. command)
    return ok and allowed == true
end

RegisterCommand("eventcore.admin", function(source, _, raw)
    local allowed, idOrReason = requireAdmin(source)
    if not allowed then return reply(source, raw, false, "EventCore admin access denied: " .. tostring(idOrReason)) end
    openPanel(idOrReason)
    reply(source, raw, true, "EventCore admin menu opened.")
end, true)

RegisterCommand("eventcore.admins", function(source, _, raw)
    local allowed, idOrReason = requireAdmin(source)
    if not allowed then return reply(source, raw, false, "EventCore admin access denied: " .. tostring(idOrReason)) end
    local rows, reason = EventCore.Access.GetLocalOnlineAdmins()
    if not rows then return reply(source, raw, false, "Admin list unavailable: " .. tostring(reason)) end
    if #rows == 0 then return reply(source, raw, true, "No global admins are online.") end
    for _, row in ipairs(rows) do
        local name = Open77.players.name(row.playerId) or ("Player " .. row.playerId)
        reply(source, raw, true, ("Global admin %d: %s (%s)")
            :format(row.playerId, tostring(name), table.concat(row.roles, ", ")))
    end
end, true)

RegisterCommand("eventcore.roles", function(source, args, raw)
    local allowed, idOrReason = requireAdmin(source)
    if not allowed then return reply(source, raw, false, "EventCore admin access denied: " .. tostring(idOrReason)) end
    local target = playerId(args and args[1])
    if not target or Open77.players.name(target) == nil then
        return reply(source, raw, false, "Usage: /eventcore.roles <online player id>")
    end
    local roles, reason = EventCore.Access.GetLocalPlayerRoles(target)
    if not roles then return reply(source, raw, false, "Role lookup failed: " .. tostring(reason)) end
    reply(source, raw, true, ("Player %d roles: %s")
        :format(target, #roles > 0 and table.concat(roles, ", ") or "none"))
end, true)

RegisterCommand("eventcore.services", function(source, _, raw)
    local allowed, idOrReason = requireAdmin(source)
    if not allowed then return reply(source, raw, false, "EventCore admin access denied: " .. tostring(idOrReason)) end
    local services = EventCore.Services.List()
    reply(source, raw, true, ("EventCore services (%d):"):format(#services))
    for _, service in ipairs(services) do
        reply(source, raw, true, ("%s v%s — %s"):format(service.id, service.version, service.resource))
    end
end, true)

RegisterCommand("eventcore.events", function(source, _, raw)
    local allowed, idOrReason = requireAdmin(source)
    if not allowed then return reply(source, raw, false, "EventCore admin access denied: " .. tostring(idOrReason)) end
    local events = EventCore.GetHandlerDiagnostics()
    reply(source, raw, true, ("EventCore handlers (%d event(s), %d listener(s)):")
        :format(#events, EventCore.GetRegisteredCount()))
    for _, event in ipairs(events) do
        reply(source, raw, true, ("%s — %d listener(s)"):format(event.event, event.count))
    end
end, true)

RegisterCommand("eventcore.help", function(source, _, raw)
    local allowed, idOrReason = requireAdmin(source)
    if not allowed then return reply(source, raw, false, "EventCore admin access denied: " .. tostring(idOrReason)) end
    reply(source, raw, true, "EventCore admin commands: /eventcore.admin, /eventcore.admins, /eventcore.roles <id>, /eventcore.services, /eventcore.events, /eventcore.help")
end, true)

RegisterNetEvent("eventcore:admin:request", function(requestId)
    local id = playerId(source)
    if not id or type(requestId) ~= "string" or #requestId > 48 then return end
    local allowed = requireAdmin(id)
    if not allowed then
        EventCore.EmitClient("admin:denied", id, { reason = "global_admin_required" })
        return
    end
    local now = GetGameTimer()
    if lastRequestAt[id] and now - lastRequestAt[id] < REQUEST_INTERVAL_MS then return end
    lastRequestAt[id] = now

    local rows = {}
    for _, rawId in ipairs(GetPlayers()) do
        local target = playerId(rawId)
        if target then
            local roles = EventCore.Access.GetLocalPlayerRoles(target) or {}
            rows[#rows + 1] = {
                playerId = target,
                name = tostring(Open77.players.name(target) or ("Player " .. target)),
                roles = roles,
                isAdmin = EventCore.Access.IsLocalAdmin(target) == true,
            }
        end
    end
    table.sort(rows, function(left, right)
        if left.isAdmin ~= right.isAdmin then return left.isAdmin end
        return left.playerId < right.playerId
    end)
    local availableCommands = {}
    for command in pairs(PANEL_COMMANDS) do
        if commandAllowed(id, command) then availableCommands[#availableCommands + 1] = command end
    end
    table.sort(availableCommands)
    local admins = EventCore.Access.GetLocalOnlineAdmins() or {}
    EventCore.EmitClient("admin:data", id, {
        requestId = requestId,
        version = EventCore.VERSION,
        apiVersion = EventCore.API_VERSION,
        serviceCount = #EventCore.Services.List(),
        players = rows,
        admins = admins,
        availableCommands = availableCommands,
        services = EventCore.Services.List(),
        eventHandlers = EventCore.GetHandlerDiagnostics(),
    })
end)

-- The panel can request quick actions or syntactically valid admin.* commands.
-- EventCore verifies global admin and the command ACL here; Open77's restricted
-- command dispatcher verifies command.<name> again when the client submits it.
RegisterNetEvent("eventcore:admin:command", function(command, args)
    local id = playerId(source)
    if not id then return end
    local allowed = requireAdmin(id)
    if not allowed then
        EventCore.EmitClient("admin:denied", id, { reason = "global_admin_required" })
        return
    end
    if type(command) ~= "string" or not commandAllowed(id, command) or type(args) ~= "table" then
        EventCore.EmitClient("admin:commandResult", id, { ok = false, message = "Command is unavailable for your Warden role." })
        return
    end
    local now = GetGameTimer()
    if lastCommandAt[id] and now - lastCommandAt[id] < COMMAND_INTERVAL_MS then return end
    lastCommandAt[id] = now
    local safeArgs = {}
    local count = #args
    if count > 12 then return end
    local keyCount = 0
    for key in pairs(args) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > count then return end
        keyCount = keyCount + 1
    end
    if keyCount ~= count then return end
    for index, value in ipairs(args) do
        if type(value) ~= "string" and type(value) ~= "number" then return end
        local text = tostring(value)
        if #text > 160 or text:find("[%c]") then return end
        safeArgs[index] = text
    end
    EventCore.EmitClient("admin:executeCommand", id, { command = command, args = safeArgs })
end)

AddEventHandler("playerDropped", function()
    local id = tonumber(source)
    if id then lastRequestAt[id], lastCommandAt[id] = nil, nil end
end)

-- Compatibility bridge for the bundled command resource while its launcher
-- moves to EventCore. The caller is fixed; the target is still checked here.
exports("OpenAdminPanel", function(targetPlayer)
    local caller = GetInvokingResource and GetInvokingResource() or nil
    if not PANEL_CALLERS[caller] then return false, "admin_panel_caller_not_trusted" end
    local allowed, idOrReason = requireAdmin(targetPlayer)
    if not allowed then return false, idOrReason end
    openPanel(idOrReason)
    return true
end)
