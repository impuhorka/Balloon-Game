local ShooterBase = require(script.Parent.ShooterBase)
local ShooterMotors = require(script.Parent.ShooterMotors)
local ShooterSniper = require(script.Parent.ShooterSniper)

local WallSniper = {}
local createWall = ShooterBase.extend(WallSniper)

local SNIPER_NAME = "Wall_Sniper"
local DEFAULT_TRACK_HEIGHT = 30

function WallSniper.new(model: Model)
	return createWall(model, "Wall")
end

function WallSniper:UsesPitchXMotor(): boolean
	return true
end

function WallSniper:GetTrackHeightLimit(): number
	return ShooterMotors.GetAttrNumber(self.Model, "TrackHeightOffset", DEFAULT_TRACK_HEIGHT)
end

function WallSniper:RefreshParts()
	if self.Model and self.Model.Name == SNIPER_NAME then
		self:RefreshCannonParts("Bearing", "Holder")
		ShooterSniper.RefreshParts(self)
		self:ResetMotors()
		self:EnsureMotors()
		return
	end
	ShooterBase.RefreshParts(self)
end

function WallSniper:IsWithinTrackHeight(targetPos: Vector3): boolean
	if not self.Bearing then
		return false
	end
	return math.abs(targetPos.Y - self.Bearing.Position.Y) <= self:GetTrackHeightLimit()
end

function WallSniper:IsBehindBottomDirection(targetPos: Vector3): boolean
	if not self.Bearing then
		return true
	end

	local toTarget = targetPos - self.Bearing.Position
	if toTarget.Magnitude < 0.001 then
		return false
	end

	return toTarget:Dot(-self.Bearing.CFrame.UpVector) > 0
end

function WallSniper:CanTrackBalloon(targetPos: Vector3): boolean
	return self:IsWithinTrackHeight(targetPos) and not self:IsBehindBottomDirection(targetPos)
end

function WallSniper:Update(dt: number)
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

	if target then
		self:RotateBearing(target.Position, dt)
		if self.PitchMotor then
			local targetX = self:GetTargetC1X(self.PitchMotor, target.Position, minPitch, maxPitch, true)
			self:RotatePitchX(targetX or 0, dt, true)
		end
		ShooterSniper.TryShoot(self, target, minPitch, maxPitch, true)
		return
	end

	self:RotateBearingToZero(dt)
	self:RotatePitchXToRest(dt)
end

return WallSniper
