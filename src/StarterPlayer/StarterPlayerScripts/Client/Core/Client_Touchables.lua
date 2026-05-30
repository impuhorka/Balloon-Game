--// Client_Touchables - Touch-to-open UI handler
--// Tag parts with "TouchTag" (CollectionService) and set attribute "UIType" (string) to the UI/frame name to open.
--// When the player touches the part, that UI opens. When they leave range, it closes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Main GUI with Frames folder: PlayerGui.MainGui.Frames[UIType] or PlayerGui.Main.Frames[UIType]
local MainGuiRoot = nil  -- MainGui or Main
local Frames = nil

-- Touch debounce so one touch doesn't fire multiple times
local touchDebounce = false

-- Track which UI parts are currently "active" (player in range, UI was opened)
local ActiveUIParts = {}

-- Custom handlers: [UIType] = { Open = function(), Close = function() }
-- Other modules can register handlers for specific UIType values
local UITypeHandlers = {}

-- Set in Init: Client_Frames (animated open/close) when available
local FramesModule = nil

local Touchables = {}

-- ========================================
-- HELPERS
-- ========================================

local function getInteractionRange(part)
	if part:IsA("BasePart") then
		return math.max(part.Size.X, part.Size.Z) * 0.5 + 2
	end
	return 10
end

local function ensureMainFrames()
	if Frames then return true end
	-- Prefer MainGui (your structure), then Main (SingingX-style)
	MainGuiRoot = PlayerGui:FindFirstChild("MainGui") or PlayerGui:FindFirstChild("Main")
	if not MainGuiRoot then return false end
	Frames = MainGuiRoot:FindFirstChild("Frames")
	return Frames ~= nil
end

local function resolveUIType(uiType)
	-- Match Client_Store / legacy place attrs: "Speed" was the old speed shop frame name
	if uiType == "SpeedUpgrades" or uiType == "SpeedStore" or uiType == "Speed" then
		return "Baloons"
	end
	return uiType
end

--- Open UI by UIType string.
--- 1) Custom handler if registered. 2) Client_Frames (animated) if available. 3) Raw visible = true.
local function openUI(uiType)
	uiType = resolveUIType(uiType)
	if UITypeHandlers[uiType] and UITypeHandlers[uiType].Open then
		UITypeHandlers[uiType].Open()
		return true
	end
	if FramesModule and FramesModule.OpenFrame then
		return FramesModule:OpenFrame(uiType)
	end
	ensureMainFrames()
	if Frames then
		local frame = Frames:FindFirstChild(uiType)
		if frame and (frame:IsA("Frame") or frame:IsA("GuiObject")) then
			frame.Visible = true
			return true
		end
	end
	-- Fallback: any ScreenGui or Frame under PlayerGui named uiType
	local gui = PlayerGui:FindFirstChild(uiType)
	if gui then
		if gui:IsA("ScreenGui") then
			gui.Enabled = true
			return true
		elseif gui:IsA("Frame") or gui:IsA("GuiObject") then
			gui.Visible = true
			return true
		end
	end
	return false
end

--- Close UI by UIType string.
local function closeUI(uiType)
	uiType = resolveUIType(uiType)
	if UITypeHandlers[uiType] and UITypeHandlers[uiType].Close then
		UITypeHandlers[uiType].Close()
		return true
	end
	if FramesModule and FramesModule.CloseFrame then
		return FramesModule:CloseFrame(uiType)
	end
	ensureMainFrames()
	if Frames then
		local frame = Frames:FindFirstChild(uiType)
		if frame and (frame:IsA("Frame") or frame:IsA("GuiObject")) then
			frame.Visible = false
			return true
		end
	end
	local gui = PlayerGui:FindFirstChild(uiType)
	if gui then
		if gui:IsA("ScreenGui") then
			gui.Enabled = false
			return true
		elseif gui:IsA("Frame") or gui:IsA("GuiObject") then
			gui.Visible = false
			return true
		end
	end
	return false
end

-- ========================================
-- TOUCH LOGIC
-- ========================================

local RangeCheckActive = false

local function startRangeCheck()
	if RangeCheckActive then return end
	RangeCheckActive = true
	
	task.spawn(function()
		while RangeCheckActive do
			task.wait(0.5)
			local character = Player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			
			if rootPart then
				local hasActiveUIs = false
				for part, isActive in pairs(ActiveUIParts) do
					if isActive and part.Parent then
						hasActiveUIs = true
						local uiType = part:GetAttribute("UIType")
						if uiType then
							local distance = (rootPart.Position - part.Position).Magnitude
							local maxRange = getInteractionRange(part)
							if distance > maxRange then
								ActiveUIParts[part] = nil
								closeUI(uiType)
							end
						else
							ActiveUIParts[part] = nil
						end
					else
						ActiveUIParts[part] = nil
					end
				end
				
				-- Stop loop if no active UIs
				if not hasActiveUIs then
					RangeCheckActive = false
				end
			end
		end
	end)
end

local function handleTouchTagInteraction(uiType, part)
	if not uiType or uiType == "" then return end
	if ActiveUIParts[part] then return end
	ActiveUIParts[part] = true
	openUI(uiType)
	startRangeCheck() -- Start checking ranges when UI opens
end

local function setupTouchTagPart(part)
	if not part:IsA("BasePart") then return end

	part.Touched:Connect(function(hit)
		if hit.Parent ~= Player.Character then return end
		if touchDebounce then return end

		local uiType = part:GetAttribute("UIType")
		if not uiType then return end

		touchDebounce = true
		handleTouchTagInteraction(uiType, part)
		task.delay(0.3, function()
			touchDebounce = false
		end)
	end)
end

-- ========================================
-- PUBLIC API
-- ========================================

--- Register custom open/close handlers for a UIType (e.g. from Client_FoodUI).
--- @param uiType string - Same value as the part's UIType attribute
--- @param openFunc function? - Called when opening
--- @param closeFunc function? - Called when closing (e.g. when player leaves range)
function Touchables:RegisterUIType(uiType, openFunc, closeFunc)
	UITypeHandlers[uiType] = {
		Open = openFunc,
		Close = closeFunc,
	}
end

--- Programmatically open a UI by type (optional; touch still works via tag/attribute).
function Touchables:OpenUI(uiType)
	return openUI(uiType)
end

--- Programmatically close a UI by type.
function Touchables:CloseUI(uiType)
	return closeUI(uiType)
end

-- ========================================
-- INIT
-- ========================================

function Touchables:Init()
	ensureMainFrames()
	-- Use Client_Frames for animated open/close when available (Library set by init.client.lua)
	FramesModule = self.Client_Frames

	for _, part in CollectionService:GetTagged("TouchTag") do
		task.spawn(setupTouchTagPart, part)
	end

	CollectionService:GetInstanceAddedSignal("TouchTag"):Connect(setupTouchTagPart)
	
	-- No longer need the always-running loop - startRangeCheck() is called on-demand
end

return Touchables
