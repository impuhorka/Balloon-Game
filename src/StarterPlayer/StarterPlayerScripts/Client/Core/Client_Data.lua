--// Client_Data - Client-side data handler using ReplicaService (Official Pattern)
--// This module provides easy access to player data via ReplicaService
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ReplicaController = require(ReplicatedStorage.Modules.Dependencies.ReplicaController)

local Player = Players.LocalPlayer

local Module = {}

Module.PlayerData = nil
Module.PlayerReplica = nil
Module.IsReady = false

-- Wait until data is ready
function Module.WaitUntilReady()
	while not Module.IsReady do
		task.wait()
	end
	return
end

-- Get the player's data table
function Module:GetData()
	return Module.PlayerData or {}
end

-- Get the player's replica object (for advanced usage)
function Module:GetReplica()
	return Module.PlayerReplica
end

-- Initialize data replication (called from init.client.lua)
function Module:Init()
	-- Helper to set player replica
	local function setPlayerReplica(replica)
		if replica.Tags.UserId and replica.Tags.UserId == Player.UserId then
			Module.PlayerReplica = replica
			Module.PlayerData = replica.Data
			Module.IsReady = true
			return true
		end
		return false
	end
	
	-- If data already received, find existing replica
	if ReplicaController.InitialDataReceived then
		-- Access internal _replicas table (no public API exists)
		for _, replica in pairs(ReplicaController._replicas) do
			if replica.Class == "PlayerData" then
				if setPlayerReplica(replica) then
					break
				end
			end
		end
	end
	
	-- Also listen for future replicas (in case of respawn/reload)
	ReplicaController.ReplicaOfClassCreated("PlayerData", function(replica)
		setPlayerReplica(replica)
	end)
end

return Module
