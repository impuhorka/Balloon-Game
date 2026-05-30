--// Server Initialization (Template)
local Start = tick()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Library = {}

repeat task.wait() until ReplicatedStorage

-- Initialize Template first (creates RemoteEvents, SoundGroups)
local Template = require(ReplicatedStorage.Modules.Template)
Template:Init()

local function shouldLoadModule(moduleScript)
	local name = moduleScript.Name
	if name:match("%.bak$") then
		return false
	end
	return true
end

-- Load server modules only
for _, Module in pairs(script:GetDescendants()) do
	if Module:IsA("ModuleScript") and shouldLoadModule(Module) then
		local ok, Required = pcall(require, Module)
		if ok then
			if type(Required) == "table" then
				pcall(function()
					setmetatable(Required, {__index = Library})
				end)
			end
			Library[Module.Name] = Required
		else
			warn(("❌ Failed to require %s: %s"):format(Module:GetFullName(), tostring(Required)))
		end
	end
end

-- Run Server_ modules that have Init()
-- IMPORTANT: Server_Data must initialize first (creates replicas)
if Library.Server_Data and type(Library.Server_Data.Init) == "function" then
	Library.Server_Data:Init()
end

for ModuleName, Module in pairs(Library) do
	if ModuleName ~= "Server_Data" and type(Module.Init) == "function" and ModuleName:match("^Server_") then
		task.spawn(function()
			Module:Init()
		end)
	end
end
