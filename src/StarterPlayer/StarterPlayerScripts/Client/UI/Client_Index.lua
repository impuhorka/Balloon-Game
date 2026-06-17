--[[
	Client_Index.lua
	
	Professional brainrot collection viewer with replica-driven updates.
	OPTIMIZED: Single grid with model swapping (not 6 grids × 30 brainrots = 180 viewports!)
	
	UI Structure:
	Main.Frames.Index
	├── Main
	│   └── GridHolder (ScrollingFrame) - ONE grid, models swap on tab switch
	│       └── Template (Frame)
	│           ├── ViewportFrame
	│           ├── Title (TextLabel)
	│           └── Rarity (TextLabel with UIGradient)
	└── Buttons
	    └── Template (Frame)
	        └── Button (ImageButton)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")

local Player = Players.LocalPlayer
local Client_Data = require(script.Parent.Parent.Core.Client_Data)
local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
local Shared_Rarity = require(ReplicatedStorage.Modules.Gameplay.Shared_Rarity)
local Shared_ModifierHandler = require(ReplicatedStorage.Modules.Gameplay.Shared_ModifierHandler)
local Shared_IndexRewards = require(ReplicatedStorage.Modules.Gameplay.Shared_IndexRewards)
local Shared_Marketplace = require(ReplicatedStorage.Modules.Settings.Shared_Marketplace)

local Module = {}

-- ========================================
-- STATE
-- ========================================

local indexUI = nil
local mainGrid = nil -- ONE grid that updates models when tab switches
local floorHolder = nil -- Floors menu (visible when ViewAll is active)
local indexData = {} -- {[Modifier] = {ConfigName1, ...}}
local currentModifier = "Normal" -- Current selected modifier

local totalBrainrotCount = nil -- Cached count of brainrots that appear in the grid (same for all modifiers)
local gamepassPriceCache = {} -- [passId] = price (number) for FloorHolder Purchase display

-- Set a label to show gamepass price (R$...). Uses cache; fetches once and updates label if needed.
local function setGamepassPriceOnLabel(label: TextLabel, passId: number)
	if not label or not label:IsA("TextLabel") or not passId then return end
	local cached = gamepassPriceCache[passId]
	if cached then
		label.Text = "R$" .. tostring(cached)
		return
	end
	label.Text = "Loading..."
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
		end)
		if ok and info and info.PriceInRobux then
			gamepassPriceCache[passId] = info.PriceInRobux
			if label.Parent then
				label.Text = "R$" .. tostring(info.PriceInRobux)
			end
		elseif label.Parent then
			label.Text = "R$?"
		end
	end)
end

-- Show or hide the Purchase button and update its price label when showing (FloorHolder item).
local function setPurchaseButtonState(buttonsFrame: Instance, passId: number?, visible: boolean)
	local purchase = buttonsFrame and buttonsFrame:FindFirstChild("Purchase")
	if not purchase or not purchase:IsA("GuiObject") then return end
	purchase.Visible = visible
	if visible and passId then
		local btn = purchase:FindFirstChild("Button")
		local title = btn and btn:FindFirstChild("Title")
		if title and title:IsA("TextLabel") then
			setGamepassPriceOnLabel(title, passId)
		end
	end
end

-- ========================================
-- VIEWPORT SETUP
-- ========================================

local function setupViewportModel(viewportFrame, configName, modifier)
	if not viewportFrame then return end
	
	local worldModel = viewportFrame:FindFirstChildOfClass("WorldModel")
	if not worldModel then
		worldModel = Instance.new("WorldModel")
		worldModel.Parent = viewportFrame
	end
	
	local model = worldModel:FindFirstChild("ViewportModel")
	if model then
		-- Reuse existing model: only apply modifier visuals (no viewport reload)
		Shared_ModifierHandler:ApplyModifierToModel(model, configName, modifier)
		return
	end
	
	-- First time: create model via handler (Normal + modifier visuals)
	model = Shared_ModifierHandler:GetBrainrotModel(configName, modifier)
	if not model then return end
	
	model.Name = "ViewportModel"
	model.Parent = worldModel
	
	local cf, size = model:GetBoundingBox()
	local maxSize = math.max(size.X, size.Y, size.Z)
	local distance = maxSize * 1.06
	local camPos = cf.Position + Vector3.new(distance, size.Y * 0.2, distance * 0.6)
	
	local camera = viewportFrame.CurrentCamera
	if not camera then
		camera = Instance.new("Camera")
		camera.Parent = viewportFrame
		viewportFrame.CurrentCamera = camera
	end
	camera.CFrame = CFrame.lookAt(camPos, cf.Position)
end

local function getAnimator(model)
	if not model then return nil end
	
	local humanoid = model:FindFirstChildOfClass("Humanoid", true)
	if humanoid then
		return humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	end
	
	local animController = model:FindFirstChildOfClass("AnimationController", true)
	if not animController then
		animController = Instance.new("AnimationController")
		animController.Parent = model
	end
	
	return animController:FindFirstChildOfClass("Animator") or Instance.new("Animator", animController)
end

local function playIdleAnimation(viewportFrame, configName)
	if not viewportFrame then return end
	
	local worldModel = viewportFrame:FindFirstChildOfClass("WorldModel")
	local model = worldModel and worldModel:FindFirstChild("ViewportModel")
	if not model then return end
	
	-- Get animation: Assets.Animations[ConfigName].Idle
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local animFolder = assets and assets:FindFirstChild("Animations")
	local configAnimFolder = animFolder and animFolder:FindFirstChild(configName)
	local idleAnim = configAnimFolder and configAnimFolder:FindFirstChild("Idle")
	
	if not (idleAnim and idleAnim:IsA("Animation")) then return end
	
	local animator = getAnimator(model)
	if not animator then return end
	
	-- Don't duplicate if already playing
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Animation and track.Animation.AnimationId == idleAnim.AnimationId then
			return
		end
	end
	
	local track = animator:LoadAnimation(idleAnim)
	track.Priority = Enum.AnimationPriority.Idle
	track.Looped = true
	track:Play(0.1, 1, 1)
end

local function stopAllAnimations(viewportFrame)
	if not viewportFrame then return end
	
	local worldModel = viewportFrame:FindFirstChildOfClass("WorldModel")
	local model = worldModel and worldModel:FindFirstChild("ViewportModel")
	if not model then return end
	
	local animator = getAnimator(model)
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop()
		end
	end
end

-- ========================================
-- FRAME UPDATES
-- ========================================

local function updateItemFrame(frame, modifier, configName)
	if not frame then return end
	
	local brainrotData = Shared_Brainrots.List[configName]
	if not brainrotData then return end
	
	local isDiscovered = indexData[modifier] and table.find(indexData[modifier], configName) ~= nil
	
	-- Update title
	local titleLabel = frame:FindFirstChild("Title")
	if titleLabel then
		titleLabel.Text = isDiscovered and brainrotData.DisplayName or "???"
	end
	
	-- Update viewport lighting
	local viewportFrame = frame:FindFirstChild("ViewportFrame")
	if viewportFrame then
		viewportFrame.LightColor = isDiscovered and Color3.fromRGB(215, 215, 215) or Color3.fromRGB(0, 0, 0)
		viewportFrame.Ambient = isDiscovered and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
		
		-- Only play animation if Index UI is visible AND discovered
		if isDiscovered and indexUI and indexUI.Visible then
			playIdleAnimation(viewportFrame, configName)
		else
			stopAllAnimations(viewportFrame)
		end
	end
end

local function wasDiscovered(data, modKey, configName)
	return data[modKey] and table.find(data[modKey], configName) ~= nil
end

local function refreshAllFrames()
	if not mainGrid then return end
	
	for _, itemFrame in ipairs(mainGrid:GetChildren()) do
		if itemFrame:IsA("Frame") and itemFrame.Name ~= "Template" and itemFrame.Name ~= "UIListLayout" then
			local configName = itemFrame.Name
			updateItemFrame(itemFrame, currentModifier, configName)
		end
	end
end

local function getTotalBrainrotCount()
	if totalBrainrotCount ~= nil then return totalBrainrotCount end
	local n = 0
	for _, brainrotData in pairs(Shared_Brainrots.List) do
		if type(brainrotData) == "table" and brainrotData.Rarity and Shared_Rarity.List[brainrotData.Rarity] then
			n += 1
		end
	end
	totalBrainrotCount = n
	return n
end

-- Update Info (Title, Description, IconFrame.ImageLabel) for a given modifier. Used by PlotFrame and FloorHolder items.
local function updateRewardInfo(infoFrame, modifier)
	if not infoFrame then return end
	local replica = Client_Data:GetReplica()
	local rewardConfig = Shared_IndexRewards:GetRewardConfig(modifier)
	local rewardsUnlocked = (replica and replica.Data and replica.Data.IndexRewardsUnlocked) or {}
	local passes = (replica and replica.Data and replica.Data.Passes) or {}
	local isUnlocked
	if Shared_IndexRewards:IsGamepassUnlock(rewardConfig) then
		isUnlocked = (passes[rewardConfig.PassName] == true)
	elseif Shared_IndexRewards:IsIndexUnlock(rewardConfig) then
		isUnlocked = (rewardsUnlocked[modifier] == true)
	elseif Shared_IndexRewards:IsSpecialRewardUnlock(rewardConfig) then
		isUnlocked = (rewardsUnlocked[modifier] == true)
	else
		isUnlocked = false
	end

	local modifierData = Shared_Rarity.ModifierData[modifier]
	local modifierDisplayName = (modifierData and modifierData.DisplayName) or (rewardConfig and rewardConfig.RewardName) or modifier
	local rewardName = (rewardConfig and rewardConfig.RewardName) or (modifierDisplayName .. " Plot")

	local titleLabel = infoFrame:FindFirstChild("Title")
	if titleLabel then
		titleLabel.Text = isUnlocked and (rewardName .. "!") or ("Unlock " .. rewardName .. "!")
	end
	local descLabel = infoFrame:FindFirstChild("Description")
	if descLabel then
		descLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		descLabel.RichText = true
		local cashMult = (rewardConfig and rewardConfig.CashMultiplier) or 0
		local multSuffix = string.format(" - x%s Cash", tostring(cashMult))
		local green = '<font color="rgb(154,255,21)">'
		local closeFont = "</font>"
		if Shared_IndexRewards:IsGamepassUnlock(rewardConfig) then
			-- Gamepass/event: owned = 1/1, not owned = 0/1
			if isUnlocked then
				descLabel.Text = green .. "You own this plot!\n[1/1]" .. closeFont .. multSuffix
			else
				local base = rewardConfig.UnlockDescription or "Purchase with Robux to unlock."
				descLabel.Text = green .. string.format("%s\n[0/1]", base) .. closeFont .. multSuffix
			end
		elseif Shared_IndexRewards:IsIndexUnlock(rewardConfig) then
			local list = indexData[modifier]
			local discovered = list and #list or 0
			local required = (rewardConfig and rewardConfig.RequiredCount) or getTotalBrainrotCount()
			descLabel.Text = green .. string.format("%s Brainrots discovered\n[%d/%d]", modifierDisplayName, discovered, required) .. closeFont .. multSuffix
		else
			descLabel.Text = green .. (rewardConfig and rewardConfig.UnlockDescription or "Unlock this plot to equip it.") .. closeFont .. multSuffix
		end
	end
	local iconFrame = infoFrame:FindFirstChild("IconFrame")
	if iconFrame then
		local imageLabel = iconFrame:FindFirstChild("ImageLabel")
		if imageLabel and imageLabel:IsA("ImageLabel") and rewardConfig and rewardConfig.Image then
			imageLabel.Image = rewardConfig.Image
		end
	end
end

local function updatePlotFrameInfo()
	if not indexUI then return end
	local plotFrame = indexUI.Main and indexUI.Main:FindFirstChild("PlotFrame")
	if not plotFrame then return end

	local replica = Client_Data:GetReplica()
	local rewardsUnlocked = (replica and replica.Data and replica.Data.IndexRewardsUnlocked) or {}
	local passes = (replica and replica.Data and replica.Data.Passes) or {}
	local rewardConfig = Shared_IndexRewards:GetRewardConfig(currentModifier)
	local isUnlocked
	if Shared_IndexRewards:IsGamepassUnlock(rewardConfig) then
		isUnlocked = (passes[rewardConfig.PassName] == true)
	elseif Shared_IndexRewards:IsIndexUnlock(rewardConfig) then
		isUnlocked = (rewardsUnlocked[currentModifier] == true)
	elseif Shared_IndexRewards:IsSpecialRewardUnlock(rewardConfig) then
		isUnlocked = (rewardsUnlocked[currentModifier] == true)
	else
		isUnlocked = false
	end
	local equippedFloor = (replica and replica.Data and replica.Data.EquippedIndexFloor) or "Default"
	local isEquipped = (equippedFloor and equippedFloor ~= "Default" and equippedFloor == currentModifier)

	-- Info (Title, Description, IconFrame.ImageLabel)
	local info = plotFrame:FindFirstChild("Info")
	if info then
		updateRewardInfo(info, currentModifier)
	end

	-- Buttons: ViewAll always; Equip visible when unlocked and not equipped; Unequip visible when equipped.
	-- LockedButton visible when locked (unless it's a Gamepass skin, then show Purchase button)
	local buttons = plotFrame:FindFirstChild("Buttons")
	if buttons then
		local viewAll = buttons:FindFirstChild("ViewAll")
		local equip = buttons:FindFirstChild("Equip")
		local unequip = buttons:FindFirstChild("Unequip")
		local lockedButton = buttons:FindFirstChild("LockedButton")
		local purchase = buttons:FindFirstChild("Purchase")
		
		local isGamepass = Shared_IndexRewards:IsGamepassUnlock(rewardConfig)
		
		if viewAll and viewAll:IsA("GuiObject") then viewAll.Visible = true end
		if equip and equip:IsA("GuiObject") then equip.Visible = isUnlocked and not isEquipped end
		if unequip and unequip:IsA("GuiObject") then unequip.Visible = isEquipped end
		
		-- Show LockedButton for locked skins (unless it's a Gamepass, then Purchase is shown)
		if lockedButton and lockedButton:IsA("GuiObject") then
			lockedButton.Visible = not isUnlocked and not isGamepass
		end
		
		-- Hide Purchase button here (handled separately via setPurchaseButtonState for gamepasses)
		if purchase and purchase:IsA("GuiObject") and not isGamepass then
			purchase.Visible = false
		end
		
		for _, child in ipairs(buttons:GetChildren()) do
			if child:IsA("GuiObject") and child ~= viewAll and child ~= equip and child ~= unequip and child ~= lockedButton and child ~= purchase then
				child.Visible = false
			end
		end
	end
end

-- Update all FloorHolder item Infos + Buttons (Equip when unlocked and not equipped; Unequip when equipped)
local function updateAllFloorItems()
	if not floorHolder then return end
	local replica = Client_Data:GetReplica()
	local rewardsUnlocked = (replica and replica.Data and replica.Data.IndexRewardsUnlocked) or {}
	local equippedFloor = (replica and replica.Data and replica.Data.EquippedIndexFloor) or "Default"
	local passes = (replica and replica.Data and replica.Data.Passes) or {}
	for _, child in ipairs(floorHolder:GetChildren()) do
		if child:IsA("GuiObject") and Shared_IndexRewards:GetRewardConfig(child.Name) then
			local modifierKey = child.Name
			local info = child:FindFirstChild("Info")
			if info then
				updateRewardInfo(info, modifierKey)
			end
			local config = Shared_IndexRewards:GetRewardConfig(modifierKey)
			local isUnlocked
			if Shared_IndexRewards:IsGamepassUnlock(config) then
				isUnlocked = (passes[config.PassName] == true)
			elseif Shared_IndexRewards:IsIndexUnlock(config) then
				isUnlocked = (rewardsUnlocked[modifierKey] == true)
			elseif Shared_IndexRewards:IsSpecialRewardUnlock(config) then
				isUnlocked = (rewardsUnlocked[modifierKey] == true)
			else
				isUnlocked = false
			end
			local isEquipped = (equippedFloor and equippedFloor ~= "Default" and equippedFloor == modifierKey)
			local buttons = child:FindFirstChild("Buttons")
			if buttons then
				local equip = buttons:FindFirstChild("Equip")
				local unequip = buttons:FindFirstChild("Unequip")
				local purchase = buttons:FindFirstChild("Purchase")
				local lockedButton = buttons:FindFirstChild("LockedButton")
				local isGamepass = config and Shared_IndexRewards:IsGamepassUnlock(config)
				local isGamepassLocked = isGamepass and not isUnlocked
				local passId = config and config.PassName and Shared_Marketplace.Passes and Shared_Marketplace.Passes[config.PassName]

				setPurchaseButtonState(buttons, passId, isGamepassLocked == true)
				if equip and equip:IsA("GuiObject") then equip.Visible = isUnlocked and not isEquipped end
				if unequip and unequip:IsA("GuiObject") then unequip.Visible = isEquipped end
				
				-- Show LockedButton for all locked skins (unless it's a Gamepass, then Purchase is shown)
				if lockedButton and lockedButton:IsA("GuiObject") then
					lockedButton.Visible = not isUnlocked and not isGamepass
				end
				
				for _, btnChild in ipairs(buttons:GetChildren()) do
					if btnChild:IsA("GuiObject") and btnChild ~= equip and btnChild ~= unequip and btnChild ~= purchase and btnChild ~= lockedButton then
						btnChild.Visible = false
					end
				end
			end
		end
	end
end

-- ========================================
-- TAB SWITCHING
-- ========================================

local function switchToModifier(newModifier)
	-- Return to grid view when clicking a modifier tab (from floors menu)
	if mainGrid then mainGrid.Visible = true end
	if floorHolder then floorHolder.Visible = false end
	local plotFrame = indexUI.Main and indexUI.Main:FindFirstChild("PlotFrame")
	if plotFrame then plotFrame.Visible = true end

	if currentModifier == newModifier then return end
	
	currentModifier = newModifier
	
	-- Update tab button states (show DarkenFrame for unselected tabs)
	for _, buttonFrame in ipairs(indexUI.Buttons:GetChildren()) do
		if buttonFrame:IsA("Frame") and buttonFrame.Name ~= "Template" and buttonFrame.Name ~= "UIListLayout" then
			local button = buttonFrame:FindFirstChild("Button")
			if button then
				local darkenFrame = button:FindFirstChild("DarkenFrame")
				if darkenFrame then
					-- Show DarkenFrame for unselected tabs, hide for selected tab
					darkenFrame.Visible = (buttonFrame.Name ~= newModifier)
				end
			end
		end
	end
	
	-- Phase 1: Update all viewport models first (no display changes yet)
	if not mainGrid then return end
	
	for _, itemFrame in ipairs(mainGrid:GetChildren()) do
		if itemFrame:IsA("Frame") and itemFrame.Name ~= "Template" and itemFrame.Name ~= "UIListLayout" then
			local configName = itemFrame.Name
			local viewportFrame = itemFrame:FindFirstChild("ViewportFrame")
			
			if viewportFrame then
				setupViewportModel(viewportFrame, configName, newModifier)
			end
		end
	end
	
	-- Phase 2: Then update frame states (title, lighting, animation)
	for _, itemFrame in ipairs(mainGrid:GetChildren()) do
		if itemFrame:IsA("Frame") and itemFrame.Name ~= "Template" and itemFrame.Name ~= "UIListLayout" then
			local configName = itemFrame.Name
			updateItemFrame(itemFrame, newModifier, configName)
		end
	end
	
	updatePlotFrameInfo()
end

-- ========================================
-- GRID CREATION (ONE grid only!)
-- ========================================

-- Rarity order for Index UI grid only (Legendary → Mythical → Secret). Other rarities match Shared_Rarity.
local INDEX_UI_RARITY_ORDER = {
	Common = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
	Mythical = 5,
	Secret = 6,
	Celestial = 7,
	Divine = 8,
	Admin = 99,
}

local function createGrid(gridTemplate, itemTemplate)
	mainGrid = gridTemplate:Clone()
	mainGrid.Name = "MainGrid"
	mainGrid.Parent = indexUI.Main
	
	-- Hide/remove the Template (we use our cloned itemTemplate for items)
	local templateChild = mainGrid:FindFirstChild("Template")
	if templateChild then
		templateChild.Visible = false
	end
	
	-- Create items for ALL brainrots (ONE time)
	for configName, brainrotData in pairs(Shared_Brainrots.List) do
		-- Skip if no valid rarity
		if type(brainrotData) ~= "table" or not brainrotData.Rarity then continue end
		local rarityInfo = Shared_Rarity.List[brainrotData.Rarity]
		if not rarityInfo then continue end
		
		local itemFrame = itemTemplate:Clone()
		itemFrame.Name = configName
		itemFrame.Visible = true
		
		-- Set rarity label + gradient (use Shared_Rarity for consistency)
		local rarityLabel = itemFrame:FindFirstChild("Rarity")
		if rarityLabel then
			local sharedRarityInfo = Shared_Rarity:GetRarityInfo(brainrotData.Rarity)
			if sharedRarityInfo then
				rarityLabel.Text = brainrotData.Rarity
				local gradient = rarityLabel:FindFirstChildOfClass("UIGradient")
				if not gradient then
					gradient = Instance.new("UIGradient")
					gradient.Parent = rarityLabel
				end
				
				if gradient and sharedRarityInfo.gradient then
					gradient.Color = sharedRarityInfo.gradient
					gradient.Rotation = (sharedRarityInfo.isRainbow and 0) or 90  -- Rainbow 0°, others 90°
				end
			end
		end
		
		itemFrame.LayoutOrder = INDEX_UI_RARITY_ORDER[brainrotData.Rarity] or rarityInfo.LayoutOrder
		
		-- Setup viewport with default modifier (Normal)
		local viewportFrame = itemFrame:FindFirstChild("ViewportFrame")
		if viewportFrame then
			setupViewportModel(viewportFrame, configName, currentModifier)
		end
		
		-- Initial update
		updateItemFrame(itemFrame, currentModifier, configName)
		
		itemFrame.Parent = mainGrid
	end
end

local function createTabButtons()
	local clickDebounce = false
	local order = Shared_IndexRewards.RewardOrder or {}
	local tabOrder = 0
	for i, modifierKey in ipairs(order) do
		local rewardConfig = Shared_IndexRewards:GetRewardConfig(modifierKey)
		if not rewardConfig then continue end
		-- Only create a tab for Index (collection) plot skins; gamepass/event skins appear in FloorHolder but have no tab
		if not Shared_IndexRewards:IsIndexUnlock(rewardConfig) then continue end
		tabOrder += 1
		local modifierData = Shared_Rarity.ModifierData[modifierKey]
		local displayName = (modifierData and modifierData.DisplayName) or (rewardConfig.RewardName and rewardConfig.RewardName:gsub(" Plot$", "")) or modifierKey
		local colorSeq, colorRot = nil, 90
		if modifierData and modifierData.Color then
			colorSeq = modifierData.Color[1]
			colorRot = modifierData.Color[2]
		else
			colorSeq = ColorSequence.new(Color3.fromRGB(255, 215, 0), Color3.fromRGB(255, 165, 0))
		end
		local buttonFrame = indexUI.Buttons.Template:Clone()
		buttonFrame.Name = modifierKey
		buttonFrame.Visible = true
		local button = buttonFrame:FindFirstChild("Button")
		if button then
			local titleLabel = button:FindFirstChild("Title")
			if titleLabel then
				titleLabel.Text = displayName
			end
			local gradient = button:FindFirstChildOfClass("UIGradient")
			if gradient and colorSeq then
				gradient.Color = colorSeq
				gradient.Rotation = colorRot
			end
			local darkenFrame = button:FindFirstChild("DarkenFrame")
			if darkenFrame then
				darkenFrame.Visible = (modifierKey ~= currentModifier)
			end
			CollectionService:AddTag(button, "AnimatedButton")
			button.MouseButton1Click:Connect(function()
				if clickDebounce then return end
				clickDebounce = true
				task.delay(0.15, function() clickDebounce = false end)
				switchToModifier(modifierKey)
			end)
		end
		buttonFrame.LayoutOrder = tabOrder
		buttonFrame.Parent = indexUI.Buttons
	end
end

-- ========================================
-- DATA SYNC
-- ========================================

local function syncIndexData()
	local replica = Client_Data:GetReplica()
	if not replica or not replica.Data then return end
	
	local replicaIndex = replica.Data.Index
	local previousIndex = indexData
	indexData = {}
	if replicaIndex then
		for modifierKey, brainrots in pairs(replicaIndex) do
			if type(brainrots) == "table" then
				indexData[modifierKey] = {}
				for _, configName in pairs(brainrots) do
					table.insert(indexData[modifierKey], configName)
				end
			end
		end
	end
	
	-- Update only item frames whose discovery state changed for the current modifier
	if not mainGrid then return end
	for _, itemFrame in ipairs(mainGrid:GetChildren()) do
		if itemFrame:IsA("Frame") and itemFrame.Name ~= "Template" and itemFrame.Name ~= "UIListLayout" then
			local configName = itemFrame.Name
			local was = wasDiscovered(previousIndex, currentModifier, configName)
			local isNow = wasDiscovered(indexData, currentModifier, configName)
			if was ~= isNow then
				updateItemFrame(itemFrame, currentModifier, configName)
			end
		end
	end
	
	updatePlotFrameInfo()
	updateAllFloorItems()
end

-- ========================================
-- INITIALIZATION
-- ========================================

function Module:Init()
	Client_Data:WaitUntilReady()
	
	local playerGui = Player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("Main", 10)
	if not mainGui then
		warn("⚠️ Client_Index: Main GUI not found")
		return
	end
	
	local framesFolder = mainGui:FindFirstChild("Frames")
	indexUI = framesFolder and framesFolder:FindFirstChild("Index")
	if not indexUI then
		warn("⚠️ Client_Index: Index frame not found")
		return
	end
	
	local mainFolder = indexUI:FindFirstChild("Main")
	if not mainFolder then
		warn("⚠️ Client_Index: Main folder not found")
		return
	end
	
	local gridHolder = mainFolder:FindFirstChild("GridHolder")
	if not gridHolder then
		warn("⚠️ Client_Index: GridHolder not found")
		return
	end
	
	local itemTemplate = gridHolder:FindFirstChild("Template")
	if not itemTemplate then
		warn("⚠️ Client_Index: Template not found in GridHolder")
		return
	end
	
	itemTemplate = itemTemplate:Clone()
	local gridTemplate = gridHolder:Clone()
	mainFolder.GridHolder:Destroy()
	
	-- Create ONE grid and buttons
	createGrid(gridTemplate, itemTemplate)
	createTabButtons()
	-- Hide templates so only cloned instances show
	local buttonsTemplate = indexUI.Buttons and indexUI.Buttons:FindFirstChild("Template")
	if buttonsTemplate then
		buttonsTemplate.Visible = false
	end

	-- FloorHolder (floors menu): build from Template (one per modifier), keep in sync with PlotFrame
	floorHolder = mainFolder:FindFirstChild("FloorHolder")
	local plotFrame = mainFolder:FindFirstChild("PlotFrame")
	if floorHolder then
		floorHolder.Visible = false
	end
	local events = ReplicatedStorage:FindFirstChild("Events")
	local indexHandlerEvent = events and events:FindFirstChild("IndexHandler")

	if floorHolder and plotFrame then
		local floorTemplate = floorHolder:FindFirstChild("Template")
		if floorTemplate then
			local order = Shared_IndexRewards.RewardOrder or {}
			for i, modifierKey in ipairs(order) do
				local rewardCfg = Shared_IndexRewards:GetRewardConfig(modifierKey)
				if rewardCfg then
					local clone = floorTemplate:Clone()
					clone.Name = modifierKey
					clone.LayoutOrder = i
					clone.Visible = true
					clone.Parent = floorHolder
					if indexHandlerEvent then
						local buttons = clone:FindFirstChild("Buttons")
						if buttons then
							local equip = buttons:FindFirstChild("Equip")
							local equipBtn = equip and equip:FindFirstChild("Button")
							if equipBtn then
								equipBtn.MouseButton1Click:Connect(function()
									indexHandlerEvent:FireServer("EquipFloor", modifierKey)
								end)
							end
							local unequip = buttons:FindFirstChild("Unequip")
							local unequipBtn = unequip and unequip:FindFirstChild("Button")
							if unequipBtn then
								unequipBtn.MouseButton1Click:Connect(function()
									indexHandlerEvent:FireServer("UnequipFloor")
								end)
							end
							-- Gamepass: wire Purchase to prompt purchase
							if Shared_IndexRewards:IsGamepassUnlock(rewardCfg) then
								local passId = rewardCfg.PassName and Shared_Marketplace.Passes and Shared_Marketplace.Passes[rewardCfg.PassName]
								if passId then
									local purchase = buttons:FindFirstChild("Purchase")
									local purchaseBtn = purchase and purchase:FindFirstChild("Button")
									if not purchaseBtn and purchase and purchase:IsA("GuiButton") then purchaseBtn = purchase end
									if purchaseBtn then
										purchaseBtn.MouseButton1Click:Connect(function()
											MarketplaceService:PromptGamePassPurchase(Player, passId)
										end)
									end
								end
							end
						end
					end
				end
			end
			floorTemplate.Visible = false
		end
		updateAllFloorItems()

		-- PlotFrame Equip / Unequip clicks
		if indexHandlerEvent then
			local buttons = plotFrame:FindFirstChild("Buttons")
			if buttons then
				local equip = buttons:FindFirstChild("Equip")
				local equipBtn = equip and equip:FindFirstChild("Button")
				if equipBtn then
					equipBtn.MouseButton1Click:Connect(function()
						indexHandlerEvent:FireServer("EquipFloor", currentModifier)
					end)
				end
				local unequip = buttons:FindFirstChild("Unequip")
				local unequipBtn = unequip and unequip:FindFirstChild("Button")
				if unequipBtn then
					unequipBtn.MouseButton1Click:Connect(function()
						indexHandlerEvent:FireServer("UnequipFloor")
					end)
				end
			end
		end

		-- ViewAll opens floors menu: hide grid and PlotFrame, show FloorHolder
		local buttons = plotFrame:FindFirstChild("Buttons")
		local viewAll = buttons and buttons:FindFirstChild("ViewAll")
		local viewAllButton = viewAll and viewAll:FindFirstChild("Button")
		if viewAllButton then
			viewAllButton.MouseButton1Click:Connect(function()
				mainGrid.Visible = false
				floorHolder.Visible = true
				plotFrame.Visible = false
				-- All modifier tabs darkened (none selected in floors view)
				for _, buttonFrame in ipairs(indexUI.Buttons:GetChildren()) do
					if buttonFrame:IsA("Frame") and buttonFrame.Name ~= "Template" and buttonFrame.Name ~= "UIListLayout" then
						local button = buttonFrame:FindFirstChild("Button")
						if button then
							local darkenFrame = button:FindFirstChild("DarkenFrame")
							if darkenFrame then
								darkenFrame.Visible = true
							end
						end
					end
				end
			end)
		end
	end

	-- Default: grid view with Normal tab open (#1)
	currentModifier = "Normal"
	mainGrid.Visible = true
	if floorHolder then floorHolder.Visible = false end
	if plotFrame then plotFrame.Visible = true end
	-- Refresh tab button states and grid content for Normal
	switchToModifier("Normal")

	-- Setup data sync
	local replica = Client_Data:GetReplica()
	if replica then
		syncIndexData()
		
		replica:ListenToChange({"Index"}, function(newValue)
			syncIndexData()
		end)
		replica:ListenToChange({"IndexRewardsUnlocked"}, function()
			updatePlotFrameInfo()
			updateAllFloorItems()
		end)
		replica:ListenToChange({"EquippedIndexFloor"}, function()
			updatePlotFrameInfo()
			updateAllFloorItems()
		end)
		replica:ListenToChange({"Passes"}, function()
			updatePlotFrameInfo()
			updateAllFloorItems()
		end)
	end
	
	-- Pause animations when UI closed
	indexUI:GetPropertyChangedSignal("Visible"):Connect(function()
		if indexUI.Visible then
			refreshAllFrames()
			updatePlotFrameInfo()
			updateAllFloorItems()
		else
			-- Stop all animations
			if mainGrid then
				for _, itemFrame in ipairs(mainGrid:GetChildren()) do
					if itemFrame:IsA("Frame") then
						local viewportFrame = itemFrame:FindFirstChild("ViewportFrame")
						stopAllAnimations(viewportFrame)
					end
				end
			end
		end
	end)
	
end

return Module
