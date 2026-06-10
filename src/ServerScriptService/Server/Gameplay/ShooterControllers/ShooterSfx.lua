local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared_Shooters = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Shooters)

local ShooterSfx = {}

local function getSfxGroup(): SoundGroup?
	local groups = ReplicatedStorage:FindFirstChild("SoundGroups")
	local sfx = groups and groups:FindFirstChild("SFX")
	if sfx and sfx:IsA("SoundGroup") then
		return sfx
	end
	return nil
end

function ShooterSfx.play(shootPart: BasePart?, soundKey: string)
	if not shootPart or not shootPart.Parent then
		return
	end

	local cfg = Shared_Shooters.WorldSounds and Shared_Shooters.WorldSounds[soundKey]
	if not cfg then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "ShooterShot_" .. soundKey
	sound.SoundId = "rbxassetid://" .. tostring(cfg.Id)
	sound.Volume = cfg.Volume or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = cfg.MinDistance or 10
	sound.RollOffMaxDistance = cfg.MaxDistance or 180
	sound.EmitterSize = cfg.EmitterSize or 4

	local sfxGroup = getSfxGroup()
	if sfxGroup then
		sound.SoundGroup = sfxGroup
	end

	sound.Parent = shootPart
	sound:Play()
	Debris:AddItem(sound, 5)
end

return ShooterSfx
