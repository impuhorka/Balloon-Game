--// Server_Settings - Server-side settings handler
--// Validates and applies player settings changes

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = ReplicatedStorage:WaitForChild("Events")
local SettingsHandler = Events:WaitForChild("SettingsHandler")

local Server_Data = require(script.Parent.Parent.Core.Server_Data)
local Server_CharacterStats = require(script.Parent.Parent.Systems.Server_CharacterStats)

local Module = {}

-- Whitelist of valid settings
local VALID_SETTINGS = {
	Music = "number",
	Sounds = "number",
	PlayerSpeedSetting = "number",
	OverheadIncomeText = "boolean",
	SlowMode = "boolean",
}

--[[
	Validate setting name and value
	@param settingName string
	@param settingValue any
	@return boolean isValid
]]
local function validateSetting(settingName, settingValue)
	local expectedType = VALID_SETTINGS[settingName]
	if not expectedType then
		return false -- Setting doesn't exist
	end
	
	if type(settingValue) ~= expectedType then
		return false -- Wrong type
	end
	
	-- Range validation for number settings
	if expectedType == "number" then
		if settingValue < 0 or settingValue > 1 then
			return false -- Out of range
		end
	end
	
	return true
end

--[[
	Handle setting update request from client
	@param player Player
	@param settingName string
	@param settingValue any
]]
local function onUpdateSetting(player: Player, settingName: string, settingValue: any)
	-- Validate setting
	if not validateSetting(settingName, settingValue) then
		warn(string.format("❌ Invalid setting update from %s: %s = %s", player.Name, tostring(settingName), tostring(settingValue)))
		return
	end
	
	-- Update data via Server_Data (handles replica sync automatically)
	local path = "Settings." .. settingName
	Server_Data:SetValue(player, path, settingValue)
	
	
	-- Apply server-side effects immediately
	if settingName == "PlayerSpeedSetting" then
		-- Update character speed immediately
		Server_CharacterStats:UpdateCharacterSpeed(player)
	elseif settingName == "OverheadIncomeText" then
		-- Update overhead billboard visibility immediately
		Server_CharacterStats:UpdateOverheadDisplay(player)
	elseif settingName == "SlowMode" then
		-- Recalculate speed with SlowMode cap
		Server_CharacterStats:UpdateCharacterSpeed(player)
	end
	-- Note: Music and Sounds are handled client-side only
end

function Module:Init()
	SettingsHandler.OnServerEvent:Connect(onUpdateSetting)
end

return Module
