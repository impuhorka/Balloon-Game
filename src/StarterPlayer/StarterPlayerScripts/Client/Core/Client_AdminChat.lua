--// Client_AdminChat: Handles admin chat tags
--// Displays dev/admin/mod tags in chat automatically
--// Group ID: 1082816729

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")

local Client_AdminChat = {}

-- Admin group configuration
local ADMIN_GROUP_ID = 1082816729
local ADMIN_TAGS = {
	[248] = "MOD",
	[249] = "ADMIN",
	[250] = "MANAGER",
	[254] = "DEV",
	[255] = "DEV" -- Owner displays as DEV
}

-- Admin tag colors
local ADMIN_TAG_COLORS = {
	[248] = "f29539",   -- Mods: Orange
	[249] = "dc146d",   -- Admins: Reddish pink
	[250] = "ff1f4c",   -- Manager: Bright red
	[254] = "20c4ff",   -- Devs: Blue
	[255] = "20c4ff"    -- Devs: Blue (Owner displays as DEV)
}

-- Helper function to check if player is admin and get their tag
local function getAdminChatTag(player)
	if not player or not player:IsA("Player") then
		return nil
	end
	
	if not player:IsInGroup(ADMIN_GROUP_ID) then
		return nil
	end
	
	local rank = player:GetRankInGroup(ADMIN_GROUP_ID)
	local tagName = ADMIN_TAGS[rank]
	
	if tagName then
		return tagName, rank
	end
	
	return nil
end

-- Helper function to check if player has VIP gamepass
local function getVIPChatTag(player)
	if not player or not player:IsA("Player") then
		return nil
	end
	
	-- Check if player has VIP pass (stored in replica/attributes)
	local hasVIP = player:GetAttribute("HasVIP")
	if hasVIP then
		return "VIP"
	end
	
	return nil
end

-- Leaderboard rank emojis and colors
local LEADERBOARD_CONFIG = {
	Rebirths = {
		emoji = "🔄",
		color = "ff00ff" -- Magenta
	},
	CashIncome = {
		emoji = "💰",
		color = "ffd500" -- Yellow
	},
	RobuxSpent = {
		emoji = "⏣",
		color = "00e4ff" -- Cyan (Robux color)
	},
}

-- Helper function to get player's leaderboard ranks (Top 100) - returns array of formatted tags
-- Only shows best rank(s) - if multiple leaderboards have same best rank, shows all of them
local function getLeaderboardChatTags(player)
	if not player or not player:IsA("Player") then
		return {}
	end
	
	-- Read ranks from Player Attributes (set by server, auto-replicated)
	local leaderboardOrder = {"Rebirths", "CashIncome", "RobuxSpent"}
	
	-- First pass: Find the best rank
	local bestRank = nil
	for _, statName in ipairs(leaderboardOrder) do
		local rank = player:GetAttribute("LeaderboardRank_" .. statName)
		if rank and rank > 0 and rank <= 100 then
			if not bestRank or rank < bestRank then
				bestRank = rank
			end
		end
	end
	
	-- If no ranks found, return empty
	if not bestRank then
		return {}
	end
	
	-- Second pass: Create tags for all leaderboards that match the best rank
	local tags = {}
	for _, statName in ipairs(leaderboardOrder) do
		local rank = player:GetAttribute("LeaderboardRank_" .. statName)
		local config = LEADERBOARD_CONFIG[statName]
		
		if rank == bestRank and config and config.emoji ~= "" then
			-- Format: [emoji#rank] with color (e.g., [💰#1] in yellow)
			local tagText = "[" .. config.emoji .. "#" .. rank .. "]"
			local coloredTag = string.format('<font color="#%s">%s</font>', config.color, tagText)
			table.insert(tags, coloredTag)
		end
	end
	
	return tags
end

function Client_AdminChat:Init()
	-- Wait for admin event (for system messages if needed)
	local AdminEvent = ReplicatedStorage.Events:WaitForChild("AdminEvent", 10)
	
	-- Get the general chat channel
	local channel = TextChatService.TextChannels:WaitForChild("RBXGeneral")
	
	-- Listen for admin messages from server (if you add this later)
	if AdminEvent then
		AdminEvent.OnClientEvent:Connect(function(param1, param2, param3, param4)
			local message, kind
			
			if param4 == "LuckyBlockReward" then
				-- Lucky block reward format: playerName, brainrotName, rarity, "LuckyBlockReward"
				local playerName = param1
				local brainrotName = param2
				local rarity = param3
				
				-- Color player name orange
				local coloredPlayer = string.format('<font color="#ffdb10">%s</font>', playerName)
				
				-- Different colors/messages based on rarity
				if rarity == "Divine" then
					local coloredBrainrot = string.format('<font color="#ff00ff">%s</font>', brainrotName)
					message = coloredPlayer .. " just got a " .. coloredBrainrot .. " from a Lucky Block! 🌟"
					kind = "LuckyBlockReward"
				else -- Celestial
					local coloredBrainrot = string.format('<font color="#bd4aff">%s</font>', brainrotName)
					message = coloredPlayer .. " just got a " .. coloredBrainrot .. " from a Lucky Block! 🎉"
					kind = "LuckyBlockReward"
				end
			elseif param4 == "ArcadeMachine" then
				-- Arcade Machine reward format: playerName, itemName, rarity, "ArcadeMachine"
				local playerName = param1
				local itemName = param2
				local rarity = param3
				
				-- Color player name orange
				local coloredPlayer = string.format('<font color="#ffdb10">%s</font>', playerName)
				
				-- Only Divine items are announced (skin uses "skin" as rarity)
				if rarity == "Divine" then
					local coloredItem = string.format('<font color="#ff00ff">%s</font>', itemName)
					message = coloredPlayer .. " just got a " .. coloredItem .. " from the Arcade Machine! 🌟"
					kind = "ArcadeMachine"
				elseif rarity == "skin" then
					local coloredItem = string.format('<font color="#ffd700">%s</font>', itemName)
					message = coloredPlayer .. " just unlocked " .. coloredItem .. " from the Arcade Machine! 🎁"
					kind = "ArcadeMachine"
				end
			else
				-- Old format: message, messageType
				message = param1
				kind = param2 or "Info"
			end
			
			local tagged = ("[[ADMIN:%s]]%s"):format(kind or "Info", message)
			channel:DisplaySystemMessage(tagged)
		end)
	end
	
	-- Set up the OnIncomingMessage handler for chat tags
	TextChatService.OnIncomingMessage = function(message)
		local props = Instance.new("TextChatMessageProperties")
		
		-- Check for admin system messages: [[ADMIN:<KIND>]]
		local kind, rest = string.match(message.Text, "^%[%[ADMIN:(%w+)%]%](.*)")
		if kind then
			-- Handle admin system messages
			props.Text = rest
			
			-- Chat-window styling for admin system messages
			local winProps = TextChatService.ChatWindowConfiguration:DeriveNewMessageProperties()
			if kind == "Error" then
				winProps.TextColor3 = Color3.fromRGB(255, 56, 56)  -- Red
			elseif kind == "Success" then
				winProps.TextColor3 = Color3.fromRGB(103, 255, 32) -- Green
			elseif kind == "Notification" then
				winProps.TextColor3 = Color3.fromRGB(255, 248, 56) -- Yellow
			elseif kind == "LuckyBlockReward" or kind == "ArcadeMachine" or kind == "Info" then
				winProps.TextColor3 = Color3.fromRGB(255, 255, 255) -- White (names are colored via rich text)
			else
				winProps.TextColor3 = Color3.fromRGB(255, 255, 255) -- White
			end
			
			-- Apply window props
			message.ChatWindowMessageProperties = winProps
			
			return props
		end
		
		-- Check if the message sender is an admin, VIP, and/or has leaderboard rank
		if message.TextSource then
			local player = Players:GetPlayerByUserId(message.TextSource.UserId)
			if player then
				local adminTag, adminRank = getAdminChatTag(player)
				local vipTag = getVIPChatTag(player)
				local leaderboardTags = getLeaderboardChatTags(player)
				
				if adminTag or vipTag or #leaderboardTags > 0 then
					local originalPrefix = message.PrefixText or ""
					local tagParts = {}
					
					-- Add all leaderboard rank tags first (already colored and formatted)
					for _, tag in ipairs(leaderboardTags) do
						table.insert(tagParts, tag) -- Already has color formatting
					end
					
					-- Add admin tag second if present
					if adminTag then
						local colorCode = ADMIN_TAG_COLORS[adminRank] or "ffffff" -- Use rank-specific color
						table.insert(tagParts, string.format('<font color="#%s">[%s]</font>', colorCode, adminTag))
					end
					
					-- Add VIP tag last if present
					if vipTag then
						table.insert(tagParts, string.format('<font color="#ffd500">[%s]</font>', vipTag)) -- Yellow for VIP
					end
					
					-- Combine all tags
					local allTags = table.concat(tagParts, " ")
					
					props.PrefixText = allTags .. " " .. originalPrefix
				end
			end
		end
		
		return props
	end
end

return Client_AdminChat
