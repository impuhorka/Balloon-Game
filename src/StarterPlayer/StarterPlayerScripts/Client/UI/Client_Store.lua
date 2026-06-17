--[[
	Client_Store.lua
	
	Handles Store UI for Gamepasses and Lucky Blocks
	- CashGamepass (2x brainrot income multiplier)
	- VIP, SpeedBoost (in GamepassHolder)
	- Sniper, AdminTablet (in GamepassHolder2)
	- Lucky Blocks (GodLuckyBlock, MythicalPlusLuckyBlock, OPLuckyBlock)
	
	Features:
	- Robux price fetching from MarketplaceService
	- Purchase prompts (PromptGamePassPurchase / PromptProductPurchase)
	- Owned state display for gamepasses
	- Gift system support (button present, implementation later)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local Client_Data = require(script.Parent.Parent.Core.Client_Data)
local Client_PolicyService = require(script.Parent.Parent.Core.Client_PolicyService)
local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
local Shared_Marketplace = require(ReplicatedStorage.Modules.Settings.Shared_Marketplace)
local Shared_LuckyBlocks = require(ReplicatedStorage.Modules.ItemConfigs.Shared_LuckyBlocks)
local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
local Shared_Rarity = require(ReplicatedStorage.Modules.Gameplay.Shared_Rarity)
local Shared_ModifierHandler = require(ReplicatedStorage.Modules.Gameplay.Shared_ModifierHandler)

local Module = {}

-- Will be set in Init (from Library)
local Client_Sounds = nil

-- Gamepass IDs (from shared config)
local GAMEPASS_IDS = Shared_Marketplace.Passes

-- Lucky Block Product IDs (from shared config)
local LUCKYBLOCK_PRODUCTS = {
	GodLuckyBlock = {
		Buy1 = Shared_Marketplace.Products["LuckyBlock1"],
		Buy3 = Shared_Marketplace.Products["LuckyBlock1_3x"],
	},
	MythicalPlusLuckyBlock = {
		Buy1 = Shared_Marketplace.Products["LuckyBlock2"],
		Buy3 = Shared_Marketplace.Products["LuckyBlock2_3x"],
	},
	OPLuckyBlock = {
		Buy1 = Shared_Marketplace.Products["LuckyBlock3"],
		Buy3 = Shared_Marketplace.Products["LuckyBlock3_3x"],
	},
}

-- Cached references
local replicaCache = nil
local storeFrame = nil

-- Price cache (prevent UI flashing, same pattern as SpeedStore)
local robuxPriceCache = {}

local function isValidMarketplaceId(id: any): boolean
	return type(id) == "number" and id > 0
end

local function markButtonUnavailable(button: Instance?, label: TextLabel?, reason: string?)
	if label then
		label.Text = reason or "Unavailable"
	end
	if button and button:IsA("GuiButton") then
		button.Active = false
		button.AutoButtonColor = false
	end
end

-- Animation state
local animationConnection = nil
local luckyBlockViewModels = {} -- Store references to ViewModels for animation with position data

-- Roulette animation state
local rouletteConnection = nil
local rouletteData = {} -- Store roulette templates and state for each lucky block

-- ========================================
-- CACHED HELPERS
-- ========================================

--- Get cached replica
local function getReplica()
	if not replicaCache and Client_Data then
		replicaCache = Client_Data:GetReplica()
	end
	return replicaCache
end

--- Check if player owns a gamepass (from replica data)
local function ownsGamepass(passName: string): boolean
	local replica = getReplica()
	if not replica then return false end
	
	local passes = replica.Data.Passes or {}
	return passes[passName] == true
end

--- Cache Robux price for a gamepass or product
local function cachePrice(productId: number, infoType)
	infoType = infoType or Enum.InfoType.GamePass
	if not isValidMarketplaceId(productId) then
		return nil
	end
	
	if robuxPriceCache[productId] then
		return robuxPriceCache[productId]
	end
	
	-- Fetch price asynchronously
	task.spawn(function()
		local success, productInfo = pcall(function()
			return MarketplaceService:GetProductInfo(productId, infoType)
		end)
		
		if success and productInfo and productInfo.PriceInRobux then
			robuxPriceCache[productId] = productInfo.PriceInRobux
		else
			robuxPriceCache[productId] = nil
			warn("⚠️ Client_Store: Failed to cache price for ID:", productId)
		end
	end)
	
	return nil
end

--- Pre-cache all gamepass and product prices on init
local function precacheAllPrices()
	-- Cache gamepass prices
	for _, passId in pairs(GAMEPASS_IDS) do
		if passId and passId > 0 then
			cachePrice(passId, Enum.InfoType.GamePass)
		end
	end
	
	-- Cache lucky block product prices
	for _, blockData in pairs(LUCKYBLOCK_PRODUCTS) do
		if blockData.Buy1 and blockData.Buy1 > 0 then
			cachePrice(blockData.Buy1, Enum.InfoType.Product)
		end
		if blockData.Buy3 and blockData.Buy3 > 0 then
			cachePrice(blockData.Buy3, Enum.InfoType.Product)
		end
	end
	
end

-- ========================================
-- CASH PRODUCTS SETUP
-- ========================================

--- Setup a cash purchase product (Cash1, Cash2, Cash3)
--- @param cashFrame Frame - The cash product UI container
--- @param productName string - Product name (e.g., "Cash1")
--- @param cashAmount number - Amount of cash this product gives
local function setupCashProduct(cashFrame: Frame, productName: string, cashAmount: number)
	if not cashFrame then return end
	
	local productId = Shared_Marketplace.Products[productName]
	
	-- Update Title with cash amount
	local titleLabel = cashFrame:FindFirstChild("Title")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = Shared_Shorten:Number(cashAmount) .. " Cash"
	end
	
	-- Find Buy button
	local buySection = cashFrame:FindFirstChild("Buy")
	local buyButton = buySection and buySection:FindFirstChild("Button")
	local priceLabel = buyButton and buyButton:FindFirstChild("Title")
	
	if not buyButton then
		warn("⚠️ Client_Store: No Buy button in", productName)
		return
	end
	if not isValidMarketplaceId(productId) then
		markButtonUnavailable(buyButton, priceLabel, "Unavailable")
		return
	end
	
	-- Setup price display
	if priceLabel then
		local cachedPrice = cachePrice(productId, Enum.InfoType.Product)
		if cachedPrice then
			priceLabel.Text = "R$" .. tostring(cachedPrice)
		else
			priceLabel.Text = "Loading..."
			
			task.spawn(function()
				local success, productInfo = pcall(function()
					return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
				end)
				
				if success and productInfo and productInfo.PriceInRobux then
					robuxPriceCache[productId] = productInfo.PriceInRobux
					priceLabel.Text = "R$" .. tostring(productInfo.PriceInRobux)
				else
					priceLabel.Text = "Buy"
					warn("⚠️ Client_Store: Failed to get price for", productName)
				end
			end)
		end
	end
	
	-- Connect purchase handler
	buyButton.Activated:Connect(function()
		-- Server will FireClient(PurchaseHandler); client listener shows rainbow + prompt
		local events = ReplicatedStorage:FindFirstChild("Events")
		local purchaseHandler = events and events:FindFirstChild("PurchaseHandler")
		if purchaseHandler then
			purchaseHandler:FireServer(productId)
		end
	end)
end

-- ========================================
-- GAMEPASS SETUP
-- ========================================

--- Setup a gamepass card (CashGamepass, VIP, SpeedBoost)
--- @param gamepassFrame Frame - The gamepass UI container
--- @param passName string - Name of the pass (e.g., "CashBoost", "VIP", "SpeedBoost")
--- @param passId number - Gamepass ID
local function setupGamepassCard(gamepassFrame: Frame, passName: string, passId: number)
	if not gamepassFrame then return end
	
	-- Find UI elements
	local buttons = gamepassFrame:FindFirstChild("Buttons")
	local info = gamepassFrame:FindFirstChild("Info")
	
	if not buttons then
		warn("⚠️ Client_Store: No Buttons in", passName)
		return
	end
	
	local robuxSection = buttons:FindFirstChild("Robux")
	local giftSection = buttons:FindFirstChild("Gift")
	local ownedFrame = gamepassFrame:FindFirstChild("Owned")
	
	if not robuxSection or not giftSection then
		warn("⚠️ Client_Store: Missing Robux or Gift section in", passName)
		return
	end
	
	local robuxButton = robuxSection:FindFirstChild("Button")
	local giftButton = giftSection:FindFirstChild("Button")
	local priceLabel = robuxButton and robuxButton:FindFirstChild("Title")
	if not isValidMarketplaceId(passId) then
		markButtonUnavailable(robuxButton, priceLabel, "Unavailable")
		markButtonUnavailable(giftButton, nil, nil)
		if ownedFrame then ownedFrame.Visible = false end
		return
	end
	
	-- Find Info elements for name and description
	local titleLabel = info and info:FindFirstChild("Title")
	local descriptionLabel = info and info:FindFirstChild("Description")
	
	-- Check if player owns this gamepass
	local isOwned = ownsGamepass(passName)
	
	--- Update UI based on ownership
	local function updateOwnershipDisplay(owned: boolean)
		if owned then
			-- Show "Owned" indicator
			if ownedFrame then ownedFrame.Visible = true end
		else
			-- Hide "Owned" indicator
			if ownedFrame then ownedFrame.Visible = false end
		end
	end
	
	-- Initial display
	updateOwnershipDisplay(isOwned)
	
	-- Setup price display and fetch gamepass info (name + description)
	if priceLabel then
		-- Try to get cached price first
		local cachedPrice = cachePrice(passId, Enum.InfoType.GamePass)
		if cachedPrice then
			priceLabel.Text = "R$" .. tostring(cachedPrice)
		else
			-- Set loading text while fetching
			priceLabel.Text = "Loading..."
			
			-- Fetch price and gamepass info with proper error handling
			task.spawn(function()
				local success, gamepassInfo = pcall(function()
					return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
				end)
				
				if success and gamepassInfo then
					-- Update price
					if gamepassInfo.PriceInRobux then
						robuxPriceCache[passId] = gamepassInfo.PriceInRobux
						priceLabel.Text = "R$" .. tostring(gamepassInfo.PriceInRobux)
					else
						priceLabel.Text = "Purchase"
					end
					
					-- Update title with gamepass name
					if titleLabel and gamepassInfo.Name then
						titleLabel.Text = gamepassInfo.Name
					end
					
					-- Update description with gamepass description
					if descriptionLabel and gamepassInfo.Description then
						descriptionLabel.Text = gamepassInfo.Description
					end
				else
					priceLabel.Text = "Purchase"
					warn("⚠️ Client_Store: Failed to get info for", passName, "ID:", passId)
				end
			end)
		end
	end
	
	-- Setup Robux button (purchase gamepass)
	if robuxButton then
		robuxButton.Activated:Connect(function()
			-- Check if player already owns this gamepass
			if ownsGamepass(passName) then
				-- Player already owns it - show popup
				local Client_Popups = require(script.Parent.Client_Popups)
				if Client_Popups then
					Client_Popups:AddPopupImmediate("You already own this gamepass!", "error")
				end
				return
			end
			
			-- Notify purchase prompt system (rainbow effect)
			if Module.Client_PurchasePrompt then
				Module.Client_PurchasePrompt:OnPromptOpening()
			end
			
			-- Prompt gamepass purchase
			local success, err = pcall(function()
				MarketplaceService:PromptGamePassPurchase(Player, passId)
			end)
			
			if not success then
				warn("⚠️ Client_Store: Failed to prompt gamepass purchase:", err)
			end
		end)
	end
	
	-- Setup Gift button: open gamepass gifting UI with this pass selected
	if giftButton then
		giftButton.Activated:Connect(function()
			-- Owning the gamepass yourself does not block gifting it to others
			local Events = ReplicatedStorage:FindFirstChild("Events")
			if not Events then return end
			local openGifting = Events:FindFirstChild("OpenGiftingUI")
			if not openGifting then
				openGifting = Instance.new("BindableEvent")
				openGifting.Name = "OpenGiftingUI"
				openGifting.Parent = Events
			end
			if openGifting:IsA("BindableEvent") then
				openGifting:Fire(passName)
			end
		end)
	end
	
	-- Listen for ownership changes (when player purchases)
	local replica = getReplica()
	if replica then
		replica:ListenToChange({"Passes", passName}, function(newValue)
			updateOwnershipDisplay(newValue == true)
		end)
	end
end

-- ========================================
-- LUCKY BLOCKS SETUP
-- ========================================

--- Setup a lucky block card (GodLuckyBlock, MythicalPlusLuckyBlock, OPLuckyBlock)
--- @param luckyBlockFrame Frame - The lucky block UI container
--- @param blockName string - Name of the block (e.g., "GodLuckyBlock")
local function setupLuckyBlockCard(luckyBlockFrame: Frame, blockName: string)
	if not luckyBlockFrame then return end
	
	local productIds = LUCKYBLOCK_PRODUCTS[blockName]
	if not productIds then
		warn("⚠️ Client_Store: No product IDs for", blockName)
		return
	end
	
	-- Find Buttons section
	local buttons = luckyBlockFrame:FindFirstChild("Buttons")
	if not buttons then
		warn("⚠️ Client_Store: No Buttons in", blockName)
		return
	end
	
	-- Setup Buy1 button
	local buy1Section = buttons:FindFirstChild("Buy1")
	local buy1Button = buy1Section and buy1Section:FindFirstChild("Button")
	local buy1PriceLabel = buy1Button and buy1Button:FindFirstChild("Title")
	
	if buy1Button and buy1PriceLabel and isValidMarketplaceId(productIds.Buy1) then
		-- Fetch and display price
		local cachedPrice = cachePrice(productIds.Buy1, Enum.InfoType.Product)
		if cachedPrice then
			buy1PriceLabel.Text = "R$" .. tostring(cachedPrice)
		else
			buy1PriceLabel.Text = "Loading..."
			
			task.spawn(function()
				local success, productInfo = pcall(function()
					return MarketplaceService:GetProductInfo(productIds.Buy1, Enum.InfoType.Product)
				end)
				
				if success and productInfo and productInfo.PriceInRobux then
					robuxPriceCache[productIds.Buy1] = productInfo.PriceInRobux
					buy1PriceLabel.Text = "R$" .. tostring(productInfo.PriceInRobux)
				else
					buy1PriceLabel.Text = "Buy 1"
					warn("⚠️ Client_Store: Failed to get price for", blockName, "Buy1")
				end
			end)
		end
		
		-- Connect purchase handler
		buy1Button.Activated:Connect(function()
			-- Gambling policy: block lucky block purchase if not allowed in region
			if Client_PolicyService:IsGamblingProduct(productIds.Buy1) and not Client_PolicyService:IsGamblingAllowed() then
				local Client_Popups = require(script.Parent.Client_Popups)
				if Client_Popups then
					Client_Popups:AddPopupImmediate(Client_PolicyService:GetRestrictionMessage(), false)
				end
				return
			end
			-- Server will FireClient(PurchaseHandler); client listener shows rainbow + prompt
			local events = ReplicatedStorage:FindFirstChild("Events")
			local purchaseHandler = events and events:FindFirstChild("PurchaseHandler")
			if purchaseHandler then
				purchaseHandler:FireServer(productIds.Buy1)
			end
		end)
	elseif buy1Button then
		markButtonUnavailable(buy1Button, buy1PriceLabel, "Unavailable")
	end
	
	-- Setup Buy3 button
	local buy3Section = buttons:FindFirstChild("Buy3")
	local buy3Button = buy3Section and buy3Section:FindFirstChild("Button")
	local buy3PriceLabel = buy3Button and buy3Button:FindFirstChild("Title")
	
	if buy3Button and buy3PriceLabel and isValidMarketplaceId(productIds.Buy3) then
		-- Fetch and display price
		local cachedPrice = cachePrice(productIds.Buy3, Enum.InfoType.Product)
		if cachedPrice then
			buy3PriceLabel.Text = "R$" .. tostring(cachedPrice)
		else
			buy3PriceLabel.Text = "Loading..."
			
			task.spawn(function()
				local success, productInfo = pcall(function()
					return MarketplaceService:GetProductInfo(productIds.Buy3, Enum.InfoType.Product)
				end)
				
				if success and productInfo and productInfo.PriceInRobux then
					robuxPriceCache[productIds.Buy3] = productInfo.PriceInRobux
					buy3PriceLabel.Text = "R$" .. tostring(productInfo.PriceInRobux)
				else
					buy3PriceLabel.Text = "Buy 3"
					warn("⚠️ Client_Store: Failed to get price for", blockName, "Buy3")
				end
			end)
		end
		
		-- Connect purchase handler
		buy3Button.Activated:Connect(function()
			-- Gambling policy: block lucky block purchase if not allowed in region
			if Client_PolicyService:IsGamblingProduct(productIds.Buy3) and not Client_PolicyService:IsGamblingAllowed() then
				local Client_Popups = require(script.Parent.Client_Popups)
				if Client_Popups then
					Client_Popups:AddPopupImmediate(Client_PolicyService:GetRestrictionMessage(), false)
				end
				return
			end
			-- Server will FireClient(PurchaseHandler); client listener shows rainbow + prompt
			local events = ReplicatedStorage:FindFirstChild("Events")
			local purchaseHandler = events and events:FindFirstChild("PurchaseHandler")
			if purchaseHandler then
				purchaseHandler:FireServer(productIds.Buy3)
			end
		end)
	elseif buy3Button then
		markButtonUnavailable(buy3Button, buy3PriceLabel, "Unavailable")
	end
end

-- ========================================
-- VIEWPORT ANIMATION
-- ========================================

--- Get mouse/camera direction for viewport rotation
local function getTargetDirection(): Vector3
	-- Check input type
	local lastInputType = UserInputService:GetLastInputType()
	local isUsingMouse = lastInputType == Enum.UserInputType.MouseMovement or 
	                     lastInputType == Enum.UserInputType.MouseButton1 or
	                     lastInputType == Enum.UserInputType.MouseButton2
	
	if isUsingMouse then
		-- PC: Use mouse position (more pronounced for better visibility)
		local mousePos = UserInputService:GetMouseLocation()
		local camera = workspace.CurrentCamera
		local viewportSize = camera.ViewportSize
		
		-- Normalize mouse position to -1 to 1 range
		local normalizedX = (mousePos.X / viewportSize.X) * 2 - 1
		local normalizedY = (mousePos.Y / viewportSize.Y) * 2 - 1
		
		-- Stronger multiplier (1.0 instead of 0.25) for more noticeable rotation
		return Vector3.new(normalizedX * 1.0, normalizedY * 1.0, 1).Unit
	end
	
	-- Mobile/Console: Use device orientation (gyroscope)
	if UserInputService.GyroscopeEnabled then
		local rotation, cframe = UserInputService:GetDeviceRotation()
		if rotation and cframe then
			-- Extract rotation angles from device orientation
			local x, y, z = cframe:ToOrientation()
			
			-- Y = yaw (rotate left/right like steering wheel) - use for horizontal rotation
			-- Don't use X (pitch) - we only want left/right rotation, not up/down
			local normalizedX = math.clamp(math.deg(y) / 30, -1, 1) * 0.5  -- Yaw for horizontal
			local normalizedY = 0  -- No vertical rotation from gyro
			
			return Vector3.new(-normalizedX, normalizedY, 1).Unit
		end
	end
	
	-- Fallback for devices without gyroscope: subtle idle animation
	local time = tick()
	local idleX = math.sin(time * 0.5) * 0.08 -- Slow sine wave for X
	local idleY = math.cos(time * 0.3) * 0.08 -- Slower cosine wave for Y
	
	return Vector3.new(idleX, idleY, 1).Unit
end

--- Update lucky block viewport rotations (orbit camera instead of moving model)
local lastViewportUpdate = 0
local cachedMousePos = Vector2.new(0, 0)
local cachedTargetDir = Vector3.new(0, 0, 1)
local cachedTime = 0

local function updateViewportRotations()
	if not storeFrame or not storeFrame.Visible then return end
	
	-- Throttle to 30fps
	local now = tick()
	if now - lastViewportUpdate < 1/30 then return end
	lastViewportUpdate = now
	cachedTime = now -- Cache tick() for this frame
	
	-- Update target direction (mouse/gyro)
	cachedTargetDir = getTargetDirection()
	
	-- Lerp factor for smooth rotation
	local lerpFactor = 0.1
	
	-- Bobbing animation (up and down)
	local bobbingOffset = math.sin(cachedTime * 1.8) * 0.5 -- Faster and larger bobbing
	
	for blockName, viewModelData in pairs(luckyBlockViewModels) do
		local camera = viewModelData.camera
		local baseCameraCFrame = viewModelData.baseCameraCFrame
		local modelCenter = viewModelData.modelCenter
		local layoutOrder = viewModelData.layoutOrder or 0
		
		if camera and baseCameraCFrame and modelCenter then
			-- Calculate parallax multiplier based on layout order and mouse position
			-- Blocks FURTHER from mouse rotate MORE (inverse parallax)
			-- LayoutOrder 1 (left) + mouse on right = rotate more right
			-- LayoutOrder 3 (right) + mouse on left = rotate more left
			local parallaxMultiplier = 1.0 + (layoutOrder * math.abs(cachedTargetDir.X) * 0.15)
			parallaxMultiplier = math.clamp(parallaxMultiplier, 1.0, 1.5)
			
			-- Calculate rotation angles (inverted for correct direction)
			local rotationStrength = 45 * parallaxMultiplier
			local yaw = math.rad(-cachedTargetDir.X * rotationStrength) -- Inverted X
			local pitch = math.rad(-cachedTargetDir.Y * rotationStrength * 1.5) -- Inverted Y
			
			-- Orbit camera around model center
			local offset = baseCameraCFrame.Position - modelCenter
			local distance = offset.Magnitude
			
			-- Create rotation around model center, then offset camera back
			local targetCFrame = CFrame.new(modelCenter)
				* CFrame.Angles(pitch, yaw, 0) -- Rotate orbit
				* CFrame.new(0, bobbingOffset, distance) -- Move camera back + bobbing
				* CFrame.Angles(-math.pi/2, 0, 0) -- Look at center
			
			-- Make camera look at model center
			targetCFrame = CFrame.new(targetCFrame.Position, modelCenter + Vector3.new(0, bobbingOffset, 0))
			
			-- Lerp for smooth animation
			camera.CFrame = camera.CFrame:Lerp(targetCFrame, lerpFactor)
		end
	end
end

--- Stop viewport animations
local function stopViewportAnimations()
	if animationConnection then
		animationConnection:Disconnect()
		animationConnection = nil
	end
	
	-- Reset all cameras to base position
	for blockName, viewModelData in pairs(luckyBlockViewModels) do
		local camera = viewModelData.camera
		local baseCameraCFrame = viewModelData.baseCameraCFrame
		
		if camera and baseCameraCFrame then
			camera.CFrame = baseCameraCFrame
		end
	end
end

--- Start viewport animations
local function startViewportAnimations()
	-- Stop existing connection if any
	stopViewportAnimations()
	
	-- Connect to Heartbeat for 30fps animation (more optimized than RenderStepped's 60fps)
	animationConnection = RunService.Heartbeat:Connect(updateViewportRotations)
end

--- Setup viewport animation for a lucky block frame
--- @param luckyBlockFrame Frame - The lucky block UI container
--- @param blockName string - Name of the block (for tracking)
local function setupViewportAnimation(luckyBlockFrame: Frame, blockName: string)
	if not luckyBlockFrame then return end
	
	local viewportFrame = luckyBlockFrame:FindFirstChild("ViewportFrame")
	if not viewportFrame or not viewportFrame:IsA("ViewportFrame") then
		warn("⚠️ Client_Store: No ViewportFrame in", blockName)
		return
	end
	
	local viewModel = viewportFrame:FindFirstChild("ViewModel")
	if not viewModel or not viewModel:IsA("Model") then
		warn("⚠️ Client_Store: No ViewModel in ViewportFrame for", blockName)
		return
	end
	
	-- Get or create camera
	local camera = viewportFrame:FindFirstChildOfClass("Camera")
	if not camera then
		camera = Instance.new("Camera")
		camera.Parent = viewportFrame
		viewportFrame.CurrentCamera = camera
	end
	
	-- Fixed camera distance (no bounding box calculation)
	local modelCenter = viewModel:GetPivot().Position
	local distance = 12 -- Fixed distance from model
	-- Position camera in front of model, looking at the center
	local baseCameraCFrame = CFrame.new(modelCenter + Vector3.new(0, 0, distance), modelCenter)
	camera.CFrame = baseCameraCFrame
	
	-- Get LayoutOrder for parallax effect (cached for optimization)
	local layoutOrder = luckyBlockFrame.LayoutOrder or 0
	
	-- Store reference with base camera CFrame
	luckyBlockViewModels[blockName] = {
		camera = camera,
		baseCameraCFrame = baseCameraCFrame,
		modelCenter = modelCenter, -- Store model center for orbiting
		layoutOrder = layoutOrder,
	}
end

-- ========================================
-- ROULETTE ANIMATION
-- ========================================

--- Setup viewport model for a brainrot (Normal + modifier visuals via Shared_ModifierHandler)
local function setupViewportModel(viewportFrame, configName, modifier)
	if not viewportFrame then return end
	local worldModel = viewportFrame:FindFirstChildOfClass("WorldModel")
	if not worldModel then
		worldModel = Instance.new("WorldModel")
		worldModel.Parent = viewportFrame
	end
	worldModel:ClearAllChildren()
	local model = Shared_ModifierHandler:GetBrainrotModel(configName, modifier or "Normal")
	if not model then return end
	model.Name = "ViewportModel"
	model.Parent = worldModel
	local cf, size = model:GetBoundingBox()
	local maxSize = math.max(size.X, size.Y, size.Z)
	local distance = maxSize * 0.8
	local camPos = cf.Position + Vector3.new(distance, size.Y * 0.2, distance * 0.6)
	local camera = viewportFrame.CurrentCamera
	if not camera then
		camera = Instance.new("Camera")
		camera.Parent = viewportFrame
		viewportFrame.CurrentCamera = camera
	end
	camera.CFrame = CFrame.lookAt(camPos, cf.Position)
end

--- Update a roulette template with reward data
local function updateRouletteTemplate(template, configName, rarity, chance)
	if not template then return end
	
	-- Setup ViewportFrame (no idle animation)
	local viewportFrame = template:FindFirstChild("ViewportFrame")
	if viewportFrame then
		setupViewportModel(viewportFrame, configName, "Normal")
	end
	
	-- Update Chance text (smart formatting: remove unnecessary decimals)
	local chanceLabel = template:FindFirstChild("Chance")
	if chanceLabel then
		-- Show chance straight up (6 → "6%", 5.9 → "5.9%", 0.01 → "0.01%")
		chanceLabel.Text = string.format("%g%%", chance)
		
		-- Update UIGradient for rarity (use Shared_Rarity like billboards do)
		local gradient = chanceLabel:FindFirstChildOfClass("UIGradient")
		if gradient then
			local rarityInfo = Shared_Rarity.List[rarity]
			if rarityInfo and rarityInfo.gradient then
				gradient.Color = rarityInfo.gradient
				gradient.Rotation = (rarityInfo.isRainbow and 0) or 90  -- Rainbow 0°, others 90°
			end
		end
	end
end

--- Setup roulette for a lucky block
local function setupRoulette(luckyBlockFrame, blockName)
	if not luckyBlockFrame then return end
	
	local listHolder = luckyBlockFrame:FindFirstChild("ListHolder")
	local template = listHolder and listHolder:FindFirstChild("Template")
	
	if not listHolder or not template then
		warn("⚠️ Client_Store: No ListHolder or Template in", blockName)
		return
	end
	
	-- Get rewards from Lucky Block config
	local luckyBlockConfig = Shared_LuckyBlocks.List[blockName]
	if not luckyBlockConfig or not luckyBlockConfig.Reward then
		warn("⚠️ Client_Store: No config for", blockName)
		return
	end
	
	-- Build reward list with chances
	local rewards = {}
	local totalWeight = 0
	
	for configName, weight in pairs(luckyBlockConfig.Reward) do
		local brainrotData = Shared_Brainrots.List[configName]
		if brainrotData then
			totalWeight = totalWeight + weight
			table.insert(rewards, {
				configName = configName,
				rarity = brainrotData.Rarity,
				weight = weight
			})
		end
	end
	
	-- Sort rewards by weight (highest first, lowest last)
	table.sort(rewards, function(a, b)
		return a.weight > b.weight
	end)
	
	-- Hide original template
	template.Visible = false
	
	-- Create clones for roulette effect (one per reward, minimum 6 for smooth animation)
	local numClones = math.max(#rewards, 6)
	local clones = {}
	
	for i = 1, numClones do
		local clone = template:Clone()
		clone.Name = "RouletteItem" .. i
		clone.Visible = true
		clone.Parent = listHolder
		
		-- Pick reward (cycle through rewards list)
		local rewardIndex = ((i - 1) % #rewards) + 1
		local reward = rewards[rewardIndex]
		
		-- Display raw weight from config as chance (e.g. 30 → "30%", 0.1 → "0.1%")
		updateRouletteTemplate(clone, reward.configName, reward.rarity, reward.weight)
		
		table.insert(clones, clone)
	end
	
	-- Store roulette data
	rouletteData[blockName] = {
		listHolder = listHolder,
		clones = clones,
		rewards = rewards,
		scrollOffset = 0,
		-- Cache for performance
		templateScale = clones[1].Size.X.Scale,
		spacing = 0.01,
	}
	
	-- Pre-calculate static values with safeguards
	local data = rouletteData[blockName]
	data.itemSpacing = data.templateScale + data.spacing
	data.totalWidth = data.itemSpacing * #clones
	
	-- Safety check: if totalWidth is invalid, disable roulette for this block
	if data.totalWidth <= 0 or data.itemSpacing <= 0 then
		warn("⚠️ Client_Store: Invalid roulette dimensions for", blockName, "- disabling animation")
		rouletteData[blockName] = nil
	end
end

--- Update roulette animations (smooth 60Hz with proper wrapping)
local rouletteScrollOffsets = {}

local function updateRoulette(deltaTime)
	if not storeFrame or not storeFrame.Visible then return end
	
	local scrollSpeed = 0.1 -- Scale per second
	
	for blockName, data in pairs(rouletteData) do
		-- Initialize scroll offset
		if not rouletteScrollOffsets[blockName] then
			rouletteScrollOffsets[blockName] = 0
		end
		
		-- Update scroll offset using actual deltaTime for smooth movement
		rouletteScrollOffsets[blockName] = rouletteScrollOffsets[blockName] + (scrollSpeed * deltaTime)
		local scrollOffset = rouletteScrollOffsets[blockName]
		
		local itemSpacing = data.itemSpacing
		local totalWidth = data.totalWidth
		
		-- Update each clone position
		for i, clone in ipairs(data.clones) do
			local basePosition = (i - 1) * itemSpacing
			local newPosition = basePosition - scrollOffset
			
			-- Wrap around when goes off left edge
			while newPosition < -itemSpacing do
				newPosition = newPosition + totalWidth
			end
			
			clone.Position = UDim2.new(newPosition, 0, 0.5, 0)
		end
	end
end

--- Stop roulette animations
local function stopRouletteAnimations()
	if rouletteConnection then
		rouletteConnection:Disconnect()
		rouletteConnection = nil
	end
	rouletteScrollOffsets = {}
end

--- Start roulette animations
local function startRouletteAnimations()
	stopRouletteAnimations()
	rouletteConnection = RunService.Heartbeat:Connect(updateRoulette)
end

-- ========================================
-- INITIALIZATION
-- ========================================

function Module:Init()
	-- Get Client_Sounds from Library (set by init.client.lua)
	Client_Sounds = self.Client_Sounds
	
	-- Pre-cache all gamepass prices early (prevents UI flashing)
	precacheAllPrices()
	
	-- Listen for ProximityHandler requests (from ShopTag proximity prompts)
	local Events = ReplicatedStorage:FindFirstChild("Events")
	if Events then
		local proximityHandler = Events:FindFirstChild("ProximityHandler")
		if proximityHandler then
			proximityHandler.OnClientEvent:Connect(function(sectionName)
				if sectionName and type(sectionName) == "string" then
					Module:OpenToSection(sectionName)
				end
			end)
		end
	end
	
	-- Wait for data
	Client_Data:WaitUntilReady()
	local replica = getReplica()
	if not replica then
		warn("⚠️ Client_Store: No replica available")
		return
	end
	
	-- Wait for UI
	local playerGui = Player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("Main", 10)
	if not mainGui then
		warn("⚠️ Client_Store: Main GUI not found")
		return
	end
	
	-- Find Frames folder
	local frames = mainGui:FindFirstChild("Frames")
	if not frames then
		warn("⚠️ Client_Store: Frames folder not found")
		return
	end
	
	-- Find Store frame
	storeFrame = frames:FindFirstChild("Store")
	if not storeFrame then
		warn("⚠️ Client_Store: Store frame not found in Frames")
		return
	end
	
	-- Find ListHolder
	local listHolder = storeFrame:FindFirstChild("ListHolder")
	if not listHolder then
		warn("⚠️ Client_Store: ListHolder not found in Store")
		return
	end
	
	-- Setup CashGamepass (directly in ListHolder)
	local cashGamepass = listHolder:FindFirstChild("CashGamepass")
	if cashGamepass then
		setupGamepassCard(cashGamepass, "CashBoost", GAMEPASS_IDS.CashBoost)
	else
		warn("⚠️ Client_Store: CashGamepass not found in ListHolder")
	end
	
	-- Setup Cash Products (Cash1, Cash2, Cash3)
	local cashHolder = listHolder:FindFirstChild("CashHolder")
	if cashHolder then
		-- Get cash amounts from shared config
		for cashName, cashAmount in pairs(Shared_Marketplace.CashAmounts) do
			local cashFrame = cashHolder:FindFirstChild(cashName)
			if cashFrame then
				setupCashProduct(cashFrame, cashName, cashAmount)
			end
		end
	else
		warn("⚠️ Client_Store: CashHolder not found in ListHolder")
	end
	
	-- Setup GamepassHolder gamepasses (VIP, SpeedBoost)
	local gamepassHolder = listHolder:FindFirstChild("GamepassHolder")
	if gamepassHolder then
		-- VIP
		local vipFrame = gamepassHolder:FindFirstChild("VIP")
		if vipFrame then
			setupGamepassCard(vipFrame, "VIP", GAMEPASS_IDS.VIP)
		else
			warn("⚠️ Client_Store: VIP not found in GamepassHolder")
		end
		
		-- SpeedBoost
		local speedBoostFrame = gamepassHolder:FindFirstChild("SpeedBoost")
		if speedBoostFrame then
			setupGamepassCard(speedBoostFrame, "SpeedBoost", GAMEPASS_IDS.SpeedBoost)
		else
			warn("⚠️ Client_Store: SpeedBoost not found in GamepassHolder")
		end
	else
		warn("⚠️ Client_Store: GamepassHolder not found in ListHolder")
	end
	
	-- Setup GamepassHolder2 gamepasses (Sniper, AdminTablet)
	local gamepassHolder2 = listHolder:FindFirstChild("GamepassHolder2")
	if gamepassHolder2 then
		local sniperFrame = gamepassHolder2:FindFirstChild("Sniper")
		if sniperFrame then
			setupGamepassCard(sniperFrame, "Sniper", GAMEPASS_IDS.Sniper)
		else
			warn("⚠️ Client_Store: Sniper not found in GamepassHolder2")
		end
		local adminTabletFrame = gamepassHolder2:FindFirstChild("AdminTablet")
		if adminTabletFrame then
			setupGamepassCard(adminTabletFrame, "Tablet", GAMEPASS_IDS.Tablet)
		else
			warn("⚠️ Client_Store: AdminTablet not found in GamepassHolder2")
		end
	else
		warn("⚠️ Client_Store: GamepassHolder2 not found in ListHolder")
	end
	
	-- Setup GamepassHolder3 gamepasses (QuickCollect)
	local gamepassHolder3 = listHolder:FindFirstChild("GamepassHolder3")
	if gamepassHolder3 then
		local quickCollectFrame = gamepassHolder3:FindFirstChild("QuickCollect")
		if quickCollectFrame then
			setupGamepassCard(quickCollectFrame, "QuickCollect", GAMEPASS_IDS.QuickCollect)
		else
			warn("⚠️ Client_Store: QuickCollect not found in GamepassHolder3")
		end
	else
		warn("⚠️ Client_Store: GamepassHolder3 not found in ListHolder")
	end

	-- Setup Lucky Blocks
	local luckyBlocksHolder = listHolder:FindFirstChild("LuckyBlocksHolder")
	if luckyBlocksHolder then
		-- GodLuckyBlock (Holy Lucky Block)
		local godBlock = luckyBlocksHolder:FindFirstChild("GodLuckyBlock")
		if godBlock then
			setupLuckyBlockCard(godBlock, "GodLuckyBlock")
			setupViewportAnimation(godBlock, "GodLuckyBlock")
			setupRoulette(godBlock, "GodLuckyBlock")
		end
		
		-- MythicalPlusLuckyBlock (Dragon Lucky Block)
		local mythicalPlusBlock = luckyBlocksHolder:FindFirstChild("MythicalPlusLuckyBlock")
		if mythicalPlusBlock then
			setupLuckyBlockCard(mythicalPlusBlock, "MythicalPlusLuckyBlock")
			setupViewportAnimation(mythicalPlusBlock, "MythicalPlusLuckyBlock")
			setupRoulette(mythicalPlusBlock, "MythicalPlusLuckyBlock")
		end
		
		-- OPLuckyBlock (Void Lucky Block)
		local opBlock = luckyBlocksHolder:FindFirstChild("OPLuckyBlock")
		if opBlock then
			setupLuckyBlockCard(opBlock, "OPLuckyBlock")
			setupViewportAnimation(opBlock, "OPLuckyBlock")
			setupRoulette(opBlock, "OPLuckyBlock")
		end
	else
		warn("⚠️ Client_Store: LuckyBlocksHolder not found in ListHolder")
	end
	
	-- Setup frame visibility listener for animation control
	local function onStoreVisibilityChanged()
		if storeFrame.Visible then
			startViewportAnimations()
			startRouletteAnimations()
		else
			stopViewportAnimations()
			stopRouletteAnimations()
		end
	end
	
	-- Initial check
	onStoreVisibilityChanged()
	
	-- Listen for visibility changes
	storeFrame:GetPropertyChangedSignal("Visible"):Connect(onStoreVisibilityChanged)
	
end

--[[
	Open Store UI and scroll to a specific section
	Called from ShopTag proximity prompts via ProximityHandler
	@param sectionName - Section to open ("LuckyBlocks", "Cash", "Gamepasses", etc.)
]]
function Module:OpenToSection(sectionName: string)
	-- Redirect old SpeedStore entrypoint to new Balloons frame
	if sectionName == "SpeedStore" or sectionName == "Speed" then
		if self.Client_Frames then
			self.Client_Frames:OpenFrame("Balloons")
		end
		return
	end

	-- Use Client_Frames to open the Store
	if self.Client_Frames then
		self.Client_Frames:OpenFrame("Store")
	elseif storeFrame then
		storeFrame.Visible = true
	end
	
	-- Wait a frame for the UI to open
	task.wait()
	
	if not storeFrame then
		warn("⚠️ Client_Store: Cannot scroll, storeFrame not initialized")
		return
	end
	
	-- ListHolder IS the ScrollingFrame
	local scrollingFrame = storeFrame:FindFirstChild("ListHolder")
	if not scrollingFrame or not scrollingFrame:IsA("ScrollingFrame") then
		warn("⚠️ Client_Store: ListHolder not found or not a ScrollingFrame")
		return
	end
	
	local targetSection
	
	-- Map section names to UI elements (children of ListHolder)
	if sectionName == "LuckyBlocks" then
		targetSection = scrollingFrame:FindFirstChild("LuckyBlocksHolder")
	elseif sectionName == "Cash" then
		targetSection = scrollingFrame:FindFirstChild("CashHolder")
	elseif sectionName == "Gamepasses" then
		targetSection = scrollingFrame:FindFirstChild("CashGamepass")
	elseif sectionName == "VIP" then
		targetSection = scrollingFrame:FindFirstChild("GamepassHolder")
	end
	
	if not targetSection then
		warn("⚠️ Client_Store: Section not found:", sectionName)
		return
	end
	
	-- Calculate scroll position to target
	-- Use AbsolutePosition but account for current scroll position
	local targetAbsY = targetSection.AbsolutePosition.Y
	local scrollFrameAbsY = scrollingFrame.AbsolutePosition.Y
	local currentScroll = scrollingFrame.CanvasPosition.Y
	
	-- The offset relative to the scrolling frame's viewport
	local viewportOffset = targetAbsY - scrollFrameAbsY
	
	-- Add current scroll position to get the actual canvas position
	local scrollOffset = math.max(0, currentScroll + viewportOffset - 20) -- 20px padding from top
	
	-- Tween to scroll position
	local TweenService = game:GetService("TweenService")
	local scrollTween = TweenService:Create(
		scrollingFrame,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{CanvasPosition = Vector2.new(0, scrollOffset)}
	)
	scrollTween:Play()
end

return Module
