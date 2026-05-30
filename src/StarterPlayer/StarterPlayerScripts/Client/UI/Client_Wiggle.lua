--// Client_Wiggle - Tag-based wiggle animation
--// Tag any GuiObject with "WiggleTag" to make it wiggle continuously

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local TAG = "WiggleTag"

local WiggleObjects = {}

-- Wiggle settings
local WIGGLE_ANGLE = 6
local WIGGLE_DURATION = 0.15   -- Per shake
local WIGGLE_COUNT = 6         -- Longer wiggle burst
local WIGGLE_PAUSE = 2.5       -- Longer pause between bursts (2 seconds)

local Wiggle = {}

-- ========================================
-- WIGGLE LOGIC
-- ========================================

--- Start continuous wiggle animation on an object
local function startWiggle(obj: GuiObject)
	if not obj or not obj:IsA("GuiObject") then return end
	if WiggleObjects[obj] then return end -- Already wiggling
	
	WiggleObjects[obj] = true
	
	local function wiggleBurst()
		if not obj or not obj.Parent then
			-- Object was destroyed, clean up
			WiggleObjects[obj] = nil
			return
		end
		
		local target = -WIGGLE_ANGLE
		local count = 0
		
		local function nextWiggle()
			count = count + 1
			if count > WIGGLE_COUNT then
				-- Burst complete, pause then start again
				task.delay(WIGGLE_PAUSE, wiggleBurst)
				return
			end
			
			if not obj or not obj.Parent then
				WiggleObjects[obj] = nil
				return
			end
			
			-- Last wiggle ends at 0, otherwise alternate
			if count == WIGGLE_COUNT then
				target = 0
			else
				target = -target
			end
			
			local tween = TweenService:Create(
				obj,
				TweenInfo.new(WIGGLE_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{Rotation = target}
			)
			tween.Completed:Connect(nextWiggle)
			tween:Play()
		end
		
		nextWiggle()
	end
	
	wiggleBurst()
end

--- Stop wiggle and reset rotation
local function stopWiggle(obj: GuiObject)
	if not obj then return end
	WiggleObjects[obj] = nil
	
	-- Reset rotation to 0
	if obj and obj.Parent then
		obj.Rotation = 0
	end
end

-- ========================================
-- SETUP & CLEANUP
-- ========================================

local function setupWiggle(obj)
	if not obj:IsA("GuiObject") then return end
	startWiggle(obj)
end

local function onTagRemoved(obj)
	stopWiggle(obj)
end

-- ========================================
-- INIT
-- ========================================

function Wiggle:Init()
	-- Setup existing tagged objects
	for _, obj in CollectionService:GetTagged(TAG) do
		task.spawn(setupWiggle, obj)
	end
	
	-- Listen for new tagged objects
	CollectionService:GetInstanceAddedSignal(TAG):Connect(setupWiggle)
	
	-- Listen for tag removal
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(onTagRemoved)
end

return Wiggle
