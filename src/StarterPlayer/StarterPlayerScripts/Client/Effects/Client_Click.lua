--// Client_Click - Global click effect system
--// Creates visual effects (glow + sparkles) on all mouse clicks and touches
--// Pattern based on SingingX

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

-- Debouncing to prevent excessive clicks
local AnimationDB = false
local DEBOUNCE_TIME = 0.05 -- 50ms cooldown between click effects
local GLOW_DURATION = 0.15 -- Glow circle animation
local SPARKLE_DURATION = 0.4 -- Sparkles last longer than glow
local SPARKLE_DISTANCE = 0.045 -- Distance from center for sparkles

local Module = {}

-- Dedicated ScreenGui for click effects (full viewport, no layout quirks)
local clickEffectsGui = nil

-- Templates for click effects (should be children of this ModuleScript in Studio)
local glowTemplate = nil
local sparkleTemplate = nil

function Module:Init()
	-- Templates are optional — click effects are skipped when absent.
	glowTemplate = script:FindFirstChild("Glow")
	sparkleTemplate = script:FindFirstChild("Sparkle")
	
	-- Create dedicated fullscreen layer for click effects (IgnoreGuiInset = viewport coords)
	clickEffectsGui = Instance.new("ScreenGui")
	clickEffectsGui.Name = "ClickEffects"
	clickEffectsGui.ResetOnSpawn = false
	clickEffectsGui.IgnoreGuiInset = true
	clickEffectsGui.DisplayOrder = 100
	clickEffectsGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	clickEffectsGui.Parent = PlayerGui
	
	-- Listen for all clicks/touches (ignore GameProcessed so effect plays on buttons too)
	UserInputService.InputBegan:Connect(function(Input, _GameProcessed)
		-- Debounce check
		if AnimationDB then return end
		
		if Input.UserInputType == Enum.UserInputType.MouseButton1
			or Input.UserInputType == Enum.UserInputType.Touch then
			-- Always use GetMouseLocation() for consistent positioning (accounts for GuiInset)
			local pos = UserInputService:GetMouseLocation()
			self:Animation(pos)
		end
	end)
end

--- Get the Glow template for use by other modules (e.g. stamina boost)
function Module:GetGlowTemplate()
	return script:FindFirstChild("Glow")
end

function Module:Animation(Position)
	-- Apply debounce
	AnimationDB = true
	task.delay(DEBOUNCE_TIME, function()
		AnimationDB = false
	end)
	
	if not clickEffectsGui then return end
	
	-- Convert viewport pixels to scale (0-1). IgnoreGuiInset = true so viewport matches.
	local vp = Camera.ViewportSize
	local ScaledPos = UDim2.fromScale(
		Position.X / vp.X,
		Position.Y / vp.Y
	)
	
	-- Create glow effect: fading circle that expands (start small, grow while fading out)
	if glowTemplate then
		local Glow = glowTemplate:Clone()
		Glow.AnchorPoint = Vector2.new(0.5, 0.5)
		Glow.Parent = clickEffectsGui
		Glow.Position = ScaledPos
		Glow.Size = UDim2.fromScale(0.015, 0.015) -- Start small
		if Glow:IsA("ImageLabel") then
			Glow.ImageTransparency = 0
		elseif Glow:IsA("Frame") then
			Glow.BackgroundTransparency = 0
		end
		
		-- Expand outward while fading
		TweenService:Create(Glow, TweenInfo.new(GLOW_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.fromScale(0.075, 0.075)}):Play()
		if Glow:IsA("ImageLabel") then
			TweenService:Create(Glow, TweenInfo.new(GLOW_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 1}):Play()
		elseif Glow:IsA("Frame") then
			TweenService:Create(Glow, TweenInfo.new(GLOW_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
		end
		
		-- Auto-cleanup Glow after animation completes
		Debris:AddItem(Glow, GLOW_DURATION + 0.1)
	end
	
	-- Create sparkle effects (SingingX style - random small offsets)
	if sparkleTemplate then
		for i = 1, 3 do
			local Sparkle = sparkleTemplate:Clone()
			Sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
			Sparkle.Parent = clickEffectsGui
			Sparkle.Position = ScaledPos -- Start at center
			
			-- Three parallel tweens like SingingX (Size, Rotation, Position with random offset)
			TweenService:Create(Sparkle, TweenInfo.new(SPARKLE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.fromScale(0, 0)}):Play()
			TweenService:Create(Sparkle, TweenInfo.new(SPARKLE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = math.random(-15, 15)}):Play()
			TweenService:Create(Sparkle, TweenInfo.new(SPARKLE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromScale(
					ScaledPos.X.Scale + math.random(-5, 5) / 200,  -- ±0.025
					ScaledPos.Y.Scale + math.random(-5, 5) / 100   -- ±0.05
				)
			}):Play()
			
			Debris:AddItem(Sparkle, SPARKLE_DURATION + 0.1)
		end
	end
end

return Module
