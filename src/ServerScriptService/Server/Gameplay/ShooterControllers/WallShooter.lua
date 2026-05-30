local ShooterBase = require(script.Parent.ShooterBase)
local ShooterMotors = require(script.Parent.ShooterMotors)
local ShooterCannon = require(script.Parent.ShooterCannon)

local WallShooter = {}
local createWall = ShooterBase.extend(WallShooter)

local CANNON_NAME = "Wall_Cannon"
local DEFAULT_TRACK_HEIGHT = 30

function WallShooter.new(model: Model)
	return createWall(model, "Wall")
end

function WallShooter:GetTrackHeightLimit(): number
	return ShooterMotors.GetAttrNumber(self.Model, "TrackHeightOffset", DEFAULT_TRACK_HEIGHT)
end

function WallShooter:RefreshParts()
	if self.Model and self.Model.Name == CANNON_NAME then
		self:RefreshCannonParts("Bearing", "Holder")
		ShooterCannon.RefreshParts(self)
		self:ResetMotors()
		self:EnsureMotors()
		return
	end
	ShooterBase.RefreshParts(self)
end

function WallShooter:IsWithinTrackHeight(targetPos: Vector3): boolean
	if not self.Bearing then
		return false
	end
	return math.abs(targetPos.Y - self.Bearing.Position.Y) <= self:GetTrackHeightLimit()
end

function WallShooter:IsBehindBottomDirection(targetPos: Vector3): boolean
	if not self.Bearing then
		return true
	end

	local toTarget = targetPos - self.Bearing.Position
	if toTarget.Magnitude < 0.001 then
		return false
	end

	return toTarget:Dot(-self.Bearing.CFrame.UpVector) > 0
end

function WallShooter:CanTrackBalloon(targetPos: Vector3): boolean
	return self:IsWithinTrackHeight(targetPos) and not self:IsBehindBottomDirection(targetPos)
end

function WallShooter:Update(dt: number)
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

	if target then
		self:RotateBearing(target.Position, dt)
		if self.PitchMotor then
			local targetZ = self:GetTargetC1Z(self.PitchMotor, target.Position, minPitch, maxPitch, true)
			self:RotatePitch(targetZ or 0, dt, true)
		end
		ShooterCannon.TryShoot(self, target, minPitch, maxPitch, true)
		return
	end

	self:RotateBearingToZero(dt)
	self:RotatePitchToRest(dt)
end

return WallShooter
