--// Shared_Balloons — shop definitions + merged BalloonConfig (gameplay tuning lives in BalloonConfig.lua).
local BalloonConfig = require(script.Parent.BalloonConfig)

local Balloons = table.clone(BalloonConfig)

Balloons.ShopOrder = {
	"BasicBalloon",
	"AdvancedBalloon",
	"ExpertBalloon",
	"PinkBalloon",
	"GodlyBalloon",
	"FireBalloon",
	"BeachBalloon",
	"HotAirBalloon",
}

Balloons.Icons = {
	BasicBalloon = "rbxassetid://130526696031554",
	AdvancedBalloon = "rbxassetid://76933990649135",
	ExpertBalloon = "rbxassetid://121481100107951",
	PinkBalloon = "rbxassetid://113267063647878",
	BeachBalloon = "rbxassetid://130746776729637",
	FireBalloon = "rbxassetid://134899154496392",
	GodlyBalloon = "rbxassetid://94697764078387",
	HotAirBalloon = "rbxassetid://110250056311238",
}

Balloons.List = {
	["BasicBalloon"] = {
		DisplayName = "Basic Balloon",
		Rarity = "Common",
		HP = 200,
		Cost = 100,
	},
	["AdvancedBalloon"] = {
		DisplayName = "Advanced Balloon",
		Rarity = "Uncommon",
		HP = 300,
		Cost = 250,
	},
	["ExpertBalloon"] = {
		DisplayName = "Expert Balloon",
		Rarity = "Rare",
		HP = 450,
		Cost = 500,
	},
	["PinkBalloon"] = {
		DisplayName = "Pink Balloon",
		Rarity = "Epic",
		HP = 600,
		Cost = 1000,
	},
	["GodlyBalloon"] = {
		DisplayName = "Godly Balloon",
		Rarity = "Legendary",
		HP = 800,
		Cost = 2500,
	},
	["FireBalloon"] = {
		DisplayName = "Fire Balloon",
		Rarity = "Mythical",
		HP = 1050,
		Cost = 5000,
	},
	["BeachBalloon"] = {
		DisplayName = "Beach Balloon",
		Rarity = "Secret",
		HP = 1350,
		Cost = 10000,
	},
	["HotAirBalloon"] = {
		DisplayName = "Hot Air Balloon",
		Rarity = "Divine",
		HP = 1700,
		Cost = 20000,
	},
}

return Balloons
