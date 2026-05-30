--[[
	Client_Slapper — click/tap while slapper equipped → swing anim + server slap hit.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Client_Inventory = require(script.Parent.Parent.Core.Client_Inventory)
local Shared_Tools = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Tools)

local Module = {}

local Player = Players.LocalPlayer

local clickCooldown = false
local requestCooldown = false

local SLAPPER_CONFIGS = {
	StandardSlapper = true,
	VIPSlapper = true,
}

local function resolvePath(path: string): Instance?
	local current: Instance? = ReplicatedStorage
	for _, part in string.split(path, ".") do
		if not current then
			return nil
		end
		current = current:FindFirstChild(part)
	end
	return current
end

local function getEquippedSlapperConfig()
	local uid = Player:GetAttribute("CurrentEquipped")
	if type(uid) ~= "string" or uid == "" then
		return nil
	end

	local item = Client_Inventory:GetItem(uid)
	if not item or item.Type ~= "Tool" or not SLAPPER_CONFIGS[item.ConfigName] then
		return nil
	end

	return Shared_Tools.List[item.ConfigName]
end

local function canSlap(): boolean
	if Player:GetAttribute("SlotPlacablePicked") then
		return false
	end
	return getEquippedSlapperConfig() ~= nil
end

local function getAnimator(): Animator?
	local character = Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

local function playSlapAnimation(config)
	local animPath = config and config.SlapAnimation
	if type(animPath) ~= "string" or animPath == "" then
		return
	end

	local anim = resolvePath(animPath)
	if not anim or not anim:IsA("Animation") then
		return
	end

	local animator = getAnimator()
	if not animator then
		return
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok or not track then
		return
	end

	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.05, 1, 1)
end

local function playSwingSound(config)
	local soundId = config and config.SwingSoundId
	if type(soundId) ~= "string" or soundId == "" then
		return
	end

	local character = Player.Character
	local parent = character and (character:FindFirstChild("HumanoidRootPart") or character)
	if not parent then
		return
	end

	local swing = Instance.new("Sound")
	swing.SoundId = soundId
	swing.Volume = 1
	swing.Parent = parent
	swing:Play()
	Debris:AddItem(swing, 1)
end

local function trySlap()
	if not canSlap() or clickCooldown or requestCooldown then
		return
	end

	local config = getEquippedSlapperConfig()
	if not config then
		return
	end

	local events = ReplicatedStorage:FindFirstChild("Events")
	local slapperEvent = events and events:FindFirstChild("Slapper")
	if not slapperEvent or not slapperEvent:IsA("RemoteEvent") then
		return
	end

	clickCooldown = true
	task.delay(0.25, function()
		clickCooldown = false
	end)

	local clientCooldown = config.ClientCooldown or 0.8
	requestCooldown = true
	task.delay(clientCooldown, function()
		requestCooldown = false
	end)

	playSlapAnimation(config)
	playSwingSound(config)
	slapperEvent:FireServer()
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	local isSlapInput = input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	if not isSlapInput then
		return
	end

	trySlap()
end

function Module:Init()
	Client_Inventory:WaitUntilReady()
	UserInputService.InputBegan:Connect(onInputBegan)
end

return Module
