-- EventCore chat skin. The platform remains the command authority: client
-- commands resolve locally, and unknown slash commands use Open77's normal
-- authenticated server command transport (including its ACL checks).
local page
local opened = false
local history = {}
local MAX_HISTORY = 60
local lastSuggestionRequest = -1
local nativeTemplates = {}

local function setNativeChatEnabled(enabled)
    if not (Open77 and Open77.exports and type(Open77.exports.call) == "function") then
        return false, "Open77 chat export bridge is unavailable"
    end
    local ok, promise, reason = pcall(Open77.exports.call, "open77_chat", "setEnabled", enabled == true)
    if not ok or not promise then return false, tostring(ok and reason or promise) end
    local awaited, accepted, detail = pcall(function() return promise:await() end)
    if not awaited or accepted == false then return false, tostring(awaited and detail or accepted) end
    return true
end

local function synchronizeNativeChat(enabled)
    CreateThread(function()
        Wait(0)
        local ok, reason = setNativeChatEnabled(enabled)
        if not ok then print("[EventCore][chat] could not " .. (enabled and "restore" or "replace") .. " Open77 chat UI: " .. reason) end
    end)
end

local function post(channel, payload)
    if page then page:send(channel, payload or {}) end
end

local function remember(line)
    if type(line) ~= "table" or type(line.text) ~= "string" then return end
    local lineType = line.type == "error" and "error" or (line.type == "system" and "system" or "player")
    local author = type(line.author) == "string" and line.author:sub(1, 48) or ""
    if lineType == "system" and author == "" then author = "EventCore" end
    history[#history + 1] = {
        type = lineType,
        author = author,
        text = line.text:sub(1, 512),
        at = type(line.at) == "number" and line.at or os.time(),
    }
    while #history > MAX_HISTORY do table.remove(history, 1) end
    post("eventcore:chat:line", history[#history])
end

local function requestSuggestions()
    local now = Open77 and Open77.time and type(Open77.time.monotonic) == "function"
        and Open77.time.monotonic() or os.clock()
    if now - lastSuggestionRequest < 0.75 then return end
    lastSuggestionRequest = now
    if type(GetRegisteredCommands) == "function" then
        local suggestions = {}
        for _, entry in ipairs(GetRegisteredCommands() or {}) do
            if type(entry) == "table" and not entry.restricted and type(entry.name) == "string" then
                suggestions[#suggestions + 1] = {
                    command = "/" .. entry.name,
                    help = type(entry.help) == "string" and entry.help or "Client command",
                    parameters = type(entry.parameters) == "table" and entry.parameters or {},
                }
            end
        end
        if #suggestions > 0 then post("eventcore:chat:suggestions", { suggestions = suggestions }) end
    end
    TriggerServerEvent("chat:ready")
end

local function relayNativeMessage(message)
    if type(message) == "string" then message = { text = message } end
    if type(message) ~= "table" then return end
    local author = type(message.author) == "string" and message.author or ""
    local args = type(message.args) == "table" and message.args or {}
    local text = type(message.text) == "string" and message.text
        or (type(message.message) == "string" and message.message or "")
    if text == "" and type(message.args) == "table" then
        local first = #args > 1 and 2 or 1
        if author == "" and #args > 1 then author = tostring(args[1] or "") end
        local parts = {}
        for index = first, #args do parts[#parts + 1] = tostring(args[index] or "") end
        text = table.concat(parts, " ")
    end
    local templateId = type(message.templateId) == "string" and message.templateId or nil
    local template = templateId and nativeTemplates[templateId] or nil
    if template then
        text = template:gsub("{(%d+)}", function(index) return tostring(args[tonumber(index) + 1] or "") end)
    end
    if text == "" then return end
    if author == "" and (message.type == "system" or message.type == "server") then author = "Server" end
    remember({ type = message.type == "error" and "error" or "system", author = author, text = text })
end

local function closeChat()
    opened = false
    post("eventcore:chat:open", { open = false })
    if page and type(page.setFocus) == "function" then page:setFocus(false, false) end
end

local function acquireChatFocus()
    if not page or not opened or type(page.setFocus) ~= "function" then return false end
    local called, focused, reason = pcall(function() return page:setFocus(true, false) end)
    if not called or focused ~= true then
        print("[EventCore][chat] keyboard focus failed: " .. tostring(called and reason or focused))
        return false
    end
    return true
end

local function openChat()
    if not page then return end
    opened = true
    acquireChatFocus()
    post("eventcore:chat:open", { open = true, history = history })
    -- CEF may process the open message after the native focus change. Repeat
    -- both sides once the browser has had a frame to expose the input field.
    CreateThread(function()
        Wait(75)
        if opened and page then
            acquireChatFocus()
            post("eventcore:chat:focus", {})
        end
    end)
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
        requestSuggestions()
        CreateThread(function() Wait(1000); requestSuggestions() end)
    end)
    page:on("eventcore:chat:submit", function(payload)
        if type(payload) == "table" then submit(payload.text) end
    end)
    page:on("eventcore:chat:close", closeChat)
    page:on("eventcore:chat:requestSuggestions", requestSuggestions)
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
RegisterNetEvent("chat:addMessage", relayNativeMessage)
RegisterNetEvent("chat:addTemplate", function(id, template)
    if type(id) == "string" and type(template) == "string" then nativeTemplates[id] = template:sub(1, 1024) end
end)
RegisterNetEvent("chat:addSuggestion", function(command, help, parameters)
    post("eventcore:chat:suggestion", {
        command = tostring(command or ""), help = tostring(help or ""),
        parameters = type(parameters) == "table" and parameters or {},
    })
end)
RegisterNetEvent("chat:addSuggestions", function(suggestions)
    if type(suggestions) == "table" and type(suggestions.suggestions) == "table" then
        suggestions = suggestions.suggestions
    end
    post("eventcore:chat:suggestions", { suggestions = type(suggestions) == "table" and suggestions or {} })
end)
RegisterNetEvent("chat:removeSuggestion", function(command)
    post("eventcore:chat:removeSuggestion", { command = tostring(command or "") })
end)
RegisterNetEvent("chat:clearSuggestions", function() post("eventcore:chat:clearSuggestions", {}) end)
-- Open77 consumes Escape in the game window before it reaches the focused
-- WebUI, then republishes it as pauseKey. Close from that host event.
AddEventHandler("open77:pauseKey", closeChat)
RegisterNetEvent("open77:command:result", function(raw, accepted, message)
    if type(message) ~= "string" then return end
    if accepted == true and message:match("^queued by ") then return end
    local text = message
    if accepted == false and message == "unknown_command" then
        text = "Unknown command: /" .. tostring(raw or "") .. ". Type / to browse available commands."
    elseif accepted == false and message:match("^permission_denied:") then
        text = "You do not have permission to run /" .. tostring(raw or "") .. "."
    elseif accepted == false and raw and raw ~= "" then
        text = tostring(raw) .. ": " .. message
    end
    remember({ type = accepted == false and "error" or "system", author = "COMMAND", text = text })
end)

AddEventHandler("onClientResourceStart", function(name)
    if name ~= GetCurrentResourceName() then return end
    createPage()
    registerChatKey()
    synchronizeNativeChat(false)
end)

AddEventHandler("onClientResourceStart", function(name)
    if name == "open77_chat" then synchronizeNativeChat(false) end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    closeChat()
    -- Restore the stock UI if EventCore is stopped or reloaded. TriggerEvent
    -- is synchronous here, so the native input is available immediately.
    TriggerEvent("chat:setEnabled", true)
    if page then page:destroy(); page = nil end
end)

-- Escape is delivered through open77:pauseKey; poll only controller B as a
-- close fallback while the chat surface owns keyboard focus.
CreateThread(function()
    local padBWasDown = false
    while true do
        if opened and Open77 and Open77.input and type(Open77.input.isDown) == "function" then
            Wait(25)
            local okPadB, padBDown = pcall(Open77.input.isDown, "padB")
            padBDown = okPadB and padBDown == true
            if padBDown and not padBWasDown then
                closeChat()
            end
            padBWasDown = padBDown
        else
            Wait(100)
            padBWasDown = false
        end
    end
end)
