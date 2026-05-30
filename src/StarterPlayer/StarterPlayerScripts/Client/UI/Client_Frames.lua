--// Client_Frames - Animated open/close for Frames (pop-in / pop-out) and close handler (Escape, CloseAll)
--// Works with MainGui.Frames or Main.Frames. Optional: Lighting.MainBlur (BlurEffect) for backdrop blur.
--//
--// Close buttons: Tag a GuiButton (TextButton/ImageButton) with "CloseFrame" (CollectionService).
--//   - Attribute "Frame" (string) = frame name to close (e.g. "Store", "FoodShop"). If missing, closes current open frame.
--//   - Attribute "Frame" = "All" closes all frames.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local Lighting = game:GetService("Lighting")

-- MainGui or Main, then Frames
local MainGuiRoot = nil
local Frames = nil
local MainBlur = nil

-- Will be set in Init (from Library)
local Client_Sounds = nil

local openDebounce = false
local currentOpenFrame = nil  -- UIType of the frame we consider "open" (for Escape to close)

-- Animation: frame slides from off-screen (Y = -0.5 or 1.5) to center (0.5, 0.5)
local POS_OFF_TOP = UDim2.new(0.5, 0, -0.5, 0)
local POS_CENTER = UDim2.new(0.5, 0, 0.5, 0)
local POS_OFF_BOTTOM = UDim2.new(0.5, 0, 1.5, 0)

local TWEEN_OPEN = TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_CLOSE = TweenInfo.new(0.15, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
local BLUR_SIZE_OPEN = 15
local BLUR_SIZE_CLOSED = 0

local FramesModule = {}

-- ========================================
-- HELPERS
-- ========================================

local function getFrames()
	if Frames then return Frames end
	MainGuiRoot = PlayerGui:FindFirstChild("MainGui") or PlayerGui:FindFirstChild("Main")
	if not MainGuiRoot then return nil end
	Frames = MainGuiRoot:FindFirstChild("Frames")
	return Frames
end

local function getBlur()
	if MainBlur ~= nil then return MainBlur end
	MainBlur = Lighting:FindFirstChild("MainBlur")
	if MainBlur and not MainBlur:IsA("BlurEffect") then
		MainBlur = nil
	end
	return MainBlur
end

local function resolveFrameAlias(uiType)
	if uiType == "SpeedUpgrades" or uiType == "SpeedStore" or uiType == "Speed" then
		return "Baloons"
	end
	return uiType
end

local function tweenBlur(size, useOpenEasing)
	local blur = getBlur()
	if not blur then return end
	local tweenInfo = if useOpenEasing then TWEEN_OPEN else TWEEN_CLOSE
	local tween = TweenService:Create(blur, tweenInfo, { Size = size })
	tween:Play()
	return tween
end

--- Returns the Frame instance for a given UIType, or nil.
local function getFrame(uiType)
	uiType = resolveFrameAlias(uiType)
	local f = getFrames()
	if not f then return nil end
	local frame = f:FindFirstChild(uiType)
	if frame and (frame:IsA("Frame") or frame:IsA("GuiObject")) then
		return frame
	end
	return nil
end

-- ========================================
-- ANIMATION
-- ========================================

--- Close a single frame with pop-out animation (no debounce; call from CloseFrame/CloseAllFrames).
local function animateCloseFrame(frame, uiType)
	if not frame or not frame.Visible then return end
	
	-- Play frame exit sound
	if Client_Sounds then
		Client_Sounds:Play("Frame Exit")
	end
	
	local tweenPos = TweenService:Create(frame, TWEEN_CLOSE, { Position = POS_OFF_BOTTOM })
	tweenBlur(BLUR_SIZE_CLOSED)
	
	-- Deactivate frame zoom (returns to running FOV)
	if FramesModule.Client_FOV and type(FramesModule.Client_FOV.SetFrameZoomActive) == "function" then
		FramesModule.Client_FOV:SetFrameZoomActive(false)
	end
	
	tweenPos:Play()
	tweenPos.Completed:Wait()
	frame.Visible = false
	frame.Position = POS_OFF_TOP
	if currentOpenFrame == uiType then
		currentOpenFrame = nil
	end
end

--- Close all visible frames with animation.
function FramesModule:CloseAllFrames()
	local f = getFrames()
	if not f then return end
	openDebounce = false
	for _, child in f:GetChildren() do
		if (child:IsA("Frame") or child:IsA("GuiObject")) and child.Visible then
			animateCloseFrame(child, child.Name)
		end
	end
	currentOpenFrame = nil
end

--- Close one frame by UIType (with animation). Safe to call if already closed.
function FramesModule:CloseFrame(uiType)
	uiType = resolveFrameAlias(uiType)
	local frame = getFrame(uiType)
	if frame then
		animateCloseFrame(frame, uiType)
		return true
	end
	return false
end

--- Open one frame by UIType (close others first, then pop-in). Toggle: if already open, closes it.
function FramesModule:OpenFrame(uiType)
	uiType = resolveFrameAlias(uiType)
	local frame = getFrame(uiType)
	if not frame then return false end

	if openDebounce then return true end
	openDebounce = true

	if frame.Visible then
		-- Already open -> close it (toggle)
		animateCloseFrame(frame, uiType)
		openDebounce = false
		return true
	end

	-- Close any other open frames first
	self:CloseAllFrames()
	openDebounce = true

	frame.Position = POS_OFF_TOP
	frame.Visible = true
	currentOpenFrame = uiType

	-- Play frame open sound
	if Client_Sounds then
		Client_Sounds:Play("Frame Open")
	end

	tweenBlur(BLUR_SIZE_OPEN, true)
	
	-- Activate frame zoom (zooms in camera)
	if self.Client_FOV and type(self.Client_FOV.SetFrameZoomActive) == "function" then
		self.Client_FOV:SetFrameZoomActive(true)
	end
	
	local tweenPos = TweenService:Create(frame, TWEEN_OPEN, { Position = POS_CENTER })
	tweenPos:Play()
	tweenPos.Completed:Connect(function()
		openDebounce = false
		
		-- Notify module that frame opened (for auto-select, etc.)
		if self[uiType] and type(self[uiType].OnOpened) == "function" then
			self[uiType]:OnOpened()
		end
	end)

	return true
end

--- Check if a frame is currently open (by UIType).
function FramesModule:IsFrameOpen(uiType)
	uiType = resolveFrameAlias(uiType)
	local frame = getFrame(uiType)
	return frame and frame.Visible
end

--- Get the UIType of the frame currently considered open (for Escape). May be nil.
function FramesModule:GetOpenFrameName()
	return currentOpenFrame
end

-- ========================================
-- CLOSE BUTTONS (tag-based)
-- ========================================

local CLOSE_FRAME_TAG = "CloseFrame"
local FRAME_ATTR = "Frame"

local function onCloseButtonActivated(button)
	local frameName = button:GetAttribute(FRAME_ATTR)
	if frameName == "All" then
		FramesModule:CloseAllFrames()
		return
	end
	if type(frameName) == "string" and #frameName > 0 then
		FramesModule:CloseFrame(frameName)
		return
	end
	-- No attribute or empty: close whatever frame is currently open
	local openName = FramesModule:GetOpenFrameName()
	if openName then
		FramesModule:CloseFrame(openName)
	end
end

local function setupCloseFrameButton(button)
	if not button:IsA("GuiButton") then return end
	button.Activated:Connect(function()
		onCloseButtonActivated(button)
	end)
end

-- ========================================
-- INIT
-- ========================================

function FramesModule:InitializeFramePositions()
	local f = getFrames()
	if not f then return end
	for _, child in f:GetChildren() do
		if child:IsA("Frame") or child:IsA("GuiObject") then
			child.Position = POS_OFF_TOP
			child.Visible = false
		end
	end
end

function FramesModule:Init()
	-- Get Client_Sounds from Library (set by init.client.lua)
	Client_Sounds = self.Client_Sounds
	
	self:InitializeFramePositions()

	-- Close buttons: tag "CloseFrame", attribute "Frame" = frame name (or "All")
	for _, button in CollectionService:GetTagged(CLOSE_FRAME_TAG) do
		task.spawn(function()
			setupCloseFrameButton(button)
		end)
	end
	CollectionService:GetInstanceAddedSignal(CLOSE_FRAME_TAG):Connect(setupCloseFrameButton)

	-- Escape key closes the current frame
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			local openName = self:GetOpenFrameName()
			if openName then
				self:CloseFrame(openName)
			end
		end
	end)
end

return FramesModule
