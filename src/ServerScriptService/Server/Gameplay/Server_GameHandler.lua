local Server_GameHandler = {}

function Server_GameHandler:AddForcedGreenLightTime(_duration: number, _sourceName: string?)
	return false
end

function Server_GameHandler:ToggleGodmode(_player: Player)
	return false
end

return Server_GameHandler
