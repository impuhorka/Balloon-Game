--// Client_GamepassGifting - Gamepass gifting UI (player list, search, GamepassIcon + Bought, no confirmation)
--// Listens to OpenGiftingUI:Fire(passName); opens Main.Frames.Gifting, populates list, sets gamepass icon and Bought per row.
--// Uses PurchasePassOwnership to get who owns the pass; click = prompt purchase or "This player already owns this gamepass".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Shared_Marketplace = require(ReplicatedStorage.Modules.Settings.Shared_Marketplace)

local Module = {}

local Events = nil
local OpenGiftingUI = nil
local PurchaseHandler = nil
local PurchasePassOwnership = nil
local GiftingFrame = nil
local ListHolder = nil
local ListTemplate = nil
local SearchBox = nil
local SelectedPassName = nil
local RowsByUserId = {}
local OwnershipByUserId = {}

-- Display name for gamepass (for confirmation text)
local PASS_DISPLAY_NAMES = {
	VIP = "VIP",
	CashBoost = "2x Cash",
	SpeedBoost = "2x Speed",
	Sniper = "Sniper",
	Tablet = "Admin Tablet",
}

local function getPassDisplayName(passName: string): string
	return PASS_DISPLAY_NAMES[passName] or passName
end

local function getGiftProductId(passName: string): (number?, string?)
	local productKey = Shared_Marketplace.GiftProductByPassName and Shared_Marketplace.GiftProductByPassName[passName]
	if not productKey then return nil, nil end
	local productId = Shared_Marketplace.Products and Shared_Marketplace.Products[productKey]
	return productId, productKey
end

local function matchesSearch(player: Player, query: string): boolean
	if not query or query == "" then return true end
	query = string.lower(string.gsub(query, "%s+", ""))
	local namePart = string.gsub(string.lower(player.Name), "%s+", "")
	local displayPart = string.gsub(string.lower(player.DisplayName or ""), "%s+", "")
	return (query == "" or string.find(namePart, query, 1, true) or string.find(displayPart, query, 1, true))
end

local function applySearchFilter()
	if not SearchBox then return end
	local query = SearchBox.Text or ""
	for userId, row in pairs(RowsByUserId) do
		if row and row.Parent then
			local p = Players:GetPlayerByUserId(userId)
			row.Visible = p and matchesSearch(p, query)
		end
	end
end

local function playerOwnsPass(userId: number): boolean
	return OwnershipByUserId[userId] == true or OwnershipByUserId[tostring(userId)] == true
end

local function applyOwnership(ownership: { [number]: boolean })
	OwnershipByUserId = ownership or {}
	for userId, row in pairs(RowsByUserId) do
		if row and row.Parent then
			local imageButton = row:FindFirstChild("ImageButton")
			local gamepassIcon = imageButton and imageButton:FindFirstChild("GamepassIcon")
			local bought = gamepassIcon and gamepassIcon:FindFirstChild("Bought")
			if gamepassIcon then
				local owns = playerOwnsPass(userId)
				gamepassIcon.ImageColor3 = owns and Color3.fromRGB(180, 180, 180) or Color3.fromRGB(255, 255, 255)
				if bought then
					bought.Visible = owns
				end
			end
		end
	end
end

local function addRow(targetPlayer: Player)
	if targetPlayer == Player then return end
	if RowsByUserId[targetPlayer.UserId] then return end
	if not ListHolder or not ListTemplate or not SelectedPassName then return end

	local row = ListTemplate:Clone()
	row.Name = tostring(targetPlayer.UserId)
	row.Visible = true

	-- Player avatar: IconFrame.Icon or Icon (ImageLabel)
	local icon = row:FindFirstChild("IconFrame", true) and row:FindFirstChild("IconFrame", true):FindFirstChild("Icon")
		or row:FindFirstChild("Icon", true)
	if icon and icon:IsA("ImageLabel") then
		task.spawn(function()
			local ok, thumb = pcall(function()
				return Players:GetUserThumbnailAsync(targetPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and thumb and icon.Parent then
				icon.Image = thumb
			end
		end)
	end

	-- Template.ImageButton.GamepassIcon.Bought
	local imageButton = row:FindFirstChild("ImageButton")
	local gamepassIcon = imageButton and imageButton:FindFirstChild("GamepassIcon")
	if gamepassIcon then
		local passId = Shared_Marketplace.Passes and Shared_Marketplace.Passes[SelectedPassName]
		if type(passId) == "number" and passId > 0 then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
				end)
				if ok and info and info.IconImageAssetId and gamepassIcon.Parent then
					gamepassIcon.Image = "rbxassetid://" .. tostring(info.IconImageAssetId)
				end
			end)
		end
		local bought = gamepassIcon:FindFirstChild("Bought")
		local owns = playerOwnsPass(targetPlayer.UserId)
		gamepassIcon.ImageColor3 = owns and Color3.fromRGB(180, 180, 180) or Color3.fromRGB(255, 255, 255)
		if bought then
			bought.Visible = owns
		end
	end

	local playerNameLabel = row:FindFirstChild("PlayerName", true) or (row:FindFirstChild("Info", true) and row:FindFirstChild("Info", true):FindFirstChild("PlayerName"))
	if not playerNameLabel and row:FindFirstChild("Info", true) then
		playerNameLabel = row:FindFirstChild("Info", true):FindFirstChildWhichIsA("TextLabel")
	end
	if playerNameLabel and playerNameLabel:IsA("TextLabel") then
		playerNameLabel.Text = targetPlayer.Name
	end
	local usernameLabel = row:FindFirstChild("Username", true) or (row:FindFirstChild("Info", true) and row:FindFirstChild("Info", true):FindFirstChild("Username"))
	if usernameLabel and usernameLabel:IsA("TextLabel") then
		usernameLabel.Text = targetPlayer.DisplayName or targetPlayer.Name
	end

	-- Click: if they own the pass show message; else prompt purchase (no confirmation frame)
	local clickTarget = imageButton or row
	clickTarget.Activated:Connect(function()
		if not SelectedPassName then
			local Client_Popups = require(script.Parent.Client_Popups)
			if Client_Popups then
				Client_Popups:AddPopupImmediate("Select a gamepass to gift first.", "error")
			end
			return
		end
		if playerOwnsPass(targetPlayer.UserId) then
			local Client_Popups = require(script.Parent.Client_Popups)
			if Client_Popups then
				Client_Popups:AddPopupImmediate("This player already owns this gamepass.", "error")
			end
			return
		end
		local productId = (getGiftProductId(SelectedPassName))
		if not productId then
			local Client_Popups = require(script.Parent.Client_Popups)
			if Client_Popups then
				Client_Popups:AddPopupImmediate("Gift is not available for this gamepass.", "error")
			end
			return
		end
		if PurchaseHandler then
			PurchaseHandler:FireServer(productId, {
				type = "GiftGamepass",
				TargetUserId = targetPlayer.UserId,
				PassName = SelectedPassName,
			})
		end
	end)

	row.Parent = ListHolder
	RowsByUserId[targetPlayer.UserId] = row
	row.Visible = matchesSearch(targetPlayer, SearchBox and SearchBox.Text or "")
end

local function removeRow(targetPlayer: Player)
	local row = RowsByUserId[targetPlayer.UserId]
	if row and row.Parent then
		row:Destroy()
	end
	RowsByUserId[targetPlayer.UserId] = nil
end

local function refreshPlayerList()
	if not ListHolder or not ListTemplate then return end
	for _, row in pairs(RowsByUserId) do
		if row and row.Parent then row:Destroy() end
	end
	RowsByUserId = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= Player then
			addRow(other)
		end
	end
	applySearchFilter()
end

local function openGiftingUI(passName: string)
	SelectedPassName = passName
	OwnershipByUserId = {}
	refreshPlayerList()
	-- Fetch who owns this pass and set Bought per row
	if PurchasePassOwnership and PurchasePassOwnership:IsA("RemoteFunction") then
		task.spawn(function()
			local ok, ownership = pcall(function()
				return PurchasePassOwnership:InvokeServer(passName)
			end)
			if ok and type(ownership) == "table" then
				applyOwnership(ownership)
			end
		end)
	end
	if Module.Client_Frames and Module.Client_Frames.OpenFrame then
		Module.Client_Frames:OpenFrame("Gifting")
	end
end

function Module:Init()
	if self and self.Client_Frames then
		Module.Client_Frames = self.Client_Frames
	end
	Events = ReplicatedStorage:FindFirstChild("Events", 10)
	if not Events then
		warn("⚠️ Client_GamepassGifting: Events not found")
		return
	end
	OpenGiftingUI = Events:FindFirstChild("OpenGiftingUI")
	if not OpenGiftingUI then
		OpenGiftingUI = Instance.new("BindableEvent")
		OpenGiftingUI.Name = "OpenGiftingUI"
		OpenGiftingUI.Parent = Events
	end
	PurchaseHandler = Events:FindFirstChild("PurchaseHandler")
	PurchasePassOwnership = Events:FindFirstChild("PurchasePassOwnership")

	local main = PlayerGui:FindFirstChild("Main", 10) or PlayerGui:FindFirstChild("MainGui", 10)
	if main then
		local frames = main:FindFirstChild("Frames")
		if frames then
			GiftingFrame = frames:FindFirstChild("Gifting")
			if GiftingFrame then
				ListHolder = GiftingFrame:FindFirstChild("ScrollingFrame") or GiftingFrame:FindFirstChild("ListHolder") or GiftingFrame
				ListTemplate = ListHolder and ListHolder:FindFirstChild("Template")
				if ListTemplate then
					ListTemplate.Visible = false
				end
				SearchBox = GiftingFrame:FindFirstChild("Search", true)
				if SearchBox and not SearchBox:IsA("TextBox") then
					SearchBox = SearchBox:FindFirstChildWhichIsA("TextBox")
				end
				if not ListTemplate then
					warn("⚠️ Client_GamepassGifting: Gifting frame has no Template in list holder")
				end
			else
				warn("⚠️ Client_GamepassGifting: Main.Frames.Gifting not found - add Gifting frame with ScrollingFrame, Template, Search")
			end
		end
	end

	OpenGiftingUI.Event:Connect(function(passName: string)
		if type(passName) ~= "string" or passName == "" then return end
		if not Shared_Marketplace.GiftProductByPassName or not Shared_Marketplace.GiftProductByPassName[passName] then
			warn("⚠️ Client_GamepassGifting: Unknown pass name for gifting:", passName)
			return
		end
		openGiftingUI(passName)
	end)

	if SearchBox and SearchBox:IsA("TextBox") then
		SearchBox:GetPropertyChangedSignal("Text"):Connect(applySearchFilter)
	end

	Players.PlayerAdded:Connect(function(other: Player)
		if other == Player then return end
		addRow(other)
	end)
	Players.PlayerRemoving:Connect(function(other: Player)
		removeRow(other)
	end)
end

return Module
