local ShooterBase = require(script.Parent.ShooterBase)
local ShooterMotors = require(script.Parent.ShooterMotors)
local ShooterArcher = require(script.Parent.ShooterArcher)

local WallArcher = {}
local createWall = ShooterBase.extend(WallArcher)

local ARCHER_NAME = "Wall_Archer"
local DEFAULT_TRACK_HEIGHT = 30

function WallArcher.new(model: Model)
	return createWall(model, "Wall")
end

function WallArcher:GetTrackHeightLimit(): number
	return ShooterMotors.GetAttrNumber(self.Model, "TrackHeightOffset", DEFAULT_TRACK_HEIGHT)
end

function WallArcher:RefreshParts()
	if self.Model and self.Model.Name == ARCHER_NAME then
		self:RefreshCannonParts("Bearing", "Holder")
		ShooterArcher.RefreshParts(self)
		self:ResetMotors()
		self:EnsureMotors()
		return
	end
	ShooterBase.RefreshParts(self)
end

function WallArcher:IsWithinTrackHeight(targetPos: Vector3): boolean
	if not self.Bearing then
		return false
	end
	return math.abs(targetPos.Y - self.Bearing.Position.Y) <= self:GetTrackHeightLimit()
end

function WallArcher:IsBehindBottomDirection(targetPos: Vector3): boolean
	if not self.Bearing then
		return true
	end

	local toTarget = targetPos - self.Bearing.Position
	if toTarget.Magnitude < 0.001 then
		return false
	end

	return toTarget:Dot(-self.Bearing.CFrame.UpVector) > 0
end

function WallArcher:CanTrackBalloon(targetPos: Vector3): boolean
	return self:IsWithinTrackHeight(targetPos) and not self:IsBehindBottomDirection(targetPos)
end

function WallArcher:Update(dt: number)
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

	if target then
		self:RotateBearing(target.Position, dt)
		if self.PitchMotor then
			local targetZ = self:GetTargetC1Z(self.PitchMotor, target.Position, minPitch, maxPitch, true)
			self:RotatePitch(targetZ or 0, dt, true)
		end
		ShooterArcher.TryShoot(self, target, minPitch, maxPitch, true)
		return
	end

	self:RotateBearingToZero(dt)
	self:RotatePitchToRest(dt)
end

return WallArcher
