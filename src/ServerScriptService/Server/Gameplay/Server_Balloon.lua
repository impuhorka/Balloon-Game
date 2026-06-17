--// Server_Balloon — balloon shop, server rig creation, _BalloonSig replication.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Server_Data = require(script.Parent.Parent.Core.Server_Data)
local BalloonFloat = require(ReplicatedStorage.Modules.Gameplay.BalloonFloat)
local BalloonInvisibleCollision = require(ReplicatedStorage.Modules.Gameplay.BalloonInvisibleCollision)
local BalloonRig = require(ReplicatedStorage.Modules.Gameplay.BalloonRig)
local BalloonRigKit = require(ReplicatedStorage.Modules.Gameplay.BalloonRigKit)
local Shared_Balloons = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Balloons)
local Config = require(ReplicatedStorage.Modules.ItemConfigs.BalloonConfig)

local Module = {}

local rigsByPlayer: { [Player]: any } = setmetatable({}, { __mode = "k" })
local sessionHpByModel: { [Model]: number } = setmetatable({}, { __mode = "k" })

local PlayerRig = {}
PlayerRig.__index = PlayerRig

--// Shop -----------------------------------------------------------------------

local function getBalloonMaxHp(configName: string): number
	local def = Shared_Balloons.List[configName]
	return math.max(0, math.floor(tonumber(def and def.HP) or 0))
end

local function runtimeEquippedFromOwned(owned: { any }): { any }
	local equipped: { any } = {}
	for _, entry in ipairs(owned) do
		local configName = BalloonRigKit.getEntryConfigName(entry)
		if configName then
			table.insert(equipped, { configName, getBalloonMaxHp(configName) })
		end
	end
	return equipped
end

local function prepareBalloonDataForSession(player: Player)
	local data = Server_Data:GetData(player)
	if not data then
		return
	end

	local names = BalloonRigKit.normalizeToConfigNames(data.Balloons)
	Server_Data:SetValue(player, "Balloons", names)
	Server_Data:SetValue(player, "EquippedBalloons", runtimeEquippedFromOwned(names))
end

local function getPlayerSessionEquipped(playerRig: any?, player: Player): { any }
	if playerRig and type(playerRig._sessionEquipped) == "table" then
		return playerRig._sessionEquipped
	end
	local data = Server_Data:GetData(player)
	return data and type(data.EquippedBalloons) == "table" and data.EquippedBalloons or {}
end

local function getSessionModelHp(balloonModel: Model, configName: string): number
	local hp = sessionHpByModel[balloonModel]
	if hp == nil then
		hp = getBalloonMaxHp(configName)
		sessionHpByModel[balloonModel] = hp
	end
	return hp
end

local function fireBalloonPopEffect(worldPos: Vector3)
	local events = ReplicatedStorage:FindFirstChild("Events")
	local playEffect = events and events:FindFirstChild("PlayEffect")
	if playEffect and playEffect:IsA("RemoteEvent") then
		playEffect:FireAllClients({
			effectType = "balloonPop",
			position = worldPos,
		})
	end
end

local function maxTotalAllowed(): number
	return Config.number("MaxTotalBalloons", 35)
end

local function totalBalloonCount(dataBalloons: { any }): number
	return #BalloonRigKit.normalizeToConfigNames(dataBalloons)
end

local function computeBalloonHpTotals(equipped: { any }): (number, number)
	local current = 0
	local maxHp = 0
	for _, entry in ipairs(equipped) do
		local configName = BalloonRigKit.getEntryConfigName(entry)
		if not configName then
			continue
		end
		local hp = if type(entry) == "table" then math.max(0, math.floor(tonumber(entry[2]) or 0)) else getBalloonMaxHp(configName)
		current += hp
		local def = Shared_Balloons.List[configName]
		maxHp += (def and tonumber(def.HP)) or hp
	end
	return current, maxHp
end

local function getBalloonsFolder(character: Model): Folder?
	return BalloonFloat.resolveBalloonsFolder(character)
end

local function clearFloatState(character: Model)
	BalloonFloat.exitFloatRigIsolation(character)
	character:SetAttribute(BalloonFloat.ACTIVE_ATTR, false)
	character:SetAttribute(BalloonFloat.HOLD_ATTR, false)
	character:SetAttribute(Config.SigAttribute, "")
end

local function syncBalloonHpAttributes(character: Model, equipped: { any })
	local curAttr = Config.BalloonTotalHPAttribute or "BalloonTotalHP"
	local maxAttr = Config.BalloonMaxHPAttribute or "BalloonMaxHP"
	if #equipped == 0 then
		character:SetAttribute(curAttr, nil)
		character:SetAttribute(maxAttr, nil)
		return
	end
	local current, maxHp = computeBalloonHpTotals(equipped)
	character:SetAttribute(curAttr, current)
	character:SetAttribute(maxAttr, maxHp)
end

local function equippedStructureSignature(equipped: { any }): { string }
	return BalloonRigKit.normalizeToConfigNames(equipped)
end

local function signaturesEqual(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	for index = 1, #a do
		if a[index] ~= b[index] then
			return false
		end
	end
	return true
end

local function initPlayerSessionEquipped(playerRig: any, player: Player)
	local data = Server_Data:GetData(player)
	local equipped = data and type(data.EquippedBalloons) == "table" and data.EquippedBalloons or {}
	local session: { any } = {}
	for _, entry in ipairs(equipped) do
		local configName = BalloonRigKit.getEntryConfigName(entry)
		if configName then
			table.insert(session, { configName, getBalloonMaxHp(configName) })
		end
	end
	playerRig._sessionEquipped = session
	playerRig._sessionEquippedSig = equippedStructureSignature(session)
end

local function syncBalloonModelHp(character: Model, equipped: { any }, pulseIndex: number?)
	local folder = getBalloonsFolder(character)
	if not folder then
		return
	end

	local curAttr = Config.BalloonInstanceHPAttribute or "BalloonCurrentHP"
	local maxAttr = Config.BalloonInstanceMaxHPAttribute or "BalloonMaxHP"
	local pulseAttr = Config.BalloonDamagedPulseAttribute or "BalloonDamagedPulse"

	for _, child in folder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end

		local balloonIndex = tonumber(child:GetAttribute("BalloonIndex"))
		local entry = if balloonIndex then equipped[balloonIndex] else nil
		local configName = BalloonRigKit.getEntryConfigName(entry)
		if not configName then
			child:SetAttribute(curAttr, nil)
			child:SetAttribute(maxAttr, nil)
			continue
		end

		local hp = getSessionModelHp(child, configName)
		local def = Shared_Balloons.List[configName]
		local maxHp = math.max(hp, math.floor(tonumber(def and def.HP) or hp))

		child:SetAttribute(curAttr, hp)
		child:SetAttribute(maxAttr, maxHp)
		if pulseIndex and balloonIndex == pulseIndex then
			local nextPulse = (tonumber(child:GetAttribute(pulseAttr)) or 0) + 1
			child:SetAttribute(pulseAttr, nextPulse)
		end
	end
end

local function countAllAttachedBalloonModels(character: Model): number
	local folder = getBalloonsFolder(character)
	if not folder then
		return 0
	end

	local count = 0
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			count += 1
		end
	end
	return count
end

local function countAttachedBalloonModels(character: Model): number
	return BalloonFloat.getEquippedCount(character)
end

local function buildEquippedFromPhysicalModels(character: Model): { any }
	return BalloonFloat.getLiveEquippedEntries(character)
end

local function applyZeroBalloonGameplayState(playerRig: any?, character: Model)
	clearFloatState(character)
	syncBalloonHpAttributes(character, {})
	if playerRig then
		playerRig._lastEquippedSig = equippedStructureSignature({})
	end
end

local function syncGameplayFromPhysicalModels(playerRig: any?, character: Model)
	if playerRig and type(playerRig._sessionEquipped) == "table" and #playerRig._sessionEquipped > 0 then
		syncBalloonHpAttributes(character, playerRig._sessionEquipped)
		return
	end

	local physicalEquipped = buildEquippedFromPhysicalModels(character)
	if #physicalEquipped == 0 then
		applyZeroBalloonGameplayState(playerRig, character)
	else
		syncBalloonHpAttributes(character, physicalEquipped)
	end
end

local function maybeResyncBrokenRig(playerRig: any, character: Model)
	if playerRig._suppressEquippedSync then
		return
	end
	if (playerRig._syncRetryCount or 0) > 0 then
		return
	end
	if character:GetAttribute(BalloonRigKit.SETTLING_ATTR) == true then
		return
	end

	local data = Server_Data:GetData(playerRig._player)
	local dataEquipped = data and type(data.EquippedBalloons) == "table" and data.EquippedBalloons or {}
	if #dataEquipped == 0 then
		return
	end
	if countAllAttachedBalloonModels(character) > 0 then
		return
	end

	local now = os.clock()
	local nextAt = playerRig._rigIntegrityCheckAt or 0
	if now < nextAt then
		return
	end
	playerRig._rigIntegrityCheckAt = now + 5

	playerRig._lastEquippedSig = nil
	playerRig:_scheduleSync(character)
end

local function applyHpOnlyUpdate(player: Player, playerRig: any, character: Model, equipped: { any })
	syncBalloonHpAttributes(character, equipped)
	syncBalloonModelHp(character, equipped)
	playerRig._lastEquippedSig = equippedStructureSignature(equipped)
end

local function reindexBalloonModels(character: Model, equipped: { any })
	local folder = getBalloonsFolder(character)
	if not folder then
		return
	end

	local models: { Model } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			table.insert(models, child)
		end
	end

	table.sort(models, function(a, b)
		return (tonumber(a:GetAttribute("BalloonIndex")) or 0) < (tonumber(b:GetAttribute("BalloonIndex")) or 0)
	end)

	for index, model in ipairs(models) do
		model:SetAttribute("BalloonIndex", index)
	end

	syncBalloonModelHp(character, equipped)
end

local function needsKnotHub(balloonCount: number): boolean
	if not Config.flag("BalloonStringKnotEnabled") then
		return false
	end
	return balloonCount >= Config.number("BalloonKnotMinBalloonCount", 5)
end

local function destroyBalloonModelAtIndex(character: Model, balloonIndex: number): boolean
	local folder = getBalloonsFolder(character)
	if not folder then
		return false
	end

	for _, child in folder:GetChildren() do
		if child:IsA("Model") and tonumber(child:GetAttribute("BalloonIndex")) == balloonIndex then
			child:Destroy()
			return true
		end
	end

	return false
end

local function commitBalloonDestroyed(player: Player, playerRig: any?, equipped: { any }, removedIndex: number)
	local data = Server_Data:GetData(player)
	if not data then
		return
	end

	local owned = BalloonRigKit.normalizeToConfigNames(data.Balloons or {})
	if removedIndex >= 1 and removedIndex <= #owned then
		table.remove(owned, removedIndex)
	end

	local nextEquipped: { any } = {}
	for _, entry in ipairs(equipped) do
		local configName = BalloonRigKit.getEntryConfigName(entry)
		if configName then
			local hp = if type(entry) == "table"
				then math.max(0, math.floor(tonumber(entry[2]) or 0))
				else getBalloonMaxHp(configName)
			table.insert(nextEquipped, { configName, hp })
		end
	end

	Server_Data:SetValue(player, "Balloons", owned)
	Server_Data:SetValue(player, "EquippedBalloons", nextEquipped)
	if playerRig then
		playerRig._sessionEquipped = nextEquipped
		playerRig._sessionEquippedSig = equippedStructureSignature(equipped)
		playerRig._lastOwnedCount = #owned
		playerRig._lastEquippedSig = equippedStructureSignature(equipped)
	end
end

local function applyCombatBalloonPop(playerRig: any, character: Model, equipped: { any }, poppedIndex: number): boolean
	local countAfter = #equipped
	local countBefore = countAfter + 1
	local hubChanging = needsKnotHub(countBefore) ~= needsKnotHub(countAfter)

	destroyBalloonModelAtIndex(character, poppedIndex)
	reindexBalloonModels(character, equipped)

	local rig = playerRig._balloonRig
	if rig and rig._character == character then
		rig._lastConfigNames = BalloonRigKit.configNamesFromEquipped(equipped)
		if hubChanging then
			rig:swapHubForBalloonCount(countAfter)
		else
			rig:SyncRopeVisibility()
		end
	end

	character:SetAttribute(Config.SigAttribute, BalloonRigKit.encodeDataBalloons(equipped))
	syncBalloonHpAttributes(character, equipped)
	syncBalloonModelHp(character, equipped)
	playerRig._lastEquippedSig = equippedStructureSignature(equipped)
	if hubChanging then
		task.defer(function()
			if character.Parent then
				BalloonFloat.refreshBalloonFollowRig(character)
			end
		end)
	else
		BalloonFloat.onBalloonPopped(character)
	end
	return hubChanging
end

local function applyCombatBalloonClear(playerRig: any, character: Model, equipped: { any })
	applyZeroBalloonGameplayState(playerRig, character)

	local rig = playerRig._balloonRig
	if rig and rig._character == character then
		rig:Clear()
		rig._lastConfigNames = {}
		BalloonRig._clearOrphanKnot(character)
	end

	playerRig._lastEquippedSig = equippedStructureSignature(equipped)
end

local function buyBalloon(player: Player, configName: string, balloonHandler: RemoteEvent, popup: RemoteEvent?)
	local balloonDef = Shared_Balloons.List[configName]
	if not balloonDef then
		return
	end

	local data = Server_Data:GetData(player)
	if not data then
		return
	end

	local owned = data.Balloons or {}
	if totalBalloonCount(owned) >= maxTotalAllowed() then
		if popup then
			popup:FireClient(player, string.format("You can own at most %d balloons.", maxTotalAllowed()), false)
		end
		return
	end

	local cost = tonumber(balloonDef.Cost) or 0
	local cash = Server_Data:GetValue(player, "Cash") or 0
	if cash < cost then
		if popup then
			popup:FireClient(player, "Not enough cash.", false)
		end
		return
	end

	Server_Data:SetValue(player, "Cash", cash - cost)
	local nextList = table.clone(owned)
	table.insert(nextList, configName)
	Server_Data:SetValue(player, "Balloons", nextList)
	balloonHandler:FireClient(player, "OwnedUpdated", configName)
end

local function appendNewEquippedFromOwned(player: Player, playerRig: any): boolean
	local data = Server_Data:GetData(player)
	if not data or not playerRig then
		return false
	end

	local owned = data.Balloons or {}
	local ownedCount = totalBalloonCount(owned)
	local lastSynced = playerRig._lastOwnedCount or 0
	if ownedCount <= lastSynced then
		playerRig._lastOwnedCount = ownedCount
		return false
	end

	local equipped = data.EquippedBalloons or {}
	local nextEquipped = table.clone(equipped)
	for i = lastSynced + 1, ownedCount do
		local configName = BalloonRigKit.getEntryConfigName(owned[i])
		if configName then
			table.insert(nextEquipped, { configName, getBalloonMaxHp(configName) })
		end
	end

	playerRig._lastOwnedCount = ownedCount
	Server_Data:SetValue(player, "EquippedBalloons", nextEquipped)
	return true
end

--// Replication + server rigs ------------------------------------------------

local function destroyLegacyHeadAttachment(head: Instance?)
	if not head then
		return
	end
	local att = head:FindFirstChild("BalloonRopeHeadAnchor")
	if att and att:IsA("Attachment") then
		att:Destroy()
	end
end

local function destroyLegacyTorsoAttachment(character: Model?)
	BalloonRig._clearLegacyTorsoHubParts(character)
end

local function isBalloonBodyPart(part: BasePart, character: Model): boolean
	if part.Name == BalloonRig.KNOT_PART_NAME then
		return true
	end
	local current: Instance? = part
	while current and current ~= character do
		if current.Name == BalloonRigKit.ATTACHED_BALLOONS_FOLDER then
			return true
		end
		current = current.Parent
	end
	return false
end

local function applyPlayerCollisionGroup(character: Model)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and not isBalloonBodyPart(d, character) then
			d.CollisionGroup = Config.PlayerCollisionGroup
		end
	end
end

local function hookPlayerCollisionGroup(character: Model)
	if character:GetAttribute("_BalloonPlayerCollisionHooked") then
		return
	end
	character:SetAttribute("_BalloonPlayerCollisionHooked", true)
	character.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") and not isBalloonBodyPart(desc, character) then
			desc.CollisionGroup = Config.PlayerCollisionGroup
		end
	end)
end

local function clearLegacyWorkspaceRig(player: Player)
	local root = Workspace:FindFirstChild(Config.LegacyRigRootName)
	if root then
		local rig = root:FindFirstChild("Rig_" .. tostring(player.UserId))
		if rig then
			rig:Destroy()
		end
	end

	local localRoot = Workspace:FindFirstChild(Config.LocalRigRootName)
	if localRoot then
		local rig = localRoot:FindFirstChild("Rig_" .. tostring(player.UserId))
		if rig then
			rig:Destroy()
		end
	end
end

local function waitForCharacterRigReady(character: Model): boolean
	if not character.Parent then
		return false
	end
	local hrp = character:WaitForChild("HumanoidRootPart", 8)
	if not hrp then
		return false
	end
	local humanoid = character:WaitForChild("Humanoid", 4)
	if not humanoid then
		return false
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso then
		torso = character:WaitForChild("UpperTorso", 4) or character:WaitForChild("Torso", 4)
	end
	if not torso then
		return false
	end
	return character:WaitForChild("Head", 4) ~= nil
end

function PlayerRig.new(player: Player)
	return setmetatable({
		_player = player,
		_dataConn = nil,
		_equippedConn = nil,
		_charConn = nil,
		_charRemovingConn = nil,
		_balloonRig = nil,
		_lastOwnedCount = 0,
		_lastEquippedSig = nil,
		_suppressEquippedSync = false,
		_syncToken = 0,
		_syncRetryCount = 0,
	}, PlayerRig)
end

function PlayerRig:_destroyBalloonRig()
	if self._balloonRig then
		self._balloonRig:Destroy()
		self._balloonRig = nil
	end
end

function PlayerRig:_getOrCreateBalloonRig(character: Model)
	if self._balloonRig and self._balloonRig._character == character then
		return self._balloonRig
	end
	self:_destroyBalloonRig()
	self._balloonRig = BalloonRig.new(nil, character, self._player)
	return self._balloonRig
end

function PlayerRig:Destroy()
	self:_destroyBalloonRig()
	if self._dataConn then
		self._dataConn:Disconnect()
		self._dataConn = nil
	end
	if self._equippedConn then
		self._equippedConn:Disconnect()
		self._equippedConn = nil
	end
	if self._charConn then
		self._charConn:Disconnect()
		self._charConn = nil
	end
	if self._charRemovingConn then
		self._charRemovingConn:Disconnect()
		self._charRemovingConn = nil
	end
end

local MAX_RIG_SYNC_RETRIES = 8

local function waitForCharacterRigReadyWithRetry(character: Model): boolean
	for _ = 1, 3 do
		if waitForCharacterRigReady(character) then
			return true
		end
		task.wait(0.4)
	end
	return false
end

function PlayerRig:_scheduleSyncRetry(character: Model, delaySeconds: number)
	if (self._syncRetryCount or 0) >= MAX_RIG_SYNC_RETRIES then
		warn(("[Server_Balloon] Rig sync gave up for %s after %d tries.")
			:format(self._player.Name, MAX_RIG_SYNC_RETRIES))
		return
	end

	self._syncRetryCount = (self._syncRetryCount or 0) + 1
	self._syncToken += 1
	local token = self._syncToken

	task.delay(delaySeconds, function()
		if token ~= self._syncToken or not character.Parent then
			return
		end
		self:_syncBalloonRig(character)
	end)
end

function PlayerRig:_syncBalloonRig(character: Model)
	if not character or not character.Parent then
		return
	end

	applyPlayerCollisionGroup(character)
	hookPlayerCollisionGroup(character)
	clearLegacyWorkspaceRig(self._player)
	BalloonRig._clearLegacyTorsoHubParts(character)
	BalloonRig._clearOrphanKnot(character)

	local head = character:FindFirstChild("Head")
	local data = Server_Data:GetData(self._player)
	local equipped = getPlayerSessionEquipped(self, self._player)
	local configNames = BalloonRigKit.configNamesFromEquipped(equipped)

	if #configNames == 0 then
		destroyLegacyHeadAttachment(head)
		destroyLegacyTorsoAttachment(character)
		clearFloatState(character)
		syncBalloonHpAttributes(character, equipped)
		self._syncRetryCount = 0
		self:_destroyBalloonRig()
		return
	end

	local hadVisual = countAttachedBalloonModels(character) > 0

	if not waitForCharacterRigReadyWithRetry(character) then
		warn(("[Server_Balloon] Character rig not ready for %s; retrying balloon spawn.")
			:format(self._player.Name))
		self:_scheduleSyncRetry(character, 0.75)
		return
	end

	local rig = self:_getOrCreateBalloonRig(character)
	local fullRebuild = rig:applyConfigList(configNames)

	if fullRebuild and not hadVisual then
		clearFloatState(character)
	end
	if fullRebuild then
		rig:_finalizeRigAfterBuild()
	else
		rig:SyncHubOrientation()
		rig:SyncRopeVisibility()
	end

	local builtCount = countAllAttachedBalloonModels(character)
	if builtCount < #configNames then
		warn(("[Server_Balloon] Built %d/%d balloons for %s; forcing full resync.")
			:format(builtCount, #configNames, self._player.Name))
		if not hadVisual then
			clearFloatState(character)
		end
		rig._lastConfigNames = {}
		rig:Sync(configNames)
		rig:_finalizeRigAfterBuild()
		builtCount = countAllAttachedBalloonModels(character)
	end

	if builtCount < #configNames then
		self:_scheduleSyncRetry(character, 0.75)
		return
	end

	character:SetAttribute(Config.SigAttribute, BalloonRigKit.encodeDataBalloons(equipped))
	syncBalloonHpAttributes(character, equipped)
	syncBalloonModelHp(character, equipped)
	local folder = getBalloonsFolder(character)
	if folder then
		BalloonFloat.applyFloatBlendToFolder(folder, 0, builtCount, character, {})
	end
	if builtCount > 0 then
		BalloonFloat.ensureBalloonFollowRig(character)
		if BalloonFloat.isFloatRigIsolated(character) then
			BalloonFloat.refreshBalloonFollowRig(character)
		end
	end
	self._lastEquippedSig = equippedStructureSignature(equipped)
	self._syncRetryCount = 0
end

function PlayerRig:_scheduleSync(character: Model)
	self._syncToken += 1
	local token = self._syncToken
	local player = self._player
	task.spawn(function()
		while player.Parent and character.Parent and token == self._syncToken do
			if BalloonRigKit.isPlotSpawnReady(player, character) then
				break
			end
			task.wait(0.05)
		end
		if token ~= self._syncToken or not character.Parent then
			return
		end
		task.wait()
		if token ~= self._syncToken or not character.Parent then
			return
		end
		self:_syncBalloonRig(character)
	end)
end

function PlayerRig:Start()
	local player = self._player
	local replica = Server_Data:GetReplica(player)
	if not replica then
		return
	end

	local function refreshVisuals()
		appendNewEquippedFromOwned(player, self)
	end

	local data = Server_Data:GetData(player)
	self._lastOwnedCount = totalBalloonCount(data and data.Balloons)
	initPlayerSessionEquipped(self, player)

	self._dataConn = replica:ListenToChange({ "Balloons" }, refreshVisuals)
	self._equippedConn = replica:ListenToChange({ "EquippedBalloons" }, function()
		if self._suppressEquippedSync then
			return
		end

		local char = player.Character
		if not char then
			return
		end

		local dataNow = Server_Data:GetData(player)
		local equippedNow = dataNow and type(dataNow.EquippedBalloons) == "table" and dataNow.EquippedBalloons or {}
		local sig = equippedStructureSignature(equippedNow)
		if self._lastEquippedSig and signaturesEqual(self._lastEquippedSig, sig) then
			applyHpOnlyUpdate(player, self, char, getPlayerSessionEquipped(self, player))
			return
		end

		initPlayerSessionEquipped(self, player)
		self._lastEquippedSig = sig
		self:_scheduleSync(char)
	end)

	self._charConn = player.CharacterAdded:Connect(function(character)
		self._syncToken += 1
		self._syncRetryCount = 0
		self:_destroyBalloonRig()
		BalloonRig._clearLegacyTorsoHubParts(character)
		BalloonRig._clearOrphanKnot(character)
		clearFloatState(character)
		prepareBalloonDataForSession(player)
		initPlayerSessionEquipped(self, player)
		local data = Server_Data:GetData(player)
		self._lastOwnedCount = totalBalloonCount(data and data.Balloons or {})
		self:_scheduleSync(character)
	end)

	self._charRemovingConn = player.CharacterRemoving:Connect(function()
		self._syncToken += 1
		self:_destroyBalloonRig()
	end)

	if player.Character then
		self:_scheduleSync(player.Character)
	end
end

local function onPlayerAddedReplication(player: Player)
	local rig = PlayerRig.new(player)
	rigsByPlayer[player] = rig
	task.defer(function()
		if not player.Parent then
			return
		end
		repeat
			task.wait(0.1)
		until Server_Data:GetReplica(player) or not player.Parent
		if not player.Parent then
			return
		end
		prepareBalloonDataForSession(player)
		rig:Start()
	end)
end

local function onPlayerRemovingReplication(player: Player)
	local rig = rigsByPlayer[player]
	if rig then
		rig:Destroy()
		rigsByPlayer[player] = nil
	end
	clearLegacyWorkspaceRig(player)
end

--// Init -----------------------------------------------------------------------

function Module:Init()
	local legacyRoot = Workspace:FindFirstChild(Config.LegacyRigRootName)
	if legacyRoot then
		legacyRoot:Destroy()
	end

	local localRoot = Workspace:FindFirstChild(Config.LocalRigRootName)
	if localRoot then
		localRoot:Destroy()
	end

	pcall(function()
		PhysicsService:RegisterCollisionGroup(Config.BalloonCollisionGroup)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(Config.PlayerCollisionGroup)
	end)
	PhysicsService:CollisionGroupSetCollidable(Config.PlayerCollisionGroup, Config.PlayerCollisionGroup, false)
	PhysicsService:CollisionGroupSetCollidable(Config.PlayerCollisionGroup, "Default", true)
	PhysicsService:CollisionGroupSetCollidable(Config.BalloonCollisionGroup, Config.BalloonCollisionGroup, true)
	PhysicsService:CollisionGroupSetCollidable(
		Config.BalloonCollisionGroup,
		"Default",
		Config.BalloonCollideWithDefaultWorld == true
	)
	PhysicsService:CollisionGroupSetCollidable(Config.BalloonCollisionGroup, Config.PlayerCollisionGroup, false)
	BalloonInvisibleCollision.registerPhysicsGroups()
	BalloonInvisibleCollision.startWatching(Workspace)

	local events = ReplicatedStorage:WaitForChild("Events")
	local balloonHandler = events:WaitForChild("BalloonHandler")
	local popup = events:FindFirstChild("Popup")

	balloonHandler.OnServerEvent:Connect(function(player: Player, action: any, arg: any)
		if action == "Buy" and type(arg) == "string" then
			buyBalloon(player, arg, balloonHandler, popup)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		onPlayerAddedReplication(player)
		player.CharacterAdded:Connect(function(character)
			applyPlayerCollisionGroup(character)
			hookPlayerCollisionGroup(character)
		end)
		if player.Character then
			applyPlayerCollisionGroup(player.Character)
			hookPlayerCollisionGroup(player.Character)
		end
	end)
	Players.PlayerRemoving:Connect(onPlayerRemovingReplication)

	for _, player in Players:GetPlayers() do
		onPlayerAddedReplication(player)
		if player.Character then
			applyPlayerCollisionGroup(player.Character)
			hookPlayerCollisionGroup(player.Character)
		end
	end

	RunService.PostSimulation:Connect(function()
		for _, playerRig in rigsByPlayer do
			local player = playerRig._player
			local character = player and player.Character
			local rig = playerRig._balloonRig
			if not rig then
				continue
			end
			if rig._isSpawnSettling and rig:_isSpawnSettling() then
				rig:_tickSpawnSettle()
			elseif rig._canSyncHubOrientation and rig:_canSyncHubOrientation() then
				rig:SyncHubOrientation()
			end

			if character and BalloonFloat.resolveBalloonsFolder(character) then
				if not BalloonFloat.isFloatRigIsolated(character) then
					local taut = character:GetAttribute(BalloonFloat.HOLD_ATTR) == true
						or character:GetAttribute(BalloonFloat.ACTIVE_ATTR) == true
					BalloonFloat.syncTorsoStrapRopes(character, taut)
					if rig:_shouldUseKnotHub() then
						rig:repairTorsoStrapsIfNeeded()
					end
				end
			end

			if character then
				maybeResyncBrokenRig(playerRig, character)
			end
		end
	end)
end

function Module.damageEquippedBalloon(player: Player, balloonIndex: number, damage: number): (boolean, boolean)
	if balloonIndex < 1 or damage <= 0 then
		return false, false
	end

	local data = Server_Data:GetData(player)
	if not data then
		return false, false
	end

	local equipped = table.clone(data.EquippedBalloons or {})
	local entry = equipped[balloonIndex]
	local configName = BalloonRigKit.getEntryConfigName(entry)
	if not configName then
		return false, false
	end

	local currentHp = if type(entry) == "table"
		then math.max(0, math.floor(tonumber(entry[2]) or 0))
		else getBalloonMaxHp(configName)
	local newHp = math.max(0, currentHp - math.floor(damage))
	local character = player.Character
	local playerRig = rigsByPlayer[player]
	local popped = newHp <= 0
	local hubChanged = false

	if popped then
		table.remove(equipped, balloonIndex)
	else
		equipped[balloonIndex] = { configName, newHp }
	end

	if playerRig then
		playerRig._suppressEquippedSync = true
	end

	if popped then
		commitBalloonDestroyed(player, playerRig, equipped, balloonIndex)
	else
		Server_Data:SetValue(player, "EquippedBalloons", equipped)
	end

	if character and playerRig then
		if popped then
			if #equipped == 0 then
				applyCombatBalloonClear(playerRig, character, equipped)
			else
				hubChanged = applyCombatBalloonPop(playerRig, character, equipped, balloonIndex)
			end
		else
			syncBalloonHpAttributes(character, equipped)
			syncBalloonModelHp(character, equipped, balloonIndex)
			playerRig._lastEquippedSig = equippedStructureSignature(equipped)
		end
	elseif character then
		syncBalloonHpAttributes(character, equipped)
		if not popped then
			syncBalloonModelHp(character, equipped, balloonIndex)
		end
	end

	if playerRig then
		playerRig._suppressEquippedSync = false
	end

	if character and playerRig then
		syncGameplayFromPhysicalModels(playerRig, character)
	elseif character and BalloonFloat.getEquippedCount(character) == 0 then
		applyZeroBalloonGameplayState(nil, character)
	end

	if character and playerRig and popped and #equipped > 0 and not hubChanged then
		local physicalCount = countAllAttachedBalloonModels(character)
		if physicalCount ~= #equipped then
			playerRig._lastEquippedSig = nil
			playerRig:_scheduleSync(character)
		end
	end

	return popped, popped and #equipped == 0
end

function Module.damageBalloonFromShooter(balloonModel: Model, damage: number): boolean
	if damage <= 0 or not balloonModel or not balloonModel.Parent then
		return false
	end

	local folder = balloonModel.Parent
	if not folder or not folder:IsA("Folder") or folder.Name ~= BalloonRigKit.ATTACHED_BALLOONS_FOLDER then
		return false
	end

	local character = BalloonFloat.resolveCharacterFromBalloonsFolder(folder)
	if not character then
		return false
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return false
	end

	local balloonIndex = tonumber(balloonModel:GetAttribute("BalloonIndex"))
	if not balloonIndex or balloonIndex < 1 then
		return false
	end

	local playerRig = rigsByPlayer[player]
	if not playerRig or type(playerRig._sessionEquipped) ~= "table" then
		return false
	end

	local equipped = playerRig._sessionEquipped
	local entry = equipped[balloonIndex]
	local configName = BalloonRigKit.getEntryConfigName(entry)
	if not configName then
		return false
	end

	local currentHp = getSessionModelHp(balloonModel, configName)
	local newHp = math.max(0, currentHp - math.floor(damage))
	sessionHpByModel[balloonModel] = newHp

	local popPos = balloonModel.PrimaryPart and balloonModel.PrimaryPart.Position
		or balloonModel:GetPivot().Position

	local popped = newHp <= 0
	if popped then
		sessionHpByModel[balloonModel] = nil
		table.remove(equipped, balloonIndex)
		playerRig._sessionEquippedSig = equippedStructureSignature(equipped)
	else
		equipped[balloonIndex] = { configName, newHp }
	end

	playerRig._suppressEquippedSync = true

	if popped then
		fireBalloonPopEffect(popPos)
		commitBalloonDestroyed(player, playerRig, equipped, balloonIndex)
		if #equipped == 0 then
			applyCombatBalloonClear(playerRig, character, equipped)
		else
			applyCombatBalloonPop(playerRig, character, equipped, balloonIndex)
		end
	else
		Server_Data:SetValue(player, "EquippedBalloons", equipped)
		syncBalloonHpAttributes(character, equipped)
		syncBalloonModelHp(character, equipped, balloonIndex)
		playerRig._lastEquippedSig = equippedStructureSignature(equipped)
	end

	playerRig._suppressEquippedSync = false

	if character and playerRig then
		syncGameplayFromPhysicalModels(playerRig, character)
	elseif character and BalloonFloat.getEquippedCount(character) == 0 then
		applyZeroBalloonGameplayState(nil, character)
	end

	if character and playerRig and popped and #equipped > 0 then
		local physicalCount = countAllAttachedBalloonModels(character)
		if physicalCount ~= #equipped then
			playerRig._lastEquippedSig = nil
			playerRig:_scheduleSync(character)
		end
	end

	return true
end

function Module.damageBalloonFromSpike(balloonModel: Model): boolean
	if not balloonModel or not balloonModel.Parent then
		return false
	end

	local folder = balloonModel.Parent
	if not folder or not folder:IsA("Folder") or folder.Name ~= BalloonRigKit.ATTACHED_BALLOONS_FOLDER then
		return false
	end

	local character = BalloonFloat.resolveCharacterFromBalloonsFolder(folder)
	if not character then
		return false
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return false
	end

	local balloonIndex = tonumber(balloonModel:GetAttribute("BalloonIndex"))
	if not balloonIndex or balloonIndex < 1 then
		return false
	end

	local playerRig = rigsByPlayer[player]
	if not playerRig or type(playerRig._sessionEquipped) ~= "table" then
		return false
	end

	local entry = playerRig._sessionEquipped[balloonIndex]
	local configName = BalloonRigKit.getEntryConfigName(entry)
	if not configName then
		return false
	end

	local currentHp = getSessionModelHp(balloonModel, configName)
	if currentHp <= 0 then
		return false
	end

	local damage = math.max(1, math.floor(currentHp / 5))
	return Module.damageBalloonFromShooter(balloonModel, damage)
end

return Module
