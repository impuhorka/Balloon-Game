--[[
	Client_MusicManager.lua
	
	Handles music switching based on IsPlaying attribute.
	- Safe zone (IsPlaying = false): Relaxed music
	- Play zone (IsPlaying = true): Intense music
]]

local Players = game:GetService("Players")

local Player = Players.LocalPlayer

local Module = {}

-- Get Client_Sounds module
local Client_Sounds = require(script.Parent.Client_Sounds)

--[[
	Update music based on IsPlaying attribute.
	Only switches when state actually changes to avoid restarting music on respawn.
]]
local currentIsPlaying = nil

local function updateMusic()
	local isPlaying = Player:GetAttribute("IsPlaying")
	if currentIsPlaying == isPlaying then return end
	currentIsPlaying = isPlaying
	
	-- NEVER switch zone music during events
	-- Client_Sounds will handle music when event ends
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local activeEvent = ReplicatedStorage:GetAttribute("ActiveEvent")
	if activeEvent then
		return
	end
	
	if isPlaying then
		Client_Sounds:FadeToIntenseMusic()
	else
		Client_Sounds:FadeToNormalMusic()
	end
end

--[[
	Initialize music system
]]
function Module:Init()
	Player:GetAttributeChangedSignal("IsPlaying"):Connect(updateMusic)
	task.wait(1.5)
	
	-- Don't trigger initial music if an event is active (event music already playing)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local activeEvent = ReplicatedStorage:GetAttribute("ActiveEvent")
	if not activeEvent then
		local initialIsPlaying = Player:GetAttribute("IsPlaying")
		currentIsPlaying = not initialIsPlaying
		updateMusic()
	end
end

return Module
