--// Client_Balloons - Balloon store frame setup and buy flow
--// Reads config names from Shared_Balloons and wires Buy buttons to BalloonHandler

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Shared_Balloons = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Balloons)
local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
local BalloonRigKit = require(ReplicatedStorage.Modules.Gameplay.BalloonRigKit)
local Client_Data = require(script.Parent.Parent.Core.Client_Data)

local Events = ReplicatedStorage:WaitForChild("Events")
local BalloonHandler = Events:WaitForChild("BalloonHandler")

local Module = {}

local BalloonsFrame
local listHolder
local bannerTotalLabel
local rowsByConfig = {}
local selectedConfigName = nil
local replicaHooksBound = false

local MAX_TOTAL = tonumber(Shared_Balloons.MaxTotalBalloons) or 15

local function getReplica()
	return Client_Data:GetReplica()
end

--- Per-configName count from replica Balloons array {ConfigName, ...}
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

--- Speed shop rows often reused a Frame named "Buy" with an inner GuiButton; strip tags/attrs that route to PurchaseHandler / frame toggle.
local function resolveBuyButton(row)
	local buy = row:FindFirstChild("Buy", true)
	if not buy then
		return nil
	end
	if buy:IsA("GuiButton") then
		return buy
	end
	local inner = buy:FindFirstChildWhichIsA("GuiButton", true)
	return inner
end

local function stripLegacyPurchaseHooks(button)
	button:SetAttribute("UIType", nil)
	button:SetAttribute("ProductID", nil)
	button:SetAttribute("BalloonBuy", true)
end

local function updateBannerTotal(total)
	if
		bannerTotalLabel
		and (bannerTotalLabel:IsA("TextLabel") or bannerTotalLabel:IsA("TextButton"))
	then
		bannerTotalLabel.Text = tostring(total) .. " / " .. tostring(MAX_TOTAL)
	end
end

--- UI places SpeedBefore / SpeedAfter under row.Info (not always direct children of row).
local function findRowSpeedField(row, fieldName)
	local info = row:FindFirstChild("Info")
	if not info then
		for _, child in ipairs(row:GetChildren()) do
			if child.Name:lower() == "info" then
				info = child
				break
			end
		end
	end
	if info then
		local inst = info:FindFirstChild(fieldName, true)
		if inst then
			return inst
		end
	end
	return row:FindFirstChild(fieldName, true)
end

--- field may be a TextLabel or a Frame containing one.
local function writeNumberToGuiField(root, value)
	if not root then
		return
	end
	local text = tostring(value)
	if root:IsA("TextLabel") or root:IsA("TextButton") or root:IsA("TextBox") then
		root.Text = text
		return
	end
	local inner = root:FindFirstChildWhichIsA("TextLabel", true)
	if inner then
		inner.Text = text
		return
	end
	inner = root:FindFirstChildWhichIsA("TextButton", true)
	if inner then
		inner.Text = text
	end
end

local function updateBeforeAfterLabels()
	local counts = getCountsByType()
	for configName, row in pairs(rowsByConfig) do
		local beforeField = findRowSpeedField(row, "SpeedBefore")
		local afterField = findRowSpeedField(row, "SpeedAfter")
		local n = counts[configName] or 0
		writeNumberToGuiField(beforeField, n)
		writeNumberToGuiField(afterField, n + 1)
	end
end

local function updateSelectedVisuals()
	for configName, row in pairs(rowsByConfig) do
		local selectedFlag = row:FindFirstChild("Selected")
		if selectedFlag and selectedFlag:IsA("GuiObject") then
			selectedFlag.Visible = (configName == selectedConfigName)
		end
	end
end

local function updateOwnershipVisuals()
	local counts, totalOwned = getCountsByType()
	local cash = getCash()
	local atCap = totalOwned >= MAX_TOTAL

	updateBannerTotal(totalOwned)
	updateBeforeAfterLabels()

	for configName, row in pairs(rowsByConfig) do
		local count = counts[configName] or 0
		local ownedFlag = row:FindFirstChild("Owned")
		if ownedFlag and ownedFlag:IsA("GuiObject") then
			ownedFlag.Visible = count > 0
		end

		local buyButton = resolveBuyButton(row)
		local buyLabel = buyButton and buyButton:FindFirstChild("Title", true)
		if buyButton and buyButton:IsA("GuiButton") then
			local config = Shared_Balloons.List[configName]
			local cost = (config and config.Cost) or 0
			local canAfford = cash >= cost
			local canBuy = not atCap and canAfford

			buyButton.Active = canBuy
			buyButton.AutoButtonColor = canBuy

			if buyLabel and buyLabel:IsA("TextLabel") then
				if atCap then
					buyLabel.Text = "Max balloons"
				elseif not canAfford then
					buyLabel.Text = "$" .. Shared_Shorten:Number(cost)
				else
					buyLabel.Text = "$" .. Shared_Shorten:Number(cost)
				end
			end
		end
	end
end

local function bindRow(configName, row)
	local config = Shared_Balloons.List[configName]
	if not config then
		return
	end

	local title = row:FindFirstChild("Title", true)
	if title and title:IsA("TextLabel") then
		title.Text = config.DisplayName or configName
	end

	local hpLabel = row:FindFirstChild("HP", true)
	if hpLabel and hpLabel:IsA("TextLabel") then
		hpLabel.Text = tostring(config.HP or 0) .. " HP"
	end

	local buyButton = resolveBuyButton(row)
	if buyButton and buyButton:IsA("GuiButton") then
		stripLegacyPurchaseHooks(buyButton)
		buyButton.MouseButton1Click:Connect(function()
			BalloonHandler:FireServer("Buy", configName)
		end)
	end

	local selectButton = row:FindFirstChild("Select", true)
	if selectButton and selectButton:IsA("GuiButton") then
		selectButton.Activated:Connect(function()
			selectedConfigName = configName
			updateSelectedVisuals()
		end)
	end
end

local function bindExistingRows()
	rowsByConfig = {}
	selectedConfigName = nil

	bannerTotalLabel = BalloonsFrame and BalloonsFrame:FindFirstChild("TotalBaloons", true)
	if not bannerTotalLabel then
		local banner = BalloonsFrame and BalloonsFrame:FindFirstChild("Banner", true)
		if banner then
			bannerTotalLabel = banner:FindFirstChild("TotalBaloons", true)
		end
	end

	for configName, config in pairs(Shared_Balloons.List) do
		local row = listHolder:FindFirstChild(configName)
		if row and row:IsA("GuiObject") then
			row.Visible = true
			rowsByConfig[configName] = row
			bindRow(configName, row)
			if not selectedConfigName then
				selectedConfigName = configName
			end
		else
			warn("⚠️ Client_Balloons: Row not found in ListHolder for", configName, "(", config.DisplayName or configName, ")")
		end
	end

	updateSelectedVisuals()
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
	-- Store UI can init before PlayerData replica exists; first refresh otherwise shows 0 until a buy fires OwnedUpdated.
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
	BalloonsFrame = frames and frames:FindFirstChild("Baloons")
	if not BalloonsFrame then
		warn("⚠️ Client_Balloons: Frames.Baloons not found")
		return
	end

	listHolder = BalloonsFrame:FindFirstChild("ListHolder", true) or BalloonsFrame
	if not listHolder then
		warn("⚠️ Client_Balloons: ListHolder not found")
		return
	end

	bindExistingRows()

	task.defer(waitForReplicaAndBind)

	BalloonHandler.OnClientEvent:Connect(function(action)
		if action == "OwnedUpdated" then
			updateOwnershipVisuals()
		end
	end)
end

return Module
