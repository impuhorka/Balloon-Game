--// Client_StarterPack - Starter Pack frame: Buy button, countdown timer (StarterPackTimer tag), close on purchase or expiry
--// Animates Main.StarterPack.ImageButton.Flame (slow rotate) and ImageButton.Icon (float up/down) while visible. SingingX-style.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Client_Data = require(script.Parent.Parent.Core.Client_Data)
local Shared_Marketplace = require(ReplicatedStorage.Modules.Settings.Shared_Marketplace)

local DURATION_SEC = Shared_Marketplace.STARTER_PACK_DURATION_SEC or 7200
local STARTER_PACK_PRODUCT_KEY = "Starter Pack"

local Module = {}

local Client_Frames = nil
local timerConnection = nil
local flameRotationTween = nil
local iconFloatTween = nil
local iconOriginalPosition = nil
-- Extrapolate playtime between replica updates (server sends every 5s; we update display every 1s)
local lastPlayTime = 0
local lastPlayTimeAt = 0

local function formatCountdown(seconds: number): string
	if seconds <= 0 then
		return "00:00"
	end
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = math.floor(seconds % 60)
	if hours >= 1 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%02d:%02d", minutes, secs)
end

local function updateTimerLabels(timeRemaining: number)
	for _, obj in ipairs(CollectionService:GetTagged("StarterPackTimer")) do
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			obj.Text = formatCountdown(timeRemaining)
		end
	end
end

local function closeStarterPackFrame()
	if Client_Frames and Client_Frames.CloseFrame then
		Client_Frames:CloseFrame("StarterPack")
	end
end

function Module:Init()
	Client_Frames = self.Client_Frames
	if not Client_Frames then return end

	Client_Data:WaitUntilReady()
	local replica = Client_Data:GetReplica()
	if not replica then return end

	local main = playerGui:FindFirstChild("Main")
	if not main then return end
	local mainStarterPackEntry = main:FindFirstChild("StarterPack") -- Button/entry in Main; hide when purchased
	local frames = main:FindFirstChild("Frames")
	if not frames then return end
	local starterPackFrame = frames:FindFirstChild("StarterPack")
	if not starterPackFrame then return end

	-- Main.StarterPack: visible only when pack not bought
	local function updateMainStarterPackVisibility()
		if mainStarterPackEntry then
			mainStarterPackEntry.Visible = not (replica.Data and replica.Data.StarterPackPurchased)
		end
	end
	updateMainStarterPackVisibility()

	-- Animations for Main.StarterPack.ImageButton: Flame = slow rotate, Icon = float up/down (SingingX-style)
	local imageButton = mainStarterPackEntry and mainStarterPackEntry:FindFirstChild("ImageButton")
	local flame = imageButton and imageButton:FindFirstChild("Flame")
	local icon = imageButton and imageButton:FindFirstChild("Icon")

	local function stopButtonAnimations()
		if flameRotationTween then
			flameRotationTween:Cancel()
			flameRotationTween = nil
		end
		if iconFloatTween then
			iconFloatTween:Cancel()
			iconFloatTween = nil
		end
		if icon and icon.Parent and iconOriginalPosition then
			icon.Position = iconOriginalPosition
		end
	end

	local function startButtonAnimations()
		if not flame and not icon then return end
		stopButtonAnimations()
		if flame and flame.Parent then
			local rotateTweenInfo = TweenInfo.new(
				8,
				Enum.EasingStyle.Linear,
				Enum.EasingDirection.InOut,
				-1,
				false,
				0
			)
			flameRotationTween = TweenService:Create(flame, rotateTweenInfo, {
				Rotation = flame.Rotation + 360,
			})
			flameRotationTween:Play()
		end
		if icon and icon.Parent then
			if not iconOriginalPosition then
				iconOriginalPosition = icon.Position
			end
			local floatTweenInfo = TweenInfo.new(
				3,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true,
				0
			)
			iconFloatTween = TweenService:Create(icon, floatTweenInfo, {
				Position = UDim2.new(iconOriginalPosition.X.Scale, iconOriginalPosition.X.Offset, iconOriginalPosition.Y.Scale - 0.1, 0),
			})
			iconFloatTween:Play()
		end
	end

	mainStarterPackEntry:GetPropertyChangedSignal("Visible"):Connect(function()
		if mainStarterPackEntry.Visible then
			startButtonAnimations()
		else
			stopButtonAnimations()
		end
	end)
	if mainStarterPackEntry.Visible then
		startButtonAnimations()
	end

	local mainFrame = starterPackFrame:FindFirstChild("MainFrame")
	if not mainFrame then return end
	local buy = mainFrame:FindFirstChild("Buy")
	if not buy then return end
	local buyButton = buy:IsA("GuiButton") and buy or buy:FindFirstChild("Button")
	if not buyButton or not buyButton:IsA("GuiButton") then return end

	-- Buy button: request purchase (server validates and fires back to prompt)
	local productId = Shared_Marketplace.Products and Shared_Marketplace.Products[STARTER_PACK_PRODUCT_KEY]
	if productId then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local purchaseHandler = Events and Events:FindFirstChild("PurchaseHandler")
		if purchaseHandler then
			buyButton.Activated:Connect(function()
				purchaseHandler:FireServer(productId, { type = "StarterPack" })
			end)
		end
	end

	-- Sync last known playtime when replica updates (server sends every 5s)
	replica:ListenToChange({"StarterPackPlayTime"}, function(newVal)
		lastPlayTime = newVal or 0
		lastPlayTimeAt = os.clock()
	end)
	lastPlayTime = replica.Data.StarterPackPlayTime or 0
	lastPlayTimeAt = os.clock()

	-- Timer: update StarterPackTimer-tagged labels every second; extrapolate playtime between replica updates
	local function runTimer()
		if timerConnection then
			task.cancel(timerConnection)
			timerConnection = nil
		end
		timerConnection = task.spawn(function()
			while true do
				task.wait(1)
				local r = Client_Data:GetReplica()
				if not r or not r.Data or r.Data.StarterPackPurchased then break end
				local estimatedPlayTime = lastPlayTime + (os.clock() - lastPlayTimeAt)
				local timeRemaining = math.ceil(DURATION_SEC - estimatedPlayTime)
				if timeRemaining <= 0 then
					closeStarterPackFrame()
					if mainStarterPackEntry then
						mainStarterPackEntry.Visible = false
					end
					break
				end
				updateTimerLabels(timeRemaining)
			end
			timerConnection = nil
		end)
	end

	runTimer()

	-- When frame opens, do one immediate timer update
	starterPackFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if starterPackFrame.Visible then
			local r = Client_Data:GetReplica()
			if r and r.Data and not r.Data.StarterPackPurchased then
				local estimatedPlayTime = lastPlayTime + (os.clock() - lastPlayTimeAt)
				local timeRemaining = math.max(0, math.ceil(DURATION_SEC - estimatedPlayTime))
				updateTimerLabels(timeRemaining)
			end
		end
	end)

	-- Close frame and hide Main.StarterPack when purchased (animations stop via Visible signal)
	replica:ListenToChange({"StarterPackPurchased"}, function(newValue)
		if newValue then
			if mainStarterPackEntry then
				mainStarterPackEntry.Visible = false
			end
			stopButtonAnimations()
			closeStarterPackFrame()
			if timerConnection then
				task.cancel(timerConnection)
				timerConnection = nil
			end
		end
	end)
end

return Module
