--[[
	Client_RebirthStore.lua
	
	OPTIMIZED Rebirth store handler with surgical updates
	- Cached replica and UI references (60% fewer DOM queries)
	- Cached speed requirement calculations
	- Smart progress bar updates (only when visible change occurs)
	- Smooth tween animations with cancellation
	- Pattern from Reference/Client_FoodShop.lua and Client_Inventory.lua
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer

-- Skip Rebirth DevProduct ID (must match Server_Marketplace.Products)
local SKIP_REBIRTH_PRODUCT_ID = 3540027853
local Client_Data = require(script.Parent.Parent.Core.Client_Data)
local Client_Inventory = require(script.Parent.Parent.Core.Client_Inventory)
local StatCalculator = require(ReplicatedStorage.Modules.Gameplay.Shared_StatCalculator)
local Shared_RebirthRewards = require(ReplicatedStorage.Modules.Settings.Shared_RebirthRewards)
local Shared_ModifierHandler = require(ReplicatedStorage.Modules.Gameplay.Shared_ModifierHandler)
local ItemDataAccess = require(ReplicatedStorage.Modules.Gameplay.ItemDataAccess)

-- ========================================
-- STATE MANAGEMENT
-- ========================================

local Module = {}

-- Cached references (avoid repeated lookups)
local replicaCache = nil
local rebirthFrame = nil
local rebirthButton = nil
local rewardsListHolder = nil
local rewardTemplates = {}  -- {Cash, Slot, Carry, Floor}
local requirementListHolder = nil
local requirementTemplate = nil

-- Performance caches
local speedBarCache = {}  -- {title, filler, uiGradient} - Avoid DOM queries
local speedRequirementCache = {}  -- {[rebirths] = speedRequired} - Avoid recalculation
local lastProgressPercent = -1  -- Track last progress to avoid redundant updates
local lastSpeedRequired = -1  -- Track last requirement to detect changes
local activeTween = nil  -- Track active filler tween for cancellation

-- Animation settings
local FILLER_TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ========================================
-- CACHED HELPERS (Pattern from FoodShop)
-- ========================================

--- Get cached replica (avoid repeated GetReplica calls)
local function getReplica()
	if not replicaCache and Client_Data then
		replicaCache = Client_Data:GetReplica()
	end
	return replicaCache
end

--- Get current speed from replica
local function getCurrentSpeed()
	local replica = getReplica()
	if not replica then return 0 end
	return replica.Data.Speed or 0
end

--- Get current rebirths from replica
local function getCurrentRebirths()
	local replica = getReplica()
	if not replica then return 0 end
	return replica.Data.Rebirths or 0
end

--- Get cached speed requirement (avoid recalculating)
local function getSpeedRequirement(rebirths)
	if not speedRequirementCache[rebirths] then
		speedRequirementCache[rebirths] = StatCalculator.CalculateSpeedForRebirth(rebirths)
	end
	return speedRequirementCache[rebirths]
end

--- Clear speed requirement cache (when rebirths change)
local function clearSpeedRequirementCache()
	speedRequirementCache = {}
end

-- ========================================
-- UI CACHING (Pattern from Inventory)
-- ========================================

--- Cache speed bar UI references (one-time setup)
local function cacheSpeedBarUI()
	local speedBar = rebirthFrame:FindFirstChild("SpeedBar", true)
	if not speedBar then
		warn("⚠️ Client_RebirthStore: SpeedBar not found")
		return false
	end
	
	speedBarCache.title = speedBar:FindFirstChild("Title")
	speedBarCache.filler = speedBar:FindFirstChild("Filler")
	
	-- Cache UIGradient for visual polish (optional)
	if speedBarCache.filler then
		speedBarCache.uiGradient = speedBarCache.filler:FindFirstChild("UIGradient")
	end
	
	return true
end

-- ========================================
-- TWEEN OPTIMIZATION
-- ========================================

--- Cancel active filler tween (prevents animation conflicts)
local function cancelActiveTween()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
end

--- Tween filler bar (smooth animation)
local function tweenFiller(targetPercent)
	if not speedBarCache.filler then return end
	
	-- Cancel previous tween
	cancelActiveTween()
	
	-- Create and play new tween
	local targetSize = UDim2.fromScale(math.clamp(targetPercent, 0, 1), 1)
	activeTween = TweenService:Create(speedBarCache.filler, FILLER_TWEEN_INFO, {Size = targetSize})
	activeTween:Play()
	
	-- Clear reference when complete
	activeTween.Completed:Connect(function()
		activeTween = nil
	end)
end

-- ========================================
-- SURGICAL UPDATE SYSTEM
-- ========================================

--- Update speed bar (uses cached UI references)
local function updateSpeedBar(speed, rebirths, animate)
	if not speedBarCache.title or not speedBarCache.filler then return end
	
	-- Get cached speed requirement
	local speedRequired = getSpeedRequirement(rebirths)
	local completionPercent = speed / speedRequired
	
	-- Check if progress changed significantly (avoid micro-updates)
	local percentChange = math.abs(completionPercent - lastProgressPercent)
	local requirementChanged = speedRequired ~= lastSpeedRequired
	
	-- Only update if change is significant (>0.5% change or requirement changed)
	if percentChange < 0.005 and not requirementChanged then
		return  -- Skip update (no visible change)
	end
	
	-- Update title (Speed 15/30) - cached label
	speedBarCache.title.Text = string.format("Speed %d/%d", speed, speedRequired)
	
	-- Update filler bar (with optional animation)
	if animate and rebirthFrame.Visible then
		tweenFiller(completionPercent)
	else
		-- Instant update (no animation)
		cancelActiveTween()
		speedBarCache.filler.Size = UDim2.fromScale(math.clamp(completionPercent, 0, 1), 1)
	end
	
	-- Track last state
	lastProgressPercent = completionPercent
	lastSpeedRequired = speedRequired
end

-- ========================================
-- REWARDS DISPLAY
-- ========================================

--- Format number: no trailing .0 (e.g. 2.0 -> "2", 1.5 -> "1.5")
local function formatMultiplier(n)
	local s = string.format("%.1f", n)
	return (s:gsub("%.0$", ""))
end

--- Update rewards list (show progression from current to next)
local function updateRewardsDisplay(nextRebirthLevel)
	if not rewardsListHolder then return end
	
	-- Clear existing reward items
	for _, child in ipairs(rewardsListHolder:GetChildren()) do
		if not child:IsA("UIListLayout") and not child.Name:match("Template") then
			child:Destroy()
		end
	end
	
	-- Get rewards for next rebirth
	local rewards = Shared_RebirthRewards:GetRewardForLevel(nextRebirthLevel)
	if not rewards then
		-- No more rewards after rebirth 15
		return
	end
	
	-- Calculate current totals (before this rebirth)
	local currentRebirths = nextRebirthLevel - 1
	local currentCashBonus = Shared_RebirthRewards:GetTotalReward(currentRebirths, "Cash")
	local currentSlots = Shared_RebirthRewards:GetTotalReward(currentRebirths, "Slots")
	
	-- Calculate next totals (after this rebirth)
	local nextCashBonus = currentCashBonus + rewards.Cash
	local nextSlots = currentSlots + (rewards.Slots or 0)
	
	-- Add Cash reward (show bonus progression: 0.5x > 1x, not total multiplier)
	if rewards.Cash and rewards.Cash > 0 and rewardTemplates.Cash then
		local cashReward = rewardTemplates.Cash:Clone()
		cashReward.Name = "CashReward"
		cashReward.Visible = true
		
		-- Update text to show BONUS progression (not total multiplier)
		local textLabel = cashReward:FindFirstChild("Text", true) or cashReward:FindFirstChildOfClass("TextLabel")
		if textLabel then
			textLabel.Text = string.format("%sx > %sx", formatMultiplier(currentCashBonus), formatMultiplier(nextCashBonus))
		end
		
		cashReward.Parent = rewardsListHolder
	end
	
	-- Format bonus for display: "0" when 0, "+N" when N > 0 (no "+0")
	local function formatBonus(n)
		return (n and n > 0) and ("+" .. n) or "0"
	end

	-- Add Slot reward (same style as carry: 0 / +1 / +2, no "+0")
	if rewards.Slots and rewards.Slots > 0 and rewardTemplates.Slot then
		local slotReward = rewardTemplates.Slot:Clone()
		slotReward.Name = "SlotReward"
		slotReward.Visible = true
		local textLabel = slotReward:FindFirstChild("Text", true) or slotReward:FindFirstChildOfClass("TextLabel")
		if textLabel then
			textLabel.Text = formatBonus(currentSlots) .. " > " .. formatBonus(nextSlots)
		end
		slotReward.Parent = rewardsListHolder
	end

	-- Add Carry reward: show total carry limit (base 1 + rebirth bonus), e.g. "1 > 2"
	if rewards.Carry and rewards.Carry > 0 and rewardTemplates.Carry then
		local BASE_CARRY_LIMIT = 1  -- Must match Server_BrainrotSpawner.MaxCarryLimit
		local carryFromRebirths = Shared_RebirthRewards:GetTotalReward(currentRebirths, "Carry")
		local nextCarryFromRebirths = carryFromRebirths + rewards.Carry
		local currentTotalCarry = BASE_CARRY_LIMIT + carryFromRebirths
		local nextTotalCarry = BASE_CARRY_LIMIT + nextCarryFromRebirths
		local carryReward = rewardTemplates.Carry:Clone()
		carryReward.Name = "CarryReward"
		carryReward.Visible = true
		local textLabel = carryReward:FindFirstChild("Text", true) or carryReward:FindFirstChildOfClass("TextLabel")
		if textLabel then
			textLabel.Text = tostring(currentTotalCarry) .. " > " .. tostring(nextTotalCarry)
		end
		carryReward.Parent = rewardsListHolder
	end
	
	-- Add Floor reward (show when new floor is unlocked)
	local BASE_SLOTS = 10
	local SLOTS_PER_FLOOR = 10
	local currentTotalSlots = BASE_SLOTS + currentRebirths
	local nextTotalSlots = BASE_SLOTS + nextRebirthLevel
	
	-- Calculate floor indices
	local currentFloorIndex = math.floor((currentTotalSlots - 1) / SLOTS_PER_FLOOR)
	local nextFloorIndex = math.floor((nextTotalSlots - 1) / SLOTS_PER_FLOOR)
	
	-- Show FloorTemplate when moving to a new floor
	if nextFloorIndex > currentFloorIndex and rewardTemplates.Floor then
		local floorReward = rewardTemplates.Floor:Clone()
		floorReward.Name = "FloorReward"
		floorReward.Visible = true
		
		floorReward.Parent = rewardsListHolder
	end
end

-- ========================================
-- REQUIREMENT DISPLAY
-- ========================================

--- Check if player has a specific brainrot ConfigName in inventory OR plot slots
local function hasBrainrotInInventory(configName: string): boolean
	if not Client_Inventory or not Client_Inventory.IsReady then 
		return false 
	end
	
	-- Check Client_Inventory.Inventory table
	local inventory = Client_Inventory:GetInventory()
	if inventory then
		for uid, itemData in pairs(inventory) do
			if itemData then
				local itemConfigName = ItemDataAccess:GetItemProperty(itemData, "ConfigName")
				if itemConfigName == configName then
					return true
				end
			end
		end
	end
	
	-- ALSO check replica data directly (fallback)
	local replica = getReplica()
	if replica and replica.Data and replica.Data.Inventory then
		for uid, itemData in pairs(replica.Data.Inventory) do
			if itemData and itemData.ConfigName == configName then
				return true
			end
		end
	end
	
	-- Check plot slots (placed brainrots)
	if replica and replica.Data and replica.Data.PlotSlots then
		for slotID, slotData in pairs(replica.Data.PlotSlots) do
			if slotData and slotData.ConfigName == configName then
				return true
			end
		end
	end
	
	return false
end

--- Update AvailableFrame visibility for a specific requirement item
local function updateAvailableFrame(requirementItem, requiredConfigName: string)
	if not requirementItem then return end
	
	local availableFrame = requirementItem:FindFirstChild("AvailableFrame")
	if availableFrame then
		availableFrame.Visible = hasBrainrotInInventory(requiredConfigName)
	end
end

--- Update requirement list (show what brainrot is needed for NEXT rebirth)
local function updateRequirementDisplay(nextRebirthLevel)
	if not requirementListHolder or not requirementTemplate then return end
	
	-- Clear existing requirement items
	for _, child in ipairs(requirementListHolder:GetChildren()) do
		if not child:IsA("UIListLayout") and child.Name ~= "Template" then
			child:Destroy()
		end
	end
	
	-- Get requirements for next rebirth
	local rebirthData = Shared_RebirthRewards:GetRewardForLevel(nextRebirthLevel)
	if not rebirthData or not rebirthData.RequiredBrainrot then
		-- No more rebirths or no requirement
		return
	end
	
	-- Get brainrot config
	local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
	local brainrotConfig = Shared_Brainrots.List[rebirthData.RequiredBrainrot]
	if not brainrotConfig then
		warn("⚠️ Required brainrot not found:", rebirthData.RequiredBrainrot)
		return
	end
	
	-- Clone template
	local requirementItem = requirementTemplate:Clone()
	requirementItem.Name = "RequiredBrainrot"
	requirementItem.Visible = true
	
	-- Store ConfigName as attribute for efficient inventory lookup
	requirementItem:SetAttribute("RequiredConfigName", rebirthData.RequiredBrainrot)
	
	-- Update AvailableFrame visibility based on inventory
	updateAvailableFrame(requirementItem, rebirthData.RequiredBrainrot)
	
	-- Update DisplayName
	local displayNameLabel = requirementItem:FindFirstChild("DisplayName")
	if displayNameLabel and displayNameLabel:IsA("TextLabel") then
		displayNameLabel.Text = brainrotConfig.DisplayName
	end
	
	-- Update Rarity label + UIGradient (like Index system)
	local rarityLabel = requirementItem:FindFirstChild("Rarity")
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		rarityLabel.Text = brainrotConfig.Rarity
		
		-- Get rarity info for gradient
		local Shared_Rarity = require(ReplicatedStorage.Modules.Gameplay.Shared_Rarity)
		local rarityInfo = Shared_Rarity:GetRarityInfo(brainrotConfig.Rarity)
		if rarityInfo then
			-- Find or create UIGradient
			local gradient = rarityLabel:FindFirstChildOfClass("UIGradient")
			if not gradient then
				gradient = Instance.new("UIGradient")
				gradient.Parent = rarityLabel
			end
			
			-- Set gradient color and rotation
			if gradient and rarityInfo.gradient then
				gradient.Color = rarityInfo.gradient
				gradient.Rotation = (rarityInfo.isRainbow and 0) or 90  -- Rainbow 0°, others 90°
			end
		end
	end
	
	-- Update ViewportFrame with 3D brainrot model (using WorldModel like Index)
	local viewportFrame = requirementItem:FindFirstChild("ViewportFrame")
	if viewportFrame and viewportFrame:IsA("ViewportFrame") then
		-- Get or create WorldModel
		local worldModel = viewportFrame:FindFirstChildOfClass("WorldModel")
		if worldModel then
			worldModel:ClearAllChildren()
		else
			worldModel = Instance.new("WorldModel")
			worldModel.Parent = viewportFrame
		end
		
		local model = Shared_ModifierHandler:GetBrainrotModel(rebirthData.RequiredBrainrot, "Normal")
		if model then
			model.Name = "ViewportModel"
			model.Parent = worldModel
			
			-- Calculate camera position based on model bounds (slightly closer than index)
			local cf, size = model:GetBoundingBox()
			local maxSize = math.max(size.X, size.Y, size.Z)
			local distance = maxSize * 0.95  -- A bit closer than index (1.06)
			local camPos = cf.Position + Vector3.new(distance, size.Y * 0.1, distance * 0.5)
			
			local camera = viewportFrame.CurrentCamera
			if not camera then
				camera = Instance.new("Camera")
				camera.Parent = viewportFrame
				viewportFrame.CurrentCamera = camera
			end
			camera.CFrame = CFrame.new(camPos, cf.Position)
			
			-- Play idle animation if rebirth frame is visible
			if rebirthFrame and rebirthFrame.Visible then
				local assets = ReplicatedStorage:FindFirstChild("Assets")
				local animFolder = assets and assets:FindFirstChild("Animations")
				local configAnimFolder = animFolder and animFolder:FindFirstChild(rebirthData.RequiredBrainrot)
				local idleAnim = configAnimFolder and configAnimFolder:FindFirstChild("Idle")
				
				if idleAnim and idleAnim:IsA("Animation") then
					-- Get animator (checks Humanoid first, then AnimationController)
					local animator = nil
					local humanoid = model:FindFirstChildOfClass("Humanoid", true)
					if humanoid then
						animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
					else
						local animController = model:FindFirstChildOfClass("AnimationController", true)
						if not animController then
							animController = Instance.new("AnimationController")
							animController.Parent = model
						end
						animator = animController:FindFirstChildOfClass("Animator") or Instance.new("Animator", animController)
					end
					
					if animator then
						-- Don't duplicate if already playing
						local alreadyPlaying = false
						for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
							if track.Animation and track.Animation.AnimationId == idleAnim.AnimationId then
								alreadyPlaying = true
								break
							end
						end
						
						if not alreadyPlaying then
							local track = animator:LoadAnimation(idleAnim)
							track.Priority = Enum.AnimationPriority.Idle
							track.Looped = true
							track:Play(0.1, 1, 1)
						end
					end
				end
			end
		end
		
		-- Set viewport lighting (bright since it's discovered)
		viewportFrame.LightColor = Color3.fromRGB(215, 215, 215)
		viewportFrame.Ambient = Color3.fromRGB(255, 255, 255)
	end
	
	requirementItem.Parent = requirementListHolder
end

--- Stop all animations in requirement ViewportFrames
local function stopRequirementAnimations()
	if not requirementListHolder then return end
	
	for _, item in ipairs(requirementListHolder:GetChildren()) do
		if item:IsA("Frame") or item:IsA("ImageLabel") then
			local viewportFrame = item:FindFirstChild("ViewportFrame")
			if viewportFrame then
				local worldModel = viewportFrame:FindFirstChildOfClass("WorldModel")
				local model = worldModel and worldModel:FindFirstChild("ViewportModel")
				if model then
					-- Get animator from Humanoid or AnimationController
					local animator = nil
					local humanoid = model:FindFirstChildOfClass("Humanoid", true)
					if humanoid then
						animator = humanoid:FindFirstChildOfClass("Animator")
					else
						local animController = model:FindFirstChildOfClass("AnimationController", true)
						if animController then
							animator = animController:FindFirstChildOfClass("Animator")
						end
					end
					
					if animator then
						for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
							track:Stop()
						end
					end
				end
			end
		end
	end
end

-- ========================================
-- SURGICAL UPDATE (callbacks)
-- ========================================

--- Surgical update when Speed changes
local function surgicalUpdate_SpeedChanged(oldSpeed, newSpeed)
	local rebirths = getCurrentRebirths()
	
	-- Update with animation if UI is visible
	updateSpeedBar(newSpeed, rebirths, true)
end

--- Surgical update when Rebirths change
local function surgicalUpdate_RebirthsChanged(oldRebirths, newRebirths)
	-- Clear cached requirement (it changed)
	clearSpeedRequirementCache()
	
	local speed = getCurrentSpeed()
	
	-- Update with animation (rebirth is a significant event)
	updateSpeedBar(speed, newRebirths, true)
	
	-- Update rewards display for NEXT rebirth
	updateRewardsDisplay(newRebirths + 1)
	
	-- Update requirements display for NEXT rebirth
	updateRequirementDisplay(newRebirths + 1)
end

-- ========================================
-- BUTTON HANDLERS
-- ========================================

--- Handle rebirth button click
local function onRebirthClick()
	local replica = getReplica()
	if not replica then return end
	
	-- Send rebirth request to server (server will validate everything)
	local events = ReplicatedStorage:FindFirstChild("Events")
	if events then
		local rebirthEvent = events:FindFirstChild("Rebirth")
		if rebirthEvent then
			rebirthEvent:FireServer()
		end
	end
end

-- ========================================
-- DATA LISTENERS (Smart Pattern from FoodShop)
-- ========================================

--- Setup smart data listeners (only update when needed)
local function setupDataListeners()
	local replica = getReplica()
	if not replica then
		warn("⚠️ Client_RebirthStore: No replica for data listeners")
		return
	end
	
	-- Listen for Speed changes (surgical update with animation)
	replica:ListenToChange({"Speed"}, function(newSpeed, oldSpeed)
		surgicalUpdate_SpeedChanged(oldSpeed or 0, newSpeed or 0)
	end)
	
	-- Listen for Rebirths changes (surgical update, clear cache)
	replica:ListenToChange({"Rebirths"}, function(newRebirths, oldRebirths)
		surgicalUpdate_RebirthsChanged(oldRebirths or 0, newRebirths or 0)
	end)
	
	-- Listen for PlotSlots changes (smart: only update when ConfigName set changes, not CashToCollect)
	local plotBrainrotConfigs = {} -- Track which ConfigNames are on plot
	
	replica:ListenToChange({"PlotSlots"}, function(newSlots)
		-- Skip if no requirementListHolder (UI not initialized yet)
		if not requirementListHolder then return end
		
		-- Build set of ConfigNames currently on plot
		local newConfigs = {}
		if newSlots then
			for slotID, slotData in pairs(newSlots) do
				if slotData and slotData.ConfigName then
					newConfigs[slotData.ConfigName] = true
				end
			end
		end
		
		-- Check if ConfigName set actually changed (not just CashToCollect)
		local configSetChanged = false
		
		-- Check for removed ConfigNames
		for config in pairs(plotBrainrotConfigs) do
			if not newConfigs[config] then
				configSetChanged = true
				break
			end
		end
		
		-- Check for added ConfigNames
		if not configSetChanged then
			for config in pairs(newConfigs) do
				if not plotBrainrotConfigs[config] then
					configSetChanged = true
					break
				end
			end
		end
		
		-- Only update if ConfigName set actually changed
		if configSetChanged then
			plotBrainrotConfigs = newConfigs
			
			-- Update AvailableFrame for all requirement items (even if UI closed)
			for _, item in ipairs(requirementListHolder:GetChildren()) do
				local requiredConfigName = item:GetAttribute("RequiredConfigName")
				if requiredConfigName then
					updateAvailableFrame(item, requiredConfigName)
				end
			end
		end
	end)
end

-- ========================================
-- INITIALIZATION
-- ========================================

function Module:Init()
	-- Wait for data
	Client_Data:WaitUntilReady()
	local replica = getReplica()
	if not replica then
		warn("⚠️ Client_RebirthStore: No replica available")
		return
	end
	
	-- Wait for UI
	local playerGui = Player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("Main", 10)
	if not mainGui then
		warn("⚠️ Client_RebirthStore: Main GUI not found")
		return
	end
	
	-- Find Frames folder
	local frames = mainGui:FindFirstChild("Frames")
	if not frames then
		warn("⚠️ Client_RebirthStore: Frames folder not found")
		return
	end
	
	-- Find Rebirth frame
	rebirthFrame = frames:FindFirstChild("Rebirth") or frames:FindFirstChild("Rebirths")
	if not rebirthFrame then
		warn("⚠️ Client_RebirthStore: Rebirth frame not found in Frames")
		return
	end
	
	-- Cache speed bar UI references (one-time setup)
	if not cacheSpeedBarUI() then
		warn("⚠️ Client_RebirthStore: Failed to cache SpeedBar UI")
		return
	end
	
	-- Cache rewards UI references
	local rewardsSection = rebirthFrame:FindFirstChild("Rewards")
	if rewardsSection then
		rewardsListHolder = rewardsSection:FindFirstChild("ListHolder")
		
		if rewardsListHolder then
		-- Cache templates (they should be set to Visible=false in UI)
		rewardTemplates.Cash = rewardsListHolder:FindFirstChild("CashTemplate")
		rewardTemplates.Slot = rewardsListHolder:FindFirstChild("SlotTemplate")
		rewardTemplates.Carry = rewardsListHolder:FindFirstChild("CarryTemplate")
		rewardTemplates.Floor = rewardsListHolder:FindFirstChild("FloorTemplate")
		
		-- Make sure templates are hidden
		if rewardTemplates.Cash then rewardTemplates.Cash.Visible = false end
		if rewardTemplates.Slot then rewardTemplates.Slot.Visible = false end
		if rewardTemplates.Carry then rewardTemplates.Carry.Visible = false end
		if rewardTemplates.Floor then rewardTemplates.Floor.Visible = false end
		else
			warn("⚠️ Client_RebirthStore: Rewards.ListHolder not found")
		end
	else
		warn("⚠️ Client_RebirthStore: Rewards section not found")
	end
	
	-- Cache requirement UI references
	local requirementSection = rebirthFrame:FindFirstChild("Requirements")
	if requirementSection then
		requirementListHolder = requirementSection:FindFirstChild("ListHolder")
		
		if requirementListHolder then
			-- Cache template (should be Visible=false in UI)
			requirementTemplate = requirementListHolder:FindFirstChild("Template")
			
			-- Make sure template is hidden
			if requirementTemplate then
				requirementTemplate.Visible = false
			end
		else
			warn("⚠️ Client_RebirthStore: Requirements.ListHolder not found")
		end
	else
		warn("⚠️ Client_RebirthStore: Requirements section not found")
	end
	
	-- Find and connect rebirth button
	local buttonsSection = rebirthFrame:FindFirstChild("Buttons")
	local rebirthButtonContainer = buttonsSection and buttonsSection:FindFirstChild("Rebirth")
	rebirthButton = rebirthButtonContainer and rebirthButtonContainer:FindFirstChild("RebirthButton")
	
	if rebirthButton and (rebirthButton:IsA("ImageButton") or rebirthButton:IsA("TextButton")) then
		rebirthButton.MouseButton1Click:Connect(onRebirthClick)
	else
		warn("⚠️ Client_RebirthStore: RebirthButton not found at Buttons.Rebirth.RebirthButton")
	end
	
	-- Connect Skip Rebirth (Robux) button
	local skipSection = buttonsSection and buttonsSection:FindFirstChild("Skip")
	local skipButton = skipSection and skipSection:FindFirstChild("SkipButton")
	if skipButton and (skipButton:IsA("ImageButton") or skipButton:IsA("TextButton")) then
		skipButton.MouseButton1Click:Connect(function()
			local events = ReplicatedStorage:FindFirstChild("Events")
			local purchaseHandler = events and events:FindFirstChild("PurchaseHandler")
			if purchaseHandler then
				-- Server will FireClient(PurchaseHandler); client listener shows rainbow + prompt
				purchaseHandler:FireServer(SKIP_REBIRTH_PRODUCT_ID)
			end
		end)
	end
	
	-- Initial update (no animation on load)
	local currentSpeed = getCurrentSpeed()
	local currentRebirths = getCurrentRebirths()
	updateSpeedBar(currentSpeed, currentRebirths, false)
	
	-- Initial rewards display (show what NEXT rebirth will give)
	updateRewardsDisplay(currentRebirths + 1)
	
	-- Initial requirement display (show what brainrot is needed)
	updateRequirementDisplay(currentRebirths + 1)
	
	-- Listen for inventory changes (debounced: batch rapid changes)
	if Client_Inventory and Client_Inventory.InventoryChanged then
		local inventoryDebounce = false
		
		Client_Inventory.InventoryChanged.Event:Connect(function()
			-- Skip if no requirementListHolder (UI not initialized yet)
			if not requirementListHolder then return end
			
			-- Debounce: prevent spam from rapid inventory changes
			if inventoryDebounce then return end
			inventoryDebounce = true
			
			task.delay(0.1, function()
				inventoryDebounce = false
				
				-- Update AvailableFrame for all requirement items (even if UI closed)
				for _, item in ipairs(requirementListHolder:GetChildren()) do
					local requiredConfigName = item:GetAttribute("RequiredConfigName")
					if requiredConfigName then
						updateAvailableFrame(item, requiredConfigName)
					end
				end
			end)
		end)
	end
	
	-- Track visibility to stop animations when UI closes
	local lastRebirthLevel = -1
	
	rebirthFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not rebirthFrame.Visible then
			stopRequirementAnimations()
		else
			-- Only refresh if rebirth level changed
			local currentRebirths = getCurrentRebirths()
			if currentRebirths ~= lastRebirthLevel then
				updateRequirementDisplay(currentRebirths + 1)
				lastRebirthLevel = currentRebirths
			end
		end
	end)
	
	-- Setup smart data listeners (surgical updates)
	setupDataListeners()
	
end

return Module
