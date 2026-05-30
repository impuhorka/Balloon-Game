--// Server_BalloonFloat — hold jump + server float physics.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BalloonFloat = require(ReplicatedStorage.Modules.Gameplay.BalloonFloat)
local Config = require(ReplicatedStorage.Modules.ItemConfigs.BalloonConfig)

local Module = {}

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

local floatStateByPlayer: { [Player]: FloatState } = {}

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

local function tickPlayerFloat(player: Player, dt: number)
	local character = player.Character
	if not character then
		return
	end

	local st = getState(player)
	local wantHold = character:GetAttribute(BalloonFloat.HOLD_ATTR) == true
	local count = BalloonFloat.getEquippedCount(character)
	local minBalloons = Config.number("BalloonFloatMinBalloons", 1)

	if count < minBalloons then
		if st.wasFloating or st.liftBlend > 0 then
			BalloonFloat.landFloatPhysics(character)
		end
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
	if st.wasFloating and not isFloating and not airborne then
		BalloonFloat.landFloatPhysics(character)
	end
	st.wasFloating = isFloating

	local folder = character:FindFirstChild(BalloonFloat.ATTACHED_BALLOONS_FOLDER)
	if folder and folder:IsA("Folder") then
		local applied = BalloonFloat.applyFloatBlendToFolder(folder, blend, count, character, {
			wantHold = wantHold,
			onGround = not airborne and not wantHold,
			fallCatch = fallCatch,
		})
		character:SetAttribute(BalloonFloat.ACTIVE_ATTR, applied > 0 and blend > 0.01)
	else
		BalloonFloat.clearHrpFloatLift(character)
	end

	local inAirLift = blend > 0.01 and airborne
	if root and inAirLift then
		if not wantHold and st.releasing then
			BalloonFloat.bleedReleaseUpwardVelocity(root, blend, dt)
		end
		if isFloating then
			local moving = humanoid and humanoid.MoveDirection.Magnitude > 0.05
			BalloonFloat.syncFloatBalloonHorizontalToRoot(character, root, moving)
			BalloonFloat.dampFloatingBalloonSwing(character, blend, not moving)
			BalloonFloat.enforceFloatRiseSpeedCap(root, blend)
		end
	elseif root and not wantHold and airborne and Config.flag("BalloonFloatParachuteEnabled") then
		BalloonFloat.applyParachuteFall(character, root, dt, blend, count)
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
			BalloonFloat.clearMassState(character)
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
		for _, player in Players:GetPlayers() do
			tickPlayerFloat(player, dt)
		end
	end)
end

return Module
