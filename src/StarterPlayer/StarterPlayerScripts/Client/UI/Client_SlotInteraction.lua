--// Client_SlotInteraction - Handles slot interaction (place/pickup), upgrade UI, and cash collection
--// Based on Tsunami's PlotsLocalHandler pattern

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Client_Data = require(script.Parent.Parent.Core.Client_Data)
local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
local Client_EffectsLibrary = require(script.Parent.Parent.Effects.Client_EffectsLibrary)
local Client_Inventory = require(script.Parent.Parent.Core.Client_Inventory)
local Shared_GradientAnimations = require(ReplicatedStorage.Modules.UI.Shared_GradientAnimations)
local Module = {}

-- Max concurrent shine overlays per slot (stacking cap)
local MAX_SHINE_STACK = 3
-- Shine gradient band width (0–1). Larger = wider bright band (e.g. 0.1 thin, 0.22 default, 0.35 wide)
local SHINE_BAND_WIDTH = 0.32

-- Will be set in Init (from Library)
local Client_Sounds = nil

-- Track which slots are setup
local SetupSlots = {}

-- Central Upgrade Button Management
local UpgradeButtons = {} -- [slotID] = {frame, costLabel, upgradeCost, canAfford}
local CashListenerSetup = false

-- Cooldowns (seconds)
local COLLECT_COOLDOWN = 0.8
local UPGRADE_COOLDOWN = 0.25

-- Prevent overlapping jump animations per brainrot
local ActiveJumps = {}

local function getPickedBrainrotUID(): string?
	local pickedUID = Player:GetAttribute("SlotPlacablePicked")
	if type(pickedUID) == "string" and pickedUID ~= "" then
		local itemData = Client_Inventory:GetItem(pickedUID)
		if itemData and itemData.Type == "Brainrot" then
			return pickedUID
		end
	end

	local equippedUID = Player:GetAttribute("CurrentEquipped")
	local brainrotEquippedUID = Player:GetAttribute("EquippedItem_Brainrot")
	if type(equippedUID) == "string" and equippedUID == brainrotEquippedUID then
		local itemData = Client_Inventory:GetItem(equippedUID)
		if itemData and itemData.Type == "Brainrot" then
			return equippedUID
		end
	end

	return nil
end

-- Helper: WaitForChild with path (like Tsunami's WaitForLoad)
local function waitForPath(parent: Instance, path: {string} | string): Instance?
	if type(path) == "string" then
		return parent:WaitForChild(path, 10)
	end
	
	local current = parent
	for _, childName in ipairs(path) do
		current = current:WaitForChild(childName, 10)
		if not current then return nil end
	end
	return current
end

--[[
	Central Upgrade Button State Management
	Optimized system that updates all upgrade buttons when cash changes
]]

-- Update visual state of upgrade button based on affordability
local function updateUpgradeButtonState(slotID: number, canAfford: boolean)
	local buttonData = UpgradeButtons[slotID]
	if not buttonData or not buttonData.frame then return end
	
	local upgradeFrame = buttonData.frame
	
	-- Find gradient elements
	local enabledGradient = upgradeFrame:FindFirstChild("UIGradientEnabled")
	local disabledGradient = upgradeFrame:FindFirstChild("UIGradientDisabled")
	local uiStroke = upgradeFrame:FindFirstChild("UIStroke")
	
	if canAfford then
		-- Affordable state
		if enabledGradient then enabledGradient.Enabled = true end
		if disabledGradient then disabledGradient.Enabled = false end
		if uiStroke then
			local strokeEnabledGradient = uiStroke:FindFirstChild("UIGradientEnabled")
			local strokeDisabledGradient = uiStroke:FindFirstChild("UIGradientDisabled")
			if strokeEnabledGradient then strokeEnabledGradient.Enabled = true end
			if strokeDisabledGradient then strokeDisabledGradient.Enabled = false end
		end
	else
		-- Not affordable state
		if enabledGradient then enabledGradient.Enabled = false end
		if disabledGradient then disabledGradient.Enabled = true end
		if uiStroke then
			local strokeEnabledGradient = uiStroke:FindFirstChild("UIGradientEnabled")
			local strokeDisabledGradient = uiStroke:FindFirstChild("UIGradientDisabled")
			if strokeEnabledGradient then strokeEnabledGradient.Enabled = false end
			if strokeDisabledGradient then strokeDisabledGradient.Enabled = true end
		end
	end
	
	-- Update cached state
	buttonData.canAfford = canAfford
end

-- Get cached upgrade cost for a slot
local function getUpgradeCost(slotID: number): number?
	local buttonData = UpgradeButtons[slotID]
	return buttonData and buttonData.upgradeCost
end

-- Update the cached upgrade cost for a slot
local function updateCachedCost(slotID: number, newCost: number?)
	local buttonData = UpgradeButtons[slotID]
	if buttonData then
		buttonData.upgradeCost = newCost
	end
end

-- Surgical update when cash changes - only update buttons where affordability changed
local function surgicalUpdate_CashChanged(oldCash: number, newCash: number)
	for slotID, buttonData in pairs(UpgradeButtons) do
		local upgradeCost = getUpgradeCost(slotID)
		
		if upgradeCost then
			local wasAffordable = oldCash >= upgradeCost
			local isAffordable = newCash >= upgradeCost
			
			-- Only update if affordability changed
			if wasAffordable ~= isAffordable then
				updateUpgradeButtonState(slotID, isAffordable)
			end
		end
	end
end

-- Setup central cash listener (called once)
local function setupCentralCashListener()
	if CashListenerSetup then return end
	CashListenerSetup = true
	
	local replica = Client_Data:GetReplica()
	if not replica then
		-- Retry setup when replica becomes available
		Client_Data.ReplicaReady:Wait()
		replica = Client_Data:GetReplica()
		if not replica then return end
	end
	
	-- Listen for Cash changes (surgical update - only when affordability changes)
	replica:ListenToChange({"Cash"}, function(newCash, oldCash)
		surgicalUpdate_CashChanged(oldCash or 0, newCash or 0)
	end)
end

-- Register an upgrade button for central management
local function registerUpgradeButton(slotID: number, upgradeFrame: GuiObject, costLabel: GuiObject, upgradeCost: number?)
	UpgradeButtons[slotID] = {
		frame = upgradeFrame,
		costLabel = costLabel,
		upgradeCost = upgradeCost,
		canAfford = false
	}
	
	-- Setup central listener if not already done
	setupCentralCashListener()
	
	-- Initial state update
	local replica = Client_Data:GetReplica()
	if replica and upgradeCost then
		local currentCash = replica.Data.Cash or 0
		local canAfford = currentCash >= upgradeCost
		updateUpgradeButtonState(slotID, canAfford)
	end
end

-- Unregister an upgrade button (cleanup)
local function unregisterUpgradeButton(slotID: number)
	UpgradeButtons[slotID] = nil
end

--[[
	Plays a "jump" animation for a brainrot when cash is collected (Tsunami pattern).
	No-op if a jump is already playing on this model.
	@param brainrotModel Model - The brainrot model to animate
]]
local function jumpBrainrot(brainrotModel: Model)
	if not brainrotModel then return end
	if ActiveJumps[brainrotModel] then return end

	-- Get primary part (handle both Model and Folder)
	local primary = nil
	if brainrotModel:IsA("Model") then
		primary = brainrotModel.PrimaryPart
	else
		-- For Folders, find first BasePart
		primary = brainrotModel:FindFirstChildWhichIsA("BasePart", true)
	end
	
	if not primary then
		warn("⚠️ No primary part for jump animation")
		return
	end

	ActiveJumps[brainrotModel] = true
	local startCFrame = primary.CFrame
	local upCFrame = startCFrame * CFrame.new(0, 1.9, 0)

	-- Jump up 1.9 studs (Tsunami values)
	local upTween = TweenService:Create(
		primary,
		TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{CFrame = upCFrame}
	)

	-- Fall back down
	local downTween = TweenService:Create(
		primary,
		TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{CFrame = startCFrame}
	)

	upTween:Play()
	upTween.Completed:Connect(function()
		downTween:Play()
	end)
	downTween.Completed:Connect(function()
		ActiveJumps[brainrotModel] = nil
	end)
end

--[[
	Hop with 360° spin (for upgrade celebration). Short duration so upgrades can be spammed.
	Spin is linear (constant speed); hop height uses a smooth arc so it doesn't feel robotic.
	No-op if a jump is already playing on this model.
	@param brainrotModel Model - The brainrot model to animate
]]
local HOP_360_DURATION = 0.3
local HOP_360_HEIGHT = 2
local function jumpBrainrot360(brainrotModel: Model)
	if not brainrotModel then return end
	if ActiveJumps[brainrotModel] then return end

	-- Get primary part (handle both Model and Folder)
	local primary = nil
	if brainrotModel:IsA("Model") then
		primary = brainrotModel.PrimaryPart
	else
		-- For Folders, find first BasePart
		primary = brainrotModel:FindFirstChildWhichIsA("BasePart", true)
	end
	
	if not primary then
		warn("⚠️ No primary part for 360 animation")
		return
	end

	ActiveJumps[brainrotModel] = true
	local RunService = game:GetService("RunService")
	local startCF = primary.CFrame
	local startRotation = startCF - startCF.Position

	local t0 = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - t0
		if elapsed >= HOP_360_DURATION then
			connection:Disconnect()
			ActiveJumps[brainrotModel] = nil
			primary.CFrame = startCF * CFrame.Angles(0, 2 * math.pi, 0)
			return
		end

		local t = elapsed / HOP_360_DURATION  -- 0 to 1
		-- Linear spin (constant angular velocity)
		local angle = t * 2 * math.pi
		-- Smooth hop arc: parabola so peak at middle (ease in/out feel without slowing the spin)
		local height = 4 * HOP_360_HEIGHT * t * (1 - t)
		local pos = startCF.Position + Vector3.new(0, height, 0)
		primary.CFrame = CFrame.new(pos) * startRotation * CFrame.Angles(0, angle, 0)
	end)
end

--[[
	Setup ProximityPrompt for placing brainrots on empty slots (owner only)
]]
local function setupPlaceBrainrotPrompt(slotModel: Model, slotID: number, plotOwnerUserId: number?)
	local plotModel = slotModel.Parent and slotModel.Parent.Parent
	local currentOwnerUserId = plotOwnerUserId
	if plotModel then
		local ownerFromAttr = plotModel:GetAttribute("OwnerUserId")
		if type(ownerFromAttr) == "number" then
			currentOwnerUserId = ownerFromAttr
		end
	end

	local standingPart = slotModel:FindFirstChild("StandingPart")
	if not standingPart or not standingPart:IsA("BasePart") then
		warn("⚠️ Slot " .. slotID .. " missing StandingPart")
		return
	end

	local attachment = standingPart:FindFirstChild("Attachment")
	if not attachment or not attachment:IsA("Attachment") then
		attachment = Instance.new("Attachment")
		attachment.Name = "Attachment"
		attachment.Parent = standingPart
	end

	if attachment:FindFirstChild("PlaceBrainrotPrompt") then
		return
	end
	
	local placeBrainrotPrompt = Instance.new("ProximityPrompt")
	placeBrainrotPrompt.Name = "PlaceBrainrotPrompt"
	placeBrainrotPrompt.Parent = attachment
	placeBrainrotPrompt.RequiresLineOfSight = false
	placeBrainrotPrompt.ActionText = "Place Here"
	placeBrainrotPrompt.HoldDuration = 0.5
	placeBrainrotPrompt.MaxActivationDistance = 10
	placeBrainrotPrompt.Enabled = false
	
	-- Visibility control: only show when player has a brainrot picked and slot is empty
	local function updatePlacePromptVisibility()
		local isOwner = type(currentOwnerUserId) == "number" and currentOwnerUserId == Player.UserId
		local slotIsEmpty = not slotModel:GetAttribute("ConfigName")
		local brainrotUID = getPickedBrainrotUID()
		placeBrainrotPrompt.Enabled = isOwner and brainrotUID ~= nil and slotIsEmpty
	end
	
	updatePlacePromptVisibility()
	Player:GetAttributeChangedSignal("SlotPlacablePicked"):Connect(updatePlacePromptVisibility)
	Player:GetAttributeChangedSignal("CurrentEquipped"):Connect(updatePlacePromptVisibility)
	Player:GetAttributeChangedSignal("EquippedItem_Brainrot"):Connect(updatePlacePromptVisibility)
	slotModel:GetAttributeChangedSignal("ConfigName"):Connect(updatePlacePromptVisibility)
	if plotModel then
		plotModel:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			currentOwnerUserId = plotModel:GetAttribute("OwnerUserId")
			updatePlacePromptVisibility()
		end)
	end
	
	-- Trigger action
	placeBrainrotPrompt.Triggered:Connect(function()
		local brainrotUID = getPickedBrainrotUID()
		if not brainrotUID then return end
		
		-- Play item placement sound
		if Client_Sounds then
			Client_Sounds:Play("Item Equip")
		end
		
		local Events = ReplicatedStorage:WaitForChild("Events")
		local PlotHandlerEvent = Events:WaitForChild("PlotHandler")
		PlotHandlerEvent:FireServer("Place", slotID, brainrotUID)
	end)
end

--[[
	Setup cash collection on DisplayPart (touch-based).
	Cash display text updates for everyone; touch (collect, animations) only for plot owner.
]]
local function setupCashCollection(slotModel: Model, slotID: number, plotOwnerUserId: number?)
	local displayPart = slotModel:FindFirstChild("DisplayPart")
	if not displayPart then
		warn("⚠️ Slot " .. slotID .. " missing DisplayPart")
		return
	end
	
	-- Find CashDisplay SurfaceGui (should already be in template)
	local cashDisplay = displayPart:FindFirstChild("CashDisplay")
	if cashDisplay and cashDisplay:IsA("SurfaceGui") then
		-- Path: CashDisplay.Title
		local cashLabel = cashDisplay:FindFirstChild("Title")
		if cashLabel and cashLabel:IsA("TextLabel") then
		-- Update cash display when CashToCollect changes (everyone sees this)
		local function updateCashDisplay()
			local cashToCollect = slotModel:GetAttribute("CashToCollect") or 0
			if cashLabel and cashLabel:IsA("TextLabel") then
				cashLabel.Text = "$" .. Shared_Shorten:Number(cashToCollect)
			end
		end
		
		updateCashDisplay()
		slotModel:GetAttributeChangedSignal("CashToCollect"):Connect(updateCashDisplay)
		else
			warn("⚠️ CashDisplay.Title not found for slot " .. slotID)
		end
	end
	
	-- Touch collection: only plot owner can trigger collect + animations
	local debounce = false
	local displayPartOriginSize = displayPart.Size
	local displayPartOriginColor = displayPart.Color
	
	displayPart.Touched:Connect(function(hit)
		if debounce then return end
		if not hit.Parent then return end
		if not hit.Parent:FindFirstChild("Humanoid") then return end
		if Players:GetPlayerFromCharacter(hit.Parent) ~= Player then return end
		
		-- Only owner can collect and trigger animations
		if not plotOwnerUserId or plotOwnerUserId ~= Player.UserId then
			return
		end
		
		local cashToCollect = slotModel:GetAttribute("CashToCollect") or 0
		if cashToCollect <= 0 then return end
		
		debounce = true
		
		-- Show cash popup immediately (client knows the amount)
		local Client_ScreenPopup = require(script.Parent.Client_ScreenPopup)
		if Client_ScreenPopup then
			Client_ScreenPopup:ShowCashPopup(cashToCollect)
		end
		
		-- DisplayPart button press animation (shrinks down and back)
		TweenService:Create(
			displayPart,
			TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true, 0),
			{Size = displayPartOriginSize - Vector3.new(0, displayPartOriginSize.Y / 2, 0)}
		):Play()
		
		-- Longer white flash on DisplayPart then back to original color
		local white = Color3.new(1, 1, 1)
		TweenService:Create(
			displayPart,
			TweenInfo.new(0.08, Enum.EasingStyle.Linear),
			{Color = white}
		):Play()
		task.delay(0.08, function()
			TweenService:Create(
				displayPart,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Color = displayPartOriginColor}
			):Play()
		end)
		
		-- Play VFX (spawn Part with ParticleEmitters and emit)
		local vfxTemplate = ReplicatedStorage:FindFirstChild("Assets")
			and ReplicatedStorage.Assets:FindFirstChild("VFX")
			and ReplicatedStorage.Assets.VFX:FindFirstChild("Collect_FX")
		
		if vfxTemplate and vfxTemplate.PrimaryPart then
			local vfx = vfxTemplate.PrimaryPart:Clone()
			vfx.Position = displayPart.Position
			vfx.Parent = workspace
			Client_EffectsLibrary:EmitParticlesInContainer(vfx, 10)
			task.delay(2, function()
				if vfx.Parent then
					vfx:Destroy()
				end
			end)
		end
		
		-- Jump animation + highlight flash on brainrot (white "Collect" preset from effects library)
		for _, child in ipairs(slotModel:GetChildren()) do
			if child:IsA("Model") and child.Name == "PlacedBrainrot" and child.PrimaryPart then
				jumpBrainrot(child)
				Client_EffectsLibrary:FlashHighlightFill(child, "Collect")
				break
			end
		end
		
		-- Play cash pickup sound
		if Client_Sounds then
			Client_Sounds:Play("Coin Collect")
		end
		
		-- Fire server to collect cash
		local Events = ReplicatedStorage:WaitForChild("Events")
		local PlotHandlerEvent = Events:WaitForChild("PlotHandler")
		PlotHandlerEvent:FireServer("Collect", slotID)
		
		task.delay(COLLECT_COOLDOWN, function()
			debounce = false
		end)
	end)
end

--[[
	Setup upgrade UI (only for owner, uses Adornee)
]]
local function setupUpgradeUI(slotModel: Model, slotID: number, plotOwnerUserId: number?)
	-- Only setup for the owner
	if not plotOwnerUserId or plotOwnerUserId ~= Player.UserId then
		return
	end
	
	local upgradePart = slotModel:FindFirstChild("UpgradePart")
	if not upgradePart then
		warn("⚠️ Slot " .. slotID .. " missing UpgradePart")
		return
	end
	
	-- Find UpgradeDisplay SurfaceGui (should already be in template)
	local upgradeDisplay = upgradePart:FindFirstChild("UpgradeDisplay")
	if not upgradeDisplay or not upgradeDisplay:IsA("SurfaceGui") then
		warn("⚠️ Slot " .. slotID .. " missing UpgradeDisplay SurfaceGui")
		return
	end
	
	-- Clone the SurfaceGui to PlayerGui and set Adornee (Tsunami pattern)
	local surfaceGuisFolder = PlayerGui:FindFirstChild("Main") and PlayerGui.Main:FindFirstChild("SurfaceGuis")
	if not surfaceGuisFolder then
		-- Create SurfaceGuis folder if it doesn't exist
		local main = PlayerGui:FindFirstChild("Main")
		if not main then
			warn("⚠️ PlayerGui.Main not found for slot " .. slotID)
			return
		end
		surfaceGuisFolder = Instance.new("Folder")
		surfaceGuisFolder.Name = "SurfaceGuis"
		surfaceGuisFolder.Parent = main
	end
	
	-- Clone and setup
	local clonedUpgradeGui = upgradeDisplay:Clone()
	clonedUpgradeGui.Name = "UpgradeDisplay_Slot" .. slotID
	clonedUpgradeGui.Parent = surfaceGuisFolder
	clonedUpgradeGui.Adornee = upgradePart
	clonedUpgradeGui.Enabled = false -- Will be enabled when brainrot is placed
	
	-- Cleanup when GUI is destroyed
	clonedUpgradeGui.AncestryChanged:Connect(function()
		if not clonedUpgradeGui.Parent then
			unregisterUpgradeButton(slotID)
		end
	end)
	
	-- Find Upgrade frame and its children
	-- Path: UpgradeDisplay.Upgrade.Amount, UpgradeDisplay.Upgrade.Level, UpgradeDisplay.Upgrade.CanvasGroup (shine target)
	local upgradeFrame = clonedUpgradeGui:FindFirstChild("Upgrade")
	if not upgradeFrame then
		warn("⚠️ UpgradeDisplay.Upgrade frame not found for slot " .. slotID)
		return
	end

	local canvasGroup = upgradeFrame:FindFirstChild("CanvasGroup")
	
	local costLabel = upgradeFrame:FindFirstChild("Amount")
	local levelLabel = upgradeFrame:FindFirstChild("Level")
	
	if not costLabel or not levelLabel then
		warn("⚠️ Missing Amount or Level in UpgradeDisplay.Upgrade for slot " .. slotID)
		return
	end
	
	-- Update cost display and visibility based on Level and ConfigName attributes
	local function updateUpgradeCost()
		local configName = slotModel:GetAttribute("ConfigName")
		
		-- Enable/disable based on whether brainrot is placed
		if configName then
			clonedUpgradeGui.Enabled = true
		else
			clonedUpgradeGui.Enabled = false
			-- Unregister button when no brainrot
			unregisterUpgradeButton(slotID)
			return
		end
		
		local level = slotModel:GetAttribute("Level") or 1
		local config = Shared_Brainrots.List[configName]
		if not config then return end
		
		local maxLevel = Shared_Brainrots.MaxLevel or 100
		
		-- At max level: show MAX instead of $0
		if level >= maxLevel then
			if costLabel:IsA("TextLabel") then
				costLabel.Text = "MAX"
			end
			if levelLabel:IsA("TextLabel") then
				levelLabel.Text = "Max Lvl"
			end
			unregisterUpgradeButton(slotID)
			return
		end
		
		-- Use new calculation function (requires modifier)
		local modifier = slotModel:GetAttribute("Modifier") or "Normal"
		local upgradeCost = Shared_Brainrots:GetUpgradeCost(configName, level, modifier)
		
		-- Update text labels
		if costLabel:IsA("TextLabel") then
			costLabel.Text = "$" .. Shared_Shorten:Number(upgradeCost)
		end
		
		if levelLabel:IsA("TextLabel") then
			levelLabel.Text = "Lvl " .. level .. " > Lvl " .. (level + 1)
		end
		
		-- Register/update button with the calculated cost
		registerUpgradeButton(slotID, upgradeFrame, costLabel, upgradeCost)
		
		-- Update visual state based on current cash
		local replica = Client_Data:GetReplica()
		if replica then
			local currentCash = replica.Data.Cash or 0
			local canAfford = currentCash >= upgradeCost
			updateUpgradeButtonState(slotID, canAfford)
		end
	end
	
	-- Highlight flash + 360° hop on brainrot when upgraded
	local function playUpgradeFlash()
		local brainrotModel = slotModel:FindFirstChild("PlacedBrainrot")
		if brainrotModel then
			Client_EffectsLibrary:FlashHighlightFill(brainrotModel, "Upgrade")
			jumpBrainrot360(brainrotModel)
		end
	end

	-- Shine sweep on Upgrade.CanvasGroup (Reference pet-style). Stacks up to MAX_SHINE_STACK.
	local function playUpgradeShine(canvasGroup: Instance?)
		if not canvasGroup or not canvasGroup:IsA("GuiObject") then return end
		-- Cap concurrent shines
		local count = 0
		for _, child in ipairs(canvasGroup:GetChildren()) do
			if child.Name == "ShineOverlay" then count += 1 end
		end
		if count >= MAX_SHINE_STACK then return end

		local transparencySeq, colorSeq = Shared_GradientAnimations:GetShineSequences(SHINE_BAND_WIDTH)
		local overlay = Instance.new("Frame")
		overlay.Name = "ShineOverlay"
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.Position = UDim2.new(0, 0, 0, 0)
		overlay.AnchorPoint = Vector2.new(0, 0)
		overlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		overlay.BackgroundTransparency = 0
		overlay.BorderSizePixel = 0
		overlay.ZIndex = (canvasGroup:IsA("GuiObject") and canvasGroup.ZIndex or 0) + 10

		local uiGradient = Instance.new("UIGradient")
		uiGradient.Transparency = transparencySeq
		uiGradient.Color = colorSeq
		uiGradient.Rotation = 45
		uiGradient.Offset = Vector2.new(-1.5, 0)
		uiGradient.Parent = overlay

		overlay.Parent = canvasGroup

		local tweenInfo = TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local shineTween = TweenService:Create(uiGradient, tweenInfo, { Offset = Vector2.new(2, 0) })
		shineTween:Play()
		shineTween.Completed:Connect(function()
			if overlay and overlay.Parent then
				overlay:Destroy()
			end
		end)
	end
	
	-- Track last level and whether we've initialized (to prevent animation on initial placement/load)
	local lastLevel = slotModel:GetAttribute("Level")
	local hasInitialized = (slotModel:GetAttribute("ConfigName") ~= nil) -- If slot already has brainrot, we're loading existing data
	
	slotModel:GetAttributeChangedSignal("Level"):Connect(function()
		local newLevel = slotModel:GetAttribute("Level") or 1
		
		-- Only play upgrade effects if:
		-- 1. We've already initialized (not first load/placement)
		-- 2. Level actually increased
		-- 3. lastLevel is valid (not nil)
		if hasInitialized and lastLevel and newLevel > lastLevel then
			playUpgradeFlash()
			-- Play upgrade VFX at brainrot position (not slot - brainrot is what we're upgrading)
			task.spawn(function()
				local brainrotModel = slotModel:FindFirstChild("PlacedBrainrot")
				local pos = brainrotModel and brainrotModel.PrimaryPart and brainrotModel.PrimaryPart.Position
					or (brainrotModel and brainrotModel:GetPivot().Position)
					or slotModel:GetPivot().Position
				Client_EffectsLibrary:PlayUpgradeVFX(pos)
			end)
		end
		
		lastLevel = newLevel
		hasInitialized = true -- After first change, mark as initialized
		updateUpgradeCost()
	end)
	slotModel:GetAttributeChangedSignal("ConfigName"):Connect(function()
		-- When ConfigName changes (new brainrot placed), reset initialization
		hasInitialized = false
		lastLevel = slotModel:GetAttribute("Level")
		updateUpgradeCost()
	end)
	
	updateUpgradeCost()
	
	-- Bind upgrade button (the Upgrade frame itself acts as the button) with 0.2s cooldown
	local upgradeDebounce = false
	if upgradeFrame:IsA("TextButton") or upgradeFrame:IsA("ImageButton") then
		upgradeFrame.MouseButton1Click:Connect(function()
			if upgradeDebounce then return end
			local replica = Client_Data:GetReplica()
			if not replica then return end
			
			local configName = slotModel:GetAttribute("ConfigName")
			if not configName then return end
			
			local level = slotModel:GetAttribute("Level") or 1
			local maxLevel = Shared_Brainrots.MaxLevel or 100
			
			-- Check max level
			if level >= maxLevel then
				return
			end
			
			local config = Shared_Brainrots.List[configName]
			if not config then return end
			
			-- Calculate upgrade cost using new formula (requires modifier)
			local modifier = slotModel:GetAttribute("Modifier") or "Normal"
			local upgradeCost = Shared_Brainrots:GetUpgradeCost(configName, level, modifier)
		
		local currentCash = replica.Data.Cash or 0
		if currentCash >= upgradeCost then
				local Client_ScreenPopup = require(script.Parent.Client_ScreenPopup)
				if Client_ScreenPopup then
					Client_ScreenPopup:ShowCashPopup(-upgradeCost, nil, nil, false)
				end
				-- Shine sweep on Upgrade.CanvasGroup (stacks up to MAX_SHINE_STACK)
				playUpgradeShine(canvasGroup)
			end
			
			-- Set debounce (server will validate affordability and send popup)
			upgradeDebounce = true
			task.delay(UPGRADE_COOLDOWN, function()
				upgradeDebounce = false
			end)
			
			-- Fire server
			local Events = ReplicatedStorage:WaitForChild("Events")
			local PlotHandlerEvent = Events:WaitForChild("PlotHandler")
			PlotHandlerEvent:FireServer("Upgrade", slotID)
		end)
	else
		warn("⚠️ Upgrade frame is not a button for slot " .. slotID)
	end
end

--[[
	Setup ProximityPrompt for picking up brainrots (owner only)
	This is called when a brainrot model is added to the slot
]]
local function setupPickupPrompt(slotModel: Model, slotID: number, brainrotModel: Model)
	if not brainrotModel or not brainrotModel.PrimaryPart then 
		warn("⚠️ Brainrot model or PrimaryPart missing for slot " .. slotID)
		return 
	end
	
	-- Check if prompt already exists (avoid duplicates)
	if brainrotModel.PrimaryPart:FindFirstChild("PickUpPrompt") then
		return
	end
	
	-- Create PickupPrompt (directly on PrimaryPart)
	local pickupPrompt = Instance.new("ProximityPrompt")
	pickupPrompt.Name = "PickUpPrompt"
	pickupPrompt.Parent = brainrotModel.PrimaryPart
	pickupPrompt.RequiresLineOfSight = false
	pickupPrompt.ActionText = "Pick Up"
	pickupPrompt.UIOffset = Vector2.new(0, -10)
	pickupPrompt.HoldDuration = 0.5
	pickupPrompt.MaxActivationDistance = 10
	
	-- Trigger action
	pickupPrompt.Triggered:Connect(function()
		local Events = ReplicatedStorage:WaitForChild("Events")
		local PlotHandlerEvent = Events:WaitForChild("PlotHandler")
		PlotHandlerEvent:FireServer("Pickup", slotID)
	end)
end

--[[
	Setup ProximityPrompt for selling brainrots (owner only)
	This is positioned higher than the pickup prompt using UIOffset
]]
local function setupSellPrompt(slotModel: Model, slotID: number, brainrotModel: Model, plotOwnerUserId: number?)
	-- Only setup for the owner
	if not plotOwnerUserId or plotOwnerUserId ~= Player.UserId then
		return
	end
	
	if not brainrotModel or not brainrotModel.PrimaryPart then 
		warn("⚠️ Brainrot model or PrimaryPart missing for sell prompt on slot " .. slotID)
		return 
	end
	
	-- Check if prompt already exists (avoid duplicates)
	if brainrotModel.PrimaryPart:FindFirstChild("SellBrainrotPrompt") then
		return
	end
	
	-- Get brainrot data to calculate sell price
	local configName = slotModel:GetAttribute("ConfigName")
	local level = slotModel:GetAttribute("Level") or 1
	local modifier = slotModel:GetAttribute("Modifier") or "Normal"
	local rebirths = Player:GetAttribute("Rebirths") or 0
	
	-- Function to update sell price
	local function updateSellPrice()
		local currentLevel = slotModel:GetAttribute("Level") or 1
		local currentConfigName = slotModel:GetAttribute("ConfigName")
		local currentModifier = slotModel:GetAttribute("Modifier") or "Normal"
		local currentRebirths = Player:GetAttribute("Rebirths") or 0
		
		if currentConfigName and brainrotModel and brainrotModel.PrimaryPart then
			-- Destroy old prompt
			local oldPrompt = brainrotModel.PrimaryPart:FindFirstChild("SellBrainrotPrompt")
			if oldPrompt then
				oldPrompt:Destroy()
			end
			
			-- Calculate new sell price
			local sellPrice = Shared_Brainrots:CalculateSellWorth(currentConfigName, currentLevel, currentModifier, currentRebirths)
			local priceText = "$" .. Shared_Shorten:Number(sellPrice)
			
			-- Create new prompt with updated price
			local sellPrompt = Instance.new("ProximityPrompt")
			sellPrompt.Name = "SellBrainrotPrompt"
			sellPrompt.Parent = brainrotModel.PrimaryPart
			sellPrompt.RequiresLineOfSight = false
			sellPrompt.ObjectText = priceText
			sellPrompt.ActionText = "Sell"
			sellPrompt.HoldDuration = 0.5
			sellPrompt.MaxActivationDistance = 10
			sellPrompt.UIOffset = Vector2.new(0, 70)
			sellPrompt.KeyboardKeyCode = Enum.KeyCode.F
			sellPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			
			-- Reconnect trigger
			sellPrompt.Triggered:Connect(function()
				local Events = ReplicatedStorage:WaitForChild("Events")
				local PlotHandlerEvent = Events:WaitForChild("PlotHandler")
				PlotHandlerEvent:FireServer("SellBrainrot", slotID)
			end)
		end
	end
	
	-- Calculate initial sell price
	local sellPrice = 0
	if configName then
		sellPrice = Shared_Brainrots:CalculateSellWorth(configName, level, modifier, rebirths)
	end
	
	-- Format price for display
	local priceText = "$" .. Shared_Shorten:Number(sellPrice)
	
	-- Create SellPrompt (directly on PrimaryPart, just like pickup but offset higher)
	local sellPrompt = Instance.new("ProximityPrompt")
	sellPrompt.Name = "SellBrainrotPrompt"
	sellPrompt.Parent = brainrotModel.PrimaryPart
	sellPrompt.RequiresLineOfSight = false
	sellPrompt.ObjectText = priceText
	sellPrompt.ActionText = "Sell"
	sellPrompt.HoldDuration = 0.5
	sellPrompt.MaxActivationDistance = 10
	sellPrompt.UIOffset = Vector2.new(0, 70) -- Position UI higher than pickup prompt
	sellPrompt.KeyboardKeyCode = Enum.KeyCode.F
	sellPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX -- Different button for gamepad
	
	-- Listen for Level changes to update sell price
	slotModel:GetAttributeChangedSignal("Level"):Connect(updateSellPrice)
	
	-- Listen for Modifier changes
	slotModel:GetAttributeChangedSignal("Modifier"):Connect(updateSellPrice)
	
	-- Listen for player rebirth changes
	Player:GetAttributeChangedSignal("Rebirths"):Connect(updateSellPrice)
	
	-- Trigger action - directly sell the brainrot from the slot
	sellPrompt.Triggered:Connect(function()
		
		-- Get brainrot info from slot attributes
		local configName = slotModel:GetAttribute("ConfigName")
		local level = slotModel:GetAttribute("Level") or 1
		
		if not configName then
			warn("⚠️ No brainrot found in slot " .. slotID)
			return
		end
		
		-- Fire server to sell the brainrot directly from the slot
		local Events = ReplicatedStorage:WaitForChild("Events")
		local PlotHandlerEvent = Events:WaitForChild("PlotHandler")
		PlotHandlerEvent:FireServer("SellBrainrot", slotID)
	end)
end

--[[
	Setup "Steal Brainrot!" ProximityPrompt on someone else's slot (non-owner only).
	Shown only when slot has a brainrot (ConfigName set). Fires PurchaseHandler with context for Option B.
	Reacts to plot OwnerUserId so when a player leaves/rejoins (attribute changes) prompts update.
]]
local function setupStealPrompt(slotModel: Model, slotID: number, plotOwnerUserId: number?)
	local part = slotModel:FindFirstChild("StandingPart") or slotModel.PrimaryPart or slotModel:FindFirstChildWhichIsA("BasePart")
	if not part then return end

	local plotModel = slotModel.Parent and slotModel.Parent.Parent
	if not plotModel then return end

	-- Track current owner so we react when they leave/rejoin (OwnerUserId changes)
	local currentOwner = plotOwnerUserId
	local stealPrompt = nil

	local function getStealPromptActionText()
		local configName = slotModel:GetAttribute("ConfigName")
		local config = configName and Shared_Brainrots.List[configName]
		local rarity = config and config.Rarity
		local replica = Client_Data:GetReplica()
		local creditsTable = (replica and replica.Data and type(replica.Data.StealCredits) == "table") and replica.Data.StealCredits or {}
		local credits = (type(rarity) == "string" and type(creditsTable[rarity]) == "number") and creditsTable[rarity] or 0
		if credits > 0 then
			return "Steal Brainrot! (" .. credits .. ")"
		end
		return "Steal Brainrot!"
	end

	local function updateStealPromptActionText()
		if stealPrompt and stealPrompt.Parent then
			stealPrompt.ActionText = getStealPromptActionText()
		end
	end

	local function updateStealPrompt()
		local owner = currentOwner
		if type(owner) ~= "number" or owner == Player.UserId then
			if stealPrompt then
				stealPrompt:Destroy()
				stealPrompt = nil
			end
			return
		end
		local configName = slotModel:GetAttribute("ConfigName")
		if configName then
			if not stealPrompt then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "StealBrainrotPrompt"
				prompt.RequiresLineOfSight = false
				prompt.ActionText = getStealPromptActionText()
				prompt.HoldDuration = 0.5
				prompt.MaxActivationDistance = 10
				prompt.Parent = part
				prompt.Triggered:Connect(function()
					local Events = ReplicatedStorage:FindFirstChild("Events")
					local purchaseHandler = Events and Events:FindFirstChild("PurchaseHandler")
					if purchaseHandler and type(currentOwner) == "number" then
						purchaseHandler:FireServer(0, { type = "StealBrainrot", targetUserId = currentOwner, slotID = slotID })
					end
				end)
				stealPrompt = prompt
				-- Update prompt text when steal credits change (replica)
				local replica = Client_Data:GetReplica()
				if replica then
					replica:ListenToChange({"StealCredits"}, updateStealPromptActionText)
				end
			else
				updateStealPromptActionText()
			end
		else
			if stealPrompt then
				stealPrompt:Destroy()
				stealPrompt = nil
			end
		end
	end

	local function onOwnerChanged()
		currentOwner = plotModel:GetAttribute("OwnerUserId")
		updateStealPrompt()
	end

	plotModel:GetAttributeChangedSignal("OwnerUserId"):Connect(onOwnerChanged)
	onOwnerChanged()
	slotModel:GetAttributeChangedSignal("ConfigName"):Connect(updateStealPrompt)
end

--[[
	Monitor slot for brainrot model being added/removed (for pickup and sell prompts, owner only)
]]
local function monitorSlotForBrainrot(slotModel: Model, slotID: number, plotOwnerUserId: number?)
	if not plotOwnerUserId or plotOwnerUserId ~= Player.UserId then
		return
	end
	
	local function checkForBrainrot()
		-- Find brainrot model in slot (named "PlacedBrainrot")
		local brainrotModel = slotModel:FindFirstChild("PlacedBrainrot")
		
		if brainrotModel and brainrotModel:IsA("Model") then
			setupPickupPrompt(slotModel, slotID, brainrotModel)
			setupSellPrompt(slotModel, slotID, brainrotModel, plotOwnerUserId)
			return
		end
	end
	
	checkForBrainrot()
	
	-- Listen for brainrot being added
	slotModel.ChildAdded:Connect(function(child)
		if child:IsA("Model") and child.Name == "PlacedBrainrot" then
			task.wait(0.1) -- Wait for PrimaryPart to be set
			checkForBrainrot()
		end
	end)
	
	-- Also check when ConfigName changes (server sets this)
	slotModel:GetAttributeChangedSignal("ConfigName"):Connect(function()
		local configName = slotModel:GetAttribute("ConfigName")
		if configName then
			task.wait(0.2) -- Give server time to create the model
			checkForBrainrot()
		end
	end)
end

--[[
	Setup a single slot (key by slotModel so every plot's slots get set up).
	When the server destroys slots on plot release and later adds new ones (same path),
	we must allow re-setup: clear the key when this slot instance is destroyed.
]]
local function setupSlot(slotModel: Model, slotID: number, plotOwnerUserId: number?)
	local key = slotModel:GetFullName() -- e.g. Game.Plots.Plot1.Slots.Slot1
	if SetupSlots[key] then return end
	SetupSlots[key] = true

	-- Allow the same path to be set up again when server replaces slots (release → reclaim)
	slotModel.Destroying:Once(function()
		SetupSlots[key] = nil
	end)

	setupPlaceBrainrotPrompt(slotModel, slotID, plotOwnerUserId)
	setupCashCollection(slotModel, slotID, plotOwnerUserId)
	setupUpgradeUI(slotModel, slotID, plotOwnerUserId)
	setupStealPrompt(slotModel, slotID, plotOwnerUserId)
	monitorSlotForBrainrot(slotModel, slotID, plotOwnerUserId)
end

--[[
	Initialize slot interaction system
]]
function Module:Init()
	-- Get Client_Sounds from Library (set by init.client.lua)
	Client_Sounds = self.Client_Sounds
	
	Client_Data:WaitUntilReady()
	
	local Workspace = game:GetService("Workspace")
	local gameFolder = Workspace:WaitForChild("Game", 10)
	if not gameFolder then 
		warn("⚠️ Game folder not found in Workspace")
		return 
	end
	
	local plotsFolder = gameFolder:WaitForChild("Plots", 10)
	if not plotsFolder then 
		warn("⚠️ Plots folder not found in Game")
		return 
	end
	
	-- Helper: set up all slots for one plot
	local function setupPlotSlots(plotModel)
		if not plotModel:IsA("Model") then return end
		local slotsFolder = plotModel:FindFirstChild("Slots")
		if not slotsFolder then return end
		local plotOwnerUserId = plotModel:GetAttribute("OwnerUserId")
		for _, slotModel in ipairs(slotsFolder:GetChildren()) do
			if slotModel:IsA("Model") then
				local slotNum = tonumber(slotModel.Name:match("%d+"))
				if slotNum then
					setupSlot(slotModel, slotNum, plotOwnerUserId)
				end
			end
		end
	end
	
	local function trySetupSlotModel(slotModel: Instance, plotModel: Model)
		if not slotModel:IsA("Model") then
			return
		end
		local slotNum = tonumber(slotModel.Name:match("%d+"))
		if not slotNum then
			return
		end
		setupSlot(slotModel, slotNum, plotModel:GetAttribute("OwnerUserId"))
	end

	local function watchPlotSlots(plotModel: Model)
		setupPlotSlots(plotModel)
		local slotsFolder = plotModel:FindFirstChild("Slots")
		if not slotsFolder then
			return
		end
		slotsFolder.ChildAdded:Connect(function(slotModel)
			task.defer(function()
				trySetupSlotModel(slotModel, plotModel)
			end)
		end)
	end

	for _, plotModel in ipairs(plotsFolder:GetChildren()) do
		if plotModel:IsA("Model") then
			watchPlotSlots(plotModel)
		end
	end

	plotsFolder.ChildAdded:Connect(function(plotModel)
		task.defer(function()
			if plotModel:IsA("Model") then
				watchPlotSlots(plotModel)
			end
		end)
	end)

	plotsFolder.DescendantAdded:Connect(function(descendant)
		if not descendant:IsA("Model") or not descendant.Name:match("^Slot%d+$") then
			return
		end
		local slotsFolder = descendant.Parent
		local plotModel = slotsFolder and slotsFolder.Parent
		if not plotModel or slotsFolder.Name ~= "Slots" then
			return
		end
		task.defer(function()
			trySetupSlotModel(descendant, plotModel)
		end)
	end)

	local function setupOwnedPlot()
		local plotID = Player:GetAttribute("CurrentPlot")
		if type(plotID) ~= "number" then
			return
		end
		local plotModel = plotsFolder:FindFirstChild("Plot" .. plotID)
		if plotModel and plotModel:IsA("Model") then
			watchPlotSlots(plotModel)
		end
	end

	task.spawn(function()
		local deadline = os.clock() + 20
		while not Player:GetAttribute("CurrentPlot") and os.clock() < deadline do
			task.wait(0.1)
		end
		setupOwnedPlot()
	end)

	Player:GetAttributeChangedSignal("CurrentPlot"):Connect(setupOwnedPlot)
end

-- Cleanup function (called when plot changes or module is destroyed)
function Module:Cleanup()
	-- Clear all upgrade button registrations
	for slotID in pairs(UpgradeButtons) do
		unregisterUpgradeButton(slotID)
	end
	
	-- Clear setup tracking
	SetupSlots = {}
end

return Module
