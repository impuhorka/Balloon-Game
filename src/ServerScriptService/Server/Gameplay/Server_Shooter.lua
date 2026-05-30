--// Server_Shooter - Registers workspace shooters and runs per-type rotation controllers

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared_Shooters = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Shooters)
local StandingShooter = require(script.Parent.ShooterControllers.StandingShooter)
local StandingArcher = require(script.Parent.ShooterControllers.StandingArcher)
local StandingSniper = require(script.Parent.ShooterControllers.StandingSniper)
local WallShooter = require(script.Parent.ShooterControllers.WallShooter)
local WallArcher = require(script.Parent.ShooterControllers.WallArcher)
local WallSniper = require(script.Parent.ShooterControllers.WallSniper)

local Module = {}

local controllers: { [Model]: any } = {}
local updateConnection: RBXScriptConnection? = nil

local MODEL_TO_CLASS = {
	Standing_Archer = StandingArcher,
	Standing_Cannon = StandingShooter,
	Standing_Sniper = StandingSniper,
	Wall_Cannon = WallShooter,
	Wall_Archer = WallArcher,
	Wall_Sniper = WallSniper,
}

local TYPE_PREFIX_TO_CLASS = {
	Standing = StandingShooter,
	Wall = WallShooter,
}

local function parseName(modelName: string): (string?, string?)
	local prefix, shooterName = string.match(modelName, "^(%a+)_([%w_]+)$")
	if not prefix or not shooterName then
		return nil, nil
	end
	return prefix, shooterName
end

local function getExpectedNameSet(): { [string]: boolean }
	local expected: { [string]: boolean } = {}
	for _, entry in pairs(Shared_Shooters.ShooterTypes or {}) do
		if type(entry) == "table" then
			local positionName = tostring(entry.PositionName or "")
			if positionName ~= "" then
				for prefix in TYPE_PREFIX_TO_CLASS do
					expected[prefix .. "_" .. positionName] = true
				end
			end
		end
	end
	return expected
end

local function createController(model: Model)
	local class = MODEL_TO_CLASS[model.Name]
	if class then
		return class.new(model)
	end

	local typePrefix = model:GetAttribute("ShooterType")
	if type(typePrefix) ~= "string" or typePrefix == "" then
		typePrefix = parseName(model.Name)
	end
	if type(typePrefix) ~= "string" then
		return nil
	end

	class = TYPE_PREFIX_TO_CLASS[typePrefix]
	if not class then
		return nil
	end

	return class.new(model)
end

local function setupShooterModel(model: Instance, expectedNames: { [string]: boolean })
	if not model:IsA("Model") or controllers[model] then
		return
	end
	if next(expectedNames) and not expectedNames[model.Name] then
		return
	end

	local controller = createController(model)
	if controller then
		controllers[model] = controller
	end
end

local function removeShooterModel(model: Instance)
	if model:IsA("Model") then
		controllers[model] = nil
	end
end

function Module:Init()
	local shootersFolder = workspace:FindFirstChild("Game") and workspace.Game:FindFirstChild("Shooters")
	if not shootersFolder or not shootersFolder:IsA("Folder") then
		warn("Server_Shooter: workspace.Game.Shooters not found")
		return
	end

	local expectedNames = getExpectedNameSet()
	for _, child in shootersFolder:GetChildren() do
		setupShooterModel(child, expectedNames)
	end

	shootersFolder.ChildAdded:Connect(function(child)
		setupShooterModel(child, expectedNames)
	end)
	shootersFolder.ChildRemoved:Connect(removeShooterModel)

	if updateConnection then
		updateConnection:Disconnect()
	end

	updateConnection = RunService.Heartbeat:Connect(function(dt)
		for model, controller in pairs(controllers) do
			if model.Parent then
				controller:Update(dt)
			else
				controllers[model] = nil
			end
		end
	end)
end

return Module
