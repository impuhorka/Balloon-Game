--// Server_LightingManager: Server-side lighting system with smooth transitions
--// Handles lighting presets and transitions for events

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local LightingManager = {}

-- State management
local defaultLighting = nil
local currentPreset = "Default"
local isTransitioning = false
local transitionDuration = 2 -- 2 seconds

-- Cache important folders
local Storage = ReplicatedStorage:WaitForChild("Storage")
local LightingPresets = Storage:FindFirstChild("LightingPreset")

-- Lighting properties (hardcoded for easy editing)
local LightingProperties = {
	Night = {
		Ambient = Color3.fromRGB(179, 179, 255), -- Dark blue ambient
		Brightness = 0.8,
		ColorShift_Bottom = Color3.fromRGB(10, 10, 30), -- Dark blue bottom
		ColorShift_Top = Color3.fromRGB(120, 165, 255), -- Dark blue top
		OutdoorAmbient = Color3.fromRGB(0,0,0), -- Dark blue outdoor
		ClockTime = 4, -- Night time
	},
	
	RainyNight = {
		Ambient = Color3.fromRGB(152, 152, 255), -- Dark blue ambient (same as Night)
		Brightness = 1,
		ColorShift_Bottom = Color3.fromRGB(10, 10, 30), -- Dark blue bottom
		ColorShift_Top = Color3.fromRGB(120, 165, 255), -- Dark blue top
		OutdoorAmbient = Color3.fromRGB(0,0,0), -- Dark blue outdoor
		ClockTime = 6, -- Night time
	},
	
	Disco = {
		Ambient = Color3.fromRGB(229, 165, 240), -- Purple ambient
		Brightness = .35,
		ColorShift_Bottom = Color3.fromRGB(75, 0, 130), -- Dark purple bottom
		ColorShift_Top = Color3.fromRGB(138, 43, 226), -- Purple top
		OutdoorAmbient = Color3.fromRGB(216, 182, 236), -- Purple outdoor
		ClockTime = 10, -- Night time
        FogColor = Color3.fromRGB(171, 35, 255)
	},

	Spooky = {
		Ambient = Color3.fromRGB(126, 126, 212), -- Purple ambient
		Brightness = 0,
		ColorShift_Bottom = Color3.fromRGB(10, 10, 10), -- Dark purple bottom
		ColorShift_Top = Color3.fromRGB(164, 226, 255), -- Purple top
		OutdoorAmbient = Color3.fromRGB(0, 0, 0), -- Purple outdoor
		ClockTime = 3, -- Night time
	}
}

-- Initialize lighting system
function LightingManager:Init()
	
	-- Wait for LightingPresets folder
	if not LightingPresets then
		warn("❌ LightingPresets folder not found in ReplicatedStorage.Storage")
		return false
	end
	
	-- Save current lighting as default (one-time only)
	self:SaveDefaultLighting()
	return true
end

-- Save current lighting as default (one-time detection)
function LightingManager:SaveDefaultLighting()
	if defaultLighting then
		return
	end
	
	-- Capture current lighting state
	defaultLighting = {
		-- Lighting properties
		Ambient = Lighting.Ambient,
		Brightness = Lighting.Brightness,
		ColorShift_Bottom = Lighting.ColorShift_Bottom,
		ColorShift_Top = Lighting.ColorShift_Top,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		ClockTime = Lighting.ClockTime,
		
		-- Atmosphere properties (if exists)
		Atmosphere = Lighting:FindFirstChild("Atmosphere") and {
			Density = Lighting.Atmosphere.Density,
			Offset = Lighting.Atmosphere.Offset,
			Color = Lighting.Atmosphere.Color,
			Decay = Lighting.Atmosphere.Decay,
			Glare = Lighting.Atmosphere.Glare,
			Haze = Lighting.Atmosphere.Haze
		} or nil,
		
		-- ColorCorrection properties (if exists)
		ColorCorrection = Lighting:FindFirstChild("ColorCorrection") and {
			Brightness = Lighting.ColorCorrection.Brightness,
			Contrast = Lighting.ColorCorrection.Contrast,
			Saturation = Lighting.ColorCorrection.Saturation,
			TintColor = Lighting.ColorCorrection.TintColor
		} or nil,
		
		-- Bloom properties (if exists)
		Bloom = Lighting:FindFirstChild("Bloom") and {
			Intensity = Lighting.Bloom.Intensity,
			Size = Lighting.Bloom.Size,
			Threshold = Lighting.Bloom.Threshold
		} or nil,
		
		-- Clone current sky (save a copy, not a reference)
		Sky = Lighting:FindFirstChild("Sky") and Lighting.Sky:Clone() or nil
	}
end

-- Transition to a specific lighting preset
function LightingManager:TransitionToPreset(presetName, instant)
	if isTransitioning then
		return false
	end
	
	local presetFolder = LightingPresets and LightingPresets:FindFirstChild(presetName)
	-- Fallback to default folder if specific preset folder doesn't exist
	if not presetFolder and LightingPresets then
		presetFolder = LightingPresets:FindFirstChild("Default")
	end
	local lightingProps = LightingProperties[presetName]
	
	if not lightingProps then

		return false
	end
	
	-- Check if LightingPresets folder exists
	if not LightingPresets then
		print("⚠️ LightingPresets folder not found in Storage")
	end
	
	isTransitioning = true
	
	-- Start transition (folder is optional, instant is optional)
	self:StartLightingTransition(lightingProps, presetFolder, function()
		currentPreset = presetName
		isTransitioning = false
		
		-- Notify clients of weather changes
		self:NotifyWeatherChange(presetFolder)
	end, instant)
	
	return true
end


-- Start smooth lighting transition
function LightingManager:StartLightingTransition(lightingProps, presetFolder, callback, instant)
	local tweens = {}
	
	-- Use instant duration if requested, otherwise use normal transition
	local duration = instant and 0.01 or transitionDuration
	
	-- Tween Lighting properties (from hardcoded values)
	for property, targetValue in pairs(lightingProps) do
		-- Only tween valid Lighting properties (not child objects like Sky)
		if (property ~= "Sky" and property ~= "Atmosphere" and property ~= "ColorCorrection" and property ~= "Bloom") and
		   Lighting[property] and type(targetValue) == type(Lighting[property]) then
			local tweenInfo = TweenInfo.new(
				duration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.InOut
			)
			
			local tween = TweenService:Create(Lighting, tweenInfo, {[property] = targetValue})
			tween:Play()
			table.insert(tweens, tween)
		end
	end
	
	-- Handle Atmosphere transition (from folder)
	local presetAtmosphere = presetFolder and presetFolder:FindFirstChild("Atmosphere")
	local atmosphere = Lighting:FindFirstChild("Atmosphere")
	
	if presetAtmosphere then
		-- Preset has atmosphere - create or update it
		if not atmosphere then
			-- Create new atmosphere
			atmosphere = presetAtmosphere:Clone()
			
			-- Set properties to 0 initially before parenting
			atmosphere.Density = 0
			atmosphere.Glare = 0
			atmosphere.Haze = 0
			
			atmosphere.Parent = Lighting
		end
		
		-- Tween atmosphere properties from 0 to preset values
		local tweenInfo = TweenInfo.new(
			duration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut
		)
		
		local tween = TweenService:Create(atmosphere, tweenInfo, {
			Density = presetAtmosphere.Density,
			Offset = presetAtmosphere.Offset,
			Color = presetAtmosphere.Color,
			Decay = presetAtmosphere.Decay,
			Glare = presetAtmosphere.Glare,
			Haze = presetAtmosphere.Haze
		})
		tween:Play()
		table.insert(tweens, tween)
	elseif atmosphere then
		-- Preset doesn't have atmosphere but one exists - destroy it
		atmosphere:Destroy()
	end
	
	-- Handle ColorCorrection transition (from folder)
	local presetColorCorrection = presetFolder and presetFolder:FindFirstChild("ColorCorrection")
	local colorCorrection = Lighting:FindFirstChild("ColorCorrection")
	
	if presetColorCorrection then
		-- Preset has color correction - create or update it
		if not colorCorrection then
			-- Create new color correction
			colorCorrection = presetColorCorrection:Clone()
			colorCorrection.Parent = Lighting
		end
		
		-- Tween color correction properties from preset object
		local tweenInfo = TweenInfo.new(
			duration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut
		)
		
		local tween = TweenService:Create(colorCorrection, tweenInfo, {
			Brightness = presetColorCorrection.Brightness,
			Contrast = presetColorCorrection.Contrast,
			Saturation = presetColorCorrection.Saturation,
			TintColor = presetColorCorrection.TintColor
		})
		tween:Play()
		table.insert(tweens, tween)
	elseif colorCorrection then
		-- Preset doesn't have color correction but one exists - destroy it
		colorCorrection:Destroy()
	end
	
	-- Handle Bloom transition (from folder)
	local presetBloom = presetFolder and presetFolder:FindFirstChild("Bloom")
	local bloom = Lighting:FindFirstChild("Bloom")
	
	if presetBloom then
		-- Preset has bloom - create or update it
		if not bloom then
			-- Create new bloom
			bloom = presetBloom:Clone()
			bloom.Parent = Lighting
		end
		
		-- Tween bloom properties from preset object
		local tweenInfo = TweenInfo.new(
			duration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut
		)
		
		local tween = TweenService:Create(bloom, tweenInfo, {
			Intensity = presetBloom.Intensity,
			Size = presetBloom.Size,
			Threshold = presetBloom.Threshold
		})
		tween:Play()
		table.insert(tweens, tween)
	elseif bloom then
		-- Preset doesn't have bloom but one exists - destroy it
		bloom:Destroy()
	end
	
	-- Handle Atmosphere restoration (for default lighting from saved state)
	if lightingProps.Atmosphere and not presetFolder then
		-- Get or create atmosphere
		local atmosphere = Lighting:FindFirstChild("Atmosphere")
		if not atmosphere then
			atmosphere = Instance.new("Atmosphere")
			atmosphere.Parent = Lighting
		end
		
		-- Tween atmosphere properties
		local tweenInfo = TweenInfo.new(
			transitionDuration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut
		)
		
		local tween = TweenService:Create(atmosphere, tweenInfo, {
			Density = lightingProps.Atmosphere.Density,
			Offset = lightingProps.Atmosphere.Offset,
			Color = lightingProps.Atmosphere.Color,
			Decay = lightingProps.Atmosphere.Decay,
			Glare = lightingProps.Atmosphere.Glare,
			Haze = lightingProps.Atmosphere.Haze
		})
		tween:Play()
		table.insert(tweens, tween)
	elseif not lightingProps.Atmosphere and not presetFolder then
		-- No atmosphere in saved default - remove it if it exists
		local atmosphere = Lighting:FindFirstChild("Atmosphere")
		if atmosphere then
			atmosphere:Destroy()
		end
	end
	
	-- Handle ColorCorrection restoration (for default lighting from saved state)
	if lightingProps.ColorCorrection and not presetFolder then
		-- Get or create color correction
		local colorCorrection = Lighting:FindFirstChild("ColorCorrection")
		if not colorCorrection then
			colorCorrection = Instance.new("ColorCorrectionEffect")
			colorCorrection.Parent = Lighting
		end
		
		-- Tween color correction properties
		local tweenInfo = TweenInfo.new(
			transitionDuration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut
		)
		
		local tween = TweenService:Create(colorCorrection, tweenInfo, {
			Brightness = lightingProps.ColorCorrection.Brightness,
			Contrast = lightingProps.ColorCorrection.Contrast,
			Saturation = lightingProps.ColorCorrection.Saturation,
			TintColor = lightingProps.ColorCorrection.TintColor
		})
		tween:Play()
		table.insert(tweens, tween)
	elseif not lightingProps.ColorCorrection and not presetFolder then
		-- No color correction in saved default - remove it if it exists
		local colorCorrection = Lighting:FindFirstChild("ColorCorrection")
		if colorCorrection then
			colorCorrection:Destroy()
		end
	end
	
	-- Handle Bloom restoration (for default lighting from saved state)
	if lightingProps.Bloom and not presetFolder then
		-- Get or create bloom
		local bloom = Lighting:FindFirstChild("Bloom")
		if not bloom then
			bloom = Instance.new("BloomEffect")
			bloom.Parent = Lighting
		end
		
		-- Tween bloom properties
		local tweenInfo = TweenInfo.new(
			transitionDuration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut
		)
		
		local tween = TweenService:Create(bloom, tweenInfo, {
			Intensity = lightingProps.Bloom.Intensity,
			Size = lightingProps.Bloom.Size,
			Threshold = lightingProps.Bloom.Threshold
		})
		tween:Play()
		table.insert(tweens, tween)
	elseif not lightingProps.Bloom and not presetFolder then
		-- No bloom in saved default - remove it if it exists
		local bloom = Lighting:FindFirstChild("Bloom")
		if bloom then
			bloom:Destroy()
		end
	end
	
	-- Handle Sky change (instant)
	local skyFolder = presetFolder and presetFolder:FindFirstChild("Sky")
	if skyFolder then
		-- Remove current sky
		local currentSky = Lighting:FindFirstChild("Sky")
		if currentSky then
			currentSky:Destroy()
		end
		
		-- Clone new sky
		local newSky = skyFolder:Clone()
		newSky.Parent = Lighting
	elseif not presetFolder and lightingProps.Sky then
		-- Restore saved default sky
		local currentSky = Lighting:FindFirstChild("Sky")
		if currentSky then
			currentSky:Destroy()
		end
		
		-- Clone saved sky
		local newSky = lightingProps.Sky:Clone()
		newSky.Parent = Lighting
	elseif not presetFolder and not lightingProps.Sky then
		-- No sky in saved default - remove current sky
		local currentSky = Lighting:FindFirstChild("Sky")
		if currentSky then
			currentSky:Destroy()
		end
	end
	
	-- Wait for all tweens to complete
	if #tweens > 0 then
		local completedTweens = 0
		for _, tween in pairs(tweens) do
			tween.Completed:Connect(function()
				completedTweens = completedTweens + 1
				if completedTweens == #tweens then
					if callback then callback() end
				end
			end)
		end
	else
		-- No tweens, call callback immediately
		if callback then callback() end
	end
end

-- Test lighting preset (for testing purposes)
function LightingManager:LoadPreset(presetName)
	return self:TransitionToPreset(presetName)
end

-- Return to default lighting
function LightingManager:ReturnToDefault()
	if not defaultLighting then
		print("❌ Default lighting not saved yet")
		return false
	end
	
	isTransitioning = true
	
	-- Use Default preset folder for restoring effects
	local defaultPresetFolder = LightingPresets and LightingPresets:FindFirstChild("Default")
	self:StartLightingTransition(defaultLighting, defaultPresetFolder, function()
		currentPreset = "Default"
		isTransitioning = false
		
		-- Notify clients of weather changes
		self:NotifyWeatherChange(defaultPresetFolder)
	end)
	
	return true
end

-- Get current lighting status
function LightingManager:GetStatus()
	return {
		currentPreset = currentPreset,
		isTransitioning = isTransitioning,
		hasDefaultSaved = defaultLighting ~= nil
	}
end

-- Get available presets
function LightingManager:GetAvailablePresets()
	local presets = {}
	if LightingPresets then
		for _, preset in pairs(LightingPresets:GetChildren()) do
			-- Only include presets that have both folder and lighting properties
			if LightingProperties[preset.Name] then
				table.insert(presets, preset.Name)
			end
		end
	end
	return presets
end

function LightingManager:ApplyCustomLighting(lightingProps)
	-- Apply custom lighting properties directly (for disco effects)
	if not lightingProps then return false end
	
	isTransitioning = true
	
	-- Tween Lighting properties
	for property, targetValue in pairs(lightingProps) do
		if Lighting[property] and type(targetValue) == type(Lighting[property]) then
			local tweenInfo = TweenInfo.new(
				2, -- 2 second transition for smooth color changes
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.InOut
			)
			
			local tween = TweenService:Create(Lighting, tweenInfo, {[property] = targetValue})
			tween:Play()
		end
	end
	
	isTransitioning = false
	return true
end

-- Update weather attributes on Lighting
function LightingManager:NotifyWeatherChange(presetFolder)
	-- Clear all weather attributes first
	Lighting:SetAttribute("Weather", nil)
	
	if presetFolder then
		-- Check for weather attributes (Rain, Snow, etc.)
		if presetFolder:GetAttribute("Rain") then
			Lighting:SetAttribute("Weather", "Rain")
		elseif presetFolder:GetAttribute("Snow") then
			Lighting:SetAttribute("Weather", "Snow")
		elseif presetFolder:GetAttribute("Disco") then
			Lighting:SetAttribute("Weather", "Disco")
		end
	end
end

return LightingManager
