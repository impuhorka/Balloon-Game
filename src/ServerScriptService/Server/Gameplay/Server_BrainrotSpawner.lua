--// Server_BrainrotSpawner - Professional brainrot world spawning system
--// Spawns brainrots in zones, handles pickup, holding, dropping, and collection

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local Server_Data = require(script.Parent.Parent.Core.Server_Data)
local Server_Inventory = require(script.Parent.Parent.Core.Server_Inventory)
local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
local Shared_LuckyBlocks = require(ReplicatedStorage.Modules.ItemConfigs.Shared_LuckyBlocks)
local Shared_Rarity = require(ReplicatedStorage.Modules.Gameplay.Shared_Rarity)
local Shared_RebirthRewards = require(ReplicatedStorage.Modules.Settings.Shared_RebirthRewards)
local Shared_ModifierHandler = require(ReplicatedStorage.Modules.Gameplay.Shared_ModifierHandler)
local Shared_ZoneConfig = require(ReplicatedStorage.Modules.Settings.Shared_ZoneConfig)
local Shared_Sounds = require(ReplicatedStorage.Modules.Settings.Shared_Sounds)
local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)

-- Events
local Events = ReplicatedStorage:WaitForChild("Events")
local BrainrotHandlerEvent = Events:WaitForChild("BrainrotHandler")

local Module = {}

-- Configuration
local CONFIG = {
	SpawnInterval = 10, -- Seconds between spawn cycles
	MinDistance = 30, -- Minimum studs between brainrots
	MaxSpawnAttempts = 10, -- Attempts to find valid position
	DespawnTimeMin = 60, -- Minimum seconds before despawn (spawned brainrots)
	DespawnTimeMax = 90, -- Maximum seconds before despawn (spawned brainrots)
	DroppedDespawnTime = 50, -- Seconds before dropped brainrots despawn
	MaxCarryLimit = 1, -- Base carry limit; +1 per Carry reward from rebirths
	SpawnEdgeBuffer = 15, -- Minimum studs from zone edge for spawning
	WalkEdgeBuffer = 10, -- Minimum studs from zone edge for walking
	
	-- Random walking (reduced frequency)
	WalkEnabled = true, -- Enable random walking
	WalkIntervalMin = 8, -- Minimum seconds between walks (was 5)
	WalkIntervalMax = 15, -- Maximum seconds between walks (was 6)
	WalkDistanceMin = 3, -- Minimum studs to walk
	WalkDistanceMax = 6, -- Maximum studs to walk
	WalkSpeed = 8, -- Walk speed (studs/second)
	
}

-- Registries (separated by item type)
local ActiveBrainrots = {} -- [uid] = brainrot data (only brainrots)
local ActiveLuckyBlocks = {} -- [uid] = lucky block data (only lucky blocks)
local HeldItems = {} -- [player] = {[uid] = {ConfigName, Modifier, Level, ItemType}} (can hold both)
local PlayerDeathConnections = {} -- [player] = connection
local WalkSchedule = {} -- [uid] = nextWalkTime (only brainrots walk)
local ReservedSlots = {} -- [spawnerPart][originalUID] = true (brainrots picked up but not collected/despawned)
local LastSpawnedPerZone = {} -- [zoneID] = configName (last spawned brainrot in that zone, prevents consecutive duplicates)

--[[
	Sync held items to client (brainrots and lucky blocks)
	@param player Player
]]
local function syncHeldItemsToClient(player)
	local heldData = HeldItems[player] or {}
	local count = 0
	for _ in pairs(heldData) do
		count = count + 1
	end
	
	-- Update attribute for UI
	player:SetAttribute("HeldBrainrotCount", count)
	
	-- Fire to client for visual update
	BrainrotHandlerEvent:FireClient(player, "UpdateHeld", heldData)
end

--[[
	Get random Normal modifier brainrot (for event upgrades)
	@return string?, table? - UID and data, or nil if none found
]]
function Module:GetRandomNormalBrainrot()
	local normalBrainrots = {}
	for uid, data in pairs(ActiveBrainrots) do
		if data.Model and data.Model.Parent and data.Modifier == "Normal" then
			table.insert(normalBrainrots, {uid, data})
		end
	end
	
	if #normalBrainrots == 0 then return nil, nil end
	
	local selected = normalBrainrots[math.random(1, #normalBrainrots)]
	return selected[1], selected[2]
end

--[[
	Upgrade a brainrot's modifier (for event effects)
	@param uid string - Brainrot UID
	@param newModifier string - New modifier ("Golden", "Diamond", etc.)
	@return boolean - Success
]]
function Module:UpgradeBrainrotModifier(uid, newModifier)
	local data = ActiveBrainrots[uid]
	if not data or not data.Model or not data.Model.Parent then
		return false
	end
	
	-- Update stored modifier
	data.Modifier = newModifier
	
	-- Apply visual changes using Shared_ModifierHandler
	Shared_ModifierHandler:ApplyModifierToModel(data.Model, data.ConfigName, newModifier)
	
	-- Reattach VFX (remove old, add new)
	local oldVFX = data.Model:FindFirstChild("ModifierVFX")
	if oldVFX then oldVFX:Destroy() end
	Shared_ModifierHandler:AttachModifierVFX(data.Model, newModifier)
	
	-- Update billboard modifier label
	local billboard = data.Billboard
	if billboard then
		local modifierLabel = billboard:FindFirstChild("Modifier", true)
		if modifierLabel and modifierLabel:IsA("TextLabel") then
			if newModifier ~= "Normal" then
				modifierLabel.Visible = true
				local specialData = Shared_Rarity.ModifierData[newModifier]
				if specialData then
					modifierLabel.Text = specialData.DisplayName
					local gradient = modifierLabel:FindFirstChildOfClass("UIGradient")
					if gradient and specialData.Color then
						gradient.Color = specialData.Color[1]
						gradient.Rotation = specialData.Color[2]
					end
				end
			else
				modifierLabel.Visible = false
			end
		end
		
		-- Update cash label (modifier affects income multiplier)
		local cashLabel = billboard:FindFirstChild("Cash", true)
		if cashLabel and cashLabel:IsA("TextLabel") then
			local basePerSec = Shared_Brainrots:GetCashPerSecond(
				data.ConfigName, 
				data.Level or 1, 
				newModifier
			)
			cashLabel.Text = "$" .. Shared_Shorten:Number(basePerSec) .. "/s"
		end
	end
	
	return true
end

--[[
	Get spawner parts from workspace
	@return Folder?
]]
local function getSpawnersFolder()
	local game = Workspace:WaitForChild("Game", 10)
	if not game then return nil end
	return game:FindFirstChild("Spawners")
end

--[[
	Check if a ConfigName is a lucky block
	@param configName string
	@return boolean
]]
local function isLuckyBlock(configName)
	return Shared_LuckyBlocks.List[configName] ~= nil
end

--[[
	Get rarity tier for server luck calculation
	@param rarity string - Rarity name (e.g., "Common", "Mythical")
	@return number - Tier level (1-9)
]]
local function getRarityTier(rarity)
	return Shared_Rarity.Order[rarity] or 1
end

--[[
	Roll for rarity tier using zone's weighted rarity table + server luck boost
	@param zoneID string - Zone identifier (e.g., "Zone1")
	@param serverLuck number - Current server luck multiplier
	@return string? - Rarity name or nil if failed
]]
local function rollRarityForZone(zoneID, serverLuck)
	local zoneConfig = Shared_ZoneConfig:GetZoneConfig(zoneID)
	local rarityWeights = zoneConfig and zoneConfig.Rarities
	if not rarityWeights then
		warn("⚠️ No rarity weights for zone:", zoneID)
		return nil
	end
	
	-- Get luck scaling rarities for this zone
	local luckScalingRarities = zoneConfig.LuckScalingRarities or {}
	local shouldScale = {}
	for _, rarity in ipairs(luckScalingRarities) do
		shouldScale[rarity] = true
	end
	
	-- Build adjusted weight table based on server luck
	-- Only rarities marked in LuckScalingRarities get multiplied by server luck
	local adjustedWeights = {}
	local totalWeight = 0
	
	for rarity, baseWeight in pairs(rarityWeights) do
		local adjustedWeight = baseWeight
		
		-- If this rarity scales with luck, multiply by server luck
		if serverLuck > 0 and shouldScale[rarity] then
			adjustedWeight = baseWeight * serverLuck
		end
		
		adjustedWeights[rarity] = adjustedWeight
		totalWeight = totalWeight + adjustedWeight
	end
	
	-- Weighted random selection
	if totalWeight <= 0 then
		warn("⚠️ Total weight is 0 for zone:", zoneID)
		return nil
	end
	
	local randomValue = math.random() * totalWeight
	local cumulativeWeight = 0
	
	for rarity, weight in pairs(adjustedWeights) do
		cumulativeWeight = cumulativeWeight + weight
		if randomValue <= cumulativeWeight then
			return rarity
		end
	end
	
	-- Fallback (shouldn't happen)
	return next(adjustedWeights)
end

--[[
	Roll for item type (Brainrot or LuckyBlock)
	@param luckyBlockChance number - Percentage chance (0-100) to spawn lucky block
	@return string - "Brainrot" or "LuckyBlock"
]]
local function rollItemType(luckyBlockChance)
	local roll = math.random() * 100
	return (roll <= luckyBlockChance) and "LuckyBlock" or "Brainrot"
end

--[[
	Get random item within a rarity tier
	@param rarity string - Rarity name (e.g., "Common", "Legendary")
	@param itemType string - "Brainrot" or "LuckyBlock"
	@param zoneID string - Zone identifier (required for lucky blocks)
	@return string? - ConfigName or nil if none found
]]
local function getRandomItemInRarity(rarity, itemType, zoneID)
	if itemType == "LuckyBlock" then
		-- For lucky blocks, get the specific lucky block for this rarity in this zone
		local luckyBlock = Shared_ZoneConfig:GetLuckyBlockForRarity(zoneID, rarity)
		if not luckyBlock then
			warn("⚠️ No lucky block configured for rarity:", rarity, "in zone:", zoneID)
		end
		return luckyBlock
	end
	
	-- For brainrots, filter by rarity AND exclude NoWorldSpawn items AND last spawned (for variety)
	local lastSpawned = LastSpawnedPerZone[zoneID]
	local candidates = {}
	for configName, config in pairs(Shared_Brainrots.List) do
		if config.Rarity == rarity and configName ~= lastSpawned and not config.NoWorldSpawn then
			table.insert(candidates, configName)
		end
	end
	
	-- If all brainrots were filtered out (only 1 brainrot in this rarity), allow duplicate
	if #candidates == 0 then
		for configName, config in pairs(Shared_Brainrots.List) do
			if config.Rarity == rarity then
				table.insert(candidates, configName)
			end
		end
	end
	
	if #candidates == 0 then
		warn("⚠️ No brainrots found for rarity:", rarity)
		return nil
	end
	
	-- Random selection from candidates
	return candidates[math.random(1, #candidates)]
end

--[[
	Get all brainrots that can spawn in a zone based on rarity (DEPRECATED - no longer used)
	@param zoneID string - e.g., "Zone1"
	@return {string} - Array of ConfigNames
]]
local function getBrainrotsForZone(zoneID)
	-- This function is deprecated but kept for backward compatibility
	-- The new system uses rollRarityForZone() + getRandomItemInRarity()
	return {}
end

--[[
	Get random position within spawner part (bottom surface).
	Uses raycast from above to find actual ground/terrain height.
	@param spawnerPart Part
	@return Vector3?
]]
local function getRandomPositionInPart(spawnerPart)
	local pos = spawnerPart.Position
	local size = spawnerPart.Size
	
	local randomX = pos.X + (math.random() * size.X - (size.X / 2))
	local randomZ = pos.Z + (math.random() * size.Z - (size.Z / 2))
	
	-- Start raycast from above the spawner part; cast down far enough for any zone height
	local rayOrigin = Vector3.new(randomX, pos.Y + size.Y, randomZ)
	local rayDirection = Vector3.new(0, -200, 0)
	
	-- Raycast to find ground
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local brainrotsFolder = Workspace.Game:FindFirstChild("Brainrots")
	local luckyBlocksFolder = Workspace.Game:FindFirstChild("LuckyBlocks")
	local filterList = {}
	if brainrotsFolder then table.insert(filterList, brainrotsFolder) end
	if luckyBlocksFolder then table.insert(filterList, luckyBlocksFolder) end
	raycastParams.FilterDescendantsInstances = filterList
	
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	
	if raycastResult then
		return raycastResult.Position
	else
		-- Fallback to bottom surface if raycast fails
		return Vector3.new(randomX, pos.Y - (size.Y / 2), randomZ)
	end
end

--[[
	Check if position is valid (not too close to other brainrots)
	@param position Vector3
	@param spawnerPart Part
	@return boolean
]]
local function isPositionValid(position, spawnerPart)
	-- Check distance to other brainrots
	for uid, brainrotData in pairs(ActiveBrainrots) do
		if brainrotData.SpawnerPart == spawnerPart and brainrotData.Model and brainrotData.Model.PrimaryPart then
			local distance = (position - brainrotData.Model.PrimaryPart.Position).Magnitude
			if distance < CONFIG.MinDistance then
				return false
			end
		end
	end
	
	-- Check edge buffer (keep spawns away from zone edges)
	if spawnerPart then
		local spawnerPos = spawnerPart.Position
		local spawnerSize = spawnerPart.Size
		local halfX = spawnerSize.X / 2
		local halfZ = spawnerSize.Z / 2
		
		-- Check if position is too close to any edge
		local distToLeftEdge = position.X - (spawnerPos.X - halfX)
		local distToRightEdge = (spawnerPos.X + halfX) - position.X
		local distToFrontEdge = position.Z - (spawnerPos.Z - halfZ)
		local distToBackEdge = (spawnerPos.Z + halfZ) - position.Z
		
		if distToLeftEdge < CONFIG.SpawnEdgeBuffer or distToRightEdge < CONFIG.SpawnEdgeBuffer or
		   distToFrontEdge < CONFIG.SpawnEdgeBuffer or distToBackEdge < CONFIG.SpawnEdgeBuffer then
			return false
		end
	end
	
	return true
end

--[[
	Create billboard for spawned/dropped brainrot with level and income display
	@param brainrotModel Model
	@param configName string
	@param modifier string
	@param level number
	@param despawnTime number
	@return BillboardGui, TextLabel
]]
local function createBrainrotBillboard(brainrotModel, configName, modifier, level, despawnTime)
	local config = Shared_Brainrots.List[configName]
	if not config then return nil end
	
	-- Get billboard template
	local billboardTemplate = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("BrainrotBillboard")
	
	if not billboardTemplate then
		warn("⚠️ Billboard template not found")
		return nil
	end
	
	-- Create attachment (Tsunami pattern: name "attach", but using our improved Size.Y positioning)
	local attachment = Instance.new("Attachment")
	attachment.Name = "attach"
	attachment.Position = Vector3.new(0, brainrotModel.PrimaryPart.Size.Y * 0.5, 0)
	attachment.Parent = brainrotModel.PrimaryPart
	
	-- Clone template
	local billboard = billboardTemplate:Clone()
	billboard.Parent = attachment
	
	-- Check for NametagHeight attribute (custom offset for this model)
	local nametagHeight = brainrotModel:GetAttribute("NametagHeight")
	
	-- If not found on clone, check original asset in ReplicatedStorage
	if not nametagHeight then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local brainrots = assets and assets:FindFirstChild("Brainrots")
		local brainrotParent = brainrots and brainrots:FindFirstChild(configName)
		if brainrotParent then
			local normalModel = brainrotParent:FindFirstChild("Normal")
			if normalModel then
				nametagHeight = normalModel:GetAttribute("NametagHeight")
			end
		end
	end
	
	if nametagHeight then
		billboard.StudsOffset = billboard.StudsOffset + nametagHeight
	end
	
	-- BillboardGui automatically faces camera (no rotation needed)
	-- Update DisplayName with level
	local displayName = billboard:FindFirstChild("DisplayName", true)
	if displayName and displayName:IsA("TextLabel") then
		displayName.Text = string.format("%s (Lv %d)", config.DisplayName, level or 1)
	end
	
	-- Update Rarity (use Shared_Rarity for consistent zone colors)
	local rarityLabel = billboard:FindFirstChild("Rarity", true)
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		local rarityInfo = Shared_Rarity:GetRarityInfo(config.Rarity)
		if rarityInfo then
			rarityLabel.Text = config.Rarity  -- Display name (e.g., "Common", "Rare")
			local gradient = rarityLabel:FindFirstChildOfClass("UIGradient")
			if not gradient then
				gradient = Instance.new("UIGradient")
				gradient.Parent = rarityLabel
			end
			
			if gradient and rarityInfo.gradient then
				gradient.Color = rarityInfo.gradient
				gradient.Rotation = (rarityInfo.isRainbow and 0) or 90  -- Rainbow 0°, others 90°
			end
		end
	end
	
	-- Update modifier label (UI child named "Modifier")
	local specialLabel = billboard:FindFirstChild("Modifier", true)
	if specialLabel and specialLabel:IsA("TextLabel") then
		if modifier ~= "Normal" then
			specialLabel.Visible = true
			local specialData = Shared_Rarity.ModifierData[modifier]
			if specialData then
				specialLabel.Text = specialData.DisplayName
				local gradient = specialLabel:FindFirstChildOfClass("UIGradient")
				if gradient and specialData.Color then
					gradient.Color = specialData.Color[1]
					gradient.Rotation = specialData.Color[2]
				end
			end
		else
			specialLabel.Visible = false
		end
	end
	
	-- Show Cash/s (income per second, not sell value)
	local cashLabel = billboard:FindFirstChild("Cash", true)
	if cashLabel and cashLabel:IsA("TextLabel") then
		-- Calculate cash per second using new formula
		local cashPerSec = Shared_Brainrots:GetCashPerSecond(configName, level or 1, modifier)
		local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
		cashLabel.Text = "$" .. Shared_Shorten:Number(cashPerSec) .. "/s"
		cashLabel.Visible = true
	end
	
	-- Hide Price label (only used for owned brainrots in slots, not spawned world brainrots)
	local priceLabel = billboard:FindFirstChild("Price", true)
	if priceLabel then
		priceLabel.Visible = false
	end
	
	-- Show Timer (Tsunami uses abbreviated time format)
	local timerFrame = billboard:FindFirstChild("Timer", true)
	local timeLabel = timerFrame and timerFrame:FindFirstChild("Time", true)
	if timerFrame and timeLabel and timeLabel:IsA("TextLabel") then
		timerFrame.Visible = true
		timeLabel.Text = tostring(math.ceil(despawnTime)) .. "s"
	end
	
	return billboard, timeLabel
end

--[[
	Create a brainrot model in the world
	@param configName string
	@param modifier string
	@param spawnerPart Part
	@param spawnPosition Vector3
	@return Model?
]]
local function createBrainrotModel(configName, modifier, spawnerPart, spawnPosition)
	local brainrotModel = Shared_ModifierHandler:GetBrainrotModel(configName, modifier or "Normal")
	if not brainrotModel then
		warn("⚠️ Brainrot not found: " .. configName)
		return nil
	end
	
	brainrotModel.Name = configName
	
	-- Ensure PrimaryPart
	if not brainrotModel.PrimaryPart then
		brainrotModel.PrimaryPart = brainrotModel:FindFirstChildWhichIsA("BasePart", true)
	end
	if not brainrotModel.PrimaryPart then
		warn("⚠️ No PrimaryPart for brainrot: " .. configName)
		brainrotModel:Destroy()
		return nil
	end
	
	local baseModelHeight = brainrotModel.PrimaryPart.Size.Y
	
	-- Position: ground + half model height (same as plot slot positioning)
	local targetPosition = spawnPosition + Vector3.new(0, baseModelHeight / 2, 0)
	
	-- Rotation: if spawnerPart exists (normal spawn), preserve X/Y and randomize Z
	-- If spawnerPart is nil (dropped brainrot), use flat Y-only rotation (no tilt)
	if spawnerPart then
		-- Normal spawn: preserve clone's rotation, randomize Z axis
		local clonePivot = brainrotModel:GetPivot()
		local rotX, rotY, rotZ = clonePivot:ToEulerAnglesXYZ()
		brainrotModel:PivotTo(CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0))
	else
		-- Dropped brainrot: flat on ground; 90° X so they lay correctly, random Y for facing
		brainrotModel:PivotTo(CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0))
	end
	
	return brainrotModel
end

--[[
	Play idle animation on spawned brainrot
	CLIENT-SIDE NOW: This function is deprecated - animations are now played by client
	@param brainrotModel Model
	@param configName string
]]
local function playIdleAnimation(brainrotModel, configName)
	-- DEPRECATED: Animations now handled client-side for performance
	-- Client detects zone tags and plays animations only when in range
	return nil
end

--[[
	Play walk animation on brainrot
	CLIENT-SIDE NOW: This function is deprecated - animations are now played by client
	@param brainrotModel Model
	@param configName string
	@return AnimationTrack?
]]
local function playWalkAnimation(brainrotModel, configName)
	-- DEPRECATED: Animations now handled client-side for performance
	-- Walk movement still works, just no animation replicated
	return nil
end

--[[
	Start random walking behavior for a brainrot
	@param uid string
	@param brainrotData table
]]
local function startRandomWalking(uid, brainrotData)
	if not CONFIG.WalkEnabled then return end
	
	-- Schedule first walk with random stagger (spread out initial walks)
	local initialDelay = math.random(0, CONFIG.WalkIntervalMax * 100) / 100
	WalkSchedule[uid] = tick() + initialDelay
end

--[[
	Perform a single walk movement for a brainrot
	@param uid string
	@param brainrotData table
]]
local function performWalk(uid, brainrotData)
	local model = brainrotData.Model
	if not model or not model.PrimaryPart then return end
	
	-- Get random nearby position within spawner bounds
	local currentPos = model.PrimaryPart.Position
	local spawnerPart = brainrotData.SpawnerPart
	
	-- Random offset (few studs)
	local randomDistance = math.random(CONFIG.WalkDistanceMin * 100, CONFIG.WalkDistanceMax * 100) / 100
	local randomAngle = math.random() * math.pi * 2
	local offsetX = math.cos(randomAngle) * randomDistance
	local offsetZ = math.sin(randomAngle) * randomDistance
	
	local targetX = currentPos.X + offsetX
	local targetZ = currentPos.Z + offsetZ
	
	-- Keep within spawner bounds (if we have a spawner part) with edge buffer
	if spawnerPart then
		local spawnerPos = spawnerPart.Position
		local spawnerSize = spawnerPart.Size
		local buffer = CONFIG.WalkEdgeBuffer
		targetX = math.clamp(targetX, spawnerPos.X - spawnerSize.X/2 + buffer, spawnerPos.X + spawnerSize.X/2 - buffer)
		targetZ = math.clamp(targetZ, spawnerPos.Z - spawnerSize.Z/2 + buffer, spawnerPos.Z + spawnerSize.Z/2 - buffer)
	end
	
	-- Raycast at destination to get correct ground height (handles slopes/terrain)
	local halfY = model.PrimaryPart.Size.Y / 2
	local rayOrigin = Vector3.new(targetX, currentPos.Y + 15, targetZ)
	local rayDirection = Vector3.new(0, -50, 0)
	
	local walkFilter = {}
	local brainrotsFolder = Workspace.Game and Workspace.Game:FindFirstChild("Brainrots")
	local luckyBlocksFolder = Workspace.Game and Workspace.Game:FindFirstChild("LuckyBlocks")
	if brainrotsFolder then
		table.insert(walkFilter, brainrotsFolder)
	end
	if luckyBlocksFolder then
		table.insert(walkFilter, luckyBlocksFolder)
	end
	
	local walkParams = RaycastParams.new()
	walkParams.FilterType = Enum.RaycastFilterType.Exclude
	walkParams.FilterDescendantsInstances = walkFilter
	
	local walkRay = Workspace:Raycast(rayOrigin, rayDirection, walkParams)
	local targetY = walkRay and (walkRay.Position.Y + halfY) or currentPos.Y
	
	local targetPos = Vector3.new(targetX, targetY, targetZ)
	
	-- Calculate walk duration
	local distance = (targetPos - currentPos).Magnitude
	local duration = distance / CONFIG.WalkSpeed
	
	-- Look at target (look on horizontal plane)
	local lookAtCFrame = CFrame.lookAt(currentPos, Vector3.new(targetPos.X, currentPos.Y, targetPos.Z))
	local finalCFrame = CFrame.new(targetPos) * (lookAtCFrame - lookAtCFrame.Position)
	
	-- Immediately orient to face target
	model:PivotTo(lookAtCFrame)
	
	-- Set attributes for CLIENT-SIDE lerping (3 attribute updates instead of 60+ CFrame updates)
	model:SetAttribute("TargetPosition", targetPos)
	model:SetAttribute("WalkDuration", duration)
	model:SetAttribute("IsMoving", true)
	
	-- After duration, ensure final position and stop movement
	task.delay(duration, function()
		if not model.Parent or not ActiveBrainrots[uid] then return end
		
		-- Set final position (ensures no desync)
		model:PivotTo(finalCFrame)
		
		-- Signal client to stop lerping
		model:SetAttribute("IsMoving", false)
	end)
	
	-- Schedule next walk with random interval
	local nextWalkDelay = math.random(CONFIG.WalkIntervalMin * 100, CONFIG.WalkIntervalMax * 100) / 100
	WalkSchedule[uid] = tick() + duration + nextWalkDelay
end

--[[
	Centralized walk scheduler (one loop for all brainrots)
]]
local function startWalkScheduler()
	if not CONFIG.WalkEnabled then return end
	
	task.spawn(function()
		while true do
			local now = tick()
			
			-- Check all scheduled walks
			for uid, nextWalkTime in pairs(WalkSchedule) do
				local brainrotData = ActiveBrainrots[uid]
				
				-- Remove if brainrot no longer exists, is owned, or is a dropped brainrot (no SpawnerPart)
				if not brainrotData or brainrotData.Owner or not brainrotData.SpawnerPart then
					WalkSchedule[uid] = nil
				-- Skip if being picked up (don't walk during hold)
				elseif brainrotData.IsBeingPickedUp then
					-- Do nothing, keep scheduled for later
				-- Execute walk if time has come
				elseif now >= nextWalkTime then
					performWalk(uid, brainrotData)
				end
			end
			
			-- Check every 0.1 seconds (responsive enough, low overhead)
			task.wait(0.1)
		end
	end)
end

--[[
	Spawn a brainrot in the world
	@param configName string
	@param modifier string
	@param spawnerPart Part
	@return string? - UID or nil on failure
]]
function Module:SpawnBrainrot(configName, modifier, spawnerPart)
	-- Find valid spawn position with spacing
	local spawnPosition = nil
	for attempt = 1, CONFIG.MaxSpawnAttempts do
		local testPosition = getRandomPositionInPart(spawnerPart)
		if isPositionValid(testPosition, spawnerPart) then
			spawnPosition = testPosition
			break
		end
	end
	
	if not spawnPosition then
		return nil -- No valid position found
	end
	
	-- Generate unique ID
	local uid = HttpService:GenerateGUID(false)
	
	-- Random despawn time
	local despawnTime = math.random(CONFIG.DespawnTimeMin, CONFIG.DespawnTimeMax)
	
	-- Get level range for this zone
	local zoneID = spawnerPart.Name
	local levelRange = Shared_ZoneConfig:GetLevelRange(zoneID) or {1, 5}
	local level = math.random(levelRange[1], levelRange[2])
	
	-- Create brainrot model
	local brainrotModel = createBrainrotModel(configName, modifier, spawnerPart, spawnPosition)
	if not brainrotModel then return nil end
	
	-- Set UID attribute for client identification
	brainrotModel:SetAttribute("UID", uid)
	
	-- Create billboard with timer, level, and income
	local billboard, timeLabel = createBrainrotBillboard(brainrotModel, configName, modifier, level, despawnTime)
	
	-- Play idle animation
	local idleTrack = playIdleAnimation(brainrotModel, configName)
	
	-- Create ProximityPrompt for pickup
	local proximityPrompt = Instance.new("ProximityPrompt")
	proximityPrompt.Name = "PickUpPrompt"
	proximityPrompt.Parent = brainrotModel.PrimaryPart
	proximityPrompt.RequiresLineOfSight = false
	proximityPrompt.ActionText = "Pick Up"
	proximityPrompt.ObjectText = "" -- No price for spawned brainrots (only for dropped/owned ones)
	proximityPrompt.HoldDuration = 0.5
	proximityPrompt.MaxActivationDistance = 6
	-- No ObjectText - price only relevant for selling in slots, not world pickups
	
	-- Register brainrot in ActiveBrainrots (not ActiveLuckyBlocks)
	local brainrotData = {
		UID = uid,
		Model = brainrotModel,
		ConfigName = configName,
		Modifier = modifier,
		Level = level,
		Owner = nil,
		SpawnerPart = spawnerPart,
		ZoneID = spawnerPart.Name,
		SpawnTime = tick(),
		DespawnTimer = despawnTime,
		Billboard = billboard,
		TimeLabel = timeLabel,
		ProximityPrompt = proximityPrompt,
		IdleTrack = idleTrack, -- Store idle animation track
		ItemType = "Brainrot", -- Identify as brainrot
	}
	
	ActiveBrainrots[uid] = brainrotData
	
	-- Setup pickup trigger
	proximityPrompt.Triggered:Connect(function(player)
		Module:PickupBrainrot(player, uid)
	end)
	
	-- Parent to world (Game.Brainrots folder)
	brainrotModel.Parent = Workspace.Game:FindFirstChild("Brainrots") or Workspace.Game
	
	-- Add zone tag for client-side animation management
	CollectionService:AddTag(brainrotModel, spawnerPart.Name .. "_Brainrot")
	
	-- Start random walking behavior
	startRandomWalking(uid, brainrotData)
	
	return uid
end

--[[
	Spawn a lucky block in the world
	@param configName string - Lucky block config name (e.g., "CommonLuckyBlock")
	@param spawnerPart Part
	@return string? - UID or nil on failure
]]
function Module:SpawnLuckyBlock(configName, spawnerPart)
	-- Find valid spawn position with spacing
	local spawnPosition = nil
	for attempt = 1, CONFIG.MaxSpawnAttempts do
		local testPosition = getRandomPositionInPart(spawnerPart)
		if isPositionValid(testPosition, spawnerPart) then
			spawnPosition = testPosition
			break
		end
	end
	
	if not spawnPosition then
		return nil -- No valid position found
	end
	
	-- Generate unique ID
	local uid = HttpService:GenerateGUID(false)
	
	-- Random despawn time (same as brainrots)
	local despawnTime = math.random(CONFIG.DespawnTimeMin, CONFIG.DespawnTimeMax)
	
	-- Get lucky block model from Assets
	local luckyBlocksFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("LuckyBlocks")
	
	if not luckyBlocksFolder then
		warn("⚠️ LuckyBlocks folder not found in Assets")
		return nil
	end
	
	local modelTemplate = luckyBlocksFolder:FindFirstChild(configName)
	if not modelTemplate then
		warn("⚠️ Lucky block model not found:", configName)
		return nil
	end
	
	local luckyBlockModel = modelTemplate:Clone()
	luckyBlockModel.Name = configName
	
	-- Ensure PrimaryPart
	if not luckyBlockModel.PrimaryPart then
		luckyBlockModel.PrimaryPart = luckyBlockModel:FindFirstChildWhichIsA("BasePart", true)
	end
	if not luckyBlockModel.PrimaryPart then
		warn("⚠️ No PrimaryPart for lucky block:", configName)
		luckyBlockModel:Destroy()
		return nil
	end
	
	-- Ensure all parts are welded to PrimaryPart (prevent falling apart)
	local primaryPart = luckyBlockModel.PrimaryPart
	for _, descendant in ipairs(luckyBlockModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= primaryPart then
			-- Unanchor non-primary parts
			descendant.Anchored = false
			
			-- Create weld if it doesn't exist
			local existingWeld = descendant:FindFirstChildWhichIsA("WeldConstraint")
			if not existingWeld then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primaryPart
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
	end
	
	-- Anchor only the PrimaryPart
	primaryPart.Anchored = true
	
	local baseModelHeight = primaryPart.Size.Y
	local groundOffset = 1.5 -- Offset from ground (1.5 studs)
	
	-- Position: ground + ground offset + half model height (use PivotTo for proper model positioning)
	local targetPosition = spawnPosition + Vector3.new(0, groundOffset + (baseModelHeight / 2), 0)
	luckyBlockModel:PivotTo(CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0))
	
	-- Get lucky block config
	local config = Shared_LuckyBlocks.List[configName]
	if not config then
		warn("⚠️ Lucky block config not found:", configName)
		luckyBlockModel:Destroy()
		return nil
	end
	
	-- Create billboard (no level or income for lucky blocks)
	local billboardTemplate = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("BrainrotBillboard")
	
	local billboard, timeLabel = nil, nil
	if billboardTemplate then
		-- Create attachment
		local attachment = Instance.new("Attachment")
		attachment.Name = "attach"
		attachment.Position = Vector3.new(0, luckyBlockModel.PrimaryPart.Size.Y * 0.5, 0)
		attachment.Parent = luckyBlockModel.PrimaryPart
		
		-- Clone template
		billboard = billboardTemplate:Clone()
		billboard.Parent = attachment
		
		-- Check for NametagHeight attribute (custom offset for this model)
		local nametagHeight = luckyBlockModel:GetAttribute("NametagHeight")
		
		-- If not found on clone, check original asset in ReplicatedStorage
		if not nametagHeight then
			local luckyBlocksFolder = ReplicatedStorage:FindFirstChild("Assets")
				and ReplicatedStorage.Assets:FindFirstChild("LuckyBlocks")
			if luckyBlocksFolder then
				local originalModel = luckyBlocksFolder:FindFirstChild(configName)
				if originalModel then
					nametagHeight = originalModel:GetAttribute("NametagHeight")
				end
			end
		end
		
		if nametagHeight then
			billboard.StudsOffset = billboard.StudsOffset + nametagHeight
		end
		
		-- Update DisplayName (no level for lucky blocks)
		local displayName = billboard:FindFirstChild("DisplayName", true)
		if displayName and displayName:IsA("TextLabel") then
			displayName.Text = config.DisplayName
		end
		
		-- Update Rarity with color
		local rarityLabel = billboard:FindFirstChild("Rarity", true)
		if rarityLabel and rarityLabel:IsA("TextLabel") then
			local rarityInfo = Shared_Rarity:GetRarityInfo(config.Rarity)
			if rarityInfo then
				rarityLabel.Text = config.Rarity
				local gradient = rarityLabel:FindFirstChildOfClass("UIGradient")
				if not gradient then
					gradient = Instance.new("UIGradient")
					gradient.Parent = rarityLabel
				end
				
				if gradient and rarityInfo.gradient then
					gradient.Color = rarityInfo.gradient
					gradient.Rotation = (rarityInfo.isRainbow and 0) or 90
				end
			end
		end
		
		-- Hide modifier label (lucky blocks don't have modifiers)
		local specialLabel = billboard:FindFirstChild("Modifier", true)
		if specialLabel then
			specialLabel.Visible = false
		end
		
		-- Hide Cash label (lucky blocks don't have income)
		local cashLabel = billboard:FindFirstChild("Cash", true)
		if cashLabel then
			cashLabel.Visible = false
		end
		
		-- Show Timer
		local timerFrame = billboard:FindFirstChild("Timer", true)
		timeLabel = timerFrame and timerFrame:FindFirstChild("Time", true)
		if timerFrame and timeLabel and timeLabel:IsA("TextLabel") then
			timerFrame.Visible = true
			timeLabel.Text = tostring(math.ceil(despawnTime)) .. "s"
		end
	end
	
	-- Create ProximityPrompt for pickup
	local proximityPrompt = Instance.new("ProximityPrompt")
	proximityPrompt.Name = "PickUpPrompt"
	proximityPrompt.Parent = luckyBlockModel.PrimaryPart
	proximityPrompt.RequiresLineOfSight = false
	proximityPrompt.ActionText = "Pick Up"
	proximityPrompt.ObjectText = "" -- No price for spawned lucky blocks
	proximityPrompt.HoldDuration = 0.5
	proximityPrompt.MaxActivationDistance = 6
	
	-- Register lucky block in ActiveLuckyBlocks (not ActiveBrainrots)
	local luckyBlockData = {
		UID = uid,
		Model = luckyBlockModel,
		ConfigName = configName,
		Modifier = nil, -- Lucky blocks don't have modifiers
		Level = nil, -- Lucky blocks don't have levels
		Owner = nil,
		SpawnerPart = spawnerPart,
		ZoneID = spawnerPart.Name,
		SpawnTime = tick(),
		DespawnTimer = despawnTime,
		Billboard = billboard,
		TimeLabel = timeLabel,
		ProximityPrompt = proximityPrompt,
		ItemType = "LuckyBlock", -- Identify as lucky block
	}
	
	ActiveLuckyBlocks[uid] = luckyBlockData
	
	-- Setup pickup trigger (routes to correct pickup function)
	proximityPrompt.Triggered:Connect(function(player)
		Module:PickupLuckyBlock(player, uid)
	end)
	
	-- Parent to world (Game.LuckyBlocks folder)
	luckyBlockModel.Parent = Workspace.Game:FindFirstChild("LuckyBlocks") or Workspace.Game
	
	-- Add zone tag for client-side animation management
	CollectionService:AddTag(luckyBlockModel, spawnerPart.Name .. "_Brainrot")
	
	-- Set Rotate attribute for client-side spinning animation
	luckyBlockModel:SetAttribute("Rotate", true)
	
	-- Add Float tag for client-side animation
	CollectionService:AddTag(luckyBlockModel, "Float")
	
	return uid
end

--[[
	Spawn a lucky block at a specific position (for dropping)
	@param configName string
	@param position Vector3
	@param originalSpawner Part? - Original spawner for respawn tracking
	@param originalUID string? - Original UID for slot reservation tracking
	@return string? - UID or nil on failure
]]
local function spawnLuckyBlockAtPosition(configName, position, originalSpawner, originalUID)
	-- Generate unique ID
	local uid = HttpService:GenerateGUID(false)
	
	-- Dropped lucky blocks have shorter despawn time
	local despawnTime = CONFIG.DroppedDespawnTime
	
	-- Get lucky block model
	local luckyBlocksFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("LuckyBlocks")
	
	if not luckyBlocksFolder then
		warn("⚠️ LuckyBlocks folder not found")
		return nil
	end
	
	local modelTemplate = luckyBlocksFolder:FindFirstChild(configName)
	if not modelTemplate then
		warn("⚠️ Lucky block model not found:", configName)
		return nil
	end
	
	local luckyBlockModel = modelTemplate:Clone()
	luckyBlockModel.Name = configName
	
	if not luckyBlockModel.PrimaryPart then
		luckyBlockModel.PrimaryPart = luckyBlockModel:FindFirstChildWhichIsA("BasePart", true)
	end
	if not luckyBlockModel.PrimaryPart then
		luckyBlockModel:Destroy()
		return nil
	end
	
	-- Ensure all parts are welded to PrimaryPart (prevent falling apart)
	local primaryPart = luckyBlockModel.PrimaryPart
	for _, descendant in ipairs(luckyBlockModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= primaryPart then
			-- Unanchor non-primary parts
			descendant.Anchored = false
			
			-- Create weld if it doesn't exist
			local existingWeld = descendant:FindFirstChildWhichIsA("WeldConstraint")
			if not existingWeld then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primaryPart
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
	end
	
	-- Anchor only the PrimaryPart
	primaryPart.Anchored = true
	
	local baseModelHeight = primaryPart.Size.Y
	local groundOffset = 1.5 -- Offset from ground (1.5 studs)
	local targetPosition = position + Vector3.new(0, groundOffset + (baseModelHeight / 2), 0)
	luckyBlockModel:PivotTo(CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0))
	
	-- Get config
	local config = Shared_LuckyBlocks.List[configName]
	if not config then
		luckyBlockModel:Destroy()
		return nil
	end
	
	-- Create billboard (simplified)
	local billboardTemplate = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("BrainrotBillboard")
	
	local billboard, timeLabel = nil, nil
	if billboardTemplate then
		local attachment = Instance.new("Attachment")
		attachment.Name = "attach"
		attachment.Position = Vector3.new(0, luckyBlockModel.PrimaryPart.Size.Y * 0.5, 0)
		attachment.Parent = luckyBlockModel.PrimaryPart
		
		billboard = billboardTemplate:Clone()
		billboard.Parent = attachment
		
		-- Check for NametagHeight attribute (custom offset for this model)
		local nametagHeight = luckyBlockModel:GetAttribute("NametagHeight")
		
		-- If not found on clone, check original asset in ReplicatedStorage
		if not nametagHeight then
			local luckyBlocksFolder = ReplicatedStorage:FindFirstChild("Assets")
				and ReplicatedStorage.Assets:FindFirstChild("LuckyBlocks")
			if luckyBlocksFolder then
				local originalModel = luckyBlocksFolder:FindFirstChild(configName)
				if originalModel then
					nametagHeight = originalModel:GetAttribute("NametagHeight")
				end
			end
		end
		
		if nametagHeight then
			billboard.StudsOffset = billboard.StudsOffset + nametagHeight
		end
		
		-- Update DisplayName
		local displayName = billboard:FindFirstChild("DisplayName", true)
		if displayName then
			displayName.Text = config.DisplayName
		end
		
		-- Update Rarity
		local rarityLabel = billboard:FindFirstChild("Rarity", true)
		if rarityLabel then
			local rarityInfo = Shared_Rarity:GetRarityInfo(config.Rarity)
			if rarityInfo then
				rarityLabel.Text = config.Rarity
				local gradient = rarityLabel:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient", rarityLabel)
				if rarityInfo.gradient then
					gradient.Color = rarityInfo.gradient
					gradient.Rotation = (rarityInfo.isRainbow and 0) or 90
				end
			end
		end
		
		-- Hide modifier and cash
		local specialLabel = billboard:FindFirstChild("Modifier", true)
		if specialLabel then specialLabel.Visible = false end
		local cashLabel = billboard:FindFirstChild("Cash", true)
		if cashLabel then cashLabel.Visible = false end
		
		-- Show Timer
		local timerFrame = billboard:FindFirstChild("Timer", true)
		timeLabel = timerFrame and timerFrame:FindFirstChild("Time", true)
		if timerFrame and timeLabel then
			timerFrame.Visible = true
			timeLabel.Text = tostring(math.ceil(despawnTime)) .. "s"
		end
	end
	
	-- Create ProximityPrompt
	local proximityPrompt = Instance.new("ProximityPrompt")
	proximityPrompt.Name = "PickUpPrompt"
	proximityPrompt.RequiresLineOfSight = false
	proximityPrompt.ActionText = "Pick Up"
	proximityPrompt.ObjectText = "" -- No price for spawned lucky blocks (dropped from opening)
	proximityPrompt.HoldDuration = 0.5
	proximityPrompt.MaxActivationDistance = 6
	proximityPrompt.Parent = luckyBlockModel.PrimaryPart
	
	-- Store data in ActiveLuckyBlocks registry
	local luckyBlockData = {
		UID = uid,
		ConfigName = configName,
		Modifier = nil,
		Level = nil,
		Model = luckyBlockModel,
		Billboard = billboard,
		TimeLabel = timeLabel,
		ProximityPrompt = proximityPrompt,
		SpawnerPart = nil,
		OriginalSpawner = originalSpawner,
		OriginalUID = originalUID, -- Store original UID for slot reservation
		DespawnTimer = despawnTime,
		Owner = nil,
		ItemType = "LuckyBlock",
		FloatingBaseY = targetPosition.Y,
	}
	
	ActiveLuckyBlocks[uid] = luckyBlockData
	
	-- Setup proximity prompt
	proximityPrompt.Triggered:Connect(function(player)
		Module:PickupLuckyBlock(player, uid)
	end)
	
	-- Parent to world (Game.LuckyBlocks folder)
	luckyBlockModel.Parent = Workspace.Game:FindFirstChild("LuckyBlocks") or Workspace.Game
	
	-- Tag as dropped lucky block for client animation (always animate - near player)
	CollectionService:AddTag(luckyBlockModel, "DroppedBrainrot")
	
	-- Set Rotate attribute for client-side spinning animation
	luckyBlockModel:SetAttribute("Rotate", true)
	
	-- Add Float tag for client-side animation
	CollectionService:AddTag(luckyBlockModel, "Float")
	
	return uid
end

--[[
	Spawn a brainrot at a specific position (for dropping)
	@param configName string
	@param modifier string
	@param level number
	@param position Vector3
	@param originalSpawner Part? - Original spawner for respawn tracking
	@param originalUID string? - Original UID for slot reservation tracking
	@return string? - UID or nil on failure
]]
local function spawnBrainrotAtPosition(configName, modifier, level, position, originalSpawner, originalUID)
	-- Generate unique ID
	local uid = HttpService:GenerateGUID(false)
	
	-- Dropped brainrots have shorter despawn time
	local despawnTime = CONFIG.DroppedDespawnTime
	
	-- Create brainrot model
	local brainrotModel = createBrainrotModel(configName, modifier, nil, position)
	if not brainrotModel then
		return nil
	end
	
	-- Create billboard
	local billboard, timeLabel = createBrainrotBillboard(brainrotModel, configName, modifier, level, despawnTime)
	
	-- Create ProximityPrompt for pickup (no sell price for dropped brainrots)
	local proximityPrompt = Instance.new("ProximityPrompt")
	proximityPrompt.Name = "PickUpPrompt"
	proximityPrompt.RequiresLineOfSight = false
	proximityPrompt.ActionText = "Pick Up"
	proximityPrompt.HoldDuration = 0.5
	proximityPrompt.MaxActivationDistance = 6
	proximityPrompt.Parent = brainrotModel.PrimaryPart
	
	-- Store brainrot data
	local brainrotData = {
		UID = uid,
		ConfigName = configName,
		Modifier = modifier,
		Level = level,
		Model = brainrotModel,
		Billboard = billboard,
		TimeLabel = timeLabel,
		ProximityPrompt = proximityPrompt,
		SpawnerPart = nil, -- No spawner for dropped brainrots (can't walk)
		OriginalSpawner = originalSpawner, -- Store for respawn when despawned
		OriginalUID = originalUID, -- Store original UID for slot reservation
		DespawnTimer = despawnTime,
		Owner = nil,
		ItemType = "Brainrot",
	}
	
	ActiveBrainrots[uid] = brainrotData
	
	-- Setup proximity prompt
	proximityPrompt.Triggered:Connect(function(player)
		Module:PickupBrainrot(player, uid)
	end)
	
	-- Parent to world (Game.Brainrots folder)
	brainrotModel.Parent = Workspace.Game:FindFirstChild("Brainrots") or Workspace.Game
	
	-- Tag as dropped brainrot for client animation (always animate - near player)
	CollectionService:AddTag(brainrotModel, "DroppedBrainrot")
	
	-- Idle animation is now client-side (no server animation needed)
	
	-- Start random walking (only for naturally spawned brainrots, NOT dropped ones)
	-- Dropped brainrots have originalSpawner set, naturally spawned ones don't
	if not originalSpawner then
		local nextWalkDelay = math.random(CONFIG.WalkIntervalMin * 100, CONFIG.WalkIntervalMax * 100) / 100
		WalkSchedule[uid] = tick() + nextWalkDelay
	end
	
	return uid
end

--[[
	Create a carried brainrot model above player's head (server-side, visible to all)
	@param player Player
	@param configName string
	@param modifier string
	@return Model?
]]
--[[
	Get attach part for carried brainrots (Head first so they stack above head)
]]
local function getCarryAttachPart(character)
	return character:FindFirstChild("Head")
		or character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character.PrimaryPart
end

--[[
	Initial Y offset above attach part for first brainrot (Head = above head, Torso = above torso)
]]
local function getCarryInitialYOffset(attachPart)
	local isHead = attachPart.Name == "Head"
	return (isHead and (attachPart.Size.Y / 2) or attachPart.Size.Y) + 0.2
end

local function createCarriedBrainrot(player, configName, modifier)
	local character = player.Character
	if not character then return nil end
	
	local attachPart = getCarryAttachPart(character)
	if not attachPart then return nil end
	
	local carriedModel = Shared_ModifierHandler:GetBrainrotModel(configName, modifier or "Normal")
	if not carriedModel then return nil end
	
	carriedModel.Name = "CarriedBrainrot_" .. player.Name
	
	if not carriedModel.PrimaryPart then
		carriedModel.PrimaryPart = carriedModel:FindFirstChildWhichIsA("BasePart", true)
	end
	if not carriedModel.PrimaryPart then
		carriedModel:Destroy()
		return nil
	end
	
	local primary = carriedModel.PrimaryPart
	local halfY = primary.Size.Y / 2
	
	-- Set all parts (non-collidable, massless, welded)
	for _, part in ipairs(carriedModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
		end
	end
	
	-- Position above attach part (from head or torso); rotate 90° on X for upright carry
	local yOffset = getCarryInitialYOffset(attachPart)
	carriedModel:PivotTo(
		attachPart.CFrame * CFrame.new(0, yOffset + halfY, 0) * CFrame.Angles(math.rad(90), 0, 0)
	)
	
	-- Weld to attach part (Head or torso)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachPart
	weld.Part1 = primary
	weld.Parent = primary
	
	-- Parent to character
	carriedModel.Parent = character
	
	return carriedModel
end

--[[
	Rebuild all carried models for a player (stacking them properly)
	@param player Player
]]
local function rebuildCarriedModels(player)
	if not HeldItems[player] then return end
	
	local character = player.Character
	if not character then return end
	
	local attachPart = getCarryAttachPart(character)
	if not attachPart then return end
	
	-- Destroy all existing carried models for this player
	for uid, heldData in pairs(HeldItems[player]) do
		if heldData.CarriedModel then
			heldData.CarriedModel:Destroy()
			heldData.CarriedModel = nil
		end
	end
	
	-- Recreate and stack all items (brainrots and lucky blocks)
	local yOffset = getCarryInitialYOffset(attachPart)
	
	for uid, heldData in pairs(HeldItems[player]) do
		local carriedModel = nil
		
		-- Get model based on item type
		if heldData.ItemType == "LuckyBlock" then
			-- Lucky block: clone from Assets.LuckyBlocks
			local luckyBlocksFolder = ReplicatedStorage:FindFirstChild("Assets")
				and ReplicatedStorage.Assets:FindFirstChild("LuckyBlocks")
			if luckyBlocksFolder then
				local template = luckyBlocksFolder:FindFirstChild(heldData.ConfigName)
				if template then
					carriedModel = template:Clone()
				end
			end
		else
			-- Brainrot: use modifier handler
			carriedModel = Shared_ModifierHandler:GetBrainrotModel(heldData.ConfigName, heldData.Modifier or "Normal")
		end
		
		if not carriedModel then continue end
		
		carriedModel.Name = "CarriedBrainrot_" .. player.Name .. "_" .. uid
		
		if not carriedModel.PrimaryPart then
			carriedModel.PrimaryPart = carriedModel:FindFirstChildWhichIsA("BasePart", true)
		end
		if not carriedModel.PrimaryPart then
			carriedModel:Destroy()
			continue
		end
		
		local primary = carriedModel.PrimaryPart
		local halfY = primary.Size.Y / 2
		
		-- Set all parts (non-collidable, massless, welded)
		for _, part in ipairs(carriedModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.Massless = true
				part.CanCollide = false
			end
		end
		
		-- Position above attach part at current yOffset (rotate 90 degrees on X axis for upright carry)
		carriedModel:PivotTo(
			attachPart.CFrame * CFrame.new(0, yOffset + halfY, 0) * CFrame.Angles(0, 0, 0)
		)
		
		-- Weld to attach part
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = attachPart
		weld.Part1 = primary
		weld.Parent = primary
		
		-- Parent to character
		carriedModel.Parent = character
		
		-- Store carried model reference
		heldData.CarriedModel = carriedModel
		
		-- Play idle animation (only for brainrots, not lucky blocks)
		-- CLIENT-SIDE NOW: Animations handled by Client_BrainrotAnimations
		-- Carried brainrots above head are handled by client based on zone proximity
		if heldData.ItemType ~= "LuckyBlock" then
			-- Animation loading removed - client handles all brainrot animations
		end
		
		-- Increment offset for next item (stack them)
		yOffset = yOffset + primary.Size.Y + 0.2
	end
end

--[[
	Pick up a brainrot (move to held state)
	@param player Player
	@param uid string
	@return boolean - Success
]]
function Module:PickupBrainrot(player, uid)
	local brainrotData = ActiveBrainrots[uid]
	if not brainrotData or brainrotData.Owner then
		return false -- Already owned or doesn't exist
	end
	
	-- Check if player/character is alive and not dying
	local character = player.Character
	if not character then
		return false
	end
	
	-- CRITICAL: Check IsDying attribute (set when shot hits, before actual death)
	if character:GetAttribute("IsDying") then
		return false -- Player is in the process of dying
	end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false -- Player is dead or dying
	end

	-- Validate player
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	
	-- Check carry limit
	local heldCount = 0
	if HeldItems[player] then
		for _ in pairs(HeldItems[player]) do
			heldCount = heldCount + 1
		end
	end
	
	local profile = Server_Data:GetProfile(player)
	local rebirths = (profile and profile.Data.Rebirths) or 0
	local carryFromRebirths = Shared_RebirthRewards:GetTotalReward(rebirths, "Carry")
	local carryLimit = CONFIG.MaxCarryLimit + carryFromRebirths
	
	if heldCount >= carryLimit then
		-- Show popup notification
		Events.Popup:FireClient(player, string.format("You can't carry more than %d!", carryLimit), false)
		return false
	end
	
	-- Destroy world brainrot model (everyone sees it disappear)
	if brainrotData.Model then
		brainrotData.Model:Destroy()
	end
	
	-- Mark as owned and remove from active brainrots
	brainrotData.Owner = player
	brainrotData.Model = nil
	brainrotData.ProximityPrompt = nil
	brainrotData.Billboard = nil
	
	-- Remove from walk schedule
	WalkSchedule[uid] = nil
	
	-- Handle slot tracking (simple version - no reservation needed)
	local originalSpawner = brainrotData.SpawnerPart
	local originalUID = uid
	
	-- Add to held registry
	if not HeldItems[player] then
		HeldItems[player] = {}
	end
	HeldItems[player][uid] = {
		ConfigName = brainrotData.ConfigName,
		Modifier = brainrotData.Modifier,
		Level = brainrotData.Level,
		CarriedModel = nil, -- Will be created when rebuilding stack
		ItemType = brainrotData.ItemType or "Brainrot",
	}
	
	-- Mark player as holding brainrot (prevents equipment)
	player:SetAttribute("IsHoldingBrainrot", true)
	
	-- Force unequip current item using proper inventory system
	local currentEquipped = player:GetAttribute("CurrentEquipped")
	if currentEquipped then
		Server_Inventory:UnequipItem(player, currentEquipped)
	end
	
	-- Rebuild all carried models (stack them) for this player
	rebuildCarriedModels(player)
	
	-- Sync to client for UI updates
	syncHeldItemsToClient(player)
	
	return true
end

--[[
	Pick up a lucky block (move to held state)
	@param player Player
	@param uid string
	@return boolean - Success
]]
function Module:PickupLuckyBlock(player, uid)
	local luckyBlockData = ActiveLuckyBlocks[uid]
	if not luckyBlockData or luckyBlockData.Owner then
		return false -- Already owned or doesn't exist
	end
	
	-- Check if player is actively playing (not dead, not in safe zone)
	if not player:GetAttribute("IsPlaying") then
		return false -- Player is dead or in safe zone
	end
	
	-- Check if player/character is alive and not dying
	local character = player.Character
	if not character then
		return false
	end
	
	-- CRITICAL: Check IsDying attribute (set when shot hits, before actual death)
	if character:GetAttribute("IsDying") then
		return false -- Player is in the process of dying
	end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false -- Player is dead or dying
	end

	-- Right safe zone (past gates): no carrying or picking up items
	if player:GetAttribute("InRightSafeZone") then
		local popupEvent = Events:FindFirstChild("Popup")
		if popupEvent then
			popupEvent:FireClient(player, "Lucky blocks are not allowed here!", false)
		end
		return false
	end
	
	-- Validate player
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	
	-- Check carry limit
	local heldCount = 0
	if HeldItems[player] then
		for _ in pairs(HeldItems[player]) do
			heldCount = heldCount + 1
		end
	end
	
	local profile = Server_Data:GetProfile(player)
	local rebirths = (profile and profile.Data.Rebirths) or 0
	local carryFromRebirths = Shared_RebirthRewards:GetTotalReward(rebirths, "Carry")
	local carryLimit = CONFIG.MaxCarryLimit + carryFromRebirths
	
	if heldCount >= carryLimit then
		-- Show popup notification
		Events.Popup:FireClient(player, string.format("You can't carry more than %d!", carryLimit), false)
		return false
	end
	
	-- Destroy world lucky block model (everyone sees it disappear)
	if luckyBlockData.Model then
		luckyBlockData.Model:Destroy()
	end
	
	-- Mark as owned and remove from active lucky blocks
	luckyBlockData.Owner = player
	luckyBlockData.Model = nil
	luckyBlockData.ProximityPrompt = nil
	luckyBlockData.Billboard = nil
	
	-- Handle slot tracking (simple version - no reservation needed)
	local originalSpawner = luckyBlockData.SpawnerPart
	local originalUID = uid
	
	-- Add to held registry
	if not HeldItems[player] then
		HeldItems[player] = {}
	end
	HeldItems[player][uid] = {
		ConfigName = luckyBlockData.ConfigName,
		Modifier = nil, -- Lucky blocks don't have modifiers
		Level = nil, -- Lucky blocks don't have levels
		CarriedModel = nil, -- Will be created when rebuilding stack
		ItemType = "LuckyBlock",
	}
	
	-- Mark player as holding item (prevents equipment)
	player:SetAttribute("IsHoldingBrainrot", true)
	
	-- Force unequip current item using proper inventory system
	local currentEquipped = player:GetAttribute("CurrentEquipped")
	if currentEquipped then
		Server_Inventory:UnequipItem(player, currentEquipped)
	end
	
	-- Rebuild all carried models (stack them) for this player
	rebuildCarriedModels(player)
	
	-- Sync to client for UI updates
	syncHeldItemsToClient(player)
	
	-- Auto-collect if player is in SafeZone (fix: picking up while already in safe zone)
	if not player:GetAttribute("IsPlaying") then
		-- Player is in SafeZone, immediately collect to inventory
		task.defer(function()
			Module:CollectHeldItems(player)
		end)
	end
	
	return true
end

--[[
	Drop all held brainrots (on death or slap).
	@param player Player
	@param dropCenterOffset Vector3? Optional. When set (e.g. from right safe zone), drop center = player position + this offset
		so brainrots land further away (e.g. Vector3.new(0, 0, -25) to drop 25 studs back in Z).
]]
function Module:DropAllHeldItems(player, dropCenterOffset)
	if not HeldItems[player] then return end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local basePosition = rootPart and rootPart.Position or Vector3.new(0, 50, 0)
	local dropPosition = basePosition
	if dropCenterOffset and (dropCenterOffset.X ~= 0 or dropCenterOffset.Y ~= 0 or dropCenterOffset.Z ~= 0) then
		dropPosition = basePosition + dropCenterOffset
	end

	for uid, heldData in pairs(HeldItems[player]) do
		-- Destroy carried model (everyone sees it disappear from above player's head)
		if heldData.CarriedModel then
			heldData.CarriedModel:Destroy()
		end
		
		-- Remove from active registries
		ActiveBrainrots[uid] = nil
		ActiveLuckyBlocks[uid] = nil
		
		-- Position near drop location (spread out) with raycast
		local randomOffset = Vector3.new(
			math.random(-5, 5),
			0,
			math.random(-5, 5)
		)
		local dropPos = dropPosition + randomOffset
		
		-- Raycast down to find ground height
		local rayOrigin = Vector3.new(dropPos.X, dropPosition.Y + 20, dropPos.Z)
		local rayDirection = Vector3.new(0, -200, 0)
		
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.CollisionGroup = "Player"
		
		-- Also exclude Brainrots and LuckyBlocks folders (all spawned items)
		local brainrotsFolder = Workspace.Game and Workspace.Game:FindFirstChild("Brainrots")
		local luckyBlocksFolder = Workspace.Game and Workspace.Game:FindFirstChild("LuckyBlocks")
		local filterList = {}
		if brainrotsFolder then table.insert(filterList, brainrotsFolder) end
		if luckyBlocksFolder then table.insert(filterList, luckyBlocksFolder) end
		if #filterList > 0 then
			raycastParams.FilterDescendantsInstances = filterList
		end
		
		local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		local groundPos = raycastResult and raycastResult.Position or (rayOrigin + rayDirection)
		
		-- Spawn dropped item (homeless - no spawner, will despawn in 50s)
		-- Original zone will spawn a replacement naturally since this doesn't have SpawnerPart
		if heldData.ItemType == "LuckyBlock" then
			spawnLuckyBlockAtPosition(heldData.ConfigName, groundPos, nil, nil)
		else
			spawnBrainrotAtPosition(heldData.ConfigName, heldData.Modifier or "Normal", heldData.Level, groundPos, nil, nil)
		end
	end
	
	-- Clear held state
	HeldItems[player] = nil
	
	-- Clear holding attribute (allows equipment again)
	player:SetAttribute("IsHoldingBrainrot", nil)
	
	-- Sync to client
	syncHeldItemsToClient(player)
end

--[[
	Collect held brainrots to inventory (secure them)
	@param player Player
	@return boolean - Success
]]
--[[
	Collect all held items (brainrots and lucky blocks) to player's inventory
	@param player Player
	@return table?, table? - Array of collected brainrot UIDs, array of collected lucky block UIDs
]]
function Module:CollectHeldItems(player)
	if not HeldItems[player] then
		return nil, nil
	end
	
	-- Count held items (dictionary, not array)
	local count = 0
	for _ in pairs(HeldItems[player]) do
		count = count + 1
	end
	
	if count == 0 then
		return nil, nil
	end
	
	local profile = Server_Data:GetProfile(player)
	if not profile then return nil, nil end
	
	-- Track collected brainrots for client notification AND for auto-equip
	local collectedBrainrots = {}
	local collectedLuckyBlocks = {}
	local collectedBrainrotUIDs = {} -- NEW: Track inventory UIDs for auto-equip
	local collectedLuckyBlockUIDs = {} -- NEW: Track inventory UIDs for auto-equip
	
	-- Move each held item to inventory
	for uid, heldData in pairs(HeldItems[player]) do
		-- Destroy carried model (everyone sees it disappear)
		if heldData.CarriedModel then
			heldData.CarriedModel:Destroy()
		end
		
		-- Remove from active brainrots and lucky blocks
		ActiveBrainrots[uid] = nil
		ActiveLuckyBlocks[uid] = nil
		
		-- Generate inventory UID
		local inventoryUID = HttpService:GenerateGUID(false)
		
		-- Add to inventory based on item type
		local itemData
		if heldData.ItemType == "LuckyBlock" then
			-- Lucky block: no modifier or level
			itemData = {
				Type = "LuckyBlock",
				ConfigName = heldData.ConfigName,
				Metadata = {},
			}
			
			-- Track inventory UID for auto-equip (LAST one will be equipped)
			table.insert(collectedLuckyBlockUIDs, inventoryUID)
			
			-- Track for client notification (callout sound + popup)
			table.insert(collectedLuckyBlocks, {
				ConfigName = heldData.ConfigName,
			})
		else
			-- Brainrot: has modifier and level
			itemData = {
				Type = "Brainrot",
				ConfigName = heldData.ConfigName,
				Metadata = {
					Modifier = heldData.Modifier or "Normal",
					Level = heldData.Level,
				},
			}
			
			-- Track inventory UID for auto-equip (LAST one will be equipped)
			table.insert(collectedBrainrotUIDs, inventoryUID)
		end
		
		Server_Data:AddToTable(player, "Inventory", inventoryUID, itemData)
		
		-- Update Index (track discovered brainrots) - only for brainrots, not lucky blocks
		if heldData.ItemType ~= "LuckyBlock" then
			local modifier = heldData.Modifier or "Normal"
			local configName = heldData.ConfigName
			local currentIndex = profile.Data.Index or {}
			
			-- Create a copy to avoid modifying profile data directly
			local updatedIndex = {}
			for rarity, brainrots in pairs(currentIndex) do
				updatedIndex[rarity] = {}
				for _, name in pairs(brainrots) do
					table.insert(updatedIndex[rarity], name)
				end
			end
			
			-- Initialize modifier array if it doesn't exist
			if not updatedIndex[modifier] then
				updatedIndex[modifier] = {}
			end
			
			-- Add the brainrot if not already discovered
			if not table.find(updatedIndex[modifier], configName) then
				table.insert(updatedIndex[modifier], configName)
				-- Update the entire Index through SetValue (this will trigger replica changes)
				Server_Data:SetValue(player, "Index", updatedIndex)
			end
			
			-- Track for client notification (callout sound + popup)
			table.insert(collectedBrainrots, {
				ConfigName = configName,
				Modifier = modifier,
				Level = heldData.Level,
			})
		end
	end
	
	-- Clear held state
	HeldItems[player] = nil
	
	-- Clear holding attribute (allows equipment again)
	player:SetAttribute("IsHoldingBrainrot", nil)
	
	-- Sync to client
	syncHeldItemsToClient(player)
	
	-- Fire client event for callouts (brainrots first, then lucky blocks)
	if #collectedBrainrots > 0 or #collectedLuckyBlocks > 0 then
		BrainrotHandlerEvent:FireClient(player, "ItemsCollected", {
			Brainrots = collectedBrainrots,
			LuckyBlocks = collectedLuckyBlocks,
		})
	end
	
	-- Return collected UIDs for auto-equip (caller can equip the last one)
	return collectedBrainrotUIDs, collectedLuckyBlockUIDs
end

--[[
	Despawn a brainrot
	@param uid string
]]
--[[
	Despawn a brainrot or lucky block
	@param uid string
	@param itemType string - "Brainrot" or "LuckyBlock"
]]
function Module:DespawnItem(uid, itemType)
	local itemData = nil
	local registry = nil
	
	if itemType == "Brainrot" then
		itemData = ActiveBrainrots[uid]
		registry = ActiveBrainrots
	elseif itemType == "LuckyBlock" then
		itemData = ActiveLuckyBlocks[uid]
		registry = ActiveLuckyBlocks
	end
	
	if not itemData then return end
	
	-- Destroy model
	if itemData.Model then
		itemData.Model:Destroy()
	end
	
	-- Remove from registries
	registry[uid] = nil
	if itemType == "Brainrot" then
		WalkSchedule[uid] = nil
	end
end

-- Backward compatibility wrapper
function Module:DespawnBrainrot(uid)
	self:DespawnItem(uid, "Brainrot")
end

--[[
	Count items in a specific zone (brainrots + lucky blocks)
	Simple version: Only count what's actively spawned in the world
	When picked up, zone spawns a replacement (no reservation system)
	@param spawnerPart Part
	@return number
]]
local function countItemsInZone(spawnerPart)
	local count = 0
	
	-- Count brainrots (only those with SpawnerPart set - actively spawned in world)
	for uid, brainrotData in pairs(ActiveBrainrots) do
		if brainrotData.SpawnerPart == spawnerPart then
			count = count + 1
		end
	end
	
	-- Count lucky blocks (only those with SpawnerPart set - actively spawned in world)
	for uid, luckyBlockData in pairs(ActiveLuckyBlocks) do
		if luckyBlockData.SpawnerPart == spawnerPart then
			count = count + 1
		end
	end
	
	return count
end

-- Backward compatibility wrapper
local function countBrainrotsInZone(spawnerPart)
	return countItemsInZone(spawnerPart)
end

--[[
	Update despawn timers for both brainrots and lucky blocks (1 second interval)
]]
function Module:StartDespawnLoop()
	task.spawn(function()
		while true do
			task.wait(1) -- Update once per second, not every frame
			
			-- Update brainrot despawn timers
			for uid, brainrotData in pairs(ActiveBrainrots) do
				-- Only tick down if not owned
				if not brainrotData.Owner then
					brainrotData.DespawnTimer = brainrotData.DespawnTimer - 1
					
					-- Update timer display (Tsunami format: with 's' suffix)
					if brainrotData.TimeLabel and brainrotData.TimeLabel:IsA("TextLabel") then
						brainrotData.TimeLabel.Text = tostring(math.ceil(math.max(0, brainrotData.DespawnTimer))) .. "s"
					end
					
					-- Despawn if time expired
					if brainrotData.DespawnTimer <= 0 then
						Module:DespawnItem(uid, "Brainrot")
					end
				end
			end
			
			-- Update lucky block despawn timers
			for uid, luckyBlockData in pairs(ActiveLuckyBlocks) do
				-- Only tick down if not owned
				if not luckyBlockData.Owner then
					luckyBlockData.DespawnTimer = luckyBlockData.DespawnTimer - 1
					
					-- Update timer display
					if luckyBlockData.TimeLabel and luckyBlockData.TimeLabel:IsA("TextLabel") then
						luckyBlockData.TimeLabel.Text = tostring(math.ceil(math.max(0, luckyBlockData.DespawnTimer))) .. "s"
					end
					
					-- Despawn if time expired
					if luckyBlockData.DespawnTimer <= 0 then
						Module:DespawnItem(uid, "LuckyBlock")
					end
				end
			end
		end
	end)
end

--[[
	Setup player death handler
	@param player Player
]]
local function setupPlayerDeathHandler(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 30)
		if not humanoid then return end
		
		-- Clean up any leftover held items state on respawn
		if HeldItems[player] then
			HeldItems[player] = nil
		end
		player:SetAttribute("IsHoldingBrainrot", false)
		
		-- Disconnect previous connection
		if PlayerDeathConnections[player] then
			PlayerDeathConnections[player]:Disconnect()
		end
		
		-- Drop all held items on death
		PlayerDeathConnections[player] = humanoid.Died:Connect(function()
			Module:DropAllHeldItems(player)
		end)
	end)
end

--[[
	Initialize spawner system
]]
function Module:Init()
	-- Setup player handlers
	Players.PlayerAdded:Connect(function(player)
		setupPlayerDeathHandler(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		-- Clean up held items
		if HeldItems[player] then
			Module:DropAllHeldItems(player)
		end
		
		-- Clean up connections
		if PlayerDeathConnections[player] then
			PlayerDeathConnections[player]:Disconnect()
			PlayerDeathConnections[player] = nil
		end
	end)
	
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayerDeathHandler(player)
	end
	
	-- Start timer cleanup for dropped/externally spawned held items.
	self:StartDespawnLoop()
	
	-- Setup RemoteEvent handlers (action-based, minimal)
	BrainrotHandlerEvent.OnServerEvent:Connect(function(player, action, ...)
		if action == "DropAll" then
			self:DropAllHeldItems(player)
		end
	end)
end

--[[
	Hook for slapper system: call this when a player gets slapped
	@param player Player - The player who got slapped
]]
function Module:OnPlayerSlapped(player)
	self:DropAllHeldItems(player)
end

--[[
	Get held items for a player (for income calculation)
	@param player Player
	@return table? - {[uid] = {ConfigName, Modifier, Level, ItemType}} or nil
]]
function Module:GetHeldBrainrots(player)
	return HeldItems[player]
end

--[[
	Spawn a lucky block at a specific world position (for events like Meteor)
	@param configName string - Lucky block config name (e.g., "CommonLuckyBlock")
	@param position Vector3 - World position to spawn at
	@param spawnerPart BasePart? - Optional spawner part for zone tracking (defaults to closest zone)
	@return string? - UID or nil on failure
]]
function Module:SpawnLuckyBlockAtPosition(configName, position, spawnerPart)
	-- If no spawner provided, find closest zone spawner
	if not spawnerPart then
		local spawnersFolder = getSpawnersFolder()
		if spawnersFolder then
			local closestSpawner = nil
			local closestDistance = math.huge
			
			for _, spawner in ipairs(spawnersFolder:GetChildren()) do
				if spawner:IsA("BasePart") then
					local distance = (spawner.Position - position).Magnitude
					if distance < closestDistance then
						closestDistance = distance
						closestSpawner = spawner
					end
				end
			end
			
			spawnerPart = closestSpawner
		end
	end
	
	-- Use the existing internal function
	return spawnLuckyBlockAtPosition(configName, position, spawnerPart, nil)
end

--[[
	Mark a held brainrot as consumed (removes from ActiveBrainrots/ActiveLuckyBlocks to allow respawn)
	Call this when brainrots are consumed by game mechanics (e.g. Piggy event)
	@param uid string - UID of the brainrot/lucky block
]]
function Module:ConsumeBrainrot(uid)
	-- Delay removal by 5 seconds to prevent instant respawn
	task.delay(5, function()
		ActiveBrainrots[uid] = nil
		ActiveLuckyBlocks[uid] = nil
	end)
end

return Module