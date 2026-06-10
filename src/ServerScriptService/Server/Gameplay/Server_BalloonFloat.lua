--// Server_BalloonFloat — hold jump + server float physics.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BalloonFloat = require(ReplicatedStorage.Modules.Gameplay.BalloonFloat)
local Config = require(ReplicatedStorage.Modules.ItemConfigs.BalloonConfig)
local Server_Propeler = require(script.Parent.Server_Propeler)
local Server_BoostCircles = require(script.Parent.Server_BoostCircles)

local Module = {}
local RISE_ROD_ANGLE_FACTOR = 0.7

type FloatState = {
	liftBlend: number,
	holdRampElapsed: number,
	releasing: boolean,
	releaseFadeElapsed: number,
	releaseStartBlend: number,
	floatAirSession: boolean,
	prevHold: boolean,
	wasFloating: boolean,
}

local floatStateByPlayer: { [Player]: FloatState } = setmetatable({}, { __mode = "k" })

local function getState(player: Player): FloatState
	local st = floatStateByPlayer[player]
	if not st then
		local base = BalloonFloat.newLiftBlendState()
		st = base :: FloatState
		st.wasFloating = false
		floatStateByPlayer[player] = st
	end
	return st
end

local function resetState(player: Player)
	floatStateByPlayer[player] = nil
end

local function setRodAnglesForVerticalState(character: Model, rising: boolean)
	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if not folder then
		return
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			for _, inst in child:GetDescendants() do
				if inst:IsA("RodConstraint") and inst.Name == "BalloonRod" then
					if rising then
						if inst:GetAttribute("_RiseOrigAngle0") == nil then
							inst:SetAttribute("_RiseOrigAngle0", inst.LimitAngle0)
						end
						if inst:GetAttribute("_RiseOrigAngle1") == nil then
							inst:SetAttribute("_RiseOrigAngle1", inst.LimitAngle1)
						end
						local baseA0 = tonumber(inst:GetAttribute("_RiseOrigAngle0")) or inst.LimitAngle0
						local baseA1 = tonumber(inst:GetAttribute("_RiseOrigAngle1")) or inst.LimitAngle1
						inst.LimitAngle0 = baseA0 * RISE_ROD_ANGLE_FACTOR
						inst.LimitAngle1 = baseA1 * RISE_ROD_ANGLE_FACTOR
					else
						local origA0 = tonumber(inst:GetAttribute("_RiseOrigAngle0"))
						local origA1 = tonumber(inst:GetAttribute("_RiseOrigAngle1"))
						if origA0 then
							inst.LimitAngle0 = origA0
						end
						if origA1 then
							inst.LimitAngle1 = origA1
						end
					end
				end
			end
		end
	end
end

local function tickPlayerFloat(player: Player, dt: number)
	local character = player.Character
	if not character then
		return
	end

	local st = getState(player)
	local zoneActive = character:GetAttribute("PropelerZoneActive") == true
	local manualHold = character:GetAttribute(BalloonFloat.HOLD_ATTR) == true
	local wantHold = manualHold or zoneActive
	local propBlend = tonumber(character:GetAttribute("PropelerBoostBlend")) or 0
	local count = BalloonFloat.getEquippedCount(character)
	local minBalloons = Config.number("BalloonFloatMinBalloons", 1)

	if count < minBalloons then
		BalloonFloat.exitFloatRigIsolation(character)
		if st.wasFloating or st.liftBlend > 0 then
			BalloonFloat.landFloatPhysics(character)
		end
		Server_Propeler.ClearPlayerBoost(character)
		st.liftBlend = 0
		st.releasing = false
		st.wasFloating = false
		st.floatAirSession = false
		st.prevHold = wantHold
		return
	end

	if BalloonFloat.hasMinimumBodyLoaded(character) and not BalloonFloat.isRigSettling(character) then
		BalloonFloat.syncMassAttributes(character)
	end

	if not BalloonFloat.isRigSettling(character) then
		BalloonFloat.ensureBalloonFollowRig(character)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and not root:IsA("BasePart") then
		root = nil
	end

	local settling = BalloonFloat.isRigSettling(character)
	local airborne = BalloonFloat.isFloatAirborne(humanoid, root, wantHold, st.floatAirSession, st.liftBlend)
	local fallCatch = wantHold and airborne and root ~= nil and root.AssemblyLinearVelocity.Y < 0

	local blend = BalloonFloat.tickLiftBlendState(st, dt, {
		wantHold = wantHold,
		airborne = airborne,
		settling = settling,
		humanoid = humanoid,
		root = root,
		resetFloatAirSessionOnLand = true,
	})

	local isFloating = blend > 0.01 and (wantHold or not airborne)
	local justStartedFloat = isFloating and not st.wasFloating
	if st.wasFloating and not isFloating and not airborne then
		BalloonFloat.landFloatPhysics(character)
		Server_Propeler.ClearPlayerBoost(character)
	end
	st.wasFloating = isFloating

	local liftMult = Server_Propeler.GetFloatLiftMult(propBlend, manualHold)
	liftMult *= 1 + Server_BoostCircles.GetCircleFloatLiftBonus(character)

	local folder = BalloonFloat.resolveBalloonsFolder(character)
	if folder then
		local applied = BalloonFloat.applyFloatBlendToFolder(folder, blend, count, character, {
			wantHold = wantHold,
			onGround = not airborne and not wantHold,
			fallCatch = fallCatch,
			liftMult = liftMult,
			manualHold = manualHold,
			propBlend = propBlend,
		})
		character:SetAttribute(BalloonFloat.ACTIVE_ATTR, applied > 0 and blend > 0.01)
	else
		BalloonFloat.clearHrpFloatLift(character)
	end

	local isolated = BalloonFloat.isFloatRigIsolated(character)
	if isolated then
		BalloonFloat.ensureFollowRigWeld(character)
		if justStartedFloat then
			BalloonFloat.softenFollowRigBalloons(character)
		end
	end

	local inAirLift = blend > 0.01 and airborne
	local isRising = root and root.AssemblyLinearVelocity.Y > 0.5
	if not isolated then
		setRodAnglesForVerticalState(character, isRising == true)
	end
	if root and inAirLift and isFloating and not isolated then
		if not wantHold and st.releasing then
			BalloonFloat.bleedReleaseUpwardVelocity(root, blend, dt)
		end

		local moving = humanoid and humanoid.MoveDirection.Magnitude > 0.05
		BalloonFloat.syncFloatBalloonHorizontalToRoot(character, root, moving)
		BalloonFloat.dampFloatingBalloonSwing(character, blend, not moving)

		local cap = BalloonFloat.computeFloatRiseCap(character, blend, manualHold)
		BalloonFloat.bleedFloatRiseToCap(root, cap, dt)
	elseif root and inAirLift and isFloating and isolated then
		local cap = BalloonFloat.computeFloatRiseCap(character, blend, manualHold)
		BalloonFloat.bleedFloatRiseToCap(root, cap, dt)
	elseif root and not wantHold and airborne and not isolated and Config.flag("BalloonFloatParachuteEnabled") then
		BalloonFloat.applyParachuteFall(character, root, dt, blend, count)
	elseif propBlend <= 0 and not zoneActive then
		Server_Propeler.ClearPlayerBoost(character)
	end
end

function Module:Init()
	local events = ReplicatedStorage:WaitForChild("Events")
	local handler = events:WaitForChild("BalloonFloatHandler")

	handler.OnServerEvent:Connect(function(player: Player, action: any, holding: any)
		if action ~= "Hold" or type(holding) ~= "boolean" then
			return
		end
		local character = player.Character
		if not character then
			return
		end
		character:SetAttribute(BalloonFloat.HOLD_ATTR, holding)
		if not holding then
			character:SetAttribute(BalloonFloat.ACTIVE_ATTR, false)
		end
	end)

	local function hookPlayer(player: Player)
		resetState(player)
		player.CharacterAdded:Connect(function(character)
			resetState(player)
			character:SetAttribute(BalloonFloat.HOLD_ATTR, false)
			character:SetAttribute(BalloonFloat.ACTIVE_ATTR, false)
			character:SetAttribute("PropelerZoneActive", nil)
			character:SetAttribute("PropelerBoostBlend", nil)
			BalloonFloat.clearMassState(character)
			BalloonFloat.exitFloatRigIsolation(character)
			setRodAnglesForVerticalState(character, false)
		end)
		player.CharacterRemoving:Connect(function()
			resetState(player)
		end)
	end

	Players.PlayerRemoving:Connect(resetState)
	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end

	RunService.PreSimulation:Connect(function(dt)
		Server_Propeler:OnPreSimulation(dt)
		Server_BoostCircles:OnPreSimulation(dt)
		for _, player in Players:GetPlayers() do
			tickPlayerFloat(player, dt)
		end
	end)
end

return Module
