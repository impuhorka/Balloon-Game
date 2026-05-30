local Shared_ZoneConfig = {}

Shared_ZoneConfig.LuckyBlockChance = 0

Shared_ZoneConfig.Zones = {
	Zone1 = {
		BrainrotsPerZone = 8,
		LevelRange = {1, 5},
		Rarities = {
			Common = 80,
			Rare = 18,
			Epic = 2,
		},
		LuckScalingRarities = {"Rare", "Epic"},
		LuckyBlocks = {},
	},
}

function Shared_ZoneConfig:GetZoneConfig(zoneID: string)
	return self.Zones[zoneID] or self.Zones.Zone1
end

function Shared_ZoneConfig:GetLevelRange(zoneID: string)
	local zoneConfig = self:GetZoneConfig(zoneID)
	return zoneConfig and zoneConfig.LevelRange
end

function Shared_ZoneConfig:GetLuckyBlockForRarity(zoneID: string, rarity: string)
	local zoneConfig = self:GetZoneConfig(zoneID)
	local luckyBlocks = zoneConfig and zoneConfig.LuckyBlocks
	return luckyBlocks and luckyBlocks[rarity] or nil
end

function Shared_ZoneConfig:GetLuckyBlockChance()
	return self.LuckyBlockChance
end

function Shared_ZoneConfig:SetLuckyBlockChance(chance: number)
	self.LuckyBlockChance = math.clamp(chance or 0, 0, 100)
end

return Shared_ZoneConfig
