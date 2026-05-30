--// BrainrotVisuals - Server-side brainrot visual management
--// Handles models, billboards, animations - all server-rendered for replication

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
local Shared_Rarity = require(ReplicatedStorage.Modules.Gameplay.Shared_Rarity)
local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
local Shared_RebirthRewards = require(ReplicatedStorage.Modules.Settings.Shared_RebirthRewards)
local Shared_ModifierHandler = require(ReplicatedStorage.Modules.Gameplay.Shared_ModifierHandler)

local BrainrotVisuals = {}

local function roundToStep(value: number, step: number): number
	return math.floor(value / step + 0.5) * step
end

-- Keep economy numbers clean when multipliers apply (avoid decimals like 388.49K/s).
local function roundEconomy(value: number): number
	if value <= 0 then
		return 0
	end
	
	if value >= 1e12 then
		return roundToStep(value, 1e10) -- 10B
	elseif value >= 1e10 then
		return roundToStep(value, 1e8) -- 100M
	elseif value >= 1e9 then
		return roundToStep(value, 1e7) -- 10M
	elseif value >= 1e8 then
		return roundToStep(value, 1e6) -- 1M
	elseif value >= 1e7 then
		return roundToStep(value, 1e5) -- 100K
	elseif value >= 1e6 then
		return roundToStep(value, 1e4) -- 10K
	elseif value >= 1e5 then
		return roundToStep(value, 1e3) -- 1K
	elseif value >= 1e4 then
		return roundToStep(value, 1e2) -- 100
	elseif value >= 1e3 then
		return roundToStep(value, 1e1) -- 10
	else
		return math.floor(value + 0.5)
	end
end

local function formatMultiplier(mult: number): string
	local rounded = math.floor(mult * 10 + 0.5) / 10
	local s = tostring(rounded)
	if s:sub(-2) == ".0" then
		s = s:sub(1, -3)
	end
	return s
end

-- Store billboard update callbacks by player
-- [player] = {callback1, callback2, ...}
local BillboardUpdateCallbacks = {}

--[[
	Updates DisplayPart visibility based on slot state
	@param slotModel Model
	@param isOccupied boolean
]]
local function updateDisplayPartVisibility(slotModel: Model, isOccupied: boolean)
	local displayPart = slotModel:FindFirstChild("DisplayPart")
	local displayPartDown = slotModel:FindFirstChild("DisplayPartDown")
	
	if displayPart then
		displayPart.Transparency = isOccupied and 0 or 1
		displayPart.CanCollide = isOccupied
		
		local cashDisplay = displayPart:FindFirstChild("CashDisplay")
		if cashDisplay and cashDisplay:IsA("SurfaceGui") then
			cashDisplay.Enabled = isOccupied
		end
	end
	
	if displayPartDown then
		displayPartDown.Transparency = isOccupied and 0 or 1
		displayPartDown.CanCollide = isOccupied
	end
end

local function isBoundsPart(part: BasePart): boolean
	if part.Name == "ModifierVFX" then
		return false
	end
	if part:FindFirstAncestorOfClass("BillboardGui") then
		return false
	end
	return true
end

local function getModelTopCenterWorld(brainrotModel: Model): Vector3
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local found = false

	for _, desc in brainrotModel:GetDescendants() do
		if desc:IsA("BasePart") and isBoundsPart(desc) then
			found = true
			local cf = desc.CFrame
			local sx, sy, sz = desc.Size.X * 0.5, desc.Size.Y * 0.5, desc.Size.Z * 0.5
			for ix = -1, 1, 2 do
				for iy = -1, 1, 2 do
					for iz = -1, 1, 2 do
						local p = cf:PointToWorldSpace(Vector3.new(sx * ix, sy * iy, sz * iz))
						minX = math.min(minX, p.X)
						minY = math.min(minY, p.Y)
						minZ = math.min(minZ, p.Z)
						maxX = math.max(maxX, p.X)
						maxY = math.max(maxY, p.Y)
						maxZ = math.max(maxZ, p.Z)
					end
				end
			end
		end
	end

	if not found then
		local bbCF, bbSize = brainrotModel:GetBoundingBox()
		return bbCF.Position + Vector3.new(0, bbSize.Y * 0.5, 0)
	end

	return Vector3.new((minX + maxX) * 0.5, maxY, (minZ + maxZ) * 0.5)
end

local function getBillboardAttachLocalPos(brainrotModel: Model, primary: BasePart): Vector3
	return primary.CFrame:PointToObjectSpace(getModelTopCenterWorld(brainrotModel))
end

local function setupBillboardUi(billboard: BillboardGui, scale: number)
	local contentRoot = billboard:FindFirstChildWhichIsA("Frame", false)
	if not contentRoot then
		contentRoot = billboard:FindFirstChildWhichIsA("GuiObject", false)
	end

	if contentRoot and contentRoot:IsA("GuiObject") then
		contentRoot.AnchorPoint = Vector2.new(0.5, 1)
		contentRoot.Position = UDim2.fromScale(0.5, 0)
		local uiScale = contentRoot:FindFirstChildOfClass("UIScale")
		if not uiScale then
			uiScale = Instance.new("UIScale")
			uiScale.Parent = contentRoot
		end
		uiScale.Scale = scale
		return
	end

	local uiScale = billboard:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = billboard
	end
	uiScale.Scale = scale
end

--[[
	Public function to hide display parts (for empty slots)
	@param slotModel Model
]]
function BrainrotVisuals:HideDisplayParts(slotModel: Model)
	updateDisplayPartVisibility(slotModel, false)
end

--[[
	Create brainrot model on slot
	@param slotModel Model
	@param configName string
	@param modifier string
	@return Model? - Created brainrot model
]]
function BrainrotVisuals:ApplyBillboardScale(brainrotModel: Model, level: number)
	if not brainrotModel then
		return
	end

	local scale = Shared_Brainrots:GetPlotScale(level or 1)
	local primary = brainrotModel.PrimaryPart
	if not primary then
		return
	end

	local billboard = brainrotModel:FindFirstChildWhichIsA("BillboardGui", true)
	if not billboard then
		return
	end

	billboard.Adornee = primary

	local rootUiScale = billboard:FindFirstChildOfClass("UIScale")
	if rootUiScale then
		rootUiScale:Destroy()
	end
	setupBillboardUi(billboard, scale)

	local baseOffsetY = billboard:GetAttribute("BaseStudsOffsetY")
	if type(baseOffsetY) ~= "number" then
		baseOffsetY = 0
		billboard:SetAttribute("BaseStudsOffsetY", baseOffsetY)
	end
	local nametagExtra = billboard:GetAttribute("NametagHeightExtra") or 0
	local attachPos = getBillboardAttachLocalPos(brainrotModel, primary)
	billboard.StudsOffset = attachPos + Vector3.new(0, (baseOffsetY + nametagExtra) * scale, 0)
end

function BrainrotVisuals:PositionBrainrotOnSlot(brainrotModel: Model, slotModel: Model, level: number)
	if not brainrotModel or not slotModel then
		return
	end

	local scale = Shared_Brainrots:GetPlotScale(level or 1)
	brainrotModel:ScaleTo(scale)

	local standingPart = slotModel:FindFirstChild("StandingPart")
	local primary = brainrotModel.PrimaryPart
	if standingPart and standingPart:IsA("BasePart") and primary then
		local modelHeight = primary.Size.Y
		local standingHeight = standingPart.Size.Y
		local standingPosition = standingPart.Position + Vector3.new(0, modelHeight / 2 + standingHeight / 2 + 0.05, 0)
		local standingCFrame = CFrame.lookAt(standingPosition, standingPosition + standingPart.CFrame.LookVector)
		primary.CFrame = standingCFrame
	end

	self:ApplyBillboardScale(brainrotModel, level or 1)
end

function BrainrotVisuals:CreateBrainrotModel(slotModel: Model, configName: string, modifier: string, level: number): Model?
	-- Get brainrot config
	local config = Shared_Brainrots.List[configName]
	if not config then
		warn("⚠️ Brainrot config not found: " .. configName)
		return nil
	end
	
	-- Get model WITHOUT VFX first (we'll add VFX after parenting)
	local brainrotParent = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("Brainrots")
		and ReplicatedStorage.Assets.Brainrots:FindFirstChild(configName)
	
	if not brainrotParent then
		warn("⚠️ Brainrot parent not found: " .. configName)
		return nil
	end
	
	local normalTemplate = brainrotParent:FindFirstChild("Normal")
	if not normalTemplate or not normalTemplate:IsA("Model") then
		warn("⚠️ Normal template not found: " .. configName)
		return nil
	end
	
	local brainrotModel = normalTemplate:Clone()
	brainrotModel.Name = configName
	
	-- Apply modifier visuals (textures, colors)
	Shared_ModifierHandler:ApplyModifierToModel(brainrotModel, configName, modifier or "Normal")
	
	if not brainrotModel.PrimaryPart then
		brainrotModel.PrimaryPart = brainrotModel:FindFirstChildWhichIsA("BasePart", true)
	end
	if not brainrotModel.PrimaryPart then
		warn("⚠️ No PrimaryPart in brainrot: " .. configName)
		brainrotModel:Destroy()
		return nil
	end
	
	brainrotModel.Name = "PlacedBrainrot"
	brainrotModel:SetAttribute("ConfigName", configName) -- Store for client animations
	brainrotModel.Parent = slotModel
	self:PositionBrainrotOnSlot(brainrotModel, slotModel, level or 1)
	
	-- IMPORTANT: Attach VFX AFTER parenting (so WeldConstraints work properly)
	Shared_ModifierHandler:AttachModifierVFX(brainrotModel, modifier or "Normal")
	
	return brainrotModel
end

--[[
	Play idle animation on brainrot
	CLIENT-SIDE NOW: Deprecated - animations handled client-side for performance
	@param brainrotModel Model
	@param configName string
]]
function BrainrotVisuals:PlayIdleAnimation(brainrotModel: Model, configName: string)
	-- DEPRECATED: Animations now handled client-side via Client_BrainrotAnimations
	-- Client detects plot tags and plays animations only when in range
	return
end

--[[
	Create billboard above brainrot head
	@param brainrotModel Model
	@param slotModel Model
	@param configName string
	@param modifier string
	@param level number
	@param ownerPlayer Player? - Owner to apply friend boost
]]
function BrainrotVisuals:CreateBillboard(brainrotModel: Model, slotModel: Model, configName: string, modifier: string, level: number, ownerPlayer: Player?)
	local config = Shared_Brainrots.List[configName]
	if not config then return end
	
	-- Ensure model has PrimaryPart
	if not brainrotModel:IsA("Model") or not brainrotModel.PrimaryPart then
		warn("⚠️ Cannot create billboard - model must have PrimaryPart")
		return
	end
	
	-- Get billboard template (Tsunami: Assets.BrainrotBillboard)
	local billboardTemplate = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("BrainrotBillboard")
	
	if not billboardTemplate then
		warn("⚠️ Billboard template not found at Assets.BrainrotBillboard")
		return
	end
	
	local billboard = billboardTemplate:Clone()
	billboard.Adornee = brainrotModel.PrimaryPart
	billboard.Parent = brainrotModel
	
	-- Check for NametagHeight attribute (custom offset for this model)
	local nametagHeight = brainrotModel:GetAttribute("NametagHeight")
	
	-- If not found on clone, check original asset in ReplicatedStorage
	if not nametagHeight then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local brainrots = assets and assets:FindFirstChild("Brainrots")
		local brainrotParent = brainrots and brainrots:FindFirstChild(configName)
		if brainrotParent then
			local normalModel = brainrotParent:FindFirstChild("Normal")
			if normalModel then
				nametagHeight = normalModel:GetAttribute("NametagHeight")
			end
		end
	end
	
	billboard:SetAttribute("BaseStudsOffsetY", billboard.StudsOffset.Y)
	if nametagHeight then
		billboard:SetAttribute("NametagHeightExtra", nametagHeight)
	end
	
	-- Update DisplayName
	local displayName = billboard:FindFirstChild("DisplayName", true)
	if displayName and displayName:IsA("TextLabel") then
		displayName.Text = config.DisplayName
	end
	
	-- Update Rarity (use Shared_Rarity for consistency)
	local rarityLabel = billboard:FindFirstChild("Rarity", true)
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		local rarityInfo = Shared_Rarity:GetRarityInfo(config.Rarity)
		if rarityInfo then
			rarityLabel.Text = config.Rarity  -- Display name (e.g., "Common", "Rare")
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
	
	-- Update modifier label (UI child named "Modifier")
	local modifierLabel = billboard:FindFirstChild("Modifier", true)
	if modifierLabel and modifierLabel:IsA("TextLabel") then
		if modifier ~= "Normal" then
			modifierLabel.Visible = true
			local specialData = Shared_Rarity.ModifierData[modifier]
			if specialData then
				modifierLabel.Text = specialData.DisplayName
				local gradient = modifierLabel:FindFirstChildOfClass("UIGradient")
				if gradient and specialData.Color then
					gradient.Color = specialData.Color[1]
					gradient.Rotation = specialData.Color[2]
				end
			end
		else
			modifierLabel.Visible = false
		end
	end
	
	-- Update Cash/s (dynamic - WITH friend boost AND rebirth multiplier applied)
	local cashLabel = billboard:FindFirstChild("Cash", true)
	if cashLabel and cashLabel:IsA("TextLabel") then
		local function updateCashPerSecond()
			local currentLevel = slotModel:GetAttribute("Level") or level
			-- Base production (rounded) from brainrot economy.
			local basePerSec = Shared_Brainrots:GetCashPerSecond(configName, currentLevel, modifier)

			-- Total multiplier: rebirths supply the base (incl. 1x), everything else adds on top.
			-- e.g. 10 rebirths = 5x, +CashBoost = +2 -> 7x
			local totalMultiplier = 1

			if ownerPlayer then
				local Server_Data = require(script.Parent.Parent.Core.Server_Data)

				-- Rebirth multiplier is the anchor (already includes the 1x base)
				local rebirths = Server_Data:GetValue(ownerPlayer, "Rebirths") or 0
				totalMultiplier = Shared_RebirthRewards:GetCashMultiplier(rebirths)

				-- CashBoost gamepass: +2 (goes from Nx → N+2x)
				local data = Server_Data:GetData(ownerPlayer)
				if data and data.Passes and data.Passes.CashBoost == true then
					totalMultiplier = totalMultiplier + 2
				end

				-- Friend boost: percentage on top (e.g. 3 friends at 10% each = +0.3)
				local friendBoostPercent = ownerPlayer:GetAttribute("FriendCashBoost") or 0
				totalMultiplier = totalMultiplier + (friendBoostPercent / 100)
			end

			local boostedPerSec = roundEconomy(basePerSec * totalMultiplier)
			cashLabel.Text = "$" .. Shared_Shorten:Number(boostedPerSec) .. "/s"
		end
		
		updateCashPerSecond()
		slotModel:GetAttributeChangedSignal("Level"):Connect(updateCashPerSecond)
		
		-- Update when owner's data changes
		if ownerPlayer then
			-- Store callback for rebirth updates
			if not BillboardUpdateCallbacks[ownerPlayer] then
				BillboardUpdateCallbacks[ownerPlayer] = {}
			end
			table.insert(BillboardUpdateCallbacks[ownerPlayer], updateCashPerSecond)
			
			-- Friend boost changes
			ownerPlayer:GetAttributeChangedSignal("FriendCashBoost"):Connect(updateCashPerSecond)
		end
	end

	self:ApplyBillboardScale(brainrotModel, level or 1)
end

--[[
	Create all visuals for a brainrot on a slot
	@param plotData table
	@param slotID number
	@param slotModel Model
	@param slotData table - {ConfigName, Modifier, Level, CashToCollect}
]]
function BrainrotVisuals:CreateBrainrotOnSlot(plotData: table, slotID: number, slotModel: Model, slotData: table)
	-- Clean up any existing brainrot first (prevent duplicates)
	if plotData.Slots[slotID].PlacedBrainrot then
		plotData.Slots[slotID].PlacedBrainrot:Destroy()
		plotData.Slots[slotID].PlacedBrainrot = nil
	end
	
	local existingBrainrot = slotModel:FindFirstChild("PlacedBrainrot")
	if existingBrainrot then
		existingBrainrot:Destroy()
	end
	
	-- Show DisplayPart
	updateDisplayPartVisibility(slotModel, true)
	
	-- Create brainrot model
	local brainrotModel = self:CreateBrainrotModel(slotModel, slotData.ConfigName, slotData.Modifier, slotData.Level or 1)
	if not brainrotModel then return end
	
	plotData.Slots[slotID].PlacedBrainrot = brainrotModel
	
	-- Add plot tag for client-side animation management
	-- Find plotID from slot model's parent hierarchy (slotModel -> Floor0 -> Plot#)
	local plotModel = slotModel.Parent and slotModel.Parent.Parent
	if plotModel and plotModel.Name:match("^Plot%d+$") then
		CollectionService:AddTag(brainrotModel, plotModel.Name .. "_Brainrot")
	end
	
	-- Play idle animation (deprecated - now client-side)
	self:PlayIdleAnimation(brainrotModel, slotData.ConfigName)
	
	-- Create billboard (pass owner for friend boost)
	self:CreateBillboard(brainrotModel, slotModel, slotData.ConfigName, slotData.Modifier, slotData.Level or 1, plotData.Owner)
end

--[[
	Destroy brainrot visuals on a slot
	@param plotData table
	@param slotID number
	@param slotModel Model
]]
function BrainrotVisuals:DestroyBrainrotOnSlot(plotData: table, slotID: number, slotModel: Model)
	-- Destroy brainrot model
	if plotData.Slots[slotID].PlacedBrainrot then
		plotData.Slots[slotID].PlacedBrainrot:Destroy()
		plotData.Slots[slotID].PlacedBrainrot = nil
	end
	
	-- Hide DisplayPart
	updateDisplayPartVisibility(slotModel, false)
end

--[[
	Update all billboard displays for a player (called on rebirth, gamepass purchase, etc.)
	@param player Player
]]
function BrainrotVisuals:UpdateAllBillboardsForPlayer(player: Player)
	local callbacks = BillboardUpdateCallbacks[player]
	if callbacks then
		for i, callback in ipairs(callbacks) do
			callback()
		end
	end
end

--[[
	Clean up billboard callbacks when player leaves
	@param player Player
]]
function BrainrotVisuals:CleanupPlayer(player: Player)
	BillboardUpdateCallbacks[player] = nil
end

return BrainrotVisuals
