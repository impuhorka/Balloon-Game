--[[
	Server_SellHandler - Brainrot selling system
	Validates and processes brainrot sales
	
	Features:
	- Sell single brainrot by UID
	- Sell all brainrots in inventory
	- Anti-spam cooldown
	- Server-side validation
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server_Data = require(script.Parent.Parent.Core.Server_Data)
local Server_Inventory = require(script.Parent.Parent.Core.Server_Inventory)
local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)

local Module = {}

-- Anti-spam cooldown
local SellCooldowns = {}
local COOLDOWN = 0.5 -- seconds

--[[
	Handle selling a single brainrot or all brainrots
	@param player Player
	@param brainrotUID string? - UID of brainrot to sell (nil = sell all)
]]
local function onSellBrainrot(player: Player, brainrotUID: string?)
	-- Cooldown check
	local now = tick()
	if (SellCooldowns[player.UserId] or 0) > now - COOLDOWN then
		return
	end
	SellCooldowns[player.UserId] = now
	
	-- Get player data
	local rebirths = Server_Data:GetValue(player, "Rebirths") or 0
	local currentCash = Server_Data:GetValue(player, "Cash") or 0
	
	if brainrotUID then
		-- ========================================
		-- SELL SINGLE BRAINROT
		-- ========================================
		
		local itemData = Server_Inventory:GetItem(player, brainrotUID)
		if not itemData then
			warn("⚠️ " .. player.Name .. " tried to sell non-existent brainrot: " .. tostring(brainrotUID))
			local popupEvent = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("Popup")
			if popupEvent then
				popupEvent:FireClient(player, "Brainrot not found!", "error")
			end
			return
		end
		
		if itemData.Type ~= "Brainrot" then
			warn("⚠️ " .. player.Name .. " tried to sell non-brainrot item: " .. tostring(brainrotUID))
			local popupEvent = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("Popup")
			if popupEvent then
				popupEvent:FireClient(player, "That's not a brainrot!", "error")
			end
			return
		end
		
		-- Calculate worth
		local worth = Shared_Brainrots:CalculateSellWorth(
			itemData.ConfigName,
			itemData.Metadata and itemData.Metadata.Level or 1,
			itemData.Metadata and itemData.Metadata.Modifier or "Normal",
			rebirths
		)
		
		-- Remove from inventory
		local success = Server_Inventory:RemoveItem(player, brainrotUID)
		if not success then
			warn("⚠️ Failed to remove brainrot " .. brainrotUID .. " from " .. player.Name)
			local popupEvent = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("Popup")
			if popupEvent then
				popupEvent:FireClient(player, "Failed to sell brainrot", "error")
			end
			return
		end
		
		-- Add cash
		Server_Data:SetValue(player, "Cash", currentCash + worth)
		
		local popupEvent = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("Popup")
		if popupEvent then
			local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
			local config = Shared_Brainrots.List[itemData.ConfigName]
			local displayName = config and config.DisplayName or itemData.ConfigName
			-- One event: text + amount so client can show both message and cash popup
			popupEvent:FireClient(player, {
				text = string.format("Sold %s for $%s!", displayName, Shared_Shorten:Number(worth)),
				amount = worth,
			}, "success")
		end
		
	else
		-- ========================================
		-- SELL ALL BRAINROTS
		-- ========================================
		
		local inventory = Server_Inventory:GetInventory(player)
		if not inventory then 
			warn("⚠️ " .. player.Name .. " has no inventory")
			return 
		end
		
		local totalWorth = 0
		local brainrotsToSell = {} -- { uid, worth }
		
		-- Calculate total and collect UIDs
		for uid, itemData in pairs(inventory) do
			if itemData.Type == "Brainrot" then
				local worth = Shared_Brainrots:CalculateSellWorth(
					itemData.ConfigName,
					itemData.Metadata and itemData.Metadata.Level or 1,
					itemData.Metadata and itemData.Metadata.Modifier or "Normal",
					rebirths
				)
				totalWorth += worth
				table.insert(brainrotsToSell, { uid = uid, worth = worth })
			end
		end
		
		if #brainrotsToSell == 0 then
			warn("⚠️ " .. player.Name .. " has no brainrots to sell")
			local popupEvent = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("Popup")
			if popupEvent then
				popupEvent:FireClient(player, "You have no brainrots to sell!", "error")
			end
			return
		end
		
		-- Remove all brainrots
		for _, entry in ipairs(brainrotsToSell) do
			Server_Inventory:RemoveItem(player, entry.uid)
		end
		
		-- Add cash
		Server_Data:SetValue(player, "Cash", currentCash + totalWorth)
		
		local popupEvent = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("Popup")
		if popupEvent then
			local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
			popupEvent:FireClient(player, {
				text = string.format("Sold %d brainrots for $%s!", #brainrotsToSell, Shared_Shorten:Number(totalWorth)),
				amount = totalWorth,
			}, "success")
		end
	end
end

--[[
	Initialize sell handler
]]
function Module:Init()
	-- Connect to SellBrainrot event (created by Template)
	local events = ReplicatedStorage:WaitForChild("Events")
	local sellEvent = events:WaitForChild("SellBrainrot")
	
	-- Connect handler
	sellEvent.OnServerEvent:Connect(onSellBrainrot)
end

return Module
