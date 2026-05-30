--// Private Services
local CollectionService = game:GetService("CollectionService")

--// Variables
local ActiveAnimations = {} -- Track loaded animations for cleanup [object] = animationTrack

--// Functions
local Module = {}

-- Handle AnimateIdle tag
local function onAnimateIdleTagged(object)
	-- Check if object is a Humanoid or AnimationController
	if not (object:IsA("Humanoid") or object:IsA("AnimationController")) then
		warn("AnimateIdle tag applied to non-Humanoid/AnimationController:", object:GetFullName())
		return
	end
	
	-- Find the IdleAnimation inside the tagged object
	local idleAnimation = object:FindFirstChild("IdleAnimation")
	if not idleAnimation or not idleAnimation:IsA("Animation") then
		--warn("AnimateIdle: No Animation named 'IdleAnimation' found in", object:GetFullName())
		return
	end
	
	-- Load and play the animation
	local success, animationTrack = pcall(function()
		return object:LoadAnimation(idleAnimation)
	end)
	
	if success and animationTrack then
		animationTrack:Play()
		ActiveAnimations[object] = animationTrack
	else
		warn("AnimateIdle: Failed to load animation for", object:GetFullName())
	end
end

-- Handle AnimateIdle tag removal
local function onAnimateIdleUntagged(object)
	local animationTrack = ActiveAnimations[object]
	if animationTrack then
		animationTrack:Stop()
		ActiveAnimations[object] = nil
	end
end

-- Initialize tag handler system
function Module:Init()
	-- Set up AnimateIdle tag handlers
	CollectionService:GetInstanceAddedSignal("AnimateIdle"):Connect(onAnimateIdleTagged)
	CollectionService:GetInstanceRemovedSignal("AnimateIdle"):Connect(onAnimateIdleUntagged)
	
	-- Handle already tagged objects
	for _, object in pairs(CollectionService:GetTagged("AnimateIdle")) do
		task.spawn(onAnimateIdleTagged, object)
	end
end

return Module
