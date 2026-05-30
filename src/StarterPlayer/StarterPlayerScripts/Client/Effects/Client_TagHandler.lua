--// Client_TagHandler - Optimized floating animation system for tagged models
--// Uses spatial partitioning for efficient distance culling

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Module = {}

-- Player references
local player = Players.LocalPlayer
local character = player.Character
local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
local playerPosition = humanoidRootPart and humanoidRootPart.Position

-- Configuration
local ACTIVATION_DISTANCE = 150 -- Activate floating within 150 studs
local CHUNK_SIZE = 100 -- World chunk size for spatial partitioning
local PLAYER_UPDATE_INTERVAL = 0.5 -- Update player position every 0.5 seconds (objects are static, only player moves!)

-- Default animation settings
local DEFAULT_FLOAT_HEIGHT = 1.5
local DEFAULT_FLOAT_SPEED = 2
local DEFAULT_ROTATE_SPEED = 45 -- Degrees per second

-- Data structures
local floatingObjects = {} -- [model] = {baseCFrame, floatHeight, floatSpeed, phaseOffset, chunkKey}
local activeObjects = {} -- Array of models currently being animated
local chunks = {} -- [chunkKey] = {model1, model2, ...}

--[[
	Convert world position to chunk key for spatial partitioning
	Only uses X and Z (horizontal distance, ignores height)
	@param position Vector3
	@return string - Chunk key (e.g., "0,0")
]]
local function getChunkKey(position: Vector3): string
	return string.format("%d,%d",
		math.floor(position.X / CHUNK_SIZE),
		math.floor(position.Z / CHUNK_SIZE)
	)
end

--[[
	Get neighboring chunk keys (3x3 grid around player)
	@param centerChunkKey string
	@return table - Array of chunk keys to check
]]
local function getNearbyChunkKeys(centerChunkKey: string): {string}
	local keys = {}
	local x, z = centerChunkKey:match("(-?%d+),(-?%d+)")
	x, z = tonumber(x), tonumber(z)
	
	-- Check 3x3 grid around player (9 chunks, not 27)
	for dx = -1, 1 do
		for dz = -1, 1 do
			table.insert(keys, string.format("%d,%d", x + dx, z + dz))
		end
	end
	
	return keys
end

--[[
	Add model to spatial partitioning system
	@param model Model
	@param chunkKey string
]]
local function addToChunk(model: Model, chunkKey: string)
	if not chunks[chunkKey] then
		chunks[chunkKey] = {}
	end
	table.insert(chunks[chunkKey], model)
end

--[[
	Remove model from spatial partitioning system
	@param model Model
	@param chunkKey string
]]
local function removeFromChunk(model: Model, chunkKey: string)
	if not chunks[chunkKey] then return end
	
	for i, m in ipairs(chunks[chunkKey]) do
		if m == model then
			table.remove(chunks[chunkKey], i)
			break
		end
	end
	
	-- Clean up empty chunks
	if #chunks[chunkKey] == 0 then
		chunks[chunkKey] = nil
	end
end

--[[
	Start floating animation for a model
	@param model Model
]]
local function startFloating(model: Model)
	if not model or not model:IsA("Model") then
		warn("⚠️ Float tag applied to non-model:", model and model:GetFullName() or "nil")
		return
	end
	
	-- Wait for model to fully load (streaming enabled support)
	if not model.PrimaryPart then
		-- Try to find a PrimaryPart
		local primaryPart = model:FindFirstChildWhichIsA("BasePart", true)
		if primaryPart then
			model.PrimaryPart = primaryPart
		else
			-- Model not fully loaded yet, wait for it
			task.spawn(function()
				local maxWait = 5
				local waited = 0
				while not model.PrimaryPart and model.Parent and waited < maxWait do
					task.wait(0.1)
					waited = waited + 0.1
					model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
				end
				
				if model.PrimaryPart and model.Parent then
					-- Retry now that model is loaded
					startFloating(model)
				end
			end)
			return
		end
	end
	
	local baseCFrame = model:GetPivot()
	local modelPosition = baseCFrame.Position
	local chunkKey = getChunkKey(modelPosition)
	
	-- Cache attributes once (avoid GetAttribute every frame)
	local floatHeight = model:GetAttribute("FloatHeight") or DEFAULT_FLOAT_HEIGHT
	local floatSpeed = model:GetAttribute("FloatSpeed") or DEFAULT_FLOAT_SPEED
	local shouldRotate = model:GetAttribute("Rotate") or false
	local rotateSpeed = model:GetAttribute("RotateSpeed") or DEFAULT_ROTATE_SPEED
	
	-- Store data with cached values
	floatingObjects[model] = {
		baseCFrame = baseCFrame,
		floatHeight = floatHeight,
		floatSpeed = floatSpeed,
		phaseOffset = math.random() * math.pi * 2, -- Random starting phase for variety
		chunkKey = chunkKey,
		shouldRotate = shouldRotate,
		rotateSpeed = rotateSpeed,
		rotationAngle = 0, -- Current rotation angle
	}
	
	-- Add to spatial partitioning
	addToChunk(model, chunkKey)
	
	-- Immediately check if should be active (don't wait for distance check interval)
	if playerPosition then
		local modelPos = model.PrimaryPart.Position
		local dx = modelPos.X - playerPosition.X
		local dz = modelPos.Z - playerPosition.Z
		local distance = math.sqrt(dx * dx + dz * dz)
		
		if distance <= ACTIVATION_DISTANCE then
			table.insert(activeObjects, model)
		end
	end
end

--[[
	Stop floating animation for a model
	@param model Model
]]
local function stopFloating(model: Model)
	local data = floatingObjects[model]
	if not data then return end
	
	-- Reset to base position
	if model and model.Parent then
		pcall(function()
			model:PivotTo(data.baseCFrame)
		end)
	end
	
	-- Remove from spatial partitioning
	removeFromChunk(model, data.chunkKey)
	
	-- Remove from active list
	for i, activeModel in ipairs(activeObjects) do
		if activeModel == model then
			table.remove(activeObjects, i)
			break
		end
	end
	
	-- Clean up data
	floatingObjects[model] = nil
end

--[[
	Update which objects should be actively animated based on player distance
	Uses spatial partitioning to only check nearby chunks
	Called when player moves to a new position
]]
local function updateActiveObjects()
	if not playerPosition then return end
	
	-- Clear active list
	table.clear(activeObjects)
	
	-- Get nearby chunks based on NEW player position
	local playerChunk = getChunkKey(playerPosition)
	local nearbyChunks = getNearbyChunkKeys(playerChunk)
	
	-- Only check models in nearby chunks (models are static, no need to recalculate their positions)
	for _, chunkKey in ipairs(nearbyChunks) do
		local chunkModels = chunks[chunkKey]
		if chunkModels then
			for _, model in ipairs(chunkModels) do
				-- Validate model still exists
				if not model or not model.Parent or not floatingObjects[model] then
					continue
				end
				
				-- Horizontal distance check only (ignore Y-axis)
				-- Use cached baseCFrame position (models don't move!)
				local modelPos = floatingObjects[model].baseCFrame.Position
				local dx = modelPos.X - playerPosition.X
				local dz = modelPos.Z - playerPosition.Z
				local distance = math.sqrt(dx * dx + dz * dz)
				
				if distance <= ACTIVATION_DISTANCE then
					table.insert(activeObjects, model)
				end
			end
		end
	end
end

--[[
	Update floating animations for all active objects
	@param currentTime number - os.clock() value
	@param deltaTime number - Time since last frame
]]
local function updateFloatingAnimations(currentTime: number, deltaTime: number)
	for _, model in ipairs(activeObjects) do
		local data = floatingObjects[model]
		if not data or not model.Parent then
			continue
		end
		
		-- Calculate sine wave offset (0 to 1 range, always positive)
		local wave = (math.sin((currentTime * data.floatSpeed) + data.phaseOffset) + 1) / 2
		local yOffset = wave * data.floatHeight
		
		-- Calculate rotation if enabled (world Y-axis spin)
		local rotation = CFrame.identity
		if data.shouldRotate then
			-- Increment rotation angle based on deltaTime
			data.rotationAngle = data.rotationAngle + (data.rotateSpeed * deltaTime)
			-- Keep angle in 0-360 range
			if data.rotationAngle >= 360 then
				data.rotationAngle = data.rotationAngle - 360
			end
			rotation = CFrame.Angles(0, math.rad(data.rotationAngle), 0)
		end
		
		-- Apply floating motion in global space (world up/down) + base rotation + optional spin
		local basePos = data.baseCFrame.Position
		local baseRotation = data.baseCFrame - data.baseCFrame.Position
		local newPosition = basePos + Vector3.new(0, yOffset, 0)
		model:PivotTo(CFrame.new(newPosition) * baseRotation * rotation)
	end
end

--[[
	Initialize the floating animation system
]]
function Module:Init()
	local lastPlayerUpdate = 0
	local currentTime = os.clock()
	
	-- Main update loop (RenderStepped for smooth 60fps animation)
	RunService.RenderStepped:Connect(function(deltaTime)
		currentTime = currentTime + deltaTime
		
		-- Update player position and recalculate active objects when player moves
		if currentTime - lastPlayerUpdate >= PLAYER_UPDATE_INTERVAL then
			character = player.Character
			humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
			playerPosition = humanoidRootPart and humanoidRootPart.Position
			
			-- Recalculate which objects should be active (only when player moves)
			updateActiveObjects()
			
			lastPlayerUpdate = currentTime
		end
		
		-- Update floating animations every frame for smooth motion
		updateFloatingAnimations(currentTime, deltaTime)
	end)
	
	-- Handle Float tag added
	CollectionService:GetInstanceAddedSignal("Float"):Connect(function(instance)
		if instance:IsA("Model") then
			task.spawn(startFloating, instance)
		end
	end)
	
	-- Handle Float tag removed
	CollectionService:GetInstanceRemovedSignal("Float"):Connect(function(instance)
		if instance:IsA("Model") then
			stopFloating(instance)
		end
	end)
	
	-- Initialize already tagged models
	for _, model in ipairs(CollectionService:GetTagged("Float")) do
		if model:IsA("Model") then
			task.spawn(startFloating, model)
		end
	end
end

return Module
