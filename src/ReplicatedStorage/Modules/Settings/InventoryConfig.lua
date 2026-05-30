local InventoryConfig = {}

InventoryConfig.HotbarSlots = 6
InventoryConfig.MaxInventorySize = 150

InventoryConfig.SlapperSlot = 1
InventoryConfig.TabletSlot = 2
InventoryConfig.SniperSlot = 3

InventoryConfig.TabletConfigName = "Tablet"
InventoryConfig.SniperConfigName = "Sniper"

InventoryConfig.ItemTypeConfig = {
	Brainrot = {
		canStack = false,
		canSell = true,
		canDrop = true,
		needsEquipped = true,
	},
	LuckyBlock = {
		canStack = true,
		canSell = false,
		canDrop = true,
		needsEquipped = true,
	},
	Tool = {
		canStack = false,
		canSell = false,
		canDrop = false,
		needsEquipped = true,
	},
	Consumable = {
		canStack = true,
		canSell = false,
		canDrop = true,
	},
}

return InventoryConfig
