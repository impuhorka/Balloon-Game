local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client_FOV = require(script.Parent.Client_FOV)
local CameraShake = require(script.Parent.Client_CameraShake)
local BoosterConfig = require(ReplicatedStorage.Modules.Settings.Shared_BoosterConfig)
local PropelerConfig = require(ReplicatedStorage.Modules.Settings.Shared_PropelerConfig)

local Module = {}

local LocalPlayer = Players.LocalPlayer
local feelNarrow = 0
local prevCircleBlend = 0

local function smoothstep01(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function getCircleFovNarrow(character: Model, blend: number): number
	local tier = character:GetAttribute("CircleBoostTier")
	local tierDef = if tier == "VIP" then BoosterConfig.VIP else BoosterConfig.Normal
	local base = tierDef and tierDef.FovNarrow or 7
	return base * smoothstep01(blend)
end

local function tickFeel(dt: number)
	local character = LocalPlayer.Character
	if not character then
		if feelNarrow > 0 then
			feelNarrow = 0
			Client_FOV:SetSpeedBoostNarrow(0)
		end
		return
	end

	local circleBlend = tonumber(character:GetAttribute("CircleBoostBlend")) or 0
	local propBlend = tonumber(character:GetAttribute("PropelerBoostBlend")) or 0

	local target = 0
	if prevCircleBlend < 0.2 and circleBlend > 0.75 then
		local tier = character:GetAttribute("CircleBoostTier")
		local shake = if tier == "VIP" then 0.2 else 0.14
		CameraShake:Start(shake, 18, 0.22, 0.14)
	end
	prevCircleBlend = circleBlend

	if circleBlend > 0.01 then
		target += getCircleFovNarrow(character, circleBlend)
	end
	if propBlend > 0.01 then
		target += (PropelerConfig.ClientFovNarrow or 9) * smoothstep01(propBlend)
	end
	local maxNarrow = BoosterConfig.FovNarrowMax or 24
	target = math.min(target, maxNarrow)

	local inRate = PropelerConfig.ClientFovNarrowInRate or BoosterConfig.FovNarrowInRate or 16
	local outRate = PropelerConfig.ClientFovNarrowOutRate or BoosterConfig.FovNarrowOutRate or 4.5
	local rate = if target > feelNarrow then inRate else outRate
	feelNarrow += (target - feelNarrow) * math.min(1, rate * dt)
	if feelNarrow < 0.05 and target == 0 then
		feelNarrow = 0
	end
	Client_FOV:SetSpeedBoostNarrow(feelNarrow)
end

function Module:Init()
	RunService.PreSimulation:Connect(tickFeel)
	LocalPlayer.CharacterRemoving:Connect(function()
		feelNarrow = 0
		prevCircleBlend = 0
		Client_FOV:SetSpeedBoostNarrow(0)
	end)
end

return Module
