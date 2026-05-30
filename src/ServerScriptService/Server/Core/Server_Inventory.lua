--// Server_Inventory - Complete server-side inventory system
--// Handles both core logic and RemoteEvent actions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local InventoryConfig = require(ReplicatedStorage.Modules.Settings.InventoryConfig)
local ItemDataAccess = require(ReplicatedStorage.Modules.Gameplay.ItemDataAccess)
local Shared_ModifierHandler = require(ReplicatedStorage.Modules.Gameplay.Shared_ModifierHandler)

local Server_Data -- Loaded in Init()

local Module = {}

-- Anti-dupe tracking for consumable items
Module.ConsumingItems = {} -- [uid] = true

--[[
	PROFESSIONAL HIGH-LEVEL INVENTORY OPERATIONS
	Use these instead of direct Server_Data calls for safety and consistency
]]

--[[
	Remove an item from inventory safely
	Handles: unequip, attribute clearing, replica update
	@param player Player
	@param uid string - Item UID
	@return boolean, string? - Success, error message
]]
function Module:RemoveItem(player: Player, uid: string): (boolean, string?)
	local profile = Server_Data:GetProfile(player)
	if not profile then return false, "No profile" end
	
	local itemData = profile.Data.Inventory[uid]
	if not itemData then return false, "Item not found" end
	
	-- Unequip if currently equipped
	if player:GetAttribute("CurrentEquipped") == uid then
		self:UnequipItem(player, uid)
	end
	
	-- Clear placement attribute
	if player:GetAttribute("SlotPlacablePicked") == uid then
		player:SetAttribute("SlotPlacablePicked", nil)
	end
	
	-- Remove using proper table operation (replica sync)
	local success = Server_Data:RemoveFromTable(player, "Inventory", uid)
	if not success then
		return false, "Failed to remove from data"
	end
	
	return true
end

--[[
	Remove item and return its data (for transfers like placement, trading)
	@param player Player
	@param uid string
	@return boolean, table? - Success, item data or error
]]
function Module:RemoveItemWithReturn(player: Player, uid: string): (boolean, table?)
	local profile = Server_Data:GetProfile(player)
	if not profile then return false, "No profile" end
	
	local itemData = table.clone(profile.Data.Inventory[uid])
	if not itemData then return false, "Item not found" end
	
	local success, err = self:RemoveItem(player, uid)
	if not success then return false, err end
	
	return true, itemData
end

--[[
	Add an item to inventory safely
	@param player Player
	@param itemType string - "Brainrot", "LuckyBlock", "Tool"
	@param configName string - Config key
	@param metadata table? - Item metadata
	@return boolean, string? - Success, UID or error
]]
function Module:AddItem(player: Player, itemType: string, configName: string, metadata: table?): (boolean, string?)
	local profile = Server_Data:GetProfile(player)
	if not profile then return false, "No profile" end
	
	-- Validate item exists in config
	local itemConfig = ItemDataAccess:GetItemConfig(itemType, configName)
	if not itemConfig then return false, "Invalid item config" end
	
	-- Create item data structure (returns uid, itemData)
	local uid, itemData = ItemDataAccess:CreateInventoryItem({
		itemType = itemType,
		configName = configName,
		metadata = metadata or {},
	})
	
	if not uid or not itemData then return false, "Failed to create item data" end
	
	-- Ensure UID is unique (regenerate if collision)
	while profile.Data.Inventory[uid] do
		uid = HttpService:GenerateGUID(false)
	end
	
	-- Add using proper table operation (replica sync)
	local success = Server_Data:AddToTable(player, "Inventory", uid, itemData)
	if not success then
		return false, "Failed to add to data"
	end
	
	return true, uid
end

--[[
	Consume an item (for openables, consumables)
	Transaction-safe with anti-dupe lock
	@param player Player
	@param uid string - Item UID
	@param callback function - Callback to execute (return success, result)
	@return boolean, any - Success, callback result
]]
function Module:ConsumeItem(player: Player, uid: string, callback: (player: Player, itemData: table) -> (boolean, any)): (boolean, any)
	-- Anti-dupe lock
	if self.ConsumingItems[uid] then
		return false, "Item already being consumed"
	end
	self.ConsumingItems[uid] = true
	
	local profile = Server_Data:GetProfile(player)
	if not profile then
		self.ConsumingItems[uid] = nil
		return false, "No profile"
	end
	
	local itemData = profile.Data.Inventory[uid]
	if not itemData then
		self.ConsumingItems[uid] = nil
		return false, "Item not found"
	end
	
	-- Execute callback (e.g., roll lucky block reward)
	local success, result = callback(player, itemData)
	if not success then
		self.ConsumingItems[uid] = nil
		return false, result or "Callback failed"
	end
	
	-- Remove item after successful callback
	local removeSuccess, removeError = self:RemoveItem(player, uid)
	self.ConsumingItems[uid] = nil
	
	if not removeSuccess then
		warn("⚠️ ConsumeItem: Callback succeeded but removal failed:", removeError)
		return false, "Failed to remove item after consumption"
	end
	
	return true, result
end

--[[
	Converts a model/folder to a Roblox Accessory for character attachment
	EXACTLY matches SingingX implementation for guaranteed compatibility
	@param modelOrFolder Model|Folder - The tool/brainrot model to convert
	@param itemType string - Item type for grip positioning ("Brainrot", "Tool", etc)
	@return Accessory - The converted accessory
]]
local function ModelToAccessory(modelOrFolder, itemType: string): Accessory
	local clone = modelOrFolder
	
	-- Set PrimaryPart if not already set
	if not clone.PrimaryPart then
		clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart")
		if not clone.PrimaryPart then 
			warn("ModelToAccessory: No BasePart found")
			return nil 
		end
	end
	
	-- Set up grip attachment based on item type (ONLY if doesn't exist)
	if not clone.PrimaryPart:FindFirstChild("RightGripAttachment") then
		local grip = Instance.new("Attachment")
		grip.Name = "RightGripAttachment"
		
		-- Brainrots: held in front of character (two-handed position)
		if itemType == "Brainrot" then
			grip.CFrame = CFrame.new(1.2, 0.1, 0) * CFrame.Angles(math.rad(90), math.rad(10), 0)
		end
		-- Tools: use default grip (CFrame.new(0,0,0)) - implicit, no need to set
		
		grip.Parent = clone.PrimaryPart
	end
	
	-- Weld all parts to PrimaryPart and set properties
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") and part ~= clone.PrimaryPart then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = clone.PrimaryPart
			weld.Part1 = part
			weld.Parent = clone.PrimaryPart
			part.Anchored = false
			part.CanCollide = false
		end
	end
	
	-- Set PrimaryPart properties
	clone.PrimaryPart.Anchored = false
	clone.PrimaryPart.CanCollide = false
	
	-- Create accessory
	local accessory = Instance.new("Accessory")
	accessory.Name = "CurrentEquippedAccessory"
	
	-- CRITICAL: Rename to Handle BEFORE parenting (SingingX order)
	clone.PrimaryPart.Name = "Handle"
	clone.PrimaryPart.Parent = accessory
	
	-- Move all other children to accessory
	for _, obj in pairs(clone:GetChildren()) do
		if obj ~= clone.PrimaryPart then
			obj.Parent = accessory
		end
	end
	
	return accessory
end

--[[
	Create billboard for equipped brainrot (with income display)
	@param model Model - The brainrot model
	@param configName string
	@param modifier string
	@param level number
	@return BillboardGui?
]]
local function createEquippedBrainrotBillboard(model: Model, configName: string, modifier: string, level: number)
	local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
	local Shared_Rarity = require(ReplicatedStorage.Modules.Gameplay.Shared_Rarity)
	local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
	
	local config = Shared_Brainrots.List[configName]
	if not config then return nil end
	
	-- Get billboard template
	local billboardTemplate = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("BrainrotBillboard")
	
	if not billboardTemplate then
		warn("⚠️ Billboard template not found for equipped brainrot")
		return nil
	end
	
	-- Create attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "attach"
	attachment.Position = Vector3.new(0, model.PrimaryPart.Size.Y * 0.5, 0)
	attachment.Parent = model.PrimaryPart
	
	-- Clone template
	local billboard = billboardTemplate:Clone()
	billboard.Parent = attachment
	
	-- Check for NametagHeight attribute
	local nametagHeight = model:GetAttribute("NametagHeight")
	if not nametagHeight then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local brainrots = assets and assets:FindFirstChild("Brainrots")
		local brainrotParent = brainrots and brainrots:FindFirstChild(configName)
		if brainrotParent then
			local normalModel = brainrotParent:FindFirstChild("Normal")
			if normalModel then
				nametagHeight = normalModel:GetAttribute("NametagHeight")
			end
		end
	end
	
	if nametagHeight then
		billboard.StudsOffset = billboard.StudsOffset + nametagHeight
	end
	
	-- Update DisplayName with level
	local displayName = billboard:FindFirstChild("DisplayName", true)
	if displayName and displayName:IsA("TextLabel") then
		displayName.Text = string.format("%s (Lv %d)", config.DisplayName, level or 1)
	end
	
	-- Update Rarity
	local rarityLabel = billboard:FindFirstChild("Rarity", true)
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		local rarityInfo = Shared_Rarity:GetRarityInfo(config.Rarity)
		if rarityInfo then
			rarityLabel.Text = config.Rarity
			local gradient = rarityLabel:FindFirstChildOfClass("UIGradient")
			if not gradient then
				gradient = Instance.new("UIGradient")
				gradient.Parent = rarityLabel
			end
			
			if gradient and rarityInfo.gradient then
				gradient.Color = rarityInfo.gradient
				gradient.Rotation = (rarityInfo.isRainbow and 0) or 90
			end
		end
	end
	
	-- Update modifier label
	local specialLabel = billboard:FindFirstChild("Modifier", true)
	if specialLabel and specialLabel:IsA("TextLabel") then
		if modifier ~= "Normal" then
			specialLabel.Visible = true
			local specialData = Shared_Rarity.ModifierData[modifier]
			if specialData then
				specialLabel.Text = specialData.DisplayName
				local gradient = specialLabel:FindFirstChildOfClass("UIGradient")
				if gradient and specialData.Color then
					gradient.Color = specialData.Color[1]
					gradient.Rotation = specialData.Color[2]
				end
			end
		else
			specialLabel.Visible = false
		end
	end
	
	-- Show Cash/s (income per second)
	local cashLabel = billboard:FindFirstChild("Cash", true)
	if cashLabel and cashLabel:IsA("TextLabel") then
		local cashPerSec = Shared_Brainrots:GetCashPerSecond(configName, level or 1, modifier)
		cashLabel.Text = "$" .. Shared_Shorten:Number(cashPerSec) .. "/s"
		cashLabel.Visible = true
	end
	
	-- Hide Price and Timer (not relevant for equipped items)
	local priceLabel = billboard:FindFirstChild("Price", true)
	if priceLabel then
		priceLabel.Visible = false
	end
	
	local timerFrame = billboard:FindFirstChild("Timer", true)
	if timerFrame then
		timerFrame.Visible = false
	end
	
	return billboard
end

--[[
	Attaches a brainrot model to the character's torso (welded in front, 1-2 studs offset)
	@param model Model - The brainrot model
	@param character Model - The character
	@return boolean - Success
]]
local function AttachBrainrotToTorso(model: Model, character: Model): boolean
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")
		if not model.PrimaryPart then return false end
	end
	
	local attachPart = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character.PrimaryPart
	if not attachPart then return false end
	
	-- Prepare model
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
		end
	end
	
	-- Weld other parts to primary
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= model.PrimaryPart then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = model.PrimaryPart
			weld.Part1 = part
			weld.Parent = model.PrimaryPart
		end
	end
	
	-- Offset 1.5 studs in front of torso (negative Z = forward)
	local forwardOffset = 0.75
	local offset = CFrame.new(0, model.PrimaryPart.Size.Y * 0.3, -model.PrimaryPart.Size.Z/2 - forwardOffset)
	model:SetPrimaryPartCFrame(attachPart.CFrame * offset)
	
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachPart
	weld.Part1 = model.PrimaryPart
	weld.Parent = model.PrimaryPart
	
	model.Name = "CurrentEquippedBrainrot"
	model.Parent = character
	
	return true
end

--[[
	Attaches lucky block to torso (better positioning than brainrots)
]]
local function AttachLuckyBlockToTorso(model: Model, character: Model): boolean
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")
		if not model.PrimaryPart then return false end
	end
	
	local attachPart = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character.PrimaryPart
	if not attachPart then return false end
	
	-- Prepare model
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
		end
	end
	
	-- Weld other parts to primary
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= model.PrimaryPart then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = model.PrimaryPart
			weld.Part1 = part
			weld.Parent = model.PrimaryPart
		end
	end
	
	-- Lucky blocks: positioned lower and further forward for better visibility
	local forwardOffset = 1.5  -- Further out than brainrots
	local heightOffset = 1  -- Lower (waist level)
	local offset = CFrame.new(0, heightOffset, -model.PrimaryPart.Size.Z/2 - forwardOffset)
	model:SetPrimaryPartCFrame(attachPart.CFrame * offset)
	
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachPart
	weld.Part1 = model.PrimaryPart
	weld.Parent = model.PrimaryPart
	
	model.Name = "CurrentEquippedLuckyBlock"
	model.Parent = character
	
	return true
end

--[[
	Initializes default inventory items for a new player
	@param player Player
]]
function Module:InitializeDefaultInventory(player: Player)
	local profile = Server_Data:GetProfile(player)
	if not profile then
		warn("Server_Inventory: Cannot initialize inventory - profile not found")
		return
	end
	
	-- Add default items from config
	for _, defaultItem in ipairs(InventoryConfig.DefaultItems) do
		self:AddItem(player, defaultItem.Type, defaultItem.ConfigName, defaultItem.Metadata)
	end
end

--[[
	Gets an item from player's inventory
	@param player Player
	@param uid string - Item UID
	@return table? - Item data or nil
]]
function Module:GetItem(player: Player, uid: string): {[string]: any}?
	local profile = Server_Data:GetProfile(player)
	if not profile then
		return nil
	end
	
	return profile.Data.Inventory[uid]
end

--[[
	Gets all items in player's inventory
	@param player Player
	@return table - Inventory dictionary
]]
function Module:GetInventory(player: Player): {[string]: any}
	local profile = Server_Data:GetProfile(player)
	if not profile then
		return {}
	end
	
	return profile.Data.Inventory or {}
end

--[[
	Checks if player has space for more items
	@param player Player
	@param count number - Number of items to add
	@return boolean - Has space
]]
function Module:HasSpace(player: Player, count: number): boolean
	local inventory = self:GetInventory(player)
	
	local currentCount = 0
	for _ in pairs(inventory) do
		currentCount = currentCount + 1
	end
	
	return (currentCount + count) <= InventoryConfig.MaxInventorySize
end

--[[
	Equips an item and spawns it on the character
	@param player Player
	@param uid string - Item UID
	@return boolean - Success
	@return string? - Error message if failed
]]
function Module:EquipItem(player: Player, uid: string): (boolean, string?)
	local itemData = self:GetItem(player, uid)
	if not itemData then
		return false, "Item not found"
	end
	
	-- Validate can equip
	local canEquip, reason = ItemDataAccess:CanEquip(player, itemData)
	if not canEquip then
		return false, reason
	end
	
	-- Check if player is holding brainrot (prevents equipment)
	if player:GetAttribute("IsHoldingBrainrot") then
		return false, "Cannot equip while carrying brainrots"
	end
	
	-- Get character
	local character = player.Character
	if not character then
		return false, "Character not found"
	end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "Humanoid not found"
	end
	
	-- Unequip current item of same type first
	local currentEquipped = player:GetAttribute("CurrentEquipped")
	if currentEquipped then
		self:UnequipItem(player, currentEquipped)
	end
	
	player:SetAttribute("CurrentEquipped", uid)
	player:SetAttribute("EquippedItem_" .. itemData.Type, uid)
	if itemData.Type == "Brainrot" or itemData.Type == "LuckyBlock" then
		player:SetAttribute("SlotPlacablePicked", uid)
	else
		player:SetAttribute("SlotPlacablePicked", nil)
	end
	
	-- Get model: Items → Assets.Items, Brainrots → Assets.Brainrots, LuckyBlocks → Assets.LuckyBlocks
	local model
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		warn("⚠️ ReplicatedStorage.Assets not found")
		return false, "Assets not found"
	end
	
	if itemData.Type == "Tool" then
		local itemsFolder = assets:FindFirstChild("Items")
		if itemsFolder then
			model = itemsFolder:FindFirstChild(itemData.ConfigName)
		end
	elseif itemData.Type == "Brainrot" then
		local modifier = (itemData.Metadata and itemData.Metadata.Modifier) or "Normal"
		model = Shared_ModifierHandler:GetBrainrotModel(itemData.ConfigName, modifier)
	elseif itemData.Type == "LuckyBlock" then
		local luckyBlocksFolder = assets:FindFirstChild("LuckyBlocks")
		if luckyBlocksFolder then
			local Shared_LuckyBlocks = require(ReplicatedStorage.Modules.ItemConfigs.Shared_LuckyBlocks)
			local modelName = Shared_LuckyBlocks:GetModelAssetName(itemData.ConfigName)
			model = luckyBlocksFolder:FindFirstChild(modelName)
		end
	end
	
	if not model then
		warn("⚠️ No model found for:", itemData.Type, itemData.ConfigName)
		return false, "Model not found"
	end
	
	-- Brainrot model from ModifierHandler is already a clone; others need cloning
	if itemData.Type ~= "Brainrot" then
		model = model:Clone()
	end
	
	-- Clone and prepare model (pcall to catch errors)
	local ok, err = pcall(function()
		if itemData.Type == "Brainrot" then
			-- Brainrots: weld to torso
			local attached = AttachBrainrotToTorso(model, character)
			if not attached then
				warn("⚠️ Failed to attach brainrot to torso")
			else
				-- Create billboard with income display
				local level = (itemData.Metadata and itemData.Metadata.Level) or 1
				local modifier = (itemData.Metadata and itemData.Metadata.Modifier) or "Normal"
				createEquippedBrainrotBillboard(model, itemData.ConfigName, modifier, level)
			end
		elseif itemData.Type == "LuckyBlock" then
			-- Lucky blocks: weld to torso with better positioning
			local attached = AttachLuckyBlockToTorso(model, character)
			if not attached then
				warn("⚠️ Failed to attach lucky block to torso")
			end
		else
			-- Tools: use Accessory system (hand attachment)
			local accessory = ModelToAccessory(model, itemData.Type)
			if not accessory then
				warn("⚠️ Failed to convert model to accessory")
				return
			end
			humanoid:AddAccessory(accessory)
		end
	end)
	
	if not ok then
		warn("⚠️ Failed to attach accessory:", err)
		return false, tostring(err)
	end
	
	return true
end

--[[
	Unequips an item and destroys its accessory
	@param player Player
	@param uid string - Item UID
	@return boolean - Success
]]
function Module:UnequipItem(player: Player, uid: string): boolean
	local itemData = self:GetItem(player, uid)
	if not itemData then
		return false
	end
	
	player:SetAttribute("CurrentEquipped", nil)
	player:SetAttribute("EquippedItem_" .. itemData.Type, nil)
	if player:GetAttribute("SlotPlacablePicked") == uid then
		player:SetAttribute("SlotPlacablePicked", nil)
	end
	
	-- Remove accessory (tools) or welded model (brainrots/lucky blocks) from character
	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child.Name == "CurrentEquippedAccessory" and child:IsA("Accessory") then
				child:Destroy()
			elseif child.Name == "CurrentEquippedBrainrot" and child:IsA("Model") then
				child:Destroy()
			elseif child.Name == "CurrentEquippedLuckyBlock" and child:IsA("Model") then
				child:Destroy()
			end
		end
	end
	
	return true
end

--[[
	Gets the currently equipped item of a type
	@param player Player
	@param itemType string - Item type
	@return string? - UID of equipped item or nil
]]
function Module:GetEquippedItem(player: Player, itemType: string): string?
	return player:GetAttribute("EquippedItem_" .. itemType)
end

--[[
	Updates hotbar slot
	@param player Player
	@param slotIndex number - Slot index (1-6)
	@param uid string? - Item UID or nil to clear
	
	NOTE: DEPRECATED - Hotbar slots are now handled client-side only
]]
--[[
function Module:SetHotbarSlot(player: Player, slotIndex: number, uid: string?)
	if slotIndex < 1 or slotIndex > InventoryConfig.HotbarSlots then
		return
	end
	
	-- Validate item exists if uid provided
	if uid and not self:GetItem(player, uid) then
		return
	end
	
	-- Update hotbar
	Server_Data:SetValue(player, "HotbarSlots." .. slotIndex, uid)
end
--]]

--[[
	Sells an item for currency
	@param player Player
	@param uid string - Item UID
	@return boolean - Success
]]
function Module:SellItem(player: Player, uid: string): boolean
	local itemData = self:GetItem(player, uid)
	if not itemData then
		return false
	end
	
	-- Check if can sell
	local canSell, sellPrice = ItemDataAccess:CanSell(itemData)
	if not canSell then
		return false
	end
	
	-- Handle consumable stacks
	local typeConfig = InventoryConfig.ItemTypeConfig[itemData.Type]
	if typeConfig and typeConfig.canStack then
		local stackCount = itemData.Metadata.StackCount or 1
		sellPrice = sellPrice * stackCount
	end
	
	-- Remove item
	local removed = self:RemoveItem(player, uid)
	if not removed then
		return false
	end
	
	-- Award currency
	Server_Data:AddValue(player, "Cash", sellPrice)
	
	return true
end

--[[
	Drops an item from inventory
	@param player Player
	@param uid string - Item UID
	@return boolean - Success
]]
function Module:DropItem(player: Player, uid: string): boolean
	local itemData = self:GetItem(player, uid)
	if not itemData then
		return false
	end
	
	-- Handle consumable stacks (drop one at a time)
	local typeConfig = InventoryConfig.ItemTypeConfig[itemData.Type]
	if typeConfig and typeConfig.canStack then
		local hasRemaining = ItemDataAccess:ConsumeFromStack(itemData)
		
		if hasRemaining then
			-- Update replica with new stack count
			Server_Data:SetValue(player, "Inventory." .. uid, itemData)
		else
			-- Stack is empty, remove item
			self:RemoveItem(player, uid)
		end
	else
		-- Non-stackable item, remove completely
		self:RemoveItem(player, uid)
	end
	
	return true
end

--[[
	Uses a consumable item
	@param player Player
	@param uid string - Item UID
	@return boolean - Success
]]
function Module:UseConsumable(player: Player, uid: string): boolean
	local itemData = self:GetItem(player, uid)
	if not itemData or itemData.Type ~= "Consumable" then
		return false
	end
	
	-- Get config for effect
	local config = ItemDataAccess:GetItemConfig(itemData.Type, itemData.ConfigName)
	if not config then
		return false
	end
	
	-- Apply effect based on type
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	
	if humanoid then
		if config.EffectType == "Heal" then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + config.EffectValue)
		elseif config.EffectType == "SpeedBuff" then
			-- Use attribute system instead of direct WalkSpeed modification
			local currentBuff = player:GetAttribute("SpeedBuffMultiplier") or 1
			player:SetAttribute("SpeedBuffMultiplier", currentBuff * (1 + config.EffectValue))
			
			task.delay(config.EffectDuration or 30, function()
				local buff = player:GetAttribute("SpeedBuffMultiplier") or 1
				player:SetAttribute("SpeedBuffMultiplier", buff / (1 + config.EffectValue))
			end)
		elseif config.EffectType == "StrengthBuff" then
			player:SetAttribute("StrengthMultiplier", (player:GetAttribute("StrengthMultiplier") or 1) + config.EffectValue)
			task.delay(config.EffectDuration or 60, function()
				player:SetAttribute("StrengthMultiplier", (player:GetAttribute("StrengthMultiplier") or 1) - config.EffectValue)
			end)
		end
	end
	
	-- Consume from stack
	local hasRemaining = ItemDataAccess:ConsumeFromStack(itemData)
	
	if hasRemaining then
		-- Update replica
		Server_Data:SetValue(player, "Inventory." .. uid, itemData)
	else
		-- Stack depleted, remove item
		self:RemoveItem(player, uid)
	end
	
	return true
end

--// REMOTE EVENT HANDLERS

--[[
	Initializes the inventory system (called from init.server.lua)
]]
function Module:Init()
	-- Load Server_Data
	Server_Data = require(script.Parent.Server_Data)
	
	-- Get Events folder
	local Events = ReplicatedStorage:WaitForChild("Events")
	
	-- Connect RemoteEvent (action-based routing)
	local InventoryHandlerEvent = Events:WaitForChild("InventoryHandler")
	
	InventoryHandlerEvent.OnServerEvent:Connect(function(player: Player, action: string, uid: string)
		if not player or not action then
			return warn("⚠️ Invalid InventoryHandler parameters")
		end
		
		if type(uid) ~= "string" or uid == "" then
			return warn("⚠️ Invalid item UID")
		end
		
		if action == "Equip" then
			Module:EquipItem(player, uid)
		elseif action == "Unequip" then
			Module:UnequipItem(player, uid)
		elseif action == "Sell" then
			Module:SellItem(player, uid)
		elseif action == "Drop" then
			Module:DropItem(player, uid)
		else
			warn("⚠️ Unknown InventoryHandler action: " .. tostring(action))
		end
	end)
	
	-- Unequip items on character respawn
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			-- Clear equipped item on respawn
			local currentEquipped = player:GetAttribute("CurrentEquipped")
			if currentEquipped then
				player:SetAttribute("CurrentEquipped", nil)
			end
		end)
	end)
	
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(character)
			local currentEquipped = player:GetAttribute("CurrentEquipped")
			if currentEquipped then
				player:SetAttribute("CurrentEquipped", nil)
			end
		end)
	end
end

return Module
