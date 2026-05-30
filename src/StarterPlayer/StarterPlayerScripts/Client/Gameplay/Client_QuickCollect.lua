--[[
	Client_QuickCollect.lua
	
	Client-side Quick Collect handler:
	- Hides other players' PickupAll parts
	- Shows only the local player's PickupAll
	- Updates billboard display based on gamepass ownership
	- Handles touch detection and effects (like regular cash collection)
	- OPTIMIZED: Listens to CashToCollect changes for instant updates
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local Client_Data = require(script.Parent.Parent.Core.Client_Data)
local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
local Shared_Marketplace = require(ReplicatedStorage.Modules.Settings.Shared_Marketplace)
local Client_EffectsLibrary = require(script.Parent.Parent.Effects.Client_EffectsLibrary)

local Module = {}

-- Will be set in Init (from Library)
local Client_Sounds = nil

-- Cache processed PickupAll parts
local ProcessedPickupAlls = {}

-- Player's PickupAll and SlotsFolder references (cached for optimization)
local PlayerPickupAll = nil
local PlayerSlotsFolder = nil

-- Touch cooldown
local COLLECT_COOLDOWN = 0.8
local touchDebounce = false

--[[
	Get player's plot ID from CurrentPlot attribute (same as tutorial system)
]]
local function getPlayerPlotID(): number?
	local plotNumber = Player:GetAttribute("CurrentPlot")
	if plotNumber and plotNumber > 0 then
		return plotNumber
	end
	return nil
end

--[[
	Check if player owns Quick Collect gamepass
]]
local function ownsQuickCollect(): boolean
	local replica = Client_Data:GetReplica()
	if not replica then return false end
	
	local passes = replica.Data.Passes or {}
	return passes.QuickCollect == true
end

--[[
	OPTIMIZED: Get total collectable cash from cached slots folder
	Server already applies ALL multipliers to CashToCollect attribute
]]
local function getTotalCollectableCash(): number
	if not PlayerSlotsFolder then return 0 end
	
	local totalCash = 0
	
	-- Single iteration through cached slots
	for _, slotModel in ipairs(PlayerSlotsFolder:GetChildren()) do
		if slotModel:IsA("Model") then
			-- Read attribute (server sets this with all boosts applied)
			totalCash = totalCash + (slotModel:GetAttribute("CashToCollect") or 0)
		end
	end
	
	return totalCash
end

--[[
	Update player's PickupAll billboard display
]]
local function updatePlayerBillboard()
	if not PlayerPickupAll then return end
	
	local primaryPart = PlayerPickupAll.PrimaryPart
	if not primaryPart then return end
	
	local cashDisplay = primaryPart:FindFirstChild("CashDisplay")
	if not cashDisplay or not cashDisplay:IsA("BillboardGui") then return end
	
	local cashLabel = cashDisplay:FindFirstChild("Cash")
	local textInfo = cashDisplay:FindFirstChild("TextInfo")
	local gamepassIcon = cashDisplay:FindFirstChild("GamepassIcon")
	
	local hasGamepass = ownsQuickCollect()
	
	if hasGamepass then
		-- Show collectable cash amount
		local totalCash = getTotalCollectableCash()
		
		if cashLabel then
			cashLabel.Text = "$" .. Shared_Shorten:Number(totalCash)
			cashLabel.Visible = true
		end
		if textInfo then
			textInfo.Text = "Pick up all cash!"
			textInfo.Visible = true
		end
		if gamepassIcon then
			gamepassIcon.Visible = false
		end
	else
		-- Show gamepass price
		if cashLabel then
			local GAMEPASS_ID = Shared_Marketplace.Passes.QuickCollect
			if type(GAMEPASS_ID) == "number" and GAMEPASS_ID > 0 then
				task.spawn(function()
					local success, info = pcall(function()
						return game:GetService("MarketplaceService"):GetProductInfo(GAMEPASS_ID, Enum.InfoType.GamePass)
					end)
					
					if success and info and info.PriceInRobux and cashLabel.Parent then
						cashLabel.Text = string.format("%d$R", info.PriceInRobux)
					elseif cashLabel.Parent then
						cashLabel.Text = "$R"
					end
				end)
			else
				cashLabel.Text = "$R"
			end
			
			cashLabel.Visible = true
		end
		if textInfo then
			textInfo.Text = "Purchase Quick Collect"
			textInfo.Visible = true
		end
		if gamepassIcon then
			gamepassIcon.Visible = true
		end
	end
end

--[[
	OPTIMIZED: Setup listeners for instant updates when cash changes
]]
local function setupSlotChangeListener()
	if not PlayerSlotsFolder then return end
	
	-- Listen to each slot's CashToCollect attribute
	for _, slotModel in ipairs(PlayerSlotsFolder:GetChildren()) do
		if slotModel:IsA("Model") then
			slotModel:GetAttributeChangedSignal("CashToCollect"):Connect(updatePlayerBillboard)
		end
	end
	
	-- Listen for new slots (rebirth bonus)
	PlayerSlotsFolder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.defer(function()
				child:GetAttributeChangedSignal("CashToCollect"):Connect(updatePlayerBillboard)
			end)
		end
	end)
end

--[[
	Play collection effects
]]
local function playCollectionEffects(cashAmount: number)
	if not PlayerPickupAll or not PlayerPickupAll.PrimaryPart then return end
	
	-- Screen popup
	local Client_ScreenPopup = require(script.Parent.Parent.UI.Client_ScreenPopup)
	if Client_ScreenPopup then
		Client_ScreenPopup:ShowCashPopup(cashAmount)
	end
	
	-- VFX
	local vfxTemplate = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("VFX")
		and ReplicatedStorage.Assets.VFX:FindFirstChild("Collect_FX")
	
	if vfxTemplate and vfxTemplate.PrimaryPart then
		local vfx = vfxTemplate.PrimaryPart:Clone()
		vfx.Position = PlayerPickupAll.PrimaryPart.Position
		vfx.Parent = workspace
		Client_EffectsLibrary:EmitParticlesInContainer(vfx, 15)
		task.delay(2, function()
			if vfx.Parent then vfx:Destroy() end
		end)
	end
	
	-- Sound
	if Client_Sounds then
		Client_Sounds:Play("Coin Collect")
	end
	
	-- Flash effect
	local primaryPart = PlayerPickupAll.PrimaryPart
	local originalColor = primaryPart.Color
	
	TweenService:Create(primaryPart, TweenInfo.new(0.08, Enum.EasingStyle.Linear), {Color = Color3.new(1, 1, 1)}):Play()
	task.delay(0.08, function()
		TweenService:Create(primaryPart, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Color = originalColor}):Play()
	end)
end

--[[
	Setup touch detection
]]
local function setupPickupAllTouch()
	if not PlayerPickupAll or not PlayerPickupAll.PrimaryPart then return end
	
	PlayerPickupAll.PrimaryPart.Touched:Connect(function(hit)
		if touchDebounce then return end
		if not hit or not hit.Parent then return end
		if not hit.Parent:FindFirstChild("Humanoid") then return end
		if Players:GetPlayerFromCharacter(hit.Parent) ~= Player then return end
		
		touchDebounce = true
		
		if ownsQuickCollect() then
			-- Collect all cash
			local cashToCollect = getTotalCollectableCash()
			if cashToCollect > 0 then
				playCollectionEffects(cashToCollect)
				
				local Events = ReplicatedStorage:FindFirstChild("Events")
				local PlotHandlerEvent = Events and Events:FindFirstChild("PlotHandler")
				if PlotHandlerEvent then
					PlotHandlerEvent:FireServer("CollectAll")
				end
			end
		else
			-- Prompt gamepass purchase
			local gamepassId = Shared_Marketplace.Passes.QuickCollect
			if type(gamepassId) == "number" and gamepassId > 0 then
				local success = pcall(function()
					game:GetService("MarketplaceService"):PromptGamePassPurchase(Player, gamepassId)
				end)
				if not success then
					warn("⚠️ Failed to prompt gamepass purchase")
				end
			else
				warn("⚠️ QuickCollect gamepass not configured")
			end
		end
		
		task.delay(COLLECT_COOLDOWN, function()
			touchDebounce = false
		end)
	end)
end

--[[
	Hide a PickupAll part
]]
local function hidePickupAll(pickupAll: Model)
	if ProcessedPickupAlls[pickupAll] then return end
	ProcessedPickupAlls[pickupAll] = true
	
	for _, descendant in ipairs(pickupAll:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanTouch = false
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
			descendant.Enabled = false
		end
	end
end

--[[
	Setup player's PickupAll
]]
local function setupPlayerPickupAll()
	local plotsFolder = workspace:FindFirstChild("Game") and workspace.Game:FindFirstChild("Plots")
	if not plotsFolder then return end
	
	local playerPlotID = getPlayerPlotID()
	if not playerPlotID then return end
	
	local plot = plotsFolder:FindFirstChild("Plot" .. tostring(playerPlotID))
	if not plot then return end
	
	local pickupAll = plot:FindFirstChild("PickupAll")
	local slotsFolder = plot:FindFirstChild("Slots")
	if not pickupAll or not pickupAll:IsA("Model") or not slotsFolder then return end
	
	-- Cache references
	PlayerPickupAll = pickupAll
	PlayerSlotsFolder = slotsFolder
	
	-- Setup systems
	setupPickupAllTouch()
	setupSlotChangeListener()
	updatePlayerBillboard()
end

--[[
	Hide other players' PickupAll parts
]]
local function hideOtherPickupAllParts()
	local plotsFolder = workspace:FindFirstChild("Game") and workspace.Game:FindFirstChild("Plots")
	if not plotsFolder then return end
	
	local playerPlotID = getPlayerPlotID()
	
	for _, plotModel in ipairs(plotsFolder:GetChildren()) do
		if plotModel:IsA("Model") then
			local pickupAll = plotModel:FindFirstChild("PickupAll")
			if pickupAll and pickupAll:IsA("Model") then
				local plotID = tonumber(plotModel.Name:match("%d+"))
				if plotID ~= playerPlotID then
					hidePickupAll(pickupAll)
				end
			end
		end
	end
end

--[[
	Initialize
]]
function Module:Init()
	Client_Sounds = self.Client_Sounds
	
	Client_Data:WaitUntilReady()
	
	if not Player.Character then
		Player.CharacterAdded:Wait()
	end
	
	task.wait(2)
	
	setupPlayerPickupAll()
	hideOtherPickupAllParts()
	
	-- Listen for gamepass purchase
	local replica = Client_Data:GetReplica()
	if replica then
		replica:ListenToChange({"Passes", "QuickCollect"}, updatePlayerBillboard)
	end
	
	-- Monitor for new plots
	local plotsFolder = workspace:FindFirstChild("Game") and workspace.Game:FindFirstChild("Plots")
	if plotsFolder then
		plotsFolder.ChildAdded:Connect(function(child)
			task.wait(0.5)
			hideOtherPickupAllParts()
		end)
	end
	
	print("✓ Client_QuickCollect initialized")
end

return Module
