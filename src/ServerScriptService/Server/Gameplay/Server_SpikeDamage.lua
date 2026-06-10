local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Modules.ItemConfigs.BalloonConfig)
local BalloonRigKit = require(ReplicatedStorage.Modules.Gameplay.BalloonRigKit)
local Server_Balloon = require(script.Parent.Server_Balloon)

local Module = {}

local SPIKES_FOLDER_NAME = "Spikes"
local SPIKE_MODEL_NAME = "SpikeDamage"
local TOP_PART_NAME = "Top"
local SPIKE_TAG = "BalloonSpikeDamage"
local SPIKE_COLLISION_GROUP = "SpikeDamage"
local DAMAGE_COOLDOWN = 1
local CHECK_INTERVAL = 0.1

local hookedTops: { [BasePart]: boolean } = {}
local spikeTops: { BasePart } = {}
local lastDamageAt: { [Model]: number } = setmetatable({}, { __mode = "k" })
local damageLock: { [Model]: boolean } = {}
local lastOverlapCheck = 0

local function ensureSpikeCollisionGroup()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(SPIKE_COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(SPIKE_COLLISION_GROUP, Config.BalloonCollisionGroup or "Balloons", true)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(SPIKE_COLLISION_GROUP, "Default", true)
	end)
end

local function getBalloonFromPart(part: BasePart): Model?
	return BalloonRigKit.getBalloonModelFromPart(part)
end

local function trySpikeDamage(balloonModel: Model)
	if damageLock[balloonModel] then
		return
	end

	local now = os.clock()
	local last = lastDamageAt[balloonModel] or 0
	if now - last < DAMAGE_COOLDOWN then
		return
	end

	damageLock[balloonModel] = true
	local ok = Server_Balloon.damageBalloonFromSpike(balloonModel)
	damageLock[balloonModel] = nil
	if ok then
		lastDamageAt[balloonModel] = now
	end
end

local function balloonOverlapsTop(balloonModel: Model, top: BasePart): boolean
	local part = balloonModel.PrimaryPart
	if not part or not part:IsA("BasePart") then
		part = balloonModel:FindFirstChildWhichIsA("BasePart", true)
	end
	if not part then
		return false
	end

	local localPos = top.CFrame:PointToObjectSpace(part.Position)
	local pad = part.Size * 0.5
	local half = top.Size * 0.5 + pad
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

local function scanBalloonsOnTop(top: BasePart)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end

		local folder = BalloonRigKit.resolveBalloonsFolder(character)
		if not folder then
			continue
		end

		for _, child in folder:GetChildren() do
			if child:IsA("Model") and balloonOverlapsTop(child, top) then
				trySpikeDamage(child)
			end
		end
	end
end

local function hookTop(top: BasePart)
	if hookedTops[top] then
		return
	end
	hookedTops[top] = true
	table.insert(spikeTops, top)

	top.CanCollide = true
	top.CanTouch = true
	top.CanQuery = true
	top.CollisionGroup = SPIKE_COLLISION_GROUP
	CollectionService:AddTag(top, SPIKE_TAG)

	top.Touched:Connect(function(hit)
		if not hit or not hit:IsA("BasePart") then
			return
		end
		local balloonModel = getBalloonFromPart(hit)
		if balloonModel then
			trySpikeDamage(balloonModel)
		end
	end)
end

local function hookSpikeModel(model: Model)
	if model.Name ~= SPIKE_MODEL_NAME then
		return
	end
	local top = model:FindFirstChild(TOP_PART_NAME, true)
	if top and top:IsA("BasePart") then
		hookTop(top)
	end
end

local function scanSpikes(root: Instance)
	for _, desc in root:GetDescendants() do
		if desc:IsA("Model") and desc.Name == SPIKE_MODEL_NAME then
			hookSpikeModel(desc)
		end
	end
	root.DescendantAdded:Connect(function(desc)
		if desc:IsA("Model") and desc.Name == SPIKE_MODEL_NAME then
			hookSpikeModel(desc)
		elseif desc:IsA("BasePart") and desc.Name == TOP_PART_NAME then
			local model = desc:FindFirstAncestorOfClass("Model")
			if model and model.Name == SPIKE_MODEL_NAME then
				hookTop(desc)
			end
		end
	end)
end

function Module:Init()
	ensureSpikeCollisionGroup()

	local spikes = workspace:WaitForChild(SPIKES_FOLDER_NAME, 30)
	if not spikes then
		warn("[Server_SpikeDamage] Missing workspace.Spikes")
		return
	end
	scanSpikes(spikes)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastOverlapCheck < CHECK_INTERVAL then
			return
		end
		lastOverlapCheck = now

		for index = #spikeTops, 1, -1 do
			local top = spikeTops[index]
			if not top.Parent then
				table.remove(spikeTops, index)
				hookedTops[top] = nil
			else
				scanBalloonsOnTop(top)
			end
		end
	end)
end

return Module
