local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared_Shooters = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Shooters)
local ShooterProjectile = require(script.Parent.ShooterProjectile)
local ShooterSfx = require(script.Parent.ShooterSfx)

local ShooterArcher = {}

local PROJECTILE_SPEED = 210
local EMIT_COUNT = 20
local RELOAD_TIME = 1
local ARROW_FADE_IN = 0.3

local arrowTemplate: Model? = nil

local function getArrowTemplate(): Model?
	if arrowTemplate and arrowTemplate.Parent then
		return arrowTemplate
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local shooterAssets = assets and assets:FindFirstChild("ShootersAssets")
	arrowTemplate = shooterAssets and shooterAssets:FindFirstChild("Arrow") :: Model?
	return arrowTemplate
end

local function prepArrowRest(arrow: Model)
	for _, desc in arrow:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
		end
	end
end

local function prepArrowFlying(arrow: Model)
	for _, desc in arrow:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
		end
	end
end

local function getArrowPrimary(arrow: Model): BasePart?
	return arrow.PrimaryPart or arrow:FindFirstChildWhichIsA("BasePart", true)
end

local function setArrowVisible(arrow: Model, transparency: number)
	for _, desc in arrow:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Transparency = transparency
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc.Transparency = transparency
		end
	end
end

local function fadeInArrow(arrow: Model)
	local goals: { [Instance]: number } = {}
	for _, desc in arrow:GetDescendants() do
		if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
			goals[desc] = desc.Transparency
			desc.Transparency = 1
		end
	end

	task.spawn(function()
		local elapsed = 0
		while elapsed < ARROW_FADE_IN and arrow.Parent do
			local dt = task.wait()
			elapsed += dt
			local t = math.min(1, elapsed / ARROW_FADE_IN)
			for inst, goal in goals do
				if inst.Parent then
					inst.Transparency = 1 + (goal - 1) * t
				end
			end
		end
		for inst, goal in goals do
			if inst.Parent then
				inst.Transparency = goal
			end
		end
	end)
end

local ARROW_LAUNCH_NAME = "ArrowLaunchAttachment"
local ARROW_LAUNCH_OFFSET = CFrame.Angles(0, -math.pi / 2, 0) * CFrame.new(2, 0, 0)

local function getLaunchAttachment(projectileAttachment: Attachment): Attachment
	local existing = projectileAttachment:FindFirstChild(ARROW_LAUNCH_NAME)
	if existing and existing:IsA("Attachment") then
		return existing
	end

	local launchAttachment = Instance.new("Attachment")
	launchAttachment.Name = ARROW_LAUNCH_NAME
	launchAttachment.CFrame = ARROW_LAUNCH_OFFSET
	launchAttachment.Parent = projectileAttachment
	return launchAttachment
end

function ShooterArcher.GetLaunchCF(controller): CFrame
	if controller.LaunchAttachment then
		return controller.LaunchAttachment.WorldCFrame
	end
	local attachment = controller.ProjectileAttachment
	if attachment then
		return attachment.WorldCFrame * ARROW_LAUNCH_OFFSET
	end
	return CFrame.new()
end

function ShooterArcher.GetSpawnCF(attachment: Attachment): CFrame
	return attachment.WorldCFrame * ARROW_LAUNCH_OFFSET
end

function ShooterArcher.RefreshParts(controller)
	ShooterArcher.DestroyRestArrow(controller)
	controller.ArrowReloading = false

	controller.ShootPart = controller:FindDirectPart("ShootPart")
	controller.ProjectileAttachment = nil
	controller.LaunchAttachment = nil
	if controller.ShootPart then
		local attachment = controller.ShootPart:FindFirstChild("ProjectileAttachment")
		if attachment and attachment:IsA("Attachment") then
			controller.ProjectileAttachment = attachment
			controller.LaunchAttachment = getLaunchAttachment(attachment)
		end
	end

	ShooterArcher.EnsureRestArrow(controller)
end

function ShooterArcher.DestroyRestArrow(controller)
	if controller.ArrowWeld then
		controller.ArrowWeld:Destroy()
		controller.ArrowWeld = nil
	end
	if controller.RestArrow then
		controller.RestArrow:Destroy()
		controller.RestArrow = nil
	end
end

function ShooterArcher.EnsureRestArrow(controller)
	if controller.ArrowReloading then
		return
	end
	if controller.RestArrow and controller.RestArrow.Parent then
		return
	end

	local attachment = controller.ProjectileAttachment
	if not attachment then
		return
	end

	local hostPart = attachment.Parent
	if not hostPart or not hostPart:IsA("BasePart") then
		return
	end

	local template = getArrowTemplate()
	if not template then
		return
	end

	local arrow = template:Clone()
	arrow.Name = "RestArrow"
	prepArrowRest(arrow)

	local primary = getArrowPrimary(arrow)
	if not primary then
		arrow:Destroy()
		return
	end

	arrow:PivotTo(ShooterArcher.GetLaunchCF(controller))
	arrow.Parent = hostPart

	local weld = Instance.new("WeldConstraint")
	weld.Name = "RestArrowWeld"
	weld.Part0 = hostPart
	weld.Part1 = primary
	weld.Parent = primary

	controller.RestArrow = arrow
	controller.ArrowWeld = weld
	fadeInArrow(arrow)
end

function ShooterArcher.GetCooldown(model: Model): number
	return Shared_Shooters.GetCooldown(model.Name)
end

function ShooterArcher.EmitShot(attachment: Attachment)
	for _, desc in attachment:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			desc:Emit(EMIT_COUNT)
		end
	end
end

function ShooterArcher.Fire(controller, targetPart: BasePart)
	local arrow = controller.RestArrow
	if not arrow or not targetPart or not targetPart.Parent then
		return
	end

	if controller.ArrowWeld then
		controller.ArrowWeld:Destroy()
		controller.ArrowWeld = nil
	end

	controller.RestArrow = nil
	controller.ArrowReloading = true

	if controller.ProjectileAttachment then
		ShooterArcher.EmitShot(controller.ProjectileAttachment)
	end
	ShooterSfx.play(controller.ShootPart, "Bow")

	prepArrowFlying(arrow)
	setArrowVisible(arrow, 0)

	local primary = getArrowPrimary(arrow)
	local pivotOffset = if primary then primary.CFrame:ToObjectSpace(arrow:GetPivot()) else CFrame.new()
	local startPos = ShooterArcher.GetLaunchCF(controller).Position
	local targetPos = targetPart.Position
	local toTarget = targetPos - startPos
	local distance = toTarget.Magnitude
	if distance < 0.05 then
		arrow:Destroy()
		controller.ArrowReloading = false
		ShooterArcher.EnsureRestArrow(controller)
		return
	end

	local moveDir = toTarget.Unit
	local launchRot = (CFrame.lookAt(startPos, startPos + moveDir) * CFrame.Angles(0, -math.pi / 2, 0)).Rotation
	local travelTime = distance / PROJECTILE_SPEED
	local pivot = pivotOffset:Inverse()

	arrow.Parent = workspace
	arrow:PivotTo(CFrame.new(startPos) * launchRot * pivot)

	task.spawn(function()
		ShooterProjectile.RunFlight(controller.Model, targetPart, startPos, PROJECTILE_SPEED, function(pos, _dir)
			arrow:PivotTo(CFrame.new(pos) * launchRot * pivot)
		end)
		if arrow.Parent then
			arrow:Destroy()
		end
	end)

	Debris:AddItem(arrow, travelTime + 1)

	task.delay(RELOAD_TIME, function()
		controller.ArrowReloading = false
		if controller.Model and controller.Model.Parent then
			ShooterArcher.EnsureRestArrow(controller)
		end
	end)
end

function ShooterArcher.TryShoot(
	controller,
	targetPart: BasePart?,
	minPitch: number,
	maxPitch: number,
	clampOnly: boolean
)
	if not targetPart then
		return
	end
	if controller.ArrowReloading or not controller.RestArrow then
		return
	end
	if not controller.ProjectileAttachment then
		return
	end

	local now = os.clock()
	local cooldown = ShooterArcher.GetCooldown(controller.Model)
	if now - (controller.LastShotTime or 0) < cooldown then
		return
	end

	if not controller:IsAimedAtTarget(targetPart.Position, minPitch, maxPitch, clampOnly) then
		return
	end

	controller.LastShotTime = now
	ShooterArcher.Fire(controller, targetPart)
end

return ShooterArcher
