--// Client_Settings - Settings UI and local application
--// Handles slider/toggle interactions, updates replica data, applies settings locally

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Events = ReplicatedStorage:WaitForChild("Events")
local SettingsHandler = Events:WaitForChild("SettingsHandler")

local Module = {}

-- References to other client modules (set in Init)
Module.Client_Data = nil
Module.Client_Sounds = nil
Module.Client_ButtonAnimation = nil

-- UI references
local SettingsFrame = nil
local ListHolder = nil

-- Setting frames cache
local SettingFrames = {
	Music = nil,
	Sounds = nil,
	PlayerSpeedSetting = nil,
	OverheadIncomeText = nil,
	SlowMode = nil, -- Outside settings frame, in Main.LeftFrame
}

-- Current replica settings (cached for performance)
local CurrentSettings = {
	Music = 1,
	Sounds = 1,
	PlayerSpeedSetting = 1,
	OverheadIncomeText = true,
	SlowMode = false,
}

-- Active drags (for sliders)
local ActiveDrags = {}

--[[
	Clamp value between 0 and 1
]]
local function clamp(value, min, max)
	return math.max(min, math.min(max, value))
end

--[[
	Update setting locally and notify server
	@param settingName string
	@param settingValue any
]]
local function updateSetting(settingName: string, settingValue: any)
	-- Update local cache
	CurrentSettings[settingName] = settingValue
	
	-- Apply setting locally
	Module:ApplySetting(settingName, settingValue)
	
	-- Notify server
	SettingsHandler:FireServer(settingName, settingValue)
end

--[[
	Update ScrollBar percent label(s). Title may be a TextLabel or a container with a nested Title label.
]]
local function setScrollBarPercentText(titleContainer: Instance?, percentText: string)
	if not titleContainer then
		return
	end

	if titleContainer:IsA("TextLabel") or titleContainer:IsA("TextButton") then
		titleContainer.Text = percentText
	end

	local nestedTitle = titleContainer:FindFirstChild("Title")
	if nestedTitle and (nestedTitle:IsA("TextLabel") or nestedTitle:IsA("TextButton")) then
		nestedTitle.Text = percentText
	end
end

--[[
	Setup slider UI (Music, Sounds, PlayerSpeedSetting)
	@param settingFrame Frame
	@param settingName string
]]
local function setupSlider(settingFrame: Frame, settingName: string)
	local scrollBar = settingFrame:FindFirstChild("ScrollBar")
	if not scrollBar then 
		warn(string.format("⚠️ ScrollBar not found for %s", settingName))
		return 
	end
	
	local scroll = scrollBar:FindFirstChild("Scroll")
	if not scroll then 
		warn(string.format("⚠️ Scroll not found for %s", settingName))
		return 
	end
	
	local scrollButton = scroll:FindFirstChild("ImageButton")
	if not scrollButton then 
		warn(string.format("⚠️ Scroll.ImageButton not found for %s", settingName))
		return 
	end
	
	local bar = scrollBar:FindFirstChild("Bar")
	if not bar then 
		warn(string.format("⚠️ Bar not found for %s", settingName))
		return 
	end
	
	-- Filler is a direct child of ScrollBar, NOT Bar!
	local filler = scrollBar:FindFirstChild("Filler")
	if not filler then 
		warn(string.format("⚠️ Filler not found for %s", settingName))
		return 
	end
	
	local title = scrollBar:FindFirstChild("Title")
	if not title then 
		warn(string.format("⚠️ Title not found for %s", settingName))
	end
	
	-- Initialize from current setting
	local initialValue = CurrentSettings[settingName] or 1
	scroll.Position = UDim2.fromScale(initialValue, 0.5)
	filler.Size = UDim2.fromScale(initialValue, 0.5)
	
	-- Update title text
	setScrollBarPercentText(title, math.round(initialValue * 100) .. "%")
	
	-- Drag functionality
	local function updateSlider(input)
		local relativeX = (input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
		local percent = clamp(relativeX, 0, 1)
		
		-- Update UI
		scroll.Position = UDim2.fromScale(percent, 0.5)
		filler.Size = UDim2.fromScale(percent, 0.5)
		
		-- Update title text
		setScrollBarPercentText(title, math.round(percent * 100) .. "%")
		
		-- Update setting
		updateSetting(settingName, percent)
	end
	
	-- Input began on scroll button
	scrollButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			ActiveDrags[settingName] = true
			
			local connection
			connection = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					ActiveDrags[settingName] = nil
					connection:Disconnect()
				end
			end)
		end
	end)
	
	-- Mouse/touch movement
	UserInputService.InputChanged:Connect(function(input)
		if ActiveDrags[settingName] and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateSlider(input)
		end
	end)
	
	-- Click on bar to jump
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			updateSlider(input)
			ActiveDrags[settingName] = true
		end
	end)
	
	bar.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			ActiveDrags[settingName] = nil
		end
	end)
end

--[[
	Setup toggle UI (OverheadIncomeText)
	@param settingFrame Frame
	@param settingName string
]]
local function setupToggle(settingFrame: Frame, settingName: string)
	local button = settingFrame:FindFirstChild("Button")
	if not button then 
		warn(string.format("⚠️ Button not found for %s", settingName))
		return 
	end
	
	local imageButton = button:FindFirstChild("ImageButton")
	if not imageButton then 
		warn(string.format("⚠️ ImageButton not found for %s", settingName))
		return 
	end
	
	local titleLabel = imageButton:FindFirstChild("Title")
	if not titleLabel then
		warn(string.format("⚠️ Title label not found for %s", settingName))
	end
	
	local uiGradient = imageButton:FindFirstChild("UIGradient")
	local uiStroke2 = imageButton:FindFirstChild("UIStroke2")
	local strokeGradient = uiStroke2 and uiStroke2:FindFirstChild("UIGradient")
	
	-- Function to update visual
	local function updateVisual(value: boolean)
		local colorSeq
		local text
		
		if value then
			colorSeq = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(125, 255, 0)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 100, 0))
			}
			text = "Enabled"
		else
			colorSeq = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 100, 0)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0))
			}
			text = "Disabled"
		end
		
		if titleLabel then
			titleLabel.Text = text
		end
		
		if uiGradient then
			uiGradient.Color = colorSeq
		end
		
		if strokeGradient then
			strokeGradient.Color = colorSeq
		end
	end
	
	-- Initialize from current setting
	local initialValue = CurrentSettings[settingName] or true
	updateVisual(initialValue)
	
	-- Click to toggle (use the ImageButton, not the Frame)
	imageButton.MouseButton1Click:Connect(function()
		local newValue = not CurrentSettings[settingName]
		
		-- Update visual immediately
		updateVisual(newValue)
		
		-- Update setting
		updateSetting(settingName, newValue)
	end)
end

--[[
	Setup SlowMode button (outside Settings frame, in Main.LeftFrame.SlowMode)
	@param leftFrame Frame - Main.LeftFrame
]]
local function setupSlowModeButton(leftFrame: Frame)
	local slowModeFrame = leftFrame:FindFirstChild("SlowMode")
	if not slowModeFrame then
		warn("⚠️ SlowMode frame not found in LeftFrame")
		return
	end
	
	local button = slowModeFrame:FindFirstChild("Button")
	if not button then
		warn("⚠️ SlowMode.Button not found")
		return
	end
	
	-- Button is the clickable element itself (TextButton or ImageButton)
	local clickableButton = button:IsA("GuiButton") and button or button:FindFirstChildOfClass("ImageButton") or button:FindFirstChildOfClass("TextButton")
	if not clickableButton then
		warn("⚠️ SlowMode.Button is not a clickable button")
		return
	end
	
	-- Title is a direct child of Button
	local titleLabel = button:FindFirstChild("Title") or button:FindFirstChild("Text")
	if not titleLabel then
		warn("⚠️ SlowMode Title label not found")
	end
	
	local uiGradient = button:FindFirstChild("UIGradient")
	local uiStroke2 = button:FindFirstChild("UIStroke2")
	local strokeGradient = uiStroke2 and uiStroke2:FindFirstChild("UIGradient")
	
	-- Tsunami pattern: get color sequence and text from boolean value
	local function getDataFromValue(value: boolean)
		local colorSeq, text
		
		if value then
			colorSeq = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(174, 255, 0)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(48, 177, 1))
			}
			text = "Slow Mode\nOn"
		else
			colorSeq = ColorSequence.new{
				ColorSequenceKeypoint.new(0, Color3.fromRGB(212, 212, 212)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(81, 81, 81))
			}
			text = "Slow Mode\nOff"
		end
		
		return colorSeq, text
	end
	
	-- Function to update visual (Tsunami pattern)
	local function updateVisual(value: boolean)
		local colorSeq, text = getDataFromValue(value)
		
		if uiGradient then
			uiGradient.Color = colorSeq
		end
		
		if strokeGradient then
			strokeGradient.Color = colorSeq
		end
		
		if titleLabel then
			titleLabel.Text = text
		end
	end
	
	-- Initialize from replica (not CurrentSettings, which may not be loaded yet)
	local replica = Module.Client_Data:GetReplica()
	local initialValue = false
	if replica and replica.Data.Settings then
		initialValue = replica.Data.Settings.SlowMode or false
	end
	updateVisual(initialValue)
	
	-- Function to toggle SlowMode
	local function toggleSlowMode()
		local newValue = not CurrentSettings.SlowMode
		
		-- Update visual immediately
		updateVisual(newValue)
		
		-- Update setting
		updateSetting("SlowMode", newValue)
		
		-- Play sound (handled by button animation if triggered via button)
		-- For hotkey, we'll trigger the button animation which plays sound
	end
	
	-- Click to toggle
	clickableButton.MouseButton1Click:Connect(toggleSlowMode)
	
	-- Hotkey T to toggle
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.T then
			-- Trigger button animation (squish + sound)
			if Module.Client_ButtonAnimation and Module.Client_ButtonAnimation.TriggerClickAnimation then
				Module.Client_ButtonAnimation:TriggerClickAnimation(clickableButton)
			end
			
			toggleSlowMode()
		end
	end)
	
	-- Listen for replica changes to update visual
	if replica then
		replica:ListenToChange({"Settings", "SlowMode"}, function(newValue)
			updateVisual(newValue or false)
		end)
	end
end

--[[
	Apply setting locally (volume, speed, billboard visibility)
	@param settingName string
	@param settingValue any
]]
function Module:ApplySetting(settingName: string, settingValue: any)
	if settingName == "Music" then
		-- Apply music volume (WaitForChild so groups can load after settings UI)
		if Module.Client_Sounds then
			local musicGroup = Module.Client_Sounds:WaitForMusicSoundGroup()
			if musicGroup then
				musicGroup.Volume = settingValue
			end
		end
	elseif settingName == "Sounds" then
		-- Apply SFX volume (WaitForChild so groups can load after settings UI)
		if Module.Client_Sounds then
			local sfxGroup = Module.Client_Sounds:WaitForSFXSoundGroup()
			if sfxGroup then
				sfxGroup.Volume = settingValue
			end
		end
	elseif settingName == "PlayerSpeedSetting" then
		-- Speed is handled server-side via Server_CharacterStats
	elseif settingName == "OverheadIncomeText" then
		-- Billboard visibility is handled server-side via Server_CharacterStats
	elseif settingName == "SlowMode" then
		-- SlowMode is handled server-side (speed cap at minimum via Server_CharacterStats)
	end
end

--[[
	Listen to replica changes and apply settings
]]
local function listenToReplicaChanges()
	local replica = Module.Client_Data:GetReplica()
	if not replica then
		warn("⚠️ Client_Settings: No replica found")
		return
	end
	
	-- Listen for each setting change
	for settingName, _ in pairs(CurrentSettings) do
		replica:ListenToChange({"Settings", settingName}, function(newValue)
			CurrentSettings[settingName] = newValue
			Module:ApplySetting(settingName, newValue)
		end)
	end
end

--[[
	Initialize settings application and replica listeners
]]
function Module:Init()
	-- Require dependencies directly
	Module.Client_Data = require(script.Parent.Parent.Core.Client_Data)
	Module.Client_Sounds = require(script.Parent.Parent.Effects.Client_Sounds)
	
	if not Module.Client_Data then
		warn("⚠️ Client_Settings: Client_Data not found")
		return
	end
	
	-- Wait for data to be ready
	Module.Client_Data.WaitUntilReady()
	
	-- Load initial settings from replica and apply them immediately
	local data = Module.Client_Data:GetData()
	if data and data.Settings then
		for settingName, settingValue in pairs(data.Settings) do
			CurrentSettings[settingName] = settingValue
			-- Apply initial settings immediately
			self:ApplySetting(settingName, settingValue)
		end
	end
	
	-- Listen to replica changes (settings apply in real-time)
	listenToReplicaChanges()
	
	-- Setup UI asynchronously (don't block initialization)
	task.spawn(function()
		local Main = PlayerGui:WaitForChild("Main", 10)
		if not Main then
			warn("⚠️ Client_Settings: Main UI not found")
			return
		end
		
		local Frames = Main:WaitForChild("Frames", 30)
		if not Frames then
			warn("⚠️ Client_Settings: Frames not found")
			return
		end
		
		SettingsFrame = Frames:WaitForChild("Settings", 30)
		if not SettingsFrame then
			warn("⚠️ Client_Settings: Settings frame not found")
			return
		end
		
		ListHolder = SettingsFrame:WaitForChild("ListHolder", 30)
		if not ListHolder then
			warn("⚠️ Client_Settings: ListHolder not found")
			return
		end
		
		-- Cache setting frames
		SettingFrames.Music = ListHolder:FindFirstChild("Music")
		SettingFrames.Sounds = ListHolder:FindFirstChild("Sounds")
		SettingFrames.PlayerSpeedSetting = ListHolder:FindFirstChild("PlayerSpeedSetting")
		SettingFrames.OverheadIncomeText = ListHolder:FindFirstChild("OverheadIncomeText")
		
		-- Setup sliders
		if SettingFrames.Music then
			setupSlider(SettingFrames.Music, "Music")
		end
		if SettingFrames.Sounds then
			setupSlider(SettingFrames.Sounds, "Sounds")
		end
		if SettingFrames.PlayerSpeedSetting then
			setupSlider(SettingFrames.PlayerSpeedSetting, "PlayerSpeedSetting")
		end
		
		-- Setup toggle
		if SettingFrames.OverheadIncomeText then
			setupToggle(SettingFrames.OverheadIncomeText, "OverheadIncomeText")
		end
		
		-- Setup SlowMode button (outside Settings frame, in Main.LeftFrame)
		local leftFrame = Main:FindFirstChild("LeftFrame")
		if leftFrame then
			setupSlowModeButton(leftFrame)
		else
			warn("⚠️ LeftFrame not found for SlowMode")
		end
	end)
end

return Module
