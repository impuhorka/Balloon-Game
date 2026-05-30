--// Client_ButtonAnimation - Tag-based hover & click (satisfying bouncy feel)
--// Tag any GuiButton (TextButton/ImageButton) with "AnimatedButton" (CollectionService).
--// Hover: poppy scale-up (Back). Click: quick squish, then bouncy release (Elastic).
--// If button has "UIType" attribute, clicking it opens that UI frame.
--// If button has "UIScale" attribute (number), hover scale uses that instead of default.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = game.Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local TAG = "AnimatedButton"

local AnimatedButtons = {}
local ButtonStates = {}  -- [button] = { uiScale, isPressed }

-- Will be set in Init (from Library)
local FramesModule = nil
local Client_Sounds = nil
local StoreModule = nil

-- Scales
local SCALE_IDLE = 1
local SCALE_HOVER = 1.06   -- noticeable pop on hover
local SCALE_PRESS = 0.94   -- squish on click

-- Icon tilt
local ICON_ROTATION_IDLE = 0
local ICON_ROTATION_HOVER = 15  -- degrees

-- Hover: smooth and subtle (Sine instead of Back - no overshoot)
local HOVER_ENTER = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local HOVER_LEAVE = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
-- Click: fast squish, smooth release (Sine instead of Elastic - no bounce)
local PRESS_DOWN = TweenInfo.new(0.06, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local RELEASE_BOUNCE = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local ButtonAnimation = {}

-- ========================================
-- TWEEN HELPERS
-- ========================================

local function tweenScale(uiScale, targetScale, tweenInfo)
	if not uiScale or not uiScale.Parent then return end
	local tween = TweenService:Create(uiScale, tweenInfo, { Scale = targetScale })
	tween:Play()
	return tween
end

local function tweenIconRotation(icon, targetRotation, tweenInfo)
	if not icon or not icon.Parent then return end
	local tween = TweenService:Create(icon, tweenInfo, { Rotation = targetRotation })
	tween:Play()
	return tween
end

-- ========================================
-- SETUP ONE BUTTON
-- ========================================

local function setupButton(button)
	if not button:IsA("GuiButton") then return end
	if AnimatedButtons[button] then return end
	
	-- Check if button has AnimationLocked attribute (priority animation running)
	if button:GetAttribute("AnimationLocked") == true then
		-- Don't setup hover/click animations while locked
		-- Listen for unlock and setup later
		local connection
		connection = button:GetAttributeChangedSignal("AnimationLocked"):Connect(function()
			if button:GetAttribute("AnimationLocked") ~= true then
				-- Unlocked, now we can setup
				connection:Disconnect()
				setupButton(button)
			end
		end)
		return
	end

	AnimatedButtons[button] = true

	local uiScale = button:FindFirstChild("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Scale = SCALE_IDLE
		uiScale.Parent = button
	end

	-- Check for IconTilt attribute
	local shouldTiltIcon = button:GetAttribute("IconTilt") == true
	local iconImage = nil
	if shouldTiltIcon then
		iconImage = button:FindFirstChild("Icon", true) -- Recursive search for Icon ImageLabel
		if iconImage and iconImage:IsA("ImageLabel") then
			iconImage.Rotation = ICON_ROTATION_IDLE -- Ensure it starts at 0
		else
			iconImage = nil -- Not found or not an ImageLabel
		end
	end

	-- Check for UIScale attribute (custom hover scale, e.g. 1.1 or 1.15)
	local hoverScale = tonumber(button:GetAttribute("UIScale")) or SCALE_HOVER
	-- Press scale proportional to hover (same squish ratio)
	local pressScale = hoverScale * (SCALE_PRESS / SCALE_HOVER)

	ButtonStates[button] = { uiScale = uiScale, isPressed = false, isHovering = false, icon = iconImage, hoverScale = hoverScale, pressScale = pressScale }

	-- Press down
	button.MouseButton1Down:Connect(function()
		if not uiScale.Parent then return end
		-- Don't animate if locked
		if button:GetAttribute("AnimationLocked") == true then return end
		ButtonStates[button].isPressed = true
		local scale = ButtonStates[button].pressScale or SCALE_PRESS
		tweenScale(uiScale, scale, PRESS_DOWN)
		
		-- Play button press sound
		if Client_Sounds then
			Client_Sounds:Play("Button Press")
		end
	end)

	-- Hover enter
	button.MouseEnter:Connect(function()
		if not uiScale.Parent then return end
		-- Don't animate if locked
		if button:GetAttribute("AnimationLocked") == true then return end
		ButtonStates[button].isHovering = true
		if ButtonStates[button].isPressed then return end
		local scale = ButtonStates[button].hoverScale or SCALE_HOVER
		tweenScale(uiScale, scale, HOVER_ENTER)
		
		-- Play mouse enter sound
		if Client_Sounds then
			Client_Sounds:Play("Mouse Enter")
		end
		
		-- Tilt icon on hover if enabled
		if iconImage and iconImage.Parent then
			tweenIconRotation(iconImage, ICON_ROTATION_HOVER, HOVER_ENTER)
		end
	end)

	-- Hover leave
	button.MouseLeave:Connect(function()
		if not uiScale.Parent then return end
		-- Don't animate if locked
		if button:GetAttribute("AnimationLocked") == true then return end
		ButtonStates[button].isHovering = false
		ButtonStates[button].isPressed = false
		tweenScale(uiScale, SCALE_IDLE, HOVER_LEAVE)
		
		-- Reset icon rotation on hover leave
		if iconImage and iconImage.Parent then
			tweenIconRotation(iconImage, ICON_ROTATION_IDLE, HOVER_LEAVE)
		end
	end)

	-- Release on button (Activated) — bouncy pop back + toggle UI if UIType set
	button.Activated:Connect(function()
		if not uiScale.Parent then return end
		-- Don't animate if locked
		if button:GetAttribute("AnimationLocked") == true then return end
		ButtonStates[button].isPressed = false
		
		-- Play button release sound
		if Client_Sounds then
			Client_Sounds:Play("Button Release")
		end
		
		-- If still hovering, go back to hover scale; otherwise idle
		local targetScale = ButtonStates[button].isHovering and (ButtonStates[button].hoverScale or SCALE_HOVER) or SCALE_IDLE
		tweenScale(uiScale, targetScale, RELEASE_BOUNCE)
		
		-- Toggle UI if UIType attribute is set (balloon store Buy buttons set BalloonBuy and clear UIType)
		local uiType = button:GetAttribute("UIType")
		if uiType and button:GetAttribute("BalloonBuy") ~= true then
			-- Special handler: InviteFriend prompts the social invite UI
			if uiType == "InviteFriend" then
				local SocialService = game:GetService("SocialService")
				local ok, err = pcall(function()
					SocialService:PromptGameInvite(Player)
				end)
				if not ok then
					warn("⚠️ Failed to prompt invite:", err)
				end
			elseif uiType == "ForceGreenLight" then
				-- Prompt ForceGreenLight dev product purchase
				local Shared_Marketplace = require(ReplicatedStorage.Modules.Settings.Shared_Marketplace)
				local productId = Shared_Marketplace.Products["ForceGreenLight"]
				if type(productId) == "number" and productId > 0 then
					local Events = ReplicatedStorage:FindFirstChild("Events")
					local PurchaseHandler = Events and Events:FindFirstChild("PurchaseHandler")
					if PurchaseHandler then
						PurchaseHandler:FireServer(productId, nil)
					end
				else
					warn("⚠️ ForceGreenLight product not configured")
				end
		elseif uiType == "VIP" then
			-- Open Store and scroll to VIP; if Store already open, do nothing
			local storeAlreadyOpen = FramesModule and FramesModule.IsFrameOpen and FramesModule:IsFrameOpen("Store")
			if not storeAlreadyOpen then
				if FramesModule and FramesModule.OpenFrame then
					FramesModule:OpenFrame("Store")
				end
				if StoreModule and StoreModule.OpenToSection then
					StoreModule:OpenToSection("VIP")
				end
			end
		elseif uiType == "CashGamepass" then
			-- Open Store and scroll to CashGamepass; if Store already open, do nothing
			local storeAlreadyOpen = FramesModule and FramesModule.IsFrameOpen and FramesModule:IsFrameOpen("Store")
			if not storeAlreadyOpen then
				if FramesModule and FramesModule.OpenFrame then
					FramesModule:OpenFrame("Store")
				end
				if StoreModule and StoreModule.OpenToSection then
					StoreModule:OpenToSection("Gamepasses")
				end
			end
			elseif FramesModule then
				-- Standard frame toggle
				if FramesModule.IsFrameOpen and FramesModule.IsFrameOpen(FramesModule, uiType) then
					if FramesModule.CloseFrame then
						FramesModule:CloseFrame(uiType)
					end
				else
					if FramesModule.OpenFrame then
						FramesModule:OpenFrame(uiType)
					end
				end
			end
		end
	end)
end

-- Global InputEnded: release scale when mouse/touch released outside button
local function onInputEnded(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	for btn, state in pairs(ButtonStates) do
		if state.isPressed and state.uiScale and state.uiScale.Parent then
			state.isPressed = false
			-- Outside button = not hovering, go to idle
			local targetScale = state.isHovering and (state.hoverScale or SCALE_HOVER) or SCALE_IDLE
			tweenScale(state.uiScale, targetScale, RELEASE_BOUNCE)
		end
	end
end

-- ========================================
-- CLEANUP ON TAG REMOVAL
-- ========================================

local function onTagRemoved(button)
	AnimatedButtons[button] = nil
	ButtonStates[button] = nil
	local uiScale = button:FindFirstChild("UIScale")
	if uiScale then
		tweenScale(uiScale, SCALE_IDLE, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	end
end

-- ========================================
-- PUBLIC API
-- ========================================

--[[
	Triggers click animation on a button (for hotkeys)
	@param button GuiButton - The button to animate
]]
function ButtonAnimation:TriggerClickAnimation(button: GuiButton)
	local state = ButtonStates[button]
	if not state or not state.uiScale or not state.uiScale.Parent then
		return
	end
	
	-- Don't animate if locked
	if button:GetAttribute("AnimationLocked") == true then
		return
	end
	
	-- Play press down animation
	state.isPressed = true
	local pressScale = state.pressScale or SCALE_PRESS
	tweenScale(state.uiScale, pressScale, PRESS_DOWN)
	
	-- Play button press sound
	if Client_Sounds then
		Client_Sounds:Play("Button Press")
	end
	
	-- Wait for press animation, then release
	task.delay(PRESS_DOWN.Time, function()
		if not state.uiScale or not state.uiScale.Parent then return end
		
		state.isPressed = false
		
		-- Play button release sound
		if Client_Sounds then
			Client_Sounds:Play("Button Release")
		end
		
		-- If hovering, go back to hover scale; otherwise idle
		local targetScale = state.isHovering and (state.hoverScale or SCALE_HOVER) or SCALE_IDLE
		tweenScale(state.uiScale, targetScale, RELEASE_BOUNCE)
	end)
end

-- ========================================
-- INIT
-- ========================================

function ButtonAnimation:Init()
	-- Get Client_Frames, Client_Store from Library (set by init.client.lua)
	FramesModule = self.Client_Frames
	Client_Sounds = self.Client_Sounds
	StoreModule = self.Client_Store
	
	UserInputService.InputEnded:Connect(onInputEnded)

	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(button)
		task.spawn(function()
			setupButton(button)
		end)
	end)

	CollectionService:GetInstanceRemovedSignal(TAG):Connect(onTagRemoved)

	for _, button in CollectionService:GetTagged(TAG) do
		task.spawn(function()
			setupButton(button)
		end)
	end
end

return ButtonAnimation
