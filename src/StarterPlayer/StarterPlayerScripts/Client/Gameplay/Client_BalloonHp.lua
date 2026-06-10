--// Client_BalloonHp — per-balloon HP billboards (Assets.BalloonHP), show on damage, hide after idle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.ItemConfigs.BalloonConfig)
local BalloonRigKit = require(ReplicatedStorage.Modules.Gameplay.BalloonRigKit)

local Module = {}

local ATTACHED_BALLOONS_FOLDER = BalloonRigKit.ATTACHED_BALLOONS_FOLDER
local HP_ATTR = Config.BalloonInstanceHPAttribute or "BalloonCurrentHP"
local MAX_HP_ATTR = Config.BalloonInstanceMaxHPAttribute or "BalloonMaxHP"
local PULSE_ATTR = Config.BalloonDamagedPulseAttribute or "BalloonDamagedPulse"
local TEMPLATE_NAME = Config.BalloonHpBillboardTemplateName or "BalloonHP"
local HIDE_SECONDS = Config.number("BalloonHpBillboardHideSeconds", 5)

type BalloonWiring = {
	billboard: BillboardGui,
	label: TextLabel,
	hideToken: number,
	conns: { RBXScriptConnection },
}

local wiringByBalloon: { [Model]: BalloonWiring } = setmetatable({}, { __mode = "k" })
local characterConns: { [Model]: { RBXScriptConnection } } = setmetatable({}, { __mode = "k" })

local function getTemplate(): BillboardGui?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild(TEMPLATE_NAME)
	if template and template:IsA("BillboardGui") then
		return template
	end
	return nil
end

local function getAdorneePart(balloonModel: Model): BasePart?
	if balloonModel.PrimaryPart and balloonModel.PrimaryPart:IsA("BasePart") then
		return balloonModel.PrimaryPart
	end
	return balloonModel:FindFirstChildWhichIsA("BasePart", true)
end

local function formatHpText(current: number, maxHp: number): string
	return string.format("%d / %d HP", math.floor(current), math.floor(maxHp))
end

local function disconnectBalloon(balloonModel: Model)
	local wiring = wiringByBalloon[balloonModel]
	if not wiring then
		return
	end
	for _, conn in wiring.conns do
		conn:Disconnect()
	end
	wiring.billboard:Destroy()
	wiringByBalloon[balloonModel] = nil
end

local function scheduleHide(balloonModel: Model, wiring: BalloonWiring)
	wiring.hideToken += 1
	local token = wiring.hideToken
	task.delay(HIDE_SECONDS, function()
		if wiringByBalloon[balloonModel] ~= wiring or wiring.hideToken ~= token then
			return
		end
		if wiring.billboard.Parent then
			wiring.billboard.Enabled = false
		end
	end)
end

local function refreshBalloonBillboard(balloonModel: Model, wiring: BalloonWiring, showOnDamage: boolean)
	local current = tonumber(balloonModel:GetAttribute(HP_ATTR))
	local maxHp = tonumber(balloonModel:GetAttribute(MAX_HP_ATTR))
	if current == nil or maxHp == nil or maxHp <= 0 then
		wiring.billboard.Enabled = false
		return
	end

	wiring.label.Text = formatHpText(current, maxHp)
	if showOnDamage then
		wiring.billboard.Enabled = true
		scheduleHide(balloonModel, wiring)
	end
end

local function bindBalloon(balloonModel: Model)
	if wiringByBalloon[balloonModel] then
		return
	end

	local template = getTemplate()
	if not template then
		return
	end

	local adornee = getAdorneePart(balloonModel)
	if not adornee then
		return
	end

	local label = template:FindFirstChild("TextLabel", true)
	if not label or not label:IsA("TextLabel") then
		warn("[Client_BalloonHp] BalloonHP template missing TextLabel")
		return
	end

	local billboard = template:Clone()
	billboard.Name = "BalloonHpBillboard"
	billboard.Adornee = adornee
	billboard.Enabled = false
	billboard.Parent = adornee

	local hpLabel = billboard:FindFirstChild("TextLabel", true)
	if not hpLabel or not hpLabel:IsA("TextLabel") then
		billboard:Destroy()
		return
	end

	local wiring: BalloonWiring = {
		billboard = billboard,
		label = hpLabel,
		hideToken = 0,
		conns = {},
	}
	wiringByBalloon[balloonModel] = wiring

	local lastHp = tonumber(balloonModel:GetAttribute(HP_ATTR))
	table.insert(wiring.conns, balloonModel:GetAttributeChangedSignal(HP_ATTR):Connect(function()
		local now = tonumber(balloonModel:GetAttribute(HP_ATTR))
		local show = lastHp ~= nil and now ~= nil and now < lastHp
		lastHp = now
		refreshBalloonBillboard(balloonModel, wiring, show)
	end))
	table.insert(wiring.conns, balloonModel:GetAttributeChangedSignal(PULSE_ATTR):Connect(function()
		task.defer(function()
			if wiringByBalloon[balloonModel] == wiring and balloonModel.Parent then
				refreshBalloonBillboard(balloonModel, wiring, true)
			end
		end)
	end))
	table.insert(wiring.conns, balloonModel:GetAttributeChangedSignal(MAX_HP_ATTR):Connect(function()
		refreshBalloonBillboard(balloonModel, wiring, wiring.billboard.Enabled)
	end))

	balloonModel.Destroying:Connect(function()
		disconnectBalloon(balloonModel)
	end)

	refreshBalloonBillboard(balloonModel, wiring, false)
end

local function unbindCharacter(character: Model)
	local conns = characterConns[character]
	if conns then
		for _, conn in conns do
			conn:Disconnect()
		end
		characterConns[character] = nil
	end

	local folder = character:FindFirstChild(ATTACHED_BALLOONS_FOLDER)
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				disconnectBalloon(child)
			end
		end
	end
end

local function bindCharacter(character: Model)
	unbindCharacter(character)

	local conns: { RBXScriptConnection } = {}
	characterConns[character] = conns

	local function scanFolder(folder: Folder)
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				bindBalloon(child)
			end
		end
	end

	local folder = character:FindFirstChild(ATTACHED_BALLOONS_FOLDER)
	if folder and folder:IsA("Folder") then
		scanFolder(folder)
	end

	table.insert(conns, character.ChildAdded:Connect(function(child)
		if child.Name == ATTACHED_BALLOONS_FOLDER and child:IsA("Folder") then
			scanFolder(child)
			table.insert(conns, child.ChildAdded:Connect(function(balloon)
				if balloon:IsA("Model") then
					bindBalloon(balloon)
				end
			end))
		end
	end))

	if folder and folder:IsA("Folder") then
		table.insert(conns, folder.ChildAdded:Connect(function(balloon)
			if balloon:IsA("Model") then
				bindBalloon(balloon)
			end
		end))
	end
end

local function setupPlayer(player: Player)
	local function onCharacter(character: Model)
		task.defer(function()
			if player.Character == character then
				bindCharacter(character)
			end
		end)
	end

	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function(character)
		unbindCharacter(character)
	end)
	if player.Character then
		onCharacter(player.Character)
	end
end

function Module:Init()
	if not getTemplate() then
		warn("[Client_BalloonHp] Missing Assets.BalloonHP — per-balloon HP UI disabled")
	end

	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
	Players.PlayerAdded:Connect(setupPlayer)
end

return Module
