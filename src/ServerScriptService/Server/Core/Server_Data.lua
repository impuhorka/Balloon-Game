--// Server_Data - Player data management (Template)
--// ProfileStore + ReplicaService with minimal schema - extend DataTemplate for your game

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local ProfileStore = require(script.Parent.ProfileStore)
local ReplicaService = require(script.Parent.ReplicaService)
require(script.Parent.Parent.Experimental.ReplicaServiceListeners)
local BalloonRigKit = require(ReplicatedStorage.Modules.Gameplay.BalloonRigKit)

local DataTemplate = {
	Cash = 0,
	Rebirths = 0,
	Speed = 0, -- Stat used to calculate overall walk speed (displayed in CurrencyFrame; formula elsewhere)
	RobuxSpent = 0, -- Total Robux spent (tracked for leaderboard)
	
	-- Offline Earnings System
	LastOfflineStart = 0, -- Timestamp when player last left (os.time())
	PendingOfflineEarnings = 0, -- Unclaimed offline earnings (before popup claim)
	
	-- Plot System
	PlotSlots = {
		-- [tostring(SlotID)] = {ConfigName, Modifier, Level, CashToCollect}
		-- Dynamically added when player places brainrots
	},
	
	-- Inventory System (Server-authoritative)
	-- EMPTY by default - starter items added via onboarding system, not template!
	-- Reconcile() would re-add removed items, causing duplication
	Inventory = {},
	

	-- Balloons System
	Balloons = {}, -- owned inventory {ConfigName, ...}; HP is session-only (not saved)
	EquippedBalloons = {}, -- session rig state {{ConfigName, HP}, ...}; cleared on leave

	-- Index (Collection tracker) - {[Modifier] = {ConfigName1, ConfigName2, ...}}
	Index = {},
	IndexRewardsUnlocked = {}, -- Plot skins unlocked via collection count {[SkinKey] = true}
	EquippedIndexFloor = "Default", -- Equipped plot skin id from Shared_IndexRewards.Rewards
	
	-- Settings (player preferences)
	Settings = {
		Music = 1, -- Volume 0-1 (default 100%)
		Sounds = 1, -- Volume 0-1 (default 100%)
		PlayerSpeedSetting = 1, -- Speed modifier 0-1 (default 100%)
		OverheadIncomeText = true, -- Show TotalPerSecond billboards (default true)
		SlowMode = false, -- Slow motion mode (default false)
	},
	
	-- NOTE: HotbarSlots removed - handled client-side as UI preference
	
	-- Marketplace System (DevProducts & Gamepasses)
	MarketplaceLogs = {
		-- [PurchaseId] = {Status = "Granted", ProductId = 123, Reason = nil, Time = 1234567890}
		-- Prevents duplicate receipt processing and tracks purchase history
	},
	Passes = {
		-- [PassName] = true/false
		-- Tracks gamepass ownership (VIP, 2xCash, etc.)
	},
	
	-- Steal Brainrot credit system: per-rarity credits; use before Robux; grant 1 for that rarity on failed apply
	StealCredits = {}, -- [Rarity] = number (e.g. Common = 1, Epic = 2)

	-- Starter Pack (2h in-game time only; ticks only while player is in-game)
	StarterPackPurchased = false,
	StarterPackPlayTime = 0, -- Seconds in-game since first join; server increments every 1s while not purchased
	
	-- Group Join Reward (one-time claim for joining group 1082816729)
	GroupJoinRewardClaimed = false,
	
	-- Favorite Prompt System (one-time per lifetime, not per session)
	HasBeenPromptedForFavorite = false,
	
	-- Tutorial System (0 = not started/old player, 1-5 = in progress, 6+ = completed)
	TutorialStep = 0,
	
	-- Event Currencies (for event-specific collectibles)
	EventCurrencies = {
		ArcadeTickets = 0,
		-- Future event currencies can be added here
	},
}

local Module = {}
Module.Profiles = {}
Module.Replicas = {}

-- Leaderboard callback (set by Server_Leaderboard during Init)
Module.LeaderboardCallback = nil

local PlayerStore = ProfileStore.New("softRelease_v2", DataTemplate)
local ReplicaClassToken = ReplicaService.NewClassToken("PlayerData")

-- Leaderboard tracked stats (constant, no need to recreate)
local LEADERBOARD_STATS = {"Rebirths", "RobuxSpent"}

-- Studio configuration:
-- TestInStudio (BoolValue) → If true, use Mock store (fresh data each session; useful for testing)
-- SaveInStudio (BoolValue) → If false, loads regular data but doesn't save it (useful for testing without corrupting live data)
local shouldSaveInStudio = true
local function getStore()
	if RunService:IsStudio() then
		-- TestInStudio controls whether to use Mock (fresh data) or real data
		local testInStudio = ServerScriptService:FindFirstChild("TestInStudio")
		if testInStudio and testInStudio:IsA("BoolValue") and testInStudio.Value == true then
			return PlayerStore.Mock -- Fresh data each session; nothing persisted
		end
		
		-- SaveInStudio controls whether to save data (but still loads real data)
		local saveInStudio = ServerScriptService:FindFirstChild("SaveInStudio")
		if saveInStudio and saveInStudio:IsA("BoolValue") and saveInStudio.Value == false then
			shouldSaveInStudio = false -- Load real data but don't save changes
		end
	end
	return PlayerStore
end

local function stripBalloonHpForSave(data)
	if not data or type(data) ~= "table" then
		return
	end
	data.Balloons = BalloonRigKit.normalizeToConfigNames(data.Balloons)
	data.EquippedBalloons = {}
end

local function getValueByPath(data, path)
	if not data or type(path) ~= "string" then return nil end
	local parts = string.split(path, ".")
	local current = data
	for _, key in ipairs(parts) do
		if type(current) ~= "table" then return nil end
		current = current[key]
	end
	return current
end

local function setValueByPath(data, path, value)
	if not data or type(path) ~= "string" then return end
	local parts = string.split(path, ".")
	local current = data
	for i = 1, #parts - 1 do
		if type(current[parts[i]]) ~= "table" then
			current[parts[i]] = {}
		end
		current = current[parts[i]]
	end
	current[parts[#parts]] = value
end

function Module:GetProfile(player)
	return self.Profiles[player]
end

function Module:GetReplica(player)
	return self.Replicas[player]
end

function Module:GetData(player)
	local profile = self.Profiles[player]
	return profile and profile.Data or nil
end

function Module:GetValue(player, path)
	local data = self:GetData(player)
	return getValueByPath(data, path)
end

function Module:SetValue(player, path, value)
	local data = self:GetData(player)
	if not data then
		return
	end

	local replica = self:GetReplica(player)
	if replica then
		local pathArray = {}
		for part in string.gmatch(path, "[^.]+") do
			table.insert(pathArray, part)
		end
		-- Must go through replica first: ReplicaServiceListeners compares old_value before assign.
		-- If we mutate profile.Data via setValueByPath before this, old_value == value and ListenToChange never runs.
		replica:SetValue(pathArray, value)
	else
		setValueByPath(data, path, value)
	end

	-- Notify leaderboard system for tracked stats (optimized - uses callback)
	if table.find(LEADERBOARD_STATS, path) and self.LeaderboardCallback then
		self.LeaderboardCallback(player.UserId, path, value)
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	if path == "Cash" then
		local cash = leaderstats:FindFirstChild("Cash")
		if cash then
			-- Format cash using Shared_Shorten
			local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
			cash.Value = Shared_Shorten:Number(value)
		end
	elseif path == "Rebirths" then
		local rebirths = leaderstats:FindFirstChild("Rebirths")
		if rebirths then
			rebirths.Value = value
		end
	elseif path == "Speed" then
		local speed = leaderstats:FindFirstChild("Speed")
		if speed then
			speed.Value = value
		end
	end
end

function Module:AddValue(player, path, amount)
	local current = self:GetValue(player, path) or 0
	self:SetValue(player, path, current + amount)
end

function Module:SubValue(player, path, amount)
	local current = self:GetValue(player, path) or 0
	self:SetValue(player, path, math.max(0, current - amount))
end

--[[
	PROFESSIONAL TABLE OPERATIONS
	Avoids manual table copying - handles Replica updates automatically
]]

--[[
	Remove a key from a table-type data field
	@param player Player
	@param path string - Path to table (e.g., "Inventory", "PlotSlots")
	@param key any - Key to remove
]]
--[[
	Remove a key from a table-type data field (DIRECT ProfileService manipulation)
	@param player Player
	@param path string - Path to table (e.g., "Inventory", "PlotSlots")
	@param key any - Key to remove
]]
function Module:RemoveFromTable(player: Player, path: string, key: any)
	local profile = self:GetProfile(player)
	if not profile then return false end
	
	local targetTable = getValueByPath(profile.Data, path)
	if not targetTable then return false end
	
	targetTable[key] = nil
	
	local replica = self:GetReplica(player)
	if replica then
		local pathArray = {}
		for part in string.gmatch(path, "[^.]+") do
			table.insert(pathArray, part)
		end
		replica:SetValue(pathArray, targetTable)
	end
	
	return true
end

--[[
	Add/Update a key in a table-type data field (DIRECT ProfileService manipulation)
	@param player Player
	@param path string - Path to table
	@param key any - Key to add/update
	@param value any - Value to set
]]
function Module:AddToTable(player: Player, path: string, key: any, value: any)
	local profile = self:GetProfile(player)
	if not profile then return false end
	
	-- DIRECT ProfileService manipulation - no cloning
	local targetTable = getValueByPath(profile.Data, path)
	if not targetTable then
		-- Create table if it doesn't exist
		setValueByPath(profile.Data, path, {})
		targetTable = getValueByPath(profile.Data, path)
	end
	
	targetTable[key] = value
	
	-- Update replica using ReplicaService's SetValue method
	local replica = self:GetReplica(player)
	if replica then
		-- Convert path string to array for ReplicaService
		local pathArray = {}
		for part in string.gmatch(path, "[^.]+") do
			table.insert(pathArray, part)
		end
		-- ReplicaService SetValue - pass the entire updated table
		replica:SetValue(pathArray, targetTable)
	end
	
	return true
end

--[[
	Update multiple keys in a table-type data field
	@param player Player
	@param path string - Path to table
	@param updates table - Dictionary of key-value pairs to update
]]
function Module:UpdateTable(player: Player, path: string, updates: {[any]: any})
	local profile = self:GetProfile(player)
	if not profile then return false end
	
	local current = getValueByPath(profile.Data, path) or {}
	local new = table.clone(current)
	
	for key, value in pairs(updates) do
		new[key] = value
	end
	
	self:SetValue(player, path, new)
	return true
end

--[[
	Wipe player's data and kick them (admin command)
	@param player Player - Player to wipe data for
]]
function Module:WipeData(player: Player)
	local profile = self:GetProfile(player)
	if not profile then
		warn("⚠️ Cannot wipe data: No profile for", player.Name)
		return false
	end

	local replica = self:GetReplica(player)
	if replica then
		for key, templateValue in pairs(DataTemplate) do
			local newVal = type(templateValue) == "table" and table.clone(templateValue) or templateValue
			replica:SetValue({ key }, newVal)
		end
	else
		for key, value in pairs(DataTemplate) do
			if type(value) == "table" then
				profile.Data[key] = table.clone(value)
			else
				profile.Data[key] = value
			end
		end
	end

	-- Update leaderstats
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
		local cash = leaderstats:FindFirstChild("Cash")
		if cash then
			cash.Value = Shared_Shorten:Number(0)
		end
		local rebirths = leaderstats:FindFirstChild("Rebirths")
		if rebirths then
			rebirths.Value = 0
		end
		local speed = leaderstats:FindFirstChild("Speed")
		if speed then
			speed.Value = 0
		end
	end

	-- Kick player so they rejoin with fresh data
	task.delay(1, function()
		if player.Parent then
			player:Kick("Your data has been wiped by an admin. Please rejoin.")
		end
	end)

	return true
end

local function createLeaderstats(player, profile)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player
	
	local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
	
	-- Cash (StringValue for formatted display)
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Value = Shared_Shorten:Number(profile.Data.Cash or 0)
	cash.Parent = leaderstats

	-- Rebirths (IntValue for small numbers)
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = profile.Data.Rebirths or 0
	rebirths.Parent = leaderstats

	-- Speed (IntValue for small numbers)
	local speed = Instance.new("IntValue")
	speed.Name = "Speed"
	speed.Value = profile.Data.Speed or 0
	speed.Parent = leaderstats

	local replica = Module.Replicas[player]
	if replica then
		replica:ListenToChange({"Cash"}, function(newValue)
			cash.Value = Shared_Shorten:Number(newValue)
		end)
		replica:ListenToChange({"Rebirths"}, function(newValue)
			rebirths.Value = newValue
		end)
		replica:ListenToChange({"Speed"}, function(newValue)
			speed.Value = newValue
		end)
	end
end

local function onPlayerAdded(player)
	local store = getStore()
	local profile = store:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function() return player.Parent ~= Players end,
	})

	if not profile then
		player:Kick("Failed to load data. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.Data.Balloons = BalloonRigKit.normalizeToConfigNames(profile.Data.Balloons)
	
	-- Starter items removed - Slapper is now a built-in tool (handled by Server_Slapper)

	profile.OnSessionEnd:Connect(function()
		Module.Profiles[player] = nil
		Module.Replicas[player] = nil
		if player.Parent then
			player:Kick("Profile session ended. Please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	
	-- Set IsVerified attribute from Roblox verified badge
	player:SetAttribute("IsVerified", player.HasVerifiedBadge)

	Module.Profiles[player] = profile

	local replica = ReplicaService.NewReplica({
		ClassToken = ReplicaClassToken,
		Data = profile.Data,
		Tags = {UserId = player.UserId},
		Replication = player,
	})

	Module.Replicas[player] = replica
	createLeaderstats(player, profile)

	-- Check gamepass ownership (like SingingX CreateMarket)
	task.defer(function()
		local Server_Marketplace = require(script.Parent.Parent.Systems.Server_Marketplace)
		Server_Marketplace:CheckGamepassOwnership(player)
	end)
	
	-- Check and auto-grant group reward if in group
	task.defer(function()
		local Server_Marketplace = require(script.Parent.Parent.Systems.Server_Marketplace)
		Server_Marketplace:CheckAndGrantGroupReward(player)
	end)
	
	-- Process offline earnings if player was offline
	task.defer(function()
		-- Small delay to ensure CashSystem is initialized
		task.wait(0.5)
		local CashSystem = require(script.Parent.Parent.Plot.CashSystem)
		CashSystem:ProcessOfflineEarnings(player)
	end)

end

local function onPlayerRemoving(player)
	local profile = Module.Profiles[player]
	if profile then
		profile.Data.LastOfflineStart = os.time()
		stripBalloonHpForSave(profile.Data)
		
		-- If SaveInStudio is false, release session without saving
		if not shouldSaveInStudio and RunService:IsStudio() then
			profile:Release()
		else
			profile:EndSession()
		end
		Module.Profiles[player] = nil
	end
	local replica = Module.Replicas[player]
	if replica then
		replica:Destroy()
		Module.Replicas[player] = nil
	end
end

-- Starter Pack: increment in-game playtime every second; replicate to client every 5s to reduce bandwidth
local STARTER_PACK_REPLICATE_INTERVAL = 5
local function starterPackPlayTimeLoop()
	task.spawn(function()
		local ticks = 0
		while true do
			task.wait(1)
			ticks = ticks + 1
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = Module.Profiles[player]
				if profile and profile.Data and not profile.Data.StarterPackPurchased then
					local current = profile.Data.StarterPackPlayTime or 0
					profile.Data.StarterPackPlayTime = current + 1
					if ticks % STARTER_PACK_REPLICATE_INTERVAL == 0 then
						Module:SetValue(player, "StarterPackPlayTime", profile.Data.StarterPackPlayTime)
					end
				end
			end
		end
	end)
end

function Module:Init()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = Module.Profiles[player]
			if profile then
				profile.Data.LastOfflineStart = os.time()
				stripBalloonHpForSave(profile.Data)
				
				-- If SaveInStudio is false, release without saving
				if not shouldSaveInStudio and RunService:IsStudio() then
					profile:Release()
				else
					profile:EndSession()
				end
			end
		end
	end)
	starterPackPlayTimeLoop()
end

return Module
