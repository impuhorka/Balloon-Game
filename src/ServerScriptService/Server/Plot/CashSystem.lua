--// CashSystem - Professional cash generation and upgrade system
--// Handles Heartbeat loop for cash accumulation and upgrade logic

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
local Shared_Marketplace = require(ReplicatedStorage.Modules.Settings.Shared_Marketplace)
local Shared_RebirthRewards = require(ReplicatedStorage.Modules.Settings.Shared_RebirthRewards)
local Shared_IndexRewards = require(ReplicatedStorage.Modules.Gameplay.Shared_IndexRewards)

local CashSystem = {}

-- Dependencies (injected at Init)
local DataService
local BrainrotVisuals

-- Constants
local CASH_TICK_INTERVAL = 1 -- seconds
local FRIEND_BOOST_PER_FRIEND = 10 -- 10% per friend in server
local FRIEND_CHECK_INTERVAL = 10 -- Recheck friend count every 10 seconds

-- Offline Earnings Config
local OFFLINE_CONFIG = {
	Enabled = true, -- Set false to disable offline earnings popup
	MaxOfflineTime = 12 * 60 * 60, -- 12 hours in seconds
	MinOfflineTime = 240, -- Minimum 2 seconds offline (TESTING: set to 60 for production)
	OfflineRate = 0.02, -- 2% of normal rate (like SingingX)
	BoostMultiplier = 10, -- 10x multiplier for Robux boost
}

-- Cache friend boost per player
local PlayerFriendBoost = {} -- [player] = multiplier (e.g. 1.3 = 30% boost)

--[[
	Initialize with dependencies
	@param dependencies table - {DataService, BrainrotVisuals}
]]
function CashSystem:Init(dependencies)
	DataService = dependencies.DataService
	BrainrotVisuals = dependencies.BrainrotVisuals
	
	-- Start friend boost tracking
	self:StartFriendBoostLoop()
end

--[[
	Count how many friends a player has in the current server
	@param player Player
	@return number - Friend count in server
]]
function CashSystem:GetFriendCountInServer(player: Player): number
	local count = 0
	
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			local ok, isFriend = pcall(function()
				return player:IsFriendsWith(otherPlayer.UserId)
			end)
			if ok and isFriend then
				count = count + 1
			end
		end
	end
	
	return count
end

--[[
	Get friend boost multiplier for a player (1.0 = no boost, 1.3 = 30% boost)
	@param player Player
	@return number
]]
function CashSystem:GetFriendBoostMultiplier(player: Player): number
	return PlayerFriendBoost[player] or 1
end

--[[
	Update friend boost for a specific player and set attribute
	@param player Player
]]
function CashSystem:UpdateFriendBoost(player: Player)
	local friendCount = self:GetFriendCountInServer(player)
	local boostPercent = friendCount * FRIEND_BOOST_PER_FRIEND
	local multiplier = 1 + (boostPercent / 100)
	
	PlayerFriendBoost[player] = multiplier
	player:SetAttribute("FriendCashBoost", boostPercent)
end

--[[
	Periodically update friend boost for all players
]]
function CashSystem:StartFriendBoostLoop()
	-- Initial update for existing players
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self:UpdateFriendBoost(player)
		end)
	end
	
	-- Update when players join/leave (affects friend counts)
	Players.PlayerAdded:Connect(function(newPlayer)
		-- Recheck all players (someone's friend may have joined)
		task.wait(1) -- Let player fully load
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				self:UpdateFriendBoost(player)
			end)
		end
	end)
	
	Players.PlayerRemoving:Connect(function(leavingPlayer)
		PlayerFriendBoost[leavingPlayer] = nil
		-- Recheck remaining players (friend may have left)
		task.defer(function()
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(function()
					self:UpdateFriendBoost(player)
				end)
			end
		end)
	end)
	
	-- Periodic refresh (handles edge cases)
	task.spawn(function()
		while true do
			task.wait(FRIEND_CHECK_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(function()
					self:UpdateFriendBoost(player)
				end)
			end
		end
	end)
end

--[[
	Calculate cash per second for a brainrot
	@param configName string
	@param modifier string
	@param level number
	@return number - Cash per second
]]
function CashSystem:GetCashPerSecond(configName: string, modifier: string, level: number): number
	-- Use new formula-driven calculation
	return Shared_Brainrots:GetCashPerSecond(configName, level, modifier)
end

--[[
	Calculate upgrade cost for a brainrot
	@param configName string
	@param currentLevel number
	@param modifier string - NEW: Required for modifier cost multiplier
	@return number - Upgrade cost
]]
function CashSystem:GetUpgradeCost(configName: string, currentLevel: number, modifier: string): number
	-- Use new formula-driven calculation with modifier cost multiplier
	return Shared_Brainrots:GetUpgradeCost(configName, currentLevel, modifier or "Normal")
end

--[[
	Upgrade a brainrot in a slot
	@param player Player
	@param plotData table
	@param slotID number
	@return boolean - Success
]]
function CashSystem:UpgradeBrainrot(player: Player, plotData: table, slotID: number): boolean
	local profile = DataService:GetProfile(player)
	if not profile then 
		warn("⚠️ No profile for " .. player.Name)
		return false
	end
	
	-- Validate brainrot exists in slot
	local slotData = profile.Data.PlotSlots[tostring(slotID)]
	if not slotData then
		warn("⚠️ No brainrot in slot")
		return false
	end
	
	local currentLevel = slotData.Level or 1
	local maxLevel = Shared_Brainrots.MaxLevel or 100
	
	-- Check max level
	if currentLevel >= maxLevel then
		warn("⚠️ Brainrot already at max level")
		return false
	end
	
	-- Check if player can afford upgrade
	local modifier = slotData.Modifier or "Normal"
	local upgradeCost = self:GetUpgradeCost(slotData.ConfigName, currentLevel, modifier)
	if (profile.Data.Cash or 0) < upgradeCost then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events then
			local popupEvent = Events:FindFirstChild("Popup")
			if popupEvent then
				popupEvent:FireClient(player, "Not enough cash!", "error", { popupType = "UpgradeError" })
			end
		end
		-- Offer Robux upgrade: server sets purchase context and prompts
		local config = Shared_Brainrots.List[slotData.ConfigName]
		if config and Shared_Marketplace.RarityToUpgradeProduct then
			local productKey = Shared_Marketplace.RarityToUpgradeProduct[config.Rarity]
			if productKey and Shared_Marketplace.Products[productKey] then
				local Server_Marketplace = require(script.Parent.Parent.Systems.Server_Marketplace)
				Server_Marketplace:OfferUpgradeWithRobux(player, slotID, productKey)
			end
		end
		return false
	end
	
	-- Deduct cost and apply upgrade
	DataService:AddValue(player, "Cash", -upgradeCost)
	return self:ApplyUpgradeToSlot(player, plotData, slotID, slotData, currentLevel)
end

--[[
	Apply one level upgrade to a slot (shared by cash and Robux upgrade).
	Does not deduct cash; caller must have already validated and deducted if paying with cash.
	@param player Player
	@param plotData table
	@param slotID number
	@param slotData table - current slot data from profile
	@param currentLevel number - current level before upgrade
	@return boolean - Success
]]
function CashSystem:ApplyUpgradeToSlot(player: Player, plotData: table, slotID: number, slotData: table, currentLevel: number): boolean
	local newSlotData = table.clone(slotData)
	newSlotData.Level = currentLevel + 1
	DataService:AddToTable(player, "PlotSlots", tostring(slotID), newSlotData)
	
	local slotModel = plotData.Slots[slotID].Model
	slotModel:SetAttribute("Level", newSlotData.Level)
	
	local brainrotModel = plotData.Slots[slotID].PlacedBrainrot
	if brainrotModel then
		BrainrotVisuals:PositionBrainrotOnSlot(brainrotModel, slotModel, newSlotData.Level)
		local billboard = brainrotModel:FindFirstChildWhichIsA("BillboardGui", true)
		if billboard then
			local levelLabel = billboard:FindFirstChild("Level", true)
			if levelLabel and levelLabel:IsA("TextLabel") then
				levelLabel.Text = "Lv " .. newSlotData.Level
			end
		end
	end
	
	local Server_CharacterStats = require(script.Parent.Parent.Systems.Server_CharacterStats)
	Server_CharacterStats:UpdateOverheadDisplay(player)
	
	local Events = ReplicatedStorage:FindFirstChild("Events")
	if Events then
		local popupEvent = Events:FindFirstChild("Popup")
		if popupEvent then
			popupEvent:FireClient(player, ("Upgraded from lvl %d > level %d!"):format(currentLevel, currentLevel + 1), "success", { popupType = "UpgradeSuccess" })
		end
	end
	
	return true
end

--[[
	Upgrade a brainrot in a slot using Robux (no cash deduction).
	Called from Server_Marketplace when "Upgrade Brainrot N" product purchase is confirmed.
	@param player Player
	@param plotData table - from PlotService:GetPlayerPlotData
	@param slotID number
	@return boolean - Success
]]
function CashSystem:UpgradeBrainrotWithRobux(player: Player, plotData: table, slotID: number): boolean
	local profile = DataService:GetProfile(player)
	if not profile then return false end
	
	local slotData = profile.Data.PlotSlots[tostring(slotID)]
	if not slotData then return false end
	
	local currentLevel = slotData.Level or 1
	local maxLevel = Shared_Brainrots.MaxLevel or 100
	if currentLevel >= maxLevel then return false end
	
	return self:ApplyUpgradeToSlot(player, plotData, slotID, slotData, currentLevel)
end

--[[
	Collect accumulated cash from a slot
	@param player Player
	@param plotData table
	@param slotID number
	@return boolean - Success
]]
function CashSystem:CollectCash(player: Player, plotData: table, slotID: number): boolean
	local profile = DataService:GetProfile(player)
	if not profile then
		warn("⚠️ No profile for " .. player.Name)
		return false
	end
	
	-- Validate brainrot exists in slot
	local slotData = profile.Data.PlotSlots[tostring(slotID)]
	if not slotData then
		warn("⚠️ No brainrot in slot")
		return false
	end
	
	-- Get CashToCollect from slot model attribute (updated every second via Heartbeat)
	local slotModel = plotData.Slots[slotID].Model
	local cashToCollect = slotModel:GetAttribute("CashToCollect") or 0
	
	if cashToCollect <= 0 then
		return false
	end
	
	-- Add cash to player
	DataService:AddValue(player, "Cash", cashToCollect)
	
	-- Reset CashToCollect (attribute only, no PlotSlots update)
	slotModel:SetAttribute("CashToCollect", 0)
	
	return true
end

--[[
	Start cash generation loop for all plots
	@param plots table - Plot registry from PlotService
]]
function CashSystem:StartCashGenerationLoop(plots: table)
	task.spawn(function()
		local debugCounter = 0 -- For occasional debug prints
		
		while true do
			task.wait(CASH_TICK_INTERVAL) -- Wait 1 second between ticks
			debugCounter = debugCounter + 1
			
			-- Generate cash for all occupied slots
			for plotID, plotData in pairs(plots) do
				if plotData.Owner then
					local profile = DataService:GetProfile(plotData.Owner)
					if profile then
						for slotID, slotInfo in pairs(plotData.Slots) do
							local slotData = profile.Data.PlotSlots[tostring(slotID)]
							if slotData and slotData.ConfigName then
								-- Calculate base cash per second
								local cashPerSec = self:GetCashPerSecond(
									slotData.ConfigName,
									slotData.Modifier or "Normal",
									slotData.Level or 1
								)
								
								-- Additive multiplier stack:
								-- rebirths = anchor including base 1x (e.g. 10 rebirths = 5x)
								-- everything else adds on top (+2 gamepass, friend boost, etc.)
								local rebirths = profile.Data.Rebirths or 0
								local totalMultiplier = Shared_RebirthRewards:GetCashMultiplier(rebirths)

								if profile.Data.Passes and profile.Data.Passes.CashBoost == true then
									totalMultiplier = totalMultiplier + 2
								end

								local equippedFloor = profile.Data.EquippedIndexFloor or "Default"
								totalMultiplier = totalMultiplier + Shared_IndexRewards:GetCashMultiplier(equippedFloor)

								local friendMult = PlayerFriendBoost[plotData.Owner] or 1
								totalMultiplier = totalMultiplier + (friendMult - 1)

								local cashGenerated = cashPerSec * CASH_TICK_INTERVAL * totalMultiplier
								
								-- Read current CashToCollect from attribute (not from slotData!)
								local slotModel = slotInfo.Model
								local currentCash = slotModel:GetAttribute("CashToCollect") or 0
								local newCashToCollect = currentCash + cashGenerated
								
								-- Update slot model attribute for client (no replica trigger)
								slotModel:SetAttribute("CashToCollect", newCashToCollect)
							end
						end
					end
				end
			end
		end
	end)
	
end

--[[
	Format offline time for display (e.g., "2h 30m" or "45m")
	@param seconds number
	@return string
]]
function CashSystem:FormatOfflineTime(seconds: number): string
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	
	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	else
		return string.format("%dm", minutes)
	end
end

--[[
	Calculate offline earnings for all brainrots in player's plot
	Called once when player joins (stores in PendingOfflineEarnings)
	@param player Player
	@return number - Total offline earnings calculated
]]
function CashSystem:CalculateOfflineEarnings(player: Player): number
	if not OFFLINE_CONFIG.Enabled then return 0 end
	
	local profile = DataService:GetProfile(player)
	if not profile then return 0 end
	
	local data = profile.Data
	local lastOfflineStart = data.LastOfflineStart or 0
	
	-- Only calculate if player has left before
	if lastOfflineStart <= 0 then return 0 end
	
	local currentTime = os.time()
	local offlineTime = currentTime - lastOfflineStart
	
	-- Must be offline for minimum time
	if offlineTime < OFFLINE_CONFIG.MinOfflineTime then return 0 end
	
	-- Cap at maximum offline time
	local cappedOfflineTime = math.min(offlineTime, OFFLINE_CONFIG.MaxOfflineTime)
	
	local totalOfflineEarnings = 0
	
	-- Process each brainrot in PlotSlots
	for slotID, slotData in pairs(data.PlotSlots) do
		if slotData and slotData.ConfigName then
			-- Calculate base cash per second
			local cashPerSec = self:GetCashPerSecond(
				slotData.ConfigName,
				slotData.Modifier or "Normal",
				slotData.Level or 1
			)
			
			-- Additive multiplier stack (no friend boost offline)
			local rebirths = data.Rebirths or 0
			local totalMultiplier = Shared_RebirthRewards:GetCashMultiplier(rebirths)

			if data.Passes and data.Passes.CashBoost == true then
				totalMultiplier = totalMultiplier + 2
			end

			local equippedFloor = data.EquippedIndexFloor or "Default"
			totalMultiplier = totalMultiplier + Shared_IndexRewards:GetCashMultiplier(equippedFloor)

			-- Calculate offline earnings (reduced rate)
			local offlineEarnings = cashPerSec * cappedOfflineTime * totalMultiplier * OFFLINE_CONFIG.OfflineRate
			
			totalOfflineEarnings = totalOfflineEarnings + offlineEarnings
		end
	end
	
	return math.floor(totalOfflineEarnings)
end

--[[
	Process offline earnings when player joins
	Stores in PendingOfflineEarnings and triggers popup (if enabled)
	@param player Player
]]
function CashSystem:ProcessOfflineEarnings(player: Player)
	if not OFFLINE_CONFIG.Enabled then return end
	
	local offlineEarnings = self:CalculateOfflineEarnings(player)
	
	if offlineEarnings > 0 then
		-- Store pending earnings in player data
		DataService:SetValue(player, "PendingOfflineEarnings", offlineEarnings)
		
		-- Trigger popup on client (UI will handle display)
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events then
			local offlineHandler = Events:FindFirstChild("OfflineHandler")
			if offlineHandler then
				-- Calculate offline time for display
				local lastOfflineStart = DataService:GetValue(player, "LastOfflineStart") or 0
				local offlineTime = os.time() - lastOfflineStart
				local cappedTime = math.min(offlineTime, OFFLINE_CONFIG.MaxOfflineTime)
				local formattedTime = self:FormatOfflineTime(cappedTime)
				
				offlineHandler:FireClient(player, {
					amount = offlineEarnings,
					offlineTime = formattedTime,
				})
			end
		end
		
	end
	
	-- Reset LastOfflineStart
	DataService:SetValue(player, "LastOfflineStart", 0)
end

--[[
	Claim offline earnings (free or boosted)
	@param player Player
	@param claimType string - "Free" or "Boost2x"
	@return boolean - Success
]]
function CashSystem:ClaimOfflineEarnings(player: Player, claimType: string): boolean
	local profile = DataService:GetProfile(player)
	if not profile then return false end
	
	local data = profile.Data
	local pendingOffline = data.PendingOfflineEarnings or 0
	
	if pendingOffline <= 0 then
		warn("⚠️ No pending offline earnings for " .. player.Name)
		return false
	end
	
	if claimType == "Free" then
		-- Give base amount
		DataService:AddValue(player, "Cash", pendingOffline)
		DataService:SetValue(player, "PendingOfflineEarnings", 0)
		
		-- Notify player
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events then
			local popupEvent = Events:FindFirstChild("Popup")
			if popupEvent then
				local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
				popupEvent:FireClient(player, {
					text = string.format("Claimed $%s offline earnings!", Shared_Shorten:Number(pendingOffline)),
					amount = pendingOffline,
				}, "success")
			end
		end
		
		return true
		
	elseif claimType == "10x" then
		-- Don't give cash yet - marketplace will handle after purchase
		-- Just validate that pending earnings exist
		return true
	end
	
	return false
end

return CashSystem
