--// Client_UIHover: Handles UI hover system for QuickInfo frame
--// Shows hover information that follows mouse cursor

-- Services
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

-- Variables
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local Module = {}

-- Private Variables
local StarterGui = game:GetService("StarterGui")
local Main = PlayerGui:WaitForChild("Main") or StarterGui:WaitForChild("Main")
local QuickInfo = Main:WaitForChild("QuickInfo")
local QuickInfoTextLabel = QuickInfo:WaitForChild("TextLabel")

local CurrentlyHoveredElement = nil
local IsQuickInfoVisible = false
local HoverOffset = Vector2.new(15, -15) -- Offset from mouse cursor
local hoverConnections = {} -- Store connections for cleanup

local BaseFrameWidth = 0
local BaseFrameHeight = 0
local FramePaddingX = 10
local FramePaddingY = 10
local DEFAULT_FONT = Enum.Font.SourceSans

-- Mobile touch hold tracking
local TouchHoldMinDuration = 0.1 -- Minimum seconds to hold before showing QuickInfo on mobile
local ActiveTouchHolds = {} -- Track active touches: [element] = {touchId, startTime, holdTimer}
local TouchHoldConnections = {} -- Store InputBegan/InputEnded connections per element for cleanup: [element] = {began, ended}

-- Calculate text size based on frame height
local function calculateTextSize(frameHeight)
	-- Base scaling: 26px text for 35px frame height
	local baseTextSize = 26
	local baseFrameHeight = 35
	
	-- Calculate scale factor
	local scaleFactor = frameHeight / baseFrameHeight
	
	-- Apply scaling with reasonable limits
	local scaledTextSize = baseTextSize * scaleFactor
	scaledTextSize = math.clamp(scaledTextSize, 12, 36) -- Min 12px, Max 36px
	
	return math.floor(scaledTextSize)
end

-- Initialize QuickInfo frame
local function initializeQuickInfo()
	QuickInfo.Visible = false
	QuickInfoTextLabel.Text = ""
	
	-- Set text size once during initialization based on frame size
	local frameHeight = QuickInfo.AbsoluteSize.Y
	local textSize = calculateTextSize(frameHeight)
	QuickInfoTextLabel.TextSize = textSize
	QuickInfoTextLabel.TextWrapped = false

	BaseFrameWidth = QuickInfo.AbsoluteSize.X
	BaseFrameHeight = QuickInfo.AbsoluteSize.Y
	FramePaddingX = math.max(FramePaddingX, BaseFrameWidth - QuickInfoTextLabel.AbsoluteSize.X)
	FramePaddingY = math.max(FramePaddingY, BaseFrameHeight - QuickInfoTextLabel.AbsoluteSize.Y)
end

-- Mouse movement connection for tracking (event-driven, most efficient!)
local mouseConnection = nil

local function stripRichTextTags(text)
	return text:gsub("<.->", "")
end

local function measureTextBounds(text, textSize, screenSize)
	local plainText = stripRichTextTags(text)
	local fontEnum = QuickInfoTextLabel.Font
	if fontEnum == Enum.Font.Unknown then
		local fontFace = QuickInfoTextLabel.FontFace
		if fontFace then
			local params = Instance.new("GetTextBoundsParams")
			params.Text = plainText
			params.Size = textSize
			params.Width = screenSize.X
			params.Font = fontFace
			local success, bounds = pcall(function()
				return TextService:GetTextBoundsAsync(params)
			end)
			params:Destroy()
			if success and bounds then
				return bounds
			end
		end
		fontEnum = DEFAULT_FONT
	end

	return TextService:GetTextSize(plainText, textSize, fontEnum, Vector2.new(screenSize.X, screenSize.Y))
end

local function resizeQuickInfoToText(text, screenSize)
	local measured = measureTextBounds(text, QuickInfoTextLabel.TextSize, screenSize)
	local width = math.max(BaseFrameWidth, math.ceil(measured.X + FramePaddingX))
	local height = math.max(BaseFrameHeight, math.ceil(measured.Y + FramePaddingY))
	width = math.min(width, math.max(BaseFrameWidth, screenSize.X - 8))
	height = math.min(height, math.max(BaseFrameHeight, screenSize.Y - 8))
	QuickInfo.Size = UDim2.new(0, width, 0, height)
	return Vector2.new(width, height)
end

-- Show QuickInfo frame with text
local function computeTooltipPosition(mousePosition, frameSize, screenSize)
	local x = mousePosition.X + HoverOffset.X
	local y = mousePosition.Y + HoverOffset.Y

	if x + frameSize.X > screenSize.X then
		x = mousePosition.X - HoverOffset.X - frameSize.X
	end

	if y + frameSize.Y > screenSize.Y then
		y = mousePosition.Y - HoverOffset.Y - frameSize.Y
	end

	x = math.clamp(x, 0, screenSize.X - frameSize.X)
	y = math.clamp(y, 0, screenSize.Y - frameSize.Y)

	return x, y
end

local function showQuickInfo(text)
	if not text or text == "" then return end
	
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	QuickInfoTextLabel.Text = text
	QuickInfo.Visible = true
	IsQuickInfoVisible = true
	
	-- Position frame near mouse cursor (use actual current sizes to prevent edge cutoff)
	local mousePosition = UserInputService:GetMouseLocation()
	local screenSize = camera.ViewportSize
	local frameSize = resizeQuickInfoToText(text, screenSize)
	local x, y = computeTooltipPosition(mousePosition, frameSize, screenSize)
	QuickInfo.Position = UDim2.new(0, x, 0, y)
	
	-- Start event-driven mouse tracking (only when mouse moves!)
	if mouseConnection then
		mouseConnection:Disconnect()
		mouseConnection = nil
	end

	mouseConnection = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			-- Use GetMouseLocation() for consistent screen coordinates
			local mousePosition = UserInputService:GetMouseLocation()
			-- Get current sizes to handle dynamic frame resizing based on text
			local frameSize = QuickInfo.AbsoluteSize
			local screenSize = workspace.CurrentCamera.ViewportSize
			local x, y = computeTooltipPosition(mousePosition, frameSize, screenSize)
			QuickInfo.Position = UDim2.new(0, x, 0, y)
		end
	end)
end

-- Disconnect hover element listeners
local function disconnectHoverListeners()
	for _, connection in pairs(hoverConnections) do
		connection:Disconnect()
	end
	hoverConnections = {}
end

-- Hide QuickInfo frame
local function hideQuickInfo()
	if not IsQuickInfoVisible then return end
	QuickInfo.Visible = false
	IsQuickInfoVisible = false
	
	-- Disconnect element listeners
	disconnectHoverListeners()
	
	-- Stop mouse tracking when hidden
	if mouseConnection then
		mouseConnection:Disconnect()
		mouseConnection = nil
	end
end

-- Handle hover enter for a UI element
local function handleHoverEnter(element)
	CurrentlyHoveredElement = element
	
	-- Get hover text from attribute
	local hoverText = element:GetAttribute("HoverText")
	
	if hoverText and hoverText ~= "" then
		showQuickInfo(hoverText)
		
		-- Connect lifecycle events for failsafe
		disconnectHoverListeners() -- Clear any existing connections
		
		-- Listen for element destruction/reparenting
		table.insert(hoverConnections, element.AncestryChanged:Connect(function()
			hideQuickInfo()
		end))
		
		-- Listen for element becoming invisible
		table.insert(hoverConnections, element:GetPropertyChangedSignal("Visible"):Connect(function()
			if not element.Visible then
				hideQuickInfo()
			end
		end))
		
		-- Listen for scroll events on parent containers
		local parent = element.Parent
		while parent and parent ~= PlayerGui do
			if parent:IsA("ScrollingFrame") then
				table.insert(hoverConnections, parent:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
					hideQuickInfo()
				end))
			end
			parent = parent.Parent
		end
	end
end

-- Handle hover exit for a UI element
local function handleHoverExit(element)
	if CurrentlyHoveredElement == element then
		CurrentlyHoveredElement = nil
		hideQuickInfo()
	end
end

-- Setup hover detection for a tagged element
local function setupHoverElement(element)
	if not element:IsA("GuiObject") then
		return
	end
	
	-- On mobile (touch-only), use touch hold (TouchStart/TouchEnd with minimum duration)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		-- Single reusable InputEnded connection per element (checks touchId)
		local inputEndedConnection = element.InputEnded:Connect(function(endInput)
			if endInput.UserInputType == Enum.UserInputType.Touch then
				local hold = ActiveTouchHolds[element]
				if hold and hold.touchId == endInput then
					-- Cancel hold timer if touch ends before minimum duration
					if hold.holdTimer then
						task.cancel(hold.holdTimer)
					end
					ActiveTouchHolds[element] = nil
					
					-- Hide QuickInfo if it was showing for this element
					if CurrentlyHoveredElement == element then
						handleHoverExit(element)
					end
				end
			end
		end)
		
		-- Single InputBegan connection per element (stored for cleanup)
		local inputBeganConnection = element.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				local touchId = input
				
				-- Cancel any existing hold for this element
				local existingHold = ActiveTouchHolds[element]
				if existingHold then
					if existingHold.holdTimer then
						task.cancel(existingHold.holdTimer)
					end
				end
				
				-- Start hold timer - only show QuickInfo if touch lasts more than 0.1s
				local holdTimer = task.delay(TouchHoldMinDuration, function()
					-- Check if touch is still active
					if ActiveTouchHolds[element] and ActiveTouchHolds[element].touchId == touchId then
						handleHoverEnter(element)
					end
				end)
				
				ActiveTouchHolds[element] = {
					touchId = touchId,
					holdTimer = holdTimer
				}
			end
		end)
		
		-- Store both connections for cleanup (one per element, not per touch!)
		TouchHoldConnections[element] = {
			began = inputBeganConnection,
			ended = inputEndedConnection
		}
	else
		-- For desktop, use MouseEnter/MouseLeave
		element.MouseEnter:Connect(function()
			handleHoverEnter(element)
		end)
		
		element.MouseLeave:Connect(function()
			handleHoverExit(element)
		end)
	end
end


-- Initialize the UIHoverManager
function Module:Init()
	task.wait(2)
	-- Initialize QuickInfo frame
	initializeQuickInfo()
	
	-- Setup existing tagged elements
	for _, element in pairs(CollectionService:GetTagged("HoverInfo")) do
		setupHoverElement(element)
	end
	
	-- Listen for new tagged elements
	CollectionService:GetInstanceAddedSignal("HoverInfo"):Connect(setupHoverElement)
	
	-- Listen for removed tagged elements
	CollectionService:GetInstanceRemovedSignal("HoverInfo"):Connect(function(element)
		if CurrentlyHoveredElement == element then
			CurrentlyHoveredElement = nil
			hideQuickInfo()
		end
		
		-- Clean up mobile touch hold tracking
		if ActiveTouchHolds[element] then
			local hold = ActiveTouchHolds[element]
			if hold.holdTimer then
				task.cancel(hold.holdTimer)
			end
			ActiveTouchHolds[element] = nil
		end
		
		-- Clean up both InputBegan and InputEnded connections (one per element)
		local connections = TouchHoldConnections[element]
		if connections then
			if connections.began then
				connections.began:Disconnect()
			end
			if connections.ended then
				connections.ended:Disconnect()
			end
			TouchHoldConnections[element] = nil
		end
	end)
	
	-- Hide tooltip when window loses focus (tab out, etc.)
	UserInputService.WindowFocusReleased:Connect(function()
		if CurrentlyHoveredElement then
			CurrentlyHoveredElement = nil
			hideQuickInfo()
		end
	end)
	
	print("✅ Client_UIHover initialized successfully")
end

-- Alias for backward compatibility
function Module:Initialize()
	return self:Init()
end

-- Manually add hover info to an element (for programmatic use)
function Module:AddHoverInfo(element, text)
	if element and element:IsA("GuiObject") then
		element:SetAttribute("HoverText", text)
		CollectionService:AddTag(element, "HoverInfo")
	end
end

-- Remove hover info from an element
function Module:RemoveHoverInfo(element)
	if element then
		CollectionService:RemoveTag(element, "HoverInfo")
	end
end

return Module
