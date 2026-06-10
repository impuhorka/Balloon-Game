--// BalloonFloat — hold jump: factor = ReferenceCount / balloonCount on BOTH force and density.
--// Total lift force = count × (140 × factor) = ReferenceCount × 140 always (e.g. 7000 at ref 50).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Parent.ItemConfigs.BalloonConfig)
local BalloonRigKit = require(script.Parent.BalloonRigKit)
local Shared_Balloons = require(script.Parent.Parent.ItemConfigs.Shared_Balloons)
local Shared_PropelerConfig = require(script.Parent.Parent.Settings.Shared_PropelerConfig)
local Shared_BoosterConfig = require(script.Parent.Parent.Settings.Shared_BoosterConfig)

local Workspace = workspace

local BalloonFloat = {}

BalloonFloat.HOLD_ATTR = "BalloonFloatHold"
BalloonFloat.ACTIVE_ATTR = "BalloonFloating"
BalloonFloat.ATTACHED_BALLOONS_FOLDER = BalloonRigKit.ATTACHED_BALLOONS_FOLDER
BalloonFloat.MASS_ATTR = "BalloonFloatPlayerMass"
BalloonFloat.MASS_SCALE_ATTR = "BalloonFloatMassScale"
BalloonFloat.RIG_MASS_ATTR = "BalloonFloatRigMass"
BalloonFloat.MASS_READY_ATTR = "BalloonFloatMassReady"
BalloonFloat._massProbe = setmetatable({} :: { [Model]: { last: number?, stable: number?, streak: number } }, { __mode = "k" })

local LIFT_FORCE_NAME = Config.BalloonLiftForceName or "BalloonLift"
local KNOT_PART_NAME = "BalloonStringKnot"
local TORSO_STRAP_ROPE_PREFIX = "BalloonTorsoStrap"
local HUB_ATT_NAME = "BalloonTorsoStringAnchor"
local FOLLOW_PART_NAME = Config.BalloonFloatFollowPartName or "BalloonFloatFollow"
local ANCHOR_FOLDER_NAME = Config.BalloonFloatAnchorFolderName or "BalloonFloatAnchor"
local LEGACY_PROXY_PART_NAME = "BalloonFloatProxy"
local FOLLOW_HOST_WELD_NAME = "BalloonFloatHostWeld"

type RigIsolationState = {
	savedHubLinks: { { constraint: Constraint, origAtt: Attachment } },
}

local _rigIsolationState = setmetatable({} :: { [Model]: RigIsolationState }, { __mode = "k" })
local BalloonRigModule: any = nil
local function getBalloonRig()
	if not BalloonRigModule then
		BalloonRigModule = require(script.Parent.BalloonRig)
	end
	return BalloonRigModule
end

function BalloonFloat.getAnchorFolder(character: Model?): Folder?
	if not character then
		return nil
	end
	local anchor = character:FindFirstChild(ANCHOR_FOLDER_NAME)
	if anchor and anchor:IsA("Folder") then
		return anchor
	end
	return nil
end

function BalloonFloat.resolveBalloonsFolder(character: Model?): Folder?
	if not character then
		return nil
	end
	local direct = character:FindFirstChild(BalloonFloat.ATTACHED_BALLOONS_FOLDER)
	if direct and direct:IsA("Folder") then
		return direct
	end
	local anchor = BalloonFloat.getAnchorFolder(character)
	if anchor then
		local nested = anchor:FindFirstChild(BalloonFloat.ATTACHED_BALLOONS_FOLDER)
		if nested and nested:IsA("Folder") then
			return nested
		end
	end
	return nil
end

function BalloonFloat.resolveCharacterFromBalloonsFolder(folder: Instance?): Model?
	if not folder or not folder:IsA("Folder") then
		return nil
	end
	local parent = folder.Parent
	if parent and parent:IsA("Folder") and parent.Name == ANCHOR_FOLDER_NAME then
		local character = parent.Parent
		if character and character:IsA("Model") then
			return character
		end
	elseif parent and parent:IsA("Model") then
		return parent
	end
	return nil
end

local function isBalloonRigPart(part: BasePart, character: Model): boolean
	if part.Name == KNOT_PART_NAME then
		return true
	end

	local current: Instance? = part
	while current and current ~= character do
		if current.Name == BalloonFloat.ATTACHED_BALLOONS_FOLDER then
			return true
		end
		current = current.Parent
	end

	return false
end

local function isPlayerBodyPart(part: BasePart, character: Model): boolean
	if part.Massless or isBalloonRigPart(part, character) then
		return false
	end

	return part:IsDescendantOf(character)
end

local function getBalloonRigSimMassInAssembly(hrp: BasePart, character: Model): number
	local assemblyRoot = hrp.AssemblyRootPart or hrp
	local total = 0
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and not desc.Massless and isBalloonRigPart(desc, character) then
			if desc.AssemblyRootPart == assemblyRoot then
				total += desc:GetMass()
			end
		end
	end
	return total
end

local function getPlayerPartMassSum(character: Model): number
	local partSum = 0
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and isPlayerBodyPart(desc, character) then
			partSum += desc:GetMass()
		end
	end
	return partSum
end

local function getCatalogRigMass(character: Model): number
	local total = 0
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and not desc.Massless and isBalloonRigPart(desc, character) then
			total += desc:GetMass()
		end
	end
	return total
end

function BalloonFloat.hasMinimumBodyLoaded(character: Model?): boolean
	if not character then
		return false
	end
	if not character:FindFirstChild("HumanoidRootPart") then
		return false
	end
	if not character:FindFirstChildOfClass("Humanoid") then
		return false
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso then
		return false
	end
	return character:FindFirstChild("Head") ~= nil
end

function BalloonFloat.isRigSettling(character: Model?): boolean
	return character ~= nil and character:GetAttribute(BalloonRigKit.SETTLING_ATTR) == true
end

function BalloonFloat.isFloatBlocked(character: Model?): boolean
	if not character then
		return true
	end
	if not BalloonRigKit.isPlotSpawnReady(nil, character) then
		return true
	end
	if BalloonFloat.isRigSettling(character) then
		return true
	end
	if not BalloonFloat.hasMinimumBodyLoaded(character) then
		return true
	end
	if character:GetAttribute(BalloonFloat.MASS_READY_ATTR) ~= true then
		local cached = character:GetAttribute(BalloonFloat.MASS_ATTR)
		if type(cached) == "number" and cached > 0 then
			return false
		end
		return true
	end
	return false
end

function BalloonFloat.isCharacterAirborne(humanoid: Humanoid?, root: BasePart?): boolean
	if not humanoid or not root then
		return false
	end

	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
		return true
	end

	if root.AssemblyLinearVelocity.Y < Config.number("BalloonFloatFallVelocityThreshold", -2) then
		return true
	end

	return humanoid.FloorMaterial == Enum.Material.Air
end

function BalloonFloat.isFloatAirborne(
	humanoid: Humanoid?,
	root: BasePart?,
	wantHold: boolean,
	_inFloatAirSession: boolean,
	currentLiftBlend: number
): boolean
	if BalloonFloat.isCharacterAirborne(humanoid, root) then
		return true
	end

	if wantHold then
		return true
	end

	-- Release fade only counts as airborne while still off the floor.
	if currentLiftBlend > 0.05 and humanoid and humanoid.FloorMaterial == Enum.Material.Air then
		return true
	end

	return false
end

function BalloonFloat.tryGroundPeelForFloat(humanoid: Humanoid?, root: BasePart?, wantHold: boolean)
	if not wantHold or not humanoid or not root then
		return
	end

	if humanoid.FloorMaterial == Enum.Material.Air then
		return
	end

	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
		return
	end

	if Config.flag("BalloonFloatAutoJumpOnHold") then
		humanoid.Jump = true
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end)
	end

	if not Config.flag("BalloonFloatGroundPeelEnabled") then
		return
	end

	local vel = root.AssemblyLinearVelocity
	local peelVy = Config.number("BalloonFloatGroundPeelVy", 8)
	local minVy = Config.number("BalloonFloatGroundPeelMinVy", 2.5)
	if vel.Y < minVy then
		root.AssemblyLinearVelocity = Vector3.new(vel.X, math.max(vel.Y, peelVy), vel.Z)
	end
end

function BalloonFloat.easeOutPow(t: number, power: number): number
	return 1 - (1 - math.clamp(t, 0, 1)) ^ power
end

type LiftBlendState = {
	liftBlend: number,
	holdRampElapsed: number,
	releasing: boolean,
	releaseFadeElapsed: number,
	releaseStartBlend: number,
	floatAirSession: boolean,
	prevHold: boolean,
}

function BalloonFloat.newLiftBlendState(): LiftBlendState
	return {
		liftBlend = 0,
		holdRampElapsed = 0,
		releasing = false,
		releaseFadeElapsed = 0,
		releaseStartBlend = 0,
		floatAirSession = false,
		prevHold = false,
	}
end

function BalloonFloat.tickLiftBlendState(
	st: LiftBlendState,
	dt: number,
	opts: {
		wantHold: boolean,
		airborne: boolean,
		settling: boolean,
		humanoid: Humanoid?,
		root: BasePart?,
		resetFloatAirSessionOnLand: boolean?,
	}
): number
	local wantHold = opts.wantHold
	local airborne = opts.airborne
	local settling = opts.settling
	local prevHold = st.prevHold

	if prevHold and not wantHold then
		st.holdRampElapsed = 0
		if airborne and st.liftBlend > 0.01 then
			st.releasing = true
			st.releaseFadeElapsed = 0
			st.releaseStartBlend = st.liftBlend
		else
			st.releasing = false
			st.liftBlend = 0
		end
	elseif wantHold then
		st.releasing = false
		if settling then
			st.liftBlend = 0
		else
			st.floatAirSession = true
			if not prevHold then
				st.holdRampElapsed = 0
			end
			local peelCharacter = if opts.root then opts.root.Parent else nil
			if not (peelCharacter and peelCharacter:IsA("Model") and BalloonFloat.isFloatRigIsolated(peelCharacter)) then
				BalloonFloat.tryGroundPeelForFloat(opts.humanoid, opts.root, wantHold)
			end
			st.holdRampElapsed += dt
			local rampSec = math.max(0.12, Config.number("BalloonFloatHoldRampSeconds", 0.25))
			local startBlend = Config.number("BalloonFloatHoldRampStartBlend", 0.15)
			local t = math.clamp(st.holdRampElapsed / rampSec, 0, 1)
			st.liftBlend = math.min(1, startBlend + (1 - startBlend) * t)
		end
	elseif st.releasing and airborne and not settling then
		st.releaseFadeElapsed += dt
		local fadeSec = Config.number("BalloonFloatReleaseLiftBlendSeconds", 0.55)
		if fadeSec <= 0 then
			st.liftBlend = 0
			st.releasing = false
		else
			local t = math.clamp(st.releaseFadeElapsed / fadeSec, 0, 1)
			local power = Config.number("BalloonFloatReleaseEasePower", 1.4)
			st.liftBlend = st.releaseStartBlend * (1 - BalloonFloat.easeOutPow(t, power))
			if t >= 1 then
				st.liftBlend = 0
				st.releasing = false
			end
		end
	elseif st.releasing then
		st.releasing = false
		st.liftBlend = 0
	elseif not airborne then
		st.liftBlend = 0
		st.holdRampElapsed = 0
		st.releasing = false
		if opts.resetFloatAirSessionOnLand then
			st.floatAirSession = false
		end
	end

	if airborne and not st.floatAirSession then
		st.floatAirSession = true
	end

	if opts.humanoid and opts.humanoid.FloorMaterial ~= Enum.Material.Air and not wantHold then
		st.floatAirSession = false
	end

	st.prevHold = wantHold

	if settling then
		return 0
	end
	return st.liftBlend
end

local function clearMassProbe(character: Model)
	BalloonFloat._massProbe[character] = nil
end

local function updateMassReady(character: Model, sampleMass: number): number
	local minReady = Config.number("BalloonFloatMinBodyMassReady", 6)
	if sampleMass < minReady then
		character:SetAttribute(BalloonFloat.MASS_READY_ATTR, false)
		return 0
	end

	local state = BalloonFloat._massProbe[character]
	if not state then
		state = { last = nil, stable = nil, streak = 0 }
		BalloonFloat._massProbe[character] = state
	end

	local tol = Config.number("BalloonFloatMassStableTolerance", 0.08)
	if state.last and math.abs(sampleMass - state.last) / math.max(state.last, 0.01) <= tol then
		state.streak += 1
	else
		state.streak = 1
	end
	state.last = sampleMass

	local need = math.max(1, math.floor(Config.number("BalloonFloatMassStableFrames", 3)))
	if state.streak >= need then
		state.stable = sampleMass
		character:SetAttribute(BalloonFloat.MASS_READY_ATTR, true)
		return sampleMass
	end

	character:SetAttribute(BalloonFloat.MASS_READY_ATTR, false)
	return state.stable or 0
end

function BalloonFloat.clearMassState(character: Model?)
	if not character then
		return
	end
	clearMassProbe(character)
	character:SetAttribute(BalloonFloat.MASS_READY_ATTR, false)
	character:SetAttribute(BalloonFloat.MASS_ATTR, nil)
	character:SetAttribute(BalloonFloat.RIG_MASS_ATTR, nil)
	character:SetAttribute(BalloonFloat.MASS_SCALE_ATTR, nil)
end

--[[ Body mass for lift: HRP assembly (physics truth) minus balloon rig in that assembly, reconciled with part sum. ]]
function BalloonFloat.getFloatLiftMass(character: Model?): number
	if not character then
		return 0
	end

	local partMass = getPlayerPartMassSum(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return partMass
	end

	local rigInAssembly = getBalloonRigSimMassInAssembly(hrp, character)
	local catalogRigMass = getCatalogRigMass(character)

	local assemblyBody = math.max(0, hrp.AssemblyMass - rigInAssembly)
	if assemblyBody <= 0.01 then
		return partMass
	end

	if partMass <= 0.01 then
		return assemblyBody
	end

	local minReady = Config.number("BalloonFloatMinBodyMassReady", 6)
	if catalogRigMass > rigInAssembly + 0.01 and partMass >= minReady and assemblyBody > partMass * 1.12 then
		return partMass
	end
	if assemblyBody < partMass * 0.55 and partMass >= minReady then
		return partMass
	end
	if assemblyBody > partMass * 1.65 and partMass >= minReady then
		return partMass
	end

	local tolerance = Config.number("BalloonFloatMassPartSumTolerance", 0.35)
	local relDelta = math.abs(assemblyBody - partMass) / partMass
	if relDelta <= tolerance then
		return assemblyBody
	end

	return math.max(assemblyBody, partMass)
end

function BalloonFloat.getBalloonRigMass(character: Model?): number
	if not character then
		return 0
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return getBalloonRigSimMassInAssembly(hrp, character)
	end

	local total = 0
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and not desc.Massless and isBalloonRigPart(desc, character) then
			total += desc:GetMass()
		end
	end
	return total
end

local function smoothstep01(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function setBalloonMassless(balloonModel: Model, massless: boolean)
	for _, d in balloonModel:GetDescendants() do
		if d:IsA("BasePart") then
			d.Massless = massless
		end
	end
end

local function setBalloonCanCollide(balloonModel: Model, canCollide: boolean)
	for _, d in balloonModel:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = canCollide
		end
	end
end

function BalloonFloat.getHoldLiftWeightRatio(): number
	local configured = Config.number("BalloonFloatHoldLiftWeightRatio", 0)
	local ratio
	if configured > 0 then
		ratio = configured
	else
		local refMass = Config.number("BalloonFloatReferencePlayerMass", 28.874)
		local refCount = Config.number("BalloonFloatReferenceBalloonCount", 50)
		local perBalloonForce = Config.number("BalloonFloatHoldLiftPerBalloon", 140)
		local refLift = refCount * perBalloonForce
		local refWeight = math.max(0.001, refMass * Workspace.Gravity)
		ratio = refLift / refWeight
	end

	return ratio * Config.number("BalloonFloatHoldLiftStrength", 1)
end

function BalloonFloat.clampTotalLift(totalLift: number, character: Model?): number
	if not Config.flag("BalloonFloatClampLiftToWeight") then
		return totalLift
	end

	local mass = BalloonFloat.getFloatLiftMass(character)
	if mass <= 0 then
		return totalLift
	end

	local weight = mass * Workspace.Gravity
	local minLift = weight * BalloonFloat.getHoldLiftWeightRatio()
	-- Floor at body-weight lift; allow higher raw when massScale/count already exceeds it.
	return math.max(totalLift, minLift)
end

function BalloonFloat.bleedReleaseUpwardVelocity(root: BasePart?, liftBlend: number, dt: number)
	if not root or liftBlend <= 0.01 or dt <= 0 then
		return
	end

	local vel = root.AssemblyLinearVelocity
	if vel.Y <= 0 then
		return
	end

	local maxVy = Config.number("BalloonFloatReleaseMaxVy", 1.5)
	local rate = Config.number("BalloonFloatReleaseVyBleedRate", 18)
	local targetVy = math.min(vel.Y, maxVy)
	local newVy = vel.Y + (targetVy - vel.Y) * math.min(1, rate * dt)
	root.AssemblyLinearVelocity = Vector3.new(vel.X, newVy, vel.Z)
end

function BalloonFloat.computeStabilizedHrpLiftForce(
	character: Model?,
	liftBlend: number,
	opts: { fallCatch: boolean?, wantHold: boolean?, liftMult: number?, manualHold: boolean?, propBlend: number? }?
): number
	if not character or liftBlend <= 0.01 then
		return 0
	end

	local mass = BalloonFloat.getFloatLiftMass(character)
	if mass <= 0 then
		mass = Config.number("BalloonFloatReferencePlayerMass", 28.874)
	end

	local strength = math.clamp(liftBlend, 0, 1)
	local liftMult = math.max(0, opts and opts.liftMult or 1)
	local propBlend = math.clamp(opts and opts.propBlend or 0, 0, 1)
	local manualHold = opts and opts.manualHold == true
	local weight = mass * Workspace.Gravity
	local fallCatch = opts and opts.fallCatch == true
	local wantHold = opts == nil or opts.wantHold ~= false

	if not wantHold then
		local ratio = Config.number("BalloonFloatReleaseHoverWeightRatio", 0.88)
		return weight * ratio * strength * liftMult
	end

	if not Config.flag("BalloonFloatVelocityStabilizeEnabled") then
		local force = weight * BalloonFloat.getHoldLiftWeightRatio() * strength * liftMult
		if fallCatch then
			force *= Config.number("BalloonFloatFallCatchForceBoost", 1.42)
		end
		return force
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local vy = 0
	if hrp and hrp:IsA("BasePart") then
		vy = hrp.AssemblyLinearVelocity.Y
	end

	local targetVy = Config.number("BalloonFloatTargetRiseSpeed", 30) * liftMult
	local response = Config.number("BalloonFloatRiseResponse", 11)
	local maxAccel = Config.number("BalloonFloatMaxRiseAccel", 48) * liftMult
	local overspeedBuffer = (if fallCatch
		then Config.number("BalloonFloatRecoveryOverspeedBuffer", 16)
		else Config.number("BalloonFloatOverspeedBuffer", 8)) * math.sqrt(liftMult)
	if propBlend > 0 then
		local zoneVyScale = Shared_PropelerConfig.ZoneTargetVyBonusScale or 0.62
		local zoneVyBonus = Config.number("BalloonFloatTargetRiseSpeed", 30) * propBlend * zoneVyScale
		targetVy += zoneVyBonus * 0.5
		overspeedBuffer += zoneVyBonus
		maxAccel += Config.number("BalloonFloatMaxRiseAccel", 48) * propBlend * 0.55
		if manualHold then
			targetVy += zoneVyBonus * 0.45
			maxAccel += Config.number("BalloonFloatMaxRiseAccel", 48) * propBlend * 0.35
			overspeedBuffer += zoneVyBonus * 0.4
		end
	end
	local minRatio = Config.number("BalloonFloatMinHoldLiftWeightRatio", 1.18)
	local hoverRatio = Config.number("BalloonFloatHoverLiftWeightRatio", 1.24)
		+ Config.number("BalloonFloatRigDragWeightRatio", 0.06)

	local vyError = targetVy - vy
	if math.abs(vyError) < 5 then
		response *= Config.number("BalloonFloatGlideResponseScale", 0.55)
	end

	local baseForce = weight * hoverRatio * liftMult
	local accelCmd = math.clamp(response * vyError, -maxAccel, maxAccel)
	local force = (baseForce + mass * accelCmd) * strength

	if fallCatch and vy < 0 then
		local fallCatchVy = Config.number("BalloonFloatFallCatchVy", -5)
		local fallMult = math.clamp(-vy / math.max(1, math.abs(fallCatchVy)), 1, 2.8)
		local extraAccel = Config.number("BalloonFloatFallCatchExtraAccel", 48) * liftMult
		force += mass * extraAccel * fallMult * strength
		force *= Config.number("BalloonFloatFallCatchForceBoost", 1.42)
	end

	local minStrength = Config.number("BalloonFloatHoldLiftMinStrength", 0.9)
	if vy < targetVy and wantHold then
		force = math.max(force, weight * minRatio * math.max(strength, minStrength) * liftMult)
	elseif vy > targetVy + overspeedBuffer then
		local recoveryCeiling = targetVy + Config.number("BalloonFloatRecoveryOverspeedBuffer", 16)
		if not fallCatch or vy > recoveryCeiling then
			force = math.min(force, baseForce * strength)
		end
	end

	return force
end

function BalloonFloat.computePropelerLiftMult(propBlend: number, manualHold: boolean): number
	propBlend = math.clamp(propBlend, 0, 1)
	local manual = Shared_PropelerConfig.ManualFloatMult or 1
	local zone = Shared_PropelerConfig.ZoneAutoFloatMult or 2.08
	local comboMult = Shared_PropelerConfig.ZoneManualHoldComboMult or 1.42

	if propBlend <= 0 then
		return manual
	end

	local curvePower = Shared_PropelerConfig.ZoneLiftCurvePower or 0.72
	local t = if curvePower ~= 1 then propBlend ^ curvePower else propBlend
	local zoneMult = manual + (zone - manual) * t
	if manualHold then
		return zoneMult * comboMult
	end
	return zoneMult
end

function BalloonFloat.dampBalloonPopSwing(character: Model?, factor: number?)
	if not character then
		return
	end
	factor = math.clamp(factor or Config.number("BalloonPopSwingDampFactor", 0.68), 0, 1)
	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if not folder then
		return
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					d.AssemblyLinearVelocity *= factor
					d.AssemblyAngularVelocity *= factor
				end
			end
		end
	end
	local knot = character:FindFirstChild(KNOT_PART_NAME)
	if not knot or not knot:IsA("BasePart") then
		local anchor = BalloonFloat.getAnchorFolder(character)
		if anchor then
			knot = anchor:FindFirstChild(KNOT_PART_NAME)
		end
	end
	if knot and knot:IsA("BasePart") then
		knot.AssemblyLinearVelocity *= factor
		knot.AssemblyAngularVelocity *= factor
	end
end

function BalloonFloat.onBalloonPopped(character: Model?)
	if not character then
		return
	end
	BalloonFloat.dampBalloonPopSwing(character)
	if _rigIsolationState[character] then
		BalloonFloat.resyncFollowRigBalloonTethers(character, false)
		return
	end
	local BalloonRig = require(script.Parent.BalloonRig)
	local rig = BalloonRig.adoptFromCharacter(character)
	rig:_refreshAdoptedRefs()
	rig:SyncRopeVisibility()
end

function BalloonFloat.bleedFloatRiseToCap(root: BasePart, cap: number, dt: number)
	if cap <= 0 then
		return
	end
	local vel = root.AssemblyLinearVelocity
	if vel.Y <= cap then
		return
	end
	local rate = Shared_PropelerConfig.ZoneExitVyBleedRate or 11
	local newVy = vel.Y + (cap - vel.Y) * math.min(1, rate * dt)
	root.AssemblyLinearVelocity = Vector3.new(vel.X, newVy, vel.Z)
end

function BalloonFloat.getFloatMaxRiseSpeed(liftBlend: number, liftMult: number?): number
	liftMult = if liftMult ~= nil then math.max(0, liftMult) else 1
	if liftMult <= 0 then
		return 0
	end
	liftBlend = math.clamp(liftBlend, 0, 1)
	if liftBlend <= 0.01 then
		return 0
	end

	local cap = Config.number("BalloonFloatMaxRiseSpeed", 0)
	if cap <= 0 then
		cap = Config.number("BalloonFloatTargetRiseSpeed", 30)
	end
	local floorMult = Config.number("BalloonFloatMinRiseSpeedMult", 0.55)
	local speedMult = floorMult + (1 - floorMult) * liftBlend
	return cap * speedMult * liftMult
end

function BalloonFloat.getCircleBoostRiseCapBonus(character: Model?): number
	if not character then
		return 0
	end
	local blend = tonumber(character:GetAttribute("CircleBoostBlend")) or 0
	if blend <= 0 then
		return 0
	end
	local tier = character:GetAttribute("CircleBoostTier")
	local tierDef = if tier == "VIP" then Shared_BoosterConfig.VIP else Shared_BoosterConfig.Normal
	return (tierDef and tierDef.RiseCapBonus or 42) * blend
end

function BalloonFloat.computeFloatRiseCap(character: Model?, liftBlend: number, manualHold: boolean): number
	local propBlend = 0
	if character then
		propBlend = tonumber(character:GetAttribute("PropelerBoostBlend")) or 0
	end
	local liftMult = BalloonFloat.computePropelerLiftMult(propBlend, manualHold)
	return BalloonFloat.getFloatMaxRiseSpeed(liftBlend, liftMult)
		+ BalloonFloat.getCircleBoostRiseCapBonus(character)
end

function BalloonFloat.enforceFloatRiseSpeedCap(root: BasePart?, liftBlend: number)
	if not root then
		return
	end

	local maxVy = BalloonFloat.getFloatMaxRiseSpeed(liftBlend)
	if maxVy <= 0 then
		return
	end

	local vel = root.AssemblyLinearVelocity
	if vel.Y > maxVy then
		root.AssemblyLinearVelocity = Vector3.new(vel.X, maxVy, vel.Z)
	end
end

function BalloonFloat.smoothFloatRiseVelocity(
	root: BasePart?,
	liftBlend: number,
	dt: number,
	character: Model?,
	wantHold: boolean?
)
	if not root or liftBlend <= 0.01 or dt <= 0 then
		return
	end

	local targetVy = if character
		then BalloonFloat.computeFloatRiseCap(character, liftBlend, wantHold == true)
		else BalloonFloat.getFloatMaxRiseSpeed(liftBlend)
	if targetVy <= 0 then
		return
	end

	local vel = root.AssemblyLinearVelocity
	local rate = Config.number("BalloonFloatStartRiseLerpRate", 14)
	local newVy = vel.Y + (targetVy - vel.Y) * math.min(1, rate * dt)
	if newVy > targetVy then
		newVy = targetVy
	end
	root.AssemblyLinearVelocity = Vector3.new(vel.X, newVy, vel.Z)
end

function BalloonFloat.applyParachuteFall(
	character: Model?,
	root: BasePart?,
	dt: number,
	liftBlend: number,
	balloonCount: number
)
	if not character or not root or not Config.flag("BalloonFloatParachuteEnabled") then
		return
	end

	if liftBlend > Config.number("BalloonFloatParachuteLiftBlend", 0.35) then
		return
	end

	local vel = root.AssemblyLinearVelocity
	local vy = vel.Y
	local terminal = Config.number("BalloonFloatParachuteTerminalVy", -24)
	if vy >= terminal then
		return
	end

	local countFactor = math.clamp(balloonCount / 12, 0.45, 1.35)
	local targetVy = terminal * countFactor
	local drag = Config.number("BalloonFloatParachuteDrag", 28)
	local t = math.clamp(1 - liftBlend / math.max(0.01, Config.number("BalloonFloatParachuteLiftBlend", 0.35)), 0, 1)
	local newVy = vy + (targetVy - vy) * math.min(1, drag * t * dt)
	root.AssemblyLinearVelocity = Vector3.new(vel.X, newVy, vel.Z)
end

local function setRodFloatRelax(inst: RodConstraint, relax: boolean)
	if relax then
		if inst:GetAttribute("_FloatStored") ~= true then
			inst:SetAttribute("_FloatStored", true)
			inst:SetAttribute("_FloatOrigLimits", inst.LimitsEnabled)
			inst:SetAttribute("_FloatOrigLen", inst.Length)
		end
		inst.LimitsEnabled = false
		local extra = Config.number("BalloonFloatRodExtraLengthStuds", 12)
		local origLen = inst:GetAttribute("_FloatOrigLen")
		if type(origLen) == "number" then
			inst.Length = origLen + extra
		end
	else
		if inst:GetAttribute("_FloatStored") == true then
			local origLimits = inst:GetAttribute("_FloatOrigLimits")
			local origLen = inst:GetAttribute("_FloatOrigLen")
			if type(origLimits) == "boolean" then
				inst.LimitsEnabled = origLimits
			end
			if type(origLen) == "number" then
				inst.Length = origLen
			end
			inst:SetAttribute("_FloatStored", nil)
			inst:SetAttribute("_FloatOrigLimits", nil)
			inst:SetAttribute("_FloatOrigLen", nil)
		end
	end
end

function BalloonFloat.restoreAllFloatRods(character: Model?)
	if not character then
		return
	end

	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if not folder then
		return
	end

	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			for _, inst in child:GetDescendants() do
				if inst:IsA("RodConstraint") and inst.Name == "BalloonRod" then
					setRodFloatRelax(inst, false)
				end
			end
		end
	end

	if BalloonFloat._rodRelaxState then
		BalloonFloat._rodRelaxState[character] = nil
	end
end

function BalloonFloat.syncTorsoStrapRopes(character: Model?, taut: boolean)
	if not character then
		return
	end

	local host = character:FindFirstChild("HumanoidRootPart")
	if not host or not host:IsA("BasePart") then
		return
	end

	local slack = if taut
		then Config.number("BalloonFloatTorsoStrapTautSlackStuds", 0.02)
		else Config.number("BalloonTorsoStrapSlackStuds", 0.35)

	for _, child in host:GetChildren() do
		if child:IsA("RopeConstraint") and string.sub(child.Name, 1, #TORSO_STRAP_ROPE_PREFIX) == TORSO_STRAP_ROPE_PREFIX then
			local att0 = child.Attachment0
			local att1 = child.Attachment1
			if att0 and att1 then
				local span = (att1.WorldPosition - att0.WorldPosition).Magnitude
				child.Length = span + slack
			end
		end
	end
end

function BalloonFloat.setFloatRodRelax(character: Model?, relax: boolean)
	if not character then
		return
	end

	local function applyRelaxState(applyRelax: boolean)
		local folder = BalloonFloat.resolveBalloonsFolder(character)
		if not folder then
			return
		end

		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				for _, inst in child:GetDescendants() do
					if inst:IsA("RodConstraint") and inst.Name == "BalloonRod" then
						setRodFloatRelax(inst, applyRelax)
					end
				end
			end
		end
	end

	if not Config.flag("BalloonFloatRelaxRodsWhileFloating") then
		if BalloonFloat._rodRelaxState and BalloonFloat._rodRelaxState[character] then
			applyRelaxState(false)
			BalloonFloat._rodRelaxState[character] = nil
		end
		return
	end

	if BalloonFloat._rodRelaxState == nil then
		BalloonFloat._rodRelaxState = {}
	end

	if BalloonFloat._rodRelaxState[character] == relax then
		if relax then
			applyRelaxState(true)
		end
		return
	end

	BalloonFloat._rodRelaxState[character] = relax
	applyRelaxState(relax)
end

function BalloonFloat.syncFloatBalloonHorizontalToRoot(character: Model?, root: BasePart?, moving: boolean)
	if not character or not root or not Config.flag("BalloonFloatSyncBalloonHorizVelocity") then
		return
	end

	local rootVel = root.AssemblyLinearVelocity
	local targetX = if moving then rootVel.X else 0
	local targetZ = if moving then rootVel.Z else 0

	local function syncPart(part: BasePart)
		local vel = part.AssemblyLinearVelocity
		part.AssemblyLinearVelocity = Vector3.new(targetX, vel.Y, targetZ)
	end

	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				for _, d in child:GetDescendants() do
					if d:IsA("BasePart") then
						syncPart(d)
					end
				end
			end
		end
	end

	local knot = character:FindFirstChild(KNOT_PART_NAME)
	if not knot or not knot:IsA("BasePart") then
		local anchor = BalloonFloat.getAnchorFolder(character)
		if anchor then
			knot = anchor:FindFirstChild(KNOT_PART_NAME)
		end
	end
	if knot and knot:IsA("BasePart") then
		syncPart(knot)
	end
end

function BalloonFloat.dampFloatingBalloonSwing(character: Model?, blend: number, _idle: boolean?)
	if not character or blend <= 0.01 or not Config.flag("BalloonFloatDampBalloonSwing") then
		return
	end

	local factor = math.clamp(Config.number("BalloonFloatBalloonSwingDampFactor", 0.82), 0, 1)
	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if not folder then
		return
	end

	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					d.AssemblyAngularVelocity *= factor
				end
			end
		end
	end

	local knot = character:FindFirstChild(KNOT_PART_NAME)
	if not knot or not knot:IsA("BasePart") then
		local anchor = BalloonFloat.getAnchorFolder(character)
		if anchor then
			knot = anchor:FindFirstChild(KNOT_PART_NAME)
		end
	end
	if knot and knot:IsA("BasePart") then
		knot.AssemblyAngularVelocity *= factor
	end
end

function BalloonFloat.computeMassScale(character: Model?, bodyMass: number?): number
	if not character or not Config.flag("BalloonFloatScaleLiftByPlayerMass") then
		return 1
	end

	local refMass = Config.number("BalloonFloatReferencePlayerMass", 28.874)
	if refMass <= 0 then
		return 1
	end

	local mass = bodyMass
	if mass == nil then
		mass = BalloonFloat.getFloatLiftMass(character)
	end
	if mass <= 0 then
		local cached = character:GetAttribute(BalloonFloat.MASS_ATTR)
		if type(cached) == "number" and cached > 0 then
			mass = cached
		else
			return 1
		end
	end

	local minScale = Config.number("BalloonFloatMassScaleMin", 0.12)
	local maxScale = Config.number("BalloonFloatMassScaleMax", 4.0)
	return math.clamp(mass / refMass, minScale, maxScale)
end

function BalloonFloat.syncMassAttributes(character: Model?)
	if not character then
		return 1
	end

	if BalloonFloat.isRigSettling(character) or not BalloonFloat.hasMinimumBodyLoaded(character) then
		character:SetAttribute(BalloonFloat.MASS_READY_ATTR, false)
		local cached = character:GetAttribute(BalloonFloat.MASS_ATTR)
		if type(cached) == "number" and cached > 0 then
			return BalloonFloat.computeMassScale(character, cached)
		end
		return 1
	end

	local floatActive = character:GetAttribute(BalloonFloat.HOLD_ATTR) == true or character:GetAttribute(BalloonFloat.ACTIVE_ATTR) == true
	if floatActive then
		local cached = character:GetAttribute(BalloonFloat.MASS_ATTR)
		if type(cached) == "number" and cached > 0 then
			return BalloonFloat.computeMassScale(character, cached)
		end
	end

	local sampleMass = BalloonFloat.getFloatLiftMass(character)
	local mass = updateMassReady(character, sampleMass)
	if mass <= 0 then
		local cached = character:GetAttribute(BalloonFloat.MASS_ATTR)
		if type(cached) == "number" and cached > 0 then
			return BalloonFloat.computeMassScale(character, cached)
		end
		return 1
	end

	local rigMass = BalloonFloat.getBalloonRigMass(character)
	local scale = BalloonFloat.computeMassScale(character, mass)
	character:SetAttribute(BalloonFloat.MASS_ATTR, mass)
	character:SetAttribute(BalloonFloat.RIG_MASS_ATTR, rigMass > 0 and rigMass or nil)
	character:SetAttribute(BalloonFloat.MASS_SCALE_ATTR, scale ~= 1 and scale or nil)
	return scale
end

function BalloonFloat.isLiveEquippedModel(model: Model, character: Model): boolean
	if not model:IsA("Model") then
		return false
	end

	local configName = model:GetAttribute("BalloonConfigName")
	if type(configName) ~= "string" or configName == "" then
		return false
	end

	local curAttr = Config.BalloonInstanceHPAttribute or "BalloonCurrentHP"
	local rawHp = model:GetAttribute(curAttr)
	if rawHp == nil then
		return true
	end

	return math.floor(tonumber(rawHp) or 0) > 0
end

local function readLiveModelHp(model: Model, configName: string): number
	local curAttr = Config.BalloonInstanceHPAttribute or "BalloonCurrentHP"
	local rawHp = model:GetAttribute(curAttr)
	if rawHp == nil then
		local def = Shared_Balloons.List[configName]
		return math.max(0, math.floor(tonumber(def and def.HP) or 0))
	end
	return math.max(0, math.floor(tonumber(rawHp) or 0))
end

function BalloonFloat.getLiveEquippedEntries(character: Model?): { { any } }
	if not character then
		return {}
	end

	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if not folder then
		return {}
	end

	local models: { Model } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and BalloonFloat.isLiveEquippedModel(child, character) then
			table.insert(models, child)
		end
	end

	table.sort(models, function(a, b)
		return (tonumber(a:GetAttribute("BalloonIndex")) or 0) < (tonumber(b:GetAttribute("BalloonIndex")) or 0)
	end)

	local equipped: { any } = {}
	for _, model in ipairs(models) do
		local configName = model:GetAttribute("BalloonConfigName")
		if type(configName) == "string" and configName ~= "" then
			table.insert(equipped, { configName, readLiveModelHp(model, configName) })
		end
	end

	return equipped
end

function BalloonFloat.getEquippedCount(character: Model?): number
	if not character then
		return 0
	end

	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if not folder then
		return 0
	end

	local modelCount = 0
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and BalloonFloat.isLiveEquippedModel(child, character) then
			modelCount += 1
		end
	end

	return modelCount
end

--[[
	Reference: 50 balloons × 140 force × 0.01 density.
	factor = 50 / count
	Each balloon: force = 140 × factor, density = 0.01 × factor
	Total force = count × 140 × (50/count) = 50 × 140 = 7000 (constant).
]]
function BalloonFloat.computeHoldParams(balloonCount: number, character: Model?)
	local count = math.max(1, balloonCount)
	local refCount = Config.number("BalloonFloatReferenceBalloonCount", 50)
	local perBalloonForce = Config.number("BalloonFloatHoldLiftPerBalloon", 140)
	local massScale = BalloonFloat.syncMassAttributes(character)

	local factor = refCount / count
	local perBalloonForceY = perBalloonForce * factor * massScale
	local totalForce = BalloonFloat.clampTotalLift(count * perBalloonForceY, character)
	perBalloonForceY = totalForce / count

	return {
		perBalloonForceY = perBalloonForceY,
		totalLift = totalForce,
		factor = factor,
		massScale = massScale,
	}
end

function BalloonFloat.findLiftForce(balloonModel: Model): VectorForce?
	local vf = balloonModel:FindFirstChild(LIFT_FORCE_NAME, true)
	if vf and vf:IsA("VectorForce") then
		return vf
	end
	return nil
end

function BalloonFloat.restoreBalloonLiftAttachment(balloonModel: Model)
	local vf = BalloonFloat.findLiftForce(balloonModel)
	if not vf or vf:GetAttribute("_FloatCenterLift") ~= true then
		return
	end

	local partName = vf:GetAttribute("_FloatOrigAttPart")
	local attName = vf:GetAttribute("_FloatOrigAttName")
	if type(partName) == "string" and type(attName) == "string" then
		for _, d in balloonModel:GetDescendants() do
			if d:IsA("BasePart") and d.Name == partName then
				local att = d:FindFirstChild(attName)
				if att and att:IsA("Attachment") then
					vf.Attachment0 = att
					break
				end
			end
		end
	end

	vf.ApplyAtCenterOfMass = false
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf:SetAttribute("_FloatCenterLift", nil)
	vf:SetAttribute("_FloatOrigAttPart", nil)
	vf:SetAttribute("_FloatOrigAttName", nil)
end

local function setPartDensity(part: BasePart, density: number)
	local props = part.CurrentPhysicalProperties
	part.CustomPhysicalProperties = PhysicalProperties.new(
		density,
		props.Friction,
		props.Elasticity,
		props.FrictionWeight,
		props.ElasticityWeight
	)
end

function BalloonFloat.applyFloatToModelWithParams(
	balloonModel: Model,
	forceY: number,
	density: number
): boolean
	local vf = BalloonFloat.findLiftForce(balloonModel)
	if vf then
		vf.Enabled = true
		vf.Force = Vector3.new(0, forceY, 0)
	end

	for _, d in balloonModel:GetDescendants() do
		if d:IsA("BasePart") then
			setPartDensity(d, density)
		end
	end

	return vf ~= nil
end

function BalloonFloat.applyFloatDensityToModel(balloonModel: Model, density: number): boolean
	for _, d in balloonModel:GetDescendants() do
		if d:IsA("BasePart") then
			setPartDensity(d, density)
		end
	end
	return true
end

function BalloonFloat.applyHrpFloatLift(character: Model?, forceY: number)
	if not character or not Config.flag("BalloonFloatCentralizedLiftEnabled") then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end

	local attName = Config.BalloonFloatHrpLiftAttachmentName or "BalloonFloatLiftAtt"
	local forceName = Config.BalloonFloatHrpLiftForceName or "BalloonFloatLift"

	local att = hrp:FindFirstChild(attName)
	if not att or not att:IsA("Attachment") then
		if att then
			att:Destroy()
		end
		att = Instance.new("Attachment")
		att.Name = attName
		att.Parent = hrp
	end

	local vf = hrp:FindFirstChild(forceName)
	if not vf or not vf:IsA("VectorForce") then
		if vf then
			vf:Destroy()
		end
		vf = Instance.new("VectorForce")
		vf.Name = forceName
		vf.Attachment0 = att
		vf.RelativeTo = Enum.ActuatorRelativeTo.World
		vf.ApplyAtCenterOfMass = true
		vf.Parent = hrp
	end

	vf.Enabled = true
	vf.Force = Vector3.new(0, forceY, 0)
end

function BalloonFloat.clearHrpFloatLift(character: Model?)
	if not character then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end

	local forceName = Config.BalloonFloatHrpLiftForceName or "BalloonFloatLift"
	local vf = hrp:FindFirstChild(forceName)
	if vf and vf:IsA("VectorForce") then
		vf.Enabled = false
		vf.Force = Vector3.zero
	end
end

local function clearTorsoStrapRopesOnHost(host: BasePart)
	for _, child in host:GetChildren() do
		if child:IsA("RopeConstraint") and string.sub(child.Name, 1, #TORSO_STRAP_ROPE_PREFIX) == TORSO_STRAP_ROPE_PREFIX then
			child:Destroy()
		end
	end
end

local function destroyLegacyFloatProxy(character: Model)
	local proxy = character:FindFirstChild(LEGACY_PROXY_PART_NAME)
	if proxy then
		proxy:Destroy()
	end
end

local function getTorsoPart(character: Model): BasePart?
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function clearKnotWelds(knot: BasePart)
	for _, child in knot:GetChildren() do
		if child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end
end

local function destroyFloatAnchorBundle(character: Model)
	local anchor = BalloonFloat.getAnchorFolder(character)
	if anchor then
		anchor:Destroy()
	end
	local legacyFollow = character:FindFirstChild(FOLLOW_PART_NAME)
	if legacyFollow then
		legacyFollow:Destroy()
	end
end

local function clearFollowHostWelds(followPart: BasePart)
	for _, child in followPart:GetChildren() do
		if child:IsA("WeldConstraint") and child.Name == FOLLOW_HOST_WELD_NAME then
			child:Destroy()
		end
	end
end

local function resolveFollowPart(character: Model): BasePart?
	local anchor = BalloonFloat.getAnchorFolder(character)
	if not anchor then
		return nil
	end
	local follow = anchor:FindFirstChild(FOLLOW_PART_NAME)
	if follow and follow:IsA("BasePart") then
		return follow
	end
	return nil
end

local function groundFollowWeldIsValid(character: Model, followPart: BasePart, hrp: BasePart): boolean
	if followPart.Anchored then
		return false
	end
	for _, child in followPart:GetChildren() do
		if child:IsA("WeldConstraint") and child.Name == FOLLOW_HOST_WELD_NAME then
			return child.Part0 == hrp and child.Part1 == followPart
		end
	end
	return false
end

local function weldFollowPartToHost(character: Model, followPart: BasePart): boolean
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local torso = getTorsoPart(character)
	if not hrp or not hrp:IsA("BasePart") or not torso then
		return false
	end

	if groundFollowWeldIsValid(character, followPart, hrp) then
		return true
	end

	local BalloonRig = getBalloonRig()
	local hubOff = BalloonRig.computeTorsoHubOffset(torso)
	local hostLocal = BalloonRig.computeHubLocalOffsetOnHrp(hrp, torso, hubOff)

	clearFollowHostWelds(followPart)
	followPart.Anchored = false
	followPart.Massless = true
	followPart.CanCollide = false
	followPart.CanQuery = false
	followPart.CanTouch = false
	followPart.CFrame = hrp.CFrame * CFrame.new(hostLocal)

	local weld = Instance.new("WeldConstraint")
	weld.Name = FOLLOW_HOST_WELD_NAME
	weld.Part0 = hrp
	weld.Part1 = followPart
	weld.Parent = followPart
	return true
end

local function assignFollowRigNetworkOwner(character: Model)
	if not RunService:IsServer() then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local function setOwner(part: Instance?)
		if not part or not part:IsA("BasePart") then
			return
		end
		pcall(function()
			part:SetNetworkOwnershipAuto(false)
			part:SetNetworkOwner(player)
		end)
	end

	setOwner(resolveFollowPart(character))

	local anchor = BalloonFloat.getAnchorFolder(character)
	if anchor then
		setOwner(anchor:FindFirstChild(KNOT_PART_NAME))
	end
end

function BalloonFloat.ensureFollowRigWeld(character: Model?): boolean
	if not character then
		return false
	end
	local follow = resolveFollowPart(character)
	if not follow then
		return false
	end
	return weldFollowPartToHost(character, follow)
end

function BalloonFloat.softenFollowRigBalloons(character: Model?, factor: number?)
	if not character then
		return
	end
	factor = math.clamp(factor or Config.number("BalloonFloatFollowRigFloatStartDamp", 0.55), 0, 1)
	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if not folder then
		return
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					d.AssemblyLinearVelocity *= factor
					d.AssemblyAngularVelocity *= factor
				end
			end
		end
	end
end

local function ensureFloatAnchorFollowPart(anchor: Folder, character: Model): BasePart?
	local follow = anchor:FindFirstChild(FOLLOW_PART_NAME)
	if follow and not follow:IsA("BasePart") then
		follow:Destroy()
		follow = nil
	end
	if not follow then
		follow = Instance.new("Part")
		follow.Name = FOLLOW_PART_NAME
		follow.Size = Vector3.new(0.1, 0.1, 0.1)
		follow.Transparency = 1
		follow.CanCollide = false
		follow.CanQuery = false
		follow.CanTouch = false
		follow.Massless = true
		follow.Anchored = false
		follow.CollisionGroup = Config.BalloonCollisionGroup or "Balloons"
		follow.Parent = anchor
	end

	weldFollowPartToHost(character, follow)
	return follow
end

local function knotIsWeldedToFollow(knot: BasePart, followPart: BasePart): boolean
	for _, child in knot:GetChildren() do
		if
			child:IsA("WeldConstraint")
			and (child.Part0 == followPart or child.Part1 == followPart)
			and (child.Part0 == knot or child.Part1 == knot)
		then
			return true
		end
	end
	return false
end

local function weldKnotToFollowPart(character: Model, followPart: BasePart, knot: BasePart)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local torso = getTorsoPart(character)
	if not hrp or not hrp:IsA("BasePart") or not torso then
		return
	end

	local BalloonRig = require(script.Parent.BalloonRig)
	local hubOff = BalloonRig.computeTorsoHubOffset(torso)
	local knotLocal = BalloonRig.computeKnotLocalOffset(hubOff)
	local knotHostLocal = BalloonRig.computeHubLocalOffsetOnHrp(hrp, torso, knotLocal)
	local hubHostLocal = BalloonRig.computeHubLocalOffsetOnHrp(hrp, torso, hubOff)

	clearKnotWelds(knot)
	knot.CFrame = followPart.CFrame * CFrame.new(knotHostLocal - hubHostLocal)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = followPart
	weld.Part1 = knot
	weld.Parent = knot
end

local function severCharacterFromBalloonRig(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		clearTorsoStrapRopesOnHost(hrp)
	end

	local anchor = BalloonFloat.getAnchorFolder(character)
	if not anchor then
		return
	end

	local follow = anchor:FindFirstChild(FOLLOW_PART_NAME)
	if not follow or not follow:IsA("BasePart") then
		return
	end

	local knotOnChar = character:FindFirstChild(KNOT_PART_NAME)
	if knotOnChar and knotOnChar:IsA("BasePart") then
		knotOnChar.Parent = anchor
		weldKnotToFollowPart(character, follow, knotOnChar)
	end
end

function BalloonFloat.hasBalloonFollowRig(character: Model?): boolean
	if not character then
		return false
	end
	local anchor = BalloonFloat.getAnchorFolder(character)
	if not anchor then
		return false
	end
	local follow = anchor:FindFirstChild(FOLLOW_PART_NAME)
	return follow ~= nil and follow:IsA("BasePart")
end

function BalloonFloat.snapFollowRigToTorso(character: Model?): boolean
	return BalloonFloat.ensureFollowRigWeld(character)
end

function BalloonFloat.ensureFollowRigBalloonsLive(character: Model?)
	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if not folder then
		return
	end

	local massScale = BalloonFloat.syncMassAttributes(character)
	local liftY = Config.number("BalloonFloatNormalLiftY", 1.45) * massScale
	local density = Config.number("BalloonFloatNormalDensity", 0.0001)

	for _, child in folder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		for _, d in child:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
			end
		end
		BalloonFloat.applyFloatToModelWithParams(child, liftY, density)
	end
end

function BalloonFloat.ensureFollowRigRodLimits(character: Model?)
	if not character or not _rigIsolationState[character] then
		return
	end

	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if not folder then
		return
	end

	local BalloonRig = require(script.Parent.BalloonRig)
	local rig = BalloonRig.adoptFromCharacter(character)
	local limitsEnabled = Config.flag("BalloonRodLimitsEnabled")
	local limitAngle1 = Config.number("BalloonRodLimitAngle1", 20)

	for _, child in folder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		for _, inst in child:GetDescendants() do
			if inst:IsA("RodConstraint") and inst.Name == "BalloonRod" then
				local hubAtt = inst.Attachment0
				inst.LimitsEnabled = limitsEnabled
				inst.LimitAngle0 = rig:_rodLimitAngle0ForHub(hubAtt)
				inst.LimitAngle1 = limitAngle1
			end
		end
	end
end

function BalloonFloat.tickFollowRigHub(character: Model?, _opts: { floating: boolean?, liftBlend: number? }?)
	if not character or not BalloonFloat.hasBalloonFollowRig(character) then
		return
	end
	BalloonFloat.ensureFollowRigWeld(character)
end

local function repointHubConstraintsToFollow(
	character: Model,
	followPart: BasePart,
	saved: { { constraint: Constraint, origAtt: Attachment } }
)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end

	local hrpHub = hrp:FindFirstChild(HUB_ATT_NAME)
	if not hrpHub or not hrpHub:IsA("Attachment") then
		return
	end

	local followHub = followPart:FindFirstChild(HUB_ATT_NAME)
	if followHub and not followHub:IsA("Attachment") then
		followHub:Destroy()
		followHub = nil
	end
	if not followHub then
		followHub = hrpHub:Clone()
		followHub.Position = Vector3.zero
		followHub.Parent = followPart
	end

	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if not folder then
		return
	end

	for _, child in folder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		for _, inst in child:GetDescendants() do
			if (inst:IsA("RodConstraint") or inst:IsA("RopeConstraint"))
				and (inst.Name == "BalloonRod" or inst.Name == "BalloonRope")
				and inst.Attachment0 == hrpHub
			then
				table.insert(saved, { constraint = inst, origAtt = hrpHub })
				inst.Attachment0 = followHub
			end
		end
	end
end

function BalloonFloat.isFloatRigIsolated(character: Model?): boolean
	return character ~= nil and _rigIsolationState[character] ~= nil
end

function BalloonFloat.refreshBalloonFollowRig(character: Model?)
	if not character or not _rigIsolationState[character] then
		return
	end

	local anchor = BalloonFloat.getAnchorFolder(character)
	if not anchor then
		return
	end

	local followPart = anchor:FindFirstChild(FOLLOW_PART_NAME)
	if not followPart or not followPart:IsA("BasePart") then
		return
	end

	local balloonsFolder = BalloonFloat.resolveBalloonsFolder(character)
	if balloonsFolder and balloonsFolder.Parent ~= anchor then
		balloonsFolder.Parent = anchor
	end

	local knot = character:FindFirstChild(KNOT_PART_NAME) or anchor:FindFirstChild(KNOT_PART_NAME)
	if knot and knot:IsA("BasePart") then
		if knot.Parent ~= anchor then
			knot.Parent = anchor
		end
		if not knotIsWeldedToFollow(knot, followPart) then
			weldKnotToFollowPart(character, followPart, knot)
		end
	end

	severCharacterFromBalloonRig(character)
	BalloonFloat.ensureFollowRigWeld(character)
	assignFollowRigNetworkOwner(character)
	BalloonFloat.restoreAllFloatRods(character)
	BalloonFloat.ensureFollowRigRodLimits(character)
	BalloonFloat.resyncFollowRigBalloonTethers(character, false)
	BalloonFloat.ensureFollowRigBalloonsLive(character)
end

function BalloonFloat.resyncFollowRigBalloonTethers(character: Model?, snapAll: boolean?)
	if not character or not _rigIsolationState[character] then
		return
	end

	local BalloonRig = require(script.Parent.BalloonRig)
	local rig = BalloonRig.adoptFromCharacter(character)
	rig:_refreshAdoptedRefs()
	if snapAll then
		rig:_snapAllBalloonsToRodRest()
	end
	rig:SyncRopeVisibility()
end

function BalloonFloat.ensureBalloonFollowRig(character: Model?)
	if not character or _rigIsolationState[character] then
		return
	end
	BalloonFloat.enterFloatRigIsolation(character)
end

function BalloonFloat.enterFloatRigIsolation(character: Model?)
	if not character or _rigIsolationState[character] then
		return
	end

	destroyLegacyFloatProxy(character)

	local anchor = Instance.new("Folder")
	anchor.Name = ANCHOR_FOLDER_NAME
	anchor.Parent = character

	local followPart = ensureFloatAnchorFollowPart(anchor, character)
	if not followPart then
		anchor:Destroy()
		return
	end

	local state: RigIsolationState = { savedHubLinks = {} }

	local balloonsFolder = BalloonFloat.resolveBalloonsFolder(character)
	if balloonsFolder and balloonsFolder.Parent ~= anchor then
		balloonsFolder.Parent = anchor
	end

	local knot = character:FindFirstChild(KNOT_PART_NAME)
	if not knot or not knot:IsA("BasePart") then
		knot = anchor:FindFirstChild(KNOT_PART_NAME)
	end
	if knot and knot:IsA("BasePart") then
		knot.Parent = anchor
		weldKnotToFollowPart(character, followPart, knot)
	else
		repointHubConstraintsToFollow(character, followPart, state.savedHubLinks)
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		clearTorsoStrapRopesOnHost(hrp)
	end

	severCharacterFromBalloonRig(character)
	BalloonFloat.ensureFollowRigWeld(character)
	assignFollowRigNetworkOwner(character)
	BalloonFloat.restoreAllFloatRods(character)
	BalloonFloat.ensureFollowRigRodLimits(character)
	BalloonFloat.resyncFollowRigBalloonTethers(character, true)
	BalloonFloat.ensureFollowRigBalloonsLive(character)
	_rigIsolationState[character] = state
end

function BalloonFloat.exitFloatRigIsolation(character: Model?)
	destroyLegacyFloatProxy(character)

	local state = if character then _rigIsolationState[character] else nil
	if not character or not state then
		destroyFloatAnchorBundle(character)
		return
	end

	local anchor = BalloonFloat.getAnchorFolder(character)
	if anchor then
		local knot = anchor:FindFirstChild(KNOT_PART_NAME)
		if knot and knot:IsA("BasePart") then
			knot.Parent = character
		end
		local balloonsFolder = anchor:FindFirstChild(BalloonFloat.ATTACHED_BALLOONS_FOLDER)
		if balloonsFolder and balloonsFolder:IsA("Folder") then
			balloonsFolder.Parent = character
		end
	end

	local knot = character:FindFirstChild(KNOT_PART_NAME)
	if knot and knot:IsA("BasePart") then
		local BalloonRig = require(script.Parent.BalloonRig)
		local rig = BalloonRig.adoptFromCharacter(character)
		rig:_repositionKnotToHost()
		rig:repairTorsoStrapsIfNeeded()
	elseif #state.savedHubLinks > 0 then
		for _, entry in state.savedHubLinks do
			local c = entry.constraint
			local orig = entry.origAtt
			if c.Parent and orig.Parent then
				c.Attachment0 = orig
			end
		end
	end

	_rigIsolationState[character] = nil
	destroyFloatAnchorBundle(character)
end

function BalloonFloat.landFloatPhysics(character: Model?)
	if not character then
		return
	end
	BalloonFloat.clearHrpFloatLift(character)
	BalloonFloat.restoreBalloonPhysics(character)
	BalloonFloat.restoreAllFloatRods(character)
end

function BalloonFloat.restoreBalloonPhysics(character: Model?)
	if not character then
		return
	end

	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if not folder then
		return
	end

	local normalDensity = Config.number("BalloonFloatNormalDensity", 0.0001)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			BalloonFloat.applyFloatDensityToModel(child, normalDensity)
			setBalloonMassless(child, false)
			setBalloonCanCollide(child, true)
			BalloonFloat.restoreBalloonLiftAttachment(child)
		end
	end
end

function BalloonFloat.applyFloatBlendToFolder(
	balloonsFolder: Folder?,
	liftBlend: number,
	balloonCount: number,
	character: Model?,
	opts: {
		wantHold: boolean?,
		onGround: boolean?,
		fallCatch: boolean?,
		liftMult: number?,
		manualHold: boolean?,
		propBlend: number?,
	}?
): number
	if not balloonsFolder then
		return 0
	end
	if balloonCount < Config.number("BalloonFloatMinBalloons", 1) then
		return 0
	end

	local normalDensity = Config.number("BalloonFloatNormalDensity", 0.0001)
	local normalLiftYBase = Config.number("BalloonFloatNormalLiftY", 1.0)

	if character and BalloonFloat.isRigSettling(character) then
		BalloonFloat.clearHrpFloatLift(character)
		for _, child in balloonsFolder:GetChildren() do
			if child:IsA("Model") and BalloonFloat.isLiveEquippedModel(child, character) then
				BalloonFloat.restoreBalloonLiftAttachment(child)
				BalloonFloat.applyFloatToModelWithParams(child, normalLiftYBase, normalDensity)
			end
		end
		return 0
	end

	opts = opts or {}
	local wantHold = opts.wantHold == true
	local onGround = opts.onGround == true
	local fallCatch = opts.fallCatch == true
	local liftMult = if opts.liftMult ~= nil then opts.liftMult else 1

	liftBlend = math.clamp(liftBlend, 0, 1)
	if onGround and not wantHold then
		liftBlend = 0
	end

	local massScale = BalloonFloat.syncMassAttributes(character)
	local normalLiftY = normalLiftYBase * massScale
	local holdParams = BalloonFloat.computeHoldParams(balloonCount, character)
	local floating = liftBlend > 0.001 and (wantHold or not onGround)
	local masslessFloat = Config.flag("BalloonFloatMasslessBalloonsWhileFloating")

	local holdBlend = 0
	if liftBlend > 0.001 and (wantHold or not onGround) then
		holdBlend = liftBlend
	end
	local blendT = smoothstep01(holdBlend)
	local isolated = character ~= nil and BalloonFloat.isFloatRigIsolated(character)
	--[[ Isolated follow rig: hub is kinematic (anchored), hold lift on HRP only.
		Balloons keep gentle VectorForce so rods never yank the player sideways. ]]
	local useCentralizedLift = Config.flag("BalloonFloatCentralizedLiftEnabled")
		and (not isolated or floating)
	local balloonForceY = normalLiftY
	if isolated then
		local bob = Config.number("BalloonFloatFollowRigFloatBobMult", 0.12)
		balloonForceY = normalLiftY * (1 + bob * blendT)
	elseif not useCentralizedLift then
		balloonForceY = normalLiftY + (holdParams.perBalloonForceY - normalLiftY) * blendT
	end

	if floating and useCentralizedLift and character then
		local hrpForce = BalloonFloat.computeStabilizedHrpLiftForce(character, liftBlend, {
			fallCatch = fallCatch,
			wantHold = wantHold,
			liftMult = liftMult,
			manualHold = opts.manualHold == true,
			propBlend = opts.propBlend or 0,
		})
		BalloonFloat.applyHrpFloatLift(character, hrpForce)
	else
		BalloonFloat.clearHrpFloatLift(character)
	end

	if character then
		if not BalloonFloat.isFloatRigIsolated(character) then
			BalloonFloat.setFloatRodRelax(character, floating)
		end
		if not floating and BalloonFloat._rodRelaxState then
			BalloonFloat._rodRelaxState[character] = nil
		end
	end

	local noCollideFloat = Config.flag("BalloonFloatNoCollideWhileFloating")
	local applied = 0
	for _, child in balloonsFolder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		if character and not BalloonFloat.isLiveEquippedModel(child, character) then
			BalloonFloat.applyFloatToModelWithParams(child, 0, normalDensity)
			continue
		end
		if masslessFloat and floating and not isolated then
			setBalloonMassless(child, true)
		elseif masslessFloat then
			setBalloonMassless(child, false)
		end
		if noCollideFloat then
			setBalloonCanCollide(child, not floating)
		end
		if BalloonFloat.applyFloatToModelWithParams(child, balloonForceY, normalDensity) then
			applied += 1
		end
	end
	return applied
end

return BalloonFloat
