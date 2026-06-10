--// BalloonConfig — tuning for balloons, replication, shop.

local Config = {}

--// Names
Config.SigAttribute = "_BalloonSig"
Config.BalloonMaxAttachDistanceStuds = 96 -- legacy; attached rig balloons always count for float
Config.BalloonTotalHPAttribute = "BalloonTotalHP"
Config.BalloonMaxHPAttribute = "BalloonMaxHP"
Config.BalloonInstanceHPAttribute = "BalloonCurrentHP"
Config.BalloonInstanceMaxHPAttribute = "BalloonMaxHP"
Config.BalloonDamagedPulseAttribute = "BalloonDamagedPulse"
Config.BalloonPopSoundId = 125516407397907
Config.BalloonHitSoundId = 83819603091899
Config.BalloonPopSoundVolume = 1.1
Config.BalloonHitSoundVolume = 0.95
Config.BalloonPopSoundMaxDistance = 190
Config.BalloonHitSoundMaxDistance = 150
Config.BalloonHpBillboardTemplateName = "BalloonHP"
Config.BalloonHpBillboardHideSeconds = 5
Config.LocalRigRootName = "LocalBalloonRigs"
Config.LegacyRigRootName = "PlayerBalloonRigs"
Config.BalloonCollisionGroup = "Balloons"
Config.PlayerCollisionGroup = "Players"
Config.BalloonCollideWithDefaultWorld = true
--[[ Balloons pass through:
	- anything under BalloonNoCollisionPaths (e.g. Game.Plots)
	- instances tagged BalloonNoCollisionTag
	- parts with Transparency >= BalloonInvisibleTransparencyMin
]]
Config.BalloonInvisibleCollisionGroup = "InvisibleColliders"
Config.BalloonNoCollisionTag = "NoBalloonCollision"
Config.BalloonInvisibleTransparencyMin = 1
Config.BalloonNoCollisionPaths = {
	"Game.Plots",
}

--// General
Config.MaxTotalBalloons = 50

--// Rod/rope rig — knot in air, multi knot attachments fan straps/rods, torso straps → knot
Config.BalloonStringKnotEnabled = true
Config.BalloonKnotMinBalloonCount = 5 -- 1–4 balloons: rods attach to torso hub (no BalloonStringKnot)
--[[ Knot Y from row-1 config height (not balloon spawn lower). Balloons lower separately via spawn lower keys. ]]
Config.BalloonKnotAboveRow1Studs = 1.04
Config.BalloonKnotExtraYOffsetStuds = -1.5 -- lowered by 3 studs from original 1.5
Config.BalloonKnotBackOffsetStuds = 0.12 -- extra Z from torso top-back hub anchor
Config.BalloonTorsoStrapSlackStuds = 0.35
Config.BalloonTorsoStrapSpreadStuds = 0.1 -- torso strap anchors spread on X
Config.BalloonTorsoStrapVisible = true
Config.BalloonFloatTorsoStrapTautSlackStuds = 0.02 -- torso→knot straps straight while balloon floating
--[[ Knot fan: local offsets on BalloonStringKnot (torso-aligned). Rods/straps pick by row/slot. ]]
Config.BalloonKnotAttachments = {
	{ name = "Center", position = Vector3.new(0, 0, 0) },
	{ name = "Back", position = Vector3.new(0, 0, 0.11) },
	{ name = "Front", position = Vector3.new(0, 0, -0.11) },
	{ name = "Left", position = Vector3.new(-0.1, 0, 0) },
	{ name = "Right", position = Vector3.new(0.1, 0, 0) },
	{ name = "Up", position = Vector3.new(0, 0.09, 0.05) },
}
Config.BalloonSpawnHeightLowerStuds = 1.2
Config.BalloonSpawnCloserToKnotStuds = 2 -- raises row spawn toward knot (shorter rods; knot stays independent)
-- Extra studs above torso hub (top-back anchor); ring Y = rodLength + this per row.
Config.BalloonSpawnAboveHubExtraStuds = 2.5
Config.BalloonDownAttachmentName = "DownAttachment"
Config.BalloonTorsoAnchorTopInsetStuds = 0.06 -- slightly below top edge
Config.BalloonTorsoAnchorTopBackInsetStuds = 0.08 -- slightly inside back face (upper back)
Config.BalloonSpawnRingRadiusStuds = 2.5 -- fallback when row omits ringRadiusStuds

--[[ Row layout (front → back): 6 / 8 / 10 balloons per ring, longer rods on outer rows.
	Index 1–6 → row 1, 7–14 → row 2, 15–24 → row 3; beyond that repeats last row size with +steps.
]]
Config.BalloonRows = {
	{ count = 4, rodLengthStuds = 7, rodLengthJitterStuds = 0.5, heightAboveRootStuds = 4, ringRadiusStuds = 3.4 },
	{ count = 6, rodLengthStuds = 9, rodLengthJitterStuds = 0.5, heightAboveRootStuds = 5.2, ringRadiusStuds = 3.8 },
	{ count = 6, rodLengthStuds = 11.5, rodLengthJitterStuds = 0.5, heightAboveRootStuds = 6.5, ringRadiusStuds = 4.4 },
}
Config.BalloonRowExtraCount = 10
Config.BalloonRowExtraRodStepStuds = 3
Config.BalloonRowExtraHeightStepStuds = 1.4
Config.BalloonRowExtraRadiusStepStuds = 0.35
Config.BalloonRowAngleStagger = true
Config.BalloonRopeLengthAboveRodStuds = 0.08
--[[ Rope visibility: row 1 = all slots except last (6→5 ropes).
	Row 2+ = rope on slot 1, +1 rope when row fills to slot (rowCount−1) e.g. 8-balloon row → slots 1 & 7. ]]

--// Rod limits & visuals (sweet spot: floaty but not wild)
Config.BalloonRodLimitsEnabled = true
Config.BalloonRodLimitAngle0NoKnot = 20
Config.BalloonRodLimitAngle0Knot = 25
Config.BalloonRodLimitAngle1 = 20
Config.BalloonRodVisible = false
Config.BalloonRodThicknessStuds = 0.08
Config.BalloonRigSpawnSettleSeconds = 1.25 -- calm physics + no hub sync right after rig build/join
--[[ TEST: true = keep balloons anchored at rod rest until full rig is built, then release together.
	Set false to restore per-balloon unanchor + spawn settle fly-in. ]]
Config.BalloonSpawnAtRodRestEnabled = true
Config.RopeThicknessStuds = 0.12

--[[ Client polish (gentle — no per-frame stiff damp, no PivotTo snap)
	Spin damp: pulse while idle only (~1s settle after you stop). Live tune via ReplicatedStorage attrs.
]]
Config.BalloonSpinDampEnabled = true
Config.BalloonSpinDampPerFrame = false
Config.BalloonSpinDampOnlyWhenIdle = true
Config.BalloonSpinDampMoveSpeedThreshold = 1.5
Config.BalloonSpinDampPerFrameFactor = 0.92
Config.BalloonSpinDampInterval = 0.12
Config.BalloonSpinDampAngularFactor = 0.7
Config.BalloonSpinDampStopRadPerSec = 0.55

--// Bleed twist spin around world Y only (no rotation snap)
Config.BalloonZeroYawSpin = true
Config.BalloonLockYawRotation = false -- true = hard-lock yaw via PivotTo (usually too stiff)

--[[ Floating balloons (hold jump) — factor = ReferenceBalloonCount / count on BOTH values.
	Per balloon: force = 140 × factor × massScale, density = 0.01 × factor.
	Total force = ReferenceBalloonCount × 140 × massScale (same fly power at any count for same body mass).
	massScale = playerBodyMass / BalloonFloatReferencePlayerMass (balloons excluded from mass).
]]
Config.BalloonLiftForceName = "BalloonLift"
Config.BalloonFloatMinBalloons = 1
Config.BalloonFloatNormalDensity = 0.0001
Config.BalloonFloatNormalLiftY = 1.45
Config.BalloonFloatHoldLiftPerBalloon = 72
Config.BalloonFloatReferenceBalloonCount = 50
--[[ Lift tuned for BalloonFloatReferencePlayerMass; other avatars scale force by (mass / reference).
	Body mass = HRP.AssemblyMass minus balloon rig parts in that assembly (rods may keep balloons separate).
	Reconciled with a part-mass catalog sum (excludes AttachedBalloons + knot); uses max if they diverge. ]]
Config.BalloonFloatReferencePlayerMass = 28.874
Config.BalloonFloatScaleLiftByPlayerMass = true
Config.BalloonFloatMassScaleMin = 0.12 -- allow light/headless avatars (old 0.45 was too high)
Config.BalloonFloatMassScaleMax = 4.0 -- heavy/custom avatars (was 2.5; capped lift too low for big bodies)
Config.BalloonFloatMassPartSumTolerance = 0.35 -- assembly vs part-sum reconcile (fractional delta)
Config.BalloonFloatMinBodyMassReady = 6 -- ignore assembly samples until body has at least this mass
Config.BalloonFloatMassStableFrames = 3 -- consecutive stable samples before trusting mass after join
Config.BalloonFloatMassStableTolerance = 0.08 -- max fractional change between samples to count as stable
Config.BalloonFloatClampLiftToWeight = true -- hold lift = bodyWeight × ratio (scales with every avatar)
Config.BalloonFloatHoldLiftWeightRatio = 1.02 -- used when velocity stabilize is off
Config.BalloonFloatHoldLiftStrength = 1
Config.BalloonFloatMaxRiseSpeed = 14
Config.BalloonFloatVelocityStabilizeEnabled = true
Config.BalloonFloatTargetRiseSpeed = 12
Config.BalloonFloatHoverLiftWeightRatio = 1.1
Config.BalloonFloatRigDragWeightRatio = 0.02
Config.BalloonFloatRiseResponse = 9
Config.BalloonFloatMaxRiseAccel = 14
Config.BalloonFloatOverspeedBuffer = 6
Config.BalloonFloatMinHoldLiftWeightRatio = 1.0
Config.BalloonFloatMinRiseSpeedMult = 0.55
Config.BalloonFloatRodExtraLengthStuds = 12
Config.BalloonFloatCentralizedLiftEnabled = true
Config.BalloonFloatHrpLiftAttachmentName = "BalloonFloatLiftAtt"
Config.BalloonFloatHrpLiftForceName = "BalloonFloatLift"
Config.BalloonFloatMasslessBalloonsWhileFloating = true
Config.BalloonFloatNoCollideWhileFloating = false
Config.BalloonFloatRelaxRodsWhileFloating = false
-- Follow hub welded to HRP; hold float lift on HRP only (balloons = gentle bob).
Config.BalloonFloatFollowPartName = "BalloonFloatFollow"
Config.BalloonFloatAnchorFolderName = "BalloonFloatAnchor"
Config.BalloonFloatClientVisualRodSnap = true
Config.BalloonFloatSyncBalloonHorizVelocity = true
-- Follow hub always welded to HRP. HRP does all hold lift; balloons keep gentle bob only.
Config.BalloonFloatFollowRigFloatBobMult = 0.12
Config.BalloonFloatFollowRigFloatStartDamp = 0.55
Config.BalloonFloatDampBalloonSwing = true
Config.BalloonFloatBalloonSwingDampFactor = 0.82
--[[ Release: ease lift off over ~half a second, then parachute glide. ]]
Config.BalloonFloatReleaseLiftBlendSeconds = 0.75
Config.BalloonFloatReleaseHoverWeightRatio = 0.88
Config.BalloonFloatReleaseMaxVy = 1.5
Config.BalloonFloatReleaseVyBleedRate = 18
--[[ Re-hold while falling: extra lift to catch + allow brief overshoot before stabilize. ]]
Config.BalloonFloatFallCatchVy = -1 -- scale catch strength from this fall speed downward
Config.BalloonFloatFallCatchForceBoost = 1.12
Config.BalloonFloatFallCatchExtraAccel = 18
Config.BalloonFloatRecoveryOverspeedBuffer = 16
--[[ Feel / juice — hold ramp, parachute glide, camera. ]]
Config.BalloonFloatAutoJumpOnHold = true
Config.BalloonFloatGroundPeelEnabled = true
Config.BalloonFloatGroundPeelVy = 16
Config.BalloonFloatGroundPeelMinVy = 5
Config.BalloonFloatHoldRampSeconds = 0.07
Config.BalloonFloatHoldRampStartBlend = 0.7
Config.BalloonFloatHoldLiftMinStrength = 0.45
Config.BalloonFloatStartRiseLerpRate = 36
Config.BalloonFloatReleaseEasePower = 1.4
Config.BalloonFloatParachuteEnabled = true
Config.BalloonFloatParachuteTerminalVy = -18
Config.BalloonFloatParachuteDrag = 22
Config.BalloonFloatParachuteLiftBlend = 0
Config.BalloonFloatFeelFovBoost = 8 -- FOV widen at full float
Config.BalloonFloatFeelFovParachute = 4 -- FOV while parachuting
Config.BalloonFloatFeelFovLerpRate = 10
Config.BalloonFloatCatchShakeIntensity = 0.28
Config.BalloonFloatCatchShakeFallVy = -14 -- min fall speed for big catch shake
Config.BalloonFloatReleaseShakeIntensity = 0.09 -- tiny pop when letting go mid-air
Config.BalloonPopSwingDampFactor = 0.68 -- damp remaining balloons on pop (no position snap)
Config.BalloonFloatGlideResponseScale = 0.55 -- softer PD when near target rise speed
Config.BalloonFloatFallVelocityThreshold = -2 -- Y velocity below this counts as falling
--[[ While floating: damp extra X/Z drift from balloon/rope swing (stronger at higher excess speed). ]]
Config.BalloonFloatHorizStabilizeEnabled = true
Config.BalloonFloatHorizMoveSpeedMultiplier = 1.28 -- horizontal walk speed while floating (hold jump only)
Config.BalloonFloatHorizMoveAccel = 52 -- studs/s² toward float move speed when holding WASD
Config.BalloonFloatFallHorizBleedEnabled = true -- bleed boosted X/Z speed after release while falling
Config.BalloonFloatFallHorizMaxMult = 1.05 -- max horizontal speed vs WalkSpeed during passive fall
Config.BalloonFloatFallHorizBleedRate = 16 -- how fast excess horizontal speed bleeds off
Config.BalloonFloatHorizStabilizeBaseRate = 12
Config.BalloonFloatHorizStabilizeSpeedScale = 0.4
Config.BalloonFloatHorizStabilizeIdleRate = 22
Config.BalloonFloatHorizStabilizeMinExcess = 0.35
Config.BalloonFloatHorizIdleStopRate = 34 -- kill X/Z drift while not moving (no minExcess gate)
Config.BalloonFloatHorizIdleStopSnap = 0.12 -- snap horizontal vel to 0 below this (studs/sec)
Config.BalloonFloatHorizIdleHardStop = true
Config.BalloonFloatHorizIdleSyncBalloons = true
--[[ Landing burst when fall distance since release >= MinFallStuds.
	Rock size + spread scale from min fall → MaxFallStuds (capped). ]]
Config.BalloonFloatLandingEffectMinFallStuds = 10
Config.BalloonFloatLandingEffectMaxFallStuds = 235 -- scale caps at/above this fall distance
Config.BalloonFloatLandingDebrisCount = 14
Config.BalloonFloatLandingRockScaleMin = 0.18
Config.BalloonFloatLandingRockScaleMax = .75
Config.BalloonFloatLandingRockScaleMinAtMaxFall = 0.42
Config.BalloonFloatLandingRockScaleMaxAtMaxFall = 1.22
Config.BalloonFloatLandingSpreadRadiusStuds = 2.7
Config.BalloonFloatLandingSpreadRadiusMaxStuds = 7.5
Config.BalloonFloatLandingRockMinSpacingStuds = 0.42
Config.BalloonFloatLandingRockMinSpacingMaxStuds = 0.58
Config.BalloonFloatLandingArcPeakY = 0.58
Config.BalloonFloatLandingArcPeakMaxY = 1.3
Config.BalloonFloatLandingArcEndY = -0.12
Config.BalloonFloatLandingArcEndMaxY = -0.28
Config.BalloonFloatLandingArcFadeBelowY = 0.1 -- fade fast once falling past this local Y
Config.BalloonFloatLandingArcDuration = 0.63
Config.BalloonFloatLandingArcFadeSpeed = 5 -- transparency/sec during fall fade
Config.BalloonFloatLandingRockFallSpeedMin = 1 -- normal drop speed multiplier
Config.BalloonFloatLandingRockFallSpeedMax = 1.65 -- faster droppers (fall phase only)
--[[ Camera shake scales with fall (MinFallStuds → MaxFallStuds), same intensity curve as rocks. ]]
Config.BalloonFloatLandingShakeIntensityMin = 0.19
Config.BalloonFloatLandingShakeIntensityMax = 0.9
Config.BalloonFloatLandingShakeDurationMin = 0.2
Config.BalloonFloatLandingShakeDurationMax = 0.55
Config.BalloonFloatLandingShakeFrequencyMin = 10
Config.BalloonFloatLandingShakeFrequencyMax = 18
Config.BalloonFloatLandingShakeFadeOutMin = 0.12
Config.BalloonFloatLandingShakeFadeOutMax = 0.26
Config.BalloonFloatLandingStabilizeSeconds = 0.22

function Config.number(key: string, fallback: number): number
	local v = Config[key]
	if type(v) == "number" and v == v then
		return v
	end
	return fallback
end

function Config.flag(key: string): boolean
	return Config[key] == true
end

function Config.vector3(key: string, fallback: Vector3): Vector3
	local v = Config[key]
	if typeof(v) == "Vector3" then
		return v
	end
	return fallback
end

return Config
