local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared_Shooters = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Shooters)
local ShooterProjectile = require(script.Parent.ShooterProjectile)

local ShooterCannon = {}

local PROJECTILE_SPEED = 150
local EMIT_COUNT = 20

local cannonBallTemplate: Model? = nil

local function getCannonBallTemplate(): Model?
	if cannonBallTemplate and cannonBallTemplate.Parent then
		return cannonBallTemplate
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local shooterAssets = assets and assets:FindFirstChild("ShootersAssets")
	cannonBallTemplate = shooterAssets and shooterAssets:FindFirstChild("CannonBall") :: Model?
	return cannonBallTemplate
end

function ShooterCannon.RefreshParts(controller)
	controller.ShootPart = controller:FindDirectPart("ShootPart")
	controller.ProjectileAttachment = nil
	if not controller.ShootPart then
		return
	end
	local attachment = controller.ShootPart:FindFirstChild("ProjectileAttachment")
	if attachment and attachment:IsA("Attachment") then
		controller.ProjectileAttachment = attachment
	end
end

function ShooterCannon.GetCooldown(model: Model): number
	return Shared_Shooters.GetCooldown(model.Name)
end

function ShooterCannon.EmitShot(attachment: Attachment)
	for _, desc in attachment:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			desc:Emit(EMIT_COUNT)
		end
	end
end

local function prepBall(ball: Model)
	for _, desc in ball:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
		end
	end
end

function ShooterCannon.Fire(controller, targetPart: BasePart)
	local attachment = controller.ProjectileAttachment
	if not attachment or not targetPart or not targetPart.Parent then
		return
	end

	local template = getCannonBallTemplate()
	if not template then
		return
	end

	local attCF = attachment.WorldCFrame
	local startPos = attCF.Position
	local targetPos = targetPart.Position
	local distance = (targetPos - startPos).Magnitude
	if distance < 0.05 then
		return
	end

	ShooterCannon.EmitShot(attachment)

	local ball = template:Clone()
	prepBall(ball)

	local spawnCF = CFrame.lookAt(startPos, startPos - attCF.RightVector)
	ball:PivotTo(spawnCF)
	ball.Parent = workspace

	local travelTime = math.max(0.05, distance / PROJECTILE_SPEED)
	local direction = (targetPos - startPos).Unit

	task.spawn(function()
		ShooterProjectile.RunFlight(controller.Model, targetPart, startPos, PROJECTILE_SPEED, function(pos, dir)
			ball:PivotTo(CFrame.lookAt(pos, pos + dir))
		end)
		if ball.Parent then
			ball:Destroy()
		end
	end)

	Debris:AddItem(ball, travelTime + 1)
end

function ShooterCannon.TryShoot(
	controller,
	targetPart: BasePart?,
	minPitch: number,
	maxPitch: number,
	clampOnly: boolean
)
	if not targetPart then
		return
	end
	if not controller.ProjectileAttachment then
		return
	end

	local now = os.clock()
	local cooldown = ShooterCannon.GetCooldown(controller.Model)
	if now - (controller.LastShotTime or 0) < cooldown then
		return
	end

	if not controller:IsAimedAtTarget(targetPart.Position, minPitch, maxPitch, clampOnly) then
		return
	end

	controller.LastShotTime = now
	ShooterCannon.Fire(controller, targetPart)
end

return ShooterCannon
