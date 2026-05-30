--// Server_Admin: Admin command system for RedGreenLight
--// Based on SingingX admin system
--// Group ID: 1082816729

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local MessagingService = game:GetService("MessagingService")
local TextService = game:GetService("TextService")

local Server_Data = require(script.Parent.Parent.Core.Server_Data)
local Server_Inventory = require(script.Parent.Parent.Core.Server_Inventory)
local Server_Marketplace = require(script.Parent.Parent.Systems.Server_Marketplace)

local Shared_LuckyBlocks = require(ReplicatedStorage.Modules.ItemConfigs.Shared_LuckyBlocks)
local Shared_Marketplace = require(ReplicatedStorage.Modules.Settings.Shared_Marketplace)

local AdminCommands = {}

--// ADMIN GROUP CONFIGURATION
local ADMIN_GROUP_ID = 33692535
local ADMIN_RANKS = {
	[248] = "Moderator",
	[249] = "Admin",
	[250] = "Manager",
	[254] = "Developer",
	[255] = "Owner"
}

--// COMMAND DEFINITIONS
local COMMANDS = {
	["setcash"] = {
		description = "Set a player's cash amount",
		usage = "/setcash [player] [amount]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true },
			{ Name = "amount", type = "number", required = true }
		}
	},
	["addcash"] = {
		description = "Add cash to a player",
		usage = "/addcash [player] [amount]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true },
			{ Name = "amount", type = "number", required = true }
		}
	},
	["addcurrency"] = {
		description = "Add event currency to a player",
		usage = "/addcurrency [player] [currency] [amount]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true },
			{ Name = "currency", type = "string", required = true },
			{ Name = "amount", type = "number", required = true }
		}
	},
	["setspeed"] = {
		description = "Set a player's speed stat",
		usage = "/setspeed [player] [amount]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true },
			{ Name = "amount", type = "number", required = true }
		}
	},
	["setrebirths"] = {
		description = "Set a player's rebirth count",
		usage = "/setrebirths [player] [amount]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true },
			{ Name = "amount", type = "number", required = true }
		}
	},
	["tp"] = {
		description = "Teleport one player to another (shortcut)",
		usage = "/tp [player1] [player2]",
		minRank = 223,
		parameters = {
			{ Name = "player1", type = "player", required = true },
			{ Name = "player2", type = "player", required = true }
		}
	},
	["announce"] = {
		description = "Broadcast a message to current server only",
		usage = "/announce [message]",
		minRank = 223,
		parameters = {
			{ Name = "message", type = "string", required = true }
		}
	},
	["kick"] = {
		description = "Kick a player from the server",
		usage = "/kick [player] [reason]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true },
			{ Name = "reason", type = "string", required = false }
		}
	},
	["wipedata"] = {
		description = "Wipe a player's data (DANGEROUS)",
		usage = "/wipedata [player]",
		minRank = 0,
		parameters = {
			{ Name = "player", type = "player", required = true }
		}
	},
	["shout"] = {
		description = "Broadcast a message to all servers",
		usage = "/shout [message]",
		minRank = 254,
		parameters = {
			{ Name = "message", type = "string", required = true }
		}
	},
	["getdata"] = {
		description = "View a player's profile data",
		usage = "/getdata [player]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true }
		}
	},
	["getinventory"] = {
		description = "View a player's inventory contents",
		usage = "/getinventory [player]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true }
		}
	},
	["goto"] = {
		description = "Teleport yourself to a player",
		usage = "/goto [player]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true }
		}
	},
	["bring"] = {
		description = "Teleport a player to you",
		usage = "/bring [player]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true }
		}
	},
	["respawn"] = {
		description = "Respawn a player",
		usage = "/respawn [player]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true }
		}
	},
	["godmode"] = {
		description = "Toggle godmode (slaps get reversed, immune to guards)",
		usage = "/godmode [player]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = false }
		}
	},
	["ban"] = {
		description = "Ban a player from the game (UserId ban)",
		usage = "/ban [player] [reason]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true },
			{ Name = "reason", type = "string", required = false }
		}
	},
	["listplayers"] = {
		description = "List all players in the server",
		usage = "/listplayers",
		minRank = 223,
		parameters = {}
	},
	["clearinventory"] = {
		description = "Clear a player's entire inventory",
		usage = "/clearinventory [player]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true }
		}
	},
	["lighting"] = {
		description = "Change lighting preset (test weather/lighting)",
		usage = "/lighting [preset] or /lighting default",
		minRank = 223,
		parameters = {
			{ Name = "preset", type = "string", required = true }
		}
	},
	["giveblock"] = {
		description = "Give lucky blocks (all or specific)",
		usage = "/giveblock [player] [all|blockname]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true },
			{ Name = "block", type = "string", required = true }
		}
	},
	["givegamepass"] = {
		description = "Grant a gamepass to a player (VIP, CashBoost, SpeedBoost, etc.)",
		usage = "/givegamepass [player] [VIP|CashBoost|SpeedBoost|Sniper|Tablet]",
		minRank = 223,
		parameters = {
			{ Name = "player", type = "player", required = true },
			{ Name = "pass", type = "string", required = true }
		}
	},
	["startevent"] = {
		description = "Manually start an event",
		usage = "/startevent [eventname]",
		minRank = 223,
		parameters = {
			{ Name = "eventname", type = "string", required = true }
		}
	},
	["endevent"] = {
		description = "End the current event",
		usage = "/endevent",
		minRank = 223,
		parameters = {}
	},
	["startglobalevent"] = {
		description = "Start an event on all servers",
		usage = "/startglobalevent [eventname]",
		minRank = 254,
		parameters = {
			{ Name = "eventname", type = "string", required = true }
		}
	},
	["endglobalevent"] = {
		description = "End the current event on all servers",
		usage = "/endglobalevent",
		minRank = 254,
		parameters = {}
	},
	["listevents"] = {
		description = "List all available events",
		usage = "/listevents",
		minRank = 223,
		parameters = {}
	},
}

--// HELPER FUNCTIONS
function AdminCommands:SendSystemMessage(player, message, messageType)
	if player then
		local Confirm = ReplicatedStorage.Events.AdminEvent
		Confirm:FireClient(player, message, messageType)
	end
end

function AdminCommands:HasPermission(player, commandName)
	local command = COMMANDS[commandName]
	if not command then return false end
	
	if not player:IsInGroup(ADMIN_GROUP_ID) then
		return false
	end
	
	local playerRank = player:GetRankInGroup(ADMIN_GROUP_ID)
	return playerRank >= command.minRank
end

--// PLAYER LOOKUP SYSTEM
function AdminCommands:FindPlayer(searchTerm)
	if not searchTerm or searchTerm == "" then return nil end
	
	-- Handle "me" keyword
	if searchTerm:lower() == "me" then
		return nil -- Will be handled by command functions
	end
	
	-- Try exact Name match first
	local player = Players:FindFirstChild(searchTerm)
	if player then return player end
	
	-- Try case-insensitive exact match
	searchTerm = searchTerm:lower()
	for _, player in pairs(Players:GetPlayers()) do
		if player.Name:lower() == searchTerm then
			return player
		end
	end
	
	-- Try partial Name match as fallback
	for _, player in pairs(Players:GetPlayers()) do
		if player.Name:lower():find(searchTerm, 1, true) then
			return player
		end
	end
	
	return nil
end

function AdminCommands:GetPlayerShoutColor(playerName)
	-- Generate consistent color based on player name using hash-like approach
	local hash = 0
	for i = 1, #playerName do
		hash = hash + string.byte(playerName, i) * i
	end
	
	-- Define a set of vibrant, readable colors for shouts
	local colors = {
		"rgb(255, 190, 39)",  -- Bright Orange
		"rgb(150, 75, 255)", -- Bright Purple
		"rgb(0, 221, 255)",  -- Bright Blue
		"rgb(255, 220, 42)",  -- Bright Yellow
		"rgb(138, 255, 29)", -- Bright Green
		"rgb(255, 108, 221)", -- Bright Pink
		"rgb(255, 37, 37)", -- Bright Red
	}
	
	-- Use hash to select color (same name always gets same color)
	local colorIndex = (hash % #colors) + 1
	return colors[colorIndex]
end

--// COMMAND HANDLERS
function AdminCommands:HandleSetCash(player, args)
	if #args < 2 then
		return "Usage: /setcash [player] [amount]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	local amount = tonumber(args[2])
	if not amount or amount < 0 then
		return "Invalid amount: " .. args[2]
	end
	
	Server_Data:SetValue(targetPlayer, "Cash", amount)
	
	self:SendSystemMessage(player, string.format("Set %s's cash to $%d", targetPlayer.Name, amount), "Success")
	return string.format("Set %s's cash to $%d", targetPlayer.Name, amount)
end

function AdminCommands:HandleAddCash(player, args)
	if #args < 2 then
		return "Usage: /addcash [player] [amount]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	local amount = tonumber(args[2])
	if not amount then
		return "Invalid amount: " .. args[2]
	end
	
	Server_Data:AddValue(targetPlayer, "Cash", amount)
	
	self:SendSystemMessage(player, string.format("Added $%d to %s", amount, targetPlayer.Name), "Success")
	return string.format("Added $%d to %s", amount, targetPlayer.Name)
end

function AdminCommands:HandleAddCurrency(player, args)
	if #args < 3 then
		return "Usage: /addcurrency [player] [currency] [amount]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	local currencyName = args[2]
	local amount = tonumber(args[3])
	if not amount then
		return "Invalid amount: " .. args[3]
	end
	
	-- Valid event currencies (case-insensitive lookup)
	local validCurrencies = {
		ArcadeTickets = "ArcadeTickets",
		-- Add more event currencies here as they're added
	}
	
	-- Find currency (case-insensitive)
	local properCurrencyName = nil
	for key, value in pairs(validCurrencies) do
		if key:lower() == currencyName:lower() then
			properCurrencyName = value
			break
		end
	end
	
	if not properCurrencyName then
		local validList = {}
		for key, _ in pairs(validCurrencies) do
			table.insert(validList, key)
		end
		return "Invalid currency. Valid currencies: " .. table.concat(validList, ", ")
	end
	
	-- Get current value
	local currentValue = Server_Data:GetValue(targetPlayer, "EventCurrencies." .. properCurrencyName) or 0
	
	-- Add to current value
	Server_Data:SetValue(targetPlayer, "EventCurrencies." .. properCurrencyName, currentValue + amount)
	
	local newTotal = currentValue + amount
	self:SendSystemMessage(player, string.format("Added %d %s to %s (new total: %d)", amount, properCurrencyName, targetPlayer.Name, newTotal), "Success")
	return string.format("Added %d %s to %s (new total: %d)", amount, properCurrencyName, targetPlayer.Name, newTotal)
end

function AdminCommands:HandleSetSpeed(player, args)
	if #args < 2 then
		return "Usage: /setspeed [player] [amount]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	local amount = tonumber(args[2])
	if not amount then
		return "Invalid amount: " .. args[2]
	end
	
	Server_Data:SetValue(targetPlayer, "Speed", amount)
	
	-- Apply speed immediately (don't rely on replica listener timing)
	local Server_CharacterStats = require(script.Parent.Parent.Systems.Server_CharacterStats)
	Server_CharacterStats:ApplyStats(targetPlayer)
	
	self:SendSystemMessage(player, string.format("Set %s's speed to %d", targetPlayer.Name, amount), "Success")
	return string.format("Set %s's speed to %d", targetPlayer.Name, amount)
end

function AdminCommands:HandleSetRebirths(player, args)
	if #args < 2 then
		return "Usage: /setrebirths [player] [amount]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	local amount = tonumber(args[2])
	if not amount then
		return "Invalid amount: " .. args[2]
	end
	
	Server_Data:SetValue(targetPlayer, "Rebirths", amount)

	-- Refresh plot: title (rebirths/cash label) and slot count (add slots if new rebirths grant more)
	local PlotService = require(script.Parent.Parent.Plot.PlotService)
	PlotService:UpdatePlotPlayerInfo(targetPlayer)
	PlotService:ExpandSlotsForRebirth(targetPlayer)
	
	self:SendSystemMessage(player, string.format("Set %s's rebirths to %d", targetPlayer.Name, amount), "Success")
	return string.format("Set %s's rebirths to %d", targetPlayer.Name, amount)
end

function AdminCommands:HandleTeleport(player, args)
	if #args < 2 then
		return "Usage: /tp [player1] [player2]"
	end
	
	local player1 = self:FindPlayer(args[1])
	local player2 = self:FindPlayer(args[2])
	
	if not player1 then
		return "Player 1 not found: " .. args[1]
	end
	
	if not player2 then
		return "Player 2 not found: " .. args[2]
	end
	
	if not player1.Character or not player2.Character then
		return "Character not found"
	end
	
	local root1 = player1.Character:FindFirstChild("HumanoidRootPart")
	local root2 = player2.Character:FindFirstChild("HumanoidRootPart")
	
	if not root1 or not root2 then
		return "Could not find HumanoidRootPart"
	end
	
	root1.CFrame = root2.CFrame
	
	self:SendSystemMessage(player, string.format("Teleported %s to %s", player1.Name, player2.Name), "Success")
	return string.format("Teleported %s to %s", player1.Name, player2.Name)
end

function AdminCommands:HandleAnnounce(player, args)
	if #args < 1 then
		return "Usage: /announce [message]"
	end
	
	-- Join all arguments to form the complete message
	local message = table.concat(args, " ")
	
	-- Check if message is too long
	if #message > 200 then
		return "Message too long. Maximum 200 characters allowed."
	end
	
	-- Filter the message for safety
	local success, filteredMessage = pcall(function()
		local result = TextService:FilterStringAsync(message, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	
	if not success then
		warn("Failed to filter announce message:", filteredMessage)
		return "Failed to process message due to filtering error"
	end
	
	-- Check if filtered message is empty
	if filteredMessage == "" then
		return "Message contains only inappropriate content and cannot be sent"
	end
	
	-- Check if message was heavily censored
	if filteredMessage:find("##+") then
		return "Message contains inappropriate content and cannot be sent"
	end
	
	if #filteredMessage < #message * 0.5 then
		return "Message contains inappropriate content and cannot be sent"
	end
	
	if message:find(" ") and not filteredMessage:find(" ") then
		return "Message contains inappropriate content and cannot be sent"
	end
	
	-- Use filtered message
	message = filteredMessage
	
	-- Check if Popup event exists
	local popupEvent = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("Popup")
	if not popupEvent then
		return "Popup system not available"
	end
	
	-- Send to current server only with unique color
	local adminColor = self:GetPlayerShoutColor(player.Name)
	local isVerified = player:GetAttribute("IsVerified") == true
	local verifiedBadge = isVerified and "" or ""
	local localMessage = '<font color="' .. adminColor .. '">' .. player.Name .. verifiedBadge .. ':</font> ' .. message
	
	local announceConfig = {
		animation = "default",
		duration = 4,
		richText = true,
		sound = "Announcement"
	}
	popupEvent:FireAllClients(localMessage, announceConfig)
	
	self:SendSystemMessage(player, "Announcement sent: " .. message, "Success")
	return "Announcement sent: " .. message
end

function AdminCommands:HandleShout(player, args)
	if #args < 1 then
		return "Usage: /shout [message]"
	end
	
	-- Join all arguments to form the complete message
	local message = table.concat(args, " ")
	
	-- Check if message is too long (Roblox has limits)
	if #message > 200 then
		return "Message too long. Maximum 200 characters allowed."
	end
	
	-- Filter the message for inappropriate content
	local success, filteredMessage = pcall(function()
		local result = TextService:FilterStringAsync(message, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	
	if not success then
		warn("Failed to filter shout message:", filteredMessage)
		return "Failed to process message due to filtering error"
	end
	
	-- Check if filtered message is empty (all content was filtered)
	if filteredMessage == "" then
		return "Message contains only inappropriate content and cannot be sent"
	end
	
	-- Check if message was censored (contains multiple # symbols in a row, indicating filtered content)
	if filteredMessage:find("##+") then
		return "Message contains inappropriate content and cannot be sent"
	end
	
	-- Check if the filtered message is significantly different from original (likely censored)
	if #filteredMessage < #message * 0.5 then
		return "Message contains inappropriate content and cannot be sent"
	end
	
	-- Additional check: if original message contained spaces but filtered doesn't, it was heavily censored
	if message:find(" ") and not filteredMessage:find(" ") then
		return "Message contains inappropriate content and cannot be sent"
	end
	
	-- Use filtered message instead of original
	message = filteredMessage
	
	-- Check if Popup event exists
	local popupEvent = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("Popup")
	if not popupEvent then
		return "Popup system not available"
	end
	
	-- Send to all other servers via MessagingService first
	local success, errorMessage = pcall(function()
		MessagingService:PublishAsync("AdminShout", {
			message = message,
			adminName = player.Name,
			isVerified = player:GetAttribute("IsVerified") == true,
			timestamp = os.time()
		})
	end)
	
	if not success then
		warn("Failed to send shout to other servers:", errorMessage)
		self:SendSystemMessage(player, "Message sent to this server, but failed to send to other servers", "Error")
		return "Message sent to this server, but failed to send to other servers"
	end

	self:SendSystemMessage(player, "Shout sent to all servers: " .. message, "Success")
	
	return "Shout sent to all servers: " .. message
end

function AdminCommands:HandleKick(player, args)
	if #args < 1 then
		return "Usage: /kick [player] [reason]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	local reason = table.concat(args, " ", 2) or "No reason provided"
	targetPlayer:Kick(reason)
	
	self:SendSystemMessage(player, string.format("Kicked %s: %s", targetPlayer.Name, reason), "Success")
	return string.format("Kicked %s: %s", targetPlayer.Name, reason)
end

function AdminCommands:HandleWipeData(player, args)
	if #args < 1 then
		return "Usage: /wipedata [player]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	Server_Data:WipeData(targetPlayer)
	
	self:SendSystemMessage(player, string.format("Wiped data for %s", targetPlayer.Name), "Success")
	return string.format("Wiped data for %s", targetPlayer.Name)
end

function AdminCommands:HandleGetData(player, args)
	if #args < 1 then
		return "Usage: /getdata [player]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	local data = Server_Data:GetData(targetPlayer)
	if not data then
		return "No data found for " .. targetPlayer.Name
	end
	
	-- Format data as readable string
	local dataStr = string.format(
		"%s's Data:\n💰 Cash: %s\n⚡ Speed: %d\n🔄 Rebirths: %d\n📦 Inventory Items: %d\n🎯 Plot Slots: %d",
		targetPlayer.Name,
		tostring(data.Cash or 0),
		data.Speed or 0,
		data.Rebirths or 0,
		data.Inventory and #data.Inventory or 0,
		data.PlotSlots and #data.PlotSlots or 0
	)
	
	self:SendSystemMessage(player, dataStr, "Info")
	return dataStr
end

function AdminCommands:HandleGetInventory(player, args)
	if #args < 1 then
		return "Usage: /getinventory [player]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	local data = Server_Data:GetData(targetPlayer)
	if not data or not data.Inventory then
		return "No inventory data found for " .. targetPlayer.Name
	end
	
	local items = {}
	for uid, itemData in pairs(data.Inventory) do
		table.insert(items, string.format("%s (%s)", itemData.ConfigName or "Unknown", itemData.Type or "Unknown"))
	end
	
	if #items == 0 then
		self:SendSystemMessage(player, targetPlayer.Name .. " has no items in inventory", "Info")
		return targetPlayer.Name .. " has no items in inventory"
	end
	
	local message = string.format("%s's Inventory (%d items):\n%s", targetPlayer.Name, #items, table.concat(items, "\n"))
	self:SendSystemMessage(player, message, "Info")
	return message
end

function AdminCommands:HandleGoto(player, args)
	if #args < 1 then
		return "Usage: /goto [player]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	if not player.Character or not targetPlayer.Character then
		return "Character not found"
	end
	
	local root1 = player.Character:FindFirstChild("HumanoidRootPart")
	local root2 = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
	
	if not root1 or not root2 then
		return "Could not find HumanoidRootPart"
	end
	
	root1.CFrame = root2.CFrame
	
	self:SendSystemMessage(player, string.format("Teleported to %s", targetPlayer.Name), "Success")
	return string.format("Teleported to %s", targetPlayer.Name)
end

function AdminCommands:HandleBring(player, args)
	if #args < 1 then
		return "Usage: /bring [player]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	if not player.Character or not targetPlayer.Character then
		return "Character not found"
	end
	
	local root1 = player.Character:FindFirstChild("HumanoidRootPart")
	local root2 = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
	
	if not root1 or not root2 then
		return "Could not find HumanoidRootPart"
	end
	
	root2.CFrame = root1.CFrame
	
	self:SendSystemMessage(player, string.format("Brought %s to you", targetPlayer.Name), "Success")
	return string.format("Brought %s to you", targetPlayer.Name)
end

function AdminCommands:HandleRespawn(player, args)
	if #args < 1 then
		return "Usage: /respawn [player]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	targetPlayer:LoadCharacter()
	
	self:SendSystemMessage(player, string.format("Respawned %s", targetPlayer.Name), "Success")
	return string.format("Respawned %s", targetPlayer.Name)
end

function AdminCommands:HandleGodmode(player, args)
	local targetPlayer
	
	if #args == 0 then
		targetPlayer = player
	else
		targetPlayer = self:FindPlayer(args[1])
		if not targetPlayer then
			return "Player not found: " .. args[1]
		end
	end
	
	-- Toggle godmode in both slapper and game handler systems
	local Server_Slapper = script.Parent.Server_Slapper
	local Server_GameHandler = script.Parent.Server_GameHandler
	
	local isEnabled = false
	
	if Server_Slapper then
		local slapperModule = require(Server_Slapper)
		if slapperModule and slapperModule.ToggleGodmode then
			isEnabled = slapperModule:ToggleGodmode(targetPlayer)
		end
	end
	
	if Server_GameHandler then
		local handlerModule = require(Server_GameHandler)
		if handlerModule and handlerModule.ToggleGodmode then
			handlerModule:ToggleGodmode(targetPlayer)
		end
	end
	
	-- Notify client tablet UI to refresh godmode button state
	local AdminTabletHandler = ReplicatedStorage.Events:FindFirstChild("AdminTabletHandler")
	if AdminTabletHandler and AdminTabletHandler:IsA("RemoteFunction") then
		task.spawn(function()
			pcall(function()
				AdminTabletHandler:InvokeClient(targetPlayer, {
					Action = "GodmodeStateUpdate",
					GodmodeEnabled = isEnabled
				})
			end)
		end)
	end
	
	if isEnabled then
		local msg = "Godmode enabled for " .. targetPlayer.Name .. " - slaps reversed, immune to guards!"
		self:SendSystemMessage(player, msg, "Success")
		if targetPlayer ~= player then
			self:SendSystemMessage(targetPlayer, "Godmode enabled by " .. player.Name .. " - you're invincible!", "Notification")
		end
		return msg
	else
		local msg = "Godmode disabled for " .. targetPlayer.Name
		self:SendSystemMessage(player, msg, "Success")
		if targetPlayer ~= player then
			self:SendSystemMessage(targetPlayer, "Godmode disabled by " .. player.Name, "Notification")
		end
		return msg
	end
end

function AdminCommands:HandleBan(player, args)
	if #args < 1 then
		return "Usage: /ban [player] [reason]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	local reason = table.concat(args, " ", 2) or "No reason provided"
	
	-- Store ban (you'll need to implement a ban datastore)
	-- For now, just kick them
	targetPlayer:Kick("You have been banned. Reason: " .. reason)
	
	self:SendSystemMessage(player, string.format("Banned %s (UserId: %d): %s", targetPlayer.Name, targetPlayer.UserId, reason), "Success")
	return string.format("Banned %s (UserId: %d): %s", targetPlayer.Name, targetPlayer.UserId, reason)
end

function AdminCommands:HandleListPlayers(player, args)
	local playerList = {}
	
	for _, plr in ipairs(Players:GetPlayers()) do
		table.insert(playerList, string.format("%s (UserId: %d)", plr.Name, plr.UserId))
	end
	
	local message = string.format("Players in server (%d):\n%s", #Players:GetPlayers(), table.concat(playerList, "\n"))
	self:SendSystemMessage(player, message, "Info")
	return message
end

function AdminCommands:HandleClearInventory(player, args)
	if #args < 1 then
		return "Usage: /clearinventory [player]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	-- Get current inventory
	local inventory = Server_Inventory:GetInventory(targetPlayer)
	if not inventory then
		return "No inventory found for " .. targetPlayer.Name
	end
	
	-- Unequip all equipped tools first
	for uid, itemData in pairs(inventory) do
		if itemData.Type == "Tool" and itemData.Equipped then
			Server_Inventory:UnequipItem(targetPlayer, uid)
		end
	end
	
	-- Don't remove slapper or gamepass tools (runtime-only, re-added by their modules)
	local InventoryConfig = require(ReplicatedStorage.Modules.Settings.InventoryConfig)
	local removedCount = 0
	for uid, itemData in pairs(inventory) do
		local isReserved = itemData.Type == "Tool" and (
			itemData.ConfigName == "StandardSlapper" or itemData.ConfigName == "VIPSlapper"
			or itemData.ConfigName == InventoryConfig.TabletConfigName or itemData.ConfigName == InventoryConfig.SniperConfigName
		)
		if not isReserved then
			Server_Inventory:RemoveItem(targetPlayer, uid)
			removedCount = removedCount + 1
		end
	end

	local Server_Slapper = require(script.Parent.Server_Slapper)
	Server_Slapper:RefreshSlapper(targetPlayer)
	local Server_GamepassTools = require(script.Parent.Server_GamepassTools)
	Server_GamepassTools:RefreshGamepassTools(targetPlayer)

	local message = string.format("Cleared %d items from %s's inventory (slapper & gamepass tools preserved)", removedCount, targetPlayer.Name)
	self:SendSystemMessage(player, message, "Success")
	return message
end

function AdminCommands:HandleLighting(player, args)
	if #args < 1 then
		return "Usage: /lighting [preset] or /lighting default"
	end
	
	local presetName = args[1]
	
	-- Import LightingManager
	local LightingManager = require(script.Parent.Parent.Systems.Server_LightingManager)
	
	if presetName:lower() == "default" then
		local success = LightingManager:ReturnToDefault()
		if success then
			local successMsg = "✅ Returned to default lighting"
			self:SendSystemMessage(player, successMsg, "Success")
			return successMsg
		else
			return "❌ Failed to return to default lighting"
		end
	else
		-- Test specific preset
		local success = LightingManager:LoadPreset(presetName)
		if success then
			local successMsg = "✅ Loaded lighting preset: " .. presetName
			self:SendSystemMessage(player, successMsg, "Success")
			return successMsg
		else
			-- Show available presets
			local availablePresets = LightingManager:GetAvailablePresets()
			local presetList = table.concat(availablePresets, ", ")
			return "❌ Preset not found. Available presets: " .. presetList
		end
	end
end

function AdminCommands:HandleGiveBlock(player, args)
	if #args < 2 then
		return "Usage: /giveblock [player] [all|blockname]"
	end
	
	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		return "Player not found: " .. args[1]
	end
	
	local blockArg = args[2]:lower()
	
	if blockArg == "all" then
		-- Give all lucky blocks
		local count = 0
		for blockId, blockConfig in pairs(Shared_LuckyBlocks.List) do
			local success, uid = Server_Inventory:AddItem(targetPlayer, "LuckyBlock", blockId, {})
			if success then
				count = count + 1
			end
		end
		
		local msg = string.format("Gave %d lucky blocks to %s", count, targetPlayer.Name)
		self:SendSystemMessage(player, msg, "Success")
		return msg
	else
		-- Give specific lucky block (case insensitive search)
		local blockId = nil
		for id, _ in pairs(Shared_LuckyBlocks.List) do
			if id:lower() == blockArg then
				blockId = id
				break
			end
		end
		
		if not blockId then
			return "Lucky block not found: " .. blockArg .. ". Use 'all' or a valid block name."
		end
		
		local success, uid = Server_Inventory:AddItem(targetPlayer, "LuckyBlock", blockId, {})
		
		if success then
			local msg = string.format("Gave %s to %s", blockId, targetPlayer.Name)
			self:SendSystemMessage(player, msg, "Success")
			return msg
		else
			return "Failed to add lucky block to inventory"
		end
	end
end

function AdminCommands:HandleGiveGamepass(player, args)
	if #args < 2 then
		self:SendSystemMessage(player, "Usage: /givegamepass [player] [VIP|CashBoost|SpeedBoost|Sniper|Tablet]", "Error")
		return
	end

	local targetPlayer = self:FindPlayer(args[1])
	if not targetPlayer then
		self:SendSystemMessage(player, "Player not found: " .. args[1], "Error")
		return
	end

	local passName = args[2]
	local Passes = Shared_Marketplace.Passes
	if not Passes then
		self:SendSystemMessage(player, "Gamepass config not available.", "Error")
		return
	end

	-- Match pass name case-insensitively
	local resolvedName = nil
	for name, _ in pairs(Passes) do
		if name:lower() == passName:lower() then
			resolvedName = name
			break
		end
	end

	if not resolvedName then
		local list = {}
		for name in pairs(Passes) do
			table.insert(list, name)
		end
		self:SendSystemMessage(player, "Unknown gamepass: " .. passName .. ". Valid: " .. table.concat(list, ", "), "Error")
		return
	end

	local passId = Passes[resolvedName]
	local data = Server_Data:GetData(targetPlayer)
	if not data then
		self:SendSystemMessage(player, "Player data not loaded for " .. targetPlayer.Name, "Error")
		return
	end

	Server_Marketplace:GamepassPurchase(targetPlayer, data, passId, resolvedName)
	local msg = string.format("Granted %s to %s", resolvedName, targetPlayer.Name)
	self:SendSystemMessage(player, msg, "Success")
	return msg
end

--// EVENT COMMANDS
function AdminCommands:HandleStartEvent(player, args)
	if #args < 1 then
		return "Usage: /startevent [eventname]"
	end
	
	local eventName = args[1]
	local Server_EventManager = require(script.Parent.Server_EventManager)
	
	local success, message = Server_EventManager:StartLocalEvent(eventName)
	
	if success then
		self:SendSystemMessage(player, "✅ Started " .. eventName .. " event!", "Success")
		return "Started " .. eventName .. " event"
	else
		self:SendSystemMessage(player, "❌ " .. message, "Error")
		return message
	end
end

function AdminCommands:HandleEndEvent(player, args)
	local Server_EventManager = require(script.Parent.Server_EventManager)
	
	local success, message = Server_EventManager:EndEvent()
	
	if success then
		self:SendSystemMessage(player, "✅ Event ended successfully", "Success")
		return "Event ended successfully"
	else
		self:SendSystemMessage(player, "❌ " .. message, "Error")
		return message
	end
end

function AdminCommands:HandleStartGlobalEvent(player, args)
	if #args < 1 then
		return "Usage: /startglobalevent [eventname]"
	end
	
	local eventName = args[1]
	local Server_EventManager = require(script.Parent.Server_EventManager)
	
	local success, message = Server_EventManager:StartGlobalEvent(eventName)
	
	if success then
		self:SendSystemMessage(player, "✅ Started " .. eventName .. " event on ALL servers!", "Success")
		return "Started " .. eventName .. " event on all servers"
	else
		self:SendSystemMessage(player, "❌ " .. message, "Error")
		return message
	end
end

function AdminCommands:HandleEndGlobalEvent(player, args)
	local Server_EventManager = require(script.Parent.Server_EventManager)
	
	local success, message = Server_EventManager:EndGlobalEvent()
	
	if success then
		self:SendSystemMessage(player, "✅ Ended event on ALL servers!", "Success")
		return "Ended event on all servers"
	else
		self:SendSystemMessage(player, "❌ " .. message, "Error")
		return message
	end
end

function AdminCommands:HandleListEvents(player, args)
	local Server_EventManager = require(script.Parent.Server_EventManager)
	
	local events = Server_EventManager:GetAvailableEvents()
	local eventList = table.concat(events, ", ")
	
	local message = string.format("Available Events (%d):\n%s", #events, eventList)
	self:SendSystemMessage(player, message, "Info")
	return message
end

--// MAIN COMMAND HANDLER
function AdminCommands:HandleCommand(player, message)
	local args = {}
	for arg in message:gmatch("%S+") do
		table.insert(args, arg)
	end
	
	if #args == 0 then return end
	
	local head = args[1]
	local commandName = head:sub(1,1) == "/" and head:sub(2) or head
	table.remove(args, 1)
	
	-- Check if command exists
	if not COMMANDS[commandName] then
		local errorMsg = "Unknown command: " .. commandName
		self:SendSystemMessage(player, errorMsg, "Error")
		return
	end
	
	-- Check permissions
	if not self:HasPermission(player, commandName) then
		local errorMsg = "You don't have permission to use this command"
		self:SendSystemMessage(player, errorMsg, "Error")
		return
	end
	
	-- Handle "me" keyword for player parameters
	for i, arg in ipairs(args) do
		if arg:lower() == "me" then
			args[i] = player.Name
		end
	end
	
	-- Route to appropriate handler
	local result
	if commandName == "setcash" then
		result = self:HandleSetCash(player, args)
	elseif commandName == "addcash" then
		result = self:HandleAddCash(player, args)
	elseif commandName == "addcurrency" then
		result = self:HandleAddCurrency(player, args)
	elseif commandName == "setspeed" then
		result = self:HandleSetSpeed(player, args)
	elseif commandName == "setrebirths" then
		result = self:HandleSetRebirths(player, args)
	elseif commandName == "tp" then
		result = self:HandleTeleport(player, args)
	elseif commandName == "announce" then
		result = self:HandleAnnounce(player, args)
	elseif commandName == "kick" then
		result = self:HandleKick(player, args)
	elseif commandName == "wipedata" then
		result = self:HandleWipeData(player, args)
	elseif commandName == "shout" then
		result = self:HandleShout(player, args)
	elseif commandName == "getdata" then
		result = self:HandleGetData(player, args)
	elseif commandName == "getinventory" then
		result = self:HandleGetInventory(player, args)
	elseif commandName == "goto" then
		result = self:HandleGoto(player, args)
	elseif commandName == "bring" then
		result = self:HandleBring(player, args)
	elseif commandName == "respawn" then
		result = self:HandleRespawn(player, args)
	elseif commandName == "godmode" then
		result = self:HandleGodmode(player, args)
	elseif commandName == "ban" then
		result = self:HandleBan(player, args)
	elseif commandName == "listplayers" then
		result = self:HandleListPlayers(player, args)
	elseif commandName == "clearinventory" then
		result = self:HandleClearInventory(player, args)
	elseif commandName == "lighting" then
		result = self:HandleLighting(player, args)
	elseif commandName == "giveblock" then
		result = self:HandleGiveBlock(player, args)
	elseif commandName == "givegamepass" then
		result = self:HandleGiveGamepass(player, args)
	elseif commandName == "startevent" then
		result = self:HandleStartEvent(player, args)
	elseif commandName == "endevent" then
		result = self:HandleEndEvent(player, args)
	elseif commandName == "startglobalevent" then
		result = self:HandleStartGlobalEvent(player, args)
	elseif commandName == "endglobalevent" then
		result = self:HandleEndGlobalEvent(player, args)
	elseif commandName == "listevents" then
		result = self:HandleListEvents(player, args)
	else
		local errorMsg = "Command not implemented: " .. commandName
		self:SendSystemMessage(player, errorMsg, "Error")
		return
	end
	
	-- Send result as system message if not already handled
	if result and type(result) == "string" then
		-- Already sent via SendSystemMessage in handler functions
	end
end

--// CREATE TEXT CHAT COMMANDS
function AdminCommands:CreateTextChatCommands()
	local folder = Instance.new("Folder")
	folder.Name = "TextChatCommands"
	folder.Parent = TextChatService
	
	for commandName, command in pairs(COMMANDS) do
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = commandName
		cmd.PrimaryAlias = "/" .. commandName
		-- Note: Description property is not supported in TextChatCommand
		
		-- Connect the command execution
		local adminModule = self
		cmd.Triggered:Connect(function(textSource, unfilteredText)
			local player = Players:GetPlayerByUserId(textSource.UserId)
			if player then
				adminModule:HandleCommand(player, unfilteredText)
			end
		end)
		
		cmd.Parent = folder
	end
end

---// INITIALIZATION
function AdminCommands:Init()
	-- Create TextChatCommands for built-in autocomplete
	self:CreateTextChatCommands()
	
	-- Listen for shouts from other servers
	local success, errorMessage = pcall(function()
		MessagingService:SubscribeAsync("AdminShout", function(messageData)
			-- Extract message data
			local message = messageData.Data.message
			local adminName = messageData.Data.adminName
			local isVerified = messageData.Data.isVerified or false
			local timestamp = messageData.Data.timestamp
			
			-- Validate message data
			if not message or not adminName or type(message) ~= "string" or type(adminName) ~= "string" then
				warn("Invalid shout message data received")
				return
			end
			
			-- Check if message is too long
			if #message > 200 then
				warn("Shout message too long, ignoring")
				return
			end
			
			-- Generate unique color for this admin based on their name
			local adminColor = self:GetPlayerShoutColor(adminName)
			
			-- Format the message with admin name and colon in their unique color
			local verifiedBadge = isVerified and "" or ""
			local formattedMessage = '<font color="' .. adminColor .. '">' .. adminName .. verifiedBadge .. ':</font> ' .. message
			
			-- Check if Popup event exists before sending
			local popupEvent = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("Popup")
			if popupEvent then
				-- Send to all players in this server with RichText formatting
				local shoutConfig = {
					animation = "default",
					duration = 5,
					richText = true,
					sound = "Announcement"
				}
				popupEvent:FireAllClients(formattedMessage, shoutConfig)
			else
				warn("Popup system not available for shout message")
			end
		end)
	end)
	
	if not success then
		warn("Failed to subscribe to AdminShout:", errorMessage)
	end
	
	-- Count commands
	local commandCount = 0
	for _ in pairs(COMMANDS) do
		commandCount = commandCount + 1
	end
	
end

return AdminCommands
