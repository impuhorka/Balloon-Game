--[[
	Client_SellBillboard - Sell brainrot billboard UI
	Uses Client_Touchables for touch detection (UIType="Sell")
	Implements Tsunami's sell functionality with our systems
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local Events = ReplicatedStorage:WaitForChild("Events")
local Assets = ReplicatedStorage:WaitForChild("Assets")

-- State
local ContainersPositions = {}
local Character
local HumanoidRootPart: BasePart? = nil
local BillboardAttachment: Attachment? = nil
local SellBillboard = nil
local SellBillboardFrame = nil
local CD = false -- Shared button cooldown
local Module = {}

-- ========================================
-- CHARACTER SETUP
-- ========================================

local function set_character(character: Model?)
	Character = character
	HumanoidRootPart = nil
	
	if not Character then
		if SellBillboard then
			SellBillboard.Adornee = nil
		end
		return
	end
	
	local rootPart = Character:WaitForChild("HumanoidRootPart", 30)
	if not rootPart then
		if SellBillboard then
			SellBillboard.Adornee = nil
		end
		return
	end
	
	HumanoidRootPart = rootPart
	
	if BillboardAttachment and BillboardAttachment.Parent then
		BillboardAttachment:Destroy()
	end
	BillboardAttachment = Instance.new("Attachment")
	BillboardAttachment.Name = "SellBillboardAttachment"
	BillboardAttachment.Parent = HumanoidRootPart
	
	if SellBillboard then
		SellBillboard.Adornee = HumanoidRootPart
	end
end

-- ========================================
-- ANIMATION
-- ========================================

local function disable_billboard()
	if not SellBillboard then return end
	if not SellBillboard.Enabled then return end
	
	for i = #ContainersPositions, 1, -1 do
		local frame = ContainersPositions[i]
		if not frame then continue end
		
		local container = frame:FindFirstChild("Container")
		if not container then continue end
		
		local origin_pos = container:GetAttribute("OriginPosition")
		if origin_pos then
			TweenService:Create(container, TweenInfo.new(.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Position = origin_pos + UDim2.fromScale(0.2, 0)}):Play()
		end
		
		task.wait(0.05)
		container.Visible = false
		if origin_pos then
			container.Position = origin_pos
		end
	end
	
	SellBillboard.Enabled = false
end

local function enable_billboard()
	if not SellBillboard or not SellBillboardFrame then return end
	
	for _, frame: Frame in pairs(SellBillboardFrame:GetChildren()) do
		if frame.ClassName ~= "Frame" then continue end
		local container = frame:FindFirstChild("Container")
		if container then
			container.Visible = false
		end
	end
	
	SellBillboard.Enabled = true
	
	for _, frame: Frame in ipairs(ContainersPositions) do
		local container = frame:FindFirstChild("Container")
		if not container then continue end
		
		local origin_pos = container:GetAttribute("OriginPosition")
		if not origin_pos then
			origin_pos = container.Position
			container:SetAttribute("OriginPosition", origin_pos)
		end
		
		container.Position = origin_pos + UDim2.fromScale(0.2, 0)
		container.Visible = true
		TweenService:Create(container, TweenInfo.new(.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Position = origin_pos}):Play()
		
		task.wait(0.05)
	end
end

-- ========================================
-- BUTTON HANDLERS (TSUNAMI FUNCTIONALITY)
-- ========================================

local function onByeClicked()
	disable_billboard()
end

local function onWorthClicked()
	local heldUID = Player:GetAttribute("SlotPlacablePicked")
	if not heldUID then 
		if Module.Client_Popups then
			Module.Client_Popups:AddPopupImmediate("You need to hold a brainrot to check its worth!", "error")
		end
		return 
	end
	
	if not Module.Client_Inventory then return end
	
	local itemData = Module.Client_Inventory:GetItem(heldUID)
	if not itemData then
		if Module.Client_Popups then
			Module.Client_Popups:AddPopupImmediate("You need to hold a brainrot to check its worth!", "error")
		end
		return
	end
	
	if itemData.Type ~= "Brainrot" then
		if Module.Client_Popups then
			Module.Client_Popups:AddPopupImmediate("You need to hold a brainrot to check its worth!", "error")
		end
		return
	end
	
	local rebirths = Player:GetAttribute("Rebirths") or 0
	local worth = Shared_Brainrots:CalculateSellWorth(
		itemData.ConfigName, 
		itemData.Metadata and itemData.Metadata.Level or 1, 
		itemData.Metadata and itemData.Metadata.Modifier or "Normal", 
		rebirths
	)
	local config = Shared_Brainrots.List[itemData.ConfigName]
	local displayName = config and config.DisplayName or itemData.ConfigName
	
	if Module.Client_Popups then
		Module.Client_Popups:AddPopupImmediate(string.format("%s is worth $%s", displayName, Shared_Shorten:Number(worth)), "success")
	end
end

local function onSellClicked()
	local heldUID = Player:GetAttribute("SlotPlacablePicked")
	if not heldUID then 
		if Module.Client_Popups then
			Module.Client_Popups:AddPopupImmediate("You need to hold a brainrot to sell it!", "error")
		end
		return 
	end
	
	if not Module.Client_Inventory then return end
	
	local itemData = Module.Client_Inventory:GetItem(heldUID)
	if not itemData then
		if Module.Client_Popups then
			Module.Client_Popups:AddPopupImmediate("You need to hold a brainrot to sell it!", "error")
		end
		return
	end
	
	if itemData.Type ~= "Brainrot" then
		if Module.Client_Popups then
			Module.Client_Popups:AddPopupImmediate("You need to hold a brainrot to sell it!", "error")
		end
		return
	end
	
	Events.SellBrainrot:FireServer(heldUID)
end

local function onSellAllClicked()
	if not Module.Client_Inventory then return end
	
	local inventory = Module.Client_Inventory:GetInventory()
	local rebirths = Player:GetAttribute("Rebirths") or 0
	local totalWorth, count = Shared_Brainrots:CalculateInventoryWorth(inventory, rebirths)
	
	if totalWorth == 0 or count == 0 then
		if Module.Client_Popups then
			Module.Client_Popups:AddPopupImmediate("You don't have any brainrots to sell!", "error")
		end
		return
	end
	
	-- Collect all brainrots for confirmation display
	local allBrainrots = {}
	for uid, itemData in pairs(inventory) do
		if itemData.Type == "Brainrot" then
			local modifier = itemData.Metadata and itemData.Metadata.Modifier or "Normal"
			table.insert(allBrainrots, {
				ConfigName = itemData.ConfigName,
				Modifier = modifier,
				Level = itemData.Metadata and itemData.Metadata.Level or 1
			})
		end
	end
	
	-- Always show confirmation for sell all
	if Module.Client_Confirmation then
		Module.Client_Confirmation:ShowSellConfirmation({
			highValueBrainrots = allBrainrots,
			totalValue = totalWorth
		}, totalWorth, true, function()
			-- Confirmed: execute sell all
			Events.SellBrainrot:FireServer()
		end)
	else
		-- Fallback if confirmation system isn't available
		warn("⚠️ Client_Confirmation not available, direct sell")
		Events.SellBrainrot:FireServer()
	end
end

-- ========================================
-- BUTTON SETUP
-- ========================================

local function setupButtons()
	if not SellBillboardFrame then return end
	
	for _, frame: Frame in pairs(SellBillboardFrame:GetChildren()) do
		if frame.ClassName ~= "Frame" then continue end
		
		local container = frame:FindFirstChild("Container")
		if not container then continue end
		
		local button = container:FindFirstChild("Button")
		if not button then continue end
		
		local textButton = button:FindFirstChild("TextButton")
		if not textButton then continue end
		
		-- Hover animation: slide button slightly to the right
		local originPos = UDim2.new(0.08, 0, 0.5, 0)
		local hoverPos = UDim2.new(0.11, 0, 0.5, 0)
		button.Position = originPos
		
		textButton.MouseEnter:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				Position = hoverPos
			}):Play()
		end)
		
		textButton.MouseLeave:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				Position = originPos
			}):Play()
		end)
		
		if not CollectionService:HasTag(textButton, "AnimatedButton") then
			CollectionService:AddTag(textButton, "AnimatedButton")
		end
		
		ContainersPositions[frame.LayoutOrder] = frame
		
		textButton.MouseButton1Click:Connect(function()
			if CD then return end
			CD = true
			task.delay(.135, function() CD = false end)
			
			if frame.Name == "Bye" then
				onByeClicked()
			elseif frame.Name == "Worth" then
				onWorthClicked()
			elseif frame.Name == "Sell" then
				onSellClicked()
			elseif frame.Name == "Everything" then
				onSellAllClicked()
			end
		end)
	end
end

-- ========================================
-- MODULE INIT
-- ========================================

function Module:Init()
	-- Get Client_Confirmation from Library (set by init.client.lua)
	-- Debug: Check if confirmation system is available
	if self.Client_Confirmation then
	else
		warn("⚠️ Client_SellBillboard: Client_Confirmation NOT available")
	end
	
	local Main = PlayerGui:FindFirstChild("Main") or PlayerGui:FindFirstChild("MainGui")
	if not Main then return end
	
	local Billboards = Main:FindFirstChild("Billboards")
	if not Billboards then
		Billboards = Instance.new("Folder")
		Billboards.Name = "Billboards"
		Billboards.Parent = Main
	end
	
	local billboardAsset = Assets:FindFirstChild("SellBillboard")
	if not billboardAsset then return end
	
	SellBillboard = billboardAsset:Clone()
	SellBillboard.Enabled = false
	SellBillboard.Parent = Billboards
	SellBillboard.Adornee = nil
	
	SellBillboardFrame = SellBillboard:FindFirstChild("SellBillboardFrame")
	if not SellBillboardFrame then return end
	
	setupButtons()
	
	if Player.Character then
		set_character(Player.Character)
	end
	
	Player.CharacterAdded:Connect(function(character: Model)
		disable_billboard()
		set_character(character)
	end)
	
	if self.Client_Touchables then
		self.Client_Touchables:RegisterUIType("Sell", function()
			set_character(Player.Character)
			enable_billboard()
		end, function()
			disable_billboard()
		end)
	end
end

return Module
