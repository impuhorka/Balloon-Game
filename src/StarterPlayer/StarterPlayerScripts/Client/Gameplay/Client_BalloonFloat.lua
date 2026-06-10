--[[
	Client_BalloonFloat — hold jump input, feel (FOV, shake, landing VFX), local horiz polish.
	Physics run on server via Server_BalloonFloat.
]]

local Debris = game:GetService("Debris")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BalloonFloat = require(ReplicatedStorage.Modules.Gameplay.BalloonFloat)
local BalloonRigKit = require(ReplicatedStorage.Modules.Gameplay.BalloonRigKit)
local CameraShake = require(script.Parent.Parent.Effects.Client_CameraShake)
local Client_FOV = require(script.Parent.Parent.Effects.Client_FOV)
local Config = require(ReplicatedStorage.Modules.ItemConfigs.BalloonConfig)
local Shared_PropelerConfig = require(ReplicatedStorage.Modules.Settings.Shared_PropelerConfig)

local Module = {}

local LocalPlayer = Players.LocalPlayer

local lastSentHold = false
local prevWantHold = false
local floatState = BalloonFloat.newLiftBlendState()

local trackingFall = false
local peakHeight = 0
local maxFallStuds = 0
local wasAirborne = false
local wasCharacterAirborne = false
local prevBalloonCount = 0
local feelFovBoost = 0
local jumpHeld = false
local JUMP_SINK_ACTION = "BalloonFloatJumpSink"
local prevFollowRigFloating = false
local prevPropBlend = 0

local LANDING_EFFECTS_FOLDER = "BalloonLandingEffects"
local LANDING_DEBRIS_GRAY = Color3.fromRGB(132, 132, 136)

local function hasMinBalloons(count: number): boolean
	return count >= Config.number("BalloonFloatMinBalloons", 1)
end

local function smoothstep01(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function isTextInputFocused(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

local function isJumpHoldActive(): boolean
	if isTextInputFocused() then
		return false
	end
	return jumpHeld
end

local function getPropellerBlend(character: Model): number
	return tonumber(character:GetAttribute("PropelerBoostBlend")) or 0
end

local function isPropellerZoneActive(character: Model): boolean
	return character:GetAttribute("PropelerZoneActive") == true or getPropellerBlend(character) > 0.01
end

local function shouldSinkJumpForBalloonFloat(): boolean
	if isTextInputFocused() then
		return false
	end
	local character = LocalPlayer.Character
	if not character or BalloonFloat.isRigSettling(character) then
		return false
	end
	return BalloonFloat.getEquippedCount(character) >= Config.number("BalloonFloatMinBalloons", 1)
end

local function bindBalloonJumpSink()
	ContextActionService:BindActionAtPriority(
		JUMP_SINK_ACTION,
		function(_, state, _input)
			if state == Enum.UserInputState.Begin then
				jumpHeld = true
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				jumpHeld = false
			end

			if isTextInputFocused() then
				jumpHeld = false
				return Enum.ContextActionResult.Pass
			end

			if shouldSinkJumpForBalloonFloat() then
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.ContextActionPriority.High.Value + 500,
		Enum.PlayerActions.CharacterJump
	)
end

local function getHumanoidAndRoot(character: Model): (Humanoid?, BasePart?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return humanoid, root
	end
	return humanoid, nil
end

local function sendHoldState(holding: boolean)
	if holding == lastSentHold then
		return
	end
	lastSentHold = holding

	local events = ReplicatedStorage:FindFirstChild("Events")
	local handler = events and events:FindFirstChild("BalloonFloatHandler")
	if handler and handler:IsA("RemoteEvent") then
		handler:FireServer("Hold", holding)
	end
end

local function resetFallTracking()
	trackingFall = false
	peakHeight = 0
	maxFallStuds = 0
	wasCharacterAirborne = false
end

local function resetFloatState()
	prevFollowRigFloating = false
	lastSentHold = false
	prevWantHold = false
	jumpHeld = false
	floatState = BalloonFloat.newLiftBlendState()
	resetFallTracking()
	wasAirborne = false
	prevBalloonCount = 0
	prevPropBlend = 0
	feelFovBoost = 0
	Client_FOV:SetBalloonFloatBoost(0)
	sendHoldState(false)
end

local function shouldUseBalloonParachute(airborne: boolean, count: number, wantHold: boolean, character: Model?): boolean
	if character and BalloonFloat.isFloatBlocked(character) then
		return false
	end
	if not airborne or not hasMinBalloons(count) then
		return false
	end
	if not Config.flag("BalloonFloatParachuteEnabled") then
		return false
	end
	return not wantHold
end

local function bleedPassiveFallHorizontal(
	humanoid: Humanoid?,
	root: BasePart,
	dt: number,
	airborne: boolean,
	count: number,
	character: Model?
)
	if isJumpHoldActive() or not Config.flag("BalloonFloatFallHorizBleedEnabled") then
		return
	end
	if not shouldUseBalloonParachute(airborne, count, false, character) then
		return
	end

	local walkSpeed = if humanoid then humanoid.WalkSpeed else 16
	local maxH = walkSpeed * Config.number("BalloonFloatFallHorizMaxMult", 1.05)
	local vel = root.AssemblyLinearVelocity
	local h = Vector3.new(vel.X, 0, vel.Z)
	local speed = h.Magnitude
	if speed <= maxH + 0.05 then
		return
	end

	local bleed = Config.number("BalloonFloatFallHorizBleedRate", 16)
	local newSpeed = speed + (maxH - speed) * math.min(1, bleed * dt)
	local newH = if speed > 0.05 then h.Unit * newSpeed else Vector3.zero
	root.AssemblyLinearVelocity = Vector3.new(newH.X, vel.Y, newH.Z)
end

local function updateFloatFeelFov(
	dt: number,
	wantHold: boolean,
	airborne: boolean,
	balloonCount: number,
	liftBlend: number,
	releasing: boolean,
	character: Model?
)
	local propBlend = 0
	if character then
		propBlend = tonumber(character:GetAttribute("PropelerBoostBlend")) or 0
	end

	if not airborne and liftBlend <= 0.01 and not releasing and propBlend <= 0.01 then
		feelFovBoost = 0
		Client_FOV:SetBalloonFloatBoost(0)
		return
	end

	local target = 0
	local parachuteLiftBlend = Config.number("BalloonFloatParachuteLiftBlend", 0.35)
	if airborne and hasMinBalloons(balloonCount) then
		local fullBoost = Config.number("BalloonFloatFeelFovBoost", 8)
		local paraBoost = Config.number("BalloonFloatFeelFovParachute", 4)
		if wantHold or liftBlend > parachuteLiftBlend then
			target = fullBoost * smoothstep01(liftBlend)
		elseif liftBlend <= parachuteLiftBlend then
			target = paraBoost
		end
	end

	local rate = Config.number("BalloonFloatFeelFovLerpRate", 10)
	feelFovBoost += (target - feelFovBoost) * math.min(1, rate * dt)
	if math.abs(feelFovBoost) < 0.05 and target == 0 then
		feelFovBoost = 0
	end
	Client_FOV:SetBalloonFloatBoost(feelFovBoost)
end

local function playPropellerFeelShake(propBlend: number, airborne: boolean, root: BasePart?)
	if not airborne or not root or propBlend <= 0.05 then
		return
	end

	if prevPropBlend < 0.05 and propBlend >= 0.12 then
		local entryShake = Shared_PropelerConfig.ClientEntryShakeIntensity or 0.26
		CameraShake:Start(entryShake, 18, 0.3, 0.2)
		return
	end

	if propBlend > 0.25 then
		local rumble = (Shared_PropelerConfig.ClientShakeIntensity or 0.14) * propBlend
		if math.random() < 0.08 * propBlend then
			CameraShake:Start(rumble, 20, 0.12, 0.08)
		end
	end
end

local function playFloatFeelShake(
	wantHold: boolean,
	prevHold: boolean,
	root: BasePart?,
	airborne: boolean,
	wasAirborneBefore: boolean
)
	if not wantHold or not airborne or not root or prevHold or wasAirborneBefore then
		return
	end

	local vy = root.AssemblyLinearVelocity.Y
	local catchVy = Config.number("BalloonFloatCatchShakeFallVy", -14)
	if vy >= catchVy then
		return
	end

	local intensity = Config.number("BalloonFloatCatchShakeIntensity", 0.28)
	local mult = math.clamp(-vy / math.abs(catchVy), 1, 2.2)
	CameraShake:Start(intensity * mult, 14, 0.22, 0.18)
end

local function stabilizeFloatHorizontal(humanoid: Humanoid?, root: BasePart, blend: number, dt: number)
	if not Config.flag("BalloonFloatHorizStabilizeEnabled") or blend <= 0.01 then
		return
	end

	local vel = root.AssemblyLinearVelocity
	local actualH = Vector3.new(vel.X, 0, vel.Z)

	local moveMult = Config.number("BalloonFloatHorizMoveSpeedMultiplier", 1)
	local intendedH = Vector3.zero
	if humanoid and humanoid.MoveDirection.Magnitude > 0.05 then
		intendedH = humanoid.MoveDirection * (humanoid.WalkSpeed * moveMult)
	end

	local excess = actualH - intendedH
	local excessSpeed = excess.Magnitude
	local minExcess = Config.number("BalloonFloatHorizStabilizeMinExcess", 0.35)
	local strength = smoothstep01(blend)
	local moving = intendedH.Magnitude > 0.1

	if not moving then
		if Config.flag("BalloonFloatHorizIdleHardStop") then
			actualH = Vector3.zero
		else
			local idleStopRate = Config.number("BalloonFloatHorizIdleStopRate", 34)
			local retain = math.exp(-idleStopRate * strength * dt)
			actualH *= retain

			local snap = Config.number("BalloonFloatHorizIdleStopSnap", 0.12)
			if actualH.Magnitude < snap then
				actualH = Vector3.zero
			end
		end
	elseif excessSpeed >= minExcess then
		local baseRate = Config.number("BalloonFloatHorizStabilizeBaseRate", 12)
		local speedScale = Config.number("BalloonFloatHorizStabilizeSpeedScale", 0.4)
		local rate = baseRate + excessSpeed * speedScale
		local retain = math.exp(-rate * strength * dt)
		local newH = intendedH + excess * retain
		actualH = Vector3.new(newH.X, 0, newH.Z)
	end

	if moving and moveMult > 1 then
		local deficit = intendedH - actualH
		if deficit.Magnitude > 0.05 then
			local accel = Config.number("BalloonFloatHorizMoveAccel", 52)
			local maxStep = accel * strength * dt
			local step = deficit.Unit * math.min(deficit.Magnitude, maxStep)
			actualH += step
		end
	end

	root.AssemblyLinearVelocity = Vector3.new(actualH.X, vel.Y, actualH.Z)
end

local function getLegGroundOrigin(character: Model): Vector3?
	local left = character:FindFirstChild("LeftFoot") or character:FindFirstChild("Left Leg")
	local right = character:FindFirstChild("RightFoot") or character:FindFirstChild("Right Leg")
	local sample = nil
	if left and left:IsA("BasePart") and right and right:IsA("BasePart") then
		sample = (left.Position + right.Position) * 0.5
	else
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			sample = root.Position - Vector3.new(0, 3, 0)
		end
	end
	if not sample then
		return nil
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local hit = Workspace:Raycast(sample + Vector3.new(0, 2.5, 0), Vector3.new(0, -12, 0), rayParams)
	local groundY = hit and hit.Position.Y or sample.Y
	return Vector3.new(sample.X, groundY + 0.04, sample.Z)
end

local function getOrCreateLandingFolder(): Folder
	local folder = Workspace:FindFirstChild(LANDING_EFFECTS_FOLDER)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = LANDING_EFFECTS_FOLDER
	folder.Parent = Workspace
	return folder
end

local function arcLocalY(t: number, peakY: number, endY: number): number
	local risePortion = 0.42
	if t <= risePortion then
		local u = t / risePortion
		return peakY * (u * (2 - u))
	end
	local u = (t - risePortion) / (1 - risePortion)
	return peakY + (endY - peakY) * (u * u)
end

local function elapsedToArcT(elapsed: number, duration: number, fallSpeedMult: number): number
	local risePortion = 0.42
	local riseTime = duration * risePortion
	local fallTime = duration * (1 - risePortion)
	if elapsed <= riseTime then
		return (elapsed / riseTime) * risePortion
	end
	local fallProgress = math.min(1, ((elapsed - riseTime) * fallSpeedMult) / fallTime)
	return risePortion + fallProgress * (1 - risePortion)
end

local function sampleRockHorizOffsets(count: number, maxRadius: number, minSpacing: number): { Vector3 }
	local offsets: { Vector3 } = {}
	local maxAttempts = math.max(count * 50, 80)
	local attempts = 0

	while #offsets < count and attempts < maxAttempts do
		attempts += 1
		local angle = math.random() * math.pi * 2
		local dist = math.sqrt(math.random()) * maxRadius
		local candidate = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)

		local ok = true
		for _, existing in offsets do
			local delta = Vector3.new(candidate.X - existing.X, 0, candidate.Z - existing.Z)
			if delta.Magnitude < minSpacing then
				ok = false
				break
			end
		end

		if ok then
			table.insert(offsets, candidate)
		end
	end

	while #offsets < count do
		local angle = math.random() * math.pi * 2
		local dist = maxRadius * (0.35 + math.random() * 0.65)
		table.insert(offsets, Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist))
	end

	return offsets
end

local function computeLandingFallIntensity(fallStuds: number): number
	local minFall = Config.number("BalloonFloatLandingEffectMinFallStuds", 15)
	local maxFall = math.max(minFall + 1, Config.number("BalloonFloatLandingEffectMaxFallStuds", 65))
	return math.clamp((fallStuds - minFall) / (maxFall - minFall), 0, 1)
end

local function playLandingBurst(character: Model, fallStuds: number)
	local origin = getLegGroundOrigin(character)
	if not origin then
		return
	end

	local intensity = computeLandingFallIntensity(fallStuds)
	local count = math.max(6, math.floor(Config.number("BalloonFloatLandingDebrisCount", 14)))
	local maxRadius = lerpNumber(
		Config.number("BalloonFloatLandingSpreadRadiusStuds", 2.7),
		Config.number("BalloonFloatLandingSpreadRadiusMaxStuds", 5.5),
		intensity
	)
	local minSpacing = lerpNumber(
		Config.number("BalloonFloatLandingRockMinSpacingStuds", 0.42),
		Config.number("BalloonFloatLandingRockMinSpacingMaxStuds", 0.58),
		intensity
	)
	local horizTargets = sampleRockHorizOffsets(count, maxRadius, minSpacing)
	local peakY = lerpNumber(
		Config.number("BalloonFloatLandingArcPeakY", 0.58),
		Config.number("BalloonFloatLandingArcPeakMaxY", 1.05),
		intensity
	)
	local endY = lerpNumber(
		Config.number("BalloonFloatLandingArcEndY", -0.12),
		Config.number("BalloonFloatLandingArcEndMaxY", -0.28),
		intensity
	)
	local scaleMin = lerpNumber(
		Config.number("BalloonFloatLandingRockScaleMin", 0.26),
		Config.number("BalloonFloatLandingRockScaleMinAtMaxFall", 0.42),
		intensity
	)
	local scaleMax = lerpNumber(
		Config.number("BalloonFloatLandingRockScaleMax", 0.38),
		Config.number("BalloonFloatLandingRockScaleMaxAtMaxFall", 0.58),
		intensity
	)
	local fadeBelowY = Config.number("BalloonFloatLandingArcFadeBelowY", 0.1)
	local duration = math.max(0.2, Config.number("BalloonFloatLandingArcDuration", 0.6))
	local fadeSpeed = Config.number("BalloonFloatLandingArcFadeSpeed", 7)
	local fallSpeedMin = Config.number("BalloonFloatLandingRockFallSpeedMin", 1)
	local fallSpeedMax = Config.number("BalloonFloatLandingRockFallSpeedMax", 1.65)
	local parent = getOrCreateLandingFolder()

	type Rock = {
		part: BasePart,
		targetHoriz: Vector3,
		elapsed: number,
		fallSpeedMult: number,
		fading: boolean,
	}

	local rocks: { Rock } = {}

	for i = 1, count do
		local part = Instance.new("Part")
		part.Name = "BalloonLandingRock"
		local scale = scaleMin + math.random() * math.max(0.01, scaleMax - scaleMin)
		part.Size = Vector3.new(scale, scale * 0.55, scale)
		part.Color = LANDING_DEBRIS_GRAY
		part.Material = Enum.Material.Slate
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CFrame = CFrame.new(origin)
		part.Parent = parent

		table.insert(rocks, {
			part = part,
			targetHoriz = horizTargets[i] or Vector3.zero,
			elapsed = 0,
			fallSpeedMult = fallSpeedMin + math.random() * math.max(0, fallSpeedMax - fallSpeedMin),
			fading = false,
		})

		Debris:AddItem(part, duration + 0.35)
	end

	local conn: RBXScriptConnection?
	conn = RunService.RenderStepped:Connect(function(dt)
		local alive = 0
		for _, rock in rocks do
			local part = rock.part
			if not part.Parent then
				continue
			end

			rock.elapsed += dt
			local t = elapsedToArcT(rock.elapsed, duration, rock.fallSpeedMult)
			local localY = arcLocalY(t, peakY, endY)
			local travel = math.clamp(t * 1.08, 0, 1)
			local horiz = rock.targetHoriz * travel
			part.CFrame = CFrame.new(origin + Vector3.new(horiz.X, localY, horiz.Z))

			if not rock.fading and t > 0.42 and localY <= fadeBelowY then
				rock.fading = true
			end

			if rock.fading then
				part.Transparency = math.clamp(part.Transparency + dt * fadeSpeed, 0, 1)
				part.Size = part.Size * (1 - dt * 2.2)
			end

			if t < 1 or part.Transparency < 1 then
				alive += 1
			elseif part.Parent then
				part:Destroy()
			end
		end

		if alive == 0 and conn then
			conn:Disconnect()
		end
	end)

	CameraShake:Start(
		lerpNumber(
			Config.number("BalloonFloatLandingShakeIntensityMin", 0.18),
			Config.number("BalloonFloatLandingShakeIntensityMax", 0.55),
			intensity
		),
		lerpNumber(
			Config.number("BalloonFloatLandingShakeFrequencyMin", 10),
			Config.number("BalloonFloatLandingShakeFrequencyMax", 18),
			intensity
		),
		lerpNumber(
			Config.number("BalloonFloatLandingShakeDurationMin", 0.2),
			Config.number("BalloonFloatLandingShakeDurationMax", 0.45),
			intensity
		),
		lerpNumber(
			Config.number("BalloonFloatLandingShakeFadeOutMin", 0.12),
			Config.number("BalloonFloatLandingShakeFadeOutMax", 0.26),
			intensity
		)
	)
end

local function tickBalloonlessFall(
	character: Model,
	root: BasePart?,
	characterAirborne: boolean
)
	if not root then
		wasCharacterAirborne = false
		return
	end

	if characterAirborne then
		if not trackingFall then
			trackingFall = true
			peakHeight = root.Position.Y
			maxFallStuds = 0
		end
		peakHeight = math.max(peakHeight, root.Position.Y)
		maxFallStuds = math.max(maxFallStuds, peakHeight - root.Position.Y)
	end

	if wasCharacterAirborne and not characterAirborne and trackingFall then
		maxFallStuds = math.max(maxFallStuds, peakHeight - root.Position.Y)
		if maxFallStuds >= Config.number("BalloonFloatLandingEffectMinFallStuds", 10) then
			playLandingBurst(character, maxFallStuds)
		end
		resetFallTracking()
	end

	wasCharacterAirborne = characterAirborne
end

local function stabilizeBalloonsAfterLanding(character: Model)
	local seconds = math.max(0, Config.number("BalloonFloatLandingStabilizeSeconds", 0.22))
	if seconds <= 0 then
		return
	end
	BalloonFloat.restoreAllFloatRods(character)
	BalloonFloat.syncTorsoStrapRopes(character, false)
end

local function tickJumpHold(dt: number)
	local character = LocalPlayer.Character
	if not character then
		if lastSentHold then
			sendHoldState(false)
		end
		resetFloatState()
		return
	end

	local count = BalloonFloat.getEquippedCount(character)
	local minBalloons = Config.number("BalloonFloatMinBalloons", 1)
	local hasMinBalloonsNow = count >= minBalloons

	local humanoid, root = getHumanoidAndRoot(character)
	local characterAirborne = BalloonFloat.isCharacterAirborne(humanoid, root) == true

	if prevBalloonCount >= minBalloons and count < minBalloons then
		floatState = BalloonFloat.newLiftBlendState()
		if lastSentHold then
			sendHoldState(false)
		end
		if characterAirborne and root then
			trackingFall = true
			peakHeight = root.Position.Y
			maxFallStuds = 0
		end
	end

	if not hasMinBalloonsNow then
		tickBalloonlessFall(character, root, characterAirborne)
		prevBalloonCount = count
		prevWantHold = false
		wasAirborne = false
		return
	end

	local manualHold = isJumpHoldActive()
	local zoneActive = isPropellerZoneActive(character)
	local wantHold = manualHold or zoneActive
	sendHoldState(manualHold)

	local settling = BalloonFloat.isRigSettling(character)
	local airborne = BalloonFloat.isFloatAirborne(humanoid, root, wantHold, floatState.floatAirSession, floatState.liftBlend)

	playFloatFeelShake(wantHold, prevWantHold, root, airborne, wasAirborne)

	local liftBlend = BalloonFloat.tickLiftBlendState(floatState, dt, {
		wantHold = wantHold,
		airborne = airborne,
		settling = settling,
		humanoid = humanoid,
		root = root,
		resetFloatAirSessionOnLand = false,
	})

	if not wantHold and liftBlend <= 0.01 then
		character:SetAttribute(BalloonFloat.ACTIVE_ATTR, false)
	end

	if prevWantHold and not wantHold and airborne and hasMinBalloons(count) then
		local releaseShake = Config.number("BalloonFloatReleaseShakeIntensity", 0.09)
		if releaseShake > 0 then
			CameraShake:Start(releaseShake, 11, 0.14, 0.1)
		end
	end

	if root and wasAirborne and not airborne then
		stabilizeBalloonsAfterLanding(character)
	end

	if root and wasAirborne and not airborne and wantHold and humanoid then
		floatState.holdRampElapsed = math.min(
			floatState.holdRampElapsed,
			Config.number("BalloonFloatHoldRampSeconds", 0.32) * 0.35
		)
	end

	prevWantHold = wantHold
	wasAirborne = airborne
	prevBalloonCount = count

	local propBlend = getPropellerBlend(character)
	playPropellerFeelShake(propBlend, airborne, root)

	updateFloatFeelFov(dt, wantHold, airborne, count, liftBlend, floatState.releasing, character)

	if character and BalloonFloat.isFloatRigIsolated(character) then
		local isFloating = liftBlend > 0.01 and (wantHold or not airborne)
		-- Zone auto-float already has speed; don't damp client-owned rig when hold stacks on booster.
		if isFloating and not prevFollowRigFloating and propBlend <= 0.05 and prevPropBlend <= 0.05 then
			BalloonFloat.softenFollowRigBalloons(character)
		end
		prevFollowRigFloating = isFloating
	end

	prevPropBlend = propBlend

	if root and hasMinBalloonsNow and not settling and not BalloonFloat.isFloatRigIsolated(character) then
		local isFloating = liftBlend > 0.01 and (wantHold or not airborne)
		if isFloating then
			stabilizeFloatHorizontal(humanoid, root, liftBlend, dt)
			if wantHold then
				BalloonFloat.smoothFloatRiseVelocity(root, liftBlend, dt, character, wantHold)
			end
		elseif not wantHold and airborne then
			bleedPassiveFallHorizontal(humanoid, root, dt, airborne, count, character)
		end
	end
end

function Module:Init()
	ReplicatedStorage:WaitForChild("Events"):WaitForChild("BalloonFloatHandler")
	bindBalloonJumpSink()
	RunService.PreSimulation:Connect(tickJumpHold)

	local function bindCharacter(character: Model)
		resetFloatState()
		BalloonFloat.clearMassState(character)
		character:SetAttribute(BalloonFloat.ACTIVE_ATTR, false)
		character:SetAttribute(BalloonFloat.HOLD_ATTR, false)
		prevBalloonCount = BalloonFloat.getEquippedCount(character)
	end

	LocalPlayer.CharacterAdded:Connect(bindCharacter)
	if LocalPlayer.Character then
		bindCharacter(LocalPlayer.Character)
	end

	LocalPlayer.CharacterRemoving:Connect(resetFloatState)
end

return Module
