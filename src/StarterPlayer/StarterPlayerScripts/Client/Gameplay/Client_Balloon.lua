--[[
	Client_Balloon — local-player polish on server-replicated balloon rigs.
	Spin damp + HRP hub sync (torso-equivalent position); rig creation and network ownership live on server.
]]

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BalloonRig = require(ReplicatedStorage.Modules.Gameplay.BalloonRig)
local BalloonInvisibleCollision = require(ReplicatedStorage.Modules.Gameplay.BalloonInvisibleCollision)
local Config = require(ReplicatedStorage.Modules.ItemConfigs.BalloonConfig)

local BalloonFloat = require(ReplicatedStorage.Modules.Gameplay.BalloonFloat)

local Module = {}

local LocalPlayer = Players.LocalPlayer
local SIG_ATTR = Config.SigAttribute
local BALLOON_COLLISION_GROUP = Config.BalloonCollisionGroup
local PLAYER_COLLISION_GROUP = Config.PlayerCollisionGroup
local RS = ReplicatedStorage

local spinDampAccum = 0
local adoptedRig: any = nil
local sigConn: RBXScriptConnection? = nil
local balloonsConn: RBXScriptConnection? = nil

local function cfgFlag(key: string): boolean
	local attr = RS:GetAttribute(key)
	if attr ~= nil then
		return attr == true
	end
	return Config.flag(key)
end

local function cfgNumber(key: string, fallback: number): number
	local attr = RS:GetAttribute(key)
	if type(attr) == "number" and attr == attr then
		return attr
	end
	return Config.number(key, fallback)
end

local function pushSpinDampAttributes()
	RS:SetAttribute("BalloonSpinDampEnabled", Config.flag("BalloonSpinDampEnabled"))
	RS:SetAttribute("BalloonSpinDampPerFrame", Config.flag("BalloonSpinDampPerFrame"))
	RS:SetAttribute("BalloonSpinDampOnlyWhenIdle", Config.flag("BalloonSpinDampOnlyWhenIdle"))
	RS:SetAttribute("BalloonSpinDampMoveSpeedThreshold", Config.number("BalloonSpinDampMoveSpeedThreshold", 1.5))
	RS:SetAttribute("BalloonSpinDampPerFrameFactor", Config.number("BalloonSpinDampPerFrameFactor", 0.92))
	RS:SetAttribute("BalloonSpinDampInterval", Config.number("BalloonSpinDampInterval", 0.12))
	RS:SetAttribute("BalloonSpinDampAngularFactor", Config.number("BalloonSpinDampAngularFactor", 0.7))
	RS:SetAttribute("BalloonSpinDampStopRadPerSec", Config.number("BalloonSpinDampStopRadPerSec", 0.55))
	RS:SetAttribute("BalloonZeroYawSpin", Config.flag("BalloonZeroYawSpin"))
	RS:SetAttribute("BalloonLockYawRotation", Config.flag("BalloonLockYawRotation"))
end

local function clearAdoptedRig()
	if adoptedRig then
		adoptedRig:Destroy()
		adoptedRig = nil
	end
end

local function getLocalAdoptedRig(): any
	local character = LocalPlayer.Character
	if not character then
		clearAdoptedRig()
		return nil
	end

	if adoptedRig and adoptedRig._character == character then
		adoptedRig:_refreshAdoptedRefs()
		return adoptedRig
	end

	clearAdoptedRig()

	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if not folder or #folder:GetChildren() == 0 then
		return nil
	end

	adoptedRig = BalloonRig.adoptFromCharacter(character, LocalPlayer)
	return adoptedRig
end

local function disconnectCharacterSignals()
	if sigConn then
		sigConn:Disconnect()
		sigConn = nil
	end
	if balloonsConn then
		balloonsConn:Disconnect()
		balloonsConn = nil
	end
end

local function bindLocalCharacter(character: Model)
	disconnectCharacterSignals()
	clearAdoptedRig()
	BalloonRig._clearLegacyTorsoHubParts(character)
	BalloonRig._clearOrphanKnot(character)

	local function refreshAdopted()
		getLocalAdoptedRig()
	end

	sigConn = character:GetAttributeChangedSignal(SIG_ATTR):Connect(refreshAdopted)

	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if folder then
		balloonsConn = folder.ChildAdded:Connect(refreshAdopted)
	end

	character.ChildAdded:Connect(function(child)
		if child.Name == BalloonRig.ATTACHED_BALLOONS_FOLDER and child:IsA("Folder") then
			-- direct folder on character
			if balloonsConn then
				balloonsConn:Disconnect()
			end
			balloonsConn = child.ChildAdded:Connect(refreshAdopted)
			refreshAdopted()
		end
	end)

	refreshAdopted()
end

--// Spin settle ----------------------------------------------------------------

local function zeroYawAngularVelocity(part: BasePart)
	local av = part.AssemblyAngularVelocity
	if av.Y ~= 0 then
		part.AssemblyAngularVelocity = Vector3.new(av.X, 0, av.Z)
	end
end

local function dampBalloonModelSpin(balloonModel: Model, factor: number, stopRadPerSec: number)
	for _, d in balloonModel:GetDescendants() do
		if d:IsA("BasePart") then
			local av = d.AssemblyAngularVelocity
			local xz = Vector3.new(av.X, 0, av.Z)
			local mag = xz.Magnitude
			if mag < stopRadPerSec then
				d.AssemblyAngularVelocity = Vector3.zero
			else
				d.AssemblyAngularVelocity = Vector3.new(xz.X * factor, 0, xz.Z * factor)
			end
		end
	end
end

local function lockBalloonModelYaw(balloonModel: Model)
	local yaw = balloonModel:GetAttribute("BalloonLockedYaw")
	if type(yaw) ~= "number" then
		return
	end
	local pivot = balloonModel:GetPivot()
	local pitch, currentYaw, roll = pivot:ToEulerAnglesYXZ()
	if math.abs(currentYaw - yaw) < 0.02 then
		return
	end
	balloonModel:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(pitch, yaw, roll))
end

local function bleedLocalBalloonYawSpin(hardLock: boolean)
	local rig = getLocalAdoptedRig()
	local folder = rig and rig._balloonsFolder
	if not folder then
		return
	end

	for _, child in folder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		if hardLock then
			lockBalloonModelYaw(child)
		end
		for _, d in child:GetDescendants() do
			if d:IsA("BasePart") then
				zeroYawAngularVelocity(d)
			end
		end
	end
end

local function isCharacterMoving(character: Model?): boolean
	if not character or not character.Parent then
		return false
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		local vel = hrp.AssemblyLinearVelocity
		local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		if hSpeed >= cfgNumber("BalloonSpinDampMoveSpeedThreshold", 1.25) then
			return true
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MoveDirection.Magnitude > 0.05 then
		return true
	end

	return false
end

local function dampLocalBalloonSpin(factor: number, stopRadPerSec: number)
	local rig = getLocalAdoptedRig()
	local folder = rig and rig._balloonsFolder
	if not folder then
		return
	end

	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			dampBalloonModelSpin(child, factor, stopRadPerSec)
		end
	end
end

local function isCharacterFloating(character: Model?): boolean
	if not character then
		return false
	end
	return character:GetAttribute(BalloonFloat.HOLD_ATTR) == true
		or character:GetAttribute(BalloonFloat.ACTIVE_ATTR) == true
end

local function tickBalloonYawLock()
	local character = LocalPlayer.Character
	if isCharacterFloating(character) then
		return
	end
	local zeroYaw = cfgFlag("BalloonZeroYawSpin")
	local hardLock = cfgFlag("BalloonLockYawRotation")
	if not zeroYaw and not hardLock then
		return
	end
	bleedLocalBalloonYawSpin(hardLock)
end

local function tickSpinDamp(dt: number)
	if not cfgFlag("BalloonSpinDampEnabled") then
		return
	end

	local character = LocalPlayer.Character
	if not character or isCharacterFloating(character) then
		return
	end

	local onlyWhenIdle = cfgFlag("BalloonSpinDampOnlyWhenIdle")
	if onlyWhenIdle and isCharacterMoving(character) then
		spinDampAccum = 0
		return
	end

	local stopRadPerSec = math.max(0, cfgNumber("BalloonSpinDampStopRadPerSec", 0.55))

	if cfgFlag("BalloonSpinDampPerFrame") then
		local factor = math.clamp(cfgNumber("BalloonSpinDampPerFrameFactor", 0.88), 0, 1)
		dampLocalBalloonSpin(factor, stopRadPerSec)
		return
	end

	local interval = cfgNumber("BalloonSpinDampInterval", 0.05)
	if interval <= 0 then
		return
	end

	spinDampAccum += dt
	if spinDampAccum < interval then
		return
	end
	spinDampAccum -= interval

	local factor = math.clamp(cfgNumber("BalloonSpinDampAngularFactor", 0.7), 0, 1)
	dampLocalBalloonSpin(factor, stopRadPerSec)
end

--// Init -----------------------------------------------------------------------

local function setupBalloonPhysics()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(BALLOON_COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(PLAYER_COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(PLAYER_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(PLAYER_COLLISION_GROUP, "Default", true)
		PhysicsService:CollisionGroupSetCollidable(BALLOON_COLLISION_GROUP, BALLOON_COLLISION_GROUP, true)
		PhysicsService:CollisionGroupSetCollidable(
			BALLOON_COLLISION_GROUP,
			"Default",
			Config.BalloonCollideWithDefaultWorld == true
		)
		PhysicsService:CollisionGroupSetCollidable(BALLOON_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
	end)
	BalloonInvisibleCollision.registerPhysicsGroups()
	BalloonInvisibleCollision.startWatching(Workspace)

	local legacy = Workspace:FindFirstChild(Config.LegacyRigRootName)
	if legacy then
		pcall(function()
			legacy:Destroy()
		end)
	end

	local localRoot = Workspace:FindFirstChild(Config.LocalRigRootName)
	if localRoot then
		pcall(function()
			localRoot:Destroy()
		end)
	end
end

function Module:Init()
	pushSpinDampAttributes()
	setupBalloonPhysics()

	LocalPlayer.CharacterAdded:Connect(function(character)
		task.defer(function()
			if LocalPlayer.Character == character then
				bindLocalCharacter(character)
			end
		end)
	end)

	LocalPlayer.CharacterRemoving:Connect(function()
		disconnectCharacterSignals()
		clearAdoptedRig()
	end)

	if LocalPlayer.Character then
		task.defer(function()
			if LocalPlayer.Character then
				bindLocalCharacter(LocalPlayer.Character)
			end
		end)
	end

	RunService.PreSimulation:Connect(function()
		tickBalloonYawLock()
	end)

	RunService.PostSimulation:Connect(function(dt)
		tickSpinDamp(dt)
	end)
end

return Module
