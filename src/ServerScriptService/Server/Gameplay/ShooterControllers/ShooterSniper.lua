local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared_Shooters = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Shooters)
local ShooterProjectile = require(script.Parent.ShooterProjectile)

local ShooterSniper = {}

local PROJECTILE_SPEED = 150
local EMIT_COUNT = 20

local sniperShotTemplate: Model? = nil
local warnedMissingTemplate = false

local function getSniperShotTemplate(): Model?
	if sniperShotTemplate and sniperShotTemplate.Parent then
		return sniperShotTemplate
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local shooterAssets = assets and assets:FindFirstChild("ShootersAssets")
	sniperShotTemplate = (shooterAssets and shooterAssets:FindFirstChild("SniperShot"))
		or (assets and assets:FindFirstChild("SniperShot")) :: Model?
	return sniperShotTemplate
end

function ShooterSniper.RefreshParts(controller)
	controller.ShootPart = controller:FindPart("ShootPart")
	controller.ProjectileAttachment = nil
	if not controller.ShootPart then
		return
	end
	local attachment = controller.ShootPart:FindFirstChild("ProjectileAttachment", true)
	if attachment and attachment:IsA("Attachment") then
		controller.ProjectileAttachment = attachment
	end
end

function ShooterSniper.GetCooldown(model: Model): number
	return Shared_Shooters.GetCooldown(model.Name)
end

function ShooterSniper.EmitShot(attachment: Attachment)
	for _, desc in attachment:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			desc:Emit(EMIT_COUNT)
		end
	end
end

local function prepShot(shot: Model)
	for _, desc in shot:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
		end
	end
end

function ShooterSniper.Fire(controller, targetPart: BasePart)
	local attachment = controller.ProjectileAttachment
	if not attachment or not targetPart or not targetPart.Parent then
		return
	end

	local attCF = attachment.WorldCFrame
	local startPos = attCF.Position
	local targetPos = targetPart.Position
	local distance = (targetPos - startPos).Magnitude
	if distance < 0.05 then
		return
	end

	ShooterSniper.EmitShot(attachment)

	local template = getSniperShotTemplate()
	if not template then
		if not warnedMissingTemplate then
			warnedMissingTemplate = true
			warn("ShooterSniper: SniperShot not found in ReplicatedStorage.Assets.ShootersAssets")
		end
		return
	end

	local shot = template:Clone()
	prepShot(shot)

	local spawnCF = CFrame.lookAt(startPos, startPos - attCF.RightVector)
	shot:PivotTo(spawnCF)
	shot.Parent = workspace

	local travelTime = math.max(0.05, distance / PROJECTILE_SPEED)
	local direction = (targetPos - startPos).Unit

	task.spawn(function()
		ShooterProjectile.RunFlight(controller.Model, targetPart, startPos, PROJECTILE_SPEED, function(pos, dir)
			shot:PivotTo(CFrame.lookAt(pos, pos + dir))
		end)
		if shot.Parent then
			shot:Destroy()
		end
	end)

	Debris:AddItem(shot, travelTime + 1)
end

function ShooterSniper.TryShoot(
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
	local cooldown = ShooterSniper.GetCooldown(controller.Model)
	if now - (controller.LastShotTime or 0) < cooldown then
		return
	end

	if not controller:IsAimedAtTarget(targetPart.Position, minPitch, maxPitch, clampOnly) then
		return
	end

	controller.LastShotTime = now
	ShooterSniper.Fire(controller, targetPart)
end

return ShooterSniper
