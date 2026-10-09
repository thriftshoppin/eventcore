-- Read-only access to Warden's effective in-game ACL roles.
-- EventCore never assigns or edits platform administration rights.

EventCore = EventCore or {}
EventCore.Access = EventCore.Access or {}

local trustedAccessReaders = {
    rpcore = true,
}

local function trustedCaller()
    local caller = GetInvokingResource and GetInvokingResource() or nil
    return type(caller) == "string" and trustedAccessReaders[caller] == true
end

local function playerRoles(playerId)
    if type(playerId) == "string" then playerId = tonumber(playerId) end
    if type(playerId) ~= "number" or playerId < 1 or playerId % 1 ~= 0 then
        return nil, "invalid_player_id"
    end
    if not (Open77 and Open77.acl and type(Open77.acl.roles) == "function") then
        return nil, "acl_unavailable"
    end

    local ok, roles, reason = pcall(Open77.acl.roles, playerId)
    if not ok then return nil, "acl_query_failed" end
    if type(roles) ~= "table" then return nil, reason or "acl_query_failed" end
    return roles
end

--- Return the connected player's effective role labels from Open77's ACL.
function EventCore.Access.GetPlayerRoles(playerId)
    if not trustedCaller() then return nil, "access_caller_not_trusted" end
    return playerRoles(playerId)
end

local function hasGlobalAdminRole(roles)
    for _, role in ipairs(roles) do
        if role == "admin" or role == "owner" then return true end
    end
    return false
end

--- True only for Open77's reserved global admin/owner roles.
--- Scoped roles such as helper, moderator, or operator remain false.
function EventCore.Access.IsAdmin(playerId)
    if not trustedCaller() then return nil, "access_caller_not_trusted" end
    local roles, reason = playerRoles(playerId)
    if not roles then return nil, reason end
    return hasGlobalAdminRole(roles)
end

--- Return the connected players holding Open77's reserved admin/owner roles.
function EventCore.Access.GetOnlineAdmins()
    if not trustedCaller() then return nil, "access_caller_not_trusted" end
    if type(GetPlayers) ~= "function" then return nil, "player_list_unavailable" end

    local ok, playerIds = pcall(GetPlayers)
    if not ok or type(playerIds) ~= "table" then return nil, "player_list_unavailable" end

    local result = {}
    for _, value in ipairs(playerIds) do
        local playerId = tonumber(value)
        if playerId and playerId > 0 and playerId % 1 == 0 then
            local roles, reason = playerRoles(playerId)
            if not roles then return nil, reason end
            if hasGlobalAdminRole(roles) then
                result[#result + 1] = { playerId = playerId, roles = roles }
            end
        end
    end
    table.sort(result, function(left, right) return left.playerId < right.playerId end)
    return result
end

exports("IsAdmin", EventCore.Access.IsAdmin)
exports("GetPlayerRoles", EventCore.Access.GetPlayerRoles)
exports("GetOnlineAdmins", EventCore.Access.GetOnlineAdmins)
