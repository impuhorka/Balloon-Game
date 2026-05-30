--// Client_TotalHealth — balloon HP billboard above player head (Assets.TotalHealth).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.ItemConfigs.BalloonConfig)
local Shared_Balloons = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Balloons)
local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
local BalloonFloat = require(ReplicatedStorage.Modules.Gameplay.BalloonFloat)
local Client_Data = require(script.Parent.Parent.Core.Client_Data)

local Module = {}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local ATT_NAME = "TotalHealthAttachment"
local BILLBOARD_NAME = "TotalHealthBillboard"

type PlayerWiring = {
	billboard: BillboardGui?,
	attachment: Attachment?,
	healthLabel: TextLabel?,
	conns: { RBXScriptConnection },
}

local wiring: { [Player]: PlayerWiring } = setmetatable({}, { __mode = "k" })
local billboardsFolder: Folder?

local function getHpAttributes(): (string, string)
	return Config.BalloonTotalHPAttribute or "BalloonTotalHP", Config.BalloonMaxHPAttribute or "BalloonMaxHP"
end

local function computeHpFromEquipped(equipped: { any }): (number, number)
	local current = 0
	local maxHp = 0
	for _, entry in ipairs(equipped) do
		if type(entry) ~= "table" then
			continue
		end
		local configName = entry[1]
		if type(configName) ~= "string" or configName == "" then
			continue
		end
		local hp = tonumber(entry[2]) or 0
		current += hp
		local def = Shared_Balloons.List[configName]
		maxHp += (def and tonumber(def.HP)) or hp
	end
	return current, maxHp
end

local function formatHpText(current: number, maxHp: number): string
	return string.format(
		"%s/%s HP",
		Shared_Shorten:Number(current),
		Shared_Shorten:Number(maxHp)
	)
end

local function disconnectWiring(w: PlayerWiring?)
	if not w then
		return
	end
	for _, conn in w.conns do
		conn:Disconnect()
	end
	table.clear(w.conns)
	if w.billboard then
		w.billboard:Destroy()
	end
	if w.attachment and w.attachment.Parent then
		w.attachment:Destroy()
	end
end

local function getBillboardsFolder(): Folder?
	if billboardsFolder and billboardsFolder.Parent then
		return billboardsFolder
	end
	local main = PlayerGui:FindFirstChild("Main") or PlayerGui:FindFirstChild("MainGui")
	if not main then
		return nil
	end
	local folder = main:FindFirstChild("Billboards")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Billboards"
		folder.Parent = main
	end
	billboardsFolder = folder
	return folder
end

local function readHpForCharacter(player: Player, character: Model): (number, number)
	if BalloonFloat.getEquippedCount(character) <= 0 then
		return 0, 0
	end

	local curAttr, maxAttr = getHpAttributes()
	local attrCurrent = character:GetAttribute(curAttr)
	local attrMax = character:GetAttribute(maxAttr)
	if type(attrCurrent) == "number" and type(attrMax) == "number" and attrMax > 0 then
		return math.max(0, attrCurrent), math.max(0, attrMax)
	end

	if player == LocalPlayer then
		local replica = Client_Data:GetReplica()
		if replica then
			local equipped = replica.Data.EquippedBalloons
			if type(equipped) == "table" then
				return computeHpFromEquipped(equipped)
			end
		end
	end

	local current = tonumber(attrCurrent) or 0
	local maxHp = tonumber(attrMax) or 0
	return current, maxHp
end

local function updateBillboard(player: Player, character: Model?)
	local w = wiring[player]
	if not w or not w.healthLabel or not w.billboard then
		return
	end
	if not character or not character.Parent then
		w.billboard.Enabled = false
		return
	end

	local current, maxHp = readHpForCharacter(player, character)
	if maxHp <= 0 then
		w.billboard.Enabled = false
		return
	end

	w.healthLabel.Text = formatHpText(current, maxHp)
	w.billboard.Enabled = true
end

local function bindCharacter(player: Player, character: Model)
	disconnectWiring(wiring[player])
	wiring[player] = { conns = {} }
	local w = wiring[player]

	local template = Assets:FindFirstChild("TotalHealth")
	if not template or not template:IsA("BillboardGui") then
		warn("[Client_TotalHealth] Assets.TotalHealth BillboardGui not found")
		return
	end

	local head = character:WaitForChild("Head", 15)
	if not head or not head:IsA("BasePart") then
		return
	end

	local folder = getBillboardsFolder()
	if not folder then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = ATT_NAME
	attachment.Position = Vector3.new(0, head.Size.Y * 0.75, 0)
	attachment.Parent = head

	local billboard = template:Clone()
	billboard.Name = BILLBOARD_NAME .. "_" .. tostring(player.UserId)
	billboard.Adornee = attachment
	billboard.Enabled = false
	billboard.Parent = folder

	local healthLabel = billboard:FindFirstChild("Health", true)
	if not healthLabel or not healthLabel:IsA("TextLabel") then
		warn("[Client_TotalHealth] Health TextLabel not found in TotalHealth billboard")
		billboard:Destroy()
		attachment:Destroy()
		return
	end

	w.attachment = attachment
	w.billboard = billboard
	w.healthLabel = healthLabel

	local curAttr, maxAttr = getHpAttributes()
	table.insert(w.conns, character:GetAttributeChangedSignal(curAttr):Connect(function()
		updateBillboard(player, character)
	end))
	table.insert(w.conns, character:GetAttributeChangedSignal(maxAttr):Connect(function()
		updateBillboard(player, character)
	end))

	if player == LocalPlayer then
		local replica = Client_Data:GetReplica()
		if replica then
			table.insert(w.conns, replica:ListenToChange({ "EquippedBalloons" }, function()
				updateBillboard(player, character)
			end))
		end
	end

	updateBillboard(player, character)
end

local function unbindPlayer(player: Player)
	disconnectWiring(wiring[player])
	wiring[player] = nil
end

local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			if player.Character == character then
				bindCharacter(player, character)
			end
		end)
	end)
	player.CharacterRemoving:Connect(function()
		unbindPlayer(player)
	end)
	if player.Character then
		task.defer(function()
			if player.Character then
				bindCharacter(player, player.Character)
			end
		end)
	end
end

function Module:Init()
	if not Assets:FindFirstChild("TotalHealth") then
		warn("[Client_TotalHealth] Waiting for Assets.TotalHealth")
		Assets:WaitForChild("TotalHealth", 30)
	end

	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(unbindPlayer)
end

return Module
