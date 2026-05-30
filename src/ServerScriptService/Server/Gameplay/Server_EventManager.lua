local Server_EventManager = {}

local NOT_CONFIGURED = "Event system is not configured in this project."

function Server_EventManager:GetActiveEventConfig()
	return nil
end

function Server_EventManager:StartLocalEvent(_eventName: string)
	return false, NOT_CONFIGURED
end

function Server_EventManager:EndEvent()
	return false, NOT_CONFIGURED
end

function Server_EventManager:StartGlobalEvent(_eventName: string)
	return false, NOT_CONFIGURED
end

function Server_EventManager:EndGlobalEvent()
	return false, NOT_CONFIGURED
end

function Server_EventManager:GetAvailableEvents()
	return {}
end

return Server_EventManager
