--// Client Initialization (Template) - SingingX pattern
local Start = tick()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local Player = Players.LocalPlayer

-- Disable Roblox default backpack (tilde key) so our custom backpack is the only one
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- Initialize ReplicaService data
local ReplicaController = require(ReplicatedStorage.Modules.Dependencies.ReplicaController)
ReplicaController.RequestData()

local Library = {}
local Libraries = { script }

-- Wait for essential data (leaderstats created by Server_Data)
repeat task.wait() until Player:FindFirstChild("leaderstats")

-- Wait for Events folder to be created by server (Template:Init())
repeat task.wait() until ReplicatedStorage:FindFirstChild("Events")

-- CRITICAL: Wait for player data replica to be fully replicated before initializing any Client modules
-- This prevents race conditions when players join via friend-join or during mid-game teleports
do
	local maxWait = 30
	local waited = 0
	
	-- Wait for initial data to be received from server
	while not ReplicaController.InitialDataReceived and waited < maxWait do
		task.wait(0.1)
		waited = waited + 0.1
	end
	
	if not ReplicaController.InitialDataReceived then
		Player:Kick("Failed to load game data. Please rejoin.")
		return
	end
	
	-- Find our specific PlayerData replica
	local playerReplica = nil
	for _, replica in pairs(ReplicaController._replicas) do
		if replica.Class == "PlayerData" and replica.Tags.UserId == Player.UserId then
			playerReplica = replica
			break
		end
	end
	
	-- If not found yet, wait for it to be created
	if not playerReplica then
		local replicaReceived = false
		ReplicaController.ReplicaOfClassCreated("PlayerData", function(replica)
			if replica.Tags.UserId == Player.UserId then
				playerReplica = replica
				replicaReceived = true
			end
		end)
		
		waited = 0
		while not replicaReceived and waited < maxWait do
			task.wait(0.1)
			waited = waited + 0.1
		end
		
		if not playerReplica then
			Player:Kick("Failed to load player data. Please rejoin.")
			return
		end
	end
	
	-- Data is now guaranteed to be ready - all Client modules can safely initialize
end

-- Load all client modules
for _, Modules in pairs(Libraries) do
	for _, Module in pairs(Modules:GetDescendants()) do
		if Module:IsA("ModuleScript") then
			local ok, Required = pcall(require, Module)
			if ok and type(Required) == "table" then
				pcall(function()
					setmetatable(Required, {__index = Library})
				end)
				Library[Module.Name] = Required
			end
		end
	end
end

-- Initialize Client_ modules with Init()
for ModuleName, Module in pairs(Library) do
	if type(Module.Init) == "function" and ModuleName:match("^Client_") then
		task.spawn(function()
			local ok, err = pcall(Module.Init, Module)
			if not ok then
				warn(("❌ Failed to initialize %s: %s"):format(ModuleName, tostring(err)))
			end
		end)
	end
end
