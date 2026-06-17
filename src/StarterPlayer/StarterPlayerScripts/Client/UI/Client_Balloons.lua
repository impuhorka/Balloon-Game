--// Client_Balloons - Balloon store frame setup and buy flow
--// Clones Frames.Balloons.ListHolder.ScrollingList.Template per balloon config.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Shared_Balloons = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Balloons)
local Shared_Rarity = require(ReplicatedStorage.Modules.Gameplay.Shared_Rarity)
local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
local BalloonRigKit = require(ReplicatedStorage.Modules.Gameplay.BalloonRigKit)
local Client_Data = require(script.Parent.Parent.Core.Client_Data)

local Events = ReplicatedStorage:WaitForChild("Events")
local BalloonHandler = Events:WaitForChild("BalloonHandler")

local Module = {}

local BalloonsFrame
local scrollingList
local rowTemplate
local bannerTotalLabel
local rowsByConfig: { [string]: GuiObject } = {}
local replicaHooksBound = false

local MAX_TOTAL = tonumber(Shared_Balloons.MaxTotalBalloons) or 15

local UNCOMMON_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(170, 255, 120)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 190, 90)),
})

local function getReplica()
	return Client_Data:GetReplica()
end

local function getCountsByType()
	local replica = getReplica()
	if not replica then
		return {}, 0
	end

	local counts = {}
	local total = 0
	for _, configName in ipairs(BalloonRigKit.normalizeToConfigNames(replica.Data.Balloons)) do
		counts[configName] = (counts[configName] or 0) + 1
		total += 1
	end

	return counts, total
end

local function getCash()
	local replica = getReplica()
	if not replica then
		return 0
	end
	return tonumber(replica.Data.Cash) or 0
end

local function getBuyButton(row: Instance): GuiButton?
	local buttons = row:FindFirstChild("Buttons", true)
	local buy = buttons and buttons:FindFirstChild("Buy")
	local buyButton = buy and buy:FindFirstChild("BuyButton")
	if buyButton and buyButton:IsA("GuiButton") then
		return buyButton
	end
	return row:FindFirstChildWhichIsA("GuiButton", true)
end

local function getBuyTitle(row: Instance): TextLabel?
	local buttons = row:FindFirstChild("Buttons", true)
	local buy = buttons and buttons:FindFirstChild("Buy")
	local buyButton = buy and buy:FindFirstChild("BuyButton")
	local title = buyButton and buyButton:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		return title
	end
	if buyButton then
		return buyButton:FindFirstChildWhichIsA("TextLabel", true)
	end
	return nil
end

local function stripLegacyPurchaseHooks(button: GuiButton)
	button:SetAttribute("UIType", nil)
	button:SetAttribute("ProductID", nil)
	button:SetAttribute("BalloonBuy", true)
end

local function applyRarityGradient(gradient: UIGradient?, rarity: string)
	if not gradient then
		return
	end

	local info = Shared_Rarity:GetRarityInfo(rarity)
	if info and info.gradient then
		gradient.Color = info.gradient
		gradient.Rotation = if info.isRainbow then 0 else 90
	elseif rarity == "Uncommon" then
		gradient.Color = UNCOMMON_GRADIENT
		gradient.Rotation = 90
	end
end

local function getRowIcon(row: Instance): GuiObject?
	local icon = row:FindFirstChild("Icon", true)
	if icon and icon:IsA("GuiObject") then
		return icon
	end
	return nil
end

local activeIconPunch: { [GuiObject]: Tween } = {}

local function playRowIconPunch(configName: string)
	local row = rowsByConfig[configName]
	if not row then
		return
	end

	local icon = getRowIcon(row)
	if not icon then
		return
	end

	local uiScale = icon:FindFirstChild("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "UIScale"
		uiScale.Scale = 1
		uiScale.Parent = icon
	end

	local previous = activeIconPunch[icon]
	if previous then
		previous:Cancel()
		activeIconPunch[icon] = nil
	end

	uiScale.Scale = 1

	local shrink = TweenService:Create(
		uiScale,
		TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = 0.9 }
	)
	local restore = TweenService:Create(
		uiScale,
		TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)

	activeIconPunch[icon] = shrink
	shrink:Play()
	shrink.Completed:Once(function()
		if activeIconPunch[icon] == shrink then
			activeIconPunch[icon] = restore
		end
		if uiScale.Parent then
			restore:Play()
		end
	end)
	restore.Completed:Once(function()
		if activeIconPunch[icon] == restore then
			activeIconPunch[icon] = nil
		end
	end)
end

local function setRowIcon(row: Instance, configName: string)
	local icon = getRowIcon(row)

	local imageId = Shared_Balloons.Icons and Shared_Balloons.Icons[configName]
	if not imageId or not icon then
		return
	end

	if icon:IsA("ImageLabel") or icon:IsA("ImageButton") then
		icon.Image = imageId
	elseif icon:IsA("ViewportFrame") then
		-- leave viewport-driven icons alone
	end
end

local function applyTitleText(titleRoot: Instance, displayName: string)
	if titleRoot:IsA("TextLabel") or titleRoot:IsA("TextButton") then
		titleRoot.Text = displayName
	end

	for _, child in titleRoot:GetChildren() do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			child.Text = displayName
		end
	end
end

local function setRowTitle(row: Instance, displayName: string)
	local title = row:FindFirstChild("Title")
	if title then
		applyTitleText(title, displayName)
		return
	end

	for _, desc in row:GetDescendants() do
		if desc.Name == "Title" then
			local buttons = row:FindFirstChild("Buttons", true)
			if not buttons or not desc:IsDescendantOf(buttons) then
				applyTitleText(desc, displayName)
				return
			end
		end
	end
end

local function setRowHealth(row: Instance, hp: number)
	local health = row:FindFirstChild("Health", true)
	local label = health and health:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = tostring(hp)
		return
	end

	local fallback = row:FindFirstChild("HP", true)
	if fallback and fallback:IsA("TextLabel") then
		fallback.Text = tostring(hp) .. " HP"
	end
end

local function getRarityLayoutOrder(rarity: string, shopIndex: number): number
	if rarity == "Uncommon" then
		return 15
	end
	local rarityOrder = Shared_Rarity.Order[rarity]
	if rarityOrder then
		return rarityOrder * 10
	end
	return shopIndex * 10
end

local function ensureListLayout(listContainer: Instance)
	for _, layout in listContainer:GetChildren() do
		if layout:IsA("UIListLayout") then
			layout.SortOrder = Enum.SortOrder.LayoutOrder
		end
	end
	local nested = listContainer:FindFirstChildWhichIsA("UIListLayout", true)
	if nested then
		nested.SortOrder = Enum.SortOrder.LayoutOrder
	end
end

local function resolveRarityTextAndGradient(rarityRoot: Instance): (TextLabel?, UIGradient?)
	if rarityRoot:IsA("TextLabel") or rarityRoot:IsA("TextButton") then
		local label = rarityRoot :: TextLabel
		return label, label:FindFirstChildOfClass("UIGradient")
	end

	local textChild = rarityRoot:FindFirstChild("Text")
	if textChild and (textChild:IsA("TextLabel") or textChild:IsA("TextButton")) then
		local label = textChild :: TextLabel
		return label, label:FindFirstChildOfClass("UIGradient") or rarityRoot:FindFirstChildOfClass("UIGradient")
	end

	local label = rarityRoot:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		return label, label:FindFirstChildOfClass("UIGradient") or rarityRoot:FindFirstChildOfClass("UIGradient")
	end

	return nil, rarityRoot:FindFirstChildOfClass("UIGradient")
end

local function setRowRarity(row: Instance, rarity: string)
	local rarityRoot = row:FindFirstChild("Rarity") or row:FindFirstChild("Rarity", true)
	if not rarityRoot then
		return
	end

	local label, gradient = resolveRarityTextAndGradient(rarityRoot)
	if label then
		label.Text = rarity
	end

	applyRarityGradient(gradient, rarity)
end

local function setRowBackgroundRarity(row: Instance, rarity: string)
	local background = row:FindFirstChild("BackgroundFrame", true)
	if not background then
		return
	end
	applyRarityGradient(background:FindFirstChildOfClass("UIGradient"), rarity)
end

local function formatCost(cost: number): string
	return "$" .. Shared_Shorten:Number(cost)
end

local function setBannerTotalText(text: string)
	if not bannerTotalLabel then
		return
	end

	if bannerTotalLabel:IsA("TextLabel") or bannerTotalLabel:IsA("TextButton") then
		bannerTotalLabel.Text = text
	end

	for _, child in bannerTotalLabel:GetChildren() do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			child.Text = text
		end
	end
end

local function updateBannerTotal(total: number)
	setBannerTotalText(string.format("%s/%s", total, MAX_TOTAL))
end

local function updateOwnershipVisuals()
	local counts, totalOwned = getCountsByType()
	local cash = getCash()
	local atCap = totalOwned >= MAX_TOTAL

	updateBannerTotal(totalOwned)

	for configName, row in pairs(rowsByConfig) do
		local config = Shared_Balloons.List[configName]
		if not config then
			continue
		end

		local count = counts[configName] or 0
		local ownedFlag = row:FindFirstChild("Owned", true)
		if ownedFlag and ownedFlag:IsA("GuiObject") then
			ownedFlag.Visible = count > 0
		end

		local buyButton = getBuyButton(row)
		local buyLabel = getBuyTitle(row)
		if buyButton then
			local cost = config.Cost or 0
			local canAfford = cash >= cost
			local canBuy = not atCap and canAfford

			buyButton.Active = canBuy
			buyButton.AutoButtonColor = canBuy

			if buyLabel then
				if atCap then
					buyLabel.Text = "MAX"
				else
					buyLabel.Text = formatCost(cost)
				end
			end
		end
	end
end

local function bindRow(configName: string, row: GuiObject)
	local config = Shared_Balloons.List[configName]
	if not config then
		return
	end

	setRowIcon(row, configName)
	setRowTitle(row, config.DisplayName or configName)
	setRowHealth(row, config.HP or 0)
	setRowRarity(row, config.Rarity or "Common")
	setRowBackgroundRarity(row, config.Rarity or "Common")

	local buyButton = getBuyButton(row)
	if buyButton then
		stripLegacyPurchaseHooks(buyButton)
		buyButton.MouseButton1Click:Connect(function()
			BalloonHandler:FireServer("Buy", configName)
		end)
	end

	local buyLabel = getBuyTitle(row)
	if buyLabel then
		buyLabel.Text = formatCost(config.Cost or 0)
	end
end

local listContainer

local function clearGeneratedRows()
	if not listContainer or not rowTemplate then
		return
	end
	for _, child in listContainer:GetChildren() do
		if child ~= rowTemplate and child:IsA("GuiObject") and not child:IsA("UILayout") then
			child:Destroy()
		end
	end
end

local function buildShopRows()
	rowsByConfig = {}
	clearGeneratedRows()

	if not listContainer or not rowTemplate then
		return
	end

	ensureListLayout(listContainer)
	rowTemplate.Visible = false
	rowTemplate.LayoutOrder = 100000

	local shopOrder = Shared_Balloons.ShopOrder
	for index, configName in ipairs(shopOrder) do
		local config = Shared_Balloons.List[configName]
		if not config then
			warn("⚠️ Client_Balloons: Missing config for", configName)
			continue
		end

		local row = rowTemplate:Clone()
		row.Name = configName
		row.Visible = true
		row.LayoutOrder = getRarityLayoutOrder(config.Rarity or "Common", index)
		row.Parent = listContainer

		rowsByConfig[configName] = row
		bindRow(configName, row)
	end

	updateOwnershipVisuals()
end

local function bindReplicaDataListeners()
	if replicaHooksBound then
		return
	end
	local replica = getReplica()
	if not replica then
		return
	end
	replicaHooksBound = true
	replica:ListenToChange({ "Balloons" }, function()
		updateOwnershipVisuals()
	end)
	replica:ListenToChange({ "Cash" }, function()
		updateOwnershipVisuals()
	end)
	updateOwnershipVisuals()
end

local function waitForReplicaAndBind()
	pcall(function()
		Client_Data.WaitUntilReady()
	end)
	if not getReplica() then
		for _ = 1, 120 do
			if getReplica() then
				break
			end
			task.wait(0.05)
		end
	end
	bindReplicaDataListeners()
end

function Module:Init()
	local mainGui = PlayerGui:FindFirstChild("MainGui") or PlayerGui:FindFirstChild("Main")
	if not mainGui then
		return
	end

	local frames = mainGui:FindFirstChild("Frames")
	BalloonsFrame = frames and frames:FindFirstChild("Balloons")
	if not BalloonsFrame then
		warn("⚠️ Client_Balloons: Frames.Balloons not found")
		return
	end

	local listHolder = BalloonsFrame:FindFirstChild("ListHolder", true)
	scrollingList = listHolder and listHolder:FindFirstChild("ScrollingList")
	if not scrollingList then
		warn("⚠️ Client_Balloons: ListHolder.ScrollingList not found")
		return
	end

	rowTemplate = scrollingList:FindFirstChild("Template")
	if not rowTemplate or not rowTemplate:IsA("GuiObject") then
		warn("⚠️ Client_Balloons: ScrollingList.Template not found")
		return
	end

	listContainer = rowTemplate.Parent
	if not listContainer then
		listContainer = scrollingList
	end

	local banner = BalloonsFrame:FindFirstChild("Banner", true)
	local totalBalloons = banner and banner:FindFirstChild("TotalBalloons")
	bannerTotalLabel = totalBalloons and totalBalloons:FindFirstChild("Title")

	buildShopRows()

	task.defer(waitForReplicaAndBind)

	BalloonHandler.OnClientEvent:Connect(function(action, configName)
		if action == "OwnedUpdated" then
			updateOwnershipVisuals()
			if type(configName) == "string" and configName ~= "" then
				playRowIconPunch(configName)
			end
		end
	end)
end

return Module
