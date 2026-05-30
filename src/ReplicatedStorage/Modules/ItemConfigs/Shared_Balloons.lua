--// Shared_Balloons — shop definitions + merged BalloonConfig (gameplay tuning lives in BalloonConfig.lua).
local BalloonConfig = require(script.Parent.BalloonConfig)

local Balloons = table.clone(BalloonConfig)

Balloons.List = {
	["BasicBalloon"] = {
		DisplayName = "Basic Balloon",
		HP = 200,
		Cost = 100,
	},
	["AdvancedBalloon"] = {
		DisplayName = "Advanced Balloon",
		HP = 300,
		Cost = 200,
	},
	["ExpertBalloon"] = {
		DisplayName = "Expert Balloon",
		HP = 450,
		Cost = 300,
	},
}

return Balloons
