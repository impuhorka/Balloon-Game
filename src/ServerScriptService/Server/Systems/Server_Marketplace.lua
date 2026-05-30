--// Server_Marketplace - Secure DevProduct and Gamepass handling
--// Handles all marketplace transactions with receipt validation and duplicate prevention
--// Adapted from SingingX production marketplace system

--// Services
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

--// Module Setup
local Module = {}

local Shared_Marketplace = require(ReplicatedStorage.Modules.Settings.Shared_Marketplace)

--// Product Definitions (from shared config)
Module.Products = Shared_Marketplace.Products
Module.CashAmounts = Shared_Marketplace.CashAmounts

--// Gamepass Definitions (from shared config)
Module.Passes = Shared_Marketplace.Passes

--// Security Tables
-- Purchase contexts prevent race conditions when multiple players purchase simultaneously
-- Structure: [UserId][ProductId] = {contextData}
Module.PurchaseContexts = {}

-- Processed receipts prevent duplicate processing of the same receipt
-- Structure: [receiptKey] = true
Module.ProcessedReceipts = {}

--// Helper Functions

-- Get player profile from Server_Data
local function getProfile(player: Player)
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	return Server_Data:GetProfile(player)
end

-- Get player data from Server_Data
local function getData(player: Player)
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	return Server_Data:GetData(player)
end

-- Log marketplace transaction to datastore
local function logMarketplace(profile, purchaseId: string, status: string, productId: number, reason: string?)
	if not profile or not profile.Data then return end
	
	local logs = profile.Data.MarketplaceLogs
	logs[purchaseId] = {
		Status = status,
		ProductId = productId,
		Reason = reason,
		Time = os.time(),
	}
end

-- Get product name from product ID
local function getProductName(productId: number): string?
	for name, id in pairs(Module.Products) do
		if id == productId then
			return name
		end
	end
	return nil
end

-- Get gamepass name from gamepass ID
local function getPassName(passId: number): string?
	for name, id in pairs(Module.Passes) do
		if id == passId then
			return name
		end
	end
	return nil
end

--// Product Handlers
-- These functions grant items/currency when purchases are confirmed
-- Add/modify handlers based on your game's needs

function Module:ProcessCashPurchase(player: Player, data: any, productName: string)
	-- Get cash amount from config
	local cashAmount = self.CashAmounts[productName] or 0
	
	if cashAmount > 0 then
		-- Use Server_Data to update cash value
		local Server_Data = require(script.Parent.Parent.Core.Server_Data)
		Server_Data:SetValue(player, "Cash", data.Cash + cashAmount)
		
		-- Send success notification and trigger cash rain effect
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events then
			-- Trigger cash rain effect using PlayEffect RemoteEvent
			local playEffect = Events:FindFirstChild("PlayEffect")
			if playEffect then
				playEffect:FireClient(player, {
					effectType = "cashrain",
					cashAmount = cashAmount
				})
			end
			
			-- Show popup
			local popupEvent = Events:FindFirstChild("Popup")
			if popupEvent then
				popupEvent:FireClient(player, "Purchased $" .. cashAmount .. " Cash!", true)
			end
		end
	end
end

function Module:ProcessSpeedPurchase(player: Player, data: any, productName: string)
	-- Grant speed based on product tier
	local speedAmount = 0
	
	if productName == "Skip Speed 1" then
		speedAmount = 1
	elseif productName == "Skip Speed 2" then
		speedAmount = 5
	elseif productName == "Skip Speed 3" then
		speedAmount = 10
	elseif productName == "SpeedBoost" then
		speedAmount = 10
	elseif productName == "SpeedBoostLarge" then
		speedAmount = 50
	end
	
	if speedAmount > 0 then
		-- Use Server_Data to update speed value
		local Server_Data = require(script.Parent.Parent.Core.Server_Data)
		Server_Data:SetValue(player, "Speed", data.Speed + speedAmount)
		
		-- Send success notification to player
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events and Events:FindFirstChild("Popup") then
			Events.Popup:FireClient(player, "Purchased +" .. speedAmount .. " Speed!", true)
		end
	end
end

function Module:ProcessOfflineBoost10x(player: Player, data: any, productName: string)
	-- Grant 10x offline earnings boost
	local pendingOffline = data.PendingOfflineEarnings or 0
	
	if pendingOffline <= 0 then
		warn("⚠️ No pending offline earnings for " .. player.Name)
		return
	end
	
	-- Give 10x the pending amount
	local boostedAmount = pendingOffline * 10
	
	-- Use Server_Data to update cash
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	Server_Data:AddValue(player, "Cash", boostedAmount)
	
	-- CRITICAL: Clear pending earnings after granting boosted amount
	Server_Data:SetValue(player, "PendingOfflineEarnings", 0)
	
	-- Send success notification
	local Events = ReplicatedStorage:FindFirstChild("Events")
	if Events and Events:FindFirstChild("Popup") then
		local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
		Events.Popup:FireClient(player, {
			text = string.format("Claimed $%s (10x Boost)!", Shared_Shorten:Number(boostedAmount)),
			amount = boostedAmount,
		}, "success")
	end
	
end

function Module:ProcessSkipRebirth(player: Player, data: any, productName: string)
	-- Perform rebirth, skipping speed requirement (Robux purchase)
	local Server_RebirthStore = require(script.Parent.Parent.Gameplay.Server_RebirthStore)
	Server_RebirthStore:DoRebirth(player, true)
end

function Module:ProcessForceGreenLight(player: Player, data: any, productName: string)
	-- Force green light for 30 seconds (stackable)
	local Server_GameHandler = require(script.Parent.Parent.Gameplay.Server_GameHandler)
	Server_GameHandler:AddForcedGreenLightTime(30, player.Name)
end

function Module:ProcessUpgradeBrainrotPurchase(player: Player, data: any, productName: string, context: any)
	local slotID = context and context.upgradeSlotID
	if not slotID or type(slotID) ~= "number" then
		warn("Server_Marketplace: Upgrade Brainrot purchase with no upgradeSlotID in context. Product:", productName, "Player:", player.Name)
		return
	end
	
	local PlotService = require(script.Parent.Parent.Plot.PlotService)
	local plotData = PlotService:GetPlayerPlotData(player)
	if not plotData or not plotData.Slots or not plotData.Slots[slotID] then
		warn("Server_Marketplace: No plot/slot for Robux upgrade. Player:", player.Name, "slotID:", slotID)
		return
	end
	
	local CashSystem = require(script.Parent.Parent.Plot.CashSystem)
	local ok = CashSystem:UpgradeBrainrotWithRobux(player, plotData, slotID)
	if not ok then
		warn("Server_Marketplace: UpgradeBrainrotWithRobux failed. Player:", player.Name, "slotID:", slotID)
	end
end

--[[
	Offer upgrade with Robux when player can't afford cash upgrade.
	Called from CashSystem. Sets purchase context and prompts; receipt handler applies upgrade.
]]
function Module:OfferUpgradeWithRobux(player: Player, slotID: number, productKey: string)
	local productId = self.Products[productKey]
	if not productId or not productKey:match("^Upgrade Brainrot %d$") then
		return
	end
	if not self.PurchaseContexts[player.UserId] then
		self.PurchaseContexts[player.UserId] = {}
	end
	self.PurchaseContexts[player.UserId][productId] = { upgradeSlotID = slotID }
	-- Option A: Fire to client so it shows rainbow and prompts (single canonical flow)
	local Events = ReplicatedStorage:FindFirstChild("Events")
	local purchaseHandler = Events and Events:FindFirstChild("PurchaseHandler")
	if purchaseHandler then
		purchaseHandler:FireClient(player, productId, self.PurchaseContexts[player.UserId][productId])
	end
end

--[[
	Per-rarity steal credits: use before Robux; grant 1 for that rarity when apply fails.
]]
local function getStealCreditsForRarity(player: Player, rarity: string): number
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	local credits = Server_Data:GetValue(player, "StealCredits")
	if type(credits) ~= "table" or type(rarity) ~= "string" then return 0 end
	return type(credits[rarity]) == "number" and credits[rarity] or 0
end

local function useStealCreditForRarity(player: Player, rarity: string): boolean
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	local credits = Server_Data:GetValue(player, "StealCredits") or {}
	local count = type(credits[rarity]) == "number" and credits[rarity] or 0
	if count < 1 then return false end
	credits[rarity] = count - 1
	if credits[rarity] == 0 then credits[rarity] = nil end
	Server_Data:SetValue(player, "StealCredits", credits)
	return true
end

local function grantStealCreditForRarity(player: Player, rarity: string)
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	local credits = Server_Data:GetValue(player, "StealCredits") or {}
	credits[rarity] = (type(credits[rarity]) == "number" and credits[rarity] or 0) + 1
	Server_Data:SetValue(player, "StealCredits", credits)
end

--[[
	Handle "request steal" via PurchaseHandler (Option B).
	Use a steal credit for this rarity first; if none, prompt for Robux.
	On apply failure (target left / slot empty), grant 1 credit for that rarity.
	Context: { type = "StealBrainrot", targetUserId = number, slotID = number, rarity = string }
]]
function Module:HandleStealBrainrotRequest(player: Player, purchaseContext: any)
	if type(purchaseContext) ~= "table" or purchaseContext.type ~= "StealBrainrot" then return end
	local targetUserId = purchaseContext.targetUserId
	local slotID = purchaseContext.slotID
	if type(targetUserId) ~= "number" or type(slotID) ~= "number" then return end
	if targetUserId == player.UserId then return end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	local targetProfile = getProfile(targetPlayer)
	if not targetPlayer or not targetProfile then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local popup = Events and Events:FindFirstChild("Popup")
		if popup then popup:FireClient(player, "That player is no longer in the game.", "error") end
		return
	end

	local slotKey = tostring(slotID)
	local slotData = targetProfile.Data.PlotSlots and targetProfile.Data.PlotSlots[slotKey]
	if not slotData or not slotData.ConfigName then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local popup = Events and Events:FindFirstChild("Popup")
		if popup then popup:FireClient(player, "There is no brainrot in that slot.", "error") end
		return
	end

	local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
	local config = Shared_Brainrots.List[slotData.ConfigName]
	local rarity = config and config.Rarity
	if not rarity or not Shared_Marketplace.RarityToStealProduct then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local popup = Events and Events:FindFirstChild("Popup")
		if popup then popup:FireClient(player, "Steal is not available for this brainrot.", "error") end
		return
	end

	local productKey = Shared_Marketplace.RarityToStealProduct[rarity]
	if not productKey or not self.Products[productKey] then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local popup = Events and Events:FindFirstChild("Popup")
		if popup then popup:FireClient(player, "Steal is not available for this rarity.", "error") end
		return
	end

	local productId = self.Products[productKey]

	-- Use a steal credit for this rarity first; if none, prompt for Robux
	if getStealCreditsForRarity(player, rarity) >= 1 then
		useStealCreditForRarity(player, rarity)
		local ok = self:ApplyStealBrainrot(player, targetUserId, slotID)
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local popup = Events and Events:FindFirstChild("Popup")
		if ok and popup then
			popup:FireClient(player, "Brainrot stolen! (1 credit used)", "success")
		elseif not ok and popup then
			popup:FireClient(player, "Couldn't complete steal! You received 1 " .. rarity .. " steal credit.", "error")
			grantStealCreditForRarity(player, rarity) -- Grant credit for that rarity on failure
		end
		return
	end

	-- No credit for this rarity: prompt for Robux (store rarity so receipt handler can grant credit on failure)
	if not self.PurchaseContexts[player.UserId] then
		self.PurchaseContexts[player.UserId] = {}
	end
	self.PurchaseContexts[player.UserId][productId] = {
		type = "StealBrainrot",
		targetUserId = targetUserId,
		slotID = slotID,
		rarity = rarity,
	}

	-- Option A: Fire to client so it shows rainbow and prompts (single canonical flow)
	local Events = ReplicatedStorage:FindFirstChild("Events")
	local purchaseHandler = Events and Events:FindFirstChild("PurchaseHandler")
	if purchaseHandler then
		purchaseHandler:FireClient(player, productId, self.PurchaseContexts[player.UserId][productId])
	end
end

function Module:ProcessStealBrainrotPurchase(player: Player, data: any, productName: string, context: any)
	if not context or context.type ~= "StealBrainrot" then
		warn("Server_Marketplace: Steal receipt with no/invalid context. Product:", productName)
		return
	end
	local targetUserId = context.targetUserId
	local slotID = context.slotID
	local rarity = context.rarity
	if type(targetUserId) ~= "number" or type(slotID) ~= "number" then return end
	local ok = self:ApplyStealBrainrot(player, targetUserId, slotID)
	if not ok then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local popup = Events and Events:FindFirstChild("Popup")
		if popup then
			popup:FireClient(player, "Couldn't complete steal - the other player left or the slot is empty. You received 1 " .. (type(rarity) == "string" and rarity or "steal") .. " steal credit.", "error")
		end
		-- Grant 1 steal credit for that rarity when purchase (Robux) fails
		if type(rarity) == "string" and rarity ~= "" then
			grantStealCreditForRarity(player, rarity)
		end
	end
end

--[[
	Teleport player to their plot after successful "Teleport Home" purchase.
]]
function Module:ProcessTeleportHome(player: Player)
	local PlotService = require(script.Parent.Parent.Plot.PlotService)
	local plotID = PlotService:GetPlayerPlot(player)
	if not plotID then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local popup = Events and Events:FindFirstChild("Popup")
		if popup then popup:FireClient(player, "You don't have a plot.", "error") end
		return
	end
	PlotService:RespawnPlayerAtPlot(player, plotID)
	local Events = ReplicatedStorage:FindFirstChild("Events")
	local popup = Events and Events:FindFirstChild("Popup")
	if popup then popup:FireClient(player, "Teleported home!", "success") end
end

--[[
	Starter Pack: grant Cash, LuckyBlock(s), one Brainrot; set StarterPackPurchased.
	Called from ProcessReceipt after validation. Rewards from Shared_Marketplace.StarterPackRewards.
]]
function Module:ProcessStarterPack(player: Player, data: any)
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	local Server_Inventory = require(script.Parent.Parent.Core.Server_Inventory)
	local rewards = Shared_Marketplace.StarterPackRewards or {}
	local Events = ReplicatedStorage:FindFirstChild("Events")
	local popup = Events and Events:FindFirstChild("Popup")

	Server_Data:SetValue(player, "StarterPackPurchased", true)

	if type(rewards.Cash) == "number" and rewards.Cash > 0 then
		Server_Data:SetValue(player, "Cash", (data.Cash or 0) + rewards.Cash)
	end

	local blockType = rewards.LuckyBlockType
	local blockCount = tonumber(rewards.LuckyBlockCount) or 1
	if blockType and blockCount > 0 then
		for _ = 1, blockCount do
			Server_Inventory:AddItem(player, "LuckyBlock", blockType, nil)
		end
	end

	local brainrotConfig = rewards.BrainrotConfigName
	if type(brainrotConfig) == "string" and brainrotConfig ~= "" then
		local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
		if Shared_Brainrots.List and Shared_Brainrots.List[brainrotConfig] then
			Server_Inventory:AddItem(player, "Brainrot", brainrotConfig, {})
		end
	end

	if popup then
		popup:FireClient(player, "Starter Pack purchased!", true)
	end
end

--[[
	Apply steal: remove brainrot from target slot, add to stealer inventory. Uses our SlotService, DataService, Server_Inventory.
]]
function Module:ApplyStealBrainrot(stealer: Player, targetUserId: number, slotID: number): boolean
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then return false end
	local targetProfile = getProfile(targetPlayer)
	if not targetProfile or not targetProfile.Data then return false end

	local slotKey = tostring(slotID)
	local slotData = targetProfile.Data.PlotSlots and targetProfile.Data.PlotSlots[slotKey]
	if not slotData or not slotData.ConfigName then return false end

	local configName = slotData.ConfigName
	local metadata = {
		Modifier = slotData.Modifier or "Normal",
		Level = slotData.Level or 1,
	}

	local DataService = require(script.Parent.Parent.Core.Server_Data)
	local removalSuccess = DataService:RemoveFromTable(targetPlayer, "PlotSlots", slotKey)
	if not removalSuccess then return false end

	local PlotService = require(script.Parent.Parent.Plot.PlotService)
	local SlotService = require(script.Parent.Parent.Plot.SlotService)
	local plotData = PlotService:GetPlayerPlotData(targetPlayer)
	if plotData and plotData.Slots and plotData.Slots[slotID] then
		local slotModel = plotData.Slots[slotID].Model
		if slotModel then
			SlotService:ClearSlotState(plotData, slotID, slotModel)
		end
	end

	local Server_CharacterStats = require(script.Parent.Parent.Systems.Server_CharacterStats)
	Server_CharacterStats:UpdateOverheadDisplay(targetPlayer)

	local Server_Inventory = require(script.Parent.Parent.Core.Server_Inventory)
	local ok, uid = Server_Inventory:AddItem(stealer, "Brainrot", configName, metadata)
	if not ok then
		warn("Server_Marketplace: ApplyStealBrainrot AddItem failed for stealer:", stealer.Name)
		return true
	end

	local Events = ReplicatedStorage:FindFirstChild("Events")
	local popup = Events and Events:FindFirstChild("Popup")
	if popup then
		popup:FireClient(stealer, "You stole a brainrot!", "success")
		if targetPlayer and targetPlayer.Parent then
			popup:FireClient(targetPlayer, "Your brainrot was stolen!", "error")
		end
	end
	return true
end

function Module:ProcessLuckyBlockPurchase(player: Player, data: any, productName: string)
	-- Determine lucky block type and quantity from product name
	local blockType = nil
	local quantity = 1
	
	-- Parse product name to determine block and quantity
	if productName == "LuckyBlock1" then
		blockType = "GodLuckyBlock"
		quantity = 1
	elseif productName == "LuckyBlock1_3x" then
		blockType = "GodLuckyBlock"
		quantity = 3
	elseif productName == "LuckyBlock2" then
		blockType = "MythicalPlusLuckyBlock"
		quantity = 1
	elseif productName == "LuckyBlock2_3x" then
		blockType = "MythicalPlusLuckyBlock"
		quantity = 3
	elseif productName == "LuckyBlock3" then
		blockType = "OPLuckyBlock"
		quantity = 1
	elseif productName == "LuckyBlock3_3x" then
		blockType = "OPLuckyBlock"
		quantity = 3
	end
	
	if not blockType then
		warn("⚠️ Server_Marketplace: Unknown lucky block product:", productName)
		return
	end
	
	-- Add lucky blocks to inventory
	local Server_Inventory = require(script.Parent.Parent.Core.Server_Inventory)
	local successCount = 0
	
	for i = 1, quantity do
		local success, result = Server_Inventory:AddItem(player, "LuckyBlock", blockType, nil)
		if success then
			successCount = successCount + 1
		else
			warn("⚠️ Failed to add lucky block:", blockType, "Error:", result)
		end
	end
	
	-- Send success notification to player
	if successCount > 0 then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events and Events:FindFirstChild("Popup") then
			local Shared_LuckyBlocks = require(ReplicatedStorage.Modules.ItemConfigs.Shared_LuckyBlocks)
			local displayName = Shared_LuckyBlocks.List[blockType].DisplayName or blockType
			local message = successCount > 1 
				and string.format("Purchased %dx %s!", successCount, displayName)
				or string.format("Purchased %s!", displayName)
			Events.Popup:FireClient(player, message, "success")
		end
	end
end

--// Gamepass Handler

function Module:GamepassPurchase(player: Player, data: any, passId: number, passName: string)
	if not player or not data or not passId or not passName then return end
	
	-- Update the gamepass value to true in player data
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	Server_Data:SetValue(player, "Passes." .. passName, true)
	
	-- Handle specific gamepass rewards/effects
	if passName == "VIP" then
		-- Set VIP attribute for chat tags (auto-replicates to client)
		player:SetAttribute("HasVIP", true)
		
		-- Upgrade slapper to VIP variant (no speed bonus)
		local Server_Slapper = require(script.Parent.Parent.Gameplay.Server_Slapper)
		Server_Slapper:RefreshSlapper(player)
		
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events and Events:FindFirstChild("Popup") then
			Events.Popup:FireClient(player, "VIP Activated!", true)
		end
	elseif passName == "CashBoost" then
		-- 2x Cash multiplier for brainrot income
		-- Update all billboards to show new income
		local BrainrotVisuals = require(script.Parent.Parent.Plot.BrainrotVisuals)
		BrainrotVisuals:UpdateAllBillboardsForPlayer(player)
		
		-- Update plot title to show new multiplier
		local PlotService = require(script.Parent.Parent.Plot.PlotService)
		PlotService:UpdatePlotPlayerInfo(player)
		
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events and Events:FindFirstChild("Popup") then
			Events.Popup:FireClient(player, "2x Cash Activated!", true)
		end
	elseif passName == "SpeedBoost" then
		-- 2x Speed multiplier (handled in Server_CharacterStats)
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events and Events:FindFirstChild("Popup") then
			Events.Popup:FireClient(player, "2x Speed Activated!", true)
		end
		
		-- Apply speed immediately
		local Server_CharacterStats = require(script.Parent.Server_CharacterStats)
		Server_CharacterStats:ApplyStats(player)
	elseif passName == "Tablet" or passName == "Sniper" then
		local Server_GamepassTools = require(script.Parent.Parent.Gameplay.Server_GamepassTools)
		Server_GamepassTools:RefreshGamepassTools(player)
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events and Events:FindFirstChild("Popup") then
			local msg = passName == "Tablet" and "Admin Tablet unlocked!" or "Sniper unlocked!"
			Events.Popup:FireClient(player, msg, true)
		end
	elseif passName == "QuickCollect" then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events and Events:FindFirstChild("Popup") then
			Events.Popup:FireClient(player, "Quick Collect activated!", true)
		end
	end
end

--// Gift gamepass: grant pass to target player (called from ProcessReceipt for *_Gift products)
--// Returns true on success, false on failure (caller should log Interrupted and return PurchaseGranted without re-logging Granted)
function Module:ProcessGiftGamepass(buyer: Player, productId: number, productName: string, context: any, buyerProfile: any, purchaseId: string): boolean
	local Events = ReplicatedStorage:FindFirstChild("Events")
	local popup = Events and Events:FindFirstChild("Popup")
	-- Resolve pass name from gift product name (e.g. VIP_Gift -> VIP)
	local passName = nil
	if Shared_Marketplace.GiftProductByPassName then
		for pn, productKey in pairs(Shared_Marketplace.GiftProductByPassName) do
			if productKey == productName then
				passName = pn
				break
			end
		end
	end
	if not passName or not self.Passes[passName] then
		logMarketplace(buyerProfile, purchaseId, "Interrupted", productId, "GiftInvalidPass")
		if popup then popup:FireClient(buyer, "Gift failed: invalid gamepass.", false) end
		return false
	end
	local targetUserId = context and context.TargetUserId
	if type(targetUserId) ~= "number" then
		logMarketplace(buyerProfile, purchaseId, "Interrupted", productId, "GiftNoTarget")
		if popup then popup:FireClient(buyer, "Gift failed: no recipient.", false) end
		return false
	end
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	local targetProfile = targetPlayer and getProfile(targetPlayer)
	local targetData = targetProfile and targetProfile.Data
	if not targetPlayer or not targetData then
		logMarketplace(buyerProfile, purchaseId, "Interrupted", productId, "GiftTargetUnavailable")
		if popup then popup:FireClient(buyer, "That player is no longer in the game.", false) end
		return false
	end
	if targetData.Passes and targetData.Passes[passName] then
		logMarketplace(buyerProfile, purchaseId, "Interrupted", productId, "GiftAlreadyOwned")
		if popup then popup:FireClient(buyer, "Player already owns this gamepass.", false) end
		return false
	end
	local passId = self.Passes[passName]
	if not passId then
		logMarketplace(buyerProfile, purchaseId, "Interrupted", productId, "GiftInvalidPass")
		if popup then popup:FireClient(buyer, "Gift failed.", false) end
		return false
	end
	-- Ensure target's Passes table exists and set the pass so their gamepass is actually granted
	if not targetData.Passes then
		targetData.Passes = {}
	end
	targetData.Passes[passName] = true
	self:GamepassPurchase(targetPlayer, targetData, passId, passName)
	if popup then
		popup:FireClient(targetPlayer, "You received a gifted gamepass!", true)
		popup:FireClient(buyer, "Your gift was sent!", true)
	end
	return true
end

--// ProcessReceipt - CRITICAL SECURITY
-- This is the ONLY secure way to handle DevProduct purchases
-- It validates receipts with Roblox servers and cannot be spoofed by exploiters

function Module:SetupProcessReceipt()
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		-- Get player from receipt
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			-- Player left before receipt processed - retry later
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		
		-- Get player profile and data
		local profile = getProfile(player)
		if not profile then
			-- Profile not loaded - retry later
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		
		local data = profile.Data
		if not data then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		
		-- Get purchase details
		local purchaseId = receiptInfo.PurchaseId
		local productId = receiptInfo.ProductId
		local logs = data.MarketplaceLogs
		
		-- Check if this receipt was already processed (duplicate prevention)
		if logs[purchaseId] then
			local status = logs[purchaseId].Status
			if status == "Granted" or status == "Interrupted" then
				-- Already processed, return success to Roblox
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
		end
		
		-- Check for duplicate receipt in memory cache
		local receiptKey = purchaseId or (tostring(player.UserId) .. "_" .. tostring(productId) .. "_" .. tostring(os.time()))
		if self.ProcessedReceipts[receiptKey] then
			warn("Server_Marketplace: Duplicate receipt detected - already processed. Receipt:", receiptKey, "Player:", player.Name)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		
		-- Mark receipt as processed in memory
		self.ProcessedReceipts[receiptKey] = true
		
		-- Get product name from ID
		local productName = getProductName(productId)
		if not productName then
			-- Unknown product - log and grant to avoid charging player
			logMarketplace(profile, purchaseId, "Interrupted", productId, "UnknownProduct")
			warn("Server_Marketplace: Unknown product ID:", productId, "for player:", player.Name)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		
		-- Get purchase context (if available)
		local context = nil
		if self.PurchaseContexts[player.UserId] then
			context = self.PurchaseContexts[player.UserId][productId]
		end
		
		-- Process the purchase based on product type
		-- Route to appropriate handler (gift products MUST be checked first so they are not matched by find("Cash") / find("Speed"))
		if productName == "VIP_Gift" or productName == "CashBoost_Gift" or productName == "SpeedBoost_Gift" or productName == "Sniper_Gift" or productName == "Tablet_Gift" or productName == "QuickCollect_Gift" then
			local giftOk = self:ProcessGiftGamepass(player, productId, productName, context, profile, purchaseId)
			if not giftOk then
				if self.PurchaseContexts[player.UserId] then
					self.PurchaseContexts[player.UserId][productId] = nil
				end
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
		elseif productName:find("Cash") then
			self:ProcessCashPurchase(player, data, productName)
		elseif productName:find("Speed") then
			self:ProcessSpeedPurchase(player, data, productName)
		elseif productName:find("LuckyBlock") then
			self:ProcessLuckyBlockPurchase(player, data, productName)
		elseif productName == "OfflineBoost10x" then
			self:ProcessOfflineBoost10x(player, data, productName)
		elseif productName == "Skip Rebirth" then
			self:ProcessSkipRebirth(player, data, productName)
		elseif productName == "ForceGreenLight" then
			self:ProcessForceGreenLight(player, data, productName)
		elseif productName and (productName == "Upgrade Brainrot 1" or productName == "Upgrade Brainrot 2" or productName == "Upgrade Brainrot 3" or productName == "Upgrade Brainrot 4" or productName == "Upgrade Brainrot 5") then
			self:ProcessUpgradeBrainrotPurchase(player, data, productName, context)
		elseif productName and productName:match("^Steal a Brainrot ") then
			self:ProcessStealBrainrotPurchase(player, data, productName, context)
		elseif productName == "Teleport Home" then
			self:ProcessTeleportHome(player)
		elseif productName == "Starter Pack" then
			-- Re-validate: not already purchased, within 2h window
			if data.StarterPackPurchased then
				warn("Server_Marketplace: Starter Pack receipt but already purchased. Player:", player.Name)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			local playTime = data.StarterPackPlayTime or 0
			local duration = Shared_Marketplace.STARTER_PACK_DURATION_SEC or 7200
			if playTime >= duration then
				warn("Server_Marketplace: Starter Pack receipt after expiry. Player:", player.Name)
				return Enum.ProductPurchaseDecision.NotProcessed
			end
			self:ProcessStarterPack(player, data)
		else
			warn("Server_Marketplace: No handler for product:", productName)
		end
		
		-- Log successful purchase
		logMarketplace(profile, purchaseId, "Granted", productId, nil)
		
		-- Track Robux spent for leaderboard (async to avoid blocking receipt processing)
		task.spawn(function()
			local success, productInfo = pcall(function()
				return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
			end)
			
			if success and productInfo and productInfo.PriceInRobux then
				local Server_Data = require(script.Parent.Parent.Core.Server_Data)
				local currentRobuxSpent = Server_Data:GetValue(player, "RobuxSpent") or 0
				Server_Data:SetValue(player, "RobuxSpent", currentRobuxSpent + productInfo.PriceInRobux)
			end
		end)
		
		-- Clear purchase context
		if self.PurchaseContexts[player.UserId] then
			self.PurchaseContexts[player.UserId][productId] = nil
		end
		
		-- Return success to Roblox
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

--// Cleanup Functions

function Module:CleanupPlayerContexts(player: Player)
	-- Clean up all purchase contexts for a player when they leave
	-- Prevents memory leaks and stale contexts
	if self.PurchaseContexts[player.UserId] then
		self.PurchaseContexts[player.UserId] = nil
	end
end

--[[
	Check and grant gamepass ownership on player join
	(In case player bought gamepass outside the game or before joining)
	SYNCHRONOUS - called directly from Init, no spawning/waiting
]]
function Module:CheckGamepassOwnership(player: Player)
	local data = getData(player)
	if not data then 
		warn("⚠️ Server_Marketplace: No data for ownership check:", player.Name)
		return 
	end
	
	-- Check each gamepass SYNCHRONOUSLY (like SingingX)
	for passName, passId in pairs(self.Passes) do
		if passId and passId > 0 then
			local success, ownsPass = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
			end)
			
			if success and ownsPass then
				-- Player owns this gamepass - check if not already granted
				if not data.Passes[passName] then
					-- Grant gamepass and call purchase handler (like SingingX line 797)
					self:GamepassPurchase(player, data, passId, passName)
				else
					-- Already owned, just ensure it's set to true
					local Server_Data = require(script.Parent.Parent.Core.Server_Data)
					Server_Data:SetValue(player, "Passes." .. passName, true)
					
					-- Set VIP attribute for chat tags if this is VIP pass
					if passName == "VIP" then
						player:SetAttribute("HasVIP", true)
					end
				end
			end
		end
	end
end

--// Initialization

-- Track when players first prompted group join (no longer needed with new system)
-- local GroupPromptTimestamps = {} -- [player] = timestamp

--[[
	Check and auto-grant group reward on player join
	Called from Server_Data after profile loads
]]
function Module:CheckAndGrantGroupReward(player: Player)
	local GROUP_ID = 1082816729
	
	-- Get player data
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	local profile = Server_Data:GetProfile(player)
	if not profile then return end
	
	-- Check if reward already claimed
	if profile.Data.GroupJoinRewardClaimed then return end
	
	-- Check if player is in the group
	local isInGroup = false
	local success, result = pcall(function()
		return player:IsInGroup(GROUP_ID)
	end)
	
	if success then
		isInGroup = result
	else
		warn("⚠️ Failed to check group membership for", player.Name, ":", result)
		return
	end
	
	-- If in group, auto-grant reward
	if isInGroup then
		-- Small delay to ensure inventory system is ready
		task.wait(0.5)
		self:GrantGroupJoinReward(player)
	end
end

--[[
	Handle group join prompt and reward
	Prompts player to join group via client-side GroupService
	Grants reward immediately upon successful join
]]
function Module:HandleGroupJoinPrompt(player: Player)
	local GROUP_ID = 1082816729
	
	-- Get player data
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	local profile = Server_Data:GetProfile(player)
	if not profile then
		warn("⚠️ No profile for group join check:", player.Name)
		return
	end
	
	-- Check if reward already claimed
	if profile.Data.GroupJoinRewardClaimed then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local popupEvent = Events and Events:FindFirstChild("Popup")
		if popupEvent then
			popupEvent:FireClient(player, "You've already claimed the group reward!", "info")
		end
		return
	end
	
	-- Check if player is already in the group
	local isInGroup = false
	local success, result = pcall(function()
		return player:IsInGroup(GROUP_ID)
	end)
	
	if success then
		isInGroup = result
	else
		warn("⚠️ Failed to check group membership for", player.Name, ":", result)
		return
	end
	
	if isInGroup then
		-- Player is already in group, grant reward immediately
		self:GrantGroupJoinReward(player)
	else
		-- Player not in group, prompt to join via client
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local groupHandler = Events and Events:FindFirstChild("GroupHandler")
		if groupHandler then
			groupHandler:FireClient(player, "Prompt", GROUP_ID)
		else
			warn("⚠️ GroupHandler event not found; cannot prompt group join for", player.Name)
		end
	end
end

--[[
	Grant group join reward (sixtysevenluckyblock)
	Only called once per player
]]
function Module:GrantGroupJoinReward(player: Player)
	local REWARD_LUCKY_BLOCK = "SixtySevenLuckyBlock"
	
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	local Server_Inventory = require(script.Parent.Parent.Core.Server_Inventory)
	local profile = Server_Data:GetProfile(player)
	
	if not profile then return end
	
	-- Double-check not already claimed
	if profile.Data.GroupJoinRewardClaimed then return end
	
	-- Mark as claimed
	Server_Data:SetValue(player, "GroupJoinRewardClaimed", true)
	
	-- Add lucky block to inventory
	Server_Inventory:AddItem(player, "LuckyBlock", REWARD_LUCKY_BLOCK, {})
	
	-- Show success popup
	local Events = ReplicatedStorage:FindFirstChild("Events")
	local popupEvent = Events and Events:FindFirstChild("Popup")
	if popupEvent then
		popupEvent:FireClient(player, "Group reward claimed! Check your inventory!", "success")
	end
end

--[[
	Setup ShopTag proximity prompts
	Connects ProximityPrompt.Triggered to marketplace handlers
	Supports tagging either the parent part/model OR the ProximityPrompt itself
]]
local function setupShopPrompt(taggedInstance)
	local prompt
	
	-- Check if the tagged instance IS a ProximityPrompt
	if taggedInstance:IsA("ProximityPrompt") then
		prompt = taggedInstance
	else
		-- Tagged instance is a part/model, find ProximityPrompt child
		prompt = taggedInstance:FindFirstChildOfClass("ProximityPrompt")
	end
	
	if not prompt then
		warn("ShopTag object missing ProximityPrompt:", taggedInstance:GetFullName())
		return
	end
	
	-- Always read attributes from the tagged object itself
	local productId = taggedInstance:GetAttribute("ProductID")
	local uiType = taggedInstance:GetAttribute("UIType")
	
	if not productId and not uiType then
		warn("ShopTag object missing ProductID or UIType attribute:", taggedInstance:GetFullName())
		return
	end
	
	prompt.Triggered:Connect(function(player)
		if not player or not player:IsA("Player") then return end
		
		if productId then
			-- Validate product exists
			local productName = getProductName(productId)
			if not productName then
				productName = getPassName(productId)
			end
			
			if not productName then
				warn("ShopTag ProductID not found in Shared_Marketplace:", productId)
				return
			end
			
			-- Fire to client so it can show purchase effects before prompting
			local Events = ReplicatedStorage:FindFirstChild("Events")
			local purchaseHandler = Events and Events:FindFirstChild("PurchaseHandler")
			if purchaseHandler then
				purchaseHandler:FireClient(player, productId, nil)
			end
			
		elseif uiType then
			-- Handle GroupJoin UIType
			if uiType == "GroupJoin" then
				Module:HandleGroupJoinPrompt(player)
			else
				if uiType == "SpeedUpgrades" or uiType == "SpeedStore" then
					uiType = "Baloons"
				end
				-- Fire ProximityHandler event to client for other UITypes
				local Events = ReplicatedStorage:FindFirstChild("Events")
				local proximityHandler = Events and Events:FindFirstChild("ProximityHandler")
				if proximityHandler then
					proximityHandler:FireClient(player, uiType)
				end
			end
		end
	end)
end

function Module:Init()
	-- Set up ProcessReceipt handler (CRITICAL)
	self:SetupProcessReceipt()
	
	-- NOTE: CheckGamepassOwnership is NOT called here
	-- It should be called from Server_Data after profile loads (like SingingX)
	-- If you need to call it for existing players on hot reload:
	-- for _, player in ipairs(Players:GetPlayers()) do
	--     self:CheckGamepassOwnership(player)
	-- end
	
	-- Clean up purchase contexts when players leave
	Players.PlayerRemoving:Connect(function(player)
		self:CleanupPlayerContexts(player)
	end)
	
	-- Handle purchase requests from client
	local Events = ReplicatedStorage:FindFirstChild("Events")
	if Events then
		local PurchaseEvent = Events:FindFirstChild("PurchaseHandler")
		if PurchaseEvent then
			PurchaseEvent.OnServerEvent:Connect(function(player, productId, purchaseContext)
				-- Option B: Steal request (client sends context only; server resolves productId)
				if type(purchaseContext) == "table" and purchaseContext.type == "StealBrainrot" then
					self:HandleStealBrainrotRequest(player, purchaseContext)
					return
				end

				-- Validate product ID
				local productName = getProductName(productId)
				if not productName then
					warn("Server_Marketplace: Invalid product ID from client:", productId, "Player:", player.Name)
					return
				end

				-- Gift gamepass: validate target before prompting purchase
				if type(purchaseContext) == "table" and purchaseContext.type == "GiftGamepass" then
					local targetUserId = purchaseContext.TargetUserId
					local passName = purchaseContext.PassName
					if type(targetUserId) ~= "number" or type(passName) ~= "string" or passName == "" then
						local popup = Events:FindFirstChild("Popup")
						if popup then popup:FireClient(player, "Invalid gift request.", false) end
						return
					end
					if targetUserId == player.UserId then
						local popup = Events:FindFirstChild("Popup")
						if popup then popup:FireClient(player, "You cannot gift yourself.", false) end
						return
					end
					local targetPlayer = Players:GetPlayerByUserId(targetUserId)
					if not targetPlayer then
						local popup = Events:FindFirstChild("Popup")
						if popup then popup:FireClient(player, "That player is no longer in the game.", false) end
						return
					end
					local targetProfile = getProfile(targetPlayer)
					local targetData = targetProfile and targetProfile.Data
					if not targetData then
						local popup = Events:FindFirstChild("Popup")
						if popup then popup:FireClient(player, "That player's data is not ready.", false) end
						return
					end
					if targetData.Passes and targetData.Passes[passName] then
						local popup = Events:FindFirstChild("Popup")
						if popup then popup:FireClient(player, "Player already owns this gamepass.", false) end
						return
					end
					-- Product must be the gift product for this pass
					local giftKey = Shared_Marketplace.GiftProductByPassName and Shared_Marketplace.GiftProductByPassName[passName]
					local expectedId = giftKey and Module.Products[giftKey]
					if expectedId ~= productId then
						local popup = Events:FindFirstChild("Popup")
						if popup then popup:FireClient(player, "Invalid gift product.", false) end
						return
					end
				end

				-- Starter Pack: validate before prompting (not purchased, within 2h)
				if productName == "Starter Pack" then
					local data = getData(player)
					if not data then
						local popup = Events:FindFirstChild("Popup")
						if popup then popup:FireClient(player, "Data not ready.", false) end
						return
					end
					if data.StarterPackPurchased then
						local popup = Events:FindFirstChild("Popup")
						if popup then popup:FireClient(player, "You already purchased the Starter Pack.", false) end
						return
					end
					local playTime = data.StarterPackPlayTime or 0
					local duration = Shared_Marketplace.STARTER_PACK_DURATION_SEC or 7200
					if playTime >= duration then
						local popup = Events:FindFirstChild("Popup")
						if popup then popup:FireClient(player, "Starter Pack offer has expired.", false) end
						return
					end
					purchaseContext = { type = "StarterPack" }
				end

				-- Store purchase context (if provided)
				if purchaseContext then
					if not self.PurchaseContexts[player.UserId] then
						self.PurchaseContexts[player.UserId] = {}
					end
					self.PurchaseContexts[player.UserId][productId] = purchaseContext
				end

				-- Option A: Fire to client so it shows rainbow and prompts (single canonical flow)
				local purchaseHandler = Events:FindFirstChild("PurchaseHandler")
				if purchaseHandler then
					purchaseHandler:FireClient(player, productId, purchaseContext)
				end
			end)
		end
	end
	
	-- Handle group join result from client
	local GroupHandler = Events:FindFirstChild("GroupHandler")
	if GroupHandler then
		GroupHandler.OnServerEvent:Connect(function(player, action, ...)
			if action == "JoinResult" then
				local groupId, joinStatus = ...
				
				-- Validate inputs
				if type(groupId) ~= "number" or type(joinStatus) ~= "userdata" then
					return
				end
				
				-- Only process if this is the correct group
				local GROUP_ID = 1082816729
				if groupId ~= GROUP_ID then
					return
				end
				
				-- Check if player joined successfully
				if joinStatus == Enum.GroupMembershipStatus.Joined then
					-- Grant reward immediately
					Module:GrantGroupJoinReward(player)
				elseif joinStatus == Enum.GroupMembershipStatus.AlreadyMember then
					-- Already member, grant reward
					Module:GrantGroupJoinReward(player)
				else
					-- Didn't join (declined, pending, or not eligible)
					local popupEvent = Events:FindFirstChild("Popup")
					if popupEvent then
						local message = "Join our group to claim your reward!"
						if joinStatus == Enum.GroupMembershipStatus.JoinRequestPending then
							message = "Group join request sent! Once approved, come back to claim your reward."
						end
						popupEvent:FireClient(player, message, "info")
					end
				end
			end
		end)
	end

	-- PurchasePassOwnership: client passes passName, server returns { [userId] = true } for players who own that pass
	local PurchasePassOwnership = Events:FindFirstChild("PurchasePassOwnership")
	if PurchasePassOwnership and PurchasePassOwnership:IsA("RemoteFunction") then
		PurchasePassOwnership.OnServerInvoke = function(player: Player, passName: string)
			if type(passName) ~= "string" or passName == "" then return {} end
			if not self.Passes[passName] then return {} end
			local result = {}
			for _, other in ipairs(Players:GetPlayers()) do
				local data = getData(other)
				if data and data.Passes and data.Passes[passName] then
					result[other.UserId] = true
				end
			end
			return result
		end
	end
	
	-- Handle gamepass purchase completion
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then return end
		
		local data = getData(player)
		if not data then return end
		
		-- Get gamepass name
		local passName = getPassName(passId)
		if not passName then return end
		
		-- CRITICAL SECURITY: Verify ownership with Roblox servers
		-- PromptGamePassPurchaseFinished can be spoofed by exploiters!
		local success, ownsPass = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		
		if success and ownsPass then
			-- Check if not already granted (prevent duplicates)
			if not data.Passes[passName] then
				self:GamepassPurchase(player, data, passId, passName)
				
				-- Track Robux spent for leaderboard (async to avoid blocking)
				task.spawn(function()
					local passSuccess, passInfo = pcall(function()
						return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
					end)
					
					if passSuccess and passInfo and passInfo.PriceInRobux then
						local Server_Data = require(script.Parent.Parent.Core.Server_Data)
						local currentRobuxSpent = Server_Data:GetValue(player, "RobuxSpent") or 0
						Server_Data:SetValue(player, "RobuxSpent", currentRobuxSpent + passInfo.PriceInRobux)
					end
				end)
				
			end
		else
			-- Security violation: Player tried to fake purchase
			warn("SECURITY: Player " .. player.Name .. " attempted to spoof gamepass purchase:", passName, "ID:", passId)
		end
	end)
	
	-- Handle offline earnings claims
	local offlineHandler = Events:FindFirstChild("OfflineHandler")
	if offlineHandler then
		offlineHandler.OnServerEvent:Connect(function(player, claimType)
			if not player or not claimType then return end
			
			local data = getData(player)
			if not data then return end
			
			if claimType == "Free" then
				-- Handle free claim through CashSystem
				local CashSystem = require(script.Parent.Parent.Plot.CashSystem)
				CashSystem:ClaimOfflineEarnings(player, "Free")
				
			elseif claimType == "10x" then
				-- Validate pending earnings exist
				local pendingOffline = data.PendingOfflineEarnings or 0
				if pendingOffline <= 0 then
					warn("⚠️ No pending offline earnings for " .. player.Name)
					return
				end
				
				-- Option A: Fire to client so it shows rainbow and prompts (single canonical flow)
				local productId = self.Products["OfflineBoost10x"]
				if productId and productId > 0 then
					local purchaseHandler = Events:FindFirstChild("PurchaseHandler")
					if purchaseHandler then
						purchaseHandler:FireClient(player, productId, nil)
					end
				else
					warn("Server_Marketplace: OfflineBoost10x product ID not configured")
				end
			end
		end)
	end
	
	-- Setup ShopTag proximity prompts
	for _, instance in ipairs(CollectionService:GetTagged("ShopTag")) do
		task.spawn(setupShopPrompt, instance)
	end
	CollectionService:GetInstanceAddedSignal("ShopTag"):Connect(setupShopPrompt)
	
	print("✓ Server_Marketplace initialized")
end

return Module
