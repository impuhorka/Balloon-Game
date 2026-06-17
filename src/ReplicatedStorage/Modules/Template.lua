--// Template - Creates RemoteEvents, RemoteFunctions, and core structure
--// Add your game-specific events here
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Module = {}

function Module:Init()
	-- Add your RemoteEvents/RemoteFunctions here, e.g.:
	-- ["MyHandler"] = "RemoteEvent",
	local RequiredEvents = {
		-- Inventory System (action-based: "Equip", "Unequip", "Sell", "Drop")
		["InventoryHandler"] = "RemoteEvent",
		
		-- Slapping System
		["Slapper"] = "RemoteEvent",
		
		-- Plot System (action-based: "Place", "Pickup", "Upgrade", "Collect")
		["PlotHandler"] = "RemoteEvent",
		
		-- Held brainrot controls (drop/update held stack)
		["BrainrotHandler"] = "RemoteEvent",
		
		-- Red Light Green Light - Single centralized guard event
		["GuardHandler"] = "RemoteEvent",
		
		-- Popup/Notification System (server -> client feedback)
		["Popup"] = "RemoteEvent",
		
		-- Admin System (admin commands feedback)
		["AdminEvent"] = "RemoteEvent",
		
		-- Sell System (sell brainrots)
		["SellBrainrot"] = "RemoteEvent",
		
		-- Tutorial System (tutorial progression)
		["Tutorial"] = "RemoteEvent",
		
		-- Speed Store (speed upgrades)
		["PurchaseSpeed"] = "RemoteEvent",
		
		-- Rebirth Store (rebirth system)
		["Rebirth"] = "RemoteEvent",
		
		-- Settings System (update player preferences)
		["SettingsHandler"] = "RemoteEvent",
		
		-- Anti-AFK System (idle detection)
		["IdleHandler"] = "RemoteEvent",
		
		-- Marketplace System (DevProduct purchases)
		["PurchaseHandler"] = "RemoteEvent",
		
		-- Offline Earnings System
		["OfflineHandler"] = "RemoteEvent", -- Bidirectional: Server->Client (show popup), Client->Server (claim)
		
		-- Item System (lucky blocks, etc.)
		["ItemHandler"] = "RemoteEvent", -- Action-based: "OpenLuckyBlock", "FinishOpening", plus server->client: "LuckyBlockAnimation"
		
		-- Balloons system (buy/equip state and data sync)
		["BalloonHandler"] = "RemoteEvent",
		-- Index / plot skins (EquipFloor, UnequipFloor)
		["IndexHandler"] = "RemoteEvent",
		-- Balloon jump-hold float (client Hold true/false → server lift on HRP)
		["BalloonFloatHandler"] = "RemoteEvent",
		
		-- Effects System (SingingX pattern - centralized visual effects)
		["PlayEffect"] = "RemoteEvent", -- Server->Client: All visual effects dispatch
		
		-- Proximity Prompt System (ShopTag handler)
		["ProximityHandler"] = "RemoteEvent", -- Server->Client: Open UI sections from proximity prompts
		
		-- Gift System (brainrot/lucky block: SendProposition, Answer; Server->Client: ShowProposition, CancelProposition)
		["GiftHandler"] = "RemoteEvent",
		-- Gamepass gifting: client asks who in session owns a pass (passName) → server returns { [userId] = true }
		["PurchasePassOwnership"] = "RemoteFunction",
		-- Admin Tablet: GetCommands + ExecuteCommand (gamepass-gated)
		["AdminTabletHandler"] = "RemoteFunction",
		-- Sniper: Shoot action (gamepass tool)
		["SniperHandler"] = "RemoteEvent",
		-- Favorite Prompt: Client notifies server when prompted (playtime only)
		["FavoriteHandler"] = "RemoteEvent",
		-- Group system: Server->Client: "Prompt" (groupId); Client->Server: "JoinResult" (groupId, status)
		["GroupHandler"] = "RemoteEvent",
		-- Zone Info: Client requests zone/plot positions for animation system
		["ZoneInfo"] = "RemoteFunction",
		
		-- Event System (SingingX pattern)
		["EventUIEvent"] = "RemoteEvent", -- Server->Client: Event UI updates ("Start", "End", "Sync", "CountdownUpdate")
		["MusicEvent"] = "RemoteEvent", -- Server->Client: Music control ("StopNormalMusic", "StartEventMusic", "StopEventMusic")
		["Sound"] = "RemoteEvent", -- Server->Client: Sound effects (e.g., "Siren", "Thunder")
		
		-- Arcade Machine System
		["ArcadeMachineRoll"] = "RemoteEvent", -- Server->Client: Trigger roulette animation with reward data
	}
	
	-- Create Events folder if it doesn't exist
	local EventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not EventsFolder then
		EventsFolder = Instance.new("Folder")
		EventsFolder.Name = "Events"
		EventsFolder.Parent = ReplicatedStorage
	end
	
	for EventName, EventType in pairs(RequiredEvents) do
		local existingEvent = EventsFolder:FindFirstChild(EventName)
		if not existingEvent then
			local newEvent = EventType == "RemoteFunction" and Instance.new("RemoteFunction") or Instance.new("RemoteEvent")
			newEvent.Name = EventName
			newEvent.Parent = EventsFolder
		end
	end
	
	-- Create SoundGroups for music system
	local soundGroupsFolder = ReplicatedStorage:FindFirstChild("SoundGroups")
	if not soundGroupsFolder then
		soundGroupsFolder = Instance.new("Folder")
		soundGroupsFolder.Name = "SoundGroups"
		soundGroupsFolder.Parent = ReplicatedStorage
	end
	if not soundGroupsFolder:FindFirstChild("Music") then
		local musicGroup = Instance.new("SoundGroup")
		musicGroup.Name = "Music"
		musicGroup.Volume = 1
		musicGroup.Parent = soundGroupsFolder
	end
	if not soundGroupsFolder:FindFirstChild("SFX") then
		local sfxGroup = Instance.new("SoundGroup")
		sfxGroup.Name = "SFX"
		sfxGroup.Volume = 1
		sfxGroup.Parent = soundGroupsFolder
	end
end

return Module
