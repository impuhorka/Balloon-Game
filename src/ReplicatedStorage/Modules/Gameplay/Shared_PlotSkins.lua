--[[
	Shared_PlotSkins - Resolve plot skin templates from Assets.PlotSkins (any depth).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared_PlotSkins = {}

local cachedFolder: Instance? = nil

local function namesMatch(a: string, b: string): boolean
	return a == b or string.lower(a) == string.lower(b)
end

local function findPlotSkinsIn(root: Instance?): Instance?
	if not root then
		return nil
	end

	local direct = root:FindFirstChild("PlotSkins")
	if direct then
		return direct
	end

	for _, child in root:GetChildren() do
		if namesMatch(child.Name, "PlotSkins") then
			return child
		end
	end

	return root:FindFirstChild("PlotSkins", true)
end

local function findAssetsRoot(): Instance?
	local direct = ReplicatedStorage:FindFirstChild("Assets")
	if direct then
		return direct
	end

	direct = ServerStorage:FindFirstChild("Assets")
	if direct then
		return direct
	end

	return ReplicatedStorage:FindFirstChild("Assets", true)
		or ServerStorage:FindFirstChild("Assets", true)
end

function Shared_PlotSkins:GetFolder(): Instance?
	if cachedFolder and cachedFolder.Parent then
		return cachedFolder
	end

	local assets = findAssetsRoot()
	if assets then
		local found = findPlotSkinsIn(assets)
		if found then
			cachedFolder = found
			return found
		end
	end

	for _, root in { ReplicatedStorage, ServerStorage } do
		local found = findPlotSkinsIn(root)
		if found then
			cachedFolder = found
			return found
		end
	end

	assets = ReplicatedStorage:WaitForChild("Assets", 30)
	if assets then
		local found = findPlotSkinsIn(assets)
		if found then
			cachedFolder = found
			return found
		end
	end

	return nil
end

function Shared_PlotSkins:FindTemplate(prefix: string, skinKey: string): Instance?
	local plotSkins = self:GetFolder()
	if not plotSkins then
		return nil
	end

	local directName = prefix .. "_" .. skinKey

	local inst = plotSkins:FindFirstChild(directName)
	if inst then
		return inst
	end

	for _, child in plotSkins:GetChildren() do
		if namesMatch(child.Name, directName) then
			return child
		end
	end

	for _, desc in plotSkins:GetDescendants() do
		if namesMatch(desc.Name, directName) then
			return desc
		end
	end

	local skinFolder = plotSkins:FindFirstChild(skinKey)
	if not skinFolder then
		for _, child in plotSkins:GetChildren() do
			if namesMatch(child.Name, skinKey) then
				skinFolder = child
				break
			end
		end
	end

	if skinFolder then
		local nested = skinFolder:FindFirstChild(directName)
			or skinFolder:FindFirstChild(prefix)
		if nested then
			return nested
		end
		for _, desc in skinFolder:GetDescendants() do
			if namesMatch(desc.Name, directName) or namesMatch(desc.Name, prefix) then
				return desc
			end
		end
	end

	return nil
end

function Shared_PlotSkins:GetTemplates(skinKey: string): (Instance?, Instance?)
	local floor0 = self:FindTemplate("Floor0", skinKey)
	local additional = self:FindTemplate("AdditionalFloor", skinKey)
	return floor0, additional
end

function Shared_PlotSkins:DescribeFolder(): string
	local plotSkins = self:GetFolder()
	if not plotSkins then
		return "(PlotSkins folder not found under ReplicatedStorage/ServerStorage Assets)"
	end

	local lines = { plotSkins:GetFullName() .. ":" }
	for _, child in plotSkins:GetChildren() do
		table.insert(lines, "  " .. child.Name .. " (" .. child.ClassName .. ")")
	end
	return table.concat(lines, "\n")
end

return Shared_PlotSkins
