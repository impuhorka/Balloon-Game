--// BalloonInvisibleCollision — balloons pass through configured paths, tagged parts, and invisible world.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")

local Config = require(script.Parent.Parent.ItemConfigs.BalloonConfig)

local BalloonInvisibleCollision = {}

local ATTACHED_BALLOONS_FOLDER = "AttachedBalloons"
local KNOT_PART_NAME = "BalloonStringKnot"

local originalGroups: { [BasePart]: string } = {}
local transparencyConns: { [BasePart]: RBXScriptConnection } = {}
local noCollisionRoots: { [Instance]: boolean } = {}
local watching = false

local function balloonGroupName(): string
	return Config.BalloonCollisionGroup or "Balloons"
end

local function invisibleGroupName(): string
	return Config.BalloonInvisibleCollisionGroup or "InvisibleColliders"
end

local function noCollisionTagName(): string
	return Config.BalloonNoCollisionTag or "NoBalloonCollision"
end

local function invisibleTransparencyMin(): number
	return Config.number("BalloonInvisibleTransparencyMin", 1)
end

local function getNoCollisionPaths(): { string }
	local paths = Config.BalloonNoCollisionPaths
	if type(paths) ~= "table" then
		return {}
	end
	return paths
end

local function resolveWorkspacePath(path: string): Instance?
	local current: Instance = workspace
	for segment in string.gmatch(path, "[^%.]+") do
		local child = current:FindFirstChild(segment)
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function isUnderNoCollisionRoot(part: BasePart): boolean
	for root, _ in noCollisionRoots do
		if part:IsDescendantOf(root) then
			return true
		end
	end
	return false
end

local function isSpikeDamageTop(part: BasePart): boolean
	if CollectionService:HasTag(part, "BalloonSpikeDamage") then
		return true
	end
	if part.Name ~= "Top" then
		return false
	end
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model.Name == "SpikeDamage"
end

local function isBalloonRigPart(part: BasePart): boolean
	if part.CollisionGroup == balloonGroupName() then
		return true
	end

	if part.Name == KNOT_PART_NAME then
		return true
	end

	local current: Instance? = part
	while current do
		if current:IsA("Folder") and current.Name == ATTACHED_BALLOONS_FOLDER then
			return true
		end
		current = current.Parent
	end

	return false
end

local function shouldAvoidBalloonCollision(part: BasePart): boolean
	if isBalloonRigPart(part) then
		return false
	end

	if CollectionService:HasTag(part, noCollisionTagName()) then
		return true
	end

	if isUnderNoCollisionRoot(part) then
		return true
	end

	local current: Instance? = part.Parent
	while current do
		if CollectionService:HasTag(current, noCollisionTagName()) then
			return true
		end
		current = current.Parent
	end

	return part.Transparency >= invisibleTransparencyMin()
end

local function restorePart(part: BasePart)
	local previous = originalGroups[part]
	if previous then
		part.CollisionGroup = previous
		originalGroups[part] = nil
	end
end

local function applyPart(part: BasePart)
	if not part:IsA("BasePart") or isBalloonRigPart(part) or isSpikeDamageTop(part) then
		return
	end

	if shouldAvoidBalloonCollision(part) then
		if originalGroups[part] == nil then
			originalGroups[part] = part.CollisionGroup
		end
		part.CollisionGroup = invisibleGroupName()
	else
		restorePart(part)
	end
end

local function bindTransparency(part: BasePart)
	if transparencyConns[part] then
		return
	end

	transparencyConns[part] = part:GetPropertyChangedSignal("Transparency"):Connect(function()
		applyPart(part)
	end)
end

local function unbindPart(part: BasePart)
	local conn = transparencyConns[part]
	if conn then
		conn:Disconnect()
		transparencyConns[part] = nil
	end
	restorePart(part)
end

local function scanInstance(root: Instance)
	if root:IsA("BasePart") then
		bindTransparency(root)
		applyPart(root)
	end

	for _, desc in root:GetDescendants() do
		if desc:IsA("BasePart") then
			bindTransparency(desc)
			applyPart(desc)
		end
	end
end

local function bindNoCollisionRoot(root: Instance)
	if noCollisionRoots[root] then
		return
	end
	noCollisionRoots[root] = true
	scanInstance(root)
	root.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			bindTransparency(desc)
			applyPart(desc)
		end
	end)
end

local function bindNoCollisionPath(path: string)
	local root = resolveWorkspacePath(path)
	if root then
		bindNoCollisionRoot(root)
		return
	end

	task.spawn(function()
		local current: Instance = workspace
		for segment in string.gmatch(path, "[^%.]+") do
			local child = current:WaitForChild(segment, 60)
			if not child then
				return
			end
			current = child
		end
		bindNoCollisionRoot(current)
	end)
end

local function bindNoCollisionPaths()
	for _, path in getNoCollisionPaths() do
		if type(path) == "string" and path ~= "" then
			bindNoCollisionPath(path)
		end
	end
end

function BalloonInvisibleCollision.registerPhysicsGroups()
	local balloonGroup = balloonGroupName()
	local invisibleGroup = invisibleGroupName()
	local playerGroup = Config.PlayerCollisionGroup or "Players"

	pcall(function()
		PhysicsService:RegisterCollisionGroup(invisibleGroup)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(balloonGroup, invisibleGroup, false)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(invisibleGroup, "Default", true)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(invisibleGroup, playerGroup, true)
	end)
end

function BalloonInvisibleCollision.startWatching(workspaceRoot: Instance?)
	if watching then
		return
	end
	watching = true

	local root = workspaceRoot or workspace
	local tag = noCollisionTagName()

	bindNoCollisionPaths()
	scanInstance(root)

	root.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			bindTransparency(desc)
			applyPart(desc)
		end
	end)

	root.DescendantRemoving:Connect(function(desc)
		if desc:IsA("BasePart") then
			unbindPart(desc)
		end
	end)

	for _, inst in CollectionService:GetTagged(tag) do
		scanInstance(inst)
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		scanInstance(inst)
	end)

	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		if inst:IsA("BasePart") then
			applyPart(inst)
		else
			for _, desc in inst:GetDescendants() do
				if desc:IsA("BasePart") then
					applyPart(desc)
				end
			end
		end
	end)
end

return BalloonInvisibleCollision
