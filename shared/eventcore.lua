--[[
    EventCore - Shared Engine
    Standardized Event Bus for Open77
]]

EventCore = EventCore or {}
EventCore.VERSION = "0.6.5"
EventCore.API_VERSION = 1
EventCore.STATE_FEED_EVENT = "state:update"

-- Priority Levels
EventCore.PRIORITY = {
    LOWEST  = 10,
    LOW     = 20,
    NORMAL  = 30,
    HIGH    = 40,
    HIGHEST = 50,
    MONITOR = 100 -- Monitor listeners cannot cancel events; runs last
}

-- Handler registry: eventName -> list of { id, callback, priority, resource }
local handlers = {}
local middlewares = {}
local handlerIdSeq = 0

local function timestamp()
    if GetGameTimer then
        return GetGameTimer() / 1000
    end
    return 0
end

--- Wraps an event context with cancellation and metadata support
local function createEventContext(eventName, payload, source)
    local isCancelled = false
    local cancelReason = nil

    local context = {
        name = eventName,
        data = payload or {},
        source = source or -1,
        timestamp = timestamp(),
        isCancelled = function() return isCancelled end,
        cancel = function(self, reason)
            isCancelled = true
            cancelReason = reason or "Event cancelled by handler"
        end,
        getCancelReason = function() return cancelReason end
    }

    return context
end

--- Register a global middleware that executes prior to event handler dispatch
function EventCore.Use(fn)
    table.insert(middlewares, fn)
end

--- Register an event listener with optional priority
function EventCore.On(eventName, callback, priority)
    if type(eventName) ~= "string" or type(callback) ~= "function" then
        print(string.format("[EventCore][ERROR] Invalid registration for event: %s", tostring(eventName)))
        return nil
    end

    priority = priority or EventCore.PRIORITY.NORMAL

    if not handlers[eventName] then
        handlers[eventName] = {}
    end

    handlerIdSeq = handlerIdSeq + 1
    local record = {
        id = handlerIdSeq,
        callback = callback,
        priority = priority,
        resource = (GetInvokingResource and GetInvokingResource()) or "local"
    }

    table.insert(handlers[eventName], record)

    -- Keep handlers sorted by priority ascending (lower values execute first, monitor last)
    table.sort(handlers[eventName], function(a, b)
        return a.priority < b.priority
    end)

    return record.id
end

--- Remove an event listener by its ID
function EventCore.Off(eventName, handlerId)
    if not handlers[eventName] then return false end

    for i, h in ipairs(handlers[eventName]) do
        if h.id == handlerId then
            table.remove(handlers[eventName], i)
            return true
        end
    end
    return false
end

--- Internal dispatch across middlewares and registered handlers
function EventCore.DispatchLocal(eventName, payload, source)
    local context = createEventContext(eventName, payload, source)

    -- 1. Execute middlewares
    for _, mw in ipairs(middlewares) do
        local ok, err = pcall(mw, context)
        if not ok then
            print(string.format("[EventCore][ERROR] Middleware error on event '%s': %s", eventName, tostring(err)))
        end
        if context.isCancelled() then
            return context
        end
    end

    -- 2. Execute priority-ordered listeners
    local list = handlers[eventName]
    if list then
        for _, record in ipairs(list) do
            if context.isCancelled() and record.priority ~= EventCore.PRIORITY.MONITOR then
                -- Event was cancelled and this is not a monitor listener
                break
            end

            local ok, err = pcall(record.callback, context.data, context)
            if not ok then
                print(string.format("[EventCore][ERROR] Listener error in '%s' on event '%s': %s",
                    record.resource, eventName, tostring(err)))
            end
        end
    end

    return context
end

--- Return diagnostics count of active handlers
function EventCore.GetRegisteredCount()
    local count = 0
    for _, list in pairs(handlers) do
        count = count + #list
    end
    return count
end

--- Return a detached diagnostic list for server administration views.
function EventCore.GetHandlerDiagnostics()
    local result = {}
    for eventName, list in pairs(handlers) do
        local resources = {}
        for _, record in ipairs(list) do
            resources[record.resource] = (resources[record.resource] or 0) + 1
        end
        result[#result + 1] = {
            event = eventName,
            count = #list,
            resources = resources,
        }
    end
    table.sort(result, function(left, right) return left.event < right.event end)
    return result
end
