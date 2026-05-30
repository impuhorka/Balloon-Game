local Server_RebirthStore = {}

function Server_RebirthStore:DoRebirth(_player: Player, _skipRequirements: boolean)
	return false, "Rebirth system is not configured in this project."
end

return Server_RebirthStore
