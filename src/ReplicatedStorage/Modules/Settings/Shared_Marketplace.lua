local Shared_Marketplace = {}

-- Placeholder IDs use 0 so copied UI can boot before this game's real
-- products and gamepasses are configured.
Shared_Marketplace.Products = {
	Cash1 = 0,
	Cash2 = 0,
	Cash3 = 0,
	LuckyBlock1 = 0,
	LuckyBlock1_3x = 0,
	LuckyBlock2 = 0,
	LuckyBlock2_3x = 0,
	LuckyBlock3 = 0,
	LuckyBlock3_3x = 0,
	OfflineBoost10x = 0,
	StarterPack = 0,
	["Starter Pack"] = 0,
	["Skip Rebirth"] = 0,
	ForceGreenLight = 0,
	["Teleport Home"] = 0,
	VIP_Gift = 0,
	CashBoost_Gift = 0,
	SpeedBoost_Gift = 0,
	Sniper_Gift = 0,
	Tablet_Gift = 0,
	QuickCollect_Gift = 0,
}

Shared_Marketplace.Passes = {
	VIP = 0,
	CashBoost = 0,
	SpeedBoost = 0,
	Sniper = 0,
	Tablet = 0,
	QuickCollect = 0,
	PremiumFloor = 0,
}

Shared_Marketplace.CashAmounts = {
	Cash1 = 1000,
	Cash2 = 10000,
	Cash3 = 100000,
}

Shared_Marketplace.RarityToStealProduct = {}
Shared_Marketplace.RarityToUpgradeProduct = {}
Shared_Marketplace.GiftProductByPassName = {}
Shared_Marketplace.StarterPackRewards = {}

Shared_Marketplace.STARTER_PACK_DURATION_SEC = 7200

return Shared_Marketplace
