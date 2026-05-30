--[[
	Client_MovementDetector.lua
	
	Phase 3: Client-side movement detection at 30 Hz
	- Detects player movement during red light
	- Sends "PlayerMoved" event to server (push-based, not polling)
	- Reduces server load by offloading detection to client
	- Client handles authority of "did I move", server handles consequence
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Player = Players.LocalPlayer

local Module = {}

-- Configuration
local CONFIG = {
	DetectionRate = 30, -- Hz (checks per second)
	MovementThreshold = 0.01, -- Same as server
	PositionThreshold = 0.05, -- Horizontal movement threshold
}

-- State
local LastPosition = nil
local LastCheckTime = 0
local IsDetecting = false

-- Events
local Events = ReplicatedStorage:WaitForChild("Events")
local GuardHandler = Events:WaitForChild("GuardHandler")

--[[
	Check if player is moving (client-side)
]]
local function isPlayerMoving()
	local character = Player.Character
	if not character then return false end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end
	
	-- Check player input (keyboard/controller)
	local isInputMoving = humanoid.MoveDirection.Magnitude > CONFIG.MovementThreshold
	
	-- Check jumping states
	local state = humanoid:GetState()
	local isJumping = state == Enum.HumanoidStateType.Jumping 
		or state == Enum.HumanoidStateType.Freefall
	
	-- Check actual velocity (catches slaps, pushes, physics movement)
	local velocity = rootPart.AssemblyLinearVelocity
	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local isPhysicsMoving = horizontalVelocity.Magnitude > CONFIG.MovementThreshold * 10
	
	-- Check position change over time (catches micro-movements and cheesing)
	local currentPos = rootPart.Position
	local isPositionChanged = false
	
	if LastPosition then
		local horizontalDelta = Vector3.new(
			currentPos.X - LastPosition.X,
			0,
			currentPos.Z - LastPosition.Z
		)
		-- Very sensitive threshold - any movement gets detected
		isPositionChanged = horizontalDelta.Magnitude > CONFIG.PositionThreshold
	end
	
	-- Update last position
	LastPosition = currentPos
	
	return isInputMoving or isJumping or isPhysicsMoving or isPositionChanged
end

--[[
	Start movement detection loop (30 Hz)
]]
local function startDetection()
	if IsDetecting then return end
	IsDetecting = true
	
	local detectionInterval = 1 / CONFIG.DetectionRate
	
	RunService.Heartbeat:Connect(function()
		if not IsDetecting then return end
		
		-- Throttle to 30 Hz
		local now = tick()
		if now - LastCheckTime < detectionInterval then return end
		LastCheckTime = now
		
		-- Only detect during red light AND when playing
		if Workspace:GetAttribute("GameState") ~= "RedLight" then 
			LastPosition = nil -- Reset when not red light
			return 
		end
		
		if not Player:GetAttribute("IsPlaying") then 
			LastPosition = nil
			return 
		end
		
		-- Check movement and send to server if detected
		if isPlayerMoving() then
			GuardHandler:FireServer("PlayerMoved")
		end
	end)
end

--[[
	Initialize
]]
function Module:Init()
	-- Start detection immediately
	startDetection()
	
end

return Module
