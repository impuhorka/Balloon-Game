local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.Settings.Shared_PropelerConfig)
local BalloonFloat = require(ReplicatedStorage.Modules.Gameplay.BalloonFloat)

local Module = {}

type PropelerUnit = {
	spinPart: BasePart,
	restCF: CFrame,
	angle: number,
	ramping: string,
	spinSign: number,
	maxSpeedRad: number,
	currentSpeedRad: number,
	accelRad: number,
	decelRad: number,
	idleSeconds: number,
	activeSeconds: number,
	spinUpSeconds: number,
	spinDownSeconds: number,
	emitters: { ParticleEmitter },
}

type BoostState = {
	blend: number,
}

local units: { PropelerUnit } = {}
local boostByPlayer: { [Player]: BoostState } = setmetatable({}, { __mode = "k" })

local BOOST_FORCE_NAME = "PropelerBoost"
local BOOST_ATT_NAME = "PropelerBoostAtt"

local function setPropelerBoostForce(hrp: BasePart, forceY: number)
	if forceY <= 0 then
		local vf = hrp:FindFirstChild(BOOST_FORCE_NAME)
		if vf then
			vf.Enabled = false
		end
		return
	end

	local att = hrp:FindFirstChild(BOOST_ATT_NAME)
	if not att or not att:IsA("Attachment") then
		if att then
			att:Destroy()
		end
		att = Instance.new("Attachment")
		att.Name = BOOST_ATT_NAME
		att.Parent = hrp
	end

	local vf = hrp:FindFirstChild(BOOST_FORCE_NAME)
	if not vf or not vf:IsA("VectorForce") then
		if vf then
			vf:Destroy()
		end
		vf = Instance.new("VectorForce")
		vf.Name = BOOST_FORCE_NAME
		vf.Attachment0 = att :: Attachment
		vf.RelativeTo = Enum.ActuatorRelativeTo.World
		vf.ApplyAtCenterOfMass = true
		vf.Parent = hrp
	end

	vf.Enabled = true
	vf.Force = Vector3.new(0, forceY, 0)
end

function Module.GetFloatLiftMult(propBlend: number, manualHold: boolean): number
	propBlend = math.clamp(propBlend, 0, 1)
	local manual = Config.ManualFloatMult or 1
	local zone = Config.ZoneAutoFloatMult or 1.4
	local comboBonus = Config.ZoneComboHalfMult or 0.35

	if propBlend <= 0 then
		return manual
	end

	local zoneMult = manual + (zone - manual) * propBlend
	if manualHold then
		return zoneMult + comboBonus * propBlend
	end
	return zoneMult
end

function Module.ApplyPlayerBoost(_character: Model, _manualHold: boolean)
end

function Module.GetBoostRiseCap(_character: Model, _manualHold: boolean, baseCap: number): number
	return baseCap
end

function Module.ClearPlayerBoost(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		setPropelerBoostForce(hrp, 0)
	end
end

local function findChildPath(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for _, name in path do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

local function resolveRoot(path: { string }): Instance?
	local root = findChildPath(Workspace, path)
	if root then
		return root
	end
	local current: Instance = Workspace
	for _, name in path do
		local child = current:WaitForChild(name, 60)
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function collectEmitters(root: Instance): { ParticleEmitter }
	local emitters: { ParticleEmitter } = {}
	for _, desc in root:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			table.insert(emitters, desc)
		end
	end
	return emitters
end

local function setEmittersEnabled(unit: PropelerUnit, enabled: boolean)
	for _, emitter in unit.emitters do
		emitter.Enabled = enabled
	end
end

local function getNumber(source: Instance?, attr: string, fallback: number): number
	if source then
		local value = tonumber(source:GetAttribute(attr))
		if value ~= nil then
			return value
		end
	end
	return fallback
end

local function bindUnit(root: Instance, unitDef: any): PropelerUnit?
	local model = root:FindFirstChild(unitDef.ModelName or "PropelerModel")
	if not model or not model:IsA("Model") then
		model = root:WaitForChild(unitDef.ModelName or "PropelerModel", 30)
	end
	if not model or not model:IsA("Model") then
		return nil
	end

	local spinPart = model.PrimaryPart
	if not spinPart or not spinPart:IsA("BasePart") then
		spinPart = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not spinPart then
		return nil
	end

	local effectsPart = model:FindFirstChild(unitDef.EffectsPartName or "Effects", true)
	local idleSeconds = getNumber(root, "PropelerIdleSeconds", getNumber(model, "PropelerIdleSeconds", Config.IdleSeconds or 5))
	local activeSeconds = getNumber(root, "PropelerActiveSeconds", getNumber(model, "PropelerActiveSeconds", Config.ActiveSeconds or 5))
	local spinUpSeconds = getNumber(root, "PropelerSpinUpSeconds", getNumber(model, "PropelerSpinUpSeconds", Config.SpinUpSeconds or 1.25))
	local spinDownSeconds = getNumber(root, "PropelerSpinDownSeconds", getNumber(model, "PropelerSpinDownSeconds", Config.SpinDownSeconds or 1.25))
	local speedDegrees = getNumber(root, "PropelerSpeedDegrees", getNumber(model, "PropelerSpeedDegrees", Config.SpeedDegrees or 720))

	spinUpSeconds = math.max(0.05, spinUpSeconds)
	spinDownSeconds = math.max(0.05, spinDownSeconds)

	spinPart.Anchored = true

	local maxSpeedRad = math.rad(speedDegrees)

	local unit: PropelerUnit = {
		spinPart = spinPart,
		restCF = spinPart.CFrame,
		angle = 0,
		ramping = "none",
		spinSign = -1,
		maxSpeedRad = maxSpeedRad,
		currentSpeedRad = 0,
		accelRad = maxSpeedRad / spinUpSeconds,
		decelRad = maxSpeedRad / spinDownSeconds,
		idleSeconds = idleSeconds,
		activeSeconds = activeSeconds,
		spinUpSeconds = spinUpSeconds,
		spinDownSeconds = spinDownSeconds,
		emitters = if effectsPart and effectsPart:IsA("BasePart") then collectEmitters(effectsPart) else {},
	}

	setEmittersEnabled(unit, false)
	return unit
end

local function getBoostState(player: Player): BoostState
	local s = boostByPlayer[player]
	if not s then
		s = { blend = 0 }
		boostByPlayer[player] = s
	end
	return s
end

local function isUnitBlowing(unit: PropelerUnit): boolean
	return unit.ramping == "up" or unit.ramping == "hold" or unit.ramping == "down"
end

local function tickZone(dt: number)
	local radius = Config.ZoneRadius or 40
	local maxHeight = Config.ZoneMaxHeightAbove or 100
	local fadeIn = math.max(0.05, Config.ZoneFadeInSeconds or 0.7)
	local fadeOut = math.max(0.05, Config.ZoneFadeOutSeconds or 1.1)
	local radiusSq = radius * radius

	local activeFans: { Vector3 } = {}
	for _, unit in units do
		if isUnitBlowing(unit) and unit.spinPart.Parent then
			table.insert(activeFans, unit.spinPart.Position)
		end
	end

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then
			continue
		end

		local state = getBoostState(player)
		local blend = 0

		if BalloonFloat.getEquippedCount(character) > 0 and #activeFans > 0 then
			local pos = hrp.Position
			local inZone = false
			for _, center in activeFans do
				local dx = pos.X - center.X
				local dz = pos.Z - center.Z
				if dx * dx + dz * dz <= radiusSq then
					local heightAbove = pos.Y - center.Y
					if heightAbove > maxHeight then
						blend = 0
						state.blend = 0
					elseif heightAbove >= 0 then
						inZone = true
						blend = math.min(1, state.blend + dt / fadeIn)
					end
					break
				end
			end
			if not inZone and state.blend > 0 then
				blend = math.max(0, state.blend - dt / fadeOut)
			end
		elseif state.blend > 0 then
			blend = math.max(0, state.blend - dt / fadeOut)
		end

		state.blend = blend
		character:SetAttribute("PropelerBoostBlend", blend)

		if blend > 0 then
			character:SetAttribute("PropelerZoneActive", true)
		elseif character:GetAttribute("PropelerZoneActive") then
			character:SetAttribute("PropelerZoneActive", nil)
		end
	end
end

local function bakeRestOrientation(unit: PropelerUnit)
	unit.restCF = unit.spinPart.CFrame
	unit.angle = 0
end

function Module:OnPreSimulation(dt: number)
	for _, unit in units do
		if not unit.spinPart.Parent then
			continue
		end

		if unit.ramping == "up" then
			unit.currentSpeedRad = math.min(unit.maxSpeedRad, unit.currentSpeedRad + unit.accelRad * dt)
		elseif unit.ramping == "down" then
			unit.currentSpeedRad = math.max(0, unit.currentSpeedRad - unit.decelRad * dt)
		elseif unit.ramping == "hold" then
			unit.currentSpeedRad = unit.maxSpeedRad
		else
			unit.currentSpeedRad = 0
		end

		if unit.currentSpeedRad > 0 then
			unit.angle += unit.spinSign * unit.currentSpeedRad * dt
		end

		unit.spinPart.CFrame = unit.restCF * CFrame.Angles(0, unit.angle, 0)
	end

	tickZone(dt)
end

local function runUnitCycle(unit: PropelerUnit)
	task.spawn(function()
		while unit.spinPart.Parent do
			unit.ramping = "none"
			unit.currentSpeedRad = 0
			setEmittersEnabled(unit, false)
			task.wait(unit.idleSeconds)

			if not unit.spinPart.Parent then
				break
			end

			setEmittersEnabled(unit, true)
			unit.ramping = "up"
			task.wait(unit.spinUpSeconds)

			if not unit.spinPart.Parent then
				break
			end

			unit.ramping = "hold"
			task.wait(unit.activeSeconds)

			if not unit.spinPart.Parent then
				break
			end

			unit.ramping = "down"
			while unit.spinPart.Parent and unit.currentSpeedRad > 0.01 do
				RunService.PreSimulation:Wait()
			end

			unit.ramping = "none"
			unit.currentSpeedRad = 0
			bakeRestOrientation(unit)
			setEmittersEnabled(unit, false)
		end
	end)
end

local function setupUnit(unitDef: any)
	task.spawn(function()
		local root = resolveRoot(unitDef.RootPath or {})
		if not root then
			warn("[Server_Propeler] Missing " .. table.concat(unitDef.RootPath or {}, "."))
			return
		end

		local unit = bindUnit(root, unitDef)
		if not unit then
			warn("[Server_Propeler] Failed to bind " .. table.concat(unitDef.RootPath or {}, ".") .. "/" .. (unitDef.ModelName or "PropelerModel"))
			return
		end

		table.insert(units, unit)
		runUnitCycle(unit)
	end)
end

function Module:Init()
	Players.PlayerRemoving:Connect(function(player)
		boostByPlayer[player] = nil
	end)

	local function cleanupLegacyBoost(character: Model)
		Module.ClearPlayerBoost(character)
		for _, name in { "PropelerLiftBoost", "PropelerLiftAtt" } do
			local hrp = character:FindFirstChild("HumanoidRootPart")
			local inst = hrp and hrp:FindFirstChild(name)
			if inst then
				inst:Destroy()
			end
		end
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(cleanupLegacyBoost)
	end)
	for _, player in Players:GetPlayers() do
		if player.Character then
			cleanupLegacyBoost(player.Character)
		end
	end

	for _, unitDef in Config.Units or {} do
		setupUnit(unitDef)
	end
end

return Module
