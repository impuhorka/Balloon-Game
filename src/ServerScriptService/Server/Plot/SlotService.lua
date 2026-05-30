--// SlotService - Professional brainrot slot management
--// Handles placement, pickup, validation - fully server-authoritative

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)

local SlotService = {}

-- Dependencies (injected at Init)
local DataService
local InventoryService
local BrainrotVisuals

-- Anti-dupe locks (per UID, not per player - allows placing different items simultaneously)
local ItemProcessingPlace = {}
local ItemProcessingPickup = {}

--[[
	Initialize with dependencies (Dependency Injection pattern)
	@param dependencies table - {DataService, InventoryService, BrainrotVisuals}
]]
function SlotService:Init(dependencies)
	DataService = dependencies.DataService
	InventoryService = dependencies.InventoryService
	BrainrotVisuals = dependencies.BrainrotVisuals
end

--[[
	Place a brainrot from inventory onto a slot
	@param player Player
	@param plotData table - Plot data from PlotService
	@param slotID number
	@param brainrotUID string - Inventory UID
	@return boolean - Success
]]
function SlotService:PlaceBrainrot(player: Player, plotData: table, slotID: number, brainrotUID: string): boolean
	-- Anti-dupe lock (per UID - allow placing different items at same time)
	if ItemProcessingPlace[brainrotUID] then 
		return false 
	end
	ItemProcessingPlace[brainrotUID] = true
	
	if not plotData.Slots or not plotData.Slots[slotID] or not plotData.Slots[slotID].Model then
		ItemProcessingPlace[brainrotUID] = nil
		warn("⚠️ Invalid slot " .. tostring(slotID) .. " for " .. player.Name)
		return false
	end
	
	-- Get player profile
	local profile = DataService:GetProfile(player)
	if not profile then
		ItemProcessingPlace[brainrotUID] = nil
		warn("⚠️ No profile for " .. player.Name)
		return false
	end
	
	-- Validate slot is empty (check both in-memory AND saved data)
	local slotOccupiedInMemory = plotData.Slots[slotID] and plotData.Slots[slotID].Data
	local slotOccupiedInData = profile.Data.PlotSlots[tostring(slotID)] ~= nil
	
	if slotOccupiedInMemory or slotOccupiedInData then
		ItemProcessingPlace[brainrotUID] = nil
		warn("⚠️ Slot already occupied")
		return false
	end
	
	-- Use professional RemoveItemWithReturn (handles unequip, attributes, replica sync)
	local removeSuccess, brainrotData = InventoryService:RemoveItemWithReturn(player, brainrotUID)
	if not removeSuccess then
		ItemProcessingPlace[brainrotUID] = nil
		warn("⚠️ Failed to remove brainrot from inventory:", brainrotData) -- brainrotData contains error msg
		return false
	end
	
	-- SECURITY: Validate item is actually a brainrot (prevent lucky blocks or other items on slots)
	if brainrotData.Type ~= "Brainrot" then
		-- ROLLBACK: Add item back to inventory
		InventoryService:AddItem(player, brainrotData.Type, brainrotData.ConfigName, brainrotData.Metadata)
		ItemProcessingPlace[brainrotUID] = nil
		warn("⚠️ Rejected placement: Only brainrots can be placed on slots - " .. player.Name)
		return false
	end
	
	-- Create slot data (store UID so pickup restores same ID, no duplicates)
	local slotData = {
		UID = brainrotUID,
		ConfigName = brainrotData.ConfigName,
		Modifier = brainrotData.Metadata.Modifier or "Normal",
		Level = brainrotData.Metadata.Level or 1,
		CashToCollect = 0,
	}
	
	-- Add to PlotSlots using professional data method
	local addSuccess = DataService:AddToTable(player, "PlotSlots", tostring(slotID), slotData)
	if not addSuccess then
		-- ROLLBACK: Add brainrot back to inventory using professional method
		InventoryService:AddItem(player, "Brainrot", brainrotData.ConfigName, brainrotData.Metadata)
		ItemProcessingPlace[brainrotUID] = nil
		warn("⚠️ Failed to add brainrot to PlotSlots, rolled back")
		return false
	end
	
	-- Update visuals (server-rendered)
	local slotModel = plotData.Slots[slotID].Model
	self:UpdateSlotState(plotData, slotID, slotData, slotModel)
	
	-- Update overhead display
	local Server_CharacterStats = require(script.Parent.Parent.Systems.Server_CharacterStats)
	Server_CharacterStats:UpdateOverheadDisplay(player)
	
	ItemProcessingPlace[brainrotUID] = nil
	return true
end

--[[
	Pick up a brainrot from a slot back into inventory
	@param player Player
	@param plotData table
	@param slotID number
	@return boolean - Success
]]
function SlotService:PickupBrainrot(player: Player, plotData: table, slotID: number): boolean
	-- Anti-dupe lock (per slot - one pickup at a time per slot)
	local pickupLockKey = tostring(player.UserId) .. ":" .. tostring(slotID)
	if ItemProcessingPickup[pickupLockKey] then 
		return false 
	end
	ItemProcessingPickup[pickupLockKey] = true
	
	if not plotData.Slots or not plotData.Slots[slotID] or not plotData.Slots[slotID].Model then
		ItemProcessingPickup[pickupLockKey] = nil
		warn("⚠️ Invalid slot " .. tostring(slotID) .. " for " .. player.Name)
		return false
	end
	
	local profile = DataService:GetProfile(player)
	if not profile then
		ItemProcessingPickup[pickupLockKey] = nil
		warn("⚠️ No profile for " .. player.Name)
		return false
	end
	
	-- Validate brainrot exists in slot (check both saved data AND in-memory)
	local slotData = profile.Data.PlotSlots[tostring(slotID)]
	local slotDataInMemory = plotData.Slots[slotID] and plotData.Slots[slotID].Data
	
	if not slotData and not slotDataInMemory then
		ItemProcessingPickup[pickupLockKey] = nil
		warn("⚠️ No brainrot in slot")
		return false
	end
	
	-- Use saved data if available, fallback to in-memory
	local actualSlotData = slotData or slotDataInMemory
	
	-- Security: same UID must not exist in Inventory (one ID = one item, no dupes)
	local itemUID = (actualSlotData.UID and type(actualSlotData.UID) == "string" and actualSlotData.UID ~= "")
		and actualSlotData.UID
		or nil
	if itemUID and profile.Data.Inventory[itemUID] then
		ItemProcessingPickup[pickupLockKey] = nil
		warn("⚠️ Pickup rejected: UID already in inventory (possible dupe) - " .. player.Name)
		return false
	end
	if not itemUID then
		itemUID = HttpService:GenerateGUID(false)
	end
	
	-- Remove from PlotSlots first (authority: item leaves slot before entering inventory)
	local removalSuccess = DataService:RemoveFromTable(player, "PlotSlots", tostring(slotID))
	if not removalSuccess then
		ItemProcessingPickup[pickupLockKey] = nil
		warn("⚠️ Failed to remove from PlotSlots")
		return false
	end
	
	-- Clear visuals
	local slotModel = plotData.Slots[slotID].Model
	self:ClearSlotState(plotData, slotID, slotModel)
	
	-- Update overhead display
	local Server_CharacterStats = require(script.Parent.Parent.Systems.Server_CharacterStats)
	Server_CharacterStats:UpdateOverheadDisplay(player)
	
	-- Add back to inventory with same UID (no duplicate IDs)
	local newItemData = {
		Type = "Brainrot",
		ConfigName = actualSlotData.ConfigName,
		Metadata = {
			Modifier = actualSlotData.Modifier or "Normal",
			Level = actualSlotData.Level or 1,
		},
	}
	
	DataService:AddToTable(player, "Inventory", itemUID, newItemData)
	
	ItemProcessingPickup[pickupLockKey] = nil
	return true
end

--[[
	Update slot visual state (attributes, models, billboards)
	@param plotData table
	@param slotID number
	@param slotData table - {ConfigName, Modifier, Level, CashToCollect}
	@param slotModel Model
]]
function SlotService:UpdateSlotState(plotData: table, slotID: number, slotData: table, slotModel: Model)
	-- Store data in plot registry
	plotData.Slots[slotID].Data = slotData
	
	-- Set attributes for client replication
	slotModel:SetAttribute("ConfigName", slotData.ConfigName)
	slotModel:SetAttribute("Modifier", slotData.Modifier)
	slotModel:SetAttribute("Level", slotData.Level)
	slotModel:SetAttribute("CashToCollect", slotData.CashToCollect or 0)
	
	-- Create visuals using BrainrotVisuals service
	BrainrotVisuals:CreateBrainrotOnSlot(plotData, slotID, slotModel, slotData)
end

--[[
	Clear slot state (remove brainrot, hide parts)
	@param plotData table
	@param slotID number
	@param slotModel Model
]]
function SlotService:ClearSlotState(plotData: table, slotID: number, slotModel: Model)
	-- Clear data
	plotData.Slots[slotID].Data = nil
	
	-- Clear attributes
	slotModel:SetAttribute("ConfigName", nil)
	slotModel:SetAttribute("Modifier", nil)
	slotModel:SetAttribute("Level", nil)
	slotModel:SetAttribute("CashToCollect", nil)
	
	-- Destroy visuals
	BrainrotVisuals:DestroyBrainrotOnSlot(plotData, slotID, slotModel)
end

--[[
	Sell a brainrot directly from a slot
	@param player Player
	@param plotData table - Plot data from PlotService
	@param slotID number
	@return boolean - Success
]]
function SlotService:SellBrainrot(player: Player, plotData: table, slotID: number): boolean
	-- Get player profile
	local profile = DataService:GetProfile(player)
	if not profile then
		warn("⚠️ No profile for " .. player.Name)
		return false
	end
	
	-- Validate slot
	if not plotData.Slots or not plotData.Slots[slotID] then
		warn("⚠️ Invalid slot " .. slotID .. " for " .. player.Name)
		return false
	end
	
	local slotModel = plotData.Slots[slotID].Model
	local slotData = plotData.Slots[slotID].Data
	
	if not slotModel or not slotData then
		warn("⚠️ No brainrot in slot " .. slotID .. " for " .. player.Name)
		-- Send error popup to player
		local Events = ReplicatedStorage:WaitForChild("Events")
		local popupEvent = Events:FindFirstChild("Popup")
		if popupEvent then
			popupEvent:FireClient(player, "No brainrot in this slot!", "error")
		end
		return false
	end
	
	-- Get brainrot info
	local configName = slotData.ConfigName
	local modifier = slotData.Modifier or "Normal"
	local level = tonumber(slotData.Level) or 1  -- Ensure level is a number
	
	-- Get brainrot config for display name
	local brainrotConfig = Shared_Brainrots.List[configName]
	if not brainrotConfig then
		warn("⚠️ Unknown brainrot config: " .. tostring(configName))
		return false
	end
	local displayName = brainrotConfig.DisplayName or configName
	
	-- Get player's rebirths for sell multiplier
	local rebirths = DataService:GetValue(player, "Rebirths") or 0
	
	-- Calculate sell worth (correct parameter order: configName, level, modifier, rebirths)
	local worth = Shared_Brainrots:CalculateSellWorth(configName, level, modifier, rebirths)
	if worth <= 0 then
		warn("⚠️ Invalid brainrot worth for " .. configName)
		return false
	end
	
	-- Add cash to player
	local currentCash = DataService:GetValue(player, "Cash") or 0
	DataService:SetValue(player, "Cash", currentCash + worth)
	
	-- Remove from PlotSlots saved data (prevents re-spawning on rejoin)
	DataService:RemoveFromTable(player, "PlotSlots", tostring(slotID))
	
	-- Clear the slot visuals and runtime state
	self:ClearSlotState(plotData, slotID, slotModel)
	
	-- Update overhead display
	local Server_CharacterStats = require(script.Parent.Parent.Systems.Server_CharacterStats)
	Server_CharacterStats:UpdateOverheadDisplay(player)
	
	-- Send success popup with cash effect
	local Events = ReplicatedStorage:WaitForChild("Events")
	local popupEvent = Events:FindFirstChild("Popup")
	if popupEvent then
		popupEvent:FireClient(player, {
			text = "Sold " .. displayName .. " for $" .. worth .. "!",
			amount = worth
		}, "success")
	end
	
	return true
end

--[[
	Load saved brainrots from PlotSlots data (on player join)
	@param player Player
	@param plotData table
]]
function SlotService:LoadSavedBrainrots(player: Player, plotData: table)
	local profile = DataService:GetProfile(player)
	if not profile then return end
	
	local loadedCount = 0
	
	-- Load each saved brainrot
	for slotIDStr, brainrotData in pairs(profile.Data.PlotSlots) do
		local slotID = tonumber(slotIDStr)
		if slotID and plotData.Slots[slotID] then
			local slotModel = plotData.Slots[slotID].Model
			self:UpdateSlotState(plotData, slotID, brainrotData, slotModel)
			loadedCount = loadedCount + 1
		end
	end
	
end

return SlotService
