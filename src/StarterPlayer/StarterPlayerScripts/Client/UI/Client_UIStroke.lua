--// Client_UIStroke - Automatically adjusts UIStroke thickness based on screen resolution
--// Usage: Tag any UIStroke with "UIStrokeAdjustment" in CollectionService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local player = game.Players.LocalPlayer
local tag = "UIStrokeAdjustment"

-- Save the connections so they can be disconnected when the tag is removed
local connections = {}

local currentCamera: Camera
local cameraConnections = {}

-- Base resolution for scaling calculations (1920x1080)
local resolution = Vector2.new(1920, 1080)
local currentResolution = Vector2.new()
local adjustmentID = 0
local adjustmentString = "AdjustmentID"

-- Store original thickness values before any modifications
local originalThickness = {}

local UIStroke = {}

-- ========================================
-- HELPER FUNCTIONS
-- ========================================

local function isLegal(object: Instance)
	-- Exclude UIStrokes inside SurfaceGui or BillboardGui (world-space UI)
	if object:FindFirstAncestorOfClass("SurfaceGui") or object:FindFirstAncestorOfClass("BillboardGui") then
		return false
	end
	
	return object:IsA("UIStroke") and not connections[object] and not object:IsDescendantOf(ReplicatedStorage) and object:IsDescendantOf(player.PlayerGui)
end

local function adjustStroke(uiStroke: UIStroke)
	if uiStroke:GetAttribute(adjustmentString) == adjustmentID then return end
	uiStroke:SetAttribute(adjustmentString, adjustmentID)
	
	local currentResolution = currentCamera.ViewportSize
	local axis = if currentResolution.X < currentResolution.Y then "X" else "Y"
	
	local v0 = currentResolution[axis]
	local v1 = resolution[axis]
	local scaleFactor = v0/v1
	
	-- Always use the original thickness stored before any modifications
	local originalValue = originalThickness[uiStroke]
	if not originalValue then
		-- If we somehow don't have the original, store current as fallback
		originalValue = uiStroke.Thickness
		originalThickness[uiStroke] = originalValue
	end
	
	-- Adjust UIStroke thickness based on original value
	local scaledThickness = originalValue * scaleFactor
	uiStroke.Thickness = scaledThickness
	
	-- Also adjust parent's Size offset if it has offset values
	-- ONLY if the parent has an attribute marking it for size adjustment
	local parent = uiStroke.Parent
	if parent and parent:IsA("GuiObject") and parent:GetAttribute("UIStrokeSizeAdjust") == true then
		local currentSize = parent.Size
		local newXOffset = currentSize.X.Offset
		local newYOffset = currentSize.Y.Offset
		
		-- Round UIStroke thickness for offset calculation (offsets must be integers)
		local roundedThickness = math.round(scaledThickness)
		
		-- Calculate correct offset based on rounded UIStroke thickness * 2
		local correctOffset = -roundedThickness * 2
		
		-- Update X.Offset if it has an offset
		if currentSize.X.Offset ~= 0 then
			newXOffset = correctOffset
		end
		
		-- Update Y.Offset if it has an offset
		if currentSize.Y.Offset ~= 0 then
			newYOffset = correctOffset
		end
		
		-- Apply the new size
		parent.Size = UDim2.new(
			currentSize.X.Scale,
			newXOffset,
			currentSize.Y.Scale,
			newYOffset
		)
	end
end

local function changeAllStrokes()
	local newResolution = currentCamera.ViewportSize
	if currentResolution == newResolution then return end
	
	-- Validate viewport size is reasonable before proceeding
	if newResolution.X <= 0 or newResolution.Y <= 0 or newResolution.X < 100 or newResolution.Y < 100 then
		return
	end
	
	currentResolution = newResolution
	adjustmentID += 1
	for v,_ in connections do
		adjustStroke(v)
	end
end

local function setupCamera()
	currentCamera = workspace.CurrentCamera
	for i,v in cameraConnections do
		v:Disconnect()
	end
	cameraConnections = {}
	
	-- Wait until camera/viewport is ready
	local maxAttempts = 5
	local attempts = 0
	
	while attempts < maxAttempts do
		if currentCamera then
			local viewport = currentCamera.ViewportSize
			if viewport.X > 0 and viewport.Y > 0 and viewport.X >= 100 and viewport.Y >= 100 then
				break
			end
		end
		
		task.wait(1)
		attempts += 1
	end
	
	if currentCamera then
		table.insert(cameraConnections, currentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(changeAllStrokes))
		changeAllStrokes()
	end
end

local function onInstanceAdded(object: UIStroke)
	-- Remember that any tag can be applied to any object, so there's no
	-- guarantee that the object with this tag is a UIStroke.
	if isLegal(object) then
		-- Store original thickness BEFORE any modifications
		local thickness = object.Thickness
		originalThickness[object] = thickness
		connections[object] = thickness  -- Keep for backwards compatibility
		adjustStroke(object)
	end
end

local function onInstanceRemoved(object: Instance)
	-- If we made a connection on this object, disconnect it (prevent memory leaks)
	if connections[object] then
		connections[object] = nil
	end
	-- Also clean up original thickness storage
	if originalThickness[object] then
		originalThickness[object] = nil
	end
end

-- ========================================
-- INITIALIZATION
-- ========================================

function UIStroke:Init()
	task.wait(2)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(setupCamera)
	setupCamera()

	-- Listen for this tag being applied to objects
	CollectionService:GetInstanceAddedSignal(tag):Connect(onInstanceAdded)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(onInstanceRemoved)

	-- Also detect any objects that already have the tag
	for _, object in pairs(CollectionService:GetTagged(tag)) do
		task.spawn(function() onInstanceAdded(object) end)
	end
end

return UIStroke
