local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.ItemConfigs.BalloonConfig)
local BalloonRigKit = require(ReplicatedStorage.Modules.Gameplay.BalloonRigKit)
local Client_EffectsLibrary = require(script.Parent.Parent.Effects.Client_EffectsLibrary)

local Module = {}

local ATTACHED_BALLOONS_FOLDER = BalloonRigKit.ATTACHED_BALLOONS_FOLDER
local PULSE_ATTR = Config.BalloonDamagedPulseAttribute or "BalloonDamagedPulse"
local characterConns: { [Model]: { RBXScriptConnection } } = setmetatable({}, { __mode = "k" })

local function getBalloonSoundPart(balloonModel: Model): BasePart?
	if balloonModel.PrimaryPart and balloonModel.PrimaryPart:IsA("BasePart") then
		return balloonModel.PrimaryPart
	end
	return balloonModel:FindFirstChildWhichIsA("BasePart", true)
end

local function bindBalloon(balloonModel: Model)
	balloonModel:GetAttributeChangedSignal(PULSE_ATTR):Connect(function()
		if not balloonModel.Parent then
			return
		end
		Client_EffectsLibrary:FlashHighlightFill(balloonModel, "Damage")
		local hitSoundId = Config.BalloonHitSoundId
		local soundPart = getBalloonSoundPart(balloonModel)
		if hitSoundId and soundPart then
			Client_EffectsLibrary:PlayAssetSound3D(soundPart, hitSoundId, {
				Volume = Config.BalloonHitSoundVolume or 0.95,
				MinDistance = 6,
				MaxDistance = Config.BalloonHitSoundMaxDistance or 150,
				EmitterSize = 3,
			})
		end
	end)
end

local function unbindCharacter(character: Model)
	local conns = characterConns[character]
	if conns then
		for _, conn in conns do
			conn:Disconnect()
		end
		characterConns[character] = nil
	end
end

local function bindCharacter(character: Model)
	unbindCharacter(character)

	local conns: { RBXScriptConnection } = {}
	characterConns[character] = conns

	local function scanFolder(folder: Folder)
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				bindBalloon(child)
			end
		end
	end

	local folder = character:FindFirstChild(ATTACHED_BALLOONS_FOLDER)
	if folder and folder:IsA("Folder") then
		scanFolder(folder)
		table.insert(conns, folder.ChildAdded:Connect(function(balloon)
			if balloon:IsA("Model") then
				bindBalloon(balloon)
			end
		end))
	end

	table.insert(conns, character.ChildAdded:Connect(function(child)
		if child.Name == ATTACHED_BALLOONS_FOLDER and child:IsA("Folder") then
			scanFolder(child)
			table.insert(conns, child.ChildAdded:Connect(function(balloon)
				if balloon:IsA("Model") then
					bindBalloon(balloon)
				end
			end))
		end
	end))
end

local function setupPlayer(player: Player)
	local function onCharacter(character: Model)
		task.defer(function()
			if player.Character == character then
				bindCharacter(character)
			end
		end)
	end

	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function(character)
		unbindCharacter(character)
	end)
	if player.Character then
		onCharacter(player.Character)
	end
end

function Module:Init()
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
	Players.PlayerAdded:Connect(setupPlayer)
end

return Module
