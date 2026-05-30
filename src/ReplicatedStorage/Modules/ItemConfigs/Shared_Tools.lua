--// Shared_Tools - Tool item configurations
--// Simple table-based config, no classes or inheritance

local Module = {}

Module.List = {
	
	
	["StandardSlapper"] = {
		DisplayName = "Slapper",
		Description = "A standard slapping tool",
		Rarity = "Common",
		Icon = "rbxassetid://134644015971764",
		
		-- Slapper stats (Tsunami-style: Power + fixed UpwardBoost)
		Power = 8,              -- Horizontal slap strength (velocity multiplier)
		UpwardBoost = 20,      -- Vertical launch (studs/s) - same as Tsunami
		Speed = 0.8,            -- Collision detection window (seconds)
		ClientCooldown = 0.8,
		ServerCooldown = 0.8,
		FlightSpeed = 2.5,      -- Ragdoll duration (seconds)
		SwingSoundId = "rbxassetid://80572912319394",
		SlapSoundId = "rbxassetid://7195270254",
		SlapAnimation = "Assets.PlayerAnimations.Slap",
	},

	["VIPSlapper"] = {
		DisplayName = "VIP Slapper",
		Description = "An exclusive VIP slapping tool with enhanced power",
		Rarity = "Legendary",
		Icon = "rbxassetid://101839632350827",
		
		-- Enhanced VIP: more horizontal power and more vertical
		Power = 10,
		UpwardBoost = 50,       -- Higher vertical than standard
		Speed = 0.8,
		ClientCooldown = 0.8,
		ServerCooldown = 0.8,
		FlightSpeed = 2.5,
		SwingSoundId = "rbxassetid://80542976063121",
		SlapSoundId = "rbxassetid://7195270254",
		SlapAnimation = "Assets.PlayerAnimations.Slap",
	},

	-- Gamepass tools (runtime-only, given on spawn if pass owned)
	["Tablet"] = {
		DisplayName = "Admin Tablet",
		Description = "Admin tablet tool",
		Rarity = "Legendary",
		Icon = "rbxassetid://106530015778459", -- Set in Roblox if needed
		HoldAnimation = "Assets.PlayerAnimations.TwoHandHolding",
	},
	["Sniper"] = {
		DisplayName = "Sniper",
		Description = "Sniper tool",
		Rarity = "Legendary",
		Icon = "rbxassetid://124801852044834", -- Set in Roblox if needed
		HoldAnimation = "Assets.PlayerAnimations.SniperHold",
	},
}

--[[
	Gets a tool config by name
	@param configName string - The tool config name
	@return table? - Tool config or nil if not found
]]
function Module:GetTool(configName: string)
	return self.List[configName]
end

--[[
	Checks if a tool exists
	@param configName string - The tool config name
	@return boolean - True if tool exists
]]
function Module:ToolExists(configName: string): boolean
	return self.List[configName] ~= nil
end

--[[
	Gets all tool names
	@return {string} - Array of tool config names
]]
function Module:GetAllToolNames(): {string}
	local names = {}
	for name, _ in pairs(self.List) do
		table.insert(names, name)
	end
	return names
end

return Module
