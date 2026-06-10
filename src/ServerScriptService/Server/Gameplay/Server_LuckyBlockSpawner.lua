local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared_LuckyBlocks = require(ReplicatedStorage.Modules.ItemConfigs.Shared_LuckyBlocks)
local Shared_Zones = require(ReplicatedStorage.Modules.Gameplay.Shared_Zones)
local Server_BrainrotSpawner = require(script.Parent.Server_BrainrotSpawner)

local Module = {}

local REFRESH_SECONDS = 3
local RESPAWN_COOLDOWN_MIN = 15
local RESPAWN_COOLDOWN_MAX = 20

local pendingRespawn = {}

local function parseZoneId(name)
	local n = string.match(name, "[Zz]one%s*(%d+)") or string.match(name, "^(%d+)$")
	if n then
		return tonumber(n)
	end
	return nil
end

local function ensureLuckyBlocksFolder()
	local gameFolder = Workspace:FindFirstChild("Game")
	if not gameFolder then
		return nil
	end

	local luckyBlocksFolder = gameFolder:FindFirstChild("LuckyBlocks")
	if luckyBlocksFolder and luckyBlocksFolder:IsA("Folder") then
		return luckyBlocksFolder
	end

	luckyBlocksFolder = Instance.new("Folder")
	luckyBlocksFolder.Name = "LuckyBlocks"
	luckyBlocksFolder.Parent = gameFolder
	return luckyBlocksFolder
end

local function ensureUID(inst, attributeName)
	local uid = inst:GetAttribute(attributeName)
	if type(uid) == "string" and uid ~= "" then
		return uid
	end
	uid = HttpService:GenerateGUID(false)
	inst:SetAttribute(attributeName, uid)
	return uid
end

local function getZoneIdForInstance(inst, spawnsRoot)
	local node = inst
	while node and node ~= spawnsRoot do
		local parent = node.Parent
		if parent == spawnsRoot then
			return parseZoneId(node.Name) or 1
		end
		node = parent
	end
	return 1
end

local function isSpawnAreasContainer(inst)
	return (inst:IsA("Model") or inst:IsA("Folder")) and string.lower(inst.Name) == "spawnareas"
end

local function isInsideSpawnAreasContainer(inst, spawnsRoot)
	local node = inst.Parent
	while node and node ~= spawnsRoot do
		if isSpawnAreasContainer(node) then
			return true
		end
		node = node.Parent
	end
	return false
end

local function collectSpawnAreaParts(container)
	local parts = {}
	for _, desc in ipairs(container:GetDescendants()) do
		if desc:IsA("BasePart") and string.lower(desc.Name) == "spawnarea" then
			table.insert(parts, desc)
		end
	end
	return parts
end

local function collectUnits(spawnsRoot)
	local units = {}

	for _, desc in ipairs(spawnsRoot:GetDescendants()) do
		if isSpawnAreasContainer(desc) then
			local parts = collectSpawnAreaParts(desc)
			if #parts > 0 then
				table.insert(units, {
					key = ensureUID(desc, "SpawnerGroupUID"),
					zoneId = getZoneIdForInstance(desc, spawnsRoot),
					parts = parts,
					isGroup = true,
				})
			end
		end
	end

	for _, desc in ipairs(spawnsRoot:GetDescendants()) do
		if desc:IsA("BasePart") and string.lower(desc.Name) == "spawnarea" and not isInsideSpawnAreasContainer(desc, spawnsRoot) then
			table.insert(units, {
				key = ensureUID(desc, "SpawnerPartUID"),
				zoneId = getZoneIdForInstance(desc, spawnsRoot),
				parts = { desc },
				isGroup = false,
			})
		end
	end

	return units
end

local function pickPartForUnit(unit)
	if #unit.parts == 0 then
		return nil
	end
	if not unit.isGroup then
		return unit.parts[1]
	end
	return unit.parts[math.random(1, #unit.parts)]
end

local function hasAnyBasePart(inst)
	if inst:IsA("BasePart") then
		return true
	end
	return inst:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

local function rollConfig(zoneId)
	local zoneConfig = Shared_Zones.List[zoneId] or Shared_Zones.List[1]
	if not zoneConfig or type(zoneConfig.LuckyBlockChances) ~= "table" then
		return "CommonLuckyBlock"
	end

	local total = 0
	for configName, weight in pairs(zoneConfig.LuckyBlockChances) do
		if type(weight) == "number" and weight > 0 and Shared_LuckyBlocks.List[configName] then
			total = total + weight
		end
	end
	if total <= 0 then
		return "CommonLuckyBlock"
	end

	local roll = math.random() * total
	local cumulative = 0
	for configName, weight in pairs(zoneConfig.LuckyBlockChances) do
		if type(weight) == "number" and weight > 0 and Shared_LuckyBlocks.List[configName] then
			cumulative = cumulative + weight
			if roll <= cumulative then
				return configName
			end
		end
	end
	return "CommonLuckyBlock"
end

local function pickTemplateForZone(luckyBlockAssets, zoneId)
	local rolledName = rollConfig(zoneId)
	local rolledTemplate = luckyBlockAssets:FindFirstChild(rolledName)
	if rolledTemplate and hasAnyBasePart(rolledTemplate) then
		return rolledName, rolledTemplate
	end

	local commonTemplate = luckyBlockAssets:FindFirstChild("CommonLuckyBlock")
	if commonTemplate and hasAnyBasePart(commonTemplate) then
		return "CommonLuckyBlock", commonTemplate
	end

	for configName in pairs(Shared_LuckyBlocks.List) do
		local template = luckyBlockAssets:FindFirstChild(configName)
		if template and hasAnyBasePart(template) then
			return configName, template
		end
	end

	return nil, nil
end

local function hasLuckyBlockForUnit(unitKey)
	local luckyBlocksFolder = ensureLuckyBlocksFolder()
	if not luckyBlocksFolder then
		return false
	end
	for _, child in ipairs(luckyBlocksFolder:GetChildren()) do
		if child:GetAttribute("SpawnerUnitKey") == unitKey then
			return true
		end
	end
	return false
end

local function getSpawnPoint(part)
	local halfX = part.Size.X * 0.5
	local halfZ = part.Size.Z * 0.5
	local offsetX = (math.random() * 2 - 1) * halfX
	local offsetZ = (math.random() * 2 - 1) * halfZ
	local localPoint = Vector3.new(offsetX, part.Size.Y * 0.5, offsetZ)
	return part.CFrame:PointToWorldSpace(localPoint)
end

local function spawnOnUnit(unit)
	if pendingRespawn[unit.key] then
		return false
	end

	local spawnPart = pickPartForUnit(unit)
	if not spawnPart or spawnPart.Parent == nil then
		return false
	end

	if hasLuckyBlockForUnit(unit.key) then
		return false
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local luckyBlockAssets = assets and assets:FindFirstChild("LuckyBlocks")
	if not luckyBlockAssets then
		warn("[Server_LuckyBlockSpawner] Assets.LuckyBlocks missing")
		return false
	end

	local configName, template = pickTemplateForZone(luckyBlockAssets, unit.zoneId)
	if not template then
		warn("[Server_LuckyBlockSpawner] No spawnable lucky block models found in Assets.LuckyBlocks")
		return false
	end

	local point = getSpawnPoint(spawnPart)
	local uid = Server_BrainrotSpawner:SpawnLuckyBlock(configName, spawnPart, {
		position = point,
		spawnerPart = spawnPart,
		spawnerUnitKey = unit.key,
		zoneTag = ("Zone%d"):format(unit.zoneId),
		holdDuration = 1,
		onCollected = function()
			if pendingRespawn[unit.key] then
				return
			end
			pendingRespawn[unit.key] = true
			local cooldown = math.random(RESPAWN_COOLDOWN_MIN, RESPAWN_COOLDOWN_MAX)
			task.delay(cooldown, function()
				pendingRespawn[unit.key] = nil
				spawnOnUnit(unit)
			end)
		end,
	})

	return uid ~= nil
end

local function clearExistingLuckyBlocks()
	local luckyBlocksFolder = ensureLuckyBlocksFolder()
	if not luckyBlocksFolder then
		return
	end
	for _, child in ipairs(luckyBlocksFolder:GetChildren()) do
		child:Destroy()
	end
end

local function fillAll(spawnsRoot)
	local units = collectUnits(spawnsRoot)
	for _, unit in ipairs(units) do
		spawnOnUnit(unit)
	end
end

local function runLoop(spawnsRoot)
	while true do
		fillAll(spawnsRoot)
		task.wait(REFRESH_SECONDS)
	end
end

function Module:Init()
	local gameFolder = Workspace:WaitForChild("Game", 120)
	if not gameFolder then
		warn("[Server_LuckyBlockSpawner] workspace.Game missing")
		return
	end

	local spawnsRoot = gameFolder:WaitForChild("Spawns", 120)
	if not spawnsRoot then
		warn("[Server_LuckyBlockSpawner] workspace.Game.Spawns missing")
		return
	end

	clearExistingLuckyBlocks()
	task.spawn(function()
		runLoop(spawnsRoot)
	end)
end

return Module
