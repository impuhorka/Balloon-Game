local ShooterBase = require(script.Parent.ShooterBase)
local ShooterArcher = require(script.Parent.ShooterArcher)

local StandingArcher = {}
local createStanding = ShooterBase.extend(StandingArcher)

local ARCHER_NAME = "Standing_Archer"

function StandingArcher.new(model: Model)
	return createStanding(model, "Standing")
end

function StandingArcher:RefreshParts()
	if self.Model and self.Model.Name == ARCHER_NAME then
		self:RefreshCannonParts("Bearing", "Holder")
		ShooterArcher.RefreshParts(self)
		self:EnsureMotors()
		return
	end
	ShooterBase.RefreshParts(self)
end

function StandingArcher:Update(dt: number)
	if not self.Model or self.Model.Name ~= ARCHER_NAME then
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
		local targetZ = self:GetTargetC1Z(self.PitchMotor, target.Position, minPitch, maxPitch, false)
		if targetZ then
			self:RotateBearing(target.Position, dt)
			self:RotatePitch(targetZ, dt, false)
			ShooterArcher.TryShoot(self, target, minPitch, maxPitch, false)
			return
		end
		self.LockedTargetPart = nil
	end

	self:RotatePitch(0, dt, false, false)
end

return StandingArcher
