--// Private Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

--// Modules
local Shared_GradientAnimations = require(ReplicatedStorage.Modules.UI.Shared_GradientAnimations)
local Shared_Rarity = require(ReplicatedStorage.Modules.Gameplay.Shared_Rarity)
local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)

--// Variables
local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui

-- Rainbow animation tracking for Mythical popups
local rainbowAnimations = {} -- {[popup] = {connection, startTime}}

local Character = Player.Character or Player.CharacterAdded:Wait()
local RootPart = Character:WaitForChild("HumanoidRootPart")

local Camera = Workspace.CurrentCamera

local Main = PlayerGui:WaitForChild("Main")

-- Typewriter sound coordination
local typewriterActiveCount = 0
local typewriterDefaultVolume = 1
local typewriterFadeTween = nil

local function getTypewriterSound(soundModule)
	if soundModule and soundModule.Typewriter and soundModule.Typewriter:IsA("Sound") then
		return soundModule.Typewriter
	end

	-- Look for Client_Sounds in Effects folder (sibling to UI)
	local clientFolder = script.Parent.Parent -- Client folder
	local effectsFolder = clientFolder:FindFirstChild("Effects")
	if effectsFolder then
		local soundScript = effectsFolder:FindFirstChild("Client_Sounds")
		if soundScript then
			local sound = soundScript:FindFirstChild("Typewriter")
			if sound and sound:IsA("Sound") then
				return sound
			end
		end
	end

	return nil
end

local function cancelTypewriterFade()
	if typewriterFadeTween then
		typewriterFadeTween:Cancel()
		typewriterFadeTween = nil
	end
end

local function acquireTypewriterSound(soundModule)
	local sound = getTypewriterSound(soundModule)
	if not sound then
		return nil
	end

	cancelTypewriterFade()

	typewriterActiveCount += 1
	typewriterDefaultVolume = math.max(sound.Volume, 0.1)
	if sound.Volume <= 0 then
		sound.Volume = typewriterDefaultVolume
	end
	sound.Looped = true
	if not sound.IsPlaying then
		sound:Play()
	end

	return sound
end

local function releaseTypewriterSound(sound, fadeOut)
	sound = sound or getTypewriterSound(nil)
	if not sound then
		return
	end

	if typewriterActiveCount > 0 then
		typewriterActiveCount -= 1
	end

	if typewriterActiveCount > 0 then
		return
	end

	typewriterActiveCount = 0

	local function finalizeStop()
		sound.Looped = false
		sound:Stop()
		sound.TimePosition = 0
		sound.Volume = typewriterDefaultVolume
	end

	if fadeOut then
		cancelTypewriterFade()
		local fadeInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		typewriterFadeTween = TweenService:Create(sound, fadeInfo, {Volume = 0})
		typewriterFadeTween:Play()
		typewriterFadeTween.Completed:Connect(function()
			if typewriterActiveCount == 0 then
				finalizeStop()
			else
				cancelTypewriterFade()
				if sound.Volume <= 0 then
					sound.Volume = typewriterDefaultVolume
				end
				sound.Looped = true
				if not sound.IsPlaying then
					sound:Play()
				end
			end
		end)
	else
		cancelTypewriterFade()
		finalizeStop()
	end
end

local Popups = {}
-- Active immediate popups (same text = rewiggle + reset lifetime): [text] = { clone, destroyAt, config }
local activeImmediatePopups = {}
-- Popups keyed by type (e.g. "UpgradeType"): replace previous, update text, rewiggle, reset lifetime
local activeImmediatePopupsByType = {}
local tutorialStepValue = 5
local tutorialSubStepValue = 0
local tutorialStepObject = nil

-- LayoutOrder tracker: higher = more recent (front row)
local nextLayoutOrder = 0
local tutorialTrackingStarted = false
local persistentPopups = {}
local moduleInitialized = false
local defaultPopupsPosition = Main.Popups.Position
local tutorialPopupsPosition = UDim2.new(0.5, 0, 0.075, 4)

local function removePersistentPopup(key)
	local entry = persistentPopups[key]
	if not entry then
		return
	end
	if entry.clone and entry.clone.Parent then
		entry.clone:Destroy()
	end
	persistentPopups[key] = nil
end

local function cleanupPersistentPopups(currentStep)
	for key, entry in pairs(persistentPopups) do
		local clone = entry.clone
		local config = entry.config
		if not clone or not clone.Parent then
			persistentPopups[key] = nil
		elseif config and config.persistUntilStep and currentStep > config.persistUntilStep then
			removePersistentPopup(key)
		end
	end
end

local function updatePopupsDock(stepValue)
	if not Main or not Main:FindFirstChild("Popups") then
		return
	end
	if stepValue and stepValue < 5 then
		if Main.Popups.Position ~= tutorialPopupsPosition then
			Main.Popups.Position = tutorialPopupsPosition
		end
	else
		if Main.Popups.Position ~= defaultPopupsPosition then
			Main.Popups.Position = defaultPopupsPosition
		end
	end
end

local function registerPersistentPopup(clone, config)
	local key = config.persistKey or HttpService:GenerateGUID(false)
	
	removePersistentPopup(key)
	persistentPopups[key] = {clone = clone, config = config}
	clone.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end
		local entry = persistentPopups[key]
		if entry and entry.clone == clone then
			persistentPopups[key] = nil
		end
	end)
	
	-- DON'T cleanup here - tutorialStepValue might not be synced yet
	-- Cleanup happens when step actually changes via GetPropertyChangedSignal
end

local function shouldAllowPopup(category, extraConfig)
	local currentStep = tutorialStepValue
	if currentStep and currentStep < 5 then
		local extraConfigTable = if typeof(extraConfig) == "table" then extraConfig else nil
		-- Tutorial category always allowed (highest priority)
		if category == "tutorial" then
			return true
		end
		if extraConfigTable and extraConfigTable.allowDuringTutorial then
			return true
		end
		if category == "warning" or category == "critical" then
			return true
		end
		return false
	end
	return true
end

local function ensureTutorialTracking()
	if tutorialTrackingStarted then
		return
	end
	tutorialTrackingStarted = true
	task.spawn(function()
		local Data = Player:WaitForChild("Data", 10)
		if not Data then
			return
		end
		local Step = Data:WaitForChild("TutorialStep", 10)
		if not Step then
			return
		end
		tutorialStepObject = Step
		tutorialStepValue = Step.Value
		cleanupPersistentPopups(tutorialStepValue)
		updatePopupsDock(tutorialStepValue)
		Step:GetPropertyChangedSignal("Value"):Connect(function()
			tutorialStepValue = Step.Value
			cleanupPersistentPopups(tutorialStepValue)
			updatePopupsDock(tutorialStepValue)
		end)

		local SubStep = Data:FindFirstChild("TutorialSubStep") or Data:WaitForChild("TutorialSubStep", 10)
		if SubStep then
			tutorialSubStepValue = SubStep.Value
			SubStep:GetPropertyChangedSignal("Value"):Connect(function()
				tutorialSubStepValue = SubStep.Value
				updatePopupsDock(tutorialStepValue)
			end)
		end
	end)
end

ensureTutorialTracking()

-- Cool gradient function with specific color handling - always lighter & less saturated
function getColorGradient(color: Color3): ColorSequence
	local h, s, v = color:ToHSV()
	
	-- Create brighter, less saturated version with logical hue shifts
	local newH = h
	local newS = math.clamp(s - 0.25, 0, 1) -- Less saturated
	local newV = math.clamp(v + 0.2, 0, 1) -- Brighter
	
	-- Blue (0.58-0.67) → shift towards cyan (0.5)
	if h >= 0.58 and h <= 0.67 then
		newH = h - 0.08 -- Move towards cyan
		
	-- Red (0.0-0.08 or 0.92-1.0) → shift towards orange (0.08)
	elseif h <= 0.08 or h >= 0.92 then
		newH = (h + 0.05) % 1 -- Move towards orange
		
	-- Purple (0.75-0.85) → shift towards pink (0.9)
	elseif h >= 0.75 and h <= 0.85 then
		newH = h + 0.08 -- Move towards pink
		
	-- Green (0.25-0.42) → shift towards yellow (0.17)
	elseif h >= 0.25 and h <= 0.42 then
		newH = h - 0.08 -- Move towards yellow
		
	-- Orange (0.08-0.17) → shift towards yellow (0.17)
	elseif h >= 0.08 and h <= 0.17 then
		newH = h + 0.03 -- Move towards yellow
		
	-- Cyan (0.5-0.58) → shift towards green (0.33)
	elseif h >= 0.5 and h <= 0.58 then
		newH = h - 0.05 -- Move slightly towards green
		
	-- Yellow (0.17-0.25) → shift towards orange (0.08)
	elseif h >= 0.17 and h <= 0.25 then
		newH = h - 0.05 -- Move towards orange
	end
	
	-- Ensure hue stays in valid range
	newH = newH % 1
	
	local brighterColor = Color3.fromHSV(newH, newS, newV)
	return ColorSequence.new(color, brighterColor) -- Normal first, brighter second
end

--// Animation Functions
local function createColoredTypewriter(element, messageParts, duration, soundModule)
	-- Special typewriter for colored text parts without HTML parsing issues
	-- Build the complete text and color map
	local fullText = ""
	local colorMap = {}
	local currentIndex = 1
	
	for _, part in ipairs(messageParts) do
		local partText = part.text
		for i = 1, #partText do
			colorMap[currentIndex] = part.color
			currentIndex = currentIndex + 1
		end
		fullText = fullText .. partText
	end
	
	local textLength = #fullText
	local delayPerChar = 0.05 -- Fixed typing speed (consistent with regular typewriter)
	
	-- Start with empty text
	element.Text = ""
	element.RichText = true -- Enable RichText for colored output
	
	-- Start typewriter sound loop
	local typewriterSound = acquireTypewriterSound(soundModule)
	if typewriterSound then
		element:SetAttribute("HasTypewriterSound", true)
	end

	local function stopTypewriterSound(immediate)
		if not typewriterSound then
			return
		end
		releaseTypewriterSound(typewriterSound, not immediate)
		typewriterSound = nil
		element:SetAttribute("HasTypewriterSound", nil)
	end
	
	-- Reveal each character with proper coloring
	for i = 1, textLength do
		task.delay((i-1) * delayPerChar, function()
			if element and element.Parent then
				local currentText = string.sub(fullText, 1, i)
				
				-- Build RichText with proper colors
				local richText = ""
				local currentPartIndex = 1
				local partStartIndex = 1
				
				for partIndex, part in ipairs(messageParts) do
					local partText = part.text
					local partEndIndex = partStartIndex + #partText - 1
					
					if partStartIndex <= i then
						local visibleEnd = math.min(partEndIndex, i)
						local visiblePart = string.sub(partText, 1, visibleEnd - partStartIndex + 1)
						
						if part.color == "orange" then
							richText = richText .. "<font color=\"rgb(255, 188, 53)\">" .. visiblePart .. "</font>"
						elseif part.color == "red" then
							richText = richText .. "<font color=\"rgb(255, 50, 50)\">" .. visiblePart .. "</font>"
						elseif part.color == "white" then
							richText = richText .. visiblePart
						elseif string.sub(part.color, 1, 1) == "#" then
							-- Handle hex colors like "#FFD700"
							richText = richText .. "<font color=\"" .. part.color .. "\">" .. visiblePart .. "</font>"
						else
							richText = richText .. visiblePart
						end
					end
					
					partStartIndex = partEndIndex + 1
				end
				
				element.Text = richText
				
				-- Stop typewriter sound when last character is written
				if i == textLength then
					stopTypewriterSound(false)
				end
			else
				stopTypewriterSound(true)
			end
		end)
	end

	if element then
		element.Destroying:Connect(function()
			stopTypewriterSound(true)
		end)
		element:GetPropertyChangedSignal("Parent"):Connect(function()
			if not element.Parent then
				stopTypewriterSound(true)
			end
		end)
	end
end

local function createDefaultAnimation(element)
	-- Style 1: Your original elastic rotation animation
	-- Set the text immediately for non-typewriter animations
	local fullText = element:GetAttribute("FullText")
	if fullText then
		element.Text = fullText
	end
	
	local info = TweenInfo.new(1, Enum.EasingStyle.Elastic)
	element.Rotation = 5
	TweenService:Create(element, info, {Rotation = 0}):Play()
end

local function createTypewriterAnimation(element, duration, soundModule)
	-- Style 2: Letter-by-letter reveal like Inspector talking
	local fullText = element:GetAttribute("FullText") or element.Text
	local messagePartsJson = element:GetAttribute("MessageParts")
	duration = duration or 4 -- Default duration if not provided
	
	-- Check if we have special message parts for colored typewriter
	if messagePartsJson then
		local success, messageParts = pcall(HttpService.JSONDecode, HttpService, messagePartsJson)
		if success then
			createColoredTypewriter(element, messageParts, duration, soundModule)
			return
		end
	end
	
	-- Always use character-by-character for typewriter effect
	-- For RichText, we'll extract visible characters and build progressively
	local visibleText = fullText:gsub("<[^>]*>", "") -- Remove HTML tags to get visible characters
	local visibleLength = #visibleText
	
	-- Fixed typing speed (always the same speed regardless of message length)
	local delayPerChar = 0.065 -- 50ms per character (consistent typing speed)
	
	-- Start with empty text
	element.Text = ""
	
	-- Start typewriter sound loop
	local typewriterSound = acquireTypewriterSound(soundModule)
	if typewriterSound then
		element:SetAttribute("HasTypewriterSound", true)
	end

	local function stopTypewriterSound(immediate)
		if not typewriterSound then
			return
		end
		releaseTypewriterSound(typewriterSound, not immediate)
		typewriterSound = nil
		element:SetAttribute("HasTypewriterSound", nil)
	end
	
	if element.RichText then
		-- For RichText: character-by-character reveal while preserving HTML structure
		for i = 1, visibleLength do
			task.delay((i-1) * delayPerChar, function()
				if element and element.Parent then
					-- Show characters up to position i while preserving HTML
					local currentVisibleText = string.sub(visibleText, 1, i)
					local visibleIndex = 1
					
					-- Rebuild the HTML structure with progressive text
					local newText = fullText:gsub(">([^<]*)<", function(content)
						if #content > 0 then
							local contentStart = visibleIndex
							local contentEnd = visibleIndex + #content - 1
							visibleIndex = visibleIndex + #content
							
							if contentStart <= i then
								local actualEnd = math.min(contentEnd, i)
								local partialContent = string.sub(visibleText, contentStart, actualEnd)
								return ">" .. partialContent .. "<"
							else
								return "><"
							end
						else
							return "><"
						end
					end)
					
					element.Text = newText
					
					-- Stop typewriter sound when last character is written
					if i == visibleLength then
						stopTypewriterSound(false)
					end
				else
					stopTypewriterSound(true)
				end
			end)
		end
	else
		-- For plain text, use character-by-character reveal
		local textLength = #fullText
		
		-- Use duration: 2/3 of duration for typing, 1/3 for fade
		local typewriterTime = duration * (2/3) -- 2/3 of duration for typing
		local plainDelayPerChar = typewriterTime / math.max(textLength, 1)
		
		-- Reveal each character with a delay
		for i = 1, textLength do
			task.delay((i-1) * plainDelayPerChar, function()
				if element and element.Parent then
					element.Text = string.sub(fullText, 1, i)
					
					-- Stop typewriter sound when last character is written
					if i == textLength then
						stopTypewriterSound(false)
					end
				else
					stopTypewriterSound(true)
				end
			end)
		end
	end

	if element then
		element.Destroying:Connect(function()
			stopTypewriterSound(true)
		end)
		element:GetPropertyChangedSignal("Parent"):Connect(function()
			if not element.Parent then
				stopTypewriterSound(true)
			end
		end)
	end
end

local function createAggressivePopAnimation(element)
	-- Style 3: Aggressive pop-out for grades
	-- Set the text immediately for non-typewriter animations
	local fullText = element:GetAttribute("FullText")
	if fullText then
		element.Text = fullText
	end
	
	-- Start very small and explode outward with strong easing
	element.Size = UDim2.fromScale(0.1, 0.1)
	
	local popInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0)
	TweenService:Create(element, popInfo, {Size = UDim2.fromScale(1, 1)}):Play()
	
	-- Add slight shake at the end for extra impact
	task.delay(0.4, function()
		if element and element.Parent then
			local shakeInfo = TweenInfo.new(0.1, Enum.EasingStyle.Linear)
			local positions = {3, -3, 2, -2, 0}
			
			for i, rotation in ipairs(positions) do
				task.delay((i-1) * 0.05, function()
					if element and element.Parent then
						TweenService:Create(element, shakeInfo, {Rotation = rotation}):Play()
					end
				end)
			end
		end
	end)
end

-- Wiggle-only animation (no text change): reuse for same-message refresh
local function playRewiggleAnimation(element, animationType)
	if animationType == "aggressive" then
		local shakeInfo = TweenInfo.new(0.1, Enum.EasingStyle.Linear)
		local positions = {3, -3, 2, -2, 0}
		for i, rotation in ipairs(positions) do
			task.delay((i - 1) * 0.05, function()
				if element and element.Parent then
					TweenService:Create(element, shakeInfo, {Rotation = rotation}):Play()
				end
			end)
		end
	else
		-- default: elastic rotation wiggle
		element.Rotation = 5
		TweenService:Create(element, TweenInfo.new(1, Enum.EasingStyle.Elastic), {Rotation = 0}):Play()
	end
end

-- Cleanup expired immediate popups (check every 0.5 seconds instead of every frame)
task.spawn(function()
	while true do
		task.wait(0.5) -- Check every 0.5 seconds instead of 60 FPS
		local now = tick()
		for text, entry in pairs(activeImmediatePopups) do
			if entry.clone and not entry.clone.Parent then
				activeImmediatePopups[text] = nil
			elseif entry.destroyAt and now >= entry.destroyAt then
				if entry.clone and entry.clone.Parent then
					local Title = entry.clone:FindFirstChild("Title")
					if Title then
						local fade_info = TweenInfo.new(0.5, Enum.EasingStyle.Quad)
						TweenService:Create(Title, fade_info, {TextTransparency = 1}):Play()
						if Title:FindFirstChild("UIStroke") then
							TweenService:Create(Title.UIStroke, fade_info, {Transparency = 1}):Play()
						end
					end
					task.delay(0.5, function()
						if entry.clone and entry.clone.Parent then
							entry.clone:Destroy()
						end
					end)
				end
				activeImmediatePopups[text] = nil
			end
		end
		for popupType, entry in pairs(activeImmediatePopupsByType) do
			if entry.clone and not entry.clone.Parent then
				activeImmediatePopupsByType[popupType] = nil
			elseif entry.destroyAt and now >= entry.destroyAt then
				if entry.clone and entry.clone.Parent then
					local Title = entry.clone:FindFirstChild("Title")
					if Title then
						local fade_info = TweenInfo.new(0.5, Enum.EasingStyle.Quad)
						TweenService:Create(Title, fade_info, {TextTransparency = 1}):Play()
						if Title:FindFirstChild("UIStroke") then
							TweenService:Create(Title.UIStroke, fade_info, {Transparency = 1}):Play()
						end
					end
					task.delay(0.5, function()
						if entry.clone and entry.clone.Parent then
							entry.clone:Destroy()
						end
					end)
				end
				activeImmediatePopupsByType[popupType] = nil
			end
		end
	end
end)

--// Simple popup presets for backwards compatibility only
local BasicPresets = {
	success = {
		color = Color3.fromHex("40ee10"),
		sound = "NotError",
		duration = 3,
		animation = "default",
		category = "info"
	},
	error = {
		color = Color3.fromHex("ff2323"),
		sound = "Error", 
		duration = 3,
		animation = "default",
		category = "warning"
	},
	announcement = {
		color = Color3.fromHex("FFFFFF"),
		sound = "Announcement",
		duration = 6,
		animation = "default",
		category = "info"
	},
}

--// Functions
local Module = {}
Module.Shared_Shorten = Shared_Shorten

-- Show shutdown updating UI with BlackFrame animation
function Module:ShowShutdownUpdatingUI()
	local PlayerGui = game:GetService("Players").LocalPlayer.PlayerGui
	local TweenService = game:GetService("TweenService")
	
	-- Wait for UpdatingUI to be available
	local UpdatingUI = PlayerGui:WaitForChild("UpdatingUI")
	local Main = UpdatingUI:WaitForChild("MainFrame")
	
	-- Step 1: Hide MainFrame first
	Main.Visible = false
	
	-- Step 2: Enable UpdatingUI
	UpdatingUI.Enabled = true
	
	-- Step 4: Find BlackFrame and do the transition
	local blackFrame = UpdatingUI:FindFirstChild("BlackFrame")
	if blackFrame then
		-- Set initial size and make visible
		blackFrame.Size = UDim2.new(4, 0, 4, 0)
		blackFrame.Visible = true
		
		-- Tween BlackFrame to cover screen (from 4,0,4,0 to center)
		local coverTween = TweenService:Create(
			blackFrame,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = UDim2.new(0.001, 0, 0.001, 0)}
		)
		
		-- When BlackFrame covers screen, make MainFrame visible and tween back
		coverTween.Completed:Connect(function()
			-- Make MainFrame visible
			Main.Visible = true
			
			-- Tween BlackFrame back to original size
			local uncoverTween = TweenService:Create(
				blackFrame,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Size = UDim2.new(4, 0, 4, 0)}
			)
			
			uncoverTween:Play()
		end)
		
		-- Start the BlackFrame transition
		coverTween:Play()
	end
end


-- defaultCategory allows callers to override the fallback category when legacy inputs are used
function Module:ParsePopupConfig(input, defaultCategory)
	local config = {}
	
	-- Handle different input types
	if type(input) == "string" then
		-- Check if it's a basic preset
		if BasicPresets[input] then
			-- Use basic preset
			for key, value in pairs(BasicPresets[input]) do
				config[key] = value
			end
		else
			-- Legacy compatibility
			if input == "announcement" then
				config = BasicPresets.announcement
			elseif input and input ~= "" then
				config = BasicPresets.success
			else
				config = BasicPresets.error
			end
		end
	elseif type(input) == "table" then
		-- Custom configuration - copy all provided values
		for key, value in pairs(input) do
			config[key] = value
		end
	elseif input == nil or input == false then
		-- Legacy nil/false = error
		config = BasicPresets.error
	else
		-- Legacy truthy = success
		config = BasicPresets.success
	end
	
	-- Ensure required defaults
	config.duration = config.duration or 4
	config.animation = config.animation or "default"
	config.richText = config.richText or false
	config.category = config.category or defaultCategory or "info"
	config.persist = config.persist == true
	
	return config
end

-- Apply animation to popup element
function Module:ApplyAnimation(element, animationType, duration, soundModule)
	if animationType == "typewriter" then
		createTypewriterAnimation(element, duration, soundModule)
	elseif animationType == "aggressive" then
		createAggressivePopAnimation(element)
	else
		-- Default to original elastic animation
		createDefaultAnimation(element)
	end
end

function Module:Init()
	if moduleInitialized then
		return
	end
	moduleInitialized = true
	local Popup = ReplicatedStorage.Events:WaitForChild("Popup")
	Popup.OnClientEvent:Connect(function(popupData, popupConfig, extraConfig)
		ensureTutorialTracking()
		local extra = if typeof(extraConfig) == "table" then extraConfig else nil
		-- Table with text + amount (e.g. sell brainrot): show cash popup then message
		if type(popupData) == "table" and popupData.text and type(popupData.amount) == "number" and popupData.amount > 0 then
			if self.Client_ScreenPopup then
				self.Client_ScreenPopup:ShowCashPopup(popupData.amount)
			end
			local parsedConfig = self:ParsePopupConfig(popupConfig)
			if shouldAllowPopup(parsedConfig.category, extra) then
				self:AddPopupImmediate(popupData.text, popupConfig, parsedConfig)
			end
			return
		end
		if type(popupData) == "table" and popupData.type then
			local category = if extra and extra.category then extra.category
				elseif type(popupConfig) == "table" and popupConfig.category then popupConfig.category
				else popupData.category or "info"
			if not shouldAllowPopup(category, extra) then
				return
			end
			if popupData.type == "event_currency" then
				self:ShowEventCurrencyPopup(popupData)
			elseif popupData.type == "currency" then
				self:CurrencyScreen(popupData.amount, popupData.color, popupData.position, popupData.timeMultiplier or 1)
			elseif popupData.type == "cost" then
				local position = popupData.position or UDim2.fromScale(math.random(2, 8)/10, math.random(2, 8)/10)
				self:NegativeCurrencyScreen(popupData.amount, position, popupData.timeMultiplier or 3)
			else
				local fallbackConfig = self:ParsePopupConfig(popupConfig, category)
				if not shouldAllowPopup(fallbackConfig.category, extra) then
					return
				end
				self:AddPopupImmediate(popupData.text or "Unknown popup", popupConfig, fallbackConfig)
			end
		else
			if type(popupData) ~= "string" then
				return
			end
			local parsedConfig = self:ParsePopupConfig(popupConfig)
			if not shouldAllowPopup(parsedConfig.category, extra) then
				return
			end
			if extra and type(extra) == "table" then
				for k, v in pairs(extra) do
					parsedConfig[k] = v
				end
			end
			local text = popupData
			if text:sub(1, 5) == "COST:" then
				local Cost = tonumber(text:sub(6))
				if Cost then
					local RandomPosition = UDim2.fromScale(math.random(2, 8)/10, math.random(2, 8)/10)
					self:NegativeCurrencyScreen(Cost, RandomPosition, 3)
				end
			elseif text:sub(1, 6) == "EVENT:" then
				self:ShowEventCurrencyPopup(text)
			elseif popupConfig == "shutdown" then
				self:ShowShutdownUpdatingUI()
			else
				self:AddPopupImmediate(text, popupConfig, parsedConfig)
			end
		end
	end)
end

function Module:AddPopupImmediate(Text, PopupConfig, preParsedConfig)
	-- Parse configuration - support both legacy and new formats
	local config = preParsedConfig or self:ParsePopupConfig(PopupConfig)
	local duration = config.duration or 4
	
	-- BLOCK all non-tutorial popups during tutorial (steps 1-4)
	if not shouldAllowPopup(config.category, config) then
		return nil
	end

	-- Type-based: same type replaces previous (update text, color, rewiggle, reset lifetime, move to front)
	if config.popupType and type(config.popupType) == "string" then
		local existing = activeImmediatePopupsByType[config.popupType]
		if existing and existing.clone and existing.clone.Parent then
			existing.destroyAt = tick() + duration
			existing.config = config
			local title = existing.clone:FindFirstChild("Title")
			if title then
				title:SetAttribute("FullText", Text)
				title.Text = Text
				
			-- Re-apply gradient animations (be tolerant of nested UI objects)
			local titleGradient = title:FindFirstChild("UIGradient")
			if not titleGradient then
				local anyGradient = title:FindFirstChildWhichIsA("UIGradient", true)
				if anyGradient and anyGradient.Parent == title then
					titleGradient = anyGradient
				end
			end

			local uiStroke = title:FindFirstChildWhichIsA("UIStroke", true)
			local strokeGradient = uiStroke and uiStroke:FindFirstChildWhichIsA("UIGradient", true)
				
				-- Clean up existing animations
				if rainbowAnimations[title] then
					if rainbowAnimations[title].tweens then
						for _, tween in ipairs(rainbowAnimations[title].tweens) do
							tween:Cancel()
						end
					end
					if rainbowAnimations[title].shakeState then
						rainbowAnimations[title].shakeState.cancelled = true
						if rainbowAnimations[title].shakeState.connection then
							rainbowAnimations[title].shakeState.connection:Disconnect()
						end
					end
					if rainbowAnimations[title].connections then
						for _, connection in ipairs(rainbowAnimations[title].connections) do
							connection:Disconnect()
						end
					end
					if rainbowAnimations[title].connection then
						rainbowAnimations[title].connection:Disconnect()
					end
					rainbowAnimations[title] = nil
				end
				
				-- Special template: animated switch effect
				if config.useSpecialTemplate and config.gradient and titleGradient and strokeGradient then
					titleGradient.Enabled = true
					strokeGradient.Enabled = true
					
					local whiteColor = Color3.fromRGB(255, 255, 255)
					
					-- Get the rarity flat color
					local rarityKey = "Celestial"
					for key, data in pairs(Shared_Rarity.List) do
						if data.gradient == config.gradient then
							rarityKey = key
							break
						end
					end
					local rarityData = Shared_Rarity.List[rarityKey]
					local celestialColor = rarityData and rarityData.flatColor or Color3.fromRGB(230, 240, 255)
					
					-- Title: White (0 → 0.499) | Celestial color (0.501 → 1)
					local titleGradientSeq = ColorSequence.new{
						ColorSequenceKeypoint.new(0, whiteColor),
						ColorSequenceKeypoint.new(0.499, whiteColor),
						ColorSequenceKeypoint.new(0.501, celestialColor),
						ColorSequenceKeypoint.new(1, celestialColor)
					}
					
					-- Stroke: Celestial color (0 → 0.499) | White (0.501 → 1)
					local strokeGradientSeq = ColorSequence.new{
						ColorSequenceKeypoint.new(0, celestialColor),
						ColorSequenceKeypoint.new(0.499, celestialColor),
						ColorSequenceKeypoint.new(0.501, whiteColor),
						ColorSequenceKeypoint.new(1, whiteColor)
					}
					
					titleGradient.Rotation = 90
					strokeGradient.Rotation = 90
					
					titleGradient.Color = titleGradientSeq
					titleGradient.Offset = Vector2.new(0, -1)
					
					strokeGradient.Color = strokeGradientSeq
					-- Keep the exact same offset as title so the cutoff line matches
					strokeGradient.Offset = Vector2.new(0, -1)
					
					local function createSwapCycle()
						local tweenInfo = TweenInfo.new(
							1.5,
							Enum.EasingStyle.Linear,
							Enum.EasingDirection.InOut,
							-1, -- Infinite
							true, -- Reverse
							0 -- No delay between cycles
						)
						
						local titleTween = TweenService:Create(titleGradient, tweenInfo, {
							Offset = Vector2.new(0, 1)
						})
						
						local strokeTween = TweenService:Create(strokeGradient, tweenInfo, {
							Offset = Vector2.new(0, 1)
						})
						
						titleTween:Play()
						strokeTween:Play()
						
						-- Shake in intervals: 1s shake, 1s wait, repeat until destroyed
						local shakeState = { cancelled = false, connection = nil }
						task.spawn(function()
							while not shakeState.cancelled do
								-- Shake for 1 second
								shakeState.connection = RunService.RenderStepped:Connect(function()
									if shakeState.cancelled then return end
									if title and title.Parent then
										local shakeX = math.random(-1, 1)
										local shakeY = math.random(-1, 1)
										title.Position = UDim2.new(0.5, shakeX, 0.5, shakeY)
									end
								end)
								task.wait(1)
								
								-- Disconnect shake
								if shakeState.connection then
									shakeState.connection:Disconnect()
									shakeState.connection = nil
								end
								
								if shakeState.cancelled then break end
								
								-- Reset to center and wait
								if title and title.Parent then
									title.Position = UDim2.new(0.5, 0, 0.5, 0)
								end
								task.wait(1)
							end
						end)
						
						if not rainbowAnimations[title] then
							rainbowAnimations[title] = {tweens = {}, connections = {}, shakeState = shakeState}
						end
						table.insert(rainbowAnimations[title].tweens, titleTween)
						table.insert(rainbowAnimations[title].tweens, strokeTween)
						rainbowAnimations[title].shakeState = shakeState
					end
					
					createSwapCycle()
				-- Regular gradient handling
				elseif titleGradient then
					if config.gradient then
						titleGradient.Color = config.gradient
						
						if config.isRainbow then
							titleGradient.Rotation = 0
							
							local startTime = tick()
							local connection = RunService.RenderStepped:Connect(function()
								local elapsed = tick() - startTime
								local keypoints = Shared_GradientAnimations:CalculateRainbowGradient(elapsed, 0)
								titleGradient.Color = ColorSequence.new(keypoints)
							end)
							
							rainbowAnimations[title] = {
								connection = connection,
								startTime = startTime
							}
						else
							titleGradient.Rotation = 90
						end
					elseif config.color then
						titleGradient.Color = getColorGradient(config.color)
					end
				end
				
				playRewiggleAnimation(title, config.animation or "default")
			end
			-- Replay sound on rewiggle
			if config.animation ~= "typewriter" then
				if config.sound and self.Client_Sounds then
					self.Client_Sounds:Play(config.sound)
				elseif self.Client_Sounds then
					self.Client_Sounds:Play("Message")
				end
			end
			-- Move to front row: set LayoutOrder to highest (most recent)
			nextLayoutOrder += 1
			existing.clone.LayoutOrder = nextLayoutOrder
			return existing.clone
		end
	end

	-- Same message already visible (no type): rewiggle and reset lifetime (replay sound, move to front)
	local existing = activeImmediatePopups[Text]
	if existing and existing.clone and existing.clone.Parent then
		existing.destroyAt = tick() + duration
		local title = existing.clone:FindFirstChild("Title")
		if title then
			playRewiggleAnimation(title, config.animation or "default")
		end
		-- Replay sound on rewiggle
		if config.animation ~= "typewriter" then
			if config.sound and self.Client_Sounds then
				self.Client_Sounds:Play(config.sound)
			elseif self.Client_Sounds then
				self.Client_Sounds:Play("Message")
			end
		end
		-- Move to front row: set LayoutOrder to highest (most recent)
		nextLayoutOrder += 1
		existing.clone.LayoutOrder = nextLayoutOrder
		return existing.clone
	end

	-- Create popup immediately without waiting for Show() loop
	local Clone
	if config.useSpecialTemplate then
		Clone = Main.Popups.SpecialTemplate:Clone()
	else
		Clone = Main.Popups.Template:Clone()
	end
	Clone.Name = "Message"
	
	-- Handle large size for grades
	if config.scaleMultiplier then
		Clone.Size = UDim2.new(Clone.Size.X.Scale, Clone.Size.X.Offset, Clone.Size.Y.Scale * config.scaleMultiplier, Clone.Size.Y.Offset)
	end
	
	-- Get the Title inside the Template
	local Title = Clone:FindFirstChild("Title")
	if not Title then return end

	local function stopTypewriterSound()
		if Title:GetAttribute("HasTypewriterSound") then
			Title:SetAttribute("HasTypewriterSound", nil)
			releaseTypewriterSound(nil, false)
		end
	end

	Clone.Destroying:Connect(stopTypewriterSound)
	Clone:GetPropertyChangedSignal("Parent"):Connect(function()
		if not Clone.Parent then
			stopTypewriterSound()
		end
	end)
	
	-- Configure RichText vs Gradient BEFORE setting text (be tolerant of nested UI objects)
	local titleGradient = Title:FindFirstChild("UIGradient")
	if not titleGradient then
		local anyGradient = Title:FindFirstChildWhichIsA("UIGradient", true)
		if anyGradient and anyGradient.Parent == Title then
			titleGradient = anyGradient
		end
	end

	local uiStroke = Title:FindFirstChildWhichIsA("UIStroke", true)
	local strokeGradient = uiStroke and uiStroke:FindFirstChildWhichIsA("UIGradient", true)
	
	if config.richText then
		-- Enable RichText, disable gradients
		Title.RichText = true
		if titleGradient then
			titleGradient.Enabled = false
		end
		if strokeGradient then
			strokeGradient.Enabled = false
		end
	elseif config.messageParts then
		-- MessageParts require RichText for colored text
		Title.RichText = true
		if titleGradient then
			titleGradient.Enabled = false
		end
		if strokeGradient then
			strokeGradient.Enabled = false
		end
		-- Ensure stroke is visible for tutorial popups
		if uiStroke then
			uiStroke.Transparency = 0
		end
	else
		-- Disable RichText, enable gradient with color
		Title.RichText = false
		
		-- Special template: animated switch effect with rainbow colors (Divine) or static color (Celestial)
		if config.useSpecialTemplate and config.gradient and titleGradient and strokeGradient then
			titleGradient.Enabled = true
			strokeGradient.Enabled = true
			
			local whiteColor = Color3.fromRGB(255, 255, 255)
			
			-- Get the rarity data to check if it's Divine (rainbow)
			local rarityKey = "Celestial" -- Default to Celestial
			local isDivine = false
			for key, data in pairs(Shared_Rarity.List) do
				if data.gradient == config.gradient then
					rarityKey = key
					isDivine = data.isRainbow == true
					break
				end
			end
			
			if isDivine then
				-- Divine: Rainbow colors with sliding white/color split
				titleGradient.Enabled = true
				strokeGradient.Enabled = true
				titleGradient.Rotation = 90
				strokeGradient.Rotation = 90
				
				-- Use proper Divine rainbow colors from Shared_Rarity (nicer colors!)
				local rainbowColors = {
					Color3.fromRGB(255, 81, 81),     -- Red
					Color3.fromRGB(255, 255, 0),   -- Yellow
					Color3.fromRGB(0, 255, 0),     -- Green
					Color3.fromRGB(79, 217, 255),   -- Blue
					Color3.fromRGB(255, 49, 224),    -- Indigo/Purple
				}
				
				local whiteColor = Color3.fromRGB(255, 255, 255)
				local startTime = tick()
				local RAINBOW_SPEED = 0.5
				
				local connection = RunService.RenderStepped:Connect(function()
					local elapsed = tick() - startTime
					local loop = ((elapsed * RAINBOW_SPEED) % 1)
					
					-- Cycle through the 6 rainbow colors smoothly
					local colorIndex = math.floor(loop * #rainbowColors) + 1
					local nextIndex = (colorIndex % #rainbowColors) + 1
					local t = (loop * #rainbowColors) % 1
					local currentColor = rainbowColors[colorIndex]:Lerp(rainbowColors[nextIndex], t)
					
					-- Title: White (0 → 0.499) | Rainbow color (0.501 → 1)
					local titleGradientSeq = ColorSequence.new{
						ColorSequenceKeypoint.new(0, whiteColor),
						ColorSequenceKeypoint.new(0.499, whiteColor),
						ColorSequenceKeypoint.new(0.501, currentColor),
						ColorSequenceKeypoint.new(1, currentColor)
					}
					
					-- Stroke: Rainbow color (0 → 0.499) | White (0.501 → 1)
					local strokeGradientSeq = ColorSequence.new{
						ColorSequenceKeypoint.new(0, currentColor),
						ColorSequenceKeypoint.new(0.499, currentColor),
						ColorSequenceKeypoint.new(0.501, whiteColor),
						ColorSequenceKeypoint.new(1, whiteColor)
					}
					
					titleGradient.Color = titleGradientSeq
					strokeGradient.Color = strokeGradientSeq
				end)
				
				-- Add sliding animation
				titleGradient.Offset = Vector2.new(0, -1)
				strokeGradient.Offset = Vector2.new(0, -1)
				
				local tweenInfo = TweenInfo.new(
					1.5,
					Enum.EasingStyle.Linear,
					Enum.EasingDirection.InOut,
					-1, -- Infinite
					true, -- Reverse (yoyo)
					0
				)
				
				local titleTween = TweenService:Create(titleGradient, tweenInfo, {Offset = Vector2.new(0, 1)})
				local strokeTween = TweenService:Create(strokeGradient, tweenInfo, {Offset = Vector2.new(0, 1)})
				
				titleTween:Play()
				strokeTween:Play()
				
				-- Track animations
				rainbowAnimations[Clone] = {
					connection = connection,
					tweens = {titleTween, strokeTween},
					startTime = startTime
				}
				
				-- Play confetti for Divine (no sound)
				local Client_EffectsLibrary = require(script.Parent.Parent.Effects.Client_EffectsLibrary)
				if Client_EffectsLibrary then
					Client_EffectsLibrary:PlayConfetti(60, 2, 1, "") -- Empty string = no sound
				end
			else
				-- Celestial: Static color
				local rarityData = Shared_Rarity.List[rarityKey]
				local celestialColor = rarityData and rarityData.flatColor or Color3.fromRGB(230, 240, 255)
				
				-- Create simple gradients with sharp cutoff
				local titleGradientSeq = ColorSequence.new{
					ColorSequenceKeypoint.new(0, whiteColor),
					ColorSequenceKeypoint.new(0.499, whiteColor),
					ColorSequenceKeypoint.new(0.501, celestialColor),
					ColorSequenceKeypoint.new(1, celestialColor)
				}
				
				local strokeGradientSeq = ColorSequence.new{
					ColorSequenceKeypoint.new(0, celestialColor),
					ColorSequenceKeypoint.new(0.499, celestialColor),
					ColorSequenceKeypoint.new(0.501, whiteColor),
					ColorSequenceKeypoint.new(1, whiteColor)
				}
				
				titleGradient.Rotation = 90
				strokeGradient.Rotation = 90
				
				titleGradient.Color = titleGradientSeq
				titleGradient.Offset = Vector2.new(0, -1)
				
				strokeGradient.Color = strokeGradientSeq
				strokeGradient.Offset = Vector2.new(0, -1)
				
				-- Sliding animation
				local tweenInfo = TweenInfo.new(
					1.5,
					Enum.EasingStyle.Linear,
					Enum.EasingDirection.InOut,
					-1, -- Infinite
					true, -- Reverse (yoyo)
					0
				)
				
				local titleTween = TweenService:Create(titleGradient, tweenInfo, {Offset = Vector2.new(0, 1)})
				local strokeTween = TweenService:Create(strokeGradient, tweenInfo, {Offset = Vector2.new(0, 1)})
				
				titleTween:Play()
				strokeTween:Play()
				
				rainbowAnimations[Clone] = {
					tweens = {titleTween, strokeTween}
				}
			end
			
			-- Add subtle shake in intervals: 1s shake, 1s wait, repeat until destroyed
			local shakeState = { cancelled = false, connection = nil }
			task.spawn(function()
				while not shakeState.cancelled do
					shakeState.connection = RunService.RenderStepped:Connect(function()
						if shakeState.cancelled then return end
						if Clone and Clone.Parent and Title then
							local shakeX = math.random(-1, 1)
							local shakeY = math.random(-1, 1)
							Title.Position = UDim2.new(0.5, shakeX, 0.5, shakeY)
						end
					end)
					task.wait(1)
					
					if shakeState.connection then
						shakeState.connection:Disconnect()
						shakeState.connection = nil
					end
					
					if shakeState.cancelled then break end
					
					if Clone and Clone.Parent and Title then
						Title.Position = UDim2.new(0.5, 0, 0.5, 0)
					end
					task.wait(1)
				end
			end)
			
			if rainbowAnimations[Clone] then
				rainbowAnimations[Clone].shakeState = shakeState
			end
			
			-- Cleanup when popup is destroyed
			Clone.AncestryChanged:Connect(function()
				if not Clone.Parent and rainbowAnimations[Clone] then
					if rainbowAnimations[Clone].connection then
						rainbowAnimations[Clone].connection:Disconnect()
					end
					if rainbowAnimations[Clone].tweens then
						for _, tween in ipairs(rainbowAnimations[Clone].tweens) do
							tween:Cancel()
						end
					end
					if rainbowAnimations[Clone].shakeState then
						rainbowAnimations[Clone].shakeState.cancelled = true
						if rainbowAnimations[Clone].shakeState.connection then
							rainbowAnimations[Clone].shakeState.connection:Disconnect()
						end
					end
					rainbowAnimations[Clone] = nil
				end
			end)
		-- Regular gradient handling
		elseif titleGradient then
			titleGradient.Enabled = true
			
			if config.gradient then
				titleGradient.Color = config.gradient
				
				-- Mythical (rainbow): animate color keypoints
				if config.isRainbow then
					titleGradient.Rotation = 0
					
					local startTime = tick()
					local connection = RunService.RenderStepped:Connect(function()
						local elapsed = tick() - startTime
						local keypoints = Shared_GradientAnimations:CalculateRainbowGradient(elapsed, 0)
						titleGradient.Color = ColorSequence.new(keypoints)
					end)
					
					-- Track animation for cleanup
					rainbowAnimations[Clone] = {
						connection = connection,
						startTime = startTime
					}
					
					-- Cleanup when popup is destroyed
					Clone.AncestryChanged:Connect(function()
						if not Clone.Parent and rainbowAnimations[Clone] then
							rainbowAnimations[Clone].connection:Disconnect()
							rainbowAnimations[Clone] = nil
						end
					end)
				else
					-- Other rarities use 90 degrees (vertical)
					titleGradient.Rotation = 90
				end
			elseif config.color then
				titleGradient.Color = getColorGradient(config.color)
			end
		end
	end
	
	-- Handle special messageParts for colored typewriter
	if config.messageParts then
		-- Store message parts for special colored typewriter
		Title:SetAttribute("MessageParts", game:GetService("HttpService"):JSONEncode(config.messageParts))
		Title:SetAttribute("FullText", "") -- Will be built from parts
	else
		-- Store the text for animation, but don't set it yet
		Title:SetAttribute("FullText", Text)
	end
	
	-- Keep TextScaled enabled (don't modify TextSize)
	-- TextScaled is already set on the template
	
	-- Play sound if specified and enabled
	-- Typewriter animations automatically use typewriter sound, others use their specified sound
	if config.animation == "typewriter" then
		-- Typewriter animations automatically get typewriter sound (handled by animation)
		-- No need to play main sound here
	elseif config.sound then
		-- Check if it's an asset ID (starts with "rbxassetid://")
		if string.match(config.sound, "^rbxassetid://") then
			-- Create and play temporary sound for asset IDs
			local sound = Instance.new("Sound")
			sound.SoundId = config.sound
			sound.Volume = 2
			sound.PlaybackSpeed = 1 -- Fixed playback speed (no random pitch)
			if self.Client_Sounds then
				self.Client_Sounds:SetGroup(sound, "SFX")
			end
			sound.Parent = game:GetService("SoundService")
			sound:Play()
			sound.Ended:Connect(function()
				sound:Destroy()
			end)
			
			-- Don't return sound - continue with popup creation
		elseif self.Client_Sounds then
			-- Use predefined sound name
			self.Client_Sounds:Play(config.sound)
		end
	elseif self.Client_Sounds then
		-- No sound specified - play default message notification sound
		self.Client_Sounds:Play("Message")
	end
	
	-- Apply animation (this will handle setting the text and sound for typewriter)
	self:ApplyAnimation(Title, config.animation, config.duration, self.Client_Sounds)
	
	-- Set LayoutOrder for new popups (higher = more recent = front row)
	nextLayoutOrder += 1
	Clone.LayoutOrder = nextLayoutOrder
	
	Clone.Parent = Main.Popups
	Clone.Visible = true
	
	if config.persist then
		registerPersistentPopup(Clone, config)
	else
		local entry = {
			clone = Clone,
			destroyAt = tick() + duration,
			config = config,
		}
		if config.popupType and type(config.popupType) == "string" then
			activeImmediatePopupsByType[config.popupType] = entry
			Clone.AncestryChanged:Connect(function(_, parent)
				if not parent and activeImmediatePopupsByType[config.popupType] and activeImmediatePopupsByType[config.popupType].clone == Clone then
					activeImmediatePopupsByType[config.popupType] = nil
				end
			end)
		else
			activeImmediatePopups[Text] = entry
			Clone.AncestryChanged:Connect(function(_, parent)
				if not parent and activeImmediatePopups[Text] and activeImmediatePopups[Text].clone == Clone then
					activeImmediatePopups[Text] = nil
				end
			end)
		end
	end
	
	return Clone
end

function Module:AddPopup(Text, PopupColor)
	if Popups[Text] then
		Popups[Text].Number += 1
		Popups[Text].Time = 0
		Popups[Text].StartTime = tick()  -- Store when this popup started
	else
		Popups[Text] = {Time = 0, Color = PopupColor, Number = 1, StartTime = tick()}
	end
end

function Module:Show()
	for ID, Popup in pairs(Popups) do
		Popup.Time += 1

		-- Check if popup should be destroyed (after 6 seconds total)
		local elapsedTime = tick() - Popup.StartTime
		if elapsedTime >= 6 then
			local Text = Main.Popups:FindFirstChild(ID)
			if Text and Text:IsA("TextLabel") then
				Text:Destroy()
			end
			Popups[ID] = nil
			continue
		end

		local Text = Main.Popups:FindFirstChild(ID)
		if Text and Text:IsA("TextLabel") then
			if Popup.Number > 1 then
				Text.Text = ID.." ["..Popup.Number.."x]"
			end
			-- Fade out effect: stay visible for 5 seconds, then fade over 1 second
			if elapsedTime <= 5 then
				-- First 5 seconds: fully visible (0 transparency)
				Text.TextTransparency = 0
				Text.UIStroke.Transparency = 0
			elseif elapsedTime <= 6 then
				-- Next 1 second: smooth fade from 0 to 1 transparency
				local fadeProgress = (elapsedTime - 5) / 1  -- 1 second fade
				-- Clamp to ensure smooth 0.0 to 1.0 range
				fadeProgress = math.clamp(fadeProgress, 0, 1)
				-- Use smooth easing for nicer fade effect
				local easedFade = fadeProgress * fadeProgress  -- Quadratic easing for smoother transition
				Text.TextTransparency = easedFade
				Text.UIStroke.Transparency = easedFade
			else
				-- After 6 seconds: fully transparent
				Text.TextTransparency = 1
				Text.UIStroke.Transparency = 1
			end
		elseif not Text then
			local Clone = Main.Popups.Title:Clone()
			Clone.Text = ID
			Clone.Name = ID
			
			-- Handle special announcement case
			if Popup.Color == "announcement" then
				self.Client_Sounds:Play("Announcement")
				Clone.TextColor3 = Color3.fromHex("FFFFFF") -- White text
				-- Make announcement text larger and more prominent
				Clone.TextScaled = true
				Clone.TextSize = 24
			elseif Popup.Color then
				self.Client_Sounds:Play("NotError")
				Clone.TextColor3 = Color3.fromHex("7BFF00") -- Green text
			else
				self.Client_Sounds:Play("Error")
				Clone.TextColor3 = Color3.fromHex("FB0104") -- Red text
			end
			
			-- Add cool gradient effect
			local gradient = Instance.new("UIGradient")
			gradient.Parent = Clone
			local baseColor = Clone.TextColor3
			gradient.Color = getColorGradient(baseColor)
			
			-- Add cool elastic rotation animation
			local rot_info = TweenInfo.new(1, Enum.EasingStyle.Elastic)
			Clone.Rotation = 5
			TweenService:Create(Clone, rot_info, {Rotation = 0}):Play()
			
			Clone.Parent = Main.Popups
			Clone.Visible = true
		end
	end
end


function Module:CurrencyScreen(Amount, Color, Position, TimeMultiplier)
	local Title = Main.Popup:Clone()
	Title.Position = Position
	Title.Text = "+"..self.Shared_Shorten:Number(Amount).."$"
	Title.TextColor3 = Color
	Title.Parent = Main
	Title.Visible = true
	
	-- Start with moderate size (not too big)
	Title.Size = UDim2.fromScale(0.1, 0.05) -- Smaller, more reasonable size
	
	task.spawn(function()
		-- Phase 1: Pop in with scale effect
		self.Client_Tween:SoftTween(Title, .15*TimeMultiplier, {Size = UDim2.fromScale(0.08, 0.04)}, true) -- Scale down slightly
		self.Client_Tween:SoftTween(Title, .1*TimeMultiplier, {Rotation = math.random(-8,8)}, true) -- Subtle rotation
		
		-- Phase 2: Start moving up immediately (no pause)
		local finalY = Position.Y.Scale - 0.12 -- Float up
		self.Client_Tween:SoftTween(Title, .6*TimeMultiplier, {Position = UDim2.fromScale(Position.X.Scale, finalY)})
		
		-- Phase 3: Delayed fade (text stays visible while moving)
		task.wait(.25*TimeMultiplier) -- Let text be visible while moving up
		-- Start both fades in the same frame (truly simultaneous)
		local fadeTime = .35*TimeMultiplier
		self.Client_Tween:SoftTween(Title, fadeTime, {TextTransparency = 1}, true) -- Text fade
		self.Client_Tween:SoftTween(Title.UIStroke, fadeTime, {Transparency = 1}, true) -- Stroke fade (same frame)
		
		-- Wait for everything to complete, then destroy
		task.wait(.35*TimeMultiplier)
		Title:Destroy()	
	end)
end

function Module:NegativeCurrencyScreen(Amount, Position, TimeMultiplier)
	local Title = Main.Popup:Clone()
	Title.Position = Position
	Title.Text = "-"..self.Shared_Shorten:Number(Amount).."$"
	Title.TextColor3 = Color3.fromRGB(255, 0, 0) -- Red color for spending
	Title.Parent = Main
	Title.Visible = true
	
	-- Start with moderate size (same as positive, not too big)
	Title.Size = UDim2.fromScale(0.1, 0.05) -- Smaller, more reasonable size
	
	task.spawn(function()
		-- Phase 1: Pop in with scale effect
		self.Client_Tween:SoftTween(Title, .15*TimeMultiplier, {Size = UDim2.fromScale(0.08, 0.04)}, true) -- Scale down slightly
		self.Client_Tween:SoftTween(Title, .1*TimeMultiplier, {Rotation = math.random(-8,8)}, true) -- Subtle rotation
		
		-- Phase 2: Start moving down immediately (no pause)
		local finalY = Position.Y.Scale + 0.12 -- Float down for negative amounts
		self.Client_Tween:SoftTween(Title, .6*TimeMultiplier, {Position = UDim2.fromScale(Position.X.Scale, finalY)}, true)
		
		-- Phase 3: Delayed fade (text stays visible while moving)
		task.wait(.25*TimeMultiplier) -- Let text be visible while moving down
		-- Start both fades in the same frame (truly simultaneous)
		local fadeTime = .35*TimeMultiplier
		self.Client_Tween:SoftTween(Title, fadeTime, {TextTransparency = 1}, true) -- Text fade
		self.Client_Tween:SoftTween(Title.UIStroke, fadeTime, {Transparency = 1}, true) -- Stroke fade (same frame)
		
		-- Wait for everything to complete, then destroy
		task.wait(.35*TimeMultiplier)
		Title:Destroy()
	end)
end

function Module:CurrencyGround(TotalCurrency, GameplayCurrency, Position)
	local Data = Players.LocalPlayer:FindFirstChild("Data")
	if not Data then return end
	
	local Plot = Workspace.Core.Scriptable.Plots:FindFirstChild(Data.CurrentPlot.Value)
	if not Plot then return end
	
	local HoneyPot = Plot:FindFirstChild("HoneyPot")
	if not HoneyPot then return end
	
	-- Get jar fill percentage before pickup
	local jarFillPercentage = HoneyPot:GetAttribute("FillPercentage") or 0
	
	-- Calculate drain time based on jar fill percentage (needed for scaling sync)
	local drainTime = math.clamp(jarFillPercentage / 100 * 2.5 + 0.5, 0.5, 3.0)
	
	-- STEP 1: Lock animation immediately to prevent conflicts
	HoneyPot:SetAttribute("IsAnimating", true)
	
	-- Reset money counter trigger flag for this animation
	self.moneyCounterTriggered = false
	
	-- Reset any previous drain position tracking for clean start
	local MovingPart = HoneyPot:FindFirstChild("MovingPart")
	if MovingPart then
		MovingPart:SetAttribute("StartDrainPosition", nil)
	end
	
	-- STEP 2: Touch feedback effect (runs in parallel with drainage - no delay)
	task.spawn(function()
		-- Create temporary highlight
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 215, 0) -- Golden
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255) -- White
	highlight.FillTransparency = 0.6
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = HoneyPot
	
		-- Smooth scale effect (like thunder effects)
		local originalScale = HoneyPot:GetAttribute("OriginalScale") or 1
		HoneyPot:SetAttribute("OriginalScale", originalScale)
		
		-- Track current scale for position calculations
		HoneyPot:SetAttribute("CurrentScale", originalScale)
		
		-- Scale up smoothly
		local scaleUpInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		self.Client_Tween:tweenScale(originalScale, originalScale * 1.1, scaleUpInfo, HoneyPot)
		HoneyPot:SetAttribute("CurrentScale", originalScale * 1.1)
		
		task.wait(0.2)
		
		-- Scale back down smoothly over drainage duration and fade highlight
		local scaleDownInfo = TweenInfo.new(drainTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		self.Client_Tween:tweenScale(originalScale * 1.1, originalScale, scaleDownInfo, HoneyPot)
		self.Client_Tween:SoftTween(highlight, drainTime, {FillTransparency = 1, OutlineTransparency = 1})
		HoneyPot:SetAttribute("CurrentScale", originalScale)
		
		task.wait(drainTime)
		highlight:Destroy()
	end)
	
	-- STEP 3: Start drainage animation immediately (parallel with highlight)

	local Model = script:FindFirstChild("Coins")
	if Model and Model:IsA("Model") and Model:FindFirstChildWhichIsA("BasePart") then
		if not Model.PrimaryPart then
			Model.PrimaryPart = Model:FindFirstChildWhichIsA("BasePart")
		end

		-- Scale animation based on jar fill percentage (drainTime already calculated above)
		local coinCount = math.clamp(math.floor(jarFillPercentage / 4) + 5, 5, 25) -- Normal progression caps at 25
		if jarFillPercentage >= 100 then
			coinCount = 40 -- Bonus coins for 100% full jar - epic effect!
		end
		local baseCoinRate = coinCount / drainTime * 1.5 -- Base spawn rate
		
		-- Calculate money per coin for popups
		-- Ensure minimum 1$ per coin to avoid +0$ popups for small amounts
		local moneyPerCoin = math.max(1, math.floor(TotalCurrency / coinCount))
		
		-- Start animated countdown of coin collector UI (sync with drain)
		-- Predict what the new values will be after animation completes
		local animationDuration = drainTime * 1.5
		local incomePerSecond = HoneyPot:GetAttribute("IncomePerSecond") or 0
		local predictedNewCoinValue = incomePerSecond * animationDuration -- Predict coin accumulation
		
		-- Predict jar fill percentage (income accumulates over 60 seconds for 100% fill)
		-- VIP players get 2x faster fill, so they reach 100% in 30 seconds
		local predictedFillPercentage = math.min((animationDuration / 60) * 100, 100) -- Max 100%
		
		local coins = {}
		local coinsSpawned = 0
		local nextCoinTime = 0 -- First coin spawns immediately
		
		-- STAGE 1: Jar draining with coin spawning
		local drainElapsed = 0
		local collectElapsed = 0
		local totalElapsed = 0
		local isCollecting = false
		
		local Connection
		Connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
			totalElapsed += dt
			
			if not isCollecting then
				-- DRAINING PHASE: Spawn coins as jar drains
				drainElapsed += dt
				nextCoinTime -= dt
				
				-- Animate jar drain - fast start (synced with scaling) then slow down
				local drainAlpha = math.clamp(drainElapsed / drainTime, 0, 1)
				local drainProgress = 1 - (1 - drainAlpha)^2 -- Fast start, then decelerates (ease-out quad)
				
				-- Update jar visual (MovingPart position) - drain from current to predicted level
				local MovingPart = HoneyPot:FindFirstChild("MovingPart")
				if MovingPart then
					local bottomPosition = MovingPart:GetAttribute("BottomPosition")
					if bottomPosition and not MovingPart:GetAttribute("StartDrainPosition") then
						-- Store the starting position for this drain
						MovingPart:SetAttribute("StartDrainPosition", MovingPart.Position)
					end
					
					local startPosition = MovingPart:GetAttribute("StartDrainPosition")
					if startPosition and bottomPosition then
						-- Get current scale factor for scale-aware position calculation
						local currentScale = HoneyPot:GetAttribute("CurrentScale") or 1
						
						-- Calculate predicted end position based on predicted fill percentage
						local partSize = MovingPart.Size
						local maxHeight = partSize.Y * currentScale -- Adjust for scale
						local scaledBottomPosition = bottomPosition -- Bottom stays the same
						local scaledTopPosition = scaledBottomPosition + Vector3.new(0, maxHeight, 0)
						local predictedEndPosition = scaledBottomPosition + (scaledTopPosition - scaledBottomPosition) * (predictedFillPercentage / 100)
						
						-- Smoothly drain from current position to predicted level (scale-aware)
						local targetPosition = startPosition:Lerp(predictedEndPosition, drainProgress)
						MovingPart.Position = targetPosition
					end
				end
				
				-- No drain sound - only individual pop sounds
				
				-- Spawn coins smoothly based on drain progress (no gaps)
				local targetCoinsSpawned = math.floor(drainProgress * coinCount + 0.5) -- Round to nearest for smooth spawning
				
				-- Ensure at least 1 coin spawns when drain starts
				if drainProgress > 0 and targetCoinsSpawned < 1 then
					targetCoinsSpawned = 1
				end
				
				-- Spawn coins smoothly without gaps
				while coinsSpawned < targetCoinsSpawned and coinsSpawned < coinCount do
					coinsSpawned += 1
					
					-- Create coin and position at jar center-top, then parent (no teleport trail)
			local Clone = Model:Clone()
					
					-- Get HoneyPot part for proper positioning
					local honeyPotPart = HoneyPot.PrimaryPart or HoneyPot:FindFirstChildWhichIsA("BasePart")
					if not honeyPotPart then
						warn("HoneyPot has no valid parts for coin spawning")
						return
					end
					
					-- Calculate center-top of HoneyPot (fountain spawn point)
					local partSize = honeyPotPart.Size
					local centerTop = honeyPotPart.Position + Vector3.new(0, partSize.Y/2, 0)
					
					-- Calculate ground level (subtract part height) + 0.5 studs up
					local groundLevel = honeyPotPart.Position.Y - partSize.Y/2 + 1
					
					-- Generate random direction for curved trajectory (much wider spread)
					local angle = math.random() * math.pi * 2 -- Random angle around circle
					local distance = math.random(12, 18) -- Even further spread (was 8-15)
					
					-- Landing position in circle around jar (further out)
					local landingPos = Vector3.new(
						centerTop.X + math.cos(angle) * distance,
						groundLevel,
						centerTop.Z + math.sin(angle) * distance
					)
					
					-- Start coin at center-top (fountain source)
					Clone:PivotTo(CFrame.new(centerTop))
					
					-- Now parent to workspace (positioned first!)
			Clone.Parent = Workspace

					-- Setup coin parts
			local Parts = {}
			for _, part in pairs(Clone:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
							part.Transparency = part == Clone.PrimaryPart and 1 or 0
							table.insert(Parts, part)
						end
					end
					
					-- Play varied coin pop sound
					task.spawn(function()
						local popSound = Instance.new("Sound")
						popSound.SoundId = "rbxassetid://120588150624601"
						popSound.Volume = 0.5
						popSound.PlaybackSpeed = math.random(80, 120) / 100 -- 0.8x to 1.2x speed for variety
						self.Client_Sounds:SetGroup(popSound, "SFX")
						popSound.Parent = Clone
						popSound:Play()
						
						-- Clean up sound after playing
						popSound.Ended:Connect(function()
							popSound:Destroy()
						end)
					end)
					
					-- Store coin data
					table.insert(coins, {
						model = Clone,
						parts = Parts,
						spawnPos = centerTop, -- Start at center-top of jar
						landingPos = landingPos, -- Land in circle around jar
						spawnTime = totalElapsed,
						isLanded = false,
						rotationSpeed = math.rad(math.random(180, 360)), -- Y-axis rotation speed only
						currentRotation = 0, -- Single Y rotation value
						originalSizes = {},
						state = "falling" -- States: "falling", "spinning", "flying"
					})
					
					-- Store original sizes
					for _, part in pairs(Parts) do
						coins[#coins].originalSizes[part] = part.Size
					end
				end -- Close while loop
				
				-- Check if drain phase is complete
				if drainElapsed >= drainTime then
					if not isCollecting then
						-- Collection phase starting - drainage stopped, allow normal updates
						HoneyPot:SetAttribute("IsAnimating", false)
					end
					isCollecting = true
					-- No sound here - individual coins play sound when collected
				end
				
			else
				-- COLLECTION PHASE: Send coins one by one to player
				collectElapsed += dt
			end
			
			-- UPDATE COINS: This runs during BOTH drain and collection phases
			local collectTime = 0.8
			for i, coin in ipairs(coins) do
				if coin.model and coin.model.Parent then
					local coinAge = totalElapsed - coin.spawnTime
					local fallTime = 0.6 -- Faster fall time for more explosive feel (was 0.8)
					
					if coin.state == "falling" then
						-- FALLING PHASE: Simple chest pop-out effect
						local t = math.clamp(coinAge / fallTime, 0, 1)
						
						local startPos = coin.spawnPos
						local endPos = coin.landingPos
						
						-- Simple horizontal lerp
						local currentHorizontal = startPos:Lerp(endPos, t)
						
						-- Proper gravity fall - pop up then fall down naturally
						local bounceHeight = 5 -- Initial pop height
						local gravity = 20 -- Gravity pull down
						
						-- Pop up quickly, then fall with gravity
						local upTime = 0.3 -- First 30% is pop-up
						local verticalOffset
						if t <= upTime then
							-- Pop-up phase
							verticalOffset = bounceHeight * (t / upTime)
						else
							-- Falling phase with gravity
							local fallTime = t - upTime
							local fallDuration = 1 - upTime
							local fallProgress = fallTime / fallDuration
							verticalOffset = bounceHeight - (gravity * fallProgress^2)
						end
						
						local currentPos = Vector3.new(
							currentHorizontal.X,
							math.max(startPos.Y + verticalOffset, endPos.Y), -- Don't go below ground
							currentHorizontal.Z
						)
						
						coin.model:PivotTo(CFrame.new(currentPos))
						
						-- Transition to spinning when landed
						if t >= 1 then
							coin.state = "spinning"
							coin.spinStartTime = totalElapsed
						end
						
					elseif coin.state == "spinning" then
						-- SPINNING PHASE: Each coin spins briefly after landing
						local spinDuration = 0.5 -- Spin for half a second (was 1.0)
						local spinElapsed = totalElapsed - coin.spinStartTime
						
						if spinElapsed < spinDuration then
							-- Still spinning
							coin.currentRotation = coin.currentRotation + coin.rotationSpeed * dt
							local rotationCF = CFrame.Angles(0, coin.currentRotation, 0)
							coin.model:PivotTo(CFrame.new(coin.landingPos) * rotationCF)
						else
						-- Done spinning - start flying immediately (independent lifecycle)
						coin.state = "flying"
						coin.flyStartTime = totalElapsed
						-- Keep spinning during flight (don't store final rotation)
						
						-- First coin is now flying (counter animation already started with drainage)
						end
						
					elseif coin.state == "flying" then
						-- FLYING PHASE: Each coin flies independently to player
						local flyTime = 0.8 -- Time to fly to player
						local flyElapsed = totalElapsed - coin.flyStartTime
						local flyAlpha = math.clamp(flyElapsed / flyTime, 0, 1)
						flyAlpha = flyAlpha^1.5 -- Ease in acceleration
						
						-- Update target to current player position (track moving player)
						local currentPlayerTarget = RootPart.Position + Vector3.new(0, 1, 0) -- Consistent spot above player
						
						-- Calculate Bezier curve control point only once
						if not coin.controlPoint then
							local startPos = coin.landingPos
							local midPoint = coin.landingPos:Lerp(currentPlayerTarget, 0.5)
							
							-- Determine which side the coin is on relative to player (ONCE)
							local playerPos = RootPart.Position
							local sideDirection = (coin.landingPos - playerPos).Unit
							local sideOffset = Vector3.new(sideDirection.X, 0, sideDirection.Z) * 3 -- Curve to the side
							coin.controlPoint = midPoint + sideOffset -- Store control point
						end
						
						-- Apply acceleration (slow start, fast finish)
						local acceleratedAlpha = flyAlpha^1.8 -- More acceleration as it gets closer
						
						-- Quadratic Bezier curve that follows player: B(t) = (1-t)²P₀ + 2(1-t)tP₁ + t²P₂
						local currentPos = (1 - acceleratedAlpha)^2 * coin.landingPos + 
							2 * (1 - acceleratedAlpha) * acceleratedAlpha * coin.controlPoint + 
							acceleratedAlpha^2 * currentPlayerTarget
						
						-- Continue spinning during flight (looks cool!)
						coin.currentRotation = coin.currentRotation + coin.rotationSpeed * dt * 0.7 -- Slower spin during flight
						local rotationCF = CFrame.Angles(0, coin.currentRotation, 0)
						coin.model:PivotTo(CFrame.new(currentPos) * rotationCF)
						
						-- Fade PARTS INSIDE the coin model in the last 20%
						local fade = math.clamp((flyAlpha - 0.8) / 0.2, 0, 1) -- Start fading at 80% progress
						for _, part in pairs(coin.parts) do
							if part ~= coin.model.PrimaryPart then
						part.Transparency = fade
							end
						end
						
						-- Play sound when very close (90% of the way) for perfect sync
						if flyAlpha >= 0.9 and not coin.soundPlayed then
							coin.soundPlayed = true
							task.spawn(function()
								local collectSound = Instance.new("Sound")
								collectSound.SoundId = "rbxassetid://94195852925775"
								collectSound.Volume = 0.5
								self.Client_Sounds:SetGroup(collectSound, "SFX")
								collectSound.Parent = workspace -- Temporary parent
								collectSound:Play()
								
								-- Clean up sound after playing
								collectSound.Ended:Connect(function()
									collectSound:Destroy()
								end)
							end)
						end
						
						-- Destroy when reached player
						if flyAlpha >= 1 then
							-- Show money popup for this coin on the sides
							local isLeftSide = math.random() > 0.5
							local screenPosition = UDim2.fromScale(
								isLeftSide and math.random(5, 25) / 100 or math.random(75, 95) / 100, -- Left or right side
								math.random(20, 80) / 100 -- Anywhere vertically
							)
							-- Use brighter gold color for individual coin popups
							self:CurrencyScreen(moneyPerCoin, Color3.fromRGB(255, 215, 0), screenPosition, 1.2)
							
							coin.model:Destroy()
							coin.model = nil
						end
					end
				end
			end
			
			-- Check if all coins collected (only during collection phase)
			if isCollecting then
				local allCollected = true
				for _, coin in ipairs(coins) do
					if coin.model and coin.model.Parent then
						allCollected = false
						break
					end
				end
				
				if allCollected then
					-- Animation complete - cleanup (IsAnimating already set to false when drain ended)
					-- Clean up drain position tracking
					local MovingPart = HoneyPot:FindFirstChild("MovingPart")
					if MovingPart then
						MovingPart:SetAttribute("StartDrainPosition", nil)
					end
					Connection:Disconnect()
				end
				end
			end)
	end
end

function Module:ShowEventCurrencyPopup(popupData)
	-- Handle both new structured data and legacy string format
	local currencyName, amount, imageId, gradientColor1, gradientColor2
	
	if type(popupData) == "table" then
		-- New structured format
		currencyName = popupData.currencyName
		amount = popupData.amount
		imageId = popupData.imageId
		gradientColor1 = popupData.gradientColor1
		gradientColor2 = popupData.gradientColor2
	else
		-- Legacy string format: "EVENT:CurrencyName|Amount|ImageId"
		local eventData = popupData:sub(7) -- Remove "EVENT:" prefix
		local parts = {}
		for part in string.gmatch(eventData, "([^|]+)") do
			table.insert(parts, part)
		end
		
		if #parts < 3 then
			warn("Client_Popups: Invalid EVENT popup format:", popupData)
			return
		end
		
		currencyName = parts[1]
		amount = tonumber(parts[2])
		imageId = parts[3]
	end
	
	if not amount then
		warn("Client_Popups: Invalid amount in EVENT popup:", amount)
		return
	end
	
	-- Use the same approach as CurrencyScreen - clone from Main.Popup
	local popup = Main.EventPopup:Clone()
	popup.Name = "EventCurrencyPopup"
	popup.Parent = Main
	popup.Visible = true
	
	-- Set the text (just show amount, no currency name)
	popup.Text = "+" .. amount
	
	-- Find and configure the ImageLabel inside EventPopup
	local imageLabel = popup:FindFirstChild("ImageLabel")
	if imageLabel and imageId then
		imageLabel.Image = imageId
		imageLabel.ImageTransparency = 0 -- Start fully visible
	end
	
	-- Apply gradient colors if provided
	if gradientColor1 and gradientColor2 then
		local gradient = popup:FindFirstChildOfClass("UIGradient")
		if not gradient then
			gradient = Instance.new("UIGradient")
			gradient.Parent = popup
		end
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, gradientColor1),
			ColorSequenceKeypoint.new(1, gradientColor2)
		})
	end
	
	-- Set position with wide random spread (same as coin pickups)
	local position = UDim2.fromScale(
		math.random(20, 80) / 100, -- Anywhere horizontally (20-80%)
		math.random(20, 80) / 100  -- Anywhere vertically (20-80%)
	)
	popup.Position = position
	
	task.spawn(function()
		-- Phase 1: Pop in with scale effect (same as CurrencyScreen)
		self.Client_Tween:SoftTween(popup, .1, {Rotation = math.random(-8,8)}, true)
		
		-- Phase 2: Start moving up immediately (same as CurrencyScreen)
		local finalY = position.Y.Scale - 0.12
		self.Client_Tween:SoftTween(popup, .6, {Position = UDim2.fromScale(position.X.Scale, finalY)})
		
		-- Phase 3: Delayed fade (same as CurrencyScreen)
		task.wait(.25)
		local fadeTime = .35
		self.Client_Tween:SoftTween(popup, fadeTime, {TextTransparency = 1}, true)
		self.Client_Tween:SoftTween(popup.UIStroke, fadeTime, {Transparency = 1}, true)
		
		-- Also fade the ImageLabel if it exists
		if imageLabel then
			self.Client_Tween:SoftTween(imageLabel, fadeTime, {ImageTransparency = 1}, true)
		end
		
		-- Wait for everything to complete, then destroy
		task.wait(.35)
		popup:Destroy()
	end)
end

Module:Init()

return Module