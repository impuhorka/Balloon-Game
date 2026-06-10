local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Modules.Settings.Shared_BoosterConfig)
local BalloonFloat = require(ReplicatedStorage.Modules.Gameplay.BalloonFloat)

local Module = {}

local CIRCLE_BLEND_ATTR = "CircleBoostBlend"
local CIRCLE_TIER_ATTR = "CircleBoostTier"

type CircleBinding = {
	part: BasePart,
	tier: string,
}

local circles: { CircleBinding } = {}
local lastTouchAt: { [Player]: { [BasePart]: number } } = setmetatable({}, { __mode = "k" })
local lastGlobalTouchAt: { [Player]: number } = setmetatable({}, { __mode = "k" })
local blendByPlayer: { [Player]: { blend: number, tier: string? } } = setmetatable({}, { __mode = "k" })

local function getTierDef(tier: string)
	if tier == "VIP" then
		return Config.VIP or {}
	end
	return Config.Normal or {}
end

local function resolveRoot(): Instance?
	local current: Instance = Workspace
	for _, name in Config.RootPath or { "Game", "Boosters" } do
		local child = current:FindFirstChild(name)
		if not child then
			child = current:WaitForChild(name, 30)
		end
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function prepareCirclePart(part: BasePart)
	part.CanTouch = true
	part.CanQuery = true
	if part:GetAttribute("BoostCirclePrepared") then
		return
	end
	part:SetAttribute("BoostCirclePrepared", true)
	part.CanCollide = false
end

local function hrpOverlapsCircle(hrp: BasePart, circle: BasePart): boolean
	local expand = Config.OverlapExpand or Vector3.new(3, 6, 3)
	local localPos = circle.CFrame:PointToObjectSpace(hrp.Position)
	local half = circle.Size * 0.5 + expand
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

local function resolveBoostDirection(hrp: BasePart, humanoid: Humanoid?, circle: BasePart): Vector3
	local vel = hrp.AssemblyLinearVelocity
	local horizontal = Vector3.new(vel.X, 0, vel.Z)
	if horizontal.Magnitude >= (Config.MinMoveSpeedForDir or 2.5) then
		return horizontal.Unit
	end

	if humanoid and humanoid.MoveDirection.Magnitude > 0.05 then
		local move = humanoid.MoveDirection
		return Vector3.new(move.X, 0, move.Z).Unit
	end

	local flatLook = circle.CFrame.LookVector
	flatLook = Vector3.new(flatLook.X, 0, flatLook.Z)
	if flatLook.Magnitude < 0.05 then
		flatLook = circle.CFrame.RightVector
		flatLook = Vector3.new(flatLook.X, 0, flatLook.Z)
	end
	if flatLook.Magnitude < 0.05 then
		return Vector3.new(0, 0, -1)
	end
	return flatLook.Unit
end

local function canUseVipCircle(player: Player): boolean
	return player:GetAttribute("HasVIP") == true
end

local function applyCircleBoost(player: Player, character: Model, circle: BasePart, tier: string)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end

	if tier == "VIP" and not canUseVipCircle(player) then
		return
	end

	local now = os.clock()
	local perPlayer = lastTouchAt[player]
	if not perPlayer then
		perPlayer = {}
		lastTouchAt[player] = perPlayer
	end

	local circleCooldown = Config.CooldownSeconds or 1.4
	if now - (perPlayer[circle] or 0) < circleCooldown then
		return
	end

	local globalCooldown = Config.GlobalCooldownSeconds or 0.35
	if now - (lastGlobalTouchAt[player] or 0) < globalCooldown then
		return
	end

	perPlayer[circle] = now
	lastGlobalTouchAt[player] = now

	local tierDef = getTierDef(tier)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local dir = resolveBoostDirection(hrp, humanoid, circle)
	local vel = hrp.AssemblyLinearVelocity
	local horizontal = Vector3.new(vel.X, 0, vel.Z)

	local launchVy = tierDef.VerticalLaunch or 54
	local minVy = tierDef.MinVerticalSpeed or 42
	local vy = math.max(vel.Y, 0) + launchVy
	vy = math.max(vy, minVy)

	local horizBoost = tierDef.HorizontalBoost or 16
	local newHorizontal = horizontal + dir * horizBoost

	hrp.AssemblyLinearVelocity = Vector3.new(newHorizontal.X, vy, newHorizontal.Z)

	local state = blendByPlayer[player]
	if not state then
		state = { blend = 0, tier = nil }
		blendByPlayer[player] = state
	end
	state.blend = 1
	state.tier = tier
	character:SetAttribute(CIRCLE_BLEND_ATTR, 1)
	character:SetAttribute(CIRCLE_TIER_ATTR, tier)
end

local function bindCircle(part: BasePart, tier: string)
	prepareCirclePart(part)
	table.insert(circles, { part = part, tier = tier })
end

local function scanFolder(folder: Instance, tier: string)
	for _, desc in folder:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name == (Config.CirclePartName or "BoostCircle") then
			bindCircle(desc, tier)
		end
	end
	folder.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") and desc.Name == (Config.CirclePartName or "BoostCircle") then
			bindCircle(desc, tier)
		end
	end)
end

local function tickOverlap()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then
			continue
		end

		for _, binding in circles do
			local part = binding.part
			if part.Parent and hrpOverlapsCircle(hrp, part) then
				applyCircleBoost(player, character, part, binding.tier)
			end
		end
	end
end

local function tickBlends(dt: number)
	local fadeOut = math.max(0.05, Config.BlendFadeOutSeconds or 1.6)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local state = blendByPlayer[player]
		if not state or state.blend <= 0 then
			if character and character:GetAttribute(CIRCLE_BLEND_ATTR) then
				character:SetAttribute(CIRCLE_BLEND_ATTR, nil)
				character:SetAttribute(CIRCLE_TIER_ATTR, nil)
			end
			continue
		end

		state.blend = math.max(0, state.blend - dt / fadeOut)
		if character then
			if state.blend > 0 then
				character:SetAttribute(CIRCLE_BLEND_ATTR, state.blend)
				if state.tier then
					character:SetAttribute(CIRCLE_TIER_ATTR, state.tier)
				end
			else
				character:SetAttribute(CIRCLE_BLEND_ATTR, nil)
				character:SetAttribute(CIRCLE_TIER_ATTR, nil)
				state.tier = nil
			end
		end
	end
end

function Module.GetCircleFloatLiftBonus(character: Model?): number
	if not character then
		return 0
	end
	local blend = tonumber(character:GetAttribute(CIRCLE_BLEND_ATTR)) or 0
	if blend <= 0 then
		return 0
	end
	local tier = character:GetAttribute(CIRCLE_TIER_ATTR)
	local tierDef = getTierDef(if type(tier) == "string" then tier else "Normal")
	return (tierDef.FloatLiftMultBonus or 0.22) * blend
end

function Module:OnPreSimulation(dt: number)
	tickOverlap()
	tickBlends(dt)
end

function Module:Init()
	Players.PlayerRemoving:Connect(function(player)
		lastTouchAt[player] = nil
		lastGlobalTouchAt[player] = nil
		blendByPlayer[player] = nil
	end)

	task.spawn(function()
		local root = resolveRoot()
		if not root then
			warn("[Server_BoostCircles] Missing Workspace." .. table.concat(Config.RootPath or {}, "."))
			return
		end

		local normal = root:FindFirstChild("Normal")
		local vip = root:FindFirstChild("VIP")
		if normal then
			scanFolder(normal, "Normal")
		end
		if vip then
			scanFolder(vip, "VIP")
		end

		if #circles == 0 then
			warn("[Server_BoostCircles] No BoostCircle parts found under " .. root:GetFullName())
		end
	end)
end

return Module
