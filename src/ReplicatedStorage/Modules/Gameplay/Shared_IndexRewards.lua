--[[
	Shared_IndexRewards - Plot skins shown in Index UI.
	Keys are arbitrary (you name them); they map to assets Floor0_<Key>, AdditionalFloor_<Key> in Assets.PlotSkins.
	UnlockType controls how the plot skin is unlocked; only "Index" entries are granted from collection count.
]]

local Shared_IndexRewards = {}

-- Display order for plot skins: used by FloorHolder (View All grid). Includes Index, Gamepass, and (in future) Event-based skins. Tabs are created only for UnlockType "Index" entries.
Shared_IndexRewards.RewardOrder = { "Normal", "Golden", "Diamond", "Galaxy", "Lava", "Rainbow", "Premium", "Arcade" }

--[[
	[Key] = config. Key = plot skin id (EquippedIndexFloor). Asset names in PlotSkins use SkinKey when set.
	SkinKey (optional): name used for Assets.PlotSkins (Floor0_<SkinKey>, AdditionalFloor_<SkinKey>). If nil, Key is used.
	UnlockType: "Index" (RequiredCount), "Gamepass" (PassName), etc.
	Common: RewardName (display), Image (rbxassetid).
	CashMultiplier (optional): additive cash bonus when equipped (e.g. 0.5 = +50% → x0.5 display, 1 = +100% → x1). Default 0.
	Optional: UnlockDescription = "Custom text when locked".
]]
Shared_IndexRewards.Rewards = {
	-- Index-based (collection). Normal uses asset name "Vanilla" (Floor0_Vanilla, AdditionalFloor_Vanilla).
	Normal = { UnlockType = "Index", RequiredCount = 40, RewardName = "Normal Plot", Image = "rbxassetid://96954863455460", CashMultiplier = 0.5, SkinKey = "Vanilla" },
	Golden = { UnlockType = "Index", RequiredCount = 25, RewardName = "Golden Plot", Image = "rbxassetid://130971480900231", CashMultiplier = 1 },
	Diamond = { UnlockType = "Index", RequiredCount = 25, RewardName = "Diamond Plot", Image = "rbxassetid://95498640750684", CashMultiplier = 1 },
	Galaxy = { UnlockType = "Index", RequiredCount = 25, RewardName = "Galaxy Plot", Image = "rbxassetid://122582977412383", CashMultiplier = 2 },
	Lava = { UnlockType = "Index", RequiredCount = 20, RewardName = "Lava Plot", Image = "rbxassetid://84592812249849", CashMultiplier = 2 },
	Rainbow = { UnlockType = "Index", RequiredCount = 15, RewardName = "Rainbow Plot", Image = "rbxassetid://92889294079976", CashMultiplier = 3 },
	-- Non-index: gamepass (name and logic are independent)
	Premium = { UnlockType = "Gamepass", PassName = "PremiumFloor", RewardName = "Premium Plot", Image = "rbxassetid://92866851454914", UnlockDescription = "Purchased in store as a pass", CashMultiplier = 3 },
	-- Special Rewards: Event-based or special unlocks (not Index or Gamepass)
	Arcade = { UnlockType = "SpecialReward", RewardName = "Arcade Plot", Image = "rbxassetid://117648268278246", UnlockDescription = "Unlocked from Arcade Machine", CashMultiplier = 3 },
}

function Shared_IndexRewards:GetRewardConfig(modifier)
	return self.Rewards[modifier]
end

-- True if this plot skin is unlocked by index collection count (RequiredCount).
function Shared_IndexRewards:IsIndexUnlock(config)
	return config and (config.UnlockType == "Index" or (config.UnlockType == nil and config.RequiredCount ~= nil))
end

-- True if this plot skin is unlocked by owning a gamepass (PassName).
function Shared_IndexRewards:IsGamepassUnlock(config)
	return config and (config.UnlockType == "Gamepass" or (config.UnlockType == nil and config.PassName ~= nil))
end

-- True if this plot skin is unlocked via special reward (events, achievements, etc).
function Shared_IndexRewards:IsSpecialRewardUnlock(config)
	return config and config.UnlockType == "SpecialReward"
end

-- Resolve EquippedIndexFloor to the asset key used in PlotSkins (Floor0_<key>, AdditionalFloor_<key>).
-- "Default" (no plot skin equipped) -> "Default" (baseline assets). "Normal" -> "Vanilla" (SkinKey). Others use Key or SkinKey.
function Shared_IndexRewards:GetSkinKey(floorKey)
	if not floorKey or floorKey == "Default" then return "Default" end
	local config = self.Rewards[floorKey]
	return (config and config.SkinKey) or floorKey
end

-- Cash multiplier when this plot skin is equipped (additive: 1 + value applied to cash). 0 = no bonus.
function Shared_IndexRewards:GetCashMultiplier(floorKey): number
	if not floorKey or floorKey == "Default" then return 0 end
	local config = self.Rewards[floorKey]
	return (config and config.CashMultiplier) or 0
end

return Shared_IndexRewards
