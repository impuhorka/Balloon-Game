--// Client_Inventory - Complete client-side inventory system
--// Handles both data access and UI rendering

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local ReplicaController = require(ReplicatedStorage.Modules.Dependencies.ReplicaController)
local ItemDataAccess = require(ReplicatedStorage.Modules.Gameplay.ItemDataAccess)
local InventoryConfig = require(ReplicatedStorage.Modules.Settings.InventoryConfig)
local Shared_Tools = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Tools)
local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Module = {}

-- Will be set in Init (from Library)
local Client_Sounds = nil

Module.Inventory = {} -- Player's inventory items
Module.HotbarSlots = {nil, nil, nil, nil, nil, nil} -- 6 hotbar slots
Module.PlayerReplica = nil
Module.IsReady = false

-- Bindable events for UI updates
Module.InventoryChanged = Instance.new("BindableEvent")
Module.HotbarChanged = Instance.new("BindableEvent")

-- UI References
local BackpackUI
local HotbarFrame
local ExpandedFrame
local GridHolder
local SearchBox
local BackpackButton -- Store reference to backpack button

-- UI State
local IsExpanded = false
local SelectedUID = nil
local SearchQuery = ""
local ClickCD = false -- Tsunami: prevent double-clicks

-- Expand animation (frame-style: slide from off-screen like Client_Frames)
local EXPAND_OPEN_TIME = 0.25
local EXPAND_CLOSE_TIME = 0.15
local ExpandTween: Tween? = nil
local ExpandOriginPosition: UDim2? = nil
-- Collapsed = same X as origin, Y below screen (slide up to open, slide down to close)
local function getExpandCollapsedPosition()
	if not ExpandOriginPosition then return nil end
	return UDim2.new(ExpandOriginPosition.X.Scale, ExpandOriginPosition.X.Offset, ExpandOriginPosition.Y.Scale + 0.5, ExpandOriginPosition.Y.Offset)
end

-- Hold Animation
local CurrentHoldTrack: AnimationTrack? = nil
local CurrentHoldAnimationId: string? = nil

-- Templates
local HotbarSlotTemplate
local GridSlotTemplate

--[[
	Inventory slot scale animation (Tsunami FrameWithImageButton - only for inventory, not global AnimatedButton)
]]
local function applyInventorySlotAnimation(frame: Frame, scale: number?)
	if not scale then scale = 0.05 end
	local imageButton = frame:FindFirstChildOfClass("ImageButton")
	if not imageButton then return end
	
	-- Store the ACTUAL original size on the frame itself for reference
	if not frame:GetAttribute("OriginalSizeX_Scale") then
		frame:SetAttribute("OriginalSizeX_Scale", frame.Size.X.Scale)
		frame:SetAttribute("OriginalSizeX_Offset", frame.Size.X.Offset)
		frame:SetAttribute("OriginalSizeY_Scale", frame.Size.Y.Scale)
		frame:SetAttribute("OriginalSizeY_Offset", frame.Size.Y.Offset)
	end
	
	local function getOriginSize(): UDim2
		return UDim2.new(
			frame:GetAttribute("OriginalSizeX_Scale"),
			frame:GetAttribute("OriginalSizeX_Offset"),
			frame:GetAttribute("OriginalSizeY_Scale"),
			frame:GetAttribute("OriginalSizeY_Offset")
		)
	end
	
	local function scaleSize(size: UDim2, factor: number): UDim2
		return UDim2.new(size.X.Scale * factor, size.X.Offset * factor, size.Y.Scale * factor, size.Y.Offset * factor)
	end
	
	imageButton.MouseButton1Click:Connect(function()
		local originSize = getOriginSize()
		TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = scaleSize(originSize, 1 + scale)
		}):Play()
		local playSound = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("PlaySound")
		if playSound then playSound:Fire("Click") end
	end)
	imageButton.MouseButton1Down:Connect(function()
		local originSize = getOriginSize()
		TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = scaleSize(originSize, 1 - scale)
		}):Play()
	end)
	imageButton.MouseLeave:Connect(function()
		local originSize = getOriginSize()
		TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Size = originSize }):Play()
	end)
	imageButton.MouseEnter:Connect(function()
		local originSize = getOriginSize()
		TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = scaleSize(originSize, 1 + scale)
		}):Play()
	end)
end

--[[
	Plays click animation on a container (for hotkey feedback - same as button click)
]]
local function playSlotClickAnimation(frame: Frame, scale: number?)
	if not scale then scale = 0.05 end
	
	-- Get stored original size
	local function getOriginSize(): UDim2
		return UDim2.new(
			frame:GetAttribute("OriginalSizeX_Scale") or frame.Size.X.Scale,
			frame:GetAttribute("OriginalSizeX_Offset") or frame.Size.X.Offset,
			frame:GetAttribute("OriginalSizeY_Scale") or frame.Size.Y.Scale,
			frame:GetAttribute("OriginalSizeY_Offset") or frame.Size.Y.Offset
		)
	end
	
	local originSize = getOriginSize()
	local function scaleSize(size: UDim2, factor: number): UDim2
		return UDim2.new(size.X.Scale * factor, size.X.Offset * factor, size.Y.Scale * factor, size.Y.Offset * factor)
	end
	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(frame, tweenInfo, { Size = scaleSize(originSize, 1 - scale) }):Play()
	task.delay(0.08, function()
		TweenService:Create(frame, tweenInfo, { Size = scaleSize(originSize, 1 + scale) }):Play()
		task.delay(0.15, function()
			TweenService:Create(frame, tweenInfo, { Size = originSize }):Play()
		end)
	end)
	local playSound = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("PlaySound")
	if playSound then playSound:Fire("Click") end
end

-- Forward declarations for functions
local setupDragToHotbar
local setupDragToExpanded
local onItemClicked
local renderHotbar
local renderExpanded

--[[
	Waits until inventory data is ready
]]
function Module:WaitUntilReady()
	while not self.IsReady do
		task.wait()
	end
end

--[[
	Gets all items in inventory
	@return table - Inventory dictionary {[uid] = itemData}
]]
function Module:GetInventory(): {[string]: any}
	return self.Inventory or {}
end

--[[
	Gets a specific item by UID
	@param uid string - Item UID
	@return table? - Item data or nil
]]
function Module:GetItem(uid: string): {[string]: any}?
	return self.Inventory[uid]
end

--[[
	Gets hotbar slots
	@return {string?} - Array of 6 UIDs or nil
]]
function Module:GetHotbarSlots(): {string?}
	return self.HotbarSlots
end

--[[
	Gets item in a specific hotbar slot
	@param slotIndex number - Slot index (1-6)
	@return table? - Item data or nil
]]
function Module:GetHotbarItem(slotIndex: number): {[string]: any}?
	if slotIndex < 1 or slotIndex > InventoryConfig.HotbarSlots then
		return nil
	end
	
	local uid = self.HotbarSlots[slotIndex]
	if not uid then
		return nil
	end
	
	return self:GetItem(uid)
end

--[[
	Gets all equipped items
	@return {table} - Array of equipped item data
]]
function Module:GetEquippedItems(): {{[string]: any}}
	local equipped = {}
	
	for uid, itemData in pairs(self.Inventory) do
		if itemData.Equipped then
			table.insert(equipped, itemData)
		end
	end
	
	return equipped
end

--[[
	Gets equipped item of a specific type
	@param itemType string - Item type (Tool)
	@return table? - Item data or nil
]]
function Module:GetEquippedItemOfType(itemType: string): {[string]: any}?
	for uid, itemData in pairs(self.Inventory) do
		if itemData.Type == itemType and itemData.Equipped then
			return itemData
		end
	end
	
	return nil
end

--[[
	Gets item property (uses ItemDataAccess for computed properties)
	@param uid string - Item UID
	@param property string - Property name
	@return any - Property value
]]
function Module:GetItemProperty(uid: string, property: string): any
	local itemData = self:GetItem(uid)
	if not itemData then
		return nil
	end
	
	return ItemDataAccess:GetItemProperty(itemData, property)
end

--[[
	Gets inventory item count
	@return number - Number of items in inventory
]]
function Module:GetItemCount(): number
	local count = 0
	for _ in pairs(self.Inventory) do
		count = count + 1
	end
	return count
end

--[[
	Checks if inventory is full
	@return boolean - Is full
]]
function Module:IsInventoryFull(): boolean
	return self:GetItemCount() >= InventoryConfig.MaxInventorySize
end

--[[
	Gets all items of a specific type
	@param itemType string - Item type
	@return {table} - Array of item data
]]
function Module:GetItemsByType(itemType: string): {{[string]: any}}
	local items = {}
	
	for uid, itemData in pairs(self.Inventory) do
		if itemData.Type == itemType then
			table.insert(items, itemData)
		end
	end
	
	return items
end

--[[
	Searches inventory for items matching a query
	@param query string - Search query (matches DisplayName or ConfigName)
	@return {table} - Array of matching item data
]]
function Module:SearchItems(query: string): {{[string]: any}}
	if not query or query == "" then
		return {}
	end
	
	local results = {}
	local lowerQuery = string.lower(query)
	
	for uid, itemData in pairs(self.Inventory) do
		local displayName = ItemDataAccess:GetItemProperty(itemData, "DisplayName") or ""
		local configName = itemData.ConfigName or ""
		
		if string.find(string.lower(displayName), lowerQuery) 
			or string.find(string.lower(configName), lowerQuery) then
			table.insert(results, itemData)
		end
	end
	
	return results
end

--[[
	Checks if item is the slapper (reserved for slot 1)
]]
local function isSlapper(uid: string): boolean
	local itemData = Module:GetItem(uid)
	return itemData and (itemData.ConfigName == "StandardSlapper" or itemData.ConfigName == "VIPSlapper")
end

--[[
	Checks if item is the Tablet gamepass tool (reserved for slot 2)
]]
local function isTablet(uid: string): boolean
	local itemData = Module:GetItem(uid)
	return itemData and itemData.Type == "Tool" and itemData.ConfigName == InventoryConfig.TabletConfigName
end

--[[
	Checks if item is the Sniper gamepass tool (reserved for slot 3)
]]
local function isSniper(uid: string): boolean
	local itemData = Module:GetItem(uid)
	return itemData and itemData.Type == "Tool" and itemData.ConfigName == InventoryConfig.SniperConfigName
end

--[[
	True if slot 2/3 is reserved (player has the pass). Only then can't other items use that slot.
]]
local function hasTabletPass(): boolean
	local r = Module.PlayerReplica
	return r and r.Data and r.Data.Passes and r.Data.Passes.Tablet == true
end

local function hasSniperPass(): boolean
	local r = Module.PlayerReplica
	return r and r.Data and r.Data.Passes and r.Data.Passes.Sniper == true
end

--[[
	True if this item is a gamepass tool AND player has the pass (so it's locked to its slot / can't move out).
]]
local function isReservedGamepassTool(uid: string): boolean
	return (isTablet(uid) and hasTabletPass()) or (isSniper(uid) and hasSniperPass())
end

--[[
	Checks if item is in hotbar
]]
local function isInHotbar(uid: string): boolean
	for i = 1, InventoryConfig.HotbarSlots do
		if Module.HotbarSlots[i] == uid then
			return true
		end
	end
	return false
end

--[[
	Shifts hotbar items when items are removed. Slot 2/3 only reserved when player has the pass.
	Evicted items from 2-6 (excluding Tablet/Sniper when they own the pass) go into 4-6.
]]
local function shiftHotbarSlots()
	local tabletSlot = InventoryConfig.TabletSlot
	local sniperSlot = InventoryConfig.SniperSlot

	-- Collect "other" UIDs from 2-6: exclude Tablet and Sniper if they stay in their reserved slots
	local otherItems = {}
	for i = 2, InventoryConfig.HotbarSlots do
		local uid = Module.HotbarSlots[i]
		if uid then
			if isTablet(uid) and hasTabletPass() then
				-- Tablet stays in slot 2 when they have pass
			elseif isSniper(uid) and hasSniperPass() then
				-- Sniper stays in its reserved slot (2 or 3 depending on tablet pass)
			else
				table.insert(otherItems, uid)
			end
		end
	end

	-- Clear slots 2-6 (slot 1 slapper untouched)
	for i = 2, InventoryConfig.HotbarSlots do
		Module.HotbarSlots[i] = nil
	end

	-- Slot 2 and 3 logic: Sniper goes to slot 2 if no tablet pass, otherwise slot 3
	if hasTabletPass() then
		-- Has tablet pass: Tablet in slot 2, Sniper in slot 3
		for uid, _ in pairs(Module.Inventory) do
			if isTablet(uid) then
				Module.HotbarSlots[tabletSlot] = uid
				break
			end
		end
		
		if hasSniperPass() then
			for uid, _ in pairs(Module.Inventory) do
				if isSniper(uid) then
					Module.HotbarSlots[sniperSlot] = uid
					break
				end
			end
		end
	else
		-- No tablet pass: Sniper goes to slot 2
		if hasSniperPass() then
			for uid, _ in pairs(Module.Inventory) do
				if isSniper(uid) then
					Module.HotbarSlots[tabletSlot] = uid -- Put sniper in slot 2
					break
				end
			end
		end
	end

	-- Fill 4-6 with other items (2 and 3 stay empty for non-pass holders; fillEmptyHotbarSlots will use them)
	local slotIndex = 4
	for _, uid in ipairs(otherItems) do
		if slotIndex <= InventoryConfig.HotbarSlots then
			Module.HotbarSlots[slotIndex] = uid
			slotIndex = slotIndex + 1
		end
	end
end

--[[
	Fills empty hotbar slots. Slapper in 1. If they have passes: Tablet in 2, Sniper in 3 (evicts whatever was there to 4-6).
	Slots 2 and 3 are only reserved when they have the pass; otherwise any item can use them.
]]
local function fillEmptyHotbarSlots()
	local slapperSlot = InventoryConfig.SlapperSlot
	local tabletSlot = InventoryConfig.TabletSlot
	local sniperSlot = InventoryConfig.SniperSlot

	-- Slot 1: slapper
	local slapperUID = nil
	for uid, _ in pairs(Module.Inventory) do
		if isSlapper(uid) then
			slapperUID = uid
			break
		end
	end
	if slapperUID then
		Module.HotbarSlots[slapperSlot] = slapperUID
	end

	-- Slot 2 and 3 logic: Sniper goes to slot 2 if no tablet pass, otherwise slot 3
	if hasTabletPass() then
		-- Has tablet pass: Tablet in slot 2, Sniper in slot 3
		for uid, _ in pairs(Module.Inventory) do
			if isTablet(uid) then
				Module.HotbarSlots[tabletSlot] = uid
				break
			end
		end
		
		if hasSniperPass() then
			for uid, _ in pairs(Module.Inventory) do
				if isSniper(uid) then
					Module.HotbarSlots[sniperSlot] = uid
					break
				end
			end
		end
	else
		-- No tablet pass: Sniper goes to slot 2
		if hasSniperPass() then
			for uid, _ in pairs(Module.Inventory) do
				if isSniper(uid) then
					Module.HotbarSlots[tabletSlot] = uid -- Put sniper in slot 2 (tablet slot)
					break
				end
			end
		end
	end

	-- Items not in hotbar: exclude slapper, and exclude Tablet/Sniper based on their actual placement
	local itemsNotInHotbar = {}
	for uid, _ in pairs(Module.Inventory) do
		if isSlapper(uid) then
			-- skip
		elseif isTablet(uid) and hasTabletPass() and Module.HotbarSlots[tabletSlot] == uid then
			-- already in slot 2 (has tablet pass)
		elseif isSniper(uid) and hasSniperPass() then
			-- Skip sniper: goes to slot 2 (no tablet) or slot 3 (has tablet)
			-- It's already placed in hotbar above
		elseif not isInHotbar(uid) then
			table.insert(itemsNotInHotbar, uid)
		end
	end

	-- Fill every empty slot 2-6 with "other" items (2 and 3 are free when no pass)
	for i = 2, InventoryConfig.HotbarSlots do
		if not Module.HotbarSlots[i] and #itemsNotInHotbar > 0 then
			Module.HotbarSlots[i] = table.remove(itemsNotInHotbar, 1)
		end
	end
end

--[[
	Sets a hotbar slot (client-side preference)
	@param slotIndex number - Slot index (1-6)
	@param uid string? - Item UID or nil to clear
]]
function Module:SetHotbarSlot(slotIndex: number, uid: string?)
	if slotIndex < 1 or slotIndex > InventoryConfig.HotbarSlots then
		return
	end
	
	-- Slot 1 reserved for slapper only
	if slotIndex == InventoryConfig.SlapperSlot then
		if uid and not isSlapper(uid) then
			return -- Cannot put non-slapper in slot 1
		end
	end
	-- Slot 2 logic: 
	-- - If has tablet pass: reserved for Tablet only
	-- - If no tablet pass but has sniper pass: reserved for Sniper only
	-- - Otherwise: any item can use it
	if slotIndex == InventoryConfig.TabletSlot then
		if hasTabletPass() and uid and not isTablet(uid) then
			return -- Has tablet pass: only tablet allowed
		elseif not hasTabletPass() and hasSniperPass() and uid and not isSniper(uid) then
			return -- No tablet pass, has sniper pass: only sniper allowed
		end
	end
	-- Slot 3 reserved for Sniper only when they have BOTH tablet and sniper passes
	if slotIndex == InventoryConfig.SniperSlot and hasTabletPass() and hasSniperPass() then
		if uid and not isSniper(uid) then
			return
		end
	end

	-- Validate item exists if uid provided
	if uid and not self:GetItem(uid) then
		return
	end

	-- Update hotbar (client-side only)
	self.HotbarSlots[slotIndex] = uid
	self.HotbarChanged:Fire()
end

--[[
	Creates a UI slot for an item
	@param itemData table - Item data
	@param uid string - Item UID
	@param isHotbar boolean - Is this for hotbar or grid
	@return Frame - The slot UI
]]
local function createItemSlot(itemData: {[string]: any}, uid: string, isHotbar: boolean): Frame
	-- Require Shared_Rarity at function scope so it's available everywhere
	local Shared_Rarity = require(ReplicatedStorage.Modules.Gameplay.Shared_Rarity)
	
	-- Select correct template based on item type (Tsunami style)
	local template
	if itemData.Type == "Brainrot" then
		template = HotbarSlotTemplate -- BrainrotTemplate (has LabelList)
	else
		template = GridSlotTemplate -- ItemTemplate (has ImageLabel for icon)
	end
	
	if not template then
		warn("No template found for", itemData.Type)
		return nil
	end
	
	local slot = template:Clone()
	slot.Name = uid
	slot.Visible = true
	
	-- Get item properties
	local displayName = ItemDataAccess:GetItemProperty(itemData, "DisplayName") or itemData.ConfigName
	local icon = ItemDataAccess:GetItemProperty(itemData, "Icon")
	local rarity = ItemDataAccess:GetItemProperty(itemData, "Rarity") or "Common"
	
	-- Find Container (Tsunami uses Container as wrapper)
	local container = slot:FindFirstChild("Container")
	if not container then
		container = slot -- Fallback if no Container
	end
	
	-- Set icon (for Tools)
	local iconImage = container:FindFirstChild("ImageLabel")
	if iconImage and iconImage:IsA("ImageLabel") and itemData.Type ~= "Brainrot" then
		iconImage.Image = icon or ""
		iconImage.Visible = true
	elseif iconImage then
		iconImage.Visible = false -- Hide for brainrots (they show 3D render)
	end
	
	-- Set hotbar index
	local hotbarIndex = container:FindFirstChild("HotbarIndex")
	if hotbarIndex and hotbarIndex:IsA("TextLabel") then
		hotbarIndex.Text = "" -- Will be set later based on position
	end
	
	-- Handle Brainrot-specific display
	if itemData.Type == "Brainrot" then
		local labelList = container:FindFirstChild("LabelList")
		if labelList then
			-- Rarity (main rarity like "Common", "Rare", etc.)
			local rarityLabel = labelList:FindFirstChild("Rarity")
			if rarityLabel and rarityLabel:IsA("TextLabel") then
				rarityLabel.Text = rarity
				
				-- Add UIGradient matching brainrot's rarity
				local rarityInfo = Shared_Rarity:GetRarityInfo(rarity)
				if rarityInfo then
					local gradient = rarityLabel:FindFirstChildOfClass("UIGradient")
					if not gradient then
						gradient = Instance.new("UIGradient")
						gradient.Parent = rarityLabel
					end
					
					if gradient and rarityInfo.gradient then
						gradient.Color = rarityInfo.gradient
						gradient.Rotation = (rarityInfo.isRainbow and 0) or 90  -- Rainbow 0°, others 90°
					end
				end
			end
			
			-- Level
			local levelLabel = labelList:FindFirstChild("Level")
			if levelLabel and levelLabel:IsA("TextLabel") then
				levelLabel.Text = "Lv." .. tostring(itemData.Metadata.Level or 1)
			end
			
			-- Display Name
			local displayNameLabel = labelList:FindFirstChild("DisplayName")
			if displayNameLabel and displayNameLabel:IsA("TextLabel") then
				displayNameLabel.Text = displayName
			end
			
			-- Modifier frame: use Container.ModifierFrame.UIGradient; hide if Normal/no modifier
			local modifierFrame = container:FindFirstChild("ModifierFrame")
			if modifierFrame then
				local modifier = itemData.Metadata and itemData.Metadata.Modifier or "Normal"
				if modifier and modifier ~= "Normal" then
					local modifierData = Shared_Rarity.ModifierData[modifier]
					if modifierData and modifierData.Color then
						modifierFrame.Visible = true
						local gradient = modifierFrame:FindFirstChildOfClass("UIGradient")
						if gradient then
							gradient.Color = modifierData.Color[1]
							gradient.Rotation = (modifier == "Rainbow") and 0 or modifierData.Color[2]
						end
					else
						modifierFrame.Visible = false
					end
				else
					modifierFrame.Visible = false
				end
			end
		end
	else
		-- For non-brainrots, just set display name
		local nameLabel = container:FindFirstChild("ItemName") or container:FindFirstChild("DisplayName")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = displayName
		end
	end
	
	-- Rarity color on RarityBorder only (Tsunami: Container.UIStroke is for selection only, not rarity)
	local rarityBorder = container:FindFirstChild("RarityBorder") or slot:FindFirstChild("RarityBorder")
	if rarityBorder and rarityBorder:IsA("UIStroke") then
		local rarityColors = {
			Common = Color3.fromRGB(200, 200, 200),
			Rare = Color3.fromRGB(0, 150, 255),
			Epic = Color3.fromRGB(200, 0, 255),
			Legendary = Color3.fromRGB(255, 200, 0),
		}
		rarityBorder.Color = rarityColors[rarity] or rarityColors.Common
	end
	
	-- Tsunami: Container.UIStroke = selection stroke. 0=visible when picked, 1=hidden when not.
	-- Only use attribute (server auth) - NOT itemData.Equipped (replica can be stale on spawn)
	local currentEquipped = Player:GetAttribute("CurrentEquipped")
	local isSelected = (uid == SelectedUID)
	local isEquipped = (uid == currentEquipped)
	
	local containerStroke = container:FindFirstChild("UIStroke")
	if containerStroke and containerStroke:IsA("UIStroke") then
		containerStroke.Transparency = (isSelected or isEquipped) and 0 or 1
	end
	
	-- Equipped indicator (if element exists)
	local equippedIndicator = container:FindFirstChild("EquippedIndicator")
	if equippedIndicator then
		equippedIndicator.Visible = isEquipped
	end
	
	-- Stack count (for consumables)
	local typeConfig = InventoryConfig.ItemTypeConfig[itemData.Type]
	if typeConfig and typeConfig.needsStackCount then
		local stackLabel = container:FindFirstChild("StackCount")
		if stackLabel and stackLabel:IsA("TextLabel") then
			local count = itemData.Metadata.StackCount or 1
			stackLabel.Text = tostring(count)
			stackLabel.Visible = count > 1
		end
	end
	
	-- Inventory slot animation (scale on hover/click - inline, not using global AnimatedButton tag)
	applyInventorySlotAnimation(container)
	
	-- Button functionality
	local button = container:FindFirstChildOfClass("ImageButton") or slot:FindFirstChildOfClass("ImageButton")
	if button then
		button.MouseButton1Click:Connect(function()
			if ClickCD then return end
			ClickCD = true
			task.delay(0.15, function() ClickCD = false end)
			
			onItemClicked(uid, itemData)
		end)
		
		-- Setup drag for hotbar items
		if isHotbar then
			setupDragToExpanded(slot, uid, button)
		else
			setupDragToHotbar(slot, uid, button)
		end
	else
		warn("⚠️ No ImageButton found in slot for:", uid)
	end
	
	return slot
end

--[[
	Handles item click (only works for hotbar items in Tsunami style)
]]
--[[
	Directly updates stroke on hotbar AND expanded frames
	UIStroke should ONLY show when item is actually equipped, not just selected
	@param uidToHide string? - When unequipping, pass uid to hide stroke immediately (optimistic)
]]
local function updateSelectionStroke(uidToHide: string?)
	local currentEquipped = Player:GetAttribute("CurrentEquipped")
	
	-- Update hotbar strokes
	if HotbarFrame then
		for _, frame in ipairs(HotbarFrame:GetChildren()) do
			if frame:IsA("Frame") and frame.Name ~= "Backpack" then
				local container = frame:FindFirstChild("Container")
				local stroke = container and container:FindFirstChild("UIStroke")
				if stroke and stroke:IsA("UIStroke") then
					-- ONLY show stroke if this item is equipped (not just selected)
					local show = frame.Name == currentEquipped and frame.Name ~= uidToHide
					stroke.Transparency = show and 0 or 1
				end
			end
		end
	end
	
	-- Update expanded grid strokes
	if GridHolder then
		for _, frame in ipairs(GridHolder:GetChildren()) do
			if frame:IsA("Frame") then
				local container = frame:FindFirstChild("Container")
				local stroke = container and container:FindFirstChild("UIStroke")
				if stroke and stroke:IsA("UIStroke") then
					local show = frame.Name == currentEquipped and frame.Name ~= uidToHide
					stroke.Transparency = show and 0 or 1
				end
			end
		end
	end
end

onItemClicked = function(uid: string, itemData: {[string]: any})
	-- Handle brainrots: set SlotPlacablePicked AND equip (Tsunami does both)
	if itemData.Type == "Brainrot" then
		local player = Players.LocalPlayer
		local currentPicked = player:GetAttribute("SlotPlacablePicked")
		local currentEquipped = player:GetAttribute("CurrentEquipped")
		local Events = ReplicatedStorage:FindFirstChild("Events")
		
		if currentPicked == uid and currentEquipped == uid then
			-- Already selected and equipped, deselect both
			SelectedUID = nil
			player:SetAttribute("SlotPlacablePicked", nil)
			local InventoryHandlerEvent = Events and Events:FindFirstChild("InventoryHandler")
			if InventoryHandlerEvent then
				InventoryHandlerEvent:FireServer("Unequip", uid)
			end
			updateSelectionStroke(uid)
		else
			-- Select for placement AND equip to hand (Tsunami behavior)
			SelectedUID = uid
			player:SetAttribute("SlotPlacablePicked", uid)
			local InventoryHandlerEvent = Events and Events:FindFirstChild("InventoryHandler")
			if InventoryHandlerEvent then
				InventoryHandlerEvent:FireServer("Equip", uid)
			end
			
			-- Play item equip sound
			if Client_Sounds then
				Client_Sounds:Play("Item Equip")
			end
			
			updateSelectionStroke()
		end
		
		return
	end
	
	-- Handle lucky blocks: set SlotPlacablePicked AND equip (like brainrots)
	if itemData.Type == "LuckyBlock" then
		local player = Players.LocalPlayer
		local currentPicked = player:GetAttribute("SlotPlacablePicked")
		local currentEquipped = player:GetAttribute("CurrentEquipped")
		local Events = ReplicatedStorage:FindFirstChild("Events")
		
		if currentPicked == uid and currentEquipped == uid then
			-- Already selected and equipped, deselect both
			SelectedUID = nil
			player:SetAttribute("SlotPlacablePicked", nil)
			local InventoryHandlerEvent = Events and Events:FindFirstChild("InventoryHandler")
			if InventoryHandlerEvent then
				InventoryHandlerEvent:FireServer("Unequip", uid)
			end
			updateSelectionStroke(uid)
		else
			-- Select for holding AND equip to hand (same as brainrots)
			-- Note: uid here is the representative (first) UID of a stack
			SelectedUID = uid
			player:SetAttribute("SlotPlacablePicked", uid)
			
			local InventoryHandlerEvent = Events and Events:FindFirstChild("InventoryHandler")
			if InventoryHandlerEvent then
				InventoryHandlerEvent:FireServer("Equip", uid)
			end
			
			-- Play item equip sound
			if Client_Sounds then
				Client_Sounds:Play("Item Equip")
			end
			
			updateSelectionStroke()
		end
		
		return
	end
	
	-- For equippable items (Tools, etc.), toggle equip/unequip
	local typeConfig = InventoryConfig.ItemTypeConfig[itemData.Type]
	if typeConfig and typeConfig.needsEquipped then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if not Events then return end
		
		local player = Players.LocalPlayer
		local currentEquipped = player:GetAttribute("CurrentEquipped")
		
		if currentEquipped == uid then
			-- Already equipped, unequip (clear selection + hide stroke optimistically)
			SelectedUID = nil
			local InventoryHandlerEvent = Events and Events:FindFirstChild("InventoryHandler")
			if InventoryHandlerEvent then
				InventoryHandlerEvent:FireServer("Unequip", uid)
			end
			updateSelectionStroke(uid) -- Pass uid to hide stroke immediately
		else
			-- Equip tool (e.g. slapper) — clear placable so click doesn't open lucky block
			SelectedUID = uid
			player:SetAttribute("SlotPlacablePicked", nil)
			local InventoryHandlerEvent = Events and Events:FindFirstChild("InventoryHandler")
			if InventoryHandlerEvent then
				InventoryHandlerEvent:FireServer("Equip", uid)
			end
			
			-- Play item equip sound
			if Client_Sounds then
				Client_Sounds:Play("Item Equip")
			end
			
			updateSelectionStroke()
		end
	else
		-- Non-equippable items don't set SelectedUID
		updateSelectionStroke()
	end
	
	-- For consumables, use immediately
	if itemData.Type == "Consumable" then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local UseEvent = Events and Events:FindFirstChild("UseConsumable")
		if UseEvent then
			UseEvent:FireServer(uid)
		end
	end
	
	-- No need to re-render expanded - updateSelectionStroke() handles visual updates
end

--// DRAG-DROP FUNCTIONALITY

--[[
	Creates a drag clone for visual feedback (Tsunami: parent to BackpackUI, high ZIndex)
]]
local function createDragClone(originalFrame: Frame): Frame
	local clone = originalFrame:Clone()
	clone.Parent = BackpackUI or originalFrame.Parent
	clone.ZIndex = 50
	clone.AnchorPoint = Vector2.new(0, 0)
	clone.AutomaticSize = Enum.AutomaticSize.None
	clone.Size = UDim2.fromOffset(originalFrame.AbsoluteSize.X, originalFrame.AbsoluteSize.Y)
	for _, gui in ipairs(clone:GetDescendants()) do
		if gui:IsA("GuiObject") then
			gui.ZIndex = 50
		end
	end
	return clone
end

--[[
	Convert screen position to GUI position (Tsunami: accounts for GuiInset)
]]
local function toGuiPos(position: Vector2): Vector2
	local inset = GuiService:GetGuiInset()
	return Vector2.new(position.X - inset.X, position.Y - inset.Y)
end

--[[
	Checks if point is inside expanded view
]]
local function isPointInExpanded(position: Vector2): boolean
	if not ExpandedFrame or not ExpandedFrame.Visible then
		return false
	end
	local pos = typeof(position) == "Vector3" and Vector2.new(position.X, position.Y) or position
	local absPos = ExpandedFrame.AbsolutePosition
	local absSize = ExpandedFrame.AbsoluteSize
	return pos.X >= absPos.X and pos.X <= absPos.X + absSize.X
		and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y
end

--[[
	Checks if point is inside hotbar
]]
local function isPointInHotbar(position: Vector2): boolean
	if not HotbarFrame then
		return false
	end
	local pos = typeof(position) == "Vector3" and Vector2.new(position.X, position.Y) or position
	local absPos = HotbarFrame.AbsolutePosition
	local absSize = HotbarFrame.AbsoluteSize
	return pos.X >= absPos.X and pos.X <= absPos.X + absSize.X
		and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y
end

--[[
	Gets hotbar slot index at point (Tsunami: get_hotbar_slot_at_point)
]]
local function getHotbarSlotAtPoint(pos: Vector2): Frame?
	if not HotbarFrame then return nil end
	for _, frame in ipairs(HotbarFrame:GetChildren()) do
		if frame:IsA("Frame") then
			local absPos = frame.AbsolutePosition
			local absSize = frame.AbsoluteSize
			if pos.X >= absPos.X and pos.X <= absPos.X + absSize.X
				and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y then
				return frame
			end
		end
	end
	return nil
end

-- Must move this many pixels to count as drag (not a click)
local DRAG_THRESHOLD = 8

--[[
	Setup drag from expanded to hotbar (Tsunami: setup_drag_to_hotbar)
	Only processes drop if user actually DRAGGED - clicks equip via MouseButton1Click
]]
setupDragToHotbar = function(frame: Frame, uid: string, button: GuiButton)
	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		
		local container = BackpackUI or frame.Parent
		if not container then return end
		
		local startPos = typeof(input.Position) == "Vector3" and Vector2.new(input.Position.X, input.Position.Y) or input.Position
		local didDrag = false
		
		local dragClone = createDragClone(frame)
		local containerPos = container.AbsolutePosition
		local framePosLocal = Vector2.new(frame.AbsolutePosition.X, frame.AbsolutePosition.Y) - containerPos
		local localMouse = toGuiPos(input.Position) - containerPos
		local offset = localMouse - framePosLocal
		local dragging = true
		
		local function updateDrag(pos: Vector2)
			local pos2 = typeof(pos) == "Vector3" and Vector2.new(pos.X, pos.Y) or pos
			local localPos = toGuiPos(pos2) - containerPos - offset
			dragClone.Position = UDim2.fromOffset(localPos.X, localPos.Y)
			if not didDrag then
				local dx = math.abs(pos2.X - startPos.X)
				local dy = math.abs(pos2.Y - startPos.Y)
				if dx > DRAG_THRESHOLD or dy > DRAG_THRESHOLD then
					didDrag = true
				end
			end
		end
		
		updateDrag(input.Position)
		
		local moveConn = UserInputService.InputChanged:Connect(function(moveInput)
			if not dragging then return end
			if moveInput.UserInputType ~= Enum.UserInputType.MouseMovement and moveInput.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			updateDrag(moveInput.Position)
		end)
		
		local endConn
		endConn = UserInputService.InputEnded:Connect(function(endInput)
			if endInput.UserInputType ~= input.UserInputType then return end
			dragging = false
			
			if moveConn then moveConn:Disconnect() end
			if endConn then endConn:Disconnect() end
			
			if didDrag then
				-- Slapper and gamepass tools cannot be moved out of hotbar
				if isSlapper(uid) or isReservedGamepassTool(uid) then
					-- Do nothing - stays in reserved slot
				else
					local pointGui = toGuiPos(endInput.Position)
					local pointRaw = typeof(endInput.Position) == "Vector3" and Vector2.new(endInput.Position.X, endInput.Position.Y) or endInput.Position
					local hotbarSlot = getHotbarSlotAtPoint(pointGui) or getHotbarSlotAtPoint(pointRaw)
					local inHotbar = hotbarSlot or (HotbarFrame and pointRaw.X >= HotbarFrame.AbsolutePosition.X and pointRaw.X <= HotbarFrame.AbsolutePosition.X + HotbarFrame.AbsoluteSize.X and pointRaw.Y >= HotbarFrame.AbsolutePosition.Y and pointRaw.Y <= HotbarFrame.AbsolutePosition.Y + HotbarFrame.AbsoluteSize.Y)

					if inHotbar then
						local emptySlot = nil
						if isTablet(uid) and hasTabletPass() then
							-- Tablet always goes to slot 2 when player has the pass
							if not Module.HotbarSlots[InventoryConfig.TabletSlot] then
								emptySlot = InventoryConfig.TabletSlot
							end
						elseif isSniper(uid) and hasSniperPass() then
							-- Sniper logic: slot 2 if no tablet pass, slot 3 if has tablet pass
							if hasTabletPass() then
								-- Has tablet pass: sniper goes to slot 3
								if not Module.HotbarSlots[InventoryConfig.SniperSlot] then
									emptySlot = InventoryConfig.SniperSlot
								end
							else
								-- No tablet pass: sniper goes to slot 2
								if not Module.HotbarSlots[InventoryConfig.TabletSlot] then
									emptySlot = InventoryConfig.TabletSlot
								end
							end
						else
							-- Other items: first empty slot in 2-6 that's not reserved
							for i = 2, InventoryConfig.HotbarSlots do
								if not Module.HotbarSlots[i] then
									-- Slot 2 reserved if has tablet pass OR (no tablet pass but has sniper pass)
									-- Slot 3 reserved if has both tablet and sniper passes
									local slot2Reserved = hasTabletPass() or (not hasTabletPass() and hasSniperPass())
									local slot3Reserved = hasTabletPass() and hasSniperPass()
									local reserved = (i == InventoryConfig.TabletSlot and slot2Reserved) 
										or (i == InventoryConfig.SniperSlot and slot3Reserved)
									if not reserved then
										emptySlot = i
										break
									end
								end
							end
						end

						if emptySlot then
							Module:SetHotbarSlot(emptySlot, uid)
						elseif hotbarSlot then
							local slotIndex = hotbarSlot.LayoutOrder
							if slotIndex >= 1 and slotIndex <= InventoryConfig.HotbarSlots then
								if slotIndex ~= InventoryConfig.SlapperSlot then
									Module:SetHotbarSlot(slotIndex, uid)
								end
							end
						end
						renderHotbar()
						renderExpanded()
					end
				end
			else
				-- Was a click (no drag) - drag clone blocked MouseButton1Click, so fire equip manually
				local itemData = Module:GetItem(uid)
				if itemData then
					onItemClicked(uid, itemData)
				end
			end
			
			dragClone:Destroy()
		end)
	end)
end

--[[
	Setup drag from hotbar to expanded (Tsunami: setup_drag_to_inventory)
	Only processes drop if user actually DRAGGED (moved) - clicks still equip via MouseButton1Click
]]
setupDragToExpanded = function(frame: Frame, uid: string, button: GuiButton)
	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		
		if not ExpandedFrame or not ExpandedFrame.Visible then
			return
		end
		
		local container = BackpackUI or frame.Parent
		if not container then return end
		
		local startPos = typeof(input.Position) == "Vector3" and Vector2.new(input.Position.X, input.Position.Y) or input.Position
		local didDrag = false
		
		local dragClone = createDragClone(frame)
		local containerPos = container.AbsolutePosition
		local framePosLocal = Vector2.new(frame.AbsolutePosition.X, frame.AbsolutePosition.Y) - containerPos
		local localMouse = toGuiPos(input.Position) - containerPos
		local offset = localMouse - framePosLocal
		local dragging = true
		
		local function updateDrag(pos: Vector2)
			local pos2 = typeof(pos) == "Vector3" and Vector2.new(pos.X, pos.Y) or pos
			local localPos = toGuiPos(pos2) - containerPos - offset
			dragClone.Position = UDim2.fromOffset(localPos.X, localPos.Y)
			if not didDrag then
				local dx = math.abs(pos2.X - startPos.X)
				local dy = math.abs(pos2.Y - startPos.Y)
				if dx > DRAG_THRESHOLD or dy > DRAG_THRESHOLD then
					didDrag = true
				end
			end
		end
		
		updateDrag(input.Position)
		
		local moveConn = UserInputService.InputChanged:Connect(function(moveInput)
			if not dragging then return end
			if moveInput.UserInputType ~= Enum.UserInputType.MouseMovement and moveInput.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			updateDrag(moveInput.Position)
		end)
		
		local endConn
		endConn = UserInputService.InputEnded:Connect(function(endInput)
			if endInput.UserInputType ~= input.UserInputType then return end
			dragging = false
			
			if moveConn then moveConn:Disconnect() end
			if endConn then endConn:Disconnect() end
			
			if didDrag then
				-- Slapper and gamepass tools cannot be moved out of hotbar
				if not isSlapper(uid) and not isReservedGamepassTool(uid) then
					local pointGui = toGuiPos(endInput.Position)
					local pointRaw = typeof(endInput.Position) == "Vector3" and Vector2.new(endInput.Position.X, endInput.Position.Y) or endInput.Position
					if isPointInExpanded(pointGui) or isPointInExpanded(pointRaw) then
						for i = 1, InventoryConfig.HotbarSlots do
							if Module.HotbarSlots[i] == uid then
								Module.HotbarSlots[i] = nil
								break
							end
						end
						Module.HotbarChanged:Fire()
						renderHotbar()
						renderExpanded()
					end
				end
			else
				-- Was a click (no drag) - drag clone blocked MouseButton1Click, so fire equip manually
				local itemData = Module:GetItem(uid)
				if itemData then
					onItemClicked(uid, itemData)
				end
			end

			dragClone:Destroy()
		end)
	end)
end

--[[
	Renders the hotbar
]]
renderHotbar = function()
	if not HotbarFrame then 
		return 
	end
	
	-- Clear existing slots (but NOT the Backpack button frame)
	for _, child in ipairs(HotbarFrame:GetChildren()) do
		if (child:IsA("Frame") or child:IsA("ImageButton")) and child.Name ~= "Backpack" then
			child:Destroy()
		end
	end
	
	local hotbarSlots = Module:GetHotbarSlots()
	
	-- Create slot for each hotbar position
	for i = 1, InventoryConfig.HotbarSlots do
		local uid = hotbarSlots[i]
		
		if uid then
			local itemData = Module:GetItem(uid)
			if itemData then
				local slot = createItemSlot(itemData, uid, true)
				if slot then
					slot.LayoutOrder = i
					slot.Parent = HotbarFrame
					
					-- Set hotbar index number
					local hotbarIndex = slot:FindFirstChild("HotbarIndex", true)
					if hotbarIndex and hotbarIndex:IsA("TextLabel") then
						hotbarIndex.Text = tostring(i)
					end
				end
			end
		end
		-- NOTE: Don't create empty slots - only show items that exist
	end
end

--[[
	Renders the expanded grid view
	Tsunami: expanded shows ONLY items NOT in hotbar (if is_in_hotbar then continue)
]]
renderExpanded = function()
	if not GridHolder then return end
	
	-- Clear existing items
	for _, child in ipairs(GridHolder:GetChildren()) do
		if child:IsA("Frame") or child:IsA("ImageButton") then
			child:Destroy()
		end
	end
	
	-- Get inventory
	local inventory = Module:GetInventory()
	
	-- Filter: only items NOT in hotbar (Tsunami theory - hotbar items don't appear in expanded)
	local items = {}
	for uid, itemData in pairs(inventory) do
		if isInHotbar(uid) then
			continue -- Skip - already in hotbar
		end
		if SearchQuery == "" then
			table.insert(items, {uid = uid, data = itemData})
		else
			local displayName = ItemDataAccess:GetItemProperty(itemData, "DisplayName") or ""
			if string.find(string.lower(displayName), string.lower(SearchQuery)) then
				table.insert(items, {uid = uid, data = itemData})
			end
		end
	end
	
	-- Sort by rarity (Common/Rare/Epic/Legendary/Mythical/Secret/Celestial/Divine), then by name
	local rarityOrder = {
		Common = 1, Rare = 2, Epic = 3, Legendary = 4,
		Mythical = 5, Secret = 6, Unreal = 7, Celestial = 8, Divine = 9,
	}
	table.sort(items, function(a, b)
		local rarityA = ItemDataAccess:GetItemProperty(a.data, "Rarity") or "Common"
		local rarityB = ItemDataAccess:GetItemProperty(b.data, "Rarity") or "Common"
		local orderA = rarityOrder[rarityA] or 0
		local orderB = rarityOrder[rarityB] or 0
		
		if orderA ~= orderB then
			return orderA > orderB
		end
		
		local nameA = ItemDataAccess:GetItemProperty(a.data, "DisplayName") or ""
		local nameB = ItemDataAccess:GetItemProperty(b.data, "DisplayName") or ""
		return nameA < nameB
	end)
	
	-- Create slots
	for _, item in ipairs(items) do
		local slot = createItemSlot(item.data, item.uid, false)
		if slot then
			slot.Parent = GridHolder
		end
	end
end

--[[
	Toggles expanded view (frame-style: slide from off-screen like Client_Frames)
]]
local function toggleExpanded()
	IsExpanded = not IsExpanded
	
	if not ExpandedFrame then return end
	
	-- Store origin position on first use
	if not ExpandOriginPosition then
		ExpandOriginPosition = ExpandedFrame.Position
	end
	
	local originPos = ExpandOriginPosition
	local collapsedPos = getExpandCollapsedPosition()
	if not collapsedPos then return end
	
	-- Cancel any ongoing tween
	if ExpandTween then
		ExpandTween:Cancel()
		ExpandTween = nil
	end
	
	if IsExpanded then
		-- Open: start off-screen below, slide up to origin
		ExpandedFrame.Position = collapsedPos
		ExpandedFrame.Visible = true
		ExpandTween = TweenService:Create(ExpandedFrame, TweenInfo.new(EXPAND_OPEN_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = originPos
		})
		ExpandTween.Completed:Connect(function()
			if ExpandTween then ExpandTween = nil end
		end)
		ExpandTween:Play()
		renderExpanded()
	else
		-- Close: slide down off-screen, then hide
		local wasClosing = true
		ExpandTween = TweenService:Create(ExpandedFrame, TweenInfo.new(EXPAND_CLOSE_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
			Position = collapsedPos
		})
		ExpandTween.Completed:Connect(function()
			if ExpandTween then ExpandTween = nil end
			if wasClosing and not IsExpanded and ExpandedFrame then
				ExpandedFrame.Visible = false
				ExpandedFrame.Position = originPos -- Reset for next open
			end
		end)
		ExpandTween:Play()
	end
end

--[[
	Handles search input
]]
local function onSearchChanged()
	if SearchBox then
		SearchQuery = SearchBox.Text
		renderExpanded()
	end
end

--[[
	Uses/equips item in hotbar slot
]]
local function useHotbarSlot(slotIndex: number)
	if ClickCD then return end
	ClickCD = true
	task.delay(0.15, function() ClickCD = false end)
	
	local itemData = Module:GetHotbarItem(slotIndex)
	if not itemData then return end
	
	local hotbarSlots = Module:GetHotbarSlots()
	local uid = hotbarSlots[slotIndex]
	if not uid then return end
	
	-- Play click animation (same as button click) for visual feedback
	if HotbarFrame then
		local slotFrame = HotbarFrame:FindFirstChild(uid)
		if slotFrame and slotFrame:IsA("Frame") then
			local container = slotFrame:FindFirstChild("Container")
			if container then
				playSlotClickAnimation(container)
			end
		end
	end
	
	onItemClicked(uid, itemData)
end

--[[
	Handles keyboard shortcuts (1-6 for hotbar, B for backpack)
]]
local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.One then
		useHotbarSlot(1)
	elseif input.KeyCode == Enum.KeyCode.Two then
		useHotbarSlot(2)
	elseif input.KeyCode == Enum.KeyCode.Three then
		useHotbarSlot(3)
	elseif input.KeyCode == Enum.KeyCode.Four then
		useHotbarSlot(4)
	elseif input.KeyCode == Enum.KeyCode.Five then
		useHotbarSlot(5)
	elseif input.KeyCode == Enum.KeyCode.Six then
		useHotbarSlot(6)
	elseif input.KeyCode == Enum.KeyCode.B then
		-- Animate backpack button when B is pressed
		if BackpackButton then
			playSlotClickAnimation(BackpackButton)
		end
		toggleExpanded()
	end
end


--[[
	Gets the Animator from the character's Humanoid
]]
local function getAnimator(): Animator?
	local character = Player.Character
	if not character then return nil end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	
	return animator
end

--[[
	Stops the current hold animation
]]
local function stopHoldAnimation()
	if CurrentHoldTrack and CurrentHoldTrack.IsPlaying then
		CurrentHoldTrack:Stop(0.2)
	end
	CurrentHoldTrack = nil
	CurrentHoldAnimationId = nil
end

--[[
	Plays a hold animation for the equipped item
]]
local function playHoldAnimation(animationPath: string)
	-- Don't restart if same animation is already playing
	if CurrentHoldAnimationId == animationPath and CurrentHoldTrack and CurrentHoldTrack.IsPlaying then
		return
	end
	
	stopHoldAnimation()
	
	local animator = getAnimator()
	if not animator then return end
	
	-- Resolve animation path (e.g., "Assets.PlayerAnimations.OneHandHolding")
	local pathParts = string.split(animationPath, ".")
	local current = ReplicatedStorage
	for _, part in ipairs(pathParts) do
		current = current:FindFirstChild(part)
		if not current then
			warn("⚠️ Animation not found at path:", animationPath)
			return
		end
	end
	
	-- Verify it's an Animation instance
	if not current:IsA("Animation") then
		warn("⚠️ Path does not lead to Animation instance:", animationPath)
		return
	end
	
	local track = animator:LoadAnimation(current)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play(0.2)
	
	CurrentHoldTrack = track
	CurrentHoldAnimationId = animationPath
end

--[[
	Updates the hold animation based on currently equipped item
]]
local function updateHoldAnimation()
	local currentEquipped = Player:GetAttribute("CurrentEquipped")
	
	if not currentEquipped then
		stopHoldAnimation()
		return
	end
	
	local itemData = Module.Inventory[currentEquipped]
	if not itemData then
		stopHoldAnimation()
		return
	end
	
	-- Determine animation based on item type
	local animationPath: string? = nil
	
	if itemData.Type == "Tool" then
		-- Tools: Get HoldAnimation from tool config
		local toolConfig = Shared_Tools.List[itemData.ConfigName]
		if toolConfig and toolConfig.HoldAnimation then
			animationPath = toolConfig.HoldAnimation
		end
	elseif itemData.Type == "Brainrot" then
		-- Brainrots: Use global two-hand hold animation
		animationPath = Shared_Brainrots.HoldAnimation
	elseif itemData.Type == "LuckyBlock" then
		-- Lucky blocks: Use global two-hand hold animation (same as brainrots)
		local Shared_LuckyBlocks = require(ReplicatedStorage.Modules.ItemConfigs.Shared_LuckyBlocks)
		animationPath = Shared_LuckyBlocks.HoldAnimation
	end
	
	if animationPath then
		playHoldAnimation(animationPath)
	else
		stopHoldAnimation()
	end
end

--[[
	Initialize replica listeners
]]
function Module:Init()
	-- Get Client_Sounds from Library (set by init.client.lua)
	Client_Sounds = self.Client_Sounds
	
	-- Helper to set player replica
	local function setPlayerReplica(replica)
		if replica.Tags.UserId and replica.Tags.UserId == Player.UserId then
			Module.PlayerReplica = replica
			Module.Inventory = replica.Data.Inventory or {}
			
			-- Initialize hotbar: slapper in slot 1, then fill empty slots
			for i = 1, InventoryConfig.HotbarSlots do
				Module.HotbarSlots[i] = nil
			end
			fillEmptyHotbarSlots()
			
			Module.IsReady = true
			
			-- Listen to inventory changes (items added/removed)
			replica:ListenToChange({"Inventory"}, function(newInventory)
				Module.Inventory = newInventory or {}
				
				-- Clean up hotbar slots that reference removed items
				for i = 1, InventoryConfig.HotbarSlots do
					local uid = Module.HotbarSlots[i]
					if uid and not Module.Inventory[uid] then
						Module.HotbarSlots[i] = nil
					end
				end
				
				-- Only fill empty slots (don't reshuffle existing items)
				fillEmptyHotbarSlots()
				
				-- Clean up attributes for removed items
				local pickedUID = Player:GetAttribute("SlotPlacablePicked")
				local equippedUID = Player:GetAttribute("CurrentEquipped")
				if pickedUID and not Module.Inventory[pickedUID] then
					Player:SetAttribute("SlotPlacablePicked", nil)
					updateSelectionStroke()
				end
				if equippedUID and not Module.Inventory[equippedUID] then
					Player:SetAttribute("CurrentEquipped", nil)
					updateSelectionStroke()
				end
				
				Module.InventoryChanged:Fire()
				Module.HotbarChanged:Fire()
			end)

			-- When Passes change (e.g. buy Tablet/Sniper), do a FULL re-layout so 2/3 become reserved and items there move to 4-6
			replica:ListenToChange({"Passes"}, function()
				-- Clean up hotbar slots that reference removed items
				for i = 1, InventoryConfig.HotbarSlots do
					local uid = Module.HotbarSlots[i]
					if uid and not Module.Inventory[uid] then
						Module.HotbarSlots[i] = nil
					end
				end
				
				-- Full reshuffle when passes change (reserves slots 2/3 for Tablet/Sniper)
				shiftHotbarSlots()
				fillEmptyHotbarSlots()
				
				Module.InventoryChanged:Fire()
				Module.HotbarChanged:Fire()
			end)
			
			-- Fire initial update
			Module.InventoryChanged:Fire()
			Module.HotbarChanged:Fire()
			
			return true
		end
		return false
	end
	
	-- If data already received, find existing replica
	if ReplicaController.InitialDataReceived then
		for _, replica in pairs(ReplicaController._replicas) do
			if replica.Class == "PlayerData" then
				if setPlayerReplica(replica) then
					break
				end
			end
		end
	end
	
	-- Also listen for future replicas
	ReplicaController.ReplicaOfClassCreated("PlayerData", function(replica)
		setPlayerReplica(replica)
	end)
	
	-- Wait for data to be ready before setting up UI
	Module:WaitUntilReady()
	
	-- Find UI elements
	local backpackUI = PlayerGui:WaitForChild("Backpack", 30)
	if not backpackUI then
		warn("⚠️  Backpack UI not found")
		return
	end
	
	BackpackUI = backpackUI
	HotbarFrame = BackpackUI:FindFirstChild("Hotbar")
	ExpandedFrame = BackpackUI:FindFirstChild("Expanded")
	if ExpandedFrame then
		ExpandOriginPosition = ExpandedFrame.Position
		
		-- Adjust size for mobile devices (smaller height)
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			ExpandedFrame.Size = UDim2.new(0, 627, 0, 250)
		end
	end
	GridHolder = ExpandedFrame and ExpandedFrame:FindFirstChild("GridHolder")
	SearchBox = ExpandedFrame and ExpandedFrame:FindFirstChild("SearchBar")
	if SearchBox then
		SearchBox = SearchBox:FindFirstChild("TextBox")
	end
	
	-- Find templates (need both BrainrotTemplate and ItemTemplate)
	local brainrotTemplate = nil
	local itemTemplate = nil
	
	if HotbarFrame then
		for _, child in ipairs(HotbarFrame:GetChildren()) do
			if child:IsA("Frame") then
				if child.Name == "BrainrotTemplate" then
					brainrotTemplate = child
					child.Parent = script
					child.Visible = true
				elseif child.Name == "ItemTemplate" or child.Name == "Template" then
					itemTemplate = child
					child.Parent = script
					child.Visible = true
				end
			end
		end
	end
	
	-- Set references (BrainrotTemplate for brainrots, ItemTemplate for tools/consumables)
	HotbarSlotTemplate = brainrotTemplate
	GridSlotTemplate = itemTemplate
	
	if not HotbarSlotTemplate then
		warn("⚠️ BrainrotTemplate not found in HotbarFrame")
	end
	if not GridSlotTemplate then
		warn("⚠️ ItemTemplate not found in HotbarFrame")
	end
	
	-- Connect search box
	if SearchBox and SearchBox:IsA("TextBox") then
		SearchBox:GetPropertyChangedSignal("Text"):Connect(onSearchChanged)
	end
	
	-- Find and connect backpack button in Hotbar
	local backpackFrame = HotbarFrame and HotbarFrame:FindFirstChild("Backpack")
	if backpackFrame then
		local container = backpackFrame:FindFirstChild("Container")
		if container then
			local backpackButton = container:FindFirstChild("ImageButton")
			if backpackButton and backpackButton:IsA("ImageButton") then
				BackpackButton = container -- Store the container for animation
				backpackButton.Activated:Connect(function()
					playSlotClickAnimation(BackpackButton)
					toggleExpanded()
				end)
			else
				warn("⚠️ ImageButton not found in Backpack.Container")
			end
		else
			warn("⚠️ Container not found in Backpack frame")
		end
	else
		warn("⚠️ Backpack frame not found in Hotbar")
	end
	
	-- Listen to inventory changes
	Module.InventoryChanged.Event:Connect(function()
		renderHotbar()
		if IsExpanded then
			renderExpanded()
		end
	end)
	
	Module.HotbarChanged.Event:Connect(function()
		renderHotbar()
	end)
	
	-- Listen to equipped state and placement state
	Player:GetAttributeChangedSignal("CurrentEquipped"):Connect(function()
		-- Clear SelectedUID if CurrentEquipped was cleared
		local currentEquipped = Player:GetAttribute("CurrentEquipped")
		if not currentEquipped then
			SelectedUID = nil
		end
		
		updateSelectionStroke()
		updateHoldAnimation() -- Update hold animation when equipping/unequipping
		-- No need to re-render expanded - selection strokes are updated directly above
	end)
	
	Player:GetAttributeChangedSignal("SlotPlacablePicked"):Connect(function()
		updateSelectionStroke()
	end)
	
	-- Handle lucky block opening (click while holding)
	local UserInputService = game:GetService("UserInputService")
	local lastClickTime = 0
	local CLICK_COOLDOWN = 0.5
	
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		local isClick = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		
		if not isClick then return end
		if os.clock() - lastClickTime < CLICK_COOLDOWN then return end
		
		local slotPicked = Player:GetAttribute("SlotPlacablePicked")
		if not slotPicked then return end
		
		-- Only open if this lucky block is actually equipped (prevents opening when user switched to slapper/tool)
		if Player:GetAttribute("CurrentEquipped") ~= slotPicked then return end
		
		local item = Module.Inventory[slotPicked]
		if not item or item.Type ~= "LuckyBlock" then return end
		
		lastClickTime = os.clock()
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local ItemHandler = Events and Events:FindFirstChild("ItemHandler")
		if ItemHandler then
			ItemHandler:FireServer("OpenLuckyBlock", slotPicked)
		end
	end)
	
	-- Handle character respawn
	Player.CharacterAdded:Connect(function(newCharacter)
		stopHoldAnimation() -- Stop any playing animations
		task.wait(0.1) -- Wait for character to load
		updateHoldAnimation() -- Re-apply hold animation if item is equipped
	end)
	
	-- Keyboard shortcuts
	UserInputService.InputBegan:Connect(onInputBegan)
	
	-- Listen for server auto-equip requests (when saving items)
	local Events = ReplicatedStorage:FindFirstChild("Events")
	local InventoryHandler = Events and Events:FindFirstChild("InventoryHandler")
	if InventoryHandler then
		InventoryHandler.OnClientEvent:Connect(function(action, data)
			if action == "AutoEquip" then
				local uid = data
				if uid and Module.Inventory[uid] then
					-- Equip through client (proper animation handling)
					local itemData = Module.Inventory[uid]
					onItemClicked(uid, itemData)
				end
			end
		end)
	end
	
	-- Initial render
	renderHotbar()
	
	updateHoldAnimation()
end

return Module
