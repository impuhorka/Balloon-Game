--// Server_PlayerTags: Manages player admin tags for chat
--// Group ID: 1082816729
--// Note: This module only handles chat tags, not overhead billboards

local Players = game:GetService("Players")

local Module = {}

-- Admin group configuration
local ADMIN_GROUP_ID = 1082816729
local ADMIN_TAGS = {
	[248] = "MOD",
	[249] = "ADMIN",
	[250] = "MANAGER",
	[254] = "DEV",
	[255] = "DEV" -- Owner displays as DEV
}

-- Helper function to get admin tag
function Module:GetAdminTag(player)
	if not player or not player:IsA("Player") then
		return nil
	end
	
	if not player:IsInGroup(ADMIN_GROUP_ID) then
		return nil
	end
	
	local rank = player:GetRankInGroup(ADMIN_GROUP_ID)
	return ADMIN_TAGS[rank], rank
end

-- Initialize (minimal setup - chat tags are handled by Client_AdminChat)
function Module:Init()
end

return Module
