--// BalloonRigKit — ownership sig encode/decode (server + client).

local Players = game:GetService("Players")

local Module = {}

local SEP = "\30"

Module.ATTACHED_BALLOONS_FOLDER = "AttachedBalloons"
Module.FLOAT_ANCHOR_FOLDER = "BalloonFloatAnchor"
Module.TORSO_SHARED_ATT_NAME = "BalloonTorsoStringAnchor"

function Module.resolveBalloonsFolder(character: Model?): Folder?
	if not character then
		return nil
	end
	local direct = character:FindFirstChild(Module.ATTACHED_BALLOONS_FOLDER)
	if direct and direct:IsA("Folder") then
		return direct
	end
	local anchor = character:FindFirstChild(Module.FLOAT_ANCHOR_FOLDER)
	if anchor and anchor:IsA("Folder") then
		local nested = anchor:FindFirstChild(Module.ATTACHED_BALLOONS_FOLDER)
		if nested and nested:IsA("Folder") then
			return nested
		end
	end
	return nil
end

function Module.resolveCharacterFromBalloonsFolder(folder: Instance?): Model?
	if not folder or not folder:IsA("Folder") then
		return nil
	end
	local parent = folder.Parent
	if parent and parent:IsA("Folder") and parent.Name == Module.FLOAT_ANCHOR_FOLDER then
		local character = parent.Parent
		if character and character:IsA("Model") then
			return character
		end
	elseif parent and parent:IsA("Model") then
		return parent
	end
	return nil
end

function Module.getBalloonModelFromPart(part: BasePart?): Model?
	if not part then
		return nil
	end
	local balloonModel = part:FindFirstAncestorWhichIsA("Model")
	if not balloonModel then
		return nil
	end
	local folder = balloonModel.Parent
	if not folder or not folder:IsA("Folder") or folder.Name ~= Module.ATTACHED_BALLOONS_FOLDER then
		return nil
	end
	return balloonModel
end
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
