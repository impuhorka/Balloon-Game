local ShooterBase = require(script.Parent.ShooterBase)
local ShooterCannon = require(script.Parent.ShooterCannon)

local StandingShooter = {}
local createStanding = ShooterBase.extend(StandingShooter)

local CANNON_NAME = "Standing_Cannon"

function StandingShooter.new(model: Model)
	return createStanding(model, "Standing")
end

function StandingShooter:RefreshParts()
	if self.Model and self.Model.Name == CANNON_NAME then
		self:RefreshCannonParts("Bearing", "Holder")
		ShooterCannon.RefreshParts(self)
		self:EnsureMotors()
		return
	end
	ShooterBase.RefreshParts(self)
end

function StandingShooter:Update(dt: number)
	if not self.Model or self.Model.Name ~= CANNON_NAME then
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
			ShooterCannon.TryShoot(self, target, minPitch, maxPitch, false)
			return
		end
		self.LockedTargetPart = nil
	end

	self:RotatePitch(0, dt, false, false)
end

return StandingShooter
