-- EventCore chat skin. The platform remains the command authority: client
-- commands resolve locally, and unknown slash commands use Open77's normal
-- authenticated server command transport (including its ACL checks).
local page
local opened = false
local history = {}
local MAX_HISTORY = 60

local function post(channel, payload)
    if page then page:send(channel, payload or {}) end
end

local function remember(line)
    if type(line) ~= "table" or type(line.text) ~= "string" then return end
    local systemLine = line.type == "system"
    local author = type(line.author) == "string" and line.author:sub(1, 48) or ""
    if systemLine and author == "" then author = "EventCore" end
    history[#history + 1] = {
        type = systemLine and "system" or "player",
        author = author,
        text = line.text:sub(1, 512),
        at = type(line.at) == "number" and line.at or os.time(),
    }
    while #history > MAX_HISTORY do table.remove(history, 1) end
    post("eventcore:chat:line", history[#history])
end

local function closeChat()
    opened = false
    post("eventcore:chat:open", { open = false })
    if page and type(page.setFocus) == "function" then page:setFocus(false, false) end
end

local function openChat()
    if not page then return end
    opened = true
    if type(page.setFocus) == "function" then
        local called, focused, reason = pcall(function() return page:setFocus(true, false) end)
        if not called or focused ~= true then
            print("[EventCore][chat] keyboard focus failed: " .. tostring(called and reason or focused))
        end
    end
    post("eventcore:chat:open", { open = true, history = history })
end

local function words(line)
    local result, current, quote, escaped = {}, {}, nil, false
    for index = 1, #line do
        local char = line:sub(index, index)
        if escaped then current[#current + 1] = char; escaped = false
        elseif char == "\\" and quote then escaped = true
        elseif quote then
            if char == quote then quote = nil else current[#current + 1] = char end
        elseif char == '"' or char == "'" then quote = char
        elseif char:match("%s") then
            if #current > 0 then result[#result + 1] = table.concat(current); current = {} end
        else current[#current + 1] = char end
    end
    if escaped or quote then return nil, "Unclosed quote in command." end
    if #current > 0 then result[#result + 1] = table.concat(current) end
    if #result == 0 or #result > 32 then return nil, "Command must contain 1–32 parts." end
    for _, part in ipairs(result) do
        if #part > 256 then return nil, "A command argument is too long." end
    end
    return result
end

local function submit(line)
    if type(line) ~= "string" then return end
    line = line:gsub("[%c]", " "):match("^%s*(.-)%s*$") or ""
    if #line == 0 then closeChat(); return end
    if #line > 512 then remember({ type = "system", text = "Message is too long." }); return end
    if line:sub(1, 1) == "/" then
        local commandLine = line:sub(2)
        local localAccepted, localReason = ExecuteCommand(commandLine)
        if localAccepted then closeChat(); return end
        if localReason and localReason ~= "unknown_command" then
            remember({ type = "system", text = tostring(localReason) })
            return
        end
        local args, parseError = words(commandLine)
        if not args then remember({ type = "system", text = parseError }); return end
        TriggerServerEvent("open77:command:execute", table.unpack(args))
    else
        TriggerServerEvent("eventcore:chat:send", line)
    end
    closeChat()
end

local function createPage()
    if page then return true end
    local surface, reason = Open77.webui.create({
        entry = "web/chat/index.html", layer = "menu", zIndex = 780,
        transparent = true, visible = true,
    })
    if not surface then
        print("[EventCore][chat] chat surface failed: " .. tostring(reason))
        return false
    end
    page = surface
    page:on("eventcore:chat:ready", function()
        post("eventcore:chat:history", { lines = history })
        post("eventcore:chat:open", { open = opened, history = history })
    end)
    page:on("eventcore:chat:submit", function(payload)
        if type(payload) == "table" then submit(payload.text) end
    end)
    page:on("eventcore:chat:close", closeChat)
    return true
end

RegisterCommand("eventcore.chat", openChat, false, { help = "Open EventCore chat" })

local function registerChatKey()
    local input = Open77 and Open77.input
    if not input or type(input.registerKeyMapping) ~= "function" then
        print("[EventCore][chat] key mapping API unavailable")
        return
    end
    local ok, accepted, effective = pcall(input.registerKeyMapping, {
        id = "eventcore.chat", name = "Open EventCore chat", key = "T", hold = false,
        onPressed = openChat,
    })
    if not ok or accepted ~= true then
        print("[EventCore][chat] key mapping failed: " .. tostring(ok and effective or accepted))
    else
        print("[EventCore][chat] bound to " .. tostring(effective))
    end
end

RegisterNetEvent("eventcore:net:chat:line", remember)
RegisterNetEvent("open77:command:result", function(raw, accepted, message)
    if type(message) ~= "string" then return end
    local text = message
    if accepted == false and raw and raw ~= "" then text = tostring(raw) .. ": " .. message end
    remember({ type = "system", author = "EventCore", text = text })
end)

AddEventHandler("onClientResourceStart", function(name)
    if name ~= GetCurrentResourceName() then return end
    createPage()
    registerChatKey()
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    closeChat()
    if page then page:destroy(); page = nil end
end)
