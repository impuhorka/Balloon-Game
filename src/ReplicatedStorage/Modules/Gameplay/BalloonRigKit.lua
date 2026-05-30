--// BalloonRigKit — ownership sig encode/decode (server + client).

local Players = game:GetService("Players")

local Module = {}

local SEP = "\30"

Module.ATTACHED_BALLOONS_FOLDER = "AttachedBalloons"
Module.TORSO_SHARED_ATT_NAME = "BalloonTorsoStringAnchor"
Module.SETTLING_ATTR = "BalloonRigSettling"
Module.PLOT_SPAWN_READY_ATTR = "PlotSpawnReady"

function Module.isPlotSpawnReady(player: Player?, character: Model?): boolean
	if not player and character then
		player = Players:GetPlayerFromCharacter(character)
	end
	if player and player:GetAttribute(Module.PLOT_SPAWN_READY_ATTR) == true then
		return true
	end
	if character and character:GetAttribute(Module.PLOT_SPAWN_READY_ATTR) == true then
		return true
	end
	return false
end

function Module.getEntryConfigName(entry: any): string?
	if type(entry) == "string" and entry ~= "" then
		return entry
	end
	if type(entry) == "table" then
		local name = entry[1]
		if type(name) == "string" and name ~= "" then
			return name
		end
	end
	return nil
end

function Module.normalizeToConfigNames(list: any): { string }
	if type(list) ~= "table" then
		return {}
	end
	local names: { string } = {}
	for _, entry in ipairs(list) do
		local name = Module.getEntryConfigName(entry)
		if name then
			table.insert(names, name)
		end
	end
	return names
end

function Module.encodeDataBalloons(dataBalloons: any): string
	if type(dataBalloons) ~= "table" then
		return ""
	end
	local parts = {}
	for _, entry in ipairs(dataBalloons) do
		local name = Module.getEntryConfigName(entry)
		if name then
			table.insert(parts, name)
		end
	end
	return table.concat(parts, SEP)
end

function Module.decodeSig(sig: any): { string }
	if type(sig) ~= "string" or sig == "" then
		return {}
	end
	local out = {}
	for piece in string.gmatch(sig, "[^\30]+") do
		if piece ~= "" then
			table.insert(out, piece)
		end
	end
	return out
end

function Module.configNamesFromEquipped(equipped: any): { string }
	return Module.decodeSig(Module.encodeDataBalloons(equipped))
end

return Module
