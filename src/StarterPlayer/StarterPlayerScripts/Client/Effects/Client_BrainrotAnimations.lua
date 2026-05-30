--// Client_BrainrotAnimations - Zone-based animation system for brainrots
--// Plays animations only for brainrots in active zones/plots within range

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Module = {}

-- Configuration
local ZONE_ACTIVATION_DISTANCE = 150  -- Studs from closest zone spawner (X-axis)
local PLOT_ACTIVATION_DISTANCE = 75   -- Studs from plot center (2D, no Y)
local UPDATE_INTERVAL = 0.5           -- Check zones/plots every 0.5s

-- Map rarity names (from CurrentZone attribute) to spawner zone IDs
-- Based on Shared_ZoneConfig: Zone1=Common, Zone2=Rare, Zone3=Epic, etc.
local RARITY_TO_ZONE_MAP = {
	Common = "Zone1",      -- SafeZone/spawn area + first play zone
	Safe = "Zone1",        -- SafeZone2 in play area (uses Zone1 spawners)
	Rare = "Zone2",        -- Rare zone
	Epic = "Zone3",        -- Epic zone
	Legendary = "Zone4",   -- Legendary zone
	Mythical = "Zone5",    -- Mythical zone
	Secret = "Zone6",      -- Secret zone
	Celestial = "Zone7",   -- Celestial zone
}

-- Data structures
local animationTracks = {}   -- [model] = {idleTrack, walkTrack, configName, isMoving}
local activeZones = {}       -- Set of active zone names {"Zone1" = true, "Zone2" = true}
local activePlots = {}       -- Set of active plot names
local movementConnections = {} -- [model] = connection
local movementLerpConnections = {} -- [model] = {connection, startPos, targetPos, startTime, duration}

-- Cached zone/plot data from server (streaming-proof)
local cachedZonePositions = {}  -- {Rare = Vector3, Epic = Vector3, ...}
local cachedPlotPositions = {}  -- {Plot1 = Vector3, Plot2 = Vector3, ...}

local function refreshPlotPositionsFromWorkspace()
	local gameFolder = Workspace:FindFirstChild("Game")
	local plotsFolder = gameFolder and gameFolder:FindFirstChild("Plots")
	if not plotsFolder then
		return
	end

	for _, plotModel in ipairs(plotsFolder:GetChildren()) do
		if plotModel:IsA("Model") then
			local teleportPart = plotModel:FindFirstChild("TeleportPart")
			if teleportPart and teleportPart:IsA("BasePart") then
				cachedPlotPositions[plotModel.Name] = teleportPart.Position
			end
		end
	end
end

-- Player references
local player = Players.LocalPlayer
local playerPosition

--[[
	Start client-side movement lerping for a brainrot
	Server sets attributes, client handles smooth interpolation
	Uses 60 FPS for active zones, 10 FPS for inactive zones (performance optimization)
	@param model Model
]]
local function startMovementLerp(model)
	-- Stop any existing lerp
	if movementLerpConnections[model] then
		if movementLerpConnections[model].connection then
			movementLerpConnections[model].connection:Disconnect()
		end
		movementLerpConnections[model] = nil
	end
	
	-- Check if this brainrot is in an active zone (same logic as animations)
	local isInActiveZone = false
	local tags = CollectionService:GetTags(model)
	for _, tag in ipairs(tags) do
		-- Check zone tags (Zone1_Brainrot through Zone7_Brainrot)
		local zoneName = tag:match("^(Zone%d+)_Brainrot$")
		if zoneName and activeZones[zoneName] then
			isInActiveZone = true
			break
		end
		
		-- Check plot tags (Plot1_Brainrot through Plot6_Brainrot)
		local plotName = tag:match("^(Plot%d+)_Brainrot$")
		if plotName and activePlots[plotName] then
			isInActiveZone = true
			break
		end
		
		-- Check dropped tag (always smooth)
		if tag == "DroppedBrainrot" then
			isInActiveZone = true
			break
		end
	end
	
	-- Get movement data from attributes (set by server)
	local targetPos = model:GetAttribute("TargetPosition")
	local duration = model:GetAttribute("WalkDuration")
	
	if not targetPos or not duration or not model.PrimaryPart then
		return
	end
	
	-- Store start position and time
	local startPos = model.PrimaryPart.Position
	local startCFrame = model:GetPivot()
	local startTime = tick()
	
	-- Calculate final CFrame (preserve rotation toward target)
	local lookAtCFrame = CFrame.lookAt(startPos, Vector3.new(targetPos.X, startPos.Y, targetPos.Z))
	local finalCFrame = CFrame.new(targetPos) * (lookAtCFrame - lookAtCFrame.Position)
	
	-- Choose update rate: 60 FPS for active zones, 10 FPS for inactive zones
	local updateRate = isInActiveZone and (1/60) or (1/10)
	
	-- Start lerping with appropriate framerate
	local running = true
	local lerpTask = task.spawn(function()
		while running do
			task.wait(updateRate)
			
			if not model or not model.Parent or not model.PrimaryPart then
				running = false
				movementLerpConnections[model] = nil
				return
			end
			
			-- Check if server stopped movement
			if not model:GetAttribute("IsMoving") then
				running = false
				movementLerpConnections[model] = nil
				return
			end
			
			local elapsed = tick() - startTime
			local alpha = math.clamp(elapsed / duration, 0, 1)
			
			-- Lerp to target
			local lerpedCFrame = startCFrame:Lerp(finalCFrame, alpha)
			model:PivotTo(lerpedCFrame)
			
			-- Stop when complete (server will also set IsMoving = false)
			if alpha >= 1 then
				running = false
				movementLerpConnections[model] = nil
			end
		end
	end)
	
	movementLerpConnections[model] = {
		task = lerpTask,
		running = running,
		startPos = startPos,
		targetPos = targetPos,
		startTime = startTime,
		duration = duration,
		updateRate = updateRate
	}
end

--[[
	Stop client-side movement lerping for a brainrot
	@param model Model
]]
local function stopMovementLerp(model)
	if movementLerpConnections[model] then
		if movementLerpConnections[model].task then
			task.cancel(movementLerpConnections[model].task)
		end
		movementLerpConnections[model] = nil
	end
end

--[[
	Load idle and walk animation tracks for a brainrot model
	@param model Model
	@return AnimationTrack?, AnimationTrack? - Idle track, Walk track
]]
local function loadAnimationTracks(model)
	-- Get config name from model (attribute for plot brainrots, name for world brainrots)
	local configName = model:GetAttribute("ConfigName") or model.Name
	
	-- Find animations folder for this brainrot
	local animFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("Animations")
		and ReplicatedStorage.Assets.Animations:FindFirstChild(configName)
	
	if not animFolder then
		return nil, nil
	end
	
	local animController = model:FindFirstChildWhichIsA("AnimationController", true)
		or model:FindFirstChildWhichIsA("Humanoid", true)
	if not animController then
		animController = Instance.new("AnimationController")
		animController.Parent = model
	end

	local animator = animController:FindFirstChildWhichIsA("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animController
	end
	
	-- Load idle animation
	local idleAnim = animFolder:FindFirstChild("Idle")
	local idleTrack = nil
	if idleAnim and idleAnim:IsA("Animation") then
		idleTrack = animator:LoadAnimation(idleAnim)
		idleTrack.Priority = Enum.AnimationPriority.Idle
		idleTrack.Looped = true
	end
	
	-- Load walk/move animation (try both names)
	local walkAnim = animFolder:FindFirstChild("Walk")
	local walkTrack = nil
	if walkAnim and walkAnim:IsA("Animation") then
		walkTrack = animator:LoadAnimation(walkAnim)
		walkTrack.Priority = Enum.AnimationPriority.Movement
		walkTrack.Looped = true
	end
	
	return idleTrack, walkTrack
end

--[[
	Start animations for a brainrot if it's in an active zone/plot
	@param model Model
]]
local function startAnimationIfActive(model)
	local trackData = animationTracks[model]
	if not trackData then return end
	
	-- Check if this brainrot is in an active zone
	local tags = CollectionService:GetTags(model)
	for _, tag in ipairs(tags) do
		-- Check zone tags (Zone1_Brainrot through Zone7_Brainrot)
		local zoneName = tag:match("^(Zone%d+)_Brainrot$")
		if zoneName and activeZones[zoneName] then
			-- In active zone - start appropriate animation
			local isMoving = model:GetAttribute("IsMoving") == true
			if isMoving and trackData.walkTrack and not trackData.walkTrack.IsPlaying then
				trackData.walkTrack:Play(0.1, 1, 1)
				trackData.isMoving = true
			elseif trackData.idleTrack and not trackData.idleTrack.IsPlaying then
				trackData.idleTrack:Play(0.1, 1, 1)
				trackData.isMoving = false
			end
			return
		end
		
		-- Check plot tags (Plot1_Brainrot through Plot6_Brainrot)
		local plotName = tag:match("^(Plot%d+)_Brainrot$")
		if plotName and activePlots[plotName] then
			-- In active plot - start idle (plots don't move)
			if trackData.idleTrack and not trackData.idleTrack.IsPlaying then
				trackData.idleTrack:Play(0, 1, 1)
				trackData.idleTrack:AdjustSpeed(1)
			end
			return
		end
		
		-- Check dropped tag
		if tag == "DroppedBrainrot" then
			-- Dropped brainrots always animate
			if trackData.idleTrack and not trackData.idleTrack.IsPlaying then
				trackData.idleTrack:Play(0.1, 1, 1)
			end
			return
		end
	end
end

--[[
	Register a brainrot model for animation management
	@param model Model
]]
local function registerBrainrot(model)
	if not model or not model:IsA("Model") then return end
	if animationTracks[model] then return end -- Already registered
	
	-- Load animation tracks
	local idleTrack, walkTrack = loadAnimationTracks(model)
	if not idleTrack then return end -- Need at least idle animation
	
	-- Store tracks and movement state (paused initially)
	animationTracks[model] = {
		idleTrack = idleTrack,
		walkTrack = walkTrack,
		configName = model.Name,
		isMoving = false,
	}
	
	-- If brainrot spawned in an already-active zone/plot, start animations immediately
	task.defer(startAnimationIfActive, model)
	
	-- Listen to IsMoving attribute changes (set by server)
	if walkTrack then
		local connection = model:GetAttributeChangedSignal("IsMoving"):Connect(function()
			local trackData = animationTracks[model]
			if not trackData or not model.Parent then
				-- Model removed, disconnect
				if movementConnections[model] then
					movementConnections[model]:Disconnect()
					movementConnections[model] = nil
				end
				stopMovementLerp(model)
				return
			end
			
			-- Get movement state from server attribute
			local isMoving = model:GetAttribute("IsMoving") == true
			
			-- Handle client-side movement lerping
			if isMoving then
				-- Started moving - start client-side lerp
				startMovementLerp(model)
			else
				-- Stopped moving - stop client-side lerp
				stopMovementLerp(model)
			end
			
			-- Only respond to attribute changes if animations are currently active (zone is active)
			local isActive = (trackData.idleTrack and trackData.idleTrack.IsPlaying) or 
			                  (trackData.walkTrack and trackData.walkTrack.IsPlaying)
			
			if not isActive then
				-- Not in active zone, don't switch animations
				return
			end
			
			-- Switch animations based on movement
			if isMoving and not trackData.isMoving then
				-- Started moving - switch to walk
				trackData.isMoving = true
				if trackData.idleTrack and trackData.idleTrack.IsPlaying then
					trackData.idleTrack:Stop(0.1)
				end
				if trackData.walkTrack and not trackData.walkTrack.IsPlaying then
					trackData.walkTrack:Play(0.1, 1, 1)
				end
				
			elseif not isMoving and trackData.isMoving then
				-- Stopped moving - switch to idle
				trackData.isMoving = false
				if trackData.walkTrack and trackData.walkTrack.IsPlaying then
					trackData.walkTrack:Stop(0.1)
				end
				if trackData.idleTrack and not trackData.idleTrack.IsPlaying then
					trackData.idleTrack:Play(0.1, 1, 1)
				end
			end
		end)
		
		movementConnections[model] = connection
	end
end

--[[
	Unregister a brainrot when it's removed
	@param model Model
]]
local function unregisterBrainrot(model)
	local trackData = animationTracks[model]
	if trackData then
		if trackData.idleTrack then
			trackData.idleTrack:Stop()
			trackData.idleTrack:Destroy()
		end
		if trackData.walkTrack then
			trackData.walkTrack:Stop()
			trackData.walkTrack:Destroy()
		end
	end
	animationTracks[model] = nil
	
	-- Disconnect movement detection
	if movementConnections[model] then
		movementConnections[model]:Disconnect()
		movementConnections[model] = nil
	end
	
	-- Stop and cleanup client-side movement lerping
	stopMovementLerp(model)
end

--[[
	Get active zones (current zone + adjacent zones)
	Simple rule: Current zone + 1 behind + 1 ahead
	@return {string} - Array of zone IDs (Zone1, Zone2, etc.)
]]
local function getActiveZones()
	if not playerPosition then
		return {}
	end
	
	local activeZoneIDs = {}
	local activeZoneSet = {}
	
	-- Get current zone from server attribute and map to zone ID
	local currentRarity = player:GetAttribute("CurrentZone")
	local currentZoneID = currentRarity and RARITY_TO_ZONE_MAP[currentRarity]
	local isPlaying = player:GetAttribute("IsPlaying")
	
	-- If no CurrentZone set at all, no animations
	if not currentZoneID then
		return {}
	end
	
	-- SafeZone: IsPlaying = false AND CurrentZone = "Common" → Only Zone1
	if not isPlaying and currentRarity == "Common" then
		table.insert(activeZoneIDs, "Zone1")
		return activeZoneIDs
	end
	
	-- SafeZone2: CurrentZone = "Safe" → Only Zone7 (regardless of IsPlaying)
	if currentRarity == "Safe" then
		table.insert(activeZoneIDs, "Zone7")
		return activeZoneIDs
	end
	
	-- Add current zone
	table.insert(activeZoneIDs, currentZoneID)
	activeZoneSet[currentZoneID] = true
	
	-- Extract zone number (e.g., "Zone3" -> 3)
	local zoneNum = tonumber(currentZoneID:match("%d+"))
	if not zoneNum then return activeZoneIDs end
	
	-- Add zone behind (if exists)
	if zoneNum > 1 then
		local behindZoneID = "Zone" .. (zoneNum - 1)
		if not activeZoneSet[behindZoneID] then
			table.insert(activeZoneIDs, behindZoneID)
			activeZoneSet[behindZoneID] = true
		end
	end
	
	-- Add zone ahead (if exists, max Zone7)
	if zoneNum < 7 then
		local aheadZoneID = "Zone" .. (zoneNum + 1)
		if not activeZoneSet[aheadZoneID] then
			table.insert(activeZoneIDs, aheadZoneID)
			activeZoneSet[aheadZoneID] = true
		end
	end
	
	return activeZoneIDs
end

--[[
	Get all plots within activation distance (2D distance, ignore Y)
	Uses cached plot positions from server
	@return {string} - Array of plot names
]]
local function getActivePlots()
	if not playerPosition then
		return {}
	end
	
	local plots = {}
	
	for plotName, plotPos in pairs(cachedPlotPositions) do
		-- 2D distance (ignore Y axis)
		local distance2D = math.sqrt(
			(plotPos.X - playerPosition.X)^2 + 
			(plotPos.Z - playerPosition.Z)^2
		)
		
		if distance2D <= PLOT_ACTIVATION_DISTANCE then
			table.insert(plots, plotName)  -- "Plot1", "Plot2", etc.
		end
	end
	
	return plots
end

--[[
	Update which zones and plots are active
	Plays/pauses animations based on proximity
]]
local function updateActiveRegions()
	if not playerPosition then return end
	
	-- Get active zones (current + closest within 150 studs)
	local newActiveZones = getActiveZones()
	
	-- Convert to set for fast lookup
	local newActiveZoneSet = {}
	for _, zoneName in ipairs(newActiveZones) do
		newActiveZoneSet[zoneName] = true
	end
	
	-- Get active plots
	local newActivePlots = getActivePlots()
	
	-- Convert plot array to set for fast lookup
	local activePlotSet = {}
	for _, plotName in ipairs(newActivePlots) do
		activePlotSet[plotName] = true
	end
	
	-- Update zone brainrot animations
	-- Use hardcoded zone list (streaming-proof - no need to check spawners)
	local ALL_ZONES = {"Zone1", "Zone2", "Zone3", "Zone4", "Zone5", "Zone6", "Zone7"}
	for _, zoneName in ipairs(ALL_ZONES) do
		local zoneTag = zoneName .. "_Brainrot"
		local shouldBeActive = newActiveZoneSet[zoneName] == true
		local wasActive = activeZones[zoneName] == true
		
		-- Only update if state changed (newly spawned brainrots handled by GetInstanceAddedSignal)
		if shouldBeActive ~= wasActive then
			if shouldBeActive then
				-- Activate this zone
				for _, model in ipairs(CollectionService:GetTagged(zoneTag)) do
						local trackData = animationTracks[model]
						if trackData then
							-- Check server's IsMoving attribute to play appropriate animation
							local isMoving = model:GetAttribute("IsMoving") == true
							
							-- Only start animations if they're not already playing
							if isMoving and trackData.walkTrack then
								-- Currently moving - play walk
								if not trackData.walkTrack.IsPlaying then
									trackData.walkTrack:Play(0.1, 1, 1)
								end
								trackData.isMoving = true
							else
								-- Stationary - play idle
								if trackData.idleTrack and not trackData.idleTrack.IsPlaying then
									trackData.idleTrack:Play(0.1, 1, 1)
								end
								trackData.isMoving = false
							end
						end
					end
				elseif wasActive and not shouldBeActive then
					-- Deactivate this zone
					for _, model in ipairs(CollectionService:GetTagged(zoneTag)) do
						local trackData = animationTracks[model]
						if trackData then
							-- STOP animations completely
							if trackData.idleTrack and trackData.idleTrack.IsPlaying then
								trackData.idleTrack:Stop()
							end
							if trackData.walkTrack and trackData.walkTrack.IsPlaying then
								trackData.walkTrack:Stop()
							end
							trackData.isMoving = false
						end
					end
				end
			end
		end
	
	-- Update active zones tracker
	activeZones = newActiveZoneSet
	
	-- Update active plots tracker
	activePlots = activePlotSet
	
	-- Update plot brainrot animations
	-- Check all plots and toggle based on active set
	for i = 1, 6 do  -- 6 total plots
		local plotName = "Plot" .. i
		local plotTag = plotName .. "_Brainrot"
		local isActive = activePlotSet[plotName] == true
		
		for _, model in ipairs(CollectionService:GetTagged(plotTag)) do
			local trackData = animationTracks[model]
			if trackData then
				if isActive then
					-- Activate - resume idle (plot brainrots don't move)
					if trackData.idleTrack then
						if not trackData.idleTrack.IsPlaying then
							trackData.idleTrack:Play(0, 1, 1)
						end
						trackData.idleTrack:AdjustSpeed(1)
					end
				else
					-- Deactivate - pause animations
					if trackData.idleTrack then
						trackData.idleTrack:AdjustSpeed(0)
					end
				end
			end
		end
	end
	
	-- Always animate dropped brainrots (they're near player who dropped them)
	for _, model in ipairs(CollectionService:GetTagged("DroppedBrainrot")) do
		local trackData = animationTracks[model]
		if trackData then
			-- Dropped brainrots don't move, just idle
			if trackData.idleTrack and not trackData.idleTrack.IsPlaying then
				trackData.idleTrack:Play(0.1, 1, 1)
			end
		end
	end
end

--[[
	Initialize animation system
]]
function Module:Init()
	-- Request zone/plot positions from server (streaming-proof, one-time call)
	local Events = ReplicatedStorage:WaitForChild("Events")
	local ZoneInfo = Events:WaitForChild("ZoneInfo")
	
	local success, data = pcall(function()
		return ZoneInfo:InvokeServer()
	end)
	
	if success and data then
		cachedZonePositions = data.Zones or {}
		cachedPlotPositions = data.Plots or {}
	else
		warn("⚠️ Client_BrainrotAnimations: Failed to get zone/plot data from server")
	end
	refreshPlotPositionsFromWorkspace()
	
	-- Wait for initial character spawn
	local character = player.Character or player.CharacterAdded:Wait()
	local hrp = character:WaitForChild("HumanoidRootPart")
	
	-- Register all zone brainrot tags (Zone1_Brainrot through Zone7_Brainrot)
	for i = 1, 7 do
		local zoneTag = "Zone" .. i .. "_Brainrot"
		
		-- Handle existing brainrots
		for _, model in ipairs(CollectionService:GetTagged(zoneTag)) do
			task.spawn(registerBrainrot, model)
		end
		
		-- Monitor new brainrots
		CollectionService:GetInstanceAddedSignal(zoneTag):Connect(function(instance)
			if instance:IsA("Model") then
				task.spawn(registerBrainrot, instance)
			end
		end)
		
		-- Handle removals
		CollectionService:GetInstanceRemovedSignal(zoneTag):Connect(function(instance)
			if instance:IsA("Model") then
				unregisterBrainrot(instance)
			end
		end)
	end
	
	-- Register all plot brainrot tags (Plot1_Brainrot through Plot6_Brainrot)
	for i = 1, 6 do
		local plotTag = "Plot" .. i .. "_Brainrot"
		
		-- Handle existing brainrots
		for _, model in ipairs(CollectionService:GetTagged(plotTag)) do
			task.spawn(registerBrainrot, model)
		end
		
		-- Monitor new brainrots
		CollectionService:GetInstanceAddedSignal(plotTag):Connect(function(instance)
			if instance:IsA("Model") then
				task.spawn(registerBrainrot, instance)
			end
		end)
		
		-- Handle removals
		CollectionService:GetInstanceRemovedSignal(plotTag):Connect(function(instance)
			if instance:IsA("Model") then
				unregisterBrainrot(instance)
			end
		end)
	end
	
	-- Register dropped brainrots
	for _, model in ipairs(CollectionService:GetTagged("DroppedBrainrot")) do
		task.spawn(registerBrainrot, model)
	end
	
	CollectionService:GetInstanceAddedSignal("DroppedBrainrot"):Connect(function(instance)
		if instance:IsA("Model") then
			task.spawn(registerBrainrot, instance)
		end
	end)
	
	CollectionService:GetInstanceRemovedSignal("DroppedBrainrot"):Connect(function(instance)
		if instance:IsA("Model") then
			unregisterBrainrot(instance)
		end
	end)
	
	-- Update loop (checks zones/plots every 0.5s)
	local lastUpdate = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		
		if now - lastUpdate >= UPDATE_INTERVAL then
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			playerPosition = hrp and hrp.Position
			
		if playerPosition then
			refreshPlotPositionsFromWorkspace()
			updateActiveRegions()
		end
		
		lastUpdate = now
	end
	end)
end

return Module
