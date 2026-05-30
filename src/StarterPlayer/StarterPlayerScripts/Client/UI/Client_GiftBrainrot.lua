--// Client_GiftBrainrot - Gift brainrot/lucky block via single GiftHandler RemoteEvent
--// ProximityPrompt on other players when local has equipped Brainrot or LuckyBlock; recipient sees GiftBrainrotFrame (Accept/Cancel)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Events = ReplicatedStorage:WaitForChild("Events", 10)
local GiftHandler = Events and Events:FindFirstChild("GiftHandler")

local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
local Shared_LuckyBlocks = require(ReplicatedStorage.Modules.ItemConfigs.Shared_LuckyBlocks)
local Shared_Rarity = require(ReplicatedStorage.Modules.Gameplay.Shared_Rarity)
local Shared_ModifierHandler = require(ReplicatedStorage.Modules.Gameplay.Shared_ModifierHandler)

local Module = {}

local PromptsByPlayer = {}
local CurrentGiftFromUserId = nil
local GiftUI = nil

local function hasGiftableEquipped()
	return Player:GetAttribute("EquippedItem_Brainrot") or Player:GetAttribute("EquippedItem_LuckyBlock")
end

local function updatePromptsEnabled()
	local enabled = hasGiftableEquipped()
	for p, prompt in pairs(PromptsByPlayer) do
		if prompt and prompt.Parent then
			prompt.Enabled = enabled
		else
			PromptsByPlayer[p] = nil
		end
	end
end

-- Clear ListHolder of GiftItem clones (so ViewportFrame models/animations are destroyed)
local function closeGiftUI()
	CurrentGiftFromUserId = nil
	if GiftUI then
		local listHolder = GiftUI:FindFirstChild("ListHolder")
		if listHolder then
			for _, child in ipairs(listHolder:GetChildren()) do
				if child.Name == "GiftItem" then
					child:Destroy()
				end
			end
		end
		GiftUI.Visible = false
	end
end

-- Setup ViewportFrame with Brainrot model from Assets (used only for brainrots)
local function setupViewportWithModel(viewportFrame, itemData: table)
	if not viewportFrame or not viewportFrame:IsA("ViewportFrame") then return end
	for _, child in ipairs(viewportFrame:GetChildren()) do
		child:Destroy()
	end
	local configName = itemData and itemData.ConfigName
	local modifier = (itemData and itemData.Modifier) or "Normal"
	if not configName then return end

	local model = Shared_ModifierHandler:GetBrainrotModel(configName, modifier)
	if not model then return end

	local camera = Instance.new("Camera")
	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewportFrame
	model.Name = "ViewportModel"
	model.Parent = worldModel
	local cf, size = model:GetBoundingBox()
	local maxSize = math.max(size.X, size.Y, size.Z)
	local distance = maxSize * 1.1
	local camPos = cf.Position + Vector3.new(distance, size.Y * 0.2, distance * 0.6)
	camera.CFrame = CFrame.lookAt(camPos, cf.Position)
end

-- Set ImageLabel with lucky block Icon from config (used only for lucky blocks)
local function setupImageLabelWithIcon(imageLabel, itemData: table)
	if not imageLabel or not imageLabel:IsA("ImageLabel") then return end
	local configName = itemData and itemData.ConfigName
	if not configName then return end
	local config = Shared_LuckyBlocks.List and Shared_LuckyBlocks.List[configName]
	if config and config.Icon then
		imageLabel.Image = config.Icon
		imageLabel.Visible = true
	else
		imageLabel.Visible = false
	end
end

local function showGiftProposition(senderUserId: number, senderName: string, dataType: string, itemData: table)
	CurrentGiftFromUserId = senderUserId
	if not GiftUI then return end
	itemData = itemData or {}

	local titleLabel = GiftUI:FindFirstChild("Title")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = string.format("%s wants to gift you something!", senderName or "Someone")
	end

	local listHolder = GiftUI:FindFirstChild("ListHolder")
	if not listHolder then
		GiftUI.Visible = true
		return
	end
	for _, child in ipairs(listHolder:GetChildren()) do
		if child.Name == "GiftItem" then
			child:Destroy()
		end
	end
	local template = listHolder:FindFirstChild("Template")
	if not template then
		GiftUI.Visible = true
		return
	end
	template.Visible = false
	local clone = template:Clone()
	clone.Visible = true
	clone.Name = "GiftItem"

	local displayNameLabel = clone:FindFirstChild("DisplayName", true)
	if displayNameLabel and displayNameLabel:IsA("TextLabel") then
		if dataType == "Brainrot" then
			local config = Shared_Brainrots.List and Shared_Brainrots.List[itemData.ConfigName]
			displayNameLabel.Text = (config and config.DisplayName) or itemData.ConfigName or "Brainrot"
		else
			-- Lucky blocks: use each block's DisplayName from config (no generic "Lucky Block" label)
			local config = Shared_LuckyBlocks.List and Shared_LuckyBlocks.List[itemData.ConfigName]
			displayNameLabel.Text = (config and config.DisplayName) or itemData.ConfigName
		end
	end

	local rarityLabel = clone:FindFirstChild("Rarity", true)
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		local rarityName = "Common"
		if dataType == "Brainrot" then
			local config = Shared_Brainrots.List and Shared_Brainrots.List[itemData.ConfigName]
			rarityName = (config and config.Rarity) or "Common"
		elseif dataType == "LuckyBlock" then
			local config = Shared_LuckyBlocks.List and Shared_LuckyBlocks.List[itemData.ConfigName]
			rarityName = (config and config.Rarity) or "Common"
		end
		local rarityData = Shared_Rarity.List and Shared_Rarity.List[rarityName]
		if rarityData then
			rarityLabel.Visible = true
			rarityLabel.Text = rarityName
			local gradient = rarityLabel:FindFirstChildOfClass("UIGradient")
			if gradient and rarityData.gradient then
				gradient.Color = rarityData.gradient
				gradient.Rotation = (rarityData.isRainbow and 0) or 90
			end
		else
			rarityLabel.Visible = false
		end
	end

	-- Brainrot: show 3D model in ViewportFrame. Lucky block: show icon in ImageLabel.
	local viewportFrame = clone:FindFirstChild("ViewportFrame")
	local imageLabel = clone:FindFirstChild("ImageLabel")
	if dataType == "Brainrot" then
		if viewportFrame and viewportFrame:IsA("ViewportFrame") then
			viewportFrame.Visible = true
			setupViewportWithModel(viewportFrame, itemData)
		end
		if imageLabel and imageLabel:IsA("ImageLabel") then
			imageLabel.Visible = false
		end
	else
		-- LuckyBlock: use ImageLabel with block Icon
		if viewportFrame and viewportFrame:IsA("ViewportFrame") then
			viewportFrame.Visible = false
		end
		if imageLabel and imageLabel:IsA("ImageLabel") then
			setupImageLabelWithIcon(imageLabel, itemData)
		end
	end

	clone.Parent = listHolder
	GiftUI.Visible = true
end

local HUMANOID_ROOT_WAIT_TIMEOUT = 5

local function createPromptForPlayer(otherPlayer: Player)
	if otherPlayer == Player then return end
	local old = PromptsByPlayer[otherPlayer]
	if old and old.Parent then old:Destroy() end
	PromptsByPlayer[otherPlayer] = nil

	local character = otherPlayer.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		-- Character can load before HumanoidRootPart replicates (e.g. both players join at once, or respawn)
		root = character:WaitForChild("HumanoidRootPart", HUMANOID_ROOT_WAIT_TIMEOUT)
	end
	if not root or not root.Parent then return end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GiftBrainrotPrompt"
	prompt.Parent = root
	prompt.RequiresLineOfSight = false
	prompt.ActionText = "Gift"
	prompt.HoldDuration = 0.75
	prompt.MaxActivationDistance = 10
	prompt.Enabled = hasGiftableEquipped()

	prompt.Triggered:Connect(function()
		if GiftHandler then
			GiftHandler:FireServer("SendProposition", otherPlayer.UserId)
		end
	end)

	prompt.AncestryChanged:Connect(function()
		if not prompt.Parent and PromptsByPlayer[otherPlayer] == prompt then
			PromptsByPlayer[otherPlayer] = nil
		end
	end)

	PromptsByPlayer[otherPlayer] = prompt
end

function Module:Init()
	if not GiftHandler then
		warn("⚠️ Client_GiftBrainrot: GiftHandler not found")
		return
	end

	-- Gift UI (optional: clone from Assets or use Main.GiftBrainrotFrame)
	local main = PlayerGui:FindFirstChild("Main", 10) or PlayerGui:WaitForChild("Main", 10)
	if main then
		GiftUI = main:FindFirstChild("GiftBrainrotFrame") or main:FindFirstChild("GiftFrame")
	end
	if not GiftUI then
		warn("⚠️ Client_GiftBrainrot: GiftBrainrotFrame (or GiftFrame) not found under Main - recipient UI will not show")
	end

	-- Listen for server-driven gift events
	GiftHandler.OnClientEvent:Connect(function(action, ...)
		if action == "ShowProposition" then
			local senderUserId, senderName, dataType, itemData = ...
			showGiftProposition(senderUserId, senderName, dataType, itemData or {})
		elseif action == "CancelProposition" then
			local senderUserId = ...
			if CurrentGiftFromUserId == senderUserId then
				closeGiftUI()
			end
		end
	end)

	-- Accept / Cancel buttons
	if GiftUI then
		local acceptBtn = GiftUI:FindFirstChild("Accept") and GiftUI.Accept:FindFirstChild("Button")
		if not acceptBtn then
			acceptBtn = GiftUI:FindFirstChild("AcceptButton") or GiftUI:FindFirstChildWhichIsA("TextButton")
		end
		if acceptBtn then
			acceptBtn.Activated:Connect(function()
				GiftHandler:FireServer("Answer", true)
				closeGiftUI()
			end)
		end
		local cancelBtn = GiftUI:FindFirstChild("Cancel") and GiftUI.Cancel:FindFirstChild("Button")
		if not cancelBtn then
			cancelBtn = GiftUI:FindFirstChild("CancelButton")
		end
		if cancelBtn and cancelBtn ~= acceptBtn then
			cancelBtn.Activated:Connect(function()
				GiftHandler:FireServer("Answer", false)
				closeGiftUI()
			end)
		end
	end

	-- Proximity prompts on other players (create when they have character, and on respawn)
	local function setupGiftPromptForPlayer(other)
		if other == Player then return end
		other.CharacterAdded:Connect(function()
			createPromptForPlayer(other)
		end)
		createPromptForPlayer(other)
	end
	for _, other in ipairs(Players:GetPlayers()) do
		task.defer(function()
			setupGiftPromptForPlayer(other)
		end)
	end
	-- Run immediately so we connect CharacterAdded before the new player's character exists.
	-- If we deferred, their character might load in the same frame and we'd miss CharacterAdded.
	Players.PlayerAdded:Connect(function(other)
		setupGiftPromptForPlayer(other)
	end)
	Players.PlayerRemoving:Connect(function(other)
		local prompt = PromptsByPlayer[other]
		if prompt and prompt.Parent then prompt:Destroy() end
		PromptsByPlayer[other] = nil
	end)

	-- Enable/disable prompts when equipped item changes
	Player:GetAttributeChangedSignal("EquippedItem_Brainrot"):Connect(updatePromptsEnabled)
	Player:GetAttributeChangedSignal("EquippedItem_LuckyBlock"):Connect(updatePromptsEnabled)
	task.defer(updatePromptsEnabled)
end

return Module
