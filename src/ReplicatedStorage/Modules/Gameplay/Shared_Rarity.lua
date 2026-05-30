--// Shared_Rarity - Rarity colors (gradients + flat) for food and other items
--// Order: Common → Rare → Epic → Legendary → Secret → Mythical → Celestial → Divine
--// Gradient: keypoint 0 = Dolje (bottom), keypoint 1 = Gore (top)

local Shared_Rarity = {}

-- Rarity order for sorting (lower = lower tier)
Shared_Rarity.Order = {
	Common = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
	Mythical = 5,
	Secret = 6,
	Celestial = 7,
	Divine = 8,
	Admin = 99, -- Admin-only items (not spawnable, Robux/special blocks)
}

-- Gradient (2 points: 0 = Dolje, 1 = Gore) + flatColor per rarity
Shared_Rarity.List = {
	["Common"] = {
		gradient = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 180, 250))
		},
		flatColor = Color3.fromRGB(98, 210, 255),
		LayoutOrder = 1,
	},
	["Rare"] = {
		gradient = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 255, 240)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 40, 255))
		},
		flatColor = Color3.fromRGB(0, 157, 255),
		LayoutOrder = 3,
	},
	["Epic"] = {
		gradient = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 140, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(65, 20, 255))
		},
		flatColor = Color3.fromRGB(212, 0, 255),
		LayoutOrder = 4,
	},
	["Legendary"] = {
		gradient = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 255, 10)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 40, 0))
		},
		flatColor = Color3.fromRGB(255, 197, 0),
		LayoutOrder = 5,
	},
	["Mythical"] = {
		gradient = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 166, 166)),
			ColorSequenceKeypoint.new(0.65, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
		},
		flatColor = Color3.fromRGB(255, 37, 37),
		LayoutOrder = 6,
	},
	["Secret"] = {
		gradient = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(243, 255, 78)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(26, 255, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
		},
		flatColor = Color3.fromRGB(0, 200, 0),
		LayoutOrder = 7,
	},
	["Celestial"] = {
		gradient = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 243, 75)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(217, 0, 255))
		},
		flatColor = Color3.fromRGB(217, 0, 255),
		LayoutOrder = 8,
	},
	["Divine"] = {
		-- Rainbow gradient (animated on client) - now the highest tier
		gradient = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 128, 0)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(0.8, Color3.fromRGB(0, 128, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(75, 0, 130))
		},
		flatColor = Color3.fromRGB(255, 42, 42),
		isRainbow = true, -- Flag for client to animate
		LayoutOrder = 9,
	},
	["Admin"] = {
		-- Black/Gold gradient for admin-only items
		gradient = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0,255,162)),
			ColorSequenceKeypoint.new(0.1, Color3.fromRGB(0,255,162)),
			ColorSequenceKeypoint.new(.9, Color3.fromRGB(255, 17, 251)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 17, 251))
		},
		flatColor = Color3.fromRGB(255, 215, 0),
		LayoutOrder = 99,
	},
}

-- Modifiers (e.g. Normal, Golden, Galaxy) – brainrot variant labels and CashMultiplier
Shared_Rarity.ModifierData = {
	Normal = {
		DisplayName = "Normal",
		CashMultiplier = 1,
		Color = {
			ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(195, 195, 195))
			},
			90
		},
		LayoutOrder = 1,
	},
	Golden = {
		DisplayName = "Golden",
		CashMultiplier = 1.25,
		Color = {
			ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(252, 255, 86)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 145, 0))
			},
			90
		},
		LayoutOrder = 2,
	},
	Diamond = {
		DisplayName = "Diamond",
		CashMultiplier = 1.5,
		Color = {
			ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(99, 232, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(37, 128, 255))
			},
			90
		},
		LayoutOrder = 3,
	},
	Galaxy = {
		DisplayName = "Galaxy",
		CashMultiplier = 1.85,
		Color = {
			ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(230, 100, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 75, 190))
			},
			90
		},
		LayoutOrder = 4,
	},
	Lava = {
		DisplayName = "Lava",
		CashMultiplier = 2.35,
		Color = {
			ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 94, 46)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(188, 0, 0))
			},
			90
		},
		LayoutOrder = 5,
	},
	Rainbow = {
		DisplayName = "Rainbow",
		CashMultiplier = 3,
		Color = {
			ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
				ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 128, 0)),
				ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(0.6, Color3.fromRGB(0, 255, 0)),
				ColorSequenceKeypoint.new(0.8, Color3.fromRGB(0, 128, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(75, 0, 130)),
			},
			15
		},
		LayoutOrder = 6,
	},
	Arcade = {
		DisplayName = "Arcade",
		CashMultiplier = 3, -- Same as Rainbow
		Color = {
			ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 255, 255)),
				ColorSequenceKeypoint.new(0.2, Color3.fromRGB(0, 255, 145)),
				ColorSequenceKeypoint.new(.95, Color3.fromRGB(255, 53, 252)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(199, 17, 255))
			},	
			85
		},
		LayoutOrder = 7,
	},
}

-- Modifier drop chances (for spawning brainrot variants)
Shared_Rarity.ModifierChances = {
	Normal = 89,    -- 80 weight
	Golden = 8,    -- 15 weight
	Diamond = 3,    -- 4 weight
	Galaxy = 0.5,   -- 0.8 weight
	Lava = 0.05,    -- 0.15 weight
	Rainbow = 0.01, -- 1000 weight (for testing - will be proportional to total)
}

function Shared_Rarity:GetRarityInfo(rarityName)
	return self.List[rarityName]
end

function Shared_Rarity:GetRarityOrder(rarityName)
	return self.Order[rarityName] or 0
end

-- Returns { gradient, flatColor } or nil
function Shared_Rarity:GetRarityColors(rarityName)
	local info = self:GetRarityInfo(rarityName)
	if info then
		return {
			gradient = info.gradient,
			flatColor = info.flatColor,
		}
	end
	return nil
end

return Shared_Rarity
