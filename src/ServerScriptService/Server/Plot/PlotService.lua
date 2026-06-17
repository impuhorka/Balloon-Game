--// PlotService - Professional plot management orchestrator
--// Handles plot claiming, ownership, spawning, and coordinates other services

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local BalloonRigKit = require(ReplicatedStorage.Modules.Gameplay.BalloonRigKit)
local Shared_RebirthRewards = require(ReplicatedStorage.Modules.Settings.Shared_RebirthRewards)
local Shared_IndexRewards = require(ReplicatedStorage.Modules.Gameplay.Shared_IndexRewards)
local Shared_PlotSkins = require(ReplicatedStorage.Modules.Gameplay.Shared_PlotSkins)

local PlotService = {}

-- Dependencies (injected at Init)
local DataService
local SlotService
local CashSystem
local BrainrotVisuals

-- Configuration
local CONFIG = {
	TotalPlots = 6,
	BaseSlots = 10,
	MaxSlots = 50,
	SlotsPerFloor = 10,
	
	-- Slot positions relative to plot's TeleportPart
	SlotsRelativeCFrame = {
		[1]  = CFrame.new(14.8, -5.63, 1.97, 0,0,1, 0,1,0, -1,0,0),
		[2]  = CFrame.new(14.8, -5.63, -10.53, 0,0,1, 0,1,0, -1,0,0),
		[3]  = CFrame.new(14.8, -5.63, -23, 0,0,1, 0,1,0, -1,0,0),
		[4]  = CFrame.new(14.8, -5.63, -35.53, 0,0,1, 0,1,0, -1,0,0),
		[5]  = CFrame.new(14.8, -5.63, -48, 0,0,1, 0,1,0, -1,0,0),
		[6]  = CFrame.new(-14.8, -5.63, 1.97, 0,0,-1, 0,1,0, 1,0,0),
		[7]  = CFrame.new(-14.8, -5.63, -10.53, 0,0,-1, 0,1,0, 1,0,0),
		[8]  = CFrame.new(-14.8, -5.63, -23, 0,0,-1, 0,1,0, 1,0,0),
		[9]  = CFrame.new(-14.8, -5.63, -35.53, 0,0,-1, 0,1,0, 1,0,0),
		[10] = CFrame.new(-14.8, -5.63, -48, 0,0,-1, 0,1,0, 1,0,0),
	},
}

-- Plot registry: [PlotID] = {Owner, Model, Slots}
PlotService.Plots = {}

--[[
	Initialize with dependencies
	@param dependencies table - {DataService, SlotService, CashSystem}
]]
function PlotService:Init(dependencies)
	DataService = dependencies.DataService
	SlotService = dependencies.SlotService
	CashSystem = dependencies.CashSystem
	BrainrotVisuals = dependencies.BrainrotVisuals
	
	-- Initialize plot registry
	for plotID = 1, CONFIG.TotalPlots do
		self.Plots[plotID] = {
			Owner = nil,
			Model = nil,
			Slots = {},
			FloorModels = {}, -- Only store upper floors (Floor1, Floor2, etc)
		}
	end
end

--[[
	Get plots folder from workspace
	@return Folder?
]]
local function getPlotsFolder()
	local game = Workspace:WaitForChild("Game", 10)
	if not game then return nil end
	return game:WaitForChild("Plots", 10)
end

--[[
	Find an available plot (unclaimed)
	@return number? - Plot ID or nil
]]
local function findAvailablePlot(plots)
	for plotID = 1, CONFIG.TotalPlots do
		if not plots[plotID] or not plots[plotID].Owner then
			return plotID
		end
	end
	return nil
end

--[[
	Get the plot a player owns
	@param player Player
	@return number? - Plot ID or nil
]]
function PlotService:GetPlayerPlot(player: Player): number?
	for plotID, plotData in pairs(self.Plots) do
		if plotData.Owner == player then
			return plotID
		end
	end
	return nil
end

--[[
	Get plot data for a player
	@param player Player
	@return table? - Plot data or nil
]]
function PlotService:GetPlayerPlotData(player: Player): table?
	local plotID = self:GetPlayerPlot(player)
	if plotID then
		return self.Plots[plotID]
	end
	return nil
end

--[[
	Floor parent on a plot: Map folder if present, otherwise the plot model itself
	(supports Plot.Map.Floor0 and Plot.Floor0 layouts).
]]
local function getPlotFloorContainer(plotModel: Model): Instance
	local map = plotModel:FindFirstChild("Map")
	if map then
		return map
	end
	for _, child in plotModel:GetChildren() do
		if string.lower(child.Name) == "map" then
			return child
		end
	end
	return plotModel
end

local function getBaseFloor(plotModel: Model): Instance?
	return getPlotFloorContainer(plotModel):FindFirstChild("Floor0")
end

-- Resolve plot skin key for template lookup (Floor0_<key>, AdditionalFloor_<key> in Assets.PlotSkins).
local function getSkinKey(player: Player, equippedFloorKey: string?): string
	local equipped = equippedFloorKey
	if equipped == nil then
		if not player or not DataService then
			return "Default"
		end
		equipped = DataService:GetValue(player, "EquippedIndexFloor")
	end
	local floorKey = (equipped == "Default" or not equipped) and "Default" or equipped
	return Shared_IndexRewards:GetSkinKey(floorKey)
end

local function getSkinPivot(inst: Instance): CFrame
	if inst:IsA("Model") then
		return inst:GetPivot()
	end
	if inst:IsA("BasePart") then
		return inst.CFrame
	end
	if inst:IsA("Folder") then
		local sum = Vector3.zero
		local count = 0
		for _, d in inst:GetDescendants() do
			if d:IsA("BasePart") then
				sum += d.Position
				count += 1
			end
		end
		if count > 0 then
			return CFrame.new(sum / count)
		end
	end
	return CFrame.new()
end

local function pivotSkinTemplate(template: Instance, target: CFrame)
	if template:IsA("Model") then
		template:PivotTo(target)
		return
	end
	if template:IsA("BasePart") then
		template.CFrame = target
		return
	end
	if not template:IsA("Folder") then
		return
	end
	local parts: { BasePart } = {}
	for _, d in template:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	if #parts == 0 then
		return
	end
	local center = Vector3.zero
	for _, part in parts do
		center += part.Position
	end
	center /= #parts
	local delta = target * CFrame.new(center):Inverse()
	for _, part in parts do
		part.CFrame = delta * part.CFrame
	end
end

local function cloneSkinForMap(template: Instance, mapName: string): Instance
	if template:IsA("Model") or template:IsA("Folder") then
		local clone = template:Clone()
		clone.Name = mapName
		return clone
	end

	if template:IsA("BasePart") then
		local wrapper = Instance.new("Model")
		wrapper.Name = mapName
		local part = template:Clone()
		part.Parent = wrapper
		wrapper.PrimaryPart = part
		return wrapper
	end

	local clone = template:Clone()
	clone.Name = mapName
	return clone
end

local function getPlotSkinTemplates(skinKey: string): (Instance?, Instance?)
	return Shared_PlotSkins:GetTemplates(skinKey)
end

local function getAdditionalFloorTemplateForOwner(owner): Model?
	local skinKey = getSkinKey(owner)
	local _, additional = getPlotSkinTemplates(skinKey)
	if additional then return additional end
	-- Fallback to default
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("OtherModels") and assets.OtherModels:FindFirstChild("AdditionalFloor")
end

--[[
	Apply player's equipped plot skin (Floor0 + AdditionalFloor) to their plot.
	Call on claim and when EquippedIndexFloor changes.
]]
function PlotService:ApplyPlotSkin(player: Player, equippedFloorKey: string?): boolean
	local plotData = self:GetPlayerPlotData(player)
	if not plotData or not plotData.Model then
		return false
	end

	local plotModel = plotData.Model
	local floorParent = getPlotFloorContainer(plotModel)

	local skinKey = getSkinKey(player, equippedFloorKey)
	local floor0Template, additionalTemplate = getPlotSkinTemplates(skinKey)
	if not floor0Template then
		warn(
			"[PlotService] Missing Floor0 template for skin key:",
			skinKey,
			"(expected Floor0_" .. skinKey .. ")\n",
			Shared_PlotSkins:DescribeFolder()
		)
		return false
	end

	local oldFloor0 = getBaseFloor(plotModel)
	if not oldFloor0 then
		warn("[PlotService] ApplyPlotSkin: Floor0 missing on", plotModel:GetFullName())
		return false
	end

	local targetCf = getSkinPivot(oldFloor0)
	oldFloor0:Destroy()

	local newFloor0 = cloneSkinForMap(floor0Template, "Floor0")
	if newFloor0:IsA("Model") and not newFloor0.PrimaryPart then
		newFloor0.PrimaryPart = newFloor0:FindFirstChildWhichIsA("BasePart", true)
	end
	pivotSkinTemplate(newFloor0, targetCf)
	newFloor0.Parent = floorParent

	if additionalTemplate then
		for floorIndex, floor in pairs(plotData.FloorModels) do
			if floor and floor.Parent then
				local cf = getSkinPivot(floor)
				floor:Destroy()
				local newFloor = cloneSkinForMap(additionalTemplate, "Floor" .. floorIndex)
				if newFloor:IsA("Model") and not newFloor.PrimaryPart then
					newFloor.PrimaryPart = newFloor:FindFirstChildWhichIsA("BasePart", true)
				end
				pivotSkinTemplate(newFloor, cf)
				newFloor.Parent = floorParent
				plotData.FloorModels[floorIndex] = newFloor
			end
		end
	end

	return true
end

--[[
	Initialize slot models on a plot (Tsunami-style positioning)
	@param plotModel Model
	@param plotData table
	@param player Player - Owner to check rebirth count
]]
local function initializePlotSlots(plotModel: Model, plotData: table, player: Player)
	-- Get slot template
	local slotTemplate = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("OtherModels")
		and ReplicatedStorage.Assets.OtherModels:FindFirstChild("Slot")
	
	if not slotTemplate then
		warn("⚠️ Slot template not found at ReplicatedStorage.Assets.OtherModels.Slot")
		return
	end
	
	-- Get or create slots folder
	local slotsFolder = plotModel:FindFirstChild("Slots")
	if not slotsFolder then
		slotsFolder = Instance.new("Folder")
		slotsFolder.Name = "Slots"
		slotsFolder.Parent = plotModel
	end
	
	-- Clear any pre-existing slots in the folder
	slotsFolder:ClearAllChildren()
	
	-- Calculate total slots based on rebirths
	local rebirths = DataService:GetValue(player, "Rebirths") or 0
	local totalSlots = Shared_RebirthRewards:GetTotalSlots(rebirths, CONFIG.BaseSlots)
	
	-- Create all slots (including rebirth bonus slots)
	for slotID = 1, totalSlots do
		PlotService:AddSlot(plotModel, plotData, slotID, slotTemplate)
	end
end

--[[
	Add a single slot to a plot (handles multi-floor positioning)
	@param plotModel Model
	@param plotData table
	@param slotID number
	@param slotTemplate Model
]]
function PlotService:AddSlot(plotModel: Model, plotData: table, slotID: number, slotTemplate: Model)
	local slotModel = slotTemplate:Clone()
	
	-- Calculate floor and relative position
	local slotRelativeID = ((slotID - 1) % CONFIG.SlotsPerFloor) + 1
	local floorIndex = math.floor((slotID - 1) / CONFIG.SlotsPerFloor)
	
	-- Create additional floors if needed (Floor1, Floor2, etc.)
	if floorIndex >= 1 and not plotData.FloorModels[floorIndex] then
		-- Check if floor already exists in plot
		local existingFloor = getPlotFloorContainer(plotModel):FindFirstChild("Floor" .. floorIndex)
		if existingFloor then
			plotData.FloorModels[floorIndex] = existingFloor
		else
			-- Create new floor from owner's skin (PlotSkins.AdditionalFloor_<key>) or default OtherModels.AdditionalFloor
			local floorTemplate = getAdditionalFloorTemplateForOwner(plotData.Owner)
			if not floorTemplate then
				floorTemplate = ReplicatedStorage:FindFirstChild("Assets")
					and ReplicatedStorage.Assets:FindFirstChild("OtherModels")
					and ReplicatedStorage.Assets.OtherModels:FindFirstChild("AdditionalFloor")
			end
			if floorTemplate then
				local newFloor = floorTemplate:Clone()
				newFloor.Name = "Floor" .. floorIndex
				newFloor.Parent = getPlotFloorContainer(plotModel)
				
				-- Get Floor0 as reference for all upper floors
				local floor0 = getBaseFloor(plotModel)
				
				-- Position floor above Floor0
				if floor0 then
					-- Position: Floor0 pivot + (floorIndex * floorHeight)
					local floorHeight = 20 -- Fixed height per floor
					local cf = floor0:GetPivot() + Vector3.new(0,2,0)+ Vector3.new(0, floorIndex * floorHeight, 0)
					
					-- Rotate every other floor (Floor 2, Floor 4, etc.)
					if floorIndex % 2 == 0 then
						cf = cf * CFrame.Angles(0, math.pi, 0)
					end
					
					newFloor:PivotTo(cf)
				else
					warn("⚠️ Cannot position Floor" .. floorIndex .. " - Floor0 not found")
				end
				
				plotData.FloorModels[floorIndex] = newFloor
			else
				warn("⚠️ AdditionalFloor template not found")
			end
		end
	end
	
	-- Position slot on the correct floor (Tsunami pattern)
	local teleportPart = plotModel:FindFirstChild("TeleportPart")
	if teleportPart then
		local slotRelativeCFrame = teleportPart.CFrame * CONFIG.SlotsRelativeCFrame[slotRelativeID]
		local finalCFrame
		
		if floorIndex == 0 then
			-- Base floor - use slot position directly
			finalCFrame = slotRelativeCFrame
		else
			-- Upper floor - lift slot by floor height
			local floor = plotData.FloorModels[floorIndex]
			if floor then
				-- Simple: use world X/Z from base reference, adjust Y by floor height
				local floorHeight = 25.2 * floorIndex -- Each floor is 20 studs up
				local finalPos = Vector3.new(
					slotRelativeCFrame.Position.X,
					slotRelativeCFrame.Position.Y + floorHeight,
					slotRelativeCFrame.Position.Z
				)
				finalCFrame = CFrame.new(finalPos) * slotRelativeCFrame.Rotation
			else
				-- No floor found, fallback
				finalCFrame = slotRelativeCFrame + Vector3.new(0, floorIndex * 20, 0)
			end
		end
		
		slotModel:PivotTo(finalCFrame)
	else
		warn("⚠️ TeleportPart not found for slot positioning")
	end
	
	slotModel.Name = "Slot" .. slotID
	slotModel.Parent = plotModel.Slots
	
	-- Hide DisplayPart/DisplayPartDown initially (slot is empty)
	if BrainrotVisuals then
		BrainrotVisuals:HideDisplayParts(slotModel)
	end
	
	-- Register slot
	plotData.Slots[slotID] = {
		Model = slotModel,
		Data = nil,
		PlacedBrainrot = nil,
	}
end

--[[
	Get PlayerTitle.BillboardGui and its PlayerInfo frame.
	@param plotModel Model
	@return BillboardGui?, Frame? - billboardGui, playerInfo (any may be nil)
]]
local function getPlayerTitleGui(plotModel: Model)
	local playerTitle = plotModel and plotModel:FindFirstChild("PlayerTitle")
	local billboardGui = playerTitle and playerTitle:FindFirstChild("BillboardGui")
	if not billboardGui or not billboardGui:IsA("BillboardGui") then
		return nil, nil
	end
	local playerInfo = billboardGui:FindFirstChild("PlayerInfo")
	return billboardGui, playerInfo
end

--[[
	Clear plot title UI to hide owner info (keep it hidden if not claimed).
	Call when releasing a plot so the next player sees unclaimed state.
	@param plotModel Model
]]
function PlotService:ClearPlotTitle(plotModel: Model)
	local billboardGui, playerInfo = getPlayerTitleGui(plotModel)
	if billboardGui then
		billboardGui.Enabled = false
	end
	if playerInfo then
		playerInfo.Visible = false
	end
end

--[[
	Update plot title UI with owner info (name, avatar, rebirths, cash bonus).
	Call when claiming a plot and when owner data changes (e.g. rebirth).
	@param plotModel Model
	@param player Player - plot owner
]]
function PlotService:UpdatePlotTitle(plotModel: Model, player: Player)
	local billboardGui, playerInfo = getPlayerTitleGui(plotModel)
	if not playerInfo then
		return
	end
	
	-- Enable billboard and show player info
	if billboardGui then
		billboardGui.Enabled = true
	end
	playerInfo.Visible = true

	-- Owner name
	local playerNameLabel = playerInfo:FindFirstChild("PlayerName")
	if playerNameLabel and playerNameLabel:IsA("TextLabel") then
		playerNameLabel.Text = player.DisplayName or player.Name
	end

	-- Rebirths and cash bonus from data
	local rebirths = (DataService and DataService:GetValue(player, "Rebirths")) or 0
	local rebirthsLabel = playerInfo:FindFirstChild("Rebirths")
	if rebirthsLabel and rebirthsLabel:IsA("TextLabel") then
		rebirthsLabel.Text = tostring(rebirths) .. " Rebirths"
	end
	
	-- Calculate total cash multiplier (rebirth + gamepass + plot skin)
	local cashBonusLabel = playerInfo:FindFirstChild("CashBonus")
	if cashBonusLabel and cashBonusLabel:IsA("TextLabel") then
		local rebirthMult = Shared_RebirthRewards:GetCashMultiplier(rebirths) - 1

		local data = DataService and DataService:GetData(player)
		local cashBoostBonus = (data and data.Passes and data.Passes.CashBoost) and 2 or 0

		local equippedFloor = (data and data.EquippedIndexFloor) or "Default"
		local plotSkinBonus = Shared_IndexRewards:GetCashMultiplier(equippedFloor)

		local actualMult = 1 + rebirthMult + cashBoostBonus + plotSkinBonus
		local displayMult = actualMult - 1

		cashBonusLabel.Text = "x" .. tostring(displayMult) .. " Cash"
	end

	-- Avatar (async; may fail) - Updated path to AvatarFrame.AvatarIcon
	local avatarFrame = playerInfo:FindFirstChild("AvatarFrame")
	local avatarIcon = avatarFrame and avatarFrame:FindFirstChild("AvatarIcon")
	if avatarIcon and avatarIcon:IsA("ImageLabel") then
		task.spawn(function()
			local ok, thumb = pcall(Players.GetUserThumbnailAsync, Players, player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
			if ok and thumb and avatarIcon.Parent then
				avatarIcon.Image = thumb
			end
		end)
	end
end

--[[
	Update plot title for a player's plot (e.g. after rebirth).
	No-op if player has no plot.
	@param player Player
]]
function PlotService:UpdatePlotPlayerInfo(player: Player)
	local plotData = self:GetPlayerPlotData(player)
	if plotData and plotData.Model then
		self:UpdatePlotTitle(plotData.Model, player)
	end
end

--[[
	Claim a plot for a player
	@param player Player
	@return number? - Plot ID or nil on failure
]]
function PlotService:ClaimPlot(player: Player): number?
	-- Check if player already owns a plot
	local existingPlot = self:GetPlayerPlot(player)
	if existingPlot then
		warn("⚠️ " .. player.Name .. " already owns plot " .. existingPlot)
		return existingPlot
	end
	
	-- Find available plot
	local plotID = findAvailablePlot(self.Plots)
	if not plotID then
		warn("⚠️ No available plots for " .. player.Name)
		return nil
	end
	
	-- Get plot model
	local plotsFolder = getPlotsFolder()
	if not plotsFolder then
		warn("⚠️ Plots folder not found in workspace")
		return nil
	end
	
	local plotModel = plotsFolder:FindFirstChild("Plot" .. plotID)
	if not plotModel then
		warn("⚠️ Plot model not found: Plot" .. plotID)
		return nil
	end
	
	-- Initialize plot
	local plotData = self.Plots[plotID]
	plotData.Owner = player
	plotData.Model = plotModel
	
	-- Set player attribute for client access (no datastore needed)
	player:SetAttribute("CurrentPlot", plotID)
	
	-- Set plot owner attribute for client
	plotModel:SetAttribute("OwnerUserId", player.UserId)
	
	-- Create slots (with rebirth bonuses)
	initializePlotSlots(plotModel, plotData, player)
	
	-- Load saved brainrots
	SlotService:LoadSavedBrainrots(player, plotData)

	-- Show owner on plot title (PlayerTitle.BillboardGui)
	self:UpdatePlotTitle(plotModel, player)

	-- Apply owner's equipped plot skin (Floor0 + AdditionalFloor from PlotSkins)
	self:ApplyPlotSkin(player)

	return plotID
end

--[[
	Respawn player at their plot
	@param player Player
	@param plotID number
]]
function PlotService:RespawnPlayerAtPlot(player: Player, plotID: number)
	local plotData = self.Plots[plotID]
	if not plotData or not plotData.Model then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root then
		return
	end

	local teleportPart = plotData.Model:FindFirstChild("TeleportPart")
	if not teleportPart then
		return
	end

	player:SetAttribute(BalloonRigKit.PLOT_SPAWN_READY_ATTR, false)
	character:SetAttribute(BalloonRigKit.PLOT_SPAWN_READY_ATTR, false)
	character:SetAttribute(BalloonRigKit.SETTLING_ATTR, true)

	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.AssemblyLinearVelocity = Vector3.zero
			desc.AssemblyAngularVelocity = Vector3.zero
		end
	end

	root.CFrame = teleportPart.CFrame * CFrame.new(0, 5, 0)

	task.defer(function()
		if not player.Parent or player.Character ~= character or not character.Parent then
			return
		end
		player:SetAttribute(BalloonRigKit.PLOT_SPAWN_READY_ATTR, true)
		character:SetAttribute(BalloonRigKit.PLOT_SPAWN_READY_ATTR, true)
		character:SetAttribute(BalloonRigKit.SETTLING_ATTR, false)
	end)
end

--[[
	Release a plot when player leaves
	@param player Player
]]
function PlotService:ReleasePlot(player: Player)
	local plotID = self:GetPlayerPlot(player)
	if not plotID then return end
	
	local plotData = self.Plots[plotID]

	-- Reset Floor0 to Default baseline so next claimer sees default plot
	if plotData.Model then
		local floor0Template = select(1, getPlotSkinTemplates("Default"))
		if floor0Template then
			local floorParent = getPlotFloorContainer(plotData.Model)
			local oldFloor0 = getBaseFloor(plotData.Model)
			local cf = CFrame.new()
			if oldFloor0 then
				cf = getSkinPivot(oldFloor0)
				oldFloor0:Destroy()
			end
			local newFloor0 = cloneSkinForMap(floor0Template, "Floor0")
			pivotSkinTemplate(newFloor0, cf)
			newFloor0.Parent = floorParent
		end
	end
	
	-- Clean up all slot visuals and brainrots
	for slotID, slotInfo in pairs(plotData.Slots) do
		if slotInfo then
			-- Destroy placed brainrot model
			if slotInfo.PlacedBrainrot then
				slotInfo.PlacedBrainrot:Destroy()
				slotInfo.PlacedBrainrot = nil
			end
			
			-- Hide display parts
			if BrainrotVisuals and slotInfo.Model then
				BrainrotVisuals:HideDisplayParts(slotInfo.Model)
			end
			
			-- Destroy slot model
			if slotInfo.Model then
				slotInfo.Model:Destroy()
			end
		end
	end
	
	-- Clear slots table
	plotData.Slots = {}
	
	-- Destroy all upper floors (Floor1+)
	for floorIndex, floor in pairs(plotData.FloorModels) do
		if floor and floor.Parent then
			floor:Destroy()
		end
	end
	plotData.FloorModels = {}
	
	-- Clear ownership
	plotData.Owner = nil
	
	-- Clear player attribute
	player:SetAttribute("CurrentPlot", nil)
	
	if plotData.Model then
		-- Reset plot title to "free plot" (hide owner, show FreePlot label)
		self:ClearPlotTitle(plotData.Model)
		plotData.Model:SetAttribute("OwnerUserId", nil)
		
		-- Clean up Slots folder if it exists
		local slotsFolder = plotData.Model:FindFirstChild("Slots")
		if slotsFolder then
			slotsFolder:ClearAllChildren()
		end
	end
end

--[[
	Expand plot slots after rebirth (adds new slot and floor if needed)
	@param player Player
]]
function PlotService:ExpandSlotsForRebirth(player: Player)
	local plotID = self:GetPlayerPlot(player)
	if not plotID then
		warn("⚠️ Cannot expand slots: Player has no plot")
		return
	end
	
	local plotData = self.Plots[plotID]
	if not plotData or not plotData.Model then
		warn("⚠️ Cannot expand slots: Invalid plot data")
		return
	end
	
	-- Get slot template
	local slotTemplate = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("OtherModels")
		and ReplicatedStorage.Assets.OtherModels:FindFirstChild("Slot")
	
	if not slotTemplate then
		warn("⚠️ Slot template not found")
		return
	end
	
	-- Ensure Slots folder exists
	local slotsFolder = plotData.Model:FindFirstChild("Slots")
	if not slotsFolder then
		slotsFolder = Instance.new("Folder")
		slotsFolder.Name = "Slots"
		slotsFolder.Parent = plotData.Model
	end
	
	-- Calculate new total slots based on current rebirths
	local rebirths = DataService:GetValue(player, "Rebirths") or 0
	local totalSlots = Shared_RebirthRewards:GetTotalSlots(rebirths, CONFIG.BaseSlots)
	local currentSlotCount = 0
	for _ in pairs(plotData.Slots) do
		currentSlotCount = currentSlotCount + 1
	end
	
	for slotID = currentSlotCount + 1, totalSlots do
		self:AddSlot(plotData.Model, plotData, slotID, slotTemplate)
		task.wait() -- Yield between slots for smooth creation
	end
end

return PlotService
