local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BalloonRigKit = require(ReplicatedStorage.Modules.Gameplay.BalloonRigKit)
local Shared_Shooters = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Shooters)
local Server_Balloon = require(script.Parent.Parent.Server_Balloon)

local ShooterProjectile = {}

local HIT_RADIUS = 10
local LEAD_ITERATIONS = 2
local STEER_BLEND = 0.55
local MAX_FLIGHT_OVERSHOOT = 0.35

local function getBalloonModelFromPart(part: BasePart?): Model?
	if not part then
		return nil
	end
	local balloonModel = part:FindFirstAncestorWhichIsA("Model")
	if not balloonModel then
		return nil
	end
	local folder = balloonModel.Parent
	if not folder or not folder:IsA("Folder") or folder.Name ~= BalloonRigKit.ATTACHED_BALLOONS_FOLDER then
		return nil
	end
	return balloonModel
end

local function getHitPart(targetPart: BasePart): BasePart
	local balloonModel = getBalloonModelFromPart(targetPart)
	if balloonModel then
		return balloonModel.PrimaryPart or targetPart
	end
	return targetPart
end

local function closestPointOnSegment(a: Vector3, b: Vector3, p: Vector3): Vector3
	local ab = b - a
	local lenSq = ab:Dot(ab)
	if lenSq < 1e-6 then
		return a
	end
	local t = math.clamp((p - a):Dot(ab) / lenSq, 0, 1)
	return a + ab * t
end

function ShooterProjectile.GetLeadPosition(targetPart: BasePart, fromPos: Vector3, projectileSpeed: number): Vector3
	local targetPos = targetPart.Position
	local relVel = targetPart.AssemblyLinearVelocity
	local leadPos = targetPos
	for _ = 1, LEAD_ITERATIONS do
		local travelTime = math.max(0.05, (leadPos - fromPos).Magnitude / projectileSpeed)
		leadPos = targetPos + relVel * travelTime
	end
	return leadPos
end

function ShooterProjectile.TryHitSegment(
	shooterModel: Model,
	fromPos: Vector3,
	toPos: Vector3,
	targetPart: BasePart?
): boolean
	if not targetPart or not targetPart.Parent then
		return false
	end

	local balloonModel = getBalloonModelFromPart(targetPart)
	if not balloonModel then
		return false
	end

	local hitPart = getHitPart(targetPart)
	local closest = closestPointOnSegment(fromPos, toPos, hitPart.Position)
	if (closest - hitPart.Position).Magnitude > HIT_RADIUS then
		return false
	end

	local damage = Shared_Shooters.GetDamage(shooterModel.Name)
	if damage <= 0 then
		return false
	end

	return Server_Balloon.damageBalloonFromShooter(balloonModel, damage)
end

function ShooterProjectile.TryHitTarget(shooterModel: Model, projectilePos: Vector3, targetPart: BasePart?): boolean
	if not targetPart or not targetPart.Parent then
		return false
	end

	local hitPart = getHitPart(targetPart)
	if (projectilePos - hitPart.Position).Magnitude > HIT_RADIUS then
		return false
	end

	local balloonModel = getBalloonModelFromPart(targetPart)
	if not balloonModel then
		return false
	end

	local damage = Shared_Shooters.GetDamage(shooterModel.Name)
	if damage <= 0 then
		return false
	end

	return Server_Balloon.damageBalloonFromShooter(balloonModel, damage)
end

function ShooterProjectile.RunFlight(
	shooterModel: Model,
	targetPart: BasePart,
	startPos: Vector3,
	projectileSpeed: number,
	updateVisual: (Vector3, Vector3) -> ()
): boolean
	if not targetPart or not targetPart.Parent then
		return false
	end

	local leadPos = ShooterProjectile.GetLeadPosition(targetPart, startPos, projectileSpeed)
	local toLead = leadPos - startPos
	local distance = toLead.Magnitude
	if distance < 0.05 then
		return false
	end

	local direction = toLead.Unit
	local travelTime = distance / projectileSpeed
	local maxTime = travelTime * (1 + MAX_FLIGHT_OVERSHOOT) + 0.2
	local elapsed = 0
	local lastPos = startPos
	local hit = false

	updateVisual(startPos, direction)

	while elapsed < maxTime and targetPart.Parent and not hit do
		local dt = task.wait()
		elapsed += dt

		local aimPos = ShooterProjectile.GetLeadPosition(targetPart, lastPos, projectileSpeed)
		local toAim = aimPos - lastPos
		if toAim.Magnitude > 0.05 then
			direction = (direction * (1 - STEER_BLEND) + toAim.Unit * STEER_BLEND).Unit
		end

		local pos = lastPos + direction * (projectileSpeed * dt)
		hit = ShooterProjectile.TryHitSegment(shooterModel, lastPos, pos, targetPart)
		updateVisual(pos, direction)
		lastPos = pos
	end

	return hit
end

return ShooterProjectile
