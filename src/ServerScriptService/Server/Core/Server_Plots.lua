--// Server_Plots - Professional plot system orchestrator
--// Clean event handling, dependency injection, service coordination

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BalloonRigKit = require(ReplicatedStorage.Modules.Gameplay.BalloonRigKit)
local Shared_Marketplace = require(ReplicatedStorage.Modules.Settings.Shared_Marketplace)

-- Services (Dependency Injection)
local Server_Data
local Server_Inventory
local PlotService
local SlotService
local BrainrotVisuals
local CashSystem

local Module = {}

local function getZonePlotInfo()
	local zones = {}
	local plots = {}

	local spawnersFolder = Workspace:FindFirstChild("Spawners")
	if spawnersFolder then
		for _, child in ipairs(spawnersFolder:GetChildren()) do
			if child:IsA("BasePart") then
				zones[child.Name] = child.Position
			end
		end
	end

	local gameFolder = Workspace:FindFirstChild("Game")
	local plotsFolder = gameFolder and gameFolder:FindFirstChild("Plots")
	if plotsFolder then
		for _, plotModel in ipairs(plotsFolder:GetChildren()) do
			if plotModel:IsA("Model") then
				local teleportPart = plotModel:FindFirstChild("TeleportPart")
				if teleportPart and teleportPart:IsA("BasePart") then
					plots[plotModel.Name] = teleportPart.Position
				end
			end
		end
	end

	return {
		Zones = zones,
		Plots = plots,
	}
end

--[[
	Initialize plot system with all dependencies
]]
function Module:Init()
	-- Load dependencies
	Server_Data = require(script.Parent.Server_Data)
	Server_Inventory = require(script.Parent.Server_Inventory)
	
	-- Load plot services
	PlotService = require(script.Parent.Parent.Plot.PlotService)
	SlotService = require(script.Parent.Parent.Plot.SlotService)
	BrainrotVisuals = require(script.Parent.Parent.Plot.BrainrotVisuals)
	CashSystem = require(script.Parent.Parent.Plot.CashSystem)
	
	-- Initialize services with dependency injection
	PlotService:Init({
		DataService = Server_Data,
		SlotService = SlotService,
		CashSystem = CashSystem,
		BrainrotVisuals = BrainrotVisuals,
	})
	
	SlotService:Init({
		DataService = Server_Data,
		InventoryService = Server_Inventory,
		BrainrotVisuals = BrainrotVisuals,
	})
	
	CashSystem:Init({
		DataService = Server_Data,
		BrainrotVisuals = BrainrotVisuals,
	})
	
	local events = ReplicatedStorage:WaitForChild("Events")
	local zoneInfo = events:WaitForChild("ZoneInfo")
	zoneInfo.OnServerInvoke = function()
		return getZonePlotInfo()
	end

	-- Setup event handlers
	self:SetupEventHandlers()
	
	-- Setup player connection handlers
	self:SetupPlayerHandlers()
	
	-- Start cash generation loop
	CashSystem:StartCashGenerationLoop(PlotService.Plots)
end

--[[
	Setup RemoteEvent handlers (clean orchestration only)
]]
function Module:SetupEventHandlers()
	local Events = ReplicatedStorage:WaitForChild("Events")
	local PlotHandlerEvent = Events:WaitForChild("PlotHandler")
	
	PlotHandlerEvent.OnServerEvent:Connect(function(player: Player, action: string, ...)
		if not player or not action then
			return warn("⚠️ Invalid PlotHandler parameters")
		end
		
		-- Get player's plot data
		local plotData = PlotService:GetPlayerPlotData(player)
		if not plotData then
			return warn("⚠️ " .. player.Name .. " has no plot")
		end
		
		-- Route to appropriate service
		if action == "Place" then
			local slotID, brainrotUID = ...
			SlotService:PlaceBrainrot(player, plotData, slotID, brainrotUID)
			
		elseif action == "Pickup" then
			local slotID = ...
			SlotService:PickupBrainrot(player, plotData, slotID)
			
		elseif action == "Upgrade" then
			local slotID = ...
			CashSystem:UpgradeBrainrot(player, plotData, slotID)
			
		elseif action == "Collect" or action == "CollectCash" then
			local slotID = ...
			CashSystem:CollectCash(player, plotData, slotID)
			
		elseif action == "SellBrainrot" then
			local slotID = ...
			SlotService:SellBrainrot(player, plotData, slotID)
			
		elseif action == "CollectAll" then
			-- Quick Collect gamepass feature (optimized for many slots)
			if Server_Data:GetValue(player, "Passes.QuickCollect") ~= true then
				return -- Silent fail (client already validated)
			end
			
			local totalCollected = 0
			
			-- OPTIMIZED: Single loop, only read attributes (no profile lookups)
			for slotID, slotInfo in pairs(plotData.Slots) do
				local slotModel = slotInfo.Model
				if slotModel then
					local cashToCollect = slotModel:GetAttribute("CashToCollect")
					
					if cashToCollect and cashToCollect > 0 then
						totalCollected = totalCollected + cashToCollect
						slotModel:SetAttribute("CashToCollect", 0)
					end
				end
			end
			
			-- Single data write at the end
			if totalCollected > 0 then
				Server_Data:AddValue(player, "Cash", totalCollected)
			end
			
		else
			warn("⚠️ Unknown PlotHandler action: " .. tostring(action))
		end
	end)
end

--[[
	Setup player join/leave handlers
]]
function Module:SetupPlayerHandlers()
	-- Player joins
	local function onPlayerAdded(player: Player)
		player:SetAttribute(BalloonRigKit.PLOT_SPAWN_READY_ATTR, false)

		-- PROPER WAIT: Poll for profile to be loaded
		local profile = nil
		local maxWait = 10
		local waited = 0
		
		while not profile and waited < maxWait do
			profile = Server_Data:GetProfile(player)
			if not profile then
				task.wait(0.1)
				waited = waited + 0.1
			end
		end
		
		if not profile then
			warn("❌ Failed to load profile for " .. player.Name)
			return
		end
		
		-- Claim plot
		local plotID = PlotService:ClaimPlot(player)
		if not plotID then
			warn("❌ Failed to claim plot for " .. player.Name)
			return
		end
		
		-- Respawn at plot
		PlotService:RespawnPlayerAtPlot(player, plotID)
		
		-- Listen for gamepass purchases to update plot title
		local replica = Server_Data:GetReplica(player)
		if replica then
			-- Update plot title when CashBoost gamepass is purchased
			replica:ListenToChange({"Passes", "CashBoost"}, function(newValue)
				PlotService:UpdatePlotPlayerInfo(player)
			end)
			
			-- Update plot title when rebirths change (affects cash multiplier)
			replica:ListenToChange({"Rebirths"}, function(newValue)
				PlotService:UpdatePlotPlayerInfo(player)
			end)
		end
		
		player.CharacterAdded:Connect(function()
			player:SetAttribute(BalloonRigKit.PLOT_SPAWN_READY_ATTR, false)
			task.defer(function()
				PlotService:RespawnPlayerAtPlot(player, plotID)
			end)
		end)
	end
	
	-- Player leaves
	local function onPlayerRemoving(player: Player)
		PlotService:ReleasePlot(player)
	end
	
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return Module
