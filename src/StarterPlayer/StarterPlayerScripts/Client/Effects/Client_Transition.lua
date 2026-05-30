--// Client_Transition - BlackFrame transition system
--// Handles circular zoom transitions for teleports, respawns, etc.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Transition = {}

-- State
local BlackFrameUI = nil
local BlackFrame = nil
local currentTransition = nil -- Stores current transition state

-- ========================================
-- INITIALIZATION
-- ========================================

function Transition:Init()
	BlackFrameUI = PlayerGui:WaitForChild("BlackFrameUI", 10)
	if not BlackFrameUI then
		warn("⚠️ BlackFrameUI not found in PlayerGui")
		return
	end
	
	BlackFrame = BlackFrameUI:WaitForChild("BlackFrame", 30)
	if not BlackFrame then
		warn("⚠️ BlackFrame not found in BlackFrameUI")
		return
	end
	
	BlackFrame.Size = UDim2.new(4, 0, 4, 0)
	BlackFrame.Visible = false
end

-- ========================================
-- CORE TRANSITION LOGIC
-- ========================================

local function cleanupTransition()
	if currentTransition then
		if currentTransition.coverTween then
			currentTransition.coverTween:Cancel()
		end
		if currentTransition.uncoverTween then
			currentTransition.uncoverTween:Cancel()
		end
		currentTransition = nil
	end
	
	if BlackFrame then
		BlackFrame.Visible = false
		BlackFrame.Size = UDim2.new(4, 0, 4, 0)
	end
end

local function startReveal(duration)
	if not BlackFrame or not currentTransition then return end
	
	-- Create reveal tween
	local uncoverTween = TweenService:Create(
		BlackFrame,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{Size = UDim2.new(4, 0, 4, 0)}
	)
	
	currentTransition.uncoverTween = uncoverTween
	
	uncoverTween.Completed:Connect(cleanupTransition)
	
	uncoverTween:Play()
end

--[[
	Start a transition (darken screen)
	@param duration - Duration of darken/reveal in seconds
	@return - Returns a control object to trigger reveal manually
]]
function Transition:Start(duration)
	if not BlackFrame then
		warn("⚠️ BlackFrame not initialized")
		return nil
	end
	
	cleanupTransition()
	
	duration = duration or 0.35
	
	-- Create new transition state
	currentTransition = {
		duration = duration,
		coverTween = nil,
		uncoverTween = nil,
		autoReveal = true,
	}
	
	-- Set initial state
	BlackFrame.Size = UDim2.new(4, 0, 4, 0)
	BlackFrame.Visible = true
	
	-- Create darken tween
	local coverTween = TweenService:Create(
		BlackFrame,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{Size = UDim2.new(0, 0, 0, 0)}
	)
	
	currentTransition.coverTween = coverTween
	coverTween:Play()
	
	-- Return control object
	return {
		-- Call when screen is fully dark and you're ready for the action
		OnDark = function(callback)
			coverTween.Completed:Wait()
			
			if callback then
				local success, err = pcall(callback)
				if not success then
					warn("⚠️ Transition callback error:", err)
				end
			end
			
			return currentTransition -- Return self for chaining
		end,
		
		-- Call to trigger reveal (or it auto-reveals after OnDark if not disabled)
		Reveal = function(waitTime)
			if waitTime then
				task.wait(waitTime)
			end
			startReveal(duration)
		end,
		
		-- Disable auto-reveal (for manual control like respawn)
		DisableAutoReveal = function()
			if currentTransition then
				currentTransition.autoReveal = false
			end
		end,
	}
end

--[[
	Trigger reveal manually (for server-controlled reveals)
]]
function Transition:Reveal()
	if currentTransition then
		startReveal(currentTransition.duration)
	else
		warn("⚠️ No active transition to reveal")
	end
end

--[[
	Legacy API: Execute a callback with auto-reveal
	@param callback - Function to call when screen is fully covered
	@param duration - Duration of transition in seconds (default 0.35)
]]
function Transition:BlackFrameTransition(callback, duration)
	local transition = self:Start(duration)
	if not transition then return end
	
	transition.OnDark(function()
		if callback then callback() end
	--	task.wait(0.1)
		transition.Reveal()
	end)
end

--[[
	Force cleanup (safety measure)
]]
function Transition:ForceCleanup()
	cleanupTransition()
end

return Transition
