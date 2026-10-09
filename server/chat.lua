-- Server-authoritative chat validation and fan-out for EventCore's skin.
EventCore = EventCore or {}
EventCore.Chat = EventCore.Chat or {}

local lastMessageAt = {}
local MESSAGE_INTERVAL_MS = 750
local MAX_MESSAGE_BYTES = 512

local function cleanMessage(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("[%c]", " "):match("^%s*(.-)%s*$") or ""
    if #value == 0 or #value > MAX_MESSAGE_BYTES or value:sub(1, 1) == "/" then return nil end
    return value
end

local function send(target, line)
    if not target or target == -1 then
        EventCore.BroadcastClient("chat:line", line)
        return true
    end
    return EventCore.EmitClient("chat:line", target, line)
end

function EventCore.Chat.Send(target, message, kind, author)
    target = tonumber(target)
    if not target or target == 0 or target < -1 or target % 1 ~= 0 then return false, "invalid_chat_target" end
    if kind ~= nil and kind ~= "player" and kind ~= "system" then return false, "invalid_chat_type" end
    if target > 0 and (not Open77.players or Open77.players.name(target) == nil) then
        return false, "invalid_chat_target"
    end
    local text = cleanMessage(message)
    if not text then return false, "invalid_chat_message" end
    local line = {
        type = kind == "system" and "system" or "player",
        author = type(author) == "string" and author:sub(1, 48) or "",
        text = text,
        at = os.time(),
    }
    return send(target, line)
end

RegisterNetEvent("eventcore:chat:send", function(message)
    local playerId = tonumber(source)
    if not playerId or playerId < 1 then return end
    local now = GetGameTimer()
    if lastMessageAt[playerId] and now - lastMessageAt[playerId] < MESSAGE_INTERVAL_MS then
        EventCore.EmitClient("chat:line", playerId, { type = "system", author = "", text = "Please wait before sending another message.", at = os.time() })
        return
    end
    local text = cleanMessage(message)
    if not text then
        EventCore.EmitClient("chat:line", playerId, { type = "system", author = "", text = "Message is empty or exceeds the 512 byte limit.", at = os.time() })
        return
    end
    lastMessageAt[playerId] = now
    local name = Open77.players.name(playerId) or ("Player " .. playerId)
    local line = { type = "player", author = tostring(name):sub(1, 48), text = text, at = os.time() }
    EventCore.DispatchLocal("chat:accepted", line, playerId)
    EventCore.BroadcastClient("chat:line", line)
end)

AddEventHandler("playerDropped", function()
    lastMessageAt[tonumber(source)] = nil
end)

-- Keep player messages accepted by the platform chat authority visible in the
-- EventCore client, including messages arriving from other compatible clients.
local platformMessageHandler
local function installPlatformMessageBridge()
    if platformMessageHandler or not (Open77 and Open77.chat and type(Open77.chat.onMessage) == "function") then return end
    local handler, reason = Open77.chat.onMessage(function(playerId, playerName, text)
        if tonumber(playerId) and type(text) == "string" then
            EventCore.BroadcastClient("chat:line", {
                type = "player", author = tostring(playerName or ("Player " .. playerId)):sub(1, 48),
                text = text:sub(1, MAX_MESSAGE_BYTES), at = os.time(),
            })
        end
    end)
    if handler then platformMessageHandler = handler
    else print("[EventCore][chat] platform message bridge unavailable: " .. tostring(reason)) end
end

AddEventHandler("onResourceStart", function(name)
    if name == GetCurrentResourceName() or name == "open77_chat" then installPlatformMessageBridge() end
end)

exports("SendChat", function(target, message, kind, author)
    local caller = GetInvokingResource and GetInvokingResource() or nil
    if not caller or not EventCore.Persistence or not EventCore.Persistence.IsTrustedCaller(caller) then
        return false, "chat_caller_not_trusted"
    end
    return EventCore.Chat.Send(target, message, kind, author)
end)
