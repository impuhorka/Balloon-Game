local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalloonRigKit = require(ReplicatedStorage.Modules.Gameplay.BalloonRigKit)
local Shared_Shooters = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Shooters)
local ShooterMotors = require(script.Parent.ShooterMotors)

local ShooterBase = {}
ShooterBase.__index = ShooterBase

function ShooterBase.extend(child: { [string]: any })
	child.__index = child
	setmetatable(child, { __index = ShooterBase })
	return function(model: Model, typeName: string)
		local self = ShooterBase.new(model, typeName)
		local instance = setmetatable(self, {
			__index = function(_, key)
				local override = rawget(child, key)
				if override ~= nil then
					return override
				end
				return ShooterBase[key]
			end,
		})
		instance:RefreshParts()
		return instance
	end
end

function ShooterBase.new(model: Model, typeName: string)
	local self = setmetatable({}, ShooterBase)
	self.Model = model
	self.TypeName = typeName
	self.Bearing = nil
	self.HolderPart = nil
	self.BearingMotor = nil
	self.PitchMotor = nil
	self.LockedTargetPart = nil
	self.LastShotTime = 0
	return self
end

function ShooterBase:GetBearingPartNames(): { string }
	return { "Bearing", "bearing" }
end

function ShooterBase:GetHolderPartNames(): { string }
	return { "HolderPart", "Holder", "holder" }
end

function ShooterBase:FindPartByNames(names: { string }): BasePart?
	for _, name in ipairs(names) do
		local found = self.Model:FindFirstChild(name, true)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	return nil
end

function ShooterBase:FindDirectPart(name: string): BasePart?
	local found = self.Model:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

function ShooterBase:FindPart(name: string): BasePart?
	return self:FindDirectPart(name) or self:FindPartByNames({ name })
end

function ShooterBase:RefreshCannonParts(bearingName: string, holderName: string)
	self.Bearing = self:FindPart(bearingName)
	self.HolderPart = self:FindPart(holderName)

	if not self.HolderPart then
		self.HolderPart = self.Model.PrimaryPart or self.Model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not self.Bearing then
		self.Bearing = self.HolderPart
	end
end

function ShooterBase:RefreshParts()
	if not self.Model or not self.Model.Parent then
		self.Bearing = nil
		self.HolderPart = nil
		return
	end

	self.Bearing = self:FindPartByNames(self:GetBearingPartNames())
	self.HolderPart = self:FindPartByNames(self:GetHolderPartNames())

	if not self.HolderPart then
		self.HolderPart = self.Model.PrimaryPart or self.Model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not self.Bearing then
		self.Bearing = self.HolderPart
	end
end

function ShooterBase:ResetMotors()
	self.BearingMotor = nil
	self.PitchMotor = nil
	self.BearingMotorC1Pos = nil
	self.PitchMotorC1Pos = nil
	self.PitchMotorRestC1 = nil
end

function ShooterBase:EnsureBearingMotor()
	if self.BearingMotor and self.BearingMotor.Parent then
		return
	end
	if not self.Bearing then
		return
	end

	self.BearingMotor = ShooterMotors.FindByPart1(self.Model, self.Bearing)
		or ShooterMotors.FindFirstOnPart(self.Bearing)
	if self.BearingMotor and not self.BearingMotorC1Pos then
		self.BearingMotorC1Pos = ShooterMotors.CacheC1(self.BearingMotor)
	end
end

function ShooterBase:EnsurePitchMotor()
	if self.PitchMotor and self.PitchMotor.Parent then
		return
	end
	if not self.HolderPart then
		return
	end

	self:EnsureBearingMotor()

	local onHolder = ShooterMotors.FindFirstOnPart(self.HolderPart)
	if onHolder and onHolder ~= self.BearingMotor and onHolder.Part0 then
		self.PitchMotor = onHolder
	else
		self.PitchMotor = ShooterMotors.FindByPart(self.Model, self.HolderPart, self.BearingMotor)
	end
	if self.PitchMotor and not self.PitchMotorC1Pos then
		self.PitchMotorC1Pos, self.PitchMotorRestC1 = ShooterMotors.CacheC1(self.PitchMotor)
	end
end

function ShooterBase:EnsureMotors()
	self:EnsureBearingMotor()
	self:EnsurePitchMotor()
end

function ShooterBase:GetYawOffset(): number
	return ShooterMotors.GetAttrNumber(self.Model, "AimYawOffset", ShooterMotors.LEFT_IS_FRONT_OFFSET)
end

function ShooterBase:GetPitchOffset(): number
	return ShooterMotors.GetAttrNumber(self.Model, "AimPitchOffset", 0)
end

function ShooterBase:GetPitchLimits(): (number, number)
	local defaults = Shared_Shooters.PitchLimits and Shared_Shooters.PitchLimits[self.Model.Name]
	local minDeg = tonumber(self.Model:GetAttribute("MinPitchDeg")) or (defaults and defaults.Min) or -25
	local maxDeg = tonumber(self.Model:GetAttribute("MaxPitchDeg")) or (defaults and defaults.Max) or 50
	return math.rad(minDeg), math.rad(maxDeg)
end

function ShooterBase:GetNoticeRadius(): number
	return ShooterMotors.GetAttrNumber(self.Model, "NoticeRadius", 250)
end

function ShooterBase:GetTurnStep(dt: number): number
	local turnSpeedDeg = ShooterMotors.GetAttrNumber(self.Model, "TurnSpeed", 180)
	return math.rad(turnSpeedDeg) * dt
end

function ShooterBase:HasActiveBalloon(character: Model): boolean
	local folder = character:FindFirstChild(BalloonRigKit.ATTACHED_BALLOONS_FOLDER)
	if not folder or not folder:IsA("Folder") then
		return false
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			return true
		end
	end
	return false
end

function ShooterBase:IsPlayerOnGround(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return true
	end
	return humanoid.FloorMaterial ~= Enum.Material.Air
end

function ShooterBase:IsPlayerEligible(character: Model): boolean
	return self:HasActiveBalloon(character) and not self:IsPlayerOnGround(character)
end

function ShooterBase:CollectEligibleBalloonParts(): { BasePart }
	local parts: { BasePart } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character or not self:IsPlayerEligible(character) then
			continue
		end

		local folder = character:FindFirstChild(BalloonRigKit.ATTACHED_BALLOONS_FOLDER)
		if not folder or not folder:IsA("Folder") then
			continue
		end

		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") then
				local part = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart", true)
				if part and part:IsA("BasePart") then
					table.insert(parts, part)
				end
			end
		end
	end
	return parts
end

function ShooterBase:IsTargetStillValid(targetPart: BasePart?): boolean
	if not targetPart or not targetPart.Parent then
		return false
	end

	local balloonModel = targetPart:FindFirstAncestorWhichIsA("Model")
	if not balloonModel or not balloonModel.Parent then
		return false
	end

	local folder = balloonModel.Parent
	if not folder:IsA("Folder") or folder.Name ~= BalloonRigKit.ATTACHED_BALLOONS_FOLDER then
		return false
	end

	local character = folder.Parent
	if not character or not character:IsA("Model") or not self:IsPlayerEligible(character) then
		return false
	end

	if not self.Bearing then
		return false
	end

	local maxDistance = self:GetNoticeRadius()
	local delta = targetPart.Position - self.Bearing.Position
	return delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z <= maxDistance * maxDistance
end

function ShooterBase:CanTrackBalloon(_targetPos: Vector3): boolean
	return true
end

function ShooterBase:AcquireTargetPart(): BasePart?
	if not self.Bearing then
		return nil
	end

	local origin = self.Bearing.Position
	local maxDistanceSq = self:GetNoticeRadius() ^ 2
	local bestPart = nil
	local bestDistSq = maxDistanceSq

	for _, balloonPart in self:CollectEligibleBalloonParts() do
		if self:CanTrackBalloon(balloonPart.Position) then
			local delta = balloonPart.Position - origin
			local distSq = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
			if distSq <= maxDistanceSq and distSq < bestDistSq then
				bestDistSq = distSq
				bestPart = balloonPart
			end
		end
	end

	return bestPart
end

function ShooterBase:RefreshLock()
	if not self:IsTargetStillValid(self.LockedTargetPart) or not self:CanTrackBalloon(self.LockedTargetPart.Position) then
		self.LockedTargetPart = self:AcquireTargetPart()
	end
end

function ShooterBase:UsesPitchXMotor(): boolean
	return false
end

function ShooterBase:IsAimedAtTarget(
	targetPos: Vector3,
	minPitch: number,
	maxPitch: number,
	clampOnly: boolean
): boolean
	if not self.PitchMotor then
		return false
	end

	local thresholdDeg = ShooterMotors.GetAttrNumber(
		self.Model,
		"ShotAimThresholdDeg",
		ShooterMotors.GetAttrNumber(self.Model, "AimThresholdDeg", 2)
	)
	local threshold = math.rad(thresholdDeg)

	if self.BearingMotor and self.BearingMotor ~= self.PitchMotor then
		local targetY = self:GetTargetC1Y(self.BearingMotor, targetPos)
		if not targetY then
			return false
		end
		local _, currentY, _ = self.BearingMotor.C1:ToEulerAnglesYXZ()
		local yawDelta = (targetY - currentY) % (math.pi * 2)
		if yawDelta > math.pi then
			yawDelta -= math.pi * 2
		elseif yawDelta < -math.pi then
			yawDelta += math.pi * 2
		end
		if math.abs(yawDelta) > threshold then
			return false
		end
	end

	if self:UsesPitchXMotor() then
		local targetX = self:GetTargetC1X(self.PitchMotor, targetPos, minPitch, maxPitch, clampOnly)
		if targetX == nil then
			return false
		end
		local currentX, _, _ = self.PitchMotor.C1:ToEulerAnglesYXZ()
		if math.abs(targetX - currentX) > threshold then
			return false
		end
	else
		local targetZ = self:GetTargetC1Z(self.PitchMotor, targetPos, minPitch, maxPitch, clampOnly)
		if targetZ == nil then
			return false
		end
		local _, _, currentZ = self.PitchMotor.C1:ToEulerAnglesYXZ()
		if math.abs(targetZ - currentZ) > threshold then
			return false
		end
	end

	return true
end

function ShooterBase:GetTargetC1Y(motor: Motor6D, targetPos: Vector3): number?
	return ShooterMotors.GetTargetC1Y(motor, targetPos, self:GetYawOffset())
end

function ShooterBase:GetTargetC1Z(
	motor: Motor6D,
	targetPos: Vector3,
	minPitch: number,
	maxPitch: number,
	clampOnly: boolean
): number?
	return ShooterMotors.GetTargetC1Z(
		motor,
		targetPos,
		minPitch,
		maxPitch,
		self:GetPitchOffset(),
		clampOnly
	)
end

function ShooterBase:GetTargetC1X(motor: Motor6D, targetPos: Vector3, minPitch: number, maxPitch: number, clampOnly: boolean): number?
	return ShooterMotors.GetTargetC1X(motor, targetPos, minPitch, maxPitch, self:GetPitchOffset(), clampOnly)
end

function ShooterBase:RotateBearing(targetPos: Vector3, dt: number)
	local motor = self.BearingMotor
	if not motor or not motor.Part0 then
		return
	end

	local targetY = self:GetTargetC1Y(motor, targetPos)
	if not targetY then
		return
	end

	local pos = self.BearingMotorC1Pos or motor.C1.Position
	ShooterMotors.ApplyC1Y(motor, pos, targetY, self:GetTurnStep(dt), self.Model, true)
end

function ShooterBase:RotateBearingToZero(dt: number)
	local motor = self.BearingMotor
	if not motor or not motor.Part0 then
		return
	end

	local pos = self.BearingMotorC1Pos or motor.C1.Position
	ShooterMotors.ApplyC1Y(motor, pos, 0, self:GetTurnStep(dt), self.Model, false)
end

function ShooterBase:RotatePitch(targetZ: number, dt: number, useRestRotation: boolean, adaptive: boolean?)
	local motor = self.PitchMotor
	if not motor then
		return
	end

	local rest = self.PitchMotorRestC1 or motor.C1
	local pos = self.PitchMotorC1Pos or rest.Position
	local restX, restY = 0, 0
	if useRestRotation then
		restX, restY = rest:ToEulerAnglesYXZ()
	end
	ShooterMotors.ApplyC1Z(motor, pos, restX, restY, targetZ, self:GetTurnStep(dt), self.Model, adaptive)
end

function ShooterBase:RotatePitchToRest(dt: number)
	local motor = self.PitchMotor
	if not motor then
		return
	end

	local rest = self.PitchMotorRestC1 or motor.C1
	local pos = self.PitchMotorC1Pos or rest.Position
	local restX, restY, restZ = rest:ToEulerAnglesYXZ()
	ShooterMotors.ApplyC1Z(motor, pos, restX, restY, restZ, self:GetTurnStep(dt), self.Model, false)
end

function ShooterBase:RotatePitchX(targetX: number, dt: number, useRestRotation: boolean, adaptive: boolean?)
	local motor = self.PitchMotor
	if not motor then
		return
	end

	local rest = self.PitchMotorRestC1 or motor.C1
	local pos = self.PitchMotorC1Pos or rest.Position
	local restY, restZ = 0, 0
	if useRestRotation then
		_, restY, restZ = rest:ToEulerAnglesYXZ()
	end
	ShooterMotors.ApplyC1X(motor, pos, restY, restZ, targetX, self:GetTurnStep(dt), self.Model, adaptive)
end

function ShooterBase:RotatePitchXToRest(dt: number)
	local motor = self.PitchMotor
	if not motor then
		return
	end

	local rest = self.PitchMotorRestC1 or motor.C1
	local pos = self.PitchMotorC1Pos or rest.Position
	local restX, restY, restZ = rest:ToEulerAnglesYXZ()
	ShooterMotors.ApplyC1X(motor, pos, restY, restZ, restX, self:GetTurnStep(dt), self.Model, false)
end

function ShooterBase:EnsureReady(): boolean
	if not self.Model or not self.Model.Parent then
		return false
	end
	if not self.Bearing or not self.HolderPart or not self.Bearing.Parent or not self.HolderPart.Parent then
		self:RefreshParts()
	end
	return self.Bearing ~= nil and self.HolderPart ~= nil
end

function ShooterBase:Update(_dt: number)
end

return ShooterBase
