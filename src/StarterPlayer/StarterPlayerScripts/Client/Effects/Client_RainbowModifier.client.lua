--[[
	Client_RainbowModifier
	Animates Rainbow modifier effects on brainrots using SurfaceAppearance.Color
	Optimized: Distance checked every 1s, color updates at 20Hz if in range
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local TAG = "Rainbow"
local RAINBOW_PERIOD = 6 -- Complete cycle duration (seconds)
local UPDATE_HZ = 20 -- Updates per second (50ms intervals)
local UPDATE_DT = 1 / UPDATE_HZ

-- Distance culling threshold (2D, ignoring height)
local MAX_DISTANCE = 200
local MAX_DISTANCE_SQ = MAX_DISTANCE * MAX_DISTANCE

-- Distance check frequency
local DISTANCE_CHECK_INTERVAL = 1.0 -- Check distance every 1 second
local BATCH_COUNT = 4 -- Spread distance checks across 4 batches (250ms per batch)
local currentBatch = 0

local trackedSAs = {} -- [SurfaceAppearance] = {lastUpdate = 0, lastDistanceCheck = 0, inRange = true, batchIndex = 0}
local connsByRoot = {} -- [Instance] = {RBXScriptConnection}
local nextBatchIndex = 0

--[[
	Calculate 2D distance squared (ignoring Y-axis)
	@param pos1 Vector3
	@param pos2 Vector3
	@return number
]]
local function distance2DSq(pos1, pos2)
	local dx = pos1.X - pos2.X
	local dz = pos1.Z - pos2.Z
	return dx * dx + dz * dz
end

--[[
	Track a SurfaceAppearance for rainbow animation
	@param sa SurfaceAppearance
]]
local function trackSA(sa)
	trackedSAs[sa] = {
		lastUpdate = 0,
		lastDistanceCheck = 0,
		inRange = true, -- Assume in range initially
		batchIndex = nextBatchIndex
	}
	
	-- Round-robin batch assignment
	nextBatchIndex = (nextBatchIndex + 1) % BATCH_COUNT
	
	if not connsByRoot[sa] then
		connsByRoot[sa] = {}
	end
	
	-- Cleanup when SurfaceAppearance is destroyed
	table.insert(connsByRoot[sa], sa.AncestryChanged:Connect(function(_, parent)
		if not parent then
			trackedSAs[sa] = nil
			for _, c in ipairs(connsByRoot[sa] or {}) do
				pcall(function() c:Disconnect() end)
			end
			connsByRoot[sa] = nil
		end
	end))
end

--[[
	Start tracking tagged SurfaceAppearances
	@param sa SurfaceAppearance
]]
local function addSurfaceAppearance(sa)
	if not sa:IsA("SurfaceAppearance") then return end
	trackSA(sa)
end

--[[
	Stop tracking an instance
	@param root Instance
]]
local function stopForRoot(root)
	for _, c in ipairs(connsByRoot[root] or {}) do
		pcall(function() c:Disconnect() end)
	end
	connsByRoot[root] = nil
	
	if root:IsA("SurfaceAppearance") then
		trackedSAs[root] = nil
	end
end

--[[
	Get position of a SurfaceAppearance (from parent part)
	@param sa SurfaceAppearance
	@return Vector3?
]]
local function getSAPosition(sa)
	local parent = sa.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	end
	return nil
end

-- Initialize: Track all existing tagged SurfaceAppearances
for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
	if inst:IsA("SurfaceAppearance") then
		addSurfaceAppearance(inst)
	end
end

-- Listen for new tagged instances
CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
	if inst:IsA("SurfaceAppearance") then
		addSurfaceAppearance(inst)
	end
end)

-- Listen for removed tags
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
	stopForRoot(inst)
end)

-- Animation loop: Distance checked every 1s, color updates at 20Hz
task.spawn(function()
	local acc = 0
	local t = 0
	
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc < UPDATE_DT then return end
		
		t = t + acc
		acc = 0
		
		-- Calculate HSV hue (0-1) based on time
		local h = (t / RAINBOW_PERIOD) % 1
		local tint = Color3.fromHSV(h, 1, 1)
		
		-- Get camera position for distance checks (only X and Z)
		local camPos = Camera.CFrame.Position
		
		-- Cycle through batches for distance checks
		currentBatch = (currentBatch + 1) % BATCH_COUNT
		
		-- Update tracked SurfaceAppearances
		for sa, data in pairs(trackedSAs) do
			if not sa.Parent then
				trackedSAs[sa] = nil
				continue
			end
			
			-- Check distance only for current batch and only every 1 second
			if data.batchIndex == currentBatch and (t - data.lastDistanceCheck) >= DISTANCE_CHECK_INTERVAL then
				local saPos = getSAPosition(sa)
				if saPos then
					-- 2D distance check (ignore Y-axis, use squared magnitude)
					local distSq = distance2DSq(camPos, saPos)
					
					-- Update range status (either play or don't play, no LOD)
					data.inRange = distSq <= MAX_DISTANCE_SQ
					
					data.lastDistanceCheck = t
				end
			end
			
			-- Skip color update if out of range
			if not data.inRange then
				continue
			end
			
			-- Check if enough time has passed for this SA's update rate
			if t - data.lastUpdate < UPDATE_DT then
				continue
			end
			
			-- Update color
			sa.Color = tint
			data.lastUpdate = t
		end
	end)
end)
