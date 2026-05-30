--// ItemDataAccess - Functional data management for inventory items
--// Inspired by SingingX DataAccess pattern - no classes, just clean functions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local InventoryConfig = require(ReplicatedStorage.Modules.Settings.InventoryConfig)
local Shared_Tools = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Tools)

local ItemDataAccess = {}

--// CONFIG MODULE LOOKUP
local CONFIG_MODULES = {
	Tool = Shared_Tools,
	Brainrot = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots),
	LuckyBlock = require(ReplicatedStorage.Modules.ItemConfigs.Shared_LuckyBlocks),
}

--[[
	Gets the config module for an item type
	@param itemType string - The item type
	@return table? - Config module or nil
]]
local function getConfigModule(itemType: string)
	return CONFIG_MODULES[itemType]
end

--[[
	Gets the config data for a specific item
	@param itemType string - The item type
	@param configName string - The config name
	@return table? - Config data or nil
]]
function ItemDataAccess:GetItemConfig(itemType: string, configName: string)
	local configModule = getConfigModule(itemType)
	if not configModule then
		warn("ItemDataAccess: Invalid item type:", itemType)
		return nil
	end
	
	local config = configModule.List[configName]
	if not config then
		warn("ItemDataAccess: Item config not found:", itemType, configName)
		return nil
	end
	
	return config
end

--[[
	Creates clean inventory item data (what gets stored in profile)
	@param itemInfo table - {itemType, configName, metadata, existingUID?}
	@return table - Clean item data for storage
]]
function ItemDataAccess:CreateInventoryItem(itemInfo: {
	itemType: string,
	configName: string,
	metadata: {[string]: any}?,
	existingUID: string?
})
	if not itemInfo or not itemInfo.itemType or not itemInfo.configName then
		warn("ItemDataAccess:CreateInventoryItem - Missing required fields")
		return nil
	end
	
	-- Verify item config exists
	local config = self:GetItemConfig(itemInfo.itemType, itemInfo.configName)
	if not config then
		return nil
	end
	
	-- Generate or use existing UID
	local uid = itemInfo.existingUID or HttpService:GenerateGUID(false)
	
	-- Get type config
	local typeConfig = InventoryConfig.ItemTypeConfig[itemInfo.itemType]
	if not typeConfig then
		warn("ItemDataAccess: No type config for", itemInfo.itemType)
		return nil
	end
	
	-- Build minimal data structure
	local itemData = {
		Type = itemInfo.itemType,
		ConfigName = itemInfo.configName,
		Metadata = itemInfo.metadata or {},
	}
	
	-- Add type-specific fields
	if typeConfig.needsEquipped then
		itemData.Equipped = false
	end
	
	if typeConfig.needsStackCount then
		itemData.Metadata.StackCount = itemData.Metadata.StackCount or 1
	end
	
	-- Brainrot-specific fields (stored in Metadata for consistency)
	if typeConfig.needsModifier then
		itemData.Metadata.Modifier = itemData.Metadata.Modifier or "Normal"
	end
	
	if typeConfig.needsLevel then
		itemData.Metadata.Level = itemData.Metadata.Level or 1
	end
	
	return uid, itemData
end

--[[
	Gets a computed property from item data (uses config + instance data)
	@param itemData table - The item data from inventory
	@param property string - Property name (DisplayName, Rarity, Damage, etc.)
	@return any - Property value
]]
function ItemDataAccess:GetItemProperty(itemData: {[string]: any}, property: string): any
	if not itemData then return nil end
	
	-- First check if property is in metadata (instance-specific)
	if itemData.Metadata and itemData.Metadata[property] ~= nil then
		return itemData.Metadata[property]
	end
	
	-- Then check config (static data)
	local config = self:GetItemConfig(itemData.Type, itemData.ConfigName)
	if config and config[property] ~= nil then
		return config[property]
	end
	
	return nil
end

--[[
	Validates if an item can be equipped by a player
	@param player Player - The player
	@param itemData table - The item data
	@return boolean - Can equip
	@return string? - Reason if cannot equip
]]
function ItemDataAccess:CanEquip(player: Player, itemData: {[string]: any}): (boolean, string?)
	if not itemData then
		return false, "Invalid item data"
	end
	
	local config = self:GetItemConfig(itemData.Type, itemData.ConfigName)
	if not config then
		return false, "Item config not found"
	end
	
	-- Check if this item type can be equipped
	local typeConfig = InventoryConfig.ItemTypeConfig[itemData.Type]
	if not typeConfig or not typeConfig.needsEquipped then
		return false, "This item type cannot be equipped"
	end
	
	-- Check level requirement
	if config.RequiredLevel then
		local playerLevel = player:GetAttribute("Level") or 1
		if playerLevel < config.RequiredLevel then
			return false, "Level " .. config.RequiredLevel .. " required"
		end
	end
	
	return true
end

--[[
	Validates if an item can be sold
	@param itemData table - The item data
	@return boolean - Can sell
	@return number? - Sell price if can sell
]]
function ItemDataAccess:CanSell(itemData: {[string]: any}): (boolean, number?)
	if not itemData then
		return false, nil
	end
	
	local config = self:GetItemConfig(itemData.Type, itemData.ConfigName)
	if not config then
		return false, nil
	end
	
	local sellPrice = config.SellPrice or 0
	if sellPrice <= 0 then
		return false, nil
	end
	
	return true, sellPrice
end

--[[
	Checks if an item can stack with another
	@param itemData1 table - First item
	@param itemData2 table - Second item
	@return boolean - Can stack together
]]
function ItemDataAccess:CanStack(itemData1: {[string]: any}, itemData2: {[string]: any}): boolean
	if not itemData1 or not itemData2 then
		return false
	end
	
	-- Must be same type and config
	if itemData1.Type ~= itemData2.Type or itemData1.ConfigName ~= itemData2.ConfigName then
		return false
	end
	
	-- Check if type supports stacking
	local typeConfig = InventoryConfig.ItemTypeConfig[itemData1.Type]
	if not typeConfig or not typeConfig.canStack then
		return false
	end
	
	return true
end

--[[
	Adds to a consumable stack
	@param itemData table - The item data
	@param amount number - Amount to add
	@return number - Amount successfully added
]]
function ItemDataAccess:AddToStack(itemData: {[string]: any}, amount: number): number
	if not itemData or not itemData.Metadata then
		return 0
	end
	
	local config = self:GetItemConfig(itemData.Type, itemData.ConfigName)
	if not config then
		return 0
	end
	
	local currentStack = itemData.Metadata.StackCount or 0
	local maxStack = config.MaxStackCount or InventoryConfig.Rules.MaxStackSize
	local maxAdd = maxStack - currentStack
	local actualAdd = math.min(amount, maxAdd)
	
	itemData.Metadata.StackCount = currentStack + actualAdd
	
	return actualAdd
end

--[[
	Consumes one item from a stack
	@param itemData table - The item data
	@return boolean - Has items remaining
]]
function ItemDataAccess:ConsumeFromStack(itemData: {[string]: any}): boolean
	if not itemData or not itemData.Metadata then
		return false
	end
	
	local stackCount = itemData.Metadata.StackCount or 0
	if stackCount <= 0 then
		return false
	end
	
	itemData.Metadata.StackCount = stackCount - 1
	return itemData.Metadata.StackCount > 0
end

return ItemDataAccess
