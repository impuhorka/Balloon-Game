--[[
	Client_Clouds.lua
	Running cloud/dust VFX at feet when moving (from SingingX).
	Active everywhere when moving and not jumping.
]]

local Players = game:GetService("Players")

local Player = Players.LocalPlayer

local Module = {}
local Character = nil
local Humanoid = nil
local LeftEmitter = nil
local RightEmitter = nil

local function createFootEmitter(foot)
	local attachment = Instance.new("Attachment")
	attachment.Name = "RunningCloudAttachment"
	attachment.Parent = foot

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FootParticles"
	emitter.Parent = attachment
	emitter.Enabled = false

	emitter.Texture = "rbxassetid://101840443279684"
	emitter.Rate = 5
	emitter.Lifetime = NumberRange.new(0.4)
	emitter.Speed = NumberRange.new(1, 2)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0.1)
	})
	emitter.Transparency = NumberSequence.new(0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.VelocitySpread = 10
	emitter.Acceleration = Vector3.new(0, 1, 0)

	return emitter
end

local function updateEmitterState()
	if not LeftEmitter or not RightEmitter then return end
	local moving = Humanoid and Humanoid.MoveDirection.Magnitude > 0
	local jumping = Humanoid and (Humanoid:GetState() == Enum.HumanoidStateType.Jumping or Humanoid:GetState() == Enum.HumanoidStateType.Freefall)
	local enable = moving and not jumping

	LeftEmitter.Enabled = enable
	RightEmitter.Enabled = enable
end

local function onCharacterAdded(character)
	-- Clear old emitters (character might be respawning)
	LeftEmitter = nil
	RightEmitter = nil
	Character = character
	Humanoid = character:WaitForChild("Humanoid", 10)
	if not Humanoid then return end

	local leftFoot = character:WaitForChild("LeftFoot", 30) or character:FindFirstChild("Left Leg")
	local rightFoot = character:WaitForChild("RightFoot", 30) or character:FindFirstChild("Right Leg")
	if not leftFoot or not rightFoot then return end

	LeftEmitter = createFootEmitter(leftFoot)
	RightEmitter = createFootEmitter(rightFoot)

	Humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(updateEmitterState)
	Humanoid.StateChanged:Connect(updateEmitterState)
	updateEmitterState()
end

function Module:Init()
	if Player.Character then
		onCharacterAdded(Player.Character)
	end
	Player.CharacterAdded:Connect(onCharacterAdded)
end

return Module
