local Shooters = {}

Shooters.Levels = {
	[1] = {
		DisplayName = "Archer",
		DMG = { 10, 100 }, -- per-shot random range [min, max]
		Cooldown = 2.5
	},
	[2] = {
		DisplayName = "Medium",
		DMG = { 100, 250 }, -- per-shot random range [min, max]
		Cooldown = 2.5,
	},
	[3] = {
		DisplayName = "Hard",
		DMG = { 250, 10000 }, -- per-shot random range [min, max]
		Cooldown = 2.5,
	},
}

Shooters.PitchLimits = {
	Standing_Archer = { Min = -10, Max = 50 },
	Standing_Cannon = { Min = -25, Max = 50 },
	Wall_Cannon = { Min = -90, Max = 0 },
	Wall_Archer = { Min = -90, Max = 0 },
	Wall_Sniper = { Min = 10, Max = 85 },
	Standing_Sniper = { Min = -50, Max = 50 },
}

--[[ position_id matches workspace spawner part Shooter{position_id}. ]]
Shooters.ShooterTypes = {
	[1] = {
		Level = 1,
		PositionName = "Archer",
	},
	[2] = {
		Level = 2,
		PositionName = "Cannon",
	},
	[3] = {
		Level = 3,
		PositionName = "Sniper",
	},
}

function Shooters.GetLevelForModel(modelName: string): number?
	local positionName = string.match(modelName, "^%a+_(.+)$")
	if not positionName then
		return nil
	end
	for _, entry in pairs(Shooters.ShooterTypes) do
		if entry.PositionName == positionName then
			return entry.Level
		end
	end
	return nil
end

function Shooters.GetCooldown(modelName: string): number
	local level = Shooters.GetLevelForModel(modelName)
	local cfg = level and Shooters.Levels[level]
	return cfg and cfg.Cooldown or 2.5
end

return Shooters
