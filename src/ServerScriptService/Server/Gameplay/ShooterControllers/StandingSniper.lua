local ShooterBase = require(script.Parent.ShooterBase)
local ShooterSniper = require(script.Parent.ShooterSniper)

local StandingSniper = {}
local createStandingSniper = ShooterBase.extend(StandingSniper)

local SNIPER_NAME = "Standing_Sniper"

function StandingSniper.new(model: Model)
	return createStandingSniper(model, "Standing")
end

function StandingSniper:UsesPitchXMotor(): boolean
	return true
end

function StandingSniper:CanTrackBalloon(targetPos: Vector3): boolean
	if not self.PitchMotor then
		return false
	end
	local minPitch, maxPitch = self:GetPitchLimits()
	return self:GetTargetC1X(self.PitchMotor, targetPos, minPitch, maxPitch, false) ~= nil
end

function StandingSniper:RefreshParts()
	if self.Model and self.Model.Name == SNIPER_NAME then
		self:RefreshCannonParts("Bearing", "Holder")
		ShooterSniper.RefreshParts(self)
		self:EnsureMotors()
		return
	end
	ShooterBase.RefreshParts(self)
end

function StandingSniper:Update(dt: number)
	if not self.Model or self.Model.Name ~= SNIPER_NAME then
		return ShooterBase.Update(self, dt)
	end
	if not self:EnsureReady() then
		return
	end

	self:EnsureMotors()
	self:RefreshLock()

	local target = self.LockedTargetPart
	local minPitch, maxPitch = self:GetPitchLimits()

	if target and self.PitchMotor then
		local targetX = self:GetTargetC1X(self.PitchMotor, target.Position, minPitch, maxPitch, false)
		if targetX then
			self:RotateBearing(target.Position, dt)
			self:RotatePitchX(targetX, dt, true)
			ShooterSniper.TryShoot(self, target, minPitch, maxPitch, false)
			return
		end
	end

	self:RotateBearingToZero(dt)
	self:RotatePitchXToRest(dt)
end

return StandingSniper
