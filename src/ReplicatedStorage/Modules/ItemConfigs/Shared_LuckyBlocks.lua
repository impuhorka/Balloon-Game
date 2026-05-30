--// Shared_LuckyBlocks - Lucky block configurations
--// Key = model name (Assets.LuckyBlocks:FindFirstChild(blockId))
--// Reward = table of brainrot chances { [BrainrotConfigName] = weight, ... }
--// Optional level for hatched brainrot:
--//   Level = number        → fixed level (e.g. 25)
--//   LevelMin, LevelMax   → random level in range (e.g. 10, 30)
--//   If omitted → default random 5–40

local Module = {}

-- Lucky block hold animation (two-handed pose, same as brainrots)
Module.HoldAnimation = "Assets.PlayerAnimations.TwoHandHolding"

Module.List = {

	CommonLuckyBlock = {
		DisplayName = "Common Lucky Block",
		Icon = "rbxassetid://139312474028542",
		Rarity = "Common",
		LevelMin = 1,
		LevelMax = 15,
		RarityPool = {
			Common = 90, -- 95% Common
			Rare = 10,    -- 5% chance for tier ahead
		},
	},

	RareLuckyBlock = {
		DisplayName = "Rare Lucky Block",
		Icon = "rbxassetid://135047745531091",
		Rarity = "Rare",
		LevelMin = 1,
		LevelMax = 15,
		RarityPool = {
			Common = 5,  -- 10% chance for tier below
			Rare = 85,    -- 90% main rarity
			Epic = 10,
		},
	},

	EpicLuckyBlock = {
		DisplayName = "Epic Lucky Block",
		Icon = "rbxassetid://101493073273518",
		Rarity = "Epic",
		LevelMin = 1,
		LevelMax = 15,
		RarityPool = {
			Rare = 5,    -- 10% chance for tier below
			Epic = 85,    -- 85% main rarity
			Legendary = 10, -- 5% chance for tier ahead
		},
	},

	LegendaryLuckyBlock = {
		DisplayName = "Legendary Lucky Block",
		Icon = "rbxassetid://108542620331487",
		Rarity = "Legendary",
		LevelMin = 1,
		LevelMax = 20,
		RarityPool = {
			Epic = 5,      -- 10% chance for tier below
			Legendary = 85, -- 85% main rarity
			Mythical = 10,   -- 5% chance for tier ahead
		},
	},

	MythicalLuckyBlock = {
		DisplayName = "Mythical Lucky Block",
		Icon = "rbxassetid://85969787725314",
		Rarity = "Mythical",
		LevelMin = 1,
		LevelMax = 25,
		RarityPool = {
			Legendary = 5, -- 10% chance for tier below
			Mythical = 85,  -- 85% main rarity
			Secret = 10,     -- 5% chance for tier ahead
		},
	},

	SecretLuckyBlock = {
		DisplayName = "Secret Lucky Block",
		Icon = "rbxassetid://107547428118639",
		Rarity = "Secret",
		LevelMin = 1,
		LevelMax = 30,
		RarityPool = {
			Mythical = 5,  -- 10% chance for tier below
			Secret = 90,    -- 85% main rarity
			Celestial = 5,  -- 5% chance for tier ahead
		},
	},

	CelestialLuckyBlock = {
		DisplayName = "Celestial Lucky Block",
		Icon = "rbxassetid://90822148934857",
		Rarity = "Celestial",
		LevelMin = 5,
		LevelMax = 30,
		RarityPool = {
			Secret = 1,    -- 10% chance for tier below
			Celestial = 94, -- 85% main rarity
			Divine = 5,     -- 5% chance for tier ahead
		},
	},

	DivineLuckyBlock = {
		DisplayName = "Divine Lucky Block",
		Icon = "rbxassetid://122030287468322",
		Rarity = "Divine",
		LevelMin = 20,
		LevelMax = 45,
		RarityPool = {
			Celestial = 10, -- 10% chance for tier below
			Divine = 90,    -- 90% main rarity (highest tier)
		},
	},

	OPLuckyBlock = {
		DisplayName = "Void Lucky Block",
		Icon = "rbxassetid://78946681963112",
		Rarity = "Admin",
		LevelMin = 15,
		LevelMax = 40,
		Reward = {
			-- BEST BLOCK: Celestial (low→high %) + 1 Divine at 2%
			["LaVaccaSaturnoSaturnita"] = 30, -- Celestial T1 (weakest, highest %)
			["ChillinChili"] = 22, -- Celestial T2
			["EsokSekolah"] = 16, -- Celestial T3
			["HappyBananaCat"] = 12, -- Celestial T4
			["LaGrandeCombinasion"] = 8, -- Celestial T5
			["JobJobJobSahur"] = 6, -- Celestial T9
			["KarkerkarKurkur"] = 4, -- Celestial T10 (strongest Celestial, lowest %)
			["Trollface"] = 2, -- Divine (only 1 Divine, 2%)
		},
	},

	MythicalPlusLuckyBlock = {
		DisplayName = "Dragon Lucky Block",
		Icon = "rbxassetid://81199801386158",
		Rarity = "Admin",
		LevelMin = 15,
		LevelMax = 40,
		Reward = {
			-- BETTER BLOCK: Mythical→Secret→Celestial (low→high %) + 1 Divine at 0.1%
			["FrigoCamelo"] = 36, -- Mythical T1 (weakest, highest %)
			["BombombiniGusini"] = 27, -- Mythical T4
			["Pakrahmatmamat"] = 18, -- Mythical T9
			["GirafaCelestre"] = 10, -- Secret T1
			["LosTralaleritos"] = 6, -- Secret T7
			["LaVaccaSaturnoSaturnita"] = 3, -- Celestial T1 (strongest non-Divine)
			["NyanCat"] = 0.1, -- Divine (only 1 Divine, 0.1%)
		},
	},

	GodLuckyBlock = {
		DisplayName = "Holy Lucky Block",
		Icon = "rbxassetid://99094593615344",
		Rarity = "Admin",  -- Admin-only, not spawnable naturally
		LevelMin = 15,
		LevelMax = 40,
		Reward = {
			-- WORST BLOCK: Legendary→Mythical→Secret (low→high %) + 1 Divine at 0.01%
			["BurbaloniLoliloli"] = 35, -- Legendary T1 (weakest, highest %)
			["BalerinaCapucina"] = 28, -- Legendary T4
			["SmurfCat"] = 18, -- Legendary T10
			["FrigoCamelo"] = 10, -- Mythical T1
			["BombombiniGusini"] = 6, -- Mythical T4
			["GirafaCelestre"] = 3, -- Secret T1 (strongest non-Divine)
			["Illuminati"] = 0.01, -- Divine (only 1 Divine, 0.01%)
		},
	},

	SixtySevenLuckyBlock = {
		DisplayName = "67 Lucky Block",
		Icon = "rbxassetid://103235654297526",
		Rarity = "Admin",
		LevelMin = 1,
		LevelMax = 2,
		Reward = {
			-- Guaranteed 67
			["67"] = 100,
		},
	},
}

-- Display order for UI (key = model name)
Module.OrderedIds = {
	"RainbowLuckyBlock",
	"CommonLuckyBlock",
	"RareLuckyBlock",
	"EpicLuckyBlock",
	"LegendaryLuckyBlock",
	"MythicalLuckyBlock",
	"SecretLuckyBlock",
	"CelestialLuckyBlock",
	"DivineLuckyBlock",
	"OPLuckyBlock",
	"MythicalPlusLuckyBlock",
	"GodLuckyBlock",
	"SixtySevenLuckyBlock",
}

--[[
	Model name for Assets.LuckyBlocks lookup. Key is the model name.
	@param blockId string - Lucky block config key (e.g. "CommonLuckyBlock")
	@return string - Name to pass to Assets.LuckyBlocks:FindFirstChild(...)
]]
function Module:GetModelAssetName(blockId: string): string
	return blockId
end

return Module