--// Client_ScreenPopup - Handles UI popups for cash collection
--// Shows cash gains with pop-out animation using UIScale

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer

local Popups = {}

-- ========================================
-- STATE
-- ========================================

local playerGui = nil
local mainGui = nil
local popupFrame = nil
local cashTemplate = nil
local speedTemplate = nil

-- Shorten module for formatting large numbers
local Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)

-- Track recent popup positions to avoid spawning too close together
local recentPositions = {}
local POSITION_HISTORY_SIZE = 5
local MIN_DISTANCE = 0.15 -- Minimum distance between popups (15% of screen)

-- ========================================
-- HELPER FUNCTIONS
-- ========================================

--- Generate a random position that doesn't overlap with recent popups
--- @return UDim2
local function generateRandomPosition()
	local maxAttempts = 10
	local attempt = 0
	
	while attempt < maxAttempts do
		-- X: 10-40% (left) or 60-90% (right), avoid center
		-- Y: 20-80% (vertical range)
		local x = math.random() < 0.5 and math.random(15, 40) / 100 or math.random(60, 85) / 100
		local y = math.random(20, 80) / 100
		local newPos = UDim2.fromScale(x, y)
		
		-- Check distance from recent positions
		local tooClose = false
		for _, recentPos in ipairs(recentPositions) do
			local dx = newPos.X.Scale - recentPos.X.Scale
			local dy = newPos.Y.Scale - recentPos.Y.Scale
			local distance = math.sqrt(dx * dx + dy * dy)
			
			if distance < MIN_DISTANCE then
				tooClose = true
				break
			end
		end
		
		if not tooClose then
			-- Store this position in history
			table.insert(recentPositions, newPos)
			if #recentPositions > POSITION_HISTORY_SIZE then
				table.remove(recentPositions, 1) -- Remove oldest
			end
			return newPos
		end
		
		attempt = attempt + 1
	end
	
	-- If all attempts failed, just return a random position (fallback)
	local x = math.random() < 0.5 and math.random(10, 40) / 100 or math.random(60, 90) / 100
	local y = math.random(20, 80) / 100
	return UDim2.fromScale(x, y)
end

-- ========================================
-- CASH POPUP
-- ========================================

--- Show a cash popup with UIScale pop-out animation
--- @param amount number - Amount of cash collected or spent (positive for gain, negative for loss)
--- @param position UDim2? - Optional position (random if not provided)
--- @param timeMultiplier number? - Optional time multiplier (default 1)
--- @param isGain boolean? - True for gains (AddUIGradient), false for losses (RemoveUIGradient). Defaults to true if amount >= 0
function Popups:ShowCashPopup(amount: number, position: UDim2?, timeMultiplier: number?, isGain: boolean?)
	if not cashTemplate then
		warn("⚠️ CashTemplate not found for popup")
		return
	end
	
	timeMultiplier = timeMultiplier or 1
	-- Default: if amount is positive, it's a gain. Otherwise, use the provided isGain value
	if isGain == nil then
		isGain = amount >= 0
	end
	
	-- Random position if not provided (avoid center, use edges)
	position = position or generateRandomPosition()
	
	-- Clone the template
	local popup = cashTemplate:Clone()
	popup.Name = "CashPopup"
	popup.Position = position
	popup.Visible = true
	popup.Parent = popupFrame
	
	-- Get or create UIScale for pop-out animation
	local uiScale = popup:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = popup
	end
	uiScale.Scale = 0 -- Start at 0 for pop-out effect
	
	-- Update the amount text
	local amountLabel = popup:FindFirstChild("Amount")
	if amountLabel then
		-- Format text: +$XXX or -$XXX
		local prefix = amount >= 0 and "+$" or "-$"
		amountLabel.Text = prefix .. Shorten:Number(math.abs(amount))
		
		-- Enable the correct gradient based on gain/loss
		local addGradient = amountLabel:FindFirstChild("AddUIGradient")
		local removeGradient = amountLabel:FindFirstChild("RemoveUIGradient")
		
		if isGain then
			-- Gain: enable AddUIGradient (green)
			if addGradient then addGradient.Enabled = true end
			if removeGradient then removeGradient.Enabled = false end
		else
			-- Loss: enable RemoveUIGradient (red)
			if addGradient then addGradient.Enabled = false end
			if removeGradient then removeGradient.Enabled = true end
		end
	end
	
	task.spawn(function()
		-- Phase 0: UIScale pop-out (NEW - starts immediately)
		local popTween = TweenService:Create(
			uiScale,
			TweenInfo.new(0.3 * timeMultiplier, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Scale = 1}
		)
		popTween:Play()
		
		-- Phase 1: Subtle rotation (start immediately, parallel with pop)
		local rotationTween = TweenService:Create(
			popup,
			TweenInfo.new(0.2 * timeMultiplier, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Rotation = math.random(-8, 8)}
		)
		rotationTween:Play()
		
		-- Phase 2: Float up (start immediately, runs in parallel)
		local finalY = position.Y.Scale - 0.12
		local positionTween = TweenService:Create(
			popup,
			TweenInfo.new(1.2 * timeMultiplier, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Position = UDim2.fromScale(position.X.Scale, finalY)}
		)
		positionTween:Play()
		
		-- Phase 3: Delayed fade (all fade tweens run simultaneously)
		task.wait(0.5 * timeMultiplier)
		local fadeTime = 0.7 * timeMultiplier
		local fadeInfo = TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		
		-- Start all fade tweens at the same time
		for _, child in ipairs(popup:GetDescendants()) do
			if child:IsA("TextLabel") or child:IsA("TextButton") then
				TweenService:Create(child, fadeInfo, {TextTransparency = 1}):Play()
				-- Also fade the UIStroke if it exists
				local uiStroke = child:FindFirstChildOfClass("UIStroke")
				if uiStroke then
					TweenService:Create(uiStroke, fadeInfo, {Transparency = 1}):Play()
				end
			elseif child:IsA("UIStroke") and child.Parent == popup then
				-- Fade strokes directly under popup
				TweenService:Create(child, fadeInfo, {Transparency = 1}):Play()
			elseif child:IsA("ImageLabel") then
				TweenService:Create(child, fadeInfo, {ImageTransparency = 1}):Play()
			end
		end
		
		-- Wait for fade to complete, then destroy
		task.wait(fadeTime)
		popup:Destroy()
	end)
end

-- ========================================
-- SPEED POPUP
-- ========================================

--- Show a speed popup with UIScale pop-out animation
--- @param amount number - Amount of speed gained
--- @param position UDim2? - Optional position (random if not provided)
--- @param timeMultiplier number? - Optional time multiplier (default 1)
function Popups:ShowSpeedPopup(amount: number, position: UDim2?, timeMultiplier: number?)
	if not speedTemplate then
		warn("⚠️ SpeedTemplate not found for popup")
		return
	end
	
	timeMultiplier = timeMultiplier or 1
	
	-- Generate random position avoiding recent popups
	position = position or generateRandomPosition()
	
	-- Clone the template
	local popup = speedTemplate:Clone()
	popup.Name = "SpeedPopup"
	popup.Position = position
	popup.Visible = true
	popup.Parent = popupFrame
	
	-- Get or create UIScale for pop-out animation
	local uiScale = popup:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = popup
	end
	uiScale.Scale = 0 -- Start at 0 for pop-out effect
	
	-- Update the amount text
	local amountLabel = popup:FindFirstChild("Amount")
	if amountLabel then
		-- Format text: +XXX for speed gains
		amountLabel.Text = "+" .. Shorten:Number(amount)
	end
	
	task.spawn(function()
		-- Phase 0: UIScale pop-out (NEW - starts immediately)
		local popTween = TweenService:Create(
			uiScale,
			TweenInfo.new(0.3 * timeMultiplier, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Scale = 1}
		)
		popTween:Play()
		
		-- Phase 1: Subtle rotation (start immediately, parallel with pop)
		local rotationTween = TweenService:Create(
			popup,
			TweenInfo.new(0.2 * timeMultiplier, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Rotation = math.random(-8, 8)}
		)
		rotationTween:Play()
		
		-- Phase 2: Float up (start immediately, runs in parallel)
		local finalY = position.Y.Scale - 0.12
		local positionTween = TweenService:Create(
			popup,
			TweenInfo.new(1.2 * timeMultiplier, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Position = UDim2.fromScale(position.X.Scale, finalY)}
		)
		positionTween:Play()
		
		-- Phase 3: Delayed fade (all fade tweens run simultaneously)
		task.wait(0.5 * timeMultiplier)
		local fadeTime = 0.7 * timeMultiplier
		local fadeInfo = TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		
		-- Start all fade tweens at the same time
		for _, child in ipairs(popup:GetDescendants()) do
			if child:IsA("TextLabel") or child:IsA("TextButton") then
				TweenService:Create(child, fadeInfo, {TextTransparency = 1}):Play()
				-- Also fade the UIStroke if it exists
				local uiStroke = child:FindFirstChildOfClass("UIStroke")
				if uiStroke then
					TweenService:Create(uiStroke, fadeInfo, {Transparency = 1}):Play()
				end
			elseif child:IsA("UIStroke") and child.Parent == popup then
				-- Fade strokes directly under popup
				TweenService:Create(child, fadeInfo, {Transparency = 1}):Play()
			elseif child:IsA("ImageLabel") then
				TweenService:Create(child, fadeInfo, {ImageTransparency = 1}):Play()
			end
		end
		
		-- Wait for fade to complete, then destroy
		task.wait(fadeTime)
		popup:Destroy()
	end)
end

-- ========================================
-- WARNING POPUP (error/info messages)
-- ========================================

--- Show a warning/error message using the same popup system
--- @param message string - Warning message to display
--- @param duration number? - Optional duration in seconds (default 3)
function Popups:ShowWarning(message: string, duration: number?)
	duration = duration or 3
	
	-- Use the standard popup system with error styling (red color)
	local config = {
		color = Color3.fromHex("ff2323"), -- Red for warnings/errors
		sound = "Error",
		duration = duration,
		animation = "default",
		category = "warning"
	}
	
	-- Create popup immediately
	local Clone = mainGui.Popups.Template:Clone()
	Clone.Name = "Warning"
	
	local Title = Clone:FindFirstChild("Title")
	if not Title then return end
	
	-- Store text for animation
	Title:SetAttribute("FullText", message)
	
	-- Configure gradient color
	local gradient = Title:FindFirstChild("UIGradient")
	if gradient then
		gradient.Enabled = true
		gradient.Color = ColorSequence.new(config.color, config.color:Lerp(Color3.new(1, 1, 1), 0.3))
	end
	
	-- Play error sound
	if config.sound then
		task.spawn(function()
			local soundModule = require(script.Parent.Parent.Effects.Client_Sounds)
			if soundModule and soundModule.Play then
				soundModule:Play(config.sound)
			end
		end)
	end
	
	-- Apply default animation (elastic rotation)
	local info = TweenInfo.new(1, Enum.EasingStyle.Elastic)
	Title.Rotation = 5
	Title.Text = message
	TweenService:Create(Title, info, {Rotation = 0}):Play()
	
	Clone.Parent = mainGui.Popups
	Clone.Visible = true
	
	-- Auto-fade and destroy after duration
	task.delay(duration, function()
		if Clone and Clone.Parent and Title then
			local fade_info = TweenInfo.new(0.5, Enum.EasingStyle.Quad)
			TweenService:Create(Title, fade_info, {TextTransparency = 1}):Play()
			if Title.UIStroke then
				TweenService:Create(Title.UIStroke, fade_info, {Transparency = 1}):Play()
			end
			
			task.delay(0.5, function()
				if Clone and Clone.Parent then
					Clone:Destroy()
				end
			end)
		end
	end)
end

-- ========================================
-- INITIALIZATION
-- ========================================

function Popups:Init()
	-- Get player GUI
	playerGui = Player:WaitForChild("PlayerGui")
	mainGui = playerGui:WaitForChild("Main", 10)
	
	if not mainGui then
		warn("⚠️ MainGui not found for popups")
		return
	end
	
	-- Get popup frame
	popupFrame = mainGui:WaitForChild("PopupFrame", 10)
	if not popupFrame then
		warn("⚠️ PopupFrame not found in MainGui")
		return
	end
	
	-- Get cash template
	cashTemplate = popupFrame:FindFirstChild("CashTemplate")
	if not cashTemplate then
		warn("⚠️ CashTemplate not found in PopupFrame")
		return
	end
	
	-- Get speed template
	speedTemplate = popupFrame:FindFirstChild("SpeedTemplate")
	if not speedTemplate then
		warn("⚠️ SpeedTemplate not found in PopupFrame")
		return
	end
	
	-- Ensure templates are invisible
	cashTemplate.Visible = false
	speedTemplate.Visible = false
end

return Popups
