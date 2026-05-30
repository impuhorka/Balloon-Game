--[[
	Client_FavoritePrompt - Professional favorite prompt system using AvatarEditorService
	Prompts players to favorite the game at optimal moments using AvatarEditorService:PromptSetFavorite()
	
	Triggers:
	- After 5 minutes of engaging gameplay (positive engagement signal) - SAVES TO DATASTORE
	- When attempting to leave (ESC menu opened) - DOES NOT SAVE (just last chance)
	
	Industry best practices:
	- Only prompt once per lifetime (tracked via datastore)
	- Use Roblox's native API for favoriting
	- Catch exit intent and positive engagement signals
	- Never spam or interrupt critical moments
]]

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local Client_Data = require(script.Parent.Parent.Core.Client_Data)

local Module = {}

-- Configuration
local PLAYTIME_THRESHOLD = 5 * 60 -- 5 minutes in seconds
local GAME_ID = 96306976668665 -- Your game's universe ID

-- State
local sessionStartTime = tick()
local hasPromptedPlaytime = false -- Playtime prompt (saves to datastore)
local hasPromptedExit = false -- Exit intent prompt (doesn't save)
local hasBeenPromptedLifetime = false -- From datastore (persists across sessions)

--[[
	Show Roblox's native favorite prompt using AvatarEditorService
	@param reason string - Why we're showing the prompt ("playtime" or "leaving")
]]
function Module:ShowFavoritePrompt(reason)
	-- Don't show if already prompted this lifetime (from datastore)
	if hasBeenPromptedLifetime then
		return
	end
	
	-- Don't show playtime prompt if already shown
	if reason == "playtime" and hasPromptedPlaytime then
		return
	end
	
	-- Don't show exit prompt if already shown or if playtime prompt was shown
	if reason == "leaving" and (hasPromptedExit or hasPromptedPlaytime) then
		return
	end
	
	-- Mark as prompted for this session
	if reason == "playtime" then
		hasPromptedPlaytime = true
	else
		hasPromptedExit = true
	end
	
	-- Use AvatarEditorService to prompt favorite
	local success, err = pcall(function()
		AvatarEditorService:PromptSetFavorite(GAME_ID, Enum.AvatarItemType.Asset, true)
	end)
	
	if success then
		-- Only save to datastore for playtime prompt (not exit intent)
		if reason == "playtime" then
			local Events = ReplicatedStorage:FindFirstChild("Events")
			local FavoriteHandler = Events and Events:FindFirstChild("FavoriteHandler")
			if FavoriteHandler then
				FavoriteHandler:FireServer("MarkPrompted")
				hasBeenPromptedLifetime = true -- Prevent any future prompts
			end
		end
	else
		-- Failed to show prompt, allow retry
		if reason == "playtime" then
			hasPromptedPlaytime = false
		else
			hasPromptedExit = false
		end
	end
end

--[[
	Check playtime and show prompt if threshold reached
]]
local function checkPlaytime()
	if hasBeenPromptedLifetime or hasPromptedPlaytime then return end
	
	local currentPlaytime = tick() - sessionStartTime
	
	-- Show prompt after threshold
	if currentPlaytime >= PLAYTIME_THRESHOLD then
		Module:ShowFavoritePrompt("playtime")
	end
end

--[[
	Detect when player is trying to leave (ESC menu opened)
	Only shows if playtime prompt hasn't been shown yet (doesn't save to datastore)
]]
local function setupExitIntentDetection()
	-- Detect ESC menu opened (player might be leaving)
	GuiService.MenuOpened:Connect(function()
		-- Don't show if already prompted this lifetime or if playtime prompt shown
		if hasBeenPromptedLifetime or hasPromptedPlaytime or hasPromptedExit then return end
		
		-- Player opened ESC menu (likely leaving)
		-- Wait a moment to ensure menu is visible, then show prompt
		task.delay(0.5, function()
			-- Only show if menu is still open (player didn't close it immediately)
			if GuiService.MenuIsOpen and not hasPromptedPlaytime and not hasPromptedExit then
				Module:ShowFavoritePrompt("leaving")
			end
		end)
	end)
end

--[[
	Initialize the favorite prompt system
]]
function Module:Init()
	-- Wait for replica to load and check if already prompted lifetime
	task.spawn(function()
		local replica = Client_Data:GetReplica()
		local waited = 0
		while not replica and waited < 10 do
			task.wait(0.5)
			waited = waited + 0.5
			replica = Client_Data:GetReplica()
		end
		
		if replica then
			-- Check if already prompted in a previous session
			hasBeenPromptedLifetime = replica.Data.HasBeenPromptedForFavorite or false
			
			-- Listen for changes (in case server updates it)
			replica:ListenToChange({"HasBeenPromptedForFavorite"}, function(newValue)
				hasBeenPromptedLifetime = newValue or false
			end)
		end
	end)
	
	-- Set up exit intent detection (ESC menu)
	setupExitIntentDetection()
	
	-- Start playtime checker (check every 30 seconds)
	task.spawn(function()
		while true do
			task.wait(30) -- Check every 30 seconds
			checkPlaytime()
			
			-- Stop checking once prompted lifetime
			if hasBeenPromptedLifetime or hasPromptedPlaytime then
				break
			end
		end
	end)
end

return Module
