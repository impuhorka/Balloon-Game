--[[
	Client_FOV.lua
	Priority-based FOV system: handles running, frame zoom, and effect locks.
	Priority (highest to lowest): FOV Lock > Frame Zoom > Running FOV
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local BASE_WALKSPEED = 16  -- Match Server_CharacterStats base
local BASE_FOV = 70
local FRAME_ZOOM_FOV = 60  -- FOV when UI frame is open (lower = zoomed in)

-- TweenInfos
local FOV_TWEEN_RUN = TweenInfo.new(0.5, Enum.EasingStyle.Exponential)
local FOV_TWEEN_FRAME_OPEN = TweenInfo.new(0.3, Enum.EasingStyle.Linear)
local FOV_TWEEN_FRAME_CLOSE = TweenInfo.new(0.15, Enum.EasingStyle.Linear)

local Module = {}
local Character = nil
local Humanoid = nil
local LastFOV = BASE_FOV
local ActiveTween = nil

-- Priority system
local FOVLocked = false       -- Highest priority: external effects
local FrameZoomActive = false -- Middle priority: UI frames
local RunDesiredFOV = BASE_FOV -- Lowest priority: running speed
local BalloonFloatFOVBoost = 0 -- additive while floating / parachuting
local SpeedBoostFovNarrow = 0 -- subtractive speed-tunnel FOV (boosters / propeller)
local PrevSpeedBoostFovNarrow = 0
local MIN_FOV = 48
local FOV_NARROW_TWEEN_IN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FOV_NARROW_TWEEN_OUT = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MAX_FOV = 100

local FOVLockTimer = nil

-- Update FOV based on current priority state
local function updateFOV(customTweenInfo)
	if FOVLocked then 
		return -- External effect owns FOV, don't touch
	end
	
	local targetFOV
	local tweenInfo = customTweenInfo or FOV_TWEEN_RUN
	
	if FrameZoomActive then
		targetFOV = FRAME_ZOOM_FOV
	else
		targetFOV = RunDesiredFOV + BalloonFloatFOVBoost - SpeedBoostFovNarrow
	end
	targetFOV = math.clamp(targetFOV, MIN_FOV, MAX_FOV)
	
	if math.abs(targetFOV - LastFOV) < 0.5 then return end
	LastFOV = targetFOV
	if ActiveTween then ActiveTween:Cancel() end
	ActiveTween = TweenService:Create(Camera, tweenInfo, { FieldOfView = targetFOV })
	ActiveTween:Play()
end

local function setupRunningFOV()
	if not Humanoid or not Humanoid.Parent then return end

	Humanoid.Running:Connect(function(speed)
		if FOVLocked then return end -- Don't update during lock
		
		local ratio = speed / BASE_WALKSPEED
		RunDesiredFOV = BASE_FOV + ratio
		
		updateFOV() -- Will use RunDesiredFOV only if FrameZoomActive is false
	end)
end

local function onCharacterAdded(character)
	Character = character
	Humanoid = character:WaitForChild("Humanoid", 10)
	if not Humanoid then return end
	LastFOV = Camera.FieldOfView
	RunDesiredFOV = LastFOV
	setupRunningFOV()
end

-- ========================================
-- PUBLIC API
-- ========================================

--- Activate/deactivate frame zoom (called by Client_Frames)
function Module:SetFrameZoomActive(active)
	FrameZoomActive = active
	
	if active then
		-- Frame opening: use frame-open tween
		updateFOV(FOV_TWEEN_FRAME_OPEN)
	else
		-- Frame closing: use frame-close tween
		updateFOV(FOV_TWEEN_FRAME_CLOSE)
	end
end

function Module:SetSpeedBoostNarrow(narrow: number)
	SpeedBoostFovNarrow = math.max(0, narrow)
	if FOVLocked then
		return
	end

	local targetFOV = if FrameZoomActive
		then FRAME_ZOOM_FOV
		else math.clamp(RunDesiredFOV + BalloonFloatFOVBoost - SpeedBoostFovNarrow, MIN_FOV, MAX_FOV)
	if math.abs(targetFOV - Camera.FieldOfView) < 0.05 then
		LastFOV = targetFOV
		return
	end

	LastFOV = targetFOV
	if ActiveTween then
		ActiveTween:Cancel()
	end
	local narrowing = narrow > PrevSpeedBoostFovNarrow
	PrevSpeedBoostFovNarrow = narrow
	ActiveTween = TweenService:Create(Camera, if narrowing then FOV_NARROW_TWEEN_IN else FOV_NARROW_TWEEN_OUT, {
		FieldOfView = targetFOV,
	})
	ActiveTween:Play()
end

function Module:SetBalloonFloatBoost(boost: number)
	BalloonFloatFOVBoost = math.max(0, boost)
	if FOVLocked then
		return
	end

	local targetFOV = if FrameZoomActive
		then FRAME_ZOOM_FOV
		else math.clamp(RunDesiredFOV + BalloonFloatFOVBoost - SpeedBoostFovNarrow, MIN_FOV, MAX_FOV)
	if math.abs(targetFOV - Camera.FieldOfView) < 0.05 then
		LastFOV = targetFOV
		return
	end

	LastFOV = targetFOV
	if ActiveTween then
		ActiveTween:Cancel()
	end
	ActiveTween = TweenService:Create(Camera, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = targetFOV,
	})
	ActiveTween:Play()
end

--- Lock FOV temporarily during special effects (highest priority)
function Module:LockFOV(duration)
	FOVLocked = true
	
	-- Store current FOV as baseline for when lock is released
	if not FOVLockTimer then
		LastFOV = Camera.FieldOfView
	end
	
	-- Clear any existing timer (extends the lock if already active)
	if FOVLockTimer then
		pcall(task.cancel, FOVLockTimer)
	end
	
	-- Auto-unlock after duration + buffer
	FOVLockTimer = task.spawn(function()
		task.wait(duration + 0.5)
		FOVLockTimer = nil
		FOVLocked = false
		LastFOV = Camera.FieldOfView
		updateFOV()
	end)
end

--- Unlock FOV to resume normal FOV handling
function Module:UnlockFOV()
	if FOVLockTimer then
		pcall(task.cancel, FOVLockTimer)
		FOVLockTimer = nil
	end
	FOVLocked = false
	updateFOV()
end

function Module:Init()
	Character = Player.Character
	if Character then
		Humanoid = Character:FindFirstChild("Humanoid")
		if Humanoid then
			LastFOV = Camera.FieldOfView
			RunDesiredFOV = LastFOV
			setupRunningFOV()
		end
	end
	Player.CharacterAdded:Connect(onCharacterAdded)
end

return Module
